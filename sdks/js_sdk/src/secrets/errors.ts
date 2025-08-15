export class SecretError extends Error {}
export class SecretNotFound extends SecretError {
  constructor(public readonly scope: string, public readonly key: string) {
    super(`secret not found: scope=${scope} key=${key}`)
  }
}
export class SecretBackendError extends SecretError {}
export class SecretPermissionError extends SecretError {}
export class SecretValidationError extends SecretError {}
