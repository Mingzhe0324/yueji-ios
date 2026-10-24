import SwiftUI
import UIKit
import UniformTypeIdentifiers
import CryptoKit

/// Automatic copies of the ledger in a folder the person picks in Files: iCloud Drive or On
/// My iPhone. They live outside the app, so deleting or reinstalling YueJi, or an AltStore
/// install that fails, leaves them in place; Restore from a backup file reads them back.
/// Access to the folder is kept with a security-scoped bookmark, so no iCloud entitlement
/// is needed. Each copy is the same complete JSON backup as "Save a complete backup".

/// How often a copy is made.
enum AutoBackupFrequency: String, CaseIterable, Identifiable {
    case daily, weekly
    var id: String { rawValue }
    /// A little under the period, so a copy made one evening is renewed the next.
    var interval: TimeInterval { self == .daily ? 20 * 3600 : 6.5 * 24 * 3600 }
    var label: String { self == .daily ? tr("每天", "Daily", "Harian") : tr("每周", "Weekly", "Mingguan") }
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
        guard name.hasPrefix(prefix), name.hasSuffix(".json"), name.count == prefix.count + 17 + 5 else { return nil }
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
        let name = AutoBackupFiles.name(for: now)
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

/// When copies are made: on opening and on leaving the app, once the period has passed,
/// and only when the ledger changed. "Back up now" always writes one.
@MainActor enum AutoBackup {
    private static var running = false

    static var isConfigured: Bool { UserDefaults.standard.data(forKey: AutoBackupKeys.bookmark) != nil }
    static var frequency: AutoBackupFrequency {
        AutoBackupFrequency(rawValue: UserDefaults.standard.string(forKey: AutoBackupKeys.frequency) ?? "") ?? .daily
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
        defer { running = false }
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
    static func choose(_ url: URL) throws {
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
}

/// The background time for one copy, ended once by whichever comes first: the copy or iOS.
private final class BackgroundTaskToken: @unchecked Sendable {
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
    @AppStorage(AutoBackupKeys.frequency) private var frequency = AutoBackupFrequency.daily.rawValue
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
                    Text(tr("在「文件」里选一个文件夹，最好是 iCloud Drive。月记会定期把账本复制到那里；删除 App、AltStore 刷新失败或手机遗失时，它仍然在。",
                            "Choose a folder in Files, ideally in iCloud Drive. YueJi regularly copies your ledger there, so it survives deleting the app, a failed AltStore refresh or a lost phone.",
                            "Pilih folder dalam Files, sebaiknya iCloud Drive. YueJi menyalin lejar anda ke sana secara berkala, jadi ia kekal walaupun aplikasi dipadam, AltStore gagal disegarkan atau telefon hilang."))
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
                Text(tr("打开或离开月记时，按所选频率在账本有变化时复制一份；只删除超出保留数量的旧自动备份，不会动文件夹里的其他文件。重新安装后，请用「从备份文件恢复」选择最新的 YueJi-auto 文件。",
                        "A copy is made when you open or leave YueJi, as often as you choose and only when something changed. Only automatic copies beyond the number kept are removed; nothing else in the folder is touched. After reinstalling, use Restore from a backup file and pick the newest YueJi-auto file.",
                        "Salinan dibuat apabila anda membuka atau meninggalkan YueJi, mengikut kekerapan pilihan dan hanya jika ada perubahan. Hanya salinan automatik melebihi bilangan disimpan dibuang; fail lain dalam folder tidak disentuh. Selepas pasang semula, gunakan Pulihkan daripada fail sandaran dan pilih fail YueJi-auto terbaharu."))
            }
        }
    }
    private func chooseButton(_ title: String, symbol: String) -> some View {
        Button { choosing = true } label: { Label(title, systemImage: symbol) }
            .sheet(isPresented: $choosing) {
                FolderPicker { url in
                    choosing = false
                    guard let url else { return }
                    do {
                        try AutoBackup.choose(url)
                        backUpNow()
                    } catch { model.error = error.localizedDescription }
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
