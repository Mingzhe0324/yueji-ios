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
    private var selectedLocale: Locale {
        Locale(identifier: language == "zh" ? "zh_Hans_MY" : language == "ms" ? "ms_MY" : language == "en" ? "en_MY" : AppLanguage.localeID)
    }
    init() { UserDefaults.standard.register(defaults: ["automationNotifications": true]); UNUserNotificationCenter.current().delegate = LedgerNotifications.shared; LedgerNotifications.registerActions(); YueJiShortcuts.updateAppShortcutParameters() }
    var body: some Scene { WindowGroup { MainView().font(.body).fontDesign(.default).environment(\.defaultMinListRowHeight, 50).environmentObject(model).environment(\.locale, selectedLocale).preferredColorScheme(colorScheme) } }
}
@MainActor final class LedgerModel: ObservableObject {
    let isPreview: Bool
    init(previewLedger: Ledger? = nil) {
        isPreview = previewLedger != nil
        if let previewLedger { ledger = previewLedger; loaded = true; didFinishLaunch = true }
    }
    @Published var ledger = Ledger() {
        didSet {
            ledgerRevision += 1
            overviewCache.removeAll(keepingCapacity: true)
            navigationIndex = nil
            refreshSignature = nil
        }
    }
    private(set) var ledgerRevision = 0
    private var refreshSignature: Data?
    private var refreshRequest = UUID()
    private var overviewCache: [String: OverviewSnapshot] = [:]
    private let projectionWorker = LedgerProjectionWorker()
    private var navigationIndex: LedgerNavigationIndex?
    @Published private(set) var operationKeys: Set<String> = []
    private var operations: [String: Task<Void, Never>] = [:]
    func isWorking(_ key: String) -> Bool { operationKeys.contains(key) }
    func waitForOperation(_ key: String) async { await operations[key]?.value }
    func perform<T>(key: String, using worker: LedgerRefreshWorker = .shared,
                    postRecurring: Bool = true,
                    action: @escaping @Sendable (inout Ledger) throws -> T,
                    completion: @escaping @MainActor (T) -> Void = { _ in },
                    failure: (@MainActor (Error) -> Void)? = nil) {
        guard !isPreview, !operationKeys.contains(key) else { return }
        operationKeys.insert(key)
        let task = Task {
            defer { operationKeys.remove(key); operations.removeValue(forKey: key) }
            do { let result = try await mutate(action, using: worker, postRecurring: postRecurring); completion(result) }
            catch is CancellationError { return }
            catch { if let failure { failure(error) } else { self.error = error.localizedDescription } }
        }
        operations[key] = task
    }
    var readIndex: LedgerNavigationIndex {
        if let navigationIndex { return navigationIndex }
        let prepared = LedgerNavigationIndex(ledger: ledger)
        navigationIndex = prepared
        return prepared
    }
    var friends: [FriendBalance] {
        readIndex.friends
    }
    var debts: [FriendDebtItem] { readIndex.debts }
    func debts(friend: String) -> [FriendDebtItem] { readIndex.debts(friend: friend) }
    func notice(id: String) -> TNGNotice? { readIndex.notice(id: id) }
    func expense(id: String) -> Expense? { readIndex.expense(id: id) }
    func settlement(id: String) -> FriendSettlement? { readIndex.settlement(id: id) }
    func settlements(friend: String) -> [FriendSettlement] { readIndex.settlements(friend: friend) }
    func overviewQuery(month: Date) -> LedgerTimelineQuery {
        LedgerTimelineQuery(revision: ledgerRevision, month: month, search: "", filter: LedgerFilter(), provider: "all")
    }
    func preparedOverview(month: Date, query: LedgerTimelineQuery) async throws -> OverviewSnapshot {
        guard query.revision == ledgerRevision else { throw CancellationError() }
        let snapshot = try await projectionWorker.overview(ledger: ledger, month: month, query: query)
        try Task.checkCancellation()
        guard query.revision == ledgerRevision else { throw CancellationError() }
        return snapshot
    }
    func preparedStatement(friend: String, month: Date?) async throws -> String {
        let revision = ledgerRevision
        let result = try await projectionWorker.statement(ledger: ledger, friend: friend, month: month)
        guard !Task.isCancelled, revision == ledgerRevision else { throw CancellationError() }
        return result
    }
    func preparedEntries(month: Date?, tag: String? = nil, friend: String? = nil) async throws -> ExpenseCollectionSnapshot {
        let revision = ledgerRevision
        let result = try await projectionWorker.entries(ledger: ledger, month: month, tag: tag, friend: friend)
        guard !Task.isCancelled, revision == ledgerRevision else { throw CancellationError() }
        return result
    }
    func preparedUpcoming(month: Date) async throws -> [PlannedCharge] {
        let revision = ledgerRevision
        let result = try await projectionWorker.upcoming(ledger: ledger, month: month)
        guard !Task.isCancelled, revision == ledgerRevision else { throw CancellationError() }
        return result
    }
    func preparedFriendSpending(friend: String, month: Date?) async throws -> FriendSpending {
        let revision = ledgerRevision
        let result = try await projectionWorker.friendSpending(ledger: ledger, friend: friend, month: month)
        guard !Task.isCancelled, revision == ledgerRevision else { throw CancellationError() }
        return result
    }
    func preparedCSV(month: Date?, splits: Bool) async throws -> Data {
        let revision = ledgerRevision
        let result = try await projectionWorker.csv(ledger: ledger, month: month, splits: splits)
        guard !Task.isCancelled, revision == ledgerRevision else { throw CancellationError() }
        return result
    }
    @discardableResult func mutate<T>(_ action: @escaping @Sendable (inout Ledger) throws -> T,
                                      using worker: LedgerRefreshWorker = .shared, postRecurring: Bool = true) async throws -> T {
        guard !isPreview else { throw CancellationError() }
        refreshRequest = UUID()
        let result = try await worker.mutate(postRecurring: postRecurring, action)
        // Re-read the latest file after committing: another action or an App Intent may
        // have written meanwhile. The refresh's request/revision guards prevent an
        // older response from overwriting a newer published ledger.
        if Task.isCancelled {
            // Cancellation after a disk commit cannot turn a successful write into
            // a stale on-screen balance. This unstructured refresh finishes publication.
            await Task { await self.refresh(postRecurring: false, using: worker) }.value
        } else { await refresh(postRecurring: false, using: worker) }
        return result
    }
    func expenseDetail(id: String) -> ExpenseDetailSnapshot? {
        // Preview/direct in-memory changes have no storage refresh to prepare an index.
        readIndex.detail(id: id)
    }
    func timeline(month: Date, query: LedgerTimelineQuery) async throws -> LedgerTimelineSnapshot {
        guard query.revision == ledgerRevision else { throw CancellationError() }
        let snapshot = try await projectionWorker.timeline(ledger: ledger, month: month, query: query)
        try Task.checkCancellation()
        guard query.revision == ledgerRevision else { throw CancellationError() }
        return snapshot
    }
    func overview(in month: Date) -> OverviewSnapshot {
        let key = TimeZone.current.identifier + "|" + monthKey(month)
        if let cached = overviewCache[key] { return cached }
        let snapshot = OverviewSnapshot(ledger: ledger, month: month)
        if overviewCache.count >= 6 { overviewCache.removeAll(keepingCapacity: true) }
        overviewCache[key] = snapshot
        return snapshot
    }
    @Published var error: String?
    @Published var didFinishLaunch = false
    @Published var loaded = false
    @Published var feedbackOwners = FeedbackPresentationOwners()
    @Published var savedNotice: UUID?
    @Published var feedbackMessage = ""
    @Published var feedbackMascot = false
    @Published var newTNGCount = 0
    @Published private(set) var undoEntries: [DeletedLedgerRecord] = []
    @Published private(set) var deletionInFlight = false
    private var undoExpiry: Task<Void, Never>?
    func deleteExpense(_ entry: Expense) async throws {
        guard !isPreview else { return }
        guard !deletionInFlight else { throw reviewError("请等待当前操作完成。", "Please wait for the current action.", "Tunggu tindakan semasa selesai.") }
        deletionInFlight = true; defer { deletionInFlight = false }
        let deletion = try await mutate({ try $0.deleteLedgerExpense(entry) }, postRecurring: false)
        finishDeletion(deletion)
    }
    func deleteAutomaticRecord(_ notice: TNGNotice) async throws {
        guard !isPreview else { return }
        guard !deletionInFlight else { throw reviewError("请等待当前操作完成。", "Please wait for the current action.", "Tunggu tindakan semasa selesai.") }
        deletionInFlight = true; defer { deletionInFlight = false }
        let deletion = try await mutate({ try $0.deleteAutomaticRecord(notice) }, postRecurring: false)
        finishDeletion(deletion)
    }
    private func finishDeletion(_ deletion: DeletedLedgerRecord) {
        undoEntries.append(deletion)
        savedNotice = nil
        undoExpiry?.cancel()
        undoExpiry = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(UIAccessibility.isVoiceOverRunning ? 30 : 10)) }
            catch { return }
            self?.undoEntries = []
        }
        // The committed snapshot is already published; do not animate the whole navigation tree.
        FeedbackHaptics.success()
        FeedbackSounds.shared.play(.deleted)
    }
    func undoDeletion() async {
        guard !isPreview, !undoEntries.isEmpty, !deletionInFlight else { return }
        deletionInFlight = true; defer { deletionInFlight = false }
        do {
            let entries = undoEntries
            undoExpiry?.cancel()
            try await mutate({ try $0.restoreDeletedRecords(entries) }, postRecurring: false)
            undoExpiry?.cancel(); undoEntries = []
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
        Task { await refresh(postRecurring: postRecurring) }
    }
    func refresh(postRecurring: Bool = true, using worker: LedgerRefreshWorker = .shared) async {
        guard !isPreview, !Task.isCancelled else { return }
        let revision = ledgerRevision
        let request = UUID()
        refreshRequest = request
        do {
            let snapshot = try await worker.snapshot(postRecurring: postRecurring)
            // An edit, restore or newer refresh must win over an older background read.
            guard !Task.isCancelled, revision == ledgerRevision, request == refreshRequest else { return }
            guard !loaded || refreshSignature != snapshot.signature else { return }
            let index = try await projectionWorker.index(ledger: snapshot.ledger, signature: snapshot.signature)
            guard !Task.isCancelled, revision == ledgerRevision, request == refreshRequest else { return }
            publish(snapshot, index: index)
        } catch is CancellationError { return }
        catch {
            guard !Task.isCancelled, revision == ledgerRevision, request == refreshRequest else { return }
            self.error = error.localizedDescription
        }
    }
    private func publish(_ snapshot: (ledger: Ledger, signature: Data), index: LedgerNavigationIndex? = nil) {
        guard !loaded || refreshSignature != snapshot.signature else { return }
        let fresh = snapshot.ledger
        let ids = Set(fresh.tngNotices.map(\.id))
        let observed = UserDefaults.standard.stringArray(forKey: "viewedTNGNoticeIDs").map { Set($0) }
        let pending = Set(UserDefaults.standard.stringArray(forKey: "pendingTNGNoticeIDs") ?? [])
        var tracker = TNGReviewTracker(observed: observed, pending: pending)
        tracker.observe(ids)
        if newTNGCount != tracker.pending.count { newTNGCount = tracker.pending.count }
        if observed != ids { UserDefaults.standard.set(Array(ids), forKey: "viewedTNGNoticeIDs") }
        if pending != tracker.pending { UserDefaults.standard.set(Array(tracker.pending), forKey: "pendingTNGNoticeIDs") }
        ledger = fresh
        navigationIndex = index
        refreshSignature = snapshot.signature
        if !loaded { loaded = true }
        Task { await BudgetAlertService.shared.check() }
    }
    func dismissNewTNG() {
        newTNGCount = 0
        if !isPreview { UserDefaults.standard.set([String](), forKey: "pendingTNGNoticeIDs") }
    }
    func change(_ action: @escaping @Sendable (inout Ledger) throws -> Void) {
        perform(key: UUID().uuidString, action: action)
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
            audio.volume = cue == .launch ? 0.85 : 0.55
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
