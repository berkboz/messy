---
format: 1920x1080
duration: 25s
message: "A free, open-source Mac cleaner: Messy finds the mess, a little broom sweeps it up, and nothing is deleted on its own"
arc: Hook → Product intro → Demo → Proof → Features → Brand outro
audience: Mac users who read brk.bz; developers and people who use a cleaner a few times a year
mode: autonomous
music: none
---

## Video direction

- **Palette** (from `frame.md`): canvas `bg` deep ink-teal; display text `text`; secondary lines `text-muted`; **`primary` mint-green = clean** (the broom, success, buttons); **`mess` coral = mess** (dust, found amounts, the squiggle under the wordmark). Cards use `card-tinted`. Never introduce other hues.
- **Type**: display/body by role from `frame.md` (Nunito, rounded). Sentence case, no exclamation marks. The brand name is always the lowercase wordmark "messy" with a hand-drawn coral squiggle under it.
- **Cast**: the broom (hero, `assets/mascot-*.png`) and the dust bunnies (the mess, `assets/dust-*.png`). Characters are cut-outs over the canvas with a soft contact shadow; they move with springy-but-settled motion, never floaty.
- **Motion grammar**: long-tail `power3` eases, smooth over bouncy except the broom's hop and the button press. No voice-over: reveals are paced to the on-screen lines — each line enters on its own beat, spread across the shot; nothing is dumped at t=0. Holds are still (a subtle jitter on the dust at most).
- **App windows**: real screenshots on rounded windows with a soft shadow, gently tilted in 3D on entry and settling flat; never rebuilt in HTML.
- **Rhythm**: Frame 2 ends on a held beat (the name lands); Frame 4's last window is the held read before the faster Frame 5; Frame 6 holds the lockup to the final frame.
- **Negative list**: no front-load-then-freeze slides; no screensaver drift where everything floats independently; no cursor arrows except the single click in Frame 3; no browser chrome; no purple-blue AI gradients; nothing important in the bottom ~17%.

## Frame 1 — Dust settles

- scene: Dark field; short lines appear one at a time while dust bunnies roll in and settle
- voiceover: ""
- duration: 3.5s
- transition_in: crossfade
- status: animated
- src: compositions/frames/01-dust.html
- type: hook
- persuasion: Pain validation
- beat: recognition + mild frustration
- blueprint: kinetic-type-beats (Adapt)
- asset_candidates: assets/dust-idle.png — fluffy dust bunny with a small smile; assets/dust-scared.png — the dust bunny wide-eyed, about to be swept
- focal: assets/dust-idle.png
- roles: dust-idle = cutout (three copies, different sizes) · dust-scared = cutout (swap in for one bunny at the end)
- on_screen: "Your Mac collects dust." / "Caches. Logs. Leftovers."

Adapt: keep the slow 2-statement relay with each line landing alone; the "payoff" is a dust bunny turning scared instead of a logo.
Scene 1 (0.0–1.3s): "Your Mac collects dust." assembles word by word (per-word staggered reveal → `dynamic-content-sequencing`), left-aligned in the upper third, display size; one dust bunny rolls in from the left and settles lower-right — asymmetric 60/40, 2 depth layers.
Scene 2 (1.3–2.6s): the first line dims to `text-muted`; "Caches. Logs. Leftovers." slams in word by word below it (kinetic beat-slam → `kinetic-beat-slam`), each word coral; two more dust bunnies drop in beside the first on the same beats.
Scene 3 (2.6–3.5s): hold the read; the front dust bunny's image hard-swaps to the scared face (instant swap, no fade) as if it noticed something coming from the right. Stillness otherwise.

narrativeRole: open on a feeling every Mac user knows, in plain words, before any product appears.
keyMessage: clutter builds up quietly.

## Frame 2 — Meet messy

- scene: The broom hops into the centre, sparkles pop; the "messy" wordmark writes itself with its coral squiggle, then one line of promise
- voiceover: ""
- duration: 3.5s
- transition_in: zoom-through
- status: animated
- src: compositions/frames/02-meet.html
- type: product_intro
- persuasion: Friendly reveal
- beat: curiosity → delight
- blueprint: titlecard-reveal (Adapt)
- asset_candidates: assets/mascot-happy.png — the broom hopping with sparkles; assets/messy-icon.png — app icon
- focal: assets/mascot-happy.png
- roles: mascot-happy = cutout (hero, left of centre) · messy-icon = supporting (small, beside the wordmark)
- on_screen: "messy" (wordmark) / "A free, open-source Mac cleaner."

Adapt: keep the three-beat title prelude (mark pop → name → tagline); the mark is the broom character, and the name is the wordmark with its squiggle drawn on.
Scene 1 (0.0–1.0s): the broom springs up from below centre-left with a squash-and-stretch hop (button-press spring → `press-release-spring`), three small mint sparkles pop around it — centered-left hero, ~40% of frame height.
Scene 2 (1.0–2.1s): to its right, the lowercase "messy" wordmark appears letter by letter (per-word staggered reveal at letter granularity → `dynamic-content-sequencing`) and the coral squiggle draws itself under it left to right (SVG self-draw → `svg-path-draw`); the small app icon fades in before the wordmark. Rule-of-thirds, wordmark on the right third line.
Scene 3 (2.1–3.5s): "A free, open-source Mac cleaner." rises in under the wordmark in `text-muted`; then a held read — the broom settles, everything still. (Held beat.)

narrativeRole: name the product and state the value in one breath.
keyMessage: there is a free, friendly cleaner for this.

## Frame 3 — One button

- scene: The real app window floats in on "Let's find the mess.", the Scan button is pressed, and the window swaps to the scan in progress
- voiceover: ""
- duration: 5s
- transition_in: crossfade
- status: animated
- src: compositions/frames/03-checkup.html
- type: key_feature
- persuasion: Show-don't-tell proof
- beat: ease
- blueprint: device-surface-showcase (Adapt)
- asset_candidates: assets/screen-checkup.png — app window, "Let's find the mess." with the broom in a ring and a green Scan button; assets/screen-scanning.png — app window mid-scan, "Hunting for mess… 40%"
- focal: assets/screen-checkup.png
- roles: screen-checkup = cutout (window, centre-right) · screen-scanning = cutout (replaces it in place)
- on_screen: "One button finds the mess."

Adapt: keep the held device surface whose screens cycle; one click drives the cycle instead of a scroll.
Scene 1 (0.0–1.4s): the app window tilts in from slightly below and settles flat, centre-right, ~62% of frame width, soft shadow under it (push / focus → `multi-phase-camera`, gentle); the headline "One button finds the mess." enters top-left as the window lands — asymmetric 30/70, 3 depth layers (canvas, window, headline).
Scene 2 (1.4–2.4s): a single cursor glides to the window's Scan button, presses it with a ripple (cursor click + ripple → `cursor-click-ripple`); the button compresses and springs.
Scene 3 (2.4–3.6s): the window's content scale-swaps in place to the scanning screen (scale-swap → `scale-swap-transition`), the cursor fades away; a slow zoom-to-target eases toward the ring with the sweeping broom (→ `coordinate-target-zoom`, small amount).
Scene 4 (3.6–5.0s): hold on the scanning window; still.

narrativeRole: show the core interaction — one press, everything is checked.
keyMessage: it is effortless.

## Frame 4 — You decide

- scene: The results window; the banner with the coral amount comes into focus, then two calm promises
- voiceover: ""
- duration: 4.5s
- transition_in: crossfade
- status: animated
- src: compositions/frames/04-results.html
- type: key_feature
- persuasion: Risk reversal
- beat: control + peace of mind
- blueprint: device-surface-showcase (Adapt)
- asset_candidates: assets/screen-results.png — app window "Here's the mess" with a "Found 86.8 MB to clean" banner, the broom and two dust bunnies, and result cards
- focal: assets/screen-results.png
- roles: screen-results = cutout (window, left)
- on_screen: "Nothing changes until you press Run." / "Everything goes to the Trash first."

Adapt: same held window idea; this time the camera reads one region (the banner) and copy carries the promise.
Scene 1 (0.0–1.5s): the results window settles left, ~58% of width; the camera eases toward its top banner with the coral "86.8 MB" (zoom-to-target → `coordinate-target-zoom`), and a soft coral glow marks the amount (keyword glow → `asr-keyword-glow`).
Scene 2 (1.5–2.8s): on the right, "Nothing changes until you press Run." enters line by line (per-word staggered reveal → `dynamic-content-sequencing`) — asymmetric 60/40.
Scene 3 (2.8–4.5s): "Everything goes to the Trash first." enters below it in `text-muted`; then a held read, camera still. (Held beat before Frame 5.)

narrativeRole: remove the fear of a cleaner deleting the wrong thing.
keyMessage: you stay in control.

## Frame 5 — Everything else

- scene: Three app windows fan out as cards with label pills, then the trust line
- voiceover: ""
- duration: 4.5s
- transition_in: push-slide LEFT
- status: animated
- src: compositions/frames/05-features.html
- type: benefits
- persuasion: Value stacking
- beat: confidence
- blueprint: grid-card-assemble (Adapt)
- asset_candidates: assets/screen-monitor.png — Monitor pane with health ring and cards; assets/screen-speed.png — Speed pane with maintenance tasks; assets/screen-scanning.png — Check up in progress
- focal: assets/screen-monitor.png
- roles: screen-monitor = cutout (centre card) · screen-speed = cutout (right card) · screen-scanning = cutout (left card)
- on_screen: "Check up" / "Monitor" / "Speed" / "No helper running as root. No account. No telemetry."

Adapt: keep the self-assembling labelled tiles; three window cards instead of a grid, then one trust line as the payoff.
Scene 1 (0.0–1.8s): three window cards start stacked at centre and expand outward into a slight fan — left, centre (raised, largest), right (cluster→outward expansion → `center-outward-expansion`); each gets a mint label pill under it as it lands ("Check up", "Monitor", "Speed"), staggered — triptych, 3 depth layers.
Scene 2 (1.8–3.0s): the fan eases back a little and dims to ~70% while the trust line "No helper running as root. No account. No telemetry." assembles phrase by phrase across the upper third (per-word staggered reveal → `dynamic-content-sequencing`).
Scene 3 (3.0–4.5s): hold the read; the three phrases are lit, still.

narrativeRole: show breadth without a feature list, then the trust line.
keyMessage: it does what the big cleaners do, quietly.

## Frame 6 — Swept clean

- scene: The broom sweeps across the frame, the dust bunnies tumble and burst into sparkles, revealing the icon, the wordmark and the URL
- voiceover: ""
- duration: 4s
- transition_in: blur-crossfade
- status: animated
- src: compositions/frames/06-outro.html
- type: brand_outro
- persuasion: Inevitability
- beat: satisfaction
- blueprint: logo-assemble-lockup (Adapt)
- asset_candidates: assets/mascot-sweep.png — the broom tilted mid-sweep with dust puffs; assets/dust-scared.png — dust bunny about to be swept; assets/dust-gone.png — dust dissolving into sparkles; assets/messy-icon.png — app icon
- focal: assets/messy-icon.png
- roles: mascot-sweep = cutout (moves across) · dust-scared = cutout (three on the floor line) · dust-gone = cutout (replaces each bunny as it is swept) · messy-icon = cutout (lockup centre)
- on_screen: "messy" (wordmark) / "Free & open source" / "brk.bz/messy"

Adapt: keep "elements clear the stage and the lockup draws itself in"; the clearing is the broom sweeping the dust.
Scene 1 (0.0–1.6s): three scared dust bunnies sit along a floor line in the lower-middle; the broom sweeps in from the left across the frame (rocking as it goes), and as it reaches each bunny the bunny hard-swaps to the dust-gone sparkle puff and fades (instant swap, a left→right wave).
Scene 2 (1.6–2.8s): behind the broom's exit, the app icon pops in at centre (button-press spring → `press-release-spring`), the "messy" wordmark appears under it and its coral squiggle draws on (SVG self-draw → `svg-path-draw`) — centered lockup, icon ~22% of frame height.
Scene 3 (2.8–4.0s): "Free & open source" and "brk.bz/messy" fade up under the lockup in `text-muted` / `primary`; hold to the final frame, still.

narrativeRole: land the brand and where to get it.
keyMessage: free, open source, brk.bz/messy.
