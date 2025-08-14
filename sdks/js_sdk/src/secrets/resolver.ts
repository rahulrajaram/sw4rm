import type { SecretsBackend } from './backend.js'
import { Scope, SecretKey, SecretSource } from './types.js'
import { SecretNotFound } from './errors.js'

export class Resolver<B extends SecretsBackend> {
  constructor(private readonly backend: B, private readonly env: Record<string, string> = process.env as any) {}

  async resolve(key: SecretKey, scope: Scope, opts?: { explicit?: string | null; envVar?: string | null }): Promise<[string, SecretSource]> {
    const explicit = opts?.explicit ?? null
    const envVar = opts?.envVar ?? null
    if (explicit !== null) return [explicit, SecretSource.CLI]
    if (envVar && this.env[envVar] && this.env[envVar] !== '') return [this.env[envVar], SecretSource.ENV]
    try {
      const v = await this.backend.get(scope, key)
      return [v, scope.isGlobal ? SecretSource.GLOBAL : SecretSource.SCOPED]
    } catch (e) {}
    if (!scope.isGlobal) {
      const v = await this.backend.get(new Scope(null), key)
      return [v, SecretSource.GLOBAL]
    }
    throw new SecretNotFound(scope.label(), key.key)
  }
}
