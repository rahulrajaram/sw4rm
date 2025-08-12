export interface WorktreePolicyContext {
  agent_id: string;
  current_state: string;
  target_worktree_id?: string;
}

export interface WorktreePolicyHook {
  canBind(ctx: WorktreePolicyContext, repoId: string, worktreeId: string): boolean;
  canUnbind(ctx: WorktreePolicyContext): boolean;
  canSwitch(ctx: WorktreePolicyContext): boolean;
}

export class DefaultWorktreePolicy implements WorktreePolicyHook {
  canBind(): boolean { return true; }
  canUnbind(): boolean { return true; }
  canSwitch(): boolean { return true; }
}

