//
//  AskResult.swift
//  Finance buddy
//
//  What one turn of the assistant produces: the prose it says, an
//  optional structured card (nothing renders these yet — they exist so
//  the card UI later is a pure view change), and any staged writes
//  awaiting the user's confirmation.
//

import Foundation
import FoundationModels

/// The assistant's answer to one question.
struct AskResult: Sendable {
    /// What the assistant says. Never empty: falls back to the card's
    /// rendered prose, which is what keeps MessageBubble working unchanged.
    var text: String
    /// Structured payload for a future card UI.
    var card: AskCard?
    /// Staged writes for the user to confirm — never applied silently.
    var proposedActions: [ProposedAction]

    nonisolated init(text: String, card: AskCard? = nil, proposedActions: [ProposedAction] = []) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        self.text = trimmed.isEmpty ? (card?.renderedText() ?? trimmed) : trimmed
        self.card = card
        self.proposedActions = proposedActions
    }
}

// MARK: - Cards

/// A structured answer where the question fits a known shape.
enum AskCard: Equatable, Sendable {
    case affordability(AffordabilityCard)
    case spendingCapacity(SpendingCapacityCard)
    case commitmentSummary(CommitmentSummaryCard)
    case proposal(ProposalCard)

    /// Flattens the card into plain prose for the transcript.
    nonisolated func renderedText() -> String {
        switch self {
        case .affordability(let card): return card.renderedText()
        case .spendingCapacity(let card): return card.renderedText()
        case .commitmentSummary(let card): return card.renderedText()
        case .proposal(let card): return card.renderedText()
        }
    }
}

/// Staged writes awaiting a yes/no. Built in Swift from the tools'
/// ProposedActions — never generated — so the approval ask is always the
/// same shape, whatever the model felt like saying.
struct ProposalCard: Equatable, Sendable {
    var actions: [ProposedAction]

    nonisolated func renderedText() -> String {
        guard !actions.isEmpty else { return "" }
        let list = actions.map(\.summary).joined(separator: "; ")
        var text = "Ready to save: \(list)."
        if actions.contains(where: { $0.confidence < 0.75 }) {
            text += " Double-check the amount — dictation can mishear numbers."
        }
        return text
    }
}

/// "Can I afford X a month?" — judged against monthly headroom.
@Generable
struct AffordabilityCard: Equatable, Sendable {
    @Guide(description: "The monthly cost being judged, exactly as a tool reported it")
    var monthlyAmount: Double

    @Guide(description: "Monthly headroom left after this cost, exactly as a tool reported it")
    var headroomAfter: Double

    @Guide(description: "The tool's verdict", .anyOf(["comfortable", "tight", "unaffordable"]))
    var verdict: String

    @Guide(description: "Assumptions made, like second-order costs included", .maximumCount(4))
    var assumptions: [String]

    nonisolated func renderedText() -> String {
        var text: String
        if headroomAfter < 0 {
            text = "\(Money.string(monthlyAmount)) a month would put you \(Money.string(abs(headroomAfter))) short every month."
        } else {
            text = "\(Money.string(monthlyAmount)) a month would leave you \(Money.string(headroomAfter)) of monthly headroom."
        }
        switch verdict {
        case "comfortable": text += " That fits comfortably."
        case "tight": text += " It fits, but only just."
        default: text += " I'd hold off, or trim other commitments first."
        }
        if !assumptions.isEmpty {
            text += " Assuming \(assumptions.joined(separator: ", "))."
        }
        return text
    }
}

/// "How much can I spend today / this week / this month?"
@Generable
struct SpendingCapacityCard: Equatable, Sendable {
    @Guide(description: "The free amount, exactly as a tool reported it")
    var amount: Double

    @Guide(description: "The window", .anyOf(["today", "this week", "this month", "until payday"]))
    var period: String

    @Guide(description: "How the figure was worked out, exactly as the tool put it")
    var basis: String

    nonisolated func renderedText() -> String {
        var text: String
        if amount < 0 {
            text = "You're \(Money.string(abs(amount))) over for \(period) — money already promised to bills."
        } else {
            text = "You've got \(Money.string(amount)) free \(period == "today" ? "today" : "for \(period)")."
        }
        if !basis.isEmpty {
            text += " That's \(basis)."
        }
        return text
    }
}

/// "What are my commitments?" — the recurring monthly picture.
@Generable
struct CommitmentSummaryCard: Equatable, Sendable {
    @Guide(description: "Each commitment, exactly as a tool reported it", .maximumCount(12))
    var items: [Item]

    @Guide(description: "The monthly total, exactly as a tool reported it")
    var total: Double

    @Generable
    struct Item: Equatable, Sendable {
        @Guide(description: "The commitment's name")
        var name: String
        @Guide(description: "Its monthly amount")
        var amount: Double
    }

    nonisolated func renderedText() -> String {
        guard !items.isEmpty else {
            return "You have no recurring commitments — your whole income is headroom."
        }
        let list = items.map { "\($0.name) \(Money.string($0.amount))" }.joined(separator: ", ")
        return "Your recurring commitments come to \(Money.string(total)) a month: \(list)."
    }
}
