// package: sw4rm.worktree
// file: worktree.proto

/* tslint:disable */
/* eslint-disable */

import * as jspb from "google-protobuf";

export class BindRequest extends jspb.Message { 
    getAgentId(): string;
    setAgentId(value: string): BindRequest;
    getRepoId(): string;
    setRepoId(value: string): BindRequest;
    getWorktreeId(): string;
    setWorktreeId(value: string): BindRequest;

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): BindRequest.AsObject;
    static toObject(includeInstance: boolean, msg: BindRequest): BindRequest.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: BindRequest, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): BindRequest;
    static deserializeBinaryFromReader(message: BindRequest, reader: jspb.BinaryReader): BindRequest;
}

export namespace BindRequest {
    export type AsObject = {
        agentId: string,
        repoId: string,
        worktreeId: string,
    }
}

export class BindResponse extends jspb.Message { 
    getOk(): boolean;
    setOk(value: boolean): BindResponse;
    getReason(): string;
    setReason(value: string): BindResponse;

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): BindResponse.AsObject;
    static toObject(includeInstance: boolean, msg: BindResponse): BindResponse.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: BindResponse, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): BindResponse;
    static deserializeBinaryFromReader(message: BindResponse, reader: jspb.BinaryReader): BindResponse;
}

export namespace BindResponse {
    export type AsObject = {
        ok: boolean,
        reason: string,
    }
}

export class UnbindRequest extends jspb.Message { 
    getAgentId(): string;
    setAgentId(value: string): UnbindRequest;

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): UnbindRequest.AsObject;
    static toObject(includeInstance: boolean, msg: UnbindRequest): UnbindRequest.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: UnbindRequest, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): UnbindRequest;
    static deserializeBinaryFromReader(message: UnbindRequest, reader: jspb.BinaryReader): UnbindRequest;
}

export namespace UnbindRequest {
    export type AsObject = {
        agentId: string,
    }
}

export class UnbindResponse extends jspb.Message { 
    getOk(): boolean;
    setOk(value: boolean): UnbindResponse;

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): UnbindResponse.AsObject;
    static toObject(includeInstance: boolean, msg: UnbindResponse): UnbindResponse.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: UnbindResponse, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): UnbindResponse;
    static deserializeBinaryFromReader(message: UnbindResponse, reader: jspb.BinaryReader): UnbindResponse;
}

export namespace UnbindResponse {
    export type AsObject = {
        ok: boolean,
    }
}

export class SwitchRequest extends jspb.Message { 
    getAgentId(): string;
    setAgentId(value: string): SwitchRequest;
    getTargetWorktreeId(): string;
    setTargetWorktreeId(value: string): SwitchRequest;
    getRequiresHitl(): boolean;
    setRequiresHitl(value: boolean): SwitchRequest;

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): SwitchRequest.AsObject;
    static toObject(includeInstance: boolean, msg: SwitchRequest): SwitchRequest.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: SwitchRequest, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): SwitchRequest;
    static deserializeBinaryFromReader(message: SwitchRequest, reader: jspb.BinaryReader): SwitchRequest;
}

export namespace SwitchRequest {
    export type AsObject = {
        agentId: string,
        targetWorktreeId: string,
        requiresHitl: boolean,
    }
}

export class SwitchApprove extends jspb.Message { 
    getAgentId(): string;
    setAgentId(value: string): SwitchApprove;
    getTargetWorktreeId(): string;
    setTargetWorktreeId(value: string): SwitchApprove;
    getTtlMs(): number;
    setTtlMs(value: number): SwitchApprove;

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): SwitchApprove.AsObject;
    static toObject(includeInstance: boolean, msg: SwitchApprove): SwitchApprove.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: SwitchApprove, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): SwitchApprove;
    static deserializeBinaryFromReader(message: SwitchApprove, reader: jspb.BinaryReader): SwitchApprove;
}

export namespace SwitchApprove {
    export type AsObject = {
        agentId: string,
        targetWorktreeId: string,
        ttlMs: number,
    }
}

export class SwitchReject extends jspb.Message { 
    getAgentId(): string;
    setAgentId(value: string): SwitchReject;
    getReason(): string;
    setReason(value: string): SwitchReject;

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): SwitchReject.AsObject;
    static toObject(includeInstance: boolean, msg: SwitchReject): SwitchReject.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: SwitchReject, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): SwitchReject;
    static deserializeBinaryFromReader(message: SwitchReject, reader: jspb.BinaryReader): SwitchReject;
}

export namespace SwitchReject {
    export type AsObject = {
        agentId: string,
        reason: string,
    }
}

export class StatusRequest extends jspb.Message { 
    getAgentId(): string;
    setAgentId(value: string): StatusRequest;

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): StatusRequest.AsObject;
    static toObject(includeInstance: boolean, msg: StatusRequest): StatusRequest.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: StatusRequest, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): StatusRequest;
    static deserializeBinaryFromReader(message: StatusRequest, reader: jspb.BinaryReader): StatusRequest;
}

export namespace StatusRequest {
    export type AsObject = {
        agentId: string,
    }
}

export class StatusResponse extends jspb.Message { 
    getRepoId(): string;
    setRepoId(value: string): StatusResponse;
    getWorktreeId(): string;
    setWorktreeId(value: string): StatusResponse;
    getState(): string;
    setState(value: string): StatusResponse;

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): StatusResponse.AsObject;
    static toObject(includeInstance: boolean, msg: StatusResponse): StatusResponse.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: StatusResponse, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): StatusResponse;
    static deserializeBinaryFromReader(message: StatusResponse, reader: jspb.BinaryReader): StatusResponse;
}

export namespace StatusResponse {
    export type AsObject = {
        repoId: string,
        worktreeId: string,
        state: string,
    }
}
