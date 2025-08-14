import type { SecretsBackend } from '../backend.js'
import { SecretBackendError, SecretNotFound } from '../errors.js'
import { Scope, SecretKey, SecretValue } from '../types.js'

export class KeyringBackend implements SecretsBackend {
  private keytar: any
  private servicePrefix: string

  constructor(servicePrefix = 'sw4rm') {
    this.servicePrefix = servicePrefix
  }

  private async ensureKeytar() {
    if (!this.keytar) {
      try {
        const mod = await import('keytar')
        this.keytar = mod.default ?? mod
      } catch (e: any) {
        throw new SecretBackendError("keyring backend unavailable; install 'keytar' package or use file backend")
      }
    }
  }

  private service(scope: Scope) { return `${this.servicePrefix}:${scope.label()}` }

  async set(scope: Scope, key: SecretKey, value: SecretValue): Promise<void> {
    await this.ensureKeytar()
    await this.keytar.setPassword(this.service(scope), key.key, value.value)
  }

  async get(scope: Scope, key: SecretKey): Promise<string> {
    await this.ensureKeytar()
    const v = await this.keytar.getPassword(this.service(scope), key.key)
    if (v == null) throw new SecretNotFound(scope.label(), key.key)
    return v
  }

  async list(): Promise<Map<[string | null, string], string>> {
    // Keytar does not support listing safely; return empty.
    return new Map()
  }
}
