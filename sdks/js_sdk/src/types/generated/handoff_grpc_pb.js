// GENERATED CODE -- DO NOT EDIT!

// Original file comments:
// SW4RM Protocol - Handoff Proto Definition
// Namespace Convention: sw4rm.{service} (e.g., sw4rm.handoff)
// See: docs/IMPLEMENTATION_PLAN.md Phase 1.1 for namespace standards.
//
'use strict';
var grpc = require('@grpc/grpc-js');
var handoff_pb = require('./handoff_pb.js');
var common_pb = require('./common_pb.js');
var google_protobuf_duration_pb = require('google-protobuf/google/protobuf/duration_pb.js');

function serialize_sw4rm_common_Empty(arg) {
  if (!(arg instanceof common_pb.Empty)) {
    throw new Error('Expected argument of type sw4rm.common.Empty');
  }
  return Buffer.from(arg.serializeBinary());
}

function deserialize_sw4rm_common_Empty(buffer_arg) {
  return common_pb.Empty.deserializeBinary(new Uint8Array(buffer_arg));
}

function serialize_sw4rm_handoff_CompleteHandoffRequest(arg) {
  if (!(arg instanceof handoff_pb.CompleteHandoffRequest)) {
    throw new Error('Expected argument of type sw4rm.handoff.CompleteHandoffRequest');
  }
  return Buffer.from(arg.serializeBinary());
}

function deserialize_sw4rm_handoff_CompleteHandoffRequest(buffer_arg) {
  return handoff_pb.CompleteHandoffRequest.deserializeBinary(new Uint8Array(buffer_arg));
}

function serialize_sw4rm_handoff_CompleteHandoffResponse(arg) {
  if (!(arg instanceof handoff_pb.CompleteHandoffResponse)) {
    throw new Error('Expected argument of type sw4rm.handoff.CompleteHandoffResponse');
  }
  return Buffer.from(arg.serializeBinary());
}

function deserialize_sw4rm_handoff_CompleteHandoffResponse(buffer_arg) {
  return handoff_pb.CompleteHandoffResponse.deserializeBinary(new Uint8Array(buffer_arg));
}

function serialize_sw4rm_handoff_GetPendingHandoffsRequest(arg) {
  if (!(arg instanceof handoff_pb.GetPendingHandoffsRequest)) {
    throw new Error('Expected argument of type sw4rm.handoff.GetPendingHandoffsRequest');
  }
  return Buffer.from(arg.serializeBinary());
}

function deserialize_sw4rm_handoff_GetPendingHandoffsRequest(buffer_arg) {
  return handoff_pb.GetPendingHandoffsRequest.deserializeBinary(new Uint8Array(buffer_arg));
}

function serialize_sw4rm_handoff_GetPendingHandoffsResponse(arg) {
  if (!(arg instanceof handoff_pb.GetPendingHandoffsResponse)) {
    throw new Error('Expected argument of type sw4rm.handoff.GetPendingHandoffsResponse');
  }
  return Buffer.from(arg.serializeBinary());
}

function deserialize_sw4rm_handoff_GetPendingHandoffsResponse(buffer_arg) {
  return handoff_pb.GetPendingHandoffsResponse.deserializeBinary(new Uint8Array(buffer_arg));
}

function serialize_sw4rm_handoff_HandoffRequest(arg) {
  if (!(arg instanceof handoff_pb.HandoffRequest)) {
    throw new Error('Expected argument of type sw4rm.handoff.HandoffRequest');
  }
  return Buffer.from(arg.serializeBinary());
}

function deserialize_sw4rm_handoff_HandoffRequest(buffer_arg) {
  return handoff_pb.HandoffRequest.deserializeBinary(new Uint8Array(buffer_arg));
}

function serialize_sw4rm_handoff_HandoffResponse(arg) {
  if (!(arg instanceof handoff_pb.HandoffResponse)) {
    throw new Error('Expected argument of type sw4rm.handoff.HandoffResponse');
  }
  return Buffer.from(arg.serializeBinary());
}

function deserialize_sw4rm_handoff_HandoffResponse(buffer_arg) {
  return handoff_pb.HandoffResponse.deserializeBinary(new Uint8Array(buffer_arg));
}


var HandoffServiceService = exports.HandoffServiceService = {
  requestHandoff: {
    path: '/sw4rm.handoff.HandoffService/RequestHandoff',
    requestStream: false,
    responseStream: false,
    requestType: handoff_pb.HandoffRequest,
    responseType: common_pb.Empty,
    requestSerialize: serialize_sw4rm_handoff_HandoffRequest,
    requestDeserialize: deserialize_sw4rm_handoff_HandoffRequest,
    responseSerialize: serialize_sw4rm_common_Empty,
    responseDeserialize: deserialize_sw4rm_common_Empty,
  },
  acceptHandoff: {
    path: '/sw4rm.handoff.HandoffService/AcceptHandoff',
    requestStream: false,
    responseStream: false,
    requestType: handoff_pb.HandoffResponse,
    responseType: common_pb.Empty,
    requestSerialize: serialize_sw4rm_handoff_HandoffResponse,
    requestDeserialize: deserialize_sw4rm_handoff_HandoffResponse,
    responseSerialize: serialize_sw4rm_common_Empty,
    responseDeserialize: deserialize_sw4rm_common_Empty,
  },
  rejectHandoff: {
    path: '/sw4rm.handoff.HandoffService/RejectHandoff',
    requestStream: false,
    responseStream: false,
    requestType: handoff_pb.HandoffResponse,
    responseType: common_pb.Empty,
    requestSerialize: serialize_sw4rm_handoff_HandoffResponse,
    requestDeserialize: deserialize_sw4rm_handoff_HandoffResponse,
    responseSerialize: serialize_sw4rm_common_Empty,
    responseDeserialize: deserialize_sw4rm_common_Empty,
  },
  getPendingHandoffs: {
    path: '/sw4rm.handoff.HandoffService/GetPendingHandoffs',
    requestStream: false,
    responseStream: false,
    requestType: handoff_pb.GetPendingHandoffsRequest,
    responseType: handoff_pb.GetPendingHandoffsResponse,
    requestSerialize: serialize_sw4rm_handoff_GetPendingHandoffsRequest,
    requestDeserialize: deserialize_sw4rm_handoff_GetPendingHandoffsRequest,
    responseSerialize: serialize_sw4rm_handoff_GetPendingHandoffsResponse,
    responseDeserialize: deserialize_sw4rm_handoff_GetPendingHandoffsResponse,
  },
  completeHandoff: {
    path: '/sw4rm.handoff.HandoffService/CompleteHandoff',
    requestStream: false,
    responseStream: false,
    requestType: handoff_pb.CompleteHandoffRequest,
    responseType: handoff_pb.CompleteHandoffResponse,
    requestSerialize: serialize_sw4rm_handoff_CompleteHandoffRequest,
    requestDeserialize: deserialize_sw4rm_handoff_CompleteHandoffRequest,
    responseSerialize: serialize_sw4rm_handoff_CompleteHandoffResponse,
    responseDeserialize: deserialize_sw4rm_handoff_CompleteHandoffResponse,
  },
};

exports.HandoffServiceClient = grpc.makeGenericClientConstructor(HandoffServiceService, 'HandoffService');
