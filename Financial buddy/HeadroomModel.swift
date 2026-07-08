//
//  HeadroomModel.swift
//  Finance buddy
//
//  Pure data model + calculations. No SwiftUI, no side effects.
//  Everything here is deterministic and injectable (calendar + "today")
//  so it can be exercised directly in tests.
//

import Foundation

// MARK: - Model

/// A regular, repeating cost that lands on the same day each month.
struct RecurringCommitment: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var name: String
    var amount: Double
    /// Day of the month the commitment is due (1...31). Clamped to the
    /// month's length when a month is shorter (e.g. a "31" in February).
    var dueDay: Int
    var category: String

    init(id: UUID = UUID(), name: String, amount: Double, dueDay: Int, category: String) {
        self.id = id
        self.name = name
        self.amount = amount
        self.dueDay = dueDay
        self.category = category
    }
}

/// A single, non-repeating future cost on a specific date.
struct OneOffCost: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var name: String
    var amount: Double
    var date: Date

    init(id: UUID = UUID(), name: String, amount: Double, date: Date) {
        self.id = id
        self.name = name
        self.amount = amount
        self.date = date
    }
}

/// Regular income and when the next pay lands.
struct Income: Codable, Equatable, Hashable {
    var amount: Double
    var nextPayDate: Date

    init(amount: Double, nextPayDate: Date) {
        self.amount = amount
        self.nextPayDate = nextPayDate
    }
}

/// The full financial picture. All calculations hang off this so a view
/// only ever needs one value.
struct Finances: Codable, Equatable {
    var balance: Double
    var income: Income
    var recurringCommitments: [RecurringCommitment]
    var oneOffCosts: [OneOffCost]

    init(balance: Double,
         income: Income,
         recurringCommitments: [RecurringCommitment] = [],
         oneOffCosts: [OneOffCost] = []) {
        self.balance = balance
        self.income = income
        self.recurringCommitments = recurringCommitments
        self.oneOffCosts = oneOffCosts
    }
}

// MARK: - Obligations (the pieces that "eat" the balance before payday)

/// A single upcoming cost that falls inside the window between now and
/// payday. This is what the Home bar renders as a proportional segment.
struct Obligation: Identifiable, Equatable {
    enum Kind: Equatable {
        case recurring(RecurringCommitment)
        case oneOff(OneOffCost)
    }

    let id: UUID
    var name: String
    var amount: Double
    /// The concrete calendar date this cost lands on inside the window.
    var date: Date
    var kind: Kind
}

// MARK: - Calculations

extension Finances {

    /// The next calendar date on or after `reference` on which a commitment
    /// with the given `dueDay` falls. If the target month is shorter than
    /// `dueDay`, the due date is clamped to the last day of that month.
    static func nextOccurrence(ofDueDay dueDay: Int,
                               onOrAfter reference: Date,
                               calendar: Calendar) -> Date {
        let startOfReference = calendar.startOfDay(for: reference)

        // Try the reference month first, then walk forward a month at a time.
        // Two iterations is always enough (this month, next month), but we
        // loop defensively.
        for monthOffset in 0...2 {
            guard
                let monthAnchor = calendar.date(byAdding: .month,
                                                value: monthOffset,
                                                to: startOfReference),
                let range = calendar.range(of: .day, in: .month, for: monthAnchor)
            else { continue }

            let clampedDay = min(dueDay, range.upperBound - 1)
            var components = calendar.dateComponents([.year, .month], from: monthAnchor)
            components.day = clampedDay

            if let candidate = calendar.date(from: components),
               calendar.startOfDay(for: candidate) >= startOfReference {
                return calendar.startOfDay(for: candidate)
            }
        }

        // Fallback: should never hit this, but never return an arbitrary date.
        return startOfReference
    }

    /// Every commitment and one-off cost whose next occurrence lands in the
    /// window [today, nextPayDate], inclusive, sorted by date.
    func upcomingObligations(asOf today: Date = Date(),
                             calendar: Calendar = .current) -> [Obligation] {
        let start = calendar.startOfDay(for: today)
        let end = calendar.startOfDay(for: income.nextPayDate)

        // If payday is in the past or today, there is no window to draw from.
        guard end >= start else { return [] }

        var result: [Obligation] = []

        for commitment in recurringCommitments {
            let occurrence = Finances.nextOccurrence(ofDueDay: commitment.dueDay,
                                                     onOrAfter: start,
                                                     calendar: calendar)
            if occurrence >= start && occurrence <= end {
                result.append(Obligation(id: commitment.id,
                                         name: commitment.name,
                                         amount: commitment.amount,
                                         date: occurrence,
                                         kind: .recurring(commitment)))
            }
        }

        for cost in oneOffCosts {
            let day = calendar.startOfDay(for: cost.date)
            if day >= start && day <= end {
                result.append(Obligation(id: cost.id,
                                         name: cost.name,
                                         amount: cost.amount,
                                         date: day,
                                         kind: .oneOff(cost)))
            }
        }

        return result.sorted { $0.date < $1.date }
    }

    /// Balance minus every obligation that lands before (and including)
    /// payday. This is the hero number.
    func safeToSpendToday(asOf today: Date = Date(),
                          calendar: Calendar = .current) -> Double {
        let committed = upcomingObligations(asOf: today, calendar: calendar)
            .reduce(0) { $0 + $1.amount }
        return balance - committed
    }

    /// Income minus the sum of all recurring commitments — the room you
    /// have across a whole month, independent of the current balance.
    var monthlyHeadroom: Double {
        income.amount - recurringCommitments.reduce(0) { $0 + $1.amount }
    }

    /// Whole days from `today` until the next pay date (never negative).
    func daysUntilPayday(asOf today: Date = Date(),
                         calendar: Calendar = .current) -> Int {
        let start = calendar.startOfDay(for: today)
        let payday = calendar.startOfDay(for: income.nextPayDate)
        let days = calendar.dateComponents([.day], from: start, to: payday).day ?? 0
        return max(0, days)
    }
}

// MARK: - Sample data (previews / first run)

extension Finances {
    static var sample: Finances {
        let cal = Calendar.current
        let today = Date()
        func daysFromNow(_ n: Int) -> Date {
            cal.date(byAdding: .day, value: n, to: cal.startOfDay(for: today)) ?? today
        }
        return Finances(
            balance: 2140,
            income: Income(amount: 2600, nextPayDate: daysFromNow(18)),
            recurringCommitments: [
                RecurringCommitment(name: "Rent", amount: 950, dueDay: cal.component(.day, from: daysFromNow(9)), category: "Housing"),
                RecurringCommitment(name: "Phone", amount: 32, dueDay: cal.component(.day, from: daysFromNow(4)), category: "Utilities"),
                RecurringCommitment(name: "Gym", amount: 45, dueDay: cal.component(.day, from: daysFromNow(12)), category: "Health"),
                RecurringCommitment(name: "Netflix", amount: 11, dueDay: cal.component(.day, from: daysFromNow(6)), category: "Subscriptions"),
            ],
            oneOffCosts: [
                OneOffCost(name: "Concert tickets", amount: 120, date: daysFromNow(5)),
                OneOffCost(name: "Dentist", amount: 80, date: daysFromNow(14)),
            ]
        )
    }

    static var empty: Finances {
        Finances(balance: 0, income: Income(amount: 0, nextPayDate: Date()))
    }
}
