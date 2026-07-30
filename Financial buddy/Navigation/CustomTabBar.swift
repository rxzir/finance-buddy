//
//  CustomTabBar.swift
//  Finance buddy
//
//  Pill-based navigation bar. The add button and tab cluster each get
//  native Liquid Glass (glassEffect). A GlassEffectContainer renders
//  them as independent glass islands — no magnify on tab switch.
//  The selection pill slides via matchedGeometryEffect.
//

import SwiftUI

// MARK: - Bar

struct CustomTabBar: View {
    @Binding var selection: Tab
    var onAdd: () -> Void
    /// Slides the whole bar off-screen while the Ask keyboard is up.
    var isVisible: Bool = true

    @Namespace private var pillNS

    var body: some View {
        GlassEffectContainer(spacing: 20) {
            HStack(spacing: 0) {
                addButton
                Spacer(minLength: 20)
                tabCluster
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
        }
        .offset(y: isVisible ? 0 : 120)
        .animation(.spring(response: 0.38, dampingFraction: 0.85), value: isVisible)
    }

    // MARK: Add button

    private var addButton: some View {
        Button(action: onAdd) {
            Image(systemName: "plus")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Color.fbInk)
                .frame(width: 52, height: 52)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: Circle())
        .accessibilityLabel("Quick add")
    }

    // MARK: Tab cluster

    private var tabCluster: some View {
        HStack(spacing: 4) {
            ForEach(Tab.allCases, id: \.self) { tab in
                tabButton(tab)
            }
        }
        .padding(4)
        .glassEffect(.regular, in: .rect(cornerRadius: 44))
    }

    @ViewBuilder
    private func tabButton(_ tab: Tab) -> some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                selection = tab
            }
        } label: {
            Image(systemName: tab.icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(tab == selection ? Color.fbInk : Color.fbSoftText)
                .frame(width: 52, height: 44)
                .background {
                    if tab == selection {
                        RoundedRectangle(cornerRadius: 40, style: .continuous)
                            .fill(Color.fbInk.opacity(0.2))
                            .matchedGeometryEffect(id: "pill", in: pillNS)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
    }
}

// MARK: - Preview

#Preview("Pill slide") {
    struct Demo: View {
        @State private var tab: Tab = .ask

        var body: some View {
            ZStack {
                FBBackground()
                FBBlobBackground()

                VStack {
                    Spacer()
                    HStack(spacing: 24) {
                        ForEach(Tab.allCases, id: \.self) { t in
                            Button(t.title) {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                    tab = t
                                }
                            }
                            .font(.fbBody(14, weight: tab == t ? .bold : .regular))
                            .foregroundStyle(tab == t ? Color.fbInk : Color.fbSoftText)
                        }
                    }
                    .padding(.bottom, 20)

                    CustomTabBar(selection: $tab, onAdd: {}, isVisible: true)
                }
            }
            .preferredColorScheme(.dark)
        }
    }
    return Demo()
}

#Preview("Keyboard hidden") {
    struct HideDemo: View {
        @State private var tab: Tab = .budget
        @State private var visible = true

        var body: some View {
            ZStack {
                FBBackground()
                VStack {
                    Spacer()
                    Button(visible ? "Hide bar" : "Show bar") {
                        visible.toggle()
                    }
                    .font(.fbBody(15, weight: .medium))
                    .foregroundStyle(Color.fbAccent)
                    .padding(.bottom, 30)
                    CustomTabBar(selection: $tab, onAdd: {}, isVisible: visible)
                }
            }
            .preferredColorScheme(.dark)
        }
    }
    return HideDemo()
}
