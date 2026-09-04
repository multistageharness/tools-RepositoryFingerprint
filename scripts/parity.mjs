#!/usr/bin/env node
/**
 * Polyglot parity harness. Runs the bash, TypeScript and Python CLIs over every fixture, normalizes
 * their JSON output, applies per-impl tolerance rules, and renders a pass/fail matrix. Exits 1 if
 * any impl diverges from the reference (TypeScript) beyond its tolerance.
 *
 *   node scripts/parity.mjs [--json]
 *
 * CLI commands can be overridden via env:
 *   RF_BASH="bash packages/bash/repo-fingerprint.sh"
 *   RF_TS="node packages/ts/dist/cli.js"
 *   RF_PY="/path/to/repo-fingerprint"   (or ".venv/bin/repo-fingerprint")
 *   RF_PWSH="pwsh -NoProfile -File packages/powershell/repo-fingerprint.ps1"
 *
 * The powershell column is included only when `pwsh` is available (or RF_PWSH is set); on hosts
 * without PowerShell it is skipped with a printed note so local parity still runs.
 */
import { execFileSync } from "node:child_process";
import { readFileSync, readdirSync, statSync, existsSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { canonicalize } from "../packages/ts/dist/canonical.js";

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(HERE, "..");
const FIXTURES = join(ROOT, "fixtures");
const asJson = process.argv.includes("--json");

const tolConfig = JSON.parse(readFileSync(join(HERE, "parity-tolerances.json"), "utf8"));
const REFERENCE = tolConfig.reference;

function words(s) {
  return s.trim().split(/\s+/);
}
function pyCommand() {
  if (process.env.RF_PY) return words(process.env.RF_PY);
  const venv = join(ROOT, ".venv", "bin", "repo-fingerprint");
  return existsSync(venv) ? [venv] : ["repo-fingerprint"];
}
function pwshAvailable() {
  if (process.env.RF_PWSH) return true;
  const probe = process.platform === "win32" ? "where" : "which";
  try {
    execFileSync(probe, ["pwsh"], { stdio: "ignore" });
    return true;
  } catch {
    return false;
  }
}
const COMMANDS = {
  bash: process.env.RF_BASH
    ? words(process.env.RF_BASH)
    : ["bash", join(ROOT, "packages/bash/repo-fingerprint.sh")],
  powershell: process.env.RF_PWSH
    ? words(process.env.RF_PWSH)
    : ["pwsh", "-NoProfile", "-File", join(ROOT, "packages/powershell/repo-fingerprint.ps1")],
  ts: process.env.RF_TS
    ? words(process.env.RF_TS)
    : ["node", join(ROOT, "packages/ts/dist/cli.js")],
  py: pyCommand(),
};

function runImpl(impl, fixtureDir, extraArgs = []) {
  const [cmd, ...base] = COMMANDS[impl];
  const args = [...base, fixtureDir, "--format", "json", ...extraArgs];
  let stdout;
  try {
    stdout = execFileSync(cmd, args, { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] });
  } catch (err) {
    // exit code 1 (no ecosystem) still prints valid JSON on stdout.
    if (err.stdout) stdout = err.stdout;
    else throw new Error(`${impl} crashed on ${fixtureDir}: ${err.message}`);
  }
  try {
    return JSON.parse(stdout);
  } catch {
    throw new Error(`${impl} produced non-JSON output on ${fixtureDir}`);
  }
}

/** Remove tolerance-ignored fields from a canonicalized report. */
function applyIgnores(report, ignore) {
  const r = structuredClone(report);
  for (const path of ignore) {
    if (path.startsWith("ecosystems[].")) {
      const field = path.slice("ecosystems[].".length);
      for (const eco of r.ecosystems ?? []) delete eco[field];
    } else {
      delete r[path];
    }
  }
  return r;
}

/** Compare an impl against the reference, honoring the union of both tolerance ignore-lists. */
function compare(implReport, refReport, implName) {
  const ignore = [
    ...(tolConfig.tolerances[implName]?.ignore ?? []),
    ...(tolConfig.tolerances[REFERENCE]?.ignore ?? []),
  ];
  const a = applyIgnores(canonicalize(implReport), ignore);
  const b = applyIgnores(canonicalize(refReport), ignore);
  return JSON.stringify(a) === JSON.stringify(b);
}

const fixtures = readdirSync(FIXTURES).filter((d) => statSync(join(FIXTURES, d)).isDirectory());
const hasPwsh = pwshAvailable();
if (!hasPwsh) console.error("note: pwsh not found — skipping the powershell column.\n");
const impls = ["bash", ...(hasPwsh ? ["powershell"] : []), "ts", "py"];
const results = {};
let failures = 0;

// Each fixture is compared twice: on a default run and on a deep (--deep) run, so the
// deep-mode additions (subRepos, dominance fallback, topology inference) stay in parity too.
const MODES = [
  { label: "", extraArgs: [] },
  { label: " (--deep)", extraArgs: ["--deep"] },
];
for (const fx of fixtures.sort()) {
  const dir = join(FIXTURES, fx);
  for (const mode of MODES) {
    const row = `${fx}${mode.label}`;
    const reports = {};
    for (const impl of impls) reports[impl] = runImpl(impl, dir, mode.extraArgs);
    results[row] = {};
    for (const impl of impls) {
      const ok = compare(reports[impl], reports[REFERENCE], impl);
      results[row][impl] = ok;
      if (!ok) failures++;
    }
  }
}

if (asJson) {
  console.log(JSON.stringify({ reference: REFERENCE, results, failures }, null, 2));
} else {
  const pad = (s, n) => String(s).padEnd(n);
  const col = 34;
  const iw = Math.max(8, ...impls.map((i) => i.length + 2));
  console.log(`Parity matrix (reference: ${REFERENCE}, tolerances applied)\n`);
  console.log(pad("fixture", col) + impls.map((i) => pad(i, iw)).join(""));
  console.log("-".repeat(col + impls.length * iw));
  for (const fx of Object.keys(results)) {
    const row = impls.map((i) => pad(results[fx][i] ? "PASS" : "FAIL", iw)).join("");
    console.log(pad(fx, col) + row);
  }
  console.log(
    `\n${failures === 0 ? "ALL PASS" : failures + " FAILURE(S)"} across ${fixtures.length} fixtures (default + --deep runs).`,
  );
}

process.exit(failures === 0 ? 0 : 1);
