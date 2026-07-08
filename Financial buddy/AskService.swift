//
//  AskService.swift
//  Finance buddy
//
//  The "Ask" backend seam. The client NEVER talks to an AI provider or
//  holds an API key — it POSTs a financial snapshot plus the question to
//  our own endpoint, which does the reasoning server-side.
//
//  Until that endpoint URL is supplied, a local heuristic reasoner stands
//  in so the feature is demonstrable. It is clearly labelled as an
//  estimate and is swapped out the moment `AskConfig.endpoint` is set.
//

import Foundation

// MARK: - Configuration

enum AskConfig {
    /// Set this to the backend URL once it exists. While nil, the local
    /// stand-in reasoner is used.
    ///
    /// Example: URL(string: "https://api.yourbackend.com/ask")
    static let endpoint: URL? = nil
}

// MARK: - Wire types

/// The financial picture sent to the backend with every question.
struct FinancialSnapshot: Encodable {
    let balance: Double
    let incomeAmount: Double
    let nextPayDate: Date
    let daysUntilPayday: Int
    let safeToSpendToday: Double
    let monthlyHeadroom: Double
    let recurringCommitments: [Line]
    let oneOffCosts: [Line]

    struct Line: Encodable {
        let name: String
        let amount: Double
    }

    init(_ f: Finances) {
        balance = f.balance
        incomeAmount = f.income.amount
        nextPayDate = f.income.nextPayDate
        daysUntilPayday = f.daysUntilPayday()
        safeToSpendToday = f.safeToSpendToday()
        monthlyHeadroom = f.monthlyHeadroom
        recurringCommitments = f.recurringCommitments.map { Line(name: $0.name, amount: $0.amount) }
        oneOffCosts = f.oneOffCosts.map { Line(name: $0.name, amount: $0.amount) }
    }
}

struct AskRequest: Encodable {
    let question: String
    let snapshot: FinancialSnapshot
}

struct AskResponse: Decodable {
    let answer: String
}

// MARK: - Service

protocol AskServing: Sendable {
    func ask(question: String, snapshot: Finances) async throws -> String
}

enum AskError: LocalizedError {
    case server(Int)
    case decoding

    var errorDescription: String? {
        switch self {
        case .server(let code): return "The assistant is unavailable (error \(code))."
        case .decoding: return "Couldn't read the assistant's reply."
        }
    }
}

/// Posts the snapshot + question to our backend. Falls back to the local
/// reasoner when no endpoint is configured.
struct AskService: AskServing {
    var endpoint: URL? = AskConfig.endpoint
    var session: URLSession = .shared

    func ask(question: String, snapshot: Finances) async throws -> String {
        guard let endpoint else {
            return LocalReasoner.answer(to: question, finances: snapshot)
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        request.httpBody = try encoder.encode(
            AskRequest(question: question, snapshot: FinancialSnapshot(snapshot))
        )

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AskError.server((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        guard let decoded = try? JSONDecoder().decode(AskResponse.self, from: data) else {
            throw AskError.decoding
        }
        return decoded.answer
    }
}
