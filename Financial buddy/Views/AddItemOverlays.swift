//
//  AddItemOverlays.swift
//  Finance buddy
//
//  Shared form building blocks and the modal scaffold used by the Budget
//  edit overlays. Deliberately NOT .sheet() — a dimmed ZStack with a
//  floating card so iOS's default sheet styling can't override the look.
//

import SwiftUI

// MARK: - Modal scaffold

/// A dimmed backdrop with a floating card, cancel/save footer, and the
/// enter/exit transition. Content is the form body.
struct ModalOverlay<Content: View>: View {
    let title: String
    var canSave: Bool
    var saveLabel: String = "Add"
    let onCancel: () -> Void
    let onSave: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture(perform: onCancel)

            VStack(spacing: 0) {
                Spacer()
                Card(cornerRadius: 22) {
                    VStack(alignment: .leading, spacing: 18) {
                        Text(title)
                            .font(.fbHeader(20))
                            .tracking(-0.3)
                            .foregroundStyle(Color.fbInk)

                        content

                        HStack(spacing: 12) {
                            Button(action: onCancel) {
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

                            Button(action: onSave) {
                                Text(saveLabel)
                                    .font(.fbBody(16, weight: .semibold))
                                    .foregroundStyle(Color.fbOnAccent)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .fill(canSave ? Color.fbPositive : Color.fbHairline)
                                    )
                            }
                            .buttonStyle(.plain)
                            .disabled(!canSave)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
        .transition(.opacity)
    }
}

// MARK: - Small form building blocks

struct LabeledField<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.fbBody(14))
                .foregroundStyle(Color.fbSoftText)
            content
        }
    }
}

struct PlainTextField: View {
    let placeholder: String
    @Binding var text: String
    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(.fbBody(17, weight: .medium))
            .foregroundStyle(Color.fbInk)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.fbBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.fbHairline, lineWidth: 1)
            )
    }
}

/// A numeric field showing the currency symbol, for a non-optional value.
struct CurrencyField: View {
    @Binding var value: Double

    var body: some View {
        HStack(spacing: 6) {
            Text(Money.currencySymbol)
                .font(.fbNumber(22, weight: .semibold))
                .foregroundStyle(Color.fbSoftText)
            TextField("0", value: $value, format: .number.precision(.fractionLength(0...2)))
                .textFieldStyle(.plain)
                .font(.fbNumber(22, weight: .semibold))
                .foregroundStyle(Color.fbInk)
                .decimalKeyboard()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.fbBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.fbHairline, lineWidth: 1)
        )
    }
}

/// Like CurrencyField but for an optional value (empty until typed).
struct CurrencyEntryField: View {
    @Binding var value: Double?
    var body: some View {
        HStack(spacing: 6) {
            Text(Money.currencySymbol)
                .font(.fbNumber(20, weight: .semibold))
                .foregroundStyle(Color.fbSoftText)
            TextField("0", value: $value, format: .number.precision(.fractionLength(0...2)))
                .textFieldStyle(.plain)
                .font(.fbNumber(20, weight: .semibold))
                .foregroundStyle(Color.fbInk)
                .decimalKeyboard()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.fbBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.fbHairline, lineWidth: 1)
        )
    }
}

extension Money {
    static var currencySymbol: String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = currencyCode
        return f.currencySymbol ?? "£"
    }
}
