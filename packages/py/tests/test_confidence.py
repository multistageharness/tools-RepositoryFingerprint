from repo_fingerprint.confidence import (
    bucket_of,
    confidence_of,
    decayed_weight,
    proximate_score,
    raw_score_of,
    round4,
)
from repo_fingerprint.types import RawSignal


def sig(kind: str, weight: float, depth: int) -> RawSignal:
    return RawSignal(ecosystem_id="x", path="p", kind=kind, weight=weight, depth=depth)


def test_depth_decay():
    assert decayed_weight(1.0, 1) == 1.0
    assert decayed_weight(1.0, 2) == 0.5
    assert decayed_weight(1.0, 3) == 0.25
    assert decayed_weight(0.2, 1) == 0.2


def test_round4_half_up():
    assert round4(0.85043139) == 0.8504
    assert round4(0.77686984) == 0.7769
    assert round4(0.22119922) == 0.2212


def test_worked_example_a():
    signals = [
        sig("primary-manifest", 1.0, 1),
        sig("config", 0.5, 1),
        sig("lockfile", 0.4, 1),
        sig("config", 0.5, 1),
    ]
    raw = raw_score_of(signals)
    assert raw == 2.4
    assert confidence_of(raw) == 0.9895
    assert bucket_of(confidence_of(raw)) == "certain"


def test_worked_example_b():
    java = [
        sig("primary-manifest", 1.0, 1),
        sig("build-wrapper", 0.3, 1),
        sig("build-wrapper", 0.3, 1),
        sig("source-layout", 0.2, 1),
        sig("source-layout", 0.2, 1),
    ]
    py = [sig("primary-manifest", 1.0, 3)]
    assert raw_score_of(java) == 2.0
    assert confidence_of(2.0) == 0.9776
    assert bucket_of(0.9776) == "certain"
    assert raw_score_of(py) == 0.25
    assert confidence_of(0.25) == 0.3781
    assert bucket_of(0.3781) == "low"
    assert proximate_score(java) == 2.0
    assert proximate_score(py) == 0


def test_bucket_boundaries():
    assert bucket_of(0.9) == "certain"
    assert bucket_of(0.8999) == "high"
    assert bucket_of(0.7) == "high"
    assert bucket_of(0.6999) == "medium"
    assert bucket_of(0.4) == "medium"
    assert bucket_of(0.3999) == "low"
    assert bucket_of(0.0001) == "low"
    assert bucket_of(0.0) == "none"
