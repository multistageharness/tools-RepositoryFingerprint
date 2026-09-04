"""Top-level orchestration: walk a repo and produce a full DetectionReport."""
from __future__ import annotations

import os
from datetime import datetime, timezone

from .confidence import primary_manifest_count
from .frameworks import match_frameworks, match_testing
from .infra import resolve_infrastructure
from .matrix import load_matrix
from .parsers import parse_manifests
from .report import aggregate, assemble_report, compute_sub_repos
from .signals import collect_signals
from .topology import infer_build_tools, infer_package_managers, resolve_topology
from .types import DetectionReport, Topology
from .walker import walk


def fingerprint(
    root: str, generated_by: str = "py", now: str | None = None, deep: bool = False
) -> DetectionReport:
    abs_root = os.path.abspath(root)
    matrix = load_matrix()
    tree = walk(abs_root)

    signals = collect_signals(matrix, tree)
    pools = parse_manifests(abs_root, tree.files)
    ecosystems, dominant = aggregate(matrix, signals, "confidence", deep)

    topology = resolve_topology(matrix, abs_root, tree.files)
    sub_repos = None
    if deep:
        sub_repos = compute_sub_repos(signals)
        # Deep topology inference: >= 2 sub-repos, no root-proximate primary manifest, and no
        # workspace/monorepo marker already detected => a marker-less "multi-repo" monorepo.
        root_primaries = primary_manifest_count(signals, True)
        if len(sub_repos) >= 2 and root_primaries == 0 and topology.type == "single":
            topology = Topology(type="monorepo", tool=None, signals=topology.signals)

    generated_at = now or datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    return assemble_report(
        root=abs_root,
        generated_by=generated_by,
        generated_at=generated_at,
        ecosystems=ecosystems,
        package_managers=infer_package_managers(matrix, tree.files),
        build_tools=infer_build_tools(matrix, tree.files),
        topology=topology,
        frameworks=match_frameworks(matrix, pools),
        testing=match_testing(matrix, pools),
        infrastructure=resolve_infrastructure(matrix, tree.files),
        dominant_ecosystem=dominant,
        sub_repos=sub_repos,
    )
