#Requires -Version 7.0
#
# repo-fingerprint (PowerShell) -- dependency-free presence scanner.
#
# The Windows/cross-platform twin of packages/bash/repo-fingerprint.sh. Detects a repository's
# ecosystems, topology and infrastructure by looking for marker files from the shared signal
# matrix. It does NOT parse manifests or compute Diagnostic Confidence: those fields are emitted as
# null (see schema/confidence-model.md). Output conforms to schema/detection-report.schema.json
# with generatedBy="powershell".
#
# Uses only built-in cmdlets (Get-ChildItem / ConvertFrom-Json / ConvertTo-Json) -- no external
# dependencies (the bash twin's find + jp are replaced by native PowerShell). Requires PowerShell 7+.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'lib/matrix.ps1')

# ---------------------------------------------------------------------------
# Usage / errors
# ---------------------------------------------------------------------------
function Get-Usage {
  @'
repo-fingerprint (PowerShell) -- presence-only repository fingerprint.

Usage:
  repo-fingerprint.ps1 [path] [--format json|text] [--deep]

Arguments:
  path                 Repository root to scan (default: current directory)

Options:
  --format <fmt>       Output format: json (default) or text
  --deep               Deep (shadow) scan: monorepo-aware dominance fallback and
                       nested sub-repo enumeration (alias: --shadow-scan)
  --list-ecosystems    Print ecosystem ids from the signal matrix and exit
  -h, --help           Show this help

Exit codes:
  0  at least one ecosystem detected
  1  no ecosystem detected
  2  usage error
'@
}

function Die([string]$Message) {
  [Console]::Error.WriteLine("error: $Message")
  [Console]::Error.WriteLine('')
  [Console]::Error.WriteLine((Get-Usage))
  exit 2
}

# ---------------------------------------------------------------------------
# Argument parsing (GNU double-dash style, mirrors the bash CLI)
# ---------------------------------------------------------------------------
$Format = 'json'
$Target = ''
$SawTarget = $false
$Deep = $false

$argv = @($args)
$i = 0
while ($i -lt $argv.Count) {
  $a = [string]$argv[$i]
  if ($a -ceq '-h' -or $a -ceq '--help') {
    Write-Output (Get-Usage)
    exit 0
  } elseif ($a -ceq '--list-ecosystems') {
    Get-RfEcosystemIds
    exit 0
  } elseif ($a -ceq '--format') {
    $i++
    if ($i -ge $argv.Count) { Die 'missing value for --format' }
    $v = [string]$argv[$i]
    if ($v -ne 'json' -and $v -ne 'text') { Die "invalid --format: $v" }
    $Format = $v
  } elseif ($a -clike '--format=*') {
    $Format = $a.Substring('--format='.Length)
    if ($Format -ne 'json' -and $Format -ne 'text') { Die "invalid --format: $Format" }
  } elseif ($a -ceq '--deep' -or $a -ceq '--shadow-scan') {
    $Deep = $true
  } elseif ($a -clike '-*') {
    Die "unknown flag: $a"
  } else {
    if ($SawTarget) { Die "unexpected extra argument: $a" }
    $Target = $a
    $SawTarget = $true
  }
  $i++
}
if (-not $SawTarget) { $Target = '.' }
if (-not (Test-Path -LiteralPath $Target -PathType Container)) {
  Die "path not found or not a directory: $Target"
}

# ---------------------------------------------------------------------------
# Filesystem walk (respecting ignore dirs)
# ---------------------------------------------------------------------------
$IgnoreNames = @(
  '.git', 'node_modules', 'dist', 'build', 'out', 'target', 'vendor', '.venv', 'venv',
  '__pycache__', '.idea', '.gradle', '.mvn', '.next', 'coverage'
)

$Files = [System.Collections.Generic.List[string]]::new()
$Dirs  = [System.Collections.Generic.List[string]]::new()

function Get-RelPath([string]$Root, [string]$Full) {
  $rel = $Full.Substring($Root.Length).TrimStart('/', '\')
  return ($rel -replace '\\', '/')
}

function Invoke-Walk([string]$Root) {
  $stack = [System.Collections.Stack]::new()
  $stack.Push($Root)
  while ($stack.Count -gt 0) {
    $dir = [string]$stack.Pop()
    $entries = Get-ChildItem -LiteralPath $dir -Force -ErrorAction SilentlyContinue
    foreach ($e in $entries) {
      if ($e.PSIsContainer) {
        if ($IgnoreNames -contains $e.Name) { continue }
        $Dirs.Add((Get-RelPath $Root $e.FullName))
        $stack.Push($e.FullName)
      } else {
        $Files.Add((Get-RelPath $Root $e.FullName))
      }
    }
  }
}

# ---------------------------------------------------------------------------
# Glob matching (mirrors bash file_matches / dir_matches)
# ---------------------------------------------------------------------------
function Test-FileMatch([string]$Path, [string]$Glob) {
  $base = Split-Path -Leaf $Path
  if ($Glob.StartsWith('*.')) {
    return $base.EndsWith($Glob.Substring(1))     # "*.csproj" -> endsWith ".csproj"
  } elseif ($Glob.Contains('/')) {
    return ($Path -eq $Glob) -or $Path.EndsWith('/' + $Glob)
  } else {
    return ($base -eq $Glob)
  }
}

function Test-DirMatch([string]$Dir, [string]$Glob) {
  return ($Dir -eq $Glob) -or $Dir.EndsWith('/' + $Glob)
}

function Test-AnyFileMatch([string]$Glob) {
  foreach ($f in $Files) { if (Test-FileMatch $f $Glob) { return $true } }
  return $false
}

# ---------------------------------------------------------------------------
# Signal collection -> list of {ecosystem, path, kind, weight}
# ---------------------------------------------------------------------------
function Get-Signals($Matrix) {
  $sigs = [System.Collections.Generic.List[object]]::new()
  foreach ($eco in $Matrix.ecosystems) {
    foreach ($sig in $eco.signals) {
      if ($sig.kind -eq 'source-layout') {
        foreach ($d in $Dirs) {
          if (Test-DirMatch $d $sig.glob) {
            $sigs.Add([pscustomobject]@{ ecosystem = $eco.id; path = $d; kind = $sig.kind; weight = $sig.weight })
          }
        }
      } else {
        foreach ($f in $Files) {
          if (Test-FileMatch $f $sig.glob) {
            $sigs.Add([pscustomobject]@{ ecosystem = $eco.id; path = $f; kind = $sig.kind; weight = $sig.weight })
          }
        }
      }
    }
  }
  return $sigs
}

# ---------------------------------------------------------------------------
# Topology / infrastructure / package-managers / build-tools
# ---------------------------------------------------------------------------
function Get-TopologyHit($Row, [string]$Root) {
  $glob = if ($Row.PSObject.Properties.Name -contains 'glob') { $Row.glob } else { $null }
  if ($glob) {
    foreach ($f in $Files) { if (Test-FileMatch $f $glob) { return $f } }
    return $null
  }
  $marker = if ($Row.PSObject.Properties.Name -contains 'marker') { $Row.marker } else { $null }
  if ($marker) {
    $full = Join-Path $Root $marker.file
    if (Test-Path -LiteralPath $full -PathType Leaf) {
      $contains = if ($marker.PSObject.Properties.Name -contains 'contains') { $marker.contains } else { $null }
      $jsonKey  = if ($marker.PSObject.Properties.Name -contains 'jsonKey') { $marker.jsonKey } else { $null }
      if ($contains) {
        if ((Get-Content -Raw -LiteralPath $full).Contains($contains)) { return $marker.file }
      } elseif ($jsonKey) {
        try {
          $j = Get-Content -Raw -LiteralPath $full | ConvertFrom-Json
          if ($j.PSObject.Properties.Name -contains $jsonKey) { return $marker.file }
        } catch { }
      }
    }
  }
  return $null
}

function Get-Topology($Matrix, [string]$Root) {
  $sigs = [System.Collections.Generic.List[string]]::new()
  $haveMonorepo = $false
  $haveWorkspace = $false
  foreach ($t in $Matrix.topology) {
    $hit = Get-TopologyHit $t $Root
    if ($hit) {
      $sigs.Add($hit)
      if ($t.type -eq 'monorepo') { $haveMonorepo = $true }
      if ($t.type -eq 'workspace') { $haveWorkspace = $true }
    }
  }
  $type = if ($haveMonorepo) { 'monorepo' } elseif ($haveWorkspace) { 'workspace' } else { 'single' }
  $tool = $null
  if ($type -ne 'single') {
    foreach ($t in $Matrix.topology) {
      if ($t.type -eq $type -and (Get-TopologyHit $t $Root)) { $tool = $t.tool; break }
    }
  }
  return [ordered]@{
    type    = $type
    tool    = $tool
    signals = @($sigs | Sort-Object -Unique)
  }
}

function Get-Infrastructure($Matrix) {
  $ci = [System.Collections.Generic.List[string]]::new()
  $containers = [System.Collections.Generic.List[string]]::new()
  $orchestration = [System.Collections.Generic.List[string]]::new()
  foreach ($inf in $Matrix.infrastructure) {
    $glob = $inf.glob
    $matched = $false
    if ((-not $glob.Contains('.')) -and $glob.Contains('/')) {
      # directory marker like .github/workflows
      foreach ($f in $Files) { if ($f -eq $glob -or $f.StartsWith($glob + '/')) { $matched = $true; break } }
    } else {
      if (Test-AnyFileMatch $glob) { $matched = $true }
    }
    if ($matched) {
      switch ($inf.category) {
        'ci'            { $ci.Add($inf.tool) }
        'containers'    { $containers.Add($inf.tool) }
        'orchestration' { $orchestration.Add($inf.tool) }
      }
    }
  }
  return [ordered]@{
    ci            = @($ci | Sort-Object -Unique)
    containers    = @($containers | Sort-Object -Unique)
    orchestration = @($orchestration | Sort-Object -Unique)
  }
}

function Get-ToolList($Rows) {
  $out = [System.Collections.Generic.List[string]]::new()
  foreach ($r in $Rows) { if (Test-AnyFileMatch $r.glob) { $out.Add($r.tool) } }
  return @($out | Sort-Object -Unique)
}

# ---------------------------------------------------------------------------
# Assembly
# ---------------------------------------------------------------------------
function Get-SubRepos($Signals) {
  # Deep-scan sub-repo enumeration: top-most nested dirs holding their own primary manifest.
  $nested = @($Signals | Where-Object { $_.kind -eq 'primary-manifest' -and $_.path.Contains('/') })
  $cands = @($nested | ForEach-Object { $_.path.Substring(0, $_.path.LastIndexOf('/')) } | Sort-Object -Unique)
  $tops = @(foreach ($d in $cands) {
    $under = $false
    foreach ($c in $cands) { if ($c -ne $d -and $d.StartsWith($c + '/')) { $under = $true; break } }
    if (-not $under) { $d }
  })
  return @(foreach ($d in ($tops | Sort-Object)) {
    $inTree = @($nested | Where-Object { $_.path.StartsWith($d + '/') })
    $counts = @{}
    foreach ($s in $inTree) {
      if (-not $counts.ContainsKey($s.ecosystem)) { $counts[$s.ecosystem] = 0 }
      $counts[$s.ecosystem]++
    }
    $rankedEco = @($counts.GetEnumerator() |
      Sort-Object @{ Expression = 'Value'; Descending = $true }, @{ Expression = 'Key'; Descending = $false })
    [ordered]@{
      path              = $d
      primaryManifests  = @($inTree | ForEach-Object { $_.path } | Sort-Object -Unique)
      dominantEcosystem = if ($rankedEco.Count -gt 0) { $rankedEco[0].Key } else { $null }
    }
  })
}

function Build-Report($Matrix, [string]$Root, $Signals, $Topology, $Infrastructure, $PackageManagers, $BuildTools, [bool]$DeepScan) {
  $names = @{}
  foreach ($e in $Matrix.ecosystems) { $names[$e.id] = $e.name }

  $groups = @($Signals | Group-Object -Property ecosystem)

  # dominant = ecosystem with the most root-level (depth <= 1) primary-manifest signals; ties by id.
  $ranked = @(foreach ($g in $groups) {
    $rp = @($g.Group | Where-Object { $_.kind -eq 'primary-manifest' -and ($_.path -notlike '*/*') }).Count
    $fp = @($g.Group | Where-Object { $_.kind -eq 'primary-manifest' }).Count
    [pscustomobject]@{ id = $g.Name; rp = $rp; fp = $fp }
  })
  $rootPrimaries = 0
  foreach ($r in $ranked) { $rootPrimaries += $r.rp }
  $dominant = $null
  if ($ranked.Count -gt 0) {
    if ($DeepScan -and $rootPrimaries -eq 0) {
      # deep dominance fallback: rank by full-depth primary-manifest count instead (ties by id).
      $dominant = ($ranked |
        Sort-Object @{ Expression = 'fp'; Descending = $true }, @{ Expression = 'id'; Descending = $false } |
        Select-Object -First 1).id
    } else {
      $dominant = ($ranked |
        Sort-Object @{ Expression = 'rp'; Descending = $true }, @{ Expression = 'id'; Descending = $false } |
        Select-Object -First 1).id
    }
  }

  $subRepos = $null
  if ($DeepScan) {
    $subRepos = @(Get-SubRepos $Signals)
    # deep topology inference: >= 2 sub-repos, no root manifest, no workspace marker => monorepo.
    if ($subRepos.Count -ge 2 -and $rootPrimaries -eq 0 -and $Topology.type -eq 'single') {
      $Topology.type = 'monorepo'
      $Topology.tool = $null
    }
  }

  $ecosystems = @(foreach ($g in ($groups | Sort-Object Name)) {
    $sigs = @($g.Group | Sort-Object path, kind | ForEach-Object {
      [ordered]@{ path = $_.path; kind = $_.kind; weight = $_.weight }
    })
    [ordered]@{
      id               = $g.Name
      name             = if ($names.ContainsKey($g.Name)) { $names[$g.Name] } else { $g.Name }
      signals          = $sigs
      rawScore         = $null
      confidence       = $null
      confidenceBucket = $null
      role             = if ($g.Name -eq $dominant) { 'primary' } else { 'auxiliary' }
    }
  })

  $generatedAt = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')

  $report = [ordered]@{
    schemaVersion     = '1.0'
    root              = $Root
    generatedBy       = 'powershell'
    generatedAt       = $generatedAt
    ecosystems        = @($ecosystems)
    packageManagers   = @($PackageManagers)
    buildTools        = @($BuildTools)
    topology          = $Topology
    frameworks        = @()
    testing           = @()
    infrastructure    = $Infrastructure
    dominantEcosystem = $dominant
  }
  if ($DeepScan) { $report.subRepos = @($subRepos) }
  return $report
}

# ---------------------------------------------------------------------------
# Text renderer (mirrors bash render_text)
# ---------------------------------------------------------------------------
function Format-Text($Report) {
  $lines = [System.Collections.Generic.List[string]]::new()
  $lines.Add("Repository: $($Report.root)")
  $lines.Add("Detected by: $($Report.generatedBy)")
  $dom = if ($Report.dominantEcosystem) { $Report.dominantEcosystem } else { '(none)' }
  $lines.Add("Dominant ecosystem: $dom")
  $lines.Add('')
  $lines.Add('Ecosystems:')
  if (@($Report.ecosystems).Count -eq 0) {
    $lines.Add('  (none)')
  } else {
    foreach ($e in $Report.ecosystems) {
      $lines.Add("  - $($e.name) [$($e.role)] signals=$(@($e.signals).Count) (presence-only)")
    }
  }
  $lines.Add('')
  $pm = if (@($Report.packageManagers).Count -gt 0) { ($Report.packageManagers -join ', ') } else { '(none)' }
  $bt = if (@($Report.buildTools).Count -gt 0) { ($Report.buildTools -join ', ') } else { '(none)' }
  $lines.Add("Package managers: $pm")
  $lines.Add("Build tools: $bt")
  $topoLine = "Topology: $($Report.topology.type)"
  if ($Report.topology.tool) { $topoLine += " ($($Report.topology.tool))" }
  $lines.Add($topoLine)
  if ($Report.Contains('subRepos') -and @($Report.subRepos).Count -gt 0) {
    $lines.Add('Sub-repos:')
    foreach ($s in $Report.subRepos) {
      $eco = if ($s.dominantEcosystem) { $s.dominantEcosystem } else { 'unknown' }
      $lines.Add("  - $($s.path) ($eco, $(@($s.primaryManifests).Count) manifest(s))")
    }
  }
  $infraAll = @($Report.infrastructure.ci) + @($Report.infrastructure.containers) + @($Report.infrastructure.orchestration)
  if (@($infraAll).Count -gt 0) { $lines.Add("Infrastructure: $($infraAll -join ', ')") }
  return ($lines -join "`n")
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
$matrixPath = Get-RfMatrixPath
if (-not (Test-Path -LiteralPath $matrixPath -PathType Leaf)) {
  Die "signal matrix not found: $matrixPath (set RF_MATRIX)"
}
$matrix = Get-Content -Raw -LiteralPath $matrixPath | ConvertFrom-Json
$root = (Resolve-Path -LiteralPath $Target).Path

Invoke-Walk $root
$signals = Get-Signals $matrix
$topology = Get-Topology $matrix $root
$infrastructure = Get-Infrastructure $matrix
$packageManagers = @(Get-ToolList $matrix.packageManagers)
$buildTools = @(Get-ToolList $matrix.buildTools)
$report = Build-Report $matrix $root $signals $topology $infrastructure $packageManagers $buildTools $Deep

$ecoCount = @($report.ecosystems).Count

if ($Format -eq 'text') {
  Write-Output (Format-Text $report)
} else {
  Write-Output ($report | ConvertTo-Json -Depth 12)
}

if ($ecoCount -gt 0) { exit 0 } else { exit 1 }
