<p align="center">
  <img width="72" alt="CaptureCue app icon" src="https://github.com/user-attachments/assets/ab90875f-4092-4ca9-b475-9a60b9c6445a" />
</p>

# <p align="center">CaptureCue</p>

> A minimal macOS capture studio for polished screenshots, demo videos, and GIFs.

CaptureCue is being rebuilt around one simple idea: capture should feel instant,
quiet, and out of the way, then the editor should help turn the result into a
clean shareable demo without a heavy production workflow.

## Direction

- **Minimal capture launcher:** a lightweight radial capture menu for screenshot,
  window, area, screen recording, and GIF/demo capture.
- **Fast demo polish:** cursor zooms, trim, background framing, captions, camera,
  audio, and export controls focused on quick product demos.
- **Screenshot utility layer:** annotations, redaction, numbered steps, copy,
  save, pin, and drag-out export will be folded in from earlier prototypes.
- **Local-first workflow:** recordings, screenshots, and editing data stay on the
  Mac by default.

## Current Starting Point

This baseline is derived from the open-source Reframed macOS recorder/editor and
has been rebranded as CaptureCue so we can build the final product in one repo.

The next major product task is replacing the existing toolbar-style capture
entry with CaptureCue's radial launcher and trimming the editor down to the
features that support fast polished demos.

## Requirements

- macOS 15.0 or later
- Screen Recording permission
- Accessibility permission
- Microphone permission for voice capture
- Camera permission for webcam overlay

## Build

```bash
make build
```

Run a local debug build:

```bash
make dev
```

## Attribution

CaptureCue starts from Reframed by Jan Kuri. See `NOTICE.md` and `LICENSE` for
upstream attribution and license details.
