"""Canonicalize a report dict for cross-impl / golden comparison.

Drops environment-specific fields (`root`, `generatedAt`, `generatedBy`) and defensively re-sorts
every array so equal information compares equal regardless of emission order.
"""
from __future__ import annotations

import copy
from typing import Any


def canonicalize(report: dict[str, Any]) -> dict[str, Any]:
    r = copy.deepcopy(report)
    for k in ("root", "generatedAt", "generatedBy"):
        r.pop(k, None)

    if isinstance(r.get("ecosystems"), list):
        for e in r["ecosystems"]:
            if isinstance(e.get("signals"), list):
                e["signals"] = sorted(e["signals"], key=lambda s: (s["path"], s["kind"]))
        r["ecosystems"] = sorted(r["ecosystems"], key=lambda e: e["id"])
    if isinstance(r.get("packageManagers"), list):
        r["packageManagers"] = sorted(r["packageManagers"])
    if isinstance(r.get("buildTools"), list):
        r["buildTools"] = sorted(r["buildTools"])
    if isinstance(r.get("frameworks"), list):
        for f in r["frameworks"]:
            if isinstance(f.get("evidence"), list):
                f["evidence"] = sorted(f["evidence"])
        r["frameworks"] = sorted(r["frameworks"], key=lambda f: (f["ecosystem"], f["name"]))
    if isinstance(r.get("testing"), list):
        r["testing"] = sorted(r["testing"], key=lambda t: (t["ecosystem"], t["framework"]))
    topo = r.get("topology")
    if isinstance(topo, dict) and isinstance(topo.get("signals"), list):
        topo["signals"] = sorted(topo["signals"])
    infra = r.get("infrastructure")
    if isinstance(infra, dict):
        for key in ("ci", "containers", "orchestration"):
            if isinstance(infra.get(key), list):
                infra[key] = sorted(infra[key])
    if isinstance(r.get("subRepos"), list):
        for s in r["subRepos"]:
            if isinstance(s.get("primaryManifests"), list):
                s["primaryManifests"] = sorted(s["primaryManifests"])
        r["subRepos"] = sorted(r["subRepos"], key=lambda s: s["path"])
    return r
