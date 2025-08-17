// package: sw4rm.reasoning
// file: reasoning.proto

/* tslint:disable */
/* eslint-disable */

import * as grpc from "@grpc/grpc-js";
import * as reasoning_pb from "./reasoning_pb";

interface IReasoningProxyService extends grpc.ServiceDefinition<grpc.UntypedServiceImplementation> {
    checkParallelism: IReasoningProxyService_ICheckParallelism;
    evaluateDebate: IReasoningProxyService_IEvaluateDebate;
    summarize: IReasoningProxyService_ISummarize;
}

interface IReasoningProxyService_ICheckParallelism extends grpc.MethodDefinition<reasoning_pb.ParallelismCheckRequest, reasoning_pb.ParallelismCheckResponse> {
    path: "/sw4rm.reasoning.ReasoningProxy/CheckParallelism";
    requestStream: false;
    responseStream: false;
    requestSerialize: grpc.serialize<reasoning_pb.ParallelismCheckRequest>;
    requestDeserialize: grpc.deserialize<reasoning_pb.ParallelismCheckRequest>;
    responseSerialize: grpc.serialize<reasoning_pb.ParallelismCheckResponse>;
    responseDeserialize: grpc.deserialize<reasoning_pb.ParallelismCheckResponse>;
}
interface IReasoningProxyService_IEvaluateDebate extends grpc.MethodDefinition<reasoning_pb.DebateEvaluateRequest, reasoning_pb.DebateEvaluateResponse> {
    path: "/sw4rm.reasoning.ReasoningProxy/EvaluateDebate";
    requestStream: false;
    responseStream: false;
    requestSerialize: grpc.serialize<reasoning_pb.DebateEvaluateRequest>;
    requestDeserialize: grpc.deserialize<reasoning_pb.DebateEvaluateRequest>;
    responseSerialize: grpc.serialize<reasoning_pb.DebateEvaluateResponse>;
    responseDeserialize: grpc.deserialize<reasoning_pb.DebateEvaluateResponse>;
}
interface IReasoningProxyService_ISummarize extends grpc.MethodDefinition<reasoning_pb.SummarizeRequest, reasoning_pb.SummarizeResponse> {
    path: "/sw4rm.reasoning.ReasoningProxy/Summarize";
    requestStream: false;
    responseStream: false;
    requestSerialize: grpc.serialize<reasoning_pb.SummarizeRequest>;
    requestDeserialize: grpc.deserialize<reasoning_pb.SummarizeRequest>;
    responseSerialize: grpc.serialize<reasoning_pb.SummarizeResponse>;
    responseDeserialize: grpc.deserialize<reasoning_pb.SummarizeResponse>;
}

export const ReasoningProxyService: IReasoningProxyService;

export interface IReasoningProxyServer extends grpc.UntypedServiceImplementation {
    checkParallelism: grpc.handleUnaryCall<reasoning_pb.ParallelismCheckRequest, reasoning_pb.ParallelismCheckResponse>;
    evaluateDebate: grpc.handleUnaryCall<reasoning_pb.DebateEvaluateRequest, reasoning_pb.DebateEvaluateResponse>;
    summarize: grpc.handleUnaryCall<reasoning_pb.SummarizeRequest, reasoning_pb.SummarizeResponse>;
}

export interface IReasoningProxyClient {
    checkParallelism(request: reasoning_pb.ParallelismCheckRequest, callback: (error: grpc.ServiceError | null, response: reasoning_pb.ParallelismCheckResponse) => void): grpc.ClientUnaryCall;
    checkParallelism(request: reasoning_pb.ParallelismCheckRequest, metadata: grpc.Metadata, callback: (error: grpc.ServiceError | null, response: reasoning_pb.ParallelismCheckResponse) => void): grpc.ClientUnaryCall;
    checkParallelism(request: reasoning_pb.ParallelismCheckRequest, metadata: grpc.Metadata, options: Partial<grpc.CallOptions>, callback: (error: grpc.ServiceError | null, response: reasoning_pb.ParallelismCheckResponse) => void): grpc.ClientUnaryCall;
    evaluateDebate(request: reasoning_pb.DebateEvaluateRequest, callback: (error: grpc.ServiceError | null, response: reasoning_pb.DebateEvaluateResponse) => void): grpc.ClientUnaryCall;
    evaluateDebate(request: reasoning_pb.DebateEvaluateRequest, metadata: grpc.Metadata, callback: (error: grpc.ServiceError | null, response: reasoning_pb.DebateEvaluateResponse) => void): grpc.ClientUnaryCall;
    evaluateDebate(request: reasoning_pb.DebateEvaluateRequest, metadata: grpc.Metadata, options: Partial<grpc.CallOptions>, callback: (error: grpc.ServiceError | null, response: reasoning_pb.DebateEvaluateResponse) => void): grpc.ClientUnaryCall;
    summarize(request: reasoning_pb.SummarizeRequest, callback: (error: grpc.ServiceError | null, response: reasoning_pb.SummarizeResponse) => void): grpc.ClientUnaryCall;
    summarize(request: reasoning_pb.SummarizeRequest, metadata: grpc.Metadata, callback: (error: grpc.ServiceError | null, response: reasoning_pb.SummarizeResponse) => void): grpc.ClientUnaryCall;
    summarize(request: reasoning_pb.SummarizeRequest, metadata: grpc.Metadata, options: Partial<grpc.CallOptions>, callback: (error: grpc.ServiceError | null, response: reasoning_pb.SummarizeResponse) => void): grpc.ClientUnaryCall;
}

export class ReasoningProxyClient extends grpc.Client implements IReasoningProxyClient {
    constructor(address: string, credentials: grpc.ChannelCredentials, options?: Partial<grpc.ClientOptions>);
    public checkParallelism(request: reasoning_pb.ParallelismCheckRequest, callback: (error: grpc.ServiceError | null, response: reasoning_pb.ParallelismCheckResponse) => void): grpc.ClientUnaryCall;
    public checkParallelism(request: reasoning_pb.ParallelismCheckRequest, metadata: grpc.Metadata, callback: (error: grpc.ServiceError | null, response: reasoning_pb.ParallelismCheckResponse) => void): grpc.ClientUnaryCall;
    public checkParallelism(request: reasoning_pb.ParallelismCheckRequest, metadata: grpc.Metadata, options: Partial<grpc.CallOptions>, callback: (error: grpc.ServiceError | null, response: reasoning_pb.ParallelismCheckResponse) => void): grpc.ClientUnaryCall;
    public evaluateDebate(request: reasoning_pb.DebateEvaluateRequest, callback: (error: grpc.ServiceError | null, response: reasoning_pb.DebateEvaluateResponse) => void): grpc.ClientUnaryCall;
    public evaluateDebate(request: reasoning_pb.DebateEvaluateRequest, metadata: grpc.Metadata, callback: (error: grpc.ServiceError | null, response: reasoning_pb.DebateEvaluateResponse) => void): grpc.ClientUnaryCall;
    public evaluateDebate(request: reasoning_pb.DebateEvaluateRequest, metadata: grpc.Metadata, options: Partial<grpc.CallOptions>, callback: (error: grpc.ServiceError | null, response: reasoning_pb.DebateEvaluateResponse) => void): grpc.ClientUnaryCall;
    public summarize(request: reasoning_pb.SummarizeRequest, callback: (error: grpc.ServiceError | null, response: reasoning_pb.SummarizeResponse) => void): grpc.ClientUnaryCall;
    public summarize(request: reasoning_pb.SummarizeRequest, metadata: grpc.Metadata, callback: (error: grpc.ServiceError | null, response: reasoning_pb.SummarizeResponse) => void): grpc.ClientUnaryCall;
    public summarize(request: reasoning_pb.SummarizeRequest, metadata: grpc.Metadata, options: Partial<grpc.CallOptions>, callback: (error: grpc.ServiceError | null, response: reasoning_pb.SummarizeResponse) => void): grpc.ClientUnaryCall;
}
