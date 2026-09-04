#!/usr/bin/env bash
# Report-shape + schema-conformance smoke test for the bash presence detector.
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLI="$TESTS_DIR/../repo-fingerprint.sh"
ROOT="$(cd "$TESTS_DIR/../../.." && pwd)"
FIXTURES="$ROOT/fixtures"
SCHEMA="$ROOT/schema/detection-report.schema.json"
VENV_PY="$ROOT/.venv/bin/python"

pass=0
fail=0
ok()   { printf 'ok   %s\n' "$1"; pass=$((pass + 1)); }
bad()  { printf 'FAIL %s\n' "$1"; fail=$((fail + 1)); }

report="$("$CLI" "$FIXTURES/node-ts" --format json)"

# 1. Parses as JSON and has all required top-level keys.
if jq -e '
  has("schemaVersion") and has("root") and has("generatedBy") and has("generatedAt")
  and has("ecosystems") and has("packageManagers") and has("buildTools") and has("topology")
  and has("frameworks") and has("testing") and has("infrastructure") and has("dominantEcosystem")
' <<<"$report" >/dev/null; then ok "all required top-level keys present"; else bad "missing top-level keys"; fi

# 2. Presence-only invariants: generatedBy=bash, confidence fields null, frameworks/testing empty.
if jq -e '.generatedBy == "bash"' <<<"$report" >/dev/null; then ok "generatedBy is bash"; else bad "generatedBy != bash"; fi
if jq -e '[.ecosystems[] | .rawScore==null and .confidence==null and .confidenceBucket==null] | all' <<<"$report" >/dev/null; then
  ok "confidence fields are null"; else bad "confidence fields not null"; fi
if jq -e '(.frameworks|length)==0 and (.testing|length)==0' <<<"$report" >/dev/null; then
  ok "frameworks/testing empty"; else bad "frameworks/testing not empty"; fi

# 3. Schema validation (uses repo venv jsonschema when available; else structural check only).
if [[ -x "$VENV_PY" ]] && "$VENV_PY" -c 'import jsonschema' 2>/dev/null; then
  validator='import json,sys,jsonschema
schema=json.load(open(sys.argv[1]))
doc=json.load(sys.stdin)
jsonschema.Draft202012Validator(schema, format_checker=jsonschema.Draft202012Validator.FORMAT_CHECKER).validate(doc)'
  if printf '%s' "$report" | "$VENV_PY" -c "$validator" "$SCHEMA"; then
    ok "report validates against schema"; else bad "report failed schema validation"; fi
else
  printf 'skip schema validation (no venv jsonschema)\n'
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]]
