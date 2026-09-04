"""Infrastructure marker detection: CI, containers, orchestration."""
from __future__ import annotations

from typing import Any

from .signals import file_matches
from .types import Infrastructure


def resolve_infrastructure(matrix: dict[str, Any], files: list[str]) -> Infrastructure:
    ci: set[str] = set()
    containers: set[str] = set()
    orchestration: set[str] = set()
    for inf in matrix["infrastructure"]:
        glob = inf["glob"]
        dir_marker = not glob.startswith("*.") and "/" in glob and "." not in glob
        if dir_marker:
            hit = any(f == glob or f.startswith(glob + "/") for f in files)
        else:
            hit = any(file_matches(f, glob) for f in files)
        if not hit:
            continue
        if inf["category"] == "ci":
            ci.add(inf["tool"])
        elif inf["category"] == "containers":
            containers.add(inf["tool"])
        else:
            orchestration.add(inf["tool"])
    return Infrastructure(
        ci=sorted(ci), containers=sorted(containers), orchestration=sorted(orchestration)
    )
