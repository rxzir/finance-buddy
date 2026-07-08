//
//  AskView.swift
//  Finance buddy
//
//  Screen 3. A chat interface. The user asks affordability questions and
//  gets a reasoned answer. The view only knows the store + a service — it
//  never touches the network itself. No NavigationStack / sheet chrome.
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
    var messages: [ChatMessage] = [
        ChatMessage(role: .assistant,
                    text: "Ask me anything about what you can afford — a car payment, a holiday, moving flat. I'll factor in the costs that hide behind the headline number.")
    ]
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
    @State private var model: ChatViewModel
    @State private var draft = ""
    @State private var dictation = DictationController()

    init(store: FinanceBuddyStore) {
        self.store = store
        _model = State(initialValue: ChatViewModel())
    }

    /// Used by previews to inject a pre-seeded conversation.
    init(store: FinanceBuddyStore, injectedModel: ChatViewModel) {
        self.store = store
        _model = State(initialValue: injectedModel)
    }

    var body: some View {
        ZStack {
            Color.fbBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                transcript
                inputBar
            }
        }
    }

    private var header: some View {
        HStack {
            Text("Ask")
                .font(.fbHeader(28))
                .tracking(-0.5)
                .foregroundStyle(Color.fbInk)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
        .padding(.bottom, 12)
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

    // MARK: Input — primary dictation, backup text field

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

            micButton

            HStack(spacing: 10) {
                TextField("…or type your question", text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.fbBody(16))
                    .foregroundStyle(Color.fbInk)
                    .lineLimit(1...4)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color.fbCard)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(Color.fbHairline, lineWidth: 1)
                    )

                Button(action: send) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color.fbOnAccent)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(canSend ? Color.fbPositive : Color.fbHairline))
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(Color.fbBackground)
    }

    /// The primary way in: tap to talk, tap again to send what was heard.
    private var micButton: some View {
        Button {
            Task {
                if let spoken = await dictation.toggle() {
                    model.send(spoken, snapshot: store.finances)
                }
            }
        } label: {
            ZStack {
                Circle()
                    .fill(dictation.isRecording ? Color.fbWarning : Color.fbPositive)
                    .frame(width: 72, height: 72)
                    .shadow(color: (dictation.isRecording ? Color.fbWarning : Color.fbPositive).opacity(0.35),
                            radius: dictation.isRecording ? 18 : 10)
                Image(systemName: dictation.isRecording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Color.fbOnAccent)
            }
        }
        .buttonStyle(.plain)
        .disabled(model.isThinking)
        .animation(.easeInOut(duration: 0.2), value: dictation.isRecording)
        .accessibilityLabel(dictation.isRecording ? "Stop and send" : "Dictate a question")
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

private struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }

            Text(message.text)
                .font(.fbBody(16))
                .foregroundStyle(message.role == .user ? Color.fbOnAccent : Color.fbInk)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(message.role == .user ? Color.fbCommitment : Color.fbCard)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.fbHairline,
                                      lineWidth: message.role == .user ? 0 : 1)
                )

            if message.role == .assistant { Spacer(minLength: 40) }
        }
    }
}

private struct ThinkingBubble: View {
    @State private var phase = 0.0
    var body: some View {
        HStack {
            HStack(spacing: 5) {
                ForEach(0..<3) { i in
                    Circle()
                        .fill(Color.fbSoftText)
                        .frame(width: 7, height: 7)
                        .opacity(phase == Double(i) ? 1 : 0.3)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.fbCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.fbHairline, lineWidth: 1)
            )
            Spacer(minLength: 40)
        }
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

/// Small wrapper so the preview can inject a pre-seeded view model.
private struct AskViewPreview: View {
    let store: FinanceBuddyStore
    let model: ChatViewModel
    var body: some View {
        AskView(store: store, injectedModel: model)
    }
}
