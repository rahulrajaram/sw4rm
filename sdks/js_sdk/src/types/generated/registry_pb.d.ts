// package: sw4rm.registry
// file: registry.proto

/* tslint:disable */
/* eslint-disable */

import * as jspb from "google-protobuf";
import * as google_protobuf_timestamp_pb from "google-protobuf/google/protobuf/timestamp_pb";
import * as common_pb from "./common_pb";

export class AgentDescriptor extends jspb.Message { 
    getAgentId(): string;
    setAgentId(value: string): AgentDescriptor;
    getName(): string;
    setName(value: string): AgentDescriptor;
    getDescription(): string;
    setDescription(value: string): AgentDescriptor;
    clearCapabilitiesList(): void;
    getCapabilitiesList(): Array<string>;
    setCapabilitiesList(value: Array<string>): AgentDescriptor;
    addCapabilities(value: string, index?: number): string;
    getCommunicationClass(): common_pb.CommunicationClass;
    setCommunicationClass(value: common_pb.CommunicationClass): AgentDescriptor;
    clearModalitiesSupportedList(): void;
    getModalitiesSupportedList(): Array<string>;
    setModalitiesSupportedList(value: Array<string>): AgentDescriptor;
    addModalitiesSupported(value: string, index?: number): string;
    clearReasoningConnectorsList(): void;
    getReasoningConnectorsList(): Array<string>;
    setReasoningConnectorsList(value: Array<string>): AgentDescriptor;
    addReasoningConnectors(value: string, index?: number): string;
    getPublicKey(): Uint8Array | string;
    getPublicKey_asU8(): Uint8Array;
    getPublicKey_asB64(): string;
    setPublicKey(value: Uint8Array | string): AgentDescriptor;
    getRegistrationType(): RegistrationType;
    setRegistrationType(value: RegistrationType): AgentDescriptor;
    getMaxConcurrentDelegations(): number;
    setMaxConcurrentDelegations(value: number): AgentDescriptor;

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): AgentDescriptor.AsObject;
    static toObject(includeInstance: boolean, msg: AgentDescriptor): AgentDescriptor.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: AgentDescriptor, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): AgentDescriptor;
    static deserializeBinaryFromReader(message: AgentDescriptor, reader: jspb.BinaryReader): AgentDescriptor;
}

export namespace AgentDescriptor {
    export type AsObject = {
        agentId: string,
        name: string,
        description: string,
        capabilitiesList: Array<string>,
        communicationClass: common_pb.CommunicationClass,
        modalitiesSupportedList: Array<string>,
        reasoningConnectorsList: Array<string>,
        publicKey: Uint8Array | string,
        registrationType: RegistrationType,
        maxConcurrentDelegations: number,
    }
}

export class RegisterAgentRequest extends jspb.Message { 

    hasAgent(): boolean;
    clearAgent(): void;
    getAgent(): AgentDescriptor | undefined;
    setAgent(value?: AgentDescriptor): RegisterAgentRequest;

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): RegisterAgentRequest.AsObject;
    static toObject(includeInstance: boolean, msg: RegisterAgentRequest): RegisterAgentRequest.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: RegisterAgentRequest, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): RegisterAgentRequest;
    static deserializeBinaryFromReader(message: RegisterAgentRequest, reader: jspb.BinaryReader): RegisterAgentRequest;
}

export namespace RegisterAgentRequest {
    export type AsObject = {
        agent?: AgentDescriptor.AsObject,
    }
}

export class RegisterAgentResponse extends jspb.Message { 
    getAccepted(): boolean;
    setAccepted(value: boolean): RegisterAgentResponse;
    getReason(): string;
    setReason(value: string): RegisterAgentResponse;

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): RegisterAgentResponse.AsObject;
    static toObject(includeInstance: boolean, msg: RegisterAgentResponse): RegisterAgentResponse.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: RegisterAgentResponse, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): RegisterAgentResponse;
    static deserializeBinaryFromReader(message: RegisterAgentResponse, reader: jspb.BinaryReader): RegisterAgentResponse;
}

export namespace RegisterAgentResponse {
    export type AsObject = {
        accepted: boolean,
        reason: string,
    }
}

export class HeartbeatRequest extends jspb.Message { 
    getAgentId(): string;
    setAgentId(value: string): HeartbeatRequest;
    getState(): common_pb.AgentState;
    setState(value: common_pb.AgentState): HeartbeatRequest;

    getHealthMap(): jspb.Map<string, string>;
    clearHealthMap(): void;

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): HeartbeatRequest.AsObject;
    static toObject(includeInstance: boolean, msg: HeartbeatRequest): HeartbeatRequest.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: HeartbeatRequest, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): HeartbeatRequest;
    static deserializeBinaryFromReader(message: HeartbeatRequest, reader: jspb.BinaryReader): HeartbeatRequest;
}

export namespace HeartbeatRequest {
    export type AsObject = {
        agentId: string,
        state: common_pb.AgentState,

        healthMap: Array<[string, string]>,
    }
}

export class HeartbeatResponse extends jspb.Message { 
    getOk(): boolean;
    setOk(value: boolean): HeartbeatResponse;

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): HeartbeatResponse.AsObject;
    static toObject(includeInstance: boolean, msg: HeartbeatResponse): HeartbeatResponse.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: HeartbeatResponse, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): HeartbeatResponse;
    static deserializeBinaryFromReader(message: HeartbeatResponse, reader: jspb.BinaryReader): HeartbeatResponse;
}

export namespace HeartbeatResponse {
    export type AsObject = {
        ok: boolean,
    }
}

export class DeregisterAgentRequest extends jspb.Message { 
    getAgentId(): string;
    setAgentId(value: string): DeregisterAgentRequest;
    getReason(): string;
    setReason(value: string): DeregisterAgentRequest;

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): DeregisterAgentRequest.AsObject;
    static toObject(includeInstance: boolean, msg: DeregisterAgentRequest): DeregisterAgentRequest.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: DeregisterAgentRequest, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): DeregisterAgentRequest;
    static deserializeBinaryFromReader(message: DeregisterAgentRequest, reader: jspb.BinaryReader): DeregisterAgentRequest;
}

export namespace DeregisterAgentRequest {
    export type AsObject = {
        agentId: string,
        reason: string,
    }
}

export class DeregisterAgentResponse extends jspb.Message { 
    getOk(): boolean;
    setOk(value: boolean): DeregisterAgentResponse;

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): DeregisterAgentResponse.AsObject;
    static toObject(includeInstance: boolean, msg: DeregisterAgentResponse): DeregisterAgentResponse.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: DeregisterAgentResponse, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): DeregisterAgentResponse;
    static deserializeBinaryFromReader(message: DeregisterAgentResponse, reader: jspb.BinaryReader): DeregisterAgentResponse;
}

export namespace DeregisterAgentResponse {
    export type AsObject = {
        ok: boolean,
    }
}

export enum RegistrationType {
    REGISTRATION_TYPE_UNSPECIFIED = 0,
    STANDARD_AGENT = 1,
    SWARM_GATEWAY = 2,
}
