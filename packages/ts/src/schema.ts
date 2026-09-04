/** ajv-backed validation of a DetectionReport against the shared JSON Schema. */
import { readFileSync } from "node:fs";
import Ajv2020Module from "ajv/dist/2020.js";
import addFormatsModule from "ajv-formats";
import { schemaPath } from "./matrix.js";
import type { DetectionReport } from "./types.js";

// ajv & ajv-formats ship as CommonJS; normalize the interop default shape.
const Ajv2020: any = (Ajv2020Module as any).default ?? Ajv2020Module;
const addFormats: any = (addFormatsModule as any).default ?? addFormatsModule;

export interface ValidationResult {
  valid: boolean;
  errors: string[];
}

let validate: any = null;

function getValidator(): any {
  if (validate) return validate;
  const schema = JSON.parse(readFileSync(schemaPath(), "utf8"));
  const ajv = new Ajv2020({ allErrors: true, strict: false });
  addFormats(ajv);
  validate = ajv.compile(schema);
  return validate;
}

export function validateReport(report: unknown): ValidationResult {
  const fn = getValidator();
  const valid = fn(report) as boolean;
  const errors = (fn.errors ?? []).map((e: any) =>
    `${e.instancePath || "<root>"} ${e.message}`.trim(),
  );
  return { valid, errors };
}

export function validateReportFile(path: string): ValidationResult {
  return validateReport(JSON.parse(readFileSync(path, "utf8")) as DetectionReport);
}
