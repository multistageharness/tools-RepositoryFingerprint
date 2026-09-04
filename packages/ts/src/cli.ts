#!/usr/bin/env node
/** CLI front-end for the TypeScript repository-fingerprint detector. */
import { existsSync, statSync } from "node:fs";
import { fingerprint } from "./fingerprint.js";
import type { DetectionReport } from "./types.js";

const USAGE = `repo-fingerprint (ts) — detect a repository's ecosystems, topology & confidence.

Usage:
  repo-fingerprint [path] [--format json|text] [--deep]

Arguments:
  path                 Repository root to scan (default: current directory)

Options:
  --format <fmt>       Output format: json (default) or text
  --deep               Deep (shadow) scan: monorepo-aware dominance fallback and
                       nested sub-repo enumeration (alias: --shadow-scan)
  -h, --help           Show this help

Exit codes:
  0  at least one ecosystem detected
  1  no ecosystem detected
  2  usage error
`;

interface Args {
  path: string;
  format: "json" | "text";
  deep: boolean;
}

export function parseArgs(argv: string[]): Args | { help: true } {
  let path = ".";
  let format: "json" | "text" = "json";
  let deep = false;
  let sawPath = false;
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i]!;
    if (a === "-h" || a === "--help") return { help: true };
    if (a === "--deep" || a === "--shadow-scan") {
      deep = true;
    } else if (a === "--format") {
      const v = argv[++i];
      if (v !== "json" && v !== "text") throw new Error(`invalid --format: ${String(v)}`);
      format = v;
    } else if (a.startsWith("--format=")) {
      const v = a.slice("--format=".length);
      if (v !== "json" && v !== "text") throw new Error(`invalid --format: ${v}`);
      format = v;
    } else if (a.startsWith("-")) {
      throw new Error(`unknown flag: ${a}`);
    } else {
      if (sawPath) throw new Error(`unexpected extra argument: ${a}`);
      path = a;
      sawPath = true;
    }
  }
  return { path, format, deep };
}

function renderText(r: DetectionReport): string {
  const lines: string[] = [];
  lines.push(`Repository: ${r.root}`);
  lines.push(`Detected by: ${r.generatedBy}`);
  lines.push(`Dominant ecosystem: ${r.dominantEcosystem ?? "(none)"}`);
  lines.push("");
  lines.push("Ecosystems:");
  if (r.ecosystems.length === 0) lines.push("  (none)");
  for (const e of r.ecosystems) {
    const conf =
      e.confidence != null ? `${e.confidence} (${e.confidenceBucket})` : "n/a (presence-only)";
    lines.push(`  - ${e.name} [${e.role}] confidence=${conf} signals=${e.signals.length}`);
  }
  lines.push("");
  lines.push(`Package managers: ${r.packageManagers.join(", ") || "(none)"}`);
  lines.push(`Build tools: ${r.buildTools.join(", ") || "(none)"}`);
  lines.push(
    `Topology: ${r.topology.type}${r.topology.tool ? ` (${r.topology.tool})` : ""}`,
  );
  if (r.subRepos && r.subRepos.length > 0) {
    lines.push("Sub-repos:");
    for (const s of r.subRepos) {
      lines.push(
        `  - ${s.path} (${s.dominantEcosystem ?? "unknown"}, ${s.primaryManifests.length} manifest(s))`,
      );
    }
  }
  if (r.frameworks.length) {
    lines.push("Frameworks:");
    for (const f of r.frameworks) lines.push(`  - ${f.name} (${f.ecosystem})`);
  }
  if (r.testing.length) {
    lines.push("Testing:");
    for (const t of r.testing) lines.push(`  - ${t.framework} (${t.ecosystem})`);
  }
  const infra = r.infrastructure;
  if (infra.ci.length || infra.containers.length || infra.orchestration.length) {
    lines.push("Infrastructure:");
    if (infra.ci.length) lines.push(`  ci: ${infra.ci.join(", ")}`);
    if (infra.containers.length) lines.push(`  containers: ${infra.containers.join(", ")}`);
    if (infra.orchestration.length)
      lines.push(`  orchestration: ${infra.orchestration.join(", ")}`);
  }
  return lines.join("\n");
}

export function main(argv: string[]): number {
  let args: Args | { help: true };
  try {
    args = parseArgs(argv);
  } catch (err) {
    process.stderr.write(`error: ${(err as Error).message}\n\n${USAGE}`);
    return 2;
  }
  if ("help" in args) {
    process.stdout.write(USAGE);
    return 0;
  }
  if (!existsSync(args.path) || !statSync(args.path).isDirectory()) {
    process.stderr.write(`error: path not found or not a directory: ${args.path}\n`);
    return 2;
  }

  const report = fingerprint(args.path, { generatedBy: "ts", deep: args.deep });
  if (args.format === "text") process.stdout.write(renderText(report) + "\n");
  else process.stdout.write(JSON.stringify(report, null, 2) + "\n");

  return report.ecosystems.length > 0 ? 0 : 1;
}

// Only run when invoked directly (not when imported by tests).
if (import.meta.url === `file://${process.argv[1]}`) {
  process.exit(main(process.argv.slice(2)));
}
