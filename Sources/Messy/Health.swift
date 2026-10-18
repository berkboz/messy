import SwiftUI

/// A 0–100 score with the reasons behind it. Every deduction is listed, so the number is never a mystery.
struct Health {
    let score: Int
    let reasons: [String]

    var label: String {
        switch score {
        case 90...: "Great"
        case 75..<90: "Good"
        case 60..<75: "Fair"
        case 40..<60: "Needs care"
        default: "Poor"
        }
    }

    var color: Color {
        switch score {
        case 75...: Brand.emerald
        case 60..<75: .yellow
        case 40..<60: .orange
        default: .red
        }
    }

    /// `threats` (strong signals) and `junk` are nil until those scans have run; `weakThreats` are
    /// risky findings with a weaker signal, such as a non-Apple certificate.
    static func compute(stats: SystemStats, threats: Int?, weakThreats: Int = 0, junk: Int64?) -> Health {
        var score = 100
        var reasons: [String] = []
        func deduct(_ n: Int, _ why: String) { score -= n; reasons.append(why) }

        if stats.diskTotal > 0 {
            let free = Double(stats.diskFree) / Double(stats.diskTotal)
            if free < 0.10 { deduct(30, "Startup disk is almost full (\(Fmt.bytes(stats.diskFree)) free)") }
            else if free < 0.20 { deduct(15, "Startup disk is getting full (\(Fmt.bytes(stats.diskFree)) free)") }
        }
        if let threats, threats > 0 {
            deduct(min(40, threats * 20), "\(plural(threats, "risky item")) in Protect")
        }
        if weakThreats > 0 {
            deduct(min(10, weakThreats * 5), "\(plural(weakThreats, "item")) to review in Protect")
        }
        if let h = stats.battery?.health, h < 80 { deduct(10, "Battery holds \(h)% of its original charge") }
        if stats.pressure >= 4 { deduct(25, "Memory pressure is critical") }
        else if stats.pressure >= 2 { deduct(10, "Memory pressure is high") }
        if stats.cpuAverage > 0.8 { deduct(10, "CPU has been busy for the last few minutes") }
        if let junk, junk > 5_000_000_000 { deduct(5, "\(Fmt.bytes(junk)) of junk can be cleaned") }

        return Health(score: max(0, score), reasons: reasons)
    }
}
