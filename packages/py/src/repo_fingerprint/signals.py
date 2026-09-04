"""Match walked paths against ecosystem signal globs, producing depth-tagged RawSignals."""
from __future__ import annotations

from typing import Any

from .types import RawSignal
from .walker import WalkResult


def posix_dirname(rel: str) -> str:
    i = rel.rfind("/")
    return "" if i < 0 else rel[:i]


def basename(rel: str) -> str:
    i = rel.rfind("/")
    return rel if i < 0 else rel[i + 1 :]


def segments(directory: str) -> int:
    return 0 if directory == "" else len(directory.split("/"))


def file_depth(rel: str) -> int:
    return segments(posix_dirname(rel)) + 1


def file_matches(rel: str, glob: str) -> bool:
    if glob.startswith("*."):
        return basename(rel).endswith(glob[1:])
    if "/" in glob:
        return rel == glob or rel.endswith("/" + glob)
    return basename(rel) == glob


def collect_signals(matrix: dict[str, Any], tree: WalkResult) -> list[RawSignal]:
    out: list[RawSignal] = []
    for eco in matrix["ecosystems"]:
        eco_id = eco["id"]
        for sig in eco["signals"]:
            glob = sig["glob"]
            kind = sig["kind"]
            weight = sig["weight"]
            if kind == "source-layout":
                for d in tree.dirs:
                    if d == glob or d.endswith("/" + glob):
                        anchor = d[: len(d) - len(glob)].rstrip("/")
                        depth = 1 if anchor == "" else segments(anchor) + 1
                        out.append(RawSignal(eco_id, d, kind, weight, depth))
            else:
                for rel in tree.files:
                    if file_matches(rel, glob):
                        out.append(RawSignal(eco_id, rel, kind, weight, file_depth(rel)))
    return out
