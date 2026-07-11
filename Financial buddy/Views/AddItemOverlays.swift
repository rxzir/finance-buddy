//
//  AddItemOverlays.swift
//  Finance buddy
//
//  The modal system and shared form building blocks. Deliberately NOT
//  .sheet() — a dimmed ZStack with floating cards so iOS's default sheet
//  styling can't override the look. Cards stack on the z-axis: when a
//  form opens on top of a list, the list recedes (scales down, dims) and
//  the form arrives with the shared fbModalPush transition.
//

import SwiftUI

// MARK: - Modal scaffold

/// Soft glass dim behind every modal: a light blur with only a whisper of
/// darkening — the screen behind stays readable, just recessed.
struct ModalBackdrop: View {
    let onTap: () -> Void
    var body: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .ignoresSafeArea()
            .overlay(Color.black.opacity(0.18).ignoresSafeArea())
            .onTapGesture(perform: onTap)
    }
}

/// A bottom-anchored floating card that can recede behind stacked cards.
/// `depth` 0 is frontmost; each level back scales down and dims, like
/// iOS's stacked sheets.
struct ModalCard<Content: View>: View {
    var depth: Int = 0
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 60)
            Card(cornerRadius: 22, opaque: true) { content }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
                // Tapping any non-interactive part of the card closes the
                // keyboard (the decimal pad has no return key). Controls
                // inside still win the tap.
                .contentShape(Rectangle())
                .onTapGesture { fbDismissKeyboard() }
        }
        .scaleEffect(1 - CGFloat(depth) * 0.05, anchor: .bottom)
        .offset(y: CGFloat(depth) * -10)
        .blur(radius: CGFloat(depth) * 1.5)
        .opacity(depth == 0 ? 1 : 0.55)
        .allowsHitTesting(depth == 0)
    }
}

/// Vertically stacked modal actions: filled primary on top, quiet
/// secondary below. The only footer layout modals use.
struct ModalActionButtons: View {
    let primaryLabel: String
    var primaryEnabled = true
    var destructive = false
    let onPrimary: () -> Void
    var secondaryLabel = "Cancel"
    let onSecondary: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            FBPrimaryButton(label: primaryLabel, enabled: primaryEnabled,
                            destructive: destructive, action: onPrimary)
            FBSecondaryButton(label: secondaryLabel, action: onSecondary)
        }
    }
}

/// Single-card modal: backdrop + one floating card with a form body and
/// the standard vertical Save/Cancel footer.
struct ModalOverlay<Content: View>: View {
    let title: String
    var canSave: Bool
    var saveLabel: String = "Add"
    let onCancel: () -> Void
    let onSave: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            ModalBackdrop(onTap: onCancel)
            ModalCard {
                VStack(alignment: .leading, spacing: 18) {
                    Text(title)
                        .font(.fbHeader(20))
                        .tracking(-0.3)
                        .foregroundStyle(Color.fbInk)

                    content

                    ModalActionButtons(primaryLabel: saveLabel,
                                       primaryEnabled: canSave,
                                       onPrimary: onSave,
                                       onSecondary: onCancel)
                }
            }
            .transition(.fbModalPush)
        }
        .transition(.opacity)
    }
}

// MARK: - List row & empty hint (shared by every manage modal)

/// A tappable item row with a trailing delete — the one list style used
/// in every manage modal (payments, income, categories).
struct ModalItemRow: View {
    let name: String
    let detail: String
    var amount: Double?
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onEdit) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name)
                            .font(.fbBody(16, weight: .medium))
                            .foregroundStyle(Color.fbInk)
                        if !detail.isEmpty {
                            Text(detail)
                                .font(.fbBody(13))
                                .foregroundStyle(Color.fbSoftText)
                        }
                    }
                    Spacer()
                    if let amount {
                        Text(Money.string(amount))
                            .font(.fbNumber(15, weight: .medium))
                            .foregroundStyle(Color.fbInk)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)

            Button(action: onDelete) {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.fbWarning.opacity(0.85))
            }
            .buttonStyle(.pressable)
        }
        .padding(.vertical, 7)
    }
}

struct ModalEmptyHint: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.fbBody(14))
            .foregroundStyle(Color.fbSoftText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 10)
    }
}

// MARK: - Drafts (shared by the manage modals and quick add)

/// Form state for a payment. `id == nil` means a brand-new item. The date
/// doubles as the monthly anchor when recurring (repeats on that day).
struct PaymentDraft {
    var id: UUID?
    var name = ""
    var amount: Double?
    var isRecurring = true
    var category = "General"
    var date = Date()

    /// Day of the month a recurring payment lands on.
    var dueDay: Int { Calendar.current.component(.day, from: date) }

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && (amount ?? 0) > 0
    }
}

/// Form state for an income source. `id == nil` means a brand-new item.
struct IncomeDraft {
    var id: UUID?
    var name = ""
    var amount: Double?
    var isRecurring = true
    var category = "General"
    var date = Date()

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && (amount ?? 0) > 0
    }
}

// MARK: - Form fields (the single source for payment / income forms)

struct PaymentFormFields: View {
    @Binding var draft: PaymentDraft
    let categories: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            LabeledField(label: "Name") {
                PlainTextField(placeholder: draft.isRecurring ? "e.g. Rent" : "e.g. Flights",
                               text: $draft.name)
            }
            LabeledField(label: "Amount") {
                CurrencyEntryField(value: $draft.amount)
            }
            FBToggleRow(label: "Recurring", isOn: $draft.isRecurring)
            LabeledField(label: draft.isRecurring ? "Next payment" : "Date") {
                VStack(alignment: .leading, spacing: 6) {
                    FBDateField(date: $draft.date)
                    if draft.isRecurring {
                        Text("Repeats monthly on this day.")
                            .font(.fbBody(12))
                            .foregroundStyle(Color.fbSoftText)
                    }
                }
            }
            LabeledField(label: "Category") {
                Picker("", selection: $draft.category) {
                    ForEach(categories, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.menu)
                .tint(Color.fbInk)
            }
        }
    }
}

struct IncomeFormFields: View {
    @Binding var draft: IncomeDraft
    let categories: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            LabeledField(label: "Name") {
                PlainTextField(placeholder: draft.isRecurring ? "e.g. Salary" : "e.g. Refund",
                               text: $draft.name)
            }
            LabeledField(label: "Amount") {
                CurrencyEntryField(value: $draft.amount)
            }
            FBToggleRow(label: "Recurring", isOn: $draft.isRecurring)
            LabeledField(label: draft.isRecurring ? "Next payment" : "Date") {
                VStack(alignment: .leading, spacing: 6) {
                    FBDateField(date: $draft.date)
                    if draft.isRecurring {
                        Text("Repeats monthly on this day.")
                            .font(.fbBody(12))
                            .foregroundStyle(Color.fbSoftText)
                    }
                }
            }
            LabeledField(label: "Category") {
                Picker("", selection: $draft.category) {
                    ForEach(categories, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.menu)
                .tint(Color.fbInk)
            }
        }
    }
}

// MARK: - Quick add (from the Ask screen's + button)

/// One modal to capture anything: an expense (default) or an income
/// stream, recurring or one-off. Reuses the same form fields as the
/// Budget manage modals.
struct QuickAddOverlay: View {
    @Bindable var store: FinanceBuddyStore
    let onClose: () -> Void

    /// 0 = expense, 1 = income — expenses are the common case.
    @State private var kind = 0
    @State private var paymentDraft: PaymentDraft
    @State private var incomeDraft: IncomeDraft

    init(store: FinanceBuddyStore, onClose: @escaping () -> Void) {
        self.store = store
        self.onClose = onClose
        var p = PaymentDraft()
        p.category = store.finances.paymentCategories.first ?? "General"
        _paymentDraft = State(initialValue: p)
        var i = IncomeDraft()
        i.category = store.finances.incomeCategories.first ?? "General"
        _incomeDraft = State(initialValue: i)
    }

    var body: some View {
        ZStack {
            ModalBackdrop(onTap: onClose)
            ModalCard {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Add")
                        .font(.fbHeader(20))
                        .tracking(-0.3)
                        .foregroundStyle(Color.fbInk)

                    FBSegmentedControl(options: ["Expense", "Income"], selection: $kind)

                    if kind == 0 {
                        PaymentFormFields(draft: $paymentDraft,
                                          categories: store.finances.paymentCategories)
                    } else {
                        IncomeFormFields(draft: $incomeDraft,
                                         categories: store.finances.incomeCategories)
                    }

                    ModalActionButtons(primaryLabel: "Add",
                                       primaryEnabled: canSave,
                                       onPrimary: save,
                                       onSecondary: onClose)
                }
            }
            .transition(.fbModalPush)
        }
        .transition(.opacity)
        .animation(.fbModal, value: kind)
    }

    private var canSave: Bool {
        kind == 0 ? paymentDraft.isValid : incomeDraft.isValid
    }

    private func save() {
        if kind == 0 {
            let d = paymentDraft
            guard let amount = d.amount else { return }
            let name = d.name.trimmingCharacters(in: .whitespaces)
            if d.isRecurring {
                store.addCommitment(RecurringCommitment(name: name, amount: amount,
                                                        dueDay: d.dueDay, category: d.category))
            } else {
                store.addOneOff(OneOffCost(name: name, amount: amount, date: d.date))
            }
        } else {
            let d = incomeDraft
            guard let amount = d.amount else { return }
            store.addIncome(IncomeSource(name: d.name.trimmingCharacters(in: .whitespaces),
                                         amount: amount,
                                         isRecurring: d.isRecurring,
                                         category: d.category,
                                         date: d.date))
        }
        onClose()
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

// MARK: - Amount keyboard arithmetic

/// Calculator ops riding on the decimal keyboard itself (an accessory row,
/// not chrome in the form): +, −, ×, ÷ chain like a pocket calculator and
/// = resolves into the field.
private struct AmountKeyboardOps: ViewModifier {
    @Binding var value: Double?
    @FocusState private var focused: Bool
    @State private var pending: Double?
    @State private var pendingOp: String?

    func body(content: Content) -> some View {
        content
            .focused($focused)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    if focused {
                        ForEach(["+", "−", "×", "÷"], id: \.self) { op in
                            Button(op) { apply(op) }
                                .font(.fbNumber(19, weight: .semibold))
                        }
                        Spacer()
                        Button("=") { resolve() }
                            .font(.fbNumber(19, weight: .bold))
                    }
                }
            }
            .onChange(of: focused) {
                // Leaving the field settles any half-finished sum.
                if !focused { resolve() }
            }
    }

    private func apply(_ op: String) {
        resolve() // chain: 12 + 5 × … resolves 17 before storing ×
        pending = value
        pendingOp = op
        value = nil
    }

    private func resolve() {
        guard let a = pending, let op = pendingOp else { return }
        let b = value ?? 0
        switch op {
        case "+": value = a + b
        case "−": value = a - b
        case "×": value = a * b
        case "÷": value = b == 0 ? a : a / b
        default:  break
        }
        pending = nil
        pendingOp = nil
    }
}

extension View {
    /// Adds the calculator row to an amount field's keyboard.
    func amountKeyboardOps(value: Binding<Double?>) -> some View {
        modifier(AmountKeyboardOps(value: value))
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
                .amountKeyboardOps(value: Binding(get: { value },
                                                  set: { value = $0 ?? 0 }))
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
                .amountKeyboardOps(value: $value)
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

/// A date field that always reads "30 July 2026" — never the compact
/// picker's "30/07/2026". Tapping it unfolds the calendar inside the
/// card; picking a day folds it back.
struct FBDateField: View {
    @Binding var date: Date
    @State private var expanded = false

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.fbModal) { expanded.toggle() }
            } label: {
                HStack {
                    Text(date.formatted(.dateTime.day().month(.wide).year()))
                        .font(.fbBody(17, weight: .medium))
                        .foregroundStyle(Color.fbInk)
                    Spacer()
                    Image(systemName: "calendar")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(expanded ? Color.fbInk : Color.fbSoftText)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)

            if expanded {
                DatePicker("", selection: $date, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .tint(Color.fbPositive)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 6)
                    .transition(.opacity)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.fbBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.fbHairline, lineWidth: 1)
        )
        .onChange(of: date) {
            withAnimation(.fbModal) { expanded = false }
        }
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
