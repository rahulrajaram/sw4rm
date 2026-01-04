PROTO_DIR=../../protos
OUT_DIR=sw4rm/protos

.PHONY: protos clean

protos:
	python -m pip install -q grpcio grpcio-tools googleapis-common-protos
	python -m grpc_tools.protoc \
		-I$(PROTO_DIR) \
		--python_out=$(OUT_DIR) \
		--grpc_python_out=$(OUT_DIR) \
		$(PROTO_DIR)/common.proto \
		$(PROTO_DIR)/registry.proto \
		$(PROTO_DIR)/router.proto \
		$(PROTO_DIR)/scheduler.proto \
		$(PROTO_DIR)/scheduler_policy.proto \
		$(PROTO_DIR)/hitl.proto \
		$(PROTO_DIR)/worktree.proto \
		$(PROTO_DIR)/tool.proto \
		$(PROTO_DIR)/connector.proto \
		$(PROTO_DIR)/negotiation.proto \
		$(PROTO_DIR)/negotiation_room.proto \
		$(PROTO_DIR)/reasoning.proto \
		$(PROTO_DIR)/logging.proto \
		$(PROTO_DIR)/policy.proto \
		$(PROTO_DIR)/activity.proto \
		$(PROTO_DIR)/handoff.proto \
		$(PROTO_DIR)/workflow.proto

clean:
	rm -f $(OUT_DIR)/*_pb2.py $(OUT_DIR)/*_pb2_grpc.py $(OUT_DIR)/*_pb2.pyi

