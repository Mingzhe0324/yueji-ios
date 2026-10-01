import SwiftUI
import UIKit
import AppIntents
import UserNotifications
import AVFoundation

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
    @Published private(set) var removingExpenseIDs: Set<String> = []
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
        let playful = UserDefaults.standard.object(forKey: "playfulAnimations") as? Bool ?? true
        if playful && !UIAccessibility.isReduceMotionEnabled {
            withAnimation(.easeIn(duration: 0.18)) { _ = removingExpenseIDs.insert(entry.id) }
            Task { [weak self] in
                do { try await Task.sleep(for: .milliseconds(190)) } catch { return }
                guard let self else { return }
                withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
                    self.reload(postRecurring: false)
                    self.removingExpenseIDs.remove(entry.id)
                }
            }
        } else { reload(postRecurring: false) }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
    func undoDeletion() {
        guard !isPreview, !undoEntries.isEmpty else { return }
        do {
            let entries = undoEntries
            try LocalStore.shared.change { try $0.restoreDeletedExpenses(entries) }
            undoExpiry?.cancel(); undoEntries = []
            removingExpenseIDs.removeAll()
            reload(postRecurring: false)
            showSaved()
        } catch { self.error = error.localizedDescription }
    }
    func showSaved(sound: FeedbackSounds.Cue = .saved) {
        savedNotice = UUID()
        if !isPreview { FeedbackSounds.shared.play(sound) }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
    func reload(postRecurring: Bool = true) { guard !isPreview else { return }; do { ledger = try LocalStore.shared.read(); loaded = true; if postRecurring { try LocalStore.shared.change { try $0.postDue() } }; ledger = try LocalStore.shared.read(); Task { await BudgetAlertService.shared.check() } } catch { self.error = error.localizedDescription } }
    func change(_ action: (inout Ledger) throws -> Void) {
        guard !isPreview else { return }
        do { try LocalStore.shared.change(action); reload() } catch { self.error = error.localizedDescription }
    }
}

/// Ambient audio respects silent mode, mixes with music, and never requests a microphone.
@MainActor final class FeedbackSounds {
    static let shared = FeedbackSounds()
    enum Cue: String { case launch = "LaunchChime", saved = "SavedChime", goal = "GoalChime" }
    private var player: AVAudioPlayer?
    private var releaseTask: Task<Void, Never>?
    func play(_ cue: Cue) {
        let enabled = UserDefaults.standard.object(forKey: "animationSounds") as? Bool ?? true
        guard enabled, UIApplication.shared.applicationState == .active,
              let asset = NSDataAsset(name: cue.rawValue) else { return }
        stop()
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.ambient, mode: .default)
            try session.setActive(true)
            let audio = try AVAudioPlayer(data: asset.data)
            audio.volume = 0.55
            audio.prepareToPlay()
            player = audio
            guard audio.play() else { stop(); return }
            let duration = audio.duration
            releaseTask = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(duration + 0.1)) } catch { return }
                self?.stop()
            }
        } catch { stop() } // An optional cue never blocks bookkeeping.
    }
    func stop() {
        releaseTask?.cancel(); releaseTask = nil
        player?.stop(); player = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
