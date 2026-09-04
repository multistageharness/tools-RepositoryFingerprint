/** Top-level orchestration: walk a repo and produce a full DetectionReport. */
import { resolve } from "node:path";
import type { DetectionReport, GeneratedBy } from "./types.js";
import { loadMatrix } from "./matrix.js";
import { walk } from "./walker.js";
import { collectSignals } from "./signals.js";
import { parseManifests } from "./parsers.js";
import { matchFrameworks, matchTesting } from "./frameworks.js";
import { inferBuildTools, inferPackageManagers, resolveTopology } from "./topology.js";
import { resolveInfrastructure } from "./infra.js";
import { aggregate, assembleReport, computeSubRepos } from "./report.js";
import { primaryManifestCount } from "./confidence.js";

export interface FingerprintOptions {
  generatedBy?: GeneratedBy;
  /** Timestamp override (mostly for deterministic tests). */
  now?: string;
  /** Deep (shadow) scan: monorepo-aware dominance fallback + sub-repo enumeration. */
  deep?: boolean;
}

export function fingerprint(root: string, opts: FingerprintOptions = {}): DetectionReport {
  const absRoot = resolve(root);
  const matrix = loadMatrix();
  const tree = walk(absRoot);
  const deep = opts.deep ?? false;

  const signals = collectSignals(matrix, tree);
  const pools = parseManifests(absRoot, tree.files);
  const { ecosystems, dominantEcosystem } = aggregate(matrix, signals, "confidence", deep);

  let topology = resolveTopology(matrix, absRoot, tree.files);
  let subRepos;
  if (deep) {
    subRepos = computeSubRepos(signals);
    // Deep topology inference: >= 2 sub-repos, no root-proximate primary manifest, and no
    // workspace/monorepo marker already detected => a marker-less "multi-repo" monorepo.
    const rootPrimaries = primaryManifestCount(signals, true);
    if (subRepos.length >= 2 && rootPrimaries === 0 && topology.type === "single") {
      topology = { ...topology, type: "monorepo", tool: null };
    }
  }

  return assembleReport({
    root: absRoot,
    generatedBy: opts.generatedBy ?? "ts",
    generatedAt: opts.now ?? new Date().toISOString(),
    ecosystems,
    packageManagers: inferPackageManagers(matrix, tree.files),
    buildTools: inferBuildTools(matrix, tree.files),
    topology,
    frameworks: matchFrameworks(matrix, pools),
    testing: matchTesting(matrix, pools),
    infrastructure: resolveInfrastructure(matrix, tree.files),
    dominantEcosystem,
    ...(subRepos ? { subRepos } : {}),
  });
}
