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

    private var saveTask: Task<Void, Never>?

    init(finances: Finances = .empty, persistence: FinancePersisting? = nil) {
        self.finances = finances
        self.persistence = persistence
    }

    // MARK: Mutations

    func addCommitment(_ c: RecurringCommitment) {
        finances.recurringCommitments.append(c)
    }

    func removeCommitment(_ c: RecurringCommitment) {
        finances.recurringCommitments.removeAll { $0.id == c.id }
    }

    func addOneOff(_ o: OneOffCost) {
        finances.oneOffCosts.append(o)
    }

    func removeOneOff(_ o: OneOffCost) {
        finances.oneOffCosts.removeAll { $0.id == o.id }
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
