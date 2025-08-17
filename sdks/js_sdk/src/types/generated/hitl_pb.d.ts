// package: sw4rm.hitl
// file: hitl.proto

/* tslint:disable */
/* eslint-disable */

import * as jspb from "google-protobuf";
import * as common_pb from "./common_pb";

export class HitlInvocation extends jspb.Message { 
    getReasonType(): common_pb.HitlReasonType;
    setReasonType(value: common_pb.HitlReasonType): HitlInvocation;
    getContext(): Uint8Array | string;
    getContext_asU8(): Uint8Array;
    getContext_asB64(): string;
    setContext(value: Uint8Array | string): HitlInvocation;
    clearProposedActionsList(): void;
    getProposedActionsList(): Array<string>;
    setProposedActionsList(value: Array<string>): HitlInvocation;
    addProposedActions(value: string, index?: number): string;
    getPriority(): number;
    setPriority(value: number): HitlInvocation;

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): HitlInvocation.AsObject;
    static toObject(includeInstance: boolean, msg: HitlInvocation): HitlInvocation.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: HitlInvocation, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): HitlInvocation;
    static deserializeBinaryFromReader(message: HitlInvocation, reader: jspb.BinaryReader): HitlInvocation;
}

export namespace HitlInvocation {
    export type AsObject = {
        reasonType: common_pb.HitlReasonType,
        context: Uint8Array | string,
        proposedActionsList: Array<string>,
        priority: number,
    }
}

export class HitlDecision extends jspb.Message { 
    getAction(): string;
    setAction(value: string): HitlDecision;
    getDecisionPayload(): Uint8Array | string;
    getDecisionPayload_asU8(): Uint8Array;
    getDecisionPayload_asB64(): string;
    setDecisionPayload(value: Uint8Array | string): HitlDecision;
    getRationale(): string;
    setRationale(value: string): HitlDecision;

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): HitlDecision.AsObject;
    static toObject(includeInstance: boolean, msg: HitlDecision): HitlDecision.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: HitlDecision, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): HitlDecision;
    static deserializeBinaryFromReader(message: HitlDecision, reader: jspb.BinaryReader): HitlDecision;
}

export namespace HitlDecision {
    export type AsObject = {
        action: string,
        decisionPayload: Uint8Array | string,
        rationale: string,
    }
}
