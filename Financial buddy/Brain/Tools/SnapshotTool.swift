//
//  SnapshotTool.swift
//  Finance buddy
//
//  Gives the model the current financial picture. Every figure is
//  computed in Swift (Tier 0) — the model only reads them back.
//

import Foundation
import FoundationModels

struct SnapshotTool: Tool {
    let name = "financialSnapshot"
    let description = "The user's current balance, safe-to-spend, payday, monthly headroom and commitments. Exact figures."

    let context: BrainContext

    @Generable
    struct Arguments {}

    func call(arguments: Arguments) async throws -> String {
        let finances = context.finances
        let days = finances.daysUntilPayday()
        let safe = finances.safeToSpendToday()

        var lines = [
            "Balance: \(Money.string(finances.balance)).",
            "Safe to spend before payday: \(Money.string(safe)).",
            days == 0 ? "Payday is today." : "Payday in \(days) day\(days == 1 ? "" : "s").",
            "Monthly income: \(Money.string(finances.totalIncome)).",
            "Monthly headroom (income minus recurring commitments): \(Money.string(finances.monthlyHeadroom)).",
        ]

        if finances.recurringCommitments.isEmpty {
            lines.append("No recurring commitments.")
        } else {
            let commitments = finances.recurringCommitments
                .map { "\($0.name) \(Money.string($0.amount)) (day \($0.dueDay))" }
                .joined(separator: ", ")
            lines.append("Recurring commitments: \(commitments).")
        }

        let upcoming = finances.upcomingObligations()
        if !upcoming.isEmpty {
            let dueSoon = upcoming
                .map { "\($0.name) \(Money.string($0.amount))" }
                .joined(separator: ", ")
            lines.append("Due before payday: \(dueSoon).")
        }

        return lines.joined(separator: " ")
    }
}
