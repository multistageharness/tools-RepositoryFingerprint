"""CLI front-end for the Python repository-fingerprint detector."""
from __future__ import annotations

import argparse
import json
import os
import sys

from .fingerprint import fingerprint
from .types import DetectionReport


def _render_text(r: DetectionReport) -> str:
    lines: list[str] = []
    lines.append(f"Repository: {r.root}")
    lines.append(f"Detected by: {r.generatedBy}")
    lines.append(f"Dominant ecosystem: {r.dominantEcosystem or '(none)'}")
    lines.append("")
    lines.append("Ecosystems:")
    if not r.ecosystems:
        lines.append("  (none)")
    for e in r.ecosystems:
        conf = (
            f"{e.confidence} ({e.confidenceBucket})"
            if e.confidence is not None
            else "n/a (presence-only)"
        )
        lines.append(f"  - {e.name} [{e.role}] confidence={conf} signals={len(e.signals)}")
    lines.append("")
    lines.append(f"Package managers: {', '.join(r.packageManagers) or '(none)'}")
    lines.append(f"Build tools: {', '.join(r.buildTools) or '(none)'}")
    topo = f"Topology: {r.topology.type}"
    if r.topology.tool:
        topo += f" ({r.topology.tool})"
    lines.append(topo)
    if r.subRepos:
        lines.append("Sub-repos:")
        for s in r.subRepos:
            eco = s.dominantEcosystem or "unknown"
            lines.append(f"  - {s.path} ({eco}, {len(s.primaryManifests)} manifest(s))")
    if r.frameworks:
        lines.append("Frameworks:")
        for f in r.frameworks:
            lines.append(f"  - {f.name} ({f.ecosystem})")
    if r.testing:
        lines.append("Testing:")
        for t in r.testing:
            lines.append(f"  - {t.framework} ({t.ecosystem})")
    infra = r.infrastructure
    if infra.ci or infra.containers or infra.orchestration:
        lines.append("Infrastructure:")
        if infra.ci:
            lines.append(f"  ci: {', '.join(infra.ci)}")
        if infra.containers:
            lines.append(f"  containers: {', '.join(infra.containers)}")
        if infra.orchestration:
            lines.append(f"  orchestration: {', '.join(infra.orchestration)}")
    return "\n".join(lines)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="repo-fingerprint",
        description="Detect a repository's ecosystems, topology & Diagnostic Confidence.",
    )
    parser.add_argument("path", nargs="?", default=".", help="repository root to scan")
    parser.add_argument(
        "--format", choices=["json", "text"], default="json", help="output format"
    )
    parser.add_argument(
        "--deep",
        "--shadow-scan",
        dest="deep",
        action="store_true",
        help="deep (shadow) scan: monorepo-aware dominance fallback and "
        "nested sub-repo enumeration",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    # argparse exits with code 2 on unknown flags / invalid choices.
    args = parser.parse_args(argv)

    if not os.path.isdir(args.path):
        print(f"error: path not found or not a directory: {args.path}", file=sys.stderr)
        return 2

    report = fingerprint(args.path, generated_by="py", deep=args.deep)
    if args.format == "text":
        print(_render_text(report))
    else:
        print(json.dumps(report.to_dict(), indent=2))

    return 0 if report.ecosystems else 1


if __name__ == "__main__":
    sys.exit(main())
