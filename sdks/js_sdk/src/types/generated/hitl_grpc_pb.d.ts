// package: sw4rm.hitl
// file: hitl.proto

/* tslint:disable */
/* eslint-disable */

import * as grpc from "@grpc/grpc-js";
import * as hitl_pb from "./hitl_pb";
import * as common_pb from "./common_pb";

interface IHitlServiceService extends grpc.ServiceDefinition<grpc.UntypedServiceImplementation> {
    decide: IHitlServiceService_IDecide;
}

interface IHitlServiceService_IDecide extends grpc.MethodDefinition<hitl_pb.HitlInvocation, hitl_pb.HitlDecision> {
    path: "/sw4rm.hitl.HitlService/Decide";
    requestStream: false;
    responseStream: false;
    requestSerialize: grpc.serialize<hitl_pb.HitlInvocation>;
    requestDeserialize: grpc.deserialize<hitl_pb.HitlInvocation>;
    responseSerialize: grpc.serialize<hitl_pb.HitlDecision>;
    responseDeserialize: grpc.deserialize<hitl_pb.HitlDecision>;
}

export const HitlServiceService: IHitlServiceService;

export interface IHitlServiceServer extends grpc.UntypedServiceImplementation {
    decide: grpc.handleUnaryCall<hitl_pb.HitlInvocation, hitl_pb.HitlDecision>;
}

export interface IHitlServiceClient {
    decide(request: hitl_pb.HitlInvocation, callback: (error: grpc.ServiceError | null, response: hitl_pb.HitlDecision) => void): grpc.ClientUnaryCall;
    decide(request: hitl_pb.HitlInvocation, metadata: grpc.Metadata, callback: (error: grpc.ServiceError | null, response: hitl_pb.HitlDecision) => void): grpc.ClientUnaryCall;
    decide(request: hitl_pb.HitlInvocation, metadata: grpc.Metadata, options: Partial<grpc.CallOptions>, callback: (error: grpc.ServiceError | null, response: hitl_pb.HitlDecision) => void): grpc.ClientUnaryCall;
}

export class HitlServiceClient extends grpc.Client implements IHitlServiceClient {
    constructor(address: string, credentials: grpc.ChannelCredentials, options?: Partial<grpc.ClientOptions>);
    public decide(request: hitl_pb.HitlInvocation, callback: (error: grpc.ServiceError | null, response: hitl_pb.HitlDecision) => void): grpc.ClientUnaryCall;
    public decide(request: hitl_pb.HitlInvocation, metadata: grpc.Metadata, callback: (error: grpc.ServiceError | null, response: hitl_pb.HitlDecision) => void): grpc.ClientUnaryCall;
    public decide(request: hitl_pb.HitlInvocation, metadata: grpc.Metadata, options: Partial<grpc.CallOptions>, callback: (error: grpc.ServiceError | null, response: hitl_pb.HitlDecision) => void): grpc.ClientUnaryCall;
}
