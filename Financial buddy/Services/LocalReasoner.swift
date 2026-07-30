//
//  LocalReasoner.swift
//  Finance buddy
//
//  A lightweight, on-device stand-in for the real backend reasoner. It
//  exists only so the Ask tab is usable before the server endpoint is
//  live. It parses an amount + a rough category from the question, adds
//  estimated second-order costs, and reasons against the user's headroom.
//
//  This is intentionally heuristic and always tells the user it's an
//  estimate. Once `AskConfig.endpoint` is set, this code is bypassed.
//

import Foundation

enum LocalReasoner {

    /// Rough second-order costs for a purchase, expressed as a monthly
    /// figure derived from the headline monthly amount.
    private struct Profile {
        let keywords: [String]
        let label: String
        /// Extra ongoing monthly cost as a multiple of the headline amount.
        let hiddenMultiplier: Double
        let notes: String
    }

    private nonisolated static let profiles: [Profile] = [
        Profile(keywords: ["car", "vehicle", "lease", "motor", "automobile"],
                label: "a car",
                hiddenMultiplier: 0.6,
                notes: "insurance, fuel, tax, servicing and the odd repair"),
        Profile(keywords: ["flat", "apartment", "rent", "house", "mortgage", "move"],
                label: "a home",
                hiddenMultiplier: 0.35,
                notes: "council tax, utilities, contents insurance and maintenance"),
        Profile(keywords: ["dog", "puppy", "cat", "pet"],
                label: "a pet",
                hiddenMultiplier: 0.5,
                notes: "food, insurance, vet visits and grooming"),
        Profile(keywords: ["gym", "membership", "subscription", "phone", "streaming"],
                label: "this subscription",
                hiddenMultiplier: 0.05,
                notes: "occasional add-ons or price rises"),
        Profile(keywords: ["holiday", "trip", "flight", "travel", "vacation"],
                label: "this trip",
                hiddenMultiplier: 0.4,
                notes: "food, transfers, activities and spending money"),
    ]

    nonisolated static func answer(to question: String, finances: Finances) -> String {
        let lower = question.lowercased()
        let amount = parseAmount(from: lower)
        let isMonthly = lower.contains("month") || lower.contains("/mo") || lower.contains("a month")
        let profile = profiles.first { p in p.keywords.contains { lower.contains($0) } }

        let headroom = finances.monthlyHeadroom
        let safe = finances.safeToSpendToday()

        guard let amount, amount > 0 else {
            return """
            Tell me the amount and I'll weigh it up. Right now you've got \
            \(Money.string(headroom)) of monthly headroom and \(Money.string(safe)) \
            safe to spend before payday.

            (Estimate from on-device reasoning — the full assistant isn't connected yet.)
            """
        }

        // Build the picture.
        let hidden = (profile?.hiddenMultiplier ?? 0) * amount
        let trueMonthly = isMonthly ? amount + hidden : hidden // one-off: only ongoing costs recur
        let thingLabel = profile?.label ?? "that"

        var lines: [String] = []

        if isMonthly {
            lines.append("A \(Money.string(amount))/month commitment for \(thingLabel) rarely stops there.")
            if let profile, hidden > 0 {
                lines.append("Budget for \(profile.notes) too — realistically closer to \(Money.string(trueMonthly)) a month all-in.")
            }
        } else {
            lines.append("\(Money.string(amount)) upfront for \(thingLabel).")
            if let profile, hidden > 0 {
                lines.append("Watch the ongoing cost afterwards — roughly \(Money.string(hidden)) a month for \(profile.notes).")
            }
        }

        // The verdict against headroom.
        let compareAgainst = isMonthly ? trueMonthly : hidden
        let remaining = headroom - compareAgainst

        if isMonthly {
            if remaining < 0 {
                lines.append("That's more than your \(Money.string(headroom)) of monthly headroom — it would put you \(Money.string(abs(remaining))) short every month. I'd hold off, or trim other commitments first.")
            } else if remaining < headroom * 0.25 {
                lines.append("It fits inside your \(Money.string(headroom)) headroom, but only just — you'd be left with about \(Money.string(remaining)) of breathing room. Doable, but tight.")
            } else {
                lines.append("That sits comfortably within your \(Money.string(headroom)) of monthly headroom, leaving around \(Money.string(remaining)) spare. Affordable.")
            }
        } else {
            if amount > safe {
                lines.append("Right now only \(Money.string(safe)) is safe to spend before payday, so paying \(Money.string(amount)) upfront today would eat into money already promised to bills.")
            } else {
                lines.append("You've got \(Money.string(safe)) safe to spend before payday, so the upfront cost is covered — just keep the ongoing costs in mind.")
            }
        }

        lines.append("(Estimate from on-device reasoning — the full assistant isn't connected yet.)")
        return lines.joined(separator: "\n\n")
    }

    /// Pulls the first monetary amount out of a question. Handles "£380",
    /// "380", "1,200", "1.2k".
    private nonisolated static func parseAmount(from text: String) -> Double? {
        // Match numbers with optional thousands separators / decimals / k suffix.
        let pattern = #"£?\s?([0-9][0-9,]*(?:\.[0-9]+)?)(k)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let numberRange = Range(match.range(at: 1), in: text) else { return nil }

        let raw = text[numberRange].replacingOccurrences(of: ",", with: "")
        guard var value = Double(raw) else { return nil }

        if match.range(at: 2).location != NSNotFound {
            value *= 1000 // "k" suffix
        }
        return value
    }
}
