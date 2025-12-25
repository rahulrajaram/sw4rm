// GENERATED CODE -- DO NOT EDIT!

// Original file comments:
// SW4RM Protocol - Negotiation Room Proto Definition
// Namespace Convention: sw4rm.{service} (e.g., sw4rm.negotiation_room)
// See: docs/IMPLEMENTATION_PLAN.md Phase 1.1 for namespace standards.
//
'use strict';
var grpc = require('@grpc/grpc-js');
var negotiation_room_pb = require('./negotiation_room_pb.js');
var google_protobuf_timestamp_pb = require('google-protobuf/google/protobuf/timestamp_pb.js');

function serialize_sw4rm_negotiation_room_GetDecisionRequest(arg) {
  if (!(arg instanceof negotiation_room_pb.GetDecisionRequest)) {
    throw new Error('Expected argument of type sw4rm.negotiation_room.GetDecisionRequest');
  }
  return Buffer.from(arg.serializeBinary());
}

function deserialize_sw4rm_negotiation_room_GetDecisionRequest(buffer_arg) {
  return negotiation_room_pb.GetDecisionRequest.deserializeBinary(new Uint8Array(buffer_arg));
}

function serialize_sw4rm_negotiation_room_GetDecisionResponse(arg) {
  if (!(arg instanceof negotiation_room_pb.GetDecisionResponse)) {
    throw new Error('Expected argument of type sw4rm.negotiation_room.GetDecisionResponse');
  }
  return Buffer.from(arg.serializeBinary());
}

function deserialize_sw4rm_negotiation_room_GetDecisionResponse(buffer_arg) {
  return negotiation_room_pb.GetDecisionResponse.deserializeBinary(new Uint8Array(buffer_arg));
}

function serialize_sw4rm_negotiation_room_GetVotesRequest(arg) {
  if (!(arg instanceof negotiation_room_pb.GetVotesRequest)) {
    throw new Error('Expected argument of type sw4rm.negotiation_room.GetVotesRequest');
  }
  return Buffer.from(arg.serializeBinary());
}

function deserialize_sw4rm_negotiation_room_GetVotesRequest(buffer_arg) {
  return negotiation_room_pb.GetVotesRequest.deserializeBinary(new Uint8Array(buffer_arg));
}

function serialize_sw4rm_negotiation_room_GetVotesResponse(arg) {
  if (!(arg instanceof negotiation_room_pb.GetVotesResponse)) {
    throw new Error('Expected argument of type sw4rm.negotiation_room.GetVotesResponse');
  }
  return Buffer.from(arg.serializeBinary());
}

function deserialize_sw4rm_negotiation_room_GetVotesResponse(buffer_arg) {
  return negotiation_room_pb.GetVotesResponse.deserializeBinary(new Uint8Array(buffer_arg));
}

function serialize_sw4rm_negotiation_room_SubmitProposalRequest(arg) {
  if (!(arg instanceof negotiation_room_pb.SubmitProposalRequest)) {
    throw new Error('Expected argument of type sw4rm.negotiation_room.SubmitProposalRequest');
  }
  return Buffer.from(arg.serializeBinary());
}

function deserialize_sw4rm_negotiation_room_SubmitProposalRequest(buffer_arg) {
  return negotiation_room_pb.SubmitProposalRequest.deserializeBinary(new Uint8Array(buffer_arg));
}

function serialize_sw4rm_negotiation_room_SubmitProposalResponse(arg) {
  if (!(arg instanceof negotiation_room_pb.SubmitProposalResponse)) {
    throw new Error('Expected argument of type sw4rm.negotiation_room.SubmitProposalResponse');
  }
  return Buffer.from(arg.serializeBinary());
}

function deserialize_sw4rm_negotiation_room_SubmitProposalResponse(buffer_arg) {
  return negotiation_room_pb.SubmitProposalResponse.deserializeBinary(new Uint8Array(buffer_arg));
}

function serialize_sw4rm_negotiation_room_SubmitVoteRequest(arg) {
  if (!(arg instanceof negotiation_room_pb.SubmitVoteRequest)) {
    throw new Error('Expected argument of type sw4rm.negotiation_room.SubmitVoteRequest');
  }
  return Buffer.from(arg.serializeBinary());
}

function deserialize_sw4rm_negotiation_room_SubmitVoteRequest(buffer_arg) {
  return negotiation_room_pb.SubmitVoteRequest.deserializeBinary(new Uint8Array(buffer_arg));
}

function serialize_sw4rm_negotiation_room_SubmitVoteResponse(arg) {
  if (!(arg instanceof negotiation_room_pb.SubmitVoteResponse)) {
    throw new Error('Expected argument of type sw4rm.negotiation_room.SubmitVoteResponse');
  }
  return Buffer.from(arg.serializeBinary());
}

function deserialize_sw4rm_negotiation_room_SubmitVoteResponse(buffer_arg) {
  return negotiation_room_pb.SubmitVoteResponse.deserializeBinary(new Uint8Array(buffer_arg));
}

function serialize_sw4rm_negotiation_room_WaitForDecisionRequest(arg) {
  if (!(arg instanceof negotiation_room_pb.WaitForDecisionRequest)) {
    throw new Error('Expected argument of type sw4rm.negotiation_room.WaitForDecisionRequest');
  }
  return Buffer.from(arg.serializeBinary());
}

function deserialize_sw4rm_negotiation_room_WaitForDecisionRequest(buffer_arg) {
  return negotiation_room_pb.WaitForDecisionRequest.deserializeBinary(new Uint8Array(buffer_arg));
}

function serialize_sw4rm_negotiation_room_WaitForDecisionResponse(arg) {
  if (!(arg instanceof negotiation_room_pb.WaitForDecisionResponse)) {
    throw new Error('Expected argument of type sw4rm.negotiation_room.WaitForDecisionResponse');
  }
  return Buffer.from(arg.serializeBinary());
}

function deserialize_sw4rm_negotiation_room_WaitForDecisionResponse(buffer_arg) {
  return negotiation_room_pb.WaitForDecisionResponse.deserializeBinary(new Uint8Array(buffer_arg));
}


// NegotiationRoomService provides RPC endpoints for the Negotiation Room pattern
// enabling multi-agent artifact approval workflows
var NegotiationRoomServiceService = exports.NegotiationRoomServiceService = {
  // SubmitProposal allows a producer agent to submit an artifact for review
submitProposal: {
    path: '/sw4rm.negotiation_room.NegotiationRoomService/SubmitProposal',
    requestStream: false,
    responseStream: false,
    requestType: negotiation_room_pb.SubmitProposalRequest,
    responseType: negotiation_room_pb.SubmitProposalResponse,
    requestSerialize: serialize_sw4rm_negotiation_room_SubmitProposalRequest,
    requestDeserialize: deserialize_sw4rm_negotiation_room_SubmitProposalRequest,
    responseSerialize: serialize_sw4rm_negotiation_room_SubmitProposalResponse,
    responseDeserialize: deserialize_sw4rm_negotiation_room_SubmitProposalResponse,
  },
  // SubmitVote allows a critic agent to submit their evaluation of an artifact
submitVote: {
    path: '/sw4rm.negotiation_room.NegotiationRoomService/SubmitVote',
    requestStream: false,
    responseStream: false,
    requestType: negotiation_room_pb.SubmitVoteRequest,
    responseType: negotiation_room_pb.SubmitVoteResponse,
    requestSerialize: serialize_sw4rm_negotiation_room_SubmitVoteRequest,
    requestDeserialize: deserialize_sw4rm_negotiation_room_SubmitVoteRequest,
    responseSerialize: serialize_sw4rm_negotiation_room_SubmitVoteResponse,
    responseDeserialize: deserialize_sw4rm_negotiation_room_SubmitVoteResponse,
  },
  // GetVotes retrieves all votes submitted for a specific artifact
getVotes: {
    path: '/sw4rm.negotiation_room.NegotiationRoomService/GetVotes',
    requestStream: false,
    responseStream: false,
    requestType: negotiation_room_pb.GetVotesRequest,
    responseType: negotiation_room_pb.GetVotesResponse,
    requestSerialize: serialize_sw4rm_negotiation_room_GetVotesRequest,
    requestDeserialize: deserialize_sw4rm_negotiation_room_GetVotesRequest,
    responseSerialize: serialize_sw4rm_negotiation_room_GetVotesResponse,
    responseDeserialize: deserialize_sw4rm_negotiation_room_GetVotesResponse,
  },
  // GetDecision retrieves the final decision for an artifact (non-blocking)
getDecision: {
    path: '/sw4rm.negotiation_room.NegotiationRoomService/GetDecision',
    requestStream: false,
    responseStream: false,
    requestType: negotiation_room_pb.GetDecisionRequest,
    responseType: negotiation_room_pb.GetDecisionResponse,
    requestSerialize: serialize_sw4rm_negotiation_room_GetDecisionRequest,
    requestDeserialize: deserialize_sw4rm_negotiation_room_GetDecisionRequest,
    responseSerialize: serialize_sw4rm_negotiation_room_GetDecisionResponse,
    responseDeserialize: deserialize_sw4rm_negotiation_room_GetDecisionResponse,
  },
  // WaitForDecision blocks until a decision is made for an artifact
waitForDecision: {
    path: '/sw4rm.negotiation_room.NegotiationRoomService/WaitForDecision',
    requestStream: false,
    responseStream: false,
    requestType: negotiation_room_pb.WaitForDecisionRequest,
    responseType: negotiation_room_pb.WaitForDecisionResponse,
    requestSerialize: serialize_sw4rm_negotiation_room_WaitForDecisionRequest,
    requestDeserialize: deserialize_sw4rm_negotiation_room_WaitForDecisionRequest,
    responseSerialize: serialize_sw4rm_negotiation_room_WaitForDecisionResponse,
    responseDeserialize: deserialize_sw4rm_negotiation_room_WaitForDecisionResponse,
  },
};

exports.NegotiationRoomServiceClient = grpc.makeGenericClientConstructor(NegotiationRoomServiceService, 'NegotiationRoomService');
