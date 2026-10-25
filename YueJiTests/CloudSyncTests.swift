import XCTest
import Foundation
@testable import YueJi

private actor MemoryCloud: CloudRemote {
    private var record: CloudRecord?
    private var loseNextResponse = false
    private var failNextSave = false
    private var duringSave: (() throws -> Void)?
    private(set) var writes = 0
    init(_ ledger: Ledger? = nil, revision: Int = 1) {
        record = ledger.map { CloudRecord(payload: $0, revision: revision, updated_at: "2026-10-25T12:00:00Z") }
    }
    func load() -> CloudRecord? { record }
    func setFailure(loseResponse: Bool = false, failBeforeSave: Bool = false) {
        loseNextResponse = loseResponse; failNextSave = failBeforeSave
    }
    func setDuringSave(_ action: @escaping () throws -> Void) { duringSave = action }
    func externalWrite(_ ledger: Ledger) {
        record = CloudRecord(payload: ledger, revision: (record?.revision ?? 0) + 1, updated_at: nil)
    }
    func save(_ ledger: Ledger, expectedRevision: Int) throws -> Int {
        if failNextSave { failNextSave = false; throw CloudFailure.connection }
        guard expectedRevision == (record?.revision ?? 0) else { throw CloudFailure.changed }
        let revision = expectedRevision + 1
        writes += 1
        record = CloudRecord(payload: ledger, revision: revision, updated_at: nil)
        let action = duringSave; duringSave = nil; try action?()
        if loseNextResponse { loseNextResponse = false; throw CloudFailure.connection }
        return revision
    }
}

final class CloudSyncTests: XCTestCase {
    private let user = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private let server = "https://example.supabase.co"
    private func ledger(_ merchant: String) -> Ledger {
        Ledger(expenses: [Expense(merchant: merchant, cents: 1250, date: Date(timeIntervalSince1970: 1_790_000_000))])
    }
    private func temporaryStore() -> LocalStore {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return LocalStore(folder: root)
    }
    func testSyncDecisionsDoNotOverwriteDivergentOrDeletedCloudData() {
        let baseline = CloudLink(userID: user, server: server, revision: 2, fingerprint: "base")
        XCTAssertEqual(CloudSyncDecision.decide(local: "new", hasLocalFile: true, remote: "base", revision: 2, link: baseline), .upload)
        XCTAssertEqual(CloudSyncDecision.decide(local: "base", hasLocalFile: true, remote: "remote-edit", revision: 3, link: baseline), .download)
        XCTAssertEqual(CloudSyncDecision.decide(local: "local-edit", hasLocalFile: true, remote: "remote-edit", revision: 3, link: baseline), .conflict)
        XCTAssertEqual(CloudSyncDecision.decide(local: "new", hasLocalFile: true, remote: nil, revision: 0, link: baseline), .conflict)
        XCTAssertEqual(CloudSyncDecision.decide(local: "guest", hasLocalFile: true, remote: "old-account", revision: 2, link: nil), .conflict)
        XCTAssertEqual(CloudSyncDecision.decide(local: "empty", hasLocalFile: false, remote: "old-account", revision: 2, link: nil), .download)
    }
    func testReinstallAutomaticallyDownloadsWithoutUploadingAnEmptyLedger() async throws {
        let original = ledger("Before uninstall")
        let cloud = MemoryCloud(original, revision: 7)
        let store = temporaryStore()
        let sync = CloudSynchronizer(store: store)
        let result = try await sync.sync(userID: user, server: server, remote: cloud)
        guard case .synced(let link, let downloaded) = result else { return XCTFail("Expected automatic restoration") }
        XCTAssertTrue(downloaded)
        XCTAssertEqual(link.revision, 7)
        XCTAssertEqual(try store.read().expenses, original.expenses)
        let writes = await cloud.writes
        XCTAssertEqual(writes, 0)
    }
    func testFirstLoginUploadsLocalLedgerAndRemembersAccount() async throws {
        let original = ledger("Local purchase")
        let store = temporaryStore(); try store.change { $0 = original }
        let cloud = MemoryCloud()
        let sync = CloudSynchronizer(store: store)
        _ = try await sync.sync(userID: user, server: server, remote: cloud)
        XCTAssertEqual(try store.cloudLink()?.userID, user)
        let remote = await cloud.load()
        XCTAssertEqual(remote?.payload.expenses, original.expenses)
        do {
            _ = try await sync.sync(userID: UUID(), server: server, remote: cloud)
            XCTFail("Another account must not inherit this ledger")
        } catch CloudFailure.accountMismatch {} catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertEqual(try store.read().expenses, original.expenses)
    }
    func testLostUploadResponseIsRecoveredWithoutDuplicatingOrOverwriting() async throws {
        let original = ledger("Lunch")
        let store = temporaryStore(); try store.change { $0 = original }
        let cloud = MemoryCloud(); await cloud.setFailure(loseResponse: true)
        let sync = CloudSynchronizer(store: store)
        do { _ = try await sync.sync(userID: user, server: server, remote: cloud); XCTFail("Expected dropped response") }
        catch CloudFailure.connection {}
        XCTAssertEqual(try store.cloudLink()?.userID, user)
        XCTAssertNil(try store.cloudLink()?.fingerprint)
        _ = try await sync.sync(userID: user, server: server, remote: cloud)
        let writes = await cloud.writes
        XCTAssertEqual(writes, 1)
        XCTAssertEqual(try store.cloudLink()?.revision, 1)
        XCTAssertEqual(try store.read().expenses, original.expenses)
    }
    func testWriteDuringUploadRemainsDirtyAndNextSyncIncludesIt() async throws {
        let original = ledger("Lunch")
        let store = temporaryStore(); try store.change { $0 = original }
        let cloud = MemoryCloud()
        await cloud.setDuringSave { try store.change { $0.budgets["2026-10"] = 100000 } }
        let sync = CloudSynchronizer(store: store)
        let first = try await sync.sync(userID: user, server: server, remote: cloud)
        guard case .synced(let link, _) = first else { return XCTFail("Expected upload") }
        let dirty = try await sync.needsUpload(comparedTo: link)
        XCTAssertTrue(dirty)
        _ = try await sync.sync(userID: user, server: server, remote: cloud)
        let remote = await cloud.load()
        XCTAssertEqual(remote?.payload.budgets["2026-10"], 100000)
        XCTAssertEqual(remote?.revision, 2)
    }
    func testConflictRequiresMatchingConfirmationAndPreservesLocalRecoveryCopy() async throws {
        let store = temporaryStore()
        let local = ledger("Local")
        let originalRemote = ledger("Cloud")
        try store.change { $0 = local }
        let cloud = MemoryCloud(originalRemote)
        let sync = CloudSynchronizer(store: store)
        let first = try await sync.sync(userID: user, server: server, remote: cloud)
        guard case .conflict(let conflict) = first else { return XCTFail("Expected conflict") }
        XCTAssertEqual(try store.read().expenses, local.expenses)
        var updated = originalRemote; updated.budgets["2026-10"] = 20000
        await cloud.externalWrite(updated)
        let stale = try await sync.sync(userID: user, server: server, remote: cloud, resolution: CloudResolution(choice: .local, conflict: conflict))
        guard case .conflict(let fresh) = stale else { return XCTFail("A stale confirmation must not overwrite newer cloud data") }
        _ = try await sync.sync(userID: user, server: server, remote: cloud, resolution: CloudResolution(choice: .remote, conflict: fresh))
        XCTAssertEqual(try store.read().expenses, updated.expenses)
        XCTAssertEqual(try LocalStore.decode(Data(contentsOf: store.recoveryFile)).expenses, local.expenses)
    }
    func testOfflineFailureKeepsLocalChangesAndCloudReplacementRejectsConcurrentEdit() async throws {
        let store = temporaryStore(); let original = ledger("Offline")
        try store.change { $0 = original }
        let hash = try CloudFingerprint.make(original)
        let cloud = MemoryCloud(); await cloud.setFailure(failBeforeSave: true)
        let sync = CloudSynchronizer(store: store)
        do { _ = try await sync.sync(userID: user, server: server, remote: cloud); XCTFail("Expected offline failure") }
        catch CloudFailure.connection {}
        XCTAssertEqual(try store.read().expenses, original.expenses)
        try store.change { $0.budgets["2026-10"] = 12300 }
        XCTAssertThrowsError(try store.replaceFromCloud(ledger("Remote"), expectedFingerprint: hash))
        XCTAssertEqual(try store.read().budgets["2026-10"], 12300)
    }
    func testCanonicalFingerprintAndConfigurationValidation() throws {
        var a = ledger("Lunch"); a.seenEvents = ["a", "b"]; a.dismissedSubscriptions = ["x", "y"]
        var b = a; b.seenEvents = ["b", "a"]; b.dismissedSubscriptions = ["y", "x"]
        XCTAssertEqual(try CloudFingerprint.make(a), try CloudFingerprint.make(b))
        XCTAssertThrowsError(try CloudConfiguration(url: "http://example.com", publicKey: "sb_publishable_example_key"))
        XCTAssertThrowsError(try CloudConfiguration(url: server, publicKey: "sb_secret_example_key"))
        XCTAssertThrowsError(try CloudConfiguration(url: server + "/rest/v1", publicKey: "sb_publishable_example_key"))
        XCTAssertEqual(try CloudConfiguration(url: server + "/", publicKey: "sb_publishable_example_key").server, server)
    }
}

/// Each ephemeral URLSession has its own host/fixture, so parallel tests cannot consume
/// one another's replies. No test reaches Supabase or sends sign-in mail.
private final class CloudHTTPStub: URLProtocol {
    struct Fixture {
        var replies: [(Int, String)]
        var requests: [URLRequest] = []
    }
    private static let lock = NSLock()
    private static var fixtures: [String: Fixture] = [:]
    static func install(host: String, replies: [(Int, String)]) {
        lock.lock(); defer { lock.unlock() }
        fixtures[host] = Fixture(replies: replies)
    }
    static func requests(host: String) -> [URLRequest] {
        lock.lock(); defer { lock.unlock() }
        return fixtures[host]?.requests ?? []
    }
    static func remove(host: String) {
        lock.lock(); defer { lock.unlock() }
        fixtures.removeValue(forKey: host)
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let host = request.url?.host ?? ""
        Self.lock.lock()
        guard var fixture = Self.fixtures[host], !fixture.replies.isEmpty, let url = request.url else {
            Self.lock.unlock()
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let reply = fixture.replies.removeFirst()
        fixture.requests.append(request); Self.fixtures[host] = fixture
        Self.lock.unlock()
        let response = HTTPURLResponse(url: url, statusCode: reply.0, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(reply.1.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class CloudHTTPTests: XCTestCase {
    private func service(replies: [(Int, String)], signedIn: Bool = false) throws -> (SupabaseCloudService, String) {
        let host = UUID().uuidString.lowercased() + ".invalid"
        CloudHTTPStub.install(host: host, replies: replies)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CloudHTTPStub.self]
        let http = URLSession(configuration: configuration)
        addTeardownBlock { http.invalidateAndCancel(); CloudHTTPStub.remove(host: host) }
        let cloud = try CloudConfiguration(url: "https://" + host, publicKey: "sb_publishable_test_fixture")
        let session = signedIn ? CloudSession(access_token: "access-fixture", refresh_token: "refresh-fixture", user: .init(id: UUID(), email: "test@example.invalid")) : nil
        return (SupabaseCloudService(configuration: cloud, session: session, http: http), host)
    }
    func testConnectionCheckUsesOnlyPublicConfigurationAndNoLedgerEndpoint() async throws {
        let (api, host) = try service(replies: [(200, "{}"), (200, "1")])
        try await api.checkConnection()
        let requests = CloudHTTPStub.requests(host: host)
        XCTAssertEqual(requests.map { $0.url?.path }, ["/auth/v1/settings", "/rest/v1/rpc/yueji_sync_health"])
        XCTAssertTrue(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == nil })
        XCTAssertTrue(requests.allSatisfy { $0.value(forHTTPHeaderField: "apikey") == "sb_publishable_test_fixture" })
    }
    func testMissingDatabaseIsDifferentFromRejectedKey() async throws {
        let (missing, _) = try service(replies: [(200, "{}"), (404, #"{"code":"PGRST202"}"#)])
        do { try await missing.checkConnection(); XCTFail("Expected missing schema") }
        catch CloudFailure.database {}
        let (badKey, _) = try service(replies: [(401, "{}")])
        do { try await badKey.checkConnection(); XCTFail("Expected rejected key") }
        catch CloudFailure.configuration {}
    }
    func testServerOutageDoesNotBecomeAnExpiredSessionOrDropCachedToken() async throws {
        let (api, host) = try service(replies: [(503, "{}"), (200, "[]")], signedIn: true)
        do { _ = try await api.refresh(); XCTFail("Expected server outage") }
        catch CloudFailure.server(let status, let endpoint) {
            XCTAssertEqual(status, 503)
            XCTAssertEqual(endpoint, "/auth/v1/token")
        }
        _ = try await api.load()
        XCTAssertEqual(CloudHTTPStub.requests(host: host).last?.value(forHTTPHeaderField: "Authorization"), "Bearer access-fixture")
        let (expired, _) = try service(replies: [(400, #"{"error_code":"refresh_token_not_found"}"#)], signedIn: true)
        do { _ = try await expired.refresh(); XCTFail("Expected expired session") }
        catch CloudFailure.session {}
    }
}
