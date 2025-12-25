// package: sw4rm.workflow
// file: workflow.proto

/* tslint:disable */
/* eslint-disable */

import * as grpc from "@grpc/grpc-js";
import * as workflow_pb from "./workflow_pb";
import * as google_protobuf_timestamp_pb from "google-protobuf/google/protobuf/timestamp_pb";

interface IWorkflowServiceService extends grpc.ServiceDefinition<grpc.UntypedServiceImplementation> {
    createWorkflow: IWorkflowServiceService_ICreateWorkflow;
    startWorkflow: IWorkflowServiceService_IStartWorkflow;
    getWorkflowState: IWorkflowServiceService_IGetWorkflowState;
    resumeWorkflow: IWorkflowServiceService_IResumeWorkflow;
}

interface IWorkflowServiceService_ICreateWorkflow extends grpc.MethodDefinition<workflow_pb.CreateWorkflowRequest, workflow_pb.CreateWorkflowResponse> {
    path: "/sw4rm.workflow.WorkflowService/CreateWorkflow";
    requestStream: false;
    responseStream: false;
    requestSerialize: grpc.serialize<workflow_pb.CreateWorkflowRequest>;
    requestDeserialize: grpc.deserialize<workflow_pb.CreateWorkflowRequest>;
    responseSerialize: grpc.serialize<workflow_pb.CreateWorkflowResponse>;
    responseDeserialize: grpc.deserialize<workflow_pb.CreateWorkflowResponse>;
}
interface IWorkflowServiceService_IStartWorkflow extends grpc.MethodDefinition<workflow_pb.StartWorkflowRequest, workflow_pb.StartWorkflowResponse> {
    path: "/sw4rm.workflow.WorkflowService/StartWorkflow";
    requestStream: false;
    responseStream: false;
    requestSerialize: grpc.serialize<workflow_pb.StartWorkflowRequest>;
    requestDeserialize: grpc.deserialize<workflow_pb.StartWorkflowRequest>;
    responseSerialize: grpc.serialize<workflow_pb.StartWorkflowResponse>;
    responseDeserialize: grpc.deserialize<workflow_pb.StartWorkflowResponse>;
}
interface IWorkflowServiceService_IGetWorkflowState extends grpc.MethodDefinition<workflow_pb.GetWorkflowStateRequest, workflow_pb.GetWorkflowStateResponse> {
    path: "/sw4rm.workflow.WorkflowService/GetWorkflowState";
    requestStream: false;
    responseStream: false;
    requestSerialize: grpc.serialize<workflow_pb.GetWorkflowStateRequest>;
    requestDeserialize: grpc.deserialize<workflow_pb.GetWorkflowStateRequest>;
    responseSerialize: grpc.serialize<workflow_pb.GetWorkflowStateResponse>;
    responseDeserialize: grpc.deserialize<workflow_pb.GetWorkflowStateResponse>;
}
interface IWorkflowServiceService_IResumeWorkflow extends grpc.MethodDefinition<workflow_pb.ResumeWorkflowRequest, workflow_pb.ResumeWorkflowResponse> {
    path: "/sw4rm.workflow.WorkflowService/ResumeWorkflow";
    requestStream: false;
    responseStream: false;
    requestSerialize: grpc.serialize<workflow_pb.ResumeWorkflowRequest>;
    requestDeserialize: grpc.deserialize<workflow_pb.ResumeWorkflowRequest>;
    responseSerialize: grpc.serialize<workflow_pb.ResumeWorkflowResponse>;
    responseDeserialize: grpc.deserialize<workflow_pb.ResumeWorkflowResponse>;
}

export const WorkflowServiceService: IWorkflowServiceService;

export interface IWorkflowServiceServer extends grpc.UntypedServiceImplementation {
    createWorkflow: grpc.handleUnaryCall<workflow_pb.CreateWorkflowRequest, workflow_pb.CreateWorkflowResponse>;
    startWorkflow: grpc.handleUnaryCall<workflow_pb.StartWorkflowRequest, workflow_pb.StartWorkflowResponse>;
    getWorkflowState: grpc.handleUnaryCall<workflow_pb.GetWorkflowStateRequest, workflow_pb.GetWorkflowStateResponse>;
    resumeWorkflow: grpc.handleUnaryCall<workflow_pb.ResumeWorkflowRequest, workflow_pb.ResumeWorkflowResponse>;
}

export interface IWorkflowServiceClient {
    createWorkflow(request: workflow_pb.CreateWorkflowRequest, callback: (error: grpc.ServiceError | null, response: workflow_pb.CreateWorkflowResponse) => void): grpc.ClientUnaryCall;
    createWorkflow(request: workflow_pb.CreateWorkflowRequest, metadata: grpc.Metadata, callback: (error: grpc.ServiceError | null, response: workflow_pb.CreateWorkflowResponse) => void): grpc.ClientUnaryCall;
    createWorkflow(request: workflow_pb.CreateWorkflowRequest, metadata: grpc.Metadata, options: Partial<grpc.CallOptions>, callback: (error: grpc.ServiceError | null, response: workflow_pb.CreateWorkflowResponse) => void): grpc.ClientUnaryCall;
    startWorkflow(request: workflow_pb.StartWorkflowRequest, callback: (error: grpc.ServiceError | null, response: workflow_pb.StartWorkflowResponse) => void): grpc.ClientUnaryCall;
    startWorkflow(request: workflow_pb.StartWorkflowRequest, metadata: grpc.Metadata, callback: (error: grpc.ServiceError | null, response: workflow_pb.StartWorkflowResponse) => void): grpc.ClientUnaryCall;
    startWorkflow(request: workflow_pb.StartWorkflowRequest, metadata: grpc.Metadata, options: Partial<grpc.CallOptions>, callback: (error: grpc.ServiceError | null, response: workflow_pb.StartWorkflowResponse) => void): grpc.ClientUnaryCall;
    getWorkflowState(request: workflow_pb.GetWorkflowStateRequest, callback: (error: grpc.ServiceError | null, response: workflow_pb.GetWorkflowStateResponse) => void): grpc.ClientUnaryCall;
    getWorkflowState(request: workflow_pb.GetWorkflowStateRequest, metadata: grpc.Metadata, callback: (error: grpc.ServiceError | null, response: workflow_pb.GetWorkflowStateResponse) => void): grpc.ClientUnaryCall;
    getWorkflowState(request: workflow_pb.GetWorkflowStateRequest, metadata: grpc.Metadata, options: Partial<grpc.CallOptions>, callback: (error: grpc.ServiceError | null, response: workflow_pb.GetWorkflowStateResponse) => void): grpc.ClientUnaryCall;
    resumeWorkflow(request: workflow_pb.ResumeWorkflowRequest, callback: (error: grpc.ServiceError | null, response: workflow_pb.ResumeWorkflowResponse) => void): grpc.ClientUnaryCall;
    resumeWorkflow(request: workflow_pb.ResumeWorkflowRequest, metadata: grpc.Metadata, callback: (error: grpc.ServiceError | null, response: workflow_pb.ResumeWorkflowResponse) => void): grpc.ClientUnaryCall;
    resumeWorkflow(request: workflow_pb.ResumeWorkflowRequest, metadata: grpc.Metadata, options: Partial<grpc.CallOptions>, callback: (error: grpc.ServiceError | null, response: workflow_pb.ResumeWorkflowResponse) => void): grpc.ClientUnaryCall;
}

export class WorkflowServiceClient extends grpc.Client implements IWorkflowServiceClient {
    constructor(address: string, credentials: grpc.ChannelCredentials, options?: Partial<grpc.ClientOptions>);
    public createWorkflow(request: workflow_pb.CreateWorkflowRequest, callback: (error: grpc.ServiceError | null, response: workflow_pb.CreateWorkflowResponse) => void): grpc.ClientUnaryCall;
    public createWorkflow(request: workflow_pb.CreateWorkflowRequest, metadata: grpc.Metadata, callback: (error: grpc.ServiceError | null, response: workflow_pb.CreateWorkflowResponse) => void): grpc.ClientUnaryCall;
    public createWorkflow(request: workflow_pb.CreateWorkflowRequest, metadata: grpc.Metadata, options: Partial<grpc.CallOptions>, callback: (error: grpc.ServiceError | null, response: workflow_pb.CreateWorkflowResponse) => void): grpc.ClientUnaryCall;
    public startWorkflow(request: workflow_pb.StartWorkflowRequest, callback: (error: grpc.ServiceError | null, response: workflow_pb.StartWorkflowResponse) => void): grpc.ClientUnaryCall;
    public startWorkflow(request: workflow_pb.StartWorkflowRequest, metadata: grpc.Metadata, callback: (error: grpc.ServiceError | null, response: workflow_pb.StartWorkflowResponse) => void): grpc.ClientUnaryCall;
    public startWorkflow(request: workflow_pb.StartWorkflowRequest, metadata: grpc.Metadata, options: Partial<grpc.CallOptions>, callback: (error: grpc.ServiceError | null, response: workflow_pb.StartWorkflowResponse) => void): grpc.ClientUnaryCall;
    public getWorkflowState(request: workflow_pb.GetWorkflowStateRequest, callback: (error: grpc.ServiceError | null, response: workflow_pb.GetWorkflowStateResponse) => void): grpc.ClientUnaryCall;
    public getWorkflowState(request: workflow_pb.GetWorkflowStateRequest, metadata: grpc.Metadata, callback: (error: grpc.ServiceError | null, response: workflow_pb.GetWorkflowStateResponse) => void): grpc.ClientUnaryCall;
    public getWorkflowState(request: workflow_pb.GetWorkflowStateRequest, metadata: grpc.Metadata, options: Partial<grpc.CallOptions>, callback: (error: grpc.ServiceError | null, response: workflow_pb.GetWorkflowStateResponse) => void): grpc.ClientUnaryCall;
    public resumeWorkflow(request: workflow_pb.ResumeWorkflowRequest, callback: (error: grpc.ServiceError | null, response: workflow_pb.ResumeWorkflowResponse) => void): grpc.ClientUnaryCall;
    public resumeWorkflow(request: workflow_pb.ResumeWorkflowRequest, metadata: grpc.Metadata, callback: (error: grpc.ServiceError | null, response: workflow_pb.ResumeWorkflowResponse) => void): grpc.ClientUnaryCall;
    public resumeWorkflow(request: workflow_pb.ResumeWorkflowRequest, metadata: grpc.Metadata, options: Partial<grpc.CallOptions>, callback: (error: grpc.ServiceError | null, response: workflow_pb.ResumeWorkflowResponse) => void): grpc.ClientUnaryCall;
}
