import tempfile

import pytest

from repo_fingerprint import cli

from conftest import FIXTURES


def test_exit_code_no_ecosystem():
    with tempfile.TemporaryDirectory() as d:
        assert cli.main([d]) == 1


def test_exit_code_detected():
    assert cli.main([str(FIXTURES / "node-ts")]) == 0


def test_exit_code_detected_text():
    assert cli.main([str(FIXTURES / "java-maven"), "--format", "text"]) == 0


def test_exit_code_missing_path():
    assert cli.main(["/no/such/path/here"]) == 2


def test_bad_flag_exits_2():
    with pytest.raises(SystemExit) as exc:
        cli.main(["--bogus", str(FIXTURES / "node-ts")])
    assert exc.value.code == 2
