import json

import pytest

from repo_fingerprint.schema import validate_report

from conftest import FIXTURES, REPO_ROOT, all_fixtures

jsonschema = pytest.importorskip("jsonschema")


def test_sample_valid():
    doc = json.loads((REPO_ROOT / "schema/examples/sample-report.json").read_text())
    valid, errors = validate_report(doc)
    assert valid, errors


def test_invalid_report_fails():
    doc = json.loads((REPO_ROOT / "schema/examples/invalid-report.json").read_text())
    valid, errors = validate_report(doc)
    assert not valid
    assert len(errors) >= 1


@pytest.mark.parametrize("fx", all_fixtures())
def test_goldens_validate(fx: str):
    for name in ("expected-report.json", "expected-report.bash.json"):
        doc = json.loads((FIXTURES / fx / name).read_text())
        valid, errors = validate_report(doc)
        assert valid, f"{fx}/{name}: {errors}"
