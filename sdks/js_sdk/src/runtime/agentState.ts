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
 * Agent runtime state machine for SW4RM.
 *
 * This module provides the AgentState enum and state transition validation
 * for implementing the agent lifecycle as specified in spec section 8.
 *
 * The agent lifecycle states are:
 * - INITIALIZING: Agent starting up and registering
 * - RUNNABLE: Agent ready to accept tasks
 * - SCHEDULED: Agent has task assigned but not yet running
 * - RUNNING: Agent actively executing task
 * - WAITING: Agent waiting for external input
 * - WAITING_RESOURCES: Agent waiting for resources
 * - SUSPENDED: Agent paused by scheduler
 * - RESUMED: Agent transitioning from suspended to running
 * - COMPLETED: Agent finished current task
 * - FAILED: Agent encountered error
 * - SHUTTING_DOWN: Agent gracefully terminating
 * - RECOVERING: Agent recovering from failure
 */

/**
 * Agent lifecycle states as defined in spec section 8.
 */
export enum AgentState {
  /** Agent state not set */
  AGENT_STATE_UNSPECIFIED = 0,
  /** Agent starting up and registering */
  INITIALIZING = 1,
  /** Agent ready to accept tasks */
  RUNNABLE = 2,
  /** Agent has task assigned but not yet running */
  SCHEDULED = 3,
  /** Agent actively executing task */
  RUNNING = 4,
  /** Agent waiting for external input */
  WAITING = 5,
  /** Agent waiting for resources */
  WAITING_RESOURCES = 6,
  /** Agent paused by scheduler */
  SUSPENDED = 7,
  /** Agent transitioning from suspended to running */
  RESUMED = 8,
  /** Agent finished current task */
  COMPLETED = 9,
  /** Agent encountered error */
  FAILED = 10,
  /** Agent gracefully terminating */
  SHUTTING_DOWN = 11,
  /** Agent recovering from failure */
  RECOVERING = 12,
}

/**
 * Error thrown when an invalid state transition is attempted.
 */
export class StateTransitionError extends Error {
  readonly fromState: AgentState;
  readonly toState: AgentState;

  constructor(fromState: AgentState, toState: AgentState) {
    const fromName = AgentState[fromState];
    const toName = AgentState[toState];
    super(`Invalid state transition from ${fromName} to ${toName}`);
    this.name = 'StateTransitionError';
    this.fromState = fromState;
    this.toState = toState;
  }
}

/**
 * State transition validation matrix.
 *
 * Maps each state to the set of valid target states.
 * Based on the state diagram in spec Appendix C.
 */
const VALID_TRANSITIONS = new Map<AgentState, Set<AgentState>>([
  // INITIALIZING -> RUNNABLE
  [AgentState.INITIALIZING, new Set<AgentState>([AgentState.RUNNABLE])],

  // RUNNABLE -> SCHEDULED
  [AgentState.RUNNABLE, new Set<AgentState>([AgentState.SCHEDULED])],

  // SCHEDULED -> RUNNING
  [AgentState.SCHEDULED, new Set<AgentState>([AgentState.RUNNING])],

  // RUNNING -> WAITING, WAITING_RESOURCES, SUSPENDED, COMPLETED, FAILED, SHUTTING_DOWN
  [
    AgentState.RUNNING,
    new Set<AgentState>([
      AgentState.WAITING,
      AgentState.WAITING_RESOURCES,
      AgentState.SUSPENDED,
      AgentState.COMPLETED,
      AgentState.FAILED,
      AgentState.SHUTTING_DOWN,
    ]),
  ],

  // WAITING -> RUNNING
  [AgentState.WAITING, new Set<AgentState>([AgentState.RUNNING])],

  // WAITING_RESOURCES -> RUNNING, FAILED (resource timeout)
  [
    AgentState.WAITING_RESOURCES,
    new Set<AgentState>([AgentState.RUNNING, AgentState.FAILED]),
  ],

  // SUSPENDED -> RESUMED
  [AgentState.SUSPENDED, new Set<AgentState>([AgentState.RESUMED])],

  // RESUMED -> RUNNING
  [AgentState.RESUMED, new Set<AgentState>([AgentState.RUNNING])],

  // COMPLETED -> RUNNABLE
  [AgentState.COMPLETED, new Set<AgentState>([AgentState.RUNNABLE])],

  // FAILED -> RECOVERING
  [AgentState.FAILED, new Set<AgentState>([AgentState.RECOVERING])],

  // SHUTTING_DOWN -> FAILED (agent_shutdown_timeout)
  [AgentState.SHUTTING_DOWN, new Set<AgentState>([AgentState.FAILED])],

  // RECOVERING -> RUNNABLE, SHUTTING_DOWN (recovery abort)
  [
    AgentState.RECOVERING,
    new Set<AgentState>([AgentState.RUNNABLE, AgentState.SHUTTING_DOWN]),
  ],
]);

/**
 * Check if a state transition is valid.
 *
 * @param fromState - The current state
 * @param toState - The target state
 * @returns True if the transition is valid, false otherwise
 */
export function isValidTransition(
  fromState: AgentState,
  toState: AgentState
): boolean {
  const validTargets = VALID_TRANSITIONS.get(fromState);
  if (!validTargets) {
    return false;
  }
  return validTargets.has(toState);
}

/**
 * Get all valid target states from a given state.
 *
 * @param fromState - The current state
 * @returns Array of valid target states
 */
export function getValidTransitions(fromState: AgentState): AgentState[] {
  const validTargets = VALID_TRANSITIONS.get(fromState);
  if (!validTargets) {
    return [];
  }
  return Array.from(validTargets);
}

/**
 * Lifecycle hook types for agent state changes.
 */
export interface AgentLifecycleHooks {
  /** Called on any state change */
  onStateChange?: (
    fromState: AgentState,
    toState: AgentState,
    context?: Record<string, unknown>
  ) => void | Promise<void>;
  /** Called when agent becomes SCHEDULED */
  onScheduled?: (taskId: string, context?: Record<string, unknown>) => void | Promise<void>;
  /** Called when agent is preempted (RUNNING -> SUSPENDED) */
  onPreempt?: (reason: string, context?: Record<string, unknown>) => void | Promise<void>;
  /** Called when agent resumes (RESUMED -> RUNNING) */
  onResume?: (context?: Record<string, unknown>) => void | Promise<void>;
  /** Called when agent starts waiting (RUNNING -> WAITING) */
  onWait?: (reason: string, context?: Record<string, unknown>) => void | Promise<void>;
  /** Called when agent waits for resources (RUNNING -> WAITING_RESOURCES) */
  onWaitResources?: (
    resources: string[],
    context?: Record<string, unknown>
  ) => void | Promise<void>;
  /** Called when task completes (RUNNING -> COMPLETED) */
  onComplete?: (result?: unknown, context?: Record<string, unknown>) => void | Promise<void>;
  /** Called when agent fails (any -> FAILED) */
  onFail?: (error: Error, context?: Record<string, unknown>) => void | Promise<void>;
  /** Called when shutdown starts (RUNNING -> SHUTTING_DOWN) */
  onShutdown?: (gracePeriodMs: number, context?: Record<string, unknown>) => void | Promise<void>;
  /** Called when recovery starts (FAILED -> RECOVERING) */
  onRecover?: (context?: Record<string, unknown>) => void | Promise<void>;
}

/**
 * Agent state machine implementation.
 *
 * Manages agent lifecycle state transitions with validation and lifecycle hooks.
 */
export class AgentStateMachine {
  private state: AgentState = AgentState.AGENT_STATE_UNSPECIFIED;
  private hooks: AgentLifecycleHooks;
  private stateHistory: Array<{
    state: AgentState;
    timestamp: string;
    context?: Record<string, unknown>;
  }> = [];

  /**
   * Create a new agent state machine.
   *
   * @param hooks - Optional lifecycle hooks
   */
  constructor(hooks?: AgentLifecycleHooks) {
    this.hooks = hooks || {};
  }

  /**
   * Get the current state.
   *
   * @returns The current agent state
   */
  getState(): AgentState {
    return this.state;
  }

  /**
   * Get the state history.
   *
   * @returns Array of state transitions with timestamps
   */
  getStateHistory(): Array<{
    state: AgentState;
    timestamp: string;
    context?: Record<string, unknown>;
  }> {
    return [...this.stateHistory];
  }

  /**
   * Initialize the agent (transition to INITIALIZING).
   *
   * @throws StateTransitionError if already initialized
   */
  async initialize(): Promise<void> {
    if (this.state !== AgentState.AGENT_STATE_UNSPECIFIED) {
      throw new StateTransitionError(this.state, AgentState.INITIALIZING);
    }
    await this.transitionTo(AgentState.INITIALIZING);
  }

  /**
   * Transition to a new state.
   *
   * @param toState - The target state
   * @param context - Optional context for the transition
   * @throws StateTransitionError if the transition is invalid
   */
  async transitionTo(
    toState: AgentState,
    context?: Record<string, unknown>
  ): Promise<void> {
    // Special case: initial transition from UNSPECIFIED
    if (
      this.state === AgentState.AGENT_STATE_UNSPECIFIED &&
      toState === AgentState.INITIALIZING
    ) {
      await this.doTransition(toState, context);
      return;
    }

    if (!isValidTransition(this.state, toState)) {
      throw new StateTransitionError(this.state, toState);
    }

    await this.doTransition(toState, context);
  }

  /**
   * Perform the state transition and call hooks.
   */
  private async doTransition(
    toState: AgentState,
    context?: Record<string, unknown>
  ): Promise<void> {
    const fromState = this.state;
    this.state = toState;

    // Record in history
    this.stateHistory.push({
      state: toState,
      timestamp: new Date().toISOString(),
      context,
    });

    // Call generic state change hook
    if (this.hooks.onStateChange) {
      await this.hooks.onStateChange(fromState, toState, context);
    }

    // Call specific hooks based on transition
    await this.callSpecificHooks(fromState, toState, context);
  }

  /**
   * Call specific lifecycle hooks based on the transition.
   */
  private async callSpecificHooks(
    fromState: AgentState,
    toState: AgentState,
    context?: Record<string, unknown>
  ): Promise<void> {
    switch (toState) {
      case AgentState.SCHEDULED:
        if (this.hooks.onScheduled) {
          const taskId = (context?.taskId as string) || 'unknown';
          await this.hooks.onScheduled(taskId, context);
        }
        break;

      case AgentState.SUSPENDED:
        if (fromState === AgentState.RUNNING && this.hooks.onPreempt) {
          const reason = (context?.reason as string) || 'preemption';
          await this.hooks.onPreempt(reason, context);
        }
        break;

      case AgentState.RUNNING:
        if (fromState === AgentState.RESUMED && this.hooks.onResume) {
          await this.hooks.onResume(context);
        }
        break;

      case AgentState.WAITING:
        if (this.hooks.onWait) {
          const reason = (context?.reason as string) || 'waiting';
          await this.hooks.onWait(reason, context);
        }
        break;

      case AgentState.WAITING_RESOURCES:
        if (this.hooks.onWaitResources) {
          const resources = (context?.resources as string[]) || [];
          await this.hooks.onWaitResources(resources, context);
        }
        break;

      case AgentState.COMPLETED:
        if (this.hooks.onComplete) {
          await this.hooks.onComplete(context?.result, context);
        }
        break;

      case AgentState.FAILED:
        if (this.hooks.onFail) {
          const error =
            (context?.error as Error) || new Error('Unknown failure');
          await this.hooks.onFail(error, context);
        }
        break;

      case AgentState.SHUTTING_DOWN:
        if (this.hooks.onShutdown) {
          const gracePeriodMs = (context?.gracePeriodMs as number) || 30000;
          await this.hooks.onShutdown(gracePeriodMs, context);
        }
        break;

      case AgentState.RECOVERING:
        if (this.hooks.onRecover) {
          await this.hooks.onRecover(context);
        }
        break;
    }
  }

  /**
   * Check if the agent can transition to a given state.
   *
   * @param toState - The target state
   * @returns True if the transition is valid
   */
  canTransitionTo(toState: AgentState): boolean {
    if (
      this.state === AgentState.AGENT_STATE_UNSPECIFIED &&
      toState === AgentState.INITIALIZING
    ) {
      return true;
    }
    return isValidTransition(this.state, toState);
  }

  /**
   * Get all states the agent can currently transition to.
   *
   * @returns Array of valid target states
   */
  getAvailableTransitions(): AgentState[] {
    if (this.state === AgentState.AGENT_STATE_UNSPECIFIED) {
      return [AgentState.INITIALIZING];
    }
    return getValidTransitions(this.state);
  }

  /**
   * Check if the agent is in a terminal state.
   *
   * Terminal states are states where the agent cannot make further
   * progress without external intervention.
   *
   * @returns True if in a terminal state
   */
  isTerminal(): boolean {
    // FAILED without recovery and SHUTTING_DOWN after timeout are terminal
    // But FAILED can transition to RECOVERING, so check the actual transitions
    return getValidTransitions(this.state).length === 0;
  }

  /**
   * Check if the agent is in an active state (executing work).
   *
   * @returns True if the agent is actively working
   */
  isActive(): boolean {
    return (
      this.state === AgentState.RUNNING ||
      this.state === AgentState.SCHEDULED ||
      this.state === AgentState.RESUMED
    );
  }

  /**
   * Check if the agent is in a waiting state.
   *
   * @returns True if the agent is waiting
   */
  isWaiting(): boolean {
    return (
      this.state === AgentState.WAITING ||
      this.state === AgentState.WAITING_RESOURCES
    );
  }

  /**
   * Check if the agent is in a suspended or shutdown state.
   *
   * @returns True if the agent is suspended or shutting down
   */
  isSuspendedOrShuttingDown(): boolean {
    return (
      this.state === AgentState.SUSPENDED ||
      this.state === AgentState.SHUTTING_DOWN
    );
  }

  /**
   * Update lifecycle hooks.
   *
   * @param hooks - New hooks to merge with existing hooks
   */
  setHooks(hooks: Partial<AgentLifecycleHooks>): void {
    this.hooks = { ...this.hooks, ...hooks };
  }

  /**
   * Reset the state machine to uninitialized state.
   *
   * This is primarily for testing purposes.
   */
  reset(): void {
    this.state = AgentState.AGENT_STATE_UNSPECIFIED;
    this.stateHistory = [];
  }
}
