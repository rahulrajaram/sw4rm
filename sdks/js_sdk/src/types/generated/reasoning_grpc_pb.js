// GENERATED CODE -- DO NOT EDIT!

'use strict';
var grpc = require('@grpc/grpc-js');
var reasoning_pb = require('./reasoning_pb.js');

function serialize_sw4rm_reasoning_DebateEvaluateRequest(arg) {
  if (!(arg instanceof reasoning_pb.DebateEvaluateRequest)) {
    throw new Error('Expected argument of type sw4rm.reasoning.DebateEvaluateRequest');
  }
  return Buffer.from(arg.serializeBinary());
}

function deserialize_sw4rm_reasoning_DebateEvaluateRequest(buffer_arg) {
  return reasoning_pb.DebateEvaluateRequest.deserializeBinary(new Uint8Array(buffer_arg));
}

function serialize_sw4rm_reasoning_DebateEvaluateResponse(arg) {
  if (!(arg instanceof reasoning_pb.DebateEvaluateResponse)) {
    throw new Error('Expected argument of type sw4rm.reasoning.DebateEvaluateResponse');
  }
  return Buffer.from(arg.serializeBinary());
}

function deserialize_sw4rm_reasoning_DebateEvaluateResponse(buffer_arg) {
  return reasoning_pb.DebateEvaluateResponse.deserializeBinary(new Uint8Array(buffer_arg));
}

function serialize_sw4rm_reasoning_ParallelismCheckRequest(arg) {
  if (!(arg instanceof reasoning_pb.ParallelismCheckRequest)) {
    throw new Error('Expected argument of type sw4rm.reasoning.ParallelismCheckRequest');
  }
  return Buffer.from(arg.serializeBinary());
}

function deserialize_sw4rm_reasoning_ParallelismCheckRequest(buffer_arg) {
  return reasoning_pb.ParallelismCheckRequest.deserializeBinary(new Uint8Array(buffer_arg));
}

function serialize_sw4rm_reasoning_ParallelismCheckResponse(arg) {
  if (!(arg instanceof reasoning_pb.ParallelismCheckResponse)) {
    throw new Error('Expected argument of type sw4rm.reasoning.ParallelismCheckResponse');
  }
  return Buffer.from(arg.serializeBinary());
}

function deserialize_sw4rm_reasoning_ParallelismCheckResponse(buffer_arg) {
  return reasoning_pb.ParallelismCheckResponse.deserializeBinary(new Uint8Array(buffer_arg));
}

function serialize_sw4rm_reasoning_SummarizeRequest(arg) {
  if (!(arg instanceof reasoning_pb.SummarizeRequest)) {
    throw new Error('Expected argument of type sw4rm.reasoning.SummarizeRequest');
  }
  return Buffer.from(arg.serializeBinary());
}

function deserialize_sw4rm_reasoning_SummarizeRequest(buffer_arg) {
  return reasoning_pb.SummarizeRequest.deserializeBinary(new Uint8Array(buffer_arg));
}

function serialize_sw4rm_reasoning_SummarizeResponse(arg) {
  if (!(arg instanceof reasoning_pb.SummarizeResponse)) {
    throw new Error('Expected argument of type sw4rm.reasoning.SummarizeResponse');
  }
  return Buffer.from(arg.serializeBinary());
}

function deserialize_sw4rm_reasoning_SummarizeResponse(buffer_arg) {
  return reasoning_pb.SummarizeResponse.deserializeBinary(new Uint8Array(buffer_arg));
}


var ReasoningProxyService = exports.ReasoningProxyService = {
  checkParallelism: {
    path: '/sw4rm.reasoning.ReasoningProxy/CheckParallelism',
    requestStream: false,
    responseStream: false,
    requestType: reasoning_pb.ParallelismCheckRequest,
    responseType: reasoning_pb.ParallelismCheckResponse,
    requestSerialize: serialize_sw4rm_reasoning_ParallelismCheckRequest,
    requestDeserialize: deserialize_sw4rm_reasoning_ParallelismCheckRequest,
    responseSerialize: serialize_sw4rm_reasoning_ParallelismCheckResponse,
    responseDeserialize: deserialize_sw4rm_reasoning_ParallelismCheckResponse,
  },
  evaluateDebate: {
    path: '/sw4rm.reasoning.ReasoningProxy/EvaluateDebate',
    requestStream: false,
    responseStream: false,
    requestType: reasoning_pb.DebateEvaluateRequest,
    responseType: reasoning_pb.DebateEvaluateResponse,
    requestSerialize: serialize_sw4rm_reasoning_DebateEvaluateRequest,
    requestDeserialize: deserialize_sw4rm_reasoning_DebateEvaluateRequest,
    responseSerialize: serialize_sw4rm_reasoning_DebateEvaluateResponse,
    responseDeserialize: deserialize_sw4rm_reasoning_DebateEvaluateResponse,
  },
  summarize: {
    path: '/sw4rm.reasoning.ReasoningProxy/Summarize',
    requestStream: false,
    responseStream: false,
    requestType: reasoning_pb.SummarizeRequest,
    responseType: reasoning_pb.SummarizeResponse,
    requestSerialize: serialize_sw4rm_reasoning_SummarizeRequest,
    requestDeserialize: deserialize_sw4rm_reasoning_SummarizeRequest,
    responseSerialize: serialize_sw4rm_reasoning_SummarizeResponse,
    responseDeserialize: deserialize_sw4rm_reasoning_SummarizeResponse,
  },
};

exports.ReasoningProxyClient = grpc.makeGenericClientConstructor(ReasoningProxyService, 'ReasoningProxy');
