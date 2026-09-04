"""Loads and locates the shared `schema/` artifacts."""
from __future__ import annotations

import json
import os
from functools import lru_cache
from pathlib import Path
from typing import Any

# .../packages/py/src/repo_fingerprint/matrix.py -> repo root is 4 levels up from this file's dir.
_REPO_ROOT = Path(__file__).resolve().parents[4]


def matrix_path() -> Path:
    override = os.environ.get("RF_MATRIX")
    return Path(override).resolve() if override else _REPO_ROOT / "schema" / "signal-matrix.json"


def schema_path() -> Path:
    override = os.environ.get("RF_SCHEMA")
    return Path(override).resolve() if override else _REPO_ROOT / "schema" / "detection-report.schema.json"


@lru_cache(maxsize=None)
def _load_cached(path_str: str) -> dict[str, Any]:
    with open(path_str, encoding="utf-8") as fh:
        return json.load(fh)


def load_matrix(path: Path | None = None) -> dict[str, Any]:
    p = path or matrix_path()
    return _load_cached(str(p))
