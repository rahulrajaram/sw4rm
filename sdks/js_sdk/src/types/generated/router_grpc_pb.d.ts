// package: sw4rm.router
// file: router.proto

/* tslint:disable */
/* eslint-disable */

import * as grpc from "@grpc/grpc-js";
import * as router_pb from "./router_pb";
import * as common_pb from "./common_pb";

interface IRouterServiceService extends grpc.ServiceDefinition<grpc.UntypedServiceImplementation> {
    sendMessage: IRouterServiceService_ISendMessage;
    streamIncoming: IRouterServiceService_IStreamIncoming;
}

interface IRouterServiceService_ISendMessage extends grpc.MethodDefinition<router_pb.SendMessageRequest, router_pb.SendMessageResponse> {
    path: "/sw4rm.router.RouterService/SendMessage";
    requestStream: false;
    responseStream: false;
    requestSerialize: grpc.serialize<router_pb.SendMessageRequest>;
    requestDeserialize: grpc.deserialize<router_pb.SendMessageRequest>;
    responseSerialize: grpc.serialize<router_pb.SendMessageResponse>;
    responseDeserialize: grpc.deserialize<router_pb.SendMessageResponse>;
}
interface IRouterServiceService_IStreamIncoming extends grpc.MethodDefinition<router_pb.StreamRequest, router_pb.StreamItem> {
    path: "/sw4rm.router.RouterService/StreamIncoming";
    requestStream: false;
    responseStream: true;
    requestSerialize: grpc.serialize<router_pb.StreamRequest>;
    requestDeserialize: grpc.deserialize<router_pb.StreamRequest>;
    responseSerialize: grpc.serialize<router_pb.StreamItem>;
    responseDeserialize: grpc.deserialize<router_pb.StreamItem>;
}

export const RouterServiceService: IRouterServiceService;

export interface IRouterServiceServer extends grpc.UntypedServiceImplementation {
    sendMessage: grpc.handleUnaryCall<router_pb.SendMessageRequest, router_pb.SendMessageResponse>;
    streamIncoming: grpc.handleServerStreamingCall<router_pb.StreamRequest, router_pb.StreamItem>;
}

export interface IRouterServiceClient {
    sendMessage(request: router_pb.SendMessageRequest, callback: (error: grpc.ServiceError | null, response: router_pb.SendMessageResponse) => void): grpc.ClientUnaryCall;
    sendMessage(request: router_pb.SendMessageRequest, metadata: grpc.Metadata, callback: (error: grpc.ServiceError | null, response: router_pb.SendMessageResponse) => void): grpc.ClientUnaryCall;
    sendMessage(request: router_pb.SendMessageRequest, metadata: grpc.Metadata, options: Partial<grpc.CallOptions>, callback: (error: grpc.ServiceError | null, response: router_pb.SendMessageResponse) => void): grpc.ClientUnaryCall;
    streamIncoming(request: router_pb.StreamRequest, options?: Partial<grpc.CallOptions>): grpc.ClientReadableStream<router_pb.StreamItem>;
    streamIncoming(request: router_pb.StreamRequest, metadata?: grpc.Metadata, options?: Partial<grpc.CallOptions>): grpc.ClientReadableStream<router_pb.StreamItem>;
}

export class RouterServiceClient extends grpc.Client implements IRouterServiceClient {
    constructor(address: string, credentials: grpc.ChannelCredentials, options?: Partial<grpc.ClientOptions>);
    public sendMessage(request: router_pb.SendMessageRequest, callback: (error: grpc.ServiceError | null, response: router_pb.SendMessageResponse) => void): grpc.ClientUnaryCall;
    public sendMessage(request: router_pb.SendMessageRequest, metadata: grpc.Metadata, callback: (error: grpc.ServiceError | null, response: router_pb.SendMessageResponse) => void): grpc.ClientUnaryCall;
    public sendMessage(request: router_pb.SendMessageRequest, metadata: grpc.Metadata, options: Partial<grpc.CallOptions>, callback: (error: grpc.ServiceError | null, response: router_pb.SendMessageResponse) => void): grpc.ClientUnaryCall;
    public streamIncoming(request: router_pb.StreamRequest, options?: Partial<grpc.CallOptions>): grpc.ClientReadableStream<router_pb.StreamItem>;
    public streamIncoming(request: router_pb.StreamRequest, metadata?: grpc.Metadata, options?: Partial<grpc.CallOptions>): grpc.ClientReadableStream<router_pb.StreamItem>;
}
