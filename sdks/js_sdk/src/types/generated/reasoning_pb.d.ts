// package: sw4rm.reasoning
// file: reasoning.proto

/* tslint:disable */
/* eslint-disable */

import * as jspb from "google-protobuf";

export class ParallelismCheckRequest extends jspb.Message { 
    getScopeA(): string;
    setScopeA(value: string): ParallelismCheckRequest;
    getScopeB(): string;
    setScopeB(value: string): ParallelismCheckRequest;

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): ParallelismCheckRequest.AsObject;
    static toObject(includeInstance: boolean, msg: ParallelismCheckRequest): ParallelismCheckRequest.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: ParallelismCheckRequest, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): ParallelismCheckRequest;
    static deserializeBinaryFromReader(message: ParallelismCheckRequest, reader: jspb.BinaryReader): ParallelismCheckRequest;
}

export namespace ParallelismCheckRequest {
    export type AsObject = {
        scopeA: string,
        scopeB: string,
    }
}

export class ParallelismCheckResponse extends jspb.Message { 
    getConfidenceScore(): number;
    setConfidenceScore(value: number): ParallelismCheckResponse;
    getNotes(): string;
    setNotes(value: string): ParallelismCheckResponse;

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): ParallelismCheckResponse.AsObject;
    static toObject(includeInstance: boolean, msg: ParallelismCheckResponse): ParallelismCheckResponse.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: ParallelismCheckResponse, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): ParallelismCheckResponse;
    static deserializeBinaryFromReader(message: ParallelismCheckResponse, reader: jspb.BinaryReader): ParallelismCheckResponse;
}

export namespace ParallelismCheckResponse {
    export type AsObject = {
        confidenceScore: number,
        notes: string,
    }
}

export class DebateEvaluateRequest extends jspb.Message { 
    getNegotiationId(): string;
    setNegotiationId(value: string): DebateEvaluateRequest;
    getProposalA(): string;
    setProposalA(value: string): DebateEvaluateRequest;
    getProposalB(): string;
    setProposalB(value: string): DebateEvaluateRequest;
    getIntensity(): string;
    setIntensity(value: string): DebateEvaluateRequest;

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): DebateEvaluateRequest.AsObject;
    static toObject(includeInstance: boolean, msg: DebateEvaluateRequest): DebateEvaluateRequest.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: DebateEvaluateRequest, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): DebateEvaluateRequest;
    static deserializeBinaryFromReader(message: DebateEvaluateRequest, reader: jspb.BinaryReader): DebateEvaluateRequest;
}

export namespace DebateEvaluateRequest {
    export type AsObject = {
        negotiationId: string,
        proposalA: string,
        proposalB: string,
        intensity: string,
    }
}

export class DebateEvaluateResponse extends jspb.Message { 
    getConfidenceScore(): number;
    setConfidenceScore(value: number): DebateEvaluateResponse;
    getNotes(): string;
    setNotes(value: string): DebateEvaluateResponse;

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): DebateEvaluateResponse.AsObject;
    static toObject(includeInstance: boolean, msg: DebateEvaluateResponse): DebateEvaluateResponse.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: DebateEvaluateResponse, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): DebateEvaluateResponse;
    static deserializeBinaryFromReader(message: DebateEvaluateResponse, reader: jspb.BinaryReader): DebateEvaluateResponse;
}

export namespace DebateEvaluateResponse {
    export type AsObject = {
        confidenceScore: number,
        notes: string,
    }
}

export class TextSegment extends jspb.Message { 
    getKind(): string;
    setKind(value: string): TextSegment;
    getContent(): string;
    setContent(value: string): TextSegment;
    getSeq(): number;
    setSeq(value: number): TextSegment;
    getAt(): string;
    setAt(value: string): TextSegment;

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): TextSegment.AsObject;
    static toObject(includeInstance: boolean, msg: TextSegment): TextSegment.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: TextSegment, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): TextSegment;
    static deserializeBinaryFromReader(message: TextSegment, reader: jspb.BinaryReader): TextSegment;
}

export namespace TextSegment {
    export type AsObject = {
        kind: string,
        content: string,
        seq: number,
        at: string,
    }
}

export class SummarizeRequest extends jspb.Message { 
    getSessionId(): string;
    setSessionId(value: string): SummarizeRequest;
    clearSegmentsList(): void;
    getSegmentsList(): Array<TextSegment>;
    setSegmentsList(value: Array<TextSegment>): SummarizeRequest;
    addSegments(value?: TextSegment, index?: number): TextSegment;
    getMaxTokens(): number;
    setMaxTokens(value: number): SummarizeRequest;
    getMode(): string;
    setMode(value: string): SummarizeRequest;

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): SummarizeRequest.AsObject;
    static toObject(includeInstance: boolean, msg: SummarizeRequest): SummarizeRequest.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: SummarizeRequest, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): SummarizeRequest;
    static deserializeBinaryFromReader(message: SummarizeRequest, reader: jspb.BinaryReader): SummarizeRequest;
}

export namespace SummarizeRequest {
    export type AsObject = {
        sessionId: string,
        segmentsList: Array<TextSegment.AsObject>,
        maxTokens: number,
        mode: string,
    }
}

export class SummarizeResponse extends jspb.Message { 
    getSummary(): string;
    setSummary(value: string): SummarizeResponse;
    getTokens(): number;
    setTokens(value: number): SummarizeResponse;
    getCostCents(): number;
    setCostCents(value: number): SummarizeResponse;
    getModel(): string;
    setModel(value: string): SummarizeResponse;

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): SummarizeResponse.AsObject;
    static toObject(includeInstance: boolean, msg: SummarizeResponse): SummarizeResponse.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: SummarizeResponse, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): SummarizeResponse;
    static deserializeBinaryFromReader(message: SummarizeResponse, reader: jspb.BinaryReader): SummarizeResponse;
}

export namespace SummarizeResponse {
    export type AsObject = {
        summary: string,
        tokens: number,
        costCents: number,
        model: string,
    }
}
