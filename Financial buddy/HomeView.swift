//
//  HomeView.swift
//  Finance buddy
//
//  Screen 1. Leads with the one number that matters, then makes it
//  literal with the eaten-balance bar, then breaks it down.
//

import SwiftUI

struct HomeView: View {
    let finances: Finances

    private var obligations: [Obligation] { finances.upcomingObligations() }
    private var safe: Double { finances.safeToSpendToday() }
    private var days: Int { finances.daysUntilPayday() }
    private var isOverspent: Bool { safe < 0 }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                hero
                barCard
                beforePaydayCard
                monthlyHeadroomCard
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(Color.hrBackground)
    }

    // MARK: Hero

    private var hero: some View {
        VStack(spacing: 6) {
            Text("SAFE TO SPEND TODAY")
                .font(.hrBody(13, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(Color.hrSoftText)

            Text(Money.string(safe))
                .font(.hrNumber(52, weight: .bold))
                .foregroundStyle(isOverspent ? Color.hrWarning : Color.hrInk)
                .minimumScaleFactor(0.5)
                .lineLimit(1)

            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.system(size: 13, weight: .semibold))
                Text(days == 0 ? "Payday is today" : "\(days) day\(days == 1 ? "" : "s") until payday")
                    .font(.hrBody(15, weight: .medium))
            }
            .foregroundStyle(Color.hrSoftText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    // MARK: Eaten-balance bar

    private var barCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Balance")
                        .font(.hrHeader(18))
                        .tracking(-0.3)
                        .foregroundStyle(Color.hrInk)
                    Spacer()
                    Text(Money.string(finances.balance))
                        .font(.hrNumber(18, weight: .semibold))
                        .foregroundStyle(Color.hrInk)
                }
                Text("What's already spoken for before payday")
                    .font(.hrBody(14))
                    .foregroundStyle(Color.hrSoftText)

                HeadroomBar(balance: finances.balance,
                            obligations: obligations,
                            safeToSpend: safe)
            }
        }
    }

    // MARK: Before payday breakdown

    private var beforePaydayCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                cardTitle("Before payday", systemImage: "arrow.down.circle")

                breakdownRow(label: "Balance", value: finances.balance)

                if obligations.isEmpty {
                    Text("Nothing due before payday.")
                        .font(.hrBody(14))
                        .foregroundStyle(Color.hrSoftText)
                } else {
                    ForEach(obligations) { ob in
                        breakdownRow(label: ob.name, value: -ob.amount, muted: true)
                    }
                }

                Divider().overlay(Color.hrHairline)

                breakdownRow(label: isOverspent ? "Overspent" : "Safe to spend",
                             value: safe,
                             emphasis: true)
            }
        }
    }

    // MARK: Monthly headroom

    private var monthlyHeadroomCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                cardTitle("Monthly headroom", systemImage: "chart.pie")

                breakdownRow(label: "Monthly income", value: finances.income.amount)
                breakdownRow(label: "All recurring commitments",
                             value: -finances.recurringCommitments.reduce(0) { $0 + $1.amount },
                             muted: true)

                Divider().overlay(Color.hrHairline)

                breakdownRow(label: "Headroom", value: finances.monthlyHeadroom, emphasis: true)

                Text("What's left each month once every regular commitment is paid.")
                    .font(.hrBody(13))
                    .foregroundStyle(Color.hrSoftText)
                    .padding(.top, 2)
            }
        }
    }

    // MARK: Building blocks

    private func cardTitle(_ text: String, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.hrSoftText)
            Text(text)
                .font(.hrHeader(17))
                .tracking(-0.3)
                .foregroundStyle(Color.hrInk)
        }
    }

    private func breakdownRow(label: String,
                              value: Double,
                              muted: Bool = false,
                              emphasis: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(.hrBody(emphasis ? 16 : 15, weight: emphasis ? .semibold : .regular))
                .foregroundStyle(muted ? Color.hrSoftText : Color.hrInk)
            Spacer()
            Text(Money.string(value, showsSign: muted))
                .font(.hrNumber(emphasis ? 17 : 15, weight: emphasis ? .bold : .regular))
                .foregroundStyle(color(for: value, muted: muted, emphasis: emphasis))
        }
    }

    private func color(for value: Double, muted: Bool, emphasis: Bool) -> Color {
        if emphasis { return value < 0 ? Color.hrWarning : Color.hrPositive }
        if muted { return Color.hrSoftText }
        return Color.hrInk
    }
}

#Preview {
    HomeView(finances: .sample)
}
