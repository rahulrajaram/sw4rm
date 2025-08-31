// package: sw4rm.scheduler
// file: scheduler_policy.proto

/* tslint:disable */
/* eslint-disable */

import * as jspb from "google-protobuf";
import * as policy_pb from "./policy_pb";

export class SetNegotiationPolicyRequest extends jspb.Message { 

    hasPolicy(): boolean;
    clearPolicy(): void;
    getPolicy(): policy_pb.NegotiationPolicy | undefined;
    setPolicy(value?: policy_pb.NegotiationPolicy): SetNegotiationPolicyRequest;

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): SetNegotiationPolicyRequest.AsObject;
    static toObject(includeInstance: boolean, msg: SetNegotiationPolicyRequest): SetNegotiationPolicyRequest.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: SetNegotiationPolicyRequest, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): SetNegotiationPolicyRequest;
    static deserializeBinaryFromReader(message: SetNegotiationPolicyRequest, reader: jspb.BinaryReader): SetNegotiationPolicyRequest;
}

export namespace SetNegotiationPolicyRequest {
    export type AsObject = {
        policy?: policy_pb.NegotiationPolicy.AsObject,
    }
}

export class SetNegotiationPolicyResponse extends jspb.Message { 
    getOk(): boolean;
    setOk(value: boolean): SetNegotiationPolicyResponse;
    getReason(): string;
    setReason(value: string): SetNegotiationPolicyResponse;

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): SetNegotiationPolicyResponse.AsObject;
    static toObject(includeInstance: boolean, msg: SetNegotiationPolicyResponse): SetNegotiationPolicyResponse.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: SetNegotiationPolicyResponse, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): SetNegotiationPolicyResponse;
    static deserializeBinaryFromReader(message: SetNegotiationPolicyResponse, reader: jspb.BinaryReader): SetNegotiationPolicyResponse;
}

export namespace SetNegotiationPolicyResponse {
    export type AsObject = {
        ok: boolean,
        reason: string,
    }
}

export class GetNegotiationPolicyRequest extends jspb.Message { 

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): GetNegotiationPolicyRequest.AsObject;
    static toObject(includeInstance: boolean, msg: GetNegotiationPolicyRequest): GetNegotiationPolicyRequest.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: GetNegotiationPolicyRequest, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): GetNegotiationPolicyRequest;
    static deserializeBinaryFromReader(message: GetNegotiationPolicyRequest, reader: jspb.BinaryReader): GetNegotiationPolicyRequest;
}

export namespace GetNegotiationPolicyRequest {
    export type AsObject = {
    }
}

export class GetNegotiationPolicyResponse extends jspb.Message { 

    hasPolicy(): boolean;
    clearPolicy(): void;
    getPolicy(): policy_pb.NegotiationPolicy | undefined;
    setPolicy(value?: policy_pb.NegotiationPolicy): GetNegotiationPolicyResponse;

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): GetNegotiationPolicyResponse.AsObject;
    static toObject(includeInstance: boolean, msg: GetNegotiationPolicyResponse): GetNegotiationPolicyResponse.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: GetNegotiationPolicyResponse, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): GetNegotiationPolicyResponse;
    static deserializeBinaryFromReader(message: GetNegotiationPolicyResponse, reader: jspb.BinaryReader): GetNegotiationPolicyResponse;
}

export namespace GetNegotiationPolicyResponse {
    export type AsObject = {
        policy?: policy_pb.NegotiationPolicy.AsObject,
    }
}

export class SetPolicyProfilesRequest extends jspb.Message { 
    clearProfilesList(): void;
    getProfilesList(): Array<policy_pb.PolicyProfile>;
    setProfilesList(value: Array<policy_pb.PolicyProfile>): SetPolicyProfilesRequest;
    addProfiles(value?: policy_pb.PolicyProfile, index?: number): policy_pb.PolicyProfile;

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): SetPolicyProfilesRequest.AsObject;
    static toObject(includeInstance: boolean, msg: SetPolicyProfilesRequest): SetPolicyProfilesRequest.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: SetPolicyProfilesRequest, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): SetPolicyProfilesRequest;
    static deserializeBinaryFromReader(message: SetPolicyProfilesRequest, reader: jspb.BinaryReader): SetPolicyProfilesRequest;
}

export namespace SetPolicyProfilesRequest {
    export type AsObject = {
        profilesList: Array<policy_pb.PolicyProfile.AsObject>,
    }
}

export class SetPolicyProfilesResponse extends jspb.Message { 
    getOk(): boolean;
    setOk(value: boolean): SetPolicyProfilesResponse;
    getReason(): string;
    setReason(value: string): SetPolicyProfilesResponse;

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): SetPolicyProfilesResponse.AsObject;
    static toObject(includeInstance: boolean, msg: SetPolicyProfilesResponse): SetPolicyProfilesResponse.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: SetPolicyProfilesResponse, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): SetPolicyProfilesResponse;
    static deserializeBinaryFromReader(message: SetPolicyProfilesResponse, reader: jspb.BinaryReader): SetPolicyProfilesResponse;
}

export namespace SetPolicyProfilesResponse {
    export type AsObject = {
        ok: boolean,
        reason: string,
    }
}

export class ListPolicyProfilesRequest extends jspb.Message { 

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): ListPolicyProfilesRequest.AsObject;
    static toObject(includeInstance: boolean, msg: ListPolicyProfilesRequest): ListPolicyProfilesRequest.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: ListPolicyProfilesRequest, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): ListPolicyProfilesRequest;
    static deserializeBinaryFromReader(message: ListPolicyProfilesRequest, reader: jspb.BinaryReader): ListPolicyProfilesRequest;
}

export namespace ListPolicyProfilesRequest {
    export type AsObject = {
    }
}

export class ListPolicyProfilesResponse extends jspb.Message { 
    clearProfilesList(): void;
    getProfilesList(): Array<policy_pb.PolicyProfile>;
    setProfilesList(value: Array<policy_pb.PolicyProfile>): ListPolicyProfilesResponse;
    addProfiles(value?: policy_pb.PolicyProfile, index?: number): policy_pb.PolicyProfile;

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): ListPolicyProfilesResponse.AsObject;
    static toObject(includeInstance: boolean, msg: ListPolicyProfilesResponse): ListPolicyProfilesResponse.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: ListPolicyProfilesResponse, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): ListPolicyProfilesResponse;
    static deserializeBinaryFromReader(message: ListPolicyProfilesResponse, reader: jspb.BinaryReader): ListPolicyProfilesResponse;
}

export namespace ListPolicyProfilesResponse {
    export type AsObject = {
        profilesList: Array<policy_pb.PolicyProfile.AsObject>,
    }
}

export class GetEffectivePolicyRequest extends jspb.Message { 
    getNegotiationId(): string;
    setNegotiationId(value: string): GetEffectivePolicyRequest;

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): GetEffectivePolicyRequest.AsObject;
    static toObject(includeInstance: boolean, msg: GetEffectivePolicyRequest): GetEffectivePolicyRequest.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: GetEffectivePolicyRequest, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): GetEffectivePolicyRequest;
    static deserializeBinaryFromReader(message: GetEffectivePolicyRequest, reader: jspb.BinaryReader): GetEffectivePolicyRequest;
}

export namespace GetEffectivePolicyRequest {
    export type AsObject = {
        negotiationId: string,
    }
}

export class GetEffectivePolicyResponse extends jspb.Message { 

    hasEffective(): boolean;
    clearEffective(): void;
    getEffective(): policy_pb.EffectivePolicy | undefined;
    setEffective(value?: policy_pb.EffectivePolicy): GetEffectivePolicyResponse;

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): GetEffectivePolicyResponse.AsObject;
    static toObject(includeInstance: boolean, msg: GetEffectivePolicyResponse): GetEffectivePolicyResponse.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: GetEffectivePolicyResponse, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): GetEffectivePolicyResponse;
    static deserializeBinaryFromReader(message: GetEffectivePolicyResponse, reader: jspb.BinaryReader): GetEffectivePolicyResponse;
}

export namespace GetEffectivePolicyResponse {
    export type AsObject = {
        effective?: policy_pb.EffectivePolicy.AsObject,
    }
}

export class SubmitEvaluationRequest extends jspb.Message { 
    getNegotiationId(): string;
    setNegotiationId(value: string): SubmitEvaluationRequest;

    hasReport(): boolean;
    clearReport(): void;
    getReport(): policy_pb.EvaluationReport | undefined;
    setReport(value?: policy_pb.EvaluationReport): SubmitEvaluationRequest;

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): SubmitEvaluationRequest.AsObject;
    static toObject(includeInstance: boolean, msg: SubmitEvaluationRequest): SubmitEvaluationRequest.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: SubmitEvaluationRequest, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): SubmitEvaluationRequest;
    static deserializeBinaryFromReader(message: SubmitEvaluationRequest, reader: jspb.BinaryReader): SubmitEvaluationRequest;
}

export namespace SubmitEvaluationRequest {
    export type AsObject = {
        negotiationId: string,
        report?: policy_pb.EvaluationReport.AsObject,
    }
}

export class SubmitEvaluationResponse extends jspb.Message { 
    getAccepted(): boolean;
    setAccepted(value: boolean): SubmitEvaluationResponse;
    getReason(): string;
    setReason(value: string): SubmitEvaluationResponse;

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): SubmitEvaluationResponse.AsObject;
    static toObject(includeInstance: boolean, msg: SubmitEvaluationResponse): SubmitEvaluationResponse.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: SubmitEvaluationResponse, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): SubmitEvaluationResponse;
    static deserializeBinaryFromReader(message: SubmitEvaluationResponse, reader: jspb.BinaryReader): SubmitEvaluationResponse;
}

export namespace SubmitEvaluationResponse {
    export type AsObject = {
        accepted: boolean,
        reason: string,
    }
}

export class HitlActionRequest extends jspb.Message { 
    getNegotiationId(): string;
    setNegotiationId(value: string): HitlActionRequest;
    getAction(): string;
    setAction(value: string): HitlActionRequest;
    getRationale(): string;
    setRationale(value: string): HitlActionRequest;

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): HitlActionRequest.AsObject;
    static toObject(includeInstance: boolean, msg: HitlActionRequest): HitlActionRequest.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: HitlActionRequest, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): HitlActionRequest;
    static deserializeBinaryFromReader(message: HitlActionRequest, reader: jspb.BinaryReader): HitlActionRequest;
}

export namespace HitlActionRequest {
    export type AsObject = {
        negotiationId: string,
        action: string,
        rationale: string,
    }
}

export class HitlActionResponse extends jspb.Message { 
    getOk(): boolean;
    setOk(value: boolean): HitlActionResponse;
    getReason(): string;
    setReason(value: string): HitlActionResponse;

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): HitlActionResponse.AsObject;
    static toObject(includeInstance: boolean, msg: HitlActionResponse): HitlActionResponse.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: HitlActionResponse, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): HitlActionResponse;
    static deserializeBinaryFromReader(message: HitlActionResponse, reader: jspb.BinaryReader): HitlActionResponse;
}

export namespace HitlActionResponse {
    export type AsObject = {
        ok: boolean,
        reason: string,
    }
}
