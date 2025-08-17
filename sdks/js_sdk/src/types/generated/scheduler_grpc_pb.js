// GENERATED CODE -- DO NOT EDIT!

'use strict';
var grpc = require('@grpc/grpc-js');
var scheduler_pb = require('./scheduler_pb.js');
var google_protobuf_duration_pb = require('google-protobuf/google/protobuf/duration_pb.js');
var common_pb = require('./common_pb.js');

function serialize_sw4rm_scheduler_PollActivityBufferRequest(arg) {
  if (!(arg instanceof scheduler_pb.PollActivityBufferRequest)) {
    throw new Error('Expected argument of type sw4rm.scheduler.PollActivityBufferRequest');
  }
  return Buffer.from(arg.serializeBinary());
}

function deserialize_sw4rm_scheduler_PollActivityBufferRequest(buffer_arg) {
  return scheduler_pb.PollActivityBufferRequest.deserializeBinary(new Uint8Array(buffer_arg));
}

function serialize_sw4rm_scheduler_PollActivityBufferResponse(arg) {
  if (!(arg instanceof scheduler_pb.PollActivityBufferResponse)) {
    throw new Error('Expected argument of type sw4rm.scheduler.PollActivityBufferResponse');
  }
  return Buffer.from(arg.serializeBinary());
}

function deserialize_sw4rm_scheduler_PollActivityBufferResponse(buffer_arg) {
  return scheduler_pb.PollActivityBufferResponse.deserializeBinary(new Uint8Array(buffer_arg));
}

function serialize_sw4rm_scheduler_PreemptRequest(arg) {
  if (!(arg instanceof scheduler_pb.PreemptRequest)) {
    throw new Error('Expected argument of type sw4rm.scheduler.PreemptRequest');
  }
  return Buffer.from(arg.serializeBinary());
}

function deserialize_sw4rm_scheduler_PreemptRequest(buffer_arg) {
  return scheduler_pb.PreemptRequest.deserializeBinary(new Uint8Array(buffer_arg));
}

function serialize_sw4rm_scheduler_PreemptResponse(arg) {
  if (!(arg instanceof scheduler_pb.PreemptResponse)) {
    throw new Error('Expected argument of type sw4rm.scheduler.PreemptResponse');
  }
  return Buffer.from(arg.serializeBinary());
}

function deserialize_sw4rm_scheduler_PreemptResponse(buffer_arg) {
  return scheduler_pb.PreemptResponse.deserializeBinary(new Uint8Array(buffer_arg));
}

function serialize_sw4rm_scheduler_PurgeActivityRequest(arg) {
  if (!(arg instanceof scheduler_pb.PurgeActivityRequest)) {
    throw new Error('Expected argument of type sw4rm.scheduler.PurgeActivityRequest');
  }
  return Buffer.from(arg.serializeBinary());
}

function deserialize_sw4rm_scheduler_PurgeActivityRequest(buffer_arg) {
  return scheduler_pb.PurgeActivityRequest.deserializeBinary(new Uint8Array(buffer_arg));
}

function serialize_sw4rm_scheduler_PurgeActivityResponse(arg) {
  if (!(arg instanceof scheduler_pb.PurgeActivityResponse)) {
    throw new Error('Expected argument of type sw4rm.scheduler.PurgeActivityResponse');
  }
  return Buffer.from(arg.serializeBinary());
}

function deserialize_sw4rm_scheduler_PurgeActivityResponse(buffer_arg) {
  return scheduler_pb.PurgeActivityResponse.deserializeBinary(new Uint8Array(buffer_arg));
}

function serialize_sw4rm_scheduler_ShutdownAgentRequest(arg) {
  if (!(arg instanceof scheduler_pb.ShutdownAgentRequest)) {
    throw new Error('Expected argument of type sw4rm.scheduler.ShutdownAgentRequest');
  }
  return Buffer.from(arg.serializeBinary());
}

function deserialize_sw4rm_scheduler_ShutdownAgentRequest(buffer_arg) {
  return scheduler_pb.ShutdownAgentRequest.deserializeBinary(new Uint8Array(buffer_arg));
}

function serialize_sw4rm_scheduler_ShutdownAgentResponse(arg) {
  if (!(arg instanceof scheduler_pb.ShutdownAgentResponse)) {
    throw new Error('Expected argument of type sw4rm.scheduler.ShutdownAgentResponse');
  }
  return Buffer.from(arg.serializeBinary());
}

function deserialize_sw4rm_scheduler_ShutdownAgentResponse(buffer_arg) {
  return scheduler_pb.ShutdownAgentResponse.deserializeBinary(new Uint8Array(buffer_arg));
}

function serialize_sw4rm_scheduler_SubmitTaskRequest(arg) {
  if (!(arg instanceof scheduler_pb.SubmitTaskRequest)) {
    throw new Error('Expected argument of type sw4rm.scheduler.SubmitTaskRequest');
  }
  return Buffer.from(arg.serializeBinary());
}

function deserialize_sw4rm_scheduler_SubmitTaskRequest(buffer_arg) {
  return scheduler_pb.SubmitTaskRequest.deserializeBinary(new Uint8Array(buffer_arg));
}

function serialize_sw4rm_scheduler_SubmitTaskResponse(arg) {
  if (!(arg instanceof scheduler_pb.SubmitTaskResponse)) {
    throw new Error('Expected argument of type sw4rm.scheduler.SubmitTaskResponse');
  }
  return Buffer.from(arg.serializeBinary());
}

function deserialize_sw4rm_scheduler_SubmitTaskResponse(buffer_arg) {
  return scheduler_pb.SubmitTaskResponse.deserializeBinary(new Uint8Array(buffer_arg));
}


var SchedulerServiceService = exports.SchedulerServiceService = {
  submitTask: {
    path: '/sw4rm.scheduler.SchedulerService/SubmitTask',
    requestStream: false,
    responseStream: false,
    requestType: scheduler_pb.SubmitTaskRequest,
    responseType: scheduler_pb.SubmitTaskResponse,
    requestSerialize: serialize_sw4rm_scheduler_SubmitTaskRequest,
    requestDeserialize: deserialize_sw4rm_scheduler_SubmitTaskRequest,
    responseSerialize: serialize_sw4rm_scheduler_SubmitTaskResponse,
    responseDeserialize: deserialize_sw4rm_scheduler_SubmitTaskResponse,
  },
  requestPreemption: {
    path: '/sw4rm.scheduler.SchedulerService/RequestPreemption',
    requestStream: false,
    responseStream: false,
    requestType: scheduler_pb.PreemptRequest,
    responseType: scheduler_pb.PreemptResponse,
    requestSerialize: serialize_sw4rm_scheduler_PreemptRequest,
    requestDeserialize: deserialize_sw4rm_scheduler_PreemptRequest,
    responseSerialize: serialize_sw4rm_scheduler_PreemptResponse,
    responseDeserialize: deserialize_sw4rm_scheduler_PreemptResponse,
  },
  shutdownAgent: {
    path: '/sw4rm.scheduler.SchedulerService/ShutdownAgent',
    requestStream: false,
    responseStream: false,
    requestType: scheduler_pb.ShutdownAgentRequest,
    responseType: scheduler_pb.ShutdownAgentResponse,
    requestSerialize: serialize_sw4rm_scheduler_ShutdownAgentRequest,
    requestDeserialize: deserialize_sw4rm_scheduler_ShutdownAgentRequest,
    responseSerialize: serialize_sw4rm_scheduler_ShutdownAgentResponse,
    responseDeserialize: deserialize_sw4rm_scheduler_ShutdownAgentResponse,
  },
  pollActivityBuffer: {
    path: '/sw4rm.scheduler.SchedulerService/PollActivityBuffer',
    requestStream: false,
    responseStream: false,
    requestType: scheduler_pb.PollActivityBufferRequest,
    responseType: scheduler_pb.PollActivityBufferResponse,
    requestSerialize: serialize_sw4rm_scheduler_PollActivityBufferRequest,
    requestDeserialize: deserialize_sw4rm_scheduler_PollActivityBufferRequest,
    responseSerialize: serialize_sw4rm_scheduler_PollActivityBufferResponse,
    responseDeserialize: deserialize_sw4rm_scheduler_PollActivityBufferResponse,
  },
  purgeActivity: {
    path: '/sw4rm.scheduler.SchedulerService/PurgeActivity',
    requestStream: false,
    responseStream: false,
    requestType: scheduler_pb.PurgeActivityRequest,
    responseType: scheduler_pb.PurgeActivityResponse,
    requestSerialize: serialize_sw4rm_scheduler_PurgeActivityRequest,
    requestDeserialize: deserialize_sw4rm_scheduler_PurgeActivityRequest,
    responseSerialize: serialize_sw4rm_scheduler_PurgeActivityResponse,
    responseDeserialize: deserialize_sw4rm_scheduler_PurgeActivityResponse,
  },
};

exports.SchedulerServiceClient = grpc.makeGenericClientConstructor(SchedulerServiceService, 'SchedulerService');
