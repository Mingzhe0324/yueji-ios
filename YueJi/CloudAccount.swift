import SwiftUI
import UIKit

@MainActor final class CloudAccount: ObservableObject {
    static let shared = CloudAccount()
    @Published private(set) var loaded = false
    @Published private(set) var signedIn = false
    @Published private(set) var email = ""
    @Published private(set) var busy = false
    @Published private(set) var message = ""
    @Published private(set) var link: CloudLink?
    @Published private(set) var conflict: CloudConflict?
    @Published private(set) var codeSent = false
    @Published private(set) var dirty = false
    @Published private(set) var lastSyncFailed = false
    @Published private(set) var cloudRestored = UUID()
    @Published var usingLocal = false
    private var session: CloudSession?
    private var service: SupabaseCloudService?
    private let synchronizer = CloudSynchronizer()
    private var pending: Task<Void, Never>?
    private var resyncRequested = false
    private var initializationFailed = false
    private var initializing = false
    var configured: Bool { CloudConfiguration.bundled != nil }
    var canEnter: Bool {
        guard loaded, !initializationFailed else { return false }
        if signedIn, link != nil { return true }
        if signedIn, usingLocal { return true }
        return link == nil && (!configured || usingLocal)
    }
    var status: String {
        if !configured { return tr("云端尚未启用", "Cloud is not enabled", "Awan belum diaktifkan") }
        if !signedIn { return tr("登录后保留账本", "Sign in to keep your ledger", "Log masuk untuk menyimpan lejar") }
        if conflict != nil { return tr("需要选择保留的账本", "Choose a ledger to keep", "Pilih lejar untuk dikekalkan") }
        if lastSyncFailed { return tr("同步需要重试", "Sync needs retrying", "Penyegerakan perlu dicuba semula") }
        if dirty { return tr("有更改等待同步", "Changes waiting to sync", "Perubahan menunggu penyegerakan") }
        if link?.fingerprint == nil { return tr("正在准备账号账本", "Preparing account ledger", "Menyediakan lejar akaun") }
        return tr("账本已同步", "Ledger synced", "Lejar disegerakkan")
    }
    func initialize() async {
        guard !loaded, !initializing else { return }
        initializing = true; defer { initializing = false }
        // No network is needed to open a previously synced account's local ledger.
        do {
            link = try await synchronizer.localLink()
            if let config = CloudConfiguration.bundled, let credential = try CloudCredentials.read(),
               credential.server == config.server,
               link == nil || link!.accepts(userID: credential.session.user.id, server: credential.server) {
                session = credential.session; signedIn = true; email = credential.session.user.email ?? ""
                service = SupabaseCloudService(configuration: config, session: credential.session)
                if let link { dirty = try await synchronizer.needsUpload(comparedTo: link) }
            }
        } catch { initializationFailed = true; message = error.localizedDescription }
        loaded = true
        if signedIn { await sync() }
    }
    private func connectedService() throws -> SupabaseCloudService {
        if let service { return service }
        guard let configuration = CloudConfiguration.bundled else { throw CloudFailure.configuration }
        let value = SupabaseCloudService(configuration: configuration)
        service = value
        return value
    }
    func checkConnection() async {
        guard !busy else { return }
        busy = true; defer { finishWork() }
        do {
            try await connectedService().checkConnection()
            message = tr("账号服务和账本数据库连接正常。", "Account service and ledger database are reachable.", "Perkhidmatan akaun dan pangkalan data lejar boleh dicapai.")
        } catch { report(error) }
    }
    func sendCode(to address: String) async {
        guard !busy else { return }
        busy = true; defer { finishWork() }
        let address = address.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            guard address.contains("@"), address.count <= 254 else { throw CloudFailure.email }
            let api = try connectedService()
            // Diagnose missing schema before asking the person to wait for an email.
            try await api.checkConnection()
            try await api.sendCode(email: address)
            email = address; codeSent = true
            message = tr("验证码已发送，请查看邮箱并输入。", "Code sent. Check your email and enter it here.", "Kod dihantar. Semak e-mel dan masukkannya di sini.")
        } catch { report(error) }
    }
    func verify(code: String) async {
        guard !busy, codeSent else { return }
        busy = true; defer { finishWork() }
        do {
            let api = try connectedService()
            let value = try await api.verify(email: email, code: code.trimmingCharacters(in: .whitespacesAndNewlines))
            let config = await api.configuration
            let existing = try await synchronizer.localLink()
            if let existing, !existing.accepts(userID: value.user.id, server: config.server) { throw CloudFailure.accountMismatch }
            try CloudCredentials.save(CloudCredential(server: config.server, session: value))
            await api.use(value)
            session = value; signedIn = true; codeSent = false; email = value.user.email ?? email
            initializationFailed = false; usingLocal = false
            try await synchronize(api, refresh: false)
        } catch { await reloadLink(); report(error) }
    }
    func changeEmail() {
        guard !busy, !signedIn else { return }
        codeSent = false; message = ""
    }
    private func reloadLink() async {
        do { link = try await synchronizer.localLink() }
        catch { initializationFailed = true }
    }
    func sync(resolution: CloudResolution? = nil) async {
        guard signedIn else { return }
        if busy { resyncRequested = true; return }
        busy = true; defer { finishWork() }
        do { try await synchronize(connectedService(), refresh: true, resolution: resolution) }
        catch { await reloadLink(); report(error) }
    }
    private func synchronize(_ api: SupabaseCloudService, refresh: Bool, resolution: CloudResolution? = nil) async throws {
        let config = await api.configuration
        if refresh {
            let value = try await api.refresh()
            try CloudCredentials.save(CloudCredential(server: config.server, session: value))
            session = value
        }
        guard let session else { throw CloudFailure.session }
        let result = try await synchronizer.sync(userID: session.user.id, server: config.server, remote: api, resolution: resolution)
        switch result {
        case .synced(let value, let downloaded):
            lastSyncFailed = false
            if downloaded { UserDefaults.standard.set(true, forKey: "completedUsageGuide") }
            link = value; conflict = nil; initializationFailed = false
            dirty = try await synchronizer.needsUpload(comparedTo: value)
            if downloaded { cloudRestored = UUID() }
            message = dirty ? tr("还有新的更改，正在继续同步。", "New changes remain; syncing again.", "Masih ada perubahan baharu; menyegerakkan lagi.") :
                tr("已同步。重新安装后，登录同一账号即可继续。", "Synced. After reinstalling, sign in to the same account to continue.", "Disegerakkan. Selepas pasang semula, log masuk ke akaun sama untuk meneruskan.")
            if dirty { resyncRequested = true }
        case .conflict(let value):
            conflict = value; dirty = true; message = CloudFailure.conflict.localizedDescription
        case .busy: resyncRequested = true
        }
    }
    func ledgerDidChange() {
        if !loaded {
            resyncRequested = true
            guard !initializing else { return }
            // Shortcuts may write without mounting the app's root view. Load the
            // saved session here too, within the available background time.
            let token = BackgroundTaskToken()
            token.begin()
            Task { await initialize(); token.end() }
            return
        }
        guard signedIn else { return }
        dirty = true
        if busy { resyncRequested = true; return }
        schedule()
    }
    private func schedule() {
        guard signedIn, conflict == nil else { return }
        pending?.cancel()
        pending = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(1)); try Task.checkCancellation() } catch { return }
            // Clear before starting IO: later changes must not cancel an upload that
            // the server may already have committed.
            self?.pending = nil
            await self?.sync()
        }
    }
    private func finishWork() {
        busy = false
        if resyncRequested { resyncRequested = false; schedule() }
    }
    private func report(_ error: Error) {
        lastSyncFailed = true
        message = error.localizedDescription
        if case CloudFailure.session = error {
            // Do not discard local data or ownership when refresh is rejected.
            signedIn = false; session = nil; usingLocal = false; pending?.cancel()
            try? CloudCredentials.clear(); service = nil
        }
    }
    func signOut() {
        guard !busy else { return }
        do {
            try CloudCredentials.clear()
            pending?.cancel(); pending = nil; resyncRequested = false
            session = nil; service = nil; signedIn = false; usingLocal = false; conflict = nil; codeSent = false
            message = tr("已退出登录。云端和本机账本均保留，请用原账号重新登录。", "Signed out. Cloud and local ledgers are retained; sign in to the original account.", "Log keluar. Lejar awan dan setempat dikekalkan; log masuk ke akaun asal.")
        } catch { report(error) }
    }
    func syncInBackground() {
        guard signedIn else { return }
        let token = BackgroundTaskToken()
        token.begin()
        Task { await sync(); token.end() }
    }
}

struct CloudEntryView: View {
    @ObservedObject private var cloud = CloudAccount.shared
    @EnvironmentObject private var model: LedgerModel
    @Environment(\.scenePhase) private var phase
    var body: some View {
        Group {
            if !cloud.loaded { ProgressView() }
            else if cloud.canEnter { MainView() }
            else { NavigationStack { CloudAccountView(isEntry: true) } }
        }
        .task { await cloud.initialize() }
        .onChange(of: cloud.cloudRestored) { _, _ in Task { await model.refresh(postRecurring: false) } }
        .onChange(of: phase) { _, value in
            if value == .active { Task { await cloud.sync() } }
            if value == .background { cloud.syncInBackground() }
        }
    }
}

struct CloudAccountView: View {
    var isEntry = false
    @ObservedObject private var cloud = CloudAccount.shared
    @Environment(\.locale) private var uiLocale
    @State private var address = ""
    @State private var code = ""
    @State private var choice: CloudChoice?
    @State private var confirmation: CloudConflict?
    @State private var confirming = false
    @State private var signingOut = false
    var body: some View {
        let _ = uiLocale.identifier
        Form {
            Section {
                Text(tr("登录同一账号，重新安装后自动找回账本并继续记账。登录后会将本机账本关联到此账号。", "Sign in to the same account after reinstalling to recover your ledger and continue. Signing in links this device's ledger to that account.", "Log masuk ke akaun sama selepas pasang semula untuk mendapatkan lejar dan meneruskan. Log masuk memautkan lejar peranti kepada akaun itu."))
            }
            if !cloud.configured {
                Section {
                    Text(CloudFailure.configuration.localizedDescription)
                }
            } else if !cloud.signedIn {
                Section(tr("邮箱登录", "Email sign-in", "Log masuk e-mel")) {
                    TextField(tr("邮箱", "Email", "E-mel"), text: $address)
                        .keyboardType(.emailAddress).textContentType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .disabled(cloud.codeSent)
                    Button(tr("发送登录验证码", "Send sign-in code", "Hantar kod log masuk")) { Task { await cloud.sendCode(to: address) } }
                        .disabled(cloud.busy || !address.contains("@"))
                    if cloud.codeSent {
                        TextField(tr("邮件验证码", "Email code", "Kod e-mel"), text: $code).textContentType(.oneTimeCode).keyboardType(.numberPad)
                        Button(tr("登录并恢复账本", "Sign in and recover ledger", "Log masuk dan pulihkan lejar")) {
                            Task { await cloud.verify(code: code); code = "" }
                        }.disabled(cloud.busy || code.isEmpty)
                        Button(tr("更换邮箱", "Change email", "Tukar e-mel")) { code = ""; cloud.changeEmail() }
                    }
                }.disabled(cloud.busy)
            } else {
                Section(tr("账号", "Account", "Akaun")) {
                    Text(cloud.email)
                    Label(cloud.status, systemImage: cloud.dirty ? "icloud.and.arrow.up" : "icloud")
                    if let date = cloud.link?.lastSync {
                        LabeledContent(tr("上次同步", "Last sync", "Segerak terakhir"), value: dateLabel(date, time: true))
                    }
                    Button(tr("立即同步", "Sync now", "Segerakkan sekarang")) { Task { await cloud.sync() } }.disabled(cloud.busy)
                    Button(tr("退出登录", "Sign out", "Log keluar"), role: .destructive) { signingOut = true }.disabled(cloud.busy)
                }
                if let conflict = cloud.conflict {
                    Section(tr("选择保留的账本", "Choose the ledger to keep", "Pilih lejar untuk dikekalkan")) {
                        LabeledContent(tr("本机账目", "Local entries", "Rekod setempat"), value: String(conflict.localCount))
                        LabeledContent(tr("云端账目", "Cloud entries", "Rekod awan"), value: conflict.remoteCount.map(String.init) ?? "—")
                        if let date = conflict.remoteDate { Text(date).font(.caption) }
                        if conflict.remoteCount != nil {
                            Button(tr("使用云端账本", "Use cloud ledger", "Gunakan lejar awan")) { choose(.remote, conflict) }
                        }
                        Button(tr("保留本机并更新云端", "Keep local and update cloud", "Kekalkan setempat dan kemas kini awan")) { choose(.local, conflict) }
                        Text(tr("这是整份账本的选择，不会自动合并金额。更改后的另一份记录可能被替换。", "This selects a whole ledger; amounts are not automatically merged. Changes in the other copy may be replaced.", "Ini memilih seluruh lejar; amaun tidak digabungkan secara automatik. Perubahan dalam salinan lain mungkin diganti.")).font(.footnote)
                    }.disabled(cloud.busy)
                }
            }
            Section {
                if cloud.busy { ProgressView(tr("正在连接…", "Connecting…", "Menyambung…")) }
                if !cloud.message.isEmpty { Text(cloud.message).font(.footnote) }
                Button(tr("检查云端连接", "Check cloud connection", "Semak sambungan awan")) { Task { await cloud.checkConnection() } }.disabled(cloud.busy || !cloud.configured)
                Text(tr("离线时可继续使用已同步到本机的账本。卸载前请确认没有等待同步的更改。", "You can use a previously synced local ledger offline. Before uninstalling, check that no changes are waiting to sync.", "Lejar setempat yang telah disegerakkan boleh digunakan di luar talian. Sebelum menyahpasang, pastikan tiada perubahan menunggu penyegerakan.")).font(.footnote)
                if isEntry, cloud.link == nil {
                    Button(tr("暂时使用本机账本", "Use local ledger for now", "Gunakan lejar setempat dahulu")) { cloud.usingLocal = true }.disabled(cloud.busy)
                }
            }
        }
        .yuejiListSurface()
        .navigationTitle(tr("账号与同步", "Account & sync", "Akaun & penyegerakan"))
        .onAppear { address = cloud.email }
        .confirmationDialog(tr("确认使用这份账本？", "Use this ledger?", "Gunakan lejar ini?"), isPresented: $confirming, titleVisibility: .visible) {
            Button(tr("确认", "Confirm", "Sahkan"), role: .destructive) {
                guard let choice, let confirmation else { return }
                Task { await cloud.sync(resolution: CloudResolution(choice: choice, conflict: confirmation)) }
            }
        }
        .confirmationDialog(tr("退出登录？", "Sign out?", "Log keluar?"), isPresented: $signingOut, titleVisibility: .visible) {
            Button(tr("退出登录", "Sign out", "Log keluar"), role: .destructive) { cloud.signOut() }
        } message: {
            Text(tr("未同步的记录只保留在本机。退出后需要用同一账号重新登录。", "Unsynced records remain only on this device. You will need to sign in to the same account again.", "Rekod belum disegerakkan hanya kekal pada peranti. Anda perlu log masuk semula ke akaun sama."))
        }
    }
    private func choose(_ choice: CloudChoice, _ conflict: CloudConflict) {
        self.choice = choice; confirmation = conflict; confirming = true
    }
}
