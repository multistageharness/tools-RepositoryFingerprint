# Polyglot Repository Fingerprint

Detect a repository's **ecosystems**, **package managers / build tools**, **topology**
(monorepo/workspace), **frameworks**, **testing tools**, and **infrastructure** signals — with four
implementations that share one JSON output contract:

| Impl | Path | What it does |
| --- | --- | --- |
| **bash** | [`packages/bash`](packages/bash) | Dependency-free presence scanner (`grep`/`test -f` style). No manifest parsing, no confidence math. |
| **PowerShell** | [`packages/powershell`](packages/powershell) | Windows/cross-platform twin of the bash scanner — same presence-only contract, built-in cmdlets only (no `jq`). |
| **TypeScript** | [`packages/ts`](packages/ts) | Full pipeline: manifest parsing, framework fingerprinting, and **Diagnostic Confidence** scoring. |
| **Python** | [`packages/py`](packages/py) | Functional twin of the TS detector — same contract, same confidence model. |

All four emit the shared **Detection Report** defined in [`schema/`](schema), and a
[parity harness](scripts/parity.mjs) proves they agree within documented tolerances.

## The shared contract

- [`schema/detection-report.schema.json`](schema/detection-report.schema.json) — the JSON Schema
  (draft 2020-12) every implementation validates against.
- [`schema/signal-matrix.json`](schema/signal-matrix.json) — the single catalog of ecosystems,
  frameworks, testing, topology and infrastructure signals (with weights) all impls read.
- [`schema/confidence-model.md`](schema/confidence-model.md) — the exact Diagnostic Confidence
  formula the TS and Python detectors implement identically.

A report carries per-ecosystem `signals`, `rawScore`, `confidence`, `confidenceBucket` and `role`
(`primary`/`auxiliary`), plus `packageManagers`, `buildTools`, `topology`, `frameworks`, `testing`,
`infrastructure` and `dominantEcosystem`. The **bash** and **PowerShell** impls leave the confidence
fields `null` and `frameworks`/`testing` empty.

## Diagnostic Confidence (summary)

Each ecosystem's signals are weighted by kind (`primary-manifest` 1.0, `config` 0.5, `lockfile` 0.4,
`build-wrapper` 0.3, `source-layout` 0.2) and **decayed by depth** (`weight × 0.5^(depth−1)`, root =
depth 1). Then:

```
rawScore     = Σ decayed weights
confidence   = round4(1 − exp(−k·rawScore))    # k = 1.9 (STEEPNESS); half-up, 4 decimals
bucket       = certain≥0.9  high≥0.7  medium≥0.4  low>0  none=0
dominant     = argmax of root-proximate (depth ≤ 1) score; others with rawScore>0 → auxiliary
```

Full spec + worked examples: [`schema/confidence-model.md`](schema/confidence-model.md).

## Usage

**bash** (needs only `bash`, `jq`, `find`):

```bash
packages/bash/repo-fingerprint.sh <path> --format json   # or: --format text
```

**PowerShell** (needs only PowerShell 7+ / `pwsh` — no external tools):

```powershell
pwsh packages/powershell/repo-fingerprint.ps1 <path> --format json   # or: --format text
```

**TypeScript** (Node ≥ 20):

```bash
cd packages/ts && npm ci && npm run build
node dist/cli.js <path> --format json
# after `npm link` (or install): repo-fingerprint <path>
```

**Python** (≥ 3.11, stdlib-only runtime):

```bash
pip install -e 'packages/py[test]'
repo-fingerprint <path> --format text
```

All four share exit-code semantics: **0** = ≥1 ecosystem detected, **1** = none, **2** = usage error.

### Deep scan (`--deep` / `--shadow-scan`)

Every CLI accepts an opt-in **`--deep`** flag (canonical; **`--shadow-scan`** is an accepted
alias) that makes the scan monorepo-aware — built for "multi-repo" repositories whose manifests
all live in nested sub-directories (no root manifest):

- **Dominance fallback** — when a repo has zero root-proximate (depth ≤ 1) primary manifests,
  dominance is ranked on full-depth evidence instead of reporting an arbitrary pick.
- **`subRepos`** — the report gains an additive optional array listing each top-most nested
  directory with its own primary manifest (`path`, `primaryManifests`, `dominantEcosystem`).
- **Topology inference** — ≥ 2 sub-repos with no root manifest and no workspace marker ⇒
  `topology.type: "monorepo"` (`tool: null`).

Without the flag the report is byte-for-byte unchanged. See
[`schema/confidence-model.md`](schema/confidence-model.md) §8 for the exact rules.

```bash
packages/bash/repo-fingerprint.sh <path> --deep --format json
```

## Parity harness

Runs every impl over every fixture in [`fixtures/`](fixtures) — once with default arguments and
once with `--deep` — applies the tolerance rules in
[`scripts/parity-tolerances.json`](scripts/parity-tolerances.json), and prints a pass/fail matrix:

```bash
node scripts/parity.mjs          # human matrix; exit 1 on divergence
node scripts/parity.mjs --json   # machine-readable
```

Golden reports (`fixtures/*/expected-report.json` + `.bash.json` + `.powershell.json`) are generated
from the reference TypeScript detector and schema-validated:

```bash
node scripts/gen-goldens.mjs           # regenerate
node scripts/gen-goldens.mjs --check   # CI drift guard
```

## Testing

| Impl | Command |
| --- | --- |
| bash | `bash packages/bash/tests/exit-codes.sh && bash packages/bash/tests/report.sh && bash packages/bash/tests/deep.sh` |
| PowerShell | `pwsh packages/powershell/tests/exit-codes.ps1 && pwsh packages/powershell/tests/report.ps1 && pwsh packages/powershell/tests/deep.ps1` |
| TypeScript | `cd packages/ts && npm test` |
| Python | `cd packages/py && python -m pytest` |
| Parity | `node scripts/parity.mjs` |

CI ([`.github/workflows/ci.yml`](.github/workflows/ci.yml)) runs a per-language job plus a parity
job that depends on all four.
