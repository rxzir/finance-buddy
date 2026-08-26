//
//  FinanceMath.swift
//  Headroom
//
//  Tier 0: the extra deterministic calculations the reasoning layer
//  needs, on top of what FinanceModel already provides. The model never
//  computes a number — every figure it speaks comes from here (or from
//  Finances' own calculations), with the calendar and "today" injectable
//  so all of it is unit-testable.
//

import Foundation

// MARK: - Affordability verdict

/// Judges a new recurring cost against monthly headroom. Same thresholds
/// the local reasoner uses: under a quarter of headroom left is "tight".
enum AffordabilityVerdict: String, Equatable, Sendable {
    case comfortable, tight, unaffordable

    nonisolated static func judge(headroom: Double, newMonthlyCost: Double) -> AffordabilityVerdict {
        let remaining = headroom - newMonthlyCost
        if remaining < 0 { return .unaffordable }
        if remaining < headroom * 0.25 { return .tight }
        return .comfortable
    }
}

// MARK: - Windowed capacity

extension Finances {

    /// The pieces behind a capacity figure, so answers can say how the
    /// number was reached.
    struct CapacityBreakdown: Equatable {
        var free: Double
        var incomeInWindow: Double
        var obligationsInWindow: Double
    }

    /// Free money over the next `days` days: balance, plus income landing
    /// inside the window, minus everything due inside it.
    nonisolated func capacity(overDays days: Int,
                  asOf today: Date = Date(),
                  calendar: Calendar = .current) -> CapacityBreakdown {
        let start = calendar.startOfDay(for: today)
        let end = calendar.date(byAdding: .day, value: days, to: start) ?? start

        let due = upcomingSchedule(asOf: today, calendar: calendar)
            .filter { $0.date <= end }
            .reduce(0) { $0 + $1.amount }

        var incoming = 0.0
        for source in incomeSources {
            if source.isRecurring {
                let occurrence = Finances.nextOccurrence(
                    ofDueDay: calendar.component(.day, from: source.date),
                    onOrAfter: start,
                    calendar: calendar)
                if occurrence <= end { incoming += source.amount }
            } else {
                let day = calendar.startOfDay(for: source.date)
                if day >= start && day <= end { incoming += source.amount }
            }
        }

        return CapacityBreakdown(free: balance + incoming - due,
                                 incomeInWindow: incoming,
                                 obligationsInWindow: due)
    }

    /// Monthly headroom left once a new recurring cost is added.
    nonisolated func headroomAfterAdding(monthly amount: Double) -> Double {
        monthlyHeadroom - amount
    }
}
