"""Framework & testing-tool fingerprinting from dependency pools."""
from __future__ import annotations

from typing import Any

from .parsers import DependencyPools
from .types import FrameworkResult, TestingResult


def _pool_for(ecosystem: str, pools: DependencyPools) -> set[str]:
    if ecosystem in ("node", "typescript"):
        return pools.js
    if ecosystem == "python":
        return pools.py
    if ecosystem in ("java-maven", "java-gradle", "kotlin"):
        return pools.java
    if ecosystem == "go":
        return pools.go
    if ecosystem == "rust":
        return pools.rust
    return set()


def match_frameworks(matrix: dict[str, Any], pools: DependencyPools) -> list[FrameworkResult]:
    out: list[FrameworkResult] = []
    for defn in matrix["frameworks"]:
        pool = _pool_for(defn["ecosystem"], pools)
        evidence = sorted(d for d in defn["deps"] if d in pool)
        if evidence:
            out.append(FrameworkResult(ecosystem=defn["ecosystem"], name=defn["name"], evidence=evidence))
    return out


def match_testing(matrix: dict[str, Any], pools: DependencyPools) -> list[TestingResult]:
    out: list[TestingResult] = []
    for defn in matrix["testing"]:
        pool = _pool_for(defn["ecosystem"], pools)
        if any(d in pool for d in defn["deps"]):
            out.append(TestingResult(ecosystem=defn["ecosystem"], framework=defn["framework"]))
    return out
