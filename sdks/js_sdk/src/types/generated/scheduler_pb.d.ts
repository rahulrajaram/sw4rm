// package: sw4rm.scheduler
// file: scheduler.proto

/* tslint:disable */
/* eslint-disable */

import * as jspb from "google-protobuf";
import * as google_protobuf_duration_pb from "google-protobuf/google/protobuf/duration_pb";
import * as common_pb from "./common_pb";

export class SubmitTaskRequest extends jspb.Message { 
    getAgentId(): string;
    setAgentId(value: string): SubmitTaskRequest;
    getTaskId(): string;
    setTaskId(value: string): SubmitTaskRequest;
    getPriority(): number;
    setPriority(value: number): SubmitTaskRequest;
    getParams(): Uint8Array | string;
    getParams_asU8(): Uint8Array;
    getParams_asB64(): string;
    setParams(value: Uint8Array | string): SubmitTaskRequest;
    getContentType(): string;
    setContentType(value: string): SubmitTaskRequest;
    getScope(): string;
    setScope(value: string): SubmitTaskRequest;

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): SubmitTaskRequest.AsObject;
    static toObject(includeInstance: boolean, msg: SubmitTaskRequest): SubmitTaskRequest.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: SubmitTaskRequest, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): SubmitTaskRequest;
    static deserializeBinaryFromReader(message: SubmitTaskRequest, reader: jspb.BinaryReader): SubmitTaskRequest;
}

export namespace SubmitTaskRequest {
    export type AsObject = {
        agentId: string,
        taskId: string,
        priority: number,
        params: Uint8Array | string,
        contentType: string,
        scope: string,
    }
}

export class SubmitTaskResponse extends jspb.Message { 
    getAccepted(): boolean;
    setAccepted(value: boolean): SubmitTaskResponse;
    getReason(): string;
    setReason(value: string): SubmitTaskResponse;

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): SubmitTaskResponse.AsObject;
    static toObject(includeInstance: boolean, msg: SubmitTaskResponse): SubmitTaskResponse.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: SubmitTaskResponse, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): SubmitTaskResponse;
    static deserializeBinaryFromReader(message: SubmitTaskResponse, reader: jspb.BinaryReader): SubmitTaskResponse;
}

export namespace SubmitTaskResponse {
    export type AsObject = {
        accepted: boolean,
        reason: string,
    }
}

export class PreemptRequest extends jspb.Message { 
    getAgentId(): string;
    setAgentId(value: string): PreemptRequest;
    getTaskId(): string;
    setTaskId(value: string): PreemptRequest;
    getReason(): string;
    setReason(value: string): PreemptRequest;

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): PreemptRequest.AsObject;
    static toObject(includeInstance: boolean, msg: PreemptRequest): PreemptRequest.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: PreemptRequest, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): PreemptRequest;
    static deserializeBinaryFromReader(message: PreemptRequest, reader: jspb.BinaryReader): PreemptRequest;
}

export namespace PreemptRequest {
    export type AsObject = {
        agentId: string,
        taskId: string,
        reason: string,
    }
}

export class PreemptResponse extends jspb.Message { 
    getEnqueued(): boolean;
    setEnqueued(value: boolean): PreemptResponse;

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): PreemptResponse.AsObject;
    static toObject(includeInstance: boolean, msg: PreemptResponse): PreemptResponse.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: PreemptResponse, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): PreemptResponse;
    static deserializeBinaryFromReader(message: PreemptResponse, reader: jspb.BinaryReader): PreemptResponse;
}

export namespace PreemptResponse {
    export type AsObject = {
        enqueued: boolean,
    }
}

export class ShutdownAgentRequest extends jspb.Message { 
    getAgentId(): string;
    setAgentId(value: string): ShutdownAgentRequest;

    hasGracePeriod(): boolean;
    clearGracePeriod(): void;
    getGracePeriod(): google_protobuf_duration_pb.Duration | undefined;
    setGracePeriod(value?: google_protobuf_duration_pb.Duration): ShutdownAgentRequest;

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): ShutdownAgentRequest.AsObject;
    static toObject(includeInstance: boolean, msg: ShutdownAgentRequest): ShutdownAgentRequest.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: ShutdownAgentRequest, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): ShutdownAgentRequest;
    static deserializeBinaryFromReader(message: ShutdownAgentRequest, reader: jspb.BinaryReader): ShutdownAgentRequest;
}

export namespace ShutdownAgentRequest {
    export type AsObject = {
        agentId: string,
        gracePeriod?: google_protobuf_duration_pb.Duration.AsObject,
    }
}

export class ShutdownAgentResponse extends jspb.Message { 
    getOk(): boolean;
    setOk(value: boolean): ShutdownAgentResponse;

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): ShutdownAgentResponse.AsObject;
    static toObject(includeInstance: boolean, msg: ShutdownAgentResponse): ShutdownAgentResponse.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: ShutdownAgentResponse, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): ShutdownAgentResponse;
    static deserializeBinaryFromReader(message: ShutdownAgentResponse, reader: jspb.BinaryReader): ShutdownAgentResponse;
}

export namespace ShutdownAgentResponse {
    export type AsObject = {
        ok: boolean,
    }
}

export class PollActivityBufferRequest extends jspb.Message { 
    getAgentId(): string;
    setAgentId(value: string): PollActivityBufferRequest;

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): PollActivityBufferRequest.AsObject;
    static toObject(includeInstance: boolean, msg: PollActivityBufferRequest): PollActivityBufferRequest.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: PollActivityBufferRequest, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): PollActivityBufferRequest;
    static deserializeBinaryFromReader(message: PollActivityBufferRequest, reader: jspb.BinaryReader): PollActivityBufferRequest;
}

export namespace PollActivityBufferRequest {
    export type AsObject = {
        agentId: string,
    }
}

export class ActivityEntry extends jspb.Message { 
    getTaskId(): string;
    setTaskId(value: string): ActivityEntry;
    getRepoId(): string;
    setRepoId(value: string): ActivityEntry;
    getWorktreeId(): string;
    setWorktreeId(value: string): ActivityEntry;
    getBranch(): string;
    setBranch(value: string): ActivityEntry;
    getDescription(): string;
    setDescription(value: string): ActivityEntry;
    getTimestamp(): string;
    setTimestamp(value: string): ActivityEntry;

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): ActivityEntry.AsObject;
    static toObject(includeInstance: boolean, msg: ActivityEntry): ActivityEntry.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: ActivityEntry, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): ActivityEntry;
    static deserializeBinaryFromReader(message: ActivityEntry, reader: jspb.BinaryReader): ActivityEntry;
}

export namespace ActivityEntry {
    export type AsObject = {
        taskId: string,
        repoId: string,
        worktreeId: string,
        branch: string,
        description: string,
        timestamp: string,
    }
}

export class PollActivityBufferResponse extends jspb.Message { 
    clearEntriesList(): void;
    getEntriesList(): Array<ActivityEntry>;
    setEntriesList(value: Array<ActivityEntry>): PollActivityBufferResponse;
    addEntries(value?: ActivityEntry, index?: number): ActivityEntry;

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): PollActivityBufferResponse.AsObject;
    static toObject(includeInstance: boolean, msg: PollActivityBufferResponse): PollActivityBufferResponse.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: PollActivityBufferResponse, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): PollActivityBufferResponse;
    static deserializeBinaryFromReader(message: PollActivityBufferResponse, reader: jspb.BinaryReader): PollActivityBufferResponse;
}

export namespace PollActivityBufferResponse {
    export type AsObject = {
        entriesList: Array<ActivityEntry.AsObject>,
    }
}

export class PurgeActivityRequest extends jspb.Message { 
    getAgentId(): string;
    setAgentId(value: string): PurgeActivityRequest;
    clearTaskIdsList(): void;
    getTaskIdsList(): Array<string>;
    setTaskIdsList(value: Array<string>): PurgeActivityRequest;
    addTaskIds(value: string, index?: number): string;

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): PurgeActivityRequest.AsObject;
    static toObject(includeInstance: boolean, msg: PurgeActivityRequest): PurgeActivityRequest.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: PurgeActivityRequest, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): PurgeActivityRequest;
    static deserializeBinaryFromReader(message: PurgeActivityRequest, reader: jspb.BinaryReader): PurgeActivityRequest;
}

export namespace PurgeActivityRequest {
    export type AsObject = {
        agentId: string,
        taskIdsList: Array<string>,
    }
}

export class PurgeActivityResponse extends jspb.Message { 
    getPurged(): number;
    setPurged(value: number): PurgeActivityResponse;

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): PurgeActivityResponse.AsObject;
    static toObject(includeInstance: boolean, msg: PurgeActivityResponse): PurgeActivityResponse.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: PurgeActivityResponse, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): PurgeActivityResponse;
    static deserializeBinaryFromReader(message: PurgeActivityResponse, reader: jspb.BinaryReader): PurgeActivityResponse;
}

export namespace PurgeActivityResponse {
    export type AsObject = {
        purged: number,
    }
}
