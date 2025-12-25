#!/usr/bin/env tsx
// moved to agents/

// Prompter for JS demo: send CONTROL seed/run messages to scheduler.

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import yargs from 'yargs/yargs';
import { hideBin } from 'yargs/helpers';

import { RouterClient, buildEnvelope, MessageType } from '../../../../sdks/js_sdk/src/index.ts';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

async function main() {
  const argv = await yargs(hideBin(process.argv))
    .option('file', { type: 'string', demandOption: true, describe: 'Path to plan or run file' })
    .strict()
    .parse();

  const filePath = path.resolve(String(argv.file));
  if (!fs.existsSync(filePath)) {
    console.error('file not found:', filePath);
    process.exit(2);
  }

  const ROUTER_HOST = process.env.ROUTER_HOST || 'localhost';
  const ROUTER_PORT = Number(process.env.ROUTER_PORT || '50051');
  const router = new RouterClient({ address: `${ROUTER_HOST}:${ROUTER_PORT}` });

  const raw = fs.readFileSync(filePath, 'utf8');
  let obj: any | null = null;
  try { obj = JSON.parse(raw); } catch {}

  let payload: Buffer;
  if (obj && typeof obj === 'object' && (obj.to === undefined || obj.to === 'scheduler') && obj.stage === 'run') {
    payload = Buffer.from(raw, 'utf8');
  } else {
    payload = Buffer.from(JSON.stringify({
      schema_version: 1,
      to: 'scheduler',
      stage: 'prompt',
      params: { prompt: raw },
    }), 'utf8');
  }

  const env = buildEnvelope({
    producer_id: 'prompter',
    message_type: MessageType.CONTROL,
    content_type: 'application/vnd.sw4rm.scheduler.command+json;v=1',
    payload,
  });
  try {
    const res = await router.sendMessage(env);
    console.log('accepted=', res.accepted, 'reason=', res.reason || '');
    process.exit(res.accepted ? 0 : 1);
  } catch (e: any) {
    console.error('send failed:', e?.message || e);
    process.exit(1);
  }
}

main();
