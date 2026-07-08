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
            Color.hrBackground.ignoresSafeArea()

            VStack(spacing: 20) {
                Spacer()

                VStack(spacing: 6) {
                    Text("Finance buddy")
                        .font(.hrHeader(28))
                        .tracking(-0.5)
                        .foregroundStyle(Color.hrInk)
                    Text(isSignUp ? "Create your account" : "Welcome back")
                        .font(.hrBody(15))
                        .foregroundStyle(Color.hrSoftText)
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
                                .font(.hrBody(13))
                                .foregroundStyle(Color.hrWarning)
                        }

                        Button(action: submit) {
                            HStack {
                                if auth.isWorking { ProgressView().tint(.hrCard) }
                                Text(isSignUp ? "Create account" : "Sign in")
                                    .font(.hrBody(16, weight: .semibold))
                            }
                            .foregroundStyle(Color.hrCard)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(canSubmit ? Color.hrPositive : Color.hrHairline)
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(!canSubmit)
                    }
                }
                .padding(.horizontal, 20)

                Button {
                    withAnimation { isSignUp.toggle(); auth.errorMessage = nil }
                } label: {
                    Text(isSignUp ? "Have an account? Sign in"
                                  : "New here? Create an account")
                        .font(.hrBody(14, weight: .medium))
                        .foregroundStyle(Color.hrPositive)
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
            } else {
                await auth.signIn(email: email, password: password)
            }
        }
    }

    private func field(_ text: Binding<String>, placeholder: String) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.plain)
            .font(.hrBody(17, weight: .medium))
            .foregroundStyle(Color.hrInk)
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.hrBackground))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.hrHairline, lineWidth: 1))
    }

    private func secureField(_ text: Binding<String>, placeholder: String) -> some View {
        SecureField(placeholder, text: text)
            .textFieldStyle(.plain)
            .font(.hrBody(17, weight: .medium))
            .foregroundStyle(Color.hrInk)
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.hrBackground))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.hrHairline, lineWidth: 1))
    }
}
#endif
