// GENERATED CODE -- DO NOT EDIT!

// Original file comments:
// SW4RM Protocol - Workflow Proto Definition
// Namespace Convention: sw4rm.{service} (e.g., sw4rm.workflow)
// See: docs/IMPLEMENTATION_PLAN.md Phase 1.1 for namespace standards.
//
'use strict';
var grpc = require('@grpc/grpc-js');
var workflow_pb = require('./workflow_pb.js');
var google_protobuf_timestamp_pb = require('google-protobuf/google/protobuf/timestamp_pb.js');

function serialize_sw4rm_workflow_CreateWorkflowRequest(arg) {
  if (!(arg instanceof workflow_pb.CreateWorkflowRequest)) {
    throw new Error('Expected argument of type sw4rm.workflow.CreateWorkflowRequest');
  }
  return Buffer.from(arg.serializeBinary());
}

function deserialize_sw4rm_workflow_CreateWorkflowRequest(buffer_arg) {
  return workflow_pb.CreateWorkflowRequest.deserializeBinary(new Uint8Array(buffer_arg));
}

function serialize_sw4rm_workflow_CreateWorkflowResponse(arg) {
  if (!(arg instanceof workflow_pb.CreateWorkflowResponse)) {
    throw new Error('Expected argument of type sw4rm.workflow.CreateWorkflowResponse');
  }
  return Buffer.from(arg.serializeBinary());
}

function deserialize_sw4rm_workflow_CreateWorkflowResponse(buffer_arg) {
  return workflow_pb.CreateWorkflowResponse.deserializeBinary(new Uint8Array(buffer_arg));
}

function serialize_sw4rm_workflow_GetWorkflowStateRequest(arg) {
  if (!(arg instanceof workflow_pb.GetWorkflowStateRequest)) {
    throw new Error('Expected argument of type sw4rm.workflow.GetWorkflowStateRequest');
  }
  return Buffer.from(arg.serializeBinary());
}

function deserialize_sw4rm_workflow_GetWorkflowStateRequest(buffer_arg) {
  return workflow_pb.GetWorkflowStateRequest.deserializeBinary(new Uint8Array(buffer_arg));
}

function serialize_sw4rm_workflow_GetWorkflowStateResponse(arg) {
  if (!(arg instanceof workflow_pb.GetWorkflowStateResponse)) {
    throw new Error('Expected argument of type sw4rm.workflow.GetWorkflowStateResponse');
  }
  return Buffer.from(arg.serializeBinary());
}

function deserialize_sw4rm_workflow_GetWorkflowStateResponse(buffer_arg) {
  return workflow_pb.GetWorkflowStateResponse.deserializeBinary(new Uint8Array(buffer_arg));
}

function serialize_sw4rm_workflow_ResumeWorkflowRequest(arg) {
  if (!(arg instanceof workflow_pb.ResumeWorkflowRequest)) {
    throw new Error('Expected argument of type sw4rm.workflow.ResumeWorkflowRequest');
  }
  return Buffer.from(arg.serializeBinary());
}

function deserialize_sw4rm_workflow_ResumeWorkflowRequest(buffer_arg) {
  return workflow_pb.ResumeWorkflowRequest.deserializeBinary(new Uint8Array(buffer_arg));
}

function serialize_sw4rm_workflow_ResumeWorkflowResponse(arg) {
  if (!(arg instanceof workflow_pb.ResumeWorkflowResponse)) {
    throw new Error('Expected argument of type sw4rm.workflow.ResumeWorkflowResponse');
  }
  return Buffer.from(arg.serializeBinary());
}

function deserialize_sw4rm_workflow_ResumeWorkflowResponse(buffer_arg) {
  return workflow_pb.ResumeWorkflowResponse.deserializeBinary(new Uint8Array(buffer_arg));
}

function serialize_sw4rm_workflow_StartWorkflowRequest(arg) {
  if (!(arg instanceof workflow_pb.StartWorkflowRequest)) {
    throw new Error('Expected argument of type sw4rm.workflow.StartWorkflowRequest');
  }
  return Buffer.from(arg.serializeBinary());
}

function deserialize_sw4rm_workflow_StartWorkflowRequest(buffer_arg) {
  return workflow_pb.StartWorkflowRequest.deserializeBinary(new Uint8Array(buffer_arg));
}

function serialize_sw4rm_workflow_StartWorkflowResponse(arg) {
  if (!(arg instanceof workflow_pb.StartWorkflowResponse)) {
    throw new Error('Expected argument of type sw4rm.workflow.StartWorkflowResponse');
  }
  return Buffer.from(arg.serializeBinary());
}

function deserialize_sw4rm_workflow_StartWorkflowResponse(buffer_arg) {
  return workflow_pb.StartWorkflowResponse.deserializeBinary(new Uint8Array(buffer_arg));
}


var WorkflowServiceService = exports.WorkflowServiceService = {
  createWorkflow: {
    path: '/sw4rm.workflow.WorkflowService/CreateWorkflow',
    requestStream: false,
    responseStream: false,
    requestType: workflow_pb.CreateWorkflowRequest,
    responseType: workflow_pb.CreateWorkflowResponse,
    requestSerialize: serialize_sw4rm_workflow_CreateWorkflowRequest,
    requestDeserialize: deserialize_sw4rm_workflow_CreateWorkflowRequest,
    responseSerialize: serialize_sw4rm_workflow_CreateWorkflowResponse,
    responseDeserialize: deserialize_sw4rm_workflow_CreateWorkflowResponse,
  },
  startWorkflow: {
    path: '/sw4rm.workflow.WorkflowService/StartWorkflow',
    requestStream: false,
    responseStream: false,
    requestType: workflow_pb.StartWorkflowRequest,
    responseType: workflow_pb.StartWorkflowResponse,
    requestSerialize: serialize_sw4rm_workflow_StartWorkflowRequest,
    requestDeserialize: deserialize_sw4rm_workflow_StartWorkflowRequest,
    responseSerialize: serialize_sw4rm_workflow_StartWorkflowResponse,
    responseDeserialize: deserialize_sw4rm_workflow_StartWorkflowResponse,
  },
  getWorkflowState: {
    path: '/sw4rm.workflow.WorkflowService/GetWorkflowState',
    requestStream: false,
    responseStream: false,
    requestType: workflow_pb.GetWorkflowStateRequest,
    responseType: workflow_pb.GetWorkflowStateResponse,
    requestSerialize: serialize_sw4rm_workflow_GetWorkflowStateRequest,
    requestDeserialize: deserialize_sw4rm_workflow_GetWorkflowStateRequest,
    responseSerialize: serialize_sw4rm_workflow_GetWorkflowStateResponse,
    responseDeserialize: deserialize_sw4rm_workflow_GetWorkflowStateResponse,
  },
  resumeWorkflow: {
    path: '/sw4rm.workflow.WorkflowService/ResumeWorkflow',
    requestStream: false,
    responseStream: false,
    requestType: workflow_pb.ResumeWorkflowRequest,
    responseType: workflow_pb.ResumeWorkflowResponse,
    requestSerialize: serialize_sw4rm_workflow_ResumeWorkflowRequest,
    requestDeserialize: deserialize_sw4rm_workflow_ResumeWorkflowRequest,
    responseSerialize: serialize_sw4rm_workflow_ResumeWorkflowResponse,
    responseDeserialize: deserialize_sw4rm_workflow_ResumeWorkflowResponse,
  },
};

exports.WorkflowServiceClient = grpc.makeGenericClientConstructor(WorkflowServiceService, 'WorkflowService');
