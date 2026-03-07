# SW4RM Agentic Protocol Documentation

This directory contains the documentation source for the SW4RM Agentic Protocol website (with sections for the reference SDKs: Python, Rust, JS/TS, Common Lisp) built with [MkDocs Material](https://squidfunk.github.io/mkdocs-material/).

## Setup

Install documentation dependencies:

```bash
pip install -e ".[docs]"
# or 
make docs-deps
```

## Development

Start the live development server:

```bash
mkdocs serve
# or
make docs-serve
```

Visit `http://localhost:8000` to view the documentation with live reloading.

## Building

Build the static site:

```bash
mkdocs build
# or  
make docs-build
```

The built site will be in the `site/` directory.

## SW4-004/SW4-005 Status Tracking

Cross-SDK implementation status for the inter-swarm extensions is tracked in:

- `documentation/protocol/extensions/index.md` (extension-level status summary)
- `artifacts/verification/` (evidence snapshots for verification claims)

When updating SW4-004 or SW4-005 docs/claims, update the extension status page and evidence snapshots together so conformance wording and parity reporting stay consistent.

## Phase Status (2026-02-15)

- **Phase 6** (`I39`-`I49`): Closed. Evidence under `artifacts/verification/`.
- **Phase 7** (`I50`-`I52`): Closed. CL gateway parity, cross-SDK conformance, testbed bootstrap.
- **Phase 8** (`I53`-`I55`): Closed. Dispatch authority reconciliation, smoke workflow, CI lockstep.
- Evidence lookup: `IMPLEMENTATION_PLAN.md` > Verification Snapshot > Evidence Index.
- Production transport runbook: `documentation/production/inter-swarm-transport-testbed.md`.
- CI smoke workflow: `.github/workflows/ci-inter-swarm-smoke-evidence.yml`.

## Verification Pipeline Runbook (Anti-Recursive Dispatch)

Use this flow to avoid recursive `yarli run` dispatch loops during tranche execution:

1. Run preflight checks before tranche verification loops:
   ```bash
   make yarli-preflight
   ```
2. Run tranche checks directly from the shell (`py-test`, `proto-check`, `docs-lint`, `docs-build`) instead of invoking `yarli run` from inside a tranche task.
3. Detect recursion by scanning tranche Verify steps and active logs for nested/self-dispatch (`yarli run`) patterns.
4. If recursion is detected, stop the inner run immediately, keep the captured logs in `artifacts/verification/`, and resume verification with direct command-family invocations.
5. For Common Lisp verification, use `make test-lisp`. If `sdks/cl_sdk` does not expose a `test` make target, the command automatically reports the caveat and runs the explicit SBCL fallback invocation.
6. Record detection/recovery and guardrail evidence in `IMPLEMENTATION_PLAN.md` before advancing to the next tranche.

## Structure

```
documentation/
├── index.md              # Homepage
├── quickstart/
│   ├── index.md          # Getting started overview
│   ├── installation.md   # Installation guide  
│   └── first-agent.md    # First agent tutorial
├── examples/
│   └── index.md          # Examples overview
├── architecture/
│   └── index.md          # Architecture overview
└── gen_ref_pages.py      # API docs generator (disabled)
```

## Deployment Options

### GitHub Pages

```bash
mkdocs gh-deploy
```

### Netlify

1. Connect your repository to Netlify
2. Set build command:
   ```bash
   mkdocs build
   ```
3. Set publish directory: `site`

### Vercel

1. Import your repository to Vercel  
2. Set build command:
   ```bash
   mkdocs build
   ```
3. Set output directory: `site`

### Docker

```dockerfile
FROM squidfunk/mkdocs-material
COPY . /docs
RUN mkdocs build
```

## Configuration

The documentation is configured in `mkdocs.yml` at the repository root. Key settings:


- **Theme**: Material Design with dark/light mode toggle
- **Plugins**: Search and section indexing
- **Extensions**: Code highlighting, diagrams, admonitions
- **Navigation**: Organized into Getting Started, Examples, and Architecture

## Writing Documentation

### Markdown Extensions

The site supports:


- **Code blocks** with syntax highlighting
- **Mermaid diagrams** for architecture visualizations  
- **Admonitions** for notes, warnings, tips
- **Tabs** for multi-option examples
- **Cards** for grid layouts

### Example Formatting

```markdown
!!! tip "Pro Tip"
    Use code blocks with language specification for syntax highlighting.

=== "Python"
    ```python
    from sw4rm.clients import RouterClient
    ```

=== "Installation"  
    ```bash
    pip install sw4rm-sdk
    ```
```

### Adding Pages


1. Create a new `.md` file in the appropriate directory
2. Add to the `nav` section in `mkdocs.yml`
3. Use relative links: `[Protocol Specification](protocol/spec.md)`

## Future Enhancements

When ready to add API documentation:


1. Uncomment the plugins in `mkdocs.yml`:
   ```yaml
   - gen-files:
       scripts: 
         - documentation/gen_ref_pages.py
   - mkdocstrings[python]
   ```

2. Add API reference to navigation:
   ```yaml  
   - API Reference: reference/
   ```

This will auto-generate API docs from docstrings in the Python code.
