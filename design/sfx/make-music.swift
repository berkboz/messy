// Synthesizes the launch film's music bed: a calm, bright loop in C at 92 BPM.
// Pad chords + a marimba-like arpeggio + soft bass + a light shaker that join in turn, then resolve.
//   swiftc -O make-music.swift -o make-music && ./make-music out.wav 26
import Foundation

let rate = 44_100.0
let args = CommandLine.arguments
let outPath = args.count > 1 ? args[1] : "temiz-bed.wav"
let length = args.count > 2 ? Double(args[2])! : 26
let beat = 60.0 / 92
let bar = beat * 4
let n = Int(length * rate)
var left = [Double](repeating: 0, count: n), right = [Double](repeating: 0, count: n)
var seed: UInt64 = 0x7E312            // deterministic noise
func noise() -> Double { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Double(Int64(bitPattern: seed >> 1)) / Double(Int64.max) }

func hz(_ midi: Int) -> Double { 440 * pow(2, Double(midi - 69) / 12) }

/// Adds a voice at `at` seconds, panned -1…1.
func add(_ at: Double, _ dur: Double, pan: Double = 0, _ voice: (Double) -> Double) {
    let s = Int(at * rate)
    let lg = sqrt((1 - pan) / 2), rg = sqrt((1 + pan) / 2)
    for i in 0..<Int(dur * rate) where s + i < n {
        let v = voice(Double(i) / rate)
        left[s + i] += v * lg
        right[s + i] += v * rg
    }
}

func pluck(_ f: Double, gain: Double, decay: Double = 5) -> (Double) -> Double {
    { t in gain * min(1, t / 0.003) * exp(-decay * t) * (sin(2 * .pi * f * t) + 0.3 * sin(4 * .pi * f * t) * exp(-8 * t)) }
}

func pad(_ notes: [Int], dur: Double, gain: Double) -> (Double) -> Double {
    { t in
        let env = min(1, t / 0.8) * min(1, (dur - t) / 0.9)
        var v = 0.0
        for m in notes {
            let f = hz(m)
            v += sin(2 * .pi * f * t) + 0.5 * sin(2 * .pi * f * 1.003 * t) + 0.12 * sin(2 * .pi * f * 2 * t)
        }
        return gain * max(0, env) * v / Double(notes.count)
    }
}

// Cmaj9, Am9, Fmaj9, G6 (MIDI)
let chords: [[Int]] = [[48, 55, 59, 62, 64], [45, 52, 55, 60, 64], [41, 48, 52, 55, 60], [43, 50, 55, 59, 64]]
let arps: [[Int]] = [[72, 76, 79, 83, 79, 76], [69, 72, 76, 79, 76, 72], [65, 69, 72, 76, 72, 69], [67, 71, 74, 76, 74, 71]]
let bars = Int(ceil(length / bar))

for b in 0..<bars {
    let t0 = Double(b) * bar
    let last = b == bars - 1
    let c = last ? 0 : b % 4
    add(t0, bar + 0.6, pad(chords[c], dur: bar + 0.6, gain: last ? 0.10 : 0.075))
    if b >= 1 {                                             // arpeggio joins in bar 2
        for i in 0..<8 where !(last && i > 3) {
            let note = arps[c][i % arps[c].count]
            add(t0 + Double(i) * beat / 2, 1.2, pan: i % 2 == 0 ? -0.35 : 0.35, pluck(hz(note), gain: 0.10))
        }
    }
    if b >= 2 {                                             // bass from bar 3
        add(t0, beat * 2, pluck(hz(chords[c][0] - 12), gain: 0.22, decay: 2.5))
        add(t0 + beat * 2, beat * 2, pluck(hz(chords[c][0] - 12), gain: 0.16, decay: 2.5))
    }
    if b >= 4 && !last {                                    // shaker from bar 5
        for i in 0..<8 {
            add(t0 + Double(i) * beat / 2, 0.06, pan: 0.2) { t in
                (i % 2 == 0 ? 0.05 : 0.03) * exp(-70 * t) * noise()
            }
        }
    }
    if last {                                               // a high sparkle on the resolve
        for (k, m) in [84, 88, 91, 96].enumerated() {
            add(t0 + 0.08 * Double(k), 1.5, pan: Double(k) * 0.2 - 0.3, pluck(hz(m), gain: 0.06, decay: 3))
        }
    }
}

// Gentle fade-in, 1.6 s fade-out, normalize to -1 dBFS.
let peak = max(left.map(abs).max()!, right.map(abs).max()!)
let norm = 0.89 / max(peak, 1e-9)
let fadeIn = Int(0.4 * rate), fadeOut = Int(1.6 * rate)
var data = Data()
func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
data.append("RIFF".data(using: .ascii)!); u32(UInt32(36 + n * 4))
data.append("WAVEfmt ".data(using: .ascii)!); u32(16); u16(1); u16(2)
u32(UInt32(rate)); u32(UInt32(rate) * 4); u16(4); u16(16)
data.append("data".data(using: .ascii)!); u32(UInt32(n * 4))
for i in 0..<n {
    let g = norm * min(1, Double(i) / Double(fadeIn)) * min(1, Double(n - i) / Double(fadeOut))
    for v in [left[i], right[i]] {
        withUnsafeBytes(of: Int16(max(-1, min(1, v * g)) * 32767).littleEndian) { data.append(contentsOf: $0) }
    }
}
try! data.write(to: URL(fileURLWithPath: outPath))
print("wrote \(String(format: "%.1f", length)) s to \(outPath)")
