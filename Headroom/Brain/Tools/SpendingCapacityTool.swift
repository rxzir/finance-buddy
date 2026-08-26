//
//  SpendingCapacityTool.swift
//  Headroom
//
//  How much is free over a window. "Today" means the pre-payday
//  safe-to-spend; week and month are balance plus income landing in the
//  window minus everything due in it. All Tier 0.
//

import Foundation
import FoundationModels

struct SpendingCapacityTool: Tool {
    let name = "spendingCapacity"
    let description = "How much the user can freely spend today, this week or this month. Exact figures."

    let context: BrainContext

    @Generable
    struct Arguments {
        @Guide(description: "The window to check", .anyOf(["today", "week", "month"]))
        var period: String
    }

    func call(arguments: Arguments) async throws -> String {
        let finances = context.finances

        switch arguments.period {
        case "week":
            return capacityLine(finances.capacity(overDays: 7), label: "this week")
        case "month":
            return capacityLine(finances.capacity(overDays: 30), label: "this month")
        default:
            let safe = finances.safeToSpendToday()
            let days = finances.daysUntilPayday()
            return """
            Free to spend today: \(Money.string(safe)). \
            Basis: balance minus everything due before payday\(days == 0 ? " (payday is today)" : " in \(days) day\(days == 1 ? "" : "s")").
            """
        }
    }

    private func capacityLine(_ breakdown: Finances.CapacityBreakdown, label: String) -> String {
        """
        Free to spend \(label): \(Money.string(breakdown.free)). \
        Basis: balance \(Money.string(context.finances.balance)) \
        plus \(Money.string(breakdown.incomeInWindow)) income landing in the window, \
        minus \(Money.string(breakdown.obligationsInWindow)) due in it.
        """
    }
}
