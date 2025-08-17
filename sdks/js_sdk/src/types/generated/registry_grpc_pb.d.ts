// package: sw4rm.registry
// file: registry.proto

/* tslint:disable */
/* eslint-disable */

import * as grpc from "@grpc/grpc-js";
import * as registry_pb from "./registry_pb";
import * as google_protobuf_timestamp_pb from "google-protobuf/google/protobuf/timestamp_pb";
import * as common_pb from "./common_pb";

interface IRegistryServiceService extends grpc.ServiceDefinition<grpc.UntypedServiceImplementation> {
    registerAgent: IRegistryServiceService_IRegisterAgent;
    heartbeat: IRegistryServiceService_IHeartbeat;
    deregisterAgent: IRegistryServiceService_IDeregisterAgent;
}

interface IRegistryServiceService_IRegisterAgent extends grpc.MethodDefinition<registry_pb.RegisterAgentRequest, registry_pb.RegisterAgentResponse> {
    path: "/sw4rm.registry.RegistryService/RegisterAgent";
    requestStream: false;
    responseStream: false;
    requestSerialize: grpc.serialize<registry_pb.RegisterAgentRequest>;
    requestDeserialize: grpc.deserialize<registry_pb.RegisterAgentRequest>;
    responseSerialize: grpc.serialize<registry_pb.RegisterAgentResponse>;
    responseDeserialize: grpc.deserialize<registry_pb.RegisterAgentResponse>;
}
interface IRegistryServiceService_IHeartbeat extends grpc.MethodDefinition<registry_pb.HeartbeatRequest, registry_pb.HeartbeatResponse> {
    path: "/sw4rm.registry.RegistryService/Heartbeat";
    requestStream: false;
    responseStream: false;
    requestSerialize: grpc.serialize<registry_pb.HeartbeatRequest>;
    requestDeserialize: grpc.deserialize<registry_pb.HeartbeatRequest>;
    responseSerialize: grpc.serialize<registry_pb.HeartbeatResponse>;
    responseDeserialize: grpc.deserialize<registry_pb.HeartbeatResponse>;
}
interface IRegistryServiceService_IDeregisterAgent extends grpc.MethodDefinition<registry_pb.DeregisterAgentRequest, registry_pb.DeregisterAgentResponse> {
    path: "/sw4rm.registry.RegistryService/DeregisterAgent";
    requestStream: false;
    responseStream: false;
    requestSerialize: grpc.serialize<registry_pb.DeregisterAgentRequest>;
    requestDeserialize: grpc.deserialize<registry_pb.DeregisterAgentRequest>;
    responseSerialize: grpc.serialize<registry_pb.DeregisterAgentResponse>;
    responseDeserialize: grpc.deserialize<registry_pb.DeregisterAgentResponse>;
}

export const RegistryServiceService: IRegistryServiceService;

export interface IRegistryServiceServer extends grpc.UntypedServiceImplementation {
    registerAgent: grpc.handleUnaryCall<registry_pb.RegisterAgentRequest, registry_pb.RegisterAgentResponse>;
    heartbeat: grpc.handleUnaryCall<registry_pb.HeartbeatRequest, registry_pb.HeartbeatResponse>;
    deregisterAgent: grpc.handleUnaryCall<registry_pb.DeregisterAgentRequest, registry_pb.DeregisterAgentResponse>;
}

export interface IRegistryServiceClient {
    registerAgent(request: registry_pb.RegisterAgentRequest, callback: (error: grpc.ServiceError | null, response: registry_pb.RegisterAgentResponse) => void): grpc.ClientUnaryCall;
    registerAgent(request: registry_pb.RegisterAgentRequest, metadata: grpc.Metadata, callback: (error: grpc.ServiceError | null, response: registry_pb.RegisterAgentResponse) => void): grpc.ClientUnaryCall;
    registerAgent(request: registry_pb.RegisterAgentRequest, metadata: grpc.Metadata, options: Partial<grpc.CallOptions>, callback: (error: grpc.ServiceError | null, response: registry_pb.RegisterAgentResponse) => void): grpc.ClientUnaryCall;
    heartbeat(request: registry_pb.HeartbeatRequest, callback: (error: grpc.ServiceError | null, response: registry_pb.HeartbeatResponse) => void): grpc.ClientUnaryCall;
    heartbeat(request: registry_pb.HeartbeatRequest, metadata: grpc.Metadata, callback: (error: grpc.ServiceError | null, response: registry_pb.HeartbeatResponse) => void): grpc.ClientUnaryCall;
    heartbeat(request: registry_pb.HeartbeatRequest, metadata: grpc.Metadata, options: Partial<grpc.CallOptions>, callback: (error: grpc.ServiceError | null, response: registry_pb.HeartbeatResponse) => void): grpc.ClientUnaryCall;
    deregisterAgent(request: registry_pb.DeregisterAgentRequest, callback: (error: grpc.ServiceError | null, response: registry_pb.DeregisterAgentResponse) => void): grpc.ClientUnaryCall;
    deregisterAgent(request: registry_pb.DeregisterAgentRequest, metadata: grpc.Metadata, callback: (error: grpc.ServiceError | null, response: registry_pb.DeregisterAgentResponse) => void): grpc.ClientUnaryCall;
    deregisterAgent(request: registry_pb.DeregisterAgentRequest, metadata: grpc.Metadata, options: Partial<grpc.CallOptions>, callback: (error: grpc.ServiceError | null, response: registry_pb.DeregisterAgentResponse) => void): grpc.ClientUnaryCall;
}

export class RegistryServiceClient extends grpc.Client implements IRegistryServiceClient {
    constructor(address: string, credentials: grpc.ChannelCredentials, options?: Partial<grpc.ClientOptions>);
    public registerAgent(request: registry_pb.RegisterAgentRequest, callback: (error: grpc.ServiceError | null, response: registry_pb.RegisterAgentResponse) => void): grpc.ClientUnaryCall;
    public registerAgent(request: registry_pb.RegisterAgentRequest, metadata: grpc.Metadata, callback: (error: grpc.ServiceError | null, response: registry_pb.RegisterAgentResponse) => void): grpc.ClientUnaryCall;
    public registerAgent(request: registry_pb.RegisterAgentRequest, metadata: grpc.Metadata, options: Partial<grpc.CallOptions>, callback: (error: grpc.ServiceError | null, response: registry_pb.RegisterAgentResponse) => void): grpc.ClientUnaryCall;
    public heartbeat(request: registry_pb.HeartbeatRequest, callback: (error: grpc.ServiceError | null, response: registry_pb.HeartbeatResponse) => void): grpc.ClientUnaryCall;
    public heartbeat(request: registry_pb.HeartbeatRequest, metadata: grpc.Metadata, callback: (error: grpc.ServiceError | null, response: registry_pb.HeartbeatResponse) => void): grpc.ClientUnaryCall;
    public heartbeat(request: registry_pb.HeartbeatRequest, metadata: grpc.Metadata, options: Partial<grpc.CallOptions>, callback: (error: grpc.ServiceError | null, response: registry_pb.HeartbeatResponse) => void): grpc.ClientUnaryCall;
    public deregisterAgent(request: registry_pb.DeregisterAgentRequest, callback: (error: grpc.ServiceError | null, response: registry_pb.DeregisterAgentResponse) => void): grpc.ClientUnaryCall;
    public deregisterAgent(request: registry_pb.DeregisterAgentRequest, metadata: grpc.Metadata, callback: (error: grpc.ServiceError | null, response: registry_pb.DeregisterAgentResponse) => void): grpc.ClientUnaryCall;
    public deregisterAgent(request: registry_pb.DeregisterAgentRequest, metadata: grpc.Metadata, options: Partial<grpc.CallOptions>, callback: (error: grpc.ServiceError | null, response: registry_pb.DeregisterAgentResponse) => void): grpc.ClientUnaryCall;
}
