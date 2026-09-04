/** Recursive filesystem walker: collects relative file & directory paths, ignoring noise dirs. */
import { readdirSync } from "node:fs";
import { join, relative, sep } from "node:path";

export const IGNORED_DIRS = new Set([
  ".git",
  "node_modules",
  "dist",
  "build",
  "out",
  "target",
  "vendor",
  ".venv",
  "venv",
  "__pycache__",
  ".idea",
  ".gradle",
  ".mvn",
  ".next",
  "coverage",
]);

export interface WalkResult {
  /** Relative POSIX file paths. */
  files: string[];
  /** Relative POSIX directory paths (excludes the root itself). */
  dirs: string[];
}

const DEFAULT_MAX_DEPTH = 12;

function toPosix(p: string): string {
  return sep === "/" ? p : p.split(sep).join("/");
}

export function walk(root: string, maxDepth: number = DEFAULT_MAX_DEPTH): WalkResult {
  const files: string[] = [];
  const dirs: string[] = [];

  const visit = (abs: string, depth: number): void => {
    if (depth > maxDepth) return;
    let entries;
    try {
      entries = readdirSync(abs, { withFileTypes: true });
    } catch {
      return;
    }
    for (const e of entries) {
      const childAbs = join(abs, e.name);
      const rel = toPosix(relative(root, childAbs));
      if (e.isDirectory()) {
        if (IGNORED_DIRS.has(e.name)) continue;
        dirs.push(rel);
        visit(childAbs, depth + 1);
      } else if (e.isFile()) {
        files.push(rel);
      }
    }
  };

  visit(root, 1);
  files.sort();
  dirs.sort();
  return { files, dirs };
}
