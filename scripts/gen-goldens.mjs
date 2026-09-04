#!/usr/bin/env node
/**
 * Generate golden reports for every fixture from the reference TypeScript detector, then validate
 * each against the shared schema. Volatile fields are replaced with stable placeholders so goldens
 * are machine-independent yet still schema-valid.
 *
 *   node scripts/gen-goldens.mjs           # write goldens
 *   node scripts/gen-goldens.mjs --check   # fail if any golden is stale (CI drift guard)
 */
import { readdirSync, writeFileSync, readFileSync, existsSync, statSync } from "node:fs";
import { join, dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { fingerprint } from "../packages/ts/dist/fingerprint.js";
import { validateReport } from "../packages/ts/dist/schema.js";

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(HERE, "..");
const FIXTURES = join(ROOT, "fixtures");
const PLACEHOLDER_TS = "1970-01-01T00:00:00Z";
const check = process.argv.includes("--check");

/** Full golden (TS/Py contract): stable placeholders for root/generatedAt/generatedBy. */
function fullGolden(report) {
  return { ...report, root: "<root>", generatedAt: PLACEHOLDER_TS, generatedBy: "ts" };
}

/** Presence projection: confidence nulled, frameworks/testing emptied, roles by primaries. */
function presenceGolden(report, generatedBy) {
  const ecosystems = report.ecosystems.map((e) => ({
    ...e,
    rawScore: null,
    confidence: null,
    confidenceBucket: null,
  }));
  return {
    ...report,
    generatedBy,
    root: "<root>",
    generatedAt: PLACEHOLDER_TS,
    ecosystems,
    frameworks: [],
    testing: [],
  };
}

const fixtures = readdirSync(FIXTURES).filter((d) => statSync(join(FIXTURES, d)).isDirectory());
let stale = 0;
for (const fx of fixtures.sort()) {
  const dir = join(FIXTURES, fx);
  const report = fingerprint(dir, { generatedBy: "ts", now: PLACEHOLDER_TS });
  const full = fullGolden(report);
  const bash = presenceGolden(report, "bash");
  const powershell = presenceGolden(report, "powershell");

  for (const [name, doc] of [
    ["expected-report.json", full],
    ["expected-report.bash.json", bash],
    ["expected-report.powershell.json", powershell],
  ]) {
    const { valid, errors } = validateReport(doc);
    if (!valid) {
      console.error(`INVALID golden ${fx}/${name}:\n  ${errors.join("\n  ")}`);
      process.exitCode = 1;
      continue;
    }
    const target = join(dir, name);
    const serialized = JSON.stringify(doc, null, 2) + "\n";
    if (check) {
      const current = existsSync(target) ? readFileSync(target, "utf8") : "";
      if (current !== serialized) {
        console.error(`STALE golden: ${fx}/${name}`);
        stale++;
      }
    } else {
      writeFileSync(target, serialized);
      console.log(`wrote ${fx}/${name}`);
    }
  }
}
if (check && stale > 0) {
  console.error(`\n${stale} golden(s) out of date. Run: node scripts/gen-goldens.mjs`);
  process.exitCode = 1;
} else if (check) {
  console.log("all goldens up to date");
}
