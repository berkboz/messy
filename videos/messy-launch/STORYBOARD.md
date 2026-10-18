---
format: 1920x1080
duration: 32s
message: "A free, open-source Mac cleaner that asks for nothing: Messy finds the mess, a little broom sweeps it up, and nothing changes until you press Run"
arc: Mess → Tension (the asks) → One-cut resolution (the sweep) → Demo → Proof → Breadth → Trust slams → One line, then the lockup
audience: Mac users who read brk.bz; developers and people who use a cleaner a few times a year
mode: autonomous
music: host
---

## Video direction

Rebuilt in October 2026 after studying the references saved in Raindrop (Launch Video and Video Agent → Inspiration): Titouan Gillet's breakdowns (Cofounder, Cloudflare, Firecrawl, Motionly), Ondo, State Machines, wabi, Kevin Ngo's procedural riso film, Koldo Huici's infinite zoom, 2irl4u's rebuilt UI, Kyle Anthony's editorial motion, dhruvxr's macro UI cuts, isaac.edits on SFX, and N01ennn's "Opus 5.5 into a studio" guide.

What we take, and where:

- **The form matches the pitch** (Firecrawl: the logo builds itself out of the product's own data). The coral scribble of mess, drawn across the real cache folders in Frame 1, untangles into the squiggle under the wordmark in Frame 3.
- **One persistent motif** (Kevin Ngo's dot): the coral line runs from the first shot to the lockup.
- **Tension buried mid-film, resolved in one cut** (Cloudflare): a stack of helper / password / trial / account dialogs, wiped by one broom stroke on the impact.
- **Rebuilt UI, not screenshots** (Ondo, 2irl4u): the Check up screen, result cards, Run button, ring, toggles and treemap are HTML, large, isolated, each with its own motion. Real copy and real numbers from the app.
- **Counted, not claimed** (Firecrawl): the junk amount counts up on the card.
- **Payoff by one line held alone** (Cloudflare): "The cleaner you can read." over the app's real source, then the lockup and URL.
- **Rhythm and sound** (isaac.edits, dhruvxr, Koldo): 120 BPM, every cut on a beat or bar, a sound on every hit, music and effects baked into one soundtrack (`design/sfx/make-soundtrack.swift`).
- **Texture** (Kevin Ngo, Koldo): stepped film grain and a vignette on every frame, so nothing reads as flat digital.

Banned defaults (N01ennn): a centred title on a gradient with everything fading in; screenshots as the hero; uniform fades; motion with no sound.

Palette from `frame.md`: ink-teal ground, `text`, `text-muted`, mint = clean, coral = mess. Type: Nunito 900 for display (the wordmark's face), JetBrains Mono for paths, labels and code.

## Frame 1 — The mess

- duration: 4s
- transition_in: cut
- status: animated
- src: compositions/frames/01-mess.html
- type: hook
- on_screen: "Your Mac keeps everything." / "Caches. Logs. Leftovers."

The real folders Messy cleans fall and pile up on the half-beat; the coral scribble tangles across them; two dust bunnies land on top.

## Frame 2 — The asks

- duration: 4s
- transition_in: cut
- status: animated
- src: compositions/frames/02-asks.html
- type: problem
- on_screen: "Most cleaners want more than your mess."

Generic system-style dialogs (helper tool, Full Disk Access, free trial, account, password, scareware, background item, upsell) slam onto a stack, one per beat; the room closes in; a riser into the cut.

## Frame 3 — One sweep

- duration: 2s
- transition_in: cut
- status: animated
- src: compositions/frames/03-sweep.html
- type: product_intro
- on_screen: "messy" / "free · open source · for your Mac"

Impact. The broom crosses the frame in one stroke, flicking every dialog away; the brand ground follows it; the scribble untangles into the squiggle; the wordmark lands on it.

## Frame 4 — One button

- duration: 4s
- transition_in: cut
- status: animated
- src: compositions/frames/04-scan.html
- type: key_feature
- on_screen: "Let's find the mess." / "Hunting for mess… N%"

Macro on the Scan button, the click on the beat, the camera pulls back, the ring fills and five module chips turn green on the beat.

## Frame 5 — You press Run

- duration: 4s
- transition_in: cut
- status: animated
- src: compositions/frames/05-results.html
- type: key_feature
- on_screen: "Nothing changes until you press Run." / "Everything goes to the Trash first."

Three result cards fly in from depth, the junk amount counts up, Run is pressed, the cards fold into the Trash.

## Frame 6 — The rest of the job

- duration: 4s
- transition_in: cut
- status: animated
- src: compositions/frames/06-everything.html
- type: benefits
- on_screen: "And the rest of the job." / Monitor · Speed · Apps · Space · Protect · Menu bar

Six tiles land on the beat, each doing its own thing: a health score, toggles, leftovers folding into an app, a treemap, a shield scan, live bars.

## Frame 7 — Trust

- duration: 4s
- transition_in: cut
- status: animated
- src: compositions/frames/07-trust.html
- type: proof
- on_screen: "No helper running as root." / "No account." / "No telemetry."

Three full-bleed slams on mint, ink and coral, hard cuts on the stabs.

## Frame 8 — The cleaner you can read

- duration: 6s
- transition_in: cut
- status: animated
- src: compositions/frames/08-outro.html
- type: brand_outro
- on_screen: "The cleaner you can read." / "messy" / "free & open source · macOS 14+" / "brk.bz/messy"

The line alone over the app's real source code; hard cut on the bar to the icon, wordmark, squiggle and URL; the broom hops in; hold.
