import SwiftUI

/// Squarified treemap layout (Bruls, Huizing & van Wijk). `values` must be sorted largest first.
enum Treemap {
    static func squarify(_ values: [Double], in rect: CGRect) -> [CGRect] {
        let total = values.reduce(0, +)
        guard total > 0, rect.width > 0, rect.height > 0 else { return values.map { _ in .zero } }
        let scaled = values.map { $0 / total * Double(rect.width * rect.height) }
        var result = [CGRect](repeating: .zero, count: values.count)
        var remaining = rect
        var i = 0

        func worst(_ row: [Double], _ side: Double) -> Double {
            let s = row.reduce(0, +)
            guard let mx = row.max(), let mn = row.min(), s > 0, mn > 0 else { return .infinity }
            return max(side * side * mx / (s * s), s * s / (side * side * mn))
        }

        while i < scaled.count {
            let side = Double(min(remaining.width, remaining.height))
            var row = [i]
            var j = i + 1
            while j < scaled.count,
                  worst((row + [j]).map { scaled[$0] }, side) <= worst(row.map { scaled[$0] }, side) {
                row.append(j)
                j += 1
            }
            let rowSum = row.reduce(0) { $0 + scaled[$1] }
            if remaining.width >= remaining.height {
                let w = CGFloat(rowSum / Double(remaining.height))
                var y = remaining.minY
                for k in row {
                    let h = CGFloat(scaled[k]) / w
                    result[k] = CGRect(x: remaining.minX, y: y, width: w, height: h)
                    y += h
                }
                remaining = CGRect(x: remaining.minX + w, y: remaining.minY,
                                   width: max(0, remaining.width - w), height: remaining.height)
            } else {
                let h = CGFloat(rowSum / Double(remaining.width))
                var x = remaining.minX
                for k in row {
                    let w = CGFloat(scaled[k]) / h
                    result[k] = CGRect(x: x, y: remaining.minY, width: w, height: h)
                    x += w
                }
                remaining = CGRect(x: remaining.minX, y: remaining.minY + h,
                                   width: remaining.width, height: max(0, remaining.height - h))
            }
            i = j
        }
        return result
    }
}

struct SpaceMapView: View {
    let entries: [DiskEntry]
    let open: (DiskEntry) -> Void
    let trash: (DiskEntry) -> Void

    /// Keep the map readable: the largest items get their own box, the rest share one.
    private var shown: [DiskEntry] { Array(entries.filter { $0.size > 0 }.prefix(48)) }
    private var restSize: Int64 { entries.filter { $0.size > 0 }.dropFirst(48).reduce(0) { $0 + $1.size } }

    var body: some View {
        GeometryReader { geo in
            let items = shown
            let values = items.map { Double($0.size) } + (restSize > 0 ? [Double(restSize)] : [])
            let rects = Treemap.squarify(values, in: CGRect(origin: .zero, size: geo.size))
            ZStack(alignment: .topLeading) {
                ForEach(Array(items.enumerated()), id: \.element.id) { i, e in
                    box(rects[i], title: e.url.lastPathComponent.displaySafe, size: e.size, index: i, isDir: e.isDir)
                        .onTapGesture(count: 2) { open(e) }
                        .contextMenu {
                            if e.isDir { Button("Open") { open(e) } }
                            Button("Show in Finder") { FS.reveal(e.url) }
                            Divider()
                            Button("Move to Trash…") { trash(e) }
                        }
                }
                if restSize > 0, let r = rects.last {
                    box(r, title: "Other items", size: restSize, index: items.count, isDir: false)
                }
            }
        }
    }

    private func box(_ r: CGRect, title: String, size: Int64, index: Int, isDir: Bool) -> some View {
        let color = Color(hue: 0.40 + Double(index % 6) * 0.035,
                          saturation: 0.55,
                          brightness: 0.62 - Double(index % 3) * 0.08)
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 6)
                .fill(LinearGradient(colors: [color, color.opacity(0.75)], startPoint: .topLeading, endPoint: .bottomTrailing))
            if r.width > 70, r.height > 34 {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        if isDir { Image(systemName: "folder.fill").font(.caption2) }
                        Text(title).font(.caption.bold()).lineLimit(1)
                    }
                    Text(Fmt.bytes(size)).font(.caption2).opacity(0.85)
                }
                .foregroundStyle(.white)
                .padding(6)
            }
        }
        .frame(width: max(0, r.width - 3), height: max(0, r.height - 3))
        .offset(x: r.minX + 1.5, y: r.minY + 1.5)
        .help("\(title) · \(Fmt.bytes(size))\(isDir ? " · double-click to open" : "")")
    }
}
