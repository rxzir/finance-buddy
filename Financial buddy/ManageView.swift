//
//  ManageView.swift
//  Finance buddy
//
//  Screen 2. Stacked forms (single column — this is a phone). Edit balance,
//  income and payday, and add / remove recurring commitments and one-off
//  costs. Add-flows use an inline custom overlay, never .sheet().
//

import SwiftUI

struct ManageView: View {
    @Bindable var store: HeadroomStore

    /// Which inline editor overlay, if any, is showing.
    enum Editor: Identifiable {
        case commitment
        case oneOff
        var id: Int { hashValue }
    }
    @State private var activeEditor: Editor?

    var body: some View {
        ZStack {
            Color.hrBackground.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    header
                    balanceCard
                    incomeCard
                    commitmentsCard
                    oneOffCard
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }

            // Custom modal overlays (no .sheet — keeps our styling).
            if let editor = activeEditor {
                overlay(for: editor)
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack {
            Text("Manage")
                .font(.hrHeader(28))
                .tracking(-0.5)
                .foregroundStyle(Color.hrInk)
            Spacer()
        }
        .padding(.top, 4)
    }

    // MARK: Balance

    private var balanceCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                fieldTitle("Current balance")
                CurrencyField(value: $store.finances.balance)
            }
        }
    }

    // MARK: Income + payday

    private var incomeCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 16) {
                fieldTitle("Income")
                VStack(alignment: .leading, spacing: 8) {
                    Text("Amount per pay")
                        .font(.hrBody(14))
                        .foregroundStyle(Color.hrSoftText)
                    CurrencyField(value: $store.finances.income.amount)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Next pay date")
                        .font(.hrBody(14))
                        .foregroundStyle(Color.hrSoftText)
                    DatePicker("", selection: $store.finances.income.nextPayDate,
                               displayedComponents: .date)
                        .labelsHidden()
                        .datePickerStyle(.compact)
                        .tint(Color.hrPositive)
                }
            }
        }
    }

    // MARK: Recurring commitments

    private var commitmentsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    fieldTitle("Recurring commitments")
                    Spacer()
                    addButton { activeEditor = .commitment }
                }

                if store.finances.recurringCommitments.isEmpty {
                    emptyHint("No commitments yet.")
                } else {
                    ForEach(store.finances.recurringCommitments) { c in
                        listRow(name: c.name,
                                detail: "Day \(c.dueDay) · \(c.category)",
                                amount: c.amount) {
                            store.removeCommitment(c)
                        }
                    }
                }
            }
        }
    }

    // MARK: One-off costs

    private var oneOffCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    fieldTitle("One-off costs")
                    Spacer()
                    addButton { activeEditor = .oneOff }
                }

                if store.finances.oneOffCosts.isEmpty {
                    emptyHint("No one-off costs yet.")
                } else {
                    ForEach(store.finances.oneOffCosts) { o in
                        listRow(name: o.name,
                                detail: o.date.formatted(date: .abbreviated, time: .omitted),
                                amount: o.amount) {
                            store.removeOneOff(o)
                        }
                    }
                }
            }
        }
    }

    // MARK: Overlay routing

    @ViewBuilder
    private func overlay(for editor: Editor) -> some View {
        switch editor {
        case .commitment:
            AddCommitmentOverlay(
                onCancel: { activeEditor = nil },
                onSave: { store.addCommitment($0); activeEditor = nil }
            )
        case .oneOff:
            AddOneOffOverlay(
                onCancel: { activeEditor = nil },
                onSave: { store.addOneOff($0); activeEditor = nil }
            )
        }
    }

    // MARK: Building blocks

    private func fieldTitle(_ text: String) -> some View {
        Text(text)
            .font(.hrHeader(17))
            .tracking(-0.3)
            .foregroundStyle(Color.hrInk)
    }

    private func emptyHint(_ text: String) -> some View {
        Text(text)
            .font(.hrBody(14))
            .foregroundStyle(Color.hrSoftText)
    }

    private func addButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.hrCard)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.hrPositive))
        }
        .buttonStyle(.plain)
    }

    private func listRow(name: String, detail: String, amount: Double,
                         onDelete: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.hrBody(16, weight: .medium))
                    .foregroundStyle(Color.hrInk)
                Text(detail)
                    .font(.hrBody(13))
                    .foregroundStyle(Color.hrSoftText)
            }
            Spacer()
            Text(Money.string(amount))
                .font(.hrNumber(16, weight: .medium))
                .foregroundStyle(Color.hrInk)
            Button(action: onDelete) {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.hrWarning.opacity(0.85))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Currency text field

/// A numeric field that shows the currency symbol and edits a Double.
struct CurrencyField: View {
    @Binding var value: Double

    var body: some View {
        HStack(spacing: 6) {
            Text(Money.currencySymbol)
                .font(.hrNumber(22, weight: .semibold))
                .foregroundStyle(Color.hrSoftText)
            TextField("0", value: $value, format: .number.precision(.fractionLength(0...2)))
                .textFieldStyle(.plain)
                .font(.hrNumber(22, weight: .semibold))
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

extension Money {
    static var currencySymbol: String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = currencyCode
        return f.currencySymbol ?? "£"
    }
}

#Preview {
    ManageView(store: HeadroomStore(finances: .sample))
}
