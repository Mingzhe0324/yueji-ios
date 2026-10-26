import SwiftUI
import UIKit
import AuthenticationServices
import CryptoKit
import Security

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
                let config = await api.configuration
                let existing = try await synchronizer.localLink()
                if let existing, !existing.accepts(userID: value.user.id, server: config.server) { throw CloudFailure.accountMismatch }
                recoverySession = value; resettingPassword = true; codeSent = false; message = ""
            } else { try await accept(value, api: api) }
        } catch { await reloadLink(); report(error) }
    }
    private func accept(_ value: CloudSession, api: SupabaseCloudService) async throws {
        let config = await api.configuration
        let existing = try await synchronizer.localLink()
        if let existing, !existing.accepts(userID: value.user.id, server: config.server) { throw CloudFailure.accountMismatch }
        try CloudCredentials.save(CloudCredential(server: config.server, session: value))
        await api.use(value)
        session = value; signedIn = true; codeSent = false; email = value.user.email ?? email
        recoverySession = nil; resettingPassword = false
        initializationFailed = false; usingLocal = false
        try await synchronize(api, refresh: false)
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
    @ObservedObject private var cloud = CloudAccount.shared
    @EnvironmentObject private var model: LedgerModel
    @Environment(\.scenePhase) private var phase
    var body: some View {
        Group {
            if !cloud.loaded { ProgressView() }
            else if cloud.canEnter { MainView() }
            else { NavigationStack {
                if cloud.signedIn { CloudAccountView(isEntry: true) }
                else { CloudWelcomeView() }
            } }
        }
        .task { await cloud.initialize() }
        .onChange(of: cloud.cloudRestored) { _, _ in Task { await model.refresh(postRecurring: false) } }
        .onChange(of: phase) { _, value in
            if value == .active { Task { await cloud.sync() } }
            if value == .background { cloud.syncInBackground() }
        }
    }
}

/// First-run moonrise. The signed-in account/conflict screen remains available above.
private struct CloudWelcomeView: View {
    @ObservedObject private var cloud = CloudAccount.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var phase
    @AppStorage("playfulAnimations") private var playful = true
    @State private var mode: Bool? // true: create account; false: returning account
    @State private var address = ""
    @State private var code = ""
    @FocusState private var field: Field?
    private enum Field: Hashable { case email, code }
    private let gold = Color(red: 0.96, green: 0.79, blue: 0.49)
    private var motion: Bool { !reduceMotion && playful && phase == .active }
    private var creating: Bool { mode == true }
    private var title: String {
        if cloud.codeSent { return tr("一封信，\n开启你的月记。", "A little code.\nA new chapter.", "Satu kod.\nBab baharu.") }
        if mode == nil { return tr("把日子，\n记成自己的光。", "Little moments.\nYour own light.", "Detik kecil.\nCahaya milikmu.") }
        return creating ? tr("你好，\n新的开始。", "Hello,\nnew beginnings.", "Helo,\npermulaan baharu.") : tr("欢迎回来，\n继续你的故事。", "Welcome back.\nYour story continues.", "Selamat kembali.\nKisahmu diteruskan.")
    }
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.06, green: 0.10, blue: 0.20), Color(red: 0.13, green: 0.20, blue: 0.32)], startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
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
                        MoonWelcomeArtwork(animated: motion).opacity(0.45)
                        YueJiCharacter(animated: motion, style: 0)
                            .frame(width: mode == nil ? 180 : 130, height: mode == nil ? 180 : 130)
                    }.frame(height: mode == nil ? 240 : 150)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 14) {
                        Text(title).font(.system(.largeTitle, design: .serif, weight: .medium)).fixedSize(horizontal: false, vertical: true)
                        Text(subtitle).font(.subheadline).foregroundStyle(.white.opacity(0.78))
                            .fixedSize(horizontal: false, vertical: true).lineSpacing(4)
                    }
                    if mode == nil { welcomeActions }
                    else { emailForm.transition(.opacity) }
                    if cloud.busy {
                        ProgressView(tr("正在连接…", "Connecting…", "Menyambung…")).tint(gold)
                    }
                    if !cloud.message.isEmpty {
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
                }.padding(28).frame(maxWidth: 520).frame(maxWidth: .infinity)
            }.scrollDismissesKeyboard(.interactively)
        }
        .foregroundStyle(.white).tint(gold).preferredColorScheme(.dark)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            address = cloud.email
            if cloud.link != nil || cloud.codeSent { mode = false }
        }
        .onChange(of: cloud.codeSent) { _, sent in if sent { field = .code } }
    }
    private var subtitle: String {
        if cloud.codeSent { return tr("验证码已发送至", "We sent a code to", "Kod dihantar ke") + " " + cloud.email }
        if mode == nil { return tr("收好每一笔生活。登录并同步，让账本随你去下一站。", "Keep a little of every day. Sign in and sync to take your ledger with you.", "Simpan setiap detik harian. Log masuk dan segerakkan untuk membawa lejar bersama.") }
        return creating ? tr("使用邮箱和密码创建账号，验证邮箱后开始同步。", "Create an account with email and password, then verify your email to start syncing.", "Cipta akaun dengan e-mel dan kata laluan, kemudian sahkan e-mel untuk menyegerakkan.") : tr("使用原来的邮箱和密码，找回已同步的账本。", "Use your original email and password to recover your synced ledger.", "Gunakan e-mel asal dan kata laluan untuk memulihkan lejar.")
    }
    private var welcomeActions: some View {
        VStack(spacing: 14) {
            Button { Task { await cloud.signInWithGoogle() } } label: {
                actionLabel(tr("通过 Google 继续", "Continue with Google", "Teruskan dengan Google"), symbol: "person.crop.circle")
            }.buttonStyle(MoonWelcomeButton(primary: false)).disabled(!cloud.configured || cloud.busy)
            if cloud.link == nil {
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
        CloudPasswordForm(creating: creating)
    }
    private func selectMode(_ create: Bool) {
        cloud.changeEmail(); code = ""
        withAnimation(motion ? .easeInOut(duration: 0.3) : nil) { mode = create }
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
                Button(tr("验证邮箱", "Verify email", "Sahkan e-mel")) {
                    focused = nil; Task { await cloud.verify(code: code); code = "" }
                }.buttonStyle(.borderedProminent).disabled(code.isEmpty)
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
                        Text(buttonTitle).fontWeight(.semibold)
                        Spacer()
                        if cloud.busy { ProgressView() } else { Image(systemName: "arrow.right") }
                    }.padding(.vertical, 8)
                }.buttonStyle(.borderedProminent).disabled(!valid)
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
        .onDisappear { clearSecrets() }
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
            clearSecrets()
        }
    }
    private func clearSecrets() { password = ""; confirmation = ""; code = "" }
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

/// Original vector character; no access to the user's Apple ID or personal Memoji.
private struct YueJiCharacter: View {
    var animated = false
    var style = 0
    private var shirt: Color { [Color.indigo, .teal, .orange][min(max(style, 0), 2)] }
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24, paused: !animated)) { context in
            let time = animated ? context.date.timeIntervalSinceReferenceDate : 0
            let blink = animated && time.truncatingRemainder(dividingBy: 4.8) < 0.16
            GeometryReader { geometry in
                let size = min(geometry.size.width, geometry.size.height)
                ZStack {
                    Circle().fill(LinearGradient(colors: [shirt.opacity(0.18), shirt.opacity(0.55)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    Ellipse().fill(shirt.gradient).frame(width: size * 0.76, height: size * 0.52).offset(y: size * 0.40)
                    RoundedRectangle(cornerRadius: size * 0.08).fill(Color(red: 0.78, green: 0.49, blue: 0.32))
                        .frame(width: size * 0.19, height: size * 0.22).offset(y: size * 0.21)
                    Ellipse().fill(Color(red: 0.17, green: 0.11, blue: 0.10).gradient)
                        .frame(width: size * 0.59, height: size * 0.65).offset(y: -size * 0.09)
                    Ellipse().fill(LinearGradient(colors: [Color(red: 1, green: 0.79, blue: 0.59), Color(red: 0.84, green: 0.55, blue: 0.37)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: size * 0.51, height: size * 0.56).offset(y: -size * 0.015)
                    Ellipse().fill(Color(red: 0.22, green: 0.14, blue: 0.11).gradient)
                        .frame(width: size * 0.49, height: size * 0.20).rotationEffect(.degrees(-14)).offset(x: -size * 0.035, y: -size * 0.24)
                    HStack(spacing: size * 0.15) {
                        ForEach(0..<2) { _ in
                            Capsule().fill(Color(red: 0.16, green: 0.10, blue: 0.10))
                                .frame(width: size * 0.04, height: size * (blink ? 0.012 : 0.065))
                        }
                    }.offset(y: -size * 0.015)
                    Capsule().fill(Color(red: 0.69, green: 0.36, blue: 0.24).opacity(0.5))
                        .frame(width: size * 0.045, height: size * 0.065).offset(y: size * 0.055)
                    Ellipse().trim(from: 0, to: 0.5).stroke(Color(red: 0.42, green: 0.19, blue: 0.15), style: StrokeStyle(lineWidth: size * 0.018, lineCap: .round))
                        .frame(width: size * 0.16, height: size * 0.09).offset(y: size * 0.10)
                    Image(systemName: "moon.fill").font(.system(size: size * 0.11)).foregroundStyle(.yellow).offset(y: size * 0.36)
                    Image(systemName: "hand.wave.fill").font(.system(size: size * 0.27)).foregroundStyle(Color(red: 1, green: 0.76, blue: 0.53))
                        .rotationEffect(.degrees(animated ? sin(time * 3) * 13 : -8), anchor: .bottom)
                        .offset(x: size * 0.33, y: size * 0.18)
                }.frame(width: size, height: size).clipShape(Circle())
                    .offset(y: animated ? sin(time * 0.8) * 2 : 0)
            }
        }.accessibilityHidden(true)
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
                Form {
                    Section {
                        HStack { Spacer(); YueJiCharacter(style: draftStyle).frame(width: 120, height: 120); Spacer() }
                        Picker(tr("头像配色", "Avatar colour", "Warna avatar"), selection: $draftStyle) {
                            Text(tr("靛蓝", "Indigo", "Indigo")).tag(0)
                            Text(tr("青绿", "Teal", "Biru kehijauan")).tag(1)
                            Text(tr("暖橙", "Orange", "Jingga")).tag(2)
                        }
                        TextField(tr("昵称", "Display name", "Nama paparan"), text: $draft)
                            .textContentType(.nickname)
                            .onChange(of: draft) { _, value in if value.count > 40 { draft = String(value.prefix(40)) } }
                    } footer: {
                        Text(tr("头像和昵称保存在这台设备，不会更改登录邮箱。", "Your avatar and name are saved on this device. Your sign-in email stays the same.", "Avatar dan nama disimpan pada peranti ini. E-mel log masuk tidak berubah."))
                    }
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
                    }.disabled(cloud.busy || cloud.codeSent || cloud.resettingPassword || cloud.link != nil)
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
            Text(tr("未同步的记录只保留在本机。退出后需要用同一账号重新登录。", "Unsynced records remain only on this device. You will need to sign in to the same account again.", "Rekod belum disegerakkan hanya kekal pada peranti. Anda perlu log masuk semula ke akaun sama."))
        }
    }
    private func choose(_ choice: CloudChoice, _ conflict: CloudConflict) {
        self.choice = choice; confirmation = conflict; confirming = true
    }
}
