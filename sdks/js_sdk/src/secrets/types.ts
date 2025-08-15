export enum SecretSource {
  CLI = 'cli',
  ENV = 'env',
  SCOPED = 'scoped',
  GLOBAL = 'global',
}

export class Scope {
  constructor(public readonly name: string | null = null) {}
  get isGlobal(): boolean { return this.name === null }
  label(): string { return this.name ?? 'global' }
}

export class SecretKey {
  constructor(public readonly key: string) {
    if (!key || key.split('.').some((p) => p.trim() === '')) {
      throw new Error('secret key must be dotted identifiers without empty segments')
    }
  }
}

export class SecretValue {
  static MAX_LEN = 8 * 1024
  constructor(public readonly value: string) {
    if (value.length > SecretValue.MAX_LEN) {
      throw new Error('secret value exceeds maximum allowed length (8KB)')
    }
  }
}
