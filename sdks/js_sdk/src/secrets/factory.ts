import { FileBackend } from './backends/file.js'
import { KeyringBackend } from './backends/keyring.js'
import type { SecretsBackend } from './backend.js'

export type BackendMode = 'auto' | 'file' | 'keyring'

function fromEnv(): BackendMode {
  const v = (process.env.SW4RM_SECRETS_BACKEND || 'auto').toLowerCase()
  if (v === 'file' || v === 'keyring') return v
  return 'auto'
}

export async function selectBackend(mode?: BackendMode): Promise<[SecretsBackend, string]> {
  const m = mode ?? fromEnv()
  if (m === 'file') return [new FileBackend(), 'file']
  if (m === 'keyring') return [new KeyringBackend(), 'keyring']
  // auto
  if (process.env.CI) return [new FileBackend(), 'file']
  try {
    // Resolve keytar quickly to decide; KeyringBackend lazily imports anyway
    await import('keytar')
    return [new KeyringBackend(), 'keyring']
  } catch {
    return [new FileBackend(), 'file']
  }
}
