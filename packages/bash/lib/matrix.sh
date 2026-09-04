#!/usr/bin/env bash
# Helper: locate the shared schema/ artifacts. Sourced by repo-fingerprint.sh.
# Resolution order: RF_MATRIX / RF_SCHEMA env overrides, else relative to this repo checkout.

# Directory containing this library (packages/bash/lib).
_rf_lib_dir() {
  cd "$(dirname "${BASH_SOURCE[0]}")" && pwd
}

rf_matrix_path() {
  if [[ -n "${RF_MATRIX:-}" ]]; then
    printf '%s\n' "$RF_MATRIX"
  else
    printf '%s\n' "$(_rf_lib_dir)/../../../schema/signal-matrix.json"
  fi
}

rf_schema_path() {
  if [[ -n "${RF_SCHEMA:-}" ]]; then
    printf '%s\n' "$RF_SCHEMA"
  else
    printf '%s\n' "$(_rf_lib_dir)/../../../schema/detection-report.schema.json"
  fi
}

# List ecosystem ids from the matrix (used by the --list-ecosystems smoke check).
rf_list_ecosystems() {
  jq -r '.ecosystems[].id' "$(rf_matrix_path)"
}
