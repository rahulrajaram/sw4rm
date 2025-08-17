// GENERATED CODE -- DO NOT EDIT!

'use strict';
var grpc = require('@grpc/grpc-js');
var tool_pb = require('./tool_pb.js');
var google_protobuf_duration_pb = require('google-protobuf/google/protobuf/duration_pb.js');

function serialize_sw4rm_tool_ToolCall(arg) {
  if (!(arg instanceof tool_pb.ToolCall)) {
    throw new Error('Expected argument of type sw4rm.tool.ToolCall');
  }
  return Buffer.from(arg.serializeBinary());
}

function deserialize_sw4rm_tool_ToolCall(buffer_arg) {
  return tool_pb.ToolCall.deserializeBinary(new Uint8Array(buffer_arg));
}

function serialize_sw4rm_tool_ToolError(arg) {
  if (!(arg instanceof tool_pb.ToolError)) {
    throw new Error('Expected argument of type sw4rm.tool.ToolError');
  }
  return Buffer.from(arg.serializeBinary());
}

function deserialize_sw4rm_tool_ToolError(buffer_arg) {
  return tool_pb.ToolError.deserializeBinary(new Uint8Array(buffer_arg));
}

function serialize_sw4rm_tool_ToolFrame(arg) {
  if (!(arg instanceof tool_pb.ToolFrame)) {
    throw new Error('Expected argument of type sw4rm.tool.ToolFrame');
  }
  return Buffer.from(arg.serializeBinary());
}

function deserialize_sw4rm_tool_ToolFrame(buffer_arg) {
  return tool_pb.ToolFrame.deserializeBinary(new Uint8Array(buffer_arg));
}


var ToolServiceService = exports.ToolServiceService = {
  call: {
    path: '/sw4rm.tool.ToolService/Call',
    requestStream: false,
    responseStream: false,
    requestType: tool_pb.ToolCall,
    responseType: tool_pb.ToolFrame,
    requestSerialize: serialize_sw4rm_tool_ToolCall,
    requestDeserialize: deserialize_sw4rm_tool_ToolCall,
    responseSerialize: serialize_sw4rm_tool_ToolFrame,
    responseDeserialize: deserialize_sw4rm_tool_ToolFrame,
  },
  // unary completion
callStream: {
    path: '/sw4rm.tool.ToolService/CallStream',
    requestStream: false,
    responseStream: true,
    requestType: tool_pb.ToolCall,
    responseType: tool_pb.ToolFrame,
    requestSerialize: serialize_sw4rm_tool_ToolCall,
    requestDeserialize: deserialize_sw4rm_tool_ToolCall,
    responseSerialize: serialize_sw4rm_tool_ToolFrame,
    responseDeserialize: deserialize_sw4rm_tool_ToolFrame,
  },
  // streaming frames
cancel: {
    path: '/sw4rm.tool.ToolService/Cancel',
    requestStream: false,
    responseStream: false,
    requestType: tool_pb.ToolCall,
    responseType: tool_pb.ToolError,
    requestSerialize: serialize_sw4rm_tool_ToolCall,
    requestDeserialize: deserialize_sw4rm_tool_ToolCall,
    responseSerialize: serialize_sw4rm_tool_ToolError,
    responseDeserialize: deserialize_sw4rm_tool_ToolError,
  },
  // best effort
};

exports.ToolServiceClient = grpc.makeGenericClientConstructor(ToolServiceService, 'ToolService');
