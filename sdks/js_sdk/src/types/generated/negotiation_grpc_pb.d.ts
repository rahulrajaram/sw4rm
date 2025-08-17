// package: sw4rm.negotiation
// file: negotiation.proto

/* tslint:disable */
/* eslint-disable */

import * as grpc from "@grpc/grpc-js";
import * as negotiation_pb from "./negotiation_pb";
import * as common_pb from "./common_pb";
import * as google_protobuf_duration_pb from "google-protobuf/google/protobuf/duration_pb";

interface INegotiationServiceService extends grpc.ServiceDefinition<grpc.UntypedServiceImplementation> {
    open: INegotiationServiceService_IOpen;
    propose: INegotiationServiceService_IPropose;
    counter: INegotiationServiceService_ICounter;
    evaluate: INegotiationServiceService_IEvaluate;
    decide: INegotiationServiceService_IDecide;
    abort: INegotiationServiceService_IAbort;
}

interface INegotiationServiceService_IOpen extends grpc.MethodDefinition<negotiation_pb.NegotiationOpen, common_pb.Empty> {
    path: "/sw4rm.negotiation.NegotiationService/Open";
    requestStream: false;
    responseStream: false;
    requestSerialize: grpc.serialize<negotiation_pb.NegotiationOpen>;
    requestDeserialize: grpc.deserialize<negotiation_pb.NegotiationOpen>;
    responseSerialize: grpc.serialize<common_pb.Empty>;
    responseDeserialize: grpc.deserialize<common_pb.Empty>;
}
interface INegotiationServiceService_IPropose extends grpc.MethodDefinition<negotiation_pb.Proposal, common_pb.Empty> {
    path: "/sw4rm.negotiation.NegotiationService/Propose";
    requestStream: false;
    responseStream: false;
    requestSerialize: grpc.serialize<negotiation_pb.Proposal>;
    requestDeserialize: grpc.deserialize<negotiation_pb.Proposal>;
    responseSerialize: grpc.serialize<common_pb.Empty>;
    responseDeserialize: grpc.deserialize<common_pb.Empty>;
}
interface INegotiationServiceService_ICounter extends grpc.MethodDefinition<negotiation_pb.CounterProposal, common_pb.Empty> {
    path: "/sw4rm.negotiation.NegotiationService/Counter";
    requestStream: false;
    responseStream: false;
    requestSerialize: grpc.serialize<negotiation_pb.CounterProposal>;
    requestDeserialize: grpc.deserialize<negotiation_pb.CounterProposal>;
    responseSerialize: grpc.serialize<common_pb.Empty>;
    responseDeserialize: grpc.deserialize<common_pb.Empty>;
}
interface INegotiationServiceService_IEvaluate extends grpc.MethodDefinition<negotiation_pb.Evaluation, common_pb.Empty> {
    path: "/sw4rm.negotiation.NegotiationService/Evaluate";
    requestStream: false;
    responseStream: false;
    requestSerialize: grpc.serialize<negotiation_pb.Evaluation>;
    requestDeserialize: grpc.deserialize<negotiation_pb.Evaluation>;
    responseSerialize: grpc.serialize<common_pb.Empty>;
    responseDeserialize: grpc.deserialize<common_pb.Empty>;
}
interface INegotiationServiceService_IDecide extends grpc.MethodDefinition<negotiation_pb.Decision, common_pb.Empty> {
    path: "/sw4rm.negotiation.NegotiationService/Decide";
    requestStream: false;
    responseStream: false;
    requestSerialize: grpc.serialize<negotiation_pb.Decision>;
    requestDeserialize: grpc.deserialize<negotiation_pb.Decision>;
    responseSerialize: grpc.serialize<common_pb.Empty>;
    responseDeserialize: grpc.deserialize<common_pb.Empty>;
}
interface INegotiationServiceService_IAbort extends grpc.MethodDefinition<negotiation_pb.AbortRequest, common_pb.Empty> {
    path: "/sw4rm.negotiation.NegotiationService/Abort";
    requestStream: false;
    responseStream: false;
    requestSerialize: grpc.serialize<negotiation_pb.AbortRequest>;
    requestDeserialize: grpc.deserialize<negotiation_pb.AbortRequest>;
    responseSerialize: grpc.serialize<common_pb.Empty>;
    responseDeserialize: grpc.deserialize<common_pb.Empty>;
}

export const NegotiationServiceService: INegotiationServiceService;

export interface INegotiationServiceServer extends grpc.UntypedServiceImplementation {
    open: grpc.handleUnaryCall<negotiation_pb.NegotiationOpen, common_pb.Empty>;
    propose: grpc.handleUnaryCall<negotiation_pb.Proposal, common_pb.Empty>;
    counter: grpc.handleUnaryCall<negotiation_pb.CounterProposal, common_pb.Empty>;
    evaluate: grpc.handleUnaryCall<negotiation_pb.Evaluation, common_pb.Empty>;
    decide: grpc.handleUnaryCall<negotiation_pb.Decision, common_pb.Empty>;
    abort: grpc.handleUnaryCall<negotiation_pb.AbortRequest, common_pb.Empty>;
}

export interface INegotiationServiceClient {
    open(request: negotiation_pb.NegotiationOpen, callback: (error: grpc.ServiceError | null, response: common_pb.Empty) => void): grpc.ClientUnaryCall;
    open(request: negotiation_pb.NegotiationOpen, metadata: grpc.Metadata, callback: (error: grpc.ServiceError | null, response: common_pb.Empty) => void): grpc.ClientUnaryCall;
    open(request: negotiation_pb.NegotiationOpen, metadata: grpc.Metadata, options: Partial<grpc.CallOptions>, callback: (error: grpc.ServiceError | null, response: common_pb.Empty) => void): grpc.ClientUnaryCall;
    propose(request: negotiation_pb.Proposal, callback: (error: grpc.ServiceError | null, response: common_pb.Empty) => void): grpc.ClientUnaryCall;
    propose(request: negotiation_pb.Proposal, metadata: grpc.Metadata, callback: (error: grpc.ServiceError | null, response: common_pb.Empty) => void): grpc.ClientUnaryCall;
    propose(request: negotiation_pb.Proposal, metadata: grpc.Metadata, options: Partial<grpc.CallOptions>, callback: (error: grpc.ServiceError | null, response: common_pb.Empty) => void): grpc.ClientUnaryCall;
    counter(request: negotiation_pb.CounterProposal, callback: (error: grpc.ServiceError | null, response: common_pb.Empty) => void): grpc.ClientUnaryCall;
    counter(request: negotiation_pb.CounterProposal, metadata: grpc.Metadata, callback: (error: grpc.ServiceError | null, response: common_pb.Empty) => void): grpc.ClientUnaryCall;
    counter(request: negotiation_pb.CounterProposal, metadata: grpc.Metadata, options: Partial<grpc.CallOptions>, callback: (error: grpc.ServiceError | null, response: common_pb.Empty) => void): grpc.ClientUnaryCall;
    evaluate(request: negotiation_pb.Evaluation, callback: (error: grpc.ServiceError | null, response: common_pb.Empty) => void): grpc.ClientUnaryCall;
    evaluate(request: negotiation_pb.Evaluation, metadata: grpc.Metadata, callback: (error: grpc.ServiceError | null, response: common_pb.Empty) => void): grpc.ClientUnaryCall;
    evaluate(request: negotiation_pb.Evaluation, metadata: grpc.Metadata, options: Partial<grpc.CallOptions>, callback: (error: grpc.ServiceError | null, response: common_pb.Empty) => void): grpc.ClientUnaryCall;
    decide(request: negotiation_pb.Decision, callback: (error: grpc.ServiceError | null, response: common_pb.Empty) => void): grpc.ClientUnaryCall;
    decide(request: negotiation_pb.Decision, metadata: grpc.Metadata, callback: (error: grpc.ServiceError | null, response: common_pb.Empty) => void): grpc.ClientUnaryCall;
    decide(request: negotiation_pb.Decision, metadata: grpc.Metadata, options: Partial<grpc.CallOptions>, callback: (error: grpc.ServiceError | null, response: common_pb.Empty) => void): grpc.ClientUnaryCall;
    abort(request: negotiation_pb.AbortRequest, callback: (error: grpc.ServiceError | null, response: common_pb.Empty) => void): grpc.ClientUnaryCall;
    abort(request: negotiation_pb.AbortRequest, metadata: grpc.Metadata, callback: (error: grpc.ServiceError | null, response: common_pb.Empty) => void): grpc.ClientUnaryCall;
    abort(request: negotiation_pb.AbortRequest, metadata: grpc.Metadata, options: Partial<grpc.CallOptions>, callback: (error: grpc.ServiceError | null, response: common_pb.Empty) => void): grpc.ClientUnaryCall;
}

export class NegotiationServiceClient extends grpc.Client implements INegotiationServiceClient {
    constructor(address: string, credentials: grpc.ChannelCredentials, options?: Partial<grpc.ClientOptions>);
    public open(request: negotiation_pb.NegotiationOpen, callback: (error: grpc.ServiceError | null, response: common_pb.Empty) => void): grpc.ClientUnaryCall;
    public open(request: negotiation_pb.NegotiationOpen, metadata: grpc.Metadata, callback: (error: grpc.ServiceError | null, response: common_pb.Empty) => void): grpc.ClientUnaryCall;
    public open(request: negotiation_pb.NegotiationOpen, metadata: grpc.Metadata, options: Partial<grpc.CallOptions>, callback: (error: grpc.ServiceError | null, response: common_pb.Empty) => void): grpc.ClientUnaryCall;
    public propose(request: negotiation_pb.Proposal, callback: (error: grpc.ServiceError | null, response: common_pb.Empty) => void): grpc.ClientUnaryCall;
    public propose(request: negotiation_pb.Proposal, metadata: grpc.Metadata, callback: (error: grpc.ServiceError | null, response: common_pb.Empty) => void): grpc.ClientUnaryCall;
    public propose(request: negotiation_pb.Proposal, metadata: grpc.Metadata, options: Partial<grpc.CallOptions>, callback: (error: grpc.ServiceError | null, response: common_pb.Empty) => void): grpc.ClientUnaryCall;
    public counter(request: negotiation_pb.CounterProposal, callback: (error: grpc.ServiceError | null, response: common_pb.Empty) => void): grpc.ClientUnaryCall;
    public counter(request: negotiation_pb.CounterProposal, metadata: grpc.Metadata, callback: (error: grpc.ServiceError | null, response: common_pb.Empty) => void): grpc.ClientUnaryCall;
    public counter(request: negotiation_pb.CounterProposal, metadata: grpc.Metadata, options: Partial<grpc.CallOptions>, callback: (error: grpc.ServiceError | null, response: common_pb.Empty) => void): grpc.ClientUnaryCall;
    public evaluate(request: negotiation_pb.Evaluation, callback: (error: grpc.ServiceError | null, response: common_pb.Empty) => void): grpc.ClientUnaryCall;
    public evaluate(request: negotiation_pb.Evaluation, metadata: grpc.Metadata, callback: (error: grpc.ServiceError | null, response: common_pb.Empty) => void): grpc.ClientUnaryCall;
    public evaluate(request: negotiation_pb.Evaluation, metadata: grpc.Metadata, options: Partial<grpc.CallOptions>, callback: (error: grpc.ServiceError | null, response: common_pb.Empty) => void): grpc.ClientUnaryCall;
    public decide(request: negotiation_pb.Decision, callback: (error: grpc.ServiceError | null, response: common_pb.Empty) => void): grpc.ClientUnaryCall;
    public decide(request: negotiation_pb.Decision, metadata: grpc.Metadata, callback: (error: grpc.ServiceError | null, response: common_pb.Empty) => void): grpc.ClientUnaryCall;
    public decide(request: negotiation_pb.Decision, metadata: grpc.Metadata, options: Partial<grpc.CallOptions>, callback: (error: grpc.ServiceError | null, response: common_pb.Empty) => void): grpc.ClientUnaryCall;
    public abort(request: negotiation_pb.AbortRequest, callback: (error: grpc.ServiceError | null, response: common_pb.Empty) => void): grpc.ClientUnaryCall;
    public abort(request: negotiation_pb.AbortRequest, metadata: grpc.Metadata, callback: (error: grpc.ServiceError | null, response: common_pb.Empty) => void): grpc.ClientUnaryCall;
    public abort(request: negotiation_pb.AbortRequest, metadata: grpc.Metadata, options: Partial<grpc.CallOptions>, callback: (error: grpc.ServiceError | null, response: common_pb.Empty) => void): grpc.ClientUnaryCall;
}
