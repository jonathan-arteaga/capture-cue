# astro-lens Product Direction

astro-lens is a native macOS capture studio: quick screenshots stay out of the way, while anything worth polishing can open in one focused editor. The MVP should feel closer to CleanShot X plus Screen Studio than a full editing cockpit.

The visual direction is native but not stock: hidden-titlebar window chrome, a soft glass capture rail, a custom command bar, a centered Studio stage, and floating editor controls. System behavior should remain macOS-native, but the surface should feel like a modern creator app rather than a settings panel.

## MVP Shape

- Capture first: area, screen, and window screenshots are available from hotkeys, the menu bar, and the compact tray.
- Mark up when needed: screenshots are copied immediately, then can be opened for arrows, shapes, text, steps, and redaction.
- Record from the same place: Studio keeps the visible path to source, record, timeline, and export.
- Bridge the workflows: a marked-up screenshot can be attached to the current Studio project as a reference snapshot.
- Stay local: captures, recordings, metadata, and exports remain on device.

## Reference Apps

- CleanShot X: fast capture, small post-capture bubble, low-friction screenshot history.
- Screen Studio: simple recording-to-polished-export path with restrained controls.
- QuickRecorder: native ScreenCaptureKit behavior and practical macOS permission handling.
- BetterCapture: native capture and codec inspiration for later export-quality work.

## Design Principles

- Minimal surface: the main window should show only what helps the current asset.
- Quiet capture: screenshots should not force users into projects or setup flows.
- One editor: image markup and video polish should feel like siblings, not two apps glued together.
- Progressive depth: advanced camera, import, audio, and export controls can return later behind deliberate affordances.
- Local-first privacy: OCR redaction and interaction anchors stay on device.
- Designed surface: prefer branded panels, docks, and focused stages over default sidebars, inspectors, and form-like controls.

## Parked Until After MVP

- Presenter camera UI as a default visible surface.
- Video import/drop as a primary path.
- Detailed audio controls in the main recording strip.
- Multi-option export cockpit.
- Cloud sharing, comments, transcripts, and team review flows.

## Privacy Posture

astro-lens captures interaction anchors so the editor can suggest zooms, cursor emphasis, and key hints after recording. These anchors are local project metadata. Normal typed characters are not stored; ordinary keys are saved only as `Key press`, while special keys such as Return, Tab, Escape, and arrows can be named.
