//
//  ProfileView.swift
//  Finance buddy
//
//  Account page: who's signed in, category management for payments and
//  income, and a deliberately quiet sign-out at the foot of the screen.
//  All confirmations are custom ZStack overlays (never .sheet / .alert).
//

import SwiftUI

struct ProfileView: View {
    @Bindable var store: FinanceBuddyStore
    /// Signed-in email; nil when auth isn't wired (e.g. Supabase not linked).
    let email: String?
    /// False hides the sign-out control (e.g. Supabase not linked).
    var canSignOut: Bool = false
    /// Asks the root to present a modal (rendered above the tab bar).
    var present: (AppModal) -> Void = { _ in }
    @AppStorage("fbAppearance") private var appearanceRaw = FBAppearance.dark.rawValue
    @State private var showStatementImport = false

    var body: some View {
        ZStack {
            // Transparent — the shared background lives at the root. The
            // title bar lives on the pager in ContentView: only the
            // outermost scroll view renders edge effects, so a page-owned
            // safeAreaBar would never get the blur pocket.
            ScrollView {
                VStack(spacing: 16) {
                    identity
                    themeCard
                    categoriesCard
                    importCard
                    footer
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollEdgeEffectStyle(.soft, for: .vertical)
        }
        .fullScreenCover(isPresented: $showStatementImport) {
            StatementImportFlow(store: store) { showStatementImport = false }
        }
    }

    // MARK: Identity — no card, just the person

    private var identity: some View {
        VStack(spacing: 10) {
            Text(initial)
                .font(.fbHeader(30))
                .foregroundStyle(Color.fbInk)
                .frame(width: 76, height: 76)
                .background(Circle().fill(Color.fbInk.opacity(0.06)))
                .overlay(Circle().strokeBorder(Color.fbHairline, lineWidth: 1))

            Text(email ?? "Not signed in")
                .font(.fbBody(16, weight: .semibold))
                .foregroundStyle(Color.fbInk)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    private var initial: String {
        guard let first = email?.first else { return "?" }
        return String(first).uppercased()
    }

    // MARK: Theme

    private var themeCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Theme")
                    .font(.fbHeader(17))
                    .tracking(-0.3)
                    .foregroundStyle(Color.fbInk)

                FBSegmentedControl(
                    options: FBAppearance.allCases.map(\.label),
                    selection: Binding(
                        get: {
                            FBAppearance.allCases.firstIndex(
                                of: FBAppearance(rawValue: appearanceRaw) ?? .dark) ?? 0
                        },
                        set: { appearanceRaw = FBAppearance.allCases[$0].rawValue }))
            }
        }
    }

    // MARK: Categories

    private var categoriesCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 4) {
                Text("Categories")
                    .font(.fbHeader(17))
                    .tracking(-0.3)
                    .foregroundStyle(Color.fbInk)
                    .padding(.bottom, 6)

                categoryRow(title: "Payments",
                            count: store.finances.paymentCategories.count,
                            income: false)
                Divider().overlay(Color.fbHairline)
                categoryRow(title: "Income",
                            count: store.finances.incomeCategories.count,
                            income: true)
            }
        }
    }

    private func categoryRow(title: String, count: Int, income: Bool) -> some View {
        Button {
            present(.categories(income: income))
        } label: {
            HStack {
                Text(title)
                    .font(.fbBody(15, weight: .medium))
                    .foregroundStyle(Color.fbInk)
                Spacer()
                Text("\(count)")
                    .font(.fbNumber(14))
                    .foregroundStyle(Color.fbSoftText)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.fbSoftText)
            }
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
    }

    // MARK: Import

    private var importCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 4) {
                Text("Import")
                    .font(.fbHeader(17))
                    .tracking(-0.3)
                    .foregroundStyle(Color.fbInk)
                    .padding(.bottom, 6)

                Button {
                    showStatementImport = true
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Bank statement")
                                .font(.fbBody(15, weight: .medium))
                                .foregroundStyle(Color.fbInk)
                            Text("PDF from your bank app")
                                .font(.fbBody(13))
                                .foregroundStyle(Color.fbSoftText)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.fbSoftText)
                    }
                    .padding(.vertical, 11)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)
            }
        }
    }

    // MARK: Footer — version whisper + quiet sign out

    private var footer: some View {
        VStack(spacing: 14) {
            if canSignOut {
                Button {
                    present(.confirmSignOut)
                } label: {
                    Text("Sign out")
                        .font(.fbBody(14, weight: .medium))
                        .foregroundStyle(Color.fbSoftText)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 16)
                }
                .buttonStyle(.pressable)
            }

            Text("Version \(appVersion)")
                .font(.fbBody(12))
                .foregroundStyle(Color.fbSoftText.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
}

// MARK: - Sign-out confirmation (custom overlay, not .alert)

struct SignOutConfirmOverlay: View {
    let onSignOut: () async -> Void
    let onClose: () -> Void
    @State private var isSigningOut = false

    var body: some View {
        ZStack {
            ModalBackdrop(onTap: onClose)

            ModalCard {
                VStack(alignment: .leading, spacing: 16) {
                    ModalHeader(title: "Sign out?", onClose: onClose)
                    Text("Your data stays safe in your account. You'll need to sign in again to see it.")
                        .font(.fbBody(15))
                        .foregroundStyle(Color.fbSoftText)

                    FBPrimaryButton(label: isSigningOut ? "Signing out…" : "Sign out",
                                    enabled: !isSigningOut,
                                    destructive: true) {
                        Task {
                            isSigningOut = true
                            await onSignOut()
                            isSigningOut = false
                            onClose()
                        }
                    }
                }
            }
            .transition(.fbModalPush)
        }
        .transition(.opacity)
    }
}

// MARK: - Category manager

/// Add / rename / delete categories for payments or income. Same modal
/// shape as the payments manager: a list card with the edit form
/// stacking on top along the z-axis.
struct ManageCategoriesOverlay: View {
    @Bindable var store: FinanceBuddyStore
    let forIncome: Bool
    let onClose: () -> Void

    /// Form state: `original == nil` means a brand-new category.
    private struct Draft {
        var original: String?
        var name = ""
        var isValid: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }
    }
    @State private var showForm = false
    @State private var draft = Draft()

    private var categories: [String] {
        forIncome ? store.finances.incomeCategories : store.finances.paymentCategories
    }

    var body: some View {
        ZStack {
            ModalBackdrop {
                if showForm { showForm = false } else { onClose() }
            }

            ModalCard(depth: showForm ? 1 : 0) { list }

            if showForm {
                ModalCard { form }
                    .transition(.fbModalPush)
                    .zIndex(1)
            }
        }
        .transition(.opacity)
        .animation(.fbModal, value: showForm)
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 16) {
            ModalHeader(title: forIncome ? "Income categories" : "Payment categories",
                        onClose: onClose)

            // Long-press-drag a row to reorder; swipe left to delete;
            // tap to rename.
            List {
                ForEach(categories, id: \.self) { category in
                    ModalItemRow(name: category, detail: "",
                                 onEdit: {
                                     draft = Draft(original: category, name: category)
                                     showForm = true
                                 })
                        .modalListRow {
                            store.removeCategory(category, forIncome: forIncome)
                        }
                }
                .onMove { offsets, destination in
                    store.moveCategories(fromOffsets: offsets, toOffset: destination,
                                         forIncome: forIncome)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .frame(maxHeight: 280)
            .scrollEdgeEffectStyle(.soft, for: .vertical)

            if categories.count == 1 {
                Text("Items using a deleted category move to the first one in the list.")
                    .font(.fbBody(12))
                    .foregroundStyle(Color.fbSoftText)
            }

            FBPrimaryButton(label: "Add") {
                draft = Draft()
                showForm = true
            }
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 18) {
            ModalHeader(title: draft.original == nil ? "New category" : "Rename category") {
                showForm = false
            }

            PlainTextField(placeholder: "Name", text: $draft.name)

            FBPrimaryButton(label: "Save", enabled: draft.isValid,
                            action: saveDraft)
        }
    }

    private func saveDraft() {
        guard draft.isValid else { return }
        if let original = draft.original {
            store.renameCategory(from: original, to: draft.name, forIncome: forIncome)
        } else {
            store.addCategory(draft.name, forIncome: forIncome)
        }
        showForm = false
    }
}

#Preview {
    let store = FinanceBuddyStore(finances: .sample)
    return PreviewModalHost(store: store) { present in
        ProfileView(store: store, email: "rxzirr@gmail.com",
                    canSignOut: true, present: present)
            .safeAreaBar(edge: .top) { PageTitleBar(title: "Profile") }
    }
}

#Preview("Categories") {
    ZStack {
        FBBackground()
        ManageCategoriesOverlay(store: FinanceBuddyStore(finances: .sample),
                                forIncome: false, onClose: {})
    }
    .preferredColorScheme(.dark)
}
