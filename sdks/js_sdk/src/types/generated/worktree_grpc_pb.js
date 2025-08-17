// GENERATED CODE -- DO NOT EDIT!

'use strict';
var grpc = require('@grpc/grpc-js');
var worktree_pb = require('./worktree_pb.js');

function serialize_sw4rm_worktree_BindRequest(arg) {
  if (!(arg instanceof worktree_pb.BindRequest)) {
    throw new Error('Expected argument of type sw4rm.worktree.BindRequest');
  }
  return Buffer.from(arg.serializeBinary());
}

function deserialize_sw4rm_worktree_BindRequest(buffer_arg) {
  return worktree_pb.BindRequest.deserializeBinary(new Uint8Array(buffer_arg));
}

function serialize_sw4rm_worktree_BindResponse(arg) {
  if (!(arg instanceof worktree_pb.BindResponse)) {
    throw new Error('Expected argument of type sw4rm.worktree.BindResponse');
  }
  return Buffer.from(arg.serializeBinary());
}

function deserialize_sw4rm_worktree_BindResponse(buffer_arg) {
  return worktree_pb.BindResponse.deserializeBinary(new Uint8Array(buffer_arg));
}

function serialize_sw4rm_worktree_StatusRequest(arg) {
  if (!(arg instanceof worktree_pb.StatusRequest)) {
    throw new Error('Expected argument of type sw4rm.worktree.StatusRequest');
  }
  return Buffer.from(arg.serializeBinary());
}

function deserialize_sw4rm_worktree_StatusRequest(buffer_arg) {
  return worktree_pb.StatusRequest.deserializeBinary(new Uint8Array(buffer_arg));
}

function serialize_sw4rm_worktree_StatusResponse(arg) {
  if (!(arg instanceof worktree_pb.StatusResponse)) {
    throw new Error('Expected argument of type sw4rm.worktree.StatusResponse');
  }
  return Buffer.from(arg.serializeBinary());
}

function deserialize_sw4rm_worktree_StatusResponse(buffer_arg) {
  return worktree_pb.StatusResponse.deserializeBinary(new Uint8Array(buffer_arg));
}

function serialize_sw4rm_worktree_SwitchApprove(arg) {
  if (!(arg instanceof worktree_pb.SwitchApprove)) {
    throw new Error('Expected argument of type sw4rm.worktree.SwitchApprove');
  }
  return Buffer.from(arg.serializeBinary());
}

function deserialize_sw4rm_worktree_SwitchApprove(buffer_arg) {
  return worktree_pb.SwitchApprove.deserializeBinary(new Uint8Array(buffer_arg));
}

function serialize_sw4rm_worktree_SwitchReject(arg) {
  if (!(arg instanceof worktree_pb.SwitchReject)) {
    throw new Error('Expected argument of type sw4rm.worktree.SwitchReject');
  }
  return Buffer.from(arg.serializeBinary());
}

function deserialize_sw4rm_worktree_SwitchReject(buffer_arg) {
  return worktree_pb.SwitchReject.deserializeBinary(new Uint8Array(buffer_arg));
}

function serialize_sw4rm_worktree_SwitchRequest(arg) {
  if (!(arg instanceof worktree_pb.SwitchRequest)) {
    throw new Error('Expected argument of type sw4rm.worktree.SwitchRequest');
  }
  return Buffer.from(arg.serializeBinary());
}

function deserialize_sw4rm_worktree_SwitchRequest(buffer_arg) {
  return worktree_pb.SwitchRequest.deserializeBinary(new Uint8Array(buffer_arg));
}

function serialize_sw4rm_worktree_UnbindRequest(arg) {
  if (!(arg instanceof worktree_pb.UnbindRequest)) {
    throw new Error('Expected argument of type sw4rm.worktree.UnbindRequest');
  }
  return Buffer.from(arg.serializeBinary());
}

function deserialize_sw4rm_worktree_UnbindRequest(buffer_arg) {
  return worktree_pb.UnbindRequest.deserializeBinary(new Uint8Array(buffer_arg));
}

function serialize_sw4rm_worktree_UnbindResponse(arg) {
  if (!(arg instanceof worktree_pb.UnbindResponse)) {
    throw new Error('Expected argument of type sw4rm.worktree.UnbindResponse');
  }
  return Buffer.from(arg.serializeBinary());
}

function deserialize_sw4rm_worktree_UnbindResponse(buffer_arg) {
  return worktree_pb.UnbindResponse.deserializeBinary(new Uint8Array(buffer_arg));
}


var WorktreeServiceService = exports.WorktreeServiceService = {
  bind: {
    path: '/sw4rm.worktree.WorktreeService/Bind',
    requestStream: false,
    responseStream: false,
    requestType: worktree_pb.BindRequest,
    responseType: worktree_pb.BindResponse,
    requestSerialize: serialize_sw4rm_worktree_BindRequest,
    requestDeserialize: deserialize_sw4rm_worktree_BindRequest,
    responseSerialize: serialize_sw4rm_worktree_BindResponse,
    responseDeserialize: deserialize_sw4rm_worktree_BindResponse,
  },
  unbind: {
    path: '/sw4rm.worktree.WorktreeService/Unbind',
    requestStream: false,
    responseStream: false,
    requestType: worktree_pb.UnbindRequest,
    responseType: worktree_pb.UnbindResponse,
    requestSerialize: serialize_sw4rm_worktree_UnbindRequest,
    requestDeserialize: deserialize_sw4rm_worktree_UnbindRequest,
    responseSerialize: serialize_sw4rm_worktree_UnbindResponse,
    responseDeserialize: deserialize_sw4rm_worktree_UnbindResponse,
  },
  requestSwitch: {
    path: '/sw4rm.worktree.WorktreeService/RequestSwitch',
    requestStream: false,
    responseStream: false,
    requestType: worktree_pb.SwitchRequest,
    responseType: worktree_pb.StatusResponse,
    requestSerialize: serialize_sw4rm_worktree_SwitchRequest,
    requestDeserialize: deserialize_sw4rm_worktree_SwitchRequest,
    responseSerialize: serialize_sw4rm_worktree_StatusResponse,
    responseDeserialize: deserialize_sw4rm_worktree_StatusResponse,
  },
  approveSwitch: {
    path: '/sw4rm.worktree.WorktreeService/ApproveSwitch',
    requestStream: false,
    responseStream: false,
    requestType: worktree_pb.SwitchApprove,
    responseType: worktree_pb.StatusResponse,
    requestSerialize: serialize_sw4rm_worktree_SwitchApprove,
    requestDeserialize: deserialize_sw4rm_worktree_SwitchApprove,
    responseSerialize: serialize_sw4rm_worktree_StatusResponse,
    responseDeserialize: deserialize_sw4rm_worktree_StatusResponse,
  },
  rejectSwitch: {
    path: '/sw4rm.worktree.WorktreeService/RejectSwitch',
    requestStream: false,
    responseStream: false,
    requestType: worktree_pb.SwitchReject,
    responseType: worktree_pb.StatusResponse,
    requestSerialize: serialize_sw4rm_worktree_SwitchReject,
    requestDeserialize: deserialize_sw4rm_worktree_SwitchReject,
    responseSerialize: serialize_sw4rm_worktree_StatusResponse,
    responseDeserialize: deserialize_sw4rm_worktree_StatusResponse,
  },
  status: {
    path: '/sw4rm.worktree.WorktreeService/Status',
    requestStream: false,
    responseStream: false,
    requestType: worktree_pb.StatusRequest,
    responseType: worktree_pb.StatusResponse,
    requestSerialize: serialize_sw4rm_worktree_StatusRequest,
    requestDeserialize: deserialize_sw4rm_worktree_StatusRequest,
    responseSerialize: serialize_sw4rm_worktree_StatusResponse,
    responseDeserialize: deserialize_sw4rm_worktree_StatusResponse,
  },
};

exports.WorktreeServiceClient = grpc.makeGenericClientConstructor(WorktreeServiceService, 'WorktreeService');
