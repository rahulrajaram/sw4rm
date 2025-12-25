// Copyright 2025 Rahul Rajaram
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

/**
 * Policy store for SW4RM.
 *
 * This module provides interfaces and implementations for storing and
 * retrieving negotiation policies. Policies define the rules and thresholds
 * for negotiation workflows.
 *
 * Based on policy.proto definitions.
 */

/**
 * HITL gate mode for policies.
 */
export enum HitlMode {
  NONE = 'None',
  PAUSE_BETWEEN_ROUNDS = 'PauseBetweenRounds',
  PAUSE_ON_FINAL_ACCEPT = 'PauseOnFinalAccept',
}

/**
 * Scoring configuration for policies.
 */
export interface ScoringConfig {
  /** Whether to require JSON schema validation */
  requireSchemaValid: boolean;
  /** Whether to require examples to pass */
  requireExamplesPass: boolean;
  /** Weight for LLM-based scoring (0-1) */
  llmWeight: number;
}

/**
 * A negotiation policy defining rules and thresholds.
 *
 * Policies are used by the scheduler to control negotiation behavior
 * and ensure consistency across negotiations.
 */
export interface NegotiationPolicy {
  /** Maximum number of negotiation rounds */
  maxRounds: number;
  /** Score threshold for approval (0-1) */
  scoreThreshold: number;
  /** Tolerance for structural differences (0-1) */
  diffTolerance: number;
  /** Timeout per round in milliseconds */
  roundTimeoutMs: number;
  /** Token budget per round */
  tokenBudgetPerRound: number;
  /** Total token budget (0 = unlimited) */
  totalTokenBudget: number;
  /** Maximum oscillations before escalation */
  oscillationLimit: number;
  /** HITL gate mode */
  hitl: HitlMode;
  /** Scoring configuration */
  scoring: ScoringConfig;
}

/**
 * Agent preferences for negotiation.
 *
 * Same fields as NegotiationPolicy but advisory; scheduler clamps to guardrails.
 */
export interface AgentPreferences {
  maxRounds?: number;
  scoreThreshold?: number;
  diffTolerance?: number;
  roundTimeoutMs?: number;
  tokenBudgetPerRound?: number;
  totalTokenBudget?: number;
  oscillationLimit?: number;
}

/**
 * Network access policy for execution.
 */
export type NetworkPolicy = 'none' | 'restricted' | 'full';

/**
 * Privilege level for execution.
 */
export type PrivilegeLevel = 'standard' | 'elevated' | 'admin';

/**
 * Backoff strategy for retries.
 */
export type BackoffStrategy = 'none' | 'linear' | 'exponential';

/**
 * Policy governing task execution.
 *
 * Defines constraints and resource limits for executing tasks.
 * Per SPEC_REQUESTS §6.3.
 *
 * Note: Named TaskExecutionPolicy to avoid conflict with tool.ts ExecutionPolicy.
 */
export interface TaskExecutionPolicy {
  /** Maximum execution time in milliseconds */
  timeoutMs: number;
  /** Maximum number of retry attempts */
  maxRetries: number;
  /** Backoff strategy for retries */
  backoff: BackoffStrategy;
  /** Whether a worktree binding is required for execution */
  worktreeRequired: boolean;
  /** Network access policy */
  networkPolicy: NetworkPolicy;
  /** Required privilege level */
  privilegeLevel: PrivilegeLevel;
  /** CPU time budget in milliseconds */
  budgetCpuMs: number;
  /** Wall clock time budget in milliseconds */
  budgetWallMs: number;
}

/**
 * Policy governing escalation behavior.
 *
 * Defines when and how negotiations should be escalated.
 * Per SPEC_REQUESTS §6.3.
 */
export interface EscalationPolicy {
  /** Whether to automatically escalate when deadlock is detected */
  autoEscalateOnDeadlock: boolean;
  /** Number of rounds without progress before declaring deadlock */
  deadlockRounds: number;
  /** List of valid reasons for escalation */
  escalationReasons: string[];
  /** Default action when escalation is triggered */
  defaultAction: 'retry_same' | 'escalate' | 'fail';
}

/**
 * Default execution policy.
 */
export const DEFAULT_EXECUTION_POLICY: TaskExecutionPolicy = {
  timeoutMs: 60000,
  maxRetries: 3,
  backoff: 'exponential',
  worktreeRequired: false,
  networkPolicy: 'restricted',
  privilegeLevel: 'standard',
  budgetCpuMs: 30000,
  budgetWallMs: 60000,
};

/**
 * Default escalation policy.
 */
export const DEFAULT_ESCALATION_POLICY: EscalationPolicy = {
  autoEscalateOnDeadlock: true,
  deadlockRounds: 3,
  escalationReasons: ['debate_deadlock', 'security_flag', 'timeout'],
  defaultAction: 'escalate',
};

/**
 * Effective policy after applying agent preferences and scheduler guardrails.
 *
 * Combines negotiation, execution, and escalation policies as per SPEC_REQUESTS §6.3.
 */
export interface EffectivePolicy {
  /** Unique identifier for this effective policy */
  policyId: string;
  /** Version string for the policy (timestamp_uuid format) */
  version: string;
  /** The derived authoritative negotiation policy */
  negotiation: NegotiationPolicy;
  /** Execution policy settings */
  execution: TaskExecutionPolicy;
  /** Escalation policy settings */
  escalation: EscalationPolicy;
  /** Per-agent clamped preferences (optional) */
  applied?: Record<string, AgentPreferences>;
  /** Negotiation ID this policy applies to */
  negotiationId?: string;
  /** Timestamp when policy was created (ISO-8601 string) */
  createdAt?: string;
}

/**
 * A named policy profile.
 */
export interface PolicyProfile {
  /** Profile name (e.g., "LOW", "MEDIUM", "HIGH") */
  name: string;
  /** The negotiation policy for this profile */
  negotiation: NegotiationPolicy;
  /** The execution policy for this profile */
  execution: TaskExecutionPolicy;
  /** The escalation policy for this profile */
  escalation: EscalationPolicy;
}

/**
 * Error thrown when a policy operation fails.
 */
export class PolicyStoreError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'PolicyStoreError';
  }
}

/**
 * Interface for policy storage backends.
 *
 * Implementations provide storage and retrieval of negotiation policies.
 * Policies are immutable once stored - saving a policy with the same
 * policy_id but different version creates a new snapshot in the history.
 */
export interface PolicyStore {
  /**
   * Get the latest version of a policy by its ID.
   *
   * @param policyId - The unique identifier of the policy
   * @returns The effective policy if found, null otherwise
   */
  getPolicy(policyId: string): Promise<EffectivePolicy | null>;

  /**
   * Save a policy snapshot.
   *
   * If the policy does not have a version, one will be generated.
   * The policy snapshot is immutable once saved.
   *
   * @param policy - The effective policy to save
   * @returns The policy ID
   */
  savePolicy(policy: EffectivePolicy): Promise<string>;

  /**
   * List all policy IDs, optionally filtered by prefix.
   *
   * @param prefix - Optional prefix to filter policy IDs
   * @returns List of matching policy IDs
   */
  listPolicies(prefix?: string): Promise<string[]>;

  /**
   * Delete a policy by its ID (removes all versions).
   *
   * @param policyId - The unique identifier of the policy
   * @returns True if the policy was deleted, false if not found
   */
  deletePolicy(policyId: string): Promise<boolean>;

  /**
   * Retrieve the complete version history for a policy.
   *
   * Returns policies in chronological order (oldest to newest).
   *
   * @param policyId - The unique identifier of the policy
   * @returns List of all versions of the policy
   */
  getHistory(policyId: string): Promise<EffectivePolicy[]>;

  /**
   * Get a policy profile by name.
   *
   * @param name - The profile name
   * @returns The policy profile if found, null otherwise
   */
  getProfile(name: string): Promise<PolicyProfile | null>;

  /**
   * Save a policy profile.
   *
   * @param profile - The policy profile to save
   * @returns The profile name
   */
  saveProfile(profile: PolicyProfile): Promise<string>;

  /**
   * List all profile names.
   *
   * @returns List of profile names
   */
  listProfiles(): Promise<string[]>;
}

/**
 * Default negotiation policy.
 *
 * Used when no specific policy is configured.
 */
export const DEFAULT_NEGOTIATION_POLICY: NegotiationPolicy = {
  maxRounds: 10,
  scoreThreshold: 0.7,
  diffTolerance: 0.3,
  roundTimeoutMs: 30000,
  tokenBudgetPerRound: 4096,
  totalTokenBudget: 0, // unlimited
  oscillationLimit: 3,
  hitl: HitlMode.NONE,
  scoring: {
    requireSchemaValid: true,
    requireExamplesPass: false,
    llmWeight: 0.5,
  },
};

/**
 * Generates a unique policy ID.
 */
function generatePolicyId(): string {
  return `policy-${Date.now()}-${Math.random().toString(36).substring(2, 9)}`;
}

/**
 * Generates a unique version identifier for a policy.
 *
 * Uses a combination of timestamp and random ID to ensure uniqueness
 * and provide chronological ordering.
 *
 * @returns A version string in the format: `{timestamp_ms}_{random_id}`
 */
function generatePolicyVersion(): string {
  const timestampMs = Date.now();
  const uniqueId = Math.random().toString(36).substring(2, 11);
  return `${timestampMs}_${uniqueId}`;
}

/**
 * In-memory implementation of PolicyStore.
 *
 * Provides a simple in-memory storage for policies and profiles with
 * full version history support. Data is lost when the process terminates.
 * Suitable for development and testing; production deployments should
 * use JsonFilePolicyStore for persistence.
 */
export class InMemoryPolicyStore implements PolicyStore {
  // Maps policy_id -> list of EffectivePolicy (chronological order)
  private policies: Map<string, EffectivePolicy[]> = new Map();
  private profiles: Map<string, PolicyProfile> = new Map();

  constructor() {
    // Initialize with default profiles
    this.initializeDefaultProfiles();
  }

  /**
   * Initialize default policy profiles.
   */
  private initializeDefaultProfiles(): void {
    const lowProfile: PolicyProfile = {
      name: 'LOW',
      negotiation: {
        maxRounds: 5,
        scoreThreshold: 0.6,
        diffTolerance: 0.4,
        roundTimeoutMs: 60000,
        tokenBudgetPerRound: 2048,
        totalTokenBudget: 0,
        oscillationLimit: 5,
        hitl: HitlMode.NONE,
        scoring: {
          requireSchemaValid: false,
          requireExamplesPass: false,
          llmWeight: 0.3,
        },
      },
      execution: {
        ...DEFAULT_EXECUTION_POLICY,
        timeoutMs: 120000, // More lenient for low priority
        maxRetries: 5,
      },
      escalation: {
        ...DEFAULT_ESCALATION_POLICY,
        deadlockRounds: 5, // More tolerant
      },
    };

    const mediumProfile: PolicyProfile = {
      name: 'MEDIUM',
      negotiation: { ...DEFAULT_NEGOTIATION_POLICY },
      execution: { ...DEFAULT_EXECUTION_POLICY },
      escalation: { ...DEFAULT_ESCALATION_POLICY },
    };

    const highProfile: PolicyProfile = {
      name: 'HIGH',
      negotiation: {
        maxRounds: 15,
        scoreThreshold: 0.85,
        diffTolerance: 0.2,
        roundTimeoutMs: 20000,
        tokenBudgetPerRound: 8192,
        totalTokenBudget: 100000,
        oscillationLimit: 2,
        hitl: HitlMode.PAUSE_ON_FINAL_ACCEPT,
        scoring: {
          requireSchemaValid: true,
          requireExamplesPass: true,
          llmWeight: 0.7,
        },
      },
      execution: {
        ...DEFAULT_EXECUTION_POLICY,
        timeoutMs: 30000, // Stricter timeout
        maxRetries: 2,
        networkPolicy: 'none', // More restrictive
      },
      escalation: {
        ...DEFAULT_ESCALATION_POLICY,
        deadlockRounds: 2, // Quick escalation
        autoEscalateOnDeadlock: true,
      },
    };

    this.profiles.set('LOW', lowProfile);
    this.profiles.set('MEDIUM', mediumProfile);
    this.profiles.set('HIGH', highProfile);
  }

  /**
   * Get the latest version of a policy by its ID.
   *
   * @param policyId - The unique identifier of the policy
   * @returns The most recent effective policy if found, null otherwise
   */
  async getPolicy(policyId: string): Promise<EffectivePolicy | null> {
    const versions = this.policies.get(policyId);
    if (!versions || versions.length === 0) {
      return null;
    }
    // Return the latest version (last in the array)
    return versions[versions.length - 1];
  }

  /**
   * Save a policy snapshot to the version history.
   *
   * If the policy does not have an ID, one will be generated.
   * If the policy does not have a version, one will be generated.
   *
   * @param policy - The effective policy to save
   * @returns The policy ID
   */
  async savePolicy(policy: EffectivePolicy): Promise<string> {
    const policyId = policy.policyId || generatePolicyId();
    const version = policy.version || generatePolicyVersion();

    const policyWithMeta: EffectivePolicy = {
      ...policy,
      policyId,
      version,
      createdAt: policy.createdAt || new Date().toISOString(),
    };

    // Get or create the version history array
    const versions = this.policies.get(policyId) || [];
    versions.push(policyWithMeta);
    this.policies.set(policyId, versions);

    return policyId;
  }

  /**
   * List all policy IDs, optionally filtered by prefix.
   *
   * @param prefix - Optional prefix to filter policy IDs
   * @returns List of matching policy IDs
   */
  async listPolicies(prefix?: string): Promise<string[]> {
    const allIds = Array.from(this.policies.keys());

    if (prefix === undefined) {
      return allIds;
    }

    return allIds.filter((id) => id.startsWith(prefix));
  }

  /**
   * Delete a policy by its ID (removes all versions).
   *
   * @param policyId - The unique identifier of the policy
   * @returns True if the policy was deleted, false if not found
   */
  async deletePolicy(policyId: string): Promise<boolean> {
    return this.policies.delete(policyId);
  }

  /**
   * Retrieve the complete version history for a policy.
   *
   * Returns policies in chronological order (oldest to newest).
   *
   * @param policyId - The unique identifier of the policy
   * @returns List of all versions of the policy
   */
  async getHistory(policyId: string): Promise<EffectivePolicy[]> {
    const versions = this.policies.get(policyId);
    if (!versions) {
      return [];
    }
    // Return a copy to prevent external mutation
    return [...versions];
  }

  /**
   * Get a policy profile by name.
   *
   * @param name - The profile name
   * @returns The policy profile if found, null otherwise
   */
  async getProfile(name: string): Promise<PolicyProfile | null> {
    return this.profiles.get(name) || null;
  }

  /**
   * Save a policy profile.
   *
   * @param profile - The policy profile to save
   * @returns The profile name
   */
  async saveProfile(profile: PolicyProfile): Promise<string> {
    this.profiles.set(profile.name, profile);
    return profile.name;
  }

  /**
   * List all profile names.
   *
   * @returns List of profile names
   */
  async listProfiles(): Promise<string[]> {
    return Array.from(this.profiles.keys());
  }

  /**
   * Create an effective policy from a profile and agent preferences.
   *
   * Clamps agent preferences to the profile's guardrails.
   *
   * @param profileName - The profile to use as base
   * @param agentPrefs - Optional agent preferences to apply
   * @param negotiationId - Optional negotiation ID
   * @returns The effective policy
   * @throws PolicyStoreError if the profile does not exist
   */
  async createEffectivePolicy(
    profileName: string,
    agentPrefs?: Record<string, AgentPreferences>,
    negotiationId?: string
  ): Promise<EffectivePolicy> {
    const profile = await this.getProfile(profileName);
    if (!profile) {
      throw new PolicyStoreError(`Profile '${profileName}' does not exist`);
    }

    const baseNegotiation = { ...profile.negotiation };
    const baseExecution = { ...profile.execution };
    const baseEscalation = { ...profile.escalation };

    // Apply and clamp agent preferences if provided
    const applied: Record<string, AgentPreferences> = {};
    if (agentPrefs) {
      for (const [agentId, prefs] of Object.entries(agentPrefs)) {
        const clamped: AgentPreferences = {};

        if (prefs.maxRounds !== undefined) {
          clamped.maxRounds = Math.min(prefs.maxRounds, baseNegotiation.maxRounds);
        }
        if (prefs.scoreThreshold !== undefined) {
          clamped.scoreThreshold = Math.max(
            prefs.scoreThreshold,
            baseNegotiation.scoreThreshold
          );
        }
        if (prefs.diffTolerance !== undefined) {
          clamped.diffTolerance = Math.min(
            prefs.diffTolerance,
            baseNegotiation.diffTolerance
          );
        }
        if (prefs.roundTimeoutMs !== undefined) {
          clamped.roundTimeoutMs = Math.min(
            prefs.roundTimeoutMs,
            baseNegotiation.roundTimeoutMs
          );
        }
        if (prefs.tokenBudgetPerRound !== undefined) {
          clamped.tokenBudgetPerRound = Math.min(
            prefs.tokenBudgetPerRound,
            baseNegotiation.tokenBudgetPerRound
          );
        }
        if (
          prefs.totalTokenBudget !== undefined &&
          baseNegotiation.totalTokenBudget > 0
        ) {
          clamped.totalTokenBudget = Math.min(
            prefs.totalTokenBudget,
            baseNegotiation.totalTokenBudget
          );
        }
        if (prefs.oscillationLimit !== undefined) {
          clamped.oscillationLimit = Math.min(
            prefs.oscillationLimit,
            baseNegotiation.oscillationLimit
          );
        }

        applied[agentId] = clamped;
      }
    }

    const effectivePolicy: EffectivePolicy = {
      policyId: generatePolicyId(),
      version: generatePolicyVersion(),
      negotiation: baseNegotiation,
      execution: baseExecution,
      escalation: baseEscalation,
      negotiationId,
      createdAt: new Date().toISOString(),
    };

    if (Object.keys(applied).length > 0) {
      effectivePolicy.applied = applied;
    }

    // Auto-save the effective policy
    await this.savePolicy(effectivePolicy);

    return effectivePolicy;
  }
}

import fsp from 'node:fs/promises';
import path from 'node:path';

/**
 * JSON file-based implementation of PolicyStore.
 *
 * Stores policies as JSON files on disk with full version history support.
 * Each policy is stored in a separate file named `{sanitized_policy_id}.json`.
 * Uses atomic writes (temp file + rename) to prevent corruption.
 *
 * Suitable for production use in single-node deployments.
 */
export class JsonFilePolicyStore implements PolicyStore {
  private readonly directory: string;
  private profiles: Map<string, PolicyProfile> = new Map();

  /**
   * Create a new JSON file policy store.
   *
   * @param directory - Directory to store policy files
   */
  constructor(directory: string) {
    this.directory = directory;
    // Initialize with default profiles
    this.initializeDefaultProfiles();
  }

  /**
   * Initialize the store, creating the directory if needed.
   */
  async initialize(): Promise<void> {
    await fsp.mkdir(this.directory, { recursive: true });
  }

  /**
   * Initialize default policy profiles.
   */
  private initializeDefaultProfiles(): void {
    const lowProfile: PolicyProfile = {
      name: 'LOW',
      negotiation: {
        maxRounds: 5,
        scoreThreshold: 0.6,
        diffTolerance: 0.4,
        roundTimeoutMs: 60000,
        tokenBudgetPerRound: 2048,
        totalTokenBudget: 0,
        oscillationLimit: 5,
        hitl: HitlMode.NONE,
        scoring: {
          requireSchemaValid: false,
          requireExamplesPass: false,
          llmWeight: 0.3,
        },
      },
      execution: {
        ...DEFAULT_EXECUTION_POLICY,
        timeoutMs: 120000,
        maxRetries: 5,
      },
      escalation: {
        ...DEFAULT_ESCALATION_POLICY,
        deadlockRounds: 5,
      },
    };

    const mediumProfile: PolicyProfile = {
      name: 'MEDIUM',
      negotiation: { ...DEFAULT_NEGOTIATION_POLICY },
      execution: { ...DEFAULT_EXECUTION_POLICY },
      escalation: { ...DEFAULT_ESCALATION_POLICY },
    };

    const highProfile: PolicyProfile = {
      name: 'HIGH',
      negotiation: {
        maxRounds: 15,
        scoreThreshold: 0.85,
        diffTolerance: 0.2,
        roundTimeoutMs: 20000,
        tokenBudgetPerRound: 8192,
        totalTokenBudget: 100000,
        oscillationLimit: 2,
        hitl: HitlMode.PAUSE_ON_FINAL_ACCEPT,
        scoring: {
          requireSchemaValid: true,
          requireExamplesPass: true,
          llmWeight: 0.7,
        },
      },
      execution: {
        ...DEFAULT_EXECUTION_POLICY,
        timeoutMs: 30000,
        maxRetries: 2,
        networkPolicy: 'none',
      },
      escalation: {
        ...DEFAULT_ESCALATION_POLICY,
        deadlockRounds: 2,
        autoEscalateOnDeadlock: true,
      },
    };

    this.profiles.set('LOW', lowProfile);
    this.profiles.set('MEDIUM', mediumProfile);
    this.profiles.set('HIGH', highProfile);
  }

  /**
   * Sanitize a policy ID for use as a filename.
   */
  private sanitizeId(policyId: string): string {
    return policyId.replace(/[/\\]/g, '_');
  }

  /**
   * Get the file path for a policy.
   */
  private getFilePath(policyId: string): string {
    return path.join(this.directory, `${this.sanitizeId(policyId)}.json`);
  }

  /**
   * Load versions from a file.
   */
  private async loadFromFile(policyId: string): Promise<EffectivePolicy[]> {
    const filePath = this.getFilePath(policyId);
    try {
      const data = await fsp.readFile(filePath, 'utf-8');
      const parsed = JSON.parse(data);
      // Handle both array (version history) and single object (legacy)
      if (Array.isArray(parsed)) {
        return parsed;
      }
      return [parsed];
    } catch {
      return [];
    }
  }

  /**
   * Save versions to a file atomically.
   */
  private async saveToFile(policyId: string, versions: EffectivePolicy[]): Promise<void> {
    await this.initialize();
    const filePath = this.getFilePath(policyId);
    const tempPath = `${filePath}.tmp.${Date.now()}`;
    const data = JSON.stringify(versions, null, 2);
    await fsp.writeFile(tempPath, data, 'utf-8');
    await fsp.rename(tempPath, filePath);
  }

  async getPolicy(policyId: string): Promise<EffectivePolicy | null> {
    const versions = await this.loadFromFile(policyId);
    if (versions.length === 0) {
      return null;
    }
    return versions[versions.length - 1];
  }

  async savePolicy(policy: EffectivePolicy): Promise<string> {
    const policyId = policy.policyId || generatePolicyId();
    const version = policy.version || generatePolicyVersion();

    const policyWithMeta: EffectivePolicy = {
      ...policy,
      policyId,
      version,
      createdAt: policy.createdAt || new Date().toISOString(),
    };

    const versions = await this.loadFromFile(policyId);
    versions.push(policyWithMeta);
    await this.saveToFile(policyId, versions);

    return policyId;
  }

  async listPolicies(prefix?: string): Promise<string[]> {
    try {
      await this.initialize();
      const files = await fsp.readdir(this.directory);
      const policyIds = files
        .filter((f) => f.endsWith('.json'))
        .map((f) => f.slice(0, -5)); // Remove .json extension

      if (prefix === undefined) {
        return policyIds;
      }
      return policyIds.filter((id) => id.startsWith(prefix));
    } catch {
      return [];
    }
  }

  async deletePolicy(policyId: string): Promise<boolean> {
    const filePath = this.getFilePath(policyId);
    try {
      await fsp.unlink(filePath);
      return true;
    } catch {
      return false;
    }
  }

  async getHistory(policyId: string): Promise<EffectivePolicy[]> {
    return this.loadFromFile(policyId);
  }

  async getProfile(name: string): Promise<PolicyProfile | null> {
    return this.profiles.get(name) || null;
  }

  async saveProfile(profile: PolicyProfile): Promise<string> {
    this.profiles.set(profile.name, profile);
    return profile.name;
  }

  async listProfiles(): Promise<string[]> {
    return Array.from(this.profiles.keys());
  }

  /**
   * Create an effective policy from a profile and agent preferences.
   */
  async createEffectivePolicy(
    profileName: string,
    agentPrefs?: Record<string, AgentPreferences>,
    negotiationId?: string
  ): Promise<EffectivePolicy> {
    const profile = await this.getProfile(profileName);
    if (!profile) {
      throw new PolicyStoreError(`Profile '${profileName}' does not exist`);
    }

    const baseNegotiation = { ...profile.negotiation };
    const baseExecution = { ...profile.execution };
    const baseEscalation = { ...profile.escalation };

    const applied: Record<string, AgentPreferences> = {};
    if (agentPrefs) {
      for (const [agentId, prefs] of Object.entries(agentPrefs)) {
        const clamped: AgentPreferences = {};
        if (prefs.maxRounds !== undefined) {
          clamped.maxRounds = Math.min(prefs.maxRounds, baseNegotiation.maxRounds);
        }
        if (prefs.scoreThreshold !== undefined) {
          clamped.scoreThreshold = Math.max(prefs.scoreThreshold, baseNegotiation.scoreThreshold);
        }
        if (prefs.diffTolerance !== undefined) {
          clamped.diffTolerance = Math.min(prefs.diffTolerance, baseNegotiation.diffTolerance);
        }
        if (prefs.roundTimeoutMs !== undefined) {
          clamped.roundTimeoutMs = Math.min(prefs.roundTimeoutMs, baseNegotiation.roundTimeoutMs);
        }
        if (prefs.tokenBudgetPerRound !== undefined) {
          clamped.tokenBudgetPerRound = Math.min(prefs.tokenBudgetPerRound, baseNegotiation.tokenBudgetPerRound);
        }
        if (prefs.totalTokenBudget !== undefined && baseNegotiation.totalTokenBudget > 0) {
          clamped.totalTokenBudget = Math.min(prefs.totalTokenBudget, baseNegotiation.totalTokenBudget);
        }
        if (prefs.oscillationLimit !== undefined) {
          clamped.oscillationLimit = Math.min(prefs.oscillationLimit, baseNegotiation.oscillationLimit);
        }
        applied[agentId] = clamped;
      }
    }

    const effectivePolicy: EffectivePolicy = {
      policyId: generatePolicyId(),
      version: generatePolicyVersion(),
      negotiation: baseNegotiation,
      execution: baseExecution,
      escalation: baseEscalation,
      negotiationId,
      createdAt: new Date().toISOString(),
    };

    if (Object.keys(applied).length > 0) {
      effectivePolicy.applied = applied;
    }

    await this.savePolicy(effectivePolicy);
    return effectivePolicy;
  }
}
