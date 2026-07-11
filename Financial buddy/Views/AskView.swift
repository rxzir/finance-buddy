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
}

@MainActor
@Observable
final class ChatViewModel {
    var messages: [ChatMessage] = []
    var isThinking = false

    @ObservationIgnored private let service: AskServing

    init(service: AskServing = AskService()) {
        self.service = service
    }

    func send(_ text: String, snapshot: Finances) {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isThinking else { return }

        messages.append(ChatMessage(role: .user, text: question))
        isThinking = true

        Task {
            let reply: String
            do {
                reply = try await service.ask(question: question, snapshot: snapshot)
            } catch {
                reply = "Sorry — \(error.localizedDescription)"
            }
            isThinking = false
            messages.append(ChatMessage(role: .assistant, text: reply))
        }
    }
}

// MARK: - View

struct AskView: View {
    let store: FinanceBuddyStore
    /// False when another tab is showing; clears keyboard focus.
    var isActive: Bool = true
    /// Asks the root to present a modal (rendered above the tab bar).
    var present: (AppModal) -> Void = { _ in }
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
         present: @escaping (AppModal) -> Void = { _ in }) {
        self.store = store
        self.isActive = isActive
        self.present = present
        _model = State(initialValue: ChatViewModel())
    }

    /// Used by previews to inject a pre-seeded conversation.
    init(store: FinanceBuddyStore, injectedModel: ChatViewModel) {
        self.store = store
        _model = State(initialValue: injectedModel)
    }

    var body: some View {
        ZStack {
            // Tapping anywhere outside the field dismisses the keyboard.
            Color.fbBackground
                .ignoresSafeArea()
                .onTapGesture { inputFocused = false }

            // A slow drift of blurred blobs so the screen feels alive.
            BlobBackground()

            VStack(spacing: 0) {
                header
                if model.messages.isEmpty {
                    emptyBody
                } else {
                    transcript
                }
                inputBar
            }
        }
        // One place handles keyboard dismissal for both swipe and tab-bar
        // navigation: leaving the tab clears focus.
        .onChange(of: isActive) {
            if !isActive { inputFocused = false }
        }
    }

    // MARK: Header — THE number, big, first

    private var header: some View {
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

        return VStack(alignment: .leading, spacing: 2) {
            Text(Money.string(safe))
                .font(.fbNumber(44, weight: .bold))
                .foregroundStyle(isOverspent ? Color.fbWarning : Color.fbInk)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .contentTransition(.numericText(value: safe))
                .animation(.spring(response: 0.5, dampingFraction: 0.8), value: safe)
            Text(subtitle)
                .font(.fbBody(15))
                .foregroundStyle(Color.fbSoftText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 12)
        // Text swallows hits, so the background-tap catcher never fires
        // here — the header dismisses the keyboard itself.
        .contentShape(Rectangle())
        .onTapGesture { inputFocused = false }
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

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !model.isThinking
    }

    private func send() {
        let text = draft
        draft = ""
        model.send(text, snapshot: store.finances)
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
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.fbCommitment)
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

// MARK: - Living background

/// Two or three big, heavily blurred monochrome blobs drifting on slow
/// sine paths — a barely-there pulse so the screen doesn't feel static.
private struct BlobBackground: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                context.addFilter(.blur(radius: 70))
                blob(&context, size: size, t: t, speed: 0.10, phase: 0.0,
                     radius: 0.42, opacity: 0.09)
                blob(&context, size: size, t: t, speed: 0.06, phase: 2.1,
                     radius: 0.50, opacity: 0.06)
                blob(&context, size: size, t: t, speed: 0.045, phase: 4.4,
                     radius: 0.34, opacity: 0.075)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private func blob(_ context: inout GraphicsContext, size: CGSize,
                      t: Double, speed: Double, phase: Double,
                      radius: Double, opacity: Double) {
        let x = size.width * (0.5 + 0.38 * sin(t * speed + phase))
        let y = size.height * (0.45 + 0.34 * cos(t * speed * 0.8 + phase * 1.3))
        let r = size.width * radius
        let rect = CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)
        context.fill(Ellipse().path(in: rect),
                     with: .color(Color.fbInk.opacity(opacity)))
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
    }
}

/// Small wrapper so the preview can inject a pre-seeded view model.
private struct AskViewPreview: View {
    let store: FinanceBuddyStore
    let model: ChatViewModel
    var body: some View {
        AskView(store: store, injectedModel: model)
    }
}
