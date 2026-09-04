import json

import pytest

from repo_fingerprint.canonical import canonicalize
from repo_fingerprint.fingerprint import fingerprint

from conftest import FIXTURES, all_fixtures


@pytest.mark.parametrize("fx", all_fixtures())
def test_golden(fx: str):
    golden = json.loads((FIXTURES / fx / "expected-report.json").read_text())
    actual = fingerprint(str(FIXTURES / fx), generated_by="py").to_dict()
    assert canonicalize(actual) == canonicalize(golden)
