#!/usr/bin/env pwsh
# Exit-code semantics for the PowerShell presence detector.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$TestsDir = $PSScriptRoot
$Cli = Join-Path $TestsDir '../repo-fingerprint.ps1'
$Root = [System.IO.Path]::GetFullPath((Join-Path $TestsDir '../../..'))
$Fixtures = Join-Path $Root 'fixtures'
# Interpreter used to spawn the CLI as a child process. RF_PWSH_EXE overrides for unusual installs
# (e.g. a dotnet-global-tool pwsh whose $PSHOME binary can't be re-exec'd directly).
$Pwsh = $env:RF_PWSH_EXE
if (-not $Pwsh) { $Pwsh = (Get-Command pwsh -ErrorAction SilentlyContinue).Source }
if (-not $Pwsh) { $Pwsh = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName }

$pass = 0
$fail = 0

function Invoke-Cli {
  param([string[]]$CliArgs)
  & $Pwsh -NoProfile -File $Cli @CliArgs *> $null
  return $LASTEXITCODE
}

function Assert-Exit([string]$Desc, [int]$Want, [int]$Got) {
  if ($Got -eq $Want) {
    Write-Host ("ok   {0} (exit {1})" -f $Desc, $Got)
    $script:pass++
  } else {
    Write-Host ("FAIL {0}: want exit {1}, got {2}" -f $Desc, $Want, $Got)
    $script:fail++
  }
}

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("rf-ps-" + [System.Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null
try {
  Assert-Exit 'empty dir -> 1'        1 (Invoke-Cli @($tmp))
  Assert-Exit 'node-ts -> 0'          0 (Invoke-Cli @((Join-Path $Fixtures 'node-ts')))
  Assert-Exit 'java-maven text -> 0'  0 (Invoke-Cli @((Join-Path $Fixtures 'java-maven'), '--format', 'text'))
  Assert-Exit 'bad flag -> 2'         2 (Invoke-Cli @('--bogus', (Join-Path $Fixtures 'node-ts')))
  Assert-Exit 'missing path -> 2'     2 (Invoke-Cli @('/no/such/path'))
  Assert-Exit 'help -> 0'             0 (Invoke-Cli @('-h'))
} finally {
  Remove-Item -Recurse -Force -LiteralPath $tmp -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host ("{0} passed, {1} failed" -f $pass, $fail)
if ($fail -ne 0) { exit 1 }
exit 0
