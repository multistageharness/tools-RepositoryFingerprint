from pathlib import Path

from repo_fingerprint.frameworks import match_frameworks, match_testing
from repo_fingerprint.matrix import load_matrix
from repo_fingerprint.parsers import parse_manifests
from repo_fingerprint.walker import walk

from conftest import FIXTURES


def pools_for(fx: str):
    root = str(FIXTURES / fx)
    return parse_manifests(root, walk(root).files)


def test_node_pool():
    p = pools_for("node-ts")
    assert {"react", "express", "typescript", "jest"} <= p.js


def test_python_pool():
    p = pools_for("python-poetry")
    assert {"django", "numpy", "pytest"} <= p.py


def test_maven_pool():
    p = pools_for("java-maven")
    assert "org.springframework.boot:spring-boot-starter" in p.java
    assert "spring-boot-starter" in p.java
    assert "com.fasterxml.jackson.core:jackson-databind" in p.java


def test_go_rust_pools():
    go = pools_for("go-mod")
    assert {"google.golang.org/grpc", "k8s.io/client-go"} <= go.go
    rust = pools_for("rust-cargo")
    assert {"tokio", "serde"} <= rust.rust


def test_nested_requirements():
    p = pools_for("java-dominant-nested-py")
    assert {"pandas", "requests"} <= p.py


def test_matchers():
    matrix = load_matrix()
    p = pools_for("node-ts")
    assert sorted(f.name for f in match_frameworks(matrix, p)) == ["Express", "React", "TypeScript"]
    assert [t.framework for t in match_testing(matrix, p)] == ["Jest"]
