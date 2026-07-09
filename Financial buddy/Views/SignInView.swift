//
//  SignInView.swift
//  Finance buddy
//
//  Email + password sign-in / sign-up. Shown after the biometric gate when
//  there's no Supabase session. Gated on the package being present.
//

#if canImport(Supabase)
import SwiftUI

struct SignInView: View {
    @Bindable var auth: SupabaseAuthModel

    @State private var email = ""
    @State private var password = ""
    @State private var isSignUp = false

    private var canSubmit: Bool {
        email.contains("@") && password.count >= 6 && !auth.isWorking
    }

    var body: some View {
        ZStack {
            Color.fbBackground.ignoresSafeArea()

            VStack(spacing: 20) {
                Spacer()

                VStack(spacing: 6) {
                    Text("Finance buddy")
                        .font(.fbHeader(28))
                        .tracking(-0.5)
                        .foregroundStyle(Color.fbInk)
                    Text(isSignUp ? "Create your account" : "Welcome back")
                        .font(.fbBody(15))
                        .foregroundStyle(Color.fbSoftText)
                }

                Card {
                    VStack(alignment: .leading, spacing: 16) {
                        LabeledField(label: "Email") {
                            field($email, placeholder: "you@example.com")
                                .textContentType(.emailAddress)
                                #if os(iOS)
                                .keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never)
                                #endif
                        }
                        LabeledField(label: "Password") {
                            secureField($password, placeholder: "At least 6 characters")
                        }

                        if let error = auth.errorMessage {
                            Text(error)
                                .font(.fbBody(13))
                                .foregroundStyle(Color.fbWarning)
                        }

                        if let info = auth.infoMessage {
                            Text(info)
                                .font(.fbBody(13))
                                .foregroundStyle(Color.fbPositive)
                        }

                        Button(action: submit) {
                            HStack {
                                if auth.isWorking { ProgressView().tint(.fbOnAccent) }
                                Text(isSignUp ? "Create account" : "Sign in")
                                    .font(.fbBody(16, weight: .semibold))
                            }
                            .foregroundStyle(Color.fbOnAccent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(canSubmit ? Color.fbPositive : Color.fbHairline)
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(!canSubmit)
                    }
                }
                .padding(.horizontal, 20)

                Button {
                    withAnimation { isSignUp.toggle(); auth.errorMessage = nil; auth.infoMessage = nil }
                } label: {
                    Text(isSignUp ? "Have an account? Sign in"
                                  : "New here? Create an account")
                        .font(.fbBody(14, weight: .medium))
                        .foregroundStyle(Color.fbPositive)
                }
                .buttonStyle(.plain)

                Spacer()
            }
        }
    }

    private func submit() {
        Task {
            if isSignUp {
                await auth.signUp(email: email, password: password)
                // Confirmation-required flow: drop back to sign-in so the
                // user can log in right after tapping the email link.
                if auth.infoMessage != nil {
                    withAnimation { isSignUp = false }
                }
            } else {
                await auth.signIn(email: email, password: password)
            }
        }
    }

    private func field(_ text: Binding<String>, placeholder: String) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.plain)
            .font(.fbBody(17, weight: .medium))
            .foregroundStyle(Color.fbInk)
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.fbBackground))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.fbHairline, lineWidth: 1))
    }

    private func secureField(_ text: Binding<String>, placeholder: String) -> some View {
        SecureField(placeholder, text: text)
            .textFieldStyle(.plain)
            .font(.fbBody(17, weight: .medium))
            .foregroundStyle(Color.fbInk)
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.fbBackground))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.fbHairline, lineWidth: 1))
    }
}
#endif
