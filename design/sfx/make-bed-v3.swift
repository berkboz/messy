// Synthesizes the v3 launch film's music bed: 120 BPM, 34 s, restrained and warm.
// FM electric piano, a soft round kick, sub bass, a quiet shaker and a slow pad, ducked under the kick.
// Sections follow the cut: tension (0–6 s) → lift on "Meet messy" (6 s) → groove (8.5–26 s)
// → held chords under the three promises (26–29 s) → resolve on the poster (29.15 s) and a long tail.
//   swiftc -O make-bed-v3.swift -o make-bed && ./make-bed out.wav
import Foundation

let rate = 44_100.0
let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "messy-bed-v3.wav"
let length = 34.0
let beat = 0.5
let n = Int(length * rate)
var L = [Double](repeating: 0, count: n), R = [Double](repeating: 0, count: n)
var duck = [Double](repeating: 1, count: n)   // sidechain envelope written by the kick
var seed: UInt64 = 0xBEDB_ED03
func noise() -> Double { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Double(Int64(bitPattern: seed >> 1)) / Double(Int64.max) }
func hz(_ m: Int) -> Double { 440 * pow(2, Double(m - 69) / 12) }

/// Adds a voice; `ducked` voices are multiplied by the kick's sidechain envelope at mix time.
var padL = [Double](repeating: 0, count: n), padR = [Double](repeating: 0, count: n)
func add(_ at: Double, _ dur: Double, pan: Double = 0, gain: Double, ducked: Bool = false, _ v: (Double) -> Double) {
    let s = Int(at * rate)
    let lg = sqrt((1 - pan) / 2) * gain, rg = sqrt((1 + pan) / 2) * gain
    for i in 0..<Int(dur * rate) where s + i >= 0 && s + i < n {
        let x = v(Double(i) / rate)
        if ducked { padL[s + i] += x * lg; padR[s + i] += x * rg } else { L[s + i] += x * lg; R[s + i] += x * rg }
    }
}

// Two-operator FM electric piano: a bell-ish attack that mellows into a sine.
func ep(_ f: Double, dur: Double) -> (Double) -> Double {
    { t in
        let env = min(1, t / 0.004) * exp(-2.2 * t) * min(1, max(0, dur - t) / 0.08)
        let idx = 2.4 * exp(-7 * t) + 0.25
        let mod = sin(2 * .pi * f * 1.0 * t) * idx
        let tine = 0.12 * sin(2 * .pi * f * 14 * t) * exp(-28 * t)
        return env * (sin(2 * .pi * f * t + mod) + tine)
    }
}
func padVoice(_ notes: [Int], dur: Double, attack: Double = 1.2) -> (Double) -> Double {
    { t in
        let env = max(0, min(1, t / attack) * min(1, (dur - t) / 1.2))
        var v = 0.0
        for (k, m) in notes.enumerated() {
            let f = hz(m)
            let det = 1 + 0.0035 * Double(k % 3 - 1)
            v += sin(2 * .pi * f * det * t) + 0.35 * sin(2 * .pi * f * 2.002 * t + 0.6)
        }
        return env * v / Double(notes.count)
    }
}
func kick(_ at: Double, gain: Double = 0.55) {
    add(at, 0.5, gain: gain) { t in
        let f = 46 + 70 * exp(-30 * t)
        return exp(-6.5 * t) * sin(2 * .pi * f * t) * min(1, t / 0.002)
    }
    // sidechain: the pad and keys dip and recover over a beat
    let s = Int(at * rate)
    for i in 0..<Int(0.45 * rate) where s + i < n {
        let t = Double(i) / rate
        duck[s + i] = min(duck[s + i], 1 - 0.45 * exp(-t / 0.12))
    }
}
var hp = 0.0, prev = 0.0
func shaker(_ at: Double, gain: Double) {
    add(at, 0.09, pan: 0.25, gain: gain) { t in
        let x = noise(); hp = 0.86 * (hp + x - prev); prev = x
        return hp * exp(-45 * t) * min(1, t / 0.006)
    }
}
func sub(_ at: Double, _ m: Int, dur: Double, gain: Double = 0.32) {
    add(at, dur, gain: gain) { t in
        let env = min(1, t / 0.01) * min(1, max(0, dur - t) / 0.05)
        return env * (sin(2 * .pi * hz(m) * t) + 0.18 * sin(4 * .pi * hz(m) * t))
    }
}
func chord(_ at: Double, _ notes: [Int], dur: Double, gain: Double, spread: Double = 0.012) {
    for (k, m) in notes.enumerated() {
        add(at + Double(k) * spread, dur, pan: Double(k) / Double(max(1, notes.count - 1)) * 0.6 - 0.3, gain: gain, ducked: true, ep(hz(m), dur: dur))
    }
}

// Voicings (MIDI). Tension: Am9, Fmaj7#11. Lift and groove: Cmaj9, Am9, Fmaj9, G6/9.
let Am9 = [57, 60, 64, 67, 71], Fm7s11 = [53, 57, 60, 64, 71]
let C9 = [48, 55, 59, 62, 64], A9 = [45, 52, 55, 60, 64], F9 = [41, 48, 52, 55, 60], G69 = [43, 50, 55, 57, 64]
let groove = [C9, A9, F9, G69]

// 0–6 s · tension: slow keys and a pad, no drums.
add(0, 3.4, gain: 0.10, ducked: true, padVoice([45, 52, 57, 60], dur: 3.4, attack: 1.6))
chord(0.1, Am9, dur: 2.9, gain: 0.07)
add(3.0, 3.4, gain: 0.10, ducked: true, padVoice([41, 48, 53, 57], dur: 3.4))
chord(3.05, Fm7s11, dur: 2.9, gain: 0.07)
for i in 0..<12 { shaker(Double(i) * 0.5 + 0.25, gain: 0.05) }   // a clock under the filling disk

// 6–8.5 s · the lift on "Meet messy".
add(6.0, 3.0, gain: 0.12, ducked: true, padVoice(C9, dur: 3.0, attack: 0.5))
chord(6.02, C9.map { $0 + 12 }, dur: 2.2, gain: 0.08, spread: 0.035)
sub(6.0, 36, dur: 2.4, gain: 0.22)
for i in 0..<5 { shaker(6.0 + Double(i) * 0.5 + 0.25, gain: 0.07) }

// 8.5–26 s · the groove: soft four-on-the-floor, offbeat keys, sub, sixteenth shaker.
let gStart = 8.5, gEnd = 26.0
var t = gStart, bar = 0
while t < gEnd - 0.01 {
    let c = groove[bar % 4]
    for k in 0..<4 { kick(t + Double(k) * beat, gain: k == 0 ? 0.55 : 0.45) }
    add(t, 2.2, gain: 0.07, ducked: true, padVoice(c, dur: 2.2, attack: 0.3))
    // keys: a stab on the "and" of 1 and 3, a lighter one on 4
    chord(t + 0.25, c.map { $0 + 12 }, dur: 0.42, gain: 0.06)
    chord(t + 1.25, c.map { $0 + 12 }, dur: 0.42, gain: 0.055)
    chord(t + 1.75, Array(c.map { $0 + 12 }.suffix(3)), dur: 0.3, gain: 0.04)
    let root = c[0] - 12
    sub(t, root, dur: 0.95); sub(t + 1.0, root, dur: 0.45); sub(t + 1.5, root + 7, dur: 0.45, gain: 0.26)
    for k in 0..<16 { shaker(t + Double(k) * 0.125, gain: k % 2 == 0 ? 0.055 : 0.03) }
    t += 2; bar += 1
}

// 26–29.15 s · the promises: drums out, one held chord per line.
for (k, c) in [A9, F9, G69].enumerated() {
    let at = 26.0 + Double(k) * 1.05
    add(at, 1.4, gain: 0.10, ducked: true, padVoice(c, dur: 1.4, attack: 0.15))
    chord(at, c.map { $0 + 12 }, dur: 1.0, gain: 0.065, spread: 0.02)
    sub(at, c[0] - 12, dur: 1.0, gain: 0.2)
}

// 29.15 s · the poster: resolve, an arpeggio up, a long tail.
kick(29.15, gain: 0.5)
add(29.15, 4.85, gain: 0.14, ducked: false, padVoice([36, 48, 55, 59, 62, 64, 71], dur: 4.85, attack: 0.08))
sub(29.15, 36, dur: 3.5, gain: 0.25)
for (k, m) in [72, 76, 79, 83, 86].enumerated() { add(29.2 + 0.09 * Double(k), 2.6, pan: Double(k) * 0.15 - 0.3, gain: 0.055, ep(hz(m), dur: 2.6)) }

// Mix: duck the pad/keys bus, soft-clip, normalize to -1 dBFS, fade the tail.
for i in 0..<n { L[i] += padL[i] * duck[i]; R[i] += padR[i] * duck[i] }
func soft(_ x: Double) -> Double { tanh(1.1 * x) / tanh(1.1) }
let peak = max(L.map(abs).max()!, R.map(abs).max()!)
let pre = 1.1 / max(peak, 1e-9)
let oL = L.map { soft($0 * pre) }, oR = R.map { soft($0 * pre) }
let post = 0.89 / max(oL.map(abs).max()!, oR.map(abs).max()!)
let fadeOut = Int(1.8 * rate), fadeIn = Int(0.02 * rate)

var data = Data()
func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
data.append("RIFF".data(using: .ascii)!); u32(UInt32(36 + n * 4))
data.append("WAVEfmt ".data(using: .ascii)!); u32(16); u16(1); u16(2)
u32(UInt32(rate)); u32(UInt32(rate) * 4); u16(4); u16(16)
data.append("data".data(using: .ascii)!); u32(UInt32(n * 4))
for i in 0..<n {
    let g = post * min(1, Double(i) / Double(fadeIn)) * min(1, Double(n - i) / Double(fadeOut))
    for v in [oL[i], oR[i]] { withUnsafeBytes(of: Int16(max(-1, min(1, v * g)) * 32767).littleEndian) { data.append(contentsOf: $0) } }
}
try! data.write(to: URL(fileURLWithPath: outPath))
print("wrote \(length) s to \(outPath)")
