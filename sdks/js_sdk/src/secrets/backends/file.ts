import { mkdirSync, readFileSync, renameSync, writeFileSync, existsSync, chmodSync } from 'node:fs'
import { join, dirname } from 'node:path'
import type { SecretsBackend } from '../backend.js'
import { SecretBackendError, SecretNotFound, SecretPermissionError } from '../errors.js'
import { Scope, SecretKey, SecretValue } from '../types.js'

function defaultPath(): string {
  const isWin = process.platform === 'win32'
  if (isWin) {
    const base = process.env.APPDATA || join(process.env.USERPROFILE || '', 'AppData', 'Roaming')
    return join(base, 'sw4rm', 'secrets.json')
  }
  const xdg = process.env.XDG_CONFIG_HOME
  const base = xdg && xdg.length > 0 ? xdg : join(process.env.HOME || '', '.config')
  return join(base, 'sw4rm', 'secrets.json')
}

export class FileBackend implements SecretsBackend {
  private path: string
  constructor(path?: string) {
    this.path = path ?? defaultPath()
    mkdirSync(dirname(this.path), { recursive: true })
    try {
      chmodSync(dirname(this.path), 0o700)
    } catch {
      // Ignore permission errors on some platforms
    }
    if (!existsSync(this.path)) {
      this.safeWrite({})
      this.enforceFilePerms()
    } else {
      this.enforceFilePerms()
    }
  }

  private enforceFilePerms() {
    if (process.platform !== 'win32') {
      try { chmodSync(this.path, 0o600) } catch (e: any) { throw new SecretPermissionError(String(e)) }
    }
  }

  private safeWrite(obj: Record<string, Record<string, string>>) {
    const tmp = join(dirname(this.path), `.secrets.${Date.now()}.${Math.random().toString(16).slice(2)}`)
    try {
      writeFileSync(tmp, JSON.stringify(obj, null, 2), { encoding: 'utf8', mode: 0o600 })
      renameSync(tmp, this.path)
      this.enforceFilePerms()
    } catch (e: any) {
      throw new SecretBackendError(String(e))
    }
  }

  private load(): Record<string, Record<string, string>> {
    try {
      const s = readFileSync(this.path, { encoding: 'utf8' })
      return JSON.parse(s)
    } catch (e: any) {
      if ((e as any).code === 'ENOENT') return {}
      throw new SecretBackendError('secrets file is corrupted or unreadable')
    }
  }

  async set(scope: Scope, key: SecretKey, value: SecretValue): Promise<void> {
    const data = this.load()
    const bucket = (data[scope.label()] = data[scope.label()] || {})
    bucket[key.key] = value.value
    this.safeWrite(data)
  }

  async get(scope: Scope, key: SecretKey): Promise<string> {
    const data = this.load()
    const v = data[scope.label()]?.[key.key]
    if (v == null) throw new SecretNotFound(scope.label(), key.key)
    return v
  }

  async list(scope?: Scope | null): Promise<Map<[string | null, string], string>> {
    const data = this.load()
    const out = new Map<[string | null, string], string>()
    if (scope) {
      for (const [k, v] of Object.entries(data[scope.label()] || {})) out.set([scope.name, k], v)
      return out
    }
    for (const [s, bucket] of Object.entries(data)) {
      for (const [k, v] of Object.entries(bucket)) out.set([s === 'global' ? null : s, k], v)
    }
    return out
  }
}
