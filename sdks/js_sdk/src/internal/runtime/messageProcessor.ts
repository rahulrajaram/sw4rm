// MessageProcessor with handler registry and basic error handling

import { AckStage, ACKLifecycleManager } from './ackLifecycle.js';

export enum MessageType {
  MESSAGE_TYPE_UNSPECIFIED = 0,
  CONTROL = 1,
  DATA = 2,
  HEARTBEAT = 3,
  NOTIFICATION = 4,
  ACKNOWLEDGEMENT = 5,
  HITL_INVOCATION = 6,
  WORKTREE_CONTROL = 7,
  NEGOTIATION = 8,
  TOOL_CALL = 9,
  TOOL_RESULT = 10,
  TOOL_ERROR = 11,
}

export interface EnvelopeLike {
  message_id: string;
  message_type: MessageType;
  correlation_id: string;
  payload?: Uint8Array;
}

type Handler = (env: EnvelopeLike) => Promise<void> | void;

export class MessageProcessor {
  private handlers = new Map<MessageType, Handler>();
  private defaultHandler?: Handler;
  private ack: ACKLifecycleManager;

  constructor(ack: ACKLifecycleManager) {
    this.ack = ack;
  }

  registerHandler(type: MessageType, handler: Handler) {
    this.handlers.set(type, handler);
  }

  setDefaultHandler(handler: Handler) {
    this.defaultHandler = handler;
  }

  async process(env: EnvelopeLike) {
    try {
      this.ack.mark(env.message_id, AckStage.RECEIVED);
      const handler = this.handlers.get(env.message_type) ?? this.defaultHandler;
      if (!handler) return; // silently drop if no handler configured
      await handler(env);
      this.ack.mark(env.message_id, AckStage.FULFILLED);
    } catch (err: any) {
      this.ack.mark(env.message_id, AckStage.FAILED, err?.message);
    }
  }
}

