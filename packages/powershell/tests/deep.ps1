#Requires -Version 7.0
# Deep-scan (--deep / --shadow-scan) semantics for the PowerShell presence detector.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$TestsDir = $PSScriptRoot
$Cli = Join-Path $TestsDir '..' 'repo-fingerprint.ps1'
$Root = (Resolve-Path (Join-Path $TestsDir '..' '..' '..')).Path
$Fixtures = Join-Path $Root 'fixtures'

$script:pass = 0
$script:fail = 0
function Ok([string]$Msg)  { Write-Output "ok   $Msg"; $script:pass++ }
function Bad([string]$Msg) { Write-Output "FAIL $Msg"; $script:fail++ }

$deep = & $Cli (Join-Path $Fixtures 'multi-repo-npm') --deep --format json | ConvertFrom-Json
$flat = & $Cli (Join-Path $Fixtures 'multi-repo-npm') --format json | ConvertFrom-Json

# 1. Deep dominance fallback + topology inference on a marker-less multi-repo.
if ($deep.dominantEcosystem -eq 'node') { Ok 'deep: dominantEcosystem resolves to node' } else { Bad 'deep: dominantEcosystem not node' }
if ($deep.topology.type -eq 'monorepo' -and $null -eq $deep.topology.tool) { Ok 'deep: topology inferred as monorepo (tool null)' } else { Bad 'deep: topology not monorepo/null' }

# 2. Sub-repo enumeration.
$paths = @($deep.subRepos | ForEach-Object { $_.path })
if (($paths -join ',') -eq 'repo-a,repo-b') { Ok 'deep: subRepos lists repo-a + repo-b' } else { Bad "deep: subRepos wrong: $($paths -join ',')" }
$ecos = @($deep.subRepos | ForEach-Object { $_.dominantEcosystem })
if (($ecos -join ',') -eq 'node,node') { Ok 'deep: per-sub-repo dominantEcosystem is node' } else { Bad 'deep: sub-repo ecosystems wrong' }

# 3. Non-deep runs keep the pre-deep contract (no subRepos key, topology single).
if (-not ($flat.PSObject.Properties.Name -contains 'subRepos')) { Ok 'non-deep: no subRepos key' } else { Bad 'non-deep: subRepos leaked' }
if ($flat.topology.type -eq 'single') { Ok 'non-deep: topology stays single' } else { Bad 'non-deep: topology changed' }

# 4. --shadow-scan is an alias of --deep.
$aliasRun = & $Cli (Join-Path $Fixtures 'multi-repo-npm') --shadow-scan --format json | ConvertFrom-Json
if ($aliasRun.topology.type -eq 'monorepo' -and (@($aliasRun.subRepos).Count -eq 2)) { Ok '--shadow-scan aliases --deep' } else { Bad '--shadow-scan diverges from --deep' }

# 5. A root-manifest repo is unchanged apart from an empty subRepos list.
$nodeDeep = & $Cli (Join-Path $Fixtures 'node-ts') --deep --format json | ConvertFrom-Json
if ((@($nodeDeep.subRepos).Count -eq 0) -and $nodeDeep.topology.type -eq 'single' -and $nodeDeep.dominantEcosystem -eq 'node') {
  Ok 'deep: root-manifest repo unchanged (empty subRepos)'
} else { Bad 'deep: root-manifest repo changed' }

# 6. Workspace-marker topology is not overridden.
$pnpmDeep = & $Cli (Join-Path $Fixtures 'pnpm-monorepo') --deep --format json | ConvertFrom-Json
$pnpmPaths = @($pnpmDeep.subRepos | ForEach-Object { $_.path })
if ($pnpmDeep.topology.type -eq 'monorepo' -and $pnpmDeep.topology.tool -eq 'pnpm' -and (($pnpmPaths -join ',') -eq 'packages/a,packages/b')) {
  Ok 'deep: pnpm workspace keeps its marker topology'
} else { Bad 'deep: pnpm topology overridden' }

Write-Output ''
Write-Output "$($script:pass) passed, $($script:fail) failed"
if ($script:fail -gt 0) { exit 1 } else { exit 0 }
