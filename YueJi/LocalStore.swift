import Foundation

/// Persist the input before attempting the ledger write. This cannot capture an automation that never ran.
struct AutomationDelivery: Codable, Identifiable {
    var id = UUID().uuidString
    var receivedAt = Date()
    var kind: String // notification / applePay
    var body = ""
    var title = ""
    var date: Date? = nil
    var eventID: String? = nil
    var amount: Double? = nil
    var merchant = ""
    var currency = "MYR"
    var description = ""
    var attempts = 0
    var lastError: String? = nil
    var lastAttempt: Date? = nil
    var source: String { kind == "applePay" ? "Apple Pay" : "银行 / TNG" }
    var marker: String { "delivery:" + id }
    func validate() throws {
        guard UUID(uuidString: id) != nil, ["notification", "applePay"].contains(kind),
              body.count <= 8000, title.count <= 500, merchant.count <= 200,
              description.count <= 2000, currency.count <= 10, (eventID?.count ?? 0) <= 500,
              receivedAt.timeIntervalSince1970.isFinite, amount?.isFinite ?? true,
              date?.timeIntervalSince1970.isFinite ?? true else {
            throw LedgerError.invalid("自动记账输入无效或过长，请检查快捷指令。")
        }
    }
}

struct AutomationResult {
    var title: String
    var message: String
    var expenseID: String? = nil
    var noticeID: String? = nil
    var shouldNotify = true
}

extension Ledger {
    mutating func applyDelivery(_ delivery: AutomationDelivery) throws -> AutomationResult {
        try delivery.validate()
        if seenEvents.contains(delivery.marker) {
            return AutomationResult(title: "月记 · 恢复检查完成", message: "此前已处理这次调用，没有重复入账。请查看账本或待确认记录。",
                                    shouldNotify: delivery.kind == "applePay" || shouldReviewFinancialNotification(delivery.body, title: delivery.title))
        }
        var copy = self
        let result: AutomationResult
        if delivery.kind == "notification" {
            let processed = try copy.processTNGNotification(body: delivery.body, title: delivery.title,
                                                          date: delivery.date ?? delivery.receivedAt, eventID: delivery.eventID)
            if delivery.date == nil, parseFinancialNotification(delivery.body, title: delivery.title)?.transactionDate == nil,
               let id = processed.noticeID, let i = copy.tngNotices.firstIndex(where: { $0.id == id }) {
                copy.tngNotices[i].usesReceivedDate = true
            }
            result = AutomationResult(title: processed.expenseID == nil ? "月记 · 交易处理结果" : "月记 · 已自动记账",
                                      message: processed.message, expenseID: processed.expenseID, noticeID: processed.noticeID,
                                      shouldNotify: processed.accepted || shouldReviewFinancialNotification(delivery.body, title: delivery.title))
        } else {
            guard let amount = delivery.amount, let date = delivery.date else { throw LedgerError.invalid("Apple Pay 缺少金额或交易日期，请检查快捷指令。") }
            let before = copy.tngNotices.count
            let saved = try copy.addPayment(amount: amount, merchant: delivery.merchant, currency: delivery.currency,
                                            date: date, eventID: delivery.eventID, description: delivery.description)
            let entry = saved ? copy.expenses.last : nil
            let pending = copy.tngNotices.count > before ? copy.tngNotices.last : nil
            let detail = entry.map { automaticExpenseDetail($0) } ?? (pending == nil ? "这笔付款已记录，没有重复入账。" : "疑似跨来源重复，已保留待确认，尚未再次计入消费。")
            copy.logAutomation(source: "Apple Pay", outcome: saved ? "saved" : (pending == nil ? "duplicate" : "pending"), detail: detail)
            result = AutomationResult(title: saved ? "月记 · 已自动记账" : (pending == nil ? "月记 · 未重复记账" : "月记 · Apple Pay 待确认"),
                                      message: detail, expenseID: entry?.id, noticeID: pending?.id)
        }
        // The marker and money are committed in the same atomic ledger file replacement.
        copy.seenEvents.insert(delivery.marker)
        self = try copy.validated()
        return result
    }
}

final class AutomationInbox {
    static let shared = AutomationInbox(folder: LocalStore.shared.folder.appendingPathComponent("AutomationInbox", isDirectory: true))
    let folder: URL
    init(folder: URL) { self.folder = folder }
    func save(_ delivery: AutomationDelivery) throws {
        try delivery.validate()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let path = folder.appendingPathComponent(delivery.id + ".json")
        if !FileManager.default.fileExists(atPath: path.path) {
            guard try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).count < 500 else {
                throw LedgerError.invalid("待重试交易已满，请先在自动记账状态页处理。此输入尚未暂存。")
            }
        }
        let bytes = try JSONEncoder().encode(delivery)
        guard bytes.count <= 100_000 else { throw LedgerError.invalid("自动记账输入过长。") }
        try bytes.write(to: path, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    func pending() throws -> [AutomationDelivery] {
        guard FileManager.default.fileExists(atPath: folder.path) else { return [] }
        let paths = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        return try paths.filter { $0.pathExtension == "json" }.map { path in
            let bytes = try Data(contentsOf: path)
            guard bytes.count <= 100_000 else { throw LedgerError.invalid("待重试文件异常，请保留文件并检查。") }
            let delivery = try JSONDecoder().decode(AutomationDelivery.self, from: bytes)
            try delivery.validate()
            guard path.deletingPathExtension().lastPathComponent == delivery.id else { throw LedgerError.invalid("待重试文件标识不一致。") }
            return delivery
        }.sorted { $0.receivedAt < $1.receivedAt }
    }
    func remove(_ delivery: AutomationDelivery) throws {
        try delivery.validate()
        let path = folder.appendingPathComponent(delivery.id + ".json")
        if FileManager.default.fileExists(atPath: path.path) { try FileManager.default.removeItem(at: path) }
    }
}

actor AutomationRecovery {
    static let shared = AutomationRecovery()
    private let store: LocalStore
    private let inbox: AutomationInbox
    private let sendsNotifications: Bool
    private var recovering = false
    init(store: LocalStore = .shared, inbox: AutomationInbox = .shared, sendsNotifications: Bool = true) {
        self.store = store; self.inbox = inbox; self.sendsNotifications = sendsNotifications
    }
    func submit(_ delivery: AutomationDelivery) async throws -> AutomationResult {
        // Failure here is reported as not retained; it must not pretend a recovery copy exists.
        do { try inbox.save(delivery) }
        catch { throw LedgerError.invalid("输入未能暂存，尚未自动入账：" + error.localizedDescription) }
        if delivery.kind == "applePay", delivery.currency.uppercased() != "MYR" {
            _ = try? await AutomaticRates.shared.refresh(delivery.currency.uppercased())
        }
        return try await process(delivery)
    }
    private func process(_ original: AutomationDelivery) async throws -> AutomationResult {
        var delivery = original
        let result: AutomationResult
        do { result = try store.change { try $0.applyDelivery(delivery) } }
        catch {
            delivery.attempts += 1; delivery.lastAttempt = Date()
            delivery.lastError = String(error.localizedDescription.prefix(1000))
            try? inbox.save(delivery) // Original input is already durable.
            throw LedgerError.invalid("交易输入已暂存，等待重试，尚未确认入账：" + error.localizedDescription)
        }
        // A cleanup failure never changes a successful commit; its marker makes recovery safe.
        try? inbox.remove(delivery)
        if result.shouldNotify && sendsNotifications {
            await LedgerNotifications.result(title: result.title, body: result.message,
                                             expenseID: result.expenseID, noticeID: result.noticeID, deliveryID: delivery.id)
        }
        return result
    }
    func retryPending(manual: Bool = false) async -> String? {
        guard !recovering else { return nil }
        recovering = true
        defer { recovering = false }
        do {
            let all = try inbox.pending()
            let eligible = all.filter { delivery in
                manual || (delivery.attempts < 3 && !(delivery.lastAttempt.map { Date().timeIntervalSince($0) < 30 } ?? false))
            }
            for delivery in eligible.prefix(30) {
                if delivery.kind == "applePay", delivery.currency.uppercased() != "MYR" {
                    _ = try? await AutomaticRates.shared.refresh(delivery.currency.uppercased())
                }
                _ = try? await process(delivery)
            }
            return nil
        } catch { return "无法读取待重试交易：" + error.localizedDescription }
    }
}

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
    static func exportData(_ ledger: Ledger) throws -> Data {
        var copy = ledger; copy.backupCreatedAt = Date(); return try encode(copy)
    }
    var recoveryFile: URL { folder.appendingPathComponent("before-last-restore.json") }
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
                _ = try ledger.validated()
                let next = try Self.encode(ledger.validated())
                guard next.count <= 20_000_000 else { throw LedgerError.invalid("备份不能超过 20 MB。") }
                if previous != next {
                    let name = "\(Int(Date().timeIntervalSince1970 * 1000))-\(UUID().uuidString).json"
                    try Self.exportData(try Self.decode(previous)).write(to: self.backupFolder.appendingPathComponent(name), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
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
        try change { ledger in
            // Independent recovery copy is not removed by the 30-snapshot rotation.
            try Self.exportData(ledger).write(to: recoveryFile, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            var next = imported; next.seenEvents.formUnion(ledger.seenEvents)
            next.postedRecurring.formUnion(ledger.postedRecurring); ledger = next
        }
    }
}
