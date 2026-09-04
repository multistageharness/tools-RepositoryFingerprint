/**
 * Diagnostic Confidence engine — the deterministic implementation of `schema/confidence-model.md`.
 * Must produce byte-identical numbers to the Python twin.
 */
import type { ConfidenceBucket, RawSignal } from "./types.js";

/** Depth decay: half the weight per level below the root. */
export function decayedWeight(weight: number, depth: number): number {
  return weight * Math.pow(0.5, Math.max(0, depth - 1));
}

/** Round half-up (away from zero) to 4 decimals. */
export function round4(x: number): number {
  return Math.round(x * 1e4) / 1e4;
}

/** rawScore = sum of depth-decayed weights. */
export function rawScoreOf(signals: RawSignal[]): number {
  return round4(signals.reduce((acc, s) => acc + decayedWeight(s.weight, s.depth), 0));
}

/** Steepness constant k — calibrated value defined in `schema/confidence-model.md` §5. */
export const STEEPNESS = 1.9;

/** confidence = round4(1 - exp(-k·rawScore)). */
export function confidenceOf(rawScore: number): number {
  return round4(1 - Math.exp(-STEEPNESS * rawScore));
}

export function bucketOf(confidence: number): ConfidenceBucket {
  if (confidence >= 0.9) return "certain";
  if (confidence >= 0.7) return "high";
  if (confidence >= 0.4) return "medium";
  if (confidence > 0) return "low";
  return "none";
}

/** Root-proximate score: only signals at depth <= 1 count toward dominance. */
export function proximateScore(signals: RawSignal[]): number {
  return round4(
    signals
      .filter((s) => s.depth <= 1)
      .reduce((acc, s) => acc + decayedWeight(s.weight, s.depth), 0),
  );
}

export function primaryManifestCount(signals: RawSignal[], depthLimited = true): number {
  return signals.filter(
    (s) => s.kind === "primary-manifest" && (!depthLimited || s.depth <= 1),
  ).length;
}
