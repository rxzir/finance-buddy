//
//  ProfileView.swift
//  Finance buddy
//
//  Basic account page: who's signed in and a sign-out action. The sign-out
//  confirmation is a custom ZStack overlay (never .sheet / .alert chrome).
//

import SwiftUI

struct ProfileView: View {
    /// Signed-in email; nil when auth isn't wired (e.g. Supabase not linked).
    let email: String?
    /// Async sign-out action; nil hides the button.
    let onSignOut: (() async -> Void)?

    @State private var showConfirm = false
    @State private var isSigningOut = false

    var body: some View {
        ZStack {
            Color.fbBackground.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    header
                    accountCard
                    aboutCard
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }

            if showConfirm {
                confirmOverlay
            }
        }
    }

    private var header: some View {
        HStack {
            Text("Profile")
                .font(.fbHeader(28))
                .tracking(-0.5)
                .foregroundStyle(Color.fbInk)
            Spacer()
        }
        .padding(.top, 4)
    }

    private var accountCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 14) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(Color.fbPositive)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(email ?? "Not signed in")
                            .font(.fbBody(17, weight: .semibold))
                            .foregroundStyle(Color.fbInk)
                        Text(email == nil ? "Connect Supabase to enable accounts"
                                          : "Signed in")
                            .font(.fbBody(13))
                            .foregroundStyle(Color.fbSoftText)
                    }
                }

                if onSignOut != nil {
                    Button {
                        showConfirm = true
                    } label: {
                        Text("Sign out")
                            .font(.fbBody(16, weight: .semibold))
                            .foregroundStyle(Color.fbWarning)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(Color.fbWarning.opacity(0.5), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var aboutCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("About")
                    .font(.fbHeader(17))
                    .tracking(-0.3)
                    .foregroundStyle(Color.fbInk)
                row("App", "Finance buddy")
                row("Version", appVersion)
                row("Data", "Stored in your Supabase account")
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.fbBody(15))
                .foregroundStyle(Color.fbSoftText)
            Spacer()
            Text(value)
                .font(.fbBody(15, weight: .medium))
                .foregroundStyle(Color.fbInk)
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    // MARK: Sign-out confirmation (custom overlay, not .alert)

    private var confirmOverlay: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture { showConfirm = false }

            Card(cornerRadius: 22) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Sign out?")
                        .font(.fbHeader(20))
                        .tracking(-0.3)
                        .foregroundStyle(Color.fbInk)
                    Text("Your data stays safe in your account. You'll need to sign in again to see it.")
                        .font(.fbBody(15))
                        .foregroundStyle(Color.fbSoftText)

                    HStack(spacing: 12) {
                        Button {
                            showConfirm = false
                        } label: {
                            Text("Cancel")
                                .font(.fbBody(16, weight: .semibold))
                                .foregroundStyle(Color.fbSoftText)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(Color.fbBackground)
                                )
                        }
                        .buttonStyle(.plain)

                        Button {
                            Task {
                                isSigningOut = true
                                await onSignOut?()
                                isSigningOut = false
                                showConfirm = false
                            }
                        } label: {
                            HStack {
                                if isSigningOut { ProgressView().tint(.fbOnAccent) }
                                Text("Sign out")
                                    .font(.fbBody(16, weight: .semibold))
                            }
                            .foregroundStyle(Color.fbOnAccent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.fbWarning)
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(isSigningOut)
                    }
                }
            }
            .padding(.horizontal, 24)
        }
        .transition(.opacity)
    }
}

#Preview {
    ProfileView(email: "rxzirr@gmail.com", onSignOut: {})
        .preferredColorScheme(.dark)
}
