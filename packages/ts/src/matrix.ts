/** Loads and types `schema/signal-matrix.json` (the shared detection catalog). */
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";
import type { SignalKind } from "./types.js";

export interface EcosystemSignalDef {
  glob: string;
  kind: SignalKind;
  weight: number;
}
export interface EcosystemDef {
  id: string;
  name: string;
  signals: EcosystemSignalDef[];
}
export interface PackageManagerDef {
  ecosystem: string;
  tool: string;
  glob: string;
}
export interface BuildToolDef {
  tool: string;
  glob: string;
}
export interface FrameworkDef {
  ecosystem: string;
  name: string;
  deps: string[];
}
export interface TestingDef {
  ecosystem: string;
  framework: string;
  deps: string[];
}
export interface TopologyDef {
  tool: string;
  type: "single" | "monorepo" | "workspace";
  kind: SignalKind;
  glob?: string;
  marker?: { file: string; contains?: string; jsonKey?: string };
}
export interface InfraDef {
  tool: string;
  glob: string;
  category: "ci" | "containers" | "orchestration";
  kind: SignalKind;
}

export interface SignalMatrix {
  matrixVersion: string;
  ecosystems: EcosystemDef[];
  packageManagers: PackageManagerDef[];
  buildTools: BuildToolDef[];
  frameworks: FrameworkDef[];
  testing: TestingDef[];
  topology: TopologyDef[];
  infrastructure: InfraDef[];
}

const HERE = dirname(fileURLToPath(import.meta.url));

/** Resolve the shared `schema/` dir: env override wins, else walk up from this module. */
export function matrixPath(): string {
  if (process.env.RF_MATRIX) return resolve(process.env.RF_MATRIX);
  // dist/ or src/ -> packages/ts -> packages -> repo root -> schema
  return resolve(HERE, "..", "..", "..", "schema", "signal-matrix.json");
}

export function schemaPath(): string {
  if (process.env.RF_SCHEMA) return resolve(process.env.RF_SCHEMA);
  return resolve(HERE, "..", "..", "..", "schema", "detection-report.schema.json");
}

let cached: SignalMatrix | null = null;
export function loadMatrix(path: string = matrixPath()): SignalMatrix {
  if (cached && path === matrixPath()) return cached;
  const parsed = JSON.parse(readFileSync(path, "utf8")) as SignalMatrix;
  if (path === matrixPath()) cached = parsed;
  return parsed;
}
