//
//  ConfirmationRouting.swift
//  Headroom
//
//  Tier 0: resolving a staged write is a yes/no decision the model never
//  sees. When proposals are pending, the user's next message is checked
//  here first — a clear yes applies them, a clear no drops them, and
//  anything else goes to the model as a normal turn (with the proposals
//  kept pending).
//

import Foundation

enum ConfirmationRouting {

    enum Decision: Equatable {
        case confirm, cancel, other
    }

    /// Only short, unambiguous replies count. "Yes but make it 30" is
    /// `other` — it goes back to the model, which will re-propose.
    static func decision(for text: String) -> Decision {
        // Apostrophes vanish ("don't" → "dont"); everything else
        // non-alphanumeric becomes a token break.
        let cleaned = text.lowercased().filter { $0 != "'" && $0 != "’" }
        let normalized = String(cleaned.map { $0.isLetter || $0.isNumber ? $0 : " " })
        let tokens = normalized.split(separator: " ").map(String.init)

        guard !tokens.isEmpty, tokens.count <= 5 else { return .other }

        if tokens.contains(where: { cancelWords.contains($0) }) {
            return .cancel
        }
        if tokens.contains(where: { confirmWords.contains($0) }),
           tokens.allSatisfy({ confirmWords.contains($0) || fillerWords.contains($0) }) {
            return .confirm
        }
        return .other
    }

    private static let confirmWords: Set<String> = [
        "confirm", "confirmed", "yes", "yeah", "yep", "yup", "sure",
        "ok", "okay", "add", "save", "log", "correct", "right",
        "ahead", "proceed", "approve", "do",
    ]

    private static let cancelWords: Set<String> = [
        "no", "nope", "cancel", "dont", "stop", "discard",
        "forget", "never", "nevermind", "drop", "remove",
    ]

    /// Words allowed to ride along with a confirmation without making it
    /// ambiguous ("yes please", "add it", "go ahead").
    private static let fillerWords: Set<String> = [
        "please", "it", "that", "them", "all", "the", "this", "go",
        "and", "thanks", "thank", "you", "payment", "income", "expense",
    ]
}
