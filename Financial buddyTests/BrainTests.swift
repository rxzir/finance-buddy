//
//  BrainTests.swift
//  Financial buddyTests
//
//  Pure-Swift tests for the Tier 0 layer: every calculation the tools
//  delegate to, ProposedAction parsing/confidence, and the question
//  routing. Nothing here touches the on-device model.
//

import Foundation
import Testing
@testable import Financial_buddy

// MARK: - Fixture

/// A hand-checked picture, pinned to 15 July 2026 so every expected
/// number below can be verified by eye.
private enum Fixture {
    static let calendar = Calendar(identifier: .gregorian)

    static var today: Date {
        calendar.date(from: DateComponents(year: 2026, month: 7, day: 15))!
    }

    static func day(_ day: Int, month: Int = 7, year: Int = 2026) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    /// Balance 1000. Salary 2400 lands the 28th; a 120 refund on the 18th.
    /// Rent 950 due the 20th, Gym 45 due the 1st. Dinner 100 on the 16th,
    /// Trip 200 on 1 September.
    static var finances: Finances {
        Finances(
            balance: 1000,
            incomeSources: [
                IncomeSource(name: "Salary", amount: 2400, isRecurring: true, date: day(28)),
                IncomeSource(name: "Refund", amount: 120, isRecurring: false, date: day(18)),
            ],
            recurringCommitments: [
                RecurringCommitment(name: "Rent", amount: 950, dueDay: 20, category: "Housing"),
                RecurringCommitment(name: "Gym", amount: 45, dueDay: 1, category: "Health"),
            ],
            oneOffCosts: [
                OneOffCost(name: "Dinner", amount: 100, date: day(16)),
                OneOffCost(name: "Trip", amount: 200, date: day(1, month: 9)),
            ])
    }
}

// MARK: - Tier 0: model calculations the tools read

struct FinanceCalculationTests {

    @Test func daysUntilPayday() {
        #expect(Fixture.finances.daysUntilPayday(asOf: Fixture.today,
                                                 calendar: Fixture.calendar) == 13)
    }

    @Test func safeToSpendCountsEverythingDueBeforePayday() {
        // Rent (20th) + Dinner (16th) land before payday on the 28th:
        // 1000 − 950 − 100 = −50.
        let safe = Fixture.finances.safeToSpendToday(asOf: Fixture.today,
                                                     calendar: Fixture.calendar)
        #expect(safe == -50)
    }

    @Test func monthlyHeadroom() {
        // (2400 + 120) income − (950 + 45) recurring = 1525.
        #expect(Fixture.finances.monthlyHeadroom == 1525)
    }

    @Test func headroomAfterAddingMonthlyCost() {
        #expect(Fixture.finances.headroomAfterAdding(monthly: 400) == 1125)
    }

    @Test func weekCapacityWindow() {
        // Window ends 22 July. Due inside: Rent 950 + Dinner 100.
        // Landing inside: Refund 120. 1000 + 120 − 1050 = 70.
        let capacity = Fixture.finances.capacity(overDays: 7,
                                                 asOf: Fixture.today,
                                                 calendar: Fixture.calendar)
        #expect(capacity.free == 70)
        #expect(capacity.incomeInWindow == 120)
        #expect(capacity.obligationsInWindow == 1050)
    }

    @Test func monthCapacityWindow() {
        // Window ends 14 August. Due inside: Rent 950 + Gym 45 (1 Aug)
        // + Dinner 100; the September trip stays out. Landing inside:
        // Salary 2400 + Refund 120. 1000 + 2520 − 1095 = 2425.
        let capacity = Fixture.finances.capacity(overDays: 30,
                                                 asOf: Fixture.today,
                                                 calendar: Fixture.calendar)
        #expect(capacity.free == 2425)
        #expect(capacity.incomeInWindow == 2520)
        #expect(capacity.obligationsInWindow == 1095)
    }
}

// MARK: - Tier 0: affordability verdict

struct AffordabilityVerdictTests {

    @Test func comfortableWhenPlentyLeft() {
        #expect(AffordabilityVerdict.judge(headroom: 1525, newMonthlyCost: 400) == .comfortable)
    }

    @Test func tightWhenUnderAQuarterLeft() {
        #expect(AffordabilityVerdict.judge(headroom: 1525, newMonthlyCost: 1200) == .tight)
    }

    @Test func unaffordableWhenOverHeadroom() {
        #expect(AffordabilityVerdict.judge(headroom: 1525, newMonthlyCost: 1600) == .unaffordable)
    }

    @Test func boundaries() {
        // Exactly consuming headroom is tight, not unaffordable.
        #expect(AffordabilityVerdict.judge(headroom: 100, newMonthlyCost: 100) == .tight)
        #expect(AffordabilityVerdict.judge(headroom: 100, newMonthlyCost: 100.01) == .unaffordable)
        // Leaving exactly a quarter is comfortable.
        #expect(AffordabilityVerdict.judge(headroom: 100, newMonthlyCost: 75) == .comfortable)
    }
}

// MARK: - ProposedAction parsing

struct ProposedActionParsingTests {

    @Test func parsesRelativeDays() {
        let today = ProposedAction.parseDate("today", asOf: Fixture.today, calendar: Fixture.calendar)
        #expect(today.parsed && today.date == Fixture.day(15))

        let yesterday = ProposedAction.parseDate(" Yesterday ", asOf: Fixture.today, calendar: Fixture.calendar)
        #expect(yesterday.parsed && yesterday.date == Fixture.day(14))

        let tomorrow = ProposedAction.parseDate("tomorrow", asOf: Fixture.today, calendar: Fixture.calendar)
        #expect(tomorrow.parsed && tomorrow.date == Fixture.day(16))
    }

    @Test func parsesISODates() {
        let parsed = ProposedAction.parseDate("2026-07-18", asOf: Fixture.today, calendar: Fixture.calendar)
        #expect(parsed.parsed && parsed.date == Fixture.day(18))
    }

    @Test func unparseableFallsBackToTodayUnconfident() {
        let vague = ProposedAction.parseDate("last tuesday", asOf: Fixture.today, calendar: Fixture.calendar)
        #expect(!vague.parsed && vague.date == Fixture.day(15))

        let nonsense = ProposedAction.parseDate("2026-13-40", asOf: Fixture.today, calendar: Fixture.calendar)
        #expect(!nonsense.parsed)
    }

    @Test func dictationConfusablesAreFlagged() {
        #expect(ProposedAction.isDictationAmbiguous(13))
        #expect(ProposedAction.isDictationAmbiguous(30))
        #expect(ProposedAction.isDictationAmbiguous(70))
        #expect(!ProposedAction.isDictationAmbiguous(20))
        #expect(!ProposedAction.isDictationAmbiguous(13.5))
        #expect(!ProposedAction.isDictationAmbiguous(-13))
    }

    @Test func confidenceDocksForAmbiguityAndGuessedDates() {
        #expect(abs(ProposedAction.confidence(amount: 22) - 0.95) < 1e-9)
        #expect(abs(ProposedAction.confidence(amount: 30) - 0.65) < 1e-9)
        #expect(abs(ProposedAction.confidence(amount: 22, dateParsed: false) - 0.8) < 1e-9)
        #expect(abs(ProposedAction.confidence(amount: 30, dateParsed: false) - 0.5) < 1e-9)
    }

    @Test func summariesNameTheThingBeingConfirmed() {
        let expense = ProposedAction.logExpense(
            .init(name: "Lunch", amount: 12, date: Fixture.today, confidence: 0.95))
        #expect(expense.summary.contains("Lunch"))

        let recurring = ProposedAction.addRecurring(
            .init(name: "Gym", amount: 40, dueDay: 1, confidence: 0.65))
        #expect(recurring.summary.contains("Gym") && recurring.summary.contains("day 1"))
    }
}

// MARK: - Question routing

struct QuestionRoutingTests {

    @Test func recurringCostsRouteToAffordability() {
        #expect(QuestionRouting.route(for: "What if I add a £40/month gym?") == .affordability)
        #expect(QuestionRouting.route(for: "Can I afford £380 a month for a car?") == .affordability)
    }

    @Test func oneOffAffordQuestionsStayProse() {
        // No monthly signal — judged against safe-to-spend in free prose,
        // not against monthly headroom.
        #expect(QuestionRouting.route(for: "Can I afford a £300 weekend away?") == .plain)
    }

    @Test func capacityQuestionsRouteToCapacityCard() {
        #expect(QuestionRouting.route(for: "How much can I spend today?") == .spendingCapacity)
        #expect(QuestionRouting.route(for: "How much do I have left this week?") == .spendingCapacity)
    }

    @Test func commitmentQuestionsRouteToSummaryCard() {
        #expect(QuestionRouting.route(for: "What are my recurring commitments?") == .commitmentSummary)
        #expect(QuestionRouting.route(for: "List my subscriptions") == .commitmentSummary)
    }

    @Test func transactionReportsStayProse() {
        // These become proposal turns; the tools stage the write.
        #expect(QuestionRouting.route(for: "I spent £20 on lunch") == .plain)
        #expect(QuestionRouting.route(for: "I got £50 back from a refund yesterday") == .plain)
    }

    @Test func affordAndWhatIfQuestionsAreHypothetical() {
        // Staged writes are dropped for these — a coaching question must
        // never come back as a save prompt.
        #expect(QuestionRouting.isHypothetical("Can I afford a £300 weekend away?"))
        #expect(QuestionRouting.isHypothetical("What if I add a £40/month gym?"))
        #expect(QuestionRouting.isHypothetical("Should I buy the new phone?"))
        #expect(QuestionRouting.isHypothetical("Is a £380/month car worth it?"))
    }

    @Test func reportsAndDirectRequestsAreNotHypothetical() {
        #expect(!QuestionRouting.isHypothetical("I spent £20 on lunch"))
        #expect(!QuestionRouting.isHypothetical("Add a £40/month gym membership"))
        #expect(!QuestionRouting.isHypothetical("I got £50 back from a refund"))
    }
}

// MARK: - AskResult / card flattening

struct AskResultTests {

    @Test func textFallsBackToCardProse() {
        let card = AskCard.commitmentSummary(
            CommitmentSummaryCard(items: [.init(name: "Rent", amount: 950)], total: 950))
        let result = AskResult(text: "   ", card: card)
        #expect(result.text == card.renderedText())
        #expect(!result.text.isEmpty)
    }

    @Test func explicitTextWins() {
        let card = AskCard.spendingCapacity(
            SpendingCapacityCard(amount: 70, period: "this week", basis: "balance minus bills"))
        let result = AskResult(text: "You have room.", card: card)
        #expect(result.text == "You have room.")
    }

    @Test func everyCardRendersNonEmptyProse() {
        let affordability = AffordabilityCard(monthlyAmount: 40, headroomAfter: 1485,
                                              verdict: "comfortable", assumptions: ["no joining fee"])
        #expect(!affordability.renderedText().isEmpty)

        let short = AffordabilityCard(monthlyAmount: 1600, headroomAfter: -75,
                                      verdict: "unaffordable", assumptions: [])
        #expect(short.renderedText().contains("short"))

        let empty = CommitmentSummaryCard(items: [], total: 0)
        #expect(!empty.renderedText().isEmpty)
    }
}

// MARK: - Confirmation routing

struct ConfirmationRoutingTests {

    @Test func clearYesesConfirm() {
        #expect(ConfirmationRouting.decision(for: "confirm") == .confirm)
        #expect(ConfirmationRouting.decision(for: "Yes please") == .confirm)
        #expect(ConfirmationRouting.decision(for: "add it") == .confirm)
        #expect(ConfirmationRouting.decision(for: "go ahead") == .confirm)
        #expect(ConfirmationRouting.decision(for: "yes, save it.") == .confirm)
    }

    @Test func clearNosCancel() {
        #expect(ConfirmationRouting.decision(for: "no") == .cancel)
        #expect(ConfirmationRouting.decision(for: "cancel that") == .cancel)
        #expect(ConfirmationRouting.decision(for: "never mind") == .cancel)
        #expect(ConfirmationRouting.decision(for: "don't add it") == .cancel)
    }

    @Test func anythingElseGoesBackToTheModel() {
        // A correction is not a confirmation.
        #expect(ConfirmationRouting.decision(for: "yes but make it 30") == .other)
        #expect(ConfirmationRouting.decision(for: "how much can I spend today?") == .other)
        #expect(ConfirmationRouting.decision(for: "") == .other)
    }
}

// MARK: - Applying confirmed actions

@MainActor
struct ConfirmationApplyTests {

    /// A service that never proposes anything; these tests drive the
    /// pending queue directly.
    private struct StubService: AskServing {
        func ask(question: String, snapshot: Finances) async throws -> AskResult {
            AskResult(text: "stub")
        }
    }

    @Test func confirmWritesToTheStoreAndClearsPending() {
        let store = FinanceBuddyStore(finances: .empty)
        let model = ChatViewModel(store: store, service: StubService())
        model.pendingActions = [
            .logExpense(.init(name: "Lunch", amount: 12, date: Fixture.today, confidence: 0.95)),
            .addRecurring(.init(name: "Gym", amount: 40, dueDay: 1, confidence: 0.65)),
        ]

        model.send("confirm", snapshot: store.finances)

        #expect(store.finances.oneOffCosts.count == 1)
        #expect(store.finances.oneOffCosts.first?.name == "Lunch")
        #expect(store.finances.recurringCommitments.first?.name == "Gym")
        #expect(model.pendingActions.isEmpty)
        #expect(model.messages.last?.role == .assistant)
        #expect(model.messages.last?.text.contains("Done") == true)
    }

    @Test func cancelDropsEverythingWithoutWriting() {
        let store = FinanceBuddyStore(finances: .empty)
        let model = ChatViewModel(store: store, service: StubService())
        model.pendingActions = [
            .logIncome(.init(name: "Refund", amount: 50, date: Fixture.today, confidence: 0.95)),
        ]

        model.send("never mind", snapshot: store.finances)

        #expect(store.finances.incomeSources.isEmpty)
        #expect(model.pendingActions.isEmpty)
        #expect(model.messages.last?.text.contains("nothing was saved") == true)
    }

    @Test func tappingConfirmAppliesAndClearsPending() {
        let store = FinanceBuddyStore(finances: .empty)
        let model = ChatViewModel(store: store, service: StubService())
        model.pendingActions = [
            .logExpense(.init(name: "Lunch", amount: 12, date: Fixture.today, confidence: 0.95)),
        ]

        model.confirmPending()

        #expect(store.finances.oneOffCosts.first?.name == "Lunch")
        #expect(model.pendingActions.isEmpty)
        #expect(model.messages.last?.text.contains("Done") == true)
    }

    @Test func tappingCancelDropsWithoutWriting() {
        let store = FinanceBuddyStore(finances: .empty)
        let model = ChatViewModel(store: store, service: StubService())
        model.pendingActions = [
            .logExpense(.init(name: "Lunch", amount: 12, date: Fixture.today, confidence: 0.95)),
        ]

        model.cancelPending()

        #expect(store.finances.oneOffCosts.isEmpty)
        #expect(model.pendingActions.isEmpty)
        #expect(model.messages.last?.text.contains("nothing was saved") == true)
    }
}

// MARK: - Proposal card

struct ProposalCardTests {

    @Test func proposalCardNamesWhatWouldBeSaved() {
        // The Confirm/Cancel affordance is the inline buttons; the prose
        // just states what is staged.
        let card = ProposalCard(actions: [
            .logExpense(.init(name: "Lunch", amount: 12, date: Fixture.today, confidence: 0.95)),
        ])
        let text = card.renderedText()
        #expect(text.contains("Lunch"))
        #expect(text.contains("Ready to save"))
    }

    @Test func lowConfidenceAddsAMishearingWarning() {
        let card = ProposalCard(actions: [
            .logExpense(.init(name: "Taxi", amount: 30, date: Fixture.today, confidence: 0.65)),
        ])
        #expect(card.renderedText().contains("Double-check"))
    }
}
