"""Recursive filesystem walker: relative POSIX file & directory paths, ignoring noise dirs."""
from __future__ import annotations

import os
from dataclasses import dataclass

IGNORED_DIRS = {
    ".git",
    "node_modules",
    "dist",
    "build",
    "out",
    "target",
    "vendor",
    ".venv",
    "venv",
    "__pycache__",
    ".idea",
    ".gradle",
    ".mvn",
    ".next",
    "coverage",
}

DEFAULT_MAX_DEPTH = 12


@dataclass
class WalkResult:
    files: list[str]
    dirs: list[str]


def walk(root: str, max_depth: int = DEFAULT_MAX_DEPTH) -> WalkResult:
    files: list[str] = []
    dirs: list[str] = []
    root_abs = os.path.abspath(root)

    for dirpath, dirnames, filenames in os.walk(root_abs):
        rel_dir = os.path.relpath(dirpath, root_abs)
        depth = 0 if rel_dir == "." else len(rel_dir.split(os.sep))
        # Prune ignored dirs and enforce max depth.
        dirnames[:] = [
            d for d in dirnames if d not in IGNORED_DIRS and depth + 1 <= max_depth
        ]
        for d in dirnames:
            rel = os.path.join(rel_dir, d) if rel_dir != "." else d
            dirs.append(rel.replace(os.sep, "/"))
        for f in filenames:
            rel = os.path.join(rel_dir, f) if rel_dir != "." else f
            files.append(rel.replace(os.sep, "/"))

    files.sort()
    dirs.sort()
    return WalkResult(files=files, dirs=dirs)
