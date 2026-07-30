//
//  ContentView.swift
//  Finance buddy
//
//  Root of the app: the biometric lock gate, then the native iOS tab
//  interface with a custom Add action button.
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
            .background {
                // Pages are transparent; previews supply what the root
                // normally does.
                FBBackground()
                FBBlobBackground()
            }
            .overlay { AppModalLayer(store: store, modal: $modal) }
            .animation(.fbModal, value: modal)
            .preferredColorScheme(.dark)
    }
}

struct ContentView: View {
    @State private var store: FinanceBuddyStore
    @State private var lock = AppLock()
    @State private var tab: Tab = .ask
    /// Ask's hero header collapse — owned here so AskView's scroll can
    /// drive AskHeaderBar without lifting that state into AskView.
    @State private var askHeaderCollapsed = false
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
            // One shared living background — pages are transparent so it
            // stays continuous while swiping between tabs.
            FBBlobBackground()

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

    @ViewBuilder
    private var mainInterface: some View {
        #if canImport(Supabase)
        MainTabShell(store: store, tab: $tab, askHeaderCollapsed: $askHeaderCollapsed,
                     modal: $modal, email: auth.email, canSignOut: true,
                     onSignOut: performSignOut)
        #else
        MainTabShell(store: store, tab: $tab, askHeaderCollapsed: $askHeaderCollapsed,
                     modal: $modal)
        #endif
    }

    private func performSignOut() async {
        #if canImport(Supabase)
        await auth.signOut()
        // Drop the local copy of the signed-out user's data.
        store.persistence = nil
        store.finances = .empty
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

/// The plain page title bar (Budget / Profile), attached via safeAreaBar
/// so the native scroll edge effect extends into it automatically.
struct PageTitleBar: View {
    let title: String

    var body: some View {
        HStack {
            Text(title)
                .font(.fbHeader(28))
                .tracking(-0.5)
                .foregroundStyle(Color.fbInk)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }
}

// MARK: - Tab shell

/// Single source of truth for the tab layout. Both ContentView and the
/// #Preview instantiate this, so any structural change applies to both.
struct MainTabShell: View {
    let store: FinanceBuddyStore
    @Binding var tab: Tab
    @Binding var askHeaderCollapsed: Bool
    @Binding var modal: AppModal?
    var email: String? = nil
    var canSignOut: Bool = false
    var onSignOut: () async -> Void = {}

    @State private var keyboardVisible = false

    var body: some View {
        ZStack {
            FBBlobBackground()
            TabView(selection: $tab) {
                AskView(store: store, isActive: tab == .ask,
                        headerCollapsed: $askHeaderCollapsed,
                        present: { modal = $0 })
                .tag(Tab.ask)

                BudgetView(store: store, present: { modal = $0 })
                .tag(Tab.budget)

                ProfileView(store: store, email: email,
                            canSignOut: canSignOut, present: { modal = $0 })
                .tag(Tab.profile)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            // safeAreaInset (not safeAreaBar) properly propagates through
            // UIPageViewController's additionalSafeAreaInsets to each page, so
            // content isn't clipped by the bars and per-page scroll edge effects
            // render at the correct boundary.
            .safeAreaInset(edge: .top, spacing: 0) {
                switch tab {
                case .ask:    AskHeaderBar(store: store, collapsed: askHeaderCollapsed)
                case .budget: PageTitleBar(title: Tab.budget.title)
                case .profile: PageTitleBar(title: Tab.profile.title)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                CustomTabBar(
                    selection: $tab,
                    onAdd: { modal = .quickAdd },
                    isVisible: !keyboardVisible
                )
            }
            .observeKeyboard(isVisible: $keyboardVisible)
            .tint(Color.fbAccent)
            // Recede the app content when any modal is open — same depth
            // values as a ModalCard at depth 1 so the initial modal feels
            // consistent with stacked modal transitions.
            .scaleEffect(modal != nil ? 0.95 : 1, anchor: .bottom)
            .offset(y: modal != nil ? -10 : 0)
            .blur(radius: modal != nil ? 1.5 : 0)
            .opacity(modal != nil ? 0.55 : 1)
            .overlay { AppModalLayer(store: store, modal: $modal, onSignOut: onSignOut) }
            .overlay { FBToastView(center: store.toasts) }
            .animation(.fbModal, value: modal)
        }
    }
}
    
    #Preview("Locked") {
        ContentView()
    }
    
    #Preview("Unlocked shell") {
        struct ShellPreview: View {
            @State private var tab: Tab = .ask
            @State private var askHeaderCollapsed = false
            @State private var modal: AppModal?
            let store = FinanceBuddyStore(finances: .sample)
            
            var body: some View {
                ZStack {
                    FBBackground()
                    FBBlobBackground()
                    MainTabShell(store: store, tab: $tab,
                                 askHeaderCollapsed: $askHeaderCollapsed,
                                 modal: $modal, email: "preview@example.com",
                                 canSignOut: true)
                }
                .preferredColorScheme(.dark)
            }
        }
        return ShellPreview()
    }

