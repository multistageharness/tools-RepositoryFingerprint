# repo-fingerprint (Python)

Python twin of the TypeScript detector. Same shared contract (`../../schema`), same Diagnostic
Confidence model — behaviorally matched via the shared golden fixtures.

```bash
pip install -e '.[test]'
repo-fingerprint ../../fixtures/node-ts --format text
python -m pytest
```
