//
//  LockView.swift
//  Headroom
//
//  The screen shown until the user passes the biometric / passcode gate.
//

import SwiftUI

struct LockView: View {
    @Bindable var lock: AppLock

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "lock.fill")
                .font(.system(size: 44, weight: .bold))
                .foregroundStyle(Color.fbPositive)

            VStack(spacing: 6) {
                Text("Headroom")
                    .font(.fbHeader(26))
                    .tracking(-0.5)
                    .foregroundStyle(Color.fbInk)
                Text("Locked for your eyes only.")
                    .font(.fbBody(15))
                    .foregroundStyle(Color.fbSoftText)
            }

            if let error = lock.lastError {
                Text(error)
                    .font(.fbBody(13))
                    .foregroundStyle(Color.fbWarning)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Spacer()

            Button {
                Task { await lock.authenticate() }
            } label: {
                Text("Unlock with \(lock.biometryName)")
                    .font(.fbBody(16, weight: .semibold))
                    .foregroundStyle(Color.fbOnAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.fbPositive)
                    )
            }
            .buttonStyle(.pressable)
            .disabled(lock.isAuthenticating)
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.fbBackground)
    }
}

#Preview {
    LockView(lock: AppLock())
}
