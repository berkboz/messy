---
format: 1920x1080
duration: 34s
message: "A free, open-source Mac cleaner that doesn't add to the mess: one click finds it, nothing changes until you press Run, and everything goes to the Trash first"
arc: Problem (the disk fills, cleaners add more) → Turn (Meet messy) → Demo as one continuous shape → Breadth on one pan → Three promises → Poster
audience: Mac users who read brk.bz; developers and people who use a cleaner a few times a year
mode: autonomous
music: host
languages: en, tr (render with --variables '{"lang":"tr"}')
---

## Video direction (v3)

Rebuilt after reading every guide saved in Raindrop (Launch Video, Video Agent and its Inspiration folder), not just the launch films. What each one decided here:

- **leomeethewoo, "Apple Framework":** intention over effects; one shot = one idea; key objects centred with room to breathe; three colours (ink, white, mint; coral only for mess); smooth eased motion; few, quiet sound effects.
- **HeyGen `heygen-apple-motion` templates:** one ease family (`EO`/`EI`, exponential, no overshoot, no bounce, nothing linear); matched vectors at every cut (frame 02 leaves moving left, frame 03 arrives moving left, frame 03 leaves left, frame 04's first line arrives moving left); no idle motion; derived blur on fast moves; a damped counter-bounce on the lockup.
- **shapelayer, launch blueprint:** text in a few big centred words, one beat each, part of the animation; UI rebuilt, not recorded, with a cursor pointing at the one thing that matters; a poster frame held for 3–4 s.
- **notdwd and 0xmovez:** one shape, never cut. The storage bar becomes the Scan button, the button becomes the scan ring, the ring opens into the results banner. Crossfades are banned.
- **Nate Parrott, Claude Design:** decide the type and colour before building. Inter (OFL, as `MessySans`), semibold, tight tracking, with Inter's single-storey a and flat-sided alternates.
- **jake11moran, rexan_wong:** show only the part of the UI the story touches, larger, on a clean ground; real copy from the app.
- **isaac.edits, Leo, beamnxw:** recorded sound effects (Pixabay set bundled with HyperFrames), placed only on actions.

Literal animation: the disk literally fills; the cleaners' own extras literally drop into it; the broom literally sweeps the junk off the bar; the junk literally flies into the Trash in the Dock; memory literally drops; an app literally leaves with its leftovers; login items literally switch off.

Removed from v2 by request: the coral squiggle, the dust bunnies, Nunito, grain, hard-cut slams.

The app UI stays in English in both versions (the app is English); only the headlines and captions are translated.

## Frame 1 — The disk fills

- duration: 8.5s
- transition_in: cut
- status: animated
- src: compositions/frames/01-storage.html
- type: hook
- on_screen: "Your Mac fills up." / "Most cleaners add to the mess." / "Meet messy." / "One click finds it."

## Frame 2 — One click, one shape

- duration: 10.5s
- transition_in: cut
- status: animated
- src: compositions/frames/02-checkup.html
- type: key_feature
- on_screen: "It checks everything at once." / "Nothing changes until you press Run." / "Everything goes to the Trash first."

## Frame 3 — The rest of the job

- duration: 7s
- transition_in: cut
- status: animated
- src: compositions/frames/03-features.html
- type: benefits
- on_screen: "And the rest of the job." + five captions

## Frame 4 — Promises, then the poster

- duration: 8s
- transition_in: cut
- status: animated
- src: compositions/frames/04-end.html
- type: brand_outro
- on_screen: "No root helper." / "No account." / "No telemetry." / "messy." / "Free and open source, for macOS." / "brk.bz/messy"
