// package: sw4rm.handoff
// file: handoff.proto

/* tslint:disable */
/* eslint-disable */

import * as jspb from "google-protobuf";
import * as common_pb from "./common_pb";
import * as google_protobuf_duration_pb from "google-protobuf/google/protobuf/duration_pb";

export class HandoffRequest extends jspb.Message { 
    getRequestId(): string;
    setRequestId(value: string): HandoffRequest;
    getFromAgent(): string;
    setFromAgent(value: string): HandoffRequest;
    getToAgent(): string;
    setToAgent(value: string): HandoffRequest;
    getReason(): string;
    setReason(value: string): HandoffRequest;
    getContextSnapshot(): Uint8Array | string;
    getContextSnapshot_asU8(): Uint8Array;
    getContextSnapshot_asB64(): string;
    setContextSnapshot(value: Uint8Array | string): HandoffRequest;
    clearCapabilitiesRequiredList(): void;
    getCapabilitiesRequiredList(): Array<string>;
    setCapabilitiesRequiredList(value: Array<string>): HandoffRequest;
    addCapabilitiesRequired(value: string, index?: number): string;
    getPriority(): number;
    setPriority(value: number): HandoffRequest;

    hasTimeout(): boolean;
    clearTimeout(): void;
    getTimeout(): google_protobuf_duration_pb.Duration | undefined;
    setTimeout(value?: google_protobuf_duration_pb.Duration): HandoffRequest;

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): HandoffRequest.AsObject;
    static toObject(includeInstance: boolean, msg: HandoffRequest): HandoffRequest.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: HandoffRequest, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): HandoffRequest;
    static deserializeBinaryFromReader(message: HandoffRequest, reader: jspb.BinaryReader): HandoffRequest;
}

export namespace HandoffRequest {
    export type AsObject = {
        requestId: string,
        fromAgent: string,
        toAgent: string,
        reason: string,
        contextSnapshot: Uint8Array | string,
        capabilitiesRequiredList: Array<string>,
        priority: number,
        timeout?: google_protobuf_duration_pb.Duration.AsObject,
    }
}

export class HandoffResponse extends jspb.Message { 
    getRequestId(): string;
    setRequestId(value: string): HandoffResponse;
    getAccepted(): boolean;
    setAccepted(value: boolean): HandoffResponse;
    getAcceptingAgent(): string;
    setAcceptingAgent(value: string): HandoffResponse;
    getRejectionReason(): string;
    setRejectionReason(value: string): HandoffResponse;

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): HandoffResponse.AsObject;
    static toObject(includeInstance: boolean, msg: HandoffResponse): HandoffResponse.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: HandoffResponse, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): HandoffResponse;
    static deserializeBinaryFromReader(message: HandoffResponse, reader: jspb.BinaryReader): HandoffResponse;
}

export namespace HandoffResponse {
    export type AsObject = {
        requestId: string,
        accepted: boolean,
        acceptingAgent: string,
        rejectionReason: string,
    }
}

export class GetPendingHandoffsRequest extends jspb.Message { 
    getAgentId(): string;
    setAgentId(value: string): GetPendingHandoffsRequest;

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): GetPendingHandoffsRequest.AsObject;
    static toObject(includeInstance: boolean, msg: GetPendingHandoffsRequest): GetPendingHandoffsRequest.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: GetPendingHandoffsRequest, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): GetPendingHandoffsRequest;
    static deserializeBinaryFromReader(message: GetPendingHandoffsRequest, reader: jspb.BinaryReader): GetPendingHandoffsRequest;
}

export namespace GetPendingHandoffsRequest {
    export type AsObject = {
        agentId: string,
    }
}

export class GetPendingHandoffsResponse extends jspb.Message { 
    clearPendingRequestsList(): void;
    getPendingRequestsList(): Array<HandoffRequest>;
    setPendingRequestsList(value: Array<HandoffRequest>): GetPendingHandoffsResponse;
    addPendingRequests(value?: HandoffRequest, index?: number): HandoffRequest;

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): GetPendingHandoffsResponse.AsObject;
    static toObject(includeInstance: boolean, msg: GetPendingHandoffsResponse): GetPendingHandoffsResponse.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: GetPendingHandoffsResponse, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): GetPendingHandoffsResponse;
    static deserializeBinaryFromReader(message: GetPendingHandoffsResponse, reader: jspb.BinaryReader): GetPendingHandoffsResponse;
}

export namespace GetPendingHandoffsResponse {
    export type AsObject = {
        pendingRequestsList: Array<HandoffRequest.AsObject>,
    }
}

export class CompleteHandoffRequest extends jspb.Message { 
    getRequestId(): string;
    setRequestId(value: string): CompleteHandoffRequest;
    getStatus(): HandoffStatus;
    setStatus(value: HandoffStatus): CompleteHandoffRequest;

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): CompleteHandoffRequest.AsObject;
    static toObject(includeInstance: boolean, msg: CompleteHandoffRequest): CompleteHandoffRequest.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: CompleteHandoffRequest, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): CompleteHandoffRequest;
    static deserializeBinaryFromReader(message: CompleteHandoffRequest, reader: jspb.BinaryReader): CompleteHandoffRequest;
}

export namespace CompleteHandoffRequest {
    export type AsObject = {
        requestId: string,
        status: HandoffStatus,
    }
}

export class CompleteHandoffResponse extends jspb.Message { 
    getSuccess(): boolean;
    setSuccess(value: boolean): CompleteHandoffResponse;
    getMessage(): string;
    setMessage(value: string): CompleteHandoffResponse;

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): CompleteHandoffResponse.AsObject;
    static toObject(includeInstance: boolean, msg: CompleteHandoffResponse): CompleteHandoffResponse.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: CompleteHandoffResponse, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): CompleteHandoffResponse;
    static deserializeBinaryFromReader(message: CompleteHandoffResponse, reader: jspb.BinaryReader): CompleteHandoffResponse;
}

export namespace CompleteHandoffResponse {
    export type AsObject = {
        success: boolean,
        message: string,
    }
}

export enum HandoffStatus {
    HANDOFF_STATUS_UNSPECIFIED = 0,
    PENDING = 1,
    ACCEPTED = 2,
    REJECTED = 3,
    COMPLETED = 4,
    EXPIRED = 5,
}
