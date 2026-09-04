/** Matches walked paths against the ecosystem signal globs, producing depth-tagged RawSignals. */
import type { RawSignal } from "./types.js";
import type { EcosystemDef, SignalMatrix } from "./matrix.js";
import type { WalkResult } from "./walker.js";

export function posixDirname(rel: string): string {
  const i = rel.lastIndexOf("/");
  return i < 0 ? "" : rel.slice(0, i);
}
export function basename(rel: string): string {
  const i = rel.lastIndexOf("/");
  return i < 0 ? rel : rel.slice(i + 1);
}
export function segments(dir: string): number {
  return dir === "" ? 0 : dir.split("/").length;
}
/** Depth of a file: repo-root file = 1. */
export function fileDepth(rel: string): number {
  return segments(posixDirname(rel)) + 1;
}

/** Does a file path match a file-kind glob? Supports `*.ext`, `a/b/c` and bare basename globs. */
export function fileMatches(rel: string, glob: string): boolean {
  if (glob.startsWith("*.")) return basename(rel).endsWith(glob.slice(1));
  if (glob.includes("/")) return rel === glob || rel.endsWith("/" + glob);
  return basename(rel) === glob;
}

function collectForEcosystem(eco: EcosystemDef, walk: WalkResult): RawSignal[] {
  const out: RawSignal[] = [];
  for (const def of eco.signals) {
    if (def.kind === "source-layout") {
      for (const dir of walk.dirs) {
        if (dir === def.glob || dir.endsWith("/" + def.glob)) {
          const anchor = dir.slice(0, dir.length - def.glob.length).replace(/\/$/, "");
          out.push({
            ecosystemId: eco.id,
            path: dir,
            kind: def.kind,
            weight: def.weight,
            depth: anchor === "" ? 1 : segments(anchor) + 1,
          });
        }
      }
    } else {
      for (const rel of walk.files) {
        if (fileMatches(rel, def.glob)) {
          out.push({
            ecosystemId: eco.id,
            path: rel,
            kind: def.kind,
            weight: def.weight,
            depth: fileDepth(rel),
          });
        }
      }
    }
  }
  return out;
}

export function collectSignals(matrix: SignalMatrix, walk: WalkResult): RawSignal[] {
  const out: RawSignal[] = [];
  for (const eco of matrix.ecosystems) out.push(...collectForEcosystem(eco, walk));
  return out;
}
