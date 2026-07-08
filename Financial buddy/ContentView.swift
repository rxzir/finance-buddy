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
            Group {
                switch tab {
                case .ask:     AskView(store: store)
                case .home:    HomeView(finances: store.finances)
                case .manage:  ManageView(store: store)
                case .profile: profileView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            CustomTabBar(selection: $tab)
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

// MARK: - Tabs

enum Tab: CaseIterable {
    case ask, home, manage, profile

    var title: String {
        switch self {
        case .ask:     return "Ask"
        case .home:    return "Home"
        case .manage:  return "Manage"
        case .profile: return "Profile"
        }
    }

    var icon: String {
        switch self {
        case .ask:     return "bubble.left.and.bubble.right.fill"
        case .home:    return "chart.bar.fill"
        case .manage:  return "slider.horizontal.3"
        case .profile: return "person.crop.circle"
        }
    }
}

/// Plain HStack of buttons — not a TabView.
struct CustomTabBar: View {
    @Binding var selection: Tab

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Tab.allCases, id: \.self) { tab in
                Button {
                    selection = tab
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 20, weight: .semibold))
                        Text(tab.title)
                            .font(.fbBody(11, weight: .semibold))
                    }
                    .foregroundStyle(selection == tab ? Color.fbPositive : Color.fbSoftText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(selection == tab ? Color.fbPositive.opacity(0.12) : .clear)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.fbCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.fbHairline, lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
}

#Preview("Locked") {
    ContentView()
}

#Preview("Unlocked shell") {
    // Shows the main interface (bypassing the lock) so the custom tab bar
    // is visible composed with a screen.
    struct ShellPreview: View {
        @State private var tab: Tab = .ask
        let store = FinanceBuddyStore(finances: .sample)
        var body: some View {
            VStack(spacing: 0) {
                Group {
                    switch tab {
                    case .ask:     AskView(store: store)
                    case .home:    HomeView(finances: store.finances)
                    case .manage:  ManageView(store: store)
                    case .profile: ProfileView(email: "preview@example.com", onSignOut: {})
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                CustomTabBar(selection: $tab)
            }
            .background(Color.fbBackground)
            .preferredColorScheme(.dark)
        }
    }
    return ShellPreview()
}
