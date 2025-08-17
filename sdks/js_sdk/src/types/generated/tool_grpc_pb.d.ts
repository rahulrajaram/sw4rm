// package: sw4rm.tool
// file: tool.proto

/* tslint:disable */
/* eslint-disable */

import * as grpc from "@grpc/grpc-js";
import * as tool_pb from "./tool_pb";
import * as google_protobuf_duration_pb from "google-protobuf/google/protobuf/duration_pb";

interface IToolServiceService extends grpc.ServiceDefinition<grpc.UntypedServiceImplementation> {
    call: IToolServiceService_ICall;
    callStream: IToolServiceService_ICallStream;
    cancel: IToolServiceService_ICancel;
}

interface IToolServiceService_ICall extends grpc.MethodDefinition<tool_pb.ToolCall, tool_pb.ToolFrame> {
    path: "/sw4rm.tool.ToolService/Call";
    requestStream: false;
    responseStream: false;
    requestSerialize: grpc.serialize<tool_pb.ToolCall>;
    requestDeserialize: grpc.deserialize<tool_pb.ToolCall>;
    responseSerialize: grpc.serialize<tool_pb.ToolFrame>;
    responseDeserialize: grpc.deserialize<tool_pb.ToolFrame>;
}
interface IToolServiceService_ICallStream extends grpc.MethodDefinition<tool_pb.ToolCall, tool_pb.ToolFrame> {
    path: "/sw4rm.tool.ToolService/CallStream";
    requestStream: false;
    responseStream: true;
    requestSerialize: grpc.serialize<tool_pb.ToolCall>;
    requestDeserialize: grpc.deserialize<tool_pb.ToolCall>;
    responseSerialize: grpc.serialize<tool_pb.ToolFrame>;
    responseDeserialize: grpc.deserialize<tool_pb.ToolFrame>;
}
interface IToolServiceService_ICancel extends grpc.MethodDefinition<tool_pb.ToolCall, tool_pb.ToolError> {
    path: "/sw4rm.tool.ToolService/Cancel";
    requestStream: false;
    responseStream: false;
    requestSerialize: grpc.serialize<tool_pb.ToolCall>;
    requestDeserialize: grpc.deserialize<tool_pb.ToolCall>;
    responseSerialize: grpc.serialize<tool_pb.ToolError>;
    responseDeserialize: grpc.deserialize<tool_pb.ToolError>;
}

export const ToolServiceService: IToolServiceService;

export interface IToolServiceServer extends grpc.UntypedServiceImplementation {
    call: grpc.handleUnaryCall<tool_pb.ToolCall, tool_pb.ToolFrame>;
    callStream: grpc.handleServerStreamingCall<tool_pb.ToolCall, tool_pb.ToolFrame>;
    cancel: grpc.handleUnaryCall<tool_pb.ToolCall, tool_pb.ToolError>;
}

export interface IToolServiceClient {
    call(request: tool_pb.ToolCall, callback: (error: grpc.ServiceError | null, response: tool_pb.ToolFrame) => void): grpc.ClientUnaryCall;
    call(request: tool_pb.ToolCall, metadata: grpc.Metadata, callback: (error: grpc.ServiceError | null, response: tool_pb.ToolFrame) => void): grpc.ClientUnaryCall;
    call(request: tool_pb.ToolCall, metadata: grpc.Metadata, options: Partial<grpc.CallOptions>, callback: (error: grpc.ServiceError | null, response: tool_pb.ToolFrame) => void): grpc.ClientUnaryCall;
    callStream(request: tool_pb.ToolCall, options?: Partial<grpc.CallOptions>): grpc.ClientReadableStream<tool_pb.ToolFrame>;
    callStream(request: tool_pb.ToolCall, metadata?: grpc.Metadata, options?: Partial<grpc.CallOptions>): grpc.ClientReadableStream<tool_pb.ToolFrame>;
    cancel(request: tool_pb.ToolCall, callback: (error: grpc.ServiceError | null, response: tool_pb.ToolError) => void): grpc.ClientUnaryCall;
    cancel(request: tool_pb.ToolCall, metadata: grpc.Metadata, callback: (error: grpc.ServiceError | null, response: tool_pb.ToolError) => void): grpc.ClientUnaryCall;
    cancel(request: tool_pb.ToolCall, metadata: grpc.Metadata, options: Partial<grpc.CallOptions>, callback: (error: grpc.ServiceError | null, response: tool_pb.ToolError) => void): grpc.ClientUnaryCall;
}

export class ToolServiceClient extends grpc.Client implements IToolServiceClient {
    constructor(address: string, credentials: grpc.ChannelCredentials, options?: Partial<grpc.ClientOptions>);
    public call(request: tool_pb.ToolCall, callback: (error: grpc.ServiceError | null, response: tool_pb.ToolFrame) => void): grpc.ClientUnaryCall;
    public call(request: tool_pb.ToolCall, metadata: grpc.Metadata, callback: (error: grpc.ServiceError | null, response: tool_pb.ToolFrame) => void): grpc.ClientUnaryCall;
    public call(request: tool_pb.ToolCall, metadata: grpc.Metadata, options: Partial<grpc.CallOptions>, callback: (error: grpc.ServiceError | null, response: tool_pb.ToolFrame) => void): grpc.ClientUnaryCall;
    public callStream(request: tool_pb.ToolCall, options?: Partial<grpc.CallOptions>): grpc.ClientReadableStream<tool_pb.ToolFrame>;
    public callStream(request: tool_pb.ToolCall, metadata?: grpc.Metadata, options?: Partial<grpc.CallOptions>): grpc.ClientReadableStream<tool_pb.ToolFrame>;
    public cancel(request: tool_pb.ToolCall, callback: (error: grpc.ServiceError | null, response: tool_pb.ToolError) => void): grpc.ClientUnaryCall;
    public cancel(request: tool_pb.ToolCall, metadata: grpc.Metadata, callback: (error: grpc.ServiceError | null, response: tool_pb.ToolError) => void): grpc.ClientUnaryCall;
    public cancel(request: tool_pb.ToolCall, metadata: grpc.Metadata, options: Partial<grpc.CallOptions>, callback: (error: grpc.ServiceError | null, response: tool_pb.ToolError) => void): grpc.ClientUnaryCall;
}
