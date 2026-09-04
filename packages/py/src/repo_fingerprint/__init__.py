"""repo_fingerprint — Python detector for the polyglot repository-fingerprint tool."""
from __future__ import annotations

from .fingerprint import fingerprint
from .types import DetectionReport

__all__ = ["fingerprint", "DetectionReport"]
__version__ = "1.0.0"
