// package: sw4rm.scheduler
// file: scheduler.proto

/* tslint:disable */
/* eslint-disable */

import * as grpc from "@grpc/grpc-js";
import * as scheduler_pb from "./scheduler_pb";
import * as google_protobuf_duration_pb from "google-protobuf/google/protobuf/duration_pb";
import * as common_pb from "./common_pb";

interface ISchedulerServiceService extends grpc.ServiceDefinition<grpc.UntypedServiceImplementation> {
    submitTask: ISchedulerServiceService_ISubmitTask;
    requestPreemption: ISchedulerServiceService_IRequestPreemption;
    shutdownAgent: ISchedulerServiceService_IShutdownAgent;
    pollActivityBuffer: ISchedulerServiceService_IPollActivityBuffer;
    purgeActivity: ISchedulerServiceService_IPurgeActivity;
}

interface ISchedulerServiceService_ISubmitTask extends grpc.MethodDefinition<scheduler_pb.SubmitTaskRequest, scheduler_pb.SubmitTaskResponse> {
    path: "/sw4rm.scheduler.SchedulerService/SubmitTask";
    requestStream: false;
    responseStream: false;
    requestSerialize: grpc.serialize<scheduler_pb.SubmitTaskRequest>;
    requestDeserialize: grpc.deserialize<scheduler_pb.SubmitTaskRequest>;
    responseSerialize: grpc.serialize<scheduler_pb.SubmitTaskResponse>;
    responseDeserialize: grpc.deserialize<scheduler_pb.SubmitTaskResponse>;
}
interface ISchedulerServiceService_IRequestPreemption extends grpc.MethodDefinition<scheduler_pb.PreemptRequest, scheduler_pb.PreemptResponse> {
    path: "/sw4rm.scheduler.SchedulerService/RequestPreemption";
    requestStream: false;
    responseStream: false;
    requestSerialize: grpc.serialize<scheduler_pb.PreemptRequest>;
    requestDeserialize: grpc.deserialize<scheduler_pb.PreemptRequest>;
    responseSerialize: grpc.serialize<scheduler_pb.PreemptResponse>;
    responseDeserialize: grpc.deserialize<scheduler_pb.PreemptResponse>;
}
interface ISchedulerServiceService_IShutdownAgent extends grpc.MethodDefinition<scheduler_pb.ShutdownAgentRequest, scheduler_pb.ShutdownAgentResponse> {
    path: "/sw4rm.scheduler.SchedulerService/ShutdownAgent";
    requestStream: false;
    responseStream: false;
    requestSerialize: grpc.serialize<scheduler_pb.ShutdownAgentRequest>;
    requestDeserialize: grpc.deserialize<scheduler_pb.ShutdownAgentRequest>;
    responseSerialize: grpc.serialize<scheduler_pb.ShutdownAgentResponse>;
    responseDeserialize: grpc.deserialize<scheduler_pb.ShutdownAgentResponse>;
}
interface ISchedulerServiceService_IPollActivityBuffer extends grpc.MethodDefinition<scheduler_pb.PollActivityBufferRequest, scheduler_pb.PollActivityBufferResponse> {
    path: "/sw4rm.scheduler.SchedulerService/PollActivityBuffer";
    requestStream: false;
    responseStream: false;
    requestSerialize: grpc.serialize<scheduler_pb.PollActivityBufferRequest>;
    requestDeserialize: grpc.deserialize<scheduler_pb.PollActivityBufferRequest>;
    responseSerialize: grpc.serialize<scheduler_pb.PollActivityBufferResponse>;
    responseDeserialize: grpc.deserialize<scheduler_pb.PollActivityBufferResponse>;
}
interface ISchedulerServiceService_IPurgeActivity extends grpc.MethodDefinition<scheduler_pb.PurgeActivityRequest, scheduler_pb.PurgeActivityResponse> {
    path: "/sw4rm.scheduler.SchedulerService/PurgeActivity";
    requestStream: false;
    responseStream: false;
    requestSerialize: grpc.serialize<scheduler_pb.PurgeActivityRequest>;
    requestDeserialize: grpc.deserialize<scheduler_pb.PurgeActivityRequest>;
    responseSerialize: grpc.serialize<scheduler_pb.PurgeActivityResponse>;
    responseDeserialize: grpc.deserialize<scheduler_pb.PurgeActivityResponse>;
}

export const SchedulerServiceService: ISchedulerServiceService;

export interface ISchedulerServiceServer extends grpc.UntypedServiceImplementation {
    submitTask: grpc.handleUnaryCall<scheduler_pb.SubmitTaskRequest, scheduler_pb.SubmitTaskResponse>;
    requestPreemption: grpc.handleUnaryCall<scheduler_pb.PreemptRequest, scheduler_pb.PreemptResponse>;
    shutdownAgent: grpc.handleUnaryCall<scheduler_pb.ShutdownAgentRequest, scheduler_pb.ShutdownAgentResponse>;
    pollActivityBuffer: grpc.handleUnaryCall<scheduler_pb.PollActivityBufferRequest, scheduler_pb.PollActivityBufferResponse>;
    purgeActivity: grpc.handleUnaryCall<scheduler_pb.PurgeActivityRequest, scheduler_pb.PurgeActivityResponse>;
}

export interface ISchedulerServiceClient {
    submitTask(request: scheduler_pb.SubmitTaskRequest, callback: (error: grpc.ServiceError | null, response: scheduler_pb.SubmitTaskResponse) => void): grpc.ClientUnaryCall;
    submitTask(request: scheduler_pb.SubmitTaskRequest, metadata: grpc.Metadata, callback: (error: grpc.ServiceError | null, response: scheduler_pb.SubmitTaskResponse) => void): grpc.ClientUnaryCall;
    submitTask(request: scheduler_pb.SubmitTaskRequest, metadata: grpc.Metadata, options: Partial<grpc.CallOptions>, callback: (error: grpc.ServiceError | null, response: scheduler_pb.SubmitTaskResponse) => void): grpc.ClientUnaryCall;
    requestPreemption(request: scheduler_pb.PreemptRequest, callback: (error: grpc.ServiceError | null, response: scheduler_pb.PreemptResponse) => void): grpc.ClientUnaryCall;
    requestPreemption(request: scheduler_pb.PreemptRequest, metadata: grpc.Metadata, callback: (error: grpc.ServiceError | null, response: scheduler_pb.PreemptResponse) => void): grpc.ClientUnaryCall;
    requestPreemption(request: scheduler_pb.PreemptRequest, metadata: grpc.Metadata, options: Partial<grpc.CallOptions>, callback: (error: grpc.ServiceError | null, response: scheduler_pb.PreemptResponse) => void): grpc.ClientUnaryCall;
    shutdownAgent(request: scheduler_pb.ShutdownAgentRequest, callback: (error: grpc.ServiceError | null, response: scheduler_pb.ShutdownAgentResponse) => void): grpc.ClientUnaryCall;
    shutdownAgent(request: scheduler_pb.ShutdownAgentRequest, metadata: grpc.Metadata, callback: (error: grpc.ServiceError | null, response: scheduler_pb.ShutdownAgentResponse) => void): grpc.ClientUnaryCall;
    shutdownAgent(request: scheduler_pb.ShutdownAgentRequest, metadata: grpc.Metadata, options: Partial<grpc.CallOptions>, callback: (error: grpc.ServiceError | null, response: scheduler_pb.ShutdownAgentResponse) => void): grpc.ClientUnaryCall;
    pollActivityBuffer(request: scheduler_pb.PollActivityBufferRequest, callback: (error: grpc.ServiceError | null, response: scheduler_pb.PollActivityBufferResponse) => void): grpc.ClientUnaryCall;
    pollActivityBuffer(request: scheduler_pb.PollActivityBufferRequest, metadata: grpc.Metadata, callback: (error: grpc.ServiceError | null, response: scheduler_pb.PollActivityBufferResponse) => void): grpc.ClientUnaryCall;
    pollActivityBuffer(request: scheduler_pb.PollActivityBufferRequest, metadata: grpc.Metadata, options: Partial<grpc.CallOptions>, callback: (error: grpc.ServiceError | null, response: scheduler_pb.PollActivityBufferResponse) => void): grpc.ClientUnaryCall;
    purgeActivity(request: scheduler_pb.PurgeActivityRequest, callback: (error: grpc.ServiceError | null, response: scheduler_pb.PurgeActivityResponse) => void): grpc.ClientUnaryCall;
    purgeActivity(request: scheduler_pb.PurgeActivityRequest, metadata: grpc.Metadata, callback: (error: grpc.ServiceError | null, response: scheduler_pb.PurgeActivityResponse) => void): grpc.ClientUnaryCall;
    purgeActivity(request: scheduler_pb.PurgeActivityRequest, metadata: grpc.Metadata, options: Partial<grpc.CallOptions>, callback: (error: grpc.ServiceError | null, response: scheduler_pb.PurgeActivityResponse) => void): grpc.ClientUnaryCall;
}

export class SchedulerServiceClient extends grpc.Client implements ISchedulerServiceClient {
    constructor(address: string, credentials: grpc.ChannelCredentials, options?: Partial<grpc.ClientOptions>);
    public submitTask(request: scheduler_pb.SubmitTaskRequest, callback: (error: grpc.ServiceError | null, response: scheduler_pb.SubmitTaskResponse) => void): grpc.ClientUnaryCall;
    public submitTask(request: scheduler_pb.SubmitTaskRequest, metadata: grpc.Metadata, callback: (error: grpc.ServiceError | null, response: scheduler_pb.SubmitTaskResponse) => void): grpc.ClientUnaryCall;
    public submitTask(request: scheduler_pb.SubmitTaskRequest, metadata: grpc.Metadata, options: Partial<grpc.CallOptions>, callback: (error: grpc.ServiceError | null, response: scheduler_pb.SubmitTaskResponse) => void): grpc.ClientUnaryCall;
    public requestPreemption(request: scheduler_pb.PreemptRequest, callback: (error: grpc.ServiceError | null, response: scheduler_pb.PreemptResponse) => void): grpc.ClientUnaryCall;
    public requestPreemption(request: scheduler_pb.PreemptRequest, metadata: grpc.Metadata, callback: (error: grpc.ServiceError | null, response: scheduler_pb.PreemptResponse) => void): grpc.ClientUnaryCall;
    public requestPreemption(request: scheduler_pb.PreemptRequest, metadata: grpc.Metadata, options: Partial<grpc.CallOptions>, callback: (error: grpc.ServiceError | null, response: scheduler_pb.PreemptResponse) => void): grpc.ClientUnaryCall;
    public shutdownAgent(request: scheduler_pb.ShutdownAgentRequest, callback: (error: grpc.ServiceError | null, response: scheduler_pb.ShutdownAgentResponse) => void): grpc.ClientUnaryCall;
    public shutdownAgent(request: scheduler_pb.ShutdownAgentRequest, metadata: grpc.Metadata, callback: (error: grpc.ServiceError | null, response: scheduler_pb.ShutdownAgentResponse) => void): grpc.ClientUnaryCall;
    public shutdownAgent(request: scheduler_pb.ShutdownAgentRequest, metadata: grpc.Metadata, options: Partial<grpc.CallOptions>, callback: (error: grpc.ServiceError | null, response: scheduler_pb.ShutdownAgentResponse) => void): grpc.ClientUnaryCall;
    public pollActivityBuffer(request: scheduler_pb.PollActivityBufferRequest, callback: (error: grpc.ServiceError | null, response: scheduler_pb.PollActivityBufferResponse) => void): grpc.ClientUnaryCall;
    public pollActivityBuffer(request: scheduler_pb.PollActivityBufferRequest, metadata: grpc.Metadata, callback: (error: grpc.ServiceError | null, response: scheduler_pb.PollActivityBufferResponse) => void): grpc.ClientUnaryCall;
    public pollActivityBuffer(request: scheduler_pb.PollActivityBufferRequest, metadata: grpc.Metadata, options: Partial<grpc.CallOptions>, callback: (error: grpc.ServiceError | null, response: scheduler_pb.PollActivityBufferResponse) => void): grpc.ClientUnaryCall;
    public purgeActivity(request: scheduler_pb.PurgeActivityRequest, callback: (error: grpc.ServiceError | null, response: scheduler_pb.PurgeActivityResponse) => void): grpc.ClientUnaryCall;
    public purgeActivity(request: scheduler_pb.PurgeActivityRequest, metadata: grpc.Metadata, callback: (error: grpc.ServiceError | null, response: scheduler_pb.PurgeActivityResponse) => void): grpc.ClientUnaryCall;
    public purgeActivity(request: scheduler_pb.PurgeActivityRequest, metadata: grpc.Metadata, options: Partial<grpc.CallOptions>, callback: (error: grpc.ServiceError | null, response: scheduler_pb.PurgeActivityResponse) => void): grpc.ClientUnaryCall;
}
