//
//  SankeyView.swift
//  Finance buddy
//
//  A minimal Sankey diagram: monthly income enters on the left and splits
//  into three flows — recurring payments, one-time payments, and the
//  hatched safe-to-spend remainder. Drawn entirely with Canvas —
//  monochrome bands, subtle gradients, no chart library.
//

import SwiftUI

struct SankeyView: View {
    let income: Double
    let recurringTotal: Double
    let oneOffTotal: Double

    private let nodeWidth: CGFloat = 5
    private let rowGap: CGFloat = 10
    private let labelWidth: CGFloat = 118
    /// Rows never get thinner than this so labels stay legible; the
    /// difference is reclaimed from the larger rows.
    private let minRowHeight: CGFloat = 30

    private struct Flow: Identifiable {
        let id: String
        let name: String
        let amount: Double
        let isSafe: Bool
    }

    /// The three groups. Safe-to-spend is what's left of income once both
    /// payment groups are covered (omitted when nothing is left).
    private var flows: [Flow] {
        var rows: [Flow] = []
        if recurringTotal > 0 {
            rows.append(Flow(id: "recurring", name: "Recurring", amount: recurringTotal, isSafe: false))
        }
        if oneOffTotal > 0 {
            rows.append(Flow(id: "oneOff", name: "One-time", amount: oneOffTotal, isSafe: false))
        }
        let safe = income - recurringTotal - oneOffTotal
        if safe > 0 {
            rows.append(Flow(id: "safe", name: "Safe to spend", amount: safe, isSafe: true))
        }
        return rows
    }

    /// Proportional heights with a readability floor: tiny amounts are
    /// clamped to `minRowHeight` and the excess is taken from big rows.
    private func rowHeights(_ rows: [Flow], usable: CGFloat) -> [CGFloat] {
        let total = max(rows.reduce(0) { $0 + $1.amount }, 0.01)
        var heights = rows.map { CGFloat($0.amount / total) * usable }

        let deficit = heights.reduce(0) { $0 + max(0, minRowHeight - $1) }
        let excess = heights.reduce(0) { $0 + max(0, $1 - minRowHeight) }
        guard deficit > 0, excess > 0 else { return heights }

        for i in heights.indices {
            if heights[i] < minRowHeight {
                heights[i] = minRowHeight
            } else {
                heights[i] -= deficit * (heights[i] - minRowHeight) / excess
            }
        }
        return heights
    }

    var body: some View {
        let rows = flows

        VStack(alignment: .leading, spacing: 10) {
            // Source label: this diagram starts from income, not balance.
            HStack {
                Text("Income")
                    .font(.fbBody(12, weight: .semibold))
                    .foregroundStyle(Color.fbSoftText)
                Text(Money.string(income))
                    .font(.fbNumber(12, weight: .semibold))
                    .foregroundStyle(Color.fbInk)
                Spacer()
            }

            if rows.isEmpty {
                Text("Add income and payments to see the flow.")
                    .font(.fbBody(13))
                    .foregroundStyle(Color.fbSoftText)
            } else {
                diagram(rows: rows)
            }
        }
    }

    private func diagram(rows: [Flow]) -> some View {
        HStack(spacing: 0) {
            // Left node: income entering the picture.
            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                .fill(Color.fbInk.opacity(0.85))
                .frame(width: nodeWidth)

            // The flow field.
            GeometryReader { geo in
                Canvas { context, size in
                    let gaps = CGFloat(max(rows.count - 1, 0)) * rowGap
                    let heights = rowHeights(rows, usable: size.height - gaps)
                    var leftY: CGFloat = gaps / 2 // left stack has no gaps; centre it
                    var rightY: CGFloat = 0

                    for (index, row) in rows.enumerated() {
                        let h = heights[index]

                        var band = Path()
                        let x1 = size.width
                        let midX = size.width * 0.5
                        band.move(to: CGPoint(x: 0, y: leftY))
                        band.addCurve(to: CGPoint(x: x1, y: rightY),
                                      control1: CGPoint(x: midX, y: leftY),
                                      control2: CGPoint(x: midX, y: rightY))
                        band.addLine(to: CGPoint(x: x1, y: rightY + h))
                        band.addCurve(to: CGPoint(x: 0, y: leftY + h),
                                      control1: CGPoint(x: midX, y: rightY + h),
                                      control2: CGPoint(x: midX, y: leftY + h))
                        band.closeSubpath()

                        let start = CGPoint(x: 0, y: leftY + h / 2)
                        let end = CGPoint(x: size.width, y: rightY + h / 2)
                        if row.isSafe {
                            context.fill(band, with: .linearGradient(
                                Gradient(colors: [Color.fbPositive.opacity(0.35),
                                                  Color.fbPositive.opacity(0.60)]),
                                startPoint: start, endPoint: end))
                        } else {
                            context.fill(band, with: .linearGradient(
                                Gradient(colors: [Color.white.opacity(0.30),
                                                  Color.white.opacity(0.14)]),
                                startPoint: start, endPoint: end))
                        }

                        leftY += h
                        rightY += h + rowGap
                    }
                }
            }

            // Right nodes + labels (same height math as the canvas).
            rightColumn(rows: rows)
                .frame(width: labelWidth)
        }
        .frame(height: max(130, CGFloat(rows.count) * 44))
        .animation(.easeInOut(duration: 0.3), value: rows.count)
    }

    private func rightColumn(rows: [Flow]) -> some View {
        GeometryReader { geo in
            let gaps = CGFloat(max(rows.count - 1, 0)) * rowGap
            let heights = rowHeights(rows, usable: geo.size.height - gaps)

            VStack(alignment: .leading, spacing: rowGap) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    HStack(spacing: 8) {
                        Group {
                            if row.isSafe {
                                StripedFill(color: Color.fbPositive, lineWidth: 1.8, spacing: 4.5)
                                    .background(Color.fbPositive.opacity(0.12))
                            } else {
                                Color.white.opacity(0.35)
                            }
                        }
                        .frame(width: nodeWidth)
                        .clipShape(RoundedRectangle(cornerRadius: 2.5, style: .continuous))

                        VStack(alignment: .leading, spacing: 0) {
                            Text(row.name)
                                .font(.fbBody(12, weight: row.isSafe ? .semibold : .medium))
                                .foregroundStyle(row.isSafe ? Color.fbInk : Color.fbSoftText)
                                .lineLimit(1)
                            Text("\(Money.string(row.amount)) · \(percent(row.amount))")
                                .font(.fbNumber(10))
                                .foregroundStyle(Color.fbSoftText)
                                .lineLimit(1)
                        }
                    }
                    .frame(height: heights[index], alignment: .center)
                }
            }
        }
    }

    private func percent(_ amount: Double) -> String {
        guard income > 0 else { return "—" }
        return "\(Int((amount / income * 100).rounded()))%"
    }
}

#Preview {
    let f = Finances.sample
    return Card {
        SankeyView(income: f.income.amount,
                   recurringTotal: f.recurringCommitments.reduce(0) { $0 + $1.amount },
                   oneOffTotal: f.oneOffCosts.reduce(0) { $0 + $1.amount })
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(FBBackground())
    .preferredColorScheme(.dark)
}
