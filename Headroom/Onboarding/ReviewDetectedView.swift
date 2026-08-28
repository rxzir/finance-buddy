//
//  ReviewDetectedView.swift
//  Headroom
//
//  Two-step full-height review: Income → Regular bills.
//  Embedded inside StatementImportFlow — no modal chrome here.
//

import SwiftUI

// MARK: - Review item

struct ReviewItem: Identifiable, Equatable {
    let id: UUID
    var isIncluded: Bool
    var displayName: String
    var category: String
    var amount: Double
    var modalDueDay: Int
    let cadence: Cadence
    let confidence: DetectionConfidence
    let occurrenceDates: [Date]
    var isIncome: Bool
    var nextPayday: Date?
}

// MARK: - Checkbox

private struct FBCheckbox: View {
    @Binding var isOn: Bool

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) { isOn.toggle() }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(isOn ? Color.fbPositive : Color.fbHairline, lineWidth: 1.5)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(isOn ? Color.fbPositive.opacity(0.15) : Color.clear)
                    )
                    .frame(width: 22, height: 22)
                if isOn {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.fbPositive)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Main review screen

struct ReviewDetectedView: View {
    @Bindable var store: HeadroomStore
    let result: DetectionResult
    var suggestedBalance: Double?
    var warnings: [String] = []
    var monthsRead: [String] = []
    let onConfirm: () -> Void
    let onCancel: () -> Void

    private var monthsImported: Int { monthsRead.count }

    @State private var reviewStep = 0
    @State private var items: [ReviewItem] = []
    @State private var incomeItem: ReviewItem?
    @State private var editingItem: ReviewItem?
    @State private var showManualAdd = false
    @State private var manualDraft = PaymentDraft()
    @State private var showManualDatePicker = false

    var body: some View {
        ZStack {
            // Two-step content — slides horizontally
            ZStack {
                if reviewStep == 0 {
                    incomeStep
                        .transition(.asymmetric(
                            insertion: .move(edge: .leading).combined(with: .opacity),
                            removal:   .move(edge: .leading).combined(with: .opacity)))
                } else {
                    billsStep
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal:   .move(edge: .trailing).combined(with: .opacity)))
                }
            }
            .animation(.spring(response: 0.38, dampingFraction: 0.88), value: reviewStep)

            // Edit item overlay
            if let editing = editingItem {
                EditDetectedItemOverlay(
                    item: editing,
                    categories: store.finances.paymentCategories,
                    onSave: { updated in
                        if let i = items.firstIndex(where: { $0.id == editing.id }) {
                            items[i] = updated
                        }
                        editingItem = nil
                    },
                    onClose: { editingItem = nil }
                )
                .transition(.fbModalPush)
                .zIndex(10)
            }

            // Manual add overlay
            if showManualAdd {
                manualAddOverlay
                    .transition(.fbModalPush)
                    .zIndex(11)
            }
        }
        .animation(.fbModal, value: editingItem?.id)
        .animation(.fbModal, value: showManualAdd)
        .onAppear(perform: buildItems)
    }

    // MARK: Step header

    private func stepHeader(title: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.fbHeader(28))
                    .tracking(-0.5)
                    .foregroundStyle(Color.fbInk)
                Spacer()
                Text("Step \(reviewStep + 1) of 2")
                    .font(.fbBody(12))
                    .foregroundStyle(Color.fbSoftText)
            }
            if !monthsRead.isEmpty {
                HStack(spacing: 5) {
                    Image(systemName: "calendar")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.fbSoftText)
                    Text(scanRangeLabel)
                        .font(.fbBody(12))
                        .foregroundStyle(Color.fbSoftText)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    private var scanRangeLabel: String {
        guard !monthsRead.isEmpty else { return "" }
        if monthsRead.count == 1 { return monthsRead[0] }
        return "\(monthsRead.first ?? "") – \(monthsRead.last ?? "") · \(monthsRead.count) months"
    }

    // MARK: Step footer

    private func stepFooter(label: String, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        VStack(spacing: 0) {
            Divider().overlay(Color.fbHairline)
            VStack(spacing: 16) {
                FBPrimaryButton(label: label, enabled: enabled, action: action)
                if reviewStep == 1 {
                    Button {
                        withAnimation(.spring(response: 0.38, dampingFraction: 0.88)) {
                            reviewStep = 0
                        }
                    } label: {
                        Text("← Back to income")
                            .font(.fbBody(13))
                            .foregroundStyle(Color.fbSoftText)
                    }
                    .buttonStyle(.pressable)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
    }

    // MARK: Income step

    private var incomeStep: some View {
        VStack(spacing: 0) {
            stepHeader(title: "Income")

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if incomeItem != nil {
                        incomeRow
                    } else {
                        emptyCard(icon: "magnifyingglass",
                                  text: "No regular income detected in your statements.")
                    }

                    Text("Select your primary salary or wage. Headroom uses this to calculate your available spending money.")
                        .font(.fbBody(13))
                        .foregroundStyle(Color.fbSoftText)
                        .padding(.top, 2)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .scrollEdgeEffectStyle(.automatic, for: .vertical)

            stepFooter(label: "Next: Bills →") {
                withAnimation(.spring(response: 0.38, dampingFraction: 0.88)) { reviewStep = 1 }
            }
        }
    }

    private var incomeRow: some View {
        let item = incomeItem!
        return HStack(spacing: 14) {
            FBCheckbox(isOn: Binding(
                get: { incomeItem?.isIncluded ?? false },
                set: { incomeItem?.isIncluded = $0 }
            ))

            VStack(alignment: .leading, spacing: 3) {
                Text(item.displayName)
                    .font(.fbBody(16, weight: .semibold))
                    .foregroundStyle(Color.fbInk)
                Text("Around the \(item.modalDueDay.ordinalString) each \(item.cadence == .fourWeekly ? "4 weeks" : "month")")
                    .font(.fbBody(12))
                    .foregroundStyle(Color.fbSoftText)
            }

            Spacer()

            Text(freqLabel(for: item))
                .font(.fbNumber(15, weight: .semibold))
                .foregroundStyle(Color.fbPositive)
                .multilineTextAlignment(.trailing)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color.fbInk.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(Color.fbPositive.opacity(item.isIncluded ? 0.28 : 0), lineWidth: 1))
        .animation(.easeInOut(duration: 0.15), value: item.isIncluded)
    }

    // MARK: Bills step

    private var billsStep: some View {
        VStack(spacing: 0) {
            stepHeader(title: "Regular bills")

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if items.isEmpty {
                        emptyCard(icon: "checkmark.seal",
                                  text: "No recurring bills detected. You can add annual ones below.")
                    } else {
                        ForEach($items) { $item in
                            billRow(item: $item)
                        }
                    }

                    if !warnings.isEmpty { warningsNote }

                    Spacer().frame(height: 6)
                    annualPrompt

                    if monthsImported > 0 && monthsImported < 3 {
                        thinHistoryNote
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .scrollEdgeEffectStyle(.automatic, for: .vertical)

            stepFooter(
                label: "Confirm · save \(includedCount) item\(includedCount == 1 ? "" : "s")",
                enabled: includedCount > 0
            ) { commit() }
        }
    }

    private func billRow(item: Binding<ReviewItem>) -> some View {
        let v = item.wrappedValue
        return HStack(spacing: 12) {
            FBCheckbox(isOn: item.isIncluded)

            VStack(alignment: .leading, spacing: 3) {
                Text(v.displayName)
                    .font(.fbBody(15, weight: .semibold))
                    .foregroundStyle(Color.fbInk)
                HStack(spacing: 5) {
                    categoryChip(v.category)
                    Text("·").foregroundStyle(Color.fbSoftText.opacity(0.5))
                    Text("~\(v.modalDueDay.ordinalString)")
                        .font(.fbBody(11))
                        .foregroundStyle(Color.fbSoftText)
                }
            }

            Spacer()

            Text(freqLabel(for: v))
                .font(.fbNumber(13, weight: .semibold))
                .foregroundStyle(Color.fbInk)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: true, vertical: false)

            Button { editingItem = v } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.fbSoftText)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.fbInk.opacity(0.05)))
            }
            .buttonStyle(.pressable)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.fbInk.opacity(v.isIncluded ? 0.05 : 0.02)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(Color.fbHairline.opacity(v.isIncluded ? 0.6 : 0.2), lineWidth: 0.5))
        .animation(.easeInOut(duration: 0.12), value: v.isIncluded)
    }

    // MARK: Annual prompt

    private var annualPrompt: some View {
        let shortHistory = monthsImported > 0 && monthsImported < 3
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "calendar.badge.plus")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.fbSoftText)
                Text(shortHistory ? "Add your annual bills" : "Anything once a year?")
                    .font(.fbBody(14, weight: .semibold))
                    .foregroundStyle(Color.fbInk)
            }
            if shortHistory {
                Text("With \(monthsImported) month\(monthsImported == 1 ? "" : "s") of history, annual bills won't be auto-detected. Add them here: insurance renewals, TV licence, road tax.")
                    .font(.fbBody(12))
                    .foregroundStyle(Color.fbSoftText)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Insurance renewals, TV licence, annual subscriptions — add any that appear less than once in your imported history.")
                    .font(.fbBody(12))
                    .foregroundStyle(Color.fbSoftText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            FBSecondaryButton(label: "Add annual payment") {
                manualDraft = PaymentDraft()
                showManualAdd = true
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.fbInk.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(Color.fbHairline, lineWidth: 0.5))
    }

    private var thinHistoryNote: some View {
        HStack(spacing: 8) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 12))
                .foregroundStyle(Color.fbWarning)
            Text("Import 3+ months to detect quarterly bills automatically.")
                .font(.fbBody(12))
                .foregroundStyle(Color.fbSoftText)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color.fbWarning.opacity(0.07)))
    }

    private var warningsNote: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(warnings, id: \.self) { w in
                HStack(spacing: 6) {
                    Image(systemName: "info.circle").font(.system(size: 11))
                    Text(w).font(.fbBody(12))
                }
                .foregroundStyle(Color.fbSoftText)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color.fbInk.opacity(0.03)))
    }

    private func emptyCard(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(Color.fbSoftText)
            Text(text)
                .font(.fbBody(14))
                .foregroundStyle(Color.fbSoftText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color.fbInk.opacity(0.04)))
    }

    // MARK: Manual add overlay

    private var manualAddOverlay: some View {
        ZStack {
            ModalBackdrop { showManualAdd = false }
            ModalCard(depth: showManualDatePicker ? 1 : 0) {
                VStack(alignment: .leading, spacing: 18) {
                    ModalHeader(title: "Annual payment", onClose: { showManualAdd = false })
                    PaymentFormFields(
                        draft: $manualDraft,
                        categories: store.finances.paymentCategories,
                        showDatePicker: $showManualDatePicker)
                    FBPrimaryButton(label: "Add", enabled: manualDraft.isValid) {
                        addManualItem()
                    }
                }
            }
            if showManualDatePicker {
                FBDatePickerCard(label: "Date", date: $manualDraft.date) {
                    showManualDatePicker = false
                }
                .transition(.fbModalPush)
                .zIndex(1)
            }
        }
        .animation(.fbModal, value: showManualDatePicker)
    }

    private func addManualItem() {
        guard let amount = manualDraft.amount else { return }
        let item = ReviewItem(
            id: UUID(), isIncluded: true,
            displayName: manualDraft.name.trimmingCharacters(in: .whitespaces),
            category: manualDraft.category,
            amount: amount, modalDueDay: manualDraft.dueDay,
            cadence: .annual, confidence: .high,
            occurrenceDates: [manualDraft.date],
            isIncome: false, nextPayday: nil)
        withAnimation(.fbModal) { items.append(item) }
        showManualAdd = false
    }

    // MARK: Build items

    private func buildItems() {
        // Annual: only shown when 24+ months of data exist (2 years).
        // Quarterly: only shown when 3+ months.
        // This prevents single one-off transactions from appearing as annual.
        items = result.commitments
            .filter { c in
                if c.cadence == .annual    { return monthsImported >= 24 }
                if c.cadence == .quarterly { return monthsImported >= 3  }
                return true
            }
            .map { c in
                ReviewItem(
                    id: c.id, isIncluded: c.confidence == .high,
                    displayName: c.displayName, category: c.category,
                    amount: c.amount, modalDueDay: c.modalDueDay,
                    cadence: c.cadence, confidence: c.confidence,
                    occurrenceDates: c.occurrenceDates,
                    isIncome: false, nextPayday: nil)
            }

        if let inc = result.income {
            let cal = Calendar(identifier: .gregorian)
            incomeItem = ReviewItem(
                id: inc.id, isIncluded: true,
                displayName: inc.displayName, category: "Salary",
                amount: inc.amount,
                modalDueDay: cal.component(.day, from: inc.nextPayday),
                cadence: inc.cadence, confidence: .high,
                occurrenceDates: inc.occurrenceDates,
                isIncome: true, nextPayday: inc.nextPayday)
        }
    }

    // MARK: Helpers

    private var includedCount: Int {
        items.filter(\.isIncluded).count + (incomeItem?.isIncluded == true ? 1 : 0)
    }

    private func freqLabel(for item: ReviewItem) -> String {
        let amt = Money.string(item.amount)
        switch item.cadence {
        case .weekly:     return "\(amt)/wk"
        case .fourWeekly: return "\(amt)/4wk"
        case .monthly:    return "\(amt)/mo"
        case .quarterly:  return "\(amt)/qtr"
        case .annual:     return "\(amt)/yr"
        }
    }

    private func categoryChip(_ cat: String) -> some View {
        Text(cat)
            .font(.fbBody(10, weight: .semibold))
            .foregroundStyle(Color.fbSoftText)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(Color.fbInk.opacity(0.07)))
    }

    private func commit() {
        for item in items where item.isIncluded {
            store.finances.recurringCommitments.append(
                RecurringCommitment(id: item.id, name: item.displayName,
                                    amount: item.amount, dueDay: item.modalDueDay,
                                    category: item.category))
        }
        if let inc = incomeItem, inc.isIncluded {
            store.finances.incomeSources.append(
                IncomeSource(id: inc.id, name: inc.displayName, amount: inc.amount,
                             isRecurring: true, category: "Salary",
                             date: inc.nextPayday ?? Date()))
        }
        onConfirm()
    }
}

// MARK: - Edit overlay

struct EditDetectedItemOverlay: View {
    let item: ReviewItem
    let categories: [String]
    let onSave: (ReviewItem) -> Void
    let onClose: () -> Void

    @State private var name: String
    @State private var amount: Double?
    @State private var category: String
    @State private var date: Date
    @State private var showDatePicker = false

    init(item: ReviewItem, categories: [String],
         onSave: @escaping (ReviewItem) -> Void,
         onClose: @escaping () -> Void) {
        self.item = item; self.categories = categories
        self.onSave = onSave; self.onClose = onClose
        _name     = State(initialValue: item.displayName)
        _amount   = State(initialValue: item.amount)
        _category = State(initialValue: item.category)
        var comps = Calendar(identifier: .gregorian).dateComponents([.year, .month], from: Date())
        comps.day = item.modalDueDay
        _date = State(initialValue: Calendar(identifier: .gregorian).date(from: comps) ?? Date())
    }

    var body: some View {
        ZStack {
            ModalBackdrop { onClose() }
            ModalCard(depth: showDatePicker ? 1 : 0) {
                VStack(alignment: .leading, spacing: 18) {
                    ModalHeader(title: "Edit", onClose: onClose)
                    PlainTextField(placeholder: "Name", text: $name)
                    CurrencyEntryField(value: $amount)
                    FBMenuField(label: "Category", selection: $category, options: categories)
                    FBDateField(label: "Due date", date: $date, showDatePicker: $showDatePicker)
                    FBPrimaryButton(label: "Save", enabled: isValid) {
                        var updated = item
                        updated.displayName = name.trimmingCharacters(in: .whitespaces)
                        updated.amount = amount ?? item.amount
                        updated.category = category
                        updated.modalDueDay = Calendar(identifier: .gregorian).component(.day, from: date)
                        onSave(updated)
                    }
                }
            }
            if showDatePicker {
                FBDatePickerCard(label: "Due date", date: $date) { showDatePicker = false }
                    .transition(.fbModalPush)
                    .zIndex(1)
            }
        }
        .animation(.fbModal, value: showDatePicker)
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && (amount ?? 0) > 0
    }
}

// MARK: - Int ordinal

extension Int {
    var ordinalString: String {
        let tens = (self / 10) % 10
        let ones = self % 10
        let suffix: String
        if tens == 1 { suffix = "th" }
        else {
            switch ones {
            case 1:  suffix = "st"
            case 2:  suffix = "nd"
            case 3:  suffix = "rd"
            default: suffix = "th"
            }
        }
        return "\(self)\(suffix)"
    }
}

// MARK: - Preview

#Preview("Review — mock data") {
    let store = HeadroomStore(finances: .empty)
    let cal = Calendar(identifier: .gregorian)

    func monthsAgo(_ m: Int, day: Int) -> Date {
        var c = cal.dateComponents([.year, .month], from: Date())
        c.month! -= m; c.day = day
        return cal.date(from: c) ?? Date()
    }

    let result = DetectionResult(
        commitments: [
            DetectedCommitment(id: UUID(), normalisedKey: "SPOTIFY",
                               displayName: "Spotify", category: "Subscriptions",
                               amount: 11.99, modalDueDay: 4, cadence: .monthly,
                               confidence: .high,
                               occurrenceDates: [monthsAgo(2, day: 4), monthsAgo(1, day: 4), monthsAgo(0, day: 4)]),
            DetectedCommitment(id: UUID(), normalisedKey: "EDF ENERGY",
                               displayName: "EDF Energy", category: "Utilities",
                               amount: 82, modalDueDay: 15, cadence: .monthly,
                               confidence: .high,
                               occurrenceDates: [monthsAgo(3, day: 15), monthsAgo(2, day: 15), monthsAgo(1, day: 15)]),
        ],
        income: DetectedIncome(
            id: UUID(), normalisedKey: "EMPLOYER LTD",
            displayName: "Employer Ltd", amount: 2400,
            nextPayday: cal.date(byAdding: .day, value: 12, to: Date()) ?? Date(),
            cadence: .monthly,
            occurrenceDates: [monthsAgo(2, day: 28), monthsAgo(1, day: 28), monthsAgo(0, day: 28)]
        )
    )

    return ZStack {
        FBBackground()
        FBBlobBackground()
        ReviewDetectedView(
            store: store, result: result, suggestedBalance: 1842.50,
            monthsRead: ["May 2026", "Jun 2026", "Jul 2026"],
            onConfirm: {}, onCancel: {}
        )
    }
    .preferredColorScheme(.dark)
}
