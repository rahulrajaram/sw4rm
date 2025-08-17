// GENERATED CODE -- DO NOT EDIT!

'use strict';
var grpc = require('@grpc/grpc-js');
var negotiation_pb = require('./negotiation_pb.js');
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

function serialize_sw4rm_negotiation_AbortRequest(arg) {
  if (!(arg instanceof negotiation_pb.AbortRequest)) {
    throw new Error('Expected argument of type sw4rm.negotiation.AbortRequest');
  }
  return Buffer.from(arg.serializeBinary());
}

function deserialize_sw4rm_negotiation_AbortRequest(buffer_arg) {
  return negotiation_pb.AbortRequest.deserializeBinary(new Uint8Array(buffer_arg));
}

function serialize_sw4rm_negotiation_CounterProposal(arg) {
  if (!(arg instanceof negotiation_pb.CounterProposal)) {
    throw new Error('Expected argument of type sw4rm.negotiation.CounterProposal');
  }
  return Buffer.from(arg.serializeBinary());
}

function deserialize_sw4rm_negotiation_CounterProposal(buffer_arg) {
  return negotiation_pb.CounterProposal.deserializeBinary(new Uint8Array(buffer_arg));
}

function serialize_sw4rm_negotiation_Decision(arg) {
  if (!(arg instanceof negotiation_pb.Decision)) {
    throw new Error('Expected argument of type sw4rm.negotiation.Decision');
  }
  return Buffer.from(arg.serializeBinary());
}

function deserialize_sw4rm_negotiation_Decision(buffer_arg) {
  return negotiation_pb.Decision.deserializeBinary(new Uint8Array(buffer_arg));
}

function serialize_sw4rm_negotiation_Evaluation(arg) {
  if (!(arg instanceof negotiation_pb.Evaluation)) {
    throw new Error('Expected argument of type sw4rm.negotiation.Evaluation');
  }
  return Buffer.from(arg.serializeBinary());
}

function deserialize_sw4rm_negotiation_Evaluation(buffer_arg) {
  return negotiation_pb.Evaluation.deserializeBinary(new Uint8Array(buffer_arg));
}

function serialize_sw4rm_negotiation_NegotiationOpen(arg) {
  if (!(arg instanceof negotiation_pb.NegotiationOpen)) {
    throw new Error('Expected argument of type sw4rm.negotiation.NegotiationOpen');
  }
  return Buffer.from(arg.serializeBinary());
}

function deserialize_sw4rm_negotiation_NegotiationOpen(buffer_arg) {
  return negotiation_pb.NegotiationOpen.deserializeBinary(new Uint8Array(buffer_arg));
}

function serialize_sw4rm_negotiation_Proposal(arg) {
  if (!(arg instanceof negotiation_pb.Proposal)) {
    throw new Error('Expected argument of type sw4rm.negotiation.Proposal');
  }
  return Buffer.from(arg.serializeBinary());
}

function deserialize_sw4rm_negotiation_Proposal(buffer_arg) {
  return negotiation_pb.Proposal.deserializeBinary(new Uint8Array(buffer_arg));
}


var NegotiationServiceService = exports.NegotiationServiceService = {
  open: {
    path: '/sw4rm.negotiation.NegotiationService/Open',
    requestStream: false,
    responseStream: false,
    requestType: negotiation_pb.NegotiationOpen,
    responseType: common_pb.Empty,
    requestSerialize: serialize_sw4rm_negotiation_NegotiationOpen,
    requestDeserialize: deserialize_sw4rm_negotiation_NegotiationOpen,
    responseSerialize: serialize_sw4rm_common_Empty,
    responseDeserialize: deserialize_sw4rm_common_Empty,
  },
  propose: {
    path: '/sw4rm.negotiation.NegotiationService/Propose',
    requestStream: false,
    responseStream: false,
    requestType: negotiation_pb.Proposal,
    responseType: common_pb.Empty,
    requestSerialize: serialize_sw4rm_negotiation_Proposal,
    requestDeserialize: deserialize_sw4rm_negotiation_Proposal,
    responseSerialize: serialize_sw4rm_common_Empty,
    responseDeserialize: deserialize_sw4rm_common_Empty,
  },
  counter: {
    path: '/sw4rm.negotiation.NegotiationService/Counter',
    requestStream: false,
    responseStream: false,
    requestType: negotiation_pb.CounterProposal,
    responseType: common_pb.Empty,
    requestSerialize: serialize_sw4rm_negotiation_CounterProposal,
    requestDeserialize: deserialize_sw4rm_negotiation_CounterProposal,
    responseSerialize: serialize_sw4rm_common_Empty,
    responseDeserialize: deserialize_sw4rm_common_Empty,
  },
  evaluate: {
    path: '/sw4rm.negotiation.NegotiationService/Evaluate',
    requestStream: false,
    responseStream: false,
    requestType: negotiation_pb.Evaluation,
    responseType: common_pb.Empty,
    requestSerialize: serialize_sw4rm_negotiation_Evaluation,
    requestDeserialize: deserialize_sw4rm_negotiation_Evaluation,
    responseSerialize: serialize_sw4rm_common_Empty,
    responseDeserialize: deserialize_sw4rm_common_Empty,
  },
  decide: {
    path: '/sw4rm.negotiation.NegotiationService/Decide',
    requestStream: false,
    responseStream: false,
    requestType: negotiation_pb.Decision,
    responseType: common_pb.Empty,
    requestSerialize: serialize_sw4rm_negotiation_Decision,
    requestDeserialize: deserialize_sw4rm_negotiation_Decision,
    responseSerialize: serialize_sw4rm_common_Empty,
    responseDeserialize: deserialize_sw4rm_common_Empty,
  },
  abort: {
    path: '/sw4rm.negotiation.NegotiationService/Abort',
    requestStream: false,
    responseStream: false,
    requestType: negotiation_pb.AbortRequest,
    responseType: common_pb.Empty,
    requestSerialize: serialize_sw4rm_negotiation_AbortRequest,
    requestDeserialize: deserialize_sw4rm_negotiation_AbortRequest,
    responseSerialize: serialize_sw4rm_common_Empty,
    responseDeserialize: deserialize_sw4rm_common_Empty,
  },
};

exports.NegotiationServiceClient = grpc.makeGenericClientConstructor(NegotiationServiceService, 'NegotiationService');
