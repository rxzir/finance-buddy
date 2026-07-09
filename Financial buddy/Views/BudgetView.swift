//
//  BudgetView.swift
//  Finance buddy
//
//  The Budget tab: the old Home overview and the Manage screen merged.
//  A custom two-segment toggle (not a native picker) flips between
//  "Overview" (how am I doing) and "Manage" (fix the numbers), and a
//  floating + button logs a one-off cost from anywhere in the tab.
//

import SwiftUI

struct BudgetView: View {
    @Bindable var store: FinanceBuddyStore

    enum Mode: String, CaseIterable {
        case overview = "Overview"
        case manage = "Manage"
    }

    @State private var mode: Mode = .overview
    @State private var showAddOneOff = false

    var body: some View {
        ZStack {
            Color.fbBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                segmentToggle
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)

                switch mode {
                case .overview: HomeView(finances: store.finances)
                case .manage:   ManageView(store: store)
                }
            }

            floatingAddButton

            if showAddOneOff {
                AddOneOffOverlay(
                    onCancel: { showAddOneOff = false },
                    onSave: { store.addOneOff($0); showAddOneOff = false }
                )
            }
        }
    }

    private var header: some View {
        HStack {
            Text("Budget")
                .font(.fbHeader(28))
                .tracking(-0.5)
                .foregroundStyle(Color.fbInk)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
        .padding(.bottom, 10)
    }

    // MARK: Segment toggle (custom — no native picker chrome)

    private var segmentToggle: some View {
        HStack(spacing: 4) {
            ForEach(Mode.allCases, id: \.self) { m in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { mode = m }
                } label: {
                    Text(m.rawValue)
                        .font(.fbBody(14, weight: .semibold))
                        .foregroundStyle(mode == m ? Color.fbInk : Color.fbSoftText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(mode == m ? Color.fbBackground : .clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(Color.fbCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(Color.fbHairline, lineWidth: 1)
        )
    }

    // MARK: Floating quick-add (one-off costs are the frequent case)

    private var floatingAddButton: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Button {
                    showAddOneOff = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Color.fbOnAccent)
                        .frame(width: 54, height: 54)
                        .background(Circle().fill(Color.fbPositive))
                        .shadow(color: Color.fbPositive.opacity(0.35), radius: 10, y: 3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add a one-off cost")
                .padding(.trailing, 20)
                .padding(.bottom, 16)
            }
        }
    }
}

#Preview {
    BudgetView(store: FinanceBuddyStore(finances: .sample))
        .preferredColorScheme(.dark)
}
