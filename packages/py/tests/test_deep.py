from dataclasses import asdict

from repo_fingerprint.fingerprint import fingerprint
from repo_fingerprint import cli

from conftest import FIXTURES


def test_deep_multi_repo_npm_resolves():
    r = fingerprint(str(FIXTURES / "multi-repo-npm"), generated_by="py", deep=True)
    assert r.dominantEcosystem == "node"
    assert r.ecosystems[0].role == "primary"
    assert r.topology.type == "monorepo"
    assert r.topology.tool is None
    assert [asdict(s) for s in r.subRepos] == [
        {
            "path": "repo-a",
            "primaryManifests": ["repo-a/package.json"],
            "dominantEcosystem": "node",
        },
        {
            "path": "repo-b",
            "primaryManifests": ["repo-b/package.json"],
            "dominantEcosystem": "node",
        },
    ]


def test_non_deep_omits_sub_repos_key():
    r = fingerprint(str(FIXTURES / "multi-repo-npm"), generated_by="py")
    d = r.to_dict()
    assert "subRepos" not in d
    assert r.topology.type == "single"


def test_deep_root_manifest_repo_unchanged():
    deep = fingerprint(str(FIXTURES / "node-ts"), generated_by="py", deep=True)
    flat = fingerprint(str(FIXTURES / "node-ts"), generated_by="py")
    assert deep.subRepos == []
    assert deep.dominantEcosystem == flat.dominantEcosystem
    assert deep.topology == flat.topology


def test_deep_root_dominance_kept_nested_aux_listed():
    r = fingerprint(str(FIXTURES / "java-dominant-nested-py"), generated_by="py", deep=True)
    assert r.dominantEcosystem == "java-maven"
    assert r.topology.type == "single"
    assert [(s.path, s.dominantEcosystem) for s in r.subRepos] == [("tools/script", "python")]


def test_deep_workspace_marker_topology_not_overridden():
    r = fingerprint(str(FIXTURES / "pnpm-monorepo"), generated_by="py", deep=True)
    assert r.topology.type == "monorepo"
    assert r.topology.tool == "pnpm"
    assert [s.path for s in r.subRepos] == ["packages/a", "packages/b"]


def test_cli_deep_and_shadow_scan_flags():
    parser = cli.build_parser()
    assert parser.parse_args([str(FIXTURES / "node-ts"), "--deep"]).deep is True
    assert parser.parse_args([str(FIXTURES / "node-ts"), "--shadow-scan"]).deep is True
    assert parser.parse_args([str(FIXTURES / "node-ts")]).deep is False
    assert cli.main([str(FIXTURES / "multi-repo-npm"), "--deep"]) == 0
