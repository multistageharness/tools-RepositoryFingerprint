"""Topology resolution + package-manager / build-tool inference."""
from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from .signals import file_matches
from .types import Topology


def _safe_read(root: str, rel: str) -> str | None:
    try:
        return (Path(root) / rel).read_text(encoding="utf-8")
    except Exception:
        return None


def _match_topology_def(defn: dict[str, Any], root: str, files: list[str]) -> str | None:
    glob = defn.get("glob")
    if glob:
        return next((f for f in files if file_matches(f, glob)), None)
    marker = defn.get("marker")
    if marker:
        hit = next((f for f in files if file_matches(f, marker["file"])), None)
        if not hit:
            return None
        content = _safe_read(root, hit)
        if content is None:
            return None
        if marker.get("contains") and marker["contains"] in content:
            return hit
        if marker.get("jsonKey"):
            try:
                obj = json.loads(content)
            except Exception:
                return None
            if isinstance(obj, dict) and marker["jsonKey"] in obj:
                return hit
    return None


def resolve_topology(matrix: dict[str, Any], root: str, files: list[str]) -> Topology:
    matched: list[tuple[dict[str, Any], str]] = []
    for defn in matrix["topology"]:
        sig = _match_topology_def(defn, root, files)
        if sig is not None:
            matched.append((defn, sig))
    if not matched:
        return Topology(type="single", tool=None, signals=[])

    has_monorepo = any(d["type"] == "monorepo" for d, _ in matched)
    topo_type = "monorepo" if has_monorepo else "workspace"
    primary = next((d for d, _ in matched if d["type"] == topo_type), matched[0][0])
    signals = sorted({s for _, s in matched})
    return Topology(type=topo_type, tool=primary["tool"], signals=signals)


def infer_package_managers(matrix: dict[str, Any], files: list[str]) -> list[str]:
    tools: set[str] = set()
    for pm in matrix["packageManagers"]:
        if any(file_matches(f, pm["glob"]) for f in files):
            tools.add(pm["tool"])
    return sorted(tools)


def infer_build_tools(matrix: dict[str, Any], files: list[str]) -> list[str]:
    tools: set[str] = set()
    for bt in matrix["buildTools"]:
        if any(file_matches(f, bt["glob"]) for f in files):
            tools.add(bt["tool"])
    return sorted(tools)
