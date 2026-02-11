// Worktree binding state machine per spec section 16.
//
// States: UNBOUND -> BOUND_HOME -> SWITCH_PENDING -> BOUND_NON_HOME
// Error: BIND_FAILED (transient)

export type WorktreeState = 'UNBOUND' | 'BOUND_HOME' | 'SWITCH_PENDING' | 'BOUND_NON_HOME' | 'BIND_FAILED';

/**
 * Valid worktree state transitions per spec §16.2.
 */
const VALID_WORKTREE_TRANSITIONS: Record<WorktreeState, WorktreeState[]> = {
  UNBOUND: ['BOUND_HOME', 'BIND_FAILED'],
  BOUND_HOME: ['SWITCH_PENDING', 'UNBOUND'],
  SWITCH_PENDING: ['BOUND_NON_HOME', 'BOUND_HOME'], // approve or reject
  BOUND_NON_HOME: ['BOUND_HOME', 'UNBOUND'], // TTL expired/revoke, or unbind
  BIND_FAILED: ['UNBOUND', 'BOUND_HOME'], // retry reset or successful retry
};

/**
 * Check if a worktree state transition is valid.
 */
export function isValidWorktreeTransition(from: WorktreeState, to: WorktreeState): boolean {
  return VALID_WORKTREE_TRANSITIONS[from]?.includes(to) ?? false;
}

export class WorktreeTransitionError extends Error {
  readonly fromState: WorktreeState;
  readonly toState: WorktreeState;

  constructor(from: WorktreeState, to: WorktreeState) {
    super(`Invalid worktree state transition from ${from} to ${to}`);
    this.name = 'WorktreeTransitionError';
    this.fromState = from;
    this.toState = to;
  }
}

/**
 * Persistent worktree state machine with full spec §16 support.
 *
 * Supports SWITCH_PENDING approval flow with TTL on BOUND_NON_HOME.
 */
export class PersistentWorktreeState {
  private state: WorktreeState = 'UNBOUND';
  private repoId?: string;
  private worktreeId?: string;
  private homeRepoId?: string;
  private homeWorktreeId?: string;
  private switchTtlMs?: number;
  private switchTimer?: ReturnType<typeof setTimeout>;

  /**
   * Transition to a new state with validation.
   * @throws WorktreeTransitionError if transition is invalid
   */
  private transitionTo(newState: WorktreeState): void {
    if (!isValidWorktreeTransition(this.state, newState)) {
      throw new WorktreeTransitionError(this.state, newState);
    }
    this.state = newState;
  }

  /**
   * Bind to a home worktree (UNBOUND -> BOUND_HOME or BIND_FAILED -> BOUND_HOME).
   */
  bind(repoId: string, worktreeId: string): void {
    this.transitionTo('BOUND_HOME');
    this.repoId = repoId;
    this.worktreeId = worktreeId;
    this.homeRepoId = repoId;
    this.homeWorktreeId = worktreeId;
  }

  /**
   * Handle bind failure (UNBOUND -> BIND_FAILED).
   */
  bindFailed(): void {
    this.transitionTo('BIND_FAILED');
  }

  /**
   * Unbind from current worktree.
   */
  unbind(): void {
    this.clearSwitchTimer();
    this.transitionTo('UNBOUND');
    this.repoId = undefined;
    this.worktreeId = undefined;
  }

  /**
   * Request switch to a non-home worktree (BOUND_HOME -> SWITCH_PENDING).
   * Requires approval or rejection before taking effect.
   */
  requestSwitch(targetRepoId: string, targetWorktreeId: string): void {
    this.transitionTo('SWITCH_PENDING');
    // Store target - will be applied on approve
    (this as any)._pendingRepoId = targetRepoId;
    (this as any)._pendingWorktreeId = targetWorktreeId;
  }

  /**
   * Approve a pending switch (SWITCH_PENDING -> BOUND_NON_HOME).
   * @param ttlMs - Time-to-live in milliseconds before auto-reverting to BOUND_HOME
   */
  approveSwitch(ttlMs = 300000): void {
    this.transitionTo('BOUND_NON_HOME');
    this.repoId = (this as any)._pendingRepoId;
    this.worktreeId = (this as any)._pendingWorktreeId;
    this.switchTtlMs = ttlMs;

    // Set up TTL auto-revert
    this.clearSwitchTimer();
    this.switchTimer = setTimeout(() => {
      this.revertToHome();
    }, ttlMs);
  }

  /**
   * Reject a pending switch (SWITCH_PENDING -> BOUND_HOME).
   */
  rejectSwitch(): void {
    this.transitionTo('BOUND_HOME');
    this.repoId = this.homeRepoId;
    this.worktreeId = this.homeWorktreeId;
    delete (this as any)._pendingRepoId;
    delete (this as any)._pendingWorktreeId;
  }

  /**
   * Revert from non-home to home worktree (BOUND_NON_HOME -> BOUND_HOME).
   * Called on TTL expiry or explicit revoke.
   */
  revertToHome(): void {
    this.clearSwitchTimer();
    if (this.state === 'BOUND_NON_HOME') {
      this.transitionTo('BOUND_HOME');
      this.repoId = this.homeRepoId;
      this.worktreeId = this.homeWorktreeId;
    }
  }

  /**
   * Reset from BIND_FAILED to UNBOUND for retry.
   */
  resetFromFailed(): void {
    this.transitionTo('UNBOUND');
  }

  private clearSwitchTimer(): void {
    if (this.switchTimer) {
      clearTimeout(this.switchTimer);
      this.switchTimer = undefined;
    }
  }

  setState(state: WorktreeState): void {
    this.state = state;
  }

  current() {
    return {
      state: this.state,
      repo_id: this.repoId,
      worktree_id: this.worktreeId,
      home_repo_id: this.homeRepoId,
      home_worktree_id: this.homeWorktreeId,
      switch_ttl_ms: this.switchTtlMs,
    };
  }
}
