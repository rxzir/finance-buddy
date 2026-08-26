//
//  OnDeviceAskService.swift
//  Headroom
//
//  Tier 1: the on-device reasoning layer. Intent understanding, tool
//  selection and phrasing happen here — free, private, offline. Every
//  number comes from a tool (Tier 0), and every failure path falls
//  through to LocalReasoner so the Ask tab always answers. Cloud
//  reasoning (Tier 2) will slot in behind the same AskServing seam.
//

import Foundation
import FoundationModels

actor OnDeviceAskService: AskServing {

    /// Permissive guardrails: the default mode false-positives on benign
    /// money questions ("can I afford…"). Permissive mode only covers
    /// string generation — guided (card) turns still run the default
    /// guardrails, so card turns degrade to prose on a violation.
    private let model = SystemLanguageModel(guardrails: .permissiveContentTransformations)
    private let context: BrainContext
    private let tools: [any Tool]
    /// One session per conversation; replaced when the context window
    /// fills up or the session errors.
    private var session: LanguageModelSession?

    init() {
        let context = BrainContext()
        self.context = context
        tools = [
            SnapshotTool(context: context),
            AffordabilityTool(context: context),
            SpendingCapacityTool(context: context),
            ProposeExpenseTool(context: context),
            ProposeIncomeTool(context: context),
            ProposeRecurringTool(context: context),
            ProposeBalanceUpdateTool(context: context),
        ]
    }

    // MARK: AskServing

    func ask(question: String, snapshot: Finances) async throws -> AskResult {
        guard ModelAvailability.check(model).isReady else {
            return AskResult(text: LocalReasoner.answer(to: question, finances: snapshot))
        }

        context.beginTurn(with: snapshot)

        do {
            return try await answer(question, allowCards: true)
        } catch let error as LanguageModelSession.GenerationError {
            switch error {
            case .exceededContextWindowSize:
                // Fresh window seeded with a summary, then one retry.
                startFreshSession(summarisingPrevious: true)
                if let retried = try? await answer(question, allowCards: true) { return retried }
            case .guardrailViolation, .refusal:
                // Guided generation runs the default guardrails even on a
                // permissive model — retry the turn as plain prose, which
                // the permissive guardrails allow, before giving up.
                if let prose = try? await answer(question, allowCards: false) { return prose }
            default:
                break
            }
            // Decoding failure, rate limit… the tab must still answer,
            // and a poisoned session shouldn't sour the next question.
            session = nil
            return AskResult(text: LocalReasoner.answer(to: question, finances: snapshot))
        } catch {
            session = nil
            return AskResult(text: LocalReasoner.answer(to: question, finances: snapshot))
        }
    }

    // MARK: One turn

    private func answer(_ question: String, allowCards: Bool) async throws -> AskResult {
        let session = try await preparedSession()

        let raw: AskResult
        switch allowCards ? QuestionRouting.route(for: question) : .plain {
        case .affordability:
            let card = try await session.respond(to: question, generating: AffordabilityCard.self).content
            raw = AskResult(text: card.renderedText(), card: .affordability(card))
        case .spendingCapacity:
            let card = try await session.respond(to: question, generating: SpendingCapacityCard.self).content
            raw = AskResult(text: card.renderedText(), card: .spendingCapacity(card))
        case .commitmentSummary:
            let card = try await session.respond(to: question, generating: CommitmentSummaryCard.self).content
            raw = AskResult(text: card.renderedText(), card: .commitmentSummary(card))
        case .plain:
            raw = AskResult(text: try await session.respond(to: question).content)
        }

        // Anything the tools staged overrides the model's phrasing: the
        // approval ask must be deterministic so that a plain "confirm"
        // or "cancel" (handled in Swift, never by the model) always works.
        let pending = context.drainPending()
        guard !pending.isEmpty else { return raw }
        // A hypothetical never becomes a write. "Can I afford X" sometimes
        // tempts the model into staging X, which would turn a coaching
        // question into a save prompt — drop the staging, keep the answer.
        guard !QuestionRouting.isHypothetical(question) else { return raw }
        let proposal = ProposalCard(actions: pending)
        return AskResult(text: proposal.renderedText(),
                         card: .proposal(proposal),
                         proposedActions: pending)
    }

    // MARK: Session lifecycle & context management

    /// Returns the live session, rolling to a fresh one (seeded with a
    /// summary) when the transcript nears the model's context window.
    private func preparedSession() async throws -> LanguageModelSession {
        if let session {
            let used = try await model.tokenCount(for: Array(session.transcript))
            if used > (model.contextSize * 3) / 4 {
                startFreshSession(summarisingPrevious: true)
            }
        } else {
            startFreshSession(summarisingPrevious: false)
        }
        guard let session else { throw AskError.decoding }
        return session
    }

    private func startFreshSession(summarisingPrevious: Bool) {
        var instructions = Self.instructionsText
        if summarisingPrevious, let old = session {
            let summary = Self.handoffSummary(from: old.transcript)
            if !summary.isEmpty {
                instructions += "\n\nThe conversation so far, in brief: \(summary)"
            }
        }
        let fresh = LanguageModelSession(model: model, tools: tools, instructions: instructions)
        fresh.prewarm()
        session = fresh
    }

    /// A short, deterministic digest of the tail of a transcript, used to
    /// seed the next session instead of failing mid-conversation.
    nonisolated static func handoffSummary(from transcript: Transcript) -> String {
        Array(transcript)
            .suffix(4)
            .map { String(String(describing: $0).prefix(200)) }
            .joined(separator: " · ")
    }

    private nonisolated static let instructionsText = """
    You are the coaching layer inside Headroom. The app shows people
    what they actually have to spare, not their raw balance.

    WHAT YOU ARE:
    You are a coach, not an adviser. You help people see their own numbers
    clearly and think through their own decisions. You never tell them what
    they should do with their money.

    NEVER:
    - Never say "you should", "I recommend", "I'd advise", "the best option is".
    - Never recommend specific financial products, accounts, or providers.
    - Never tell someone to buy, not buy, invest, or save a specific amount.

    INSTEAD:
    - Reflect their numbers back: "That leaves you £340 a month of headroom."
    - Surface the trade-off and hand the decision back: "That's doable on
      paper. Whether it's comfortable is your call."
    - Ask a sharpening question when it helps them decide for themselves.

    STYLE:
    - Two or three sentences. Never more than four. Short is the whole point.
    - Plain words. No jargon, no "furthermore", no filler preamble.
    - Warm and direct. Never preachy, never a lecture.
    - Lead with the number that answers their question, then one line of
      context if it earns its place.

    NUMBERS:
    - Never calculate anything yourself; always call a tool for any figure.
    - Monthly headroom is based on recurring income only — one-off income
      does not count towards headroom.
    - A new recurring cost is judged against monthly headroom, not today's
      safe-to-spend.
    - When they ask about a purchase, name the realistic second-order costs
      they didn't mention and say what you assumed.

    LOGGING (one-off transactions):
    - When someone reports spending money ("I spent", "I paid", "I bought",
      "just spent"), always call proposeExpense immediately. Never skip it.
    - When someone reports receiving money ("I got", "I received", "I earned",
      "I was paid"), always call proposeIncome immediately. Never skip it.
    - When someone asks to add a one-time expense (e.g. "add a dentist bill
      for £80", "log a £50 expense"), call proposeExpense.
    - When someone asks to add a one-time income (e.g. "add a bonus of £500",
      "log a refund of £120", "I got some extra income"), call proposeIncome.
    - Never say the transaction is saved — it is only staged for confirmation.
    - After staging, briefly confirm what you staged and ask them to confirm.

    BALANCE:
    - When someone tells you their current balance or asks to update/correct
      it ("my balance is £1,200", "I have £800 in my account", "update my
      balance to £3,000", "set my balance"), call proposeBalanceUpdate with
      the figure they gave. Never calculate a new balance yourself.
    - This replaces the stored balance entirely — not an adjustment.
    """
}

// MARK: - Routing (Tier 0 — deterministic, unit-tested)

/// Which answer shape fits the question. Guided generation is used where
/// a card fits; everything else is a plain prose turn.
enum AskRoute: Equatable {
    case affordability, spendingCapacity, commitmentSummary, plain
}

enum QuestionRouting {

    /// Phrases that report money actually moving — these turns may stage
    /// a write for confirmation.
    private nonisolated static let reportPhrases = [
        "i spent", "i paid", "i bought", "i got", "i received", "just spent",
    ]

    /// Phrases that explore a purchase rather than report one.
    private nonisolated static let hypotheticalPhrases = [
        "afford", "what if", "should i", "is it worth", "worth it",
        "could i", "would i be able",
    ]

    /// True when the question weighs a purchase rather than reporting
    /// one. Staged writes are discarded for these turns: exploring "can I
    /// afford X" must answer like a coach, never become a save prompt.
    nonisolated static func isHypothetical(_ question: String) -> Bool {
        let q = question.lowercased()
        // A report is a fact, however it's phrased.
        if reportPhrases.contains(where: q.contains) { return false }
        return hypotheticalPhrases.contains(where: q.contains)
    }

    nonisolated static func route(for question: String) -> AskRoute {
        let q = question.lowercased()

        // Reports of money moving are proposal turns, answered in prose.
        if reportPhrases.contains(where: q.contains) {
            return .plain
        }

        let mentionsMonthly = q.contains("month") || q.contains("/mo")
            || q.contains("recurring") || q.contains("subscription")

        // Recurring costs are judged against monthly headroom (rule 2);
        // one-off "can I afford" questions stay prose so the model can
        // weigh safe-to-spend and second-order costs freely.
        if mentionsMonthly &&
            (q.contains("afford") || q.contains("what if") || q.contains("add") || q.contains("take on")) {
            return .affordability
        }

        if q.contains("commitment") || q.contains("recurring") || q.contains("subscriptions")
            || q.contains("my bills") {
            return .commitmentSummary
        }

        if q.contains("how much") &&
            (q.contains("spend") || q.contains("left") || q.contains("free")) {
            return .spendingCapacity
        }

        return .plain
    }
}
