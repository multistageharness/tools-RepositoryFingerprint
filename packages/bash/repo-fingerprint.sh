#!/usr/bin/env bash
#
# repo-fingerprint (bash) — dependency-free presence scanner.
#
# Detects a repository's ecosystems, topology and infrastructure by looking for marker files from
# the shared signal matrix. It does NOT parse manifests or compute Diagnostic Confidence: those
# fields are emitted as null (see schema/confidence-model.md). Output conforms to
# schema/detection-report.schema.json with generatedBy="bash".
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/matrix.sh
source "$SCRIPT_DIR/lib/matrix.sh"

usage() {
  cat <<'EOF'
repo-fingerprint (bash) — presence-only repository fingerprint.

Usage:
  repo-fingerprint.sh [path] [--format json|text] [--deep]

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
EOF
}

die() {
  printf 'error: %s\n\n' "$1" >&2
  usage >&2
  exit 2
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
FORMAT="json"
TARGET=""
SAW_TARGET=0
DEEP=0

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help) usage; exit 0 ;;
      --list-ecosystems) rf_list_ecosystems; exit 0 ;;
      --format)
        shift || die "missing value for --format"
        [[ "${1:-}" == "json" || "${1:-}" == "text" ]] || die "invalid --format: ${1:-}"
        FORMAT="$1"
        ;;
      --format=*)
        FORMAT="${1#--format=}"
        [[ "$FORMAT" == "json" || "$FORMAT" == "text" ]] || die "invalid --format: $FORMAT"
        ;;
      --deep|--shadow-scan) DEEP=1 ;;
      -*) die "unknown flag: $1" ;;
      *)
        [[ $SAW_TARGET -eq 1 ]] && die "unexpected extra argument: $1"
        TARGET="$1"; SAW_TARGET=1
        ;;
    esac
    shift
  done
  [[ $SAW_TARGET -eq 0 ]] && TARGET="."
  [[ -d "$TARGET" ]] || die "path not found or not a directory: $TARGET"
}

# ---------------------------------------------------------------------------
# Filesystem walk (respecting ignore dirs)
# ---------------------------------------------------------------------------
IGNORE_NAMES=(.git node_modules dist build out target vendor .venv venv __pycache__ .idea .gradle .mvn .next coverage)

FILES=()
DIRS=()

walk() {
  local root="$1" p rel
  local -a prune=()
  local n
  for n in "${IGNORE_NAMES[@]}"; do
    prune+=(-name "$n" -prune -o)
  done
  while IFS= read -r p; do
    [[ "$p" == "$root" ]] && continue
    rel="${p#"$root"/}"
    if [[ -d "$p" ]]; then
      DIRS+=("$rel")
    else
      FILES+=("$rel")
    fi
  done < <(find "$root" "${prune[@]}" -print)
}

# ---------------------------------------------------------------------------
# Glob matching
# ---------------------------------------------------------------------------
# file_matches <path> <glob>
file_matches() {
  local p="$1" g="$2" base="${1##*/}"
  if [[ "$g" == '*.'* ]]; then
    [[ "$base" == *"${g#\*}" ]]
  elif [[ "$g" == */* ]]; then
    [[ "$p" == "$g" || "$p" == *"/$g" ]]
  else
    [[ "$base" == "$g" ]]
  fi
}

# dir_matches <dir> <glob>
dir_matches() {
  local d="$1" g="$2"
  [[ "$d" == "$g" || "$d" == *"/$g" ]]
}

# json_string_array <elems...> -> sorted, unique JSON array (empty-safe on bash 3.2).
json_string_array() {
  local out="[]" x
  for x in "$@"; do
    [[ -z "$x" ]] && continue
    out="$(jq -c --arg v "$x" '. + [$v]' <<<"$out")"
  done
  jq -c 'unique | sort' <<<"$out"
}

any_file_matches() {
  local g="$1" f
  for f in "${FILES[@]:-}"; do
    [[ -z "$f" ]] && continue
    file_matches "$f" "$g" && return 0
  done
  return 1
}

# ---------------------------------------------------------------------------
# Signal collection -> NDJSON of {ecosystem,path,kind,weight}
# ---------------------------------------------------------------------------
SIGNALS_NDJSON=""

collect_signals() {
  local matrix="$1"
  local eco kind weight glob f d
  # Iterate ecosystem signals: "eco<TAB>glob<TAB>kind<TAB>weight"
  while IFS=$'\t' read -r eco glob kind weight; do
    [[ -z "$eco" ]] && continue
    if [[ "$kind" == "source-layout" ]]; then
      for d in "${DIRS[@]:-}"; do
        [[ -z "$d" ]] && continue
        if dir_matches "$d" "$glob"; then
          SIGNALS_NDJSON+="$(jq -cn --arg e "$eco" --arg p "$d" --arg k "$kind" --argjson w "$weight" \
            '{ecosystem:$e,path:$p,kind:$k,weight:$w}')"$'\n'
        fi
      done
    else
      for f in "${FILES[@]:-}"; do
        [[ -z "$f" ]] && continue
        if file_matches "$f" "$glob"; then
          SIGNALS_NDJSON+="$(jq -cn --arg e "$eco" --arg p "$f" --arg k "$kind" --argjson w "$weight" \
            '{ecosystem:$e,path:$p,kind:$k,weight:$w}')"$'\n'
        fi
      done
    fi
  done < <(jq -r '.ecosystems[] as $e | $e.signals[] | [$e.id, .glob, .kind, (.weight|tostring)] | @tsv' "$matrix")
}

# ---------------------------------------------------------------------------
# Topology / infrastructure / package-managers / build-tools
# ---------------------------------------------------------------------------
detect_topology() {
  local matrix="$1" root="$2"
  local tool type glob mfile mcontains mkey hit f
  local best_type="single" best_tool="null"
  local -a sigs=()
  local have_monorepo=0 have_workspace=0
  while IFS=$'\t' read -r tool type glob mfile mcontains mkey; do
    hit=""
    if [[ "$glob" != "null" && -n "$glob" ]]; then
      if any_file_matches "$glob"; then
        # record the concrete matched file
        for f in "${FILES[@]:-}"; do file_matches "$f" "$glob" && { hit="$f"; break; }; done
      fi
    elif [[ "$mfile" != "null" ]]; then
      if [[ -f "$root/$mfile" ]]; then
        if [[ "$mcontains" != "null" ]] && grep -qF "$mcontains" "$root/$mfile"; then
          hit="$mfile"
        elif [[ "$mkey" != "null" ]] && jq -e --arg k "$mkey" 'has($k)' "$root/$mfile" >/dev/null 2>&1; then
          hit="$mfile"
        fi
      fi
    fi
    if [[ -n "$hit" ]]; then
      sigs+=("$hit")
      [[ "$type" == "monorepo" ]] && have_monorepo=1
      [[ "$type" == "workspace" ]] && have_workspace=1
    fi
  done < <(jq -r '.topology[] | [.tool, .type, (.glob // "null"), (.marker.file // "null"), (.marker.contains // "null"), (.marker.jsonKey // "null")] | @tsv' "$matrix")

  if [[ $have_monorepo -eq 1 ]]; then best_type="monorepo"; else
    [[ $have_workspace -eq 1 ]] && best_type="workspace"
  fi
  # pick first matched tool whose type matches best_type
  if [[ "$best_type" != "single" ]]; then
    while IFS=$'\t' read -r tool type glob mfile mcontains mkey; do
      local matched=0
      if [[ "$glob" != "null" && -n "$glob" ]]; then any_file_matches "$glob" && matched=1
      elif [[ "$mfile" != "null" && -f "$root/$mfile" ]]; then
        if [[ "$mcontains" != "null" ]] && grep -qF "$mcontains" "$root/$mfile"; then matched=1
        elif [[ "$mkey" != "null" ]] && jq -e --arg k "$mkey" 'has($k)' "$root/$mfile" >/dev/null 2>&1; then matched=1; fi
      fi
      if [[ $matched -eq 1 && "$type" == "$best_type" ]]; then best_tool="\"$tool\""; break; fi
    done < <(jq -r '.topology[] | [.tool, .type, (.glob // "null"), (.marker.file // "null"), (.marker.contains // "null"), (.marker.jsonKey // "null")] | @tsv' "$matrix")
  fi

  # emit JSON: {type,tool,signals}
  local sig_json
  sig_json="$(json_string_array "${sigs[@]:-}")"
  jq -cn --arg t "$best_type" --argjson tool "$best_tool" --argjson sigs "$sig_json" \
    '{type:$t, tool:$tool, signals:$sigs}'
}

detect_infra() {
  local matrix="$1"
  local tool glob category f matched
  local ci=() containers=() orchestration=()
  while IFS=$'\t' read -r tool glob category; do
    matched=0
    if [[ "$glob" != *"."* && "$glob" == */* ]]; then
      # directory marker like .github/workflows
      for f in "${FILES[@]:-}"; do [[ "$f" == "$glob" || "$f" == "$glob/"* ]] && { matched=1; break; }; done
    else
      any_file_matches "$glob" && matched=1
    fi
    if [[ $matched -eq 1 ]]; then
      case "$category" in
        ci) ci+=("$tool") ;;
        containers) containers+=("$tool") ;;
        orchestration) orchestration+=("$tool") ;;
      esac
    fi
  done < <(jq -r '.infrastructure[] | [.tool, .glob, .category] | @tsv' "$matrix")

  local ci_j containers_j orch_j
  ci_j="$(json_string_array "${ci[@]:-}")"
  containers_j="$(json_string_array "${containers[@]:-}")"
  orch_j="$(json_string_array "${orchestration[@]:-}")"
  # NB: the variable must not be named `or` — `$or` is a reserved word in jq and never compiles.
  jq -cn --argjson ci "$ci_j" --argjson co "$containers_j" --argjson orch "$orch_j" \
    '{ci:$ci, containers:$co, orchestration:$orch}'
}

detect_list() {
  # $1 matrix, $2 jq-path to array with .tool/.glob
  local matrix="$1" query="$2"
  local tool glob out=()
  while IFS=$'\t' read -r tool glob; do
    any_file_matches "$glob" && out+=("$tool")
  done < <(jq -r "$query"' | [.tool, .glob] | @tsv' "$matrix")
  json_string_array "${out[@]:-}"
}

# ---------------------------------------------------------------------------
# Assembly
# ---------------------------------------------------------------------------
build_report() {
  local matrix="$1" root="$2" topo_json="$3" infra_json="$4" pm_json="$5" bt_json="$6"
  local names_json generated_at deep_j
  names_json=$(jq -c '[.ecosystems[]|{key:.id,value:.name}]|from_entries' "$matrix")
  generated_at=$(date -u +%FT%TZ)
  deep_j=$([[ $DEEP -eq 1 ]] && echo true || echo false)

  printf '%s' "$SIGNALS_NDJSON" | jq -s \
    --arg root "$root" \
    --arg genAt "$generated_at" \
    --argjson names "$names_json" \
    --argjson topology "$topo_json" \
    --argjson infrastructure "$infra_json" \
    --argjson packageManagers "$pm_json" \
    --argjson buildTools "$bt_json" \
    --argjson deep "$deep_j" '
    # group signals by ecosystem
    ( group_by(.ecosystem) ) as $groups
    | ( [ $groups[] | { id: .[0].ecosystem,
          rp: ( [ .[] | select(.kind=="primary-manifest" and (.path|contains("/")|not)) ] | length ),
          fp: ( [ .[] | select(.kind=="primary-manifest") ] | length ) } ] ) as $stats
    | ( [ $stats[].rp ] | add // 0 ) as $rootPrimaries
    | ( $stats | sort_by(.id) | sort_by(-.rp) ) as $ranked
    # deep dominance fallback: with --deep and zero root-level primary manifests,
    # rank by full-depth primary-manifest count instead (ties by id).
    | ( if ($ranked|length) == 0 then null
        elif ($deep and $rootPrimaries == 0) then ( ($stats | sort_by(.id) | sort_by(-.fp))[0].id )
        else $ranked[0].id end ) as $dominant
    # sub-repo enumeration (--deep): top-most nested dirs holding their own primary manifest.
    | ( [ .[] | select(.kind=="primary-manifest" and (.path|contains("/"))) ] ) as $nested
    | ( [ $nested[].path | split("/")[:-1] | join("/") ] | unique ) as $cands
    | ( [ $cands[] | . as $d
          | select( ( [ $cands[] | select(. != $d and ($d | startswith(. + "/"))) ] | length ) == 0 ) ] ) as $tops
    | ( [ $tops[] | . as $d
          | { path: $d,
              primaryManifests: ( [ $nested[] | select(.path | startswith($d + "/")) | .path ] | unique ),
              dominantEcosystem:
                ( [ $nested[] | select(.path | startswith($d + "/")) ]
                  | group_by(.ecosystem)
                  | [ .[] | { id: .[0].ecosystem, n: length } ]
                  | sort_by(.id) | sort_by(-.n)
                  | .[0].id ) } ]
        | sort_by(.path) ) as $subRepos
    # deep topology inference: >= 2 sub-repos, no root manifest, no workspace marker => monorepo.
    | ( if ($deep and ($subRepos|length) >= 2 and $rootPrimaries == 0 and $topology.type == "single")
        then ($topology + {type: "monorepo", tool: null})
        else $topology end ) as $topo
    | { schemaVersion: "1.0",
        root: $root,
        generatedBy: "bash",
        generatedAt: $genAt,
        ecosystems: ( [ $groups[]
          | { id: .[0].ecosystem,
              name: ( $names[.[0].ecosystem] // .[0].ecosystem ),
              signals: ( [ .[] | {path,kind,weight} ] | sort_by(.path, .kind) ),
              rawScore: null,
              confidence: null,
              confidenceBucket: null,
              role: ( if .[0].ecosystem == $dominant then "primary" else "auxiliary" end )
            } ] | sort_by(.id) ),
        packageManagers: $packageManagers,
        buildTools: $buildTools,
        topology: $topo,
        frameworks: [],
        testing: [],
        infrastructure: $infrastructure,
        dominantEcosystem: $dominant
      }
      + ( if $deep then { subRepos: $subRepos } else {} end )'
}

# ---------------------------------------------------------------------------
# Text renderer
# ---------------------------------------------------------------------------
render_text() {
  local report="$1"
  jq -r '
    "Repository: \(.root)",
    "Detected by: \(.generatedBy)",
    "Dominant ecosystem: \(.dominantEcosystem // "(none)")",
    "",
    "Ecosystems:",
    ( if (.ecosystems|length)==0 then "  (none)"
      else (.ecosystems[] | "  - \(.name) [\(.role)] signals=\(.signals|length) (presence-only)") end ),
    "",
    "Package managers: \((.packageManagers|join(", ")) // "" | if .=="" then "(none)" else . end)",
    "Build tools: \((.buildTools|join(", ")) // "" | if .=="" then "(none)" else . end)",
    "Topology: \(.topology.type)\(if .topology.tool then " (\(.topology.tool))" else "" end)",
    ( if ((.subRepos // [])|length)>0 then
        "Sub-repos:",
        ( .subRepos[] | "  - \(.path) (\(.dominantEcosystem // "unknown"), \(.primaryManifests|length) manifest(s))" )
      else empty end ),
    ( if ((.infrastructure.ci+.infrastructure.containers+.infrastructure.orchestration)|length)>0
      then "Infrastructure: \((.infrastructure.ci+.infrastructure.containers+.infrastructure.orchestration)|join(", "))"
      else empty end )
  ' <<<"$report"
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
main() {
  parse_args "$@"
  local matrix root
  matrix="$(rf_matrix_path)"
  [[ -f "$matrix" ]] || die "signal matrix not found: $matrix (set RF_MATRIX)"
  root="$(cd "$TARGET" && pwd)"

  walk "$root"
  collect_signals "$matrix"
  local topo infra pms bts report
  topo="$(detect_topology "$matrix" "$root")"
  infra="$(detect_infra "$matrix")"
  pms="$(detect_list "$matrix" '.packageManagers[]')"
  bts="$(detect_list "$matrix" '.buildTools[]')"
  report="$(build_report "$matrix" "$root" "$topo" "$infra" "$pms" "$bts")"

  local eco_count
  eco_count=$(jq '.ecosystems|length' <<<"$report")

  if [[ "$FORMAT" == "text" ]]; then
    render_text "$report"
  else
    jq . <<<"$report"
  fi

  [[ "$eco_count" -gt 0 ]] && exit 0 || exit 1
}

main "$@"
