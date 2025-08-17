// package: sw4rm.worktree
// file: worktree.proto

/* tslint:disable */
/* eslint-disable */

import * as grpc from "@grpc/grpc-js";
import * as worktree_pb from "./worktree_pb";

interface IWorktreeServiceService extends grpc.ServiceDefinition<grpc.UntypedServiceImplementation> {
    bind: IWorktreeServiceService_IBind;
    unbind: IWorktreeServiceService_IUnbind;
    requestSwitch: IWorktreeServiceService_IRequestSwitch;
    approveSwitch: IWorktreeServiceService_IApproveSwitch;
    rejectSwitch: IWorktreeServiceService_IRejectSwitch;
    status: IWorktreeServiceService_IStatus;
}

interface IWorktreeServiceService_IBind extends grpc.MethodDefinition<worktree_pb.BindRequest, worktree_pb.BindResponse> {
    path: "/sw4rm.worktree.WorktreeService/Bind";
    requestStream: false;
    responseStream: false;
    requestSerialize: grpc.serialize<worktree_pb.BindRequest>;
    requestDeserialize: grpc.deserialize<worktree_pb.BindRequest>;
    responseSerialize: grpc.serialize<worktree_pb.BindResponse>;
    responseDeserialize: grpc.deserialize<worktree_pb.BindResponse>;
}
interface IWorktreeServiceService_IUnbind extends grpc.MethodDefinition<worktree_pb.UnbindRequest, worktree_pb.UnbindResponse> {
    path: "/sw4rm.worktree.WorktreeService/Unbind";
    requestStream: false;
    responseStream: false;
    requestSerialize: grpc.serialize<worktree_pb.UnbindRequest>;
    requestDeserialize: grpc.deserialize<worktree_pb.UnbindRequest>;
    responseSerialize: grpc.serialize<worktree_pb.UnbindResponse>;
    responseDeserialize: grpc.deserialize<worktree_pb.UnbindResponse>;
}
interface IWorktreeServiceService_IRequestSwitch extends grpc.MethodDefinition<worktree_pb.SwitchRequest, worktree_pb.StatusResponse> {
    path: "/sw4rm.worktree.WorktreeService/RequestSwitch";
    requestStream: false;
    responseStream: false;
    requestSerialize: grpc.serialize<worktree_pb.SwitchRequest>;
    requestDeserialize: grpc.deserialize<worktree_pb.SwitchRequest>;
    responseSerialize: grpc.serialize<worktree_pb.StatusResponse>;
    responseDeserialize: grpc.deserialize<worktree_pb.StatusResponse>;
}
interface IWorktreeServiceService_IApproveSwitch extends grpc.MethodDefinition<worktree_pb.SwitchApprove, worktree_pb.StatusResponse> {
    path: "/sw4rm.worktree.WorktreeService/ApproveSwitch";
    requestStream: false;
    responseStream: false;
    requestSerialize: grpc.serialize<worktree_pb.SwitchApprove>;
    requestDeserialize: grpc.deserialize<worktree_pb.SwitchApprove>;
    responseSerialize: grpc.serialize<worktree_pb.StatusResponse>;
    responseDeserialize: grpc.deserialize<worktree_pb.StatusResponse>;
}
interface IWorktreeServiceService_IRejectSwitch extends grpc.MethodDefinition<worktree_pb.SwitchReject, worktree_pb.StatusResponse> {
    path: "/sw4rm.worktree.WorktreeService/RejectSwitch";
    requestStream: false;
    responseStream: false;
    requestSerialize: grpc.serialize<worktree_pb.SwitchReject>;
    requestDeserialize: grpc.deserialize<worktree_pb.SwitchReject>;
    responseSerialize: grpc.serialize<worktree_pb.StatusResponse>;
    responseDeserialize: grpc.deserialize<worktree_pb.StatusResponse>;
}
interface IWorktreeServiceService_IStatus extends grpc.MethodDefinition<worktree_pb.StatusRequest, worktree_pb.StatusResponse> {
    path: "/sw4rm.worktree.WorktreeService/Status";
    requestStream: false;
    responseStream: false;
    requestSerialize: grpc.serialize<worktree_pb.StatusRequest>;
    requestDeserialize: grpc.deserialize<worktree_pb.StatusRequest>;
    responseSerialize: grpc.serialize<worktree_pb.StatusResponse>;
    responseDeserialize: grpc.deserialize<worktree_pb.StatusResponse>;
}

export const WorktreeServiceService: IWorktreeServiceService;

export interface IWorktreeServiceServer extends grpc.UntypedServiceImplementation {
    bind: grpc.handleUnaryCall<worktree_pb.BindRequest, worktree_pb.BindResponse>;
    unbind: grpc.handleUnaryCall<worktree_pb.UnbindRequest, worktree_pb.UnbindResponse>;
    requestSwitch: grpc.handleUnaryCall<worktree_pb.SwitchRequest, worktree_pb.StatusResponse>;
    approveSwitch: grpc.handleUnaryCall<worktree_pb.SwitchApprove, worktree_pb.StatusResponse>;
    rejectSwitch: grpc.handleUnaryCall<worktree_pb.SwitchReject, worktree_pb.StatusResponse>;
    status: grpc.handleUnaryCall<worktree_pb.StatusRequest, worktree_pb.StatusResponse>;
}

export interface IWorktreeServiceClient {
    bind(request: worktree_pb.BindRequest, callback: (error: grpc.ServiceError | null, response: worktree_pb.BindResponse) => void): grpc.ClientUnaryCall;
    bind(request: worktree_pb.BindRequest, metadata: grpc.Metadata, callback: (error: grpc.ServiceError | null, response: worktree_pb.BindResponse) => void): grpc.ClientUnaryCall;
    bind(request: worktree_pb.BindRequest, metadata: grpc.Metadata, options: Partial<grpc.CallOptions>, callback: (error: grpc.ServiceError | null, response: worktree_pb.BindResponse) => void): grpc.ClientUnaryCall;
    unbind(request: worktree_pb.UnbindRequest, callback: (error: grpc.ServiceError | null, response: worktree_pb.UnbindResponse) => void): grpc.ClientUnaryCall;
    unbind(request: worktree_pb.UnbindRequest, metadata: grpc.Metadata, callback: (error: grpc.ServiceError | null, response: worktree_pb.UnbindResponse) => void): grpc.ClientUnaryCall;
    unbind(request: worktree_pb.UnbindRequest, metadata: grpc.Metadata, options: Partial<grpc.CallOptions>, callback: (error: grpc.ServiceError | null, response: worktree_pb.UnbindResponse) => void): grpc.ClientUnaryCall;
    requestSwitch(request: worktree_pb.SwitchRequest, callback: (error: grpc.ServiceError | null, response: worktree_pb.StatusResponse) => void): grpc.ClientUnaryCall;
    requestSwitch(request: worktree_pb.SwitchRequest, metadata: grpc.Metadata, callback: (error: grpc.ServiceError | null, response: worktree_pb.StatusResponse) => void): grpc.ClientUnaryCall;
    requestSwitch(request: worktree_pb.SwitchRequest, metadata: grpc.Metadata, options: Partial<grpc.CallOptions>, callback: (error: grpc.ServiceError | null, response: worktree_pb.StatusResponse) => void): grpc.ClientUnaryCall;
    approveSwitch(request: worktree_pb.SwitchApprove, callback: (error: grpc.ServiceError | null, response: worktree_pb.StatusResponse) => void): grpc.ClientUnaryCall;
    approveSwitch(request: worktree_pb.SwitchApprove, metadata: grpc.Metadata, callback: (error: grpc.ServiceError | null, response: worktree_pb.StatusResponse) => void): grpc.ClientUnaryCall;
    approveSwitch(request: worktree_pb.SwitchApprove, metadata: grpc.Metadata, options: Partial<grpc.CallOptions>, callback: (error: grpc.ServiceError | null, response: worktree_pb.StatusResponse) => void): grpc.ClientUnaryCall;
    rejectSwitch(request: worktree_pb.SwitchReject, callback: (error: grpc.ServiceError | null, response: worktree_pb.StatusResponse) => void): grpc.ClientUnaryCall;
    rejectSwitch(request: worktree_pb.SwitchReject, metadata: grpc.Metadata, callback: (error: grpc.ServiceError | null, response: worktree_pb.StatusResponse) => void): grpc.ClientUnaryCall;
    rejectSwitch(request: worktree_pb.SwitchReject, metadata: grpc.Metadata, options: Partial<grpc.CallOptions>, callback: (error: grpc.ServiceError | null, response: worktree_pb.StatusResponse) => void): grpc.ClientUnaryCall;
    status(request: worktree_pb.StatusRequest, callback: (error: grpc.ServiceError | null, response: worktree_pb.StatusResponse) => void): grpc.ClientUnaryCall;
    status(request: worktree_pb.StatusRequest, metadata: grpc.Metadata, callback: (error: grpc.ServiceError | null, response: worktree_pb.StatusResponse) => void): grpc.ClientUnaryCall;
    status(request: worktree_pb.StatusRequest, metadata: grpc.Metadata, options: Partial<grpc.CallOptions>, callback: (error: grpc.ServiceError | null, response: worktree_pb.StatusResponse) => void): grpc.ClientUnaryCall;
}

export class WorktreeServiceClient extends grpc.Client implements IWorktreeServiceClient {
    constructor(address: string, credentials: grpc.ChannelCredentials, options?: Partial<grpc.ClientOptions>);
    public bind(request: worktree_pb.BindRequest, callback: (error: grpc.ServiceError | null, response: worktree_pb.BindResponse) => void): grpc.ClientUnaryCall;
    public bind(request: worktree_pb.BindRequest, metadata: grpc.Metadata, callback: (error: grpc.ServiceError | null, response: worktree_pb.BindResponse) => void): grpc.ClientUnaryCall;
    public bind(request: worktree_pb.BindRequest, metadata: grpc.Metadata, options: Partial<grpc.CallOptions>, callback: (error: grpc.ServiceError | null, response: worktree_pb.BindResponse) => void): grpc.ClientUnaryCall;
    public unbind(request: worktree_pb.UnbindRequest, callback: (error: grpc.ServiceError | null, response: worktree_pb.UnbindResponse) => void): grpc.ClientUnaryCall;
    public unbind(request: worktree_pb.UnbindRequest, metadata: grpc.Metadata, callback: (error: grpc.ServiceError | null, response: worktree_pb.UnbindResponse) => void): grpc.ClientUnaryCall;
    public unbind(request: worktree_pb.UnbindRequest, metadata: grpc.Metadata, options: Partial<grpc.CallOptions>, callback: (error: grpc.ServiceError | null, response: worktree_pb.UnbindResponse) => void): grpc.ClientUnaryCall;
    public requestSwitch(request: worktree_pb.SwitchRequest, callback: (error: grpc.ServiceError | null, response: worktree_pb.StatusResponse) => void): grpc.ClientUnaryCall;
    public requestSwitch(request: worktree_pb.SwitchRequest, metadata: grpc.Metadata, callback: (error: grpc.ServiceError | null, response: worktree_pb.StatusResponse) => void): grpc.ClientUnaryCall;
    public requestSwitch(request: worktree_pb.SwitchRequest, metadata: grpc.Metadata, options: Partial<grpc.CallOptions>, callback: (error: grpc.ServiceError | null, response: worktree_pb.StatusResponse) => void): grpc.ClientUnaryCall;
    public approveSwitch(request: worktree_pb.SwitchApprove, callback: (error: grpc.ServiceError | null, response: worktree_pb.StatusResponse) => void): grpc.ClientUnaryCall;
    public approveSwitch(request: worktree_pb.SwitchApprove, metadata: grpc.Metadata, callback: (error: grpc.ServiceError | null, response: worktree_pb.StatusResponse) => void): grpc.ClientUnaryCall;
    public approveSwitch(request: worktree_pb.SwitchApprove, metadata: grpc.Metadata, options: Partial<grpc.CallOptions>, callback: (error: grpc.ServiceError | null, response: worktree_pb.StatusResponse) => void): grpc.ClientUnaryCall;
    public rejectSwitch(request: worktree_pb.SwitchReject, callback: (error: grpc.ServiceError | null, response: worktree_pb.StatusResponse) => void): grpc.ClientUnaryCall;
    public rejectSwitch(request: worktree_pb.SwitchReject, metadata: grpc.Metadata, callback: (error: grpc.ServiceError | null, response: worktree_pb.StatusResponse) => void): grpc.ClientUnaryCall;
    public rejectSwitch(request: worktree_pb.SwitchReject, metadata: grpc.Metadata, options: Partial<grpc.CallOptions>, callback: (error: grpc.ServiceError | null, response: worktree_pb.StatusResponse) => void): grpc.ClientUnaryCall;
    public status(request: worktree_pb.StatusRequest, callback: (error: grpc.ServiceError | null, response: worktree_pb.StatusResponse) => void): grpc.ClientUnaryCall;
    public status(request: worktree_pb.StatusRequest, metadata: grpc.Metadata, callback: (error: grpc.ServiceError | null, response: worktree_pb.StatusResponse) => void): grpc.ClientUnaryCall;
    public status(request: worktree_pb.StatusRequest, metadata: grpc.Metadata, options: Partial<grpc.CallOptions>, callback: (error: grpc.ServiceError | null, response: worktree_pb.StatusResponse) => void): grpc.ClientUnaryCall;
}
