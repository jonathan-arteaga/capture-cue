# Release Distribution

astro-lens is currently packaged outside the Mac App Store. The first release path is a `.dmg` generated from the SwiftPM app bundle. Local builds prefer an installed Apple Development certificate so macOS privacy grants stay tied to a stable app identity. If no Apple Development identity is available, the script falls back to ad-hoc signing. Set `ASTRO_LENS_CODE_SIGN_IDENTITY` to override the signing identity.

## Local Build

```sh
./script/build_and_run.sh --verify
./script/package_dmg.sh
./script/validate_release_artifact.sh
```

The DMG is written to `dist/astro-lens.dmg`.

When packaging, `script/package_dmg.sh` prefers an installed Developer ID Application certificate. That keeps release artifacts closer to the future notarized distribution path while still working without the Mac App Store.

## Notarized DMG

For internal distribution outside the Mac App Store, use Developer ID signing plus Apple notarization:

```sh
./script/package_dmg.sh
APPLE_ID="you@example.com" \
APPLE_TEAM_ID="JTR454HMP7" \
APPLE_APP_SPECIFIC_PASSWORD="app-specific-password" \
./script/notarize_dmg.sh
```

If you already stored credentials in a keychain profile:

```sh
ASTRO_LENS_NOTARY_KEYCHAIN_PROFILE="astro-lensNotary" ./script/notarize_dmg.sh
```

The notarization script verifies the app signature, checks that the app is Developer ID signed with hardened runtime, verifies the DMG, submits it with `notarytool`, staples the ticket, and validates the stapled DMG with Gatekeeper.

`script/validate_release_artifact.sh` is credential-free and safe to run locally or in future automation for every build. It verifies the app signature, required privacy usage descriptions, hardened runtime and timestamping when Developer ID is used, and the DMG checksum.

## Permission Notes

macOS privacy permissions are tied to an app's security identity. During development, repeatedly rebuilding or replacing an ad-hoc signed app bundle can make macOS treat the app as new. The local script now prefers a persistent Apple Development identity to reduce repeated Screen Recording, Camera, and Microphone prompts. If prompts continue after changing the signing identity, remove the old astro-lens privacy entries in System Settings and grant access once to the newly signed app.

Interaction anchors may also require keyboard or input monitoring permission. astro-lens stores only privacy-safe key labels, not typed characters.
