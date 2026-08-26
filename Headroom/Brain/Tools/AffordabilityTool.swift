//
//  AffordabilityTool.swift
//  Headroom
//
//  Judges a new recurring monthly cost against monthly headroom — never
//  against today's safe-to-spend. Arithmetic and verdict are Tier 0.
//

import Foundation
import FoundationModels

struct AffordabilityTool: Tool {
    let name = "checkAffordability"
    let description = "Judge a new recurring monthly cost against the user's monthly headroom. Exact arithmetic and verdict."

    let context: BrainContext

    @Generable
    struct Arguments {
        @Guide(description: "The new cost per month, including any ongoing extras you estimated")
        var monthlyAmount: Double
    }

    func call(arguments: Arguments) async throws -> String {
        let finances = context.finances
        let headroom = finances.monthlyHeadroom
        let after = finances.headroomAfterAdding(monthly: arguments.monthlyAmount)
        let verdict = AffordabilityVerdict.judge(headroom: headroom,
                                                 newMonthlyCost: arguments.monthlyAmount)

        return """
        New monthly cost: \(Money.string(arguments.monthlyAmount)). \
        Monthly headroom now: \(Money.string(headroom)). \
        Headroom after this cost: \(Money.string(after)). \
        Verdict: \(verdict.rawValue).
        """
    }
}
