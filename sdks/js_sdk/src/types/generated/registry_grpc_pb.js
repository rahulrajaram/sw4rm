// GENERATED CODE -- DO NOT EDIT!

'use strict';
var grpc = require('@grpc/grpc-js');
var registry_pb = require('./registry_pb.js');
var google_protobuf_timestamp_pb = require('google-protobuf/google/protobuf/timestamp_pb.js');
var common_pb = require('./common_pb.js');

function serialize_sw4rm_registry_DeregisterAgentRequest(arg) {
  if (!(arg instanceof registry_pb.DeregisterAgentRequest)) {
    throw new Error('Expected argument of type sw4rm.registry.DeregisterAgentRequest');
  }
  return Buffer.from(arg.serializeBinary());
}

function deserialize_sw4rm_registry_DeregisterAgentRequest(buffer_arg) {
  return registry_pb.DeregisterAgentRequest.deserializeBinary(new Uint8Array(buffer_arg));
}

function serialize_sw4rm_registry_DeregisterAgentResponse(arg) {
  if (!(arg instanceof registry_pb.DeregisterAgentResponse)) {
    throw new Error('Expected argument of type sw4rm.registry.DeregisterAgentResponse');
  }
  return Buffer.from(arg.serializeBinary());
}

function deserialize_sw4rm_registry_DeregisterAgentResponse(buffer_arg) {
  return registry_pb.DeregisterAgentResponse.deserializeBinary(new Uint8Array(buffer_arg));
}

function serialize_sw4rm_registry_HeartbeatRequest(arg) {
  if (!(arg instanceof registry_pb.HeartbeatRequest)) {
    throw new Error('Expected argument of type sw4rm.registry.HeartbeatRequest');
  }
  return Buffer.from(arg.serializeBinary());
}

function deserialize_sw4rm_registry_HeartbeatRequest(buffer_arg) {
  return registry_pb.HeartbeatRequest.deserializeBinary(new Uint8Array(buffer_arg));
}

function serialize_sw4rm_registry_HeartbeatResponse(arg) {
  if (!(arg instanceof registry_pb.HeartbeatResponse)) {
    throw new Error('Expected argument of type sw4rm.registry.HeartbeatResponse');
  }
  return Buffer.from(arg.serializeBinary());
}

function deserialize_sw4rm_registry_HeartbeatResponse(buffer_arg) {
  return registry_pb.HeartbeatResponse.deserializeBinary(new Uint8Array(buffer_arg));
}

function serialize_sw4rm_registry_RegisterAgentRequest(arg) {
  if (!(arg instanceof registry_pb.RegisterAgentRequest)) {
    throw new Error('Expected argument of type sw4rm.registry.RegisterAgentRequest');
  }
  return Buffer.from(arg.serializeBinary());
}

function deserialize_sw4rm_registry_RegisterAgentRequest(buffer_arg) {
  return registry_pb.RegisterAgentRequest.deserializeBinary(new Uint8Array(buffer_arg));
}

function serialize_sw4rm_registry_RegisterAgentResponse(arg) {
  if (!(arg instanceof registry_pb.RegisterAgentResponse)) {
    throw new Error('Expected argument of type sw4rm.registry.RegisterAgentResponse');
  }
  return Buffer.from(arg.serializeBinary());
}

function deserialize_sw4rm_registry_RegisterAgentResponse(buffer_arg) {
  return registry_pb.RegisterAgentResponse.deserializeBinary(new Uint8Array(buffer_arg));
}


var RegistryServiceService = exports.RegistryServiceService = {
  registerAgent: {
    path: '/sw4rm.registry.RegistryService/RegisterAgent',
    requestStream: false,
    responseStream: false,
    requestType: registry_pb.RegisterAgentRequest,
    responseType: registry_pb.RegisterAgentResponse,
    requestSerialize: serialize_sw4rm_registry_RegisterAgentRequest,
    requestDeserialize: deserialize_sw4rm_registry_RegisterAgentRequest,
    responseSerialize: serialize_sw4rm_registry_RegisterAgentResponse,
    responseDeserialize: deserialize_sw4rm_registry_RegisterAgentResponse,
  },
  heartbeat: {
    path: '/sw4rm.registry.RegistryService/Heartbeat',
    requestStream: false,
    responseStream: false,
    requestType: registry_pb.HeartbeatRequest,
    responseType: registry_pb.HeartbeatResponse,
    requestSerialize: serialize_sw4rm_registry_HeartbeatRequest,
    requestDeserialize: deserialize_sw4rm_registry_HeartbeatRequest,
    responseSerialize: serialize_sw4rm_registry_HeartbeatResponse,
    responseDeserialize: deserialize_sw4rm_registry_HeartbeatResponse,
  },
  deregisterAgent: {
    path: '/sw4rm.registry.RegistryService/DeregisterAgent',
    requestStream: false,
    responseStream: false,
    requestType: registry_pb.DeregisterAgentRequest,
    responseType: registry_pb.DeregisterAgentResponse,
    requestSerialize: serialize_sw4rm_registry_DeregisterAgentRequest,
    requestDeserialize: deserialize_sw4rm_registry_DeregisterAgentRequest,
    responseSerialize: serialize_sw4rm_registry_DeregisterAgentResponse,
    responseDeserialize: deserialize_sw4rm_registry_DeregisterAgentResponse,
  },
};

exports.RegistryServiceClient = grpc.makeGenericClientConstructor(RegistryServiceService, 'RegistryService');
