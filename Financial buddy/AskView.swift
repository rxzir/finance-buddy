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
    let store: HeadroomStore
    @State private var model: ChatViewModel
    @State private var draft = ""

    init(store: HeadroomStore) {
        self.store = store
        _model = State(initialValue: ChatViewModel())
    }

    /// Used by previews to inject a pre-seeded conversation.
    init(store: HeadroomStore, injectedModel: ChatViewModel) {
        self.store = store
        _model = State(initialValue: injectedModel)
    }

    var body: some View {
        ZStack {
            Color.hrBackground.ignoresSafeArea()

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
                .font(.hrHeader(28))
                .tracking(-0.5)
                .foregroundStyle(Color.hrInk)
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

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Can I afford…", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.hrBody(16))
                .foregroundStyle(Color.hrInk)
                .lineLimit(1...4)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color.hrCard)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color.hrHairline, lineWidth: 1)
                )

            Button(action: send) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color.hrCard)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(canSend ? Color.hrPositive : Color.hrHairline))
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(Color.hrBackground)
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
                .font(.hrBody(16))
                .foregroundStyle(message.role == .user ? Color.hrCard : Color.hrInk)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(message.role == .user ? Color.hrCommitment : Color.hrCard)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.hrHairline,
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
                        .fill(Color.hrSoftText)
                        .frame(width: 7, height: 7)
                        .opacity(phase == Double(i) ? 1 : 0.3)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.hrCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.hrHairline, lineWidth: 1)
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
    let store = HeadroomStore(finances: .sample)
    let model = ChatViewModel()
    model.messages.append(ChatMessage(role: .user, text: "Can I afford a £380/month car payment?"))
    model.messages.append(ChatMessage(role: .assistant,
        text: LocalReasoner.answer(to: "Can I afford a £380/month car payment?", finances: store.finances)))
    return AskViewPreview(store: store, model: model)
}

/// Small wrapper so the preview can inject a pre-seeded view model.
private struct AskViewPreview: View {
    let store: HeadroomStore
    let model: ChatViewModel
    var body: some View {
        AskView(store: store, injectedModel: model)
    }
}
