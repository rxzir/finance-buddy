//
//  SankeyView.swift
//  Headroom
//
//  A two-stage Sankey: every income stream flows into the balance pool in
//  the middle (labelled with the accumulated total), which fans out into
//  recurring payments, one-time payments and the hatched safe-to-spend
//  remainder. Drawn entirely with Canvas — monochrome bands, subtle
//  gradients, no chart library. Labels sit inside the diagram: income
//  labels to the right of their node, expense labels to the left of theirs.
//

import SwiftUI

struct SankeyView: View {
    let sources: [IncomeSource]
    let recurringTotal: Double
    let oneOffTotal: Double

    private let nodeWidth: CGFloat = 5
    private let rowGap: CGFloat = 10
    private let labelInset: CGFloat = 10
    /// Headroom above the diagram for the pool's total-income label.
    private let topInset: CGFloat = 18
    /// Rows never get thinner than this so the two-line labels stay
    /// legible; the difference is reclaimed from the larger rows.
    private let minRowHeight: CGFloat = 32

    private struct Flow: Identifiable {
        let id: String
        let name: String
        let amount: Double
        var isSafe = false
    }

    private var income: Double { sources.reduce(0) { $0 + $1.amount } }

    /// Every income stream keeps its own band and label.
    private var inflows: [Flow] {
        sources.filter { $0.amount > 0 }
            .map { Flow(id: $0.id.uuidString, name: $0.name, amount: $0.amount) }
    }

    /// The three outgoing groups. Safe-to-spend is what's left of income
    /// once both payment groups are covered (omitted when nothing is left).
    private var outflows: [Flow] {
        var rows: [Flow] = []
        if recurringTotal > 0 {
            rows.append(Flow(id: "recurring", name: "Recurring", amount: recurringTotal))
        }
        if oneOffTotal > 0 {
            rows.append(Flow(id: "oneOff", name: "One-time", amount: oneOffTotal))
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
        let left = inflows
        let right = outflows

        if left.isEmpty || right.isEmpty {
            Text("Add income and payments to see the flow.")
                .font(.fbBody(13))
                .foregroundStyle(Color.fbSoftText)
        } else {
            Canvas { context, size in
                draw(left: left, right: right, in: &context, size: size)
            }
            .frame(height: max(150, CGFloat(max(left.count, right.count)) * 48) + topInset)
            .animation(.easeInOut(duration: 0.3), value: left.count + right.count)
        }
    }

    // MARK: Drawing

    private func draw(left: [Flow], right: [Flow],
                      in context: inout GraphicsContext, size: CGSize) {
        // The top inset keeps room for the pool's total label.
        let fieldHeight = size.height - topInset
        let leftGaps = CGFloat(max(left.count - 1, 0)) * rowGap
        let rightGaps = CGFloat(max(right.count - 1, 0)) * rowGap
        let leftHeights = rowHeights(left, usable: fieldHeight - leftGaps)
        let rightHeights = rowHeights(right, usable: fieldHeight - rightGaps)
        let leftSum = leftHeights.reduce(0, +)
        let rightSum = rightHeights.reduce(0, +)

        let cx = size.width * 0.5
        let poolLeft = cx - nodeWidth / 2
        let poolRight = cx + nodeWidth / 2

        // Stage 1: income nodes at the left edge → pool (pool stack has
        // no gaps).
        var y = topInset
        var poolY = topInset + (fieldHeight - leftSum) / 2
        for (index, row) in left.enumerated() {
            let h = leftHeights[index]
            node(&context, rect: CGRect(x: 0, y: y, width: nodeWidth, height: h), safe: false)
            band(&context,
                 fromX: nodeWidth, fromY: y, fromH: h,
                 toX: poolLeft, toY: poolY, toH: h,
                 safe: false)
            // Income label INSIDE the diagram, to the right of the line.
            label(&context, row: row,
                  at: CGPoint(x: nodeWidth + labelInset, y: y + h / 2),
                  trailing: false)
            y += h + rowGap
            poolY += h
        }

        // The balance pool node, capped with the accumulated income.
        let poolHeight = max(leftSum, rightSum)
        let poolRect = CGRect(x: poolLeft,
                              y: topInset + (fieldHeight - poolHeight) / 2,
                              width: nodeWidth,
                              height: poolHeight)
        context.fill(Path(roundedRect: poolRect, cornerRadius: 2.5),
                     with: .color(Color.fbInk.opacity(0.85)))
        context.draw(
            Text(Money.string(income))
                .font(.fbNumber(11, weight: .semibold))
                .foregroundStyle(Color.fbInk),
            at: CGPoint(x: cx, y: poolRect.minY - 6),
            anchor: .bottom)

        // Stage 2: pool → payment groups at the right edge.
        var outPoolY = topInset + (fieldHeight - rightSum) / 2
        var ry = topInset
        for (index, row) in right.enumerated() {
            let h = rightHeights[index]
            node(&context,
                 rect: CGRect(x: size.width - nodeWidth, y: ry, width: nodeWidth, height: h),
                 safe: row.isSafe)
            band(&context,
                 fromX: poolRight, fromY: outPoolY, fromH: h,
                 toX: size.width - nodeWidth, toY: ry, toH: h,
                 safe: row.isSafe, brightAtStart: true)
            // Expense label INSIDE the diagram, to the left of the line.
            label(&context, row: row,
                  at: CGPoint(x: size.width - nodeWidth - labelInset, y: ry + h / 2),
                  trailing: true)
            outPoolY += h
            ry += h + rowGap
        }
    }

    /// One curved band between two vertical slices. `brightAtStart` puts
    /// the denser end of the gradient at the `from` edge — expenses use it
    /// so their weight hugs the centre pool.
    private func band(_ context: inout GraphicsContext,
                      fromX: CGFloat, fromY: CGFloat, fromH: CGFloat,
                      toX: CGFloat, toY: CGFloat, toH: CGFloat,
                      safe: Bool, brightAtStart: Bool = false) {
        var path = Path()
        let midX = (fromX + toX) / 2
        path.move(to: CGPoint(x: fromX, y: fromY))
        path.addCurve(to: CGPoint(x: toX, y: toY),
                      control1: CGPoint(x: midX, y: fromY),
                      control2: CGPoint(x: midX, y: toY))
        path.addLine(to: CGPoint(x: toX, y: toY + toH))
        path.addCurve(to: CGPoint(x: fromX, y: fromY + fromH),
                      control1: CGPoint(x: midX, y: toY + toH),
                      control2: CGPoint(x: midX, y: fromY + fromH))
        path.closeSubpath()

        let start = CGPoint(x: fromX, y: fromY + fromH / 2)
        let end = CGPoint(x: toX, y: toY + toH / 2)
        if safe {
            context.fill(path, with: .linearGradient(
                Gradient(colors: [Color.fbPositive.opacity(0.3),
                                  Color.fbPositive.opacity(0.07)]),
                startPoint: start, endPoint: end))
        } else {
            let opacities: [Double] = brightAtStart ? [0.3, 0.07] : [0.07, 0.3]
            context.fill(path, with: .linearGradient(
                Gradient(colors: opacities.map { Color.fbInk.opacity($0) }),
                startPoint: start, endPoint: end))
        }
    }

    /// A node bar at either edge. The safe node keeps the hatched look.
    private func node(_ context: inout GraphicsContext, rect: CGRect, safe: Bool) {
        let shape = Path(roundedRect: rect, cornerRadius: 2.5)
        if safe {
            context.drawLayer { layer in
                layer.clip(to: shape)
                layer.fill(shape, with: .color(Color.fbPositive.opacity(0.12)))
                var stripes = Path()
                var x = rect.minX - rect.height
                while x < rect.maxX {
                    stripes.move(to: CGPoint(x: x, y: rect.maxY))
                    stripes.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
                    x += 4.5
                }
                layer.stroke(stripes, with: .color(Color.fbPositive), lineWidth: 1.8)
            }
        } else {
            context.fill(shape, with: .color(Color.fbInk.opacity(0.35)))
        }
    }

    /// Two-line label drawn inside the flow field. `trailing` anchors the
    /// text's trailing edge at `point` (expense side).
    private func label(_ context: inout GraphicsContext, row: Flow,
                       at point: CGPoint, trailing: Bool) {
        let anchor: UnitPoint = trailing ? .trailing : .leading
        // Safe-to-spend keeps plain white text over its band.
        let name = Text(row.name)
            .font(.fbBody(11, weight: row.isSafe ? .semibold : .medium))
            .foregroundStyle(row.isSafe ? Color.white : Color.fbInk.opacity(0.85))
        let value = Text("\(Money.string(row.amount)) · \(percent(row.amount))")
            .font(.fbNumber(9))
            .foregroundStyle(row.isSafe ? Color.white.opacity(0.8) : Color.fbSoftText)

        context.draw(name, at: CGPoint(x: point.x, y: point.y - 7), anchor: anchor)
        context.draw(value, at: CGPoint(x: point.x, y: point.y + 7), anchor: anchor)
    }

    private func percent(_ amount: Double) -> String {
        guard income > 0 else { return "—" }
        return "\(Int((amount / income * 100).rounded()))%"
    }
}

#Preview {
    let f = Finances.sample
    return Card {
        SankeyView(sources: f.incomeSources,
                   recurringTotal: f.recurringCommitments.reduce(0) { $0 + $1.amount },
                   oneOffTotal: f.oneOffCosts.reduce(0) { $0 + $1.amount })
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(FBBackground())
    .preferredColorScheme(.dark)
}
