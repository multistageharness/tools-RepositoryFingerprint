#!/usr/bin/env pwsh
# Corpus-wide golden suite for the PowerShell presence detector: for every fixture, the live
# CLI's JSON output must canonically equal expected-report.powershell.json, hold the
# presence-only invariants, validate against the shared schema, and render text naming the
# dominant ecosystem.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$TestsDir = $PSScriptRoot
$Cli = Join-Path $TestsDir '../repo-fingerprint.ps1'
$Root = [System.IO.Path]::GetFullPath((Join-Path $TestsDir '../../..'))
$Fixtures = Join-Path $Root 'fixtures'
$Schema = Join-Path $Root 'schema/detection-report.schema.json'
# Interpreter used to spawn the CLI as a child process. RF_PWSH_EXE overrides for unusual installs
# (e.g. a dotnet-global-tool pwsh whose $PSHOME binary can't be re-exec'd directly).
$Pwsh = $env:RF_PWSH_EXE
if (-not $Pwsh) { $Pwsh = (Get-Command pwsh -ErrorAction SilentlyContinue).Source }
if (-not $Pwsh) { $Pwsh = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName }

$pass = 0
$fail = 0
function Test-Ok([string]$Desc) { Write-Host ("ok   {0}" -f $Desc); $script:pass++ }
function Test-Bad([string]$Desc) { Write-Host ("FAIL {0}" -f $Desc); $script:fail++ }

# Canonical JSON: recursive serialization with sorted object keys and normalized number
# literals (1.0 and 1 compare equal), after dropping the fields the goldens stub
# (root, generatedAt). Key order and number formatting are serialization artifacts, not data.
function ConvertTo-CanonicalJson($Node) {
  if ($null -eq $Node) { return 'null' }
  if ($Node -is [bool]) { if ($Node) { return 'true' } else { return 'false' } }
  if ($Node -is [string]) { return (ConvertTo-Json -InputObject $Node -Compress) }
  if ($Node -is [System.ValueType]) {
    $d = [double]$Node
    if ($d -eq [math]::Truncate($d) -and [math]::Abs($d) -lt 9007199254740992) {
      return ([long]$d).ToString([cultureinfo]::InvariantCulture)
    }
    return $d.ToString('R', [cultureinfo]::InvariantCulture)
  }
  if ($Node -is [System.Collections.IEnumerable]) {
    $items = @(foreach ($item in $Node) { ConvertTo-CanonicalJson $item })
    return '[' + ($items -join ',') + ']'
  }
  $parts = @(foreach ($p in ($Node.PSObject.Properties | Sort-Object -Property Name)) {
    (ConvertTo-Json -InputObject $p.Name -Compress) + ':' + (ConvertTo-CanonicalJson $p.Value)
  })
  return '{' + ($parts -join ',') + '}'
}

function Get-CanonicalReport([string]$Json) {
  $obj = $Json | ConvertFrom-Json
  foreach ($k in @('root', 'generatedAt')) { $obj.PSObject.Properties.Remove($k) }
  return ConvertTo-CanonicalJson $obj
}

# Schema validation uses the repo venv jsonschema when available (report.ps1's skip-with-note).
$venvPy = $null
foreach ($cand in @((Join-Path $Root '.venv/bin/python'), (Join-Path $Root '.venv/Scripts/python.exe'))) {
  if (Test-Path -LiteralPath $cand -PathType Leaf) { $venvPy = $cand; break }
}
$hasJsonschema = $false
if ($venvPy) {
  try {
    & $venvPy -c 'import jsonschema' *> $null
    if ($LASTEXITCODE -eq 0) { $hasJsonschema = $true }
  } catch {
    # venv python exists but can't run here (e.g. a foreign-platform venv) — skip, don't fail.
    $hasJsonschema = $false
  }
}
$validator = @'
import json, sys, jsonschema
schema = json.load(open(sys.argv[1]))
doc = json.load(sys.stdin)
jsonschema.Draft202012Validator(schema, format_checker=jsonschema.Draft202012Validator.FORMAT_CHECKER).validate(doc)
'@
if (-not $hasJsonschema) { Write-Host 'skip schema validation (no venv jsonschema)' }

# Dynamic discovery with a non-empty-corpus guard.
$fixtureDirs = @(Get-ChildItem -LiteralPath $Fixtures -Directory -ErrorAction SilentlyContinue | Sort-Object -Property Name)
if ($fixtureDirs.Count -eq 0) {
  Write-Host "FAIL no fixture directories found under $Fixtures — a 0-fixture pass would be a silent defect"
  exit 1
}

foreach ($dir in $fixtureDirs) {
  $fx = $dir.Name
  $goldenPath = Join-Path $dir.FullName 'expected-report.powershell.json'
  if (-not (Test-Path -LiteralPath $goldenPath -PathType Leaf)) {
    Test-Bad "${fx}: missing golden $goldenPath"
    continue
  }
  $goldenRaw = Get-Content -LiteralPath $goldenPath -Raw
  $golden = $goldenRaw | ConvertFrom-Json
  $wantExit = if (@($golden.ecosystems).Count -gt 0) { 0 } else { 1 }

  $raw = (& $Pwsh -NoProfile -File $Cli $dir.FullName '--format' 'json' 2>$null) -join "`n"
  $gotExit = $LASTEXITCODE
  if ($gotExit -eq $wantExit) { Test-Ok "${fx}: json exit $gotExit" }
  else { Test-Bad "${fx}: json want exit $wantExit, got $gotExit" }

  if ((Get-CanonicalReport $raw) -eq (Get-CanonicalReport $goldenRaw)) { Test-Ok "${fx}: matches golden" }
  else { Test-Bad "${fx}: diverges from golden" }

  # Presence-only invariants on the live report.
  $report = $raw | ConvertFrom-Json
  if ($report.generatedBy -eq 'powershell') { Test-Ok "${fx}: generatedBy is powershell" }
  else { Test-Bad "${fx}: generatedBy != powershell (got $($report.generatedBy))" }

  $confidenceNull = $true
  foreach ($e in $report.ecosystems) {
    if ($null -ne $e.rawScore -or $null -ne $e.confidence -or $null -ne $e.confidenceBucket) { $confidenceNull = $false }
  }
  if ($confidenceNull) { Test-Ok "${fx}: confidence fields null" } else { Test-Bad "${fx}: confidence fields not null" }

  if (@($report.frameworks).Count -eq 0 -and @($report.testing).Count -eq 0) { Test-Ok "${fx}: frameworks/testing empty" }
  else { Test-Bad "${fx}: frameworks/testing not empty" }

  if ($hasJsonschema) {
    $raw | & $venvPy -c $validator $Schema *> $null
    if ($LASTEXITCODE -eq 0) { Test-Ok "${fx}: live output validates against schema" }
    else { Test-Bad "${fx}: live output failed schema validation" }
  }

  # Text rendering names the golden's dominant ecosystem (content check skipped when null).
  $text = (& $Pwsh -NoProfile -File $Cli $dir.FullName '--format' 'text' 2>$null) -join "`n"
  $textExit = $LASTEXITCODE
  if ($textExit -eq $wantExit) { Test-Ok "${fx}: text exit $textExit" }
  else { Test-Bad "${fx}: text want exit $wantExit, got $textExit" }
  if ($null -ne $golden.dominantEcosystem) {
    $needle = "Dominant ecosystem: $($golden.dominantEcosystem)"
    if ($text.Contains($needle)) { Test-Ok "${fx}: text names dominant ecosystem $($golden.dominantEcosystem)" }
    else { Test-Bad "${fx}: text missing `"$needle`"" }
  }
}

Write-Host ''
Write-Host ("{0} passed, {1} failed" -f $pass, $fail)
if ($fail -ne 0) { exit 1 }
exit 0
