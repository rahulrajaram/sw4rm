/**
 * Secrets Management Example for SW4RM JS SDK.
 *
 * This example demonstrates:
 * - Backend selection (auto, file, keyring)
 * - Storing and retrieving scoped and global secrets
 * - Resolver precedence: explicit > env > scoped > global
 * - Error handling for missing secrets
 * - Listing all secrets
 *
 * Prerequisites:
 *   - Build the SDK: `npm run build`
 *
 * Run:
 *   npx ts-node examples/secretsExample.ts
 */

import * as fs from 'node:fs'
import * as os from 'node:os'
import * as path from 'node:path'

import {
  FileBackend,
  Resolver,
  Scope,
  SecretKey,
  SecretNotFound,
  Secrets,
  SecretValue,
  selectBackend,
} from '../src/index.js'

// ---------------------------------------------------------------------------
// Scenario 1: Backend Selection
// ---------------------------------------------------------------------------

async function demoBackendSelection(): Promise<void> {
  console.log('\n' + '='.repeat(60))
  console.log('SCENARIO 1: Backend Selection')
  console.log('='.repeat(60))

  // File backend — always available, no system keyring required
  const [, nameFile] = await selectBackend('file')
  console.log(`\n  Explicit file backend: ${nameFile}`)

  // Auto selection — prefers keyring when available, falls back to file
  const [, nameAuto] = await selectBackend('auto')
  console.log(`  Auto-selected backend: ${nameAuto}`)

  console.log('\n  Backend modes: auto, file, keyring')
  console.log('  Env override: SW4RM_SECRETS_BACKEND=file')
}

// ---------------------------------------------------------------------------
// Scenario 2: Store and Retrieve Secrets
// ---------------------------------------------------------------------------

async function demoStoreAndRetrieve(): Promise<void> {
  console.log('\n' + '='.repeat(60))
  console.log('SCENARIO 2: Store and Retrieve Secrets')
  console.log('='.repeat(60))

  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'sw4rm-secrets-'))
  try {
    const backend = new FileBackend(path.join(tmpDir, 'secrets.json'))
    const store = new Secrets(backend)

    // Global scope — shared across all agents
    const globalScope = new Scope(null)
    // Agent-specific scope
    const agentScope = new Scope('agent-alpha')

    // Store global API key
    await store.set(globalScope, new SecretKey('api_key'), new SecretValue('sk-global-abc123'))
    console.log('\n  Stored global secret: api_key')

    // Store agent-scoped override
    await store.set(agentScope, new SecretKey('api_key'), new SecretValue('sk-agent-xyz789'))
    console.log('  Stored scoped secret: agent-alpha/api_key')

    // Store agent-specific secret
    await store.set(agentScope, new SecretKey('db_password'), new SecretValue('pg-secret-42'))
    console.log('  Stored scoped secret: agent-alpha/db_password')

    // Retrieve global
    const val = await store.get(globalScope, new SecretKey('api_key'))
    console.log(`\n  Global api_key:   ${val}`)

    // Retrieve scoped (returns the agent's own override, not the global value)
    const valScoped = await store.get(agentScope, new SecretKey('api_key'))
    console.log(`  Scoped api_key:   ${valScoped}`)

    // Retrieve agent-only secret
    const valDb = await store.get(agentScope, new SecretKey('db_password'))
    console.log(`  Scoped db_password: ${valDb}`)
  } finally {
    fs.rmSync(tmpDir, { recursive: true, force: true })
  }
}

// ---------------------------------------------------------------------------
// Scenario 3: Resolver Precedence
// ---------------------------------------------------------------------------

async function demoResolverPrecedence(): Promise<void> {
  console.log('\n' + '='.repeat(60))
  console.log('SCENARIO 3: Resolver Precedence')
  console.log('='.repeat(60))

  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'sw4rm-secrets-'))
  try {
    const backend = new FileBackend(path.join(tmpDir, 'secrets.json'))
    const store = new Secrets(backend)

    const globalScope = new Scope(null)
    const agentScope = new Scope('agent-beta')

    // Seed the store with both a global and a scoped value
    await store.set(globalScope, new SecretKey('token'), new SecretValue('global-token'))
    await store.set(agentScope, new SecretKey('token'), new SecretValue('scoped-token'))

    // Use a controlled env dictionary rather than the real process.env
    const fakeEnv: Record<string, string> = { SW4RM_TOKEN: 'env-token' }
    const resolver = new Resolver(backend, fakeEnv)

    const key = new SecretKey('token')

    // Level 1: Explicit value wins over everything
    const [val1, src1] = await resolver.resolve(key, agentScope, {
      explicit: 'cli-token',
      envVar: 'SW4RM_TOKEN',
    })
    console.log(`\n  1. Explicit provided:  value=${val1}, source=${src1}`)

    // Level 2: Env var (no explicit supplied)
    const [val2, src2] = await resolver.resolve(key, agentScope, { envVar: 'SW4RM_TOKEN' })
    console.log(`  2. Env var fallback:   value=${val2}, source=${src2}`)

    // Level 3: Scoped secret (no explicit, no env var match)
    const [val3, src3] = await resolver.resolve(key, agentScope)
    console.log(`  3. Scoped fallback:    value=${val3}, source=${src3}`)

    // Level 4: Global secret (scope has no override, falls through to global)
    const otherScope = new Scope('agent-gamma')
    const [val4, src4] = await resolver.resolve(key, otherScope)
    console.log(`  4. Global fallback:    value=${val4}, source=${src4}`)

    console.log('\n  Precedence: explicit > env > scoped > global')
  } finally {
    fs.rmSync(tmpDir, { recursive: true, force: true })
  }
}

// ---------------------------------------------------------------------------
// Scenario 4: Error Handling
// ---------------------------------------------------------------------------

async function demoErrorHandling(): Promise<void> {
  console.log('\n' + '='.repeat(60))
  console.log('SCENARIO 4: Error Handling')
  console.log('='.repeat(60))

  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'sw4rm-secrets-'))
  try {
    const backend = new FileBackend(path.join(tmpDir, 'secrets.json'))
    const store = new Secrets(backend)

    // Attempt to retrieve a secret that was never stored
    try {
      await store.get(new Scope(null), new SecretKey('nonexistent'))
    } catch (err) {
      if (err instanceof SecretNotFound) {
        console.log(`\n  SecretNotFound: ${err.message}`)
      } else {
        throw err
      }
    }

    // Resolver with no env and empty store — no fallback chain can satisfy it
    const resolver = new Resolver(backend, {})
    try {
      await resolver.resolve(new SecretKey('missing'), new Scope('test'))
    } catch (err) {
      if (err instanceof SecretNotFound) {
        console.log(`  Resolver SecretNotFound: ${err.message}`)
      } else {
        throw err
      }
    }

    console.log('\n  Missing secrets raise SecretNotFound with scope and key info')
  } finally {
    fs.rmSync(tmpDir, { recursive: true, force: true })
  }
}

// ---------------------------------------------------------------------------
// Scenario 5: Listing Secrets
// ---------------------------------------------------------------------------

async function demoListing(): Promise<void> {
  console.log('\n' + '='.repeat(60))
  console.log('SCENARIO 5: Listing Secrets')
  console.log('='.repeat(60))

  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'sw4rm-secrets-'))
  try {
    const backend = new FileBackend(path.join(tmpDir, 'secrets.json'))
    const store = new Secrets(backend)

    // Store a variety of secrets across multiple scopes
    await store.set(new Scope(null), new SecretKey('global_a'), new SecretValue('val_a'))
    await store.set(new Scope(null), new SecretKey('global_b'), new SecretValue('val_b'))
    await store.set(new Scope('team-x'), new SecretKey('team_secret'), new SecretValue('val_c'))
    await store.set(new Scope('team-y'), new SecretKey('team_secret'), new SecretValue('val_d'))

    // List all secrets across every scope
    const allSecrets = await store.list()
    console.log(`\n  Total secrets stored: ${allSecrets.size}`)

    // Sort entries for deterministic output: null (global) sorts before named scopes
    const entries = [...allSecrets.entries()].sort(([a], [b]) => {
      const scopeA = a[0] ?? ''
      const scopeB = b[0] ?? ''
      if (scopeA !== scopeB) return scopeA < scopeB ? -1 : 1
      return a[1] < b[1] ? -1 : 1
    })
    for (const [[scopeName, key], value] of entries) {
      const scopeLabel = scopeName ?? '(global)'
      console.log(`    ${scopeLabel.padEnd(15)} / ${key.padEnd(15)} = ${value}`)
    }

    // List restricted to a single scope
    const globalOnly = await store.list(new Scope(null))
    console.log(`\n  Global scope only: ${globalOnly.size} secret(s)`)

    const teamX = await store.list(new Scope('team-x'))
    console.log(`  team-x scope only: ${teamX.size} secret(s)`)
  } finally {
    fs.rmSync(tmpDir, { recursive: true, force: true })
  }
}

// ---------------------------------------------------------------------------
// Main entry point
// ---------------------------------------------------------------------------

async function main(): Promise<void> {
  console.log('\nSW4RM Secrets Management Example')
  console.log('='.repeat(60))
  console.log('This demonstrates scoped secret storage, resolution, and listing\n')

  await demoBackendSelection()
  await demoStoreAndRetrieve()
  await demoResolverPrecedence()
  await demoErrorHandling()
  await demoListing()

  console.log('\n' + '='.repeat(60))
  console.log('ALL SECRETS SCENARIOS COMPLETED')
  console.log('='.repeat(60))
  console.log('\nKey takeaways:')
  console.log('1. Use selectBackend() for auto/file/keyring selection')
  console.log("2. new Scope(null) = global, new Scope('name') = agent-specific")
  console.log('3. Resolver follows: explicit > env > scoped > global')
  console.log('4. SecretNotFound raised when no fallback exists')
  console.log('5. list() returns all secrets, optionally filtered by scope')
}

main().catch((err) => {
  console.error('Fatal error:', err)
  process.exit(1)
})
