"""Manifest parsers producing per-language dependency pools for fingerprinting.

Identifier normalization matches the TypeScript twin so the two agree on framework detection.
"""
from __future__ import annotations

import json
import re
import tomllib
import xml.etree.ElementTree as ET
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from .signals import basename


@dataclass
class DependencyPools:
    js: set[str] = field(default_factory=set)
    py: set[str] = field(default_factory=set)
    java: set[str] = field(default_factory=set)
    go: set[str] = field(default_factory=set)
    rust: set[str] = field(default_factory=set)


def _read(root: str, rel: str) -> str:
    return (Path(root) / rel).read_text(encoding="utf-8")


def _normalize_py(name: str) -> str:
    return re.sub(r"[-_.]+", "-", name.strip().lower())


def _pep508_name(spec: str) -> str | None:
    s = spec.strip()
    if not s or s.startswith("#"):
        return None
    m = re.match(r"^([A-Za-z0-9._-]+)", s)
    return _normalize_py(m.group(1)) if m else None


def _local(tag: str) -> str:
    return tag.rsplit("}", 1)[-1]


def _add_package_json(root: str, rel: str, pools: DependencyPools) -> None:
    try:
        pkg = json.loads(_read(root, rel))
    except Exception:
        return
    for field_name in ("dependencies", "devDependencies", "peerDependencies", "optionalDependencies"):
        deps = pkg.get(field_name)
        if isinstance(deps, dict):
            pools.js.update(deps.keys())


def _add_pyproject(root: str, rel: str, pools: DependencyPools) -> None:
    try:
        doc = tomllib.loads(_read(root, rel))
    except Exception:
        return
    project = doc.get("project", {})
    for spec in project.get("dependencies", []) or []:
        n = _pep508_name(str(spec))
        if n:
            pools.py.add(n)
    for arr in (project.get("optional-dependencies", {}) or {}).values():
        for spec in arr or []:
            n = _pep508_name(str(spec))
            if n:
                pools.py.add(n)
    poetry = doc.get("tool", {}).get("poetry", {})
    for name in (poetry.get("dependencies", {}) or {}):
        if name.lower() != "python":
            pools.py.add(_normalize_py(name))
    for group in (poetry.get("group", {}) or {}).values():
        for name in (group.get("dependencies", {}) or {}):
            if name.lower() != "python":
                pools.py.add(_normalize_py(name))


def _add_requirements(root: str, rel: str, pools: DependencyPools) -> None:
    try:
        text = _read(root, rel)
    except Exception:
        return
    for line in text.splitlines():
        n = _pep508_name(line)
        if n:
            pools.py.add(n)


def _add_setup_py(root: str, rel: str, pools: DependencyPools) -> None:
    try:
        src = _read(root, rel)
    except Exception:
        return
    m = re.search(r"install_requires\s*=\s*\[(.*?)\]", src, re.DOTALL)
    if m:
        for q in re.findall(r"""["']([^"']+)["']""", m.group(1)):
            n = _pep508_name(q)
            if n:
                pools.py.add(n)


def _add_pom(root: str, rel: str, pools: DependencyPools) -> None:
    try:
        tree = ET.parse(str(Path(root) / rel))
    except Exception:
        return
    for dep in tree.iter():
        if _local(dep.tag) != "dependency":
            continue
        group = ""
        artifact = ""
        for child in dep:
            ln = _local(child.tag)
            if ln == "groupId":
                group = (child.text or "").strip()
            elif ln == "artifactId":
                artifact = (child.text or "").strip()
        if group and artifact:
            pools.java.add(f"{group}:{artifact}")
        if artifact:
            pools.java.add(artifact)


def _add_gradle(root: str, rel: str, pools: DependencyPools) -> None:
    try:
        src = _read(root, rel)
    except Exception:
        return
    for m in re.finditer(r"""["']([\w.-]+):([\w.-]+):[\w.$-]+["']""", src):
        pools.java.add(f"{m.group(1)}:{m.group(2)}")
        pools.java.add(m.group(2))


def _add_go_mod(root: str, rel: str, pools: DependencyPools) -> None:
    try:
        src = _read(root, rel)
    except Exception:
        return
    for m in re.finditer(
        r"^\s*(?:require\s+)?([a-zA-Z0-9._~-]+(?:/[a-zA-Z0-9._~-]+)+)\s+v", src, re.MULTILINE
    ):
        pools.go.add(m.group(1))


def _add_cargo(root: str, rel: str, pools: DependencyPools) -> None:
    try:
        doc = tomllib.loads(_read(root, rel))
    except Exception:
        return
    for section in ("dependencies", "dev-dependencies", "build-dependencies"):
        tbl = doc.get(section)
        if isinstance(tbl, dict):
            pools.rust.update(tbl.keys())


def parse_manifests(root: str, files: list[str]) -> DependencyPools:
    pools = DependencyPools()
    for rel in files:
        base = basename(rel)
        if base == "package.json":
            _add_package_json(root, rel, pools)
        elif base == "pyproject.toml":
            _add_pyproject(root, rel, pools)
        elif base == "requirements.txt":
            _add_requirements(root, rel, pools)
        elif base == "setup.py":
            _add_setup_py(root, rel, pools)
        elif base == "pom.xml":
            _add_pom(root, rel, pools)
        elif base in ("build.gradle", "build.gradle.kts"):
            _add_gradle(root, rel, pools)
        elif base == "go.mod":
            _add_go_mod(root, rel, pools)
        elif base == "Cargo.toml":
            _add_cargo(root, rel, pools)
    return pools
