import SwiftUI
import Security
import CryptoKit

private struct CloudSession: Codable {
    var access_token: String
    var refresh_token: String
    var user: CloudUser
}
private struct CloudUser: Codable { var id: String; var email: String? }
private struct CloudBackup: Decodable { var payload: Ledger; var revision: Int; var updated_at: String }
private enum CloudKeys {
    static let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "YueJi.CloudSession", kSecAttrAccount as String: "session"]
    static func read() -> Data? {
        var lookup = query; lookup[kSecReturnData as String] = true; lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?; guard SecItemCopyMatching(lookup as CFDictionary, &result) == errSecSuccess else { return nil }; return result as? Data
    }
    static func save(_ data: Data) throws {
        let attributes: [String: Any] = [kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query; attributes.forEach { item[$0.key] = $0.value }
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw LedgerError.invalid("无法安全保存登录，请重试。") }
        } else if status != errSecSuccess { throw LedgerError.invalid("无法安全保存登录，请重试。") }
    }
    static func clear() { SecItemDelete(query as CFDictionary) }
}

/// Cloud backup is explicitly enabled only after the user chooses the account's data.
/// Revision conflicts stop uploads; a different account never inherits local data automatically.
@MainActor final class CloudAccount: ObservableObject {
    static let shared = CloudAccount()
    @Published private(set) var email: String?
    @Published private(set) var busy = false
    @Published private(set) var message = ""
    @Published private(set) var ready = false
    @Published private(set) var remoteAvailable = false
    @Published private(set) var lastBackup: Date?
    private var session: CloudSession?
    private var revision = 0
    private var pending: Task<Void, Never>?
    private var observer: NSObjectProtocol?
    private var generation = UUID()
    private var fingerprint: String?
    private var remote: CloudBackup?
    private var base: String { (Bundle.main.object(forInfoDictionaryKey: "YueJiSupabaseURL") as? String ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "/ ")) }
    private var publicKey: String { Bundle.main.object(forInfoDictionaryKey: "YueJiSupabasePublicKey") as? String ?? "" }
    var configured: Bool { URL(string: base)?.scheme == "https" && !publicKey.isEmpty && !publicKey.contains("$(") }
    private init() {
        if let data = CloudKeys.read(), let value = try? JSONDecoder().decode(CloudSession.self, from: data) { session = value; email = value.user.email }
        let savedDate = UserDefaults.standard.double(forKey: "lastCloudBackup")
        if savedDate > 0 { lastBackup = Date(timeIntervalSince1970: savedDate) }
        observer = NotificationCenter.default.addObserver(forName: .yuejiLedgerChanged, object: nil, queue: .main) { _ in
            Task { @MainActor in CloudAccount.shared.schedule() }
        }
    }
    private func request(_ path: String, method: String = "POST", body: Data? = nil, authenticated: Bool = false) async throws -> Data {
        guard configured, let url = URL(string: base + path) else { throw LedgerError.invalid("云端尚未配置，请先按 CloudSetup.md 配置项目。") }
        var request = URLRequest(url: url); request.httpMethod = method; request.httpBody = body; request.timeoutInterval = 25
        request.setValue(publicKey, forHTTPHeaderField: "apikey"); request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if authenticated { guard let session else { throw LedgerError.invalid("请先登录。") }; request.setValue("Bearer " + session.access_token, forHTTPHeaderField: "Authorization") }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let detail = json?["msg"] as? String ?? json?["message"] as? String ?? json?["error_description"] as? String ?? "请求失败，请检查网络或登录状态。"
            throw LedgerError.invalid(detail)
        }
        return data
    }
    private func json(_ values: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: values) }
    private func install(_ data: Data) throws {
        let value = try JSONDecoder().decode(CloudSession.self, from: data)
        try CloudKeys.save(try JSONEncoder().encode(value)); session = value; email = value.user.email
    }
    private func refresh() async throws {
        guard let session else { throw LedgerError.invalid("请先登录。") }
        let data = try await request("/auth/v1/token?grant_type=refresh_token", body: json(["refresh_token": session.refresh_token]))
        try install(data)
    }
    func authenticate(email: String, password: String, create: Bool) async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do {
            guard email.contains("@"), password.count >= 8 else { throw LedgerError.invalid("请输入有效邮箱和至少 8 位密码。") }
            let data = try await request(create ? "/auth/v1/signup" : "/auth/v1/token?grant_type=password", body: json(["email": email.trimmingCharacters(in: .whitespacesAndNewlines), "password": password]))
            if create, (try? JSONDecoder().decode(CloudSession.self, from: data)) == nil { message = "验证邮件已发送。点击邮件中的确认链接后，返回登录。"; return }
            try install(data); lastBackup = nil; generation = UUID(); ready = false; remote = nil; remoteAvailable = false; revision = 0; fingerprint = nil; try await loadRemote()
        } catch { message = error.localizedDescription }
    }
    func requestReset(_ email: String) async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do { _ = try await request("/auth/v1/recover", body: json(["email": email])); message = "重置邮件已发送。请在下方输入邮件验证码和新密码。" }
        catch { message = error.localizedDescription }
    }
    func verify(email: String, code: String, newPassword: String, recovery: Bool) async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do {
            if recovery && newPassword.count < 8 { throw LedgerError.invalid("新密码至少需要 8 位。") }
            let data = try await request("/auth/v1/verify", body: json(["email": email, "token": code, "type": recovery ? "recovery" : "signup"]))
            try install(data); ready = false; remote = nil; remoteAvailable = false; revision = 0; fingerprint = nil; generation = UUID()
            if recovery { _ = try await request("/auth/v1/user", method: "PUT", body: json(["password": newPassword]), authenticated: true) }
            try await loadRemote()
        } catch { message = error.localizedDescription }
    }
    private func loadRemote() async throws {
        guard let session else { return }
        let data = try await request("/rest/v1/yueji_backups?select=payload,revision,updated_at&user_id=eq." + session.user.id, method: "GET", authenticated: true)
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        remote = try decoder.decode([CloudBackup].self, from: data).first
        if let remote { _ = try remote.payload.validated() }
        remoteAvailable = remote != nil; revision = remote?.revision ?? 0
        message = remote == nil ? "云端暂无备份。请选择上传本机账目。" : "找到云端备份。请选择恢复云端，或用本机账目替换云端。"
    }
    func reconnect() async {
        guard configured, session != nil, !busy else { return }; busy = true; defer { busy = false }
        do {
            try await refresh()
            if !ready {
                try await loadRemote()
                if let session, UserDefaults.standard.string(forKey: "cloudLedgerOwner") == session.user.id,
                   UserDefaults.standard.object(forKey: "cloudSyncedRevision") != nil,
                   UserDefaults.standard.integer(forKey: "cloudSyncedRevision") == revision, remote != nil {
                    ready = true; fingerprint = UserDefaults.standard.string(forKey: "cloudSyncedFingerprint")
                    try await upload()
                }
            } else { try await upload() }
        } catch { message = "尚未同步：" + error.localizedDescription }
    }
    func useLocal() async {
        guard !busy, let session else { return }; busy = true; defer { busy = false }
        do {
            let owner = UserDefaults.standard.string(forKey: "cloudLedgerOwner")
            guard owner == nil || owner == session.user.id else { throw LedgerError.invalid("本机账目属于另一个账号。请先恢复此账号的云端备份，不能跨账号上传。") }
            try await refresh(); try await upload()
            UserDefaults.standard.set(session.user.id, forKey: "cloudLedgerOwner"); ready = true; schedule()
        } catch { message = error.localizedDescription; ready = false }
    }
    func restoreRemote() async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do {
            ready = false; pending?.cancel(); try await refresh(); try await loadRemote()
            guard let remote, let session else { throw LedgerError.invalid("没有可恢复的云端备份。") }
            let data = try LocalStore.encode(remote.payload.validated())
            try LocalStore.shared.replaceCloud(data)
            fingerprint = Self.digest(data); revision = remote.revision
            persistSync()
            UserDefaults.standard.set(session.user.id, forKey: "cloudLedgerOwner")
            ready = true; message = "云端账目已恢复。原本机账目保存在导入前恢复副本中。"
            NotificationCenter.default.post(name: .yuejiCloudRestored, object: nil)
        } catch { message = error.localizedDescription }
    }
    static func digest(_ data: Data) -> String {
        var canonical = data
        if var object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            for key in ["seenEvents", "postedRecurring", "dismissedDuplicates"] {
                if let values = object[key] as? [String] { object[key] = values.sorted() }
            }
            if let sorted = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) { canonical = sorted }
        }
        return SHA256.hash(data: canonical).map { String(format: "%02x", $0) }.joined()
    }
    private func upload() async throws {
        let token = generation
        let data = try LocalStore.encode(LocalStore.shared.read()); let hash = Self.digest(data)
        guard fingerprint != hash else { message = "账目已与云端一致。"; return }
        let payload = try JSONSerialization.jsonObject(with: data)
        let response = try await request("/rest/v1/rpc/save_yueji_backup", body: json(["p_payload": payload, "p_expected_revision": revision]), authenticated: true)
        guard generation == token else { return }
        revision = try JSONDecoder().decode(Int.self, from: response); fingerprint = hash
        persistSync()
        lastBackup = Date(); UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "lastCloudBackup")
        remoteAvailable = true; message = "备份成功。卸载后登录同一账号即可恢复这份账目。"
        if let current = try? LocalStore.encode(LocalStore.shared.read()), Self.digest(current) != hash { schedule() }
    }
    private func persistSync() {
        UserDefaults.standard.set(revision, forKey: "cloudSyncedRevision")
        UserDefaults.standard.set(fingerprint, forKey: "cloudSyncedFingerprint")
    }
    private func schedule() {
        guard ready, session != nil else { return }; pending?.cancel()
        pending = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(2)); try Task.checkCancellation() } catch { return }
            await self?.reconnect()
        }
    }
    func signOut() {
        guard !busy else { return }; pending?.cancel(); generation = UUID(); ready = false
        session = nil; email = nil; remote = nil; revision = 0; fingerprint = nil; remoteAvailable = false; lastBackup = nil
        CloudKeys.clear(); message = "已退出。账目仍保留在本机，请勿卸载未备份的记录。"
    }
}
extension Notification.Name {
    static let yuejiLedgerChanged = Notification.Name("yuejiLedgerChanged")
    static let yuejiCloudRestored = Notification.Name("yuejiCloudRestored")
}

struct CloudAccountView: View {
    @ObservedObject private var cloud = CloudAccount.shared
    @EnvironmentObject private var model: LedgerModel
    @State private var email = ""
    @State private var password = ""
    @State private var creating = false
    @State private var code = ""
    @State private var recovering = false
    @State private var newPassword = ""
    @State private var confirmUpload = false
    @State private var confirmRestore = false
    var body: some View {
        Form {
            if !cloud.configured {
                Section("云端尚未启用") { Text("此版本已加入账号与云备份接入。需要先按源码中的 CloudSetup.md 创建 Supabase 项目、运行 SQL 并配置 URL 与公开密钥，然后重新构建。启用前请继续导出完整备份。") }
            } else if let account = cloud.email {
                Section("账号") { Text(account); Button("退出登录") { cloud.signOut() }.disabled(cloud.busy) }
                Section("云端账目") {
                    Text(cloud.ready ? "自动备份已启用：修改后联网同步，打开 App 时重试。离线期间的新记录仍需等待同步成功。" : "先选择保留哪一份账目，再启用自动备份。")
                    if let date = cloud.lastBackup { Text("最近成功备份：" + dateLabel(date, time: true)).font(.footnote) }
                    Button(cloud.remoteAvailable ? "用本机账目替换云端备份" : "备份本机账目到此账号") { confirmUpload = true }
                    if cloud.remoteAvailable { Button("恢复此账号的云端账目") { confirmRestore = true } }
                    Button("检查并同步") { Task { await cloud.reconnect() } }
                }.disabled(cloud.busy)
            } else {
                Section(creating ? "创建账号" : "登录") {
                    TextField("邮箱", text: $email).textContentType(.emailAddress).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("密码（至少 8 位）", text: $password).textContentType(creating ? .newPassword : .password)
                    Button(creating ? "创建账号" : "登录") { Task { await cloud.authenticate(email: email, password: password, create: creating); password = "" } }.disabled(cloud.busy)
                    Toggle("创建新账号", isOn: $creating)
                    Button("忘记密码") { Task { recovering = true; await cloud.requestReset(email) } }.disabled(cloud.busy || !email.contains("@"))
                }.disabled(cloud.busy)
                Section(recovering ? "重置密码" : "验证新账号") {
                    TextField("邮件验证码", text: $code).textContentType(.oneTimeCode).textInputAutocapitalization(.never)
                    if recovering { SecureField("新密码（至少 8 位）", text: $newPassword).textContentType(.newPassword) }
                    Button(recovering ? "验证并设置新密码" : "验证邮箱") { Task { await cloud.verify(email: email, code: code, newPassword: newPassword, recovery: recovering); code = ""; newPassword = "" } }.disabled(cloud.busy || code.isEmpty)
                    Text("请使用邮件中的验证码。若邮件只包含链接，请先按 CloudSetup.md 配置验证码邮件模板。").font(.footnote)
                }
            }
            if cloud.busy { ProgressView("正在连接…") }
            if !cloud.message.isEmpty { Section("状态") { Text(cloud.message).font(.footnote).textSelection(.enabled) } }
        }.navigationTitle("账号与云备份")
            .task { await cloud.reconnect() }
            .confirmationDialog("用本机账目替换此账号的云端备份？", isPresented: $confirmUpload, titleVisibility: .visible) {
                Button("确认上传") { Task { await cloud.useLocal() } }
            } message: { Text("已有云端备份将被替换；本机属于其他账号时会阻止上传。") }
            .confirmationDialog("用云端账目替换本机账目？", isPresented: $confirmRestore, titleVisibility: .visible) {
                Button("确认恢复") { Task { await cloud.restoreRemote(); model.reload(postRecurring: false) } }
            } message: { Text("本机原数据会先保存为恢复副本。这是整份恢复，不会重复叠加记录。") }
    }
}
