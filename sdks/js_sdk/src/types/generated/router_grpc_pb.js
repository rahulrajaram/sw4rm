// GENERATED CODE -- DO NOT EDIT!

'use strict';
var grpc = require('@grpc/grpc-js');
var router_pb = require('./router_pb.js');
var common_pb = require('./common_pb.js');

function serialize_sw4rm_router_DeliveryAckRequest(arg) {
  if (!(arg instanceof router_pb.DeliveryAckRequest)) {
    throw new Error('Expected argument of type sw4rm.router.DeliveryAckRequest');
  }
  return Buffer.from(arg.serializeBinary());
}

function deserialize_sw4rm_router_DeliveryAckRequest(buffer_arg) {
  return router_pb.DeliveryAckRequest.deserializeBinary(new Uint8Array(buffer_arg));
}

function serialize_sw4rm_router_DeliveryAckResponse(arg) {
  if (!(arg instanceof router_pb.DeliveryAckResponse)) {
    throw new Error('Expected argument of type sw4rm.router.DeliveryAckResponse');
  }
  return Buffer.from(arg.serializeBinary());
}

function deserialize_sw4rm_router_DeliveryAckResponse(buffer_arg) {
  return router_pb.DeliveryAckResponse.deserializeBinary(new Uint8Array(buffer_arg));
}

function serialize_sw4rm_router_SendMessageRequest(arg) {
  if (!(arg instanceof router_pb.SendMessageRequest)) {
    throw new Error('Expected argument of type sw4rm.router.SendMessageRequest');
  }
  return Buffer.from(arg.serializeBinary());
}

function deserialize_sw4rm_router_SendMessageRequest(buffer_arg) {
  return router_pb.SendMessageRequest.deserializeBinary(new Uint8Array(buffer_arg));
}

function serialize_sw4rm_router_SendMessageResponse(arg) {
  if (!(arg instanceof router_pb.SendMessageResponse)) {
    throw new Error('Expected argument of type sw4rm.router.SendMessageResponse');
  }
  return Buffer.from(arg.serializeBinary());
}

function deserialize_sw4rm_router_SendMessageResponse(buffer_arg) {
  return router_pb.SendMessageResponse.deserializeBinary(new Uint8Array(buffer_arg));
}

function serialize_sw4rm_router_StreamItem(arg) {
  if (!(arg instanceof router_pb.StreamItem)) {
    throw new Error('Expected argument of type sw4rm.router.StreamItem');
  }
  return Buffer.from(arg.serializeBinary());
}

function deserialize_sw4rm_router_StreamItem(buffer_arg) {
  return router_pb.StreamItem.deserializeBinary(new Uint8Array(buffer_arg));
}

function serialize_sw4rm_router_StreamRequest(arg) {
  if (!(arg instanceof router_pb.StreamRequest)) {
    throw new Error('Expected argument of type sw4rm.router.StreamRequest');
  }
  return Buffer.from(arg.serializeBinary());
}

function deserialize_sw4rm_router_StreamRequest(buffer_arg) {
  return router_pb.StreamRequest.deserializeBinary(new Uint8Array(buffer_arg));
}


var RouterServiceService = exports.RouterServiceService = {
  sendMessage: {
    path: '/sw4rm.router.RouterService/SendMessage',
    requestStream: false,
    responseStream: false,
    requestType: router_pb.SendMessageRequest,
    responseType: router_pb.SendMessageResponse,
    requestSerialize: serialize_sw4rm_router_SendMessageRequest,
    requestDeserialize: deserialize_sw4rm_router_SendMessageRequest,
    responseSerialize: serialize_sw4rm_router_SendMessageResponse,
    responseDeserialize: deserialize_sw4rm_router_SendMessageResponse,
  },
  streamIncoming: {
    path: '/sw4rm.router.RouterService/StreamIncoming',
    requestStream: false,
    responseStream: true,
    requestType: router_pb.StreamRequest,
    responseType: router_pb.StreamItem,
    requestSerialize: serialize_sw4rm_router_StreamRequest,
    requestDeserialize: deserialize_sw4rm_router_StreamRequest,
    responseSerialize: serialize_sw4rm_router_StreamItem,
    responseDeserialize: deserialize_sw4rm_router_StreamItem,
  },
  // per-agent inbound stream
ackDelivery: {
    path: '/sw4rm.router.RouterService/AckDelivery',
    requestStream: false,
    responseStream: false,
    requestType: router_pb.DeliveryAckRequest,
    responseType: router_pb.DeliveryAckResponse,
    requestSerialize: serialize_sw4rm_router_DeliveryAckRequest,
    requestDeserialize: deserialize_sw4rm_router_DeliveryAckRequest,
    responseSerialize: serialize_sw4rm_router_DeliveryAckResponse,
    responseDeserialize: deserialize_sw4rm_router_DeliveryAckResponse,
  },
  // consumer ACK: releases the pending row
};

exports.RouterServiceClient = grpc.makeGenericClientConstructor(RouterServiceService, 'RouterService');
