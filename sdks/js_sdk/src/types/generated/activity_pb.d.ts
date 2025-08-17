// package: sw4rm.activity
// file: activity.proto

/* tslint:disable */
/* eslint-disable */

import * as jspb from "google-protobuf";

export class Artifact extends jspb.Message { 
    getNegotiationId(): string;
    setNegotiationId(value: string): Artifact;
    getKind(): string;
    setKind(value: string): Artifact;
    getVersion(): string;
    setVersion(value: string): Artifact;
    getContentType(): string;
    setContentType(value: string): Artifact;
    getContent(): Uint8Array | string;
    getContent_asU8(): Uint8Array;
    getContent_asB64(): string;
    setContent(value: Uint8Array | string): Artifact;
    getCreatedAt(): string;
    setCreatedAt(value: string): Artifact;

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): Artifact.AsObject;
    static toObject(includeInstance: boolean, msg: Artifact): Artifact.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: Artifact, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): Artifact;
    static deserializeBinaryFromReader(message: Artifact, reader: jspb.BinaryReader): Artifact;
}

export namespace Artifact {
    export type AsObject = {
        negotiationId: string,
        kind: string,
        version: string,
        contentType: string,
        content: Uint8Array | string,
        createdAt: string,
    }
}

export class AppendArtifactRequest extends jspb.Message { 

    hasArtifact(): boolean;
    clearArtifact(): void;
    getArtifact(): Artifact | undefined;
    setArtifact(value?: Artifact): AppendArtifactRequest;

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): AppendArtifactRequest.AsObject;
    static toObject(includeInstance: boolean, msg: AppendArtifactRequest): AppendArtifactRequest.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: AppendArtifactRequest, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): AppendArtifactRequest;
    static deserializeBinaryFromReader(message: AppendArtifactRequest, reader: jspb.BinaryReader): AppendArtifactRequest;
}

export namespace AppendArtifactRequest {
    export type AsObject = {
        artifact?: Artifact.AsObject,
    }
}

export class AppendArtifactResponse extends jspb.Message { 
    getOk(): boolean;
    setOk(value: boolean): AppendArtifactResponse;
    getReason(): string;
    setReason(value: string): AppendArtifactResponse;

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): AppendArtifactResponse.AsObject;
    static toObject(includeInstance: boolean, msg: AppendArtifactResponse): AppendArtifactResponse.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: AppendArtifactResponse, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): AppendArtifactResponse;
    static deserializeBinaryFromReader(message: AppendArtifactResponse, reader: jspb.BinaryReader): AppendArtifactResponse;
}

export namespace AppendArtifactResponse {
    export type AsObject = {
        ok: boolean,
        reason: string,
    }
}

export class ListArtifactsRequest extends jspb.Message { 
    getNegotiationId(): string;
    setNegotiationId(value: string): ListArtifactsRequest;
    getKind(): string;
    setKind(value: string): ListArtifactsRequest;

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): ListArtifactsRequest.AsObject;
    static toObject(includeInstance: boolean, msg: ListArtifactsRequest): ListArtifactsRequest.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: ListArtifactsRequest, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): ListArtifactsRequest;
    static deserializeBinaryFromReader(message: ListArtifactsRequest, reader: jspb.BinaryReader): ListArtifactsRequest;
}

export namespace ListArtifactsRequest {
    export type AsObject = {
        negotiationId: string,
        kind: string,
    }
}

export class ListArtifactsResponse extends jspb.Message { 
    clearItemsList(): void;
    getItemsList(): Array<Artifact>;
    setItemsList(value: Array<Artifact>): ListArtifactsResponse;
    addItems(value?: Artifact, index?: number): Artifact;

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): ListArtifactsResponse.AsObject;
    static toObject(includeInstance: boolean, msg: ListArtifactsResponse): ListArtifactsResponse.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: ListArtifactsResponse, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): ListArtifactsResponse;
    static deserializeBinaryFromReader(message: ListArtifactsResponse, reader: jspb.BinaryReader): ListArtifactsResponse;
}

export namespace ListArtifactsResponse {
    export type AsObject = {
        itemsList: Array<Artifact.AsObject>,
    }
}
