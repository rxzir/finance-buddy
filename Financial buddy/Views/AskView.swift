//
//  AskView.swift
//  Finance buddy
//
//  Screen 1 (the landing tab). One input pill: type straight away, or tap
//  the mic inside the field to dictate; + on the left quickly logs an
//  expense or income. The header leads with the one number that matters —
//  what's left to spend. The view only knows the store + a service — it
//  never touches the network itself.
//

import SwiftUI

// MARK: - Chat state

struct ChatMessage: Identifiable, Equatable {
    enum Role { case user, assistant }
    let id = UUID()
    let role: Role
    var text: String
    /// Staged writes this message asked the user to confirm. The inline
    /// Confirm/Cancel buttons render only while these are still the
    /// pending set — resolving or re-proposing hides them.
    var proposedActions: [ProposedAction] = []
}

@MainActor
@Observable
final class ChatViewModel {
    var messages: [ChatMessage] = []
    var isThinking = false
    /// Staged writes the assistant proposed, awaiting the user's
    /// confirmation. Nothing touches the store until they say yes.
    var pendingActions: [ProposedAction] = []

    @ObservationIgnored private let service: AskServing
    /// Where confirmed actions are applied. Nil in previews: proposals
    /// still stage, confirming explains it can't save.
    @ObservationIgnored private weak var store: FinanceBuddyStore?

    init(store: FinanceBuddyStore? = nil, service: AskServing = OnDeviceAskService()) {
        self.store = store
        self.service = service
    }

    func send(_ text: String, snapshot: Finances) {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isThinking else { return }

        messages.append(ChatMessage(role: .user, text: question))

        // Resolving a staged write is deterministic Swift, never a model
        // turn: a clear yes applies it, a clear no drops it, anything
        // else falls through to the model with the proposals kept.
        if !pendingActions.isEmpty {
            switch ConfirmationRouting.decision(for: question) {
            case .confirm:
                resolvePending(applying: true)
                return
            case .cancel:
                resolvePending(applying: false)
                return
            case .other:
                break
            }
        }

        isThinking = true
        Task {
            var reply: ChatMessage
            do {
                let result = try await service.ask(question: question, snapshot: snapshot)
                reply = ChatMessage(role: .assistant, text: result.text,
                                    proposedActions: result.proposedActions)
                if !result.proposedActions.isEmpty {
                    // Replace, don't stack: a re-proposal supersedes the
                    // old one instead of double-logging on confirm.
                    pendingActions = result.proposedActions
                }
            } catch {
                reply = ChatMessage(role: .assistant, text: "Sorry — \(error.localizedDescription)")
            }
            isThinking = false
            messages.append(reply)
        }
    }

    /// The inline Confirm button — same path as typing "confirm".
    func confirmPending() {
        guard !pendingActions.isEmpty, !isThinking else { return }
        resolvePending(applying: true)
    }

    /// The inline Cancel button — same path as typing "cancel".
    func cancelPending() {
        guard !pendingActions.isEmpty, !isThinking else { return }
        resolvePending(applying: false)
    }

    private func resolvePending(applying: Bool) {
        let actions = pendingActions
        pendingActions = []
        let text = applying ? apply(actions) : "Dropped — nothing was saved."
        messages.append(ChatMessage(role: .assistant, text: text))
    }

    /// Applies confirmed actions with the same store calls the quick-add
    /// overlay uses, and reports the new position.
    private func apply(_ actions: [ProposedAction]) -> String {
        guard let store else {
            return "I can't save right now — use the + button instead."
        }
        for action in actions {
            switch action {
            case .logExpense(let draft):
                store.addOneOff(OneOffCost(name: draft.name, amount: draft.amount, date: draft.date))
            case .logIncome(let draft):
                store.addIncome(IncomeSource(name: draft.name, amount: draft.amount,
                                             isRecurring: false, category: "General",
                                             date: draft.date))
            case .addRecurring(let draft):
                store.addCommitment(RecurringCommitment(name: draft.name, amount: draft.amount,
                                                        dueDay: draft.dueDay, category: "General"))
            }
        }
        let saved = actions.map(\.summary).joined(separator: "; ")
        let safe = store.finances.safeToSpendToday()
        return "Done — saved: \(saved). Safe to spend is now \(Money.string(safe))."
    }
}

// MARK: - View

struct AskView: View {
    let store: FinanceBuddyStore
    /// False when another tab is showing; clears keyboard focus.
    var isActive: Bool = true
    /// Asks the root to present a modal (rendered above the tab bar).
    var present: (AppModal) -> Void = { _ in }
    /// True once the conversation has the floor: the hero number shrinks
    /// to the top. Collapses on first send and while scrolling; a pull
    /// past the top of the transcript brings it back. Owned by the root,
    /// which renders `AskHeaderBar` in the pager's top bar.
    @Binding var headerCollapsed: Bool
    @State private var model: ChatViewModel
    @State private var draft = ""
    @State private var dictation = DictationController()
    @FocusState private var inputFocused: Bool

    /// Short, wry, budget-flavoured — one is picked per visit.
    private static let greetings = [
        "Your money called. It wants a plan",
        "Spend like someone's watching",
        "Every pound needs a job",
        "Let's make payday last",
        "Small leaks sink big ships",
        "Future you says thanks",
        "Budgeting: adulting on hard mode",
        "Wallet check, vibe check",
    ]
    @State private var greeting = AskView.greetings.randomElement() ?? "Hello"

    private static let suggestions = [
        "Can I afford a £300 weekend away?",
        "What if I add a £40/month gym?",
        "How much can I spend today?",
    ]

    init(store: FinanceBuddyStore, isActive: Bool = true,
         headerCollapsed: Binding<Bool> = .constant(false),
         present: @escaping (AppModal) -> Void = { _ in }) {
        self.store = store
        self.isActive = isActive
        self.present = present
        _headerCollapsed = headerCollapsed
        _model = State(initialValue: ChatViewModel(store: store))
    }

    /// Used by previews to inject a pre-seeded conversation.
    init(store: FinanceBuddyStore, injectedModel: ChatViewModel) {
        self.store = store
        _headerCollapsed = .constant(true)
        _model = State(initialValue: injectedModel)
    }

    var body: some View {
        ZStack {
            // Transparent tap catcher — the shared background (and its
            // blob drift) lives at the root, behind every page.
            Color.clear
                .contentShape(Rectangle())
                .ignoresSafeArea()
                .onTapGesture { inputFocused = false }

            VStack(spacing: 0) {
                if model.messages.isEmpty {
                    emptyBody
                } else {
                    transcript
                }
                inputBar
            }
        }
        // The hero header (AskHeaderBar) is rendered by the pager's top
        // safeAreaBar in ContentView — only the outermost scroll view
        // renders edge effects, so the bar can't live on this page.
        // One place handles keyboard dismissal for both swipe and tab-bar
        // navigation: leaving the tab clears focus.
        .onChange(of: isActive) {
            if !isActive { inputFocused = false }
        }
        // The first message hands the screen to the conversation.
        .onChange(of: model.messages.count) { old, new in
            if old == 0 && new > 0 {
                withAnimation(.fbModal) { headerCollapsed = true }
            } else if new == 0 {
                withAnimation(.fbModal) { headerCollapsed = false }
            }
        }
    }

    // MARK: Empty state — a quiet greeting mid-screen, questions at the foot

    private var emptyBody: some View {
        VStack(spacing: 0) {
            Spacer()
            Text(greeting)
                .font(.fbBody(16, weight: .medium))
                .foregroundStyle(Color.fbSoftText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 44)
            Spacer()
            suggestionButtons
                .padding(.horizontal, 20)
                .padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { inputFocused = false }
    }

    private var suggestionButtons: some View {
        VStack(spacing: 10) {
            ForEach(AskView.suggestions, id: \.self) { suggestion in
                Button {
                    model.send(suggestion, snapshot: store.finances)
                } label: {
                    HStack {
                        Text(suggestion)
                            .font(.fbBody(15, weight: .medium))
                            .foregroundStyle(Color.fbInk)
                            .multilineTextAlignment(.leading)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.fbSoftText)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 13)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.fbCard)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.fbHairline, lineWidth: 1)
                    )
                }
                .buttonStyle(.pressable)
            }
        }
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(model.messages) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                        if awaitsDecision(message) {
                            ProposalDecisionButtons(onConfirm: { model.confirmPending() },
                                                    onCancel: { model.cancelPending() })
                        }
                    }
                    if model.isThinking {
                        ThinkingBubble()
                            .id("thinking")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .frame(maxWidth: .infinity, minHeight: 1)
                .contentShape(Rectangle())
                .onTapGesture { inputFocused = false } // tap transcript → dismiss keyboard
            }
            .scrollDismissesKeyboard(.immediately)
            .scrollEdgeEffectStyle(.soft, for: .vertical)
            // Scrolling the transcript keeps the hero minimised; pulling
            // down past the top (rubber-band) brings it back.
            .onScrollGeometryChange(for: CGFloat.self,
                                    of: { $0.contentOffset.y + $0.contentInsets.top }) { _, offset in
                if offset < -50, headerCollapsed {
                    withAnimation(.fbModal) { headerCollapsed = false }
                } else if offset > 12, !headerCollapsed, !model.messages.isEmpty {
                    withAnimation(.fbModal) { headerCollapsed = true }
                }
            }
            .onChange(of: model.messages.count) {
                withAnimation { proxy.scrollTo(model.messages.last?.id, anchor: .bottom) }
            }
            .onChange(of: model.isThinking) {
                if model.isThinking {
                    withAnimation { proxy.scrollTo("thinking", anchor: .bottom) }
                }
            }
        }
    }

    // MARK: Input — one pill: type, or tap the mic inside it to talk

    private var inputBar: some View {
        VStack(spacing: 14) {
            if dictation.isRecording {
                Text(dictation.transcript.isEmpty ? "Listening…" : dictation.transcript)
                    .font(.fbBody(15))
                    .foregroundStyle(dictation.transcript.isEmpty ? Color.fbSoftText : Color.fbInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
            }

            if let error = dictation.errorMessage {
                Text(error)
                    .font(.fbBody(13))
                    .foregroundStyle(Color.fbWarning)
                    .padding(.horizontal, 20)
            }

            HStack(spacing: 10) {
                // Quick add sits to the left of the field.
                Button {
                    present(.quickAdd)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.fbInk)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Color.fbInk.opacity(0.06)))
                        .overlay(Circle().strokeBorder(Color.fbHairline, lineWidth: 1))
                }
                .buttonStyle(.pressable)
                .accessibilityLabel("Add income or expense")

                // The field pill, with the mic living inside it.
                HStack(spacing: 8) {
                    TextField("Ask anything", text: $draft, axis: .vertical)
                        .textFieldStyle(.plain)
                        .focused($inputFocused)
                        .font(.fbBody(16))
                        .foregroundStyle(Color.fbInk)
                        .lineLimit(1...4)

                    Button {
                        Task {
                            if let spoken = await dictation.toggle() {
                                model.send(spoken, snapshot: store.finances)
                            }
                        }
                    } label: {
                        Image(systemName: dictation.isRecording ? "stop.fill" : "mic.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(dictation.isRecording ? Color.fbWarning : Color.fbSoftText)
                            .frame(width: 30, height: 30)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.pressable)
                    .disabled(model.isThinking)
                    .animation(.easeInOut(duration: 0.2), value: dictation.isRecording)
                    .accessibilityLabel(dictation.isRecording ? "Stop and send" : "Dictate a question")
                }
                .padding(.leading, 16)
                .padding(.trailing, 8)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color.fbCard)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Color.fbHairline, lineWidth: 1)
                )

                // Send only exists once there's something to send.
                if canSend {
                    Button(action: send) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Color.fbOnAccent)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(Color.fbPositive))
                    }
                    .buttonStyle(.pressable)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
                    .accessibilityLabel("Send")
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: canSend)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    /// A message keeps its decision card only while its proposals are
    /// still the pending set — confirming, cancelling or re-proposing
    /// makes it a plain transcript line again.
    private func awaitsDecision(_ message: ChatMessage) -> Bool {
        message.role == .assistant
            && !message.proposedActions.isEmpty
            && message.proposedActions == model.pendingActions
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !model.isThinking
    }

    private func send() {
        let text = draft
        draft = ""
        model.send(text, snapshot: store.finances)
    }
}

// MARK: - Header bar — THE number, big, first

/// The Ask tab's title bar: the safe-to-spend hero. Rendered by the
/// pager's top `safeAreaBar` in ContentView (only the outermost scroll
/// view gets the soft edge blur), with the collapse state driven by
/// AskView's transcript.
struct AskHeaderBar: View {
    let store: FinanceBuddyStore
    let collapsed: Bool

    var body: some View {
        let safe = store.finances.safeToSpendToday()
        let days = store.finances.daysUntilPayday()
        let isOverspent = safe < 0

        let subtitle: String
        if isOverspent {
            subtitle = "Overspent · payday in \(days) day\(days == 1 ? "" : "s")"
        } else if days == 0 {
            subtitle = "Payday is today"
        } else {
            subtitle = "Left for \(days) day\(days == 1 ? "" : "s")"
        }

        let collapsedSuffix = isOverspent ? "overspent"
            : (days == 0 ? "payday today" : "for \(days) day\(days == 1 ? "" : "s")")

        return VStack(alignment: .leading, spacing: 2) {
            if !collapsed {
                Text(Date().formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(.fbBody(14))
                    .foregroundStyle(Color.fbSoftText)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // The amount and its collapsed suffix scale together (not a
            // font swap) so the minimise glides. The suffix is oversized
            // pre-scale so it lands at body size once shrunk.
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(Money.string(safe))
                    .font(.fbNumber(44, weight: .bold))
                    .foregroundStyle(isOverspent ? Color.fbWarning : Color.fbInk)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .contentTransition(.numericText(value: safe))
                    .animation(.spring(response: 0.5, dampingFraction: 0.8), value: safe)
                if collapsed {
                    Text(collapsedSuffix)
                        .font(.fbBody(23))
                        .foregroundStyle(Color.fbSoftText)
                        .transition(.opacity)
                }
            }
            .scaleEffect(collapsed ? 0.62 : 1, anchor: .bottomLeading)
            .frame(height: collapsed ? 32 : 50, alignment: .bottomLeading)

            if !collapsed {
                Text(subtitle)
                    .font(.fbBody(15))
                    .foregroundStyle(Color.fbSoftText)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, collapsed ? 6 : 12)
        .padding(.bottom, collapsed ? 8 : 12)
        .animation(.fbModal, value: collapsed)
        // Text swallows hits, so AskView's background-tap catcher never
        // fires here — the header dismisses the keyboard itself. It lives
        // outside AskView's focus scope, so it resigns first responder.
        .contentShape(Rectangle())
        .onTapGesture {
            #if os(iOS)
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                            to: nil, from: nil, for: nil)
            #endif
        }
    }
}

// MARK: - Bubbles

/// User messages keep their bubble; the assistant answers in plain text,
/// like the page itself is talking.
private struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        if message.role == .user {
            HStack {
                Spacer(minLength: 40)
                Text(message.text)
                    .font(.fbBody(16))
                    .foregroundStyle(Color.fbOnAccent)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        // Bright bubble, dark text — same contrast pairing
                        // as the primary buttons.
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.fbPositive)
                    )
            }
        } else {
            Text(message.text)
                .font(.fbBody(16))
                .foregroundStyle(Color.fbInk)
                .lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
        }
    }
}

/// The tap targets for a staged write: Confirm on top, Cancel below —
/// the design system's vertical stack, never side-by-side. Typing or
/// dictating "confirm"/"cancel" still works through the same paths.
private struct ProposalDecisionButtons: View {
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            FBPrimaryButton(label: "Confirm", action: onConfirm)
            FBSecondaryButton(label: "Cancel", action: onCancel)
        }
        .padding(.top, 2)
        .transition(.opacity)
    }
}

private struct ThinkingBubble: View {
    @State private var phase = 0.0
    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3) { i in
                Circle()
                    .fill(Color.fbSoftText)
                    .frame(width: 7, height: 7)
                    .opacity(phase == Double(i) ? 1 : 0.3)
            }
            Spacer(minLength: 40)
        }
        .padding(.vertical, 8)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                phase = 2
            }
        }
    }
}

#Preview {
    // Seed a short conversation so the preview shows real bubbles.
    let store = FinanceBuddyStore(finances: .sample)
    let model = ChatViewModel()
    model.messages.append(ChatMessage(role: .user, text: "Can I afford a £380/month car payment?"))
    model.messages.append(ChatMessage(role: .assistant,
        text: LocalReasoner.answer(to: "Can I afford a £380/month car payment?", finances: store.finances)))
    return AskViewPreview(store: store, model: model)
}

#Preview("Empty") {
    let store = FinanceBuddyStore(finances: .sample)
    return PreviewModalHost(store: store) { present in
        AskView(store: store, present: present)
            .safeAreaBar(edge: .top) { AskHeaderBar(store: store, collapsed: false) }
    }
}

/// Small wrapper so the preview can inject a pre-seeded view model.
private struct AskViewPreview: View {
    let store: FinanceBuddyStore
    let model: ChatViewModel
    var body: some View {
        AskView(store: store, injectedModel: model)
            .safeAreaBar(edge: .top) { AskHeaderBar(store: store, collapsed: true) }
            .background {
                FBBackground()
                FBBlobBackground()
            }
            .preferredColorScheme(.dark)
    }
}
