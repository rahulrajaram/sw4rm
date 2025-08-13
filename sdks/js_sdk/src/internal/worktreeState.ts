// In-memory Worktree state; persistence backends to be added later

export type WorktreeState = 'UNBOUND' | 'BOUND_HOME' | 'SWITCH_PENDING' | 'BOUND_NON_HOME' | 'BIND_FAILED';

export class PersistentWorktreeState {
  private state: WorktreeState = 'UNBOUND';
  private repoId?: string;
  private worktreeId?: string;

  bind(repoId: string, worktreeId: string) {
    this.repoId = repoId;
    this.worktreeId = worktreeId;
    this.state = 'BOUND_HOME';
  }

  unbind() {
    this.repoId = undefined;
    this.worktreeId = undefined;
    this.state = 'UNBOUND';
  }

  setState(state: WorktreeState) {
    this.state = state;
  }

  current() {
    return { state: this.state, repo_id: this.repoId, worktree_id: this.worktreeId };
  }
}

