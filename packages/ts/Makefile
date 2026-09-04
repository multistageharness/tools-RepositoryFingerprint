# Local driver for the TypeScript detector, mirroring the CI `ts` job
# (.github/workflows/ci.yml: npm ci -> typecheck -> build -> test).

NPM   ?= npm
NODE  ?= node
LOGS  ?= logs

.DEFAULT_GOAL := help

.PHONY: help install typecheck lint build test integration integration-report ci clean

help: ## Show available targets
	@grep -E '^[a-z-]+:.*##' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-12s %s\n", $$1, $$2}'

install: ## Clean install from package-lock.json (same as CI)
	$(NPM) ci

typecheck: ## Type-check without emitting
	$(NPM) run typecheck

lint: ## Alias of typecheck (tsc --noEmit)
	$(NPM) run lint

build: ## Compile src/ to dist/
	$(NPM) run build

test: ## Full test suite (unit + golden + CLI integration)
	$(NPM) test

integration: ## CLI integration suite; writes reports (junit xml, tap, spec log, fixtures jsonl) under logs/
	@mkdir -p $(LOGS)
	@stamp=$$(date +%Y%m%d-%H%M%S); \
	INTEGRATION_SUMMARY_FILE=$(CURDIR)/$(LOGS)/integration-$$stamp.fixtures.jsonl \
	$(NODE) --require tsx/cjs --require ./test/support/raise-max-listeners.ts --import tsx --test \
	  --test-reporter=spec  --test-reporter-destination=stdout \
	  --test-reporter=spec  --test-reporter-destination=$(LOGS)/integration-$$stamp.log \
	  --test-reporter=junit --test-reporter-destination=$(LOGS)/integration-$$stamp.junit.xml \
	  --test-reporter=tap   --test-reporter-destination=$(LOGS)/integration-$$stamp.tap \
	  test/cli-integration.test.ts; \
	status=$$?; \
	echo "reports written to $(LOGS)/integration-$$stamp.{log,junit.xml,tap,fixtures.jsonl}"; \
	exit $$status

integration-report: integration ## Alias for integration (kept for compatibility)

ci: install typecheck build test ## Run the CI ts job's steps in order

clean: ## Remove build output and installed dependencies
	rm -rf dist node_modules
