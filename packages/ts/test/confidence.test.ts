import { test } from "node:test";
import assert from "node:assert/strict";
import {
  bucketOf,
  confidenceOf,
  decayedWeight,
  proximateScore,
  rawScoreOf,
  round4,
} from "../src/confidence.js";
import type { RawSignal } from "../src/types.js";

function sig(kind: RawSignal["kind"], weight: number, depth: number): RawSignal {
  return { ecosystemId: "x", path: "p", kind, weight, depth };
}

test("depth decay halves weight per level below root", () => {
  assert.equal(decayedWeight(1.0, 1), 1.0);
  assert.equal(decayedWeight(1.0, 2), 0.5);
  assert.equal(decayedWeight(1.0, 3), 0.25);
  assert.equal(decayedWeight(0.2, 1), 0.2);
});

test("round4 is half-up to 4 decimals", () => {
  assert.equal(round4(0.85043139), 0.8504);
  assert.equal(round4(0.77686984), 0.7769);
  assert.equal(round4(0.22119922), 0.2212);
});

test("worked example A — node+ts single instance (rawScore 2.4)", () => {
  const signals = [
    sig("primary-manifest", 1.0, 1),
    sig("config", 0.5, 1),
    sig("lockfile", 0.4, 1),
    sig("config", 0.5, 1),
  ];
  const raw = rawScoreOf(signals);
  assert.equal(raw, 2.4);
  assert.equal(confidenceOf(raw), 0.9895);
  assert.equal(bucketOf(confidenceOf(raw)), "certain");
});

test("worked example B — java dominant, python auxiliary", () => {
  const java = [
    sig("primary-manifest", 1.0, 1),
    sig("build-wrapper", 0.3, 1),
    sig("build-wrapper", 0.3, 1),
    sig("source-layout", 0.2, 1),
    sig("source-layout", 0.2, 1),
  ];
  const py = [sig("primary-manifest", 1.0, 3)];

  assert.equal(rawScoreOf(java), 2.0);
  assert.equal(confidenceOf(2.0), 0.9776);
  assert.equal(bucketOf(0.9776), "certain");

  assert.equal(rawScoreOf(py), 0.25);
  assert.equal(confidenceOf(0.25), 0.3781);
  assert.equal(bucketOf(0.3781), "low");

  // dominance: only depth<=1 signals count
  assert.equal(proximateScore(java), 2.0);
  assert.equal(proximateScore(py), 0);
});

test("bucket boundaries", () => {
  assert.equal(bucketOf(0.9), "certain");
  assert.equal(bucketOf(0.8999), "high");
  assert.equal(bucketOf(0.7), "high");
  assert.equal(bucketOf(0.6999), "medium");
  assert.equal(bucketOf(0.4), "medium");
  assert.equal(bucketOf(0.3999), "low");
  assert.equal(bucketOf(0.0001), "low");
  assert.equal(bucketOf(0), "none");
});
