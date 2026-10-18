// Synthesizes the launch film's soundtrack: music and sound effects in one stereo WAV, 120 BPM, 32 s.
// The effects sit on the film's beat grid (0.5 s beats, 2 s bars), so cuts and hits land together.
//   swiftc -O make-soundtrack.swift -o make-soundtrack && ./make-soundtrack out.wav
import Foundation

let rate = 44_100.0
let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "messy-soundtrack.wav"
let length = 32.0
let beat = 0.5, bar = 2.0
let n = Int(length * rate)
var left = [Double](repeating: 0, count: n), right = [Double](repeating: 0, count: n)

var seed: UInt64 = 0x5EED_3E55
func noise() -> Double {
    seed = seed &* 6364136223846793005 &+ 1442695040888963407
    return Double(Int64(bitPattern: seed >> 1)) / Double(Int64.max)
}
func hz(_ midi: Int) -> Double { 440 * pow(2, Double(midi - 69) / 12) }

/// Adds a voice at `at` seconds for `dur` seconds, panned -1…1.
func add(_ at: Double, _ dur: Double, pan: Double = 0, gain: Double = 1, _ voice: (Double) -> Double) {
    let s = Int(at * rate)
    let lg = sqrt((1 - pan) / 2) * gain, rg = sqrt((1 + pan) / 2) * gain
    for i in 0..<Int(dur * rate) where s + i >= 0 && s + i < n {
        let v = voice(Double(i) / rate)
        left[s + i] += v * lg
        right[s + i] += v * rg
    }
}

// MARK: Instruments

func kick(_ t: Double) -> Double {
    let f = 48 + 110 * exp(-28 * t)
    return 0.9 * exp(-7 * t) * sin(2 * .pi * f * t) + 0.25 * exp(-60 * t) * noise()
}
func clap(_ t: Double) -> Double {
    let env = exp(-22 * t) + 0.5 * exp(-60 * max(0, t - 0.012)) + 0.35 * exp(-60 * max(0, t - 0.024))
    return 0.35 * env * noise()
}
var hatHP = 0.0, hatPrev = 0.0
func hat(_ t: Double) -> Double {
    let x = noise()
    hatHP = 0.82 * (hatHP + x - hatPrev); hatPrev = x       // one-pole high-pass
    return 0.16 * exp(-55 * t) * hatHP
}
func pluck(_ f: Double, decay: Double = 5, bright: Double = 0.3) -> (Double) -> Double {
    { t in min(1, t / 0.003) * exp(-decay * t) * (sin(2 * .pi * f * t) + bright * sin(4 * .pi * f * t) * exp(-8 * t)) }
}
func bass(_ f: Double, dur: Double) -> (Double) -> Double {
    { t in
        let env = min(1, t / 0.005) * min(1, (dur - t) / 0.03) * exp(-1.5 * t)
        return max(0, env) * (sin(2 * .pi * f * t) + 0.35 * sin(4 * .pi * f * t) + 0.12 * sin(6 * .pi * f * t))
    }
}
func pad(_ notes: [Int], dur: Double, attack: Double = 0.6) -> (Double) -> Double {
    { t in
        let env = max(0, min(1, t / attack) * min(1, (dur - t) / 0.8))
        var v = 0.0
        for m in notes {
            let f = hz(m)
            v += sin(2 * .pi * f * t) + 0.5 * sin(2 * .pi * f * 1.004 * t) + 0.1 * sin(2 * .pi * f * 2 * t)
        }
        return env * v / Double(notes.count)
    }
}
/// Band-passed noise sweeping from `from` to `to` Hz.
func sweep(length: Double, from: Double, to: Double, attack: Double) -> (Double) -> Double {
    var low = 0.0, band = 0.0
    return { t in
        let p = min(1, t / length)
        let cutoff = from * pow(to / from, p)
        let f = 2 * sin(.pi * min(cutoff, 18_000) / rate)
        low += f * band
        let high = noise() - low - 0.55 * band
        band += f * high
        let env = p < attack ? p / attack : pow(max(0, 1 - (p - attack) / (1 - attack)), 2)
        return env * band
    }
}

// MARK: Sound effects

func pop(_ at: Double, pitch: Double = 1, pan: Double = 0, gain: Double = 1) {
    add(at, 0.12, pan: pan, gain: 0.32 * gain) { t in
        let f = (900 + 700 * exp(-40 * t)) * pitch
        return exp(-38 * t) * sin(2 * .pi * f * t)
    }
}
func tick(_ at: Double, pan: Double = 0) { add(at, 0.05, pan: pan, gain: 0.22, pluck(1760, decay: 90, bright: 0)) }
func click(_ at: Double) {
    add(at, 0.06, gain: 0.5) { t in exp(-90 * t) * (sin(2 * .pi * 2400 * t) * 0.6 + noise() * 0.4) }
    add(at + 0.07, 0.05, gain: 0.3) { t in exp(-90 * t) * sin(2 * .pi * 1800 * t) }
}
func thunk(_ at: Double, pan: Double = 0) {       // a dialog landing on the stack
    add(at, 0.25, pan: pan, gain: 0.55) { t in
        let f = 120 + 160 * exp(-30 * t)
        return exp(-16 * t) * sin(2 * .pi * f * t) + 0.15 * exp(-50 * t) * noise()
    }
}
func whoosh(_ at: Double, _ dur: Double, from: Double, to: Double, gain: Double = 0.5, pan: Double = 0) {
    add(at, dur, pan: pan, gain: gain, sweep(length: dur, from: from, to: to, attack: 0.55))
}
func impact(_ at: Double, gain: Double = 1) {
    add(at, 1.4, gain: 0.9 * gain) { t in
        let f = 38 + 70 * exp(-12 * t)
        return exp(-3.2 * t) * sin(2 * .pi * f * t)
    }
    add(at, 1.2, gain: 0.35 * gain, sweep(length: 1.2, from: 6000, to: 900, attack: 0.02))
    add(at, 0.4, gain: 0.6 * gain, kick)
}
func sparkle(_ at: Double, gain: Double = 1) {
    for (k, m) in [96, 100, 103, 108].enumerated() {
        add(at + 0.06 * Double(k), 0.6, pan: Double(k) * 0.25 - 0.4, gain: 0.07 * gain, pluck(hz(m), decay: 7, bright: 0))
    }
}
func trashFwip(_ at: Double) { whoosh(at, 0.3, from: 3500, to: 260, gain: 0.55) }
func slam(_ at: Double, chord: [Int]) {
    add(at, 0.5, gain: 0.85, kick)
    add(at, 0.9, gain: 0.16, pad(chord, dur: 0.9, attack: 0.005))
    add(at, 0.35, gain: 0.25) { t in exp(-14 * t) * noise() }
}

// MARK: Harmony

// Cmaj9, Am9, Fmaj9, G6 — the same progression as the app's sounds and the old bed.
let chords: [[Int]] = [[48, 55, 59, 62, 64], [45, 52, 55, 60, 64], [41, 48, 52, 55, 60], [43, 50, 55, 59, 64]]
let arps: [[Int]] = [[72, 76, 79, 83, 79, 76, 74, 76], [69, 72, 76, 79, 76, 72, 71, 72],
                     [65, 69, 72, 76, 72, 69, 67, 69], [67, 71, 74, 76, 74, 71, 69, 71]]

// MARK: Arrangement (bar = 2 s)

// Bars 1–2 (0–4 s) · the mess piles up: a low pad and a clock-like pulse; a pop for each path that lands.
add(0, 4.4, gain: 0.07, pad([36, 43, 50], dur: 4.4, attack: 1.2))
for i in 0..<16 { add(Double(i) * 0.25, 0.08, pan: i % 2 == 0 ? -0.3 : 0.3, gain: i % 4 == 0 ? 1 : 0.55, hat) }
for i in 0..<8 { pop(0.25 + Double(i) * 0.45, pitch: 0.8 + 0.05 * Double(i % 4), pan: Double(i % 3) * 0.3 - 0.3, gain: 0.8) }

// Bars 3–4 (4–8 s) · the asks: a pulsing, slightly sour bass under a stack of dialogs and a rising riser.
for i in 0..<16 {
    let t = 4 + Double(i) * 0.25
    add(t, 0.22, gain: 0.11, bass(hz(i % 8 < 6 ? 37 : 38), dur: 0.22))  // C#2 against C: uneasy
}
add(4, 4.2, gain: 0.06, pad([49, 56, 61], dur: 4.2, attack: 1.5))
for i in 0..<8 { thunk(4 + Double(i) * 0.5, pan: Double(i % 3) * 0.35 - 0.35) }
add(6, 2.0, gain: 0.55, sweep(length: 2.0, from: 300, to: 9000, attack: 0.97))       // riser into the cut
for i in 0..<8 { add(7 + Double(i) * 0.125, 0.1, gain: 0.25 + 0.06 * Double(i), clap) } // roll

// Bar 5 (8–10 s) · the sweep: impact, a big whoosh as the broom crosses, sparkle on the wordmark.
impact(8)
whoosh(8.02, 0.65, from: 400, to: 7000, gain: 0.75)
sparkle(9.0, gain: 1.4)
add(8, 2.2, gain: 0.09, pad(chords[0], dur: 2.2, attack: 0.02))

// Bars 6–11 (10–22 s) · the groove: kick, clap, hats, bass and the marimba arpeggio.
for b in 5..<11 {
    let t0 = Double(b) * bar
    let c = (b - 5) % 4
    for k in 0..<4 { add(t0 + Double(k) * beat, 0.45, gain: 0.7, kick) }
    for k in [1, 3] { add(t0 + Double(k) * beat, 0.3, gain: 0.8, clap) }
    for k in 0..<8 { add(t0 + Double(k) * beat / 2 + beat / 4, 0.08, pan: 0.25, gain: 0.9, hat) }
    add(t0, bar + 0.4, gain: 0.05, pad(chords[c], dur: bar + 0.4, attack: 0.3))
    let root = chords[c][0] - 12
    for k in 0..<8 {
        let note = k == 6 ? root + 7 : root
        add(t0 + Double(k) * beat / 2, 0.24, gain: 0.16, bass(hz(note), dur: 0.24))
    }
    for k in 0..<8 {
        add(t0 + Double(k) * beat / 2, 0.9, pan: k % 2 == 0 ? -0.4 : 0.4, gain: 0.075, pluck(hz(arps[c][k]), decay: 6))
    }
}

// Scan (10–14 s): the click, a whoosh as the ring starts, a tick per module.
click(11.0)
whoosh(11.05, 0.6, from: 350, to: 3200, gain: 0.35)
for (k, t) in [11.5, 12.0, 12.5, 13.0, 13.5].enumerated() { tick(t, pan: Double(k) * 0.2 - 0.4) }
add(13.5, 0.6, gain: 0.25, pluck(hz(84), decay: 6, bright: 0))

// Results (14–18 s): three cards pop in, Run is pressed, the cards fly to the Trash.
for (k, t) in [14.0, 14.25, 14.5].enumerated() { pop(t, pitch: 1 + 0.12 * Double(k), pan: Double(k) * 0.4 - 0.4) }
add(14.6, 0.5, gain: 0.25, pluck(hz(79), decay: 6)); add(14.71, 0.6, gain: 0.25, pluck(hz(84), decay: 6))
click(16.5)
trashFwip(16.62); trashFwip(16.78); trashFwip(16.94)

// Everything else (18–22 s): six tiles land on the beat.
for k in 0..<6 { pop(18 + Double(k) * 0.5, pitch: 0.9 + 0.08 * Double(k), pan: Double(k % 3) * 0.4 - 0.4, gain: 0.9) }

// Bars 12–13 (22–26 s) · trust: three slams on full chords, hats keep time between them.
slam(22.0, chord: [48, 55, 64, 67, 72])
slam(23.25, chord: [45, 52, 60, 64, 69])
slam(24.5, chord: [41, 53, 57, 60, 65])
for k in 0..<16 { add(22 + Double(k) * 0.25, 0.08, pan: 0.2, gain: 0.7, hat) }
add(25.0, 1.0, gain: 0.35, sweep(length: 1.0, from: 500, to: 6000, attack: 0.95))

// Bars 14–16 (26–32 s) · the line, then the lockup: open chord, the "done" arpeggio, a long tail.
add(26, 6, gain: 0.11, pad([48, 55, 59, 64, 67], dur: 6, attack: 0.4))
add(26, 2, gain: 0.08, pluck(hz(36), decay: 1.2, bright: 0))
for (k, m) in [72, 76, 79, 84].enumerated() { add(28 + 0.07 * Double(k), 1.4, pan: Double(k) * 0.2 - 0.3, gain: 0.2, pluck(hz(m), decay: 3.5)) }
pop(28.0, pitch: 0.8, gain: 1.2)
sparkle(28.35, gain: 1.6)
add(28.0, 0.5, gain: 0.5, kick)

// MARK: Master: soft limiter, normalize to -1 dBFS, 10 ms in, 2.5 s fade out.

func soft(_ x: Double) -> Double { tanh(1.2 * x) / tanh(1.2) }
let peak = max(left.map(abs).max()!, right.map(abs).max()!)
let pre = 1.15 / max(peak, 1e-9)
var outL = left.map { soft($0 * pre) }, outR = right.map { soft($0 * pre) }
let post = 0.89 / max(outL.map(abs).max()!, outR.map(abs).max()!)
let fadeIn = Int(0.01 * rate), fadeOut = Int(2.5 * rate)

var data = Data()
func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
data.append("RIFF".data(using: .ascii)!); u32(UInt32(36 + n * 4))
data.append("WAVEfmt ".data(using: .ascii)!); u32(16); u16(1); u16(2)
u32(UInt32(rate)); u32(UInt32(rate) * 4); u16(4); u16(16)
data.append("data".data(using: .ascii)!); u32(UInt32(n * 4))
for i in 0..<n {
    let g = post * min(1, Double(i) / Double(fadeIn)) * min(1, Double(n - i) / Double(fadeOut))
    for v in [outL[i], outR[i]] {
        withUnsafeBytes(of: Int16(max(-1, min(1, v * g)) * 32767).littleEndian) { data.append(contentsOf: $0) }
    }
}
try! data.write(to: URL(fileURLWithPath: outPath))
print("wrote \(length) s to \(outPath)")
