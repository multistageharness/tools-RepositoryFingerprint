import { test } from "node:test";
import assert from "node:assert/strict";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { parseManifests } from "../src/parsers.js";
import { walk } from "../src/walker.js";
import { matchFrameworks, matchTesting } from "../src/frameworks.js";
import { loadMatrix } from "../src/matrix.js";

const FIXTURES = resolve(dirname(fileURLToPath(import.meta.url)), "..", "..", "..", "fixtures");

function poolsFor(fx: string) {
  const root = resolve(FIXTURES, fx);
  return parseManifests(root, walk(root).files);
}

test("node package.json deps land in the js pool", () => {
  const p = poolsFor("node-ts");
  assert.ok(p.js.has("react"));
  assert.ok(p.js.has("express"));
  assert.ok(p.js.has("typescript"));
  assert.ok(p.js.has("jest"));
});

test("python poetry deps normalize into the py pool", () => {
  const p = poolsFor("python-poetry");
  assert.ok(p.py.has("django"));
  assert.ok(p.py.has("numpy"));
  assert.ok(p.py.has("pytest"));
});

test("maven pom yields group:artifact and bare artifact tokens", () => {
  const p = poolsFor("java-maven");
  assert.ok(p.java.has("org.springframework.boot:spring-boot-starter"));
  assert.ok(p.java.has("spring-boot-starter"));
  assert.ok(p.java.has("com.fasterxml.jackson.core:jackson-databind"));
});

test("go.mod and Cargo.toml pools", () => {
  const go = poolsFor("go-mod");
  assert.ok(go.go.has("google.golang.org/grpc"));
  assert.ok(go.go.has("k8s.io/client-go"));
  const rust = poolsFor("rust-cargo");
  assert.ok(rust.rust.has("tokio"));
  assert.ok(rust.rust.has("serde"));
});

test("requirements.txt in a nested dir feeds the py pool", () => {
  const p = poolsFor("java-dominant-nested-py");
  assert.ok(p.py.has("pandas"));
  assert.ok(p.py.has("requests"));
});

test("framework & testing matchers resolve from pools", () => {
  const matrix = loadMatrix();
  const p = poolsFor("node-ts");
  const fw = matchFrameworks(matrix, p).map((f) => f.name).sort();
  assert.deepEqual(fw, ["Express", "React", "TypeScript"]);
  const testing = matchTesting(matrix, p).map((t) => t.framework);
  assert.deepEqual(testing, ["Jest"]);
});
