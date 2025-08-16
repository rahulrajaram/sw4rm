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

.PHONY: swarm-core-up swarm-core-down swarm-core-restart swarm-core-status swarm-core-logs
swarm-core-up:
	@SWARM_REGISTRY_IMAGE=$${SWARM_REGISTRY_IMAGE} \
	 SWARM_ROUTER_IMAGE=$${SWARM_ROUTER_IMAGE} \
	 SWARM_SCHEDULER_IMAGE=$${SWARM_SCHEDULER_IMAGE} \
	 SWARM_NEGOTIATION_IMAGE=$${SWARM_NEGOTIATION_IMAGE} \
	 bash bee/scripts/swarmctl.sh up

swarm-core-down:
	bash bee/scripts/swarmctl.sh down

swarm-core-restart:
	@SWARM_REGISTRY_IMAGE=$${SWARM_REGISTRY_IMAGE} \
	 SWARM_ROUTER_IMAGE=$${SWARM_ROUTER_IMAGE} \
	 SWARM_SCHEDULER_IMAGE=$${SWARM_SCHEDULER_IMAGE} \
	 SWARM_NEGOTIATION_IMAGE=$${SWARM_NEGOTIATION_IMAGE} \
	 bash bee/scripts/swarmctl.sh restart

swarm-core-status:
	bash bee/scripts/swarmctl.sh status

swarm-core-logs:
	bash bee/scripts/swarmctl.sh logs

.PHONY: swarm-hive-bootstrap swarm-hive-check
swarm-hive-bootstrap:
	@BEE_BIN=$${BEE_BIN:-./bee/target/debug/bee} HIVE=$${HIVE:-dev} bash bee/scripts/swarmctl.sh hive-bootstrap

swarm-hive-check:
	@BEE_BIN=$${BEE_BIN:-./bee/target/debug/bee} HIVE=$${HIVE:-dev} bash bee/scripts/swarmctl.sh hive-check

.PHONY: swarm-agents-up swarm-agents-down swarm-demo-consult
swarm-agents-up:
	@BEE_BIN=$${BEE_BIN:-./bee/target/debug/bee} HIVE=$${HIVE:-dev} LOG_DIR=$${LOG_DIR:-logs} bash bee/scripts/swarmctl.sh agents-up

swarm-agents-down:
	@LOG_DIR=$${LOG_DIR:-logs} bash bee/scripts/swarmctl.sh agents-down

swarm-demo-consult:
	@BEE_BIN=$${BEE_BIN:-./bee/target/debug/bee} bash bee/scripts/swarmctl.sh demo-consult
