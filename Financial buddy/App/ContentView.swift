//
//  ContentView.swift
//  Finance buddy
//
//  Root of the app: the biometric lock gate, then the custom tab
//  interface. Deliberately no TabView / NavigationStack — the tab bar is a
//  plain HStack of buttons so iOS 26's Liquid Glass can't restyle it.
//  Ask is the landing tab.
//

import SwiftUI

struct ContentView: View {
    @State private var store: FinanceBuddyStore
    @State private var lock = AppLock()
    @State private var tab: Tab = .ask
    @State private var keyboardVisible = false
    #if canImport(Supabase)
    @State private var auth = SupabaseAuthModel()
    #endif

    init() {
        // With Supabase wired up the user's real data is loaded after
        // sign-in, so start empty. Otherwise seed sample data so the app is
        // usable out of the box.
        #if canImport(Supabase)
        _store = State(initialValue: FinanceBuddyStore(finances: .empty))
        #else
        _store = State(initialValue: FinanceBuddyStore(finances: .sample))
        #endif
    }

    var body: some View {
        ZStack {
            Color.fbBackground.ignoresSafeArea()

            if lock.isUnlocked {
                postUnlock
                    .transition(.opacity)
            } else {
                LockView(lock: lock)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: lock.isUnlocked)
        .task { await lock.authenticate() }
        .preferredColorScheme(.dark) // dark theme: keep system controls in step
    }

    /// After the biometric gate: sign-in (Supabase) then the main interface.
    @ViewBuilder
    private var postUnlock: some View {
        #if canImport(Supabase)
        if !auth.isReady {
            ProgressView()
                .tint(Color.fbPositive)
                .task { await auth.restore() }
        } else if !auth.isSignedIn {
            SignInView(auth: auth)
        } else {
            mainInterface
                .task(id: auth.userId) { await connectStore() }
        }
        #else
        mainInterface
        #endif
    }

    #if canImport(Supabase)
    private func connectStore() async {
        guard let id = auth.userId else { return }
        store.persistence = SupabaseFinancePersistence(userId: id)
        await store.load()
    }
    #endif

    private var mainInterface: some View {
        VStack(spacing: 0) {
            // Horizontally paged screens — swipe between tabs. A non-lazy
            // HStack keeps every page (and its state, like the chat) alive.
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    ForEach(Tab.allCases, id: \.self) { page in
                        pageView(for: page)
                            .containerRelativeFrame(.horizontal)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: pagedTab)
            .scrollIndicators(.hidden)

            // The tab bar makes way for the keyboard so the input field
            // sits directly above it with nothing in between.
            if !keyboardVisible {
                CustomTabBar(selection: pagedTab)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: keyboardVisible)
        .observeKeyboard(isVisible: $keyboardVisible)
    }

    /// Bridges the optional scroll position to the concrete tab selection.
    private var pagedTab: Binding<Tab?> {
        Binding(get: { tab }, set: { tab = $0 ?? tab })
    }

    @ViewBuilder
    private func pageView(for page: Tab) -> some View {
        switch page {
        case .ask:     AskView(store: store, isActive: tab == .ask)
        case .budget:  BudgetView(store: store)
        case .profile: profileView
        }
    }

    @ViewBuilder
    private var profileView: some View {
        #if canImport(Supabase)
        ProfileView(email: auth.email) {
            await auth.signOut()
            // Drop the local copy of the signed-out user's data.
            store.persistence = nil
            store.finances = .empty
        }
        #else
        ProfileView(email: nil, onSignOut: nil)
        #endif
    }
}

// MARK: - Keyboard visibility

extension View {
    /// Tracks the software keyboard's visibility into a binding (iOS only;
    /// a no-op elsewhere). Uses async notification streams — no Combine.
    func observeKeyboard(isVisible: Binding<Bool>) -> some View {
        #if os(iOS)
        return self
            .task {
                for await _ in NotificationCenter.default.notifications(
                    named: UIResponder.keyboardWillShowNotification
                ) {
                    await MainActor.run { isVisible.wrappedValue = true }
                }
            }
            .task {
                for await _ in NotificationCenter.default.notifications(
                    named: UIResponder.keyboardWillHideNotification
                ) {
                    await MainActor.run { isVisible.wrappedValue = false }
                }
            }
        #else
        return self
        #endif
    }
}

// MARK: - Tabs

enum Tab: CaseIterable {
    case ask, budget, profile

    var title: String {
        switch self {
        case .ask:     return "Ask"
        case .budget:  return "Budget"
        case .profile: return "Profile"
        }
    }

    var icon: String {
        switch self {
        case .ask:     return "bubble.left.and.bubble.right.fill"
        case .budget:  return "chart.pie.fill"
        case .profile: return "person.crop.circle"
        }
    }
}

/// Minimal pager bar: three icons and an active dot. Swiping the pages
/// moves the selection; tapping an icon jumps to the page. Not a TabView.
struct CustomTabBar: View {
    @Binding var selection: Tab?

    var body: some View {
        HStack(spacing: 36) {
            ForEach(Tab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) { selection = tab }
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 21, weight: .semibold))
                            .foregroundStyle(selection == tab ? Color.fbPositive : Color.fbSoftText)
                        Rectangle()
                            .fill(selection == tab ? Color.fbPositive : .clear)
                            .frame(width: 40, height: 4)
                    }
                    .frame(width: 44, height: 40)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
            }
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(Color.fbBackground)
    }
}

#Preview("Locked") {
    ContentView()
}

#Preview("Unlocked shell") {
    // Shows the main interface (bypassing the lock) so the custom tab bar
    // is visible composed with a screen.
    struct ShellPreview: View {
        @State private var tab: Tab? = .ask
        let store = FinanceBuddyStore(finances: .sample)
        var body: some View {
            VStack(spacing: 0) {
                ScrollView(.horizontal) {
                    HStack(spacing: 0) {
                        ForEach(Tab.allCases, id: \.self) { page in
                            Group {
                                switch page {
                                case .ask:     AskView(store: store)
                                case .budget:  BudgetView(store: store)
                                case .profile: ProfileView(email: "preview@example.com", onSignOut: {})
                                }
                            }
                            .containerRelativeFrame(.horizontal)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $tab)
                .scrollIndicators(.hidden)

                CustomTabBar(selection: $tab)
            }
            .background(Color.fbBackground)
            .preferredColorScheme(.dark)
        }
    }
    return ShellPreview()
}
