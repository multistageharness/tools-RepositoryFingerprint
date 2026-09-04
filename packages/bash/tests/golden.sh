#!/usr/bin/env bash
# Corpus-wide golden suite for the bash presence detector: for every fixture, the live CLI's
# JSON output must canonically equal expected-report.bash.json, hold the presence-only
# invariants, validate against the shared schema, and render text naming the dominant ecosystem.
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLI="$TESTS_DIR/../repo-fingerprint.sh"
ROOT="$(cd "$TESTS_DIR/../../.." && pwd)"
FIXTURES="$ROOT/fixtures"
SCHEMA="$ROOT/schema/detection-report.schema.json"
VENV_PY="$ROOT/.venv/bin/python"

# Canonical form: drop the fields the goldens stub (root, generatedAt) and normalize number
# literals — the detector emits 1.0 where the golden generator serializes 1, and jq >= 1.7
# preserves literals instead of collapsing them.
CANON='del(.root, .generatedAt) | walk(if type == "number" then . + 0 else . end)'

pass=0
fail=0
ok()  { printf 'ok   %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf 'FAIL %s\n' "$1"; fail=$((fail + 1)); }

# Schema validation uses the repo venv jsonschema when available (report.sh's skip-with-note).
have_validator=0
if [[ -x "$VENV_PY" ]] && "$VENV_PY" -c 'import jsonschema' 2>/dev/null; then have_validator=1; fi
validator='import json,sys,jsonschema
schema=json.load(open(sys.argv[1]))
doc=json.load(sys.stdin)
jsonschema.Draft202012Validator(schema, format_checker=jsonschema.Draft202012Validator.FORMAT_CHECKER).validate(doc)'
[[ "$have_validator" -eq 1 ]] || printf 'skip schema validation (no venv jsonschema)\n'

# Dynamic discovery with a non-empty-corpus guard.
fixtures=()
for d in "$FIXTURES"/*/; do
  [[ -d "$d" ]] && fixtures+=("$(basename "$d")")
done
if [[ "${#fixtures[@]}" -eq 0 ]]; then
  printf 'FAIL no fixture directories found under %s — a 0-fixture pass would be a silent defect\n' "$FIXTURES"
  exit 1
fi

for fx in "${fixtures[@]}"; do
  golden="$FIXTURES/$fx/expected-report.bash.json"
  if [[ ! -f "$golden" ]]; then bad "$fx: missing golden $golden"; continue; fi
  want_exit=1
  if jq -e '(.ecosystems | length) > 0' "$golden" >/dev/null; then want_exit=0; fi

  report="$("$CLI" "$FIXTURES/$fx" --format json 2>/dev/null)"
  got_exit=$?
  if [[ "$got_exit" -eq "$want_exit" ]]; then ok "$fx: json exit $got_exit"; else bad "$fx: json want exit $want_exit, got $got_exit"; fi

  if [[ "$(jq -Sc "$CANON" <<<"$report")" == "$(jq -Sc "$CANON" "$golden")" ]]; then
    ok "$fx: matches golden"; else bad "$fx: diverges from golden"; fi

  # Presence-only invariants on the live report.
  if jq -e '.generatedBy == "bash"' <<<"$report" >/dev/null; then ok "$fx: generatedBy is bash"; else bad "$fx: generatedBy != bash"; fi
  if jq -e '[.ecosystems[] | .rawScore==null and .confidence==null and .confidenceBucket==null] | all' <<<"$report" >/dev/null; then
    ok "$fx: confidence fields null"; else bad "$fx: confidence fields not null"; fi
  if jq -e '(.frameworks|length)==0 and (.testing|length)==0' <<<"$report" >/dev/null; then
    ok "$fx: frameworks/testing empty"; else bad "$fx: frameworks/testing not empty"; fi

  if [[ "$have_validator" -eq 1 ]]; then
    if printf '%s' "$report" | "$VENV_PY" -c "$validator" "$SCHEMA" 2>/dev/null; then
      ok "$fx: live output validates against schema"; else bad "$fx: live output failed schema validation"; fi
  fi

  # Text rendering names the golden's dominant ecosystem (content check skipped when null).
  text="$("$CLI" "$FIXTURES/$fx" --format text 2>/dev/null)"
  text_exit=$?
  if [[ "$text_exit" -eq "$want_exit" ]]; then ok "$fx: text exit $text_exit"; else bad "$fx: text want exit $want_exit, got $text_exit"; fi
  dom="$(jq -r '.dominantEcosystem // empty' "$golden")"
  if [[ -n "$dom" ]]; then
    if grep -qF "Dominant ecosystem: $dom" <<<"$text"; then
      ok "$fx: text names dominant ecosystem $dom"; else bad "$fx: text missing \"Dominant ecosystem: $dom\""; fi
  fi
done

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]]
