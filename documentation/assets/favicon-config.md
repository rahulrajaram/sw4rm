# SW4RM Favicon Implementation Guide

## Quick Implementation

### 1. Choose Your Pattern
View all patterns in: `documentation/assets/icon-patterns.html`

### 2. Generate Favicon Sizes
Use the base SVG to create these sizes:

- 16x16px (browser tab)
- 32x32px (browser tab, high DPI)
- 48x48px (Windows shortcut)
- 192x192px (Android)
- 512x512px (iOS, large displays)

### 3. MkDocs Material Configuration

Add to your `mkdocs.yml`:

```yaml
theme:
  name: material
  favicon: assets/icons/favicon.ico
  logo: assets/icons/logo.svg
  
extra_css:
  - assets/css/custom.css
```

### 4. Custom CSS for Consistent Branding

```css
/* Custom CSS for icon consistency */
.md-header__button.md-logo img,
.md-header__button.md-logo svg {
  height: 32px;
  width: 32px;
}

/* Dark theme adjustments */
[data-md-color-scheme="slate"] .md-logo svg {
  filter: brightness(1.2);
}
```

## Recommended Patterns

### For Documentation Sites:

- **Pattern 1** (Geometric Network): Professional, scales well
- **Pattern 3** (Hexagonal Grid): Modern, tech-focused
- **Pattern 5** (Gradient Orb): Clean, memorable

### For Brand Identity:

- **Pattern 8** (S Monogram): Unique brand mark
- **Pattern 5** (Gradient Orb): Modern, AI-focused

### For Technical Audiences:

- **Pattern 2** (Signal Waves): Communication focus
- **Pattern 4** (Circuit Board): Developer appeal

## Color Schemes

Each pattern includes multiple color variants:

- **Blue Scheme**: Professional, trustworthy (#3b82f6, #1e40af)
- **Green Scheme**: Growth, technology (#10b981, #059669)
- **Purple Scheme**: Innovation, creativity (#8b5cf6, #7c3aed)
- **Teal Scheme**: Modern, balanced (#14b8a6, #0d9488)

## Implementation Files

Available in `documentation/assets/icons/`:

- `pattern-1-network.svg`
- `pattern-2-waves.svg`
- `pattern-3-hexagon.svg`
- `pattern-5-orb.svg`
- `pattern-8-s-logo.svg`

## Next Steps


1. Choose your preferred pattern from the HTML preview
2. Customize colors if needed
3. Generate favicon sizes using online tools or ImageMagick
4. Update MkDocs configuration
5. Test across different devices and themes
