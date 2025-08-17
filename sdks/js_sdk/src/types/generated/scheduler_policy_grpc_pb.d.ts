// package: sw4rm.scheduler
// file: scheduler_policy.proto

/* tslint:disable */
/* eslint-disable */

import * as grpc from "@grpc/grpc-js";
import * as scheduler_policy_pb from "./scheduler_policy_pb";
import * as policy_pb from "./policy_pb";

interface ISchedulerPolicyServiceService extends grpc.ServiceDefinition<grpc.UntypedServiceImplementation> {
    setWagglePolicy: ISchedulerPolicyServiceService_ISetWagglePolicy;
    getWagglePolicy: ISchedulerPolicyServiceService_IGetWagglePolicy;
    setPolicyProfiles: ISchedulerPolicyServiceService_ISetPolicyProfiles;
    listPolicyProfiles: ISchedulerPolicyServiceService_IListPolicyProfiles;
    getEffectivePolicy: ISchedulerPolicyServiceService_IGetEffectivePolicy;
    submitEvaluation: ISchedulerPolicyServiceService_ISubmitEvaluation;
    hitlAction: ISchedulerPolicyServiceService_IHitlAction;
}

interface ISchedulerPolicyServiceService_ISetWagglePolicy extends grpc.MethodDefinition<scheduler_policy_pb.SetWagglePolicyRequest, scheduler_policy_pb.SetWagglePolicyResponse> {
    path: "/sw4rm.scheduler.SchedulerPolicyService/SetWagglePolicy";
    requestStream: false;
    responseStream: false;
    requestSerialize: grpc.serialize<scheduler_policy_pb.SetWagglePolicyRequest>;
    requestDeserialize: grpc.deserialize<scheduler_policy_pb.SetWagglePolicyRequest>;
    responseSerialize: grpc.serialize<scheduler_policy_pb.SetWagglePolicyResponse>;
    responseDeserialize: grpc.deserialize<scheduler_policy_pb.SetWagglePolicyResponse>;
}
interface ISchedulerPolicyServiceService_IGetWagglePolicy extends grpc.MethodDefinition<scheduler_policy_pb.GetWagglePolicyRequest, scheduler_policy_pb.GetWagglePolicyResponse> {
    path: "/sw4rm.scheduler.SchedulerPolicyService/GetWagglePolicy";
    requestStream: false;
    responseStream: false;
    requestSerialize: grpc.serialize<scheduler_policy_pb.GetWagglePolicyRequest>;
    requestDeserialize: grpc.deserialize<scheduler_policy_pb.GetWagglePolicyRequest>;
    responseSerialize: grpc.serialize<scheduler_policy_pb.GetWagglePolicyResponse>;
    responseDeserialize: grpc.deserialize<scheduler_policy_pb.GetWagglePolicyResponse>;
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
    setWagglePolicy: grpc.handleUnaryCall<scheduler_policy_pb.SetWagglePolicyRequest, scheduler_policy_pb.SetWagglePolicyResponse>;
    getWagglePolicy: grpc.handleUnaryCall<scheduler_policy_pb.GetWagglePolicyRequest, scheduler_policy_pb.GetWagglePolicyResponse>;
    setPolicyProfiles: grpc.handleUnaryCall<scheduler_policy_pb.SetPolicyProfilesRequest, scheduler_policy_pb.SetPolicyProfilesResponse>;
    listPolicyProfiles: grpc.handleUnaryCall<scheduler_policy_pb.ListPolicyProfilesRequest, scheduler_policy_pb.ListPolicyProfilesResponse>;
    getEffectivePolicy: grpc.handleUnaryCall<scheduler_policy_pb.GetEffectivePolicyRequest, scheduler_policy_pb.GetEffectivePolicyResponse>;
    submitEvaluation: grpc.handleUnaryCall<scheduler_policy_pb.SubmitEvaluationRequest, scheduler_policy_pb.SubmitEvaluationResponse>;
    hitlAction: grpc.handleUnaryCall<scheduler_policy_pb.HitlActionRequest, scheduler_policy_pb.HitlActionResponse>;
}

export interface ISchedulerPolicyServiceClient {
    setWagglePolicy(request: scheduler_policy_pb.SetWagglePolicyRequest, callback: (error: grpc.ServiceError | null, response: scheduler_policy_pb.SetWagglePolicyResponse) => void): grpc.ClientUnaryCall;
    setWagglePolicy(request: scheduler_policy_pb.SetWagglePolicyRequest, metadata: grpc.Metadata, callback: (error: grpc.ServiceError | null, response: scheduler_policy_pb.SetWagglePolicyResponse) => void): grpc.ClientUnaryCall;
    setWagglePolicy(request: scheduler_policy_pb.SetWagglePolicyRequest, metadata: grpc.Metadata, options: Partial<grpc.CallOptions>, callback: (error: grpc.ServiceError | null, response: scheduler_policy_pb.SetWagglePolicyResponse) => void): grpc.ClientUnaryCall;
    getWagglePolicy(request: scheduler_policy_pb.GetWagglePolicyRequest, callback: (error: grpc.ServiceError | null, response: scheduler_policy_pb.GetWagglePolicyResponse) => void): grpc.ClientUnaryCall;
    getWagglePolicy(request: scheduler_policy_pb.GetWagglePolicyRequest, metadata: grpc.Metadata, callback: (error: grpc.ServiceError | null, response: scheduler_policy_pb.GetWagglePolicyResponse) => void): grpc.ClientUnaryCall;
    getWagglePolicy(request: scheduler_policy_pb.GetWagglePolicyRequest, metadata: grpc.Metadata, options: Partial<grpc.CallOptions>, callback: (error: grpc.ServiceError | null, response: scheduler_policy_pb.GetWagglePolicyResponse) => void): grpc.ClientUnaryCall;
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
    public setWagglePolicy(request: scheduler_policy_pb.SetWagglePolicyRequest, callback: (error: grpc.ServiceError | null, response: scheduler_policy_pb.SetWagglePolicyResponse) => void): grpc.ClientUnaryCall;
    public setWagglePolicy(request: scheduler_policy_pb.SetWagglePolicyRequest, metadata: grpc.Metadata, callback: (error: grpc.ServiceError | null, response: scheduler_policy_pb.SetWagglePolicyResponse) => void): grpc.ClientUnaryCall;
    public setWagglePolicy(request: scheduler_policy_pb.SetWagglePolicyRequest, metadata: grpc.Metadata, options: Partial<grpc.CallOptions>, callback: (error: grpc.ServiceError | null, response: scheduler_policy_pb.SetWagglePolicyResponse) => void): grpc.ClientUnaryCall;
    public getWagglePolicy(request: scheduler_policy_pb.GetWagglePolicyRequest, callback: (error: grpc.ServiceError | null, response: scheduler_policy_pb.GetWagglePolicyResponse) => void): grpc.ClientUnaryCall;
    public getWagglePolicy(request: scheduler_policy_pb.GetWagglePolicyRequest, metadata: grpc.Metadata, callback: (error: grpc.ServiceError | null, response: scheduler_policy_pb.GetWagglePolicyResponse) => void): grpc.ClientUnaryCall;
    public getWagglePolicy(request: scheduler_policy_pb.GetWagglePolicyRequest, metadata: grpc.Metadata, options: Partial<grpc.CallOptions>, callback: (error: grpc.ServiceError | null, response: scheduler_policy_pb.GetWagglePolicyResponse) => void): grpc.ClientUnaryCall;
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
