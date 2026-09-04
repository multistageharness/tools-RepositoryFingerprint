"""Dataclasses mirroring `schema/detection-report.schema.json`."""
from __future__ import annotations

from dataclasses import dataclass, field, asdict
from typing import Any, Literal, Optional

GeneratedBy = Literal["bash", "ts", "py"]
SignalKind = Literal[
    "primary-manifest",
    "lockfile",
    "build-wrapper",
    "config",
    "source-layout",
    "workspace-marker",
    "infra-marker",
]
ConfidenceBucket = Optional[Literal["none", "low", "medium", "high", "certain"]]
EcosystemRole = Literal["primary", "auxiliary"]
TopologyType = Literal["single", "monorepo", "workspace"]


@dataclass
class Signal:
    path: str
    kind: str
    weight: float


@dataclass
class EcosystemResult:
    id: str
    name: str
    signals: list[Signal]
    rawScore: Optional[float]
    confidence: Optional[float]
    confidenceBucket: ConfidenceBucket
    role: EcosystemRole


@dataclass
class Topology:
    type: str
    tool: Optional[str]
    signals: list[str]


@dataclass
class FrameworkResult:
    ecosystem: str
    name: str
    evidence: list[str]


@dataclass
class TestingResult:
    ecosystem: str
    framework: str


@dataclass
class Infrastructure:
    ci: list[str]
    containers: list[str]
    orchestration: list[str]


@dataclass
class SubRepo:
    """Deep-scan (`--deep`) only: a top-most nested directory with its own primary manifest."""

    path: str
    primaryManifests: list[str]
    dominantEcosystem: Optional[str]


@dataclass
class DetectionReport:
    schemaVersion: str
    root: str
    generatedBy: str
    generatedAt: str
    ecosystems: list[EcosystemResult]
    packageManagers: list[str]
    buildTools: list[str]
    topology: Topology
    frameworks: list[FrameworkResult]
    testing: list[TestingResult]
    infrastructure: Infrastructure
    dominantEcosystem: Optional[str]
    # Present only on deep (`--deep` / `--shadow-scan`) runs; omitted from to_dict() when None
    # so non-deep reports stay byte-identical to the pre-deep contract.
    subRepos: Optional[list[SubRepo]] = None

    def to_dict(self) -> dict[str, Any]:
        d = asdict(self)
        if self.subRepos is None:
            del d["subRepos"]
        return d


@dataclass
class RawSignal:
    """A signal discovered on disk, carrying the depth needed for confidence decay."""

    ecosystem_id: str
    path: str
    kind: str
    weight: float
    depth: int
