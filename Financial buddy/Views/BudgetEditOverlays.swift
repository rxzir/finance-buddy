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
                ModalCard(depth: showIncomeForm ? 1 : 0) { incomeList }
                    .transition(.fbModalPush)
                    .zIndex(1)
            }

            if showIncomeForm {
                ModalCard { incomeForm }
                    .transition(.fbModalPush)
                    .zIndex(2)
            }
        }
        .transition(.opacity)
        .animation(.fbModal, value: showIncome)
        .animation(.fbModal, value: showIncomeForm)
    }

    private var mainDepth: Int {
        guard showIncome else { return 0 }
        return showIncomeForm ? 2 : 1
    }

    /// Backdrop taps dismiss only the frontmost layer.
    private func backdropTapped() {
        if showIncomeForm { showIncomeForm = false }
        else if showIncome { showIncome = false }
        else { onClose() }
    }

    // MARK: Layer 0 — balance & payday

    private var mainForm: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Edit your numbers")
                .font(.fbHeader(20))
                .tracking(-0.3)
                .foregroundStyle(Color.fbInk)

            LabeledField(label: "Current balance") {
                CurrencyField(value: $balance)
            }

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
                .padding(.horizontal, 14)
                .padding(.vertical, 13)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.fbBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.fbHairline, lineWidth: 1)
                )
            }
            .buttonStyle(.pressable)

            ModalActionButtons(primaryLabel: "Save",
                               onPrimary: save,
                               onSecondary: onClose)
        }
    }

    private func save() {
        store.finances.balance = balance
        onClose()
    }

    // MARK: Layer 1 — income list (same shape as the payments modal)

    private var incomeList: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Income")
                .font(.fbHeader(20))
                .tracking(-0.3)
                .foregroundStyle(Color.fbInk)

            ScrollView {
                VStack(spacing: 2) {
                    if store.finances.incomeSources.isEmpty {
                        ModalEmptyHint(text: "No income yet.")
                    }
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
                                     },
                                     onDelete: { store.removeIncome(source) })
                    }
                }
            }
            .frame(maxHeight: 240)

            VStack(spacing: 10) {
                FBPrimaryButton(label: "Add") {
                    var draft = IncomeDraft()
                    draft.category = store.finances.incomeCategories.first ?? "General"
                    incomeDraft = draft
                    showIncomeForm = true
                }
                FBSecondaryButton(label: "Done") { showIncome = false }
            }
        }
    }

    // MARK: Layer 2 — income add/edit form

    private var incomeForm: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(incomeDraft.id == nil ? "New income" : "Edit income")
                .font(.fbHeader(20))
                .tracking(-0.3)
                .foregroundStyle(Color.fbInk)

            IncomeFormFields(draft: $incomeDraft,
                             categories: store.finances.incomeCategories)

            ModalActionButtons(primaryLabel: "Save",
                               primaryEnabled: incomeDraft.isValid,
                               onPrimary: saveIncomeDraft,
                               onSecondary: { showIncomeForm = false })
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
    @State private var draft = PaymentDraft()

    var body: some View {
        ZStack {
            ModalBackdrop {
                if showForm { showForm = false } else { onClose() }
            }

            ModalCard(depth: showForm ? 1 : 0) { list }

            if showForm {
                ModalCard { form }
                    .transition(.fbModalPush)
                    .zIndex(1)
            }
        }
        .transition(.opacity)
        .animation(.fbModal, value: showForm)
    }

    // MARK: List layer

    private var list: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Upcoming payments")
                .font(.fbHeader(20))
                .tracking(-0.3)
                .foregroundStyle(Color.fbInk)

            ScrollView {
                VStack(spacing: 2) {
                    if store.finances.recurringCommitments.isEmpty
                        && store.finances.oneOffCosts.isEmpty {
                        ModalEmptyHint(text: "No payments yet.")
                    }
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
                                     },
                                     onDelete: { store.removeCommitment(c) })
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
                                     },
                                     onDelete: { store.removeOneOff(o) })
                    }
                }
            }
            .frame(maxHeight: 260)

            VStack(spacing: 10) {
                FBPrimaryButton(label: "Add") {
                    var new = PaymentDraft()
                    new.category = store.finances.paymentCategories.first ?? "General"
                    draft = new
                    showForm = true
                }
                FBSecondaryButton(label: "Done", action: onClose)
            }
        }
    }

    // MARK: Form layer (stacked on top)

    private var form: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(draft.id == nil ? "New payment" : "Edit payment")
                .font(.fbHeader(20))
                .tracking(-0.3)
                .foregroundStyle(Color.fbInk)

            PaymentFormFields(draft: $draft,
                              categories: store.finances.paymentCategories)

            ModalActionButtons(primaryLabel: "Save",
                               primaryEnabled: draft.isValid,
                               onPrimary: saveDraft,
                               onSecondary: { showForm = false })
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
