#!/usr/bin/env bash
# Deep-scan (--deep / --shadow-scan) semantics for the bash presence detector.
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLI="$TESTS_DIR/../repo-fingerprint.sh"
ROOT="$(cd "$TESTS_DIR/../../.." && pwd)"
FIXTURES="$ROOT/fixtures"

pass=0
fail=0
ok()   { printf 'ok   %s\n' "$1"; pass=$((pass + 1)); }
bad()  { printf 'FAIL %s\n' "$1"; fail=$((fail + 1)); }

deep="$("$CLI" "$FIXTURES/multi-repo-npm" --deep --format json)"
flat="$("$CLI" "$FIXTURES/multi-repo-npm" --format json)"

# 1. Deep dominance fallback + topology inference on a marker-less multi-repo.
if jq -e '.dominantEcosystem == "node"' <<<"$deep" >/dev/null; then
  ok "deep: dominantEcosystem resolves to node"; else bad "deep: dominantEcosystem not node"; fi
if jq -e '.topology.type == "monorepo" and .topology.tool == null' <<<"$deep" >/dev/null; then
  ok "deep: topology inferred as monorepo (tool null)"; else bad "deep: topology not monorepo/null"; fi

# 2. Sub-repo enumeration.
if jq -e '[.subRepos[].path] == ["repo-a", "repo-b"]' <<<"$deep" >/dev/null; then
  ok "deep: subRepos lists repo-a + repo-b"; else bad "deep: subRepos wrong"; fi
if jq -e '[.subRepos[].dominantEcosystem] == ["node", "node"]' <<<"$deep" >/dev/null; then
  ok "deep: per-sub-repo dominantEcosystem is node"; else bad "deep: sub-repo ecosystems wrong"; fi

# 3. Non-deep runs keep the pre-deep contract (no subRepos key, topology single).
if jq -e 'has("subRepos") | not' <<<"$flat" >/dev/null; then
  ok "non-deep: no subRepos key"; else bad "non-deep: subRepos leaked"; fi
if jq -e '.topology.type == "single"' <<<"$flat" >/dev/null; then
  ok "non-deep: topology stays single"; else bad "non-deep: topology changed"; fi

# 4. --shadow-scan is an alias of --deep.
alias_run="$("$CLI" "$FIXTURES/multi-repo-npm" --shadow-scan --format json)"
if [[ "$(jq -Sc 'del(.generatedAt)' <<<"$alias_run")" == "$(jq -Sc 'del(.generatedAt)' <<<"$deep")" ]]; then
  ok "--shadow-scan aliases --deep"; else bad "--shadow-scan diverges from --deep"; fi

# 5. A root-manifest repo is unchanged apart from an empty subRepos list.
node_deep="$("$CLI" "$FIXTURES/node-ts" --deep --format json)"
if jq -e '(.subRepos == []) and .topology.type == "single" and .dominantEcosystem == "node"' <<<"$node_deep" >/dev/null; then
  ok "deep: root-manifest repo unchanged (empty subRepos)"; else bad "deep: root-manifest repo changed"; fi

# 6. Workspace-marker topology is not overridden.
pnpm_deep="$("$CLI" "$FIXTURES/pnpm-monorepo" --deep --format json)"
if jq -e '.topology.type == "monorepo" and .topology.tool == "pnpm" and ([.subRepos[].path] == ["packages/a", "packages/b"])' <<<"$pnpm_deep" >/dev/null; then
  ok "deep: pnpm workspace keeps its marker topology"; else bad "deep: pnpm topology overridden"; fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]]
