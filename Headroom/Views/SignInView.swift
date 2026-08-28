//
//  SignInView.swift
//  Headroom
//
//  Email + password sign-in / sign-up. Shown after the biometric gate when
//  there's no Supabase session. Gated on the package being present.
//

#if canImport(Supabase)
import SwiftUI
import AuthenticationServices
import CryptoKit

struct SignInView: View {
    @Bindable var auth: SupabaseAuthModel
    @Environment(\.colorScheme) private var colorScheme

    @State private var email = ""
    @State private var password = ""
    @State private var isSignUp = false
    @State private var isForgotPassword = false
    @State private var pendingAppleNonce: String?

    private var canSubmit: Bool {
        if isForgotPassword {
            return email.contains("@") && !auth.isWorking
        }
        return email.contains("@") && password.count >= 6 && !auth.isWorking
    }

    var body: some View {
        ZStack {
            FBBackground()

            VStack(spacing: 20) {
                Spacer()

                // Header — icon changes per mode so the screens feel distinct
                VStack(spacing: 10) {
                    Image(systemName: isForgotPassword ? "envelope.badge"
                                     : (isSignUp ? "person.badge.plus" : "lock.fill"))
                        .font(.system(size: 30, weight: .medium))
                        .foregroundStyle(Color.fbSoftText)

                    VStack(spacing: 4) {
                        Text("Headroom")
                            .font(.fbHeader(28))
                            .tracking(-0.5)
                            .foregroundStyle(Color.fbInk)
                        Text(isForgotPassword ? "Reset your password"
                                             : (isSignUp ? "Create your account" : "Welcome back"))
                            .font(.fbBody(15))
                            .foregroundStyle(Color.fbSoftText)
                    }
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
                        if !isForgotPassword {
                            LabeledField(label: "Password") {
                                secureField($password, placeholder: "At least 6 characters")
                            }
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
                                Text(isForgotPassword ? "Send reset link"
                                                      : (isSignUp ? "Create account" : "Sign in"))
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
                        .buttonStyle(.pressable)
                        .disabled(!canSubmit)

                        // Social sign-in — hidden in forgot-password flow
                        if !isForgotPassword {
                            HStack {
                                Rectangle().fill(Color.fbHairline).frame(height: 1)
                                Text("or")
                                    .font(.fbBody(12))
                                    .foregroundStyle(Color.fbSoftText)
                                    .padding(.horizontal, 8)
                                Rectangle().fill(Color.fbHairline).frame(height: 1)
                            }

                            SignInWithAppleButton(
                                isSignUp ? .signUp : .signIn,
                                onRequest: { request in
                                    let raw = UUID().uuidString + UUID().uuidString
                                    pendingAppleNonce = raw
                                    request.requestedScopes = [.fullName, .email]
                                    request.nonce = SHA256.hash(data: Data(raw.utf8))
                                        .compactMap { String(format: "%02x", $0) }.joined()
                                },
                                onCompletion: { result in
                                    switch result {
                                    case .success(let authorization):
                                        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                                              let nonce = pendingAppleNonce else { return }
                                        Task { await auth.signInWithApple(credential: credential, nonce: nonce) }
                                    case .failure(let error):
                                        let code = (error as NSError).code
                                        if code != ASAuthorizationError.canceled.rawValue {
                                            auth.errorMessage = error.localizedDescription
                                        }
                                    }
                                }
                            )
                            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                            .frame(height: 50)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                            googleSignInButton
                        }
                    }
                }
                .padding(.horizontal, 20)

                // Bottom links
                if isForgotPassword {
                    Button {
                        withAnimation { isForgotPassword = false; auth.errorMessage = nil; auth.infoMessage = nil }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.fbBody(13, weight: .semibold))
                            Text("Back to sign in")
                                .font(.fbBody(14, weight: .medium))
                        }
                        .foregroundStyle(Color.fbAccent)
                    }
                    .buttonStyle(.pressable)
                } else {
                    VStack(spacing: 10) {
                        Button {
                            withAnimation { isSignUp.toggle(); auth.errorMessage = nil; auth.infoMessage = nil }
                        } label: {
                            HStack(spacing: 4) {
                                Text(isSignUp ? "Have an account?" : "New here?")
                                    .font(.fbBody(14))
                                    .foregroundStyle(Color.fbSoftText)
                                Text(isSignUp ? "Sign in" : "Create an account")
                                    .font(.fbBody(14, weight: .semibold))
                                    .foregroundStyle(Color.fbAccent)
                                    .underline()
                            }
                        }
                        .buttonStyle(.pressable)

                        if !isSignUp {
                            Button {
                                withAnimation { isForgotPassword = true; auth.errorMessage = nil; auth.infoMessage = nil }
                            } label: {
                                Text("Forgot password?")
                                    .font(.fbBody(14, weight: .medium))
                                    .foregroundStyle(Color.fbAccent)
                                    .underline()
                            }
                            .buttonStyle(.pressable)
                        }
                    }
                }

                Spacer()
            }
        }
    }

    private var googleSignInButton: some View {
        Button {
            Task { await auth.signInWithGoogle() }
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(Color.white).frame(width: 22, height: 22)
                    Text("G")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color(hex: 0x4285F4))
                }
                Text(isSignUp ? "Sign up with Google" : "Sign in with Google")
                    .font(.fbBody(16, weight: .semibold))
                    .foregroundStyle(Color.fbInk)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.fbBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.fbHairline, lineWidth: 1)
            )
        }
        .buttonStyle(.pressable)
        .disabled(auth.isWorking)
    }

    private func submit() {
        Task {
            if isForgotPassword {
                await auth.resetPassword(email: email)
            } else if isSignUp {
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
