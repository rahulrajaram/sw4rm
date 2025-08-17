// package: sw4rm.negotiation
// file: negotiation.proto

/* tslint:disable */
/* eslint-disable */

import * as jspb from "google-protobuf";
import * as common_pb from "./common_pb";
import * as google_protobuf_duration_pb from "google-protobuf/google/protobuf/duration_pb";

export class NegotiationOpen extends jspb.Message { 
    getNegotiationId(): string;
    setNegotiationId(value: string): NegotiationOpen;
    getCorrelationId(): string;
    setCorrelationId(value: string): NegotiationOpen;
    getTopic(): string;
    setTopic(value: string): NegotiationOpen;
    clearParticipantsList(): void;
    getParticipantsList(): Array<string>;
    setParticipantsList(value: Array<string>): NegotiationOpen;
    addParticipants(value: string, index?: number): string;
    getIntensity(): common_pb.DebateIntensity;
    setIntensity(value: common_pb.DebateIntensity): NegotiationOpen;

    hasDebateTimeout(): boolean;
    clearDebateTimeout(): void;
    getDebateTimeout(): google_protobuf_duration_pb.Duration | undefined;
    setDebateTimeout(value?: google_protobuf_duration_pb.Duration): NegotiationOpen;

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): NegotiationOpen.AsObject;
    static toObject(includeInstance: boolean, msg: NegotiationOpen): NegotiationOpen.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: NegotiationOpen, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): NegotiationOpen;
    static deserializeBinaryFromReader(message: NegotiationOpen, reader: jspb.BinaryReader): NegotiationOpen;
}

export namespace NegotiationOpen {
    export type AsObject = {
        negotiationId: string,
        correlationId: string,
        topic: string,
        participantsList: Array<string>,
        intensity: common_pb.DebateIntensity,
        debateTimeout?: google_protobuf_duration_pb.Duration.AsObject,
    }
}

export class Proposal extends jspb.Message { 
    getNegotiationId(): string;
    setNegotiationId(value: string): Proposal;
    getFromAgent(): string;
    setFromAgent(value: string): Proposal;
    getContentType(): string;
    setContentType(value: string): Proposal;
    getPayload(): Uint8Array | string;
    getPayload_asU8(): Uint8Array;
    getPayload_asB64(): string;
    setPayload(value: Uint8Array | string): Proposal;

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): Proposal.AsObject;
    static toObject(includeInstance: boolean, msg: Proposal): Proposal.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: Proposal, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): Proposal;
    static deserializeBinaryFromReader(message: Proposal, reader: jspb.BinaryReader): Proposal;
}

export namespace Proposal {
    export type AsObject = {
        negotiationId: string,
        fromAgent: string,
        contentType: string,
        payload: Uint8Array | string,
    }
}

export class CounterProposal extends jspb.Message { 
    getNegotiationId(): string;
    setNegotiationId(value: string): CounterProposal;
    getFromAgent(): string;
    setFromAgent(value: string): CounterProposal;
    getContentType(): string;
    setContentType(value: string): CounterProposal;
    getPayload(): Uint8Array | string;
    getPayload_asU8(): Uint8Array;
    getPayload_asB64(): string;
    setPayload(value: Uint8Array | string): CounterProposal;

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): CounterProposal.AsObject;
    static toObject(includeInstance: boolean, msg: CounterProposal): CounterProposal.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: CounterProposal, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): CounterProposal;
    static deserializeBinaryFromReader(message: CounterProposal, reader: jspb.BinaryReader): CounterProposal;
}

export namespace CounterProposal {
    export type AsObject = {
        negotiationId: string,
        fromAgent: string,
        contentType: string,
        payload: Uint8Array | string,
    }
}

export class Evaluation extends jspb.Message { 
    getNegotiationId(): string;
    setNegotiationId(value: string): Evaluation;
    getFromAgent(): string;
    setFromAgent(value: string): Evaluation;
    getConfidenceScore(): number;
    setConfidenceScore(value: number): Evaluation;
    getNotes(): string;
    setNotes(value: string): Evaluation;

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): Evaluation.AsObject;
    static toObject(includeInstance: boolean, msg: Evaluation): Evaluation.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: Evaluation, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): Evaluation;
    static deserializeBinaryFromReader(message: Evaluation, reader: jspb.BinaryReader): Evaluation;
}

export namespace Evaluation {
    export type AsObject = {
        negotiationId: string,
        fromAgent: string,
        confidenceScore: number,
        notes: string,
    }
}

export class Decision extends jspb.Message { 
    getNegotiationId(): string;
    setNegotiationId(value: string): Decision;
    getDecidedBy(): string;
    setDecidedBy(value: string): Decision;
    getContentType(): string;
    setContentType(value: string): Decision;
    getResult(): Uint8Array | string;
    getResult_asU8(): Uint8Array;
    getResult_asB64(): string;
    setResult(value: Uint8Array | string): Decision;

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): Decision.AsObject;
    static toObject(includeInstance: boolean, msg: Decision): Decision.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: Decision, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): Decision;
    static deserializeBinaryFromReader(message: Decision, reader: jspb.BinaryReader): Decision;
}

export namespace Decision {
    export type AsObject = {
        negotiationId: string,
        decidedBy: string,
        contentType: string,
        result: Uint8Array | string,
    }
}

export class AbortRequest extends jspb.Message { 
    getNegotiationId(): string;
    setNegotiationId(value: string): AbortRequest;
    getReason(): string;
    setReason(value: string): AbortRequest;

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): AbortRequest.AsObject;
    static toObject(includeInstance: boolean, msg: AbortRequest): AbortRequest.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: AbortRequest, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): AbortRequest;
    static deserializeBinaryFromReader(message: AbortRequest, reader: jspb.BinaryReader): AbortRequest;
}

export namespace AbortRequest {
    export type AsObject = {
        negotiationId: string,
        reason: string,
    }
}
