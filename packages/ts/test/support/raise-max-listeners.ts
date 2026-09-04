/**
 * Preloaded via `--require` (with tsx/cjs) ahead of the integration suite.
 * With four reporter destinations, the runner's pipelines attach 11 end/close/
 * error listeners to its TestsStream, tripping the default ceiling of 10 and
 * emitting MaxListenersExceededWarning. Must be a CJS --require preload, not
 * an ESM --import: reporters are composed before --import modules execute.
 * Raise the default instead of silencing warnings with --no-warnings.
 */
import { setMaxListeners } from "node:events";

setMaxListeners(64);
