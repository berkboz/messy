// Normalizes a one-row sprite sheet: finds each frame by the transparent gaps between them, keeps
// the sheet's shared vertical span (so a hop still rises), centres each frame horizontally, and
// writes equal square cells in one row.
//   swiftc -O slice-sprites.swift -o slice && ./slice in.png out.png <frames> <cell px>
import AppKit

let a = CommandLine.arguments
let count = Int(a[3])!, cell = Int(a[4])!
let src = NSImage(contentsOfFile: a[1])!
var r = CGRect(origin: .zero, size: src.size)
let cg = src.cgImage(forProposedRect: &r, context: nil, hints: nil)!
let w = cg.width, h = cg.height
var px = [UInt8](repeating: 0, count: w * h * 4)
let cs = CGColorSpaceCreateDeviceRGB()
let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: cs,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
func alpha(_ x: Int, _ y: Int) -> UInt8 { px[(y * w + x) * 4 + 3] }

// Column runs that contain anything opaque.
let filled = (0..<w).map { x in (0..<h).contains { alpha(x, $0) > 16 } }
var runs: [(Int, Int)] = []
var start: Int?
for x in 0..<w {
    if filled[x], start == nil { start = x }
    if !filled[x], let s = start { runs.append((s, x - 1)); start = nil }
}
if let s = start { runs.append((s, w - 1)) }
// Small runs (dust puffs, sparkles) join the nearest large run until there are `count` frames.
while runs.count > count {
    let i = runs.indices.min { (runs[$0].1 - runs[$0].0) < (runs[$1].1 - runs[$1].0) }!
    let left = i > 0 ? runs[i].0 - runs[i - 1].1 : Int.max
    let right = i < runs.count - 1 ? runs[i + 1].0 - runs[i].1 : Int.max
    let j = left <= right ? i - 1 : i + 1
    runs[min(i, j)] = (min(runs[i].0, runs[j].0), max(runs[i].1, runs[j].1))
    runs.remove(at: max(i, j))
}
guard runs.count == count else { fatalError("found \(runs.count) frames, expected \(count)") }

// Shared vertical span across the whole sheet.
var top = h, bottom = 0
for y in 0..<h where (0..<w).contains(where: { alpha($0, y) > 16 }) { top = min(top, y); bottom = max(bottom, y) }
let span = bottom - top
let widest = runs.map { $0.1 - $0.0 }.max()!
let side = CGFloat(max(span, widest)) * 1.08
let scale = CGFloat(cell) / side

let out = CGContext(data: nil, width: cell * count, height: cell, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
out.interpolationQuality = .high
for (i, run) in runs.enumerated() {
    // Pixel rows are top-down here; CGImage cropping uses the same top-left origin.
    let crop = cg.cropping(to: CGRect(x: run.0, y: top, width: run.1 - run.0 + 1, height: span + 1))!
    let fw = CGFloat(run.1 - run.0 + 1) * scale, fh = CGFloat(span + 1) * scale
    out.draw(crop, in: CGRect(x: CGFloat(i * cell) + (CGFloat(cell) - fw) / 2, y: (CGFloat(cell) - fh) / 2, width: fw, height: fh))
}
try! NSBitmapImageRep(cgImage: out.makeImage()!).representation(using: .png, properties: [:])!
    .write(to: URL(fileURLWithPath: a[2]))
print("\(count) frames → \(a[2])")
