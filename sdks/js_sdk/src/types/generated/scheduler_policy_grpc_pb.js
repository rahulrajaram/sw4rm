// GENERATED CODE -- DO NOT EDIT!

'use strict';
var grpc = require('@grpc/grpc-js');
var scheduler_policy_pb = require('./scheduler_policy_pb.js');
var policy_pb = require('./policy_pb.js');

function serialize_sw4rm_scheduler_GetEffectivePolicyRequest(arg) {
  if (!(arg instanceof scheduler_policy_pb.GetEffectivePolicyRequest)) {
    throw new Error('Expected argument of type sw4rm.scheduler.GetEffectivePolicyRequest');
  }
  return Buffer.from(arg.serializeBinary());
}

function deserialize_sw4rm_scheduler_GetEffectivePolicyRequest(buffer_arg) {
  return scheduler_policy_pb.GetEffectivePolicyRequest.deserializeBinary(new Uint8Array(buffer_arg));
}

function serialize_sw4rm_scheduler_GetEffectivePolicyResponse(arg) {
  if (!(arg instanceof scheduler_policy_pb.GetEffectivePolicyResponse)) {
    throw new Error('Expected argument of type sw4rm.scheduler.GetEffectivePolicyResponse');
  }
  return Buffer.from(arg.serializeBinary());
}

function deserialize_sw4rm_scheduler_GetEffectivePolicyResponse(buffer_arg) {
  return scheduler_policy_pb.GetEffectivePolicyResponse.deserializeBinary(new Uint8Array(buffer_arg));
}

function serialize_sw4rm_scheduler_GetNegotiationPolicyRequest(arg) {
  if (!(arg instanceof scheduler_policy_pb.GetNegotiationPolicyRequest)) {
    throw new Error('Expected argument of type sw4rm.scheduler.GetNegotiationPolicyRequest');
  }
  return Buffer.from(arg.serializeBinary());
}

function deserialize_sw4rm_scheduler_GetNegotiationPolicyRequest(buffer_arg) {
  return scheduler_policy_pb.GetNegotiationPolicyRequest.deserializeBinary(new Uint8Array(buffer_arg));
}

function serialize_sw4rm_scheduler_GetNegotiationPolicyResponse(arg) {
  if (!(arg instanceof scheduler_policy_pb.GetNegotiationPolicyResponse)) {
    throw new Error('Expected argument of type sw4rm.scheduler.GetNegotiationPolicyResponse');
  }
  return Buffer.from(arg.serializeBinary());
}

function deserialize_sw4rm_scheduler_GetNegotiationPolicyResponse(buffer_arg) {
  return scheduler_policy_pb.GetNegotiationPolicyResponse.deserializeBinary(new Uint8Array(buffer_arg));
}

function serialize_sw4rm_scheduler_HitlActionRequest(arg) {
  if (!(arg instanceof scheduler_policy_pb.HitlActionRequest)) {
    throw new Error('Expected argument of type sw4rm.scheduler.HitlActionRequest');
  }
  return Buffer.from(arg.serializeBinary());
}

function deserialize_sw4rm_scheduler_HitlActionRequest(buffer_arg) {
  return scheduler_policy_pb.HitlActionRequest.deserializeBinary(new Uint8Array(buffer_arg));
}

function serialize_sw4rm_scheduler_HitlActionResponse(arg) {
  if (!(arg instanceof scheduler_policy_pb.HitlActionResponse)) {
    throw new Error('Expected argument of type sw4rm.scheduler.HitlActionResponse');
  }
  return Buffer.from(arg.serializeBinary());
}

function deserialize_sw4rm_scheduler_HitlActionResponse(buffer_arg) {
  return scheduler_policy_pb.HitlActionResponse.deserializeBinary(new Uint8Array(buffer_arg));
}

function serialize_sw4rm_scheduler_ListPolicyProfilesRequest(arg) {
  if (!(arg instanceof scheduler_policy_pb.ListPolicyProfilesRequest)) {
    throw new Error('Expected argument of type sw4rm.scheduler.ListPolicyProfilesRequest');
  }
  return Buffer.from(arg.serializeBinary());
}

function deserialize_sw4rm_scheduler_ListPolicyProfilesRequest(buffer_arg) {
  return scheduler_policy_pb.ListPolicyProfilesRequest.deserializeBinary(new Uint8Array(buffer_arg));
}

function serialize_sw4rm_scheduler_ListPolicyProfilesResponse(arg) {
  if (!(arg instanceof scheduler_policy_pb.ListPolicyProfilesResponse)) {
    throw new Error('Expected argument of type sw4rm.scheduler.ListPolicyProfilesResponse');
  }
  return Buffer.from(arg.serializeBinary());
}

function deserialize_sw4rm_scheduler_ListPolicyProfilesResponse(buffer_arg) {
  return scheduler_policy_pb.ListPolicyProfilesResponse.deserializeBinary(new Uint8Array(buffer_arg));
}

function serialize_sw4rm_scheduler_SetNegotiationPolicyRequest(arg) {
  if (!(arg instanceof scheduler_policy_pb.SetNegotiationPolicyRequest)) {
    throw new Error('Expected argument of type sw4rm.scheduler.SetNegotiationPolicyRequest');
  }
  return Buffer.from(arg.serializeBinary());
}

function deserialize_sw4rm_scheduler_SetNegotiationPolicyRequest(buffer_arg) {
  return scheduler_policy_pb.SetNegotiationPolicyRequest.deserializeBinary(new Uint8Array(buffer_arg));
}

function serialize_sw4rm_scheduler_SetNegotiationPolicyResponse(arg) {
  if (!(arg instanceof scheduler_policy_pb.SetNegotiationPolicyResponse)) {
    throw new Error('Expected argument of type sw4rm.scheduler.SetNegotiationPolicyResponse');
  }
  return Buffer.from(arg.serializeBinary());
}

function deserialize_sw4rm_scheduler_SetNegotiationPolicyResponse(buffer_arg) {
  return scheduler_policy_pb.SetNegotiationPolicyResponse.deserializeBinary(new Uint8Array(buffer_arg));
}

function serialize_sw4rm_scheduler_SetPolicyProfilesRequest(arg) {
  if (!(arg instanceof scheduler_policy_pb.SetPolicyProfilesRequest)) {
    throw new Error('Expected argument of type sw4rm.scheduler.SetPolicyProfilesRequest');
  }
  return Buffer.from(arg.serializeBinary());
}

function deserialize_sw4rm_scheduler_SetPolicyProfilesRequest(buffer_arg) {
  return scheduler_policy_pb.SetPolicyProfilesRequest.deserializeBinary(new Uint8Array(buffer_arg));
}

function serialize_sw4rm_scheduler_SetPolicyProfilesResponse(arg) {
  if (!(arg instanceof scheduler_policy_pb.SetPolicyProfilesResponse)) {
    throw new Error('Expected argument of type sw4rm.scheduler.SetPolicyProfilesResponse');
  }
  return Buffer.from(arg.serializeBinary());
}

function deserialize_sw4rm_scheduler_SetPolicyProfilesResponse(buffer_arg) {
  return scheduler_policy_pb.SetPolicyProfilesResponse.deserializeBinary(new Uint8Array(buffer_arg));
}

function serialize_sw4rm_scheduler_SubmitEvaluationRequest(arg) {
  if (!(arg instanceof scheduler_policy_pb.SubmitEvaluationRequest)) {
    throw new Error('Expected argument of type sw4rm.scheduler.SubmitEvaluationRequest');
  }
  return Buffer.from(arg.serializeBinary());
}

function deserialize_sw4rm_scheduler_SubmitEvaluationRequest(buffer_arg) {
  return scheduler_policy_pb.SubmitEvaluationRequest.deserializeBinary(new Uint8Array(buffer_arg));
}

function serialize_sw4rm_scheduler_SubmitEvaluationResponse(arg) {
  if (!(arg instanceof scheduler_policy_pb.SubmitEvaluationResponse)) {
    throw new Error('Expected argument of type sw4rm.scheduler.SubmitEvaluationResponse');
  }
  return Buffer.from(arg.serializeBinary());
}

function deserialize_sw4rm_scheduler_SubmitEvaluationResponse(buffer_arg) {
  return scheduler_policy_pb.SubmitEvaluationResponse.deserializeBinary(new Uint8Array(buffer_arg));
}


var SchedulerPolicyServiceService = exports.SchedulerPolicyServiceService = {
  setNegotiationPolicy: {
    path: '/sw4rm.scheduler.SchedulerPolicyService/SetNegotiationPolicy',
    requestStream: false,
    responseStream: false,
    requestType: scheduler_policy_pb.SetNegotiationPolicyRequest,
    responseType: scheduler_policy_pb.SetNegotiationPolicyResponse,
    requestSerialize: serialize_sw4rm_scheduler_SetNegotiationPolicyRequest,
    requestDeserialize: deserialize_sw4rm_scheduler_SetNegotiationPolicyRequest,
    responseSerialize: serialize_sw4rm_scheduler_SetNegotiationPolicyResponse,
    responseDeserialize: deserialize_sw4rm_scheduler_SetNegotiationPolicyResponse,
  },
  getNegotiationPolicy: {
    path: '/sw4rm.scheduler.SchedulerPolicyService/GetNegotiationPolicy',
    requestStream: false,
    responseStream: false,
    requestType: scheduler_policy_pb.GetNegotiationPolicyRequest,
    responseType: scheduler_policy_pb.GetNegotiationPolicyResponse,
    requestSerialize: serialize_sw4rm_scheduler_GetNegotiationPolicyRequest,
    requestDeserialize: deserialize_sw4rm_scheduler_GetNegotiationPolicyRequest,
    responseSerialize: serialize_sw4rm_scheduler_GetNegotiationPolicyResponse,
    responseDeserialize: deserialize_sw4rm_scheduler_GetNegotiationPolicyResponse,
  },
  setPolicyProfiles: {
    path: '/sw4rm.scheduler.SchedulerPolicyService/SetPolicyProfiles',
    requestStream: false,
    responseStream: false,
    requestType: scheduler_policy_pb.SetPolicyProfilesRequest,
    responseType: scheduler_policy_pb.SetPolicyProfilesResponse,
    requestSerialize: serialize_sw4rm_scheduler_SetPolicyProfilesRequest,
    requestDeserialize: deserialize_sw4rm_scheduler_SetPolicyProfilesRequest,
    responseSerialize: serialize_sw4rm_scheduler_SetPolicyProfilesResponse,
    responseDeserialize: deserialize_sw4rm_scheduler_SetPolicyProfilesResponse,
  },
  listPolicyProfiles: {
    path: '/sw4rm.scheduler.SchedulerPolicyService/ListPolicyProfiles',
    requestStream: false,
    responseStream: false,
    requestType: scheduler_policy_pb.ListPolicyProfilesRequest,
    responseType: scheduler_policy_pb.ListPolicyProfilesResponse,
    requestSerialize: serialize_sw4rm_scheduler_ListPolicyProfilesRequest,
    requestDeserialize: deserialize_sw4rm_scheduler_ListPolicyProfilesRequest,
    responseSerialize: serialize_sw4rm_scheduler_ListPolicyProfilesResponse,
    responseDeserialize: deserialize_sw4rm_scheduler_ListPolicyProfilesResponse,
  },
  getEffectivePolicy: {
    path: '/sw4rm.scheduler.SchedulerPolicyService/GetEffectivePolicy',
    requestStream: false,
    responseStream: false,
    requestType: scheduler_policy_pb.GetEffectivePolicyRequest,
    responseType: scheduler_policy_pb.GetEffectivePolicyResponse,
    requestSerialize: serialize_sw4rm_scheduler_GetEffectivePolicyRequest,
    requestDeserialize: deserialize_sw4rm_scheduler_GetEffectivePolicyRequest,
    responseSerialize: serialize_sw4rm_scheduler_GetEffectivePolicyResponse,
    responseDeserialize: deserialize_sw4rm_scheduler_GetEffectivePolicyResponse,
  },
  submitEvaluation: {
    path: '/sw4rm.scheduler.SchedulerPolicyService/SubmitEvaluation',
    requestStream: false,
    responseStream: false,
    requestType: scheduler_policy_pb.SubmitEvaluationRequest,
    responseType: scheduler_policy_pb.SubmitEvaluationResponse,
    requestSerialize: serialize_sw4rm_scheduler_SubmitEvaluationRequest,
    requestDeserialize: deserialize_sw4rm_scheduler_SubmitEvaluationRequest,
    responseSerialize: serialize_sw4rm_scheduler_SubmitEvaluationResponse,
    responseDeserialize: deserialize_sw4rm_scheduler_SubmitEvaluationResponse,
  },
  hitlAction: {
    path: '/sw4rm.scheduler.SchedulerPolicyService/HitlAction',
    requestStream: false,
    responseStream: false,
    requestType: scheduler_policy_pb.HitlActionRequest,
    responseType: scheduler_policy_pb.HitlActionResponse,
    requestSerialize: serialize_sw4rm_scheduler_HitlActionRequest,
    requestDeserialize: deserialize_sw4rm_scheduler_HitlActionRequest,
    responseSerialize: serialize_sw4rm_scheduler_HitlActionResponse,
    responseDeserialize: deserialize_sw4rm_scheduler_HitlActionResponse,
  },
};

exports.SchedulerPolicyServiceClient = grpc.makeGenericClientConstructor(SchedulerPolicyServiceService, 'SchedulerPolicyService');
