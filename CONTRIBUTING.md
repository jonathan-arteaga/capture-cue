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
- `CaptureCue/Recording`: capture pipeline and writers
- `CaptureCue/Editor`: timeline, properties, and preview
- `CaptureCue/Compositor`: video composition and export
- `CaptureCue/State`: app state and configuration
- `CaptureCue/UI`: reusable interface components
- `CaptureCue/Utilities`: shared helpers

## License

By contributing, you agree that your contributions will be licensed under the
MIT License.
