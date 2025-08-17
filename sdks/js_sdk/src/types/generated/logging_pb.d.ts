// package: sw4rm.logging
// file: logging.proto

/* tslint:disable */
/* eslint-disable */

import * as jspb from "google-protobuf";
import * as google_protobuf_timestamp_pb from "google-protobuf/google/protobuf/timestamp_pb";

export class LogEvent extends jspb.Message { 

    hasTs(): boolean;
    clearTs(): void;
    getTs(): google_protobuf_timestamp_pb.Timestamp | undefined;
    setTs(value?: google_protobuf_timestamp_pb.Timestamp): LogEvent;
    getCorrelationId(): string;
    setCorrelationId(value: string): LogEvent;
    getAgentId(): string;
    setAgentId(value: string): LogEvent;
    getEventType(): string;
    setEventType(value: string): LogEvent;
    getLevel(): string;
    setLevel(value: string): LogEvent;
    getDetailsJson(): string;
    setDetailsJson(value: string): LogEvent;

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): LogEvent.AsObject;
    static toObject(includeInstance: boolean, msg: LogEvent): LogEvent.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: LogEvent, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): LogEvent;
    static deserializeBinaryFromReader(message: LogEvent, reader: jspb.BinaryReader): LogEvent;
}

export namespace LogEvent {
    export type AsObject = {
        ts?: google_protobuf_timestamp_pb.Timestamp.AsObject,
        correlationId: string,
        agentId: string,
        eventType: string,
        level: string,
        detailsJson: string,
    }
}

export class IngestResponse extends jspb.Message { 
    getOk(): boolean;
    setOk(value: boolean): IngestResponse;

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): IngestResponse.AsObject;
    static toObject(includeInstance: boolean, msg: IngestResponse): IngestResponse.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: IngestResponse, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): IngestResponse;
    static deserializeBinaryFromReader(message: IngestResponse, reader: jspb.BinaryReader): IngestResponse;
}

export namespace IngestResponse {
    export type AsObject = {
        ok: boolean,
    }
}
