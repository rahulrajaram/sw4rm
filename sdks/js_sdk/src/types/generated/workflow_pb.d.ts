// package: sw4rm.workflow
// file: workflow.proto

/* tslint:disable */
/* eslint-disable */

import * as jspb from "google-protobuf";
import * as google_protobuf_timestamp_pb from "google-protobuf/google/protobuf/timestamp_pb";

export class WorkflowNode extends jspb.Message { 
    getNodeId(): string;
    setNodeId(value: string): WorkflowNode;
    getAgentId(): string;
    setAgentId(value: string): WorkflowNode;
    clearDependenciesList(): void;
    getDependenciesList(): Array<string>;
    setDependenciesList(value: Array<string>): WorkflowNode;
    addDependencies(value: string, index?: number): string;
    getTriggerType(): TriggerType;
    setTriggerType(value: TriggerType): WorkflowNode;

    getInputMappingMap(): jspb.Map<string, string>;
    clearInputMappingMap(): void;

    getOutputMappingMap(): jspb.Map<string, string>;
    clearOutputMappingMap(): void;

    getMetadataMap(): jspb.Map<string, string>;
    clearMetadataMap(): void;

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): WorkflowNode.AsObject;
    static toObject(includeInstance: boolean, msg: WorkflowNode): WorkflowNode.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: WorkflowNode, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): WorkflowNode;
    static deserializeBinaryFromReader(message: WorkflowNode, reader: jspb.BinaryReader): WorkflowNode;
}

export namespace WorkflowNode {
    export type AsObject = {
        nodeId: string,
        agentId: string,
        dependenciesList: Array<string>,
        triggerType: TriggerType,

        inputMappingMap: Array<[string, string]>,

        outputMappingMap: Array<[string, string]>,

        metadataMap: Array<[string, string]>,
    }
}

export class WorkflowDefinition extends jspb.Message { 
    getWorkflowId(): string;
    setWorkflowId(value: string): WorkflowDefinition;

    getNodesMap(): jspb.Map<string, WorkflowNode>;
    clearNodesMap(): void;

    hasCreatedAt(): boolean;
    clearCreatedAt(): void;
    getCreatedAt(): google_protobuf_timestamp_pb.Timestamp | undefined;
    setCreatedAt(value?: google_protobuf_timestamp_pb.Timestamp): WorkflowDefinition;

    getMetadataMap(): jspb.Map<string, string>;
    clearMetadataMap(): void;

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): WorkflowDefinition.AsObject;
    static toObject(includeInstance: boolean, msg: WorkflowDefinition): WorkflowDefinition.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: WorkflowDefinition, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): WorkflowDefinition;
    static deserializeBinaryFromReader(message: WorkflowDefinition, reader: jspb.BinaryReader): WorkflowDefinition;
}

export namespace WorkflowDefinition {
    export type AsObject = {
        workflowId: string,

        nodesMap: Array<[string, WorkflowNode.AsObject]>,
        createdAt?: google_protobuf_timestamp_pb.Timestamp.AsObject,

        metadataMap: Array<[string, string]>,
    }
}

export class NodeState extends jspb.Message { 
    getNodeId(): string;
    setNodeId(value: string): NodeState;
    getStatus(): NodeStatus;
    setStatus(value: NodeStatus): NodeState;

    hasStartedAt(): boolean;
    clearStartedAt(): void;
    getStartedAt(): google_protobuf_timestamp_pb.Timestamp | undefined;
    setStartedAt(value?: google_protobuf_timestamp_pb.Timestamp): NodeState;

    hasCompletedAt(): boolean;
    clearCompletedAt(): void;
    getCompletedAt(): google_protobuf_timestamp_pb.Timestamp | undefined;
    setCompletedAt(value?: google_protobuf_timestamp_pb.Timestamp): NodeState;
    getOutput(): string;
    setOutput(value: string): NodeState;
    getError(): string;
    setError(value: string): NodeState;

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): NodeState.AsObject;
    static toObject(includeInstance: boolean, msg: NodeState): NodeState.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: NodeState, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): NodeState;
    static deserializeBinaryFromReader(message: NodeState, reader: jspb.BinaryReader): NodeState;
}

export namespace NodeState {
    export type AsObject = {
        nodeId: string,
        status: NodeStatus,
        startedAt?: google_protobuf_timestamp_pb.Timestamp.AsObject,
        completedAt?: google_protobuf_timestamp_pb.Timestamp.AsObject,
        output: string,
        error: string,
    }
}

export class WorkflowState extends jspb.Message { 
    getWorkflowId(): string;
    setWorkflowId(value: string): WorkflowState;

    getNodeStatesMap(): jspb.Map<string, NodeState>;
    clearNodeStatesMap(): void;
    getWorkflowData(): string;
    setWorkflowData(value: string): WorkflowState;

    hasStartedAt(): boolean;
    clearStartedAt(): void;
    getStartedAt(): google_protobuf_timestamp_pb.Timestamp | undefined;
    setStartedAt(value?: google_protobuf_timestamp_pb.Timestamp): WorkflowState;

    hasCompletedAt(): boolean;
    clearCompletedAt(): void;
    getCompletedAt(): google_protobuf_timestamp_pb.Timestamp | undefined;
    setCompletedAt(value?: google_protobuf_timestamp_pb.Timestamp): WorkflowState;

    getMetadataMap(): jspb.Map<string, string>;
    clearMetadataMap(): void;

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): WorkflowState.AsObject;
    static toObject(includeInstance: boolean, msg: WorkflowState): WorkflowState.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: WorkflowState, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): WorkflowState;
    static deserializeBinaryFromReader(message: WorkflowState, reader: jspb.BinaryReader): WorkflowState;
}

export namespace WorkflowState {
    export type AsObject = {
        workflowId: string,

        nodeStatesMap: Array<[string, NodeState.AsObject]>,
        workflowData: string,
        startedAt?: google_protobuf_timestamp_pb.Timestamp.AsObject,
        completedAt?: google_protobuf_timestamp_pb.Timestamp.AsObject,

        metadataMap: Array<[string, string]>,
    }
}

export class CreateWorkflowRequest extends jspb.Message { 

    hasDefinition(): boolean;
    clearDefinition(): void;
    getDefinition(): WorkflowDefinition | undefined;
    setDefinition(value?: WorkflowDefinition): CreateWorkflowRequest;

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): CreateWorkflowRequest.AsObject;
    static toObject(includeInstance: boolean, msg: CreateWorkflowRequest): CreateWorkflowRequest.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: CreateWorkflowRequest, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): CreateWorkflowRequest;
    static deserializeBinaryFromReader(message: CreateWorkflowRequest, reader: jspb.BinaryReader): CreateWorkflowRequest;
}

export namespace CreateWorkflowRequest {
    export type AsObject = {
        definition?: WorkflowDefinition.AsObject,
    }
}

export class CreateWorkflowResponse extends jspb.Message { 
    getWorkflowId(): string;
    setWorkflowId(value: string): CreateWorkflowResponse;
    getSuccess(): boolean;
    setSuccess(value: boolean): CreateWorkflowResponse;
    getError(): string;
    setError(value: string): CreateWorkflowResponse;

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): CreateWorkflowResponse.AsObject;
    static toObject(includeInstance: boolean, msg: CreateWorkflowResponse): CreateWorkflowResponse.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: CreateWorkflowResponse, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): CreateWorkflowResponse;
    static deserializeBinaryFromReader(message: CreateWorkflowResponse, reader: jspb.BinaryReader): CreateWorkflowResponse;
}

export namespace CreateWorkflowResponse {
    export type AsObject = {
        workflowId: string,
        success: boolean,
        error: string,
    }
}

export class StartWorkflowRequest extends jspb.Message { 
    getWorkflowId(): string;
    setWorkflowId(value: string): StartWorkflowRequest;
    getWorkflowData(): string;
    setWorkflowData(value: string): StartWorkflowRequest;

    getMetadataMap(): jspb.Map<string, string>;
    clearMetadataMap(): void;

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): StartWorkflowRequest.AsObject;
    static toObject(includeInstance: boolean, msg: StartWorkflowRequest): StartWorkflowRequest.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: StartWorkflowRequest, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): StartWorkflowRequest;
    static deserializeBinaryFromReader(message: StartWorkflowRequest, reader: jspb.BinaryReader): StartWorkflowRequest;
}

export namespace StartWorkflowRequest {
    export type AsObject = {
        workflowId: string,
        workflowData: string,

        metadataMap: Array<[string, string]>,
    }
}

export class StartWorkflowResponse extends jspb.Message { 
    getWorkflowId(): string;
    setWorkflowId(value: string): StartWorkflowResponse;

    hasState(): boolean;
    clearState(): void;
    getState(): WorkflowState | undefined;
    setState(value?: WorkflowState): StartWorkflowResponse;
    getSuccess(): boolean;
    setSuccess(value: boolean): StartWorkflowResponse;
    getError(): string;
    setError(value: string): StartWorkflowResponse;

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): StartWorkflowResponse.AsObject;
    static toObject(includeInstance: boolean, msg: StartWorkflowResponse): StartWorkflowResponse.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: StartWorkflowResponse, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): StartWorkflowResponse;
    static deserializeBinaryFromReader(message: StartWorkflowResponse, reader: jspb.BinaryReader): StartWorkflowResponse;
}

export namespace StartWorkflowResponse {
    export type AsObject = {
        workflowId: string,
        state?: WorkflowState.AsObject,
        success: boolean,
        error: string,
    }
}

export class GetWorkflowStateRequest extends jspb.Message { 
    getWorkflowId(): string;
    setWorkflowId(value: string): GetWorkflowStateRequest;

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): GetWorkflowStateRequest.AsObject;
    static toObject(includeInstance: boolean, msg: GetWorkflowStateRequest): GetWorkflowStateRequest.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: GetWorkflowStateRequest, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): GetWorkflowStateRequest;
    static deserializeBinaryFromReader(message: GetWorkflowStateRequest, reader: jspb.BinaryReader): GetWorkflowStateRequest;
}

export namespace GetWorkflowStateRequest {
    export type AsObject = {
        workflowId: string,
    }
}

export class GetWorkflowStateResponse extends jspb.Message { 

    hasState(): boolean;
    clearState(): void;
    getState(): WorkflowState | undefined;
    setState(value?: WorkflowState): GetWorkflowStateResponse;
    getSuccess(): boolean;
    setSuccess(value: boolean): GetWorkflowStateResponse;
    getError(): string;
    setError(value: string): GetWorkflowStateResponse;

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): GetWorkflowStateResponse.AsObject;
    static toObject(includeInstance: boolean, msg: GetWorkflowStateResponse): GetWorkflowStateResponse.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: GetWorkflowStateResponse, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): GetWorkflowStateResponse;
    static deserializeBinaryFromReader(message: GetWorkflowStateResponse, reader: jspb.BinaryReader): GetWorkflowStateResponse;
}

export namespace GetWorkflowStateResponse {
    export type AsObject = {
        state?: WorkflowState.AsObject,
        success: boolean,
        error: string,
    }
}

export class ResumeWorkflowRequest extends jspb.Message { 
    getWorkflowId(): string;
    setWorkflowId(value: string): ResumeWorkflowRequest;
    getNodeId(): string;
    setNodeId(value: string): ResumeWorkflowRequest;
    getWorkflowData(): string;
    setWorkflowData(value: string): ResumeWorkflowRequest;

    getMetadataMap(): jspb.Map<string, string>;
    clearMetadataMap(): void;

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): ResumeWorkflowRequest.AsObject;
    static toObject(includeInstance: boolean, msg: ResumeWorkflowRequest): ResumeWorkflowRequest.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: ResumeWorkflowRequest, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): ResumeWorkflowRequest;
    static deserializeBinaryFromReader(message: ResumeWorkflowRequest, reader: jspb.BinaryReader): ResumeWorkflowRequest;
}

export namespace ResumeWorkflowRequest {
    export type AsObject = {
        workflowId: string,
        nodeId: string,
        workflowData: string,

        metadataMap: Array<[string, string]>,
    }
}

export class ResumeWorkflowResponse extends jspb.Message { 
    getWorkflowId(): string;
    setWorkflowId(value: string): ResumeWorkflowResponse;

    hasState(): boolean;
    clearState(): void;
    getState(): WorkflowState | undefined;
    setState(value?: WorkflowState): ResumeWorkflowResponse;
    getSuccess(): boolean;
    setSuccess(value: boolean): ResumeWorkflowResponse;
    getError(): string;
    setError(value: string): ResumeWorkflowResponse;

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): ResumeWorkflowResponse.AsObject;
    static toObject(includeInstance: boolean, msg: ResumeWorkflowResponse): ResumeWorkflowResponse.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: ResumeWorkflowResponse, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): ResumeWorkflowResponse;
    static deserializeBinaryFromReader(message: ResumeWorkflowResponse, reader: jspb.BinaryReader): ResumeWorkflowResponse;
}

export namespace ResumeWorkflowResponse {
    export type AsObject = {
        workflowId: string,
        state?: WorkflowState.AsObject,
        success: boolean,
        error: string,
    }
}

export enum NodeStatus {
    NODE_STATUS_UNSPECIFIED = 0,
    PENDING = 1,
    READY = 2,
    RUNNING = 3,
    COMPLETED = 4,
    FAILED = 5,
    SKIPPED = 6,
}

export enum TriggerType {
    TRIGGER_TYPE_UNSPECIFIED = 0,
    EVENT = 1,
    SCHEDULE = 2,
    MANUAL = 3,
    DEPENDENCY = 4,
}
