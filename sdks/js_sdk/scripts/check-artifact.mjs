// Exercise the distributable layout without falling back to monorepo sources.
import assert from 'node:assert/strict';
import { cpSync, mkdtempSync, readFileSync, rmSync, symlinkSync } from 'node:fs';
import { createRequire } from 'node:module';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const root = fileURLToPath(new URL('..', import.meta.url));
const isolated = mkdtempSync(path.join(tmpdir(), 'sw4rm-package-'));
try {
  for (const entry of ['package.json', 'dist', 'protos']) {
    cpSync(path.join(root, entry), path.join(isolated, entry), { recursive: true });
  }
  // Reuse declared, already-installed dependencies; no package installation.
  symlinkSync(path.join(root, 'node_modules'), path.join(isolated, 'node_modules'), 'dir');
  const manifest = JSON.parse(readFileSync(path.join(isolated, 'package.json'), 'utf8'));
  const require = createRequire(path.join(isolated, 'package.json'));
  const esm = await import(pathToFileURL(path.join(isolated, manifest.exports['.'].import)).href);
  const cjs = require(path.join(isolated, manifest.exports['.'].require));
  for (const [format, sdk] of [['ESM', esm], ['CommonJS', cjs]]) {
    assert.equal(sdk.version, manifest.version);
    const router = new sdk.RouterClient({ address: '127.0.0.1:1' });
    assert.equal(typeof router.ackDelivery, 'function');
    // Construction loads every packaged schema. Inspect the actual RPC binding.
    assert.equal(typeof router.client.AckDelivery, 'function');
    router.client.close();
    const protocol = new sdk.ProtocolClient({ address: '127.0.0.1:1' });
    for (const [rpc, definition] of Object.entries(sdk.protocolMethods)) {
      const { client, method } = protocol.resolve(rpc, definition.serverStreaming);
      assert.equal(typeof client[method], 'function', rpc);
    }
    protocol.close();
    console.log(`${format} package import, ACK and ${Object.keys(sdk.protocolMethods).length} RPC bindings passed`);
  }
} finally {
  rmSync(isolated, { recursive: true, force: true });
}
