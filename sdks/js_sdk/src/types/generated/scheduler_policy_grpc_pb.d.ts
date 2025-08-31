// package: sw4rm.scheduler
// file: scheduler_policy.proto

/* tslint:disable */
/* eslint-disable */

import * as grpc from "@grpc/grpc-js";
import * as scheduler_policy_pb from "./scheduler_policy_pb";
import * as policy_pb from "./policy_pb";

interface ISchedulerPolicyServiceService extends grpc.ServiceDefinition<grpc.UntypedServiceImplementation> {
    setNegotiationPolicy: ISchedulerPolicyServiceService_ISetNegotiationPolicy;
    getNegotiationPolicy: ISchedulerPolicyServiceService_IGetNegotiationPolicy;
    setPolicyProfiles: ISchedulerPolicyServiceService_ISetPolicyProfiles;
    listPolicyProfiles: ISchedulerPolicyServiceService_IListPolicyProfiles;
    getEffectivePolicy: ISchedulerPolicyServiceService_IGetEffectivePolicy;
    submitEvaluation: ISchedulerPolicyServiceService_ISubmitEvaluation;
    hitlAction: ISchedulerPolicyServiceService_IHitlAction;
}

interface ISchedulerPolicyServiceService_ISetNegotiationPolicy extends grpc.MethodDefinition<scheduler_policy_pb.SetNegotiationPolicyRequest, scheduler_policy_pb.SetNegotiationPolicyResponse> {
    path: "/sw4rm.scheduler.SchedulerPolicyService/SetNegotiationPolicy";
    requestStream: false;
    responseStream: false;
    requestSerialize: grpc.serialize<scheduler_policy_pb.SetNegotiationPolicyRequest>;
    requestDeserialize: grpc.deserialize<scheduler_policy_pb.SetNegotiationPolicyRequest>;
    responseSerialize: grpc.serialize<scheduler_policy_pb.SetNegotiationPolicyResponse>;
    responseDeserialize: grpc.deserialize<scheduler_policy_pb.SetNegotiationPolicyResponse>;
}
interface ISchedulerPolicyServiceService_IGetNegotiationPolicy extends grpc.MethodDefinition<scheduler_policy_pb.GetNegotiationPolicyRequest, scheduler_policy_pb.GetNegotiationPolicyResponse> {
    path: "/sw4rm.scheduler.SchedulerPolicyService/GetNegotiationPolicy";
    requestStream: false;
    responseStream: false;
    requestSerialize: grpc.serialize<scheduler_policy_pb.GetNegotiationPolicyRequest>;
    requestDeserialize: grpc.deserialize<scheduler_policy_pb.GetNegotiationPolicyRequest>;
    responseSerialize: grpc.serialize<scheduler_policy_pb.GetNegotiationPolicyResponse>;
    responseDeserialize: grpc.deserialize<scheduler_policy_pb.GetNegotiationPolicyResponse>;
}
interface ISchedulerPolicyServiceService_ISetPolicyProfiles extends grpc.MethodDefinition<scheduler_policy_pb.SetPolicyProfilesRequest, scheduler_policy_pb.SetPolicyProfilesResponse> {
    path: "/sw4rm.scheduler.SchedulerPolicyService/SetPolicyProfiles";
    requestStream: false;
    responseStream: false;
    requestSerialize: grpc.serialize<scheduler_policy_pb.SetPolicyProfilesRequest>;
    requestDeserialize: grpc.deserialize<scheduler_policy_pb.SetPolicyProfilesRequest>;
    responseSerialize: grpc.serialize<scheduler_policy_pb.SetPolicyProfilesResponse>;
    responseDeserialize: grpc.deserialize<scheduler_policy_pb.SetPolicyProfilesResponse>;
}
interface ISchedulerPolicyServiceService_IListPolicyProfiles extends grpc.MethodDefinition<scheduler_policy_pb.ListPolicyProfilesRequest, scheduler_policy_pb.ListPolicyProfilesResponse> {
    path: "/sw4rm.scheduler.SchedulerPolicyService/ListPolicyProfiles";
    requestStream: false;
    responseStream: false;
    requestSerialize: grpc.serialize<scheduler_policy_pb.ListPolicyProfilesRequest>;
    requestDeserialize: grpc.deserialize<scheduler_policy_pb.ListPolicyProfilesRequest>;
    responseSerialize: grpc.serialize<scheduler_policy_pb.ListPolicyProfilesResponse>;
    responseDeserialize: grpc.deserialize<scheduler_policy_pb.ListPolicyProfilesResponse>;
}
interface ISchedulerPolicyServiceService_IGetEffectivePolicy extends grpc.MethodDefinition<scheduler_policy_pb.GetEffectivePolicyRequest, scheduler_policy_pb.GetEffectivePolicyResponse> {
    path: "/sw4rm.scheduler.SchedulerPolicyService/GetEffectivePolicy";
    requestStream: false;
    responseStream: false;
    requestSerialize: grpc.serialize<scheduler_policy_pb.GetEffectivePolicyRequest>;
    requestDeserialize: grpc.deserialize<scheduler_policy_pb.GetEffectivePolicyRequest>;
    responseSerialize: grpc.serialize<scheduler_policy_pb.GetEffectivePolicyResponse>;
    responseDeserialize: grpc.deserialize<scheduler_policy_pb.GetEffectivePolicyResponse>;
}
interface ISchedulerPolicyServiceService_ISubmitEvaluation extends grpc.MethodDefinition<scheduler_policy_pb.SubmitEvaluationRequest, scheduler_policy_pb.SubmitEvaluationResponse> {
    path: "/sw4rm.scheduler.SchedulerPolicyService/SubmitEvaluation";
    requestStream: false;
    responseStream: false;
    requestSerialize: grpc.serialize<scheduler_policy_pb.SubmitEvaluationRequest>;
    requestDeserialize: grpc.deserialize<scheduler_policy_pb.SubmitEvaluationRequest>;
    responseSerialize: grpc.serialize<scheduler_policy_pb.SubmitEvaluationResponse>;
    responseDeserialize: grpc.deserialize<scheduler_policy_pb.SubmitEvaluationResponse>;
}
interface ISchedulerPolicyServiceService_IHitlAction extends grpc.MethodDefinition<scheduler_policy_pb.HitlActionRequest, scheduler_policy_pb.HitlActionResponse> {
    path: "/sw4rm.scheduler.SchedulerPolicyService/HitlAction";
    requestStream: false;
    responseStream: false;
    requestSerialize: grpc.serialize<scheduler_policy_pb.HitlActionRequest>;
    requestDeserialize: grpc.deserialize<scheduler_policy_pb.HitlActionRequest>;
    responseSerialize: grpc.serialize<scheduler_policy_pb.HitlActionResponse>;
    responseDeserialize: grpc.deserialize<scheduler_policy_pb.HitlActionResponse>;
}

export const SchedulerPolicyServiceService: ISchedulerPolicyServiceService;

export interface ISchedulerPolicyServiceServer extends grpc.UntypedServiceImplementation {
    setNegotiationPolicy: grpc.handleUnaryCall<scheduler_policy_pb.SetNegotiationPolicyRequest, scheduler_policy_pb.SetNegotiationPolicyResponse>;
    getNegotiationPolicy: grpc.handleUnaryCall<scheduler_policy_pb.GetNegotiationPolicyRequest, scheduler_policy_pb.GetNegotiationPolicyResponse>;
    setPolicyProfiles: grpc.handleUnaryCall<scheduler_policy_pb.SetPolicyProfilesRequest, scheduler_policy_pb.SetPolicyProfilesResponse>;
    listPolicyProfiles: grpc.handleUnaryCall<scheduler_policy_pb.ListPolicyProfilesRequest, scheduler_policy_pb.ListPolicyProfilesResponse>;
    getEffectivePolicy: grpc.handleUnaryCall<scheduler_policy_pb.GetEffectivePolicyRequest, scheduler_policy_pb.GetEffectivePolicyResponse>;
    submitEvaluation: grpc.handleUnaryCall<scheduler_policy_pb.SubmitEvaluationRequest, scheduler_policy_pb.SubmitEvaluationResponse>;
    hitlAction: grpc.handleUnaryCall<scheduler_policy_pb.HitlActionRequest, scheduler_policy_pb.HitlActionResponse>;
}

export interface ISchedulerPolicyServiceClient {
    setNegotiationPolicy(request: scheduler_policy_pb.SetNegotiationPolicyRequest, callback: (error: grpc.ServiceError | null, response: scheduler_policy_pb.SetNegotiationPolicyResponse) => void): grpc.ClientUnaryCall;
    setNegotiationPolicy(request: scheduler_policy_pb.SetNegotiationPolicyRequest, metadata: grpc.Metadata, callback: (error: grpc.ServiceError | null, response: scheduler_policy_pb.SetNegotiationPolicyResponse) => void): grpc.ClientUnaryCall;
    setNegotiationPolicy(request: scheduler_policy_pb.SetNegotiationPolicyRequest, metadata: grpc.Metadata, options: Partial<grpc.CallOptions>, callback: (error: grpc.ServiceError | null, response: scheduler_policy_pb.SetNegotiationPolicyResponse) => void): grpc.ClientUnaryCall;
    getNegotiationPolicy(request: scheduler_policy_pb.GetNegotiationPolicyRequest, callback: (error: grpc.ServiceError | null, response: scheduler_policy_pb.GetNegotiationPolicyResponse) => void): grpc.ClientUnaryCall;
    getNegotiationPolicy(request: scheduler_policy_pb.GetNegotiationPolicyRequest, metadata: grpc.Metadata, callback: (error: grpc.ServiceError | null, response: scheduler_policy_pb.GetNegotiationPolicyResponse) => void): grpc.ClientUnaryCall;
    getNegotiationPolicy(request: scheduler_policy_pb.GetNegotiationPolicyRequest, metadata: grpc.Metadata, options: Partial<grpc.CallOptions>, callback: (error: grpc.ServiceError | null, response: scheduler_policy_pb.GetNegotiationPolicyResponse) => void): grpc.ClientUnaryCall;
    setPolicyProfiles(request: scheduler_policy_pb.SetPolicyProfilesRequest, callback: (error: grpc.ServiceError | null, response: scheduler_policy_pb.SetPolicyProfilesResponse) => void): grpc.ClientUnaryCall;
    setPolicyProfiles(request: scheduler_policy_pb.SetPolicyProfilesRequest, metadata: grpc.Metadata, callback: (error: grpc.ServiceError | null, response: scheduler_policy_pb.SetPolicyProfilesResponse) => void): grpc.ClientUnaryCall;
    setPolicyProfiles(request: scheduler_policy_pb.SetPolicyProfilesRequest, metadata: grpc.Metadata, options: Partial<grpc.CallOptions>, callback: (error: grpc.ServiceError | null, response: scheduler_policy_pb.SetPolicyProfilesResponse) => void): grpc.ClientUnaryCall;
    listPolicyProfiles(request: scheduler_policy_pb.ListPolicyProfilesRequest, callback: (error: grpc.ServiceError | null, response: scheduler_policy_pb.ListPolicyProfilesResponse) => void): grpc.ClientUnaryCall;
    listPolicyProfiles(request: scheduler_policy_pb.ListPolicyProfilesRequest, metadata: grpc.Metadata, callback: (error: grpc.ServiceError | null, response: scheduler_policy_pb.ListPolicyProfilesResponse) => void): grpc.ClientUnaryCall;
    listPolicyProfiles(request: scheduler_policy_pb.ListPolicyProfilesRequest, metadata: grpc.Metadata, options: Partial<grpc.CallOptions>, callback: (error: grpc.ServiceError | null, response: scheduler_policy_pb.ListPolicyProfilesResponse) => void): grpc.ClientUnaryCall;
    getEffectivePolicy(request: scheduler_policy_pb.GetEffectivePolicyRequest, callback: (error: grpc.ServiceError | null, response: scheduler_policy_pb.GetEffectivePolicyResponse) => void): grpc.ClientUnaryCall;
    getEffectivePolicy(request: scheduler_policy_pb.GetEffectivePolicyRequest, metadata: grpc.Metadata, callback: (error: grpc.ServiceError | null, response: scheduler_policy_pb.GetEffectivePolicyResponse) => void): grpc.ClientUnaryCall;
    getEffectivePolicy(request: scheduler_policy_pb.GetEffectivePolicyRequest, metadata: grpc.Metadata, options: Partial<grpc.CallOptions>, callback: (error: grpc.ServiceError | null, response: scheduler_policy_pb.GetEffectivePolicyResponse) => void): grpc.ClientUnaryCall;
    submitEvaluation(request: scheduler_policy_pb.SubmitEvaluationRequest, callback: (error: grpc.ServiceError | null, response: scheduler_policy_pb.SubmitEvaluationResponse) => void): grpc.ClientUnaryCall;
    submitEvaluation(request: scheduler_policy_pb.SubmitEvaluationRequest, metadata: grpc.Metadata, callback: (error: grpc.ServiceError | null, response: scheduler_policy_pb.SubmitEvaluationResponse) => void): grpc.ClientUnaryCall;
    submitEvaluation(request: scheduler_policy_pb.SubmitEvaluationRequest, metadata: grpc.Metadata, options: Partial<grpc.CallOptions>, callback: (error: grpc.ServiceError | null, response: scheduler_policy_pb.SubmitEvaluationResponse) => void): grpc.ClientUnaryCall;
    hitlAction(request: scheduler_policy_pb.HitlActionRequest, callback: (error: grpc.ServiceError | null, response: scheduler_policy_pb.HitlActionResponse) => void): grpc.ClientUnaryCall;
    hitlAction(request: scheduler_policy_pb.HitlActionRequest, metadata: grpc.Metadata, callback: (error: grpc.ServiceError | null, response: scheduler_policy_pb.HitlActionResponse) => void): grpc.ClientUnaryCall;
    hitlAction(request: scheduler_policy_pb.HitlActionRequest, metadata: grpc.Metadata, options: Partial<grpc.CallOptions>, callback: (error: grpc.ServiceError | null, response: scheduler_policy_pb.HitlActionResponse) => void): grpc.ClientUnaryCall;
}

export class SchedulerPolicyServiceClient extends grpc.Client implements ISchedulerPolicyServiceClient {
    constructor(address: string, credentials: grpc.ChannelCredentials, options?: Partial<grpc.ClientOptions>);
    public setNegotiationPolicy(request: scheduler_policy_pb.SetNegotiationPolicyRequest, callback: (error: grpc.ServiceError | null, response: scheduler_policy_pb.SetNegotiationPolicyResponse) => void): grpc.ClientUnaryCall;
    public setNegotiationPolicy(request: scheduler_policy_pb.SetNegotiationPolicyRequest, metadata: grpc.Metadata, callback: (error: grpc.ServiceError | null, response: scheduler_policy_pb.SetNegotiationPolicyResponse) => void): grpc.ClientUnaryCall;
    public setNegotiationPolicy(request: scheduler_policy_pb.SetNegotiationPolicyRequest, metadata: grpc.Metadata, options: Partial<grpc.CallOptions>, callback: (error: grpc.ServiceError | null, response: scheduler_policy_pb.SetNegotiationPolicyResponse) => void): grpc.ClientUnaryCall;
    public getNegotiationPolicy(request: scheduler_policy_pb.GetNegotiationPolicyRequest, callback: (error: grpc.ServiceError | null, response: scheduler_policy_pb.GetNegotiationPolicyResponse) => void): grpc.ClientUnaryCall;
    public getNegotiationPolicy(request: scheduler_policy_pb.GetNegotiationPolicyRequest, metadata: grpc.Metadata, callback: (error: grpc.ServiceError | null, response: scheduler_policy_pb.GetNegotiationPolicyResponse) => void): grpc.ClientUnaryCall;
    public getNegotiationPolicy(request: scheduler_policy_pb.GetNegotiationPolicyRequest, metadata: grpc.Metadata, options: Partial<grpc.CallOptions>, callback: (error: grpc.ServiceError | null, response: scheduler_policy_pb.GetNegotiationPolicyResponse) => void): grpc.ClientUnaryCall;
    public setPolicyProfiles(request: scheduler_policy_pb.SetPolicyProfilesRequest, callback: (error: grpc.ServiceError | null, response: scheduler_policy_pb.SetPolicyProfilesResponse) => void): grpc.ClientUnaryCall;
    public setPolicyProfiles(request: scheduler_policy_pb.SetPolicyProfilesRequest, metadata: grpc.Metadata, callback: (error: grpc.ServiceError | null, response: scheduler_policy_pb.SetPolicyProfilesResponse) => void): grpc.ClientUnaryCall;
    public setPolicyProfiles(request: scheduler_policy_pb.SetPolicyProfilesRequest, metadata: grpc.Metadata, options: Partial<grpc.CallOptions>, callback: (error: grpc.ServiceError | null, response: scheduler_policy_pb.SetPolicyProfilesResponse) => void): grpc.ClientUnaryCall;
    public listPolicyProfiles(request: scheduler_policy_pb.ListPolicyProfilesRequest, callback: (error: grpc.ServiceError | null, response: scheduler_policy_pb.ListPolicyProfilesResponse) => void): grpc.ClientUnaryCall;
    public listPolicyProfiles(request: scheduler_policy_pb.ListPolicyProfilesRequest, metadata: grpc.Metadata, callback: (error: grpc.ServiceError | null, response: scheduler_policy_pb.ListPolicyProfilesResponse) => void): grpc.ClientUnaryCall;
    public listPolicyProfiles(request: scheduler_policy_pb.ListPolicyProfilesRequest, metadata: grpc.Metadata, options: Partial<grpc.CallOptions>, callback: (error: grpc.ServiceError | null, response: scheduler_policy_pb.ListPolicyProfilesResponse) => void): grpc.ClientUnaryCall;
    public getEffectivePolicy(request: scheduler_policy_pb.GetEffectivePolicyRequest, callback: (error: grpc.ServiceError | null, response: scheduler_policy_pb.GetEffectivePolicyResponse) => void): grpc.ClientUnaryCall;
    public getEffectivePolicy(request: scheduler_policy_pb.GetEffectivePolicyRequest, metadata: grpc.Metadata, callback: (error: grpc.ServiceError | null, response: scheduler_policy_pb.GetEffectivePolicyResponse) => void): grpc.ClientUnaryCall;
    public getEffectivePolicy(request: scheduler_policy_pb.GetEffectivePolicyRequest, metadata: grpc.Metadata, options: Partial<grpc.CallOptions>, callback: (error: grpc.ServiceError | null, response: scheduler_policy_pb.GetEffectivePolicyResponse) => void): grpc.ClientUnaryCall;
    public submitEvaluation(request: scheduler_policy_pb.SubmitEvaluationRequest, callback: (error: grpc.ServiceError | null, response: scheduler_policy_pb.SubmitEvaluationResponse) => void): grpc.ClientUnaryCall;
    public submitEvaluation(request: scheduler_policy_pb.SubmitEvaluationRequest, metadata: grpc.Metadata, callback: (error: grpc.ServiceError | null, response: scheduler_policy_pb.SubmitEvaluationResponse) => void): grpc.ClientUnaryCall;
    public submitEvaluation(request: scheduler_policy_pb.SubmitEvaluationRequest, metadata: grpc.Metadata, options: Partial<grpc.CallOptions>, callback: (error: grpc.ServiceError | null, response: scheduler_policy_pb.SubmitEvaluationResponse) => void): grpc.ClientUnaryCall;
    public hitlAction(request: scheduler_policy_pb.HitlActionRequest, callback: (error: grpc.ServiceError | null, response: scheduler_policy_pb.HitlActionResponse) => void): grpc.ClientUnaryCall;
    public hitlAction(request: scheduler_policy_pb.HitlActionRequest, metadata: grpc.Metadata, callback: (error: grpc.ServiceError | null, response: scheduler_policy_pb.HitlActionResponse) => void): grpc.ClientUnaryCall;
    public hitlAction(request: scheduler_policy_pb.HitlActionRequest, metadata: grpc.Metadata, options: Partial<grpc.CallOptions>, callback: (error: grpc.ServiceError | null, response: scheduler_policy_pb.HitlActionResponse) => void): grpc.ClientUnaryCall;
}
