/**
 * CLI integration suite: spawns `src/cli.ts` as a real child process against every fixture,
 * asserting golden JSON equality, schema validity of live output, text rendering, deep-mode
 * behavior, and all documented exit codes (0 / 1 / 2 / --help).
 *
 * This deliberately overlaps golden.test.ts: that suite proves the library layer in-process;
 * this one proves the process boundary (argument parsing, stdout serialization, exit codes).
 * Neither replaces the other.
 */
import { test } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { appendFileSync, mkdtempSync, readFileSync, readdirSync, rmSync, statSync } from "node:fs";
import { tmpdir } from "node:os";
import { resolve, dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { canonicalize } from "../src/canonical.js";
import { validateReport } from "../src/schema.js";

const PKG = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const ROOT = resolve(PKG, "..", "..");
const FIXTURES = join(ROOT, "fixtures");
const CLI = join(PKG, "src", "cli.ts");

interface CliResult {
  status: number | null;
  stdout: string;
  stderr: string;
}

// cwd is pinned to the package dir so `--import tsx` resolves from its node_modules,
// independent of where `npm test` was launched from.
function runCli(args: string[]): CliResult {
  const r = spawnSync(process.execPath, ["--import", "tsx", CLI, ...args], {
    cwd: PKG,
    encoding: "utf8",
  });
  assert.equal(r.error, undefined, `failed to spawn CLI: ${r.error?.message}`);
  return { status: r.status, stdout: r.stdout, stderr: r.stderr };
}

// Opt-in per-fixture expected/actual summary (JSONL), for tracking false positives.
// Set by `make integration-report`; plain `npm test` writes nothing (NF3).
const SUMMARY_FILE = process.env.INTEGRATION_SUMMARY_FILE ?? "";

interface EcoSummary {
  name: string;
  role: string;
  confidence: number | null;
  signals: string[];
}

interface ReportSummary {
  dominantEcosystem: string | null;
  ecosystems: EcoSummary[];
}

function summarize(report: any): ReportSummary {
  return {
    dominantEcosystem: report.dominantEcosystem ?? null,
    ecosystems: (report.ecosystems ?? []).map((e: any) => ({
      name: e.name,
      role: e.role,
      confidence: e.confidence ?? null,
      signals: (e.signals ?? []).map((s: any) => `${s.path} (${s.kind})`),
    })),
  };
}

function recordSummary(entry: Record<string, unknown>): void {
  if (SUMMARY_FILE) appendFileSync(SUMMARY_FILE, JSON.stringify(entry) + "\n");
}

let fixtures: string[] = [];
try {
  fixtures = readdirSync(FIXTURES).filter((d) => statSync(join(FIXTURES, d)).isDirectory());
} catch {
  // handled by the guard test below
}

test("fixture corpus exists and is non-empty", () => {
  assert.ok(
    fixtures.length > 0,
    `no fixture directories found under ${FIXTURES} — a 0-fixture pass would be a silent defect`,
  );
});

for (const fx of fixtures) {
  const fixtureDir = join(FIXTURES, fx);

  test(`cli json: ${fx} exits 0, matches golden, validates against schema`, (t) => {
    const golden = JSON.parse(readFileSync(join(fixtureDir, "expected-report.json"), "utf8"));
    const expected = summarize(golden);
    t.diagnostic(`fixture=${fx} expected dominant=${expected.dominantEcosystem ?? "(none)"}`);
    for (const e of expected.ecosystems) {
      t.diagnostic(
        `fixture=${fx} expect ${e.name}[${e.role}] confidence=${e.confidence ?? "n/a"} ` +
          `signals: ${e.signals.join(", ") || "(none)"}`,
      );
    }

    const r = runCli([fixtureDir]);
    assert.equal(r.status, 0, `expected exit 0, got ${r.status}; stderr: ${r.stderr}`);
    const report = JSON.parse(r.stdout);

    // Record expected vs actual before asserting, so a mismatch still lands in the summary.
    const goldenMatch =
      JSON.stringify(canonicalize(report)) === JSON.stringify(canonicalize(golden));
    recordSummary({
      fixture: fx,
      exitCode: r.status,
      goldenMatch,
      expected,
      actual: summarize(report),
    });

    assert.deepEqual(canonicalize(report), canonicalize(golden));
    const { valid, errors } = validateReport(report);
    assert.ok(valid, `live CLI output is schema-invalid: ${errors.join("; ")}`);
  });

  test(`cli text: ${fx} renders with the dominant ecosystem`, () => {
    const golden = JSON.parse(readFileSync(join(fixtureDir, "expected-report.json"), "utf8"));
    const r = runCli([fixtureDir, "--format", "text"]);
    assert.equal(r.status, 0, `expected exit 0, got ${r.status}; stderr: ${r.stderr}`);
    assert.ok(r.stdout.length > 0, "text output must be non-empty");
    const expected = `Dominant ecosystem: ${golden.dominantEcosystem ?? "(none)"}`;
    assert.ok(r.stdout.includes(expected), `text output missing "${expected}"`);
  });
}

test("cli deep: --deep on multi-repo-npm reports monorepo topology and sub-repos", () => {
  const r = runCli([join(FIXTURES, "multi-repo-npm"), "--deep"]);
  assert.equal(r.status, 0, `stderr: ${r.stderr}`);
  const report = JSON.parse(r.stdout);
  assert.equal(report.topology.type, "monorepo");
  assert.deepEqual(
    report.subRepos.map((s: { path: string }) => s.path),
    ["repo-a", "repo-b"],
  );
});

test("cli deep: --shadow-scan is an exact alias for --deep", () => {
  const fixtureDir = join(FIXTURES, "multi-repo-npm");
  const deep = runCli([fixtureDir, "--deep"]);
  const shadow = runCli([fixtureDir, "--shadow-scan"]);
  assert.equal(deep.status, 0);
  assert.equal(shadow.status, 0);
  assert.deepEqual(
    canonicalize(JSON.parse(shadow.stdout)),
    canonicalize(JSON.parse(deep.stdout)),
  );
});

test("cli deep: without the flag, multi-repo-npm keeps its golden single topology", () => {
  const r = runCli([join(FIXTURES, "multi-repo-npm")]);
  assert.equal(r.status, 0, `stderr: ${r.stderr}`);
  const report = JSON.parse(r.stdout);
  assert.equal(report.topology.type, "single");
  assert.ok(!("subRepos" in report));
});

test("cli exit 1: an empty directory detects no ecosystem", () => {
  const scratch = mkdtempSync(join(tmpdir(), "repo-fp-cli-"));
  try {
    const r = runCli([scratch]);
    assert.equal(r.status, 1, `expected exit 1, got ${r.status}; stderr: ${r.stderr}`);
    const report = JSON.parse(r.stdout);
    assert.equal(report.ecosystems.length, 0);
  } finally {
    rmSync(scratch, { recursive: true, force: true });
  }
});

test("cli exit 2: unknown flag fails with usage on stderr", () => {
  const r = runCli(["--no-such-flag"]);
  assert.equal(r.status, 2);
  assert.ok(r.stderr.includes("unknown flag: --no-such-flag"));
  assert.ok(r.stderr.includes("Usage:"));
});

test("cli exit 2: invalid --format value fails with usage on stderr", () => {
  const r = runCli(["--format", "yaml"]);
  assert.equal(r.status, 2);
  assert.ok(r.stderr.includes("invalid --format: yaml"));
  assert.ok(r.stderr.includes("Usage:"));
});

test("cli exit 2: nonexistent path fails with an error on stderr", () => {
  const missing = join(tmpdir(), "repo-fp-cli-definitely-missing");
  const r = runCli([missing]);
  assert.equal(r.status, 2);
  assert.ok(r.stderr.includes("path not found or not a directory"));
});

test("cli --help: exits 0 with usage on stdout", () => {
  const r = runCli(["--help"]);
  assert.equal(r.status, 0);
  assert.ok(r.stdout.includes("Usage:"));
  assert.ok(r.stdout.includes("Exit codes:"));
  assert.equal(r.stderr, "");
});
