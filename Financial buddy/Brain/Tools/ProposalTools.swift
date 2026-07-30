//
//  ProposalTools.swift
//  Finance buddy
//
//  The staging tools. These parse what the user reported and hand back a
//  ProposedAction via the BrainContext — they NEVER touch the store.
//  Dictation mishears amounts, so everything waits for confirmation.
//

import Foundation
import FoundationModels

// MARK: - Expense

struct ProposeExpenseTool: Tool {
    let name = "proposeExpense"
    let description = "Stage a one-off expense the user reported, for their confirmation. Writes nothing."

    let context: BrainContext

    @Generable
    struct Arguments {
        @Guide(description: "Short name for the expense, like 'Lunch'")
        var name: String
        @Guide(description: "Amount spent")
        var amount: Double
        @Guide(description: "When, like 'today', 'yesterday' or '2026-07-18'")
        var date: String
    }

    func call(arguments: Arguments) async throws -> String {
        let (date, parsed) = ProposedAction.parseDate(arguments.date)
        let draft = ProposedAction.ExpenseDraft(
            name: arguments.name,
            amount: arguments.amount,
            date: date,
            confidence: ProposedAction.confidence(amount: arguments.amount, dateParsed: parsed))
        context.stage(.logExpense(draft))
        return "Staged (not saved): \(ProposedAction.logExpense(draft).summary). Ask the user to confirm before it is recorded; never say it is done."
    }
}

// MARK: - Income

struct ProposeIncomeTool: Tool {
    let name = "proposeIncome"
    let description = "Stage money the user reported coming in, for their confirmation. Writes nothing."

    let context: BrainContext

    @Generable
    struct Arguments {
        @Guide(description: "Short name for where it came from, like 'Refund'")
        var name: String
        @Guide(description: "Amount received")
        var amount: Double
        @Guide(description: "When, like 'today', 'yesterday' or '2026-07-18'")
        var date: String
    }

    func call(arguments: Arguments) async throws -> String {
        let (date, parsed) = ProposedAction.parseDate(arguments.date)
        let draft = ProposedAction.IncomeDraft(
            name: arguments.name,
            amount: arguments.amount,
            date: date,
            confidence: ProposedAction.confidence(amount: arguments.amount, dateParsed: parsed))
        context.stage(.logIncome(draft))
        return "Staged (not saved): \(ProposedAction.logIncome(draft).summary). Ask the user to confirm before it is recorded; never say it is done."
    }
}

// MARK: - Balance update

struct ProposeBalanceUpdateTool: Tool {
    let name = "proposeBalanceUpdate"
    let description = "Stage a correction to the user's current account balance, for their confirmation. Writes nothing."

    let context: BrainContext

    @Generable
    struct Arguments {
        @Guide(description: "The new account balance to set")
        var newBalance: Double
    }

    func call(arguments: Arguments) async throws -> String {
        let draft = ProposedAction.BalanceDraft(
            newBalance: arguments.newBalance,
            confidence: ProposedAction.confidence(amount: arguments.newBalance))
        context.stage(.updateBalance(draft))
        return "Staged (not saved): set balance to \(Money.string(arguments.newBalance)). Ask the user to confirm before it is recorded; never say it is done."
    }
}

// MARK: - Recurring commitment

struct ProposeRecurringTool: Tool {
    let name = "proposeRecurring"
    let description = "Stage a new recurring monthly commitment the user wants, for their confirmation. Writes nothing."

    let context: BrainContext

    @Generable
    struct Arguments {
        @Guide(description: "Short name for the commitment, like 'Gym'")
        var name: String
        @Guide(description: "Amount per month")
        var amount: Double
        @Guide(description: "Day of the month it falls due", .range(1...31))
        var dueDay: Int
    }

    func call(arguments: Arguments) async throws -> String {
        let draft = ProposedAction.RecurringDraft(
            name: arguments.name,
            amount: arguments.amount,
            dueDay: min(max(arguments.dueDay, 1), 31),
            confidence: ProposedAction.confidence(amount: arguments.amount))
        context.stage(.addRecurring(draft))
        return "Staged (not saved): \(ProposedAction.addRecurring(draft).summary). Ask the user to confirm before it is added; never say it is done."
    }
}
