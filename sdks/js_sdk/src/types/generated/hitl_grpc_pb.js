// GENERATED CODE -- DO NOT EDIT!

'use strict';
var grpc = require('@grpc/grpc-js');
var hitl_pb = require('./hitl_pb.js');
var common_pb = require('./common_pb.js');

function serialize_sw4rm_hitl_HitlDecision(arg) {
  if (!(arg instanceof hitl_pb.HitlDecision)) {
    throw new Error('Expected argument of type sw4rm.hitl.HitlDecision');
  }
  return Buffer.from(arg.serializeBinary());
}

function deserialize_sw4rm_hitl_HitlDecision(buffer_arg) {
  return hitl_pb.HitlDecision.deserializeBinary(new Uint8Array(buffer_arg));
}

function serialize_sw4rm_hitl_HitlInvocation(arg) {
  if (!(arg instanceof hitl_pb.HitlInvocation)) {
    throw new Error('Expected argument of type sw4rm.hitl.HitlInvocation');
  }
  return Buffer.from(arg.serializeBinary());
}

function deserialize_sw4rm_hitl_HitlInvocation(buffer_arg) {
  return hitl_pb.HitlInvocation.deserializeBinary(new Uint8Array(buffer_arg));
}


var HitlServiceService = exports.HitlServiceService = {
  // Invocation is carried in Envelope.payload; this service handles the decision side.
decide: {
    path: '/sw4rm.hitl.HitlService/Decide',
    requestStream: false,
    responseStream: false,
    requestType: hitl_pb.HitlInvocation,
    responseType: hitl_pb.HitlDecision,
    requestSerialize: serialize_sw4rm_hitl_HitlInvocation,
    requestDeserialize: deserialize_sw4rm_hitl_HitlInvocation,
    responseSerialize: serialize_sw4rm_hitl_HitlDecision,
    responseDeserialize: deserialize_sw4rm_hitl_HitlDecision,
  },
};

exports.HitlServiceClient = grpc.makeGenericClientConstructor(HitlServiceService, 'HitlService');
