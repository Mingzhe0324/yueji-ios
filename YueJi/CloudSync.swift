import Foundation
import CryptoKit
import Security

struct CloudConfiguration: Equatable {
    let url: URL
    let publicKey: String
    var server: String { url.absoluteString }

    init(url: String, publicKey: String) throws {
        let address = url.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let key = publicKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = URL(string: address), parsed.scheme == "https", parsed.host != nil,
              parsed.user == nil, parsed.password == nil, parsed.query == nil, parsed.fragment == nil,
              parsed.path.isEmpty, !address.contains("$("), Self.isPublicKey(key) else { throw CloudFailure.configuration }
        self.url = parsed; self.publicKey = key
    }
    static var bundled: CloudConfiguration? {
        try? CloudConfiguration(url: Bundle.main.object(forInfoDictionaryKey: "YueJiSupabaseURL") as? String ?? "",
                               publicKey: Bundle.main.object(forInfoDictionaryKey: "YueJiSupabasePublicKey") as? String ?? "")
    }
    static func isPublicKey(_ value: String) -> Bool {
        if value.hasPrefix("sb_publishable_"), value.count > 20 { return true }
        let parts = value.split(separator: ".")
        guard parts.count == 3 else { return false }
        var base64 = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard let data = Data(base64Encoded: base64), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return object["role"] as? String == "anon"
    }
}

enum CloudFailure: LocalizedError {
    case password, credentials, googleUnavailable
    case transport(code: Int, endpoint: String)
    case server(status: Int, endpoint: String)
    case configuration, database, connection, session, accountMismatch, changed, conflict, invalidResponse, keychain, rateLimit, email, authentication
    var errorDescription: String? {
        switch self {
        case .googleUnavailable: return tr("Google 登录尚未启用。请先完成 Supabase 的 Google Provider 和回调地址设置。", "Google sign-in is not enabled. Complete the Supabase Google provider and callback setup.", "Log masuk Google belum diaktifkan. Lengkapkan tetapan Google dan panggil balik Supabase.")
        case .password: return tr("密码至少需要 8 个字符，且两次输入必须一致。服务器也可能要求更强的密码。", "Use at least 8 characters and matching passwords. The server may require a stronger password.", "Gunakan sekurang-kurangnya 8 aksara dan kata laluan sepadan.")
        case .credentials: return tr("邮箱或密码不正确，或邮箱尚未验证。已有验证码账号可通过忘记密码设置密码。", "Email or password is incorrect, or email is unconfirmed. Existing email-code accounts can set a password using Forgot password.", "E-mel atau kata laluan salah, atau e-mel belum disahkan. Akaun kod e-mel boleh menggunakan Lupa kata laluan.")
        case let .transport(code, endpoint):
            return tr("网络请求未完成", "Network request did not complete", "Permintaan rangkaian tidak selesai") + " (\(endpoint), URL \(code)). " + tr("请将此提示提供给开发者。本机账本仍保留。", "Share this message with the developer. Your local ledger is retained.", "Kongsi mesej ini dengan pembangun. Lejar setempat dikekalkan.")
        case let .server(status, endpoint):
            return tr("云端服务返回错误", "Cloud service returned an error", "Perkhidmatan awan mengembalikan ralat") + " (\(endpoint), HTTP \(status))."
        case .configuration: return tr("此版本尚未配置有效的云端连接，账本仍保留在本机。", "Cloud connection is not configured in this build. Your ledger stays on this device.", "Sambungan awan belum dikonfigurasi dalam binaan ini. Lejar kekal pada peranti.")
        case .database: return tr("已连接服务，但账本数据库尚未初始化。请完成云端数据库设置。", "Service reached, but the ledger database is not initialized. Complete cloud database setup.", "Perkhidmatan disambung tetapi pangkalan data lejar belum disediakan.")
        case .connection: return tr("暂时无法连接云端。未同步的更改仍保留在本机，请联网后重试。", "Cannot reach the cloud. Unsynced changes remain on this device; retry when online.", "Tidak dapat mencapai awan. Perubahan belum disegerakkan kekal pada peranti; cuba semula apabila dalam talian.")
        case .session: return tr("登录已失效，请用同一账号重新登录。本机账本仍保留。", "Session expired. Sign in to the same account again; your local ledger is retained.", "Sesi tamat. Log masuk semula ke akaun sama; lejar setempat dikekalkan.")
        case .accountMismatch: return tr("本机账本已关联另一个账号或云端服务。请登录原账号，避免混入其他人的数据。", "This ledger belongs to another account or cloud service. Sign in to its original account.", "Lejar ini milik akaun atau perkhidmatan awan lain. Log masuk ke akaun asal.")
        case .changed: return tr("账本在操作期间有更改，请重新检查并同步。", "The ledger changed during this action. Check and sync again.", "Lejar berubah semasa tindakan ini. Semak dan segerakkan semula.")
        case .conflict: return tr("本机与云端都有不同记录，请选择保留哪一份。", "This device and the cloud have different records. Choose which ledger to keep.", "Peranti dan awan mempunyai rekod berbeza. Pilih lejar untuk dikekalkan.")
        case .invalidResponse: return tr("云端返回的数据无效，未替换本机账本。", "Cloud data is invalid. The local ledger was not replaced.", "Data awan tidak sah. Lejar setempat tidak diganti.")
        case .keychain: return tr("无法安全保存登录状态，请重试。", "Cannot securely save the session. Please retry.", "Tidak dapat menyimpan sesi dengan selamat. Cuba semula.")
        case .rateLimit: return tr("请求过于频繁，请稍后再试。", "Too many requests. Please try again later.", "Terlalu banyak permintaan. Cuba lagi nanti.")
        case .email: return tr("验证码邮件未能发送。请检查邮箱及服务端邮件配置。", "Could not send the code. Check the email address and service email configuration.", "Kod tidak dapat dihantar. Semak alamat e-mel dan konfigurasi e-mel perkhidmatan.")
        case .authentication: return tr("验证码无效或已过期，请重新获取。", "The code is invalid or expired. Request a new code.", "Kod tidak sah atau tamat tempoh. Minta kod baharu.")
        }
    }
}

enum BankAnalysisFailure: String, LocalizedError {
    case notConfigured = "not_configured", quotaUnavailable = "quota_unavailable", dailyLimit = "daily_limit"
    case modelUnavailable = "model_unavailable", modelAccessDenied = "model_access_denied"
    case modelRequestRejected = "model_request_rejected", modelRateLimit = "model_rate_limit"
    case modelServerError = "model_server_error", modelOverloaded = "model_overloaded"
    case timeout = "analysis_timeout", connection = "analysis_connection_failed", unavailable = "analysis_unavailable"
    case invalidResponse = "invalid_model_response", incomplete = "incomplete_analysis", invalid = "invalid_analysis"
    case invalidNotification = "invalid_notification"

    var errorDescription: String? {
        let message: String
        switch self {
        case .notConfigured:
            message = tr("银行 AI 尚未配置，请检查服务端 GEMINI_BANK_MODEL 和密钥。", "Bank AI is not configured. Check GEMINI_BANK_MODEL and the server key.", "AI bank belum dikonfigurasi. Semak GEMINI_BANK_MODEL dan kunci pelayan.")
        case .quotaUnavailable:
            message = tr("无法检查银行 AI 使用额度，请检查 claim_bank_analysis 数据库函数。", "Cannot check the bank AI allowance. Check claim_bank_analysis.", "Kuota AI bank tidak dapat disemak. Semak claim_bank_analysis.")
        case .dailyLimit:
            message = tr("今天的银行 AI 分析次数已用完，暂时使用本机规则。", "Today's bank AI allowance is used up. Local rules remain available.", "Kuota AI bank hari ini habis. Peraturan setempat masih tersedia.")
        case .modelUnavailable:
            message = tr("找不到所配置的 Gemini 银行模型，请核对 GEMINI_BANK_MODEL 的完整模型 ID。", "The configured Gemini bank model was not found. Check the exact GEMINI_BANK_MODEL ID.", "Model Gemini bank tidak ditemui. Semak ID GEMINI_BANK_MODEL yang tepat.")
        case .modelAccessDenied:
            message = tr("Gemini 拒绝访问，请检查服务端 API Key、项目权限或密钥限制。", "Gemini denied access. Check the server API key, project access and key restrictions.", "Gemini menolak akses. Semak kunci API, akses projek dan sekatan kunci.")
        case .modelRequestRejected:
            message = tr("Gemini 不接受当前请求，请检查模型与请求格式是否兼容。", "Gemini rejected the request. Check model and request compatibility.", "Gemini menolak permintaan. Semak keserasian model dan format.")
        case .modelRateLimit:
            message = tr("Gemini 额度不足或请求过于频繁，请检查 Google 项目用量，稍后重试。", "Gemini quota or rate limit reached. Check Google project usage and retry later.", "Had kuota atau kadar Gemini dicapai. Semak penggunaan projek Google dan cuba kemudian.")
        case .timeout:
            message = tr("银行 AI 分析超时，请稍后重试；自动记账会使用本机规则，不明确的留待确认。", "Bank AI analysis timed out. Retry later; automatic entries use local rules and unclear cases await review.", "Analisis AI bank tamat masa. Cuba kemudian; peraturan setempat digunakan dan kes tidak jelas perlu disemak.")
        case .connection:
            message = tr("银行 AI 服务连接失败，请稍后重试。", "Bank AI service connection failed. Retry later.", "Sambungan perkhidmatan AI bank gagal. Cuba kemudian.")
        case .modelServerError, .modelOverloaded:
            message = tr("Gemini 服务暂时出错或繁忙，请稍后重试。", "Gemini is temporarily failing or busy. Retry later.", "Gemini bermasalah atau sibuk buat sementara. Cuba kemudian.")
        case .invalidResponse, .incomplete, .invalid:
            message = tr("银行 AI 未返回完整有效的分析，未根据此结果更新余额。", "Bank AI did not return a complete valid analysis. This result did not update balances.", "AI bank tidak memulangkan analisis lengkap yang sah. Hasil ini tidak mengubah baki.")
        case .invalidNotification:
            message = tr("通知内容无效或过长，请检查输入。", "Notification content is invalid or too long. Check the input.", "Kandungan notifikasi tidak sah atau terlalu panjang. Semak input.")
        case .unavailable:
            message = tr("银行 AI 暂时不可用；若仍只有此错误，请更新服务端函数以获取具体原因。", "Bank AI is unavailable. Update the server function if this generic error persists.", "AI bank tidak tersedia. Kemas kini fungsi pelayan jika ralat umum ini berterusan.")
        }
        return message + " (" + rawValue + ")"
    }
}

enum ReceiptRecognitionFailure: String, LocalizedError {
    case notConfigured = "not_configured", quotaUnavailable = "quota_unavailable"
    case dailyLimit = "daily_limit", invalidImage = "invalid_image"
    case incompleteReceipt = "incomplete_receipt", invalidReceipt = "invalid_receipt"
    case invalidOrNonMYRReceipt = "invalid_or_non_myr_receipt"
    case modelUnavailable = "model_unavailable", modelAccessDenied = "model_access_denied"
    case modelRequestRejected = "model_request_rejected", modelRateLimit = "model_rate_limit"
    case recognitionFailed = "recognition_failed", recognitionUnavailable = "recognition_unavailable"

    var errorDescription: String? {
        let message: String
        switch self {
        case .notConfigured:
            message = tr("Gemini 收据服务尚未配置完成，请检查服务端密钥及收据模型设置。", "Gemini receipts are not configured. Check the server key and receipt model settings.", "Resit Gemini belum dikonfigurasi. Semak kunci pelayan dan tetapan model resit.")
        case .quotaUnavailable:
            message = tr("无法检查收据识别额度，请检查服务端收据额度数据库设置。", "Cannot check the scan allowance. Check the receipt quota database setup.", "Tidak dapat menyemak kuota imbasan. Semak tetapan pangkalan data kuota resit.")
        case .dailyLimit:
            message = tr("今天的 Gemini 收据识别次数已用完，请稍后再试或使用本机识别。", "Today's Gemini scan allowance is used up. Try later or use on-device recognition.", "Kuota imbasan Gemini hari ini telah habis. Cuba kemudian atau gunakan pengecaman setempat.")
        case .invalidImage:
            message = tr("收据图片无效或过大，请重新选择或拍摄。", "The receipt image is invalid or too large. Choose another photo or scan again.", "Imej resit tidak sah atau terlalu besar. Pilih foto lain atau imbas semula.")
        case .incompleteReceipt:
            message = tr("Gemini 未返回完整识别结果，请用清晰的单张收据重试。", "Gemini did not return a complete result. Retry with one clear receipt.", "Gemini tidak memulangkan hasil lengkap. Cuba semula dengan satu resit yang jelas.")
        case .invalidReceipt:
            message = tr("Gemini 返回的收据格式无效，请重试。", "Gemini returned an invalid receipt format. Please retry.", "Gemini memulangkan format resit tidak sah. Cuba semula.")
        case .invalidOrNonMYRReceipt:
            message = tr("识别结果金额格式不正确，或未确认收据币种为 MYR／RM。请确保币种清晰可见后重试。", "The amounts are invalid or MYR/RM could not be confirmed. Ensure the currency is visible and retry.", "Format amaun tidak sah atau MYR/RM tidak dapat disahkan. Pastikan mata wang jelas dan cuba semula.")
        case .modelUnavailable:
            message = tr("收据识别模型不可用，请检查服务端 GEMINI_RECEIPT_MODEL 设置。", "The receipt model is unavailable. Check GEMINI_RECEIPT_MODEL on the server.", "Model resit tidak tersedia. Semak GEMINI_RECEIPT_MODEL pada pelayan.")
        case .modelAccessDenied:
            message = tr("Gemini 拒绝服务端访问，请检查 API 密钥及模型权限。", "Gemini denied server access. Check the API key and model permissions.", "Gemini menolak akses pelayan. Semak kunci API dan kebenaran model.")
        case .modelRequestRejected:
            message = tr("Gemini 拒绝识别请求，请检查服务端模型是否支持图片及结构化输出。", "Gemini rejected the request. Check that the server model supports images and structured output.", "Gemini menolak permintaan. Semak sokongan imej dan output berstruktur model pelayan.")
        case .modelRateLimit:
            message = tr("Gemini 服务额度不足或请求过于频繁，请稍后重试。", "Gemini quota is exhausted or requests are too frequent. Try again later.", "Kuota Gemini habis atau permintaan terlalu kerap. Cuba lagi kemudian.")
        case .recognitionFailed:
            message = tr("Gemini 服务返回错误，请稍后重试。", "Gemini returned a service error. Try again later.", "Gemini memulangkan ralat perkhidmatan. Cuba lagi kemudian.")
        case .recognitionUnavailable:
            message = tr("收据识别连接失败或超时，请稍后重试。", "Receipt recognition could not connect or timed out. Please retry later.", "Sambungan pengecaman resit gagal atau tamat masa. Cuba lagi kemudian.")
        }
        return message + " (\(rawValue))"
    }
}

struct CloudSession: Codable {
    struct User: Codable { let id: UUID; let email: String? }
    let access_token: String
    let refresh_token: String
    let user: User
}
struct CloudCredential: Codable {
    let server: String
    let session: CloudSession
}
enum CloudInstallation {
    static let key = "cloudInstallationInitialized.v1"
    static func prepare(defaults: UserDefaults = .standard, cloudConfigured: Bool = true, hasExistingLink: Bool,
                        clearCredentials: () throws -> Void) throws {
        // Local-only builds must neither depend on Keychain availability nor mark
        // credentials handled: a later cloud-enabled build still needs cleanup.
        guard cloudConfigured else { return }
        guard !defaults.bool(forKey: key) else { return }
        // A pre-marker installation with a bound ledger is an ordinary upgrade.
        if !hasExistingLink { try clearCredentials() }
        defaults.set(true, forKey: key)
    }
}

enum CloudCredentials {
    private static let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "YueJi.AccountSync.v2", kSecAttrAccount as String: "session"]
    static func read() throws -> CloudCredential? {
        var lookup = query; lookup[kSecReturnData as String] = true; lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(lookup as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw CloudFailure.keychain }
        return try JSONDecoder().decode(CloudCredential.self, from: data)
    }
    static func save(_ value: CloudCredential) throws {
        let data = try JSONEncoder().encode(value)
        let attributes: [String: Any] = [kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query; attributes.forEach { item[$0.key] = $0.value }
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw CloudFailure.keychain }
        } else if status != errSecSuccess { throw CloudFailure.keychain }
    }
    static func clear() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw CloudFailure.keychain }
    }
}

struct CloudLink: Codable, Equatable {
    let userID: UUID
    let server: String
    var revision = 0
    var fingerprint: String?
    var lastSync: Date?
    func accepts(userID: UUID, server: String) -> Bool { self.userID == userID && self.server == server }
}
struct CloudRecord: Decodable {
    let payload: Ledger
    let revision: Int
    let updated_at: String?
}
enum CloudFingerprint {
    static func make(_ ledger: Ledger) throws -> String {
        guard var object = try JSONSerialization.jsonObject(with: LocalStore.encode(ledger)) as? [String: Any] else { throw CloudFailure.invalidResponse }
        // Set encoding order is not stable across reads or devices.
        for key in ["seenEvents", "postedRecurring", "dismissedDuplicates", "dismissedSubscriptions"] {
            if let values = object[key] as? [String] { object[key] = values.sorted() }
        }
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
enum CloudSyncDecision: Equatable {
    case upload, download, equal, conflict
    static func decide(local: String, hasLocalFile: Bool, remote: String?, revision: Int, link: CloudLink?) -> Self {
        guard let remote else { return (link?.revision ?? 0) == 0 ? .upload : .conflict }
        if local == remote { return .equal }
        if !hasLocalFile { return .download }
        if link?.fingerprint == local { return .download }
        if link?.revision == revision, link?.fingerprint == remote { return .upload }
        return .conflict
    }
}
struct CloudConflict {
    let localFingerprint: String
    let remoteFingerprint: String?
    let remoteRevision: Int
    let localCount: Int
    let remoteCount: Int?
    let remoteDate: String?
}
enum CloudChoice: Equatable { case local, remote }
struct CloudResolution { let choice: CloudChoice; let conflict: CloudConflict }
enum CloudSyncResult {
    case synced(CloudLink, downloaded: Bool), conflict(CloudConflict), busy
}
protocol CloudRemote {
    func load() async throws -> CloudRecord?
    func save(_ ledger: Ledger, expectedRevision: Int) async throws -> Int
}

/// HTTP only; account state, local IO and conflict decisions are kept separately testable.
actor SupabaseCloudService: CloudRemote {
    let configuration: CloudConfiguration
    private var session: CloudSession?
    private let http: URLSession
    init(configuration: CloudConfiguration, session: CloudSession? = nil, http: URLSession = .shared) {
        self.configuration = configuration; self.session = session; self.http = http
    }
    private func request(_ path: String, method: String = "POST", body: [String: Any]? = nil, authenticated: Bool = false) async throws -> Data {
        guard let url = URL(string: configuration.server + path) else { throw CloudFailure.configuration }
        var request = URLRequest(url: url); request.httpMethod = method; request.timeoutInterval = 30
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(configuration.publicKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        if authenticated {
            guard let session else { throw CloudFailure.session }
            request.setValue("Bearer " + session.access_token, forHTTPHeaderField: "Authorization")
        }
        let data: Data; let response: URLResponse
        do { (data, response) = try await http.data(for: request) }
        catch is CancellationError { throw CancellationError() }
        catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            throw CloudFailure.transport(code: error.code.rawValue, endpoint: url.path)
        }
        catch { throw CloudFailure.connection }
        guard let response = response as? HTTPURLResponse else { throw CloudFailure.invalidResponse }
        guard (200..<300).contains(response.statusCode) else {
            let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            // Keep 401 as a session error so CloudAccount can refresh and retry.
            if path == "/functions/v1/investment-research", response.statusCode == 403 {
                throw reviewError("公司研究仅限服务端配置的个人账号使用。", "Company research is restricted to the configured personal account.", "Penyelidikan syarikat terhad kepada akaun peribadi yang ditetapkan.")
            }
            if path == "/functions/v1/receipt-gemini", response.statusCode != 401,
               let receiptCode = object?["error"] as? String,
               let failure = ReceiptRecognitionFailure(rawValue: receiptCode) { throw failure }
            if path == "/functions/v1/bank-notification-gemini", response.statusCode != 401,
               let code = object?["error"] as? String,
               let failure = BankAnalysisFailure(rawValue: code) { throw failure }
            let code = object?["error_code"] as? String ?? object?["code"] as? String ?? ""
            if code == "40001" { throw CloudFailure.changed }
            if ["42P01", "42883", "PGRST202", "PGRST205"].contains(code) { throw CloudFailure.database }
            if response.statusCode == 429 { throw CloudFailure.rateLimit }
            if code == "weak_password" || code == "same_password" { throw CloudFailure.password }
            if path.contains("grant_type=password"), [400, 401, 422].contains(response.statusCode) { throw CloudFailure.credentials }
            if path.contains("grant_type=refresh_token"), [400, 401].contains(response.statusCode) { throw CloudFailure.session }
            if path.contains("/verify"), [400, 401].contains(response.statusCode) { throw CloudFailure.authentication }
            if response.statusCode == 401 { throw authenticated ? CloudFailure.session : CloudFailure.configuration }
            if response.statusCode == 403 { throw CloudFailure.configuration }
            if path.contains("/otp") || path.contains("/signup") || path.contains("/recover") { throw CloudFailure.email }
            throw CloudFailure.server(status: response.statusCode, endpoint: url.path)
        }
        guard data.count <= 25_000_000 else { throw CloudFailure.invalidResponse }
        return data
    }
    func checkConnection() async throws {
        _ = try await request("/auth/v1/settings", method: "GET")
        let health = try await request("/rest/v1/rpc/yueji_sync_health", body: [:])
        guard (try? JSONDecoder().decode(Int.self, from: health)) == 1 else { throw CloudFailure.database }
    }
    func assistant(mode: String, text: String, categories: [String], merchant: String = "") async throws -> Data {
        guard mode == "classify", text.count <= 1000, merchant.count <= 200 else { throw CloudFailure.invalidResponse }
        do { return try await request("/functions/v1/assistant-gemini", body: ["mode": mode, "text": text, "merchant": merchant, "categories": categories], authenticated: true) }
        catch CloudFailure.server(let status, _) {
            if status == 422 {
                throw reviewError("AI 未能明确理解，请缩短描述并重试。", "AI could not interpret this clearly. Try a shorter description.", "AI tidak dapat mentafsir dengan jelas. Cuba penerangan lebih ringkas.")
            }
            throw reviewError("AI 服务尚未就绪，请检查 assistant-gemini、GEMINI_ASSISTANT_MODEL 和额度 SQL。", "AI service is not ready. Check assistant-gemini, GEMINI_ASSISTANT_MODEL and quota SQL.", "Perkhidmatan AI belum tersedia. Semak assistant-gemini, GEMINI_ASSISTANT_MODEL dan SQL kuota.")
        }
    }
    func researchStock(symbols: [String]) async throws -> Data {
        guard (1...3).contains(symbols.count), Set(symbols).count == symbols.count,
              symbols.allSatisfy({ ObservedStock.normalized($0) == $0 }) else { throw CloudFailure.invalidResponse }
        do { return try await request("/functions/v1/investment-research", body: ["symbols": symbols], authenticated: true) }
        catch CloudFailure.server(let status, _) {
            if status == 422 {
                throw reviewError("未取得有来源的研究资料，请稍后重试。", "No sourced research was returned. Try again later.", "Tiada penyelidikan bersumber. Cuba lagi kemudian.")
            }
            throw reviewError("公司研究尚未就绪，请检查 investment-research 部署及独立研究配置。", "Company research is unavailable. Check investment-research deployment and its separate configuration.", "Penyelidikan syarikat belum tersedia. Semak penggunaan investment-research dan konfigurasi berasingan.")
        }
    }
    func recognizeReceipt(image: Data, transaction: Bool = false) async throws -> Data {
        guard image.count <= 4_000_000 else { throw CloudFailure.invalidResponse }
        var body = ["image": image.base64EncodedString()]
        if transaction { body["mode"] = "transaction" }
        do { return try await request("/functions/v1/receipt-gemini", body: body, authenticated: true) }
        catch CloudFailure.server(let status, _) {
            if status == 404 {
                throw reviewError("未找到收据识别服务，请检查当前 Supabase 项目是否已部署 receipt-gemini。", "Receipt recognition was not found. Check that receipt-gemini is deployed to the current Supabase project.", "Perkhidmatan resit tidak ditemui. Semak bahawa receipt-gemini telah digunakan pada projek Supabase semasa.")
            }
            throw LedgerError.invalid(tr("Gemini 收据服务暂时不可用，请稍后重试。", "Gemini receipt service is unavailable. Please retry later.", "Perkhidmatan resit Gemini tidak tersedia. Cuba lagi kemudian.") + " (HTTP \(status))")
        }
    }
    func analyseBankNotification(body: String, title: String, source: String) async throws -> Data {
        guard body.count <= 8000, title.count <= 500, source.count <= 120 else { throw CloudFailure.invalidResponse }
        do {
            return try await request("/functions/v1/bank-notification-gemini",
                                     body: ["body": body, "title": title, "source": source], authenticated: true)
        } catch CloudFailure.server(let status, _) {
            if status == 404 {
                throw reviewError("未找到银行 AI 服务，请部署 bank-notification-gemini。", "Bank AI service was not found. Deploy bank-notification-gemini.", "Perkhidmatan AI bank tidak ditemui. Gunakan bank-notification-gemini.")
            }
            throw LedgerError.invalid(tr("银行 AI 服务返回错误，请查看同一时间的服务端日志。", "Bank AI returned an error. Check server logs at the same time.", "AI bank memulangkan ralat. Semak log pelayan pada masa yang sama.") + " (HTTP \(status))")
        }
    }
    func sendCode(email: String, createAccount: Bool = true) async throws {
        _ = try await request("/auth/v1/otp", body: ["email": email, "create_user": createAccount])
    }
    func signUp(email: String, password: String) async throws -> CloudSession? {
        let data = try await request("/auth/v1/signup", body: ["email": email, "password": password])
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        if object?["access_token"] != nil { return try JSONDecoder().decode(CloudSession.self, from: data) }
        return nil
    }
    func signIn(email: String, password: String) async throws -> CloudSession {
        let data = try await request("/auth/v1/token?grant_type=password", body: ["email": email, "password": password])
        return try JSONDecoder().decode(CloudSession.self, from: data)
    }
    func recover(email: String) async throws {
        _ = try await request("/auth/v1/recover", body: ["email": email])
    }
    func exchangeGoogleCode(_ code: String, verifier: String) async throws -> CloudSession {
        let data = try await request("/auth/v1/token?grant_type=pkce", body: ["auth_code": code, "code_verifier": verifier])
        return try JSONDecoder().decode(CloudSession.self, from: data)
    }
    func checkGoogleProvider() async throws {
        let data = try await request("/auth/v1/settings", method: "GET")
        let settings = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard (settings?["external"] as? [String: Any])?["google"] as? Bool == true else { throw CloudFailure.googleUnavailable }
    }
    func updatePassword(_ password: String) async throws {
        _ = try await request("/auth/v1/user", method: "PUT", body: ["password": password], authenticated: true)
    }
    func verify(email: String, code: String, type: String = "email") async throws -> CloudSession {
        let data = try await request("/auth/v1/verify", body: ["email": email, "token": code, "type": type])
        return try JSONDecoder().decode(CloudSession.self, from: data)
    }
    func use(_ value: CloudSession) { session = value }
    func refresh() async throws -> CloudSession {
        guard let session else { throw CloudFailure.session }
        let data = try await request("/auth/v1/token?grant_type=refresh_token", body: ["refresh_token": session.refresh_token])
        let value = try JSONDecoder().decode(CloudSession.self, from: data)
        guard value.user.id == session.user.id else { throw CloudFailure.accountMismatch }
        self.session = value
        return value
    }
    func load() async throws -> CloudRecord? {
        guard let session else { throw CloudFailure.session }
        let data = try await request("/rest/v1/yueji_backups?select=payload,revision,updated_at&user_id=eq." + session.user.id.uuidString.lowercased(), method: "GET", authenticated: true)
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let records = try decoder.decode([CloudRecord].self, from: data)
        guard records.count <= 1 else { throw CloudFailure.invalidResponse }
        if let record = records.first { guard record.revision > 0 else { throw CloudFailure.invalidResponse }; _ = try record.payload.validated() }
        return records.first
    }
    func save(_ ledger: Ledger, expectedRevision: Int) async throws -> Int {
        let payload = try JSONSerialization.jsonObject(with: LocalStore.encode(ledger.validated()))
        let data = try await request("/rest/v1/rpc/save_yueji_backup", body: ["p_payload": payload, "p_expected_revision": expectedRevision], authenticated: true)
        let revision = try JSONDecoder().decode(Int.self, from: data)
        guard revision == expectedRevision + 1 else { throw CloudFailure.invalidResponse }
        return revision
    }
}

actor CloudSynchronizer {
    private let overrideStore: LocalStore?
    private var store: LocalStore { overrideStore ?? .shared }
    private var running = false
    init(store: LocalStore? = nil) { self.overrideStore = store }
    func localLink() throws -> CloudLink? { try store.cloudLink() }
    func sync(userID: UUID, server: String, remote: any CloudRemote, resolution: CloudResolution? = nil) async throws -> CloudSyncResult {
        let store = self.store // Pin the account for the entire network operation.
        guard !running else { return .busy }
        running = true; defer { running = false }
        let previousLink = try store.cloudLink()
        if let previousLink, !previousLink.accepts(userID: userID, server: server) { throw CloudFailure.accountMismatch }
        let cloud = try await remote.load()
        try Task.checkCancellation()
        let snapshot = try store.readSnapshot()
        let localHash = try CloudFingerprint.make(snapshot.ledger)
        let remoteHash = try cloud.map { try CloudFingerprint.make($0.payload) }
        let conflict = CloudConflict(localFingerprint: localHash, remoteFingerprint: remoteHash, remoteRevision: cloud?.revision ?? 0,
                                     localCount: snapshot.ledger.expenses.count, remoteCount: cloud?.payload.expenses.count, remoteDate: cloud?.updated_at)
        var decision = CloudSyncDecision.decide(local: localHash, hasLocalFile: !snapshot.signature.isEmpty,
                                                remote: remoteHash, revision: cloud?.revision ?? 0, link: previousLink)
        if let resolution {
            guard resolution.conflict.localFingerprint == localHash,
                  resolution.conflict.remoteFingerprint == remoteHash,
                  resolution.conflict.remoteRevision == conflict.remoteRevision else { return .conflict(conflict) }
            decision = resolution.choice == .local ? .upload : .download
        }
        guard decision != .conflict else { return .conflict(conflict) }
        // Bind before the first upload: a lost HTTP response cannot leave these records
        // eligible for uploading into a different person's account.
        var link = previousLink ?? CloudLink(userID: userID, server: server)
        try store.writeCloudLink(link)
        switch decision {
        case .download:
            guard let cloud else { return .conflict(conflict) }
            try store.replaceFromCloud(cloud.payload, expectedFingerprint: localHash)
            link.revision = cloud.revision; link.fingerprint = remoteHash
        case .upload:
            link.revision = try await remote.save(snapshot.ledger, expectedRevision: cloud?.revision ?? 0)
            link.fingerprint = localHash
        case .equal:
            link.revision = cloud?.revision ?? 0; link.fingerprint = localHash
        case .conflict: return .conflict(conflict)
        }
        // Keep the fingerprint of the exact snapshot acknowledged by the server. A
        // local write during upload remains dirty and is picked up by the next pass.
        link.lastSync = Date()
        try store.writeCloudLink(link)
        return .synced(link, downloaded: decision == .download)
    }
    func needsUpload(comparedTo link: CloudLink) throws -> Bool {
        try CloudFingerprint.make(store.read()) != link.fingerprint
    }
}
