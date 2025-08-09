VENV=venv
PYTHON := $(VENV)/bin/python
PIP := $(VENV)/bin/pip
PY_OUT=py_sdk/sw4rm/protos
PROTOS=common.proto registry.proto router.proto scheduler.proto hitl.proto \
  worktree.proto tool.proto connector.proto negotiation.proto reasoning.proto logging.proto

.PHONY: protos
$(PY_OUT):
	mkdir -p $(PY_OUT)

protos: $(PY_OUT)
	@inc=$$($(PYTHON) -c "import sys; \
	try: \
	    import pkg_resources, grpc_tools; \
	    print(pkg_resources.resource_filename('grpc_tools', '_proto')); \
	except: \
	    pass"); \
	if [ -n "$$inc" ]; then \
	  $(PYTHON) -m grpc_tools.protoc -I. -I"$$inc" --python_out=$(PY_OUT) --grpc_python_out=$(PY_OUT) --pyi_out=$(PY_OUT) $(PROTOS); \
	else \
	  $(PYTHON) -m grpc_tools.protoc -I. --python_out=$(PY_OUT) --grpc_python_out=$(PY_OUT) --pyi_out=$(PY_OUT) $(PROTOS); \
	fi
	@echo "Fixing relative imports..."
	@cd $(PY_OUT) && sed -i 's/^import \(.*_pb2\)/from . import \1/' *_pb2.py *_pb2_grpc.py

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
	$(PYTHON) -m mkdocs serve

# Add dev-deps as an implicit prerequisite for common tasks
protos: dev-deps
smoke: dev-deps
