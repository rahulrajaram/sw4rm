PY_OUT=py_sdk/agentos/protos
PROTOS=common.proto registry.proto router.proto scheduler.proto hitl.proto \
  worktree.proto tool.proto connector.proto negotiation.proto reasoning.proto logging.proto

.PHONY: protos
$(PY_OUT):
	mkdir -p $(PY_OUT)

protos: $(PY_OUT)
	python -m grpc_tools.protoc -I. --python_out=$(PY_OUT) --grpc_python_out=$(PY_OUT) $(PROTOS)
