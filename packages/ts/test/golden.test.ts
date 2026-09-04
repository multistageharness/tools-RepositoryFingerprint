import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync, readdirSync, statSync } from "node:fs";
import { resolve, dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { fingerprint } from "../src/fingerprint.js";
import { canonicalize } from "../src/canonical.js";

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..", "..", "..");
const FIXTURES = join(ROOT, "fixtures");

const fixtures = readdirSync(FIXTURES).filter((d) => statSync(join(FIXTURES, d)).isDirectory());

for (const fx of fixtures) {
  test(`golden: ${fx} reproduces expected-report.json`, () => {
    const golden = JSON.parse(readFileSync(join(FIXTURES, fx, "expected-report.json"), "utf8"));
    const actual = fingerprint(join(FIXTURES, fx), { generatedBy: "ts" });
    assert.deepEqual(canonicalize(actual), canonicalize(golden));
  });
}
