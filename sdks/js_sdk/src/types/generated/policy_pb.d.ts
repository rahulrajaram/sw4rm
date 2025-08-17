// package: sw4rm.policy
// file: policy.proto

/* tslint:disable */
/* eslint-disable */

import * as jspb from "google-protobuf";

export class WagglePolicy extends jspb.Message { 
    getMaxRounds(): number;
    setMaxRounds(value: number): WagglePolicy;
    getScoreThreshold(): number;
    setScoreThreshold(value: number): WagglePolicy;
    getDiffTolerance(): number;
    setDiffTolerance(value: number): WagglePolicy;
    getRoundTimeoutMs(): number;
    setRoundTimeoutMs(value: number): WagglePolicy;
    getTokenBudgetPerRound(): number;
    setTokenBudgetPerRound(value: number): WagglePolicy;
    getTotalTokenBudget(): number;
    setTotalTokenBudget(value: number): WagglePolicy;
    getOscillationLimit(): number;
    setOscillationLimit(value: number): WagglePolicy;

    hasHitl(): boolean;
    clearHitl(): void;
    getHitl(): WagglePolicy.Hitl | undefined;
    setHitl(value?: WagglePolicy.Hitl): WagglePolicy;

    hasScoring(): boolean;
    clearScoring(): void;
    getScoring(): WagglePolicy.Scoring | undefined;
    setScoring(value?: WagglePolicy.Scoring): WagglePolicy;

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): WagglePolicy.AsObject;
    static toObject(includeInstance: boolean, msg: WagglePolicy): WagglePolicy.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: WagglePolicy, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): WagglePolicy;
    static deserializeBinaryFromReader(message: WagglePolicy, reader: jspb.BinaryReader): WagglePolicy;
}

export namespace WagglePolicy {
    export type AsObject = {
        maxRounds: number,
        scoreThreshold: number,
        diffTolerance: number,
        roundTimeoutMs: number,
        tokenBudgetPerRound: number,
        totalTokenBudget: number,
        oscillationLimit: number,
        hitl?: WagglePolicy.Hitl.AsObject,
        scoring?: WagglePolicy.Scoring.AsObject,
    }


    export class Hitl extends jspb.Message { 
        getMode(): string;
        setMode(value: string): Hitl;

        serializeBinary(): Uint8Array;
        toObject(includeInstance?: boolean): Hitl.AsObject;
        static toObject(includeInstance: boolean, msg: Hitl): Hitl.AsObject;
        static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
        static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
        static serializeBinaryToWriter(message: Hitl, writer: jspb.BinaryWriter): void;
        static deserializeBinary(bytes: Uint8Array): Hitl;
        static deserializeBinaryFromReader(message: Hitl, reader: jspb.BinaryReader): Hitl;
    }

    export namespace Hitl {
        export type AsObject = {
            mode: string,
        }
    }

    export class Scoring extends jspb.Message { 
        getRequireSchemaValid(): boolean;
        setRequireSchemaValid(value: boolean): Scoring;
        getRequireExamplesPass(): boolean;
        setRequireExamplesPass(value: boolean): Scoring;
        getLlmWeight(): number;
        setLlmWeight(value: number): Scoring;

        serializeBinary(): Uint8Array;
        toObject(includeInstance?: boolean): Scoring.AsObject;
        static toObject(includeInstance: boolean, msg: Scoring): Scoring.AsObject;
        static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
        static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
        static serializeBinaryToWriter(message: Scoring, writer: jspb.BinaryWriter): void;
        static deserializeBinary(bytes: Uint8Array): Scoring;
        static deserializeBinaryFromReader(message: Scoring, reader: jspb.BinaryReader): Scoring;
    }

    export namespace Scoring {
        export type AsObject = {
            requireSchemaValid: boolean,
            requireExamplesPass: boolean,
            llmWeight: number,
        }
    }

}

export class AgentPreferences extends jspb.Message { 
    getMaxRounds(): number;
    setMaxRounds(value: number): AgentPreferences;
    getScoreThreshold(): number;
    setScoreThreshold(value: number): AgentPreferences;
    getDiffTolerance(): number;
    setDiffTolerance(value: number): AgentPreferences;
    getRoundTimeoutMs(): number;
    setRoundTimeoutMs(value: number): AgentPreferences;
    getTokenBudgetPerRound(): number;
    setTokenBudgetPerRound(value: number): AgentPreferences;
    getTotalTokenBudget(): number;
    setTotalTokenBudget(value: number): AgentPreferences;
    getOscillationLimit(): number;
    setOscillationLimit(value: number): AgentPreferences;

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): AgentPreferences.AsObject;
    static toObject(includeInstance: boolean, msg: AgentPreferences): AgentPreferences.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: AgentPreferences, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): AgentPreferences;
    static deserializeBinaryFromReader(message: AgentPreferences, reader: jspb.BinaryReader): AgentPreferences;
}

export namespace AgentPreferences {
    export type AsObject = {
        maxRounds: number,
        scoreThreshold: number,
        diffTolerance: number,
        roundTimeoutMs: number,
        tokenBudgetPerRound: number,
        totalTokenBudget: number,
        oscillationLimit: number,
    }
}

export class EffectivePolicy extends jspb.Message { 

    hasPolicy(): boolean;
    clearPolicy(): void;
    getPolicy(): WagglePolicy | undefined;
    setPolicy(value?: WagglePolicy): EffectivePolicy;

    getAppliedMap(): jspb.Map<string, AgentPreferences>;
    clearAppliedMap(): void;

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): EffectivePolicy.AsObject;
    static toObject(includeInstance: boolean, msg: EffectivePolicy): EffectivePolicy.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: EffectivePolicy, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): EffectivePolicy;
    static deserializeBinaryFromReader(message: EffectivePolicy, reader: jspb.BinaryReader): EffectivePolicy;
}

export namespace EffectivePolicy {
    export type AsObject = {
        policy?: WagglePolicy.AsObject,

        appliedMap: Array<[string, AgentPreferences.AsObject]>,
    }
}

export class PolicyProfile extends jspb.Message { 
    getName(): string;
    setName(value: string): PolicyProfile;

    hasPolicy(): boolean;
    clearPolicy(): void;
    getPolicy(): WagglePolicy | undefined;
    setPolicy(value?: WagglePolicy): PolicyProfile;

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): PolicyProfile.AsObject;
    static toObject(includeInstance: boolean, msg: PolicyProfile): PolicyProfile.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: PolicyProfile, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): PolicyProfile;
    static deserializeBinaryFromReader(message: PolicyProfile, reader: jspb.BinaryReader): PolicyProfile;
}

export namespace PolicyProfile {
    export type AsObject = {
        name: string,
        policy?: WagglePolicy.AsObject,
    }
}

export class DeltaSummary extends jspb.Message { 
    getMagnitude(): number;
    setMagnitude(value: number): DeltaSummary;
    clearChangedPathsList(): void;
    getChangedPathsList(): Array<string>;
    setChangedPathsList(value: Array<string>): DeltaSummary;
    addChangedPaths(value: string, index?: number): string;

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): DeltaSummary.AsObject;
    static toObject(includeInstance: boolean, msg: DeltaSummary): DeltaSummary.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: DeltaSummary, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): DeltaSummary;
    static deserializeBinaryFromReader(message: DeltaSummary, reader: jspb.BinaryReader): DeltaSummary;
}

export namespace DeltaSummary {
    export type AsObject = {
        magnitude: number,
        changedPathsList: Array<string>,
    }
}

export class EvaluationReport extends jspb.Message { 
    getFromAgent(): string;
    setFromAgent(value: string): EvaluationReport;
    getDeterministicScore(): number;
    setDeterministicScore(value: number): EvaluationReport;
    getLlmConfidence(): number;
    setLlmConfidence(value: number): EvaluationReport;
    getNotes(): string;
    setNotes(value: string): EvaluationReport;

    hasDelta(): boolean;
    clearDelta(): void;
    getDelta(): DeltaSummary | undefined;
    setDelta(value?: DeltaSummary): EvaluationReport;

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): EvaluationReport.AsObject;
    static toObject(includeInstance: boolean, msg: EvaluationReport): EvaluationReport.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: EvaluationReport, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): EvaluationReport;
    static deserializeBinaryFromReader(message: EvaluationReport, reader: jspb.BinaryReader): EvaluationReport;
}

export namespace EvaluationReport {
    export type AsObject = {
        fromAgent: string,
        deterministicScore: number,
        llmConfidence: number,
        notes: string,
        delta?: DeltaSummary.AsObject,
    }
}

export class DecisionReport extends jspb.Message { 
    getDecidedBy(): string;
    setDecidedBy(value: string): DecisionReport;
    getFinalScore(): number;
    setFinalScore(value: number): DecisionReport;
    getRationale(): string;
    setRationale(value: string): DecisionReport;
    getStopReason(): string;
    setStopReason(value: string): DecisionReport;

    serializeBinary(): Uint8Array;
    toObject(includeInstance?: boolean): DecisionReport.AsObject;
    static toObject(includeInstance: boolean, msg: DecisionReport): DecisionReport.AsObject;
    static extensions: {[key: number]: jspb.ExtensionFieldInfo<jspb.Message>};
    static extensionsBinary: {[key: number]: jspb.ExtensionFieldBinaryInfo<jspb.Message>};
    static serializeBinaryToWriter(message: DecisionReport, writer: jspb.BinaryWriter): void;
    static deserializeBinary(bytes: Uint8Array): DecisionReport;
    static deserializeBinaryFromReader(message: DecisionReport, reader: jspb.BinaryReader): DecisionReport;
}

export namespace DecisionReport {
    export type AsObject = {
        decidedBy: string,
        finalScore: number,
        rationale: string,
        stopReason: string,
    }
}
