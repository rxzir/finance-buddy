//
//  BudgetEditOverlays.swift
//  Finance buddy
//
//  The Budget tab's edit modals, built as custom ZStack overlays (never
//  .sheet()). Cards stack on the z-axis:
//  - EditTodayOverlay: balance & payday, with the income manager (list →
//    add/edit form) stacking on top.
//  - ManageCommitmentsOverlay: recurring + one-off payments behind a
//    segmented toggle; the add/edit form stacks on top of the list.
//
//  Drafts are non-optional state behind a `showForm` flag — an optional
//  draft unwrapped with Binding($draft) traps when the form is dismissed
//  mid-transition.
//

import SwiftUI

// MARK: - Edit balance / payday (+ stacked income manager)

struct EditTodayOverlay: View {
    @Bindable var store: FinanceBuddyStore
    let onClose: () -> Void

    @State private var balance: Double

    // The stacked income layers.
    @State private var showIncome = false
    @State private var showIncomeForm = false
    @State private var incomeDraft = IncomeDraft()
    @State private var showDatePicker = false

    init(store: FinanceBuddyStore, onClose: @escaping () -> Void) {
        self.store = store
        self.onClose = onClose
        _balance = State(initialValue: store.finances.balance)
    }

    var body: some View {
        ZStack {
            ModalBackdrop(onTap: backdropTapped)

            ModalCard(depth: mainDepth) { mainForm }

            if showIncome {
                ModalCard(depth: incomeListDepth) { incomeList }
                    .transition(.fbModalPush)
                    .zIndex(1)
            }

            if showIncomeForm {
                ModalCard(depth: showDatePicker ? 1 : 0) { incomeForm }
                    .transition(.fbModalPush)
                    .zIndex(2)
            }

            if showDatePicker {
                FBDatePickerCard(label: "Date", date: $incomeDraft.date) {
                    showDatePicker = false
                }
                .transition(.fbModalPush)
                .zIndex(3)
            }
        }
        .transition(.opacity)
        .animation(.fbModal, value: showIncome)
        .animation(.fbModal, value: showIncomeForm)
        .animation(.fbModal, value: showDatePicker)
    }

    private var mainDepth: Int {
        var d = 0
        if showIncome { d += 1 }
        if showIncomeForm { d += 1 }
        if showDatePicker { d += 1 }
        return d
    }

    private var incomeListDepth: Int {
        var d = 0
        if showIncomeForm { d += 1 }
        if showDatePicker { d += 1 }
        return d
    }

    /// Backdrop taps dismiss only the frontmost layer.
    private func backdropTapped() {
        if showDatePicker { showDatePicker = false }
        else if showIncomeForm { showIncomeForm = false }
        else if showIncome { showIncome = false }
        else { onClose() }
    }

    // MARK: Layer 0 — balance & payday

    private var mainForm: some View {
        VStack(alignment: .leading, spacing: 24) {
            ModalHeader(title: "Edit your numbers", onClose: onClose)

            CurrencyField(label: "Current balance", value: $balance)

            // Payday is derived from recurring income dates, so income is
            // the only other thing to manage — one card up the stack.
            Button {
                showIncome = true
            } label: {
                HStack(spacing: 10) {
                    Text("Income sources")
                        .font(.fbBody(15, weight: .medium))
                        .foregroundStyle(Color.fbInk)
                    Spacer()
                    Text(Money.string(store.finances.totalIncome))
                        .font(.fbNumber(14, weight: .medium))
                        .foregroundStyle(Color.fbSoftText)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.fbSoftText)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
            .padding(.bottom, 10)

            FBPrimaryButton(label: "Save", action: save)
        }
    }

    private func save() {
        store.finances.balance = balance
        onClose()
    }

    // MARK: Layer 1 — income list (same shape as the payments modal)

    private var incomeList: some View {
        VStack(alignment: .leading, spacing: 16) {
            ModalHeader(title: "Income") { showIncome = false }

            if store.finances.incomeSources.isEmpty {
                ModalEmptyHint(text: "No income yet.")
            } else {
                List {
                    ForEach(store.finances.incomeSources) { source in
                        ModalItemRow(name: source.name,
                                     detail: source.isRecurring
                                         ? "Monthly · \(source.category)"
                                         : "\(source.date.formatted(.dateTime.day().month(.abbreviated))) · \(source.category)",
                                     amount: source.amount,
                                     onEdit: {
                                         incomeDraft = IncomeDraft(id: source.id,
                                                                   name: source.name,
                                                                   amount: source.amount,
                                                                   isRecurring: source.isRecurring,
                                                                   category: source.category,
                                                                   date: source.date)
                                         showIncomeForm = true
                                     })
                            .modalListRow { store.removeIncome(source) }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .frame(maxHeight: 240)
                .scrollEdgeEffectStyle(.soft, for: .vertical)
            }

            FBPrimaryButton(label: "Add") {
                var draft = IncomeDraft()
                draft.category = store.finances.incomeCategories.first ?? "General"
                incomeDraft = draft
                showIncomeForm = true
            }
        }
    }

    // MARK: Layer 2 — income add/edit form

    private var incomeForm: some View {
        VStack(alignment: .leading, spacing: 18) {
            ModalHeader(title: incomeDraft.id == nil ? "New income" : "Edit income") {
                showIncomeForm = false
            }

            IncomeFormFields(draft: $incomeDraft,
                             categories: store.finances.incomeCategories,
                             showDatePicker: $showDatePicker)

            FBPrimaryButton(label: "Save", enabled: incomeDraft.isValid,
                            action: saveIncomeDraft)
        }
    }

    private func saveIncomeDraft() {
        guard let amount = incomeDraft.amount else { return }
        let source = IncomeSource(id: incomeDraft.id ?? UUID(),
                                  name: incomeDraft.name.trimmingCharacters(in: .whitespaces),
                                  amount: amount,
                                  isRecurring: incomeDraft.isRecurring,
                                  category: incomeDraft.category,
                                  date: incomeDraft.date)
        incomeDraft.id == nil ? store.addIncome(source) : store.updateIncome(source)
        showIncomeForm = false
    }
}

// MARK: - Manage commitments & one-off costs

struct ManageCommitmentsOverlay: View {
    @Bindable var store: FinanceBuddyStore
    let onClose: () -> Void

    @State private var showForm = false
    @State private var showDatePicker = false
    @State private var draft = PaymentDraft()

    var body: some View {
        ZStack {
            ModalBackdrop {
                if showDatePicker { showDatePicker = false }
                else if showForm { showForm = false }
                else { onClose() }
            }

            ModalCard(depth: showForm ? (showDatePicker ? 2 : 1) : 0) { list }

            if showForm {
                ModalCard(depth: showDatePicker ? 1 : 0) { form }
                    .transition(.fbModalPush)
                    .zIndex(1)
            }

            if showDatePicker {
                FBDatePickerCard(label: "Date", date: $draft.date) { showDatePicker = false }
                    .transition(.fbModalPush)
                    .zIndex(2)
            }
        }
        .transition(.opacity)
        .animation(.fbModal, value: showForm)
        .animation(.fbModal, value: showDatePicker)
    }

    // MARK: List layer

    private var list: some View {
        VStack(alignment: .leading, spacing: 16) {
            ModalHeader(title: "Upcoming payments", onClose: onClose)

            if store.finances.recurringCommitments.isEmpty
                && store.finances.oneOffCosts.isEmpty {
                ModalEmptyHint(text: "No payments yet.")
            } else {
                List {
                    ForEach(store.finances.recurringCommitments) { c in
                        ModalItemRow(name: c.name,
                                     detail: "Monthly · \(c.category)",
                                     amount: c.amount,
                                     onEdit: {
                                         draft = PaymentDraft(
                                             id: c.id, name: c.name,
                                             amount: c.amount,
                                             isRecurring: true,
                                             category: c.category,
                                             date: Finances.nextOccurrence(ofDueDay: c.dueDay,
                                                                           onOrAfter: Date(),
                                                                           calendar: .current))
                                         showForm = true
                                     })
                            .modalListRow { store.removeCommitment(c) }
                    }
                    ForEach(store.finances.oneOffCosts) { o in
                        ModalItemRow(name: o.name,
                                     detail: o.date.formatted(date: .abbreviated, time: .omitted),
                                     amount: o.amount,
                                     onEdit: {
                                         draft = PaymentDraft(id: o.id, name: o.name,
                                                              amount: o.amount,
                                                              isRecurring: false,
                                                              date: o.date)
                                         showForm = true
                                     })
                            .modalListRow { store.removeOneOff(o) }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .frame(maxHeight: 260)
                .scrollEdgeEffectStyle(.soft, for: .vertical)
            }

            FBPrimaryButton(label: "Add") {
                var new = PaymentDraft()
                new.category = store.finances.paymentCategories.first ?? "General"
                draft = new
                showForm = true
            }
        }
    }

    // MARK: Form layer (stacked on top)

    private var form: some View {
        VStack(alignment: .leading, spacing: 18) {
            ModalHeader(title: draft.id == nil ? "New payment" : "Edit payment") {
                showForm = false
            }

            PaymentFormFields(draft: $draft,
                              categories: store.finances.paymentCategories,
                              showDatePicker: $showDatePicker)

            FBPrimaryButton(label: "Save", enabled: draft.isValid,
                            action: saveDraft)
        }
    }

    private func saveDraft() {
        guard let amount = draft.amount else { return }
        let name = draft.name.trimmingCharacters(in: .whitespaces)

        if draft.isRecurring {
            let item = RecurringCommitment(id: draft.id ?? UUID(), name: name, amount: amount,
                                           dueDay: draft.dueDay, category: draft.category)
            draft.id == nil ? store.addCommitment(item) : store.updateCommitment(item)
        } else {
            let item = OneOffCost(id: draft.id ?? UUID(), name: name, amount: amount, date: draft.date)
            draft.id == nil ? store.addOneOff(item) : store.updateOneOff(item)
        }
        showForm = false
    }
}

#Preview("Manage commitments") {
    ZStack {
        FBBackground()
        ManageCommitmentsOverlay(store: FinanceBuddyStore(finances: .sample), onClose: {})
    }
    .preferredColorScheme(.dark)
}

#Preview("Edit today") {
    ZStack {
        FBBackground()
        EditTodayOverlay(store: FinanceBuddyStore(finances: .sample), onClose: {})
    }
    .preferredColorScheme(.dark)
}
