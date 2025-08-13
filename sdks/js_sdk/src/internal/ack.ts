import { EnvelopeBuilt, MessageType, buildEnvelope } from './envelope.js';

export interface AckPayload {
  ack_for_message_id: string;
  ack_stage: number; // AckStage enum numeric value
  error_code?: number;
  note?: string;
}

export function buildAckEnvelope(params: {
  producer_id: string;
  correlation_id?: string;
  ack: AckPayload;
  content_type?: 'application/json';
}): EnvelopeBuilt {
  const payloadBytes = new TextEncoder().encode(JSON.stringify(params.ack));
  return buildEnvelope({
    producer_id: params.producer_id,
    correlation_id: params.correlation_id,
    message_type: MessageType.ACKNOWLEDGEMENT,
    content_type: params.content_type ?? 'application/json',
    payload: payloadBytes,
  });
}

