//
//  AppLock.swift
//  Finance buddy
//
//  Face ID / Touch ID gate on launch, falling back to the device passcode
//  when biometrics aren't enrolled or available. Uses
//  `.deviceOwnerAuthentication`, which chains biometrics → passcode for us.
//

import Foundation
import LocalAuthentication

@MainActor
@Observable
final class AppLock {
    var isUnlocked = false
    var lastError: String?
    private(set) var isAuthenticating = false

    /// The human-facing name of whatever biometry the device offers.
    var biometryName: String {
        switch LAContext().biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "device passcode"
        }
    }

    func authenticate() async {
        guard !isUnlocked, !isAuthenticating else { return }
        isAuthenticating = true
        defer { isAuthenticating = false }

        let context = LAContext()
        context.localizedFallbackTitle = "Enter Passcode"

        var policyError: NSError?
        // If no authentication is configured at all, don't lock the user
        // out of their own app.
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &policyError) else {
            isUnlocked = true
            return
        }

        do {
            isUnlocked = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Unlock Finance buddy to see what you can spend."
            )
            lastError = nil
        } catch {
            isUnlocked = false
            lastError = (error as? LAError)?.friendlyMessage ?? error.localizedDescription
        }
    }
}

private extension LAError {
    var friendlyMessage: String? {
        switch code {
        case .userCancel, .appCancel, .systemCancel:
            return nil // user backed out; not an error worth shouting about
        case .userFallback:
            return nil
        default:
            return localizedDescription
        }
    }
}
