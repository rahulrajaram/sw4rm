// package: sw4rm.activity
// file: activity.proto

/* tslint:disable */
/* eslint-disable */

import * as grpc from "@grpc/grpc-js";
import * as activity_pb from "./activity_pb";

interface IActivityServiceService extends grpc.ServiceDefinition<grpc.UntypedServiceImplementation> {
    appendArtifact: IActivityServiceService_IAppendArtifact;
    listArtifacts: IActivityServiceService_IListArtifacts;
}

interface IActivityServiceService_IAppendArtifact extends grpc.MethodDefinition<activity_pb.AppendArtifactRequest, activity_pb.AppendArtifactResponse> {
    path: "/sw4rm.activity.ActivityService/AppendArtifact";
    requestStream: false;
    responseStream: false;
    requestSerialize: grpc.serialize<activity_pb.AppendArtifactRequest>;
    requestDeserialize: grpc.deserialize<activity_pb.AppendArtifactRequest>;
    responseSerialize: grpc.serialize<activity_pb.AppendArtifactResponse>;
    responseDeserialize: grpc.deserialize<activity_pb.AppendArtifactResponse>;
}
interface IActivityServiceService_IListArtifacts extends grpc.MethodDefinition<activity_pb.ListArtifactsRequest, activity_pb.ListArtifactsResponse> {
    path: "/sw4rm.activity.ActivityService/ListArtifacts";
    requestStream: false;
    responseStream: false;
    requestSerialize: grpc.serialize<activity_pb.ListArtifactsRequest>;
    requestDeserialize: grpc.deserialize<activity_pb.ListArtifactsRequest>;
    responseSerialize: grpc.serialize<activity_pb.ListArtifactsResponse>;
    responseDeserialize: grpc.deserialize<activity_pb.ListArtifactsResponse>;
}

export const ActivityServiceService: IActivityServiceService;

export interface IActivityServiceServer extends grpc.UntypedServiceImplementation {
    appendArtifact: grpc.handleUnaryCall<activity_pb.AppendArtifactRequest, activity_pb.AppendArtifactResponse>;
    listArtifacts: grpc.handleUnaryCall<activity_pb.ListArtifactsRequest, activity_pb.ListArtifactsResponse>;
}

export interface IActivityServiceClient {
    appendArtifact(request: activity_pb.AppendArtifactRequest, callback: (error: grpc.ServiceError | null, response: activity_pb.AppendArtifactResponse) => void): grpc.ClientUnaryCall;
    appendArtifact(request: activity_pb.AppendArtifactRequest, metadata: grpc.Metadata, callback: (error: grpc.ServiceError | null, response: activity_pb.AppendArtifactResponse) => void): grpc.ClientUnaryCall;
    appendArtifact(request: activity_pb.AppendArtifactRequest, metadata: grpc.Metadata, options: Partial<grpc.CallOptions>, callback: (error: grpc.ServiceError | null, response: activity_pb.AppendArtifactResponse) => void): grpc.ClientUnaryCall;
    listArtifacts(request: activity_pb.ListArtifactsRequest, callback: (error: grpc.ServiceError | null, response: activity_pb.ListArtifactsResponse) => void): grpc.ClientUnaryCall;
    listArtifacts(request: activity_pb.ListArtifactsRequest, metadata: grpc.Metadata, callback: (error: grpc.ServiceError | null, response: activity_pb.ListArtifactsResponse) => void): grpc.ClientUnaryCall;
    listArtifacts(request: activity_pb.ListArtifactsRequest, metadata: grpc.Metadata, options: Partial<grpc.CallOptions>, callback: (error: grpc.ServiceError | null, response: activity_pb.ListArtifactsResponse) => void): grpc.ClientUnaryCall;
}

export class ActivityServiceClient extends grpc.Client implements IActivityServiceClient {
    constructor(address: string, credentials: grpc.ChannelCredentials, options?: Partial<grpc.ClientOptions>);
    public appendArtifact(request: activity_pb.AppendArtifactRequest, callback: (error: grpc.ServiceError | null, response: activity_pb.AppendArtifactResponse) => void): grpc.ClientUnaryCall;
    public appendArtifact(request: activity_pb.AppendArtifactRequest, metadata: grpc.Metadata, callback: (error: grpc.ServiceError | null, response: activity_pb.AppendArtifactResponse) => void): grpc.ClientUnaryCall;
    public appendArtifact(request: activity_pb.AppendArtifactRequest, metadata: grpc.Metadata, options: Partial<grpc.CallOptions>, callback: (error: grpc.ServiceError | null, response: activity_pb.AppendArtifactResponse) => void): grpc.ClientUnaryCall;
    public listArtifacts(request: activity_pb.ListArtifactsRequest, callback: (error: grpc.ServiceError | null, response: activity_pb.ListArtifactsResponse) => void): grpc.ClientUnaryCall;
    public listArtifacts(request: activity_pb.ListArtifactsRequest, metadata: grpc.Metadata, callback: (error: grpc.ServiceError | null, response: activity_pb.ListArtifactsResponse) => void): grpc.ClientUnaryCall;
    public listArtifacts(request: activity_pb.ListArtifactsRequest, metadata: grpc.Metadata, options: Partial<grpc.CallOptions>, callback: (error: grpc.ServiceError | null, response: activity_pb.ListArtifactsResponse) => void): grpc.ClientUnaryCall;
}
