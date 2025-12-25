// package: sw4rm.negotiation_room
// file: negotiation_room.proto

/* tslint:disable */
/* eslint-disable */

import * as grpc from "@grpc/grpc-js";
import * as negotiation_room_pb from "./negotiation_room_pb";
import * as google_protobuf_timestamp_pb from "google-protobuf/google/protobuf/timestamp_pb";

interface INegotiationRoomServiceService extends grpc.ServiceDefinition<grpc.UntypedServiceImplementation> {
    submitProposal: INegotiationRoomServiceService_ISubmitProposal;
    submitVote: INegotiationRoomServiceService_ISubmitVote;
    getVotes: INegotiationRoomServiceService_IGetVotes;
    getDecision: INegotiationRoomServiceService_IGetDecision;
    waitForDecision: INegotiationRoomServiceService_IWaitForDecision;
}

interface INegotiationRoomServiceService_ISubmitProposal extends grpc.MethodDefinition<negotiation_room_pb.SubmitProposalRequest, negotiation_room_pb.SubmitProposalResponse> {
    path: "/sw4rm.negotiation_room.NegotiationRoomService/SubmitProposal";
    requestStream: false;
    responseStream: false;
    requestSerialize: grpc.serialize<negotiation_room_pb.SubmitProposalRequest>;
    requestDeserialize: grpc.deserialize<negotiation_room_pb.SubmitProposalRequest>;
    responseSerialize: grpc.serialize<negotiation_room_pb.SubmitProposalResponse>;
    responseDeserialize: grpc.deserialize<negotiation_room_pb.SubmitProposalResponse>;
}
interface INegotiationRoomServiceService_ISubmitVote extends grpc.MethodDefinition<negotiation_room_pb.SubmitVoteRequest, negotiation_room_pb.SubmitVoteResponse> {
    path: "/sw4rm.negotiation_room.NegotiationRoomService/SubmitVote";
    requestStream: false;
    responseStream: false;
    requestSerialize: grpc.serialize<negotiation_room_pb.SubmitVoteRequest>;
    requestDeserialize: grpc.deserialize<negotiation_room_pb.SubmitVoteRequest>;
    responseSerialize: grpc.serialize<negotiation_room_pb.SubmitVoteResponse>;
    responseDeserialize: grpc.deserialize<negotiation_room_pb.SubmitVoteResponse>;
}
interface INegotiationRoomServiceService_IGetVotes extends grpc.MethodDefinition<negotiation_room_pb.GetVotesRequest, negotiation_room_pb.GetVotesResponse> {
    path: "/sw4rm.negotiation_room.NegotiationRoomService/GetVotes";
    requestStream: false;
    responseStream: false;
    requestSerialize: grpc.serialize<negotiation_room_pb.GetVotesRequest>;
    requestDeserialize: grpc.deserialize<negotiation_room_pb.GetVotesRequest>;
    responseSerialize: grpc.serialize<negotiation_room_pb.GetVotesResponse>;
    responseDeserialize: grpc.deserialize<negotiation_room_pb.GetVotesResponse>;
}
interface INegotiationRoomServiceService_IGetDecision extends grpc.MethodDefinition<negotiation_room_pb.GetDecisionRequest, negotiation_room_pb.GetDecisionResponse> {
    path: "/sw4rm.negotiation_room.NegotiationRoomService/GetDecision";
    requestStream: false;
    responseStream: false;
    requestSerialize: grpc.serialize<negotiation_room_pb.GetDecisionRequest>;
    requestDeserialize: grpc.deserialize<negotiation_room_pb.GetDecisionRequest>;
    responseSerialize: grpc.serialize<negotiation_room_pb.GetDecisionResponse>;
    responseDeserialize: grpc.deserialize<negotiation_room_pb.GetDecisionResponse>;
}
interface INegotiationRoomServiceService_IWaitForDecision extends grpc.MethodDefinition<negotiation_room_pb.WaitForDecisionRequest, negotiation_room_pb.WaitForDecisionResponse> {
    path: "/sw4rm.negotiation_room.NegotiationRoomService/WaitForDecision";
    requestStream: false;
    responseStream: false;
    requestSerialize: grpc.serialize<negotiation_room_pb.WaitForDecisionRequest>;
    requestDeserialize: grpc.deserialize<negotiation_room_pb.WaitForDecisionRequest>;
    responseSerialize: grpc.serialize<negotiation_room_pb.WaitForDecisionResponse>;
    responseDeserialize: grpc.deserialize<negotiation_room_pb.WaitForDecisionResponse>;
}

export const NegotiationRoomServiceService: INegotiationRoomServiceService;

export interface INegotiationRoomServiceServer extends grpc.UntypedServiceImplementation {
    submitProposal: grpc.handleUnaryCall<negotiation_room_pb.SubmitProposalRequest, negotiation_room_pb.SubmitProposalResponse>;
    submitVote: grpc.handleUnaryCall<negotiation_room_pb.SubmitVoteRequest, negotiation_room_pb.SubmitVoteResponse>;
    getVotes: grpc.handleUnaryCall<negotiation_room_pb.GetVotesRequest, negotiation_room_pb.GetVotesResponse>;
    getDecision: grpc.handleUnaryCall<negotiation_room_pb.GetDecisionRequest, negotiation_room_pb.GetDecisionResponse>;
    waitForDecision: grpc.handleUnaryCall<negotiation_room_pb.WaitForDecisionRequest, negotiation_room_pb.WaitForDecisionResponse>;
}

export interface INegotiationRoomServiceClient {
    submitProposal(request: negotiation_room_pb.SubmitProposalRequest, callback: (error: grpc.ServiceError | null, response: negotiation_room_pb.SubmitProposalResponse) => void): grpc.ClientUnaryCall;
    submitProposal(request: negotiation_room_pb.SubmitProposalRequest, metadata: grpc.Metadata, callback: (error: grpc.ServiceError | null, response: negotiation_room_pb.SubmitProposalResponse) => void): grpc.ClientUnaryCall;
    submitProposal(request: negotiation_room_pb.SubmitProposalRequest, metadata: grpc.Metadata, options: Partial<grpc.CallOptions>, callback: (error: grpc.ServiceError | null, response: negotiation_room_pb.SubmitProposalResponse) => void): grpc.ClientUnaryCall;
    submitVote(request: negotiation_room_pb.SubmitVoteRequest, callback: (error: grpc.ServiceError | null, response: negotiation_room_pb.SubmitVoteResponse) => void): grpc.ClientUnaryCall;
    submitVote(request: negotiation_room_pb.SubmitVoteRequest, metadata: grpc.Metadata, callback: (error: grpc.ServiceError | null, response: negotiation_room_pb.SubmitVoteResponse) => void): grpc.ClientUnaryCall;
    submitVote(request: negotiation_room_pb.SubmitVoteRequest, metadata: grpc.Metadata, options: Partial<grpc.CallOptions>, callback: (error: grpc.ServiceError | null, response: negotiation_room_pb.SubmitVoteResponse) => void): grpc.ClientUnaryCall;
    getVotes(request: negotiation_room_pb.GetVotesRequest, callback: (error: grpc.ServiceError | null, response: negotiation_room_pb.GetVotesResponse) => void): grpc.ClientUnaryCall;
    getVotes(request: negotiation_room_pb.GetVotesRequest, metadata: grpc.Metadata, callback: (error: grpc.ServiceError | null, response: negotiation_room_pb.GetVotesResponse) => void): grpc.ClientUnaryCall;
    getVotes(request: negotiation_room_pb.GetVotesRequest, metadata: grpc.Metadata, options: Partial<grpc.CallOptions>, callback: (error: grpc.ServiceError | null, response: negotiation_room_pb.GetVotesResponse) => void): grpc.ClientUnaryCall;
    getDecision(request: negotiation_room_pb.GetDecisionRequest, callback: (error: grpc.ServiceError | null, response: negotiation_room_pb.GetDecisionResponse) => void): grpc.ClientUnaryCall;
    getDecision(request: negotiation_room_pb.GetDecisionRequest, metadata: grpc.Metadata, callback: (error: grpc.ServiceError | null, response: negotiation_room_pb.GetDecisionResponse) => void): grpc.ClientUnaryCall;
    getDecision(request: negotiation_room_pb.GetDecisionRequest, metadata: grpc.Metadata, options: Partial<grpc.CallOptions>, callback: (error: grpc.ServiceError | null, response: negotiation_room_pb.GetDecisionResponse) => void): grpc.ClientUnaryCall;
    waitForDecision(request: negotiation_room_pb.WaitForDecisionRequest, callback: (error: grpc.ServiceError | null, response: negotiation_room_pb.WaitForDecisionResponse) => void): grpc.ClientUnaryCall;
    waitForDecision(request: negotiation_room_pb.WaitForDecisionRequest, metadata: grpc.Metadata, callback: (error: grpc.ServiceError | null, response: negotiation_room_pb.WaitForDecisionResponse) => void): grpc.ClientUnaryCall;
    waitForDecision(request: negotiation_room_pb.WaitForDecisionRequest, metadata: grpc.Metadata, options: Partial<grpc.CallOptions>, callback: (error: grpc.ServiceError | null, response: negotiation_room_pb.WaitForDecisionResponse) => void): grpc.ClientUnaryCall;
}

export class NegotiationRoomServiceClient extends grpc.Client implements INegotiationRoomServiceClient {
    constructor(address: string, credentials: grpc.ChannelCredentials, options?: Partial<grpc.ClientOptions>);
    public submitProposal(request: negotiation_room_pb.SubmitProposalRequest, callback: (error: grpc.ServiceError | null, response: negotiation_room_pb.SubmitProposalResponse) => void): grpc.ClientUnaryCall;
    public submitProposal(request: negotiation_room_pb.SubmitProposalRequest, metadata: grpc.Metadata, callback: (error: grpc.ServiceError | null, response: negotiation_room_pb.SubmitProposalResponse) => void): grpc.ClientUnaryCall;
    public submitProposal(request: negotiation_room_pb.SubmitProposalRequest, metadata: grpc.Metadata, options: Partial<grpc.CallOptions>, callback: (error: grpc.ServiceError | null, response: negotiation_room_pb.SubmitProposalResponse) => void): grpc.ClientUnaryCall;
    public submitVote(request: negotiation_room_pb.SubmitVoteRequest, callback: (error: grpc.ServiceError | null, response: negotiation_room_pb.SubmitVoteResponse) => void): grpc.ClientUnaryCall;
    public submitVote(request: negotiation_room_pb.SubmitVoteRequest, metadata: grpc.Metadata, callback: (error: grpc.ServiceError | null, response: negotiation_room_pb.SubmitVoteResponse) => void): grpc.ClientUnaryCall;
    public submitVote(request: negotiation_room_pb.SubmitVoteRequest, metadata: grpc.Metadata, options: Partial<grpc.CallOptions>, callback: (error: grpc.ServiceError | null, response: negotiation_room_pb.SubmitVoteResponse) => void): grpc.ClientUnaryCall;
    public getVotes(request: negotiation_room_pb.GetVotesRequest, callback: (error: grpc.ServiceError | null, response: negotiation_room_pb.GetVotesResponse) => void): grpc.ClientUnaryCall;
    public getVotes(request: negotiation_room_pb.GetVotesRequest, metadata: grpc.Metadata, callback: (error: grpc.ServiceError | null, response: negotiation_room_pb.GetVotesResponse) => void): grpc.ClientUnaryCall;
    public getVotes(request: negotiation_room_pb.GetVotesRequest, metadata: grpc.Metadata, options: Partial<grpc.CallOptions>, callback: (error: grpc.ServiceError | null, response: negotiation_room_pb.GetVotesResponse) => void): grpc.ClientUnaryCall;
    public getDecision(request: negotiation_room_pb.GetDecisionRequest, callback: (error: grpc.ServiceError | null, response: negotiation_room_pb.GetDecisionResponse) => void): grpc.ClientUnaryCall;
    public getDecision(request: negotiation_room_pb.GetDecisionRequest, metadata: grpc.Metadata, callback: (error: grpc.ServiceError | null, response: negotiation_room_pb.GetDecisionResponse) => void): grpc.ClientUnaryCall;
    public getDecision(request: negotiation_room_pb.GetDecisionRequest, metadata: grpc.Metadata, options: Partial<grpc.CallOptions>, callback: (error: grpc.ServiceError | null, response: negotiation_room_pb.GetDecisionResponse) => void): grpc.ClientUnaryCall;
    public waitForDecision(request: negotiation_room_pb.WaitForDecisionRequest, callback: (error: grpc.ServiceError | null, response: negotiation_room_pb.WaitForDecisionResponse) => void): grpc.ClientUnaryCall;
    public waitForDecision(request: negotiation_room_pb.WaitForDecisionRequest, metadata: grpc.Metadata, callback: (error: grpc.ServiceError | null, response: negotiation_room_pb.WaitForDecisionResponse) => void): grpc.ClientUnaryCall;
    public waitForDecision(request: negotiation_room_pb.WaitForDecisionRequest, metadata: grpc.Metadata, options: Partial<grpc.CallOptions>, callback: (error: grpc.ServiceError | null, response: negotiation_room_pb.WaitForDecisionResponse) => void): grpc.ClientUnaryCall;
}
