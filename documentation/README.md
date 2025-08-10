# SW4RM Agentic Protocol Documentation

This directory contains the documentation source for the SW4RM Agentic Protocol website (with a section for the reference Python SDK) built with [MkDocs Material](https://squidfunk.github.io/mkdocs-material/).

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
2. Set build command: `mkdocs build`
3. Set publish directory: `site`

### Vercel

1. Import your repository to Vercel  
2. Set build command: `mkdocs build`
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
    from sw4rm import SDK
    ```

=== "Installation"  
    ```bash
    pip install sw4rm-sdk
    ```
```

### Adding Pages

1. Create a new `.md` file in the appropriate directory
2. Add to the `nav` section in `mkdocs.yml`
3. Use relative links: `[Link text](../other-section/page.md)`

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
