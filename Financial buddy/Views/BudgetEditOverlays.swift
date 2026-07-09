//
//  BudgetEditOverlays.swift
//  Finance buddy
//
//  The two edit "sheets" for the Budget tab, built as custom ZStack
//  overlays (never .sheet()):
//  - EditTodayOverlay: balance, income amount, next payday
//  - ManageCommitmentsOverlay: add / edit / delete recurring commitments
//    and one-off costs behind a segmented toggle
//

import SwiftUI

// MARK: - Edit balance / income / payday

struct EditTodayOverlay: View {
    @Bindable var store: FinanceBuddyStore
    let onClose: () -> Void

    @State private var balance: Double
    @State private var incomeAmount: Double
    @State private var payday: Date

    init(store: FinanceBuddyStore, onClose: @escaping () -> Void) {
        self.store = store
        self.onClose = onClose
        _balance = State(initialValue: store.finances.balance)
        _incomeAmount = State(initialValue: store.finances.income.amount)
        _payday = State(initialValue: store.finances.income.nextPayDate)
    }

    var body: some View {
        ModalOverlay(title: "Edit your numbers",
                     canSave: true,
                     saveLabel: "Save",
                     onCancel: onClose,
                     onSave: save) {
            VStack(alignment: .leading, spacing: 16) {
                LabeledField(label: "Current balance") {
                    CurrencyField(value: $balance)
                }
                LabeledField(label: "Income per pay") {
                    CurrencyField(value: $incomeAmount)
                }
                LabeledField(label: "Next payday") {
                    DatePicker("", selection: $payday, displayedComponents: .date)
                        .labelsHidden()
                        .datePickerStyle(.compact)
                        .tint(Color.fbPositive)
                }
            }
        }
    }

    private func save() {
        store.finances.balance = balance
        store.finances.income.amount = incomeAmount
        store.finances.income.nextPayDate = payday
        onClose()
    }
}

// MARK: - Manage commitments & one-off costs

struct ManageCommitmentsOverlay: View {
    @Bindable var store: FinanceBuddyStore
    let onClose: () -> Void

    enum Segment: String, CaseIterable {
        case recurring = "Recurring"
        case oneOff = "One-off"
    }

    /// Form state for adding or editing a single item. `id == nil` means
    /// a brand-new item.
    private struct Draft {
        var id: UUID?
        var name = ""
        var amount: Double?
        var dueDay = 1
        var category = "General"
        var date = Date()
        var isRecurring: Bool
    }

    @State private var segment: Segment = .recurring
    @State private var draft: Draft?

    private let categories = ["General", "Housing", "Utilities", "Subscriptions",
                              "Health", "Transport", "Insurance", "Debt"]

    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture { if draft == nil { onClose() } }

            VStack(spacing: 0) {
                Spacer(minLength: 60)
                Card(cornerRadius: 22) {
                    VStack(alignment: .leading, spacing: 16) {
                        header

                        if draft == nil {
                            segmentToggle
                            itemList
                            addButton // same position & style for both segments
                        } else {
                            form
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
        .transition(.opacity)
    }

    // MARK: Pieces

    private var header: some View {
        HStack {
            Text(draft == nil ? "Edit commitments"
                              : (draft?.id == nil ? "New item" : "Edit item"))
                .font(.fbHeader(20))
                .tracking(-0.3)
                .foregroundStyle(Color.fbInk)
            Spacer()
            if draft == nil {
                Button(action: onClose) {
                    Text("Done")
                        .font(.fbBody(15, weight: .semibold))
                        .foregroundStyle(Color.fbPositive)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var segmentToggle: some View {
        HStack(spacing: 4) {
            ForEach(Segment.allCases, id: \.self) { s in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { segment = s }
                } label: {
                    Text(s.rawValue)
                        .font(.fbBody(14, weight: .semibold))
                        .foregroundStyle(segment == s ? Color.fbInk : Color.fbSoftText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(segment == s ? Color.fbBackground : .clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.fbBackground.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.fbHairline, lineWidth: 1)
        )
    }

    private var itemList: some View {
        ScrollView {
            VStack(spacing: 2) {
                switch segment {
                case .recurring:
                    if store.finances.recurringCommitments.isEmpty {
                        emptyHint("No recurring commitments yet.")
                    }
                    ForEach(store.finances.recurringCommitments) { c in
                        itemRow(name: c.name,
                                detail: "Day \(c.dueDay) · \(c.category)",
                                amount: c.amount,
                                onEdit: {
                                    draft = Draft(id: c.id, name: c.name, amount: c.amount,
                                                  dueDay: c.dueDay, category: c.category,
                                                  isRecurring: true)
                                },
                                onDelete: { store.removeCommitment(c) })
                    }
                case .oneOff:
                    if store.finances.oneOffCosts.isEmpty {
                        emptyHint("No one-off costs yet.")
                    }
                    ForEach(store.finances.oneOffCosts) { o in
                        itemRow(name: o.name,
                                detail: o.date.formatted(date: .abbreviated, time: .omitted),
                                amount: o.amount,
                                onEdit: {
                                    draft = Draft(id: o.id, name: o.name, amount: o.amount,
                                                  date: o.date, isRecurring: false)
                                },
                                onDelete: { store.removeOneOff(o) })
                    }
                }
            }
        }
        .frame(maxHeight: 260)
    }

    private func emptyHint(_ text: String) -> some View {
        Text(text)
            .font(.fbBody(14))
            .foregroundStyle(Color.fbSoftText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 10)
    }

    private func itemRow(name: String, detail: String, amount: Double,
                         onEdit: @escaping () -> Void,
                         onDelete: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Button(action: onEdit) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name)
                            .font(.fbBody(16, weight: .medium))
                            .foregroundStyle(Color.fbInk)
                        Text(detail)
                            .font(.fbBody(13))
                            .foregroundStyle(Color.fbSoftText)
                    }
                    Spacer()
                    Text(Money.string(amount))
                        .font(.fbNumber(15, weight: .medium))
                        .foregroundStyle(Color.fbInk)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: onDelete) {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.fbWarning.opacity(0.85))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 7)
    }

    /// Full-width add button — identical placement and style whichever
    /// segment is showing.
    private var addButton: some View {
        Button {
            draft = Draft(isRecurring: segment == .recurring)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .bold))
                Text(segment == .recurring ? "Add recurring commitment" : "Add one-off cost")
                    .font(.fbBody(15, weight: .semibold))
            }
            .foregroundStyle(Color.fbOnAccent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.fbPositive)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Add / edit form

    @ViewBuilder
    private var form: some View {
        if let current = draft {
            VStack(alignment: .leading, spacing: 16) {
                LabeledField(label: "Name") {
                    PlainTextField(placeholder: current.isRecurring ? "e.g. Rent" : "e.g. Flights",
                                   text: Binding(get: { draft?.name ?? "" },
                                                 set: { draft?.name = $0 }))
                }
                LabeledField(label: "Amount") {
                    CurrencyEntryField(value: Binding(get: { draft?.amount },
                                                      set: { draft?.amount = $0 }))
                }

                if current.isRecurring {
                    LabeledField(label: "Due day of month") {
                        Picker("", selection: Binding(get: { draft?.dueDay ?? 1 },
                                                      set: { draft?.dueDay = $0 })) {
                            ForEach(1...31, id: \.self) { Text("Day \($0)").tag($0) }
                        }
                        .pickerStyle(.menu)
                        .tint(Color.fbInk)
                    }
                    LabeledField(label: "Category") {
                        Picker("", selection: Binding(get: { draft?.category ?? "General" },
                                                      set: { draft?.category = $0 })) {
                            ForEach(categories, id: \.self) { Text($0).tag($0) }
                        }
                        .pickerStyle(.menu)
                        .tint(Color.fbInk)
                    }
                } else {
                    LabeledField(label: "Date") {
                        DatePicker("", selection: Binding(get: { draft?.date ?? Date() },
                                                          set: { draft?.date = $0 }),
                                   displayedComponents: .date)
                            .labelsHidden()
                            .datePickerStyle(.compact)
                            .tint(Color.fbPositive)
                    }
                }

                HStack(spacing: 12) {
                    Button {
                        draft = nil
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

                    Button(action: saveDraft) {
                        Text("Save")
                            .font(.fbBody(16, weight: .semibold))
                            .foregroundStyle(Color.fbOnAccent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(canSaveDraft ? Color.fbPositive : Color.fbHairline)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSaveDraft)
                }
            }
        }
    }

    private var canSaveDraft: Bool {
        guard let draft else { return false }
        return !draft.name.trimmingCharacters(in: .whitespaces).isEmpty && (draft.amount ?? 0) > 0
    }

    private func saveDraft() {
        guard let d = draft, let amount = d.amount else { return }
        let name = d.name.trimmingCharacters(in: .whitespaces)

        if d.isRecurring {
            let item = RecurringCommitment(id: d.id ?? UUID(), name: name, amount: amount,
                                           dueDay: d.dueDay, category: d.category)
            d.id == nil ? store.addCommitment(item) : store.updateCommitment(item)
        } else {
            let item = OneOffCost(id: d.id ?? UUID(), name: name, amount: amount, date: d.date)
            d.id == nil ? store.addOneOff(item) : store.updateOneOff(item)
        }
        draft = nil
    }
}

#Preview("Manage commitments") {
    ZStack {
        Color.fbBackground.ignoresSafeArea()
        ManageCommitmentsOverlay(store: FinanceBuddyStore(finances: .sample), onClose: {})
    }
    .preferredColorScheme(.dark)
}
