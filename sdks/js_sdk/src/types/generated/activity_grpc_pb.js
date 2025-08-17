// GENERATED CODE -- DO NOT EDIT!

'use strict';
var grpc = require('@grpc/grpc-js');
var activity_pb = require('./activity_pb.js');

function serialize_sw4rm_activity_AppendArtifactRequest(arg) {
  if (!(arg instanceof activity_pb.AppendArtifactRequest)) {
    throw new Error('Expected argument of type sw4rm.activity.AppendArtifactRequest');
  }
  return Buffer.from(arg.serializeBinary());
}

function deserialize_sw4rm_activity_AppendArtifactRequest(buffer_arg) {
  return activity_pb.AppendArtifactRequest.deserializeBinary(new Uint8Array(buffer_arg));
}

function serialize_sw4rm_activity_AppendArtifactResponse(arg) {
  if (!(arg instanceof activity_pb.AppendArtifactResponse)) {
    throw new Error('Expected argument of type sw4rm.activity.AppendArtifactResponse');
  }
  return Buffer.from(arg.serializeBinary());
}

function deserialize_sw4rm_activity_AppendArtifactResponse(buffer_arg) {
  return activity_pb.AppendArtifactResponse.deserializeBinary(new Uint8Array(buffer_arg));
}

function serialize_sw4rm_activity_ListArtifactsRequest(arg) {
  if (!(arg instanceof activity_pb.ListArtifactsRequest)) {
    throw new Error('Expected argument of type sw4rm.activity.ListArtifactsRequest');
  }
  return Buffer.from(arg.serializeBinary());
}

function deserialize_sw4rm_activity_ListArtifactsRequest(buffer_arg) {
  return activity_pb.ListArtifactsRequest.deserializeBinary(new Uint8Array(buffer_arg));
}

function serialize_sw4rm_activity_ListArtifactsResponse(arg) {
  if (!(arg instanceof activity_pb.ListArtifactsResponse)) {
    throw new Error('Expected argument of type sw4rm.activity.ListArtifactsResponse');
  }
  return Buffer.from(arg.serializeBinary());
}

function deserialize_sw4rm_activity_ListArtifactsResponse(buffer_arg) {
  return activity_pb.ListArtifactsResponse.deserializeBinary(new Uint8Array(buffer_arg));
}


var ActivityServiceService = exports.ActivityServiceService = {
  appendArtifact: {
    path: '/sw4rm.activity.ActivityService/AppendArtifact',
    requestStream: false,
    responseStream: false,
    requestType: activity_pb.AppendArtifactRequest,
    responseType: activity_pb.AppendArtifactResponse,
    requestSerialize: serialize_sw4rm_activity_AppendArtifactRequest,
    requestDeserialize: deserialize_sw4rm_activity_AppendArtifactRequest,
    responseSerialize: serialize_sw4rm_activity_AppendArtifactResponse,
    responseDeserialize: deserialize_sw4rm_activity_AppendArtifactResponse,
  },
  listArtifacts: {
    path: '/sw4rm.activity.ActivityService/ListArtifacts',
    requestStream: false,
    responseStream: false,
    requestType: activity_pb.ListArtifactsRequest,
    responseType: activity_pb.ListArtifactsResponse,
    requestSerialize: serialize_sw4rm_activity_ListArtifactsRequest,
    requestDeserialize: deserialize_sw4rm_activity_ListArtifactsRequest,
    responseSerialize: serialize_sw4rm_activity_ListArtifactsResponse,
    responseDeserialize: deserialize_sw4rm_activity_ListArtifactsResponse,
  },
};

exports.ActivityServiceClient = grpc.makeGenericClientConstructor(ActivityServiceService, 'ActivityService');
