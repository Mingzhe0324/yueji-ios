import SwiftUI
import UIKit
import UniformTypeIdentifiers
import CryptoKit

/// Automatic copies of the ledger in an external folder picked in Files. iCloud Drive
/// is recommended; local folders do not protect against losing the phone. The app's
/// own container is rejected because it is removed on uninstall.
/// Access to the folder is kept with a security-scoped bookmark, so no iCloud entitlement
/// is needed. Each copy is the same complete JSON backup as "Save a complete backup".

/// How often a copy is made.
enum AutoBackupFrequency: String, CaseIterable, Identifiable {
    case everyChange, daily, weekly
    var id: String { rawValue }
    /// A little under the period, so a copy made one evening is renewed the next.
    var interval: TimeInterval {
        switch self { case .everyChange: return 0; case .daily: return 20 * 3600; case .weekly: return 6.5 * 24 * 3600 }
    }
    var label: String {
        switch self {
        case .everyChange: return tr("每次更改后", "After every change", "Selepas setiap perubahan")
        case .daily: return tr("每天", "Daily", "Harian")
        case .weekly: return tr("每周", "Weekly", "Mingguan")
        }
    }
}

/// The settings and status, in UserDefaults so the settings page can observe them.
enum AutoBackupKeys {
    static let bookmark = "autoBackupBookmark"
    static let folderName = "autoBackupFolderName"
    static let frequency = "autoBackupFrequency"
    static let keep = "autoBackupKeep"
    /// When the newest copy was written (seconds since 1970).
    static let lastDate = "autoBackupLastDate"
    /// When the folder was last brought up to date, with or without a new copy.
    static let lastChecked = "autoBackupLastChecked"
    static let lastFile = "autoBackupLastFile"
    /// SHA-256 of the ledger file the newest copy was made from.
    static let lastHash = "autoBackupLastHash"
    static let lastError = "autoBackupLastError"
    static let defaultKeep = 14
    static let keepChoices = [7, 14, 30]
}

/// Names of the automatic copies, and which ones to remove.
enum AutoBackupFiles {
    static let prefix = "YueJi-auto-"
    /// "YueJi-auto-2026-10-24-183005.json": sorts by time.
    static func name(for date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return prefix + formatter.string(from: date) + ".json"
    }
    /// The automatic copy a folder entry stands for, or nil for anything else. iCloud Drive
    /// lists a copy that is only in the cloud as ".name.icloud".
    static func backupName(of entry: String) -> String? {
        var name = entry
        if name.hasPrefix("."), name.hasSuffix(".icloud") { name = String(name.dropFirst().dropLast(7)) }
        guard name.hasPrefix(prefix), name.hasSuffix(".json") else { return nil }
        let stem = String(name.dropFirst(prefix.count).dropLast(5))
        // Keep old backups readable; new names also have milliseconds and a UUID to
        // prevent rapid saves or another installation from overwriting a copy.
        let pattern = #"^\d{4}-\d{2}-\d{2}-\d{6}(-\d{3}-[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12})?$"#
        guard stem.range(of: pattern, options: .regularExpression) != nil else { return nil }
        return name
    }
    /// The folder entries holding automatic copies older than the newest `keep`. Nothing
    /// else in the folder is ever included.
    static func expired(_ entries: [String], keep: Int) -> [String] {
        let copies = entries.compactMap { entry in backupName(of: entry).map { (entry: entry, name: $0) } }
            .sorted { $0.name > $1.name }
        return copies.dropFirst(max(1, keep)).map { $0.entry }
    }
}

enum AutoBackupPolicy {
    static func isDue(now: Date, last: Date?, frequency: AutoBackupFrequency) -> Bool {
        guard let last else { return true }
        // A clock moved back makes it due rather than never.
        return now < last || now.timeIntervalSince(last) >= frequency.interval
    }
}

enum AutoBackupOutcome: Equatable {
    case notConfigured, notDue, busy
    /// Nothing changed since the newest copy, which is still in the folder.
    case unchanged
    case saved(file: String)
    case failed(String)
}

struct AutoBackupJob {
    let bookmark: Data
    let force: Bool
    let lastHash: String?
    let keep: Int
    let now: Date
}

struct AutoBackupResult {
    var outcome: AutoBackupOutcome
    var hash: String? = nil
    /// iOS asked for a fresh bookmark: the folder moved or was renamed.
    var refreshedBookmark: Data? = nil
}

/// Reads the ledger and writes the copy away from the main actor.
actor AutoBackupWriter {
    static let shared = AutoBackupWriter()
    private let store: LocalStore
    init(store: LocalStore = .shared) { self.store = store }

    func validateDestination(_ folder: URL) throws {
        let access = folder.startAccessingSecurityScopedResource()
        defer { if access { folder.stopAccessingSecurityScopedResource() } }
        // A fresh install must not rotate its previous installation's history by
        // configuring an empty ledger over the old backup folder.
        if try store.readSnapshot().signature.isEmpty, try Self.hasCopy(in: folder) {
            throw reviewError("此文件夹里已有备份。请先恢复以前的账本，或选择一个新的空文件夹。", "This folder already contains backups. Restore your previous ledger first, or choose a new empty folder.", "Folder ini sudah mengandungi sandaran. Pulihkan lejar terdahulu dahulu, atau pilih folder kosong baharu.")
        }
    }

    func perform(_ job: AutoBackupJob) -> AutoBackupResult {
        var stale = false
        let folder: URL
        do {
            folder = try URL(resolvingBookmarkData: job.bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
        } catch {
            return AutoBackupResult(outcome: .failed(tr("找不到备份文件夹，请重新选择。", "The backup folder can't be found. Choose it again.", "Folder sandaran tidak ditemui. Pilih semula.")))
        }
        let access = folder.startAccessingSecurityScopedResource()
        defer { if access { folder.stopAccessingSecurityScopedResource() } }
        var result: AutoBackupResult
        do {
            let snapshot = try store.readSnapshot()
            let hash = Self.digest(snapshot.signature)
            if !job.force, hash == job.lastHash, try Self.hasCopy(in: folder) {
                result = AutoBackupResult(outcome: .unchanged, hash: hash)
            } else {
                let name = try Self.write(LocalStore.exportData(snapshot.ledger), into: folder, now: job.now, keep: job.keep)
                result = AutoBackupResult(outcome: .saved(file: name), hash: hash)
            }
        } catch {
            result = AutoBackupResult(outcome: .failed(error.localizedDescription))
        }
        if stale {
            result.refreshedBookmark = try? folder.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
        }
        return result
    }

    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Writes one copy, then removes the automatic copies past `keep`. File coordination
    /// lets iCloud Drive see only whole files.
    static func write(_ data: Data, into folder: URL, now: Date, keep: Int) throws -> String {
        // Round-trip validation happens before any existing copies can be rotated.
        _ = try LocalStore.decode(data)
        let milliseconds = Int((now.timeIntervalSince1970 - floor(now.timeIntervalSince1970)) * 1000)
        let name = String(AutoBackupFiles.name(for: now).dropLast(5)) + String(format: "-%03d-", milliseconds) + UUID().uuidString + ".json"
        try coordinate(writing: folder.appendingPathComponent(name), options: .forReplacing) { url in
            try data.write(to: url, options: .atomic)
        }
        let entries = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        for entry in AutoBackupFiles.expired(entries, keep: keep) where entry != name {
            // A copy that can't be removed now is tried again next time.
            try? coordinate(writing: folder.appendingPathComponent(entry), options: .forDeleting) { url in
                try FileManager.default.removeItem(at: url)
            }
        }
        return name
    }

    static func hasCopy(in folder: URL) throws -> Bool {
        try FileManager.default.contentsOfDirectory(atPath: folder.path).contains { AutoBackupFiles.backupName(of: $0) != nil }
    }

    private static func coordinate(writing url: URL, options: NSFileCoordinator.WritingOptions, _ body: (URL) throws -> Void) throws {
        var coordinationError: NSError?
        var bodyError: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: options, error: &coordinationError) { actual in
            do { try body(actual) } catch { bodyError = error }
        }
        if let coordinationError { throw coordinationError }
        if let bodyError { throw bodyError }
    }
}

/// Every-change mode also runs after committed writes. Daily/weekly modes are checked
/// on opening/leaving the app. "Back up now" always writes one.
@MainActor enum AutoBackup {
    private static var running = false
    private static var changePending = false

    static var isConfigured: Bool { UserDefaults.standard.data(forKey: AutoBackupKeys.bookmark) != nil }
    static var frequency: AutoBackupFrequency {
        AutoBackupFrequency(rawValue: UserDefaults.standard.string(forKey: AutoBackupKeys.frequency) ?? "") ?? .everyChange
    }
    static var keep: Int {
        let value = UserDefaults.standard.integer(forKey: AutoBackupKeys.keep)
        return value > 0 ? value : AutoBackupKeys.defaultKeep
    }

    @discardableResult
    static func run(force: Bool = false, now: Date = Date()) async -> AutoBackupOutcome {
        let defaults = UserDefaults.standard
        guard let bookmark = defaults.data(forKey: AutoBackupKeys.bookmark) else { return .notConfigured }
        let checked = defaults.object(forKey: AutoBackupKeys.lastChecked) as? Double
        guard force || AutoBackupPolicy.isDue(now: now, last: checked.map { Date(timeIntervalSince1970: $0) }, frequency: frequency) else {
            return .notDue
        }
        guard !running else { return .busy }
        running = true
        defer {
            running = false
            // A commit arriving while IO is suspended must get its own fresh snapshot.
            if changePending {
                changePending = false
                ledgerDidChange()
            }
        }
        let job = AutoBackupJob(bookmark: bookmark, force: force, lastHash: defaults.string(forKey: AutoBackupKeys.lastHash), keep: keep, now: now)
        let result = await AutoBackupWriter.shared.perform(job)
        record(result, now: now, bookmark: bookmark)
        return result.outcome
    }

    private static func record(_ result: AutoBackupResult, now: Date, bookmark: Data) {
        let defaults = UserDefaults.standard
        // The folder may have been changed or turned off while the copy was being made.
        guard defaults.data(forKey: AutoBackupKeys.bookmark) == bookmark else { return }
        if let refreshed = result.refreshedBookmark { defaults.set(refreshed, forKey: AutoBackupKeys.bookmark) }
        switch result.outcome {
        case .saved(let file):
            defaults.set(now.timeIntervalSince1970, forKey: AutoBackupKeys.lastDate)
            defaults.set(now.timeIntervalSince1970, forKey: AutoBackupKeys.lastChecked)
            defaults.set(file, forKey: AutoBackupKeys.lastFile)
            defaults.set(result.hash, forKey: AutoBackupKeys.lastHash)
            defaults.removeObject(forKey: AutoBackupKeys.lastError)
        case .unchanged:
            defaults.set(now.timeIntervalSince1970, forKey: AutoBackupKeys.lastChecked)
            defaults.removeObject(forKey: AutoBackupKeys.lastError)
        case .failed(let message):
            defaults.set(message, forKey: AutoBackupKeys.lastError)
        case .notConfigured, .notDue, .busy:
            break
        }
    }

    /// Keeps access to a folder picked in Files. A new folder starts its own history.
    static func choose(_ url: URL) async throws {
        let path = url.resolvingSymlinksInPath().standardizedFileURL.path
        let home = URL(fileURLWithPath: NSHomeDirectory()).resolvingSymlinksInPath().standardizedFileURL.path
        guard path != home, !path.hasPrefix(home + "/") else {
            throw reviewError("请选择 iCloud Drive 中的文件夹，不要选择月记自己的文件夹。", "Choose a folder in iCloud Drive, outside YueJi's own folder.", "Pilih folder dalam iCloud Drive, di luar folder YueJi sendiri.")
        }
        try await AutoBackupWriter.shared.validateDestination(url)
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let bookmark = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
        let defaults = UserDefaults.standard
        clearStatus()
        defaults.set(bookmark, forKey: AutoBackupKeys.bookmark)
        defaults.set(FileManager.default.displayName(atPath: url.path), forKey: AutoBackupKeys.folderName)
    }

    /// Stops making copies. The copies already in the folder stay there.
    static func turnOff() {
        changePending = false
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: AutoBackupKeys.bookmark)
        defaults.removeObject(forKey: AutoBackupKeys.folderName)
        clearStatus()
    }

    private static func clearStatus() {
        let defaults = UserDefaults.standard
        for key in [AutoBackupKeys.lastDate, AutoBackupKeys.lastChecked, AutoBackupKeys.lastFile, AutoBackupKeys.lastHash, AutoBackupKeys.lastError] {
            defaults.removeObject(forKey: key)
        }
    }

    /// On leaving the app iOS allows a short while; the copy is written atomically, so one
    /// cut short leaves no partial file and is made again next time.
    static func runInBackground() {
        guard isConfigured else { return }
        let token = BackgroundTaskToken()
        token.begin()
        Task {
            await run()
            token.end()
        }
    }

    /// Called only after a committed write in the production store, including Shortcuts.
    static func ledgerDidChange() {
        guard isConfigured, frequency == .everyChange else { return }
        if running { changePending = true; return }
        runInBackground()
    }
}

/// The background time for one copy, ended once by whichever comes first: the copy or iOS.
final class BackgroundTaskToken: @unchecked Sendable {
    private let lock = NSLock()
    private var id = UIBackgroundTaskIdentifier.invalid
    private var ended = false
    @MainActor func begin() {
        let started = UIApplication.shared.beginBackgroundTask(withName: "YueJi backup") { [weak self] in self?.end() }
        lock.lock()
        if ended {
            lock.unlock()
            UIApplication.shared.endBackgroundTask(started)
            return
        }
        id = started
        lock.unlock()
    }
    func end() {
        lock.lock()
        let current = id
        id = .invalid
        ended = true
        lock.unlock()
        guard current != .invalid else { return }
        DispatchQueue.main.async { UIApplication.shared.endBackgroundTask(current) }
    }
}

// MARK: - Settings

/// The automatic backup settings at the top of Backups & export.
struct AutoBackupSection: View {
    @Environment(\.locale) private var uiLocale
    @EnvironmentObject private var model: LedgerModel
    @AppStorage(AutoBackupKeys.bookmark) private var bookmark = Data()
    @AppStorage(AutoBackupKeys.folderName) private var folderName = ""
    @AppStorage(AutoBackupKeys.frequency) private var frequency = AutoBackupFrequency.everyChange.rawValue
    @AppStorage(AutoBackupKeys.keep) private var keep = AutoBackupKeys.defaultKeep
    @AppStorage(AutoBackupKeys.lastDate) private var lastDate = 0.0
    @AppStorage(AutoBackupKeys.lastError) private var lastError = ""
    @State private var choosing = false
    @State private var working = false
    @State private var confirmingOff = false
    var body: some View {
        let _ = uiLocale.identifier
        Section {
            if bookmark.isEmpty {
                Label {
                    Text(tr("在 iCloud Drive 新建一个「YueJi Backups」文件夹并选择它。备份会保留在 App 外。卸载前请确认备份成功，并在「文件」中等待 iCloud 上传完成。本机文件不能保护手机遗失后的数据。",
                            "Create and choose a YueJi Backups folder in iCloud Drive. Backups stay outside the app. Before uninstalling, check that a backup succeeded and wait for its iCloud upload in Files. Local folders cannot protect against losing your phone.",
                            "Cipta dan pilih folder YueJi Backups dalam iCloud Drive. Sandaran kekal di luar aplikasi. Sebelum menyahpasang, pastikan sandaran berjaya dan muat naik iCloud selesai dalam Files. Folder setempat tidak melindungi data jika telefon hilang."))
                        .font(.subheadline)
                } icon: {
                    Image(systemName: "externaldrive.badge.icloud").foregroundStyle(IslandTheme.accent)
                }
                chooseButton(tr("选择备份文件夹", "Choose a backup folder", "Pilih folder sandaran"), symbol: "folder.badge.plus")
                    .accessibilityIdentifier("backup.auto.choose")
            } else {
                LabeledContent(tr("文件夹", "Folder", "Folder"), value: folderName)
                Picker(tr("频率", "How often", "Kekerapan"), selection: $frequency) {
                    ForEach(AutoBackupFrequency.allCases) { Text($0.label).tag($0.rawValue) }
                }
                .onChange(of: frequency) { _, _ in backUpNow() }
                Picker(tr("保留", "Keep", "Simpan"), selection: $keep) {
                    ForEach(AutoBackupKeys.keepChoices, id: \.self) { count in Text(copies(count)).tag(count) }
                }
                LabeledContent(tr("上次备份", "Last backup", "Sandaran terakhir"), value: lastLabel)
                if !lastError.isEmpty {
                    Label(lastError, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote).foregroundStyle(.orange)
                }
                Button(action: backUpNow) {
                    HStack {
                        Label(tr("立即备份", "Back up now", "Sandarkan sekarang"), systemImage: "arrow.clockwise.icloud")
                        Spacer(minLength: 8)
                        if working { ProgressView().controlSize(.small) }
                    }
                }
                .disabled(working)
                .accessibilityIdentifier("backup.auto.now")
                chooseButton(tr("更换文件夹", "Change folder", "Tukar folder"), symbol: "folder")
                Button(tr("关闭自动备份", "Turn off automatic backup", "Matikan sandaran automatik"), role: .destructive) {
                    confirmingOff = true
                }
                .confirmationDialog(tr("关闭自动备份？", "Turn off automatic backup?", "Matikan sandaran automatik?"), isPresented: $confirmingOff, titleVisibility: .visible) {
                    Button(tr("关闭", "Turn off", "Matikan"), role: .destructive) { AutoBackup.turnOff() }
                } message: {
                    Text(tr("已经存在文件夹里的备份会保留。", "Copies already in the folder stay there.", "Salinan yang sudah ada dalam folder kekal di sana."))
                }
            }
        } header: {
            Text(tr("自动备份", "Automatic backup", "Sandaran automatik"))
        } footer: {
            if !bookmark.isEmpty {
                Text(tr("「每次更改后」会在账本保存后备份；每天或每周会在打开或离开 App 时检查。重新安装后，选择「恢复以前的账本」，恢复最新备份，再选择备份文件夹。仅保留所选数量的自动备份。备份成功表示文件已写入，不代表 iCloud 已完成上传。",
                        "After every change backs up saved ledger changes; daily or weekly checks run when you open or leave the app. After reinstalling, choose Restore previous ledger, restore your newest backup, then choose your backup folder again. Only the selected number of automatic copies is kept. A successful write does not confirm that iCloud has finished uploading.",
                        "Selepas setiap perubahan menyandarkan perubahan lejar yang disimpan; semakan harian atau mingguan berjalan apabila aplikasi dibuka atau ditinggalkan. Selepas pasang semula, pilih Pulihkan lejar terdahulu, pulihkan sandaran terkini, kemudian pilih folder sandaran semula. Hanya bilangan salinan dipilih disimpan. Penulisan berjaya tidak mengesahkan muat naik iCloud selesai."))
            }
        }
    }
    private func chooseButton(_ title: String, symbol: String) -> some View {
        Button { choosing = true } label: { Label(title, systemImage: symbol) }
            .disabled(working)
            .sheet(isPresented: $choosing) {
                FolderPicker { url in
                    choosing = false
                    guard let url else { return }
                    working = true
                    Task {
                        do {
                            try await AutoBackup.choose(url)
                            working = false
                            backUpNow()
                        } catch {
                            working = false
                            model.error = error.localizedDescription
                        }
                    }
                }
                .ignoresSafeArea()
            }
    }
    private var lastLabel: String {
        lastDate > 0 ? dateLabel(Date(timeIntervalSince1970: lastDate), time: true) : tr("尚未备份", "Not yet", "Belum lagi")
    }
    private func copies(_ count: Int) -> String {
        tr("\(count) 份", "\(count) copies", "\(count) salinan")
    }
    private func backUpNow() {
        guard !working else { return }
        working = true
        Task {
            let outcome = await AutoBackup.run(force: true)
            working = false
            switch outcome {
            case .saved:
                model.showSaved(message: tr("已备份到「\(folderName)」", "Backed up to \(folderName)", "Disandarkan ke \(folderName)"))
            case .failed(let message):
                model.error = message
            default:
                break
            }
        }
    }
}

/// Available before the usage guide as well as in Settings. Reading a file only previews
/// it; RestorePreviewView retains the explicit replacement confirmation and recovery copy.
struct BackupRecoverySection: View {
    @Environment(\.locale) private var uiLocale
    var onRestored: () -> Void = {}
    @State private var importing = false
    @State private var preview: RestorePreview?
    @State private var reading = false
    @State private var readTask: Task<Void, Never>?
    @State private var request = UUID()
    @State private var restored = false
    @State private var error: String?

    var body: some View {
        let _ = uiLocale.identifier
        Section {
            Text(tr("重新安装了月记？从 iCloud Drive 选择以前最新的 YueJi-auto 备份，预览后恢复账本。请先恢复，再开启自动备份。",
                    "Reinstalled YueJi? Choose your newest previous YueJi-auto backup in iCloud Drive, preview it, and restore your ledger. Restore first, then enable automatic backup.",
                    "Pasang semula YueJi? Pilih sandaran YueJi-auto terdahulu yang terkini dalam iCloud Drive, pratonton dan pulihkan lejar anda. Pulihkan dahulu, kemudian aktifkan sandaran automatik."))
                .font(.subheadline)
            Button { importing = true } label: {
                Label(tr("恢复以前的账本", "Restore previous ledger", "Pulihkan lejar terdahulu"), systemImage: "arrow.down.doc")
            }
            .disabled(reading)
            .accessibilityIdentifier("backup.recover")
            if reading { ProgressView(tr("正在读取备份…", "Reading backup…", "Membaca sandaran…")) }
            if restored {
                Label(tr("账本已恢复。请选择备份文件夹，继续保护之后的更改。", "Ledger restored. Choose a backup folder to protect future changes.", "Lejar dipulihkan. Pilih folder sandaran untuk melindungi perubahan seterusnya."), systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text(tr("重新安装后恢复", "Recovery after reinstalling", "Pemulihan selepas pasang semula"))
        } footer: {
            Text(tr("可恢复账目、预算、分账、固定消费及储蓄目标等账本数据。外观、通知权限和未保存的草稿不会随账本恢复。没有保存在 App 外的备份，卸载后无法找回本机账本。",
                    "Restores ledger data including entries, budgets, splits, recurring bills and savings goals. Appearance, notification permissions and unsaved drafts are not restored. Without a backup outside the app, an uninstalled local ledger cannot be recovered.",
                    "Memulihkan data lejar termasuk rekod, bajet, bahagian, bil berulang dan matlamat simpanan. Rupa, kebenaran notifikasi dan draf belum disimpan tidak dipulihkan. Tanpa sandaran di luar aplikasi, lejar setempat yang dipadam tidak boleh dipulihkan."))
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            do { read(try result.get()) } catch { self.error = error.localizedDescription }
        }
        .sheet(item: $preview) { value in
            RestorePreviewView(preview: value) { restored = true; onRestored() }.ledgerFeedback(modal: true)
        }
        .alert(tr("无法读取备份", "Cannot read backup", "Tidak dapat membaca sandaran"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
        .onDisappear { readTask?.cancel(); request = UUID(); reading = false }
    }

    private func read(_ url: URL) {
        let current = UUID()
        request = current; reading = true
        readTask = Task {
            defer { if request == current { reading = false } }
            do {
                let value = try await LedgerRefreshWorker.shared.preview(url: url)
                guard !Task.isCancelled, request == current else { return }
                preview = value
            } catch {
                guard !Task.isCancelled, request == current else { return }
                self.error = error.localizedDescription
            }
        }
    }
}

struct BackupWelcomeView: View {
    let onContinue: () -> Void
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink(tr("登录账号，恢复云端账本", "Sign in to recover your cloud ledger", "Log masuk untuk pulihkan lejar awan")) { CloudAccountView() }
                }
                BackupRecoverySection()
                AutoBackupSection()
            }
            .yuejiListSurface()
            .navigationTitle(tr("保留你的账本", "Keep your ledger", "Simpan lejar anda"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("继续", "Continue", "Teruskan"), action: onContinue)
                        .accessibilityIdentifier("backup.welcome.continue")
                }
            }
        }
    }
}

/// The Files folder picker. It hands back the folder, or nil when cancelled.
private struct FolderPicker: UIViewControllerRepresentable {
    let onFinish: (URL?) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onFinish: (URL?) -> Void
        init(onFinish: @escaping (URL?) -> Void) { self.onFinish = onFinish }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { onFinish(urls.first) }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { onFinish(nil) }
    }
}
