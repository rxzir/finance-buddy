//
//  AddItemOverlays.swift
//  Finance buddy
//
//  Custom modal overlays for adding a recurring commitment or a one-off
//  cost. Deliberately NOT .sheet() — a dimmed ZStack with a floating card
//  so iOS's default sheet styling can't override the look.
//

import SwiftUI

// MARK: - Scaffold shared by both overlays

/// A dimmed backdrop with a floating card, cancel/save footer, and the
/// enter/exit transition. Content is the form body.
struct ModalOverlay<Content: View>: View {
    let title: String
    var canSave: Bool
    let onCancel: () -> Void
    let onSave: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            Color.hrInk.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture(perform: onCancel)

            VStack(spacing: 0) {
                Spacer()
                Card(cornerRadius: 22) {
                    VStack(alignment: .leading, spacing: 18) {
                        Text(title)
                            .font(.hrHeader(20))
                            .tracking(-0.3)
                            .foregroundStyle(Color.hrInk)

                        content

                        HStack(spacing: 12) {
                            Button(action: onCancel) {
                                Text("Cancel")
                                    .font(.hrBody(16, weight: .semibold))
                                    .foregroundStyle(Color.hrSoftText)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .fill(Color.hrBackground)
                                    )
                            }
                            .buttonStyle(.plain)

                            Button(action: onSave) {
                                Text("Add")
                                    .font(.hrBody(16, weight: .semibold))
                                    .foregroundStyle(Color.hrCard)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .fill(canSave ? Color.hrPositive : Color.hrHairline)
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

// MARK: - Add recurring commitment

struct AddCommitmentOverlay: View {
    let onCancel: () -> Void
    let onSave: (RecurringCommitment) -> Void

    @State private var name = ""
    @State private var amount: Double?
    @State private var dueDay = 1
    @State private var category = "General"

    private let categories = ["General", "Housing", "Utilities", "Subscriptions",
                              "Health", "Transport", "Insurance", "Debt"]

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && (amount ?? 0) > 0
    }

    var body: some View {
        ModalOverlay(title: "New commitment",
                     canSave: canSave,
                     onCancel: onCancel,
                     onSave: save) {
            VStack(alignment: .leading, spacing: 16) {
                LabeledField(label: "Name") {
                    PlainTextField(placeholder: "e.g. Rent", text: $name)
                }
                LabeledField(label: "Amount") {
                    CurrencyEntryField(value: $amount)
                }
                LabeledField(label: "Due day of month") {
                    Picker("", selection: $dueDay) {
                        ForEach(1...31, id: \.self) { Text("Day \($0)").tag($0) }
                    }
                    .pickerStyle(.menu)
                    .tint(Color.hrInk)
                }
                LabeledField(label: "Category") {
                    Picker("", selection: $category) {
                        ForEach(categories, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .tint(Color.hrInk)
                }
            }
        }
    }

    private func save() {
        onSave(RecurringCommitment(name: name.trimmingCharacters(in: .whitespaces),
                                   amount: amount ?? 0,
                                   dueDay: dueDay,
                                   category: category))
    }
}

// MARK: - Add one-off cost

struct AddOneOffOverlay: View {
    let onCancel: () -> Void
    let onSave: (OneOffCost) -> Void

    @State private var name = ""
    @State private var amount: Double?
    @State private var date = Date()

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && (amount ?? 0) > 0
    }

    var body: some View {
        ModalOverlay(title: "New one-off cost",
                     canSave: canSave,
                     onCancel: onCancel,
                     onSave: save) {
            VStack(alignment: .leading, spacing: 16) {
                LabeledField(label: "Name") {
                    PlainTextField(placeholder: "e.g. Flights", text: $name)
                }
                LabeledField(label: "Amount") {
                    CurrencyEntryField(value: $amount)
                }
                LabeledField(label: "Date") {
                    DatePicker("", selection: $date, displayedComponents: .date)
                        .labelsHidden()
                        .datePickerStyle(.compact)
                        .tint(Color.hrPositive)
                }
            }
        }
    }

    private func save() {
        onSave(OneOffCost(name: name.trimmingCharacters(in: .whitespaces),
                          amount: amount ?? 0,
                          date: date))
    }
}

// MARK: - Small form building blocks

struct LabeledField<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.hrBody(14))
                .foregroundStyle(Color.hrSoftText)
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
            .font(.hrBody(17, weight: .medium))
            .foregroundStyle(Color.hrInk)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.hrBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.hrHairline, lineWidth: 1)
            )
    }
}

/// Like CurrencyField but for an optional value (empty until typed).
struct CurrencyEntryField: View {
    @Binding var value: Double?
    var body: some View {
        HStack(spacing: 6) {
            Text(Money.currencySymbol)
                .font(.hrNumber(20, weight: .semibold))
                .foregroundStyle(Color.hrSoftText)
            TextField("0", value: $value, format: .number.precision(.fractionLength(0...2)))
                .textFieldStyle(.plain)
                .font(.hrNumber(20, weight: .semibold))
                .foregroundStyle(Color.hrInk)
                .decimalKeyboard()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.hrBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.hrHairline, lineWidth: 1)
        )
    }
}

#Preview("Add commitment") {
    ZStack {
        Color.hrBackground.ignoresSafeArea()
        AddCommitmentOverlay(onCancel: {}, onSave: { _ in })
    }
}
