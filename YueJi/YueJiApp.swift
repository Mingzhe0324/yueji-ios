import SwiftUI
import UIKit
import AppIntents
import UserNotifications

@main
struct YueJiApp: App {
    @StateObject private var model = LedgerModel()
    @AppStorage("appLanguage") private var language = "system"
    @AppStorage("appAppearance") private var appearance = "system"
    private var colorScheme: ColorScheme? { appearance == "dark" ? .dark : appearance == "light" ? .light : nil }
    init() { UNUserNotificationCenter.current().delegate = LedgerNotifications.shared; YueJiShortcuts.updateAppShortcutParameters() }
    var body: some Scene { WindowGroup { MainView().font(.body).fontDesign(.default).environment(\.defaultMinListRowHeight, 50).environmentObject(model).environment(\.locale, Locale(identifier: AppLanguage.localeID)).id(language).preferredColorScheme(colorScheme) } }
}
@MainActor final class LedgerModel: ObservableObject {
    let isPreview: Bool
    init(previewLedger: Ledger? = nil) {
        isPreview = previewLedger != nil
        if let previewLedger { ledger = previewLedger; loaded = true }
    }
    @Published var ledger = Ledger()
    @Published var error: String?
    @Published var didFinishLaunch = false
    @Published var loaded = false
    @Published var savedNotice: UUID?
    @Published private(set) var undoEntries: [Expense] = []
    private var undoExpiry: Task<Void, Never>?
    func deleteExpense(_ entry: Expense) throws {
        guard !isPreview else { return }
        try LocalStore.shared.change { try $0.deleteExpense(entry) }
        undoEntries.append(entry)
        savedNotice = nil
        undoExpiry?.cancel()
        undoExpiry = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(UIAccessibility.isVoiceOverRunning ? 30 : 10)) }
            catch { return }
            self?.undoEntries = []
        }
        reload(postRecurring: false)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
    func undoDeletion() {
        guard !isPreview, !undoEntries.isEmpty else { return }
        do {
            let entries = undoEntries
            try LocalStore.shared.change { try $0.restoreDeletedExpenses(entries) }
            undoExpiry?.cancel(); undoEntries = []
            reload(postRecurring: false)
            showSaved()
        } catch { self.error = error.localizedDescription }
    }
    func showSaved() {
        savedNotice = UUID()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
    func reload(postRecurring: Bool = true) { guard !isPreview else { return }; do { ledger = try LocalStore.shared.read(); loaded = true; if postRecurring { try LocalStore.shared.change { try $0.postDue() } }; ledger = try LocalStore.shared.read(); Task { await BudgetAlertService.shared.check() } } catch { self.error = error.localizedDescription } }
    func change(_ action: (inout Ledger) throws -> Void) {
        guard !isPreview else { return }
        do { try LocalStore.shared.change(action); reload() } catch { self.error = error.localizedDescription }
    }
}
