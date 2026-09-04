# Shared Detection Contract

This directory is the **single source of truth** the bash, TypeScript, and Python detectors all
conform to.

| File | Purpose |
| --- | --- |
| [`detection-report.schema.json`](./detection-report.schema.json) | JSON Schema (draft 2020-12) for the output every impl emits. |
| [`signal-matrix.json`](./signal-matrix.json) | Ecosystems, frameworks, testing, topology & infrastructure signals + weights. |
| [`confidence-model.md`](./confidence-model.md) | The Diagnostic Confidence formula (TS + Py implement it identically). |
| [`examples/sample-report.json`](./examples/sample-report.json) | A hand-written **valid** report. |
| [`examples/invalid-report.json`](./examples/invalid-report.json) | A deliberately **invalid** report (bad enum + missing field). |

## Validating a report

**With ajv (Node):** the TypeScript package ships a validator — from `../packages/ts`:

```bash
node -e "import('./dist/schema.js').then(m => m.validateReportFile(process.argv[1]))" <report.json>
```

**With Python jsonschema** (from a venv that has `jsonschema` installed):

```bash
python -m repo_fingerprint.schema <report.json>      # via the py package
# or ad-hoc:
python - <<'PY'
import json, jsonschema
schema = json.load(open("schema/detection-report.schema.json"))
doc = json.load(open("report.json"))
jsonschema.validate(doc, schema, format_checker=jsonschema.FormatChecker())
print("valid")
PY
```

The [smoke test](../packages/ts/test/schema.test.ts) asserts `sample-report.json` validates and
`invalid-report.json` does not.
