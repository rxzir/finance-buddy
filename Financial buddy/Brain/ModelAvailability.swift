//
//  ModelAvailability.swift
//  Finance buddy
//
//  One place that answers "can we use the on-device model right now?".
//  Nothing constructs a LanguageModelSession without checking this first.
//

import Foundation
import FoundationModels

/// App-facing availability of the on-device foundation model.
enum ModelAvailability: Equatable, Sendable {
    case ready
    case unavailable(reason: String)

    nonisolated var isReady: Bool {
        if case .ready = self { return true }
        return false
    }

    /// Snapshot of the system model's availability right now.
    nonisolated static func check(_ model: SystemLanguageModel = .default) -> ModelAvailability {
        switch model.availability {
        case .available:
            return .ready
        case .unavailable(.deviceNotEligible):
            return .unavailable(reason: "This device doesn't support Apple Intelligence.")
        case .unavailable(.appleIntelligenceNotEnabled):
            return .unavailable(reason: "Apple Intelligence is turned off in Settings.")
        case .unavailable(.modelNotReady):
            return .unavailable(reason: "The on-device model is still downloading.")
        case .unavailable:
            return .unavailable(reason: "The on-device model is unavailable.")
        }
    }
}
