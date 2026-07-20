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
//  Fields follow the reference style: a soft filled pill whose label
//  doubles as the placeholder and floats into a tiny caption when the
//  field is focused or populated. Modals close from an X in the header;
//  footers carry a single primary action.
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

/// Every modal card's first row: the title with a round close button on
/// the right — modals have no Cancel in the footer.
struct ModalHeader: View {
    let title: String
    let onClose: () -> Void

    var body: some View {
        HStack {
            Text(title)
                .font(.fbHeader(20))
                .tracking(-0.3)
                .foregroundStyle(Color.fbInk)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.fbSoftText)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color.fbInk.opacity(0.06)))
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("Close")
        }
    }
}

// MARK: - List row & empty hint (shared by every manage modal)

/// A tappable item row — the one list style used in every manage modal
/// (payments, income, categories). Deletion lives on the row's
/// swipe-left action, so there's no trailing minus button.
struct ModalItemRow: View {
    let name: String
    let detail: String
    var amount: Double?
    let onEdit: () -> Void

    var body: some View {
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
        .padding(.vertical, 7)
    }
}

extension View {
    /// Shared row chrome for Lists living inside modal cards: clear row,
    /// no separators or default insets, and swipe-left to delete.
    func modalListRow(onDelete: @escaping () -> Void) -> some View {
        self
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets())
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                        .labelStyle(.iconOnly)
                }
            }
            .background(Color.clear)
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
    @Binding var showDatePicker: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PlainTextField(placeholder: "Name", text: $draft.name)
            CurrencyEntryField(value: $draft.amount)
            FBMenuField(label: "Category", selection: $draft.category,
                        options: categories)
            DateRecurringGroupField(date: $draft.date, isRecurring: $draft.isRecurring,
                                    showDatePicker: $showDatePicker)
        }
    }
}

struct IncomeFormFields: View {
    @Binding var draft: IncomeDraft
    let categories: [String]
    @Binding var showDatePicker: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PlainTextField(placeholder: "Name", text: $draft.name)
            CurrencyEntryField(value: $draft.amount)
            FBMenuField(label: "Category", selection: $draft.category,
                        options: categories)
            DateRecurringGroupField(date: $draft.date, isRecurring: $draft.isRecurring,
                                    showDatePicker: $showDatePicker)
        }
    }
}

/// Date picker row and recurring toggle sharing one rounded-rect container.
struct DateRecurringGroupField: View {
    @Binding var date: Date
    @Binding var isRecurring: Bool
    @Binding var showDatePicker: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Date row — mirrors FBFieldShell layout without its own background.
            Button {
                fbDismissKeyboard()
                showDatePicker = true
            } label: {
                HStack(spacing: 10) {
                    ZStack(alignment: .leading) {
                        Text("Date")
                            .font(.fbBody(16))
                            .foregroundStyle(Color.fbSoftText)
                            .scaleEffect(0.74, anchor: .leading)
                            .offset(y: -12)
                        Text(date.formatted(.dateTime.day().month(.wide).year()))
                            .font(.fbBody(16, weight: .medium))
                            .foregroundStyle(Color.fbInk)
                            .offset(y: 9)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "calendar")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(showDatePicker ? Color.fbInk : Color.fbSoftText)
                }
                .padding(.horizontal, 16)
                .frame(height: 60)
            }
            .buttonStyle(.pressable)

            Rectangle()
                .fill(Color.fbHairline)
                .frame(height: 1)
                .padding(.horizontal, 16)

            // Recurring toggle — label uses soft text colour, not full white.
            Toggle(isOn: $isRecurring) {
                Text("Recurring")
                    .font(.fbBody(15, weight: .medium))
                    .foregroundStyle(Color.fbSoftText)
            }
            .toggleStyle(FBSwitchStyle())
            .padding(.horizontal, 16)
            .frame(height: 60)
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.fbInk.opacity(0.05))
        )
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
    @State private var showDatePicker = false

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
            ModalBackdrop {
                if showDatePicker { showDatePicker = false } else { onClose() }
            }
            ModalCard(depth: showDatePicker ? 1 : 0) {
                VStack(alignment: .leading, spacing: 18) {
                    ModalHeader(title: "Add", onClose: onClose)

                    FBSegmentedControl(options: ["Expense", "Income"], selection: $kind)

                    if kind == 0 {
                        PaymentFormFields(draft: $paymentDraft,
                                          categories: store.finances.paymentCategories,
                                          showDatePicker: $showDatePicker)
                    } else {
                        IncomeFormFields(draft: $incomeDraft,
                                         categories: store.finances.incomeCategories,
                                         showDatePicker: $showDatePicker)
                    }

                    FBPrimaryButton(label: "Add", enabled: canSave, action: save)
                }
            }
            .transition(.fbModalPush)

            if showDatePicker {
                FBDatePickerCard(label: "Date", date: currentDateBinding) {
                    showDatePicker = false
                }
                .transition(.fbModalPush)
                .zIndex(1)
            }
        }
        .transition(.opacity)
        .animation(.fbModal, value: kind)
        .animation(.fbModal, value: showDatePicker)
    }

    private var currentDateBinding: Binding<Date> {
        Binding(
            get: { kind == 0 ? paymentDraft.date : incomeDraft.date },
            set: { if kind == 0 { paymentDraft.date = $0 } else { incomeDraft.date = $0 } }
        )
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

/// External label + content — kept for the sign-in screen; modal forms
/// use the floating-label filled fields below instead.
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

/// The filled field per the reference: a soft rounded well whose label
/// sits as the placeholder, then floats into a tiny caption once the
/// field is focused or holds a value. Fixed height — nothing reflows.
struct FBFieldShell<Content: View, Trailing: View>: View {
    let label: String
    let floating: Bool
    @ViewBuilder var content: Content
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 10) {
            ZStack(alignment: .leading) {
                Text(label)
                    .font(.fbBody(16))
                    .foregroundStyle(Color.fbSoftText)
                    .scaleEffect(floating ? 0.74 : 1, anchor: .leading)
                    .offset(y: floating ? -12 : 0)
                content
                    .offset(y: floating ? 9 : 0)
                    .opacity(floating ? 1 : 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .padding(.horizontal, 16)
        .frame(height: 60)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.fbInk.opacity(0.05))
        )
        .animation(.spring(response: 0.28, dampingFraction: 0.85), value: floating)
    }
}

/// The Recurring switch in the same filled well as every other field.
struct FBToggleField: View {
    let label: String
    @Binding var isOn: Bool

    var body: some View {
        FBToggleRow(label: label, isOn: $isOn)
            .padding(.horizontal, 16)
            .frame(height: 60)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.fbInk.opacity(0.05))
            )
    }
}

struct PlainTextField: View {
    /// Doubles as the floating label.
    let placeholder: String
    @Binding var text: String
    @FocusState private var focused: Bool

    var body: some View {
        FBFieldShell(label: placeholder, floating: focused || !text.isEmpty) {
            TextField("", text: $text)
                .textFieldStyle(.plain)
                .font(.fbBody(16, weight: .medium))
                .foregroundStyle(Color.fbInk)
                .focused($focused)
        } trailing: {
            EmptyView()
        }
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
    }
}

// MARK: - Amount fields (expression editing)

/// The shared amount editor. The raw expression shows in the field while
/// typing (12 + 5 × 2); the bound value tracks its live result; = or
/// leaving the field settles the text to the result. Ops are separate
/// pill ornaments riding above the decimal keyboard.
private struct AmountExpressionField: View {
    let label: String
    @Binding var value: Double?

    @State private var text: String
    @FocusState private var focused: Bool

    init(label: String, value: Binding<Double?>) {
        self.label = label
        _value = value
        _text = State(initialValue: value.wrappedValue.map(Money.editString) ?? "")
    }

    private var floating: Bool { focused || !text.isEmpty }

    // True when the expression contains an arithmetic operator.
    private var hasOperator: Bool {
        text.contains(where: { "+−×÷".contains($0) })
    }

    // True when both operands are present (last char is a digit/dot, not an op).
    private var expressionIsComplete: Bool {
        guard let last = text.last else { return false }
        return "0123456789.".contains(last) && hasOperator
    }

    var body: some View {
        FBFieldShell(label: label, floating: floating) {
            ZStack(alignment: .leading) {
                // Input layer — text turns invisible during expression mode so
                // only the cursor shows, anchoring the styled overlay below.
                HStack(spacing: 6) {
                    if !hasOperator {
                        Text(Money.currencySymbol)
                            .font(.fbNumber(16, weight: .semibold))
                            .foregroundStyle(Color.fbSoftText)
                    }
                    TextField("", text: $text)
                        .textFieldStyle(.plain)
                        .font(.fbNumber(16, weight: .semibold))
                        .foregroundStyle(hasOperator ? Color.clear : Color.fbInk)
                        .decimalKeyboard()
                        .focused($focused)
                }
                // Styled expression overlay (only while an operator is present).
                if hasOperator {
                    expressionOverlay
                }
            }
        } trailing: {
            EmptyView()
        }
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
        .toolbar {
            // Keys appear immediately on focus so the bar height is stable from
            // the moment the keyboard rises — no second layout jump on first digit.
            ToolbarItemGroup(placement: .keyboard) {
                if focused {
                    opKey("+")
                        .disabled(text.isEmpty).opacity(text.isEmpty ? 0.35 : 1)
                    Spacer()
                    opKey("−")
                        .disabled(text.isEmpty).opacity(text.isEmpty ? 0.35 : 1)
                    Spacer()
                    opKey("×")
                        .disabled(text.isEmpty).opacity(text.isEmpty ? 0.35 : 1)
                    Spacer()
                    opKey("÷")
                        .disabled(text.isEmpty).opacity(text.isEmpty ? 0.35 : 1)
                    Spacer()
                    opKey("=")
                        .foregroundStyle(Color.fbOnAccent)
                        .backgroundStyle(Color.fbInk)
                        .disabled(text.isEmpty).opacity(text.isEmpty ? 0.35 : 1)
                }
            }
        }
        .onChange(of: text) {
            value = AmountExpressionField.evaluate(text)
        }
        .onChange(of: focused) {
            if !focused { settle() }
        }
    }

    // "10+" → raw text in white
    // "10+10" → "10+10=" in soft grey + "£20" in white
    @ViewBuilder
    private var expressionOverlay: some View {
        if expressionIsComplete, let result = AmountExpressionField.evaluate(text) {
            let expr = Text(text + "=").foregroundStyle(Color.fbSoftText)
            let res  = Text(Money.currencySymbol + Money.editString(result)).foregroundStyle(Color.fbInk)
            Text("\(expr)\(res)")
                .font(.fbNumber(16, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .allowsHitTesting(false)
        } else {
            Text(text)
                .font(.fbNumber(16, weight: .semibold))
                .foregroundStyle(Color.fbInk)
                .allowsHitTesting(false)
        }
    }

    private func opKey(_ op: String) -> some View {
        Button {
            op == "=" ? settle() : insert(op)
        } label: {
            Text(op)
                .font(.fbNumber(18, weight: .semibold))
                .foregroundStyle(Color.fbInk)
        }
        .buttonStyle(.pressable)
    }

    private func insert(_ op: String) {
        var trimmed = text
        while let last = trimmed.last, last == " " || "+−×÷".contains(last) {
            trimmed.removeLast()
        }
        guard !trimmed.isEmpty else { return }
        text = trimmed + "\(op)"
    }

    private func settle() {
        guard let result = AmountExpressionField.evaluate(text) else { return }
        text = Money.editString(result)
        value = result
    }

    /// Left-to-right tokens, × ÷ before + −. Incomplete tails ("12 +")
    /// evaluate to what's complete so the Save button tracks live.
    static func evaluate(_ raw: String) -> Double? {
        let cleaned = raw.replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: " ", with: "")
        guard !cleaned.isEmpty else { return nil }

        var numbers: [Double] = []
        var ops: [Character] = []
        var current = ""
        for ch in cleaned {
            if "0123456789.".contains(ch) {
                current.append(ch)
            } else if "+−×÷".contains(ch) {
                guard let n = Double(current) else { return numbers.first }
                numbers.append(n)
                ops.append(ch)
                current = ""
            } else {
                return nil
            }
        }
        if !current.isEmpty {
            guard let n = Double(current) else { return numbers.first }
            numbers.append(n)
        }
        while ops.count >= numbers.count, !ops.isEmpty { ops.removeLast() }
        guard numbers.count == ops.count + 1 else { return numbers.first }

        var i = 0
        while i < ops.count {
            if ops[i] == "×" || ops[i] == "÷" {
                let b = numbers[i + 1]
                numbers[i] = ops[i] == "×" ? numbers[i] * b
                                           : (b == 0 ? numbers[i] : numbers[i] / b)
                numbers.remove(at: i + 1)
                ops.remove(at: i)
            } else {
                i += 1
            }
        }
        var result = numbers[0]
        for (k, op) in ops.enumerated() {
            result = op == "+" ? result + numbers[k + 1] : result - numbers[k + 1]
        }
        return result
    }
}

/// A numeric field showing the currency symbol, for a non-optional value.
struct CurrencyField: View {
    var label = "Amount"
    @Binding var value: Double

    var body: some View {
        AmountExpressionField(label: label,
                              value: Binding(get: { value },
                                             set: { value = $0 ?? 0 }))
    }
}

/// Like CurrencyField but for an optional value (empty until typed).
struct CurrencyEntryField: View {
    var label = "Amount"
    @Binding var value: Double?
    var body: some View {
        AmountExpressionField(label: label, value: $value)
    }
}

/// A date field in the same filled style — label floats above the
/// "30 July 2026" value. Callers must manage `showDatePicker` state and
/// render `FBDatePickerCard` at the enclosing ZStack level so it pushes
/// the underlying card back along the z-axis.
struct FBDateField: View {
    var label = "Date"
    @Binding var date: Date
    @Binding var showDatePicker: Bool

    var body: some View {
        Button {
            fbDismissKeyboard()
            showDatePicker = true
        } label: {
            FBFieldShell(label: label, floating: true) {
                Text(date.formatted(.dateTime.day().month(.wide).year()))
                    .font(.fbBody(16, weight: .medium))
                    .foregroundStyle(Color.fbInk)
            } trailing: {
                Image(systemName: "calendar")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(showDatePicker ? Color.fbInk : Color.fbSoftText)
            }
        }
        .buttonStyle(.pressable)
    }
}

/// The date picker as a floating modal card — rendered at the parent
/// ZStack level so it can push the underlying form card back along the
/// z-axis with the shared fbModalPush transition. Apply `.transition(.fbModalPush)`
/// and `.zIndex(n)` at the call site.
struct FBDatePickerCard: View {
    let label: String
    @Binding var date: Date
    let onClose: () -> Void

    var body: some View {
        ModalCard {
            VStack(alignment: .leading, spacing: 10) {
                ModalHeader(title: label, onClose: onClose)
                DatePicker("", selection: $date, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .tint(Color.fbPositive)
            }
        }
        .onChange(of: date) {
            onClose()
        }
    }
}

/// The dropdown in the same filled style: tiny label, current value, and
/// a chevron; options come from a Menu.
struct FBMenuField: View {
    let label: String
    @Binding var selection: String
    let options: [String]

    var body: some View {
        Menu {
            ForEach(options, id: \.self) { option in
                Button(option) { selection = option }
            }
        } label: {
            FBFieldShell(label: label, floating: true) {
                Text(selection)
                    .font(.fbBody(16, weight: .medium))
                    .foregroundStyle(Color.fbInk)
            } trailing: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.fbSoftText)
            }
        }
        .buttonStyle(.pressable)
    }
}

extension Money {
    static var currencySymbol: String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = currencyCode
        return f.currencySymbol ?? "£"
    }

    /// Bare editable number — no grouping or symbol, trailing zeros
    /// trimmed ("2140", "12.5").
    static func editString(_ value: Double) -> String {
        if value.rounded() == value, abs(value) < 1e15 {
            return String(Int(value))
        }
        var s = String(format: "%.2f", value)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }
}
