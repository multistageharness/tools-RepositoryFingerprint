/** Weighted aggregation, dominant/auxiliary resolution, and assembly into the shared schema. */
import type { DetectionReport, EcosystemResult, RawSignal, Signal, SubRepo } from "./types.js";
import type { SignalMatrix } from "./matrix.js";
import { posixDirname } from "./signals.js";
import {
  bucketOf,
  confidenceOf,
  primaryManifestCount,
  proximateScore,
  rawScoreOf,
} from "./confidence.js";

export type ScoreMode = "confidence" | "presence";

interface EcoGroup {
  id: string;
  name: string;
  raw: RawSignal[];
}

function groupByEcosystem(matrix: SignalMatrix, signals: RawSignal[]): EcoGroup[] {
  const names = new Map(matrix.ecosystems.map((e) => [e.id, e.name] as const));
  const byId = new Map<string, RawSignal[]>();
  for (const s of signals) {
    const arr = byId.get(s.ecosystemId) ?? [];
    arr.push(s);
    byId.set(s.ecosystemId, arr);
  }
  return [...byId.entries()].map(([id, raw]) => ({ id, name: names.get(id) ?? id, raw }));
}

/** Root-level primary-manifest count (depth <= 1), used for presence-mode dominance & tie-breaks. */
function rootPrimaryCount(raw: RawSignal[]): number {
  return primaryManifestCount(raw, true);
}

function pickDominant(groups: EcoGroup[], mode: ScoreMode, deep = false): string | null {
  if (groups.length === 0) return null;
  // Deep dominance fallback: with --deep and zero root-proximate (depth <= 1) primary manifests,
  // lift the depth limit and rank on full-depth evidence instead.
  const fullDepth = deep && groups.every((g) => rootPrimaryCount(g.raw) === 0);
  const scored = groups.map((g) => ({
    id: g.id,
    score:
      mode === "confidence"
        ? fullDepth
          ? rawScoreOf(g.raw)
          : proximateScore(g.raw)
        : primaryManifestCount(g.raw, !fullDepth),
    primaries: primaryManifestCount(g.raw, !fullDepth),
  }));
  scored.sort((a, b) => {
    if (b.score !== a.score) return b.score - a.score;
    if (b.primaries !== a.primaries) return b.primaries - a.primaries;
    return a.id < b.id ? -1 : a.id > b.id ? 1 : 0;
  });
  return scored[0]!.id;
}

/** Deep-scan sub-repo enumeration: top-most nested dirs holding their own primary manifest. */
export function computeSubRepos(signals: RawSignal[]): SubRepo[] {
  const nested = signals.filter((s) => s.kind === "primary-manifest" && s.path.includes("/"));
  const cands = [...new Set(nested.map((s) => posixDirname(s.path)))];
  const tops = cands
    .filter((d) => !cands.some((c) => c !== d && d.startsWith(c + "/")))
    .sort();
  return tops.map((d) => {
    const inTree = nested.filter((s) => s.path.startsWith(d + "/"));
    const counts = new Map<string, number>();
    for (const s of inTree) counts.set(s.ecosystemId, (counts.get(s.ecosystemId) ?? 0) + 1);
    const ranked = [...counts.entries()].sort((a, b) =>
      b[1] !== a[1] ? b[1] - a[1] : a[0] < b[0] ? -1 : 1,
    );
    return {
      path: d,
      primaryManifests: [...new Set(inTree.map((s) => s.path))].sort(),
      dominantEcosystem: ranked.length > 0 ? ranked[0]![0] : null,
    };
  });
}

function toSignals(raw: RawSignal[]): Signal[] {
  return raw
    .map((s) => ({ path: s.path, kind: s.kind, weight: s.weight }))
    .sort((a, b) => (a.path < b.path ? -1 : a.path > b.path ? 1 : a.kind < b.kind ? -1 : 1));
}

export interface Aggregation {
  ecosystems: EcosystemResult[];
  dominantEcosystem: string | null;
}

export function aggregate(
  matrix: SignalMatrix,
  signals: RawSignal[],
  mode: ScoreMode,
  deep = false,
): Aggregation {
  const groups = groupByEcosystem(matrix, signals);
  const dominant = pickDominant(groups, mode, deep);

  const ecosystems: EcosystemResult[] = groups.map((g) => {
    const rawScore = mode === "confidence" ? rawScoreOf(g.raw) : null;
    const confidence = rawScore != null ? confidenceOf(rawScore) : null;
    const confidenceBucket = confidence != null ? bucketOf(confidence) : null;
    return {
      id: g.id,
      name: g.name,
      signals: toSignals(g.raw),
      rawScore,
      confidence,
      confidenceBucket,
      role: g.id === dominant ? "primary" : "auxiliary",
    };
  });

  ecosystems.sort((a, b) => (a.id < b.id ? -1 : a.id > b.id ? 1 : 0));
  return { ecosystems, dominantEcosystem: dominant };
}

/** Assemble the final, canonically-ordered report. */
export function assembleReport(parts: Omit<DetectionReport, "schemaVersion">): DetectionReport {
  return {
    schemaVersion: "1.0",
    ...parts,
    ecosystems: [...parts.ecosystems].sort((a, b) => (a.id < b.id ? -1 : a.id > b.id ? 1 : 0)),
    packageManagers: [...new Set(parts.packageManagers)].sort(),
    buildTools: [...new Set(parts.buildTools)].sort(),
    frameworks: [...parts.frameworks].sort((a, b) =>
      a.ecosystem !== b.ecosystem
        ? a.ecosystem < b.ecosystem
          ? -1
          : 1
        : a.name < b.name
          ? -1
          : a.name > b.name
            ? 1
            : 0,
    ),
    testing: [...parts.testing].sort((a, b) =>
      a.ecosystem !== b.ecosystem
        ? a.ecosystem < b.ecosystem
          ? -1
          : 1
        : a.framework < b.framework
          ? -1
          : a.framework > b.framework
            ? 1
            : 0,
    ),
    topology: { ...parts.topology, signals: [...new Set(parts.topology.signals)].sort() },
    infrastructure: {
      ci: [...new Set(parts.infrastructure.ci)].sort(),
      containers: [...new Set(parts.infrastructure.containers)].sort(),
      orchestration: [...new Set(parts.infrastructure.orchestration)].sort(),
    },
    ...(parts.subRepos
      ? {
          subRepos: [...parts.subRepos]
            .sort((a, b) => (a.path < b.path ? -1 : a.path > b.path ? 1 : 0))
            .map((s) => ({ ...s, primaryManifests: [...s.primaryManifests].sort() })),
        }
      : {}),
  };
}
