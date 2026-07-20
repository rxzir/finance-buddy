//
//  BalanceBar.swift
//  Finance buddy
//
//  The signature visual: a horizontal bar of the month's money. Payments
//  already made are faded grey, payments still pending before payday are
//  white, and the hatched remainder is what's safe to spend. Tapping a
//  segment makes it glow while the rest fade; the tapped segment's info
//  is published to the parent (which swaps it into the balance row).
//

import SwiftUI

/// What the parent shows for a tapped segment.
struct BarSegmentInfo: Equatable {
    var name: String
    var amount: Double
    var percent: Int
    var isSafe: Bool
    var isCompleted: Bool
}

struct BalanceBar: View {
    /// Payments that already left the account this month (faded grey).
    let completed: [Obligation]
    /// Payments still to come before payday (white).
    let pending: [Obligation]
    let safeToSpend: Double
    /// The tapped segment, surfaced to the parent. Nil when nothing is
    /// selected.
    @Binding var selection: BarSegmentInfo?

    private let barHeight: CGFloat = 34
    private let gap: CGFloat = 2

    private enum SegmentID: Equatable {
        case completed(UUID)
        case pending(UUID)
        case safe
    }
    @State private var selectedID: SegmentID?

    private var showsSafe: Bool { safeToSpend > 0 }

    /// The whole bar is the month: done + pending + what's left.
    private var denominator: Double {
        let total = completed.reduce(0) { $0 + $1.amount }
            + pending.reduce(0) { $0 + $1.amount }
            + max(safeToSpend, 0)
        return max(total, 0.01)
    }

    private var segmentCount: Int {
        completed.count + pending.count + (showsSafe ? 1 : 0)
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            HStack(spacing: gap) {
                ForEach(completed) { ob in
                    // Past payments highlight with a white stroke — a fill
                    // change reads poorly on the muted grey.
                    segment(id: .completed(ob.id), width: segmentWidth(ob.amount, in: width),
                            glows: false) { isSelected in
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.fbCommitment.opacity(0.30))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .strokeBorder(Color.white.opacity(isSelected ? 0.9 : 0),
                                                  lineWidth: 1.5)
                            )
                    }
                }

                ForEach(pending) { ob in
                    segment(id: .pending(ob.id), width: segmentWidth(ob.amount, in: width)) { _ in
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.fbInk)
                    }
                }

                if showsSafe {
                    // Safe-to-spend answers a tap by going fully opaque —
                    // no glow on the hatching.
                    segment(id: .safe, width: segmentWidth(safeToSpend, in: width),
                            glows: false) { isSelected in
                        StripedFill(color: Color.fbPositive.opacity(isSelected ? 1 : 0.50))
                            .background(Color.fbPositive.opacity(isSelected ? 0.18 : 0.10))
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }
                }
            }
        }
        .frame(height: barHeight)
        // No outer clip: its larger corner radius cropped the selection
        // stroke and glow on the outermost segments.
    }

    /// Shared per-segment treatment: tap to select, fade when something
    /// else is. The shape builder gets the selected flag so each segment
    /// type styles its own selected state; `glows` adds the halo.
    private func segment<S: View>(id: SegmentID, width: CGFloat, glows: Bool = true,
                                  @ViewBuilder shape: (Bool) -> S) -> some View {
        let isSelected = selectedID == id
        let somethingSelected = selectedID != nil
        return shape(isSelected)
            .frame(width: max(2, width))
            .opacity(!somethingSelected || isSelected ? 1 : 0.3)
            .shadow(color: Color.fbInk.opacity(glows && isSelected ? 0.65 : 0),
                    radius: glows && isSelected ? 7 : 0)
            .contentShape(Rectangle())
            .onTapGesture { toggle(id) }
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: selectedID)
    }

    private func toggle(_ id: SegmentID) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            selectedID = (selectedID == id) ? nil : id
            selection = selectedID.flatMap(info(for:))
        }
    }

    private func info(for id: SegmentID) -> BarSegmentInfo? {
        func percent(_ amount: Double) -> Int {
            Int((amount / denominator * 100).rounded())
        }
        switch id {
        case .safe:
            return BarSegmentInfo(name: "Safe to spend", amount: safeToSpend,
                                  percent: percent(safeToSpend), isSafe: true,
                                  isCompleted: false)
        case .completed(let uuid):
            guard let ob = completed.first(where: { $0.id == uuid }) else { return nil }
            return BarSegmentInfo(name: ob.name, amount: ob.amount,
                                  percent: percent(ob.amount), isSafe: false,
                                  isCompleted: true)
        case .pending(let uuid):
            guard let ob = pending.first(where: { $0.id == uuid }) else { return nil }
            return BarSegmentInfo(name: ob.name, amount: ob.amount,
                                  percent: percent(ob.amount), isSafe: false,
                                  isCompleted: false)
        }
    }

    private func segmentWidth(_ amount: Double, in totalWidth: CGFloat) -> CGFloat {
        let available = totalWidth - CGFloat(max(segmentCount - 1, 0)) * gap
        return CGFloat(amount / denominator) * available
    }
}

// MARK: - Striped fill

/// Diagonal 45° hatching — used for the safe-to-spend segment so "money
/// that's yours" reads differently from the solid committed blocks.
struct StripedFill: View {
    var color: Color
    var lineWidth: CGFloat = 2.5
    var spacing: CGFloat = 6

    var body: some View {
        Canvas { context, size in
            var path = Path()
            // Cover the whole rect with 45° lines, starting off-canvas so
            // the corner is striped too.
            var x = -size.height
            while x < size.width {
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += spacing
            }
            context.stroke(path, with: .color(color), lineWidth: lineWidth)
        }
    }
}

#Preview {
    struct BarPreview: View {
        @State private var selection: BarSegmentInfo?
        let f = Finances.sample
        var body: some View {
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    if let selection {
                        Text("\(selection.name) · \(Money.string(selection.amount)) · \(selection.percent)%")
                            .font(.fbBody(13))
                            .foregroundStyle(Color.fbInk)
                    }
                    BalanceBar(completed: f.paidThisMonth(),
                               pending: f.upcomingObligations(),
                               safeToSpend: f.safeToSpendToday(),
                               selection: $selection)
                }
            }
            .padding()
        }
    }
    return BarPreview()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.fbBackground)
        .preferredColorScheme(.dark)
}
