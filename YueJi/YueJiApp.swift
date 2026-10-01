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
    @Published var feedbackOwners = FeedbackPresentationOwners()
    @Published var savedNotice: UUID?
    @Published var feedbackMessage = ""
    @Published var feedbackMascot = false
    @Published var newTNGCount = 0
    @Published private(set) var undoEntries: [DeletedLedgerRecord] = []
    @Published private(set) var removingExpenseIDs: Set<String> = []
    private var undoExpiry: Task<Void, Never>?
    func deleteExpense(_ entry: Expense) throws {
        guard !isPreview else { return }
        var deletion: DeletedLedgerRecord?
        try LocalStore.shared.change { deletion = try $0.deleteLedgerExpense(entry) }
        guard let deletion else { return }
        finishDeletion(deletion, id: entry.id)
    }
    func deleteAutomaticRecord(_ notice: TNGNotice) throws {
        guard !isPreview else { return }
        var deletion: DeletedLedgerRecord?
        try LocalStore.shared.change { deletion = try $0.deleteAutomaticRecord(notice) }
        guard let deletion else { return }
        finishDeletion(deletion, id: notice.id)
    }
    private func finishDeletion(_ deletion: DeletedLedgerRecord, id: String) {
        undoEntries.append(deletion)
        savedNotice = nil
        undoExpiry?.cancel()
        undoExpiry = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(UIAccessibility.isVoiceOverRunning ? 30 : 10)) }
            catch { return }
            self?.undoEntries = []
        }
        let playful = UserDefaults.standard.object(forKey: "playfulAnimations") as? Bool ?? true
        if playful && !UIAccessibility.isReduceMotionEnabled {
            withAnimation(.easeIn(duration: 0.18)) { _ = removingExpenseIDs.insert(id) }
            Task { [weak self] in
                do { try await Task.sleep(for: .milliseconds(190)) } catch { return }
                guard let self else { return }
                withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
                    self.reload(postRecurring: false)
                    self.removingExpenseIDs.remove(id)
                }
            }
        } else { reload(postRecurring: false) }
        FeedbackHaptics.success()
        FeedbackSounds.shared.play(.deleted)
    }
    func undoDeletion() {
        guard !isPreview, !undoEntries.isEmpty else { return }
        do {
            let entries = undoEntries
            try LocalStore.shared.change { try $0.restoreDeletedRecords(entries) }
            undoExpiry?.cancel(); undoEntries = []
            removingExpenseIDs.removeAll()
            reload(postRecurring: false)
            showSaved(message: tr("已恢复", "Restored", "Dipulihkan"), sound: .restored)
        } catch { self.error = error.localizedDescription }
    }
    func showSaved(message: String? = nil, sound: FeedbackSounds.Cue = .saved, firstEntry: Bool = false) {
        feedbackMessage = message ?? tr("已保存", "Saved", "Disimpan")
        feedbackMascot = sound == .goal || (firstEntry && !UserDefaults.standard.bool(forKey: "celebratedFirstEntry"))
        if firstEntry && !isPreview { UserDefaults.standard.set(true, forKey: "celebratedFirstEntry") }
        savedNotice = UUID()
        if !isPreview {
            FeedbackSounds.shared.play(sound); FeedbackHaptics.success()
            if UIAccessibility.isVoiceOverRunning { UIAccessibility.post(notification: .announcement, argument: feedbackMessage) }
        }
    }
    func reload(postRecurring: Bool = true) {
        guard !isPreview else { return }
        do {
            if postRecurring { try LocalStore.shared.change { try $0.postDue() } }
            let fresh = try LocalStore.shared.read()
            let ids = Set(fresh.tngNotices.map(\.id))
            var tracker = TNGReviewTracker(
                observed: UserDefaults.standard.stringArray(forKey: "viewedTNGNoticeIDs").map { Set($0) },
                pending: Set(UserDefaults.standard.stringArray(forKey: "pendingTNGNoticeIDs") ?? []))
            tracker.observe(ids)
            newTNGCount = tracker.pending.count
            UserDefaults.standard.set(Array(ids), forKey: "viewedTNGNoticeIDs")
            UserDefaults.standard.set(Array(tracker.pending), forKey: "pendingTNGNoticeIDs")
            ledger = fresh; loaded = true
            Task { await BudgetAlertService.shared.check() }
        } catch { self.error = error.localizedDescription }
    }
    func dismissNewTNG() {
        newTNGCount = 0
        if !isPreview { UserDefaults.standard.set([String](), forKey: "pendingTNGNoticeIDs") }
    }
    func change(_ action: (inout Ledger) throws -> Void) {
        guard !isPreview else { return }
        do { try LocalStore.shared.change(action); reload() } catch { self.error = error.localizedDescription }
    }
}

/// Ambient audio respects silent mode, mixes with music, and never requests a microphone.
@MainActor final class FeedbackSounds {
    static let shared = FeedbackSounds()
    enum Cue: String { case launch = "LaunchChime", saved = "SavedChime", goal = "GoalChime", deleted = "DeleteCue", restored = "RestoreCue", deposit = "DepositCue" }
    static func permits(_ cue: Cue, mode: String, enabled: Bool) -> Bool {
        enabled && mode != "off" && (mode != "success" || cue == .saved || cue == .goal)
    }
    private var player: AVAudioPlayer?
    private var releaseTask: Task<Void, Never>?
    func play(_ cue: Cue) {
        let enabled = UserDefaults.standard.object(forKey: "animationSounds") as? Bool ?? true
        let mode = UserDefaults.standard.string(forKey: "soundFeedbackMode") ?? "full"
        guard Self.permits(cue, mode: mode, enabled: enabled), UIApplication.shared.applicationState == .active,
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

@MainActor enum FeedbackHaptics {
    static var enabled: Bool { UserDefaults.standard.object(forKey: "feedbackHaptics") as? Bool ?? true }
    static func success() { if enabled { UINotificationFeedbackGenerator().notificationOccurred(.success) } }
    static func error() { if enabled { UINotificationFeedbackGenerator().notificationOccurred(.error) } }
    static func selection() { if enabled { UISelectionFeedbackGenerator().selectionChanged() } }
}
