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

function serialize_sw4rm_scheduler_GetWagglePolicyRequest(arg) {
  if (!(arg instanceof scheduler_policy_pb.GetWagglePolicyRequest)) {
    throw new Error('Expected argument of type sw4rm.scheduler.GetWagglePolicyRequest');
  }
  return Buffer.from(arg.serializeBinary());
}

function deserialize_sw4rm_scheduler_GetWagglePolicyRequest(buffer_arg) {
  return scheduler_policy_pb.GetWagglePolicyRequest.deserializeBinary(new Uint8Array(buffer_arg));
}

function serialize_sw4rm_scheduler_GetWagglePolicyResponse(arg) {
  if (!(arg instanceof scheduler_policy_pb.GetWagglePolicyResponse)) {
    throw new Error('Expected argument of type sw4rm.scheduler.GetWagglePolicyResponse');
  }
  return Buffer.from(arg.serializeBinary());
}

function deserialize_sw4rm_scheduler_GetWagglePolicyResponse(buffer_arg) {
  return scheduler_policy_pb.GetWagglePolicyResponse.deserializeBinary(new Uint8Array(buffer_arg));
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

function serialize_sw4rm_scheduler_SetWagglePolicyRequest(arg) {
  if (!(arg instanceof scheduler_policy_pb.SetWagglePolicyRequest)) {
    throw new Error('Expected argument of type sw4rm.scheduler.SetWagglePolicyRequest');
  }
  return Buffer.from(arg.serializeBinary());
}

function deserialize_sw4rm_scheduler_SetWagglePolicyRequest(buffer_arg) {
  return scheduler_policy_pb.SetWagglePolicyRequest.deserializeBinary(new Uint8Array(buffer_arg));
}

function serialize_sw4rm_scheduler_SetWagglePolicyResponse(arg) {
  if (!(arg instanceof scheduler_policy_pb.SetWagglePolicyResponse)) {
    throw new Error('Expected argument of type sw4rm.scheduler.SetWagglePolicyResponse');
  }
  return Buffer.from(arg.serializeBinary());
}

function deserialize_sw4rm_scheduler_SetWagglePolicyResponse(buffer_arg) {
  return scheduler_policy_pb.SetWagglePolicyResponse.deserializeBinary(new Uint8Array(buffer_arg));
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
  setWagglePolicy: {
    path: '/sw4rm.scheduler.SchedulerPolicyService/SetWagglePolicy',
    requestStream: false,
    responseStream: false,
    requestType: scheduler_policy_pb.SetWagglePolicyRequest,
    responseType: scheduler_policy_pb.SetWagglePolicyResponse,
    requestSerialize: serialize_sw4rm_scheduler_SetWagglePolicyRequest,
    requestDeserialize: deserialize_sw4rm_scheduler_SetWagglePolicyRequest,
    responseSerialize: serialize_sw4rm_scheduler_SetWagglePolicyResponse,
    responseDeserialize: deserialize_sw4rm_scheduler_SetWagglePolicyResponse,
  },
  getWagglePolicy: {
    path: '/sw4rm.scheduler.SchedulerPolicyService/GetWagglePolicy',
    requestStream: false,
    responseStream: false,
    requestType: scheduler_policy_pb.GetWagglePolicyRequest,
    responseType: scheduler_policy_pb.GetWagglePolicyResponse,
    requestSerialize: serialize_sw4rm_scheduler_GetWagglePolicyRequest,
    requestDeserialize: deserialize_sw4rm_scheduler_GetWagglePolicyRequest,
    responseSerialize: serialize_sw4rm_scheduler_GetWagglePolicyResponse,
    responseDeserialize: deserialize_sw4rm_scheduler_GetWagglePolicyResponse,
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
