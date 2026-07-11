//
//  SupabasePersistence.swift
//  Finance buddy
//
//  Supabase-backed auth + persistence, scoped to the signed-in user.
//
//  This whole file is gated on `canImport(Supabase)`, so the project keeps
//  building before the SPM package is added. Once you add `supabase-swift`
//  and fill in `SupabaseConfig`, it activates automatically.
//
//  SQL schema this expects is documented at the bottom of the file.
//

#if canImport(Supabase)
import Foundation
import Supabase

// MARK: - Configuration

enum SupabaseConfig {
    /// Values live in the git-ignored SupabaseSecrets.swift — see
    /// SupabaseSecrets.swift.example for the template.
    static let url = SupabaseSecrets.projectURL
    static let anonKey = SupabaseSecrets.anonKey

    static let client = SupabaseClient(
        supabaseURL: url,
        supabaseKey: anonKey,
        options: SupabaseClientOptions(
            db: .init(encoder: postgrestEncoder, decoder: postgrestDecoder),
            // Opt in to the SDK's future session behavior; silences its
            // runtime notice. We read auth.session directly (which
            // validates/refreshes), so the emitted initial session's
            // validity doesn't affect us.
            auth: .init(emitLocalSessionAsInitialSession: true)
        )
    )

    /// Postgres `timestamptz` comes back as ISO 8601 with or without
    /// fractional seconds (e.g. "2026-07-27T00:00:00+00:00"). Pin both
    /// directions explicitly so decoding never depends on SDK defaults.
    static let postgrestDecoder: JSONDecoder = {
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let string = try decoder.singleValueContainer().decode(String.self)
            if let date = withFractional.date(from: string) ?? plain.date(from: string) {
                return date
            }
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Unrecognised timestamp: \(string)"
            ))
        }
        return decoder
    }()

    static let postgrestEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}

// MARK: - Auth

@MainActor
@Observable
final class SupabaseAuthModel {
    /// Nil while we're still restoring any persisted session on launch.
    var isReady = false
    var userId: UUID?
    var email: String?
    var errorMessage: String?
    var isWorking = false

    var isSignedIn: Bool { userId != nil }

    private let client = SupabaseConfig.client

    /// Restore a persisted session (Supabase stores it in the keychain).
    func restore() async {
        defer { isReady = true }
        if let session = try? await client.auth.session {
            userId = session.user.id
            email = session.user.email
        }
    }

    func signIn(email: String, password: String) async {
        await run {
            let session = try await self.client.auth.signIn(email: email, password: password)
            self.userId = session.user.id
            self.email = session.user.email
        }
    }

    /// Set when sign-up succeeded but the account still needs email
    /// confirmation before it can sign in.
    var infoMessage: String?

    func signUp(email: String, password: String) async {
        await run {
            let response = try await self.client.auth.signUp(email: email, password: password)
            if let session = response.session {
                // Email confirmation is off — signed in immediately.
                self.userId = session.user.id
                self.email = session.user.email
            } else {
                // Confirmation required: NOT signed in yet. Treating the
                // user as signed in here would leave every RLS write
                // failing with an invalid session.
                self.infoMessage = "Almost there — confirm the link we sent to \(email), then sign in."
            }
        }
    }

    func signOut() async {
        try? await client.auth.signOut()
        userId = nil
        email = nil
    }

    private func run(_ work: @escaping () async throws -> Void) async {
        isWorking = true
        errorMessage = nil
        infoMessage = nil
        defer { isWorking = false }
        do { try await work() }
        catch { errorMessage = error.localizedDescription }
    }
}

// MARK: - Persistence

/// Reads/writes the user's finances across three tables. Small data set,
/// so commitments / one-offs are replaced wholesale on save.
struct SupabaseFinancePersistence: FinancePersisting {
    let userId: UUID
    private var client: SupabaseClient { SupabaseConfig.client }

    func load() async throws -> Finances? {
        async let core: [FinancesRow] = client
            .from("finances").select().eq("user_id", value: userId).execute().value
        async let incomes: [IncomeSourceRow] = client
            .from("income_sources").select().eq("user_id", value: userId).execute().value
        async let commitments: [CommitmentRow] = client
            .from("recurring_commitments").select().eq("user_id", value: userId).execute().value
        async let oneOffs: [OneOffRow] = client
            .from("one_off_costs").select().eq("user_id", value: userId).execute().value

        let (coreRows, incomeRows, commitmentRows, oneOffRows) =
            try await (core, incomes, commitments, oneOffs)
        guard let c = coreRows.first else { return nil } // nothing saved yet

        var sources = incomeRows.map {
            IncomeSource(id: $0.id, name: $0.name, amount: $0.amount,
                         isRecurring: $0.is_recurring ?? true,
                         category: $0.category ?? "General",
                         date: $0.date ?? c.next_pay_date)
        }
        // Migration: accounts saved before multi-income only have the old
        // single income_amount — surface it as a "Salary" source anchored
        // on the stored payday.
        if sources.isEmpty && c.income_amount > 0 {
            sources = [IncomeSource(name: "Salary", amount: c.income_amount,
                                    isRecurring: true, category: "Salary",
                                    date: c.next_pay_date)]
        }

        return Finances(
            balance: c.balance,
            incomeSources: sources,
            recurringCommitments: commitmentRows.map {
                RecurringCommitment(id: $0.id, name: $0.name, amount: $0.amount,
                                    dueDay: $0.due_day, category: $0.category)
            },
            oneOffCosts: oneOffRows.map {
                OneOffCost(id: $0.id, name: $0.name, amount: $0.amount, date: $0.date)
            },
            paymentCategories: c.payment_categories ?? Finances.defaultPaymentCategories,
            incomeCategories: c.income_categories ?? Finances.defaultIncomeCategories
        )
    }

    func save(_ finances: Finances) async throws {
        // 1. Upsert the single core row (income_amount kept as the total
        //    for backwards compatibility).
        try await client.from("finances").upsert(
            FinancesRow(user_id: userId,
                        balance: finances.balance,
                        income_amount: finances.totalIncome,
                        // Payday is now derived from recurring income; the
                        // column stays populated for backwards compatibility.
                        next_pay_date: finances.nextPayday(),
                        payment_categories: finances.paymentCategories,
                        income_categories: finances.incomeCategories),
            onConflict: "user_id"
        ).execute()

        // 2. Replace child rows for this user.
        try await client.from("income_sources").delete().eq("user_id", value: userId).execute()
        if !finances.incomeSources.isEmpty {
            try await client.from("income_sources").insert(
                finances.incomeSources.map {
                    IncomeSourceRow(id: $0.id, user_id: userId, name: $0.name,
                                    amount: $0.amount, is_recurring: $0.isRecurring,
                                    category: $0.category, date: $0.date)
                }
            ).execute()
        }

        try await client.from("recurring_commitments").delete().eq("user_id", value: userId).execute()
        if !finances.recurringCommitments.isEmpty {
            try await client.from("recurring_commitments").insert(
                finances.recurringCommitments.map {
                    CommitmentRow(id: $0.id, user_id: userId, name: $0.name,
                                  amount: $0.amount, due_day: $0.dueDay, category: $0.category)
                }
            ).execute()
        }

        try await client.from("one_off_costs").delete().eq("user_id", value: userId).execute()
        if !finances.oneOffCosts.isEmpty {
            try await client.from("one_off_costs").insert(
                finances.oneOffCosts.map {
                    OneOffRow(id: $0.id, user_id: userId, name: $0.name,
                              amount: $0.amount, date: $0.date)
                }
            ).execute()
        }
    }
}

// MARK: - Row DTOs (snake_case to match Postgres columns)

private struct FinancesRow: Codable {
    var user_id: UUID
    var balance: Double
    var income_amount: Double
    var next_pay_date: Date
    // Optional so rows written before the categories migration still decode.
    var payment_categories: [String]?
    var income_categories: [String]?
}

private struct IncomeSourceRow: Codable {
    var id: UUID
    var user_id: UUID
    var name: String
    var amount: Double
    // Optional so rows written before the recurring/category/date
    // migrations decode.
    var is_recurring: Bool?
    var category: String?
    var date: Date?
}

private struct CommitmentRow: Codable {
    var id: UUID
    var user_id: UUID
    var name: String
    var amount: Double
    var due_day: Int
    var category: String
}

private struct OneOffRow: Codable {
    var id: UUID
    var user_id: UUID
    var name: String
    var amount: Double
    var date: Date
}

#endif

/*
 ── Supabase SQL schema ───────────────────────────────────────────────────
 Run this in the Supabase SQL editor. The whole block is idempotent —
 safe to re-run on an existing project (tables are `if not exists`,
 columns are added `if not exists`, policies are dropped and recreated).
 RLS ensures each user only ever sees their own rows.

 create table if not exists finances (
   user_id uuid primary key references auth.users on delete cascade,
   balance numeric not null default 0,
   income_amount numeric not null default 0,
   next_pay_date timestamptz not null default now()
 );
 -- 2026-07-11: user-editable category lists.
 alter table finances add column if not exists payment_categories jsonb;
 alter table finances add column if not exists income_categories jsonb;

 -- 2026-07-11: multiple income sources, split recurring/one-off + category.
 create table if not exists income_sources (
   id uuid primary key default gen_random_uuid(),
   user_id uuid not null references auth.users on delete cascade,
   name text not null,
   amount numeric not null,
   is_recurring boolean not null default true,
   category text not null default 'General',
   date timestamptz not null default now()
 );
 alter table income_sources add column if not exists is_recurring boolean not null default true;
 alter table income_sources add column if not exists category text not null default 'General';
 alter table income_sources add column if not exists date timestamptz not null default now();

 create table if not exists recurring_commitments (
   id uuid primary key default gen_random_uuid(),
   user_id uuid not null references auth.users on delete cascade,
   name text not null,
   amount numeric not null,
   due_day int not null check (due_day between 1 and 31),
   category text not null default 'General'
 );

 create table if not exists one_off_costs (
   id uuid primary key default gen_random_uuid(),
   user_id uuid not null references auth.users on delete cascade,
   name text not null,
   amount numeric not null,
   date timestamptz not null
 );

 alter table finances               enable row level security;
 alter table income_sources        enable row level security;
 alter table recurring_commitments  enable row level security;
 alter table one_off_costs          enable row level security;

 drop policy if exists "own finances"       on finances;
 drop policy if exists "own income_sources" on income_sources;
 drop policy if exists "own commitments"    on recurring_commitments;
 drop policy if exists "own one_offs"       on one_off_costs;

 create policy "own finances"       on finances
   for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
 create policy "own income_sources" on income_sources
   for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
 create policy "own commitments"    on recurring_commitments
   for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
 create policy "own one_offs"       on one_off_costs
   for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
 ──────────────────────────────────────────────────────────────────────────
*/
