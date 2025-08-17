// GENERATED CODE -- DO NOT EDIT!

'use strict';
var grpc = require('@grpc/grpc-js');
var connector_pb = require('./connector_pb.js');

function serialize_sw4rm_connector_DescribeToolsRequest(arg) {
  if (!(arg instanceof connector_pb.DescribeToolsRequest)) {
    throw new Error('Expected argument of type sw4rm.connector.DescribeToolsRequest');
  }
  return Buffer.from(arg.serializeBinary());
}

function deserialize_sw4rm_connector_DescribeToolsRequest(buffer_arg) {
  return connector_pb.DescribeToolsRequest.deserializeBinary(new Uint8Array(buffer_arg));
}

function serialize_sw4rm_connector_DescribeToolsResponse(arg) {
  if (!(arg instanceof connector_pb.DescribeToolsResponse)) {
    throw new Error('Expected argument of type sw4rm.connector.DescribeToolsResponse');
  }
  return Buffer.from(arg.serializeBinary());
}

function deserialize_sw4rm_connector_DescribeToolsResponse(buffer_arg) {
  return connector_pb.DescribeToolsResponse.deserializeBinary(new Uint8Array(buffer_arg));
}

function serialize_sw4rm_connector_ProviderRegisterRequest(arg) {
  if (!(arg instanceof connector_pb.ProviderRegisterRequest)) {
    throw new Error('Expected argument of type sw4rm.connector.ProviderRegisterRequest');
  }
  return Buffer.from(arg.serializeBinary());
}

function deserialize_sw4rm_connector_ProviderRegisterRequest(buffer_arg) {
  return connector_pb.ProviderRegisterRequest.deserializeBinary(new Uint8Array(buffer_arg));
}

function serialize_sw4rm_connector_ProviderRegisterResponse(arg) {
  if (!(arg instanceof connector_pb.ProviderRegisterResponse)) {
    throw new Error('Expected argument of type sw4rm.connector.ProviderRegisterResponse');
  }
  return Buffer.from(arg.serializeBinary());
}

function deserialize_sw4rm_connector_ProviderRegisterResponse(buffer_arg) {
  return connector_pb.ProviderRegisterResponse.deserializeBinary(new Uint8Array(buffer_arg));
}


var ConnectorServiceService = exports.ConnectorServiceService = {
  registerProvider: {
    path: '/sw4rm.connector.ConnectorService/RegisterProvider',
    requestStream: false,
    responseStream: false,
    requestType: connector_pb.ProviderRegisterRequest,
    responseType: connector_pb.ProviderRegisterResponse,
    requestSerialize: serialize_sw4rm_connector_ProviderRegisterRequest,
    requestDeserialize: deserialize_sw4rm_connector_ProviderRegisterRequest,
    responseSerialize: serialize_sw4rm_connector_ProviderRegisterResponse,
    responseDeserialize: deserialize_sw4rm_connector_ProviderRegisterResponse,
  },
  describeTools: {
    path: '/sw4rm.connector.ConnectorService/DescribeTools',
    requestStream: false,
    responseStream: false,
    requestType: connector_pb.DescribeToolsRequest,
    responseType: connector_pb.DescribeToolsResponse,
    requestSerialize: serialize_sw4rm_connector_DescribeToolsRequest,
    requestDeserialize: deserialize_sw4rm_connector_DescribeToolsRequest,
    responseSerialize: serialize_sw4rm_connector_DescribeToolsResponse,
    responseDeserialize: deserialize_sw4rm_connector_DescribeToolsResponse,
  },
};

exports.ConnectorServiceClient = grpc.makeGenericClientConstructor(ConnectorServiceService, 'ConnectorService');
