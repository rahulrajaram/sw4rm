// package: sw4rm.connector
// file: connector.proto

/* tslint:disable */
/* eslint-disable */

import * as grpc from "@grpc/grpc-js";
import * as connector_pb from "./connector_pb";

interface IConnectorServiceService extends grpc.ServiceDefinition<grpc.UntypedServiceImplementation> {
    registerProvider: IConnectorServiceService_IRegisterProvider;
    describeTools: IConnectorServiceService_IDescribeTools;
}

interface IConnectorServiceService_IRegisterProvider extends grpc.MethodDefinition<connector_pb.ProviderRegisterRequest, connector_pb.ProviderRegisterResponse> {
    path: "/sw4rm.connector.ConnectorService/RegisterProvider";
    requestStream: false;
    responseStream: false;
    requestSerialize: grpc.serialize<connector_pb.ProviderRegisterRequest>;
    requestDeserialize: grpc.deserialize<connector_pb.ProviderRegisterRequest>;
    responseSerialize: grpc.serialize<connector_pb.ProviderRegisterResponse>;
    responseDeserialize: grpc.deserialize<connector_pb.ProviderRegisterResponse>;
}
interface IConnectorServiceService_IDescribeTools extends grpc.MethodDefinition<connector_pb.DescribeToolsRequest, connector_pb.DescribeToolsResponse> {
    path: "/sw4rm.connector.ConnectorService/DescribeTools";
    requestStream: false;
    responseStream: false;
    requestSerialize: grpc.serialize<connector_pb.DescribeToolsRequest>;
    requestDeserialize: grpc.deserialize<connector_pb.DescribeToolsRequest>;
    responseSerialize: grpc.serialize<connector_pb.DescribeToolsResponse>;
    responseDeserialize: grpc.deserialize<connector_pb.DescribeToolsResponse>;
}

export const ConnectorServiceService: IConnectorServiceService;

export interface IConnectorServiceServer extends grpc.UntypedServiceImplementation {
    registerProvider: grpc.handleUnaryCall<connector_pb.ProviderRegisterRequest, connector_pb.ProviderRegisterResponse>;
    describeTools: grpc.handleUnaryCall<connector_pb.DescribeToolsRequest, connector_pb.DescribeToolsResponse>;
}

export interface IConnectorServiceClient {
    registerProvider(request: connector_pb.ProviderRegisterRequest, callback: (error: grpc.ServiceError | null, response: connector_pb.ProviderRegisterResponse) => void): grpc.ClientUnaryCall;
    registerProvider(request: connector_pb.ProviderRegisterRequest, metadata: grpc.Metadata, callback: (error: grpc.ServiceError | null, response: connector_pb.ProviderRegisterResponse) => void): grpc.ClientUnaryCall;
    registerProvider(request: connector_pb.ProviderRegisterRequest, metadata: grpc.Metadata, options: Partial<grpc.CallOptions>, callback: (error: grpc.ServiceError | null, response: connector_pb.ProviderRegisterResponse) => void): grpc.ClientUnaryCall;
    describeTools(request: connector_pb.DescribeToolsRequest, callback: (error: grpc.ServiceError | null, response: connector_pb.DescribeToolsResponse) => void): grpc.ClientUnaryCall;
    describeTools(request: connector_pb.DescribeToolsRequest, metadata: grpc.Metadata, callback: (error: grpc.ServiceError | null, response: connector_pb.DescribeToolsResponse) => void): grpc.ClientUnaryCall;
    describeTools(request: connector_pb.DescribeToolsRequest, metadata: grpc.Metadata, options: Partial<grpc.CallOptions>, callback: (error: grpc.ServiceError | null, response: connector_pb.DescribeToolsResponse) => void): grpc.ClientUnaryCall;
}

export class ConnectorServiceClient extends grpc.Client implements IConnectorServiceClient {
    constructor(address: string, credentials: grpc.ChannelCredentials, options?: Partial<grpc.ClientOptions>);
    public registerProvider(request: connector_pb.ProviderRegisterRequest, callback: (error: grpc.ServiceError | null, response: connector_pb.ProviderRegisterResponse) => void): grpc.ClientUnaryCall;
    public registerProvider(request: connector_pb.ProviderRegisterRequest, metadata: grpc.Metadata, callback: (error: grpc.ServiceError | null, response: connector_pb.ProviderRegisterResponse) => void): grpc.ClientUnaryCall;
    public registerProvider(request: connector_pb.ProviderRegisterRequest, metadata: grpc.Metadata, options: Partial<grpc.CallOptions>, callback: (error: grpc.ServiceError | null, response: connector_pb.ProviderRegisterResponse) => void): grpc.ClientUnaryCall;
    public describeTools(request: connector_pb.DescribeToolsRequest, callback: (error: grpc.ServiceError | null, response: connector_pb.DescribeToolsResponse) => void): grpc.ClientUnaryCall;
    public describeTools(request: connector_pb.DescribeToolsRequest, metadata: grpc.Metadata, callback: (error: grpc.ServiceError | null, response: connector_pb.DescribeToolsResponse) => void): grpc.ClientUnaryCall;
    public describeTools(request: connector_pb.DescribeToolsRequest, metadata: grpc.Metadata, options: Partial<grpc.CallOptions>, callback: (error: grpc.ServiceError | null, response: connector_pb.DescribeToolsResponse) => void): grpc.ClientUnaryCall;
}
