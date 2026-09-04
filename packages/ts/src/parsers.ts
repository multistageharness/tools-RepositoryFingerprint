/**
 * Manifest parsers. Each parser extracts the set of dependency identifiers used for framework and
 * testing fingerprinting. Identifiers are normalized per-language so the Python twin can match them.
 */
import { readFileSync } from "node:fs";
import { join } from "node:path";
import TOML from "@iarna/toml";
import { XMLParser } from "fast-xml-parser";
import { basename } from "./signals.js";

export interface DependencyPools {
  /** JavaScript/TypeScript package names (from every package.json). */
  js: Set<string>;
  /** Python distribution names, PEP 503-ish normalized (lowercase). */
  py: Set<string>;
  /** JVM coordinates: both `group:artifact` and bare `artifact`. */
  java: Set<string>;
  /** Go module paths. */
  go: Set<string>;
  /** Rust crate names. */
  rust: Set<string>;
}

function read(root: string, rel: string): string {
  return readFileSync(join(root, rel), "utf8");
}

function normalizePy(name: string): string {
  return name
    .trim()
    .toLowerCase()
    .replace(/[-_.]+/g, "-");
}

/** Strip a PEP 508 requirement down to its distribution name. */
function pep508Name(spec: string): string | null {
  const s = spec.trim();
  if (!s || s.startsWith("#")) return null;
  const m = s.match(/^([A-Za-z0-9._-]+)/);
  return m ? normalizePy(m[1]!) : null;
}

function addPackageJson(root: string, rel: string, pools: DependencyPools): void {
  try {
    const pkg = JSON.parse(read(root, rel)) as Record<string, unknown>;
    for (const field of [
      "dependencies",
      "devDependencies",
      "peerDependencies",
      "optionalDependencies",
    ]) {
      const deps = pkg[field];
      if (deps && typeof deps === "object") {
        for (const name of Object.keys(deps as object)) pools.js.add(name);
      }
    }
  } catch {
    /* ignore malformed manifest */
  }
}

function addPyproject(root: string, rel: string, pools: DependencyPools): void {
  try {
    const doc = TOML.parse(read(root, rel)) as any;
    const projDeps = doc?.project?.dependencies;
    if (Array.isArray(projDeps)) {
      for (const spec of projDeps) {
        const n = pep508Name(String(spec));
        if (n) pools.py.add(n);
      }
    }
    const optional = doc?.project?.["optional-dependencies"];
    if (optional && typeof optional === "object") {
      for (const arr of Object.values(optional)) {
        if (Array.isArray(arr))
          for (const spec of arr) {
            const n = pep508Name(String(spec));
            if (n) pools.py.add(n);
          }
      }
    }
    const poetry = doc?.tool?.poetry;
    if (poetry?.dependencies && typeof poetry.dependencies === "object") {
      for (const name of Object.keys(poetry.dependencies)) {
        if (name.toLowerCase() !== "python") pools.py.add(normalizePy(name));
      }
    }
    if (poetry?.group && typeof poetry.group === "object") {
      for (const g of Object.values<any>(poetry.group)) {
        if (g?.dependencies && typeof g.dependencies === "object") {
          for (const name of Object.keys(g.dependencies)) {
            if (name.toLowerCase() !== "python") pools.py.add(normalizePy(name));
          }
        }
      }
    }
  } catch {
    /* ignore */
  }
}

function addRequirements(root: string, rel: string, pools: DependencyPools): void {
  try {
    for (const line of read(root, rel).split(/\r?\n/)) {
      const n = pep508Name(line);
      if (n) pools.py.add(n);
    }
  } catch {
    /* ignore */
  }
}

function addSetupPy(root: string, rel: string, pools: DependencyPools): void {
  try {
    const src = read(root, rel);
    const m = src.match(/install_requires\s*=\s*\[([^\]]*)\]/s);
    if (m) {
      for (const q of m[1]!.match(/["']([^"']+)["']/g) ?? []) {
        const n = pep508Name(q.replace(/["']/g, ""));
        if (n) pools.py.add(n);
      }
    }
  } catch {
    /* ignore */
  }
}

function addPom(root: string, rel: string, pools: DependencyPools): void {
  try {
    const parser = new XMLParser({ ignoreAttributes: true, isArray: () => false });
    const doc = parser.parse(read(root, rel)) as any;
    let deps = doc?.project?.dependencies?.dependency;
    if (!deps) return;
    if (!Array.isArray(deps)) deps = [deps];
    for (const d of deps) {
      const group = d?.groupId != null ? String(d.groupId).trim() : "";
      const artifact = d?.artifactId != null ? String(d.artifactId).trim() : "";
      if (group && artifact) pools.java.add(`${group}:${artifact}`);
      if (artifact) pools.java.add(artifact);
    }
  } catch {
    /* ignore */
  }
}

function addGradle(root: string, rel: string, pools: DependencyPools): void {
  try {
    const src = read(root, rel);
    for (const m of src.matchAll(/["']([\w.-]+):([\w.-]+):[\w.$-]+["']/g)) {
      pools.java.add(`${m[1]}:${m[2]}`);
      pools.java.add(m[2]!);
    }
  } catch {
    /* ignore */
  }
}

function addGoMod(root: string, rel: string, pools: DependencyPools): void {
  try {
    const src = read(root, rel);
    // require ( ... ) blocks and single-line requires
    for (const m of src.matchAll(/^\s*(?:require\s+)?([a-zA-Z0-9._~-]+(?:\/[a-zA-Z0-9._~-]+)+)\s+v/gm)) {
      pools.go.add(m[1]!);
    }
  } catch {
    /* ignore */
  }
}

function addCargo(root: string, rel: string, pools: DependencyPools): void {
  try {
    const doc = TOML.parse(read(root, rel)) as any;
    for (const section of ["dependencies", "dev-dependencies", "build-dependencies"]) {
      const tbl = doc?.[section];
      if (tbl && typeof tbl === "object") for (const name of Object.keys(tbl)) pools.rust.add(name);
    }
  } catch {
    /* ignore */
  }
}

/** Parse every recognized manifest under `root`, returning per-language dependency pools. */
export function parseManifests(root: string, files: string[]): DependencyPools {
  const pools: DependencyPools = {
    js: new Set(),
    py: new Set(),
    java: new Set(),
    go: new Set(),
    rust: new Set(),
  };
  for (const rel of files) {
    const base = basename(rel);
    if (base === "package.json") addPackageJson(root, rel, pools);
    else if (base === "pyproject.toml") addPyproject(root, rel, pools);
    else if (base === "requirements.txt") addRequirements(root, rel, pools);
    else if (base === "setup.py") addSetupPy(root, rel, pools);
    else if (base === "pom.xml") addPom(root, rel, pools);
    else if (base === "build.gradle" || base === "build.gradle.kts") addGradle(root, rel, pools);
    else if (base === "go.mod") addGoMod(root, rel, pools);
    else if (base === "Cargo.toml") addCargo(root, rel, pools);
  }
  return pools;
}
