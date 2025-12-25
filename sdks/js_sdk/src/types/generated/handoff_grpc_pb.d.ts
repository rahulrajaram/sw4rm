// package: sw4rm.handoff
// file: handoff.proto

/* tslint:disable */
/* eslint-disable */

import * as grpc from "@grpc/grpc-js";
import * as handoff_pb from "./handoff_pb";
import * as common_pb from "./common_pb";
import * as google_protobuf_duration_pb from "google-protobuf/google/protobuf/duration_pb";

interface IHandoffServiceService extends grpc.ServiceDefinition<grpc.UntypedServiceImplementation> {
    requestHandoff: IHandoffServiceService_IRequestHandoff;
    acceptHandoff: IHandoffServiceService_IAcceptHandoff;
    rejectHandoff: IHandoffServiceService_IRejectHandoff;
    getPendingHandoffs: IHandoffServiceService_IGetPendingHandoffs;
    completeHandoff: IHandoffServiceService_ICompleteHandoff;
}

interface IHandoffServiceService_IRequestHandoff extends grpc.MethodDefinition<handoff_pb.HandoffRequest, common_pb.Empty> {
    path: "/sw4rm.handoff.HandoffService/RequestHandoff";
    requestStream: false;
    responseStream: false;
    requestSerialize: grpc.serialize<handoff_pb.HandoffRequest>;
    requestDeserialize: grpc.deserialize<handoff_pb.HandoffRequest>;
    responseSerialize: grpc.serialize<common_pb.Empty>;
    responseDeserialize: grpc.deserialize<common_pb.Empty>;
}
interface IHandoffServiceService_IAcceptHandoff extends grpc.MethodDefinition<handoff_pb.HandoffResponse, common_pb.Empty> {
    path: "/sw4rm.handoff.HandoffService/AcceptHandoff";
    requestStream: false;
    responseStream: false;
    requestSerialize: grpc.serialize<handoff_pb.HandoffResponse>;
    requestDeserialize: grpc.deserialize<handoff_pb.HandoffResponse>;
    responseSerialize: grpc.serialize<common_pb.Empty>;
    responseDeserialize: grpc.deserialize<common_pb.Empty>;
}
interface IHandoffServiceService_IRejectHandoff extends grpc.MethodDefinition<handoff_pb.HandoffResponse, common_pb.Empty> {
    path: "/sw4rm.handoff.HandoffService/RejectHandoff";
    requestStream: false;
    responseStream: false;
    requestSerialize: grpc.serialize<handoff_pb.HandoffResponse>;
    requestDeserialize: grpc.deserialize<handoff_pb.HandoffResponse>;
    responseSerialize: grpc.serialize<common_pb.Empty>;
    responseDeserialize: grpc.deserialize<common_pb.Empty>;
}
interface IHandoffServiceService_IGetPendingHandoffs extends grpc.MethodDefinition<handoff_pb.GetPendingHandoffsRequest, handoff_pb.GetPendingHandoffsResponse> {
    path: "/sw4rm.handoff.HandoffService/GetPendingHandoffs";
    requestStream: false;
    responseStream: false;
    requestSerialize: grpc.serialize<handoff_pb.GetPendingHandoffsRequest>;
    requestDeserialize: grpc.deserialize<handoff_pb.GetPendingHandoffsRequest>;
    responseSerialize: grpc.serialize<handoff_pb.GetPendingHandoffsResponse>;
    responseDeserialize: grpc.deserialize<handoff_pb.GetPendingHandoffsResponse>;
}
interface IHandoffServiceService_ICompleteHandoff extends grpc.MethodDefinition<handoff_pb.CompleteHandoffRequest, handoff_pb.CompleteHandoffResponse> {
    path: "/sw4rm.handoff.HandoffService/CompleteHandoff";
    requestStream: false;
    responseStream: false;
    requestSerialize: grpc.serialize<handoff_pb.CompleteHandoffRequest>;
    requestDeserialize: grpc.deserialize<handoff_pb.CompleteHandoffRequest>;
    responseSerialize: grpc.serialize<handoff_pb.CompleteHandoffResponse>;
    responseDeserialize: grpc.deserialize<handoff_pb.CompleteHandoffResponse>;
}

export const HandoffServiceService: IHandoffServiceService;

export interface IHandoffServiceServer extends grpc.UntypedServiceImplementation {
    requestHandoff: grpc.handleUnaryCall<handoff_pb.HandoffRequest, common_pb.Empty>;
    acceptHandoff: grpc.handleUnaryCall<handoff_pb.HandoffResponse, common_pb.Empty>;
    rejectHandoff: grpc.handleUnaryCall<handoff_pb.HandoffResponse, common_pb.Empty>;
    getPendingHandoffs: grpc.handleUnaryCall<handoff_pb.GetPendingHandoffsRequest, handoff_pb.GetPendingHandoffsResponse>;
    completeHandoff: grpc.handleUnaryCall<handoff_pb.CompleteHandoffRequest, handoff_pb.CompleteHandoffResponse>;
}

export interface IHandoffServiceClient {
    requestHandoff(request: handoff_pb.HandoffRequest, callback: (error: grpc.ServiceError | null, response: common_pb.Empty) => void): grpc.ClientUnaryCall;
    requestHandoff(request: handoff_pb.HandoffRequest, metadata: grpc.Metadata, callback: (error: grpc.ServiceError | null, response: common_pb.Empty) => void): grpc.ClientUnaryCall;
    requestHandoff(request: handoff_pb.HandoffRequest, metadata: grpc.Metadata, options: Partial<grpc.CallOptions>, callback: (error: grpc.ServiceError | null, response: common_pb.Empty) => void): grpc.ClientUnaryCall;
    acceptHandoff(request: handoff_pb.HandoffResponse, callback: (error: grpc.ServiceError | null, response: common_pb.Empty) => void): grpc.ClientUnaryCall;
    acceptHandoff(request: handoff_pb.HandoffResponse, metadata: grpc.Metadata, callback: (error: grpc.ServiceError | null, response: common_pb.Empty) => void): grpc.ClientUnaryCall;
    acceptHandoff(request: handoff_pb.HandoffResponse, metadata: grpc.Metadata, options: Partial<grpc.CallOptions>, callback: (error: grpc.ServiceError | null, response: common_pb.Empty) => void): grpc.ClientUnaryCall;
    rejectHandoff(request: handoff_pb.HandoffResponse, callback: (error: grpc.ServiceError | null, response: common_pb.Empty) => void): grpc.ClientUnaryCall;
    rejectHandoff(request: handoff_pb.HandoffResponse, metadata: grpc.Metadata, callback: (error: grpc.ServiceError | null, response: common_pb.Empty) => void): grpc.ClientUnaryCall;
    rejectHandoff(request: handoff_pb.HandoffResponse, metadata: grpc.Metadata, options: Partial<grpc.CallOptions>, callback: (error: grpc.ServiceError | null, response: common_pb.Empty) => void): grpc.ClientUnaryCall;
    getPendingHandoffs(request: handoff_pb.GetPendingHandoffsRequest, callback: (error: grpc.ServiceError | null, response: handoff_pb.GetPendingHandoffsResponse) => void): grpc.ClientUnaryCall;
    getPendingHandoffs(request: handoff_pb.GetPendingHandoffsRequest, metadata: grpc.Metadata, callback: (error: grpc.ServiceError | null, response: handoff_pb.GetPendingHandoffsResponse) => void): grpc.ClientUnaryCall;
    getPendingHandoffs(request: handoff_pb.GetPendingHandoffsRequest, metadata: grpc.Metadata, options: Partial<grpc.CallOptions>, callback: (error: grpc.ServiceError | null, response: handoff_pb.GetPendingHandoffsResponse) => void): grpc.ClientUnaryCall;
    completeHandoff(request: handoff_pb.CompleteHandoffRequest, callback: (error: grpc.ServiceError | null, response: handoff_pb.CompleteHandoffResponse) => void): grpc.ClientUnaryCall;
    completeHandoff(request: handoff_pb.CompleteHandoffRequest, metadata: grpc.Metadata, callback: (error: grpc.ServiceError | null, response: handoff_pb.CompleteHandoffResponse) => void): grpc.ClientUnaryCall;
    completeHandoff(request: handoff_pb.CompleteHandoffRequest, metadata: grpc.Metadata, options: Partial<grpc.CallOptions>, callback: (error: grpc.ServiceError | null, response: handoff_pb.CompleteHandoffResponse) => void): grpc.ClientUnaryCall;
}

export class HandoffServiceClient extends grpc.Client implements IHandoffServiceClient {
    constructor(address: string, credentials: grpc.ChannelCredentials, options?: Partial<grpc.ClientOptions>);
    public requestHandoff(request: handoff_pb.HandoffRequest, callback: (error: grpc.ServiceError | null, response: common_pb.Empty) => void): grpc.ClientUnaryCall;
    public requestHandoff(request: handoff_pb.HandoffRequest, metadata: grpc.Metadata, callback: (error: grpc.ServiceError | null, response: common_pb.Empty) => void): grpc.ClientUnaryCall;
    public requestHandoff(request: handoff_pb.HandoffRequest, metadata: grpc.Metadata, options: Partial<grpc.CallOptions>, callback: (error: grpc.ServiceError | null, response: common_pb.Empty) => void): grpc.ClientUnaryCall;
    public acceptHandoff(request: handoff_pb.HandoffResponse, callback: (error: grpc.ServiceError | null, response: common_pb.Empty) => void): grpc.ClientUnaryCall;
    public acceptHandoff(request: handoff_pb.HandoffResponse, metadata: grpc.Metadata, callback: (error: grpc.ServiceError | null, response: common_pb.Empty) => void): grpc.ClientUnaryCall;
    public acceptHandoff(request: handoff_pb.HandoffResponse, metadata: grpc.Metadata, options: Partial<grpc.CallOptions>, callback: (error: grpc.ServiceError | null, response: common_pb.Empty) => void): grpc.ClientUnaryCall;
    public rejectHandoff(request: handoff_pb.HandoffResponse, callback: (error: grpc.ServiceError | null, response: common_pb.Empty) => void): grpc.ClientUnaryCall;
    public rejectHandoff(request: handoff_pb.HandoffResponse, metadata: grpc.Metadata, callback: (error: grpc.ServiceError | null, response: common_pb.Empty) => void): grpc.ClientUnaryCall;
    public rejectHandoff(request: handoff_pb.HandoffResponse, metadata: grpc.Metadata, options: Partial<grpc.CallOptions>, callback: (error: grpc.ServiceError | null, response: common_pb.Empty) => void): grpc.ClientUnaryCall;
    public getPendingHandoffs(request: handoff_pb.GetPendingHandoffsRequest, callback: (error: grpc.ServiceError | null, response: handoff_pb.GetPendingHandoffsResponse) => void): grpc.ClientUnaryCall;
    public getPendingHandoffs(request: handoff_pb.GetPendingHandoffsRequest, metadata: grpc.Metadata, callback: (error: grpc.ServiceError | null, response: handoff_pb.GetPendingHandoffsResponse) => void): grpc.ClientUnaryCall;
    public getPendingHandoffs(request: handoff_pb.GetPendingHandoffsRequest, metadata: grpc.Metadata, options: Partial<grpc.CallOptions>, callback: (error: grpc.ServiceError | null, response: handoff_pb.GetPendingHandoffsResponse) => void): grpc.ClientUnaryCall;
    public completeHandoff(request: handoff_pb.CompleteHandoffRequest, callback: (error: grpc.ServiceError | null, response: handoff_pb.CompleteHandoffResponse) => void): grpc.ClientUnaryCall;
    public completeHandoff(request: handoff_pb.CompleteHandoffRequest, metadata: grpc.Metadata, callback: (error: grpc.ServiceError | null, response: handoff_pb.CompleteHandoffResponse) => void): grpc.ClientUnaryCall;
    public completeHandoff(request: handoff_pb.CompleteHandoffRequest, metadata: grpc.Metadata, options: Partial<grpc.CallOptions>, callback: (error: grpc.ServiceError | null, response: handoff_pb.CompleteHandoffResponse) => void): grpc.ClientUnaryCall;
}
