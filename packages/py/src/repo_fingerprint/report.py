"""Weighted aggregation, dominant/auxiliary resolution, and assembly into the shared schema."""
from __future__ import annotations

from typing import Any, Literal

from .confidence import (
    bucket_of,
    confidence_of,
    primary_manifest_count,
    proximate_score,
    raw_score_of,
)
from .types import (
    DetectionReport,
    EcosystemResult,
    FrameworkResult,
    Infrastructure,
    RawSignal,
    Signal,
    SubRepo,
    TestingResult,
    Topology,
)

ScoreMode = Literal["confidence", "presence"]


def _group_by_ecosystem(
    matrix: dict[str, Any], signals: list[RawSignal]
) -> list[tuple[str, str, list[RawSignal]]]:
    names = {e["id"]: e["name"] for e in matrix["ecosystems"]}
    by_id: dict[str, list[RawSignal]] = {}
    for s in signals:
        by_id.setdefault(s.ecosystem_id, []).append(s)
    return [(eid, names.get(eid, eid), raw) for eid, raw in by_id.items()]


def _pick_dominant(
    groups: list[tuple[str, str, list[RawSignal]]], mode: ScoreMode, deep: bool = False
) -> str | None:
    if not groups:
        return None
    # Deep dominance fallback: with --deep and zero root-proximate (depth <= 1) primary
    # manifests, lift the depth limit and rank on full-depth evidence instead.
    full_depth = deep and all(
        primary_manifest_count(raw, True) == 0 for _eid, _name, raw in groups
    )
    depth_limited = not full_depth
    scored = []
    for eid, _name, raw in groups:
        if mode == "confidence":
            score = raw_score_of(raw) if full_depth else proximate_score(raw)
        else:
            score = primary_manifest_count(raw, depth_limited)
        scored.append((eid, score, primary_manifest_count(raw, depth_limited)))
    # sort: score desc, primaries desc, id asc
    scored.sort(key=lambda t: (-t[1], -t[2], t[0]))
    return scored[0][0]


def compute_sub_repos(signals: list[RawSignal]) -> list[SubRepo]:
    """Deep-scan sub-repo enumeration: top-most nested dirs holding their own primary manifest."""
    nested = [s for s in signals if s.kind == "primary-manifest" and "/" in s.path]
    cands = sorted({s.path.rsplit("/", 1)[0] for s in nested})
    tops = [d for d in cands if not any(c != d and d.startswith(c + "/") for c in cands)]
    out: list[SubRepo] = []
    for d in tops:
        in_tree = [s for s in nested if s.path.startswith(d + "/")]
        counts: dict[str, int] = {}
        for s in in_tree:
            counts[s.ecosystem_id] = counts.get(s.ecosystem_id, 0) + 1
        ranked = sorted(counts.items(), key=lambda kv: (-kv[1], kv[0]))
        out.append(
            SubRepo(
                path=d,
                primaryManifests=sorted({s.path for s in in_tree}),
                dominantEcosystem=ranked[0][0] if ranked else None,
            )
        )
    return out


def _to_signals(raw: list[RawSignal]) -> list[Signal]:
    sigs = [Signal(path=s.path, kind=s.kind, weight=s.weight) for s in raw]
    sigs.sort(key=lambda s: (s.path, s.kind))
    return sigs


def aggregate(
    matrix: dict[str, Any], signals: list[RawSignal], mode: ScoreMode, deep: bool = False
) -> tuple[list[EcosystemResult], str | None]:
    groups = _group_by_ecosystem(matrix, signals)
    dominant = _pick_dominant(groups, mode, deep)

    ecosystems: list[EcosystemResult] = []
    for eid, name, raw in groups:
        raw_score = raw_score_of(raw) if mode == "confidence" else None
        confidence = confidence_of(raw_score) if raw_score is not None else None
        bucket = bucket_of(confidence) if confidence is not None else None
        ecosystems.append(
            EcosystemResult(
                id=eid,
                name=name,
                signals=_to_signals(raw),
                rawScore=raw_score,
                confidence=confidence,
                confidenceBucket=bucket,
                role="primary" if eid == dominant else "auxiliary",
            )
        )
    ecosystems.sort(key=lambda e: e.id)
    return ecosystems, dominant


def assemble_report(
    *,
    root: str,
    generated_by: str,
    generated_at: str,
    ecosystems: list[EcosystemResult],
    package_managers: list[str],
    build_tools: list[str],
    topology: Topology,
    frameworks: list[FrameworkResult],
    testing: list[TestingResult],
    infrastructure: Infrastructure,
    dominant_ecosystem: str | None,
    sub_repos: list[SubRepo] | None = None,
) -> DetectionReport:
    ecosystems = sorted(ecosystems, key=lambda e: e.id)
    frameworks = sorted(frameworks, key=lambda f: (f.ecosystem, f.name))
    for f in frameworks:
        f.evidence = sorted(f.evidence)
    testing = sorted(testing, key=lambda t: (t.ecosystem, t.framework))
    topology = Topology(type=topology.type, tool=topology.tool, signals=sorted(set(topology.signals)))
    infrastructure = Infrastructure(
        ci=sorted(set(infrastructure.ci)),
        containers=sorted(set(infrastructure.containers)),
        orchestration=sorted(set(infrastructure.orchestration)),
    )
    if sub_repos is not None:
        sub_repos = sorted(
            (
                SubRepo(
                    path=s.path,
                    primaryManifests=sorted(s.primaryManifests),
                    dominantEcosystem=s.dominantEcosystem,
                )
                for s in sub_repos
            ),
            key=lambda s: s.path,
        )
    return DetectionReport(
        schemaVersion="1.0",
        root=root,
        generatedBy=generated_by,
        generatedAt=generated_at,
        ecosystems=ecosystems,
        packageManagers=sorted(set(package_managers)),
        buildTools=sorted(set(build_tools)),
        topology=topology,
        frameworks=frameworks,
        testing=testing,
        infrastructure=infrastructure,
        dominantEcosystem=dominant_ecosystem,
        subRepos=sub_repos,
    )
