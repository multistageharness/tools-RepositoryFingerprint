"""Diagnostic Confidence engine — deterministic twin of the TS implementation.

Byte-identical numbers to `schema/confidence-model.md` and the TypeScript detector.
"""
from __future__ import annotations

import math
from decimal import ROUND_HALF_UP, Decimal
from typing import Iterable

from .types import RawSignal


def decayed_weight(weight: float, depth: int) -> float:
    return weight * (0.5 ** max(0, depth - 1))


def round4(x: float) -> float:
    """Round half-up (away from zero) to 4 decimals, matching JS Math.round(x*1e4)/1e4."""
    return float(Decimal(repr(x)).quantize(Decimal("0.0001"), rounding=ROUND_HALF_UP))


def raw_score_of(signals: Iterable[RawSignal]) -> float:
    return round4(sum(decayed_weight(s.weight, s.depth) for s in signals))


# Steepness constant k — calibrated value defined in `schema/confidence-model.md` §5.
STEEPNESS = 1.9


def confidence_of(raw_score: float) -> float:
    return round4(1 - math.exp(-STEEPNESS * raw_score))


def bucket_of(confidence: float) -> str:
    if confidence >= 0.9:
        return "certain"
    if confidence >= 0.7:
        return "high"
    if confidence >= 0.4:
        return "medium"
    if confidence > 0:
        return "low"
    return "none"


def proximate_score(signals: Iterable[RawSignal]) -> float:
    return round4(
        sum(decayed_weight(s.weight, s.depth) for s in signals if s.depth <= 1)
    )


def primary_manifest_count(signals: Iterable[RawSignal], depth_limited: bool = True) -> int:
    return sum(
        1
        for s in signals
        if s.kind == "primary-manifest" and (not depth_limited or s.depth <= 1)
    )
