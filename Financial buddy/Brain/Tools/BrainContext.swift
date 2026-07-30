//
//  BrainContext.swift
//  Finance buddy
//
//  Shared state for one conversation's tools. The session (and the tools
//  it was constructed with) lives for the whole conversation, but the
//  financial snapshot changes with every question — so tools read it
//  from here instead of capturing it. Proposed actions staged by tools
//  collect here too, and the service drains them after each turn.
//

import Foundation

final class BrainContext: @unchecked Sendable {
    private let lock = NSLock()
    private nonisolated(unsafe) var _finances: Finances
    private nonisolated(unsafe) var _pending: [ProposedAction] = []

    init(finances: Finances = .empty) {
        _finances = finances
    }

    /// The snapshot the current question is being answered against.
    nonisolated var finances: Finances {
        lock.lock()
        defer { lock.unlock() }
        return _finances
    }

    /// Called at the start of each turn: fresh snapshot, no leftover
    /// proposals from an earlier question.
    nonisolated func beginTurn(with finances: Finances) {
        lock.lock()
        defer { lock.unlock() }
        _finances = finances
        _pending = []
    }

    /// Tools stage writes here. Nothing is ever applied to the store.
    nonisolated func stage(_ action: ProposedAction) {
        lock.lock()
        defer { lock.unlock() }
        _pending.append(action)
    }

    /// Hands back everything staged this turn and clears the slate.
    nonisolated func drainPending() -> [ProposedAction] {
        lock.lock()
        defer { lock.unlock() }
        let pending = _pending
        _pending = []
        return pending
    }
}
