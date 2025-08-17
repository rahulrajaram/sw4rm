// package: sw4rm.tool
// file: tool.proto

/* tslint:disable */
/* eslint-disable */

import * as jspb from "google-protobuf";
import * as google_protobuf_duration_pb from "google-protobuf/google/protobuf/duration_pb";

export class ExecutionPolicy extends jspb.Message { 

    hasTimeout(): boolean;
    clearTimeout(): void;
    getTimeout(): google_protobuf_duration_pb.Duration | undefined;
    setTimeout(value?: google_protobuf_duration_pb.Duration): ExecutionPolicy;
    getMaxRetries(): number;
    setMaxRetries(value: number): ExecutionPolicy;
    getBackoff(): string;
    setBackoff(value: string): ExecutionPolicy;
    getWorktreeRequired(): boolean;
    setWorktreeRequired(value: boolean): ExecutionPolicy;
    getNetworkPolicy(): string;
    setNetworkPolicy(value: string): ExecutionPolicy;
    getPrivilegeLevel(): string;
    setPrivilegeLevel(value: string): ExecutionPolicy;
    getBudgetCpuMs(): number;
    setBudgetCpuMs(value: number): ExecutionPolicy;
    getBudgetWallMs(): number;
    setBudgetWallMs(value: number): ExecutionPolicy;

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): ExecutionPolicy.AsObject;
    static toObject(includeInstance: boolean, msg: ExecutionPolicy): ExecutionPolicy.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: ExecutionPolicy, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): ExecutionPolicy;
    static deserializeBinaryFromReader(message: ExecutionPolicy, reader: jspb.BinaryReader): ExecutionPolicy;
}

export namespace ExecutionPolicy {
    export type AsObject = {
        timeout?: google_protobuf_duration_pb.Duration.AsObject,
        maxRetries: number,
        backoff: string,
        worktreeRequired: boolean,
        networkPolicy: string,
        privilegeLevel: string,
        budgetCpuMs: number,
        budgetWallMs: number,
    }
}

export class ToolCall extends jspb.Message { 
    getCallId(): string;
    setCallId(value: string): ToolCall;
    getToolName(): string;
    setToolName(value: string): ToolCall;
    getProviderId(): string;
    setProviderId(value: string): ToolCall;
    getContentType(): string;
    setContentType(value: string): ToolCall;
    getArgs(): Uint8Array | string;
    getArgs_asU8(): Uint8Array;
    getArgs_asB64(): string;
    setArgs(value: Uint8Array | string): ToolCall;

    hasPolicy(): boolean;
    clearPolicy(): void;
    getPolicy(): ExecutionPolicy | undefined;
    setPolicy(value?: ExecutionPolicy): ToolCall;
    getStream(): boolean;
    setStream(value: boolean): ToolCall;

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): ToolCall.AsObject;
    static toObject(includeInstance: boolean, msg: ToolCall): ToolCall.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: ToolCall, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): ToolCall;
    static deserializeBinaryFromReader(message: ToolCall, reader: jspb.BinaryReader): ToolCall;
}

export namespace ToolCall {
    export type AsObject = {
        callId: string,
        toolName: string,
        providerId: string,
        contentType: string,
        args: Uint8Array | string,
        policy?: ExecutionPolicy.AsObject,
        stream: boolean,
    }
}

export class ToolFrame extends jspb.Message { 
    getCallId(): string;
    setCallId(value: string): ToolFrame;
    getFrameNo(): number;
    setFrameNo(value: number): ToolFrame;
    getFinal(): boolean;
    setFinal(value: boolean): ToolFrame;
    getContentType(): string;
    setContentType(value: string): ToolFrame;
    getData(): Uint8Array | string;
    getData_asU8(): Uint8Array;
    getData_asB64(): string;
    setData(value: Uint8Array | string): ToolFrame;
    getSummary(): Uint8Array | string;
    getSummary_asU8(): Uint8Array;
    getSummary_asB64(): string;
    setSummary(value: Uint8Array | string): ToolFrame;

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): ToolFrame.AsObject;
    static toObject(includeInstance: boolean, msg: ToolFrame): ToolFrame.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: ToolFrame, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): ToolFrame;
    static deserializeBinaryFromReader(message: ToolFrame, reader: jspb.BinaryReader): ToolFrame;
}

export namespace ToolFrame {
    export type AsObject = {
        callId: string,
        frameNo: number,
        pb_final: boolean,
        contentType: string,
        data: Uint8Array | string,
        summary: Uint8Array | string,
    }
}

export class ToolError extends jspb.Message { 
    getCallId(): string;
    setCallId(value: string): ToolError;
    getErrorCode(): string;
    setErrorCode(value: string): ToolError;
    getMessage(): string;
    setMessage(value: string): ToolError;

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): ToolError.AsObject;
    static toObject(includeInstance: boolean, msg: ToolError): ToolError.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: ToolError, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): ToolError;
    static deserializeBinaryFromReader(message: ToolError, reader: jspb.BinaryReader): ToolError;
}

export namespace ToolError {
    export type AsObject = {
        callId: string,
        errorCode: string,
        message: string,
    }
}
