import SwiftUI
import AppIntents

@main
struct YueJiApp: App {
    @StateObject private var model = LedgerModel()
    init() { YueJiShortcuts.updateAppShortcutParameters() }
    var body: some Scene { WindowGroup { MainView().environmentObject(model) } }
}
@MainActor final class LedgerModel: ObservableObject {
    @Published var ledger = Ledger()
    @Published var error: String?
    @Published var loaded = false
    func reload() { do { ledger = try LocalStore.shared.read(); loaded = true } catch { self.error = error.localizedDescription } }
    func change(_ action: (inout Ledger) throws -> Void) {
        do { try LocalStore.shared.change(action); reload() } catch { self.error = error.localizedDescription }
    }
}
