#!/usr/bin/env bash
# Exit-code semantics for the bash presence detector.
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLI="$TESTS_DIR/../repo-fingerprint.sh"
ROOT="$(cd "$TESTS_DIR/../../.." && pwd)"
FIXTURES="$ROOT/fixtures"

pass=0
fail=0
check() {
  local desc="$1" want="$2" got="$3"
  if [[ "$got" == "$want" ]]; then
    printf 'ok   %s (exit %s)\n' "$desc" "$got"; pass=$((pass + 1))
  else
    printf 'FAIL %s: want exit %s, got %s\n' "$desc" "$want" "$got"; fail=$((fail + 1))
  fi
}

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

"$CLI" "$tmp" >/dev/null 2>&1; check "empty dir -> 1" 1 $?
"$CLI" "$FIXTURES/node-ts" >/dev/null 2>&1; check "node-ts -> 0" 0 $?
"$CLI" "$FIXTURES/java-maven" --format text >/dev/null 2>&1; check "java-maven text -> 0" 0 $?
"$CLI" --bogus "$FIXTURES/node-ts" >/dev/null 2>&1; check "bad flag -> 2" 2 $?
"$CLI" /no/such/path >/dev/null 2>&1; check "missing path -> 2" 2 $?
"$CLI" -h >/dev/null 2>&1; check "help -> 0" 0 $?

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]]
