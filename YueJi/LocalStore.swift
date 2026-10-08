import Foundation
import Security

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
    var sourceApp: String? = nil
    var useTransactionDate: Bool? = nil // nil preserves deliveries queued by older versions
    var source: String { kind == "applePay" ? "Apple Pay" : notificationProvider(sourceApp: sourceApp, title: title, body: body) }
    var applePayDate: Date { useTransactionDate == false ? receivedAt : (date ?? receivedAt) }
    var applePayTimeSource: String { useTransactionDate == false || date == nil ? "received" : "supplied" }
    var marker: String { "delivery:" + id }
    func validate() throws {
        guard UUID(uuidString: id) != nil, ["notification", "applePay"].contains(kind),
              body.count <= 8000, title.count <= 500, merchant.count <= 200,
              description.count <= 2000, currency.count <= 10, (eventID?.count ?? 0) <= 500,
              (sourceApp == nil || sourceApp!.isEmpty || validFinancialSource(sourceApp!)),
              !(kind == "applePay" && useTransactionDate == true && date == nil),
              receivedAt.timeIntervalSince1970 >= 0, receivedAt.timeIntervalSince1970 < 4_102_444_800, amount?.isFinite ?? true,
              date?.timeIntervalSince1970.isFinite ?? true else {
            throw LedgerError.invalid("自动记账输入无效或过长，请检查快捷指令。")
        }
    }
}

enum AutomationNotificationSound: String {
    case incoming, outgoing, neutral
}

struct AutomationResult {
    var title: String
    var message: String
    var expenseID: String? = nil
    var noticeID: String? = nil
    var shouldNotify = true
    var sound: AutomationNotificationSound = .neutral
}

extension Ledger {
    // Direction comes from the saved transaction, never from notification prose.
    // Ambiguous and duplicate outcomes must not sound like a fresh money movement.
    func notificationSound(expenseID: String?, noticeID: String?) -> AutomationNotificationSound {
        if let expenseID, expenses.contains(where: { $0.id == expenseID }) { return .outgoing }
        guard let noticeID, let notice = tngNotices.first(where: { $0.id == noticeID }),
              !notice.possibleDuplicate, notice.status != "ignored" else { return .neutral }
        switch notice.kind {
        case "incoming": return .incoming
        case "transfer": return .outgoing
        default: return .neutral
        }
    }
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
                                                          date: delivery.date ?? delivery.receivedAt, eventID: delivery.eventID, sourceApp: delivery.sourceApp)
            if delivery.date == nil, parseFinancialNotification(delivery.body, title: delivery.title, sourceApp: delivery.sourceApp)?.transactionDate == nil,
               let id = processed.noticeID, let i = copy.tngNotices.firstIndex(where: { $0.id == id }) {
                copy.tngNotices[i].usesReceivedDate = true
            }
            result = AutomationResult(title: processed.expenseID == nil ? "月记 · 交易处理结果" : "月记 · 已自动记账",
                                      message: processed.message, expenseID: processed.expenseID, noticeID: processed.noticeID,
                                      shouldNotify: processed.accepted || shouldReviewFinancialNotification(delivery.body, title: delivery.title),
                                      sound: copy.notificationSound(expenseID: processed.expenseID, noticeID: processed.noticeID))
        } else {
            guard let amount = delivery.amount else { throw LedgerError.invalid("Apple Pay 缺少金额，请检查快捷指令。") }
            let date = delivery.applePayDate
            let before = copy.tngNotices.count
            let saved = try copy.addPayment(amount: amount, merchant: delivery.merchant, currency: delivery.currency,
                                            date: date, eventID: delivery.eventID, description: delivery.description)
            if saved, let index = copy.expenses.indices.last { copy.expenses[index].timeSource = delivery.applePayTimeSource }
            if copy.tngNotices.count > before, let index = copy.tngNotices.indices.last {
                copy.tngNotices[index].usesReceivedDate = delivery.applePayTimeSource == "received"
            }
            let entry = saved ? copy.expenses.last : nil
            let pending = copy.tngNotices.count > before ? copy.tngNotices.last : nil
            let detail = entry.map { automaticExpenseDetail($0) } ?? (pending == nil ? "这笔付款已记录，没有重复入账。" : "疑似重复，已保留待确认，尚未再次计入消费。")
            copy.logAutomation(source: "Apple Pay", outcome: saved ? "saved" : (pending == nil ? "duplicate" : "pending"), detail: detail)
            result = AutomationResult(title: saved ? "月记 · 已自动记账" : (pending == nil ? "月记 · 未重复记账" : "月记 · Apple Pay 待确认"),
                                      message: detail, expenseID: entry?.id, noticeID: pending?.id, sound: saved ? .outgoing : .neutral)
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
        var result: AutomationResult
        do {
            result = try store.change { ledger in
                let result = try ledger.applyDelivery(delivery)
                if GeminiSettings.enabled, let id = result.expenseID { ledger.enqueueAICategory(id) }
                return result
            }
        }
        catch {
            delivery.attempts += 1; delivery.lastAttempt = Date()
            delivery.lastError = String(error.localizedDescription.prefix(1000))
            try? inbox.save(delivery) // Original input is already durable.
            throw LedgerError.invalid("交易输入已暂存，等待重试，尚未确认入账：" + error.localizedDescription)
        }
        // A cleanup failure never changes a successful commit; its marker makes recovery safe.
        try? inbox.remove(delivery)
        if let id = result.expenseID {
            await GeminiClassifier.shared.classify(id, store: store)
            if let entry = try? store.read().expenses.first(where: { $0.id == id }) {
                result.message = automaticExpenseDetail(entry)
                if let ai = entry.aiCategory { result.message += "\n" + ai.label }
            }
        }
        if result.shouldNotify && sendsNotifications {
            await LedgerNotifications.result(title: result.title, body: result.message,
                                             expenseID: result.expenseID, noticeID: result.noticeID, deliveryID: delivery.id, sound: result.sound)
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
            await GeminiClassifier.shared.retry(store: store, manual: manual)
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

struct AICategoryState: Codable, Equatable {
    var id = UUID().uuidString
    var status = "pending"
    var attempts = 0
    var lastAttempt: Date? = nil
    var suggested: String? = nil
    var detail = ""
    var label: String {
        switch status {
        case "classified": return "Gemini 已分类"
        case "review": return "AI 分类待确认"
        case "failed": return "AI 暂不可用 · 已保留账目"
        default: return "等待 AI 分类 · 已保留账目"
        }
    }
    func validate() throws {
        guard UUID(uuidString: id) != nil, ["pending", "classified", "review", "failed"].contains(status),
              (0...100).contains(attempts), detail.count <= 200,
              suggested == nil || categories.contains(suggested!),
              lastAttempt?.timeIntervalSince1970.isFinite ?? true else {
            throw LedgerError.invalid("AI 分类状态无效。")
        }
    }
}
struct GeminiCategoryResponse: Codable {
    let category: String
    let confidence: Double
    let needsReview: Bool
    let reason: String
    func validate() throws {
        guard categories.contains(category), confidence.isFinite, (0...1).contains(confidence), reason.count <= 200 else {
            throw LedgerError.invalid("AI 返回的分类无效，原账目已保留。")
        }
    }
}
extension Ledger {
    mutating func enqueueAICategory(_ id: String) {
        guard let i = expenses.firstIndex(where: { $0.id == id }),
              expenses[i].aiCategory == nil, expenses[i].categoryAllocations?.isEmpty ?? true,
              merchantCategories[friendKey(expenses[i].merchant)] == nil else { return }
        expenses[i].aiCategory = AICategoryState()
    }
    mutating func applyAICategory(_ reply: GeminiCategoryResponse, original: Expense) throws {
        try reply.validate()
        guard let i = expenses.firstIndex(where: { $0.id == original.id }),
              expenses[i].aiCategory?.id == original.aiCategory?.id,
              expenses[i].aiCategory?.status == "pending" else { return }
        guard expenses[i].merchant == original.merchant, expenses[i].category == original.category,
              expenses[i].categoryAllocations?.isEmpty ?? true else {
            expenses[i].aiCategory = nil
            return
        }
        if let remembered = merchantCategories[friendKey(original.merchant)] {
            expenses[i].category = remembered
            expenses[i].aiCategory = nil
            return
        }
        let accepted = !reply.needsReview && reply.confidence >= 0.85 && reply.category != "其他"
        if accepted { expenses[i].category = reply.category }
        expenses[i].aiCategory?.status = accepted ? "classified" : "review"
        expenses[i].aiCategory?.suggested = reply.category
        expenses[i].aiCategory?.detail = reply.reason
    }
}

// The Gemini key exists only on the server. This is a separate, revocable
// personal access token, stored outside exported ledger files.
enum GeminiSettings {
    static var enabled: Bool { UserDefaults.standard.bool(forKey: "gemini.enabled") }
    static var endpoint: String { UserDefaults.standard.string(forKey: "gemini.endpoint") ?? "" }
    static func endpointURL(_ value: String) throws -> URL {
        guard let u = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
              u.scheme == "https", let host = u.host, host.hasSuffix(".supabase.co"),
              u.user == nil, u.password == nil, u.query == nil, u.fragment == nil,
              u.port == nil, u.path == "/functions/v1/classify-merchant" else {
            throw LedgerError.invalid("请输入 Supabase 的 classify-merchant HTTPS 函数地址。")
        }
        return u
    }
    static var keychainQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "YueJi.GeminiProxy",
         kSecAttrAccount as String: "personal-access"]
    }
    static func token() -> String? {
        var query = keychainQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func save(endpoint: String, token: String, enabled: Bool) throws {
        let url = try endpointURL(endpoint)
        let secret = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard secret.range(of: #"\A[A-Za-z0-9_-]{32,128}\z"#, options: .regularExpression) != nil else {
            throw LedgerError.invalid("连接码须为 32–128 位字母、数字、下划线或连字符；不要填 Gemini API Key。")
        }
        let data = Data(secret.utf8)
        let update = [kSecValueData as String: data] as [String: Any]
        var status = SecItemUpdate(keychainQuery as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var query = keychainQuery
            query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(query as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw LedgerError.invalid("无法安全保存连接码，请解锁手机后重试。") }
        UserDefaults.standard.set(url.absoluteString, forKey: "gemini.endpoint")
        UserDefaults.standard.set(enabled, forKey: "gemini.enabled")
    }
    static func disable() { UserDefaults.standard.set(false, forKey: "gemini.enabled") }
    static func sanitizedMerchant(_ value: String) -> String {
        var text = value
        for pattern in [#"https?://\S+"#, #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#,
                        #"\b(?:account|acct|card|a/c|ref(?:erence)?)\s*[:#]?\s*[A-Z0-9* -]{4,}"#,
                        #"\b\d(?:[ -]?\d){5,}\b"#] {
            text = text.replacingOccurrences(of: pattern, with: "[removed]", options: [.regularExpression, .caseInsensitive])
        }
        return String(notificationText(text).prefix(200))
    }
}
private final class GeminiNoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
actor GeminiClassifier {
    static let shared = GeminiClassifier()
    private var running: Set<String> = []
    func request(merchant: String) async throws -> GeminiCategoryResponse {
        let url = try GeminiSettings.endpointURL(GeminiSettings.endpoint)
        guard let token = GeminiSettings.token() else { throw LedgerError.invalid("请先保存 AI 连接设置。") }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"; req.timeoutInterval = 12
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(token, forHTTPHeaderField: "X-YueJi-Token")
        req.httpBody = try JSONEncoder().encode(["merchant": GeminiSettings.sanitizedMerchant(merchant)])
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 12; config.timeoutIntervalForResource = 15
        let session = URLSession(configuration: config, delegate: GeminiNoRedirect(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw LedgerError.invalid("AI 服务没有有效回应。") }
        guard http.statusCode == 200 else {
            switch http.statusCode {
            case 401, 403: throw LedgerError.invalid("AI 连接码不正确，或后端尚未配置。")
            case 429: throw LedgerError.invalid("AI 调用额度或频率已达上限，请稍后重试。")
            default: throw LedgerError.invalid("AI 服务暂不可用，请检查后端密钥和模型设置。")
            }
        }
        guard data.count <= 4096 else { throw LedgerError.invalid("AI 返回内容过长。") }
        let result = try JSONDecoder().decode(GeminiCategoryResponse.self, from: data)
        try result.validate()
        return result
    }
    func classify(_ id: String, store: LocalStore) async {
        let key = store.folder.path + "/" + id
        guard GeminiSettings.enabled, !running.contains(key) else { return }
        running.insert(key); defer { running.remove(key) }
        var snapshot: Expense?
        do {
            snapshot = try store.change { ledger in
                guard let i = ledger.expenses.firstIndex(where: { $0.id == id }),
                      ledger.expenses[i].aiCategory?.status == "pending" else { return nil }
                if let remembered = ledger.merchantCategories[friendKey(ledger.expenses[i].merchant)] {
                    ledger.expenses[i].category = remembered; ledger.expenses[i].aiCategory = nil
                    return nil
                }
                ledger.expenses[i].aiCategory?.attempts += 1
                ledger.expenses[i].aiCategory?.lastAttempt = Date()
                return ledger.expenses[i]
            }
            guard let snapshot else { return }
            let reply = try await request(merchant: snapshot.merchant)
            guard GeminiSettings.enabled else { return }
            try store.change { try $0.applyAICategory(reply, original: snapshot) }
        } catch {
            guard let snapshot else { return }
            try? store.change { ledger in
                guard let i = ledger.expenses.firstIndex(where: { $0.id == id }),
                      ledger.expenses[i].aiCategory?.id == snapshot.aiCategory?.id,
                      ledger.expenses[i].aiCategory?.status == "pending" else { return }
                ledger.expenses[i].aiCategory?.detail = "AI 暂不可用，账目和本地分类已保留。"
                if (ledger.expenses[i].aiCategory?.attempts ?? 0) >= 3 { ledger.expenses[i].aiCategory?.status = "failed" }
            }
        }
    }
    func retry(store: LocalStore = .shared, manual: Bool = false) async {
        guard GeminiSettings.enabled, let ledger = try? store.read() else { return }
        let ids = ledger.expenses.filter {
            guard let state = $0.aiCategory else { return false }
            if manual { return ["pending", "failed"].contains(state.status) }
            return state.status == "pending" && state.attempts < 3 &&
                (state.lastAttempt.map { Date().timeIntervalSince($0) >= 60 } ?? true)
        }.prefix(5).map(\.id)
        for id in ids {
            if manual {
                try? store.change { ledger in
                    guard let i = ledger.expenses.firstIndex(where: { $0.id == id }),
                          ["pending", "failed"].contains(ledger.expenses[i].aiCategory?.status ?? "") else { return }
                    ledger.expenses[i].aiCategory?.status = "pending"
                    ledger.expenses[i].aiCategory?.attempts = 0
                }
            }
            await classify(id, store: store)
        }
    }
}

