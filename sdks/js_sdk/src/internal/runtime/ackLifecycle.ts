// ACK lifecycle helper per spec §11

export enum AckStage {
  ACK_STAGE_UNSPECIFIED = 0,
  RECEIVED = 1,
  READ = 2,
  FULFILLED = 3,
  REJECTED = 4,
  FAILED = 5,
  TIMED_OUT = 6,
}

export interface AckState {
  messageId: string;
  stage: AckStage;
  lastUpdateIso: string;
  note?: string;
  errorCode?: number;
}

export class ACKLifecycleManager {
  private acks = new Map<string, AckState>();

  mark(messageId: string, stage: AckStage, note?: string, errorCode?: number) {
    const st: AckState = {
      messageId,
      stage,
      lastUpdateIso: new Date().toISOString(),
      note,
      errorCode,
    };
    this.acks.set(messageId, st);
  }

  get(messageId: string): AckState | undefined {
    return this.acks.get(messageId);
  }

  recent(limit = 100): AckState[] {
    const arr = [...this.acks.values()].sort((a, b) => a.lastUpdateIso.localeCompare(b.lastUpdateIso));
    return arr.slice(Math.max(0, arr.length - limit));
  }

  reconcileLateAck(messageId: string, stage: AckStage) {
    const curr = this.acks.get(messageId);
    if (!curr || curr.stage === stage) return;
    // Update to reflect late ACK arrival
    this.mark(messageId, stage, 'late_ack_reconciled');
  }

  toJSON(): AckState[] {
    return [...this.acks.values()].sort((a, b) => a.lastUpdateIso.localeCompare(b.lastUpdateIso));
  }

  fromJSON(states: AckState[]) {
    this.acks.clear();
    for (const s of states) this.acks.set(s.messageId, s);
  }
}
