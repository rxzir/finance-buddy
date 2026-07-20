//
//  BudgetView.swift
//  Finance buddy
//
//  One scrollable screen:
//  1. TODAY — everything floats card-less on the background: the chart
//     toggle + edit pencil, the safe-to-spend hero, then the month bar /
//     flow view.
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
        // Transparent — the shared background lives at the root. The title
        // bar is NOT attached here: iOS only renders scroll edge effects
        // for the outermost scroll view, so inside the horizontal pager a
        // page-owned safeAreaBar never gets the blur pocket. The pager in
        // ContentView owns the title bar (and the tab bar) instead.
        ScrollView {
            VStack(spacing: 16) {
                hero
                commitmentsCard
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
        .scrollEdgeEffectStyle(.soft, for: .vertical)
    }

    // MARK: 1. Today

    /// Everything card-less on the background: controls row, the
    /// safe-to-spend hero, then the chosen chart.
    private var hero: some View {
        let safe = finances.safeToSpendToday()
        let isOverspent = safe < 0

        return VStack(spacing: 12) {
            HStack(alignment: .top) {
                chartToggle
                Spacer()
                pencilButton { present(.editToday) }
            }

            VStack(spacing: 4) {
                Text(isOverspent ? "OVERSPENT" : "SAFE TO SPEND")
                    .font(.fbBody(12, weight: .semibold))
                    .tracking(1.4)
                    .foregroundStyle(Color.fbSoftText)
                Text(Money.string(safe))
                    .font(.fbNumber(44, weight: .bold))
                    .foregroundStyle(isOverspent ? Color.fbWarning : Color.fbInk)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .contentTransition(.numericText(value: safe))
                    .animation(.spring(response: 0.5, dampingFraction: 0.8), value: safe)
                Text("of \(Money.string(finances.balance)) balance")
                    .font(.fbBody(14, weight: .medium))
                    .foregroundStyle(Color.fbSoftText)
                    .contentTransition(.numericText(value: finances.balance))
                    .animation(.spring(response: 0.5, dampingFraction: 0.8), value: finances.balance)
            }

            chart
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var chart: some View {
        switch chartStyle {
        case .bar:
            VStack(alignment: .leading, spacing: 10) {
                // One fixed-height row: the month's income by default,
                // swapped in place for the tapped segment's details —
                // the layout never resizes.
                barStatusRow
                BalanceBar(completed: finances.paidThisMonth(),
                           pending: finances.upcomingObligations(),
                           safeToSpend: finances.safeToSpendToday(),
                           selection: $barSelection)
            }
            .transition(.opacity.combined(with: .scale(scale: 0.97)))
        case .sankey:
            // Income streams into the three groups — a monthly view,
            // unlike the balance-based bar.
            SankeyView(sources: finances.incomeSources,
                       recurringTotal: finances.recurringCommitments.reduce(0) { $0 + $1.amount },
                       oneOffTotal: finances.upcomingSchedule()
                           .filter { if case .oneOff = $0.kind { return true }; return false }
                           .reduce(0) { $0 + $1.amount })
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
        }
    }

    /// The row above the bar. Income and selection share the exact same
    /// typography and slot so tapping never moves the layout.
    private var barStatusRow: some View {
        HStack(spacing: 8) {
            if let sel = barSelection {
                Text(sel.name + " · \(sel.percent)%")
                    .font(.fbBody(14, weight: .medium))
                    .foregroundStyle(Color.fbInk)
                    .lineLimit(1)
                Spacer()
                Text((sel.isCompleted ? "paid · " : "") + "\(Money.string(sel.amount))")
                    .font(.fbNumber(15, weight: .semibold))
                    .foregroundStyle(Color.fbInk)
            } else {
                Text("Income")
                    .font(.fbBody(14, weight: .medium))
                    .foregroundStyle(Color.fbSoftText)
                Spacer()
                Text(Money.string(finances.totalIncome))
                    .font(.fbNumber(15, weight: .semibold))
                    .foregroundStyle(Color.fbSoftText)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: barSelection)
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
            .safeAreaBar(edge: .top) { PageTitleBar(title: "Budget") }
    }
}
