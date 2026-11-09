import SwiftUI
import PhotosUI
import MapKit
import UserNotifications
import CryptoKit

private let parkingAccent = Color(red: 1, green: 0.32, blue: 0.035)

struct ParkingVehicle: Codable, Equatable {
    var brand = ""
    var model = ""
    var year = ""
    var color = "silver"
    var body = "car"
    var title: String { [brand, model, year].filter { !$0.isEmpty }.joined(separator: " · ") }
    var tint: Color {
        switch color {
        case "white": return .white
        case "black": return Color(white: 0.15)
        case "red": return .red
        case "blue": return .blue
        case "green": return .green
        default: return .gray
        }
    }
}

private struct ParkingActionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline)
            .frame(maxWidth: .infinity, minHeight: 52)
            .foregroundStyle(.white)
            .background(parkingAccent, in: Capsule())
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

/// The map represents only a recorded coordinate, never available parking spaces.
private struct ParkingMapCard: View {
    let session: ParkingSession?
    var vehicle: ParkingVehicle? = nil
    private var shownVehicle: ParkingVehicle? { session?.vehicle ?? vehicle }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(tr("每一次停靠", "Every stop", "Setiap persinggahan"))
                        .font(.title2.weight(.light)).foregroundStyle(.secondary)
                    Text(tr("都有迹可寻", "Find your way back", "Cari jalan kembali"))
                        .font(.largeTitle.bold())
                }
                Spacer(minLength: 8)
                Image(systemName: "parkingsign").font(.title2.bold()).foregroundStyle(.white)
                    .frame(width: 52, height: 52).background(parkingAccent, in: Circle())
            }
            ZStack(alignment: .bottomLeading) {
                if let place = session?.place, let latitude = place.latitude, let longitude = place.longitude {
                    let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
                    Map(initialPosition: .region(MKCoordinateRegion(center: coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.006, longitudeDelta: 0.006))), interactionModes: []) {
                        Marker(session?.name.isEmpty == false ? session!.name : place.name, systemImage: "car.fill", coordinate: coordinate)
                            .tint(parkingAccent)
                    }.accessibilityLabel(tr("已记录的停车位置", "Recorded parking location", "Lokasi parkir direkodkan"))
                } else {
                    ZStack {
                        Color(uiColor: .tertiarySystemGroupedBackground)
                        RoundedRectangle(cornerRadius: 24).strokeBorder(.secondary.opacity(0.15), style: StrokeStyle(lineWidth: 2, dash: [10]))
                            .padding(30)
                        VStack(spacing: 12) {
                            Image(systemName: shownVehicle?.body == "suv" ? "suv.side.fill" : "car.side.fill")
                                .font(.system(size: 76, weight: .light))
                                .foregroundStyle(shownVehicle?.tint ?? .gray)
                                .shadow(color: .black.opacity(0.25), radius: 2, y: 2)
                            Text(tr("车辆示意图", "Vehicle illustration", "Ilustrasi kenderaan"))
                                .font(.caption).foregroundStyle(.secondary)
                        }.offset(y: -18)
                    }
                }
                Label(session?.place == nil
                    ? tr("开始停车后记录位置", "Save a location when you park", "Simpan lokasi apabila parkir")
                    : tr("我的停车位置", "My parked car", "Lokasi kereta saya"), systemImage: "location.fill")
                    .font(.subheadline.weight(.semibold)).padding(12)
                    .background(.regularMaterial, in: Capsule()).padding(16)
            }.frame(height: 250).clipShape(RoundedRectangle(cornerRadius: 30))
            HStack(spacing: 12) {
                Image(systemName: "car.fill").font(.title2)
                VStack(alignment: .leading, spacing: 4) {
                    Text(session?.plate.isEmpty == false ? session!.plate : tr("我的车辆", "My vehicle", "Kenderaan saya")).font(.headline)
                    if let vehicle = shownVehicle, !vehicle.title.isEmpty {
                        Text(vehicle.title).font(.subheadline).lineLimit(2)
                    }
                    Text(session?.bay.isEmpty == false ? session!.bay : tr("记录车位 · 计时 · 找车", "Save your bay · track time · find car", "Simpan petak · kira masa · cari kereta"))
                        .font(.caption)
                }
                Spacer()
                Image(systemName: "arrow.down.right").font(.title2)
            }.foregroundStyle(.white).padding(20)
                .background(parkingAccent, in: RoundedRectangle(cornerRadius: 26))
        }.padding(.vertical, 8)
    }
}

private struct ParkingTimerDial: View {
    let session: ParkingSession
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let elapsed = max(0, (session.endedAt ?? context.date).timeIntervalSince(session.startedAt))
            let duration = session.paidUntil.map { $0.timeIntervalSince(session.startedAt) } ?? 0
            let fraction = duration > 0 ? min(1, elapsed / duration) : 0
            ZStack {
                Circle().stroke(.secondary.opacity(0.1), lineWidth: 16)
                if duration > 0 {
                    Circle().trim(from: 0, to: fraction)
                        .stroke(parkingAccent, style: StrokeStyle(lineWidth: 16, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                VStack(spacing: 10) {
                    Image(systemName: session.endedAt == nil ? "hourglass" : "checkmark")
                        .font(.title2).foregroundStyle(parkingAccent)
                    let minutes = session.durationMinutes(now: context.date)
                    Text("\(minutes / 60) h \(minutes % 60) min").font(.title.bold().monospacedDigit())
                    Text(session.endedAt == nil ? tr("已停时长", "Time parked", "Tempoh parkir") : tr("总停车时长", "Total parking time", "Jumlah tempoh parkir"))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.frame(width: 220, height: 220).padding(18).frame(maxWidth: .infinity)
        }
    }
}

struct ParkingReceiptHints {
    var amounts: [String] = []
    var endDates: [Date] = []
    var places: [String] = []
    init(text: String) {
        let lines = text.components(separatedBy: .newlines)
        let money = try! NSRegularExpression(pattern: #"(?i)\b(?:RM|MYR)\s*([0-9]{1,5}\.[0-9]{2})\b"#)
        for match in money.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            if let range = Range(match.range(at: 1), in: text) {
                let value = String(text[range])
                if !amounts.contains(value) { amounts.append(value) }
            }
        }
        for (index, line) in lines.enumerated() {
            if line.range(of: #"(?i)^\s*(location|car park|parking location|lokasi)\s*:\s*\S"#, options: .regularExpression) != nil,
               let colon = line.firstIndex(of: ":") {
                places.append(String(line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces).prefix(200)))
            }
            guard line.range(of: #"(?i)(expiry|expires|end time|paid until|tamat|到期|结束时间)"#, options: .regularExpression) != nil else { continue }
            // A time alone is ambiguous; only offer complete date + time candidates.
            let candidates = [line.components(separatedBy: ": ").last ?? line, index + 1 < lines.count ? lines[index + 1] : ""]
            for candidate in candidates {
                guard candidate.range(of: #"\b\d{4}\b"#, options: .regularExpression) != nil,
                      candidate.range(of: #"\d{1,2}:\d{2}"#, options: .regularExpression) != nil else { continue }
                for format in ["dd/MM/yyyy HH:mm", "dd/MM/yyyy h:mm a", "yyyy-MM-dd HH:mm", "d MMM yyyy h:mm a"] {
                    let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
                    formatter.timeZone = TimeZone(identifier: "Asia/Kuala_Lumpur"); formatter.dateFormat = format; formatter.isLenient = false
                    if let date = formatter.date(from: candidate.trimmingCharacters(in: .whitespaces)), !endDates.contains(date) { endDates.append(date) }
                }
            }
        }
    }
}

struct ParkingSession: Codable, Identifiable {
    var id = UUID().uuidString
    var startedAt = Date()
    var endedAt: Date?
    var plate = ""
    var vehicle: ParkingVehicle?
    var name = ""
    var bay = ""
    var place: ExpensePlace?
    var photo: Data?
    var paidUntil: Date?
    var paidCents: Int?
    var reminderMinutes = 10
    var expenseID: String?
    var notificationID: String { "parking." + id }
    func durationMinutes(now: Date) -> Int {
        max(0, Int((endedAt ?? now).timeIntervalSince(startedAt) / 60))
    }
    func reminderDate(now: Date) -> Date? {
        guard endedAt == nil, let paidUntil else { return nil }
        let date = paidUntil.addingTimeInterval(-Double(reminderMinutes * 60))
        return date > now ? date : nil
    }
}

@MainActor
final class ParkingStore: ObservableObject {
    @Published private(set) var sessions: [ParkingSession] = []
    @Published private(set) var rememberedPlates: [String] = []
    @Published private(set) var vehicles: [String: ParkingVehicle] = [:]
    let scope: String
    private let url: URL
    private let platesKey: String
    private var vehiclesURL: URL { url.deletingPathExtension().appendingPathExtension("vehicles.json") }
    static func plateKey(_ raw: String) -> String {
        String(raw.uppercased().filter { !$0.isWhitespace }.prefix(20))
    }
    func vehicle(for plate: String) -> ParkingVehicle? { vehicles[Self.plateKey(plate)] }
    func saveVehicle(_ vehicle: ParkingVehicle, plate: String) throws {
        let key = Self.plateKey(plate)
        guard !key.isEmpty else { throw LedgerError.invalid(tr("请先填写车牌", "Enter a plate first", "Isi plat dahulu")) }
        var updated = vehicles; updated[key] = vehicle
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(updated).write(to: vehiclesURL, options: [.atomic, .completeFileProtection])
        vehicles = updated
        rememberPlate(plate)
    }
    init(scope: String) {
        self.scope = scope
        let hash = SHA256.hash(data: Data(scope.utf8)).map { String(format: "%02x", $0) }.joined()
        platesKey = "parking.plates." + hash
        url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Parking").appendingPathComponent(hash + ".json")
    }
    func load() throws {
        rememberedPlates = UserDefaults.standard.stringArray(forKey: platesKey) ?? []
        if FileManager.default.fileExists(atPath: vehiclesURL.path) {
            vehicles = try JSONDecoder().decode([String: ParkingVehicle].self, from: Data(contentsOf: vehiclesURL))
        }
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        sessions = try JSONDecoder().decode([ParkingSession].self, from: Data(contentsOf: url))
        if rememberedPlates.isEmpty {
            for session in sessions.reversed() { rememberPlate(session.plate) }
        }
    }
    func save(_ session: ParkingSession) throws {
        var updated = sessions.filter { $0.id != session.id }
        updated.insert(session, at: 0)
        try persist(updated)
        rememberPlate(session.plate)
    }
    func rememberPlate(_ raw: String) {
        let plate = String(raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased().prefix(20))
        guard !plate.isEmpty else { return }
        rememberedPlates = [plate] + rememberedPlates.filter { $0 != plate }
        UserDefaults.standard.set(rememberedPlates, forKey: platesKey)
    }
    func delete(_ session: ParkingSession) throws {
        try persist(sessions.filter { $0.id != session.id })
        cancelReminder(session)
    }
    private func persist(_ updated: [ParkingSession]) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(updated).write(to: url, options: [.atomic, .completeFileProtection])
        sessions = updated
    }
    func cancelReminder(_ session: ParkingSession) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [session.notificationID])
        center.removeDeliveredNotifications(withIdentifiers: [session.notificationID])
    }
    func remind(_ session: ParkingSession) async throws -> Bool {
        cancelReminder(session)
        guard let date = session.reminderDate(now: Date()) else { return false }
        let center = UNUserNotificationCenter.current()
        guard try await center.requestAuthorization(options: [.alert, .sound]) else { return false }
        guard let current = sessions.first(where: { $0.id == session.id }), current.endedAt == nil,
              current.paidUntil == session.paidUntil, date > Date(),
              CloudAccount.shared.researchHistoryScope == scope else { return false }
        let content = UNMutableNotificationContent()
        content.title = tr("停车即将到期", "Parking expires soon", "Parkir hampir tamat")
        content.body = tr("请查看已确认的停车结束时间，按需续费或取车。", "Check your confirmed parking end time and renew or collect your car.", "Semak masa tamat parkir dan lanjutkan atau ambil kereta.")
        content.sound = .default
        try await center.add(UNNotificationRequest(identifier: session.notificationID, content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, date.timeIntervalSinceNow), repeats: false)))
        return true
    }
}

struct ParkingView: View {
    @ObservedObject private var account = CloudAccount.shared
    var body: some View {
        Group {
            if let scope = account.researchHistoryScope { ParkingHome(scope: scope).id(scope) }
            else { ContentUnavailableView(tr("请先登录", "Sign in first", "Log masuk dahulu"), systemImage: "person.crop.circle") }
        }.navigationTitle(tr("停车助手", "Parking assistant", "Pembantu parkir"))
    }
}

private struct ParkingStatus: View {
    let session: ParkingSession
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            VStack(alignment: .leading, spacing: 10) {
                Label(session.name.isEmpty ? tr("未填写停车地点", "Parking place not entered", "Tempat parkir belum diisi") : session.name,
                      systemImage: "parkingsign.circle.fill").font(.headline)
                if !session.plate.isEmpty { Text(session.plate).font(.title3.monospaced().bold()) }
                if !session.bay.isEmpty { Label(session.bay, systemImage: "mappin.and.ellipse") }
                let minutes = session.durationMinutes(now: context.date)
                Label("\(minutes / 60) h \(minutes % 60) min", systemImage: "timer").font(.title2.monospacedDigit())
                if session.endedAt != nil {
                    Text(tr("已结束", "Ended", "Tamat")).foregroundStyle(.secondary)
                } else if let end = session.paidUntil {
                    if end <= context.date {
                        Label(tr("已确认的停车时间已到期", "Confirmed parking time expired", "Masa parkir disahkan telah tamat"), systemImage: "exclamationmark.clock")
                            .foregroundStyle(.red)
                    } else {
                        Text(tr("已付费至", "Paid until", "Dibayar sehingga") + " " + end.formatted(date: .omitted, time: .shortened))
                            .foregroundStyle(.secondary)
                        Text(end, style: .relative).monospacedDigit()
                    }
                } else {
                    Label(tr("缴费待确认", "Payment awaiting confirmation", "Bayaran menunggu pengesahan"), systemImage: "clock.badge.questionmark")
                        .foregroundStyle(.orange)
                }
                if let cents = session.paidCents { Text(money(cents)).font(.headline) }
            }.padding(.vertical, 8)
        }
    }
}

private struct ParkingHome: View {
    @StateObject private var store: ParkingStore
    @StateObject private var locator = ExpensePlaceLocator()
    @Environment(\.openURL) private var openURL
    @State private var plate = ""
    @State private var name = ""
    @State private var bay = ""
    @State private var error = ""
    @State private var ready = false
    @State private var startingID: String?
    @State private var goToTNG = false
    @State private var search = ""
    @State private var openedSession: ParkingSession?
    @State private var editingVehicle = false
    private var active: ParkingSession? { store.sessions.first { $0.endedAt == nil } }
    private var savedPlates: [String] {
        store.rememberedPlates
    }
    private var history: [ParkingSession] {
        store.sessions.filter { $0.endedAt != nil && (search.isEmpty ||
            ($0.name + " " + $0.plate + " " + $0.bay).localizedCaseInsensitiveContains(search)) }
    }
    init(scope: String) { _store = StateObject(wrappedValue: ParkingStore(scope: scope)) }
    private func launchTNG() {
        openURL(URL(string: "https://visit.tngdigital.com.my/StreetParking")!) { accepted in
            if !accepted { error = tr("无法打开 TNG，请手动打开 eWallet 的 Parking。记录已保存。", "Open Parking in TNG manually. Your record is saved.", "Buka Parking dalam TNG sendiri. Rekod telah disimpan.") }
        }
    }
    private func start(tng: Bool) {
        guard ready, startingID == nil, !store.sessions.contains(where: { $0.endedAt == nil }) else { return }
        do {
            var session = ParkingSession()
            session.plate = String(plate.trimmingCharacters(in: .whitespacesAndNewlines).uppercased().prefix(20)); session.name = String(name.prefix(200)); session.bay = String(bay.prefix(200))
            session.vehicle = store.vehicle(for: plate)
            try store.save(session)
            startingID = session.id; goToTNG = tng; error = ""
            locator.start()
        } catch { self.error = error.localizedDescription }
    }
    private func finishLocation() {
        guard let id = startingID else { return }
        startingID = nil
        if var session = store.sessions.first(where: { $0.id == id }) {
            session.place = locator.result
            do { try store.save(session) } catch { self.error = error.localizedDescription }
        }
        if goToTNG { goToTNG = false; launchTNG() }
        else { openedSession = store.sessions.first { $0.id == id } }
    }
    var body: some View {
        List {
            Section {
                ParkingMapCard(session: active, vehicle: store.vehicle(for: plate))
            }.listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            Section {
                Text(tr("保存车位、停车计时、前往 TNG 缴费。记录仅保存在这台设备，不随账本同步。", "Save your bay, track time and pay through TNG. Parking records stay on this device and do not sync with the ledger.", "Simpan petak, kira masa dan bayar melalui TNG. Rekod parkir hanya pada peranti ini, tidak disegerak dengan lejar."))
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if let session = active {
                Section(tr("正在停车", "Current parking", "Parkir semasa")) {
                    ParkingStatus(session: session)
                    Button(tr("管理停车 · 找车 / 续费 / 结束", "Manage · find car / renew / end", "Urus · cari kereta / lanjut / tamat")) { openedSession = session }
                        .buttonStyle(ParkingActionStyle())
                        .disabled(startingID != nil)
                    Button(tr("前往 TNG 停车缴费", "Open TNG parking", "Buka parkir TNG"), action: launchTNG)
                        .disabled(startingID != nil)
                }
            } else {
                Section(tr("开始停车", "Start parking", "Mula parkir")) {
                    TextField(tr("车牌（可选）", "Plate (optional)", "Plat (pilihan)"), text: $plate)
                        .textInputAutocapitalization(.characters).autocorrectionDisabled()
                        .onSubmit { store.rememberPlate(plate) }
                    Button(tr("记住车牌", "Remember plate", "Ingat plat")) { store.rememberPlate(plate) }
                        .disabled(plate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button {
                        editingVehicle = true
                    } label: {
                        Label(store.vehicle(for: plate)?.title.isEmpty == false ? store.vehicle(for: plate)!.title :
                            tr("设置品牌、车型与颜色", "Set brand, model and colour", "Tetapkan jenama, model dan warna"), systemImage: "car.side.fill")
                    }.disabled(ParkingStore.plateKey(plate).isEmpty)
                    if !savedPlates.isEmpty {
                        Menu(tr("选择已用车牌", "Choose a used plate", "Pilih plat terdahulu")) {
                            ForEach(savedPlates, id: \.self) { value in Button(value) { plate = value } }
                        }
                        Text(tr("已记住上次车牌，可直接使用或修改。", "Your last plate is remembered. Use it or change it.", "Plat terakhir diingati. Gunakan atau ubah."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    TextField(tr("停车场或地区", "Car park or area", "Tempat atau kawasan"), text: $name)
                    TextField(tr("楼层 / 区域 / 车位号", "Floor / zone / bay", "Tingkat / zon / petak"), text: $bay)
                    Button(tr("开始停车并前往 TNG", "Start and open TNG", "Mula dan buka TNG")) { start(tng: true) }
                        .buttonStyle(ParkingActionStyle()).disabled(!ready)
                    Button(tr("只记录停车", "Record parking only", "Rekod parkir sahaja")) { start(tng: false) }.disabled(!ready)
                }
            }
            if startingID != nil {
                Section {
                    ProgressView(tr("记录已保存，正在定位…", "Saved. Finding location…", "Disimpan. Mencari lokasi…"))
                    Button(tr("跳过定位，继续", "Skip location and continue", "Langkau lokasi dan teruskan")) { locator.cancel(); finishLocation() }
                }
            }
            if let message = locator.message { Text(message).font(.footnote).foregroundStyle(.secondary) }
            if !error.isEmpty { Text(error).foregroundStyle(.red) }
            Section(tr("停车历史", "Parking history", "Sejarah parkir")) {
                TextField(tr("搜索地点、车牌或车位", "Search place, plate or bay", "Cari tempat, plat atau petak"), text: $search)
                if history.isEmpty {
                    Text(tr("暂无匹配记录。结束停车后，可在这里查看时长和费用。", "No matching records. Finished parking appears here with duration and fees.", "Tiada rekod sepadan. Parkir tamat muncul di sini dengan tempoh dan bayaran."))
                        .font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(history) { session in
                    NavigationLink { ParkingDetail(store: store, session: session) } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Label(session.name.isEmpty ? tr("停车", "Parking", "Parkir") : session.name, systemImage: "parkingsign.circle.fill")
                            Text(session.startedAt, style: .date).font(.caption)
                            let minutes = session.durationMinutes(now: Date())
                            Text("\(minutes / 60) h \(minutes % 60) min" + (session.paidCents.map { " · " + money($0) } ?? ""))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }.disabled(startingID != nil)
                }
            }
            Section(tr("使用步骤", "How it works", "Cara penggunaan")) {
                Label(tr("1. 开始停车，保存地点与车位", "1. Start and save your location and bay", "1. Mula dan simpan lokasi serta petak"), systemImage: "mappin")
                Label(tr("2. 在 TNG 付款，返回确认到期时间", "2. Pay in TNG, return to confirm expiry", "2. Bayar dalam TNG, kembali sahkan tamat"), systemImage: "creditcard")
                Label(tr("3. 到期提醒、地图找车，结束后核对记账", "3. Reminder, find car, then review the expense", "3. Peringatan, cari kereta, kemudian semak belanja"), systemImage: "checkmark.circle")
            }.font(.footnote)
        }
        .listStyle(.insetGrouped).tint(parkingAccent)
        .sheet(isPresented: $editingVehicle) {
            ParkingVehicleEditor(store: store, plate: plate, vehicle: store.vehicle(for: plate) ?? ParkingVehicle())
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: Binding(get: { openedSession != nil }, set: { if !$0 { openedSession = nil } })) {
            if let session = openedSession { ParkingDetail(store: store, session: session) }
        }
        .task {
            do { try store.load(); if plate.isEmpty { plate = savedPlates.first ?? "" }; ready = true }
            catch { self.error = error.localizedDescription }
        }
        .onChange(of: locator.result) { _, result in if result != nil { finishLocation() } }
        .onChange(of: locator.message) { _, message in if message != nil { finishLocation() } }
        .onDisappear {
            store.rememberPlate(plate)
            locator.cancel(); startingID = nil; goToTNG = false
        }
    }
}

private struct ParkingVehicleEditor: View {
    @ObservedObject var store: ParkingStore
    let plate: String
    @State var vehicle: ParkingVehicle
    @Environment(\.dismiss) private var dismiss
    @State private var error = ""
    var body: some View {
        NavigationStack {
            Form {
                Section(plate) {
                    TextField(tr("品牌（例如 Perodua）", "Brand (e.g. Perodua)", "Jenama (cth. Perodua)"), text: $vehicle.brand)
                    TextField(tr("车型（例如 Myvi）", "Model (e.g. Myvi)", "Model (cth. Myvi)"), text: $vehicle.model)
                    TextField(tr("年份（可选）", "Year (optional)", "Tahun (pilihan)"), text: $vehicle.year).keyboardType(.numberPad)
                    Picker(tr("车身类型", "Body type", "Jenis badan"), selection: $vehicle.body) {
                        Text(tr("轿车 / 掀背车", "Sedan / hatchback", "Sedan / hatchback")).tag("car")
                        Text("SUV / MPV").tag("suv")
                    }
                    Picker(tr("车身颜色", "Vehicle colour", "Warna kenderaan"), selection: $vehicle.color) {
                        Text(tr("银 / 灰", "Silver / grey", "Perak / kelabu")).tag("silver")
                        Text(tr("白色", "White", "Putih")).tag("white")
                        Text(tr("黑色", "Black", "Hitam")).tag("black")
                        Text(tr("红色", "Red", "Merah")).tag("red")
                        Text(tr("蓝色", "Blue", "Biru")).tag("blue")
                        Text(tr("绿色", "Green", "Hijau")).tag("green")
                    }
                }
                Section {
                    ParkingMapCard(session: nil, vehicle: vehicle)
                    Text(tr("资料由你填写并绑定车牌。目前按车身类型和颜色显示示意图，不是品牌车型的精确外观。", "Your details are saved against this plate. The illustration uses body type and colour, not the exact model design.", "Butiran disimpan mengikut plat ini. Ilustrasi menggunakan jenis badan dan warna, bukan reka bentuk model tepat."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                if !error.isEmpty { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle(tr("我的车辆", "My vehicle", "Kenderaan saya"))
            .navigationBarTitleDisplayMode(.inline).tint(parkingAccent)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("取消", "Cancel", "Batal")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("保存", "Save", "Simpan")) {
                        vehicle.brand = String(vehicle.brand.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))
                        vehicle.model = String(vehicle.model.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
                        vehicle.year = String(vehicle.year.filter(\.isNumber).prefix(4))
                        do { try store.saveVehicle(vehicle, plate: plate); dismiss() }
                        catch { self.error = error.localizedDescription }
                    }.disabled(vehicle.brand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || vehicle.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

private struct ParkingDetail: View {
    @ObservedObject var store: ParkingStore
    @EnvironmentObject private var model: LedgerModel
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @State var session: ParkingSession
    @State private var until = Date().addingTimeInterval(3600)
    @State private var amount = ""
    @State private var message = ""
    @State private var photo: PhotosPickerItem?
    @State private var receipt: PhotosPickerItem?
    @State private var receiptText = ""
    @State private var busy = false
    @State private var deleting = false
    @State private var ending = false
    @State private var initialized = false
    @State private var expenseDraft: Expense?
    private func save() { do { try store.save(session); message = tr("已保存", "Saved", "Disimpan") } catch { message = error.localizedDescription } }
    private func confirmPayment() {
        guard until > Date(), until > session.startedAt else { message = tr("请选择未来的结束时间", "Choose a future end time", "Pilih masa tamat akan datang"); return }
        do {
            let cents: Int? = amount.isEmpty ? nil : try toCents(amount)
            if let cents, cents <= 0 { throw LedgerError.invalid(tr("金额必须大于零", "Amount must be positive", "Amaun mesti positif")) }
            var updated = session; updated.paidUntil = until; updated.paidCents = cents
            try store.save(updated); session = updated; busy = true
            Task { @MainActor in
                defer { busy = false }
                do {
                    let scheduled = try await store.remind(updated)
                    message = scheduled ? tr("已确认，提醒已安排", "Confirmed; reminder scheduled", "Disahkan; peringatan dijadualkan") : tr("已确认，但未安排提醒：检查通知权限或提前时间。", "Confirmed, but no reminder scheduled. Check permission and lead time.", "Disahkan tetapi tiada peringatan. Semak kebenaran dan masa awal.")
                } catch { message = tr("已确认，但提醒设置失败。", "Confirmed, but reminder setup failed.", "Disahkan tetapi peringatan gagal.") }
            }
        } catch { message = error.localizedDescription }
    }
    private func prepareExpense() {
        guard let cents = session.paidCents, session.expenseID == nil else { return }
        var draft = Expense(merchant: session.name.isEmpty ? "Parking" : session.name, cents: cents, date: session.startedAt, category: "交通", source: "手动")
        draft.note = tr("停车费用；请核对付款时间、账户和已有记录。", "Parking fee; verify payment time, account and existing entries.", "Bayaran parkir; semak masa, akaun dan rekod sedia ada.")
        // Use the existing screenshot duplicate-review flow; no ledger entry is created here.
        expenseDraft = draft
    }
    var body: some View {
        Form {
            Section {
                ParkingMapCard(session: session)
            }.listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            Section {
                ParkingTimerDial(session: session)
                ParkingStatus(session: session)
                LabeledContent(tr("开始时间", "Start time", "Masa mula")) {
                    Text(session.startedAt, format: .dateTime.month().day().hour().minute())
                }
                if let end = session.endedAt {
                    Text(tr("已结束", "Ended", "Tamat")); Text(end, style: .time)
                } else {
                    Label(tr("停车计时", "Elapsed parking time", "Masa parkir"), systemImage: "timer")
                    Text(session.startedAt, style: .timer).font(.largeTitle.monospacedDigit())
                }
                Text(session.paidUntil == nil ? tr("缴费待确认", "Payment awaiting confirmation", "Bayaran menunggu pengesahan") : tr("缴费由你确认，未与 TNG 同步", "Payment confirmed by you; not synced with TNG", "Bayaran disahkan oleh anda; tidak disegerak dengan TNG"))
                    .font(.footnote).foregroundStyle(.secondary)
                if let end = session.paidUntil { LabeledContent(tr("已确认的结束时间", "Confirmed end time", "Masa tamat disahkan")) { Text(end, format: .dateTime.month().day().hour().minute()) } }
            }
            Section(tr("我的车位", "My parking spot", "Tempat kereta saya")) {
                TextField(tr("车牌", "Plate", "Plat"), text: $session.plate)
                TextField(tr("停车场或地区", "Car park or area", "Tempat atau kawasan"), text: $session.name)
                TextField(tr("楼层 / 区域 / 车位号", "Floor / zone / bay", "Tingkat / zon / petak"), text: $session.bay)
                if let place = session.place, let lat = place.latitude, let lon = place.longitude {
                    Text(place.name).font(.caption)
                    Button(tr("地图找车", "Find car on map", "Cari kereta pada peta")) {
                        MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon)))
                            .openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
                    }
                }
                Text(tr("定位无法判断楼层；请补充车位号或照片。", "GPS cannot identify the floor. Add a bay number or photo.", "GPS tidak mengenal pasti tingkat. Tambah nombor petak atau foto.")).font(.caption)
                PhotosPicker(selection: $photo, matching: .images) { Label(tr("添加车位照片", "Add parking photo", "Tambah foto parkir"), systemImage: "photo") }.disabled(busy)
                if let data = session.photo, let image = UIImage(data: data) {
                    Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 240)
                    Button(tr("移除照片", "Remove photo", "Buang foto")) { session.photo = nil; save() }
                }
                Button(tr("保存车位资料", "Save parking details", "Simpan butiran parkir"), action: save)
            }
            if session.endedAt == nil {
                Section(tr("缴费与提醒", "Payment and reminder", "Bayaran dan peringatan")) {
                    Link(tr("前往 TNG 停车缴费", "Open TNG parking", "Buka parkir TNG"), destination: URL(string: "https://visit.tngdigital.com.my/StreetParking")!)
                    Text(tr("跳转不会确认付款。请按 TNG 收据核对以下资料。", "Opening TNG does not confirm payment. Check these fields against your receipt.", "Membuka TNG tidak mengesahkan bayaran. Semak medan dengan resit.")) .font(.caption)
                    PhotosPicker(selection: $receipt, matching: .images) { Text(tr("识别付款截图（本机）", "Read payment screenshot (on device)", "Baca tangkap layar bayaran (pada peranti)")) }.disabled(busy)
                    if !receiptText.isEmpty {
                        DisclosureGroup(tr("识别文字 · 请核对", "Recognized text · review", "Teks dikenal pasti · semak")) { Text(receiptText).font(.caption).textSelection(.enabled) }
                        let hints = ParkingReceiptHints(text: receiptText)
                        ForEach(hints.amounts, id: \.self) { value in
                            Button("MYR " + value) { amount = value }
                        }
                        ForEach(hints.endDates, id: \.self) { date in
                            Button { until = date } label: { Text(date, format: .dateTime.year().month().day().hour().minute()) }
                        }
                        ForEach(Array(Set(hints.places)).sorted(), id: \.self) { place in
                            Button(place) { session.name = place }
                        }
                        Text(tr("点选候选资料填入表单，不会自动确认付款。", "Tap a candidate to fill the form; this does not confirm payment.", "Tekan cadangan untuk mengisi borang; bayaran tidak disahkan automatik.")).font(.caption)
                    }
                    DatePicker(tr("已付费至", "Paid until", "Dibayar sehingga"), selection: $until)
                    TextField(tr("累计付款金额 MYR（可选）", "Total paid MYR (optional)", "Jumlah dibayar MYR (pilihan)"), text: $amount).keyboardType(.decimalPad)
                    Text(tr("续费后填写累计金额，并更新到期时间；已记账的消费需要到账本修改。", "After renewal, enter the total paid and new expiry. Update any saved expense in Ledger.", "Selepas lanjutan, isi jumlah bayaran dan tamat baharu. Kemas kini belanja tersimpan dalam Lejar."))
                        .font(.caption).foregroundStyle(.secondary)
                    Picker(tr("提前提醒", "Remind before", "Ingatkan sebelum"), selection: $session.reminderMinutes) {
                        ForEach([5, 10, 15], id: \.self) { Text("\($0) min").tag($0) }
                    }
                    Button(tr("确认已付款并设置提醒", "Confirm payment and set reminder", "Sahkan bayaran dan tetapkan peringatan"), action: confirmPayment)
                        .buttonStyle(ParkingActionStyle()).disabled(busy)
                }
            }
            if session.endedAt != nil && session.expenseID == nil {
                Section(tr("补录停车费用", "Add final parking fee", "Tambah bayaran akhir parkir")) {
                    TextField(tr("累计付款金额 MYR", "Total paid MYR", "Jumlah dibayar MYR"), text: $amount).keyboardType(.decimalPad)
                    Button(tr("保存费用", "Save fee", "Simpan bayaran")) {
                        do {
                            let cents = try toCents(amount)
                            guard cents > 0 else { throw LedgerError.invalid(tr("金额必须大于零", "Amount must be positive", "Amaun mesti positif")) }
                            var updated = session; updated.paidCents = cents
                            try store.save(updated); session = updated
                        } catch { message = error.localizedDescription }
                    }
                }
            }
            Section {
                if let id = session.expenseID {
                    Text(model.ledger.expenses.contains(where: { $0.id == id }) ? tr("已保存到账本", "Saved to ledger", "Disimpan dalam lejar") : tr("曾保存到账本，原记录已不在当前账本中。", "Previously saved; the entry is no longer in this ledger.", "Pernah disimpan; rekod tiada lagi dalam lejar ini."))
                } else if session.paidCents != nil {
                    Button(tr("核对并记账", "Review and record expense", "Semak dan rekod belanja"), action: prepareExpense)
                }
                if session.endedAt == nil {
                    Button(tr("结束停车", "End parking", "Tamatkan parkir")) { ending = true }.disabled(busy)
                }
                Button(tr("删除停车记录", "Delete parking record", "Padam rekod parkir"), role: .destructive) { deleting = true }.disabled(busy)
                if busy { ProgressView() }
                if !message.isEmpty { Text(message).font(.footnote) }
            }
        }.navigationTitle(tr("停车详情", "Parking details", "Butiran parkir"))
        .tint(parkingAccent).navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !initialized else { return }; initialized = true
            until = session.paidUntil ?? Date().addingTimeInterval(3600)
            amount = session.paidCents.map { Currency.input($0, "MYR") } ?? ""
        }
        .confirmationDialog(tr("确认结束停车？", "End this parking session?", "Tamatkan sesi parkir ini?"), isPresented: $ending, titleVisibility: .visible) {
            Button(tr("结束停车", "End parking", "Tamatkan parkir")) {
                var updated = session; updated.endedAt = Date()
                do { try store.save(updated); session = updated; store.cancelReminder(updated) }
                catch { message = error.localizedDescription }
            }
        } message: {
            Text(tr("停止本机计时和提醒，不会取消或退款 TNG 的停车付款。", "Stops this timer and reminder. It does not cancel or refund parking in TNG.", "Menghentikan pemasa dan peringatan ini. Tidak membatalkan atau memulangkan bayaran TNG."))
        }
        .task(id: photo) {
            guard let photo else { return }; busy = true; defer { busy = false }
            do {
                guard let data = try await photo.loadTransferable(type: Data.self), data.count <= 20_000_000,
                      let image = UIImage(data: data) else { throw CloudFailure.invalidResponse }
                let scale = min(1, 1200 / max(image.size.width, image.size.height))
                let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                let format = UIGraphicsImageRendererFormat(); format.scale = 1
                let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
                try Task.checkCancellation()
                session.photo = resized.jpegData(compressionQuality: 0.7); save()
            } catch is CancellationError { } catch { message = tr("无法读取照片", "Unable to read photo", "Tidak dapat membaca foto") }
        }
        .task(id: receipt) {
            guard let receipt else { return }; busy = true; defer { busy = false }
            do {
                guard let data = try await receipt.loadTransferable(type: Data.self), data.count <= 20_000_000 else { throw CloudFailure.invalidResponse }
                let text = try await ReceiptOCR.read(data); try Task.checkCancellation()
                receiptText = String(text.prefix(12000))
                message = tr("请从识别文字核对地点、金额及完整日期时间，再确认付款。模糊资料不会自动填写。", "Review place, amount and full date/time from the recognized text before confirming. Ambiguous details are not filled automatically.", "Semak tempat, amaun dan tarikh/masa penuh daripada teks sebelum mengesahkan. Butiran kabur tidak diisi automatik.")
            } catch is CancellationError { } catch { message = tr("截图识别失败，请手动填写", "Screenshot recognition failed; enter details manually", "Pengecaman gagal; isi butiran sendiri") }
        }
        .sheet(item: $expenseDraft) { draft in
            ExpenseEditor(original: nil, initialDraft: draft, reviewDuplicates: true, onSaved: {
                session.expenseID = draft.id; save()
            })
        }
        .alert(tr("删除停车记录？", "Delete parking record?", "Padam rekod parkir?"), isPresented: $deleting) {
            Button(tr("删除", "Delete", "Padam"), role: .destructive) {
                do { try store.delete(session); dismiss() } catch { message = error.localizedDescription }
            }
            Button(tr("取消", "Cancel", "Batal"), role: .cancel) {}
        } message: { Text(tr("会移除照片和提醒，账本中的消费不会删除。", "Removes the photo and reminder, but keeps ledger expenses.", "Memadam foto dan peringatan tetapi mengekalkan belanja lejar.")) }
    }
}
