//
//  ProposedAction.swift
//  Headroom
//
//  Staged writes. Tools NEVER mutate the store: when the user reports a
//  transaction ("I spent £20 on lunch"), a tool parses it into one of
//  these and it rides back on the AskResult. Dictation mishears amounts
//  (thirteen/thirty), so nothing is written until the user confirms.
//

import Foundation

/// A store mutation the assistant wants to make, awaiting the user's
/// confirmation. Confirmation UI comes later; for now these sit in
/// ChatViewModel.pendingActions and the assistant asks in words.
enum ProposedAction: Identifiable, Equatable, Sendable {
    case logExpense(ExpenseDraft)
    case logIncome(IncomeDraft)
    case addRecurring(RecurringDraft)
    case updateBalance(BalanceDraft)

    /// A one-off expense the user reported having spent.
    struct ExpenseDraft: Equatable, Sendable {
        let id: UUID
        var name: String
        var amount: Double
        var date: Date
        /// 0...1 — how sure we are the fields were heard/parsed right.
        var confidence: Double

        nonisolated init(id: UUID = UUID(), name: String, amount: Double, date: Date, confidence: Double) {
            self.id = id
            self.name = name
            self.amount = amount
            self.date = date
            self.confidence = confidence
        }
    }

    /// Money the user reported coming in.
    struct IncomeDraft: Equatable, Sendable {
        let id: UUID
        var name: String
        var amount: Double
        var date: Date
        var confidence: Double

        nonisolated init(id: UUID = UUID(), name: String, amount: Double, date: Date, confidence: Double) {
            self.id = id
            self.name = name
            self.amount = amount
            self.date = date
            self.confidence = confidence
        }
    }

    /// A new monthly commitment the user wants to add.
    struct RecurringDraft: Equatable, Sendable {
        let id: UUID
        var name: String
        var amount: Double
        /// Day of the month it falls due (1...31).
        var dueDay: Int
        var confidence: Double

        nonisolated init(id: UUID = UUID(), name: String, amount: Double, dueDay: Int, confidence: Double) {
            self.id = id
            self.name = name
            self.amount = amount
            self.dueDay = dueDay
            self.confidence = confidence
        }
    }

    /// A correction to the current account balance.
    struct BalanceDraft: Equatable, Sendable {
        let id: UUID
        var newBalance: Double
        var confidence: Double

        nonisolated init(id: UUID = UUID(), newBalance: Double, confidence: Double) {
            self.id = id
            self.newBalance = newBalance
            self.confidence = confidence
        }
    }

    nonisolated var id: UUID {
        switch self {
        case .logExpense(let draft): return draft.id
        case .logIncome(let draft): return draft.id
        case .addRecurring(let draft): return draft.id
        case .updateBalance(let draft): return draft.id
        }
    }

    nonisolated var confidence: Double {
        switch self {
        case .logExpense(let draft): return draft.confidence
        case .logIncome(let draft): return draft.confidence
        case .addRecurring(let draft): return draft.confidence
        case .updateBalance(let draft): return draft.confidence
        }
    }

    /// One line the UI (or the assistant's prose) can use when asking the
    /// user to confirm.
    nonisolated var summary: String {
        switch self {
        case .logExpense(let draft):
            return "Log \(Money.string(draft.amount)) spent on \(draft.name) (\(draft.date.formatted(date: .abbreviated, time: .omitted)))"
        case .logIncome(let draft):
            return "Log \(Money.string(draft.amount)) in from \(draft.name) (\(draft.date.formatted(date: .abbreviated, time: .omitted)))"
        case .addRecurring(let draft):
            return "Add \(draft.name) at \(Money.string(draft.amount))/month, due on day \(draft.dueDay)"
        case .updateBalance(let draft):
            return "Set balance to \(Money.string(draft.newBalance))"
        }
    }
}

// MARK: - Parsing helpers (Tier 0 — deterministic, unit-tested)

extension ProposedAction {

    /// Parses a spoken/typed date like "today", "yesterday", "tomorrow" or
    /// "2026-07-18". Falls back to today, with `parsed: false` so the
    /// confidence score can reflect the guess.
    nonisolated static func parseDate(_ text: String,
                          asOf today: Date = Date(),
                          calendar: Calendar = .current) -> (date: Date, parsed: Bool) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let start = calendar.startOfDay(for: today)

        switch trimmed {
        case "today", "now", "just now", "this morning", "tonight", "this evening":
            return (start, true)
        case "yesterday", "last night":
            return (calendar.date(byAdding: .day, value: -1, to: start) ?? start, true)
        case "tomorrow":
            return (calendar.date(byAdding: .day, value: 1, to: start) ?? start, true)
        default:
            break
        }

        // ISO-style yyyy-MM-dd.
        let parts = trimmed.split(separator: "-")
        if parts.count == 3,
           let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
           year >= 2000, (1...12).contains(month), (1...31).contains(day) {
            var components = DateComponents()
            components.year = year
            components.month = month
            components.day = day
            if let date = calendar.date(from: components) {
                return (calendar.startOfDay(for: date), true)
            }
        }

        return (start, false)
    }

    /// Whole amounts whose spoken forms are easily misheard by dictation
    /// ("thirteen" vs "thirty", "fifteen" vs "fifty", …).
    nonisolated static func isDictationAmbiguous(_ amount: Double) -> Bool {
        guard amount >= 0, amount < 1_000_000_000, amount == amount.rounded() else { return false }
        let confusables: Set<Int> = [13, 14, 15, 16, 17, 18, 19, 30, 40, 50, 60, 70, 80, 90]
        return confusables.contains(Int(amount))
    }

    /// A deterministic confidence score: high by default, docked when the
    /// amount is a dictation confusable or the date had to be guessed.
    nonisolated static func confidence(amount: Double, dateParsed: Bool = true) -> Double {
        var score = 0.95
        if isDictationAmbiguous(amount) { score -= 0.3 }
        if !dateParsed { score -= 0.15 }
        return max(0.05, min(1, score))
    }
}
