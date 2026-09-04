import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync, readdirSync, statSync } from "node:fs";
import { resolve, dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { validateReport } from "../src/schema.js";

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..", "..", "..");

test("sample-report.json validates", () => {
  const doc = JSON.parse(readFileSync(join(ROOT, "schema/examples/sample-report.json"), "utf8"));
  const { valid, errors } = validateReport(doc);
  assert.ok(valid, `expected valid, got: ${errors.join("; ")}`);
});

test("invalid-report.json fails validation", () => {
  const doc = JSON.parse(readFileSync(join(ROOT, "schema/examples/invalid-report.json"), "utf8"));
  const { valid, errors } = validateReport(doc);
  assert.equal(valid, false);
  assert.ok(errors.length >= 1);
});

test("every fixture golden validates against the schema", () => {
  const fixturesDir = join(ROOT, "fixtures");
  const fixtures = readdirSync(fixturesDir).filter((d) =>
    statSync(join(fixturesDir, d)).isDirectory(),
  );
  for (const fx of fixtures) {
    for (const name of ["expected-report.json", "expected-report.bash.json"]) {
      const doc = JSON.parse(readFileSync(join(fixturesDir, fx, name), "utf8"));
      const { valid, errors } = validateReport(doc);
      assert.ok(valid, `${fx}/${name} invalid: ${errors.join("; ")}`);
    }
  }
});
