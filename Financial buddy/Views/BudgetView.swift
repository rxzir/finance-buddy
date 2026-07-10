//
//  BudgetView.swift
//  Finance buddy
//
//  One scrollable screen, three cards, no duplicated numbers:
//  1. TODAY — safe-to-spend hero (the only place it appears here),
//     the commitment bar, days to payday. Pencil edits balance/income/payday.
//  2. COMMITMENTS — recurring + one-offs merged into one list sorted by
//     next due date, split visually at payday. Pencil manages the items.
//  3. MONTHLY HEADROOM — income minus recurring. No edit icon; its inputs
//     are already editable from the two cards above.
//

import SwiftUI

struct BudgetView: View {
    @Bindable var store: FinanceBuddyStore

    enum ActiveOverlay {
        case editToday
        case manageCommitments
    }
    @State private var overlay: ActiveOverlay?

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

    private var finances: Finances { store.finances }

    var body: some View {
        ZStack {
            FBBackground()

            ScrollView {
                VStack(spacing: 16) {
                    header
                    todayCard
                    commitmentsCard
                    headroomCard
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 24)
            }

            switch overlay {
            case .editToday:
                EditTodayOverlay(store: store) { overlay = nil }
            case .manageCommitments:
                ManageCommitmentsOverlay(store: store) { overlay = nil }
            case nil:
                EmptyView()
            }
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

    private var todayCard: some View {
        let safe = finances.safeToSpendToday()
        let days = finances.daysUntilPayday()
        let isOverspent = safe < 0

        return Card {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    chartToggle
                    Spacer()
                    pencilButton { overlay = .editToday }
                }

                // The hero — the only place safe-to-spend is shown.
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
                    Text(days == 0 ? "Payday is today" : "\(days) day\(days == 1 ? "" : "s") until payday")
                        .font(.fbBody(14, weight: .medium))
                        .foregroundStyle(Color.fbSoftText)
                }
                .frame(maxWidth: .infinity)

                // Balance context + one of two visuals (no legend — the
                // itemized list is the Upcoming payments card below).
                HStack {
                    Text("Balance")
                        .font(.fbBody(14))
                        .foregroundStyle(Color.fbSoftText)
                    Spacer()
                    Text(Money.string(finances.balance))
                        .font(.fbNumber(15, weight: .semibold))
                        .foregroundStyle(Color.fbInk)
                        .contentTransition(.numericText(value: finances.balance))
                        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: finances.balance)
                }

                switch chartStyle {
                case .bar:
                    BalanceBar(balance: finances.balance,
                               obligations: finances.upcomingObligations(),
                               safeToSpend: safe,
                               showsLegend: false)
                        .transition(.opacity.combined(with: .scale(scale: 0.97)))
                case .sankey:
                    SankeyView(balance: finances.balance,
                               obligations: finances.upcomingObligations(),
                               safeToSpend: safe)
                        .transition(.opacity.combined(with: .scale(scale: 0.97)))
                }
            }
        }
    }

    /// Two tiny icons flipping the Today visual between the eaten bar and
    /// the flow (sankey) view.
    private var chartToggle: some View {
        HStack(spacing: 2) {
            ForEach(ChartStyle.allCases, id: \.self) { style in
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        chartStyle = style
                    }
                } label: {
                    Image(systemName: style.icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(chartStyle == style ? Color.fbInk : Color.fbSoftText)
                        .frame(width: 30, height: 26)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(chartStyle == style ? Color.white.opacity(0.10) : .clear)
                        )
                }
                .buttonStyle(.pressable)
                .accessibilityLabel(style == .bar ? "Bar view" : "Flow view")
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.fbHairline, lineWidth: 1)
        )
    }

    // MARK: 2. Commitments (merged list, split at payday)

    private var commitmentsCard: some View {
        let schedule = finances.upcomingSchedule()
        let payday = Calendar.current.startOfDay(for: finances.income.nextPayDate)
        let before = schedule.filter { $0.date <= payday }
        let after = schedule.filter { $0.date > payday }

        return Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    cardTitle("Upcoming payments")
                    Spacer()
                    pencilButton { overlay = .manageCommitments }
                }

                if schedule.isEmpty {
                    Text("Nothing coming up. Add payments with the pencil.")
                        .font(.fbBody(14))
                        .foregroundStyle(Color.fbSoftText)
                } else {
                    if !before.isEmpty {
                        sectionLabel("Before payday")
                        ForEach(before) { item in
                            scheduleRow(item, emphasised: true)
                        }
                    }

                    if !after.isEmpty {
                        if !before.isEmpty {
                            Divider().overlay(Color.fbHairline).padding(.vertical, 2)
                        }
                        sectionLabel("After payday")
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

        return HStack(spacing: 10) {
            Image(systemName: isRecurring ? "repeat" : "calendar")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(emphasised ? Color.fbCommitment : Color.fbSoftText)
                .frame(width: 16)

            Text(item.name)
                .font(.fbBody(15, weight: emphasised ? .semibold : .regular))
                .foregroundStyle(emphasised ? Color.fbInk : Color.fbSoftText)

            Spacer()

            Text(item.date.formatted(.dateTime.day().month(.abbreviated)))
                .font(.fbBody(13))
                .foregroundStyle(Color.fbSoftText)

            Text(Money.string(item.amount))
                .font(.fbNumber(15, weight: emphasised ? .semibold : .regular))
                .foregroundStyle(emphasised ? Color.fbInk : Color.fbSoftText)
                .frame(minWidth: 64, alignment: .trailing)
        }
        .padding(.vertical, 3)
    }

    // MARK: 3. Monthly headroom (read-only — inputs live in cards 1 & 2)

    private var headroomCard: some View {
        let recurringTotal = finances.recurringCommitments.reduce(0) { $0 + $1.amount }
        let headroom = finances.monthlyHeadroom

        return Card {
            VStack(alignment: .leading, spacing: 12) {
                cardTitle("Monthly headroom")

                row("Monthly income", Money.string(finances.income.amount))
                row("Recurring commitments", Money.string(-recurringTotal), muted: true)

                Divider().overlay(Color.fbHairline)

                HStack {
                    Text("Headroom")
                        .font(.fbBody(16, weight: .semibold))
                        .foregroundStyle(Color.fbInk)
                    Spacer()
                    Text(Money.string(headroom))
                        .font(.fbNumber(17, weight: .bold))
                        .foregroundStyle(headroom < 0 ? Color.fbWarning : Color.fbPositive)
                }

                Text("What's left each month once every regular commitment is paid.")
                    .font(.fbBody(13))
                    .foregroundStyle(Color.fbSoftText)
            }
        }
    }

    private func row(_ label: String, _ value: String, muted: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(.fbBody(15))
                .foregroundStyle(muted ? Color.fbSoftText : Color.fbInk)
            Spacer()
            Text(value)
                .font(.fbNumber(15))
                .foregroundStyle(muted ? Color.fbSoftText : Color.fbInk)
        }
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
                .background(Circle().fill(Color.white.opacity(0.05)))
                .overlay(Circle().strokeBorder(Color.fbHairline, lineWidth: 1))
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("Edit")
    }
}

#Preview {
    BudgetView(store: FinanceBuddyStore(finances: .sample))
        .preferredColorScheme(.dark)
}
