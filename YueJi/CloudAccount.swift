import SwiftUI
import UIKit
import AuthenticationServices
import CryptoKit
import Security
import UserNotifications
import SceneKit

@MainActor final class CloudAccount: ObservableObject {
    static let shared = CloudAccount()
    @Published private(set) var loaded = false
    @Published private(set) var signedIn = false
    @Published private(set) var signInPresentationID = UUID()
    @Published private(set) var needsSignInAgain = false
    @Published private(set) var changingAccount = false
    @Published private(set) var email = ""
    @Published private(set) var busy = false
    @Published private(set) var message = ""
    @Published private(set) var link: CloudLink?
    @Published private(set) var conflict: CloudConflict?
    @Published private(set) var codeSent = false
    @Published private(set) var resettingPassword = false
    private var verificationType = "signup"
    private var recoverySession: CloudSession?
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
    private let googleBrowser = GoogleAccountBrowser()
    var configured: Bool { CloudConfiguration.bundled != nil }
    var canEnter: Bool {
        guard loaded, !initializationFailed, !changingAccount else { return false }
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
            try CloudInstallation.prepare(cloudConfigured: configured, hasExistingLink: link != nil,
                                          clearCredentials: CloudCredentials.clear)
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
    func verify(code: String) async {
        guard !busy, codeSent else { return }
        busy = true; defer { finishWork() }
        do {
            let api = try connectedService()
            let value = try await api.verify(email: email, code: code.trimmingCharacters(in: .whitespacesAndNewlines), type: verificationType)
            if verificationType == "recovery" {
                recoverySession = value; resettingPassword = true; codeSent = false; message = ""
            } else { try await accept(value, api: api) }
        } catch { await reloadLink(); report(error) }
    }
    private func accept(_ value: CloudSession, api: SupabaseCloudService) async throws {
        let config = await api.configuration
        changingAccount = true
        defer { changingAccount = false }
        let target = try LocalStore.accountStore(userID: value.user.id, server: config.server)
        let switched = target.folder != LocalStore.shared.folder
        try CloudCredentials.save(CloudCredential(server: config.server, session: value))
        if switched {
            AutoBackup.turnOff()
            UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
            UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        }
        LocalStore.activate(target)
        link = try target.cloudLink()
        conflict = nil; dirty = false; lastSyncFailed = false
        await api.use(value)
        session = value; signedIn = true; codeSent = false; email = value.user.email ?? email
        needsSignInAgain = false
        recoverySession = nil; resettingPassword = false
        initializationFailed = false; usingLocal = false
        try await synchronize(api, refresh: false)
        signInPresentationID = UUID()
    }
    func signInWithGoogle() async {
        guard !busy else { return }
        busy = true; defer { finishWork() }
        do {
            let api = try connectedService()
            try await api.checkGoogleProvider()
            let config = await api.configuration
            let result = try await googleBrowser.authorize(server: config.server)
            let value = try await api.exchangeGoogleCode(result.code, verifier: result.verifier)
            try await accept(value, api: api)
        } catch is CancellationError { }
        catch { await reloadLink(); report(error) }
    }
    func authenticate(address: String, password: String, confirmation: String, creating: Bool) async {
        guard !busy else { return }
        busy = true; defer { finishWork() }
        do {
            let address = address.trimmingCharacters(in: .whitespacesAndNewlines)
            guard address.contains("@"), !password.isEmpty else { throw CloudFailure.credentials }
            if creating { guard password.count >= 8, password == confirmation else { throw CloudFailure.password } }
            let api = try connectedService()
            try await api.checkConnection()
            if creating {
                if let value = try await api.signUp(email: address, password: password) {
                    try await accept(value, api: api)
                } else {
                    email = address; verificationType = "signup"; codeSent = true
                    message = tr("请查收注册验证码。若邮箱已有账号，请返回登录或重设密码。", "Check for your signup code. If you already have an account, sign in or reset your password.", "Semak kod pendaftaran. Jika sudah ada akaun, log masuk atau tetapkan semula kata laluan.")
                }
            } else {
                let value = try await api.signIn(email: address, password: password)
                try await accept(value, api: api)
            }
        } catch { await reloadLink(); report(error) }
    }
    func requestPasswordReset(address: String) async {
        guard !busy else { return }
        busy = true; defer { finishWork() }
        do {
            let address = address.trimmingCharacters(in: .whitespacesAndNewlines)
            guard address.contains("@") else { throw CloudFailure.email }
            try await connectedService().recover(email: address)
            email = address; verificationType = "recovery"; codeSent = true
            message = tr("如果账号存在，将收到重设密码验证码。", "If the account exists, a password reset code will arrive.", "Jika akaun wujud, kod tetapan semula akan dihantar.")
        } catch { report(error) }
    }
    func savePassword(_ password: String, confirmation: String) async {
        guard !busy, signedIn || recoverySession != nil else { return }
        busy = true; defer { finishWork() }
        do {
            guard password.count >= 8, password == confirmation else { throw CloudFailure.password }
            let api = try connectedService()
            if let recoverySession {
                await api.use(recoverySession)
                try await api.updatePassword(password)
                try await accept(recoverySession, api: api)
            } else {
                let refreshed = try await api.refresh()
                try CloudCredentials.save(CloudCredential(server: (await api.configuration).server, session: refreshed))
                session = refreshed
                try await api.updatePassword(password)
                message = tr("密码已更新。下次可使用邮箱和密码登录。", "Password updated. Use email and password next time.", "Kata laluan dikemas kini. Gunakan e-mel dan kata laluan lain kali.")
            }
        } catch { report(error) }
    }
    func changeEmail() {
        guard !busy, !signedIn else { return }
        codeSent = false; resettingPassword = false; recoverySession = nil; message = ""
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
            needsSignInAgain = true
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
            needsSignInAgain = false
            message = tr("已退出登录。账本已单独保留，可登录其他账号；切回原账号即可继续。", "Signed out. Your ledger is kept separately. Sign in to another account, or return to this one later.", "Log keluar. Lejar disimpan berasingan. Log masuk ke akaun lain atau kembali kemudian.")
        } catch { report(error) }
    }
    func syncInBackground() {
        guard signedIn else { return }
        let token = BackgroundTaskToken()
        token.begin()
        Task { await sync(); token.end() }
    }
}

@MainActor private final class GoogleAccountBrowser: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var browser: ASWebAuthenticationSession?
    private var anchor: UIWindow?
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        anchor ?? ASPresentationAnchor()
    }
    func authorize(server: String) async throws -> (code: String, verifier: String) {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw CloudFailure.keychain }
        func base64URL(_ data: Data) -> String {
            data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        }
        let verifier = base64URL(Data(bytes))
        let challenge = base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
        guard var url = URLComponents(string: server + "/auth/v1/authorize") else { throw CloudFailure.configuration }
        url.queryItems = [URLQueryItem(name: "provider", value: "google"),
                         URLQueryItem(name: "redirect_to", value: "yueji-auth://auth/callback"),
                         URLQueryItem(name: "code_challenge", value: challenge),
                         URLQueryItem(name: "code_challenge_method", value: "s256")]
        guard let start = url.url else { throw CloudFailure.configuration }
        anchor = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }.flatMap(\.windows).first(where: \.isKeyWindow)
        guard anchor != nil else { throw CloudFailure.connection }
        defer { browser = nil; anchor = nil }
        let callback: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: start, callbackURLScheme: "yueji-auth") { url, error in
                if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    continuation.resume(throwing: CancellationError())
                } else if let url { continuation.resume(returning: url) }
                else { continuation.resume(throwing: CloudFailure.connection) }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = true
            browser = session
            if !session.start() { continuation.resume(throwing: CloudFailure.connection) }
        }
        guard callback.scheme == "yueji-auth", callback.host == "auth", callback.path == "/callback",
              let components = URLComponents(url: callback, resolvingAgainstBaseURL: false),
              components.queryItems?.contains(where: { $0.name == "error" }) != true,
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value, !code.isEmpty else {
            throw CloudFailure.authentication
        }
        return (code, verifier)
    }
}

struct CloudEntryView: View {
    @State private var showSignInSuccess = false
    @ObservedObject private var cloud = CloudAccount.shared
    @EnvironmentObject private var model: LedgerModel
    @Environment(\.scenePhase) private var phase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("playfulAnimations") private var playful = true
    var body: some View {
        Group {
            if !cloud.loaded || cloud.changingAccount { ProgressView() }
            else if cloud.canEnter {
                AccountLedgerContent().id(cloud.link?.userID.uuidString ?? "guest").transition(.opacity)
            }
            else { NavigationStack {
                if cloud.signedIn { CloudAccountView(isEntry: true) }
                else { CloudWelcomeView() }
            } }
        }
        .animation(reduceMotion || !playful ? nil : .easeInOut(duration: 0.25), value: cloud.canEnter)
        .overlay(alignment: .top) {
            if showSignInSuccess && cloud.canEnter && cloud.signedIn {
                Label(tr("登录成功", "Signed in", "Berjaya log masuk"), systemImage: "checkmark.circle.fill")
                    .font(.headline).padding(16)
                    .background(.regularMaterial, in: Capsule()).padding(.top, 12)
                    .transition(.opacity).allowsHitTesting(false)
            }
        }
        .onChange(of: cloud.signInPresentationID) { _, _ in
            showSignInSuccess = true
        }
        .task(id: showSignInSuccess) {
            guard showSignInSuccess else { return }
            do { try await Task.sleep(for: .seconds(1.2)) } catch { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { showSignInSuccess = false }
        }
        .task { await cloud.initialize() }
        .onChange(of: cloud.cloudRestored) { _, _ in Task { await model.refresh(postRecurring: false) } }
        .onChange(of: phase) { _, value in
            if value == .active { Task { await cloud.sync() } }
            if value == .background { cloud.syncInBackground() }
        }
    }
}

/// Recreate UI state and pending editor tasks when the authenticated owner changes.
private struct AccountLedgerContent: View {
    @StateObject private var model = LedgerModel()
    @ObservedObject private var cloud = CloudAccount.shared
    var body: some View {
        MainView().environmentObject(model)
            .onChange(of: cloud.cloudRestored) { _, _ in Task { await model.refresh(postRecurring: false) } }
    }
}

/// First-run moonrise. The signed-in account/conflict screen remains available above.
private struct CloudWelcomeView: View {
    @ObservedObject private var cloud = CloudAccount.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var phase
    @AppStorage("playfulAnimations") private var playful = true
    @State private var appeared = false
    @State private var enteringText = false
    @State private var mode: Bool? // true: create account; false: returning account
    @State private var address = ""
    @State private var code = ""
    @FocusState private var field: Field?
    private enum Field: Hashable { case email, code }
    private let gold = Color(red: 0.96, green: 0.79, blue: 0.49)
    private var motion: Bool { !reduceMotion && playful && phase == .active }
    private var creating: Bool { mode == true }
    private var title: String {
        if cloud.needsSignInAgain { return tr("欢迎回来，\n请重新登录。", "Welcome back.\nSign in again.", "Selamat kembali.\nLog masuk semula.") }
        if cloud.codeSent { return tr("一封信，\n开启你的月记。", "A little code.\nA new chapter.", "Satu kod.\nBab baharu.") }
        if mode == nil { return tr("把日子，\n记成自己的光。", "Little moments.\nYour own light.", "Detik kecil.\nCahaya milikmu.") }
        return creating ? tr("你好，\n新的开始。", "Hello,\nnew beginnings.", "Helo,\npermulaan baharu.") : tr("欢迎回来，\n继续你的故事。", "Welcome back.\nYour story continues.", "Selamat kembali.\nKisahmu diteruskan.")
    }
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.06, green: 0.10, blue: 0.20), Color(red: 0.13, green: 0.20, blue: 0.32)], startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
            GeometryReader { proxy in
                ZStack {
                    Circle().fill(Color.indigo.opacity(0.40)).frame(width: 280, height: 280)
                        .position(x: proxy.size.width * 0.1, y: proxy.size.height * 0.2)
                    Circle().fill(gold.opacity(0.16)).frame(width: 240, height: 240)
                        .position(x: proxy.size.width * 0.95, y: proxy.size.height * 0.55)
                }.blur(radius: 70)
            }.ignoresSafeArea().allowsHitTesting(false).accessibilityHidden(true)
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    HStack {
                        Label("YUEJI / 月记", systemImage: "moon.fill")
                            .font(.caption.weight(.semibold)).tracking(3).foregroundStyle(gold)
                        Spacer()
                        if mode != nil {
                            Button {
                                field = nil; cloud.changeEmail(); code = ""
                                withAnimation(motion ? .easeInOut(duration: 0.3) : nil) { mode = nil }
                            } label: { Image(systemName: "arrow.left").frame(width: 44, height: 44) }
                                .accessibilityLabel(tr("返回欢迎页", "Back to welcome", "Kembali ke alu-aluan"))
                                .disabled(cloud.busy)
                        }
                    }
                    ZStack {
                        MoonWelcomeArtwork(animated: motion && !enteringText && !cloud.busy).opacity(0.45)
                        YueJiCharacter(animated: motion && !enteringText && !cloud.busy, style: 0)
                            .frame(width: mode == nil ? 180 : 130, height: mode == nil ? 180 : 130)
                    }.frame(height: mode == nil ? 240 : 150)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 14) {
                        Text(title).font(.system(.largeTitle, design: .rounded, weight: .bold)).fixedSize(horizontal: false, vertical: true)
                        Text(subtitle).font(.subheadline).foregroundStyle(.white.opacity(0.78))
                            .fixedSize(horizontal: false, vertical: true).lineSpacing(4)
                    }
                    VStack(alignment: .leading, spacing: 18) {
                        if mode == nil { welcomeActions }
                        else {
                            Label(creating ? tr("创建你的账号", "Create your account", "Cipta akaun anda") : tr("登录月记", "Sign in to YueJi", "Log masuk ke YueJi"), systemImage: creating ? "person.crop.circle.badge.plus" : "lock.shield")
                                .font(.headline)
                            emailForm.transition(.opacity.combined(with: .offset(y: motion ? 10 : 0)))
                        }
                    }.padding(22).modifier(AccountGlassSurface())
                    if cloud.busy {
                        ProgressView(tr("正在连接…", "Connecting…", "Menyambung…")).tint(gold)
                    }
                    if !cloud.message.isEmpty && mode == nil {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(cloud.message).font(.footnote).textSelection(.enabled)
                            Button(tr("检查云端连接", "Check cloud connection", "Semak sambungan awan")) {
                                field = nil; Task { await cloud.checkConnection() }
                            }.font(.footnote.weight(.semibold)).disabled(cloud.busy || !cloud.configured)
                        }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 20))
                    }
                    if !cloud.configured { Text(CloudFailure.configuration.localizedDescription).font(.footnote) }
                    if cloud.link == nil {
                        Button(tr("先逛逛，使用本机账本", "Explore with a local ledger", "Teroka dengan lejar setempat")) {
                            field = nil; cloud.usingLocal = true
                        }.font(.subheadline).frame(maxWidth: .infinity, minHeight: 44).disabled(cloud.busy)
                        Text(tr("本机模式不会上传账本；登录并同步后才能跨设备恢复。", "Local mode stays on this device. Sign in and sync to restore on another device.", "Mod setempat kekal pada peranti ini. Log masuk dan segerakkan untuk pulih pada peranti lain."))
                            .font(.caption).foregroundStyle(.white.opacity(0.65)).multilineTextAlignment(.center)
                    }
                }.padding(24).frame(maxWidth: 520).frame(maxWidth: .infinity)
                    .opacity(appeared || !motion ? 1 : 0)
                    .offset(y: appeared || !motion ? 0 : 16)
            }.scrollDismissesKeyboard(.interactively)
        }
        .foregroundStyle(.white).tint(gold).preferredColorScheme(.dark)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            withAnimation(motion ? .spring(response: 0.65, dampingFraction: 0.86) : nil) { appeared = true }
            address = cloud.email
            if cloud.link != nil || cloud.codeSent || cloud.needsSignInAgain { mode = false }
        }
        .onChange(of: cloud.codeSent) { _, sent in if sent { field = .code } }
    }
    private var subtitle: String {
        if cloud.needsSignInAgain { return tr("登录已过期。本机账本和未同步的更改仍保留，请使用原账号登录后继续同步。", "Your session expired. Your local ledger and pending changes are safe. Sign in to the same account to resume syncing.", "Sesi tamat. Lejar setempat dan perubahan belum disegerakkan dikekalkan. Log masuk ke akaun asal untuk meneruskan.") }
        if cloud.codeSent { return tr("验证码已发送至", "We sent a code to", "Kod dihantar ke") + " " + cloud.email }
        if mode == nil { return tr("收好每一笔生活。登录并同步，让账本随你去下一站。", "Keep a little of every day. Sign in and sync to take your ledger with you.", "Simpan setiap detik harian. Log masuk dan segerakkan untuk membawa lejar bersama.") }
        return creating ? tr("使用邮箱和密码创建账号，验证邮箱后开始同步。", "Create an account with email and password, then verify your email to start syncing.", "Cipta akaun dengan e-mel dan kata laluan, kemudian sahkan e-mel untuk menyegerakkan.") : tr("使用原来的邮箱和密码，找回已同步的账本。", "Use your original email and password to recover your synced ledger.", "Gunakan e-mel asal dan kata laluan untuk memulihkan lejar.")
    }
    private var welcomeActions: some View {
        VStack(spacing: 14) {
            Button { Task { await cloud.signInWithGoogle() } } label: {
                actionLabel(tr("通过 Google 继续", "Continue with Google", "Teruskan dengan Google"), symbol: "person.crop.circle")
            }.buttonStyle(MoonWelcomeButton(primary: false)).disabled(!cloud.configured || cloud.busy)
            Group {
                Button { selectMode(true) } label: {
                    actionLabel(tr("创建账户", "Create account", "Cipta akaun"), symbol: "sparkles")
                }.buttonStyle(MoonWelcomeButton(primary: true)).disabled(!cloud.configured || cloud.busy)
            }
            Button { selectMode(false) } label: {
                actionLabel(tr("已有账户 · 登录", "Already a member? Sign in", "Sudah ada akaun? Log masuk"), symbol: "arrow.right")
            }.buttonStyle(MoonWelcomeButton(primary: false)).disabled(!cloud.configured || cloud.busy)
        }
    }
    private var emailForm: some View {
        CloudPasswordForm(creating: creating, focusChanged: { enteringText = $0 })
    }
    private func selectMode(_ create: Bool) {
        cloud.changeEmail(); code = ""
        withAnimation(motion ? .spring(response: 0.48, dampingFraction: 0.86) : nil) { mode = create }
    }
    private func actionLabel(_ text: String, symbol: String) -> some View {
        HStack { Text(text).multilineTextAlignment(.leading); Spacer(minLength: 12); Image(systemName: symbol) }
            .font(.body.weight(.semibold)).padding(20).frame(maxWidth: .infinity, minHeight: 58)
    }
}

private struct CloudRegistrationView: View {
    @ObservedObject private var cloud = CloudAccount.shared
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Form {
            CloudPasswordForm(creating: true)
            if !cloud.message.isEmpty { Text(cloud.message).font(.footnote) }
        }
        .navigationTitle(tr("创建账户", "Create account", "Cipta akaun"))
        .onChange(of: cloud.signedIn) { _, value in if value { dismiss() } }
    }
}

private struct CloudPasswordForm: View {
    let creating: Bool
    var changingPassword = false
    var focusChanged: (Bool) -> Void = { _ in }
    @ObservedObject private var cloud = CloudAccount.shared
    @State private var address = ""
    @State private var password = ""
    @State private var confirmation = ""
    @State private var code = ""
    @State private var recovering = false
    @FocusState private var focused: Field?
    private enum Field: Hashable { case email, password, confirmation, code }
    private var newPassword: Bool { creating || cloud.resettingPassword || changingPassword }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if cloud.codeSent && !changingPassword {
                Text(cloud.email).font(.footnote)
                TextField(tr("邮件验证码", "Email code", "Kod e-mel"), text: $code)
                    .textContentType(.oneTimeCode).keyboardType(.numberPad).focused($focused, equals: .code)
                    .padding(14).background(.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
                Button {
                    focused = nil
                    Task {
                        await cloud.verify(code: code)
                        if cloud.signedIn || cloud.resettingPassword { code = "" }
                    }
                } label: {
                    HStack {
                        Text(tr("验证邮箱", "Verify email", "Sahkan e-mel"))
                        Spacer()
                        if cloud.busy { ProgressView() } else { Image(systemName: "checkmark.shield") }
                    }.padding(.vertical, 12).frame(minHeight: 44)
                }.buttonStyle(.borderedProminent).disabled(code.isEmpty)
                if !cloud.message.isEmpty { Text(cloud.message).font(.footnote) }
                Button(tr("返回 / 重新发送", "Back / resend", "Kembali / hantar semula")) { cloud.changeEmail(); code = "" }
            } else {
                if !cloud.resettingPassword && !changingPassword {
                    TextField(tr("邮箱", "Email", "E-mel"), text: $address)
                        .textContentType(.username).keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().focused($focused, equals: .email)
                        .padding(14).background(.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
                }
                if !recovering || cloud.resettingPassword || changingPassword {
                    SecureField(newPassword ? tr("新密码（至少 8 个字符）", "New password (at least 8 characters)", "Kata laluan baharu (sekurang-kurangnya 8 aksara)") : tr("密码", "Password", "Kata laluan"), text: $password)
                        .textContentType(newPassword ? .newPassword : .password)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().focused($focused, equals: .password)
                        .padding(14).background(.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
                    if newPassword {
                        SecureField(tr("再次输入密码", "Confirm password", "Sahkan kata laluan"), text: $confirmation)
                            .textContentType(.newPassword).textInputAutocapitalization(.never).autocorrectionDisabled()
                            .focused($focused, equals: .confirmation)
                            .padding(14).background(.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
                        if !confirmation.isEmpty && password != confirmation {
                            Text(tr("两次密码不一致", "Passwords do not match", "Kata laluan tidak sepadan")).font(.footnote)
                        }
                    }
                }
                Button(action: submit) {
                    HStack {
                        Text(cloud.busy ? tr("正在处理…", "Please wait…", "Sila tunggu…") : buttonTitle).fontWeight(.semibold)
                        Spacer()
                        if cloud.busy { ProgressView() } else { Image(systemName: "arrow.right") }
                    }.padding(.vertical, 12).frame(minHeight: 44)
                }.buttonStyle(.borderedProminent).disabled(!valid)
                if !cloud.message.isEmpty {
                    Text(cloud.message).font(.footnote).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("account.form.feedback")
                }
                if !creating && !changingPassword && !cloud.resettingPassword {
                    Button(recovering ? tr("返回密码登录", "Back to password sign-in", "Kembali ke log masuk") : tr("忘记密码 / 首次设置密码", "Forgot password / Set first password", "Lupa kata laluan / Tetapkan kali pertama")) {
                        password = ""; confirmation = ""; recovering.toggle(); focused = .email
                    }.frame(minHeight: 44)
                    if !recovering {
                        Button(tr("通过 Google 继续", "Continue with Google", "Teruskan dengan Google")) {
                            focused = nil; clearSecrets(); Task { await cloud.signInWithGoogle() }
                        }.frame(minHeight: 44)
                    }
                }
                if cloud.resettingPassword {
                    Button(tr("取消", "Cancel", "Batal")) { cloud.changeEmail(); clearSecrets(); recovering = false }
                }
            }
        }
        .disabled(cloud.busy || !cloud.configured)
        .onAppear { address = cloud.email }
        .onChange(of: creating) { _, _ in clearSecrets(); recovering = false; cloud.changeEmail() }
        .onChange(of: cloud.codeSent) { _, value in if value { clearSecrets(); focused = .code } }
        .onChange(of: cloud.resettingPassword) { _, value in if value { clearSecrets(); focused = .password } }
        .onChange(of: focused) { _, value in focusChanged(value != nil) }
        .onDisappear { clearSecrets(); focusChanged(false) }
    }
    private var valid: Bool {
        if changingPassword || cloud.resettingPassword { return password.count >= 8 && password == confirmation }
        if !address.contains("@") { return false }
        if recovering { return true }
        return creating ? password.count >= 8 && password == confirmation : !password.isEmpty
    }
    private var buttonTitle: String {
        if changingPassword || cloud.resettingPassword { return tr("保存密码", "Save password", "Simpan kata laluan") }
        if recovering { return tr("发送重设验证码", "Send reset code", "Hantar kod tetapan semula") }
        return creating ? tr("创建账户", "Create account", "Cipta akaun") : tr("登录", "Sign in", "Log masuk")
    }
    private func submit() {
        guard valid, !cloud.busy else { return }
        focused = nil
        Task {
            if changingPassword || cloud.resettingPassword { await cloud.savePassword(password, confirmation: confirmation) }
            else if recovering { await cloud.requestPasswordReset(address: address) }
            else { await cloud.authenticate(address: address, password: password, confirmation: confirmation, creating: creating) }
            if cloud.signedIn || cloud.codeSent { clearSecrets() }
        }
    }
    private func clearSecrets() { password = ""; confirmation = ""; code = "" }
}

private struct AccountGlassSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    func body(content: Content) -> some View {
        content
            .background {
                let shape = RoundedRectangle(cornerRadius: 30, style: .continuous)
                if reduceTransparency { shape.fill(Color(red: 0.16, green: 0.21, blue: 0.31)) }
                else { shape.fill(.ultraThinMaterial) }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [.white.opacity(0.38), .white.opacity(0.06), .white.opacity(0.15)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .shadow(color: .black.opacity(0.18), radius: 24, y: 12)
    }
}

private struct MoonWelcomeButton: ButtonStyle {
    let primary: Bool
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(primary ? Color(red: 0.12, green: 0.16, blue: 0.24) : .white)
            .background(primary ? Color(red: 0.96, green: 0.79, blue: 0.49) : .white.opacity(0.08), in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(primary ? 0 : 0.22)))
            .opacity(enabled ? (configuration.isPressed ? 0.8 : 1) : 0.45)
            .scaleEffect(configuration.isPressed && !reduceMotion && ElegantMotion.enabled ? 0.98 : 1)
            .animation(reduceMotion || !ElegantMotion.enabled ? nil : .spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

private struct MoonWelcomeArtwork: View {
    let animated: Bool
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !animated)) { context in
            let time = animated ? context.date.timeIntervalSinceReferenceDate : 0
            let drift = sin(time * 0.65)
            ZStack {
                Circle().fill(Color.orange.opacity(0.10)).frame(width: 190, height: 190).blur(radius: 30)
                Circle().strokeBorder(.white.opacity(0.13), lineWidth: 1).frame(width: 230, height: 230)
                    .scaleEffect(y: 0.54).rotationEffect(.degrees(-24))
                Image(systemName: "moon.fill")
                    .font(.system(size: 104, weight: .ultraLight))
                    .foregroundStyle(LinearGradient(colors: [Color(red: 1, green: 0.9, blue: 0.66), Color(red: 0.80, green: 0.57, blue: 0.30)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .rotationEffect(.degrees(-18 + drift * 3)).offset(y: drift * 6)
                    .shadow(color: .orange.opacity(0.15), radius: 18, y: 8)
                ForEach(0..<7) { index in
                    let angle = Double(index) * 2.399
                    Image(systemName: index.isMultiple(of: 3) ? "sparkle" : "circle.fill")
                        .font(.system(size: index.isMultiple(of: 3) ? 12 : 3))
                        .foregroundStyle(Color(red: 0.96, green: 0.79, blue: 0.49))
                        .opacity(0.55 + 0.35 * sin(time * 0.8 + Double(index)))
                        .offset(x: cos(angle) * 113, y: sin(angle) * 66 + drift * 3)
                }
                Image(systemName: "book.closed.fill").font(.system(size: 20))
                    .foregroundStyle(Color(red: 0.96, green: 0.79, blue: 0.49))
                    .padding(14).background(Color(red: 0.19, green: 0.26, blue: 0.36), in: RoundedRectangle(cornerRadius: 18))
                    .rotationEffect(.degrees(9)).offset(x: 76, y: 42 - drift * 5)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// Packed avatar choices retain compatibility with earlier profile values.
private struct AvatarLook {
    let rawValue: Int
    private var safe: Int { min(max(rawValue, 0), 11519) }
    var shirt: Int { safe % 3 }
    var skin: Int { (safe / 3) % 5 }
    var hair: Int { (safe / 15) % 4 }
    var hairColor: Int { (safe / 60) % 4 }
    var glasses: Int { (safe / 240) % 3 }
    var face: Int { (safe / 720) % 2 }
    var beard: Int { (safe / 1440) % 2 }
    var expression: Int { (safe / 2880) % 4 }
    func replacing(divisor: Int, count: Int, with value: Int) -> Int {
        safe + (min(max(value, 0), count - 1) - (safe / divisor) % count) * divisor
    }
}

private struct YueJiCharacter: View {
    var animated = false
    var style = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var phase
    var body: some View {
        AvatarSceneView(style: style, animated: animated && !reduceMotion && phase == .active)
            .background(Color.indigo.opacity(0.12), in: Circle())
            .clipShape(Circle()).allowsHitTesting(false).accessibilityHidden(true)
    }
}

/// Original, locally generated geometry. No camera, downloaded models or private avatar APIs.
private struct AvatarSceneView: UIViewRepresentable {
    let style: Int
    let animated: Bool
    final class Coordinator {
        var style = -1
        var moving = false
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        view.backgroundColor = .clear
        view.isOpaque = false
        view.antialiasingMode = .multisampling2X
        view.preferredFramesPerSecond = 24
        view.rendersContinuously = false
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        return view
    }
    func updateUIView(_ view: SCNView, context: Context) {
        if context.coordinator.style != style {
            view.scene = Self.makeScene(AvatarLook(rawValue: style))
            context.coordinator.style = style
            context.coordinator.moving = false
        }
        if context.coordinator.moving != animated {
            let head = view.scene?.rootNode.childNode(withName: "head", recursively: true)
            head?.removeAllActions()
            head?.eulerAngles = SCNVector3(0, -0.10, 0)
            if animated {
                let turn = SCNAction.sequence([
                    .rotateTo(x: 0.03, y: 0.12, z: 0.025, duration: 2.5),
                    .rotateTo(x: 0, y: -0.10, z: 0, duration: 2.5)
                ])
                head?.runAction(.sequence([turn, .wait(duration: 3)]))
            }
            for name in ["leftEye", "rightEye"] {
                guard let eye = head?.childNode(withName: name, recursively: true) else { continue }
                eye.removeAllActions(); eye.scale = SCNVector3(1, 1, 1)
                if animated {
                    let close = SCNAction.customAction(duration: 0.10) { node, elapsed in
                        node.scale.y = 1 - Float(elapsed / 0.10) * 0.9
                    }
                    let open = SCNAction.customAction(duration: 0.12) { node, elapsed in
                        node.scale.y = 0.1 + Float(elapsed / 0.12) * 0.9
                    }
                    eye.runAction(.repeatForever(.sequence([.wait(duration: 4.5), close, open])))
                }
            }
            context.coordinator.moving = animated
        }
        view.isPlaying = animated
        view.setNeedsDisplay()
    }
    static func dismantleUIView(_ view: SCNView, coordinator: Coordinator) {
        view.isPlaying = false
        view.scene = nil
    }
    private static func material(_ color: UIColor, roughness: CGFloat = 0.55) -> SCNMaterial {
        let m = SCNMaterial()
        m.diffuse.contents = color
        m.lightingModel = .physicallyBased
        m.roughness.contents = roughness
        m.metalness.contents = 0.0
        return m
    }
    private static func makeScene(_ look: AvatarLook) -> SCNScene {
        let scene = SCNScene()
        let camera = SCNNode(); camera.camera = SCNCamera()
        camera.camera?.usesOrthographicProjection = true
        camera.camera?.orthographicScale = 1.30
        camera.position = SCNVector3(0, 0.05, 5)
        scene.rootNode.addChildNode(camera)
        for (position, intensity) in [(SCNVector3(-3, 4, 5), CGFloat(950)), (SCNVector3(3, 1, 3), CGFloat(450))] {
            let light = SCNNode(); light.light = SCNLight()
            light.light?.type = .omni; light.light?.intensity = intensity
            light.position = position; scene.rootNode.addChildNode(light)
        }
        let fill = SCNNode(); fill.light = SCNLight()
        fill.light?.type = .ambient; fill.light?.intensity = 250
        scene.rootNode.addChildNode(fill)
        let skinColors: [UIColor] = [UIColor(red: 1, green: 0.81, blue: 0.66, alpha: 1), UIColor(red: 0.91, green: 0.65, blue: 0.44, alpha: 1), UIColor(red: 0.74, green: 0.48, blue: 0.31, alpha: 1), UIColor(red: 0.55, green: 0.32, blue: 0.20, alpha: 1), UIColor(red: 0.34, green: 0.19, blue: 0.12, alpha: 1)]
        let skin = material(skinColors[look.skin], roughness: 0.65)
        let hair = material([UIColor(white: 0.045, alpha: 1), UIColor.brown, UIColor(red: 0.68, green: 0.43, blue: 0.16, alpha: 1), UIColor.lightGray][look.hairColor], roughness: 0.38)
        let shirt = material([UIColor.systemIndigo, .systemTeal, .systemOrange][look.shirt])
        let head = SCNNode(); head.name = "head"
        head.eulerAngles.y = -0.10
        scene.rootNode.addChildNode(head)
        @discardableResult func ball(_ parent: SCNNode, _ position: SCNVector3, _ scale: SCNVector3, _ m: SCNMaterial) -> SCNNode {
            let geometry = SCNSphere(radius: 1); geometry.segmentCount = 32
            geometry.materials = [m]
            let n = SCNNode(geometry: geometry); n.position = position; n.scale = scale
            parent.addChildNode(n); return n
        }
        ball(scene.rootNode, SCNVector3(0, -1.03, -0.12), SCNVector3(0.82, 0.48, 0.40), shirt)
        ball(head, SCNVector3(0, -0.72, 0), SCNVector3(0.21, 0.35, 0.23), skin)
        ball(head, SCNVector3(0, 0, 0), SCNVector3(look.face == 0 ? 0.64 : 0.59, 0.83, 0.55), skin)
        for x in [Float(-0.64), Float(0.64)] {
            ball(head, SCNVector3(x, -0.02, 0), SCNVector3(0.12, 0.21, 0.12), skin)
        }
        if look.hair != 3 {
            ball(head, SCNVector3(0, 0.48, -0.12), SCNVector3(0.67, 0.48, 0.54), hair)
            for i in 0..<7 {
                let x = Float(i - 3) * 0.17
                ball(head, SCNVector3(x, 0.57 - abs(x) * 0.12, 0.35), SCNVector3(0.14, look.hair == 2 ? 0.17 : 0.28, 0.19), hair)
            }
            if look.hair == 1 {
                for x in [Float(-0.56), Float(0.56)] { ball(head, SCNVector3(x, -0.10, -0.16), SCNVector3(0.19, 0.75, 0.35), hair) }
            }
        }
        for (i, x) in [Float(-0.27), Float(0.27)].enumerated() {
            let eye = SCNNode(); eye.position = SCNVector3(x, 0.12, 0.48)
            eye.name = i == 0 ? "leftEye" : "rightEye"
            head.addChildNode(eye)
            let wink = look.expression == 2 && i == 1
            ball(eye, SCNVector3Zero, SCNVector3(0.18, wink ? 0.025 : 0.14, 0.085), material(wink ? .brown : .white))
            if !wink {
                ball(eye, SCNVector3(0, 0, 0.078), SCNVector3(0.078, 0.095, 0.025), material(.brown))
                ball(eye, SCNVector3(0, 0, 0.10), SCNVector3(0.043, 0.065, 0.014), material(.black))
                ball(eye, SCNVector3(-0.025, 0.035, 0.115), SCNVector3(0.019, 0.024, 0.01), material(.white))
            }
            let brow = ball(head, SCNVector3(x, look.expression == 3 ? 0.36 : 0.31, 0.48), SCNVector3(0.18, 0.035, 0.04), hair)
            brow.eulerAngles.z = i == 0 ? 0.08 : -0.08
            if look.glasses != 0 {
                let path = UIBezierPath(roundedRect: CGRect(x: -0.22, y: -0.18, width: 0.44, height: 0.36), cornerRadius: look.glasses == 1 ? 0.17 : 0.07)
                let inner = UIBezierPath(roundedRect: CGRect(x: -0.18, y: -0.14, width: 0.36, height: 0.28), cornerRadius: look.glasses == 1 ? 0.13 : 0.045)
                path.append(inner.reversing())
                let frame = SCNShape(path: path, extrusionDepth: 0.045)
                frame.firstMaterial = material(.darkGray, roughness: 0.3)
                let n = SCNNode(geometry: frame); n.position = SCNVector3(x, 0.12, 0.64); head.addChildNode(n)
            }
        }
        if look.glasses != 0 { ball(head, SCNVector3(0, 0.16, 0.66), SCNVector3(0.09, 0.025, 0.025), material(.darkGray)) }
        ball(head, SCNVector3(0, -0.12, 0.55), SCNVector3(0.105, 0.13, 0.14), skin)
        let open = look.expression == 1 || look.expression == 3
        let lips = material(UIColor(red: 0.40, green: 0.10, blue: 0.12, alpha: 1))
        if open {
            ball(head, SCNVector3(0, -0.38, 0.48), SCNVector3(look.expression == 3 ? 0.09 : 0.22, 0.12, 0.045), lips)
        } else {
            let smile = UIBezierPath()
            smile.move(to: CGPoint(x: -0.21, y: 0.025))
            smile.addQuadCurve(to: CGPoint(x: 0.21, y: 0.025), controlPoint: CGPoint(x: 0, y: -0.08))
            smile.addQuadCurve(to: CGPoint(x: -0.21, y: 0.025), controlPoint: CGPoint(x: 0, y: -0.17))
            smile.close()
            let geometry = SCNShape(path: smile, extrusionDepth: 0.025)
            geometry.firstMaterial = lips
            let mouth = SCNNode(geometry: geometry); mouth.position = SCNVector3(0, -0.34, 0.53)
            head.addChildNode(mouth)
        }
        if look.expression == 1 { ball(head, SCNVector3(0, -0.34, 0.52), SCNVector3(0.18, 0.045, 0.02), material(.white)) }
        if look.beard == 1 { ball(head, SCNVector3(0, -0.62, 0.31), SCNVector3(0.28, 0.10, 0.12), hair) }
        return scene
    }
}


/// Shared profile keys keep the Settings summary and profile editor in sync.
struct AccountSettingsCard: View {
    @ObservedObject private var cloud = CloudAccount.shared
    var body: some View {
        NavigationLink { CloudAccountView() } label: {
            AccountSettingsSummary(accountID: cloud.link?.userID.uuidString ?? cloud.email,
                                   email: cloud.email, signedIn: cloud.signedIn,
                                   status: cloud.status, attention: cloud.lastSyncFailed || cloud.conflict != nil)
                .id(cloud.link?.userID.uuidString ?? cloud.email)
        }.accessibilityIdentifier("settings.account")
    }
}

private struct AccountSettingsSummary: View {
    let email: String
    let signedIn: Bool
    let status: String
    let attention: Bool
    @AppStorage private var nickname: String
    @AppStorage private var avatarStyle: Int
    init(accountID: String, email: String, signedIn: Bool, status: String, attention: Bool) {
        self.email = email; self.signedIn = signedIn; self.status = status; self.attention = attention
        _nickname = AppStorage(wrappedValue: "", "accountProfile.name." + accountID)
        _avatarStyle = AppStorage(wrappedValue: 0, "accountProfile.avatar." + accountID)
    }
    var body: some View {
        HStack(spacing: 16) {
            YueJiCharacter(style: signedIn ? avatarStyle : 0)
                .frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 6) {
                Text(signedIn ? (nickname.isEmpty ? tr("月记用户", "YueJi member", "Pengguna YueJi") : nickname)
                     : tr("登录月记", "Sign in to YueJi", "Log masuk ke YueJi"))
                    .font(.title3.weight(.semibold)).foregroundStyle(.primary)
                Text(signedIn ? email : tr("登录并同步，让账本随你同行", "Sign in and take your ledger with you", "Log masuk dan bawa lejar bersama"))
                    .font(.subheadline).foregroundStyle(.secondary)
                    .lineLimit(2)
                Label(status, systemImage: attention ? "exclamationmark.icloud" : signedIn ? "icloud" : "person.crop.circle")
                    .font(.caption).foregroundStyle(attention ? Color.orange : Color.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(.vertical, 10)
    }
}

private struct AccountProfileHeader: View {
    let email: String
    @AppStorage private var nickname: String
    @AppStorage private var avatarStyle: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var phase
    @AppStorage("playfulAnimations") private var playful = true
    @State private var editing = false
    @State private var draft = ""
    @State private var draftStyle = 0
    @State private var avatarTab = 0
    init(accountID: String, email: String) {
        self.email = email
        _nickname = AppStorage(wrappedValue: "", "accountProfile.name." + accountID)
        _avatarStyle = AppStorage(wrappedValue: 0, "accountProfile.avatar." + accountID)
    }
    var body: some View {
        VStack(spacing: 10) {
            YueJiCharacter(animated: playful && !reduceMotion && phase == .active, style: avatarStyle)
                .frame(width: 100, height: 100)
            Text(nickname.isEmpty ? tr("月记用户", "YueJi member", "Pengguna YueJi") : nickname)
                .font(.title2.weight(.semibold)).multilineTextAlignment(.center)
            Text(email).font(.subheadline).foregroundStyle(.secondary).textSelection(.enabled)
            Button(tr("编辑头像与昵称", "Edit avatar and name", "Edit avatar dan nama")) {
                draft = nickname; draftStyle = avatarStyle; editing = true
            }.font(.subheadline).frame(minHeight: 44)
        }.frame(maxWidth: .infinity).padding(.vertical, 12)
        .sheet(isPresented: $editing) {
            NavigationStack {
                VStack(spacing: 0) {
                    YueJiCharacter(animated: playful && !reduceMotion && phase == .active, style: draftStyle)
                        .frame(width: 180, height: 180).padding(12)
                        .accessibilityHidden(true)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            HStack {
                                Button(tr("男生预设", "Boy preset", "Pratetap lelaki")) { draftStyle = 0 }
                                Spacer()
                                Button(tr("女生预设", "Girl preset", "Pratetap perempuan")) { draftStyle = 735 }
                            }.buttonStyle(.bordered).frame(minHeight: 44)
                            Text(tr("预设只是起点，每一项都可以自由搭配。", "Start with a preset, then make every detail yours.", "Mulakan dengan pratetap dan sesuaikan setiap ciri."))
                                .font(.caption).foregroundStyle(.secondary)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    ForEach(0..<5) { index in
                                        Button {
                                            withAnimation(reduceMotion || !playful ? nil : .easeInOut(duration: 0.2)) { avatarTab = index }
                                        } label: {
                                            Text([tr("脸部", "Face", "Muka"), tr("头发", "Hair", "Rambut"), tr("配饰", "Accessories", "Aksesori"), tr("服装", "Clothing", "Pakaian"), tr("表情", "Expression", "Ekspresi")][index])
                                                .font(.subheadline.weight(.semibold)).padding(.horizontal, 16).frame(minHeight: 44)
                                                .background(avatarTab == index ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.08), in: Capsule())
                                        }.buttonStyle(.plain).accessibilityAddTraits(avatarTab == index ? .isSelected : [])
                                    }
                                }
                            }
                            Group {
                                if avatarTab == 0 {
                                    avatarPicker(tr("肤色", "Skin tone", "Tona kulit"), options: [tr("浅色", "Light", "Cerah"), tr("暖浅色", "Warm light", "Cerah hangat"), tr("中等", "Medium", "Sederhana"), tr("棕色", "Brown", "Coklat"), tr("深色", "Deep", "Gelap")], divisor: 3)
                                    avatarPicker(tr("脸型", "Face shape", "Bentuk muka"), options: [tr("圆润", "Round", "Bulat"), tr("椭圆", "Oval", "Bujur")], divisor: 720)
                                } else if avatarTab == 1 {
                                    avatarPicker(tr("发型", "Hairstyle", "Gaya rambut"), options: [tr("短发", "Short", "Pendek"), tr("长发", "Long", "Panjang"), tr("卷发", "Curly", "Keriting"), tr("光头", "Shaved", "Botak")], divisor: 15)
                                    avatarPicker(tr("发色", "Hair colour", "Warna rambut"), options: [tr("黑色", "Black", "Hitam"), tr("棕色", "Brown", "Coklat"), tr("金色", "Blond", "Perang"), tr("银色", "Silver", "Perak")], divisor: 60)
                                    avatarPicker(tr("胡须", "Facial hair", "Janggut"), options: [tr("无", "None", "Tiada"), tr("短胡须", "Short beard", "Janggut pendek")], divisor: 1440)
                                } else if avatarTab == 2 {
                                    avatarPicker(tr("眼镜", "Glasses", "Cermin mata"), options: [tr("无", "None", "Tiada"), tr("圆框", "Round", "Bulat"), tr("方框", "Square", "Segi empat")], divisor: 240)
                                } else if avatarTab == 3 {
                                    avatarPicker(tr("服装配色", "Clothing", "Pakaian"), options: [tr("靛蓝", "Indigo", "Indigo"), tr("青绿", "Teal", "Biru kehijauan"), tr("暖橙", "Orange", "Jingga")], divisor: 1)
                                } else {
                                    avatarPicker(tr("表情", "Expression", "Ekspresi"), options: [tr("微笑", "Smile", "Senyum"), tr("大笑", "Laugh", "Ketawa"), tr("眨眼", "Wink", "Kenyit"), tr("惊讶", "Surprised", "Terkejut")], divisor: 2880)
                                }
                            }
                            Divider()
                            TextField(tr("昵称", "Display name", "Nama paparan"), text: $draft)
                                .textContentType(.nickname).textFieldStyle(.roundedBorder)
                                .onChange(of: draft) { _, value in if value.count > 40 { draft = String(value.prefix(40)) } }
                            Text(tr("头像和昵称保存在这台设备，不会更改登录邮箱。", "Your avatar and name are saved on this device. Your sign-in email stays the same.", "Avatar dan nama disimpan pada peranti ini. E-mel log masuk tidak berubah."))
                                .font(.footnote).foregroundStyle(.secondary)
                        }.padding(20).frame(maxWidth: 560).frame(maxWidth: .infinity)
                    }.scrollDismissesKeyboard(.interactively)
                }
                .navigationTitle(tr("个人资料", "Profile", "Profil"))
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button(tr("取消", "Cancel", "Batal")) { editing = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(tr("保存", "Save", "Simpan")) {
                            nickname = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                            avatarStyle = draftStyle; editing = false
                        }
                    }
                }
            }
        }
    }
    private func avatarPicker(_ title: String, options: [String], divisor: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 12)], spacing: 12) {
                ForEach(options.indices, id: \.self) { index in
                    let selected = (max(0, draftStyle) / divisor) % options.count == index
                    let candidate = AvatarLook(rawValue: draftStyle).replacing(divisor: divisor, count: options.count, with: index)
                    Button { draftStyle = candidate } label: {
                        VStack(spacing: 8) {
                            YueJiCharacter(style: candidate).frame(width: 58, height: 58)
                            Text(options[index]).font(.caption.weight(.medium)).fixedSize(horizontal: false, vertical: true)
                            Image(systemName: selected ? "checkmark.circle.fill" : "circle").foregroundStyle(selected ? Color.accentColor : Color.secondary)
                        }.frame(maxWidth: .infinity).padding(10)
                            .background(selected ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 18))
                            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2))
                    }.buttonStyle(.plain)
                        .accessibilityLabel(title + ": " + options[index])
                        .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
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
                Section {
                    CloudPasswordForm(creating: false)
                    NavigationLink { CloudRegistrationView() } label: {
                        Label(tr("创建账户", "Create account", "Cipta akaun"), systemImage: "person.badge.plus")
                    }.disabled(cloud.busy || cloud.codeSent || cloud.resettingPassword)
                }
            } else {
                Section(tr("账号", "Account", "Akaun")) {
                    AccountProfileHeader(accountID: cloud.link?.userID.uuidString ?? cloud.email, email: cloud.email)
                        .id(cloud.link?.userID.uuidString ?? cloud.email)
                    Label(cloud.status, systemImage: cloud.dirty ? "icloud.and.arrow.up" : "icloud")
                    if let date = cloud.link?.lastSync {
                        LabeledContent(tr("上次同步", "Last sync", "Segerak terakhir"), value: dateLabel(date, time: true))
                    }
                    Button(tr("立即同步", "Sync now", "Segerakkan sekarang")) { Task { await cloud.sync() } }.disabled(cloud.busy)
                    Button(tr("退出登录", "Sign out", "Log keluar"), role: .destructive) { signingOut = true }.disabled(cloud.busy)
                }
                Section(tr("设置 / 修改密码", "Set / change password", "Tetapkan / tukar kata laluan")) {
                    CloudPasswordForm(creating: false, changingPassword: true)
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
            Text(tr("此账号的账本和未同步记录会单独保留在本机。可以登录其他账号，切回此账号后继续同步。切换账号后请重新选择外部自动备份文件夹。", "This account's ledger and unsynced entries stay separately on this device. You can sign in to another account and return later. Choose an external auto-backup folder again after switching accounts.", "Lejar dan rekod belum disegerakkan disimpan berasingan. Anda boleh bertukar akaun dan kembali kemudian. Pilih semula folder sandaran luaran selepas bertukar akaun."))
        }
    }
    private func choose(_ choice: CloudChoice, _ conflict: CloudConflict) {
        self.choice = choice; confirmation = conflict; confirming = true
    }
}
