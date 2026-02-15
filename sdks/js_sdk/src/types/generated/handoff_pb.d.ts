// package: sw4rm.handoff
// file: handoff.proto

/* tslint:disable */
/* eslint-disable */

import * as jspb from "google-protobuf";
import * as common_pb from "./common_pb";
import * as google_protobuf_duration_pb from "google-protobuf/google/protobuf/duration_pb";

export class BudgetEnvelope extends jspb.Message { 
    getTokenBudgetRemaining(): number;
    setTokenBudgetRemaining(value: number): BudgetEnvelope;
    getWallTimeRemainingMs(): number;
    setWallTimeRemainingMs(value: number): BudgetEnvelope;
    getDeadlineEpochMs(): number;
    setDeadlineEpochMs(value: number): BudgetEnvelope;
    getCurrentDepth(): number;
    setCurrentDepth(value: number): BudgetEnvelope;
    getMaxDelegationDepth(): number;
    setMaxDelegationDepth(value: number): BudgetEnvelope;

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): BudgetEnvelope.AsObject;
    static toObject(includeInstance: boolean, msg: BudgetEnvelope): BudgetEnvelope.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: BudgetEnvelope, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): BudgetEnvelope;
    static deserializeBinaryFromReader(message: BudgetEnvelope, reader: jspb.BinaryReader): BudgetEnvelope;
}

export namespace BudgetEnvelope {
    export type AsObject = {
        tokenBudgetRemaining: number,
        wallTimeRemainingMs: number,
        deadlineEpochMs: number,
        currentDepth: number,
        maxDelegationDepth: number,
    }
}

export class SwarmDelegationPolicy extends jspb.Message { 
    getMaxRetriesOnOverloaded(): number;
    setMaxRetriesOnOverloaded(value: number): SwarmDelegationPolicy;
    getInitialBackoffMs(): number;
    setInitialBackoffMs(value: number): SwarmDelegationPolicy;
    getBackoffMultiplier(): number;
    setBackoffMultiplier(value: number): SwarmDelegationPolicy;
    getMaxBackoffMs(): number;
    setMaxBackoffMs(value: number): SwarmDelegationPolicy;
    getAllowSpilloverRouting(): boolean;
    setAllowSpilloverRouting(value: boolean): SwarmDelegationPolicy;
    getMaxRedirects(): number;
    setMaxRedirects(value: number): SwarmDelegationPolicy;

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): SwarmDelegationPolicy.AsObject;
    static toObject(includeInstance: boolean, msg: SwarmDelegationPolicy): SwarmDelegationPolicy.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: SwarmDelegationPolicy, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): SwarmDelegationPolicy;
    static deserializeBinaryFromReader(message: SwarmDelegationPolicy, reader: jspb.BinaryReader): SwarmDelegationPolicy;
}

export namespace SwarmDelegationPolicy {
    export type AsObject = {
        maxRetriesOnOverloaded: number,
        initialBackoffMs: number,
        backoffMultiplier: number,
        maxBackoffMs: number,
        allowSpilloverRouting: boolean,
        maxRedirects: number,
    }
}

export class CancelDelegation extends jspb.Message { 
    getCorrelationId(): string;
    setCorrelationId(value: string): CancelDelegation;
    getReason(): string;
    setReason(value: string): CancelDelegation;
    getGracePeriodMs(): number;
    setGracePeriodMs(value: number): CancelDelegation;

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): CancelDelegation.AsObject;
    static toObject(includeInstance: boolean, msg: CancelDelegation): CancelDelegation.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: CancelDelegation, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): CancelDelegation;
    static deserializeBinaryFromReader(message: CancelDelegation, reader: jspb.BinaryReader): CancelDelegation;
}

export namespace CancelDelegation {
    export type AsObject = {
        correlationId: string,
        reason: string,
        gracePeriodMs: number,
    }
}

export class CancelDelegationResponse extends jspb.Message { 
    getAcknowledged(): boolean;
    setAcknowledged(value: boolean): CancelDelegationResponse;
    getMessage(): string;
    setMessage(value: string): CancelDelegationResponse;

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): CancelDelegationResponse.AsObject;
    static toObject(includeInstance: boolean, msg: CancelDelegationResponse): CancelDelegationResponse.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: CancelDelegationResponse, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): CancelDelegationResponse;
    static deserializeBinaryFromReader(message: CancelDelegationResponse, reader: jspb.BinaryReader): CancelDelegationResponse;
}

export namespace CancelDelegationResponse {
    export type AsObject = {
        acknowledged: boolean,
        message: string,
    }
}

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

    hasBudget(): boolean;
    clearBudget(): void;
    getBudget(): BudgetEnvelope | undefined;
    setBudget(value?: BudgetEnvelope): HandoffRequest;

    hasDelegationPolicy(): boolean;
    clearDelegationPolicy(): void;
    getDelegationPolicy(): SwarmDelegationPolicy | undefined;
    setDelegationPolicy(value?: SwarmDelegationPolicy): HandoffRequest;

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
        budget?: BudgetEnvelope.AsObject,
        delegationPolicy?: SwarmDelegationPolicy.AsObject,
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
    getRejectionCode(): common_pb.ErrorCode;
    setRejectionCode(value: common_pb.ErrorCode): HandoffResponse;
    getRetryAfterMs(): number;
    setRetryAfterMs(value: number): HandoffResponse;
    getRedirectToAgentId(): string;
    setRedirectToAgentId(value: string): HandoffResponse;

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
        rejectionCode: common_pb.ErrorCode,
        retryAfterMs: number,
        redirectToAgentId: string,
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
