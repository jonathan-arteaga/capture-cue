# Contributing to CaptureCue

CaptureCue is currently a personal early-stage app. Contributions are welcome
once the first public direction settles.

## Local Build

```bash
make build
```

Or build and launch from the Codex app with the configured `Run` action.

## Project Shape

- `CaptureCue/App`: app entry, permissions, and window management
- `CaptureCue/Features/Recording`: capture pipeline and writers
- `CaptureCue/Features/Editor`: timeline, properties, and preview
- `CaptureCue/Features/Compositor`: video composition and export
- `CaptureCue/Stores`: app state and configuration
- `CaptureCue/DesignSystem`: reusable interface components
- `CaptureCue/Support/Utilities`: shared helpers

## License

By contributing, you agree that your contributions will be licensed under the
MIT License.
