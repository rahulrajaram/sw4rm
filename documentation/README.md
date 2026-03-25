# SW4RM Agentic Protocol Documentation

This directory contains the MkDocs source for the SW4RM Agentic Protocol website built with [MkDocs Material](https://squidfunk.github.io/mkdocs-material/).

Public-facing docs treat Python as the reference SDK and include the other
official SDKs where they are implemented: Rust, JavaScript/TypeScript, Common Lisp,
and Elixir.

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

## Status Tracking

Cross-SDK implementation status for the inter-swarm extensions is tracked in:

- `documentation/protocol/extensions/index.md` (extension-level status summary)
- `artifacts/verification/` (evidence snapshots for verification claims)

Update the status page and evidence snapshots together whenever SW4-004 or SW4-005 claims change.

## Structure

- `documentation/index.md` - homepage
- `documentation/quickstart/` - getting started guide
- `documentation/examples/index.md` - cross-SDK example matrix
- `documentation/architecture/` - architecture overview
- `documentation/protocol/` - protocol and extension specs

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

When API reference generation is ready, re-enable `gen_ref_pages.py` and add a reference section to the navigation.
