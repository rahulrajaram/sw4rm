// package: sw4rm.negotiation_room
// file: negotiation_room.proto

/* tslint:disable */
/* eslint-disable */

import * as jspb from "google-protobuf";
import * as google_protobuf_timestamp_pb from "google-protobuf/google/protobuf/timestamp_pb";

export class NegotiationProposal extends jspb.Message { 
    getArtifactType(): ArtifactType;
    setArtifactType(value: ArtifactType): NegotiationProposal;
    getArtifactId(): string;
    setArtifactId(value: string): NegotiationProposal;
    getProducerId(): string;
    setProducerId(value: string): NegotiationProposal;
    getArtifact(): Uint8Array | string;
    getArtifact_asU8(): Uint8Array;
    getArtifact_asB64(): string;
    setArtifact(value: Uint8Array | string): NegotiationProposal;
    getArtifactContentType(): string;
    setArtifactContentType(value: string): NegotiationProposal;
    clearRequestedCriticsList(): void;
    getRequestedCriticsList(): Array<string>;
    setRequestedCriticsList(value: Array<string>): NegotiationProposal;
    addRequestedCritics(value: string, index?: number): string;
    getNegotiationRoomId(): string;
    setNegotiationRoomId(value: string): NegotiationProposal;

    hasCreatedAt(): boolean;
    clearCreatedAt(): void;
    getCreatedAt(): google_protobuf_timestamp_pb.Timestamp | undefined;
    setCreatedAt(value?: google_protobuf_timestamp_pb.Timestamp): NegotiationProposal;

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): NegotiationProposal.AsObject;
    static toObject(includeInstance: boolean, msg: NegotiationProposal): NegotiationProposal.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: NegotiationProposal, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): NegotiationProposal;
    static deserializeBinaryFromReader(message: NegotiationProposal, reader: jspb.BinaryReader): NegotiationProposal;
}

export namespace NegotiationProposal {
    export type AsObject = {
        artifactType: ArtifactType,
        artifactId: string,
        producerId: string,
        artifact: Uint8Array | string,
        artifactContentType: string,
        requestedCriticsList: Array<string>,
        negotiationRoomId: string,
        createdAt?: google_protobuf_timestamp_pb.Timestamp.AsObject,
    }
}

export class NegotiationVote extends jspb.Message { 
    getArtifactId(): string;
    setArtifactId(value: string): NegotiationVote;
    getCriticId(): string;
    setCriticId(value: string): NegotiationVote;
    getScore(): number;
    setScore(value: number): NegotiationVote;
    getConfidence(): number;
    setConfidence(value: number): NegotiationVote;
    getPassed(): boolean;
    setPassed(value: boolean): NegotiationVote;
    clearStrengthsList(): void;
    getStrengthsList(): Array<string>;
    setStrengthsList(value: Array<string>): NegotiationVote;
    addStrengths(value: string, index?: number): string;
    clearWeaknessesList(): void;
    getWeaknessesList(): Array<string>;
    setWeaknessesList(value: Array<string>): NegotiationVote;
    addWeaknesses(value: string, index?: number): string;
    clearRecommendationsList(): void;
    getRecommendationsList(): Array<string>;
    setRecommendationsList(value: Array<string>): NegotiationVote;
    addRecommendations(value: string, index?: number): string;
    getNegotiationRoomId(): string;
    setNegotiationRoomId(value: string): NegotiationVote;

    hasVotedAt(): boolean;
    clearVotedAt(): void;
    getVotedAt(): google_protobuf_timestamp_pb.Timestamp | undefined;
    setVotedAt(value?: google_protobuf_timestamp_pb.Timestamp): NegotiationVote;

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): NegotiationVote.AsObject;
    static toObject(includeInstance: boolean, msg: NegotiationVote): NegotiationVote.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: NegotiationVote, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): NegotiationVote;
    static deserializeBinaryFromReader(message: NegotiationVote, reader: jspb.BinaryReader): NegotiationVote;
}

export namespace NegotiationVote {
    export type AsObject = {
        artifactId: string,
        criticId: string,
        score: number,
        confidence: number,
        passed: boolean,
        strengthsList: Array<string>,
        weaknessesList: Array<string>,
        recommendationsList: Array<string>,
        negotiationRoomId: string,
        votedAt?: google_protobuf_timestamp_pb.Timestamp.AsObject,
    }
}

export class AggregatedScore extends jspb.Message { 
    getMean(): number;
    setMean(value: number): AggregatedScore;
    getMinScore(): number;
    setMinScore(value: number): AggregatedScore;
    getMaxScore(): number;
    setMaxScore(value: number): AggregatedScore;
    getStdDev(): number;
    setStdDev(value: number): AggregatedScore;
    getWeightedMean(): number;
    setWeightedMean(value: number): AggregatedScore;
    getVoteCount(): number;
    setVoteCount(value: number): AggregatedScore;

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): AggregatedScore.AsObject;
    static toObject(includeInstance: boolean, msg: AggregatedScore): AggregatedScore.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: AggregatedScore, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): AggregatedScore;
    static deserializeBinaryFromReader(message: AggregatedScore, reader: jspb.BinaryReader): AggregatedScore;
}

export namespace AggregatedScore {
    export type AsObject = {
        mean: number,
        minScore: number,
        maxScore: number,
        stdDev: number,
        weightedMean: number,
        voteCount: number,
    }
}

export class NegotiationDecision extends jspb.Message { 
    getArtifactId(): string;
    setArtifactId(value: string): NegotiationDecision;
    getOutcome(): DecisionOutcome;
    setOutcome(value: DecisionOutcome): NegotiationDecision;
    clearVotesList(): void;
    getVotesList(): Array<NegotiationVote>;
    setVotesList(value: Array<NegotiationVote>): NegotiationDecision;
    addVotes(value?: NegotiationVote, index?: number): NegotiationVote;

    hasAggregatedScore(): boolean;
    clearAggregatedScore(): void;
    getAggregatedScore(): AggregatedScore | undefined;
    setAggregatedScore(value?: AggregatedScore): NegotiationDecision;
    getPolicyVersion(): string;
    setPolicyVersion(value: string): NegotiationDecision;
    getReason(): string;
    setReason(value: string): NegotiationDecision;
    getNegotiationRoomId(): string;
    setNegotiationRoomId(value: string): NegotiationDecision;

    hasDecidedAt(): boolean;
    clearDecidedAt(): void;
    getDecidedAt(): google_protobuf_timestamp_pb.Timestamp | undefined;
    setDecidedAt(value?: google_protobuf_timestamp_pb.Timestamp): NegotiationDecision;

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): NegotiationDecision.AsObject;
    static toObject(includeInstance: boolean, msg: NegotiationDecision): NegotiationDecision.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: NegotiationDecision, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): NegotiationDecision;
    static deserializeBinaryFromReader(message: NegotiationDecision, reader: jspb.BinaryReader): NegotiationDecision;
}

export namespace NegotiationDecision {
    export type AsObject = {
        artifactId: string,
        outcome: DecisionOutcome,
        votesList: Array<NegotiationVote.AsObject>,
        aggregatedScore?: AggregatedScore.AsObject,
        policyVersion: string,
        reason: string,
        negotiationRoomId: string,
        decidedAt?: google_protobuf_timestamp_pb.Timestamp.AsObject,
    }
}

export class SubmitProposalRequest extends jspb.Message { 

    hasProposal(): boolean;
    clearProposal(): void;
    getProposal(): NegotiationProposal | undefined;
    setProposal(value?: NegotiationProposal): SubmitProposalRequest;

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): SubmitProposalRequest.AsObject;
    static toObject(includeInstance: boolean, msg: SubmitProposalRequest): SubmitProposalRequest.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: SubmitProposalRequest, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): SubmitProposalRequest;
    static deserializeBinaryFromReader(message: SubmitProposalRequest, reader: jspb.BinaryReader): SubmitProposalRequest;
}

export namespace SubmitProposalRequest {
    export type AsObject = {
        proposal?: NegotiationProposal.AsObject,
    }
}

export class SubmitProposalResponse extends jspb.Message { 
    getArtifactId(): string;
    setArtifactId(value: string): SubmitProposalResponse;
    getNegotiationRoomId(): string;
    setNegotiationRoomId(value: string): SubmitProposalResponse;

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): SubmitProposalResponse.AsObject;
    static toObject(includeInstance: boolean, msg: SubmitProposalResponse): SubmitProposalResponse.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: SubmitProposalResponse, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): SubmitProposalResponse;
    static deserializeBinaryFromReader(message: SubmitProposalResponse, reader: jspb.BinaryReader): SubmitProposalResponse;
}

export namespace SubmitProposalResponse {
    export type AsObject = {
        artifactId: string,
        negotiationRoomId: string,
    }
}

export class SubmitVoteRequest extends jspb.Message { 

    hasVote(): boolean;
    clearVote(): void;
    getVote(): NegotiationVote | undefined;
    setVote(value?: NegotiationVote): SubmitVoteRequest;

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): SubmitVoteRequest.AsObject;
    static toObject(includeInstance: boolean, msg: SubmitVoteRequest): SubmitVoteRequest.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: SubmitVoteRequest, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): SubmitVoteRequest;
    static deserializeBinaryFromReader(message: SubmitVoteRequest, reader: jspb.BinaryReader): SubmitVoteRequest;
}

export namespace SubmitVoteRequest {
    export type AsObject = {
        vote?: NegotiationVote.AsObject,
    }
}

export class SubmitVoteResponse extends jspb.Message { 
    getArtifactId(): string;
    setArtifactId(value: string): SubmitVoteResponse;
    getCriticId(): string;
    setCriticId(value: string): SubmitVoteResponse;

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): SubmitVoteResponse.AsObject;
    static toObject(includeInstance: boolean, msg: SubmitVoteResponse): SubmitVoteResponse.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: SubmitVoteResponse, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): SubmitVoteResponse;
    static deserializeBinaryFromReader(message: SubmitVoteResponse, reader: jspb.BinaryReader): SubmitVoteResponse;
}

export namespace SubmitVoteResponse {
    export type AsObject = {
        artifactId: string,
        criticId: string,
    }
}

export class GetVotesRequest extends jspb.Message { 
    getArtifactId(): string;
    setArtifactId(value: string): GetVotesRequest;
    getNegotiationRoomId(): string;
    setNegotiationRoomId(value: string): GetVotesRequest;

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): GetVotesRequest.AsObject;
    static toObject(includeInstance: boolean, msg: GetVotesRequest): GetVotesRequest.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: GetVotesRequest, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): GetVotesRequest;
    static deserializeBinaryFromReader(message: GetVotesRequest, reader: jspb.BinaryReader): GetVotesRequest;
}

export namespace GetVotesRequest {
    export type AsObject = {
        artifactId: string,
        negotiationRoomId: string,
    }
}

export class GetVotesResponse extends jspb.Message { 
    clearVotesList(): void;
    getVotesList(): Array<NegotiationVote>;
    setVotesList(value: Array<NegotiationVote>): GetVotesResponse;
    addVotes(value?: NegotiationVote, index?: number): NegotiationVote;
    getVoteCount(): number;
    setVoteCount(value: number): GetVotesResponse;

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): GetVotesResponse.AsObject;
    static toObject(includeInstance: boolean, msg: GetVotesResponse): GetVotesResponse.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: GetVotesResponse, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): GetVotesResponse;
    static deserializeBinaryFromReader(message: GetVotesResponse, reader: jspb.BinaryReader): GetVotesResponse;
}

export namespace GetVotesResponse {
    export type AsObject = {
        votesList: Array<NegotiationVote.AsObject>,
        voteCount: number,
    }
}

export class GetDecisionRequest extends jspb.Message { 
    getArtifactId(): string;
    setArtifactId(value: string): GetDecisionRequest;
    getNegotiationRoomId(): string;
    setNegotiationRoomId(value: string): GetDecisionRequest;

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): GetDecisionRequest.AsObject;
    static toObject(includeInstance: boolean, msg: GetDecisionRequest): GetDecisionRequest.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: GetDecisionRequest, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): GetDecisionRequest;
    static deserializeBinaryFromReader(message: GetDecisionRequest, reader: jspb.BinaryReader): GetDecisionRequest;
}

export namespace GetDecisionRequest {
    export type AsObject = {
        artifactId: string,
        negotiationRoomId: string,
    }
}

export class GetDecisionResponse extends jspb.Message { 

    hasDecision(): boolean;
    clearDecision(): void;
    getDecision(): NegotiationDecision | undefined;
    setDecision(value?: NegotiationDecision): GetDecisionResponse;

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): GetDecisionResponse.AsObject;
    static toObject(includeInstance: boolean, msg: GetDecisionResponse): GetDecisionResponse.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: GetDecisionResponse, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): GetDecisionResponse;
    static deserializeBinaryFromReader(message: GetDecisionResponse, reader: jspb.BinaryReader): GetDecisionResponse;
}

export namespace GetDecisionResponse {
    export type AsObject = {
        decision?: NegotiationDecision.AsObject,
    }
}

export class WaitForDecisionRequest extends jspb.Message { 
    getArtifactId(): string;
    setArtifactId(value: string): WaitForDecisionRequest;
    getNegotiationRoomId(): string;
    setNegotiationRoomId(value: string): WaitForDecisionRequest;
    getTimeoutSeconds(): number;
    setTimeoutSeconds(value: number): WaitForDecisionRequest;

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): WaitForDecisionRequest.AsObject;
    static toObject(includeInstance: boolean, msg: WaitForDecisionRequest): WaitForDecisionRequest.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: WaitForDecisionRequest, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): WaitForDecisionRequest;
    static deserializeBinaryFromReader(message: WaitForDecisionRequest, reader: jspb.BinaryReader): WaitForDecisionRequest;
}

export namespace WaitForDecisionRequest {
    export type AsObject = {
        artifactId: string,
        negotiationRoomId: string,
        timeoutSeconds: number,
    }
}

export class WaitForDecisionResponse extends jspb.Message { 

    hasDecision(): boolean;
    clearDecision(): void;
    getDecision(): NegotiationDecision | undefined;
    setDecision(value?: NegotiationDecision): WaitForDecisionResponse;

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): WaitForDecisionResponse.AsObject;
    static toObject(includeInstance: boolean, msg: WaitForDecisionResponse): WaitForDecisionResponse.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: WaitForDecisionResponse, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): WaitForDecisionResponse;
    static deserializeBinaryFromReader(message: WaitForDecisionResponse, reader: jspb.BinaryReader): WaitForDecisionResponse;
}

export namespace WaitForDecisionResponse {
    export type AsObject = {
        decision?: NegotiationDecision.AsObject,
    }
}

export enum ArtifactType {
    ARTIFACT_TYPE_UNSPECIFIED = 0,
    REQUIREMENTS = 1,
    PLAN = 2,
    CODE = 3,
    DEPLOYMENT = 4,
}

export enum DecisionOutcome {
    DECISION_OUTCOME_UNSPECIFIED = 0,
    APPROVED = 1,
    REVISION_REQUESTED = 2,
    ESCALATED_TO_HITL = 3,
}
