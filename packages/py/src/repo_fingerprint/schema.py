"""Validate a DetectionReport against the shared JSON Schema (requires jsonschema).

Usage: python -m repo_fingerprint.schema <report.json>
"""
from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any

from .matrix import schema_path


def validate_report(report: Any) -> tuple[bool, list[str]]:
    try:
        import jsonschema  # noqa: WPS433 (optional dependency)
    except ImportError as exc:  # pragma: no cover
        raise RuntimeError("jsonschema is required for validation (pip install 'repo-fingerprint[test]')") from exc

    with open(schema_path(), encoding="utf-8") as fh:
        schema = json.load(fh)
    validator = jsonschema.Draft202012Validator(
        schema, format_checker=jsonschema.Draft202012Validator.FORMAT_CHECKER
    )
    errors = [f"{list(e.absolute_path)} {e.message}" for e in validator.iter_errors(report)]
    return (len(errors) == 0, errors)


def main(argv: list[str] | None = None) -> int:
    args = sys.argv[1:] if argv is None else argv
    if not args:
        print("usage: python -m repo_fingerprint.schema <report.json>", file=sys.stderr)
        return 2
    doc = json.loads(Path(args[0]).read_text(encoding="utf-8"))
    valid, errors = validate_report(doc)
    if valid:
        print("valid")
        return 0
    for e in errors:
        print(f"invalid: {e}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
