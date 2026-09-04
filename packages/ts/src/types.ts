/**
 * TypeScript mirror of `schema/detection-report.schema.json`. Kept in lock-step with the schema
 * by the smoke test in `test/schema.test.ts`.
 */

export type GeneratedBy = "bash" | "ts" | "py";

export type SignalKind =
  | "primary-manifest"
  | "lockfile"
  | "build-wrapper"
  | "config"
  | "source-layout"
  | "workspace-marker"
  | "infra-marker";

export type ConfidenceBucket = "none" | "low" | "medium" | "high" | "certain" | null;

export type EcosystemRole = "primary" | "auxiliary";

export type TopologyType = "single" | "monorepo" | "workspace";

export interface Signal {
  path: string;
  kind: SignalKind;
  weight: number;
}

export interface EcosystemResult {
  id: string;
  name: string;
  signals: Signal[];
  rawScore: number | null;
  confidence: number | null;
  confidenceBucket: ConfidenceBucket;
  role: EcosystemRole;
}

export interface Topology {
  type: TopologyType;
  tool: string | null;
  signals: string[];
}

export interface FrameworkResult {
  ecosystem: string;
  name: string;
  evidence: string[];
}

export interface TestingResult {
  ecosystem: string;
  framework: string;
}

export interface Infrastructure {
  ci: string[];
  containers: string[];
  orchestration: string[];
}

/** Deep-scan (`--deep`) only: a top-most nested directory holding its own primary manifest. */
export interface SubRepo {
  path: string;
  primaryManifests: string[];
  dominantEcosystem: string | null;
}

export interface DetectionReport {
  schemaVersion: "1.0";
  root: string;
  generatedBy: GeneratedBy;
  generatedAt: string;
  ecosystems: EcosystemResult[];
  packageManagers: string[];
  buildTools: string[];
  topology: Topology;
  frameworks: FrameworkResult[];
  testing: TestingResult[];
  infrastructure: Infrastructure;
  dominantEcosystem: string | null;
  /** Present only on deep (`--deep` / `--shadow-scan`) runs. */
  subRepos?: SubRepo[];
}

/** A signal discovered on disk, with the depth needed for confidence decay. */
export interface RawSignal {
  ecosystemId: string;
  path: string;
  kind: SignalKind;
  weight: number;
  depth: number;
}
