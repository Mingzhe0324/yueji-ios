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
    case configuration, database, connection, session, accountMismatch, changed, conflict, invalidResponse, keychain, rateLimit, email, authentication
    var errorDescription: String? {
        switch self {
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
        catch { throw CloudFailure.connection }
        guard let response = response as? HTTPURLResponse else { throw CloudFailure.invalidResponse }
        guard (200..<300).contains(response.statusCode) else {
            let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let code = object?["error_code"] as? String ?? object?["code"] as? String ?? ""
            if code == "40001" { throw CloudFailure.changed }
            if ["42P01", "42883", "PGRST202", "PGRST205"].contains(code) { throw CloudFailure.database }
            if response.statusCode == 429 { throw CloudFailure.rateLimit }
            if path.contains("grant_type=refresh_token"), [400, 401].contains(response.statusCode) { throw CloudFailure.session }
            if path.contains("/verify"), [400, 401].contains(response.statusCode) { throw CloudFailure.authentication }
            if response.statusCode == 401 { throw authenticated ? CloudFailure.session : CloudFailure.configuration }
            if response.statusCode == 403 { throw CloudFailure.configuration }
            if path.contains("/otp") { throw CloudFailure.email }
            throw CloudFailure.connection
        }
        guard data.count <= 25_000_000 else { throw CloudFailure.invalidResponse }
        return data
    }
    func checkConnection() async throws {
        _ = try await request("/auth/v1/settings", method: "GET")
        let health = try await request("/rest/v1/rpc/yueji_sync_health", body: [:])
        guard (try? JSONDecoder().decode(Int.self, from: health)) == 1 else { throw CloudFailure.database }
    }
    func sendCode(email: String) async throws {
        _ = try await request("/auth/v1/otp", body: ["email": email, "create_user": true])
    }
    func verify(email: String, code: String) async throws -> CloudSession {
        let data = try await request("/auth/v1/verify", body: ["email": email, "token": code, "type": "email"])
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
    private let store: LocalStore
    private var running = false
    init(store: LocalStore = .shared) { self.store = store }
    func localLink() throws -> CloudLink? { try store.cloudLink() }
    func sync(userID: UUID, server: String, remote: any CloudRemote, resolution: CloudResolution? = nil) async throws -> CloudSyncResult {
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
