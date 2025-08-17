// package: sw4rm.logging
// file: logging.proto

/* tslint:disable */
/* eslint-disable */

import * as grpc from "@grpc/grpc-js";
import * as logging_pb from "./logging_pb";
import * as google_protobuf_timestamp_pb from "google-protobuf/google/protobuf/timestamp_pb";

interface ILoggingServiceService extends grpc.ServiceDefinition<grpc.UntypedServiceImplementation> {
    ingest: ILoggingServiceService_IIngest;
}

interface ILoggingServiceService_IIngest extends grpc.MethodDefinition<logging_pb.LogEvent, logging_pb.IngestResponse> {
    path: "/sw4rm.logging.LoggingService/Ingest";
    requestStream: false;
    responseStream: false;
    requestSerialize: grpc.serialize<logging_pb.LogEvent>;
    requestDeserialize: grpc.deserialize<logging_pb.LogEvent>;
    responseSerialize: grpc.serialize<logging_pb.IngestResponse>;
    responseDeserialize: grpc.deserialize<logging_pb.IngestResponse>;
}

export const LoggingServiceService: ILoggingServiceService;

export interface ILoggingServiceServer extends grpc.UntypedServiceImplementation {
    ingest: grpc.handleUnaryCall<logging_pb.LogEvent, logging_pb.IngestResponse>;
}

export interface ILoggingServiceClient {
    ingest(request: logging_pb.LogEvent, callback: (error: grpc.ServiceError | null, response: logging_pb.IngestResponse) => void): grpc.ClientUnaryCall;
    ingest(request: logging_pb.LogEvent, metadata: grpc.Metadata, callback: (error: grpc.ServiceError | null, response: logging_pb.IngestResponse) => void): grpc.ClientUnaryCall;
    ingest(request: logging_pb.LogEvent, metadata: grpc.Metadata, options: Partial<grpc.CallOptions>, callback: (error: grpc.ServiceError | null, response: logging_pb.IngestResponse) => void): grpc.ClientUnaryCall;
}

export class LoggingServiceClient extends grpc.Client implements ILoggingServiceClient {
    constructor(address: string, credentials: grpc.ChannelCredentials, options?: Partial<grpc.ClientOptions>);
    public ingest(request: logging_pb.LogEvent, callback: (error: grpc.ServiceError | null, response: logging_pb.IngestResponse) => void): grpc.ClientUnaryCall;
    public ingest(request: logging_pb.LogEvent, metadata: grpc.Metadata, callback: (error: grpc.ServiceError | null, response: logging_pb.IngestResponse) => void): grpc.ClientUnaryCall;
    public ingest(request: logging_pb.LogEvent, metadata: grpc.Metadata, options: Partial<grpc.CallOptions>, callback: (error: grpc.ServiceError | null, response: logging_pb.IngestResponse) => void): grpc.ClientUnaryCall;
}
