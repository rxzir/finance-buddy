//
//  FinanceModel.swift
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

/// One stream of money coming in — salary, refunds, bonuses… Mirrors the
/// payments split: recurring streams repeat monthly, one-offs land once.
struct IncomeSource: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var name: String
    var amount: Double
    var isRecurring: Bool
    var category: String
    /// When the money lands. For recurring income this anchors the monthly
    /// cycle (it repeats on this day of the month); the soonest recurring
    /// occurrence across all sources IS the next payday.
    var date: Date

    init(id: UUID = UUID(), name: String, amount: Double,
         isRecurring: Bool = true, category: String = "General",
         date: Date = Date()) {
        self.id = id
        self.name = name
        self.amount = amount
        self.isRecurring = isRecurring
        self.category = category
        self.date = date
    }
}

/// The full financial picture. All calculations hang off this so a view
/// only ever needs one value.
struct Finances: Codable, Equatable {
    var balance: Double
    /// Money coming in each month, from any number of avenues.
    var incomeSources: [IncomeSource]
    var recurringCommitments: [RecurringCommitment]
    var oneOffCosts: [OneOffCost]
    /// User-editable category lists (managed from the Profile screen).
    var paymentCategories: [String]
    var incomeCategories: [String]

    nonisolated static let defaultPaymentCategories = ["General", "Housing", "Utilities", "Subscriptions",
                                           "Health", "Transport", "Insurance", "Debt"]
    nonisolated static let defaultIncomeCategories = ["General", "Salary", "Freelance", "Refunds", "Gifts"]

    /// All monthly income combined.
    nonisolated var totalIncome: Double {
        incomeSources.reduce(0) { $0 + $1.amount }
    }

    nonisolated var recurringIncome: Double {
        incomeSources.filter(\.isRecurring).reduce(0) { $0 + $1.amount }
    }

    nonisolated var oneOffIncome: Double {
        incomeSources.filter { !$0.isRecurring }.reduce(0) { $0 + $1.amount }
    }

    nonisolated init(balance: Double,
         incomeSources: [IncomeSource] = [],
         recurringCommitments: [RecurringCommitment] = [],
         oneOffCosts: [OneOffCost] = [],
         paymentCategories: [String] = Finances.defaultPaymentCategories,
         incomeCategories: [String] = Finances.defaultIncomeCategories) {
        self.balance = balance
        self.incomeSources = incomeSources
        self.recurringCommitments = recurringCommitments
        self.oneOffCosts = oneOffCosts
        self.paymentCategories = paymentCategories
        self.incomeCategories = incomeCategories
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
    nonisolated static func nextOccurrence(ofDueDay dueDay: Int,
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

    /// The next payday — the soonest upcoming occurrence of any recurring
    /// income. Each recurring income repeats monthly on the day of its
    /// anchor date. Falls back to today when no recurring income exists.
    nonisolated func nextPayday(asOf today: Date = Date(),
                    calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: today)
        let candidates = incomeSources.filter(\.isRecurring).map {
            Finances.nextOccurrence(ofDueDay: calendar.component(.day, from: $0.date),
                                    onOrAfter: start,
                                    calendar: calendar)
        }
        return candidates.min() ?? start
    }

    /// Every commitment and one-off cost whose next occurrence lands in the
    /// window [today, next payday], inclusive, sorted by date.
    nonisolated func upcomingObligations(asOf today: Date = Date(),
                             calendar: Calendar = .current) -> [Obligation] {
        let start = calendar.startOfDay(for: today)
        let end = nextPayday(asOf: today, calendar: calendar)

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

    /// The full forward schedule — every recurring commitment's next
    /// occurrence and every future one-off, merged and sorted by date.
    /// Unlike `upcomingObligations` this is not limited to the pre-payday
    /// window; the view splits it at payday.
    nonisolated func upcomingSchedule(asOf today: Date = Date(),
                          calendar: Calendar = .current) -> [Obligation] {
        let start = calendar.startOfDay(for: today)
        var result: [Obligation] = []

        for commitment in recurringCommitments {
            let occurrence = Finances.nextOccurrence(ofDueDay: commitment.dueDay,
                                                     onOrAfter: start,
                                                     calendar: calendar)
            result.append(Obligation(id: commitment.id,
                                     name: commitment.name,
                                     amount: commitment.amount,
                                     date: occurrence,
                                     kind: .recurring(commitment)))
        }

        for cost in oneOffCosts {
            let day = calendar.startOfDay(for: cost.date)
            if day >= start {
                result.append(Obligation(id: cost.id,
                                         name: cost.name,
                                         amount: cost.amount,
                                         date: day,
                                         kind: .oneOff(cost)))
            }
        }

        return result.sorted { $0.date < $1.date }
    }

    /// Payments that have already landed this month — recurring commitments
    /// whose due day has passed and one-offs dated earlier in the month.
    /// The bar renders these as the faded "done" segments.
    func paidThisMonth(asOf today: Date = Date(),
                       calendar: Calendar = .current) -> [Obligation] {
        let start = calendar.startOfDay(for: today)
        guard let monthStart = calendar.dateInterval(of: .month, for: start)?.start else {
            return []
        }
        var result: [Obligation] = []

        for commitment in recurringCommitments {
            let occurrence = Finances.nextOccurrence(ofDueDay: commitment.dueDay,
                                                     onOrAfter: monthStart,
                                                     calendar: calendar)
            if occurrence >= monthStart && occurrence < start {
                result.append(Obligation(id: commitment.id,
                                         name: commitment.name,
                                         amount: commitment.amount,
                                         date: occurrence,
                                         kind: .recurring(commitment)))
            }
        }

        for cost in oneOffCosts {
            let day = calendar.startOfDay(for: cost.date)
            if day >= monthStart && day < start {
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
    nonisolated func safeToSpendToday(asOf today: Date = Date(),
                          calendar: Calendar = .current) -> Double {
        let committed = upcomingObligations(asOf: today, calendar: calendar)
            .reduce(0) { $0 + $1.amount }
        return balance - committed
    }

    /// Recurring income minus the sum of all recurring commitments — the
    /// structural monthly surplus, independent of one-off windfalls or the
    /// current balance. One-off income is excluded so affordability judgements
    /// are based on the reliable, repeating income only.
    nonisolated var monthlyHeadroom: Double {
        recurringIncome - recurringCommitments.reduce(0) { $0 + $1.amount }
    }

    /// Whole days from `today` until the next pay date (never negative).
    nonisolated func daysUntilPayday(asOf today: Date = Date(),
                         calendar: Calendar = .current) -> Int {
        let start = calendar.startOfDay(for: today)
        let payday = nextPayday(asOf: today, calendar: calendar)
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
            incomeSources: [
                IncomeSource(name: "Salary", amount: 2400, isRecurring: true,
                             category: "Salary", date: daysFromNow(18)),
                IncomeSource(name: "Refund", amount: 120, isRecurring: false,
                             category: "Refunds", date: daysFromNow(4)),
                IncomeSource(name: "Bonus", amount: 80, isRecurring: false,
                             category: "Salary", date: daysFromNow(10)),
            ],
            recurringCommitments: [
                RecurringCommitment(name: "Rent", amount: 950, dueDay: cal.component(.day, from: daysFromNow(9)), category: "Housing"),
                RecurringCommitment(name: "Phone", amount: 32, dueDay: cal.component(.day, from: daysFromNow(4)), category: "Utilities"),
                RecurringCommitment(name: "Gym", amount: 45, dueDay: cal.component(.day, from: daysFromNow(12)), category: "Health"),
                RecurringCommitment(name: "Netflix", amount: 11, dueDay: cal.component(.day, from: daysFromNow(6)), category: "Subscriptions"),
                RecurringCommitment(name: "Electricity", amount: 60, dueDay: max(1, cal.component(.day, from: daysFromNow(-6))), category: "Utilities"),
            ],
            oneOffCosts: [
                OneOffCost(name: "Concert tickets", amount: 120, date: daysFromNow(5)),
                OneOffCost(name: "Dentist", amount: 80, date: daysFromNow(14)),
                OneOffCost(name: "Birthday gift", amount: 40, date: daysFromNow(-3)),
            ]
        )
    }

    nonisolated static var empty: Finances {
        Finances(balance: 0)
    }
}
