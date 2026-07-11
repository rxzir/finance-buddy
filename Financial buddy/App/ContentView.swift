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

/// Every modal in the app. Screens *request* a modal via their `present`
/// callback; ContentView renders it above the tab bar. Presenting at the
/// root is what guarantees modals sit on top of the bar on the z-axis —
/// overlays rendered inside a page always draw underneath a safe-area bar.
enum AppModal: Equatable {
    case editToday
    case managePayments
    case quickAdd
    case categories(income: Bool)
    case confirmSignOut
}

/// The root modal renderer: maps the active `AppModal` to its overlay.
/// Used by ContentView, and by previews (via `PreviewModalHost`) so
/// modals are visible in the canvas too.
struct AppModalLayer: View {
    @Bindable var store: FinanceBuddyStore
    @Binding var modal: AppModal?
    var onSignOut: () async -> Void = {}

    var body: some View {
        switch modal {
        case .editToday:
            EditTodayOverlay(store: store) { modal = nil }
        case .managePayments:
            ManageCommitmentsOverlay(store: store) { modal = nil }
        case .quickAdd:
            QuickAddOverlay(store: store) { modal = nil }
        case .categories(let income):
            ManageCategoriesOverlay(store: store, forIncome: income) { modal = nil }
        case .confirmSignOut:
            SignOutConfirmOverlay(onSignOut: onSignOut) { modal = nil }
        case nil:
            EmptyView()
        }
    }
}

/// Preview-only harness: hosts a page together with the root modal layer
/// so tapping the page's edit/add buttons shows the modal in the canvas,
/// exactly as ContentView composes it at runtime.
struct PreviewModalHost<Content: View>: View {
    @State private var modal: AppModal?
    let store: FinanceBuddyStore
    @ViewBuilder let content: (_ present: @escaping (AppModal) -> Void) -> Content

    var body: some View {
        content({ modal = $0 })
            .overlay { AppModalLayer(store: store, modal: $modal) }
            .animation(.fbModal, value: modal)
            .preferredColorScheme(.dark)
    }
}

struct ContentView: View {
    @State private var store: FinanceBuddyStore
    @State private var lock = AppLock()
    @State private var tab: Tab = .ask
    @State private var keyboardVisible = false
    /// The one modal that's up, rendered at the root above the tab bar.
    @State private var modal: AppModal?
    @AppStorage("fbAppearance") private var appearanceRaw = FBAppearance.dark.rawValue
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
            FBBackground()

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
        // User-chosen appearance; nil (system) follows the device setting.
        .preferredColorScheme((FBAppearance(rawValue: appearanceRaw) ?? .dark).colorScheme)
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
        // Soft progressive-blur fade where content meets the top edge and
        // the tab bar pocket — every vertical scroll in the hierarchy.
        .scrollEdgeEffectStyle(.soft, for: .vertical)
        // A real bar (not a VStack sibling): pages scroll under it and the
        // system fades content into its pocket. It only makes way for the
        // keyboard — modals don't move it, they simply cover it.
        .safeAreaBar(edge: .bottom) {
            if !keyboardVisible {
                CustomTabBar(selection: pagedTab)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        // The modal layer sits OUTSIDE the safe-area bar, so it always
        // draws in front of the tab bar; the backdrop dims the bar along
        // with the rest of the screen.
        .overlay { modalLayer }
        .animation(.easeInOut(duration: 0.2), value: keyboardVisible)
        .animation(.fbModal, value: modal)
        .observeKeyboard(isVisible: $keyboardVisible)
    }

    private var modalLayer: some View {
        AppModalLayer(store: store, modal: $modal, onSignOut: performSignOut)
    }

    private func performSignOut() async {
        #if canImport(Supabase)
        await auth.signOut()
        // Drop the local copy of the signed-out user's data.
        store.persistence = nil
        store.finances = .empty
        #endif
    }

    /// Bridges the optional scroll position to the concrete tab selection.
    /// The setter animates so the tab bar pill glides when the change
    /// comes from a swipe, exactly as it does from a tap.
    private var pagedTab: Binding<Tab?> {
        Binding(get: { tab },
                set: { newValue in
                    guard let newValue, newValue != tab else { return }
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        tab = newValue
                    }
                })
    }

    @ViewBuilder
    private func pageView(for page: Tab) -> some View {
        switch page {
        case .ask:     AskView(store: store, isActive: tab == .ask,
                               present: { modal = $0 })
        case .budget:  BudgetView(store: store,
                                  present: { modal = $0 })
        case .profile: profileView
        }
    }

    @ViewBuilder
    private var profileView: some View {
        #if canImport(Supabase)
        ProfileView(store: store, email: auth.email, canSignOut: true,
                    present: { modal = $0 })
        #else
        ProfileView(store: store, email: nil, canSignOut: false,
                    present: { modal = $0 })
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

/// Minimal pager bar: a floating glass capsule with three icons and a
/// pill that glides between them. Swiping the pages moves the selection;
/// tapping an icon jumps to the page. Not a TabView.
struct CustomTabBar: View {
    @Binding var selection: Tab?
    @Namespace private var pill
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Tab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        selection = tab
                    }
                } label: {
                    Image(systemName: tab.icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(selection == tab ? Color.fbInk : Color.fbSoftText)
                        .frame(width: 58, height: 40)
                        .background {
                            if selection == tab {
                                Capsule()
                                    .fill(Color.fbInk.opacity(0.10))
                                    
                                    .matchedGeometryEffect(id: "activePill", in: pill)
                            }
                        }
                }
                .buttonStyle(.pressable)
                .accessibilityLabel(tab.title)
            }
        }
        .padding(5)
        .background {
            Capsule().fill(.ultraThinMaterial)
            // The deepening tint reads right in dark; light mode gets a
            // frosted white lift instead so the bar doesn't turn muddy.
            Capsule().fill(
                scheme == .dark
                    ? LinearGradient(colors: [Color.black.opacity(0.2),
                                              Color.black.opacity(0.6)],
                                     startPoint: .top, endPoint: .bottom)
                    : LinearGradient(colors: [Color.white.opacity(0.7),
                                              Color.white.opacity(0.35)],
                                     startPoint: .top, endPoint: .bottom)
            )
        }
        .overlay(
            Capsule().strokeBorder(
                LinearGradient(colors: [Color.fbInk.opacity(0.16),
                                        Color.fbInk.opacity(0.04)],
                               startPoint: .top, endPoint: .bottom),
                lineWidth: 0.5
            )
        )
        .shadow(color: .black.opacity(scheme == .dark ? 0.25 : 0.10), radius: 18, y: 6)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity)
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
        @State private var modal: AppModal?
        let store = FinanceBuddyStore(finances: .sample)
        var body: some View {
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    ForEach(Tab.allCases, id: \.self) { page in
                        Group {
                            switch page {
                            case .ask:     AskView(store: store, present: { modal = $0 })
                            case .budget:  BudgetView(store: store, present: { modal = $0 })
                            case .profile: ProfileView(store: store, email: "preview@example.com",
                                                       canSignOut: true, present: { modal = $0 })
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
            .scrollEdgeEffectStyle(.soft, for: .vertical)
            .safeAreaBar(edge: .bottom) {
                CustomTabBar(selection: $tab)
            }
            .overlay { AppModalLayer(store: store, modal: $modal) }
            .animation(.fbModal, value: modal)
            .background(Color.fbBackground)
            .preferredColorScheme(.dark)
        }
    }
    return ShellPreview()
}
