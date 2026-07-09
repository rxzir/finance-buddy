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
    @Bindable var store: FinanceBuddyStore

    /// Which inline editor overlay, if any, is showing.
    enum Editor: Identifiable {
        case commitment
        case oneOff
        var id: Int { hashValue }
    }
    @State private var activeEditor: Editor?

    var body: some View {
        ZStack {
            Color.fbBackground.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
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
                        .font(.fbBody(14))
                        .foregroundStyle(Color.fbSoftText)
                    CurrencyField(value: $store.finances.income.amount)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Next pay date")
                        .font(.fbBody(14))
                        .foregroundStyle(Color.fbSoftText)
                    DatePicker("", selection: $store.finances.income.nextPayDate,
                               displayedComponents: .date)
                        .labelsHidden()
                        .datePickerStyle(.compact)
                        .tint(Color.fbPositive)
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
            .font(.fbHeader(17))
            .tracking(-0.3)
            .foregroundStyle(Color.fbInk)
    }

    private func emptyHint(_ text: String) -> some View {
        Text(text)
            .font(.fbBody(14))
            .foregroundStyle(Color.fbSoftText)
    }

    private func addButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.fbOnAccent)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.fbPositive))
        }
        .buttonStyle(.plain)
    }

    private func listRow(name: String, detail: String, amount: Double,
                         onDelete: @escaping () -> Void) -> some View {
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
                .font(.fbNumber(16, weight: .medium))
                .foregroundStyle(Color.fbInk)
            Button(action: onDelete) {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.fbWarning.opacity(0.85))
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

extension Money {
    static var currencySymbol: String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = currencyCode
        return f.currencySymbol ?? "£"
    }
}

#Preview {
    ManageView(store: FinanceBuddyStore(finances: .sample))
}
