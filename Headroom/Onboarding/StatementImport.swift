//
//  StatementImport.swift
//  Headroom
//
//  PDF parser for UK bank statements + the full-screen import flow.
//  Priority: PDFKit text extraction with x-coordinate column detection.
//  Fallback: Vision OCR for image-based pages.
//  All parsing is on-device; files are never sent anywhere.
//

import SwiftUI
import PDFKit
@preconcurrency import Vision
import UniformTypeIdentifiers

// MARK: - Domain types

struct ParsedTransaction: Identifiable, Sendable {
    let id: UUID
    let date: Date
    let description: String
    /// Positive = credit (money in), negative = debit (money out).
    let amount: Double
}

struct ParseResult: Sendable {
    let transactions: [ParsedTransaction]
    let closingBalance: Double?
    let warnings: [String]
    /// Calendar months covered, e.g. ["Jan 2026", "Feb 2026"]. Sorted chronologically.
    let monthsRead: [String]
}

enum ParseError: LocalizedError, Equatable {
    case emptyDocument
    case noTransactionsFound

    var errorDescription: String? {
        switch self {
        case .emptyDocument:      return "The PDF appears to be empty or couldn't be read."
        case .noTransactionsFound: return "No transactions found. Make sure this is a bank statement PDF."
        }
    }
}

// MARK: - PDF word with position

struct PDFTextWord: Sendable {
    let text: String
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    var maxX: CGFloat { x + width }
}

// MARK: - PDF column map

struct PDFColumnMap: Sendable {
    let dateMaxX:    CGFloat
    let debitMinX:   CGFloat
    let creditMinX:  CGFloat
    let balanceMinX: CGFloat
}

// MARK: - PDF statement parser

enum PDFStatementParser {

    static func parse(url: URL) async throws -> ParseResult {
        guard let document = PDFDocument(url: url), document.pageCount > 0 else {
            throw ParseError.emptyDocument
        }
        var allLines: [[PDFTextWord]] = []
        for i in 0..<document.pageCount {
            guard let page = document.page(at: i) else { continue }
            let words = await extractWords(from: page)
            allLines.append(contentsOf: groupIntoLines(words))
        }
        guard !allLines.isEmpty else { throw ParseError.emptyDocument }

        let (txs, closingBalance): ([ParsedTransaction], Double?)
        if let colMap = detectColumnMap(from: allLines) {
            (txs, closingBalance) = parseTransactions(from: allLines, columnMap: colMap)
        } else {
            (txs, closingBalance) = textFallbackTransactions(from: allLines)
        }

        let cutoff   = Calendar(identifier: .gregorian)
            .date(byAdding: .month, value: -12, to: Date()) ?? .distantPast
        let filtered = txs.filter { $0.date >= cutoff }
        let dropped  = txs.count - filtered.count
        guard !filtered.isEmpty else { throw ParseError.noTransactionsFound }

        var warnings: [String] = []
        if dropped > 0 {
            warnings.append(
                "\(dropped) transaction\(dropped == 1 ? "" : "s") older than 12 months excluded.")
        }
        return ParseResult(transactions: filtered, closingBalance: closingBalance,
                           warnings: warnings, monthsRead: monthLabels(from: filtered))
    }

    // MARK: Word extraction

    static func extractWords(from page: PDFPage) async -> [PDFTextWord] {
        guard let text = page.string, !text.isEmpty else { return await ocrWords(from: page) }
        let words = pdfKitWords(from: page, text: text)
        return words.count >= 10 ? words : await ocrWords(from: page)
    }

    private static func pdfKitWords(from page: PDFPage, text: String) -> [PDFTextWord] {
        let ns      = text as NSString
        let pattern = try! NSRegularExpression(pattern: "\\S+")
        return pattern.matches(in: text, range: NSRange(location: 0, length: ns.length))
            .compactMap { match -> PDFTextWord? in
                guard let sel = page.selection(for: match.range) else { return nil }
                let bounds = sel.bounds(for: page)
                guard bounds != .null, bounds.width > 0 else { return nil }
                return PDFTextWord(text: ns.substring(with: match.range),
                                   x: bounds.minX, y: bounds.midY, width: bounds.width)
            }
    }

    private static func ocrWords(from page: PDFPage) async -> [PDFTextWord] {
        let pageRect = page.bounds(for: .mediaBox)
        let scale: CGFloat = 2
        let imgSize = CGSize(width: pageRect.width * scale, height: pageRect.height * scale)
        let renderer = UIGraphicsImageRenderer(size: imgSize)
        let img = renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: imgSize))
            ctx.cgContext.translateBy(x: 0, y: imgSize.height)
            ctx.cgContext.scaleBy(x: scale, y: -scale)
            page.draw(with: .mediaBox, to: ctx.cgContext)
        }
        guard let cg = img.cgImage else { return [] }
        return await withCheckedContinuation { cont in
            let req = VNRecognizeTextRequest { req, _ in
                guard let obs = req.results as? [VNRecognizedTextObservation] else {
                    cont.resume(returning: []); return
                }
                let words: [PDFTextWord] = obs.compactMap { ob in
                    guard let cand = ob.topCandidates(1).first else { return nil }
                    let bb = ob.boundingBox
                    return PDFTextWord(text: cand.string,
                                       x: bb.minX  * pageRect.width,
                                       y: bb.midY  * pageRect.height,
                                       width: bb.width * pageRect.width)
                }
                cont.resume(returning: words)
            }
            req.recognitionLevel = .accurate
            req.recognitionLanguages = ["en-GB"]
            DispatchQueue.global(qos: .userInitiated).async {
                try? VNImageRequestHandler(cgImage: cg, options: [:]).perform([req])
            }
        }
    }

    // MARK: Line grouping

    static func groupIntoLines(_ words: [PDFTextWord], tolerance: CGFloat = 5) -> [[PDFTextWord]] {
        guard !words.isEmpty else { return [] }
        let sorted = words.sorted { $0.y > $1.y }
        var lines:   [[PDFTextWord]] = []
        var current: [PDFTextWord]   = [sorted[0]]
        var lineY = sorted[0].y
        for word in sorted.dropFirst() {
            if abs(word.y - lineY) <= tolerance {
                current.append(word)
            } else {
                lines.append(current.sorted { $0.x < $1.x })
                current = [word]; lineY = word.y
            }
        }
        lines.append(current.sorted { $0.x < $1.x })
        return lines
    }

    // MARK: Column map detection

    static func detectColumnMap(from lines: [[PDFTextWord]]) -> PDFColumnMap? {
        for line in lines {
            let lower  = line.map { $0.text.lowercased() }
            let joined = lower.joined(separator: " ")
            guard joined.contains("date"), joined.contains("balance") else { continue }
            guard let dateIdx = lower.firstIndex(where: { $0 == "date" || $0.hasSuffix("date") }),
                  let balIdx  = lower.firstIndex(where: { $0.hasPrefix("balance") }) else { continue }

            let dateWord = line[dateIdx], balWord = line[balIdx]
            guard dateWord.x < balWord.x else { continue }

            let debitTerms  = Set(["out", "debit", "dr", "withdrawal", "withdrawals"])
            let creditTerms = Set(["in", "credit", "cr", "deposit", "deposits"])
            let leadTerms   = Set(["money", "paid", "cash"])

            var debitX: CGFloat?, creditX: CGFloat?
            for i in 0..<lower.count {
                let w = lower[i]
                if debitTerms.contains(w) {
                    let anchor = (i > 0 && leadTerms.contains(lower[i-1])) ? line[i-1] : line[i]
                    debitX = anchor.x
                }
                if creditTerms.contains(w) && w != "in"
                    || (w == "in" && i > 0 && leadTerms.contains(lower[i-1])) {
                    let anchor = (i > 0 && leadTerms.contains(lower[i-1])) ? line[i-1] : line[i]
                    creditX = anchor.x
                }
            }
            if creditX == nil, let inIdx = lower.lastIndex(where: { $0 == "in" }) {
                let inW = line[inIdx]
                if inW.x > (dateWord.maxX + (balWord.x - dateWord.maxX) * 0.35) {
                    creditX = inW.x
                }
            }
            if let dx = debitX, let cx = creditX, dx > cx { swap(&debitX, &creditX) }

            let span = balWord.x - dateWord.maxX
            let dX   = debitX  ?? (dateWord.maxX + span * 0.53)
            let cX   = creditX ?? (dateWord.maxX + span * 0.73)
            return PDFColumnMap(
                dateMaxX:    dateWord.maxX + 10,
                debitMinX:   dX  - 12,
                creditMinX:  cX  - 12,
                balanceMinX: balWord.x - 12)
        }
        return nil
    }

    // MARK: Transaction parsing

    static func parseTransactions(from lines: [[PDFTextWord]],
                                   columnMap m: PDFColumnMap) -> ([ParsedTransaction], Double?) {
        var transactions:   [ParsedTransaction] = []
        var closingBalance: Double?
        var pendingDate:    Date?
        var pendingDesc:    [String] = []
        var pendingAmount:  Double?
        let fmt = DateFormatter(); fmt.locale = Locale(identifier: "en_GB")

        func flush() {
            guard let d = pendingDate, let a = pendingAmount, !pendingDesc.isEmpty else { return }
            transactions.append(ParsedTransaction(id: UUID(), date: d,
                                                   description: pendingDesc.joined(separator: " "),
                                                   amount: a))
            pendingDate = nil; pendingDesc = []; pendingAmount = nil
        }

        for line in lines {
            let datePart   = line.filter { $0.x <  m.dateMaxX  }.map(\.text).joined(separator: " ")
            let descPart   = line.filter { $0.x >= m.dateMaxX  && $0.x < m.debitMinX  }.map(\.text).joined(separator: " ")
            let debitPart  = line.filter { $0.x >= m.debitMinX && $0.x < m.creditMinX }.map(\.text).joined(separator: "")
            let creditPart = line.filter { $0.x >= m.creditMinX && $0.x < m.balanceMinX }.map(\.text).joined(separator: "")
            let balPart    = line.filter { $0.x >= m.balanceMinX }.map(\.text).joined(separator: "")

            if let b = parseAmount(balPart) { closingBalance = b }

            if let date = parseDate(datePart, formatter: fmt), !descPart.isEmpty {
                flush()
                let debit  = parseAmount(debitPart)  ?? 0
                let credit = parseAmount(creditPart) ?? 0
                let amount = credit > 0 ? credit : (debit > 0 ? -debit : 0)
                if amount != 0 {
                    pendingDate = date; pendingAmount = amount; pendingDesc = [descPart]
                }
            } else if pendingDate != nil, !descPart.isEmpty,
                      datePart.trimmingCharacters(in: .whitespaces).isEmpty {
                pendingDesc.append(descPart)
            }
        }
        flush()
        return (transactions, closingBalance)
    }

    // MARK: Text fallback

    private static func textFallbackTransactions(
        from lines: [[PDFTextWord]]) -> ([ParsedTransaction], Double?) {
        var txs: [ParsedTransaction] = []
        var closingBalance: Double?
        let fmt = DateFormatter(); fmt.locale = Locale(identifier: "en_GB")
        let numRE = try! NSRegularExpression(pattern: #"[\d,]+\.\d{2}"#)
        for line in lines {
            let text = line.map(\.text).joined(separator: " ")
            let ns   = text as NSString
            guard let dateRange = text.range(
                of: #"^(\d{2}[/\-\.]\d{2}[/\-\.]\d{2,4}|\d{1,2}\s+[A-Za-z]{3}\s+\d{4})"#,
                options: .regularExpression),
                  let date = parseDate(String(text[dateRange]), formatter: fmt) else { continue }
            let numMatches = numRE.matches(in: text, range: NSRange(location: 0, length: ns.length))
            guard numMatches.count >= 2 else { continue }
            if let last = Double(ns.substring(with: numMatches.last!.range)
                                   .replacingOccurrences(of: ",", with: "")) {
                closingBalance = last
            }
            let amtStr = ns.substring(with: numMatches[numMatches.count - 2].range)
                .replacingOccurrences(of: ",", with: "")
            if let amt = Double(amtStr), amt > 0 {
                let dateEnd  = text.index(text.startIndex, offsetBy: text[dateRange].count)
                let amtStart = text.index(text.startIndex,
                                          offsetBy: numMatches[numMatches.count - 2].range.location)
                if dateEnd < amtStart {
                    let desc = String(text[dateEnd..<amtStart]).trimmingCharacters(in: .whitespaces)
                    if !desc.isEmpty {
                        txs.append(ParsedTransaction(id: UUID(), date: date,
                                                      description: desc, amount: -amt))
                    }
                }
            }
        }
        return (txs, closingBalance)
    }

    // MARK: Helpers

    static func monthLabels(from txs: [ParsedTransaction]) -> [String] {
        let cal = Calendar(identifier: .gregorian)
        let fmt = DateFormatter(); fmt.locale = Locale(identifier: "en_GB"); fmt.dateFormat = "MMM yyyy"
        let starts = Set(txs.map { tx -> Date in
            var c = cal.dateComponents([.year, .month], from: tx.date); c.day = 1
            return cal.date(from: c) ?? tx.date
        })
        return starts.sorted().map { fmt.string(from: $0) }
    }

    static func parseDate(_ raw: String, formatter: DateFormatter) -> Date? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        formatter.locale = Locale(identifier: "en_GB")
        for fmt in ["dd/MM/yyyy","yyyy-MM-dd","dd MMM yyyy","d MMM yyyy",
                    "dd-MM-yyyy","d/M/yyyy","MM/dd/yyyy","dd/MM/yy",
                    "dd.MM.yyyy","yyyy/MM/dd","d MMM yy"] {
            formatter.dateFormat = fmt
            if let d = formatter.date(from: s) { return d }
        }
        return nil
    }

    static func parseAmount(_ raw: String) -> Double? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        let isNeg = s.hasPrefix("-") || s.hasPrefix("\u{2212}")
                 || (s.hasPrefix("(") && s.hasSuffix(")"))
        s = s
            .replacingOccurrences(of: "(", with: "").replacingOccurrences(of: ")", with: "")
            .replacingOccurrences(of: "\u{2212}", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "£", with: "").replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: "€", with: "").replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespaces)
        guard let v = Double(s), v >= 0 else { return nil }
        return isNeg ? -v : v
    }
}

// MARK: - Statement merger

enum StatementMerger {

    static func merge(_ results: [ParseResult]) -> ParseResult {
        guard !results.isEmpty else {
            return ParseResult(transactions: [], closingBalance: nil, warnings: [], monthsRead: [])
        }
        let allTxs   = results.flatMap(\.transactions)
        let deduped  = deduplicate(allTxs).sorted { $0.date < $1.date }
        let cutoff   = Calendar(identifier: .gregorian)
            .date(byAdding: .month, value: -12, to: Date()) ?? .distantPast
        let filtered = deduped.filter { $0.date >= cutoff }
        let dropped  = deduped.count - filtered.count

        var warnings = results.flatMap(\.warnings)
        if dropped > 0 {
            warnings.append("\(dropped) transaction\(dropped == 1 ? "" : "s") older than 12 months excluded.")
        }
        return ParseResult(transactions: filtered,
                           closingBalance: results.compactMap(\.closingBalance).last,
                           warnings: warnings,
                           monthsRead: PDFStatementParser.monthLabels(from: filtered))
    }

    private static func deduplicate(_ txs: [ParsedTransaction]) -> [ParsedTransaction] {
        var seen = Set<String>()
        return txs.filter { seen.insert(dedupeKey($0)).inserted }
    }

    static func dedupeKey(_ tx: ParsedTransaction) -> String {
        let cal = Calendar(identifier: .gregorian)
        let c   = cal.dateComponents([.year, .month, .day], from: tx.date)
        let dateKey = "\(c.year ?? 0)-\(String(format: "%02d", c.month ?? 0))-\(String(format: "%02d", c.day ?? 0))"
        let amtKey  = String(format: "%.2f", tx.amount)
        let descKey = String(tx.description.uppercased()
            .filter { $0.isLetter || $0.isNumber }.prefix(25))
        return "\(dateKey)|\(amtKey)|\(descKey)"
    }
}

// MARK: - Shredder animation

struct ShredderAnimationView: View {
    var onComplete: () -> Void

    @State private var paperY: CGFloat = -180
    @State private var paperOpacity: Double = 1
    @State private var stripsVisible = false
    @State private var containerOpacity: Double = 1

    var body: some View {
        ZStack {
            Color.black.opacity(0.88 * containerOpacity)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Paper document sliding into shredder
                paperView
                    .offset(y: paperY)
                    .opacity(paperOpacity)

                // Shredder body
                shredderBody

                // Falling strips
                if stripsVisible {
                    stripsView
                        .transition(.opacity)
                }

                Spacer()
            }
            .opacity(containerOpacity)
        }
        .onAppear(perform: startAnimation)
    }

    private var paperView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white)
                .frame(width: 70, height: 92)
                .shadow(color: .black.opacity(0.3), radius: 16, y: 6)

            VStack(spacing: 5) {
                ForEach(0..<5) { _ in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.black.opacity(0.1))
                        .frame(width: 42, height: 5)
                }
            }

            Image(systemName: "doc.text")
                .font(.system(size: 22))
                .foregroundStyle(Color.black.opacity(0.18))
        }
    }

    private var shredderBody: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color(white: 0.20))
                .frame(width: 116, height: 26)
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Color.black.opacity(0.55))
                .frame(width: 68, height: 5)
        }
    }

    private var stripsView: some View {
        let palette: [Color] = [
            .fbPositive.opacity(0.6),
            Color(white: 0.88),
            Color(white: 0.96),
            .fbSoftText.opacity(0.35),
            Color(white: 0.80),
            .fbPositive.opacity(0.4)
        ]
        let lengths: [CGFloat] = [68, 82, 52, 76, 60, 90, 55, 72, 48, 85, 63, 44]

        return HStack(spacing: 3) {
            ForEach(0..<12, id: \.self) { i in
                StripView(
                    color: palette[i % palette.count],
                    targetLength: lengths[i % lengths.count],
                    delay: Double(i) * 0.045)
            }
        }
        .frame(width: 116)
    }

    private func startAnimation() {
        // Paper slides into shredder
        withAnimation(.easeIn(duration: 0.55)) { paperY = 0 }

        // Paper disappears, strips appear
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.60) {
            withAnimation(.easeOut(duration: 0.15)) { paperOpacity = 0 }
            withAnimation { stripsVisible = true }
        }

        // Fade everything out
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.80) {
            withAnimation(.easeIn(duration: 0.50)) { containerOpacity = 0 }
        }

        // Complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.40) {
            onComplete()
        }
    }
}

private struct StripView: View {
    let color: Color
    let targetLength: CGFloat
    let delay: Double

    @State private var length: CGFloat = 0
    @State private var opacity: Double = 1

    var body: some View {
        RoundedRectangle(cornerRadius: 1.5)
            .fill(color)
            .frame(width: 6, height: length)
            .opacity(opacity)
            .onAppear {
                withAnimation(.easeOut(duration: 0.48).delay(delay)) {
                    length = targetLength
                }
                withAnimation(.easeIn(duration: 0.35).delay(delay + 0.55)) {
                    opacity = 0
                }
            }
    }
}

// MARK: - Import flow (full-screen)

struct StatementImportFlow: View {
    @Bindable var store: HeadroomStore
    let onDone: () -> Void

    enum ImportStep { case picker, loading, reviewing, error(String) }

    @State private var step: ImportStep = .picker
    @State private var showFilePicker = false
    @State private var pickedURLs: [URL] = []
    @State private var loadingMessage = "Reading statements…"
    @State private var detectionResult: DetectionResult?
    @State private var suggestedBalance: Double?
    @State private var parseWarnings: [String] = []
    @State private var monthsRead:    [String] = []
    @State private var showShredder = false

    private let labeler = MerchantLabeler()

    var body: some View {
        ZStack {
            FBBackground()
            FBBlobBackground()

            VStack(spacing: 0) {
                closeBar

                switch step {
                case .picker:
                    pickerContent
                        .transition(.asymmetric(insertion: .opacity, removal: .opacity))
                case .loading:
                    loadingContent
                        .transition(.opacity)
                case .reviewing:
                    reviewContent
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal:   .opacity))
                case .error(let msg):
                    errorContent(msg)
                        .transition(.opacity)
                }
            }
            .animation(.spring(response: 0.40, dampingFraction: 0.88), value: stepID)

            if showShredder {
                ShredderAnimationView { finalize() }
                    .transition(.opacity)
                    .zIndex(100)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: showShredder)
        .ignoresSafeArea(edges: .bottom)
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: true,
            onCompletion: handleFileSelection)
    }

    // MARK: Bars

    private var closeBar: some View {
        HStack {
            Spacer()
            Button(action: onDone) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.fbSoftText)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color.fbInk.opacity(0.08)))
                    .overlay(Circle().strokeBorder(Color.fbHairline, lineWidth: 0.5))
            }
            .buttonStyle(.pressable)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 4)
    }

    // MARK: Picker

    private var pickerContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Large title
                VStack(alignment: .leading, spacing: 6) {
                    Text("Import")
                        .font(.fbHeader(36))
                        .tracking(-1)
                        .foregroundStyle(Color.fbInk)
                    Text("statements")
                        .font(.fbHeader(36))
                        .tracking(-1)
                        .foregroundStyle(Color.fbInk)
                }

                // Privacy badge
                HStack(spacing: 10) {
                    Image(systemName: "lock.shield")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.fbSoftText)
                    Text("Your statements never leave your phone.")
                        .font(.fbBody(13, weight: .medium))
                        .foregroundStyle(Color.fbSoftText)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.fbInk.opacity(0.05)))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.fbHairline, lineWidth: 1))

                Text("Export monthly PDFs from your bank app, then choose up to 12 files. Headroom reads them on-device and detects your recurring payments — nothing is uploaded.")
                    .font(.fbBody(14))
                    .foregroundStyle(Color.fbSoftText)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 5) {
                    Text("WORKS WITH")
                        .font(.fbBody(10, weight: .semibold))
                        .tracking(1.4)
                        .foregroundStyle(Color.fbSoftText)
                    Text("Lloyds · Barclays · HSBC · NatWest · Halifax · Santander · Nationwide · First Direct · Monzo · Starling · Chase")
                        .font(.fbBody(13))
                        .foregroundStyle(Color.fbSoftText)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
        .scrollEdgeEffectStyle(.automatic, for: .vertical)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 20) {
                FBPrimaryButton(label: "Choose PDF files") { showFilePicker = true }
                Button(action: onDone) {
                    Text("Not now")
                        .font(.fbBody(14))
                        .foregroundStyle(Color.fbSoftText)
                }
                .buttonStyle(.pressable)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .background(
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .ignoresSafeArea()
            )
        }
    }

    // MARK: Loading

    private var loadingContent: some View {
        VStack(spacing: 20) {
            Spacer()
            ProgressView()
                .tint(Color.fbPositive)
                .scaleEffect(1.5)
            Text(loadingMessage)
                .font(.fbBody(15))
                .foregroundStyle(Color.fbSoftText)
                .multilineTextAlignment(.center)
                .animation(.default, value: loadingMessage)
            Spacer()
        }
        .padding(.horizontal, 40)
    }

    // MARK: Review

    private var reviewContent: some View {
        Group {
            if let result = detectionResult {
                ReviewDetectedView(
                    store: store,
                    result: result,
                    suggestedBalance: suggestedBalance,
                    warnings: parseWarnings,
                    monthsRead: monthsRead,
                    onConfirm: { showShredder = true },
                    onCancel: { step = .picker }
                )
            }
        }
    }

    // MARK: Error

    private func errorContent(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Import failed")
                .font(.fbHeader(28))
                .tracking(-0.5)
                .foregroundStyle(Color.fbInk)
                .padding(.horizontal, 24)
                .padding(.top, 16)

            Text(message)
                .font(.fbBody(14))
                .foregroundStyle(Color.fbSoftText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)

            Spacer()
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                FBPrimaryButton(label: "Try other files") { step = .picker }
                Button(action: onDone) {
                    Text("Cancel")
                        .font(.fbBody(14))
                        .foregroundStyle(Color.fbSoftText)
                }
                .buttonStyle(.pressable)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
    }

    // MARK: File handling

    private func handleFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let e):
            step = .error("Couldn't open the files: \(e.localizedDescription)")
        case .success(let urls):
            guard !urls.isEmpty else { return }
            pickedURLs = urls; step = .loading
            Task { await parseAndDetect(urls: urls) }
        }
    }

    private func parseAndDetect(urls: [URL]) async {
        var results:  [ParseResult] = []
        var warnings: [String]      = []

        for (i, url) in urls.enumerated() {
            loadingMessage = urls.count > 1
                ? "Reading file \(i + 1) of \(urls.count)…"
                : "Reading your statement…"

            let accessed = url.startAccessingSecurityScopedResource()
            do {
                results.append(try await PDFStatementParser.parse(url: url))
            } catch {
                warnings.append("'\(url.deletingPathExtension().lastPathComponent)': \(error.localizedDescription)")
            }
            if accessed { url.stopAccessingSecurityScopedResource() }
        }

        if results.isEmpty {
            step = .error(warnings.first ?? "None of the selected files could be read.")
            return
        }

        loadingMessage = "Merging transactions…"
        var merged = StatementMerger.merge(results)
        if !warnings.isEmpty {
            merged = ParseResult(transactions: merged.transactions,
                                 closingBalance: merged.closingBalance,
                                 warnings: warnings + merged.warnings,
                                 monthsRead: merged.monthsRead)
        }

        loadingMessage = "Detecting recurring payments…"
        let detected = RecurrenceDetector.detect(from: merged.transactions)

        loadingMessage = "Labelling merchants…"
        let keys = Array(Set(detected.commitments.map(\.normalisedKey) +
                              (detected.income.map { [$0.normalisedKey] } ?? [])))
        let labels = await labeler.label(keys: keys)

        var labelled = detected
        labelled = DetectionResult(
            commitments: labelled.commitments.map { c in
                var m = c
                if let l = labels[c.normalisedKey] { m.displayName = l.displayName; m.category = l.category }
                return m
            },
            income: labelled.income.map { i in
                var m = i
                if let l = labels[i.normalisedKey] { m.displayName = l.displayName }
                return m
            }
        )

        detectionResult  = labelled
        suggestedBalance = merged.closingBalance
        parseWarnings    = merged.warnings
        monthsRead       = merged.monthsRead
        step             = .reviewing
    }

    // MARK: Finalise

    private func finalize() {
        detectionResult = nil; parseWarnings = []; monthsRead = []
        for url in pickedURLs {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            let tmp  = FileManager.default.temporaryDirectory
            let inSandbox = docs.map { url.path.hasPrefix($0.path) } ?? false
                         || url.path.hasPrefix(tmp.path)
            if inSandbox { try? FileManager.default.removeItem(at: url) }
        }
        pickedURLs = []
        onDone()
    }

    private var stepID: Int {
        switch step {
        case .picker: return 0; case .loading: return 1
        case .reviewing: return 2; case .error: return 3
        }
    }
}

// MARK: - Preview

#Preview("Import — picker") {
    StatementImportFlow(store: HeadroomStore(finances: .empty), onDone: {})
        .preferredColorScheme(.dark)
}

#Preview("Shredder") {
    ZStack {
        Color.black.ignoresSafeArea()
        ShredderAnimationView(onComplete: {})
    }
}
