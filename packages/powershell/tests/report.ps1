#!/usr/bin/env pwsh
# Report-shape + schema-conformance smoke test for the PowerShell presence detector.
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

$raw = & $Pwsh -NoProfile -File $Cli (Join-Path $Fixtures 'node-ts') '--format' 'json'
$report = $raw | ConvertFrom-Json

# 1. All required top-level keys present.
$required = @(
  'schemaVersion', 'root', 'generatedBy', 'generatedAt', 'ecosystems', 'packageManagers',
  'buildTools', 'topology', 'frameworks', 'testing', 'infrastructure', 'dominantEcosystem'
)
$have = @($report.PSObject.Properties.Name)
$missing = @($required | Where-Object { $have -notcontains $_ })
if ($missing.Count -eq 0) { Test-Ok 'all required top-level keys present' }
else { Test-Bad "missing top-level keys: $($missing -join ', ')" }

# 2. Presence-only invariants: generatedBy=powershell, confidence fields null, frameworks/testing empty.
if ($report.generatedBy -eq 'powershell') { Test-Ok 'generatedBy is powershell' }
else { Test-Bad "generatedBy != powershell (got $($report.generatedBy))" }

$confidenceNull = $true
foreach ($e in $report.ecosystems) {
  if ($null -ne $e.rawScore -or $null -ne $e.confidence -or $null -ne $e.confidenceBucket) { $confidenceNull = $false }
}
if ($confidenceNull) { Test-Ok 'confidence fields are null' } else { Test-Bad 'confidence fields not null' }

if (@($report.frameworks).Count -eq 0 -and @($report.testing).Count -eq 0) { Test-Ok 'frameworks/testing empty' }
else { Test-Bad 'frameworks/testing not empty' }

# 3. Schema validation (uses repo venv jsonschema when available; else structural check only).
$venvPy = $null
foreach ($cand in @((Join-Path $Root '.venv/bin/python'), (Join-Path $Root '.venv/Scripts/python.exe'))) {
  if (Test-Path -LiteralPath $cand -PathType Leaf) { $venvPy = $cand; break }
}
$hasJsonschema = $false
if ($venvPy) {
  & $venvPy -c 'import jsonschema' *> $null
  if ($LASTEXITCODE -eq 0) { $hasJsonschema = $true }
}
if ($hasJsonschema) {
  $validator = @'
import json, sys, jsonschema
schema = json.load(open(sys.argv[1]))
doc = json.load(sys.stdin)
jsonschema.Draft202012Validator(schema, format_checker=jsonschema.Draft202012Validator.FORMAT_CHECKER).validate(doc)
'@
  $raw | & $venvPy -c $validator $Schema
  if ($LASTEXITCODE -eq 0) { Test-Ok 'report validates against schema' }
  else { Test-Bad 'report failed schema validation' }
} else {
  Write-Host 'skip schema validation (no venv jsonschema)'
}

Write-Host ''
Write-Host ("{0} passed, {1} failed" -f $pass, $fail)
if ($fail -ne 0) { exit 1 }
exit 0
