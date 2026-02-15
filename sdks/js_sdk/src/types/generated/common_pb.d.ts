// package: sw4rm.common
// file: common.proto

/* tslint:disable */
/* eslint-disable */

import * as jspb from "google-protobuf";
import * as google_protobuf_timestamp_pb from "google-protobuf/google/protobuf/timestamp_pb";
import * as google_protobuf_duration_pb from "google-protobuf/google/protobuf/duration_pb";

export class Envelope extends jspb.Message { 
    getMessageId(): string;
    setMessageId(value: string): Envelope;
    getIdempotencyToken(): string;
    setIdempotencyToken(value: string): Envelope;
    getProducerId(): string;
    setProducerId(value: string): Envelope;
    getCorrelationId(): string;
    setCorrelationId(value: string): Envelope;
    getSequenceNumber(): number;
    setSequenceNumber(value: number): Envelope;
    getRetryCount(): number;
    setRetryCount(value: number): Envelope;
    getMessageType(): MessageType;
    setMessageType(value: MessageType): Envelope;
    getContentType(): string;
    setContentType(value: string): Envelope;
    getContentLength(): number;
    setContentLength(value: number): Envelope;
    getRepoId(): string;
    setRepoId(value: string): Envelope;
    getWorktreeId(): string;
    setWorktreeId(value: string): Envelope;
    getHlcTimestamp(): string;
    setHlcTimestamp(value: string): Envelope;
    getTtlMs(): number;
    setTtlMs(value: number): Envelope;

    hasTimestamp(): boolean;
    clearTimestamp(): void;
    getTimestamp(): google_protobuf_timestamp_pb.Timestamp | undefined;
    setTimestamp(value?: google_protobuf_timestamp_pb.Timestamp): Envelope;
    getPayload(): Uint8Array | string;
    getPayload_asU8(): Uint8Array;
    getPayload_asB64(): string;
    setPayload(value: Uint8Array | string): Envelope;
    getState(): EnvelopeState;
    setState(value: EnvelopeState): Envelope;
    getParentCorrelationId(): string;
    setParentCorrelationId(value: string): Envelope;

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): Envelope.AsObject;
    static toObject(includeInstance: boolean, msg: Envelope): Envelope.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: Envelope, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): Envelope;
    static deserializeBinaryFromReader(message: Envelope, reader: jspb.BinaryReader): Envelope;
}

export namespace Envelope {
    export type AsObject = {
        messageId: string,
        idempotencyToken: string,
        producerId: string,
        correlationId: string,
        sequenceNumber: number,
        retryCount: number,
        messageType: MessageType,
        contentType: string,
        contentLength: number,
        repoId: string,
        worktreeId: string,
        hlcTimestamp: string,
        ttlMs: number,
        timestamp?: google_protobuf_timestamp_pb.Timestamp.AsObject,
        payload: Uint8Array | string,
        state: EnvelopeState,
        parentCorrelationId: string,
    }
}

export class Ack extends jspb.Message { 
    getAckForMessageId(): string;
    setAckForMessageId(value: string): Ack;
    getAckStage(): AckStage;
    setAckStage(value: AckStage): Ack;
    getErrorCode(): ErrorCode;
    setErrorCode(value: ErrorCode): Ack;
    getNote(): string;
    setNote(value: string): Ack;

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): Ack.AsObject;
    static toObject(includeInstance: boolean, msg: Ack): Ack.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: Ack, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): Ack;
    static deserializeBinaryFromReader(message: Ack, reader: jspb.BinaryReader): Ack;
}

export namespace Ack {
    export type AsObject = {
        ackForMessageId: string,
        ackStage: AckStage,
        errorCode: ErrorCode,
        note: string,
    }
}

export class Empty extends jspb.Message { 

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): Empty.AsObject;
    static toObject(includeInstance: boolean, msg: Empty): Empty.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: Empty, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): Empty;
    static deserializeBinaryFromReader(message: Empty, reader: jspb.BinaryReader): Empty;
}

export namespace Empty {
    export type AsObject = {
    }
}

export enum MessageType {
    MESSAGE_TYPE_UNSPECIFIED = 0,
    CONTROL = 1,
    DATA = 2,
    HEARTBEAT = 3,
    NOTIFICATION = 4,
    ACKNOWLEDGEMENT = 5,
    HITL_INVOCATION = 6,
    WORKTREE_CONTROL = 7,
    NEGOTIATION = 8,
    TOOL_CALL = 9,
    TOOL_RESULT = 10,
    TOOL_ERROR = 11,
}

export enum AckStage {
    ACK_STAGE_UNSPECIFIED = 0,
    RECEIVED = 1,
    READ = 2,
    FULFILLED = 3,
    REJECTED = 4,
    FAILED = 5,
    TIMED_OUT = 6,
}

export enum ErrorCode {
    ERROR_CODE_UNSPECIFIED = 0,
    BUFFER_FULL = 1,
    NO_ROUTE = 2,
    ACK_TIMEOUT = 3,
    AGENT_UNAVAILABLE = 4,
    AGENT_SHUTDOWN = 5,
    VALIDATION_ERROR = 6,
    PERMISSION_DENIED = 7,
    UNSUPPORTED_MESSAGE_TYPE = 8,
    OVERSIZE_PAYLOAD = 9,
    TOOL_TIMEOUT = 10,
    PARTIAL_DELIVERY = 11,
    FORCED_PREEMPTION = 12,
    TTL_EXPIRED = 13,
    DUPLICATE_DETECTED = 14,
    ALREADY_IN_PROGRESS = 15,
    OVERLOADED = 16,
    REDIRECT = 20,
    INTERNAL_ERROR = 99,
}

export enum AgentState {
    AGENT_STATE_UNSPECIFIED = 0,
    INITIALIZING = 1,
    RUNNABLE = 2,
    SCHEDULED = 3,
    RUNNING = 4,
    WAITING = 5,
    WAITING_RESOURCES = 6,
    SUSPENDED = 7,
    RESUMED = 8,
    COMPLETED = 9,
    FAILED_STATE = 10,
    SHUTTING_DOWN = 11,
    RECOVERING = 12,
}

export enum CommunicationClass {
    COMM_CLASS_UNSPECIFIED = 0,
    PRIVILEGED = 1,
    STANDARD = 2,
    BULK = 3,
}

export enum DebateIntensity {
    DEBATE_INTENSITY_UNSPECIFIED = 0,
    LOWEST = 1,
    LOW = 2,
    MEDIUM = 3,
    HIGH = 4,
    HIGHEST = 5,
}

export enum HitlReasonType {
    HITL_REASON_UNSPECIFIED = 0,
    CONFLICT = 1,
    SECURITY_APPROVAL = 2,
    TASK_ESCALATION = 3,
    MANUAL_OVERRIDE = 4,
    WORKTREE_OVERRIDE = 5,
    DEBATE_DEADLOCK = 6,
    TOOL_PRIVILEGE_ESCALATION = 7,
    CONNECTOR_APPROVAL = 8,
}

export enum EnvelopeState {
    ENVELOPE_STATE_UNSPECIFIED = 0,
    ENVELOPE_STATE_SENT = 1,
    ENVELOPE_STATE_RECEIVED = 2,
    ENVELOPE_STATE_READ = 3,
    ENVELOPE_STATE_FULFILLED = 4,
    ENVELOPE_STATE_REJECTED = 5,
    ENVELOPE_STATE_FAILED = 6,
    ENVELOPE_STATE_TIMED_OUT = 7,
}
