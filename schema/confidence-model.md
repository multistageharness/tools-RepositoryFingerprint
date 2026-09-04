# Diagnostic Confidence Model

This document is the formal, deterministic definition of the **Diagnostic Confidence** score.
The TypeScript and Python detectors implement it **identically** — the [Worked Examples](#worked-examples)
below are the parity oracle their unit tests assert against. The bash detector does **not** implement
this model; it emits `rawScore` / `confidence` / `confidenceBucket` as `null`.

## 1. Signal kinds & default weights

Every signal in [`signal-matrix.json`](./signal-matrix.json) carries an explicit `weight`, but each
weight is the default for its `kind`:

| Kind | Default weight | Meaning |
| --- | ---: | --- |
| `primary-manifest` | 1.0 | The canonical manifest for the ecosystem (`pom.xml`, `package.json`, `go.mod`, …). |
| `config` | 0.5 | A strong ecosystem config (`tsconfig.json`, `settings.gradle`, `*.sln`). |
| `lockfile` | 0.4 | A resolved dependency lock (`package-lock.json`, `poetry.lock`, `Cargo.lock`). |
| `build-wrapper` | 0.3 | A build wrapper / driver (`mvnw`, `gradlew`, `Makefile`). |
| `source-layout` | 0.2 | A conventional source tree (`src/main/java`, `src/main/kotlin`). |
| `workspace-marker` | 0.6 | A monorepo / workspace marker. Feeds **topology**, not the ecosystem score. |
| `infra-marker` | 0.0 | A CI / container / orchestration marker. Feeds **infrastructure**, not the ecosystem score. |

Only the first five kinds contribute to an ecosystem's `rawScore`. `workspace-marker` and
`infra-marker` are catalogued into `topology` and `infrastructure` respectively.

## 2. Depth

Signals found deeper in the tree are weaker evidence for the repository-level ecosystem. Define the
**depth** of a signal as the number of path segments of its location, with a repo-root file at
**depth 1**:

```
depth(path) = segments(dirname(path)) + 1
```

- A root file such as `pom.xml` → `dirname` is the root (0 segments) → **depth 1**.
- `tools/script/requirements.txt` → `dirname` = `tools/script` (2 segments) → **depth 3**.
- A `source-layout` directory marker is recorded at its **anchor directory** (the directory that
  contains the source tree). A root-level `src/main/java` tree is anchored at the root → **depth 1**.

## 3. Depth decay

```
decayed(signal) = weight(signal) * 0.5 ^ max(0, depth(signal) - 1)
```

So a signal loses half its weight per level below the root. A `primary-manifest` (weight 1.0) at
depth 3 contributes `1.0 * 0.5^2 = 0.25`.

## 4. Raw score

```
rawScore(eco) = Σ decayed(signal)   over all signals attributed to `eco`
```

## 5. Normalization

```
confidence(eco) = round4( 1 - exp(-k · rawScore(eco)) )

k = 1.9   (steepness constant; `STEEPNESS` in both engines)
```

`round4` is **round-half-up** (half away from zero) to **4 decimal places**. JavaScript's
`Math.round(x * 1e4) / 1e4` rounds half-up for positive numbers; Python **must** use an explicit
half-up rounding (e.g. `decimal.Decimal(...).quantize(..., ROUND_HALF_UP)`) because the built-in
`round()` is banker's rounding and would diverge.

`confidence` is monotonic in `rawScore` and lies in `[0, 1)`.

**Calibration of `k`** (against the post-enrichment fixture rawScore distribution; the smallest
one-decimal value clearing the floor with ≥ 0.02 of confidence margin):

1. **Floor** — every root-evidenced primary reaches `certain`: the minimum root-evidenced
   primary fixture rawScore is `r_min = 1.4`, and `k · 1.4 = 2.66 ≥ ln(10) = 2.3026`
   (`confidence = 0.9301`, margin 0.0301 above the 0.90 threshold). `k = 1.8` was rejected
   (0.9195, margin 0.0195 < 0.02); `k = 1.5` fails the floor outright (0.8775).
2. **Ceiling** — nothing saturates to 1.0000: the maximum fixture rawScore is `r_max = 2.3`,
   and `k · 2.3 = 4.37 < 9.9035 = −ln(5 × 10⁻⁵)` (`confidence = 0.9873 < 1`), preserving
   `confidence ∈ [0, 1)` under round4.
3. **Discrimination** — deep-only evidence stays below the band: the depth-2-only
   `multi-repo-npm` primary (rawScore 1.0) lands at `0.8504 < 0.90`, and every auxiliary stays
   below it. `k = 2` also satisfies all three constraints but was rejected as not the smallest
   passing value (less headroom under the 0.90 boundary for deep-only cases).

## 6. Buckets

| Bucket | Condition (on `confidence`) |
| --- | --- |
| `certain` | `>= 0.9` |
| `high` | `>= 0.7` |
| `medium` | `>= 0.4` |
| `low` | `> 0` |
| `none` | `== 0` (i.e. `rawScore == 0`) |

## 7. Dominant / auxiliary roles

Repository-level dominance considers only **root-proximate** evidence — signals at **depth ≤ 1**:

```
proximateScore(eco) = Σ decayed(signal)   over signals of `eco` with depth <= 1
dominant = argmax_eco proximateScore(eco)
```

Ties are broken by (1) **more `primary-manifest` signals at depth ≤ 1**, then (2) **lexicographically
smallest `id`**. The dominant ecosystem gets `role = "primary"`; **every other ecosystem with
`rawScore > 0`** gets `role = "auxiliary"`. If no ecosystem has any signal, `dominantEcosystem` is
`null`.

## 8. Deep scan (`--deep` / `--shadow-scan`)

Default behavior is exactly as above and the report is byte-for-byte unchanged without the flag.
With the opt-in `--deep` flag (canonical name; `--shadow-scan` is an accepted alias) the detectors
become monorepo-aware:

1. **Deep dominance fallback.** When a repository has **zero `primary-manifest` signals at
   depth ≤ 1** (e.g. a "multi-repo" monorepo whose manifests all live in nested sub-dirs), the
   depth ≤ 1 restriction of §7 is lifted and dominance is ranked on **full-depth** evidence
   instead: the TS/Py detectors rank by full-depth `rawScore` (ties by full-depth
   `primary-manifest` count, then smallest `id`); the presence-only bash/PowerShell detectors rank
   by full-depth `primary-manifest` count (ties by smallest `id`). When any root-proximate primary
   manifest exists, dominance is computed exactly as in §7.
2. **Sub-repo enumeration.** The report gains an additive, optional `subRepos` array: each
   **top-most** nested directory that holds its own `primary-manifest` signal (directories nested
   under an already-listed sub-repo are folded into it). Each entry carries `path`, the
   `primaryManifests` found in its subtree, and its own presence-ranked `dominantEcosystem`
   (full-depth manifest count, ties by smallest `id`). Entries are sorted by `path`.
3. **Topology inference.** When a deep scan finds **≥ 2 sub-repos**, **no root-proximate primary
   manifest**, and no workspace/monorepo marker matched (i.e. marker-driven topology said
   `single`), `topology.type` is inferred as `"monorepo"` with `tool: null`.

`subRepos` is emitted **only** on deep runs (it may be an empty array there); non-deep reports omit
the key entirely, keeping the pre-deep contract stable. Exit-code semantics are unchanged.

## Worked Examples

These are exact and are asserted by the TS and Py unit tests.

### Example A — a Node + TypeScript project (single ecosystem instance)

Signals, all at **depth 1**:

| Signal | Kind | Weight | Depth | Decayed |
| --- | --- | ---: | ---: | ---: |
| `package.json` | primary-manifest | 1.0 | 1 | 1.0 |
| `tsconfig.json` | config | 0.5 | 1 | 0.5 |
| `package-lock.json` | lockfile | 0.4 | 1 | 0.4 |
| `.npmrc` | config | 0.5 | 1 | 0.5 |

- `rawScore = 1.0 + 0.5 + 0.4 + 0.5 = 2.4`
- `confidence = 1 - exp(-1.9 · 2.4) = 1 - exp(-4.56) = 1 - 0.0104621 = 0.9895379 → 0.9895`
- `bucket = certain` (≥ 0.9)

### Example B — Java-dominant with a nested Python auxiliary

`fixtures/java-dominant-nested-py`: a root Maven project with a deep helper script that has its own
`requirements.txt`.

**Java (Maven)** — all at depth 1:

| Signal | Kind | Weight | Depth | Decayed |
| --- | --- | ---: | ---: | ---: |
| `pom.xml` | primary-manifest | 1.0 | 1 | 1.0 |
| `mvnw` | build-wrapper | 0.3 | 1 | 0.3 |
| `mvnw.cmd` | build-wrapper | 0.3 | 1 | 0.3 |
| `src/main/java` | source-layout | 0.2 | 1 | 0.2 |
| `src/test/java` | source-layout | 0.2 | 1 | 0.2 |

- `rawScore(java-maven) = 1.0 + 0.3 + 0.3 + 0.2 + 0.2 = 2.0`
- `confidence = 1 - exp(-1.9 · 2.0) = 1 - exp(-3.8) = 1 - 0.0223708 = 0.9776292 → 0.9776` → bucket `certain`
- `proximateScore(java-maven) = 2.0`

**Python** — one manifest at `tools/script/requirements.txt` (depth 3):

| Signal | Kind | Weight | Depth | Decayed |
| --- | --- | ---: | ---: | ---: |
| `tools/script/requirements.txt` | primary-manifest | 1.0 | 3 | `1.0 * 0.5^2 = 0.25` |

- `rawScore(python) = 0.25`
- `confidence = 1 - exp(-1.9 · 0.25) = 1 - exp(-0.475) = 1 - 0.6218851 = 0.3781149 → 0.3781` → bucket `low`
- `proximateScore(python) = 0` (no signal at depth ≤ 1)

**Roles:** `proximateScore(java-maven)=2.0 > proximateScore(python)=0` ⇒ **java-maven is dominant
(`primary`)**, **python is `auxiliary`**. `dominantEcosystem = "java-maven"`.
