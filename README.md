# CaptureCue

CaptureCue is a native macOS screenshot, recording, and lightweight editing tool.

## MVP

- CleanShot-style screenshot capture from hotkeys and the menu bar.
- Quick post-capture bubble for copy, save, pin, and markup.
- Recent capture tray with optional image markup.
- Marked-up screenshots can be used as Studio references.
- Studio recording flow with source selection, record/stop, timeline, and export.
- Local-first storage under Application Support and Movies.

## Run

```bash
./script/build_and_run.sh
```

## Test

```bash
swift test
```

## Package

```bash
./script/package_dmg.sh
```

The app needs macOS Screen Recording access for screenshots and recordings. Camera and microphone support still exist under the hood for later Studio expansion, but they are not part of the first visible MVP path.
