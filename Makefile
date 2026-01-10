VENV=venv
PYTHON := $(VENV)/bin/python
PIP := $(VENV)/bin/pip
PY_OUT=sdks/py_sdk/sw4rm/protos
PROTO_DIR=protos
PROTOS=$(PROTO_DIR)/*.proto

.PHONY: protos
$(PY_OUT):
	mkdir -p $(PY_OUT)

protos: $(PY_OUT)
	@inc=$$($(PYTHON) -c "import pkg_resources, grpc_tools; print(pkg_resources.resource_filename('grpc_tools','_proto'))" 2>/dev/null || true); \
	if [ -n "$$inc" ]; then \
	  $(PYTHON) -m grpc_tools.protoc -I$(PROTO_DIR) -I"$$inc" --python_out=$(PY_OUT) --grpc_python_out=$(PY_OUT) --pyi_out=$(PY_OUT) $(PROTOS); \
	else \
	  $(PYTHON) -m grpc_tools.protoc -I$(PROTO_DIR) --python_out=$(PY_OUT) --grpc_python_out=$(PY_OUT) --pyi_out=$(PY_OUT) $(PROTOS); \
	fi
	@echo "Fixing relative imports..."
	@cd $(PY_OUT) && sed -i 's/^import \(.*_pb2\)/from . import \1/' *_pb2.py *_pb2_grpc.py

.PHONY: check-stubs
check-stubs:
	$(PYTHON) scripts/ensure_stubs_present.py

.PHONY: release
release: dev-deps protos check-stubs
	$(PYTHON) -m build

.PHONY: smoke-wheel
smoke-wheel:
	@set -e; \
	WHEEL=$$(ls -t dist/*.whl | head -n1); \
	if [ -z "$$WHEEL" ]; then echo "No wheel found in dist/. Run 'make release' first."; exit 1; fi; \
	. $(VENV)/bin/activate; \
	python -m pip install --force-reinstall "$$WHEEL" >/dev/null; \
	python -c "import json; import subprocess; print('sw4rm import ok'); print(subprocess.run(['sw4rm-doctor'], capture_output=True, text=True).stdout)"

# -----------------------
# Dry-run and verification
# -----------------------
.PHONY: release-verify
release-verify: check-stubs
	@set -e; \
	echo "[verify] Running metadata verifier..."; \
	$(PYTHON) scripts/verify_dist_metadata.py; \
	if $(PYTHON) -m twine --version >/dev/null 2>&1; then \
	  echo "[verify] Running twine check..."; \
	  $(PYTHON) -m twine check dist/* || echo "[warn] 'twine check' failed; possibly due to older Twine not supporting Metadata-Version 2.4. Basic metadata verified."; \
	else \
	  echo "[verify] Twine not installed; skipping 'twine check'. Install with: $(PIP) install twine"; \
	fi

.PHONY: build-temp
build-temp: protos check-stubs
	@set -e; \
	outdir=$$(mktemp -d); \
	echo "[build-temp] Building into $$outdir"; \
	$(PYTHON) -m build --outdir "$$outdir"; \
	echo "[build-temp] Build complete. Cleaning $$outdir"; \
	rm -rf "$$outdir"; \
	echo "[build-temp] Done. No artifacts left behind."

.PHONY: publish-test
publish-test: release
	@set -e; \
	if ! $(PYTHON) -m twine --version >/dev/null 2>&1; then \
	  echo "[publish-test] twine not installed in venv. Install with: $(PIP) install twine"; \
	  exit 1; \
	fi; \
	$(PYTHON) -m twine upload --repository testpypi dist/*

.PHONY: publish
publish: release-verify
	@set -e; \
	if ! $(PYTHON) -m twine --version >/dev/null 2>&1; then \
	  echo "[publish] twine not installed in venv. Install with: $(PIP) install twine"; \
	  exit 1; \
	fi; \
	$(PYTHON) -m twine upload dist/*

.PHONY: tag
tag:
	@set -e; \
	ver=$$(sed -n 's/^version = "\(.*\)"/\1/p' pyproject.toml | head -n1); \
	if [ -z "$$ver" ]; then echo "[tag] version not found in pyproject.toml"; exit 1; fi; \
	if git rev-parse -q --verify "refs/tags/v$$ver" >/dev/null; then \
	  echo "[tag] tag v$$ver already exists"; \
	else \
	  git tag -a "v$$ver" -m "release v$$ver"; \
	  echo "[tag] created tag v$$ver"; \
	fi

.PHONY: tag-push
tag-push:
	@git push --tags

# -----------------------
# Release helpers
# -----------------------
.PHONY: tag-all tag-py tag-npm tag-rs

# Create all three tags for a version (requires versions already bumped)
tag-all:
	@set -e; \
	if [ -z "$(VER)" ]; then echo "Usage: make tag-all VER=X.Y.Z"; exit 1; fi; \
	python scripts/release_all.py $(VER) --push

# Create a single tag
tag-py:
	@set -e; \
	if [ -z "$(VER)" ]; then echo "Usage: make tag-py VER=X.Y.Z"; exit 1; fi; \
	python scripts/release.py py $(VER) --push

tag-npm:
	@set -e; \
	if [ -z "$(VER)" ]; then echo "Usage: make tag-npm VER=X.Y.Z"; exit 1; fi; \
	python scripts/release.py npm $(VER) --push

tag-rs:
	@set -e; \
	if [ -z "$(VER)" ]; then echo "Usage: make tag-rs VER=X.Y.Z"; exit 1; fi; \
	python scripts/release.py rs $(VER) --push

.PHONY: smoke
smoke:
	$(PYTHON) scripts/smoke_protos.py

# Ensure a repo-local virtualenv exists; error if it cannot be created.
.PHONY: venv
venv:
	@set -e; \
	if [ -x $(VENV)/bin/python ]; then \
	  echo "[make] venv exists"; \
	else \
	  echo "[make] creating venv..."; \
	  if command -v python3 >/dev/null 2>&1 && python3 -c "import ensurepip" >/dev/null 2>&1; then \
	    python3 -m venv $(VENV); \
	  elif command -v virtualenv >/dev/null 2>&1; then \
	    virtualenv -p $$(command -v python3 || echo python3) $(VENV); \
	  elif [ -x "$$HOME/3124/bin/virtualenv" ]; then \
	    "$$HOME/3124/bin/virtualenv" -p "$$HOME/3124/bin/python" $(VENV); \
	  elif [ -x "$$HOME/3124/bin/python" ]; then \
	    "$$HOME/3124/bin/python" -m venv $(VENV); \
	  else \
	    echo "[make] Error: cannot create venv (install python3-venv or virtualenv)"; exit 1; \
	  fi; \
	fi

.PHONY: dev-deps
dev-deps: venv
	$(PYTHON) -m pip install -e ".[dev]"

# Documentation targets
.PHONY: docs-serve docs-build docs-deps
docs-deps: venv
	$(PIP) install -e ".[docs]"

docs-build: docs-deps protos
	$(PYTHON) -m mkdocs build

docs-serve: docs-deps protos
	$(PYTHON) -m mkdocs serve --dev-addr=0.0.0.0:8010

# Documentation linting
.PHONY: docs-lint docs-fix-spacing install-git-hooks
docs-lint:
	$(PYTHON) scripts/check_docs_style.py

docs-fix-spacing:
	$(PYTHON) scripts/fix_docs_style.py

install-git-hooks:
	bash scripts/install_git_hooks.sh

# Add dev-deps as an implicit prerequisite for common tasks
protos: dev-deps
smoke: dev-deps

.PHONY: clean
clean:
	rm -rf dist build site sdks/py_sdk/sw4rm_sdk.egg-info

# -----------------------
# Swarm Core Orchestration
# -----------------------

# -----------------------
# Unified Testing
# -----------------------
.PHONY: test test-python test-rust test-js demo-examples

test: test-python test-rust test-js

test-python: dev-deps protos
	@echo "[python] Running unit tests..."
	@$(PYTHON) -m pytest -q sdks/py_sdk/tests

test-rust:
	@set -e; \
	if command -v protoc >/dev/null 2>&1; then \
	  echo "[rust] Running cargo tests..."; \
	  (cd sdks/rust_sdk && PROTO_DIR=$(CURDIR)/protos cargo test --all --locked --color=always); \
	else \
	  echo "[rust] protoc not found. Install protobuf-compiler to run Rust tests."; \
	  exit 2; \
	fi

test-js:
	@set -e; \
	if command -v node >/dev/null 2>&1; then \
	  echo "[js] Running JS tests..."; \
	  cd sdks/js_sdk; \
	  if [ ! -d node_modules ]; then \
	    if [ -n "$$NO_NPM_INSTALL" ]; then \
	      echo "[js] node_modules missing and NO_NPM_INSTALL set; skipping npm ci"; \
	    else \
	      npm ci; \
	    fi; \
	  fi; \
    npm run build; \
    npm test --silent -- --run; \
	else \
	  echo "[js] Node.js not found. Install Node >= 20 to run JS tests."; \
	  exit 3; \
	fi

# Run JS ACK demo examples that exercise Router + ACK flow
demo-examples:
	@set -e; \
	if ! command -v node >/dev/null 2>&1; then \
	  echo "[demo] Node.js not found. Install Node >= 20 to run examples."; \
	  exit 3; \
	fi; \
	if [ ! -d sdks/js_sdk/node_modules ]; then \
	  if [ -n "$$NO_NPM_INSTALL" ]; then \
	    echo "[demo] sdks/js_sdk/node_modules missing and NO_NPM_INSTALL set; aborting."; \
	    exit 4; \
	  else \
	    echo "[demo] Installing JS SDK deps..."; \
	    (cd sdks/js_sdk && npm ci); \
	  fi; \
	fi; \
	echo "[demo] Running ACK demo via examples/sdk-usage/run_all.sh"; \
	bash examples/sdk-usage/run_all.sh ack-demo
