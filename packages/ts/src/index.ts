export * from "./types.js";
export { fingerprint } from "./fingerprint.js";
export type { FingerprintOptions } from "./fingerprint.js";
export { loadMatrix, matrixPath, schemaPath } from "./matrix.js";
export type { SignalMatrix } from "./matrix.js";
export {
  decayedWeight,
  round4,
  rawScoreOf,
  confidenceOf,
  bucketOf,
  proximateScore,
} from "./confidence.js";
export { validateReport, validateReportFile } from "./schema.js";
export { canonicalize } from "./canonical.js";
