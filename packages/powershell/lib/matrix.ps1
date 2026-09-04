# Helper: locate the shared schema/ artifacts. Dot-sourced by repo-fingerprint.ps1.
# Resolution order: RF_MATRIX / RF_SCHEMA env overrides, else relative to this repo checkout.
#
# $PSScriptRoot inside these functions is packages/powershell/lib (the dir holding this file),
# mirroring the bash lib's _rf_lib_dir helper.

function Get-RfMatrixPath {
  if ($env:RF_MATRIX) { return $env:RF_MATRIX }
  return [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../schema/signal-matrix.json'))
}

function Get-RfSchemaPath {
  if ($env:RF_SCHEMA) { return $env:RF_SCHEMA }
  return [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../schema/detection-report.schema.json'))
}

# List ecosystem ids from the matrix (used by the --list-ecosystems smoke check).
function Get-RfEcosystemIds {
  $matrixPath = Get-RfMatrixPath
  $matrix = Get-Content -Raw -LiteralPath $matrixPath | ConvertFrom-Json
  foreach ($e in $matrix.ecosystems) { $e.id }
}
