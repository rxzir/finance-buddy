//
//  RecurrenceDetector.swift
//  Finance buddy
//
//  Pure deterministic Swift — no AI, no UI, no I/O. Takes an array of
//  parsed transactions and outputs clustered recurring commitments and
//  the detected salary.  Fully injectable (no Date() calls inside) so
//  unit tests can drive it with synthetic data.
//

import Foundation

// MARK: - Output types

enum Cadence: String, Equatable, Hashable, Codable, CaseIterable, Sendable {
    case weekly        // median gap  6–8 d
    case fourWeekly    // 26–30 d
    case monthly       // 28–31 d
    case quarterly     // 85–95 d
    case annual        // 350–380 d

    var displayName: String {
        switch self {
        case .weekly:     return "Weekly"
        case .fourWeekly: return "Every 4 weeks"
        case .monthly:    return "Monthly"
        case .quarterly:  return "Quarterly"
        case .annual:     return "Annual"
        }
    }
}

enum DetectionConfidence: String, Equatable, Codable, Sendable {
    case high, low
}

struct DetectedCommitment: Identifiable, Equatable, Sendable {
    let id: UUID
    let normalisedKey: String
    var displayName: String      // overwritten by MerchantLabeler
    var category: String         // overwritten by MerchantLabeler
    let amount: Double           // median across occurrences
    let modalDueDay: Int         // most-common day of month (1…31)
    let cadence: Cadence
    let confidence: DetectionConfidence
    let occurrenceDates: [Date]  // sorted ascending; drives the evidence line
}

struct DetectedIncome: Identifiable, Equatable, Sendable {
    let id: UUID
    let normalisedKey: String
    var displayName: String
    let amount: Double
    let nextPayday: Date
    let cadence: Cadence
    let occurrenceDates: [Date]
}

struct DetectionResult: Sendable, Equatable {
    var commitments: [DetectedCommitment]  // debits, sorted largest first
    var income: DetectedIncome?            // largest regular credit
}

// MARK: - Detector

enum RecurrenceDetector {

    // MARK: Public entry point

    static func detect(from transactions: [ParsedTransaction]) -> DetectionResult {
        let debits  = transactions.filter { $0.amount < 0 }
        let credits = transactions.filter { $0.amount > 0 }
        return DetectionResult(
            commitments: detectCommitments(from: debits),
            income: detectIncome(from: credits)
        )
    }

    // MARK: Normalisation (public for unit tests)

    /// Strips noise so the same merchant always hashes to the same key.
    /// Result is UPPER CASE, whitespace-collapsed, with digits, dates, store
    /// numbers and common legal suffixes removed.
    static func normalise(_ raw: String) -> String {
        var s = raw.uppercased()

        // Date-like substrings: "13 JAN", "13/01/24", "2024-01-13"
        s = s.replacingOccurrences(
            of: #"\b\d{1,2}\s+(?:JAN|FEB|MAR|APR|MAY|JUN|JUL|AUG|SEP|OCT|NOV|DEC)\b"#,
            with: " ", options: .regularExpression)
        s = s.replacingOccurrences(
            of: #"\d{1,4}[/\-\.]\d{1,2}(?:[/\-\.]\d{2,4})?"#,
            with: " ", options: .regularExpression)

        // Digit runs of 3+ (account refs, store numbers like 001, card last-4, order IDs)
        s = s.replacingOccurrences(of: #"\d{3,}"#, with: " ", options: .regularExpression)

        // Store/branch numbers like #042 or *12
        s = s.replacingOccurrences(of: #"[#\*]\d+"#, with: " ", options: .regularExpression)

        // Card references
        s = s.replacingOccurrences(of: #"\bCARD\s*\d*\b"#, with: " ", options: .regularExpression)

        // Legal / payment noise words
        let noise = ["DIRECT DEBIT", "STANDING ORDER", "FASTER PAYMENT",
                     " PLC", " LTD", " LIMITED", " INC", " CO ", " UK ", " GB ",
                     "PURCHASE", " FP ", " DD ", " SO "]
        for n in noise { s = s.replacingOccurrences(of: n, with: " ") }

        // Collapse whitespace
        s = s.components(separatedBy: .whitespaces).filter { !$0.isEmpty }.joined(separator: " ")
        return s.trimmingCharacters(in: .whitespaces)
    }

    // MARK: Commitment detection (debits)

    private static func detectCommitments(from debits: [ParsedTransaction]) -> [DetectedCommitment] {
        let filtered = debits.filter { !isLikelyTransfer($0.description) }
        var results: [DetectedCommitment] = []

        for (key, group) in cluster(filtered) {
            let sorted = group.sorted { $0.date < $1.date }
            let dates  = sorted.map(\.date)
            guard let cadence = classifyCadence(dates: dates) else { continue }
            guard sorted.count >= minimumOccurrences(cadence) else { continue }

            let amounts = sorted.map { abs($0.amount) }
            let conf: DetectionConfidence = (cadence == .annual || sorted.count == 1) ? .low : .high

            results.append(DetectedCommitment(
                id: UUID(),
                normalisedKey: key,
                displayName: key.capitalized,
                category: "Other",
                amount: median(amounts),
                modalDueDay: modalDay(dates),
                cadence: cadence,
                confidence: conf,
                occurrenceDates: dates
            ))
        }
        return results.sorted { $0.amount > $1.amount }
    }

    // MARK: Income detection (credits)

    private static func detectIncome(from credits: [ParsedTransaction]) -> DetectedIncome? {
        let filtered = credits.filter { !isLikelyTransfer($0.description) }
        var candidates: [(String, DetectedCommitment)] = []

        for (key, group) in cluster(filtered) {
            let sorted = group.sorted { $0.date < $1.date }
            let dates  = sorted.map(\.date)
            guard let cadence = classifyCadence(dates: dates) else { continue }
            guard sorted.count >= minimumOccurrences(cadence) else { continue }

            let amounts = sorted.map { abs($0.amount) }
            let conf: DetectionConfidence = (cadence == .annual || sorted.count == 1) ? .low : .high

            candidates.append((key, DetectedCommitment(
                id: UUID(),
                normalisedKey: key,
                displayName: key.capitalized,
                category: "Salary",
                amount: median(amounts),
                modalDueDay: modalDay(dates),
                cadence: cadence,
                confidence: conf,
                occurrenceDates: dates
            )))
        }

        guard let (_, best) = candidates.max(by: { $0.1.amount < $1.1.amount }) else { return nil }

        let nextPayday: Date = {
            // Avoid Calendar.current (@MainActor in Swift 6) inside Sendable context
            let cal = Calendar(identifier: .gregorian)
            let today = cal.startOfDay(for: Date())
            return Finances.nextOccurrence(ofDueDay: best.modalDueDay,
                                           onOrAfter: today,
                                           calendar: cal)
        }()

        return DetectedIncome(
            id: best.id,
            normalisedKey: best.normalisedKey,
            displayName: best.displayName,
            amount: best.amount,
            nextPayday: nextPayday,
            cadence: best.cadence,
            occurrenceDates: best.occurrenceDates
        )
    }

    // MARK: Clustering — normalised key + amount within 5 %

    private static func cluster(_ txs: [ParsedTransaction]) -> [String: [ParsedTransaction]] {
        var clusters: [String: [ParsedTransaction]] = [:]
        for tx in txs {
            let key = normalise(tx.description)
            guard !key.isEmpty else { continue }
            // Try to find an existing cluster whose key fuzzy-matches and
            // whose reference amount is within 5 % of this transaction.
            var merged = false
            for existingKey in clusters.keys where keysMatch(key, existingKey) {
                if let ref = clusters[existingKey]?.first {
                    let ratio = abs(tx.amount) / abs(ref.amount)
                    if ratio >= 0.95 && ratio <= 1.05 {
                        clusters[existingKey]?.append(tx)
                        merged = true
                        break
                    }
                }
            }
            if !merged { clusters[key, default: []].append(tx) }
        }
        return clusters
    }

    /// One key is a prefix of the other (both ≥4 chars) — covers "AMAZON"
    /// matching "AMAZON PRIME".
    private static func keysMatch(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        guard a.count >= 4, b.count >= 4 else { return false }
        let (shorter, longer) = a.count <= b.count ? (a, b) : (b, a)
        return longer.hasPrefix(shorter)
    }

    // MARK: Cadence classification

    private static func classifyCadence(dates: [Date]) -> Cadence? {
        guard dates.count >= 2 else { return .annual } // single occurrence → annual candidate
        let sorted = dates.sorted()
        var gaps: [Double] = []
        for i in 1..<sorted.count {
            gaps.append(sorted[i].timeIntervalSince(sorted[i - 1]) / 86_400)
        }
        let med = median(gaps)
        switch med {
        case 6...8:       return .weekly
        case 26...30:     return .fourWeekly
        case 28...31:     return .monthly
        case 85...95:     return .quarterly
        case 350...380:   return .annual
        default:          return nil
        }
    }

    private static func minimumOccurrences(_ cadence: Cadence) -> Int {
        switch cadence {
        case .weekly, .fourWeekly, .monthly: return 3
        case .quarterly:                      return 2
        case .annual:                         return 1
        }
    }

    // MARK: Helpers

    private static func isLikelyTransfer(_ desc: String) -> Bool {
        let u = desc.uppercased()
        return ["TRANSFER", " TFR", "XFER", "INTER-ACCOUNT",
                "INTERNAL", "OWN ACCOUNT"].contains(where: u.contains)
    }

    private static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let s = values.sorted()
        let m = s.count / 2
        return s.count % 2 == 0 ? (s[m - 1] + s[m]) / 2 : s[m]
    }

    private static func modalDay(_ dates: [Date]) -> Int {
        let cal = Calendar(identifier: .gregorian)
        let days = dates.map { cal.component(.day, from: $0) }
        let counts = Dictionary(grouping: days, by: { $0 }).mapValues(\.count)
        return counts.max(by: { $0.value < $1.value })?.key ?? 1
    }
}
