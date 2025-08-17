// package: sw4rm.connector
// file: connector.proto

/* tslint:disable */
/* eslint-disable */

import * as jspb from "google-protobuf";

export class ToolDescriptor extends jspb.Message { 
    getToolName(): string;
    setToolName(value: string): ToolDescriptor;
    getInputSchema(): string;
    setInputSchema(value: string): ToolDescriptor;
    getOutputSchema(): string;
    setOutputSchema(value: string): ToolDescriptor;
    getIdempotent(): boolean;
    setIdempotent(value: boolean): ToolDescriptor;
    getNeedsWorktree(): boolean;
    setNeedsWorktree(value: boolean): ToolDescriptor;
    getDefaultTimeoutS(): number;
    setDefaultTimeoutS(value: number): ToolDescriptor;
    getMaxConcurrency(): number;
    setMaxConcurrency(value: number): ToolDescriptor;
    getSideEffects(): string;
    setSideEffects(value: string): ToolDescriptor;

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): ToolDescriptor.AsObject;
    static toObject(includeInstance: boolean, msg: ToolDescriptor): ToolDescriptor.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: ToolDescriptor, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): ToolDescriptor;
    static deserializeBinaryFromReader(message: ToolDescriptor, reader: jspb.BinaryReader): ToolDescriptor;
}

export namespace ToolDescriptor {
    export type AsObject = {
        toolName: string,
        inputSchema: string,
        outputSchema: string,
        idempotent: boolean,
        needsWorktree: boolean,
        defaultTimeoutS: number,
        maxConcurrency: number,
        sideEffects: string,
    }
}

export class ProviderRegisterRequest extends jspb.Message { 
    getProviderId(): string;
    setProviderId(value: string): ProviderRegisterRequest;
    clearToolsList(): void;
    getToolsList(): Array<ToolDescriptor>;
    setToolsList(value: Array<ToolDescriptor>): ProviderRegisterRequest;
    addTools(value?: ToolDescriptor, index?: number): ToolDescriptor;

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): ProviderRegisterRequest.AsObject;
    static toObject(includeInstance: boolean, msg: ProviderRegisterRequest): ProviderRegisterRequest.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: ProviderRegisterRequest, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): ProviderRegisterRequest;
    static deserializeBinaryFromReader(message: ProviderRegisterRequest, reader: jspb.BinaryReader): ProviderRegisterRequest;
}

export namespace ProviderRegisterRequest {
    export type AsObject = {
        providerId: string,
        toolsList: Array<ToolDescriptor.AsObject>,
    }
}

export class ProviderRegisterResponse extends jspb.Message { 
    getOk(): boolean;
    setOk(value: boolean): ProviderRegisterResponse;
    getReason(): string;
    setReason(value: string): ProviderRegisterResponse;

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): ProviderRegisterResponse.AsObject;
    static toObject(includeInstance: boolean, msg: ProviderRegisterResponse): ProviderRegisterResponse.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: ProviderRegisterResponse, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): ProviderRegisterResponse;
    static deserializeBinaryFromReader(message: ProviderRegisterResponse, reader: jspb.BinaryReader): ProviderRegisterResponse;
}

export namespace ProviderRegisterResponse {
    export type AsObject = {
        ok: boolean,
        reason: string,
    }
}

export class DescribeToolsRequest extends jspb.Message { 
    getProviderId(): string;
    setProviderId(value: string): DescribeToolsRequest;

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): DescribeToolsRequest.AsObject;
    static toObject(includeInstance: boolean, msg: DescribeToolsRequest): DescribeToolsRequest.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: DescribeToolsRequest, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): DescribeToolsRequest;
    static deserializeBinaryFromReader(message: DescribeToolsRequest, reader: jspb.BinaryReader): DescribeToolsRequest;
}

export namespace DescribeToolsRequest {
    export type AsObject = {
        providerId: string,
    }
}

export class DescribeToolsResponse extends jspb.Message { 
    clearToolsList(): void;
    getToolsList(): Array<ToolDescriptor>;
    setToolsList(value: Array<ToolDescriptor>): DescribeToolsResponse;
    addTools(value?: ToolDescriptor, index?: number): ToolDescriptor;

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): DescribeToolsResponse.AsObject;
    static toObject(includeInstance: boolean, msg: DescribeToolsResponse): DescribeToolsResponse.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: DescribeToolsResponse, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): DescribeToolsResponse;
    static deserializeBinaryFromReader(message: DescribeToolsResponse, reader: jspb.BinaryReader): DescribeToolsResponse;
}

export namespace DescribeToolsResponse {
    export type AsObject = {
        toolsList: Array<ToolDescriptor.AsObject>,
    }
}
