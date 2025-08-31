Release and Publish Guide

This repo ships SDKs to three registries. Each has a dedicated GitHub Actions workflow triggered by a tag:

- Python (PyPI): tag `py-vX.Y.Z`
- JavaScript (npm): tag `npm-vX.Y.Z`
- Rust (crates.io): tag `rs-vX.Y.Z`

Before tagging, bump the version in the respective manifest:

- PyPI: `pyproject.toml` → `[project].version`
- npm: `sdks/js_sdk/package.json` → `version`
- crates.io: `sdks/rust_sdk/Cargo.toml` → `[package].version`

Required GitHub Secrets (Environment: production)

- Store as Environment secrets under Settings → Environments → production → Environment secrets.
- `PYPI_API_TOKEN`: PyPI token for the project (format: `pypi-...`).
- `NPM_TOKEN`: npm Automation token with publish scope.
- `CRATES_IO_TOKEN`: crates.io API token.

Set these under: GitHub → Settings → Secrets and variables → Actions → New repository secret.

How to Release

1) Python (PyPI)
   - Update `pyproject.toml` version.
   - Build locally (optional): `python -m build && twine check dist/*`.
   - Push tag: `git tag py-vX.Y.Z && git push origin py-vX.Y.Z`.

2) JavaScript (npm)
   - Update `sdks/js_sdk/package.json` version.
   - Build locally (optional): `cd sdks/js_sdk && npm ci && npm run build`.
   - Push tag: `git tag npm-vX.Y.Z && git push origin npm-vX.Y.Z`.

3) Rust (crates.io)
   - Update `sdks/rust_sdk/Cargo.toml` version.
   - Test package (optional): `cargo package --manifest-path sdks/rust_sdk/Cargo.toml`.
   - Push tag: `git tag rs-vX.Y.Z && git push origin rs-vX.Y.Z`.

Notes

- The workflows validate that the tag version matches the file version and will fail if they differ.
- Re-publishing the same version will fail on the registry; re-tag after bumping the version.
- If you prefer publishing on GitHub Releases instead of tags, we can switch triggers to `release: published` and parse the release name.

Local Version Management

- Pre-commit hook enforces SemVer and lockstep versions (spec, Python, JS, Rust):
  - Enable hooks once: `git config core.hooksPath .githooks && chmod +x .githooks/pre-commit`.
  - If the spec/protos or an SDK changed, the hook requires a version bump.
- Bump all versions in one go: `python scripts/bump_version.py X.Y.Z [--stage]`.
- Create tags (publish happens in Actions):
  - One SDK: `python scripts/release.py [py|npm|rs] X.Y.Z --push`
  - All SDKs: `python scripts/release_all.py X.Y.Z --push`

Environments

- Publish jobs run under the `production` environment for auditability and isolated secrets.
- Add optional protection rules (required reviewers, branch/tag allowlist, wait timer) under Settings → Environments → production.
