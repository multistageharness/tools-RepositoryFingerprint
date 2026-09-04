/** Infrastructure marker detection: CI, containers, orchestration. */
import type { Infrastructure } from "./types.js";
import type { SignalMatrix } from "./matrix.js";
import { fileMatches } from "./signals.js";

export function resolveInfrastructure(matrix: SignalMatrix, files: string[]): Infrastructure {
  const ci = new Set<string>();
  const containers = new Set<string>();
  const orchestration = new Set<string>();
  for (const inf of matrix.infrastructure) {
    // `.github/workflows` is a directory marker: match any file beneath it.
    const dirMarker = !inf.glob.startsWith("*.") && inf.glob.includes("/") && !inf.glob.includes(".");
    const hit = dirMarker
      ? files.some((f) => f === inf.glob || f.startsWith(inf.glob + "/"))
      : files.some((f) => fileMatches(f, inf.glob));
    if (!hit) continue;
    if (inf.category === "ci") ci.add(inf.tool);
    else if (inf.category === "containers") containers.add(inf.tool);
    else orchestration.add(inf.tool);
  }
  return {
    ci: [...ci].sort(),
    containers: [...containers].sort(),
    orchestration: [...orchestration].sort(),
  };
}
