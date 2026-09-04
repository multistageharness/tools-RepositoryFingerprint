"""CLI integration suite: spawns the detector as a real child process against every fixture,
asserting golden JSON equality, schema validity of live output, text rendering, deep-mode
behavior, and all documented exit codes (0 / 1 / 2 / --help).

This deliberately overlaps test_golden.py and test_cli.py: those prove the library layer
in-process; this one proves the process boundary (argument parsing, stdout serialization,
exit codes). Neither replaces the other.
"""
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

from repo_fingerprint.canonical import canonicalize
from repo_fingerprint.schema import validate_report

from conftest import FIXTURES, all_fixtures

pytest.importorskip("jsonschema")


def _cli_command() -> list[str]:
    """Console script when present, `python -m` fallback (mirrors scripts/parity.mjs)."""
    script = Path(sys.executable).parent / "repo-fingerprint"
    if script.is_file() and os.access(script, os.X_OK):
        return [str(script)]
    found = shutil.which("repo-fingerprint")
    if found:
        return [found]
    return [sys.executable, "-m", "repo_fingerprint.cli"]


CLI = _cli_command()


def run_cli(*args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run([*CLI, *args], capture_output=True, text=True)


def load_golden(fx: str) -> dict:
    path = FIXTURES / fx / "expected-report.json"
    assert path.is_file(), f"missing golden: {path}"
    return json.loads(path.read_text())


def test_fixture_corpus_non_empty():
    assert all_fixtures(), (
        f"no fixture directories found under {FIXTURES} — "
        "a 0-fixture pass would be a silent defect"
    )


@pytest.mark.parametrize("fx", all_fixtures())
def test_cli_json_matches_golden_and_schema(fx: str):
    golden = load_golden(fx)
    r = run_cli(str(FIXTURES / fx))
    want = 0 if golden["ecosystems"] else 1
    assert r.returncode == want, f"expected exit {want}, got {r.returncode}; stderr: {r.stderr}"
    report = json.loads(r.stdout)  # also proves stdout carries JSON and nothing else
    assert report["generatedBy"] == "py"
    assert canonicalize(report) == canonicalize(golden)
    valid, errors = validate_report(report)
    assert valid, f"live CLI output is schema-invalid: {errors}"


@pytest.mark.parametrize("fx", all_fixtures())
def test_cli_text_renders_dominant_ecosystem(fx: str):
    golden = load_golden(fx)
    r = run_cli(str(FIXTURES / fx), "--format", "text")
    want = 0 if golden["ecosystems"] else 1
    assert r.returncode == want, f"expected exit {want}, got {r.returncode}; stderr: {r.stderr}"
    assert r.stdout, "text output must be non-empty"
    if golden["dominantEcosystem"] is not None:
        expected = f"Dominant ecosystem: {golden['dominantEcosystem']}"
        assert expected in r.stdout, f'text output missing "{expected}"'


def test_cli_deep_multi_repo_npm_reports_topology_and_sub_repos():
    r = run_cli(str(FIXTURES / "multi-repo-npm"), "--deep")
    assert r.returncode == 0, r.stderr
    report = json.loads(r.stdout)
    assert report["topology"]["type"] == "monorepo"
    assert [s["path"] for s in report["subRepos"]] == ["repo-a", "repo-b"]
    assert [s["dominantEcosystem"] for s in report["subRepos"]] == ["node", "node"]


def test_cli_shadow_scan_is_exact_alias_for_deep():
    deep = run_cli(str(FIXTURES / "multi-repo-npm"), "--deep")
    shadow = run_cli(str(FIXTURES / "multi-repo-npm"), "--shadow-scan")
    assert deep.returncode == 0
    assert shadow.returncode == 0
    assert canonicalize(json.loads(shadow.stdout)) == canonicalize(json.loads(deep.stdout))


def test_cli_non_deep_omits_sub_repos():
    r = run_cli(str(FIXTURES / "multi-repo-npm"))
    assert r.returncode == 0, r.stderr
    report = json.loads(r.stdout)
    assert "subRepos" not in report
    assert report["topology"]["type"] == "single"


def test_cli_exit_0_detecting_fixture_json_and_text():
    for fmt in ("json", "text"):
        r = run_cli(str(FIXTURES / "node-ts"), "--format", fmt)
        assert r.returncode == 0, f"--format {fmt}: {r.stderr}"


def test_cli_exit_1_empty_directory(tmp_path: Path):
    r = run_cli(str(tmp_path))
    assert r.returncode == 1, f"expected exit 1, got {r.returncode}; stderr: {r.stderr}"
    report = json.loads(r.stdout)
    assert report["ecosystems"] == []


def test_cli_exit_2_unknown_flag():
    r = run_cli("--no-such-flag", str(FIXTURES / "node-ts"))
    assert r.returncode == 2
    assert "usage" in r.stderr.lower()


def test_cli_exit_2_nonexistent_path():
    r = run_cli("/no/such/path/here")
    assert r.returncode == 2
    assert "path not found or not a directory" in r.stderr


def test_cli_help_exits_0_with_usage():
    r = run_cli("--help")
    assert r.returncode == 0
    assert "usage" in r.stdout.lower()
    assert r.stderr == ""
