import { test } from "node:test";
import assert from "node:assert/strict";
import { resolve, dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { fingerprint } from "../src/fingerprint.js";
import { parseArgs } from "../src/cli.js";
import { validateReport } from "../src/schema.js";

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..", "..", "..");
const FIXTURES = join(ROOT, "fixtures");

test("deep: multi-repo-npm resolves dominance, sub-repos and monorepo topology", () => {
  const r = fingerprint(join(FIXTURES, "multi-repo-npm"), { generatedBy: "ts", deep: true });
  assert.equal(r.dominantEcosystem, "node");
  assert.equal(r.ecosystems[0]!.role, "primary");
  assert.equal(r.topology.type, "monorepo");
  assert.equal(r.topology.tool, null);
  assert.deepEqual(r.subRepos, [
    {
      path: "repo-a",
      primaryManifests: ["repo-a/package.json"],
      dominantEcosystem: "node",
    },
    {
      path: "repo-b",
      primaryManifests: ["repo-b/package.json"],
      dominantEcosystem: "node",
    },
  ]);
  const { valid, errors } = validateReport(r);
  assert.ok(valid, `deep report must stay schema-valid: ${errors.join("; ")}`);
});

test("non-deep: multi-repo-npm keeps the default contract (no subRepos key)", () => {
  const r = fingerprint(join(FIXTURES, "multi-repo-npm"), { generatedBy: "ts" });
  assert.ok(!("subRepos" in r));
  assert.equal(r.topology.type, "single");
});

test("deep: a root-manifest repo is unchanged apart from an empty subRepos list", () => {
  const deep = fingerprint(join(FIXTURES, "node-ts"), { generatedBy: "ts", deep: true });
  const flat = fingerprint(join(FIXTURES, "node-ts"), { generatedBy: "ts" });
  assert.deepEqual(deep.subRepos, []);
  assert.equal(deep.dominantEcosystem, flat.dominantEcosystem);
  assert.deepEqual(deep.topology, flat.topology);
});

test("deep: root-dominant repo keeps root dominance; nested aux becomes a sub-repo", () => {
  const r = fingerprint(join(FIXTURES, "java-dominant-nested-py"), {
    generatedBy: "ts",
    deep: true,
  });
  assert.equal(r.dominantEcosystem, "java-maven");
  assert.equal(r.topology.type, "single");
  assert.deepEqual(
    r.subRepos!.map((s) => ({ path: s.path, eco: s.dominantEcosystem })),
    [{ path: "tools/script", eco: "python" }],
  );
});

test("deep: workspace-marker topology is not overridden", () => {
  const r = fingerprint(join(FIXTURES, "pnpm-monorepo"), { generatedBy: "ts", deep: true });
  assert.equal(r.topology.type, "monorepo");
  assert.equal(r.topology.tool, "pnpm");
  assert.deepEqual(
    r.subRepos!.map((s) => s.path),
    ["packages/a", "packages/b"],
  );
});

test("cli: --deep and --shadow-scan set the deep flag", () => {
  assert.deepEqual(parseArgs(["--deep", "x"]), { path: "x", format: "json", deep: true });
  assert.deepEqual(parseArgs(["--shadow-scan", "x"]), { path: "x", format: "json", deep: true });
  assert.deepEqual(parseArgs(["x"]), { path: "x", format: "json", deep: false });
});
