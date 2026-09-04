/** Topology (monorepo/workspace) resolution + package-manager / build-tool inference. */
import { readFileSync } from "node:fs";
import { join } from "node:path";
import type { Topology } from "./types.js";
import type { SignalMatrix, TopologyDef } from "./matrix.js";
import { fileMatches } from "./signals.js";

function safeRead(root: string, rel: string): string | null {
  try {
    return readFileSync(join(root, rel), "utf8");
  } catch {
    return null;
  }
}

function matchTopologyDef(def: TopologyDef, root: string, files: string[]): string | null {
  if (def.glob) {
    const hit = files.find((f) => fileMatches(f, def.glob!));
    return hit ?? null;
  }
  if (def.marker) {
    const { file, contains, jsonKey } = def.marker;
    const hit = files.find((f) => fileMatches(f, file));
    if (!hit) return null;
    const content = safeRead(root, hit);
    if (content == null) return null;
    if (contains && content.includes(contains)) return hit;
    if (jsonKey) {
      try {
        const obj = JSON.parse(content) as Record<string, unknown>;
        if (Object.prototype.hasOwnProperty.call(obj, jsonKey)) return hit;
      } catch {
        return null;
      }
    }
    return null;
  }
  return null;
}

export function resolveTopology(matrix: SignalMatrix, root: string, files: string[]): Topology {
  const matched: { def: TopologyDef; signal: string }[] = [];
  for (const def of matrix.topology) {
    const signal = matchTopologyDef(def, root, files);
    if (signal != null) matched.push({ def, signal });
  }
  if (matched.length === 0) return { type: "single", tool: null, signals: [] };

  const hasMonorepo = matched.some((m) => m.def.type === "monorepo");
  const type = hasMonorepo ? "monorepo" : "workspace";
  // Prefer a tool whose type matches the resolved topology type, else the first match.
  const primary = matched.find((m) => m.def.type === type) ?? matched[0]!;
  const signals = [...new Set(matched.map((m) => m.signal))].sort();
  return { type, tool: primary.def.tool, signals };
}

export function inferPackageManagers(matrix: SignalMatrix, files: string[]): string[] {
  const tools = new Set<string>();
  for (const pm of matrix.packageManagers) {
    if (files.some((f) => fileMatches(f, pm.glob))) tools.add(pm.tool);
  }
  return [...tools].sort();
}

export function inferBuildTools(matrix: SignalMatrix, files: string[]): string[] {
  const tools = new Set<string>();
  for (const bt of matrix.buildTools) {
    if (files.some((f) => fileMatches(f, bt.glob))) tools.add(bt.tool);
  }
  return [...tools].sort();
}
