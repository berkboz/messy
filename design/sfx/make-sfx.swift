// Synthesizes Temiz's sound effects as 44.1 kHz mono WAV files.
//   swiftc -O make-sfx.swift -o make-sfx && ./make-sfx ../../Resources/Sounds
import Foundation

let rate = 44_100.0
var rng = SystemRandomNumberGenerator()

func silence(_ seconds: Double) -> [Double] { Array(repeating: 0, count: Int(seconds * rate)) }

/// A soft, marimba-like note: a sine plus a quiet octave, with a fast attack and exponential decay.
func pluck(_ freq: Double, length: Double = 0.6, decay: Double = 6, gain: Double = 0.5) -> [Double] {
    (0..<Int(length * rate)).map { i in
        let t = Double(i) / rate
        let env = min(1, t / 0.004) * exp(-decay * t)
        return gain * env * (sin(2 * .pi * freq * t) + 0.25 * sin(2 * .pi * freq * 2 * t) + 0.08 * sin(2 * .pi * freq * 3 * t))
    }
}

/// Filtered noise whose band moves from `from` to `to` Hz: a whoosh up or a "fwip" down.
func whoosh(length: Double, from: Double, to: Double, gain: Double = 0.35, attack: Double = 0.4) -> [Double] {
    let n = Int(length * rate)
    var low = 0.0, band = 0.0
    return (0..<n).map { i in
        let p = Double(i) / Double(n)
        let cutoff = from * pow(to / from, p)
        let f = 2 * sin(.pi * cutoff / rate)             // state-variable filter
        let x = Double.random(in: -1...1, using: &rng)
        low += f * band
        let high = x - low - 0.6 * band
        band += f * high
        let env = p < attack ? p / attack : pow(1 - (p - attack) / (1 - attack), 2)
        return gain * env * band
    }
}

func mix(_ tracks: [(at: Double, samples: [Double])], length: Double) -> [Double] {
    var out = silence(length)
    for (at, s) in tracks {
        let start = Int(at * rate)
        for (i, v) in s.enumerated() where start + i < out.count { out[start + i] += v }
    }
    let peak = out.map(abs).max() ?? 1
    let norm = peak > 0.9 ? 0.9 / peak : 1
    // 5 ms fade at both ends so nothing clicks.
    let fade = Int(0.005 * rate)
    return out.enumerated().map { i, v in
        v * norm * min(1, Double(i) / Double(fade)) * min(1, Double(out.count - i) / Double(fade))
    }
}

func note(_ name: String) -> Double {
    let names = ["C": -9, "D": -7, "E": -5, "F": -4, "G": -2, "A": 0, "B": 2]
    let octave = Int(String(name.last!))!
    return 440 * pow(2, Double(names[String(name.first!)]! + (octave - 4) * 12) / 12)
}

func writeWAV(_ samples: [Double], to url: URL) {
    var data = Data()
    func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
    func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
    let pcm = samples.map { Int16(max(-1, min(1, $0)) * 32767) }
    data.append("RIFF".data(using: .ascii)!); u32(UInt32(36 + pcm.count * 2))
    data.append("WAVEfmt ".data(using: .ascii)!); u32(16); u16(1); u16(1)
    u32(UInt32(rate)); u32(UInt32(rate) * 2); u16(2); u16(16)
    data.append("data".data(using: .ascii)!); u32(UInt32(pcm.count * 2))
    for s in pcm { withUnsafeBytes(of: s.littleEndian) { data.append(contentsOf: $0) } }
    try! data.write(to: url)
}

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

let sounds: [String: [Double]] = [
    // Scan starts: an airy whoosh rising into a soft note.
    "scan": mix([(0, whoosh(length: 0.55, from: 350, to: 3200, gain: 0.30)),
                 (0.38, pluck(note("E6"), length: 0.45, decay: 9, gain: 0.25))], length: 0.85),
    // Results are ready: two gentle notes.
    "found": mix([(0, pluck(note("G5"), length: 0.5, gain: 0.4)),
                  (0.11, pluck(note("C6"), length: 0.6, gain: 0.4))], length: 0.75),
    // Something to look at: the same shape, falling and lower.
    "warn": mix([(0, pluck(note("A4"), length: 0.5, decay: 7, gain: 0.45)),
                 (0.13, pluck(note("F4"), length: 0.6, decay: 7, gain: 0.45))], length: 0.8),
    // Done: a sparkly rising arpeggio with a few high glints.
    "done": mix([(0.00, pluck(note("C6"), gain: 0.35)), (0.07, pluck(note("E6"), gain: 0.35)),
                 (0.14, pluck(note("G6"), gain: 0.35)), (0.21, pluck(note("C7"), length: 0.9, decay: 4, gain: 0.35)),
                 (0.30, pluck(5274, length: 0.3, decay: 14, gain: 0.08)), (0.42, pluck(6272, length: 0.3, decay: 14, gain: 0.07)),
                 (0.55, pluck(5920, length: 0.3, decay: 14, gain: 0.06))], length: 1.3),
    // Moved to the Trash: a short downward fwip.
    "trash": mix([(0, whoosh(length: 0.28, from: 3500, to: 260, gain: 0.45, attack: 0.15))], length: 0.32),
    // A tick for checkboxes and switches.
    "tick": mix([(0, pluck(1760, length: 0.045, decay: 90, gain: 0.25))], length: 0.05),
]
for (name, samples) in sounds { writeWAV(samples, to: out.appendingPathComponent("\(name).wav")) }
print("wrote \(sounds.count) sounds to \(out.path)")
