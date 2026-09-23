import Foundation

/// App UI and App Intent use the same sandbox file. File coordination serializes read-modify-write.
/// No App Group or paid iCloud entitlement is required. Explicit exports use the Files document picker.
final class LocalStore {
    static let shared = LocalStore()
    let folder: URL
    init(folder: URL? = nil) {
        self.folder = folder ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("YueJi", isDirectory: true)
    }
    private var file: URL { folder.appendingPathComponent("ledger.json") }
    private var backupFolder: URL { folder.appendingPathComponent("Backups", isDirectory: true) }
    static func encode(_ ledger: Ledger) throws -> Data { let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601; return try encoder.encode(ledger) }
    static func decode(_ data: Data) throws -> Ledger { guard data.count <= 20_000_000 else { throw LedgerError.invalid("备份不能超过 20 MB。") }; let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601; return try decoder.decode(Ledger.self, from: data).validated() }
    private func prepare() throws { try FileManager.default.createDirectory(at: backupFolder, withIntermediateDirectories: true) }
    private func readUnlocked() throws -> Ledger {
        guard FileManager.default.fileExists(atPath: file.path) else { return Ledger() }
        return try Self.decode(Data(contentsOf: file)) // Corrupt data is never silently replaced with an empty ledger.
    }
    func read() throws -> Ledger {
        try prepare()
        if !FileManager.default.fileExists(atPath: file.path) { return Ledger() }
        var output: Result<Ledger, Error> = .failure(LedgerError.invalid("无法读取账本。"))
        var error: NSError?
        NSFileCoordinator().coordinate(readingItemAt: file, options: [], error: &error) { _ in output = Result { try self.readUnlocked() } }
        if let error { throw error }
        return try output.get()
    }
    @discardableResult func change<T>(_ action: (inout Ledger) throws -> T) throws -> T {
        try prepare()
        var output: Result<T, Error> = .failure(LedgerError.invalid("账本正忙，请重试。"))
        var error: NSError?
        NSFileCoordinator().coordinate(writingItemAt: file, options: .forMerging, error: &error) { _ in
            output = Result {
                var ledger = try self.readUnlocked()
                let previous = try Self.encode(ledger)
                let result = try action(&ledger)
                let next = try Self.encode(ledger.validated())
                if previous != next {
                    let name = "\(Int(Date().timeIntervalSince1970 * 1000))-\(UUID().uuidString).json"
                    try previous.write(to: self.backupFolder.appendingPathComponent(name), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                    try next.write(to: self.file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                    let backups = try self.backups()
                    for old in backups.dropFirst(30) { try? FileManager.default.removeItem(at: old) }
                }
                return result
            }
        }
        if let error { throw error }
        return try output.get()
    }
    func backups() throws -> [URL] { try prepare(); return try FileManager.default.contentsOfDirectory(at: backupFolder, includingPropertiesForKeys: nil).filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent > $1.lastPathComponent } }
    func restore(_ data: Data) throws {
        let imported = try Self.decode(data)
        try change { ledger in var next = imported; next.seenEvents.formUnion(ledger.seenEvents); next.postedRecurring.formUnion(ledger.postedRecurring); ledger = next }
    }
}
