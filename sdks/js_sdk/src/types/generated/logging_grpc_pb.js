// GENERATED CODE -- DO NOT EDIT!

'use strict';
var grpc = require('@grpc/grpc-js');
var logging_pb = require('./logging_pb.js');
var google_protobuf_timestamp_pb = require('google-protobuf/google/protobuf/timestamp_pb.js');

function serialize_sw4rm_logging_IngestResponse(arg) {
  if (!(arg instanceof logging_pb.IngestResponse)) {
    throw new Error('Expected argument of type sw4rm.logging.IngestResponse');
  }
  return Buffer.from(arg.serializeBinary());
}

function deserialize_sw4rm_logging_IngestResponse(buffer_arg) {
  return logging_pb.IngestResponse.deserializeBinary(new Uint8Array(buffer_arg));
}

function serialize_sw4rm_logging_LogEvent(arg) {
  if (!(arg instanceof logging_pb.LogEvent)) {
    throw new Error('Expected argument of type sw4rm.logging.LogEvent');
  }
  return Buffer.from(arg.serializeBinary());
}

function deserialize_sw4rm_logging_LogEvent(buffer_arg) {
  return logging_pb.LogEvent.deserializeBinary(new Uint8Array(buffer_arg));
}


var LoggingServiceService = exports.LoggingServiceService = {
  ingest: {
    path: '/sw4rm.logging.LoggingService/Ingest',
    requestStream: false,
    responseStream: false,
    requestType: logging_pb.LogEvent,
    responseType: logging_pb.IngestResponse,
    requestSerialize: serialize_sw4rm_logging_LogEvent,
    requestDeserialize: deserialize_sw4rm_logging_LogEvent,
    responseSerialize: serialize_sw4rm_logging_IngestResponse,
    responseDeserialize: deserialize_sw4rm_logging_IngestResponse,
  },
};

exports.LoggingServiceClient = grpc.makeGenericClientConstructor(LoggingServiceService, 'LoggingService');
