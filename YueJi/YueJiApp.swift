import SwiftUI
import AppIntents

@main
struct YueJiApp: App {
    @StateObject private var model = LedgerModel()
    @AppStorage("appLanguage") private var language = "system"
    @AppStorage("appAppearance") private var appearance = "system"
    private var colorScheme: ColorScheme? { appearance == "dark" ? .dark : appearance == "light" ? .light : nil }
    init() { YueJiShortcuts.updateAppShortcutParameters() }
    var body: some Scene { WindowGroup { MainView().environmentObject(model).environment(\.locale, Locale(identifier: AppLanguage.localeID)).id(language).preferredColorScheme(colorScheme) } }
}
@MainActor final class LedgerModel: ObservableObject {
    @Published var ledger = Ledger()
    @Published var error: String?
    @Published var loaded = false
    func reload() { do { ledger = try LocalStore.shared.read(); loaded = true; try LocalStore.shared.change { try $0.postDue() }; ledger = try LocalStore.shared.read() } catch { self.error = error.localizedDescription } }
    func change(_ action: (inout Ledger) throws -> Void) {
        do { try LocalStore.shared.change(action); reload() } catch { self.error = error.localizedDescription }
    }
}
