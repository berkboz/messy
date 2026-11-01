# Design language: Messy

The rules a contributor follows so a change looks like it belongs. When two options are both fine, the principles decide.

## Principles
1. Friendly and calm, never alarming: a small broom mascot, soft mint sky, rounded cards. It is a cleaner, not an antivirus siren.
2. Coral means mess, mint/teal means clean. Use `Brand.coral` only for found junk, duplicates and threats; a tile with nothing found falls back to the primary text colour.
3. Messy draws its own controls so nothing looks like stock macOS. Style once at the root with `.messyStyle()`.
4. Honest copy: say what will happen, what goes to the Trash, and what Messy cannot do.
5. Cheap when idle: no animated full-window blurs, static backgrounds.

## Tokens
Source of truth: `Sources/Messy/Theme.swift` (`Brand.teal`, `Brand.emerald`, gradient) and `Sources/Messy/DesignSystem.swift` (`Brand.mint`, `Brand.sky`, `Brand.ink`, `Brand.coral`, `BrandBackground`, control styles). Never hard-code a colour that has a token.

| Token | Value | Use |
|---|---|---|
| `Brand.teal` | rgb(0.055, 0.624, 0.604) | tint, borders (18% opacity), ring |
| `Brand.emerald` | rgb(0.122, 0.749, 0.451) | gradient end, "clean" |
| `Brand.coral` | rgb(1.0, 0.52, 0.42) | mess: junk, duplicates, threats |
| `Brand.ink` | rgb(0.04, 0.20, 0.22) | shadows, dark text accents |

## Type and layout
System font, semibold for icons and headings. Cards: `.card()` modifier (regular material, 16 pt radius, teal 18% hairline, soft ink shadow). Result tiles use `Tile`; scans use `ScanRing`.

## Motion
Scan ring eases (0.5 s ease-in-out) instead of jumping; a highlight arc runs while scanning. The mascot has sprites (idle, sweep, happy, worried, blink, hop) in `Resources/Mascot/`. Sounds in `Resources/Sounds/` are synthesized by the scripts in `design/sfx/`.

## Imagery and icons
SF Symbols with `GradientIcon`. Brand art and the app icon are in `design/` and `Resources/`. Screenshots in the README come from `design/screenshots/`.

## Don'ts
- No stock macOS toggles/buttons, no red alarm styling for ordinary findings, no telemetry or network calls to illustrate a feature.
- No new brand colours outside `Theme.swift` / `DesignSystem.swift`.

## Verify a design change
1. `SIGN_IDENTITY="" ./build.sh && open build/Messy.app`.
2. Check the pane in light and dark mode and at the minimum window size.
3. Run `./test.sh`; include before/after screenshots in the PR.

## Tools the design work uses
The launch video uses HyperFrames (`videos/messy-launch/`, its own `AGENTS.md` lists the skills).
