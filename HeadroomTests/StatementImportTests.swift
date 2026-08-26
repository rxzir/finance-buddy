//
//  StatementImportTests.swift
//  Financial buddyTests
//
//  Unit tests for PDFStatementParser, StatementMerger, and RecurrenceDetector.
//  Nothing here touches UI, the on-device model, PDFKit, or Vision —
//  all PDF parser methods are tested by injecting mock [PDFTextWord] arrays.
//

import Foundation
import Testing
@testable import Financial_buddy

// MARK: - Helpers shared across test structs

private func makeTx(date: Date, desc: String, amount: Double) -> ParsedTransaction {
    ParsedTransaction(id: UUID(), date: date, description: desc, amount: amount)
}

private func dateOffset(months: Int, day: Int) -> Date {
    let cal = Calendar(identifier: .gregorian)
    var c = cal.dateComponents([.year, .month], from: Date())
    c.month! -= months
    c.day = day
    return cal.date(from: c) ?? Date()
}

// MARK: - PDF parser tests

struct PDFParserTests {

    // A Lloyds-style header row:
    //   Date  Transaction Description  Money out  Money in  Balance
    private let lloydHeader: [PDFTextWord] = [
        PDFTextWord(text: "Date",        x:  50, y: 700, width: 25),
        PDFTextWord(text: "Transaction", x: 110, y: 700, width: 65),
        PDFTextWord(text: "Description", x: 180, y: 700, width: 65),
        PDFTextWord(text: "Money",       x: 305, y: 700, width: 35),
        PDFTextWord(text: "out",         x: 345, y: 700, width: 15),
        PDFTextWord(text: "Money",       x: 383, y: 700, width: 35),
        PDFTextWord(text: "in",          x: 423, y: 700, width: 10),
        PDFTextWord(text: "Balance",     x: 455, y: 700, width: 40),
    ]

    // MARK: Column map detection

    @Test func detectsLloydsStyleColumns() throws {
        let map = try #require(PDFStatementParser.detectColumnMap(from: [lloydHeader]))
        // Date column ends well before the description
        #expect(map.dateMaxX < 110)
        // Debit column starts around the "Money" word at x=305 (±20)
        #expect(map.debitMinX > 280 && map.debitMinX < 325)
        // Credit column starts around the second "Money" at x=383 (±20)
        #expect(map.creditMinX > 360 && map.creditMinX < 405)
        // Balance column starts near the "Balance" word at x=455 (±15)
        #expect(map.balanceMinX > 438 && map.balanceMinX < 470)
        // All boundaries must increase left→right
        #expect(map.dateMaxX < map.debitMinX)
        #expect(map.debitMinX < map.creditMinX)
        #expect(map.creditMinX < map.balanceMinX)
    }

    @Test func noColumnMapWhenNoDateWord() {
        let headerNoDate: [PDFTextWord] = [
            PDFTextWord(text: "Description", x: 110, y: 700, width: 65),
            PDFTextWord(text: "Balance",     x: 455, y: 700, width: 40),
        ]
        let map = PDFStatementParser.detectColumnMap(from: [headerNoDate])
        #expect(map == nil)
    }

    // MARK: Line grouping

    @Test func groupsWordsOnSameLine() {
        let words: [PDFTextWord] = [
            PDFTextWord(text: "A", x: 10, y: 100.0, width: 8),
            PDFTextWord(text: "B", x: 25, y: 100.3, width: 8),  // same line (Δy < 5)
            PDFTextWord(text: "C", x: 10, y: 80.0,  width: 8),  // new line
        ]
        let lines = PDFStatementParser.groupIntoLines(words)
        #expect(lines.count == 2)
        #expect(lines[0].count == 2)   // A, B on the first (higher-Y) line
        #expect(lines[1].count == 1)   // C on the second line
    }

    @Test func lineWordsAreSortedLeftToRight() {
        let words: [PDFTextWord] = [
            PDFTextWord(text: "Z", x: 200, y: 100, width: 10),
            PDFTextWord(text: "A", x:  50, y: 100, width: 10),
            PDFTextWord(text: "M", x: 120, y: 100, width: 10),
        ]
        let lines = PDFStatementParser.groupIntoLines(words)
        let texts = lines[0].map(\.text)
        #expect(texts == ["A", "M", "Z"])
    }

    // MARK: Transaction parsing

    @Test func parsesDebitTransaction() throws {
        let map = try #require(PDFStatementParser.detectColumnMap(from: [lloydHeader]))
        // A single debit transaction row
        let txLine: [PDFTextWord] = [
            PDFTextWord(text: "05/01/2026", x:  50, y: 650, width: 55),
            PDFTextWord(text: "SPOTIFY",    x: 120, y: 650, width: 45),
            PDFTextWord(text: "PREMIUM",    x: 175, y: 650, width: 50),
            PDFTextWord(text: "DD",         x: 230, y: 650, width: 15),
            PDFTextWord(text: "11.99",      x: 318, y: 650, width: 25),  // debit column
            PDFTextWord(text: "1228.02",    x: 458, y: 650, width: 40),  // balance
        ]
        let (txs, _) = PDFStatementParser.parseTransactions(from: [lloydHeader, txLine], columnMap: map)
        let tx = try #require(txs.first)
        #expect(tx.amount < 0)
        #expect(abs(tx.amount + 11.99) < 0.01)
        #expect(tx.description.contains("SPOTIFY"))
    }

    @Test func parsesCreditTransaction() throws {
        let map = try #require(PDFStatementParser.detectColumnMap(from: [lloydHeader]))
        let txLine: [PDFTextWord] = [
            PDFTextWord(text: "28/07/2026", x:  50, y: 650, width: 55),
            PDFTextWord(text: "EMPLOYER",   x: 120, y: 650, width: 55),
            PDFTextWord(text: "SALARY",     x: 180, y: 650, width: 40),
            PDFTextWord(text: "2400.00",    x: 390, y: 650, width: 40),  // credit column
            PDFTextWord(text: "3628.02",    x: 458, y: 650, width: 40),  // balance
        ]
        let (txs, closing) = PDFStatementParser.parseTransactions(from: [lloydHeader, txLine], columnMap: map)
        let tx = try #require(txs.first)
        #expect(tx.amount > 0)
        #expect(abs(tx.amount - 2400.00) < 0.01)
        #expect(tx.description.contains("EMPLOYER"))
        #expect((closing ?? 0) > 0)
    }

    @Test func joinsMultiLineDescription() throws {
        let map = try #require(PDFStatementParser.detectColumnMap(from: [lloydHeader]))
        // First line: has date + first part of description
        let line1: [PDFTextWord] = [
            PDFTextWord(text: "10/06/2026", x:  50, y: 640, width: 55),
            PDFTextWord(text: "PAYPAL",     x: 120, y: 640, width: 40),
            PDFTextWord(text: "24.99",      x: 318, y: 640, width: 25),
            PDFTextWord(text: "1200.00",    x: 458, y: 640, width: 40),
        ]
        // Second line: continuation — no date, just more description
        let line2: [PDFTextWord] = [
            PDFTextWord(text: "*DIGITALRIVER",  x: 120, y: 620, width: 80),
            PDFTextWord(text: "IE",              x: 205, y: 620, width: 12),
        ]
        let (txs, _) = PDFStatementParser.parseTransactions(
            from: [lloydHeader, line1, line2], columnMap: map)
        let tx = try #require(txs.first)
        #expect(tx.description.contains("PAYPAL"))
        #expect(tx.description.contains("DIGITALRIVER"))
    }

    // MARK: Amount parsing

    @Test func parseAmountHandlesUnicodeMinus() {
        let v = PDFStatementParser.parseAmount("\u{2212}11.99")
        #expect(v != nil)
        #expect(v! < 0)
    }

    @Test func parseAmountHandlesBrackets() {
        let v = PDFStatementParser.parseAmount("(99.00)")
        #expect(v != nil)
        #expect(v! < 0)
    }

    @Test func parseAmountHandlesCurrencySymbol() {
        let v = PDFStatementParser.parseAmount("£1,234.56")
        #expect(v != nil)
        #expect(abs(v! - 1234.56) < 0.01)
    }

    // MARK: Date parsing

    @Test func parseDateBritishFormat() {
        let fmt = DateFormatter()
        let d = PDFStatementParser.parseDate("15/07/2026", formatter: fmt)
        #expect(d != nil)
        let cal = Calendar(identifier: .gregorian)
        #expect(cal.component(.day,   from: d!) == 15)
        #expect(cal.component(.month, from: d!) == 7)
        #expect(cal.component(.year,  from: d!) == 2026)
    }

    @Test func parseDateISOFormat() {
        let fmt = DateFormatter()
        let d = PDFStatementParser.parseDate("2026-07-15", formatter: fmt)
        #expect(d != nil)
        let cal = Calendar(identifier: .gregorian)
        #expect(cal.component(.month, from: d!) == 7)
        #expect(cal.component(.day,   from: d!) == 15)
    }

    @Test func parseDateVerboseFormat() {
        let fmt = DateFormatter()
        let d = PDFStatementParser.parseDate("15 Jul 2026", formatter: fmt)
        #expect(d != nil)
        let cal = Calendar(identifier: .gregorian)
        #expect(cal.component(.month, from: d!) == 7)
    }
}

// MARK: - Merger tests

struct StatementMergerTests {

    @Test func deduplicatesOverlappingRows() {
        let date = dateOffset(months: 1, day: 10)
        let tx   = makeTx(date: date, desc: "SPOTIFY PREMIUM DD", amount: -11.99)

        let r1 = ParseResult(transactions: [tx], closingBalance: 500,
                             warnings: [], monthsRead: ["Jun 2026"])
        let r2 = ParseResult(transactions: [tx], closingBalance: 490,
                             warnings: [], monthsRead: ["Jun 2026"])

        let merged = StatementMerger.merge([r1, r2])
        // Duplicate row must be removed — only one Spotify
        #expect(merged.transactions.count == 1)
    }

    @Test func mergesMonthLabels() {
        let r1 = ParseResult(
            transactions: [makeTx(date: dateOffset(months: 2, day: 1), desc: "A", amount: -10)],
            closingBalance: nil, warnings: [], monthsRead: ["May 2026"])
        let r2 = ParseResult(
            transactions: [makeTx(date: dateOffset(months: 1, day: 1), desc: "B", amount: -10)],
            closingBalance: nil, warnings: [], monthsRead: ["Jun 2026"])

        let merged = StatementMerger.merge([r1, r2])
        #expect(merged.monthsRead.count == 2)
        // Both months must appear in the merged result
        #expect(merged.monthsRead.contains(where: { $0.contains("May") }))
        #expect(merged.monthsRead.contains(where: { $0.contains("Jun") }))
    }

    @Test func mergesNonOverlappingTransactions() {
        let txs1 = (1...3).map { makeTx(date: dateOffset(months: 2, day: $0), desc: "X", amount: -10) }
        let txs2 = (1...3).map { makeTx(date: dateOffset(months: 1, day: $0), desc: "Y", amount: -20) }

        let r1 = ParseResult(transactions: txs1, closingBalance: nil, warnings: [], monthsRead: [])
        let r2 = ParseResult(transactions: txs2, closingBalance: nil, warnings: [], monthsRead: [])

        let merged = StatementMerger.merge([r1, r2])
        // All 6 distinct transactions should survive dedup
        #expect(merged.transactions.count == 6)
    }

    @Test func dedupeKeyIsStable() {
        let date = dateOffset(months: 1, day: 15)
        let tx   = makeTx(date: date, desc: "NETFLIX.COM 123456", amount: -17.99)
        let key1 = StatementMerger.dedupeKey(tx)
        let key2 = StatementMerger.dedupeKey(tx)
        #expect(key1 == key2)
    }

    @Test func emptyInputReturnsEmpty() {
        let merged = StatementMerger.merge([])
        #expect(merged.transactions.isEmpty)
        #expect(merged.monthsRead.isEmpty)
    }

    @Test func usesLastClosingBalance() {
        let r1 = ParseResult(transactions: [makeTx(date: dateOffset(months: 2, day: 1),
                                                    desc: "A", amount: -10)],
                             closingBalance: 1000, warnings: [], monthsRead: [])
        let r2 = ParseResult(transactions: [makeTx(date: dateOffset(months: 1, day: 1),
                                                    desc: "B", amount: -10)],
                             closingBalance: 2000, warnings: [], monthsRead: [])
        let merged = StatementMerger.merge([r1, r2])
        #expect(merged.closingBalance == 2000)
    }
}

// MARK: - RecurrenceDetector tests

struct RecurrenceDetectorTests {

    private let cal = Calendar(identifier: .gregorian)

    private func tx(date: Date, desc: String, amount: Double) -> ParsedTransaction {
        ParsedTransaction(id: UUID(), date: date, description: desc, amount: amount)
    }

    private func daysAgo(_ n: Int) -> Date {
        cal.date(byAdding: .day, value: -n, to: cal.startOfDay(for: Date())) ?? Date()
    }

    private func monthsAgo(_ m: Int, day: Int) -> Date {
        var c = cal.dateComponents([.year, .month], from: Date())
        c.month! -= m
        c.day = day
        return cal.date(from: c) ?? Date()
    }

    // MARK: Normalisation

    @Test func normalisationStripsDigitsAndNoise() {
        let raw  = "SPOTIFY MUSIC 123456 CARD 4242 15/01/25 LTD UK"
        let norm = RecurrenceDetector.normalise(raw)
        #expect(!norm.contains("123456"))
        #expect(!norm.contains("4242"))
        #expect(!norm.contains("15/01"))
        #expect(!norm.contains("LTD"))
        #expect(norm.contains("SPOTIFY"))
    }

    @Test func normalisationNoisyDescriptionMatchesClean() {
        // 3-digit store number "001" and date "01/05/25" must both be stripped
        let noisy = RecurrenceDetector.normalise("SPOTIFY PREMIUM 001 DD 01/05/25")
        let clean = RecurrenceDetector.normalise("SPOTIFY PREMIUM")
        #expect(noisy == clean)
    }

    // MARK: Monthly recurring (Spotify)

    @Test func detectsMonthlySpotify() {
        let txs: [ParsedTransaction] = [
            tx(date: monthsAgo(3, day: 4), desc: "SPOTIFY PREMIUM DD", amount: -11.99),
            tx(date: monthsAgo(2, day: 4), desc: "SPOTIFY PREMIUM DD", amount: -11.99),
            tx(date: monthsAgo(1, day: 4), desc: "SPOTIFY PREMIUM DD", amount: -11.99),
        ]
        let result = RecurrenceDetector.detect(from: txs)
        #expect(result.commitments.count == 1)
        let c = result.commitments[0]
        #expect(c.cadence == .monthly)
        #expect(c.confidence == .high)
        #expect(abs(c.amount - 11.99) < 0.01)
        #expect(c.modalDueDay == 4)
    }

    // MARK: Four-weekly

    @Test func detectsFourWeekly() {
        // every 28 days
        let base = daysAgo(84)
        let txs: [ParsedTransaction] = [
            tx(date: base,                    desc: "FOUR WEEKLY PAYMENT", amount: -100),
            tx(date: cal.date(byAdding: .day, value: 28,  to: base) ?? base, desc: "FOUR WEEKLY PAYMENT", amount: -100),
            tx(date: cal.date(byAdding: .day, value: 56,  to: base) ?? base, desc: "FOUR WEEKLY PAYMENT", amount: -100),
            tx(date: cal.date(byAdding: .day, value: 84,  to: base) ?? base, desc: "FOUR WEEKLY PAYMENT", amount: -100),
        ]
        let result = RecurrenceDetector.detect(from: txs)
        let match = result.commitments.first { $0.cadence == .fourWeekly }
        #expect(match != nil)
    }

    // MARK: Annual single-hit → LOW confidence

    @Test func annualSingleHitIsLowConfidence() {
        let txs: [ParsedTransaction] = [
            tx(date: monthsAgo(11, day: 10), desc: "ANNUAL INSURANCE RENEWAL", amount: -450),
        ]
        let result = RecurrenceDetector.detect(from: txs)
        let annual = result.commitments.first { $0.cadence == .annual }
        #expect(annual != nil)
        #expect(annual?.confidence == .low)
    }

    // MARK: Salary credit detection
    // Use day 15 each month so gaps (30-31 d) land in the monthly range (28-31 d)
    // and not in the overlapping fourWeekly range (26-30 d).

    @Test func detectsSalaryCredit() {
        let txs: [ParsedTransaction] = [
            tx(date: monthsAgo(2, day: 15), desc: "EMPLOYER LTD SALARY BACS", amount: 2400),
            tx(date: monthsAgo(1, day: 15), desc: "EMPLOYER LTD SALARY BACS", amount: 2400),
            tx(date: monthsAgo(0, day: 15), desc: "EMPLOYER LTD SALARY BACS", amount: 2400),
        ]
        let result = RecurrenceDetector.detect(from: txs)
        #expect(result.income != nil)
        #expect(abs((result.income?.amount ?? 0) - 2400) < 0.01)
        #expect(result.income?.cadence == .monthly)
    }

    // MARK: Amount drift within 5 % still clusters

    @Test func amountDriftWithin5PercentClusters() {
        let txs: [ParsedTransaction] = [
            tx(date: monthsAgo(3, day: 15), desc: "ELECTRICITY DD", amount: -80.00),
            tx(date: monthsAgo(2, day: 15), desc: "ELECTRICITY DD", amount: -82.50),  // +3.1 %
            tx(date: monthsAgo(1, day: 15), desc: "ELECTRICITY DD", amount: -77.60),  // −3.0 %
        ]
        let result = RecurrenceDetector.detect(from: txs)
        #expect(result.commitments.count == 1)
        #expect(result.commitments[0].cadence == .monthly)
    }

    // MARK: Noisy description matches normalised

    @Test func noisyDescriptionsClusterTogether() {
        let txs: [ParsedTransaction] = [
            tx(date: monthsAgo(3, day: 1), desc: "AMAZON PRIME 123456 DD 01/03/25", amount: -8.99),
            tx(date: monthsAgo(2, day: 1), desc: "AMAZON PRIME 654321 DD 01/04/25", amount: -8.99),
            tx(date: monthsAgo(1, day: 1), desc: "AMAZON PRIME 999999 DD 01/05/25", amount: -8.99),
        ]
        let result = RecurrenceDetector.detect(from: txs)
        #expect(result.commitments.count == 1)
        #expect(result.commitments[0].occurrenceDates.count == 3)
    }

    // MARK: Transfers are ignored
    // Use monthsAgo(0, day: 4) for the third Spotify so all three fall on the 4th
    // of consecutive months, giving 30-31 d gaps (monthly cadence).

    @Test func internalTransfersIgnored() {
        let txs: [ParsedTransaction] = [
            tx(date: monthsAgo(2, day: 1), desc: "TRANSFER TO SAVINGS", amount: -200),
            tx(date: monthsAgo(1, day: 1), desc: "TRANSFER TO SAVINGS", amount: -200),
            tx(date: daysAgo(30),           desc: "TRANSFER TO SAVINGS", amount: -200),
            tx(date: monthsAgo(2, day: 4), desc: "SPOTIFY PREMIUM", amount: -11.99),
            tx(date: monthsAgo(1, day: 4), desc: "SPOTIFY PREMIUM", amount: -11.99),
            tx(date: monthsAgo(0, day: 4), desc: "SPOTIFY PREMIUM", amount: -11.99),
        ]
        let result = RecurrenceDetector.detect(from: txs)
        // Only Spotify; transfer cluster must be filtered out
        #expect(result.commitments.allSatisfy { !$0.normalisedKey.contains("TRANSFER") })
        #expect(result.commitments.count == 1)
    }

    // MARK: Minimum occurrence rules

    @Test func monthlyRequiresThreeOccurrences() {
        // Only 2 monthly occurrences — should NOT appear
        let txs: [ParsedTransaction] = [
            tx(date: monthsAgo(2, day: 10), desc: "NEW SUBSCRIPTION", amount: -9.99),
            tx(date: monthsAgo(1, day: 10), desc: "NEW SUBSCRIPTION", amount: -9.99),
        ]
        let result = RecurrenceDetector.detect(from: txs)
        let match = result.commitments.first { $0.normalisedKey.contains("NEW") }
        #expect(match == nil)
    }

    @Test func quarterlyRequiresTwoOccurrences() {
        // Quarterly: gap ~91 days, 2 occurrences → should appear
        let txs: [ParsedTransaction] = [
            tx(date: daysAgo(91), desc: "QUARTERLY FEE", amount: -30),
            tx(date: daysAgo(0),  desc: "QUARTERLY FEE", amount: -30),
        ]
        let result = RecurrenceDetector.detect(from: txs)
        let match = result.commitments.first { $0.cadence == .quarterly }
        #expect(match != nil)
    }
}
