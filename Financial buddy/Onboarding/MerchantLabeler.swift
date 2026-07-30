//
//  MerchantLabeler.swift
//  Finance buddy
//
//  On-device AI step. Receives ONLY the ~15 unique normalised merchant keys
//  (never raw transactions), asks the on-device model for a clean display
//  name and category, and falls back to title-cased key + "Other" when the
//  model is unavailable.
//

import Foundation
import FoundationModels

// MARK: - @Generable types (file-level so the macro can expand them)

@Generable
private struct MerchantLabel {
    @Guide(description: "Clean, title-cased merchant name, e.g. 'Spotify', 'EDF Energy', 'HMRC'.")
    var displayName: String

    @Guide(description: "Exactly one of: Housing, Utilities, Subscriptions, Debt, Insurance, Other.")
    var category: String
}

@Generable
private struct MerchantLabelBatch {
    @Guide(description: "One label per merchant key provided, in the same order, no extras or missing entries.")
    var labels: [MerchantLabel]
}

// MARK: - Labeler actor

actor MerchantLabeler {

    // Stored at init so availability checks don't touch async statics
    private let model = SystemLanguageModel.default

    /// Returns a mapping key → (displayName, category) for every key supplied.
    /// If the model is unavailable or errors, every key falls back to a
    /// title-cased version of the key + category "Other".
    func label(keys: [String]) async -> [String: (displayName: String, category: String)] {
        guard !keys.isEmpty else { return [:] }
        // Skip synchronous availability pre-check (model.availability is async in SDK).
        // LanguageModelSession.respond throws if the model isn't available; the catch
        // below already handles that by returning title-cased fallback labels.
        let keysList = keys.joined(separator: ", ")
        let count = keys.count
        let prompt = """
        Label these bank-statement merchant keys with a clean display name and category.
        Keys (in order): \(keysList)
        Return exactly \(count) label\(count == 1 ? "" : "s"), one per key, same order.
        """

        do {
            let session = LanguageModelSession(
                model: model,
                instructions: "You label UK bank statement merchant names concisely. Categories: Housing, Utilities, Subscriptions, Debt, Insurance, Other."
            )
            let response = try await session.respond(to: prompt, generating: MerchantLabelBatch.self)
            let batch = response.content.labels

            var result: [String: (displayName: String, category: String)] = [:]
            for (i, key) in keys.enumerated() {
                if i < batch.count {
                    result[key] = (batch[i].displayName, validCategory(batch[i].category))
                } else {
                    result[key] = fallbackLabel(key)
                }
            }
            return result
        } catch {
            return fallback(keys)
        }
    }

    // MARK: Fallbacks

    private func fallback(_ keys: [String]) -> [String: (displayName: String, category: String)] {
        Dictionary(uniqueKeysWithValues: keys.map { ($0, fallbackLabel($0)) })
    }

    private func fallbackLabel(_ key: String) -> (displayName: String, category: String) {
        let name = key.split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined(separator: " ")
        return (name, "Other")
    }

    private let validCategories = ["Housing", "Utilities", "Subscriptions",
                                   "Debt", "Insurance", "Other"]

    private func validCategory(_ raw: String) -> String {
        validCategories.first { $0.caseInsensitiveCompare(raw) == .orderedSame } ?? "Other"
    }
}
