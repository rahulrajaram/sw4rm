// package: sw4rm.router
// file: router.proto

/* tslint:disable */
/* eslint-disable */

import * as jspb from "google-protobuf";
import * as common_pb from "./common_pb";

export class SendMessageRequest extends jspb.Message { 

    hasMsg(): boolean;
    clearMsg(): void;
    getMsg(): common_pb.Envelope | undefined;
    setMsg(value?: common_pb.Envelope): SendMessageRequest;

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): SendMessageRequest.AsObject;
    static toObject(includeInstance: boolean, msg: SendMessageRequest): SendMessageRequest.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: SendMessageRequest, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): SendMessageRequest;
    static deserializeBinaryFromReader(message: SendMessageRequest, reader: jspb.BinaryReader): SendMessageRequest;
}

export namespace SendMessageRequest {
    export type AsObject = {
        msg?: common_pb.Envelope.AsObject,
    }
}

export class SendMessageResponse extends jspb.Message { 
    getAccepted(): boolean;
    setAccepted(value: boolean): SendMessageResponse;
    getReason(): string;
    setReason(value: string): SendMessageResponse;

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): SendMessageResponse.AsObject;
    static toObject(includeInstance: boolean, msg: SendMessageResponse): SendMessageResponse.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: SendMessageResponse, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): SendMessageResponse;
    static deserializeBinaryFromReader(message: SendMessageResponse, reader: jspb.BinaryReader): SendMessageResponse;
}

export namespace SendMessageResponse {
    export type AsObject = {
        accepted: boolean,
        reason: string,
    }
}

export class StreamRequest extends jspb.Message { 
    getAgentId(): string;
    setAgentId(value: string): StreamRequest;

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): StreamRequest.AsObject;
    static toObject(includeInstance: boolean, msg: StreamRequest): StreamRequest.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: StreamRequest, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): StreamRequest;
    static deserializeBinaryFromReader(message: StreamRequest, reader: jspb.BinaryReader): StreamRequest;
}

export namespace StreamRequest {
    export type AsObject = {
        agentId: string,
    }
}

export class StreamItem extends jspb.Message { 

    hasMsg(): boolean;
    clearMsg(): void;
    getMsg(): common_pb.Envelope | undefined;
    setMsg(value?: common_pb.Envelope): StreamItem;

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): StreamItem.AsObject;
    static toObject(includeInstance: boolean, msg: StreamItem): StreamItem.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: StreamItem, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): StreamItem;
    static deserializeBinaryFromReader(message: StreamItem, reader: jspb.BinaryReader): StreamItem;
}

export namespace StreamItem {
    export type AsObject = {
        msg?: common_pb.Envelope.AsObject,
    }
}
