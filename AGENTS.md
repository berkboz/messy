# Agent brief: Messy

Messy is a free, open-source Mac maintenance app (SwiftUI, macOS 14+, Swift Package, one dependency: Sparkle). It finds junk, threats, duplicates and large files and shows them as cards; the user ticks what to remove. The repo is PUBLIC and MIT-licensed: never commit secrets, signing material, or personal paths.

## Run and verify
- Build: `SIGN_IDENTITY="" ./build.sh` then `open build/Messy.app` (omit `SIGN_IDENTITY=""` to sign with a Developer ID found in the keychain).
- Check before claiming done: `./test.sh` (must print no failures) and a clean `./build.sh`.
- Visual changes: build, open the app, look at the affected pane in light and dark mode; attach a screenshot to the PR.

## Conventions
- Sources in `Sources/Messy/`, one file per pane. `test.sh` lists the logic files it compiles by name: add a new logic file there if the tests need it.
- Brand colours and shared views live in `Theme.swift`; custom control styles in `DesignSystem.swift` (applied once with `.messyStyle()`). Do not use stock macOS controls or inline colours.
- Design language: follow `DESIGN.md`.
- `build/`, `.build/`, `design/site/`, `design/post/` and renders are gitignored. `videos/messy-launch/` is its own HyperFrames project: read its `AGENTS.md` before touching it.

## Product rules (they decide arguments; also stated in README)
- Nothing is deleted by Messy itself: everything goes to the Trash; Empty Trash asks Finder after confirmation.
- No privileged helper, no daemon, no root component. Admin tasks run fixed built-in commands behind the macOS password dialog, or are shown as a quoted command the user can run.
- No network unless the user clicks (update checks, speed test). No account, telemetry or analytics.
- Honest about limits: no signature-based antivirus, no private-API features (chip temperatures, fan speeds).

## Pitfalls
- Both `arm64` and `x86_64` triples write to the same products folder; `build.sh` copies each binary out right away. Keep that order if you edit it.
- Animating full-window blurs costs real CPU on an idle screen: backgrounds are static on purpose.
- Releases: bump `CFBundleShortVersionString` and `CFBundleVersion` in `Resources/Info.plist`, then `PUBLISH=1 ./release.sh`. Maintainer-only (needs Developer ID, notarytool profile `messy-notary`, Sparkle EdDSA key in the keychain).
