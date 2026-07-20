//
//  FinanceBuddyStore.swift
//  Finance buddy
//
//  The single observable owner of the user's financial data. Views read
//  and mutate through this. Persistence is delegated to a backing store
//  (Supabase) behind a protocol so the UI never talks to the network
//  directly.
//

import Foundation
import Observation

@MainActor
@Observable
final class FinanceBuddyStore {
    var finances: Finances {
        didSet { scheduleSave() }
    }

    /// Backing persistence. Defaults to a no-op so previews and first-run
    /// work without a network. Swapped for the Supabase-backed store at
    /// launch once the user is signed in.
    @ObservationIgnored var persistence: FinancePersisting?

    /// Bottom toasts for add/delete feedback. Deletions carry an undo
    /// that restores the pre-delete snapshot.
    let toasts = ToastCenter()

    private var saveTask: Task<Void, Never>?

    init(finances: Finances = .empty, persistence: FinancePersisting? = nil) {
        self.finances = finances
        self.persistence = persistence
    }

    // MARK: Mutations

    func addCommitment(_ c: RecurringCommitment) {
        finances.recurringCommitments.append(c)
        toasts.show("\(c.name) added")
    }

    func removeCommitment(_ c: RecurringCommitment) {
        finances.recurringCommitments.removeAll { $0.id == c.id }
        toasts.show("\(c.name) deleted", undo: { [weak self] in
            self?.finances.recurringCommitments.append(c)
        })
    }

    func updateCommitment(_ c: RecurringCommitment) {
        if let index = finances.recurringCommitments.firstIndex(where: { $0.id == c.id }) {
            finances.recurringCommitments[index] = c
        }
    }

    func addOneOff(_ o: OneOffCost) {
        finances.oneOffCosts.append(o)
        toasts.show("\(o.name) added")
    }

    func removeOneOff(_ o: OneOffCost) {
        finances.oneOffCosts.removeAll { $0.id == o.id }
        toasts.show("\(o.name) deleted", undo: { [weak self] in
            self?.finances.oneOffCosts.append(o)
        })
    }

    func updateOneOff(_ o: OneOffCost) {
        if let index = finances.oneOffCosts.firstIndex(where: { $0.id == o.id }) {
            finances.oneOffCosts[index] = o
        }
    }

    func addIncome(_ s: IncomeSource) {
        finances.incomeSources.append(s)
        toasts.show("\(s.name) added")
    }

    func removeIncome(_ s: IncomeSource) {
        finances.incomeSources.removeAll { $0.id == s.id }
        toasts.show("\(s.name) deleted", undo: { [weak self] in
            self?.finances.incomeSources.append(s)
        })
    }

    func updateIncome(_ s: IncomeSource) {
        if let index = finances.incomeSources.firstIndex(where: { $0.id == s.id }) {
            finances.incomeSources[index] = s
        }
    }

    // MARK: Categories (managed from Profile)

    func addCategory(_ name: String, forIncome: Bool) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        if forIncome {
            guard !finances.incomeCategories.contains(trimmed) else { return }
            finances.incomeCategories.append(trimmed)
        } else {
            guard !finances.paymentCategories.contains(trimmed) else { return }
            finances.paymentCategories.append(trimmed)
        }
    }

    /// Renames a category and re-tags every item that used the old name.
    func renameCategory(from old: String, to new: String, forIncome: Bool) {
        let trimmed = new.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != old else { return }
        if forIncome {
            guard let index = finances.incomeCategories.firstIndex(of: old) else { return }
            finances.incomeCategories[index] = trimmed
            for i in finances.incomeSources.indices where finances.incomeSources[i].category == old {
                finances.incomeSources[i].category = trimmed
            }
        } else {
            guard let index = finances.paymentCategories.firstIndex(of: old) else { return }
            finances.paymentCategories[index] = trimmed
            for i in finances.recurringCommitments.indices where finances.recurringCommitments[i].category == old {
                finances.recurringCommitments[i].category = trimmed
            }
        }
    }

    /// Reorders categories (drag-and-drop in the manage modal). Mirrors
    /// SwiftUI's move(fromOffsets:toOffset:) semantics without importing
    /// SwiftUI into the model layer.
    func moveCategories(fromOffsets: IndexSet, toOffset: Int, forIncome: Bool) {
        func moved(_ array: [String]) -> [String] {
            let moving = fromOffsets.map { array[$0] }
            var rest = array
            for index in fromOffsets.sorted(by: >) { rest.remove(at: index) }
            let insertAt = toOffset - fromOffsets.filter { $0 < toOffset }.count
            rest.insert(contentsOf: moving, at: insertAt)
            return rest
        }
        if forIncome {
            finances.incomeCategories = moved(finances.incomeCategories)
        } else {
            finances.paymentCategories = moved(finances.paymentCategories)
        }
    }

    /// Removes a category; items that used it fall back to the first
    /// remaining category. The last category can't be removed.
    func removeCategory(_ name: String, forIncome: Bool) {
        if forIncome {
            guard finances.incomeCategories.count > 1 else { return }
            finances.incomeCategories.removeAll { $0 == name }
            let fallback = finances.incomeCategories[0]
            for i in finances.incomeSources.indices where finances.incomeSources[i].category == name {
                finances.incomeSources[i].category = fallback
            }
        } else {
            guard finances.paymentCategories.count > 1 else { return }
            finances.paymentCategories.removeAll { $0 == name }
            let fallback = finances.paymentCategories[0]
            for i in finances.recurringCommitments.indices where finances.recurringCommitments[i].category == name {
                finances.recurringCommitments[i].category = fallback
            }
        }
    }

    // MARK: Loading & saving

    func load() async {
        guard let persistence else { return }
        do {
            if let loaded = try await persistence.load() {
                finances = loaded
            }
        } catch {
            // Keep whatever we have locally; surface later via UI if needed.
            print("Finance buddy: load failed — \(error)")
        }
    }

    /// Debounce rapid edits (e.g. typing in a field) into a single save.
    private func scheduleSave() {
        guard persistence != nil else { return }
        saveTask?.cancel()
        let snapshot = finances
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            do {
                try await self?.persistence?.save(snapshot)
            } catch {
                print("Finance buddy: save failed — \(error)")
            }
        }
    }
}

// MARK: - Persistence boundary

/// Anything that can persist the user's finances. Keeps the store testable
/// and lets Supabase live entirely behind this seam.
protocol FinancePersisting: Sendable {
    func load() async throws -> Finances?
    func save(_ finances: Finances) async throws
}
