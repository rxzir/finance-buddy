//
//  BudgetView.swift
//  Finance buddy
//
//  One scrollable screen:
//  1. TODAY — safe-to-spend hero floating on the background (no card),
//     then a card with the month bar / flow view. Pencil edits
//     balance/payday/income.
//  2. UPCOMING PAYMENTS — recurring + one-offs merged into one list
//     sorted by next due date; everything after payday sits under a
//     "Next month" divider. Pencil manages the items.
//

import SwiftUI

struct BudgetView: View {
    @Bindable var store: FinanceBuddyStore
    /// Asks the root to present a modal (rendered above the tab bar).
    var present: (AppModal) -> Void = { _ in }

    /// How the Today card visualises the balance being spent.
    enum ChartStyle: String, CaseIterable {
        case bar, sankey
        var icon: String {
            switch self {
            case .bar:    return "chart.bar.xaxis"
            case .sankey: return "arrow.triangle.branch"
            }
        }
    }
    @State private var chartStyle: ChartStyle = .bar
    @State private var barSelection: BarSegmentInfo?

    private var finances: Finances { store.finances }

    var body: some View {
        ZStack {
            FBBackground()

            ScrollView {
                VStack(spacing: 16) {
                    header
                    hero
                    chartCard
                    commitmentsCard
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
            .scrollEdgeEffectStyle(.soft, for: .vertical)
        }
    }

    private var header: some View {
        HStack {
            Text("Budget")
                .font(.fbHeader(28))
                .tracking(-0.5)
                .foregroundStyle(Color.fbInk)
            Spacer()
        }
        .padding(.top, 4)
    }

    // MARK: 1. Today

    /// The hero floats directly on the background — no card chrome.
    private var hero: some View {
        let safe = finances.safeToSpendToday()
        let days = finances.daysUntilPayday()
        let isOverspent = safe < 0

        return VStack(spacing: 4) {
            Text(isOverspent ? "OVERSPENT" : "SAFE TO SPEND")
                .font(.fbBody(12, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(Color.fbSoftText)
            // The hero pairs safe-to-spend with the balance it comes from.
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(Money.string(safe))
                    .font(.fbNumber(44, weight: .bold))
                    .foregroundStyle(isOverspent ? Color.fbWarning : Color.fbInk)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .contentTransition(.numericText(value: safe))
                    .animation(.spring(response: 0.5, dampingFraction: 0.8), value: safe)
                Text("of \(Money.string(finances.balance))")
                    .font(.fbNumber(15, weight: .medium))
                    .foregroundStyle(Color.fbSoftText)
                    .contentTransition(.numericText(value: finances.balance))
                    .animation(.spring(response: 0.5, dampingFraction: 0.8), value: finances.balance)
            }
            Text(days == 0 ? "Payday is today" : "\(days) day\(days == 1 ? "" : "s") until payday")
                .font(.fbBody(14, weight: .medium))
                .foregroundStyle(Color.fbSoftText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private var chartCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    chartToggle
                    Spacer()
                    pencilButton { present(.editToday) }
                }

                // Details of a tapped bar segment; nothing otherwise (the
                // balance lives in the hero, the chart shows the income).
                contextRow

                switch chartStyle {
                case .bar:
                    BalanceBar(completed: finances.paidThisMonth(),
                               pending: finances.upcomingObligations(),
                               safeToSpend: finances.safeToSpendToday(),
                               selection: $barSelection)
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
                case .sankey:
                    // Income (recurring/one-time) into the three groups —
                    // a monthly view, unlike the balance-based bar.
                    SankeyView(sources: finances.incomeSources,
                               recurringTotal: finances.recurringCommitments.reduce(0) { $0 + $1.amount },
                               oneOffTotal: finances.upcomingSchedule()
                        .filter { if case .oneOff = $0.kind { return true }; return false }
                        .reduce(0) { $0 + $1.amount })
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
                }
            }
        }
    }

    @ViewBuilder
    private var contextRow: some View {
        if chartStyle == .bar, let sel = barSelection {
            HStack(spacing: 8) {
                
                Text(sel.name + " · \(sel.percent)%")
                    .font(.fbBody(14, weight: .medium))
                    .foregroundStyle(Color.fbInk)
                    .lineLimit(1)
                Spacer()
                Text((sel.isCompleted ? "paid · " : "") + "\(Money.string(sel.amount))")
                    .font(.fbNumber(15, weight: .semibold))
                    .foregroundStyle(Color.fbInk)
            }
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    private func selectionSwatch(_ sel: BarSegmentInfo) -> some View {
        Group {
            if sel.isSafe {
                StripedFill(color: Color.fbPositive, lineWidth: 1.5, spacing: 4)
                    .background(Color.fbPositive.opacity(0.12))
            } else if sel.isCompleted {
                Color.fbCommitment.opacity(0.30)
            } else {
                Color.fbInk
            }
        }
        .frame(width: 12, height: 12)
        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
    }

    /// Two tiny icons flipping the Today visual between the eaten bar and
    /// the flow (sankey) view.
    private var chartToggle: some View {
        HStack(spacing: 2) {
            ForEach(ChartStyle.allCases, id: \.self) { style in
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        chartStyle = style
                        barSelection = nil
                    }
                } label: {
                    Image(systemName: style.icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(chartStyle == style ? Color.fbInk : Color.fbSoftText)
                        .frame(width: 30, height: 26)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(chartStyle == style ? Color.fbInk.opacity(0.10) : .clear)
                        )
                }
                .buttonStyle(.pressable)
                .accessibilityLabel(style == .bar ? "Bar view" : "Flow view")
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.fbInk.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.fbHairline, lineWidth: 1)
        )
    }

    // MARK: 2. Commitments (merged list, split at payday)

    private var commitmentsCard: some View {
        let schedule = finances.upcomingSchedule()
        let payday = finances.nextPayday()
        let before = schedule.filter { $0.date <= payday }
        let after = schedule.filter { $0.date > payday }

        return Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    cardTitle("Upcoming payments")
                    Spacer()
                    pencilButton { present(.managePayments) }
                }

                if schedule.isEmpty {
                    Text("Nothing coming up. Add payments with the pencil.")
                        .font(.fbBody(14))
                        .foregroundStyle(Color.fbSoftText)
                } else {
                    ForEach(before) { item in
                        scheduleRow(item, emphasised: true)
                    }

                    if !after.isEmpty {
                        if !before.isEmpty {
                            Divider().overlay(Color.fbHairline).padding(.vertical, 2)
                        }
                        sectionLabel("Next month")
                        ForEach(after) { item in
                            scheduleRow(item, emphasised: false)
                        }
                    }
                }
            }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.fbBody(11, weight: .semibold))
            .tracking(1.2)
            .foregroundStyle(Color.fbSoftText)
            .padding(.top, 2)
    }

    private func scheduleRow(_ item: Obligation, emphasised: Bool) -> some View {
        let isRecurring: Bool
        if case .recurring = item.kind { isRecurring = true } else { isRecurring = false }

        return HStack(spacing: 12) {
            // A contained icon keeps every row the same height and lets
            // the name/date block align cleanly beside it.
            Image(systemName: isRecurring ? "repeat" : "calendar")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(emphasised ? Color.fbInk : Color.fbSoftText)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.fbInk.opacity(0.05)))
                .overlay(Circle().strokeBorder(Color.fbHairline, lineWidth: 1))

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.fbBody(15, weight: emphasised ? .semibold : .regular))
                    .foregroundStyle(emphasised ? Color.fbInk : Color.fbSoftText)
                Text(item.date.formatted(.dateTime.day().month(.abbreviated)))
                    .font(.fbBody(12))
                    .foregroundStyle(Color.fbSoftText)
            }

            Spacer()

            Text(Money.string(item.amount))
                .font(.fbNumber(15, weight: emphasised ? .semibold : .regular))
                .foregroundStyle(emphasised ? Color.fbInk : Color.fbSoftText)
                .frame(minWidth: 64, alignment: .trailing)
        }
        .padding(.vertical, 4)
    }

    // MARK: Shared bits

    private func cardTitle(_ text: String) -> some View {
        Text(text)
            .font(.fbHeader(17))
            .tracking(-0.3)
            .foregroundStyle(Color.fbInk)
    }

    private func pencilButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "pencil")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.fbSoftText)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.fbInk.opacity(0.05)))
                .overlay(Circle().strokeBorder(Color.fbHairline, lineWidth: 1))
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("Edit")
    }
}

#Preview {
    let store = FinanceBuddyStore(finances: .sample)
    return PreviewModalHost(store: store) { present in
        BudgetView(store: store, present: present)
    }
}
