/** Framework & testing-tool fingerprinting: match dependency pools against the matrix rules. */
import type { FrameworkResult, TestingResult } from "./types.js";
import type { SignalMatrix } from "./matrix.js";
import type { DependencyPools } from "./parsers.js";

function poolFor(ecosystem: string, pools: DependencyPools): Set<string> {
  switch (ecosystem) {
    case "node":
    case "typescript":
      return pools.js;
    case "python":
      return pools.py;
    case "java-maven":
    case "java-gradle":
    case "kotlin":
      return pools.java;
    case "go":
      return pools.go;
    case "rust":
      return pools.rust;
    default:
      return new Set();
  }
}

export function matchFrameworks(matrix: SignalMatrix, pools: DependencyPools): FrameworkResult[] {
  const out: FrameworkResult[] = [];
  for (const def of matrix.frameworks) {
    const pool = poolFor(def.ecosystem, pools);
    const evidence = def.deps.filter((d) => pool.has(d)).sort();
    if (evidence.length > 0) {
      out.push({ ecosystem: def.ecosystem, name: def.name, evidence });
    }
  }
  return out;
}

export function matchTesting(matrix: SignalMatrix, pools: DependencyPools): TestingResult[] {
  const out: TestingResult[] = [];
  for (const def of matrix.testing) {
    const pool = poolFor(def.ecosystem, pools);
    if (def.deps.some((d) => pool.has(d))) {
      out.push({ ecosystem: def.ecosystem, framework: def.framework });
    }
  }
  return out;
}
