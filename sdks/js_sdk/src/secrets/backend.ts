import type { Scope, SecretKey, SecretValue } from './types.js'

export interface SecretsBackend {
  set(scope: Scope, key: SecretKey, value: SecretValue): Promise<void>
  get(scope: Scope, key: SecretKey): Promise<string>
  list(scope?: Scope | null): Promise<Map<[string | null, string], string>>
}

export class Secrets<B extends SecretsBackend> {
  constructor(public readonly backend: B) {}
  set(scope: Scope, key: SecretKey, value: SecretValue) { return this.backend.set(scope, key, value) }
  get(scope: Scope, key: SecretKey) { return this.backend.get(scope, key) }
  list(scope?: Scope | null) { return this.backend.list(scope) }
}
