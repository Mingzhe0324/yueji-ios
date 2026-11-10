import SwiftUI
import PhotosUI
import MapKit
import UserNotifications
import CryptoKit
import SceneKit

private let parkingAccent = Color(red: 0.12, green: 0.65, blue: 0.39)

/// Local, generic body-style models; never a claimed replica of a brand/model.
private struct ParkingVehicleModel: View {
    let vehicle: ParkingVehicle
    @State private var interactive = false
    private func scene() -> SCNScene {
        let scene = SCNScene()
        scene.background.contents = UIColor(white: 0.94, alpha: 1)
        let mpv = vehicle.displayBody == "mpv"
        let suv = vehicle.displayBody == "suv"
        let pickup = vehicle.displayBody == "pickup"
        let coupe = vehicle.displayBody == "coupe"
        let sedan = vehicle.displayBody == "sedan" || coupe
        let length: CGFloat = pickup ? 5.2 : mpv ? 4.8 : (sedan ? 4.6 : (suv ? 4.4 : 3.8))
        let roof: CGFloat = pickup ? 1.85 : coupe ? 1.35 : mpv ? 1.95 : (suv ? 1.85 : 1.5)
        let paint = UIColor(vehicle.tint)
        func material(_ color: UIColor, metal: CGFloat = 0) -> SCNMaterial {
            let m = SCNMaterial(); m.diffuse.contents = color
            m.lightingModel = .physicallyBased; m.metalness.contents = metal; m.roughness.contents = 0.3
            return m
        }
        func box(_ w: CGFloat, _ h: CGFloat, _ d: CGFloat, _ x: CGFloat, _ y: CGFloat, _ z: CGFloat, _ color: UIColor) {
            let g = SCNBox(width: w, height: h, length: d, chamferRadius: min(0.1, h / 3))
            g.materials = [material(color, metal: color == paint ? 0.45 : 0)]
            let n = SCNNode(geometry: g); n.position = SCNVector3(Float(x), Float(y), Float(z))
            scene.rootNode.addChildNode(n)
        }
        box(length, 0.65, 1.75, 0, 0.75, 0, paint)
        if pickup {
            box(1.8, 0.1, 1.45, 1.55, 1.1, 0, .darkGray)
            box(1.8, 0.35, 0.12, 1.55, 1.22, -0.8, paint)
            box(1.8, 0.35, 0.12, 1.55, 1.22, 0.8, paint)
            box(0.12, 0.35, 1.6, 2.5, 1.22, 0, paint)
        }
        let front: CGFloat = mpv ? -1.65 : -0.9
        let rear: CGFloat = pickup ? 0.2 : sedan ? 0.85 : length / 2 - 0.25
        let path = UIBezierPath()
        path.move(to: CGPoint(x: front - 0.35, y: 1.02))
        path.addLine(to: CGPoint(x: front + 0.35, y: roof))
        path.addLine(to: CGPoint(x: rear - 0.2, y: roof))
        path.addLine(to: CGPoint(x: rear + 0.2, y: 1.02))
        path.close()
        let cabin = SCNShape(path: path, extrusionDepth: 1.5)
        cabin.chamferRadius = 0.08; cabin.materials = [material(UIColor(red: 0.13, green: 0.2, blue: 0.24, alpha: 1), metal: 0.3)]
        scene.rootNode.addChildNode(SCNNode(geometry: cabin))
        box(rear - front - 0.45, 0.10, 1.48, (front + rear + 0.15) / 2, roof, 0, paint)
        for side in [-1, 1] as [CGFloat] {
            for x in [-length * 0.31, length * 0.31] {
                let tire = SCNCylinder(radius: 0.39, height: 0.25)
                tire.materials = [material(.init(white: 0.08, alpha: 1))]
                let wheel = SCNNode(geometry: tire)
                wheel.eulerAngles.x = .pi / 2
                wheel.position = SCNVector3(Float(x), 0.42, Float(side * 0.85))
                scene.rootNode.addChildNode(wheel)
                let hub = SCNCylinder(radius: 0.25, height: 0.265)
                hub.materials = [material(.lightGray, metal: 0.8)]
                let rim = SCNNode(geometry: hub); wheel.addChildNode(rim)
            }
            box(0.09, roof - 1.08, 0.06, (front + rear) / 2, (roof + 1.08) / 2, side * 0.77, paint)
            box(0.26, 0.04, 0.04, 0.5, 0.98, side * 0.89, .lightGray)
            box(0.22, 0.15, 0.24, front + 0.1, 1.15, side * 0.95, paint)
            box(0.06, 0.16, 0.45, -length / 2, 0.88, side * 0.56, .white)
            box(0.06, 0.16, 0.38, length / 2, 0.88, side * 0.58, .systemRed)
        }
        box(0.06, 0.23, 0.85, -length / 2 - 0.01, 0.6, 0, .darkGray)
        box(6, 0.08, 3.2, 0, -0.03, 0, UIColor(white: 0.88, alpha: 1))
        let camera = SCNNode(); camera.camera = SCNCamera()
        camera.camera?.usesOrthographicProjection = true; camera.camera?.orthographicScale = 3.25
        camera.position = SCNVector3(-6, 3.5, 6)
        camera.look(at: SCNVector3(0, 0.8, 0)); scene.rootNode.addChildNode(camera)
        let light = SCNNode(); light.light = SCNLight(); light.light?.type = .omni
        light.light?.intensity = 1300; light.position = SCNVector3(-3, 6, 5)
        scene.rootNode.addChildNode(light)
        let ambient = SCNNode(); ambient.light = SCNLight(); ambient.light?.type = .ambient
        ambient.light?.intensity = 450; scene.rootNode.addChildNode(ambient)
        return scene
    }
    var body: some View {
        SceneView(scene: scene(), options: interactive ? [.allowsCameraControl] : [])
            .allowsHitTesting(interactive)
            .overlay(alignment: .bottomTrailing) {
                Button { interactive.toggle() } label: {
                    Label(interactive ? tr("完成", "Done", "Selesai") : tr("旋转 3D", "Rotate 3D", "Putar 3D"), systemImage: "rotate.3d")
                        .font(.caption).padding(8).background(.regularMaterial, in: Capsule())
                }.padding(8)
            }
    }
}

struct ParkingVehicle: Codable, Equatable {
    var brand = ""
    var model = ""
    var year = ""
    var color = "silver"
    var body = "hatchback"
    var photo: Data?
    var bodyOverride: String?
    var displayBody: String { bodyOverride ?? VehicleChoices.bodyType(brand: brand, model: model) ?? body }
    var title: String { [brand, model, year].filter { !$0.isEmpty }.joined(separator: " · ") }
    var tint: Color {
        switch color {
        case "white": return .white
        case "black": return Color(white: 0.15)
        case "red": return .red
        case "blue": return .blue
        case "green": return .green
        case "grey": return Color(white: 0.4)
        case "pearl": return Color(red: 0.96, green: 0.94, blue: 0.87)
        case "navy": return Color(red: 0.12, green: 0.2, blue: 0.4)
        case "teal": return .teal
        case "yellow": return .yellow
        case "orange": return .orange
        case "brown": return .brown
        case "beige": return Color(red: 0.8, green: 0.73, blue: 0.6)
        case "gold": return Color(red: 0.77, green: 0.61, blue: 0.3)
        case "purple": return .purple
        case "pink": return .pink
        case "maroon": return Color(red: 0.5, green: 0.1, blue: 0.2)
        case "bronze": return Color(red: 0.6, green: 0.4, blue: 0.25)
        default: return .gray
        }
    }
}

private struct ParkingActionStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline)
            .frame(maxWidth: .infinity, minHeight: 52)
            .foregroundStyle(.white)
            .background(parkingAccent, in: Capsule())
            .opacity(configuration.isPressed ? 0.75 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: configuration.isPressed)
    }
}

private struct ParkingPaymentReturn: ViewModifier {
    @ObservedObject var store: ParkingStore
    let sessionID: String?
    var enabled = true
    let review: () -> Void
    @Environment(\.scenePhase) private var scenePhase
    @State private var asking = false
    private func check() {
        asking = enabled && store.sessions.contains { $0.id == sessionID && $0.endedAt == nil && $0.awaitingPaymentReview == true }
    }
    private func clear() {
        guard var session = store.sessions.first(where: { $0.id == sessionID }) else { return }
        session.awaitingPaymentReview = false
        try? store.save(session)
    }
    func body(content: Content) -> some View {
        content.onAppear { check() }
            .onChange(of: sessionID) { _, _ in check() }
            .onChange(of: scenePhase) { _, phase in if phase == .active { check() } }
            .confirmationDialog(tr("已在 TNG 完成付款？", "Did you pay in TNG?", "Sudah bayar dalam TNG?"), isPresented: $asking, titleVisibility: .visible) {
                Button(tr("已付款，核对资料", "Paid — review details", "Sudah bayar — semak butiran")) { clear(); review() }
                Button(tr("还没付款", "Not paid yet", "Belum bayar"), role: .cancel) { clear() }
            } message: {
                Text(tr("请核对收据金额与到期时间，确认后再记账。", "Check the receipt amount and expiry before recording the expense.", "Semak amaun resit dan masa tamat sebelum merekod belanja."))
            }
    }
}

/// The map represents only a recorded coordinate, never available parking spaces.
private struct ParkingMapCard: View {
    let session: ParkingSession?
    var vehicle: ParkingVehicle? = nil
    private var shownVehicle: ParkingVehicle? { session?.vehicle ?? vehicle }
    var body: some View {
        VStack(spacing: 0) {
            if let place = session?.place, let latitude = place.latitude, let longitude = place.longitude {
                let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
                Map(initialPosition: .region(MKCoordinateRegion(center: coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.004, longitudeDelta: 0.004))), interactionModes: [.pan, .zoom]) {
                    Marker(session?.name.isEmpty == false ? session!.name : place.name, systemImage: "parkingsign", coordinate: coordinate).tint(parkingAccent)
                }
                .id("\(latitude),\(longitude)")
                .frame(height: 190)
                .accessibilityLabel(tr("停车位置地图", "Parking location map", "Peta lokasi parkir"))
            }
            VStack(alignment: .leading, spacing: 14) {
                Group {
                    if let data = shownVehicle?.photo, let image = UIImage(data: data) {
                        Image(uiImage: image).resizable().scaledToFit()
                    } else {
                        ParkingVehicleModel(vehicle: shownVehicle ?? ParkingVehicle())
                    }
                }.frame(maxWidth: .infinity).frame(height: 170)
                    .background(Color(white: 0.94), in: RoundedRectangle(cornerRadius: 20))
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .accessibilityLabel(shownVehicle?.photo == nil ? tr("车身类型示意图", "Body-style illustration", "Ilustrasi jenis badan") : tr("我的车辆照片", "My vehicle photo", "Foto kenderaan saya"))
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(shownVehicle?.title.isEmpty == false ? shownVehicle!.title : tr("我的车辆", "My vehicle", "Kenderaan saya"))
                            .font(.title3.bold())
                        if let plate = session?.plate, !plate.isEmpty {
                            Text(plate).font(.subheadline.monospaced().weight(.semibold)).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Image(systemName: "car.side.fill").foregroundStyle(parkingAccent).padding(12)
                        .background(parkingAccent.opacity(0.1), in: Circle())
                }
                if let name = session?.name, !name.isEmpty {
                    Label(name, systemImage: "mappin.and.ellipse").font(.subheadline).foregroundStyle(.secondary)
                }
                if shownVehicle?.photo == nil {
                    Text(tr("车身类型示意图", "Body-style illustration", "Ilustrasi jenis badan")).font(.caption2).foregroundStyle(.secondary)
                }
                if let vehicle = shownVehicle {
                    HStack(spacing: 8) {
                        Circle().fill(vehicle.tint).frame(width: 16, height: 16).overlay(Circle().stroke(.gray.opacity(0.5)))
                        Text(VehicleChoices.colourName(vehicle.color)).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }.padding(18)
        }.background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 28))
            .clipShape(RoundedRectangle(cornerRadius: 28))
            .shadow(color: .black.opacity(0.04), radius: 12, y: 5)
    }
}

private struct ParkingTimerDial: View {
    let session: ParkingSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.5), value: fraction)
                }
                VStack(spacing: 10) {
                    Image(systemName: session.endedAt == nil ? "hourglass" : "checkmark")
                        .font(.title2).foregroundStyle(parkingAccent)
                    let minutes = session.durationMinutes(now: context.date)
                    Text("\(minutes / 60) h \(minutes % 60) min").font(.title.bold().monospacedDigit())
                        .contentTransition(.numericText())
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: minutes)
                    Text(session.endedAt == nil ? tr("已停时长", "Time parked", "Tempoh parkir") : tr("总停车时长", "Total parking time", "Jumlah tempoh parkir"))
                        .font(.caption).foregroundStyle(.secondary)
                    if session.endedAt == nil, let end = session.paidUntil {
                        let remaining = max(0, Int(ceil(end.timeIntervalSince(context.date) / 60)))
                        Text(remaining > 0 ? tr("剩余", "Remaining", "Baki") + " \(remaining) min" : tr("已到期", "Expired", "Tamat"))
                            .font(.headline).foregroundStyle(parkingAccent)
                    }
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
    var renewalExpenseIDs: [String]?
    var floor: String?
    var zone: String?
    var awaitingPaymentReview: Bool?
    var spotLabel: String { [floor ?? "", zone ?? "", bay].filter { !$0.isEmpty }.joined(separator: " · ") }
    var ledgerIDs: [String] { (expenseID.map { [$0] } ?? []) + (renewalExpenseIDs ?? []) }
    func renewalDifference(expenses: [Expense]) -> Int? {
        guard !ledgerIDs.isEmpty, Set(ledgerIDs).count == ledgerIDs.count, let total = paidCents else { return nil }
        let linked = expenses.filter { ledgerIDs.contains($0.id) }
        guard linked.count == ledgerIDs.count else { return nil }
        let difference = total - linked.reduce(0) { $0 + $1.cents }
        return difference > 0 ? difference : nil
    }
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var locatedAt: Date?
    @State private var automaticName = ""
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
    @State private var addingVehicle = false
    private var active: ParkingSession? { store.sessions.first { $0.endedAt == nil } }
    private var previewSession: ParkingSession {
        var value = ParkingSession()
        value.plate = plate; value.name = name; value.bay = bay
        value.vehicle = store.vehicle(for: plate); value.place = locator.result
        return value
    }
    private var savedPlates: [String] {
        store.rememberedPlates
    }
    private var history: [ParkingSession] {
        store.sessions.filter { $0.endedAt != nil && (search.isEmpty ||
            ($0.name + " " + $0.plate + " " + $0.bay).localizedCaseInsensitiveContains(search)) }
    }
    init(scope: String) { _store = StateObject(wrappedValue: ParkingStore(scope: scope)) }
    private func launchTNG() {
        guard var session = active else { return }
        session.awaitingPaymentReview = true
        do { try store.save(session) } catch { self.error = error.localizedDescription; return }
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
            if let locatedAt, Date().timeIntervalSince(locatedAt) < 60 { session.place = locator.result }
            if session.place == nil && session.name == automaticName { session.name = "" }
            try store.save(session)
            startingID = session.id; goToTNG = tng; error = ""
            if session.place != nil { finishLocation() }
            else { locator.start(automatic: true) }
        } catch { self.error = error.localizedDescription }
    }
    private func finishLocation() {
        guard let id = startingID else { return }
        startingID = nil
        if var session = store.sessions.first(where: { $0.id == id }) {
            session.place = locator.result
            if session.name.isEmpty || session.name == automaticName { session.name = locator.result?.name ?? session.name }
            do { try store.save(session) } catch { self.error = error.localizedDescription }
        }
        if goToTNG { goToTNG = false; launchTNG() }
        else { openedSession = store.sessions.first { $0.id == id } }
    }
    private var homeContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(active == nil ? tr("轻松停好，安心出发", "Park easy. Go freely.", "Parkir mudah. Teruskan perjalanan.") : tr("你的车，就在这里", "Your car is right here", "Kereta anda di sini"))
                            .font(.title2.bold())
                        Text(active == nil ? tr("选好车辆，位置自动填入", "Choose your car. Location fills itself.", "Pilih kereta. Lokasi diisi automatik.") : tr("计时、找车、缴费，一目了然", "Time, location and payment at a glance", "Masa, lokasi dan bayaran sepintas lalu"))
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "parkingsign").font(.title2.bold()).foregroundStyle(.white)
                        .frame(width: 48, height: 48).background(parkingAccent, in: RoundedRectangle(cornerRadius: 16))
                }
                if let session = active {
                    VStack(spacing: 16) {
                        HStack {
                            Label(tr("正在停车", "PARKED", "SEDANG PARKIR"), systemImage: "parkingsign.circle.fill")
                                .font(.caption.weight(.bold)).foregroundStyle(parkingAccent)
                            Spacer()
                            Text(session.name.isEmpty ? tr("我的车位", "My parking spot", "Tempat kereta saya") : session.name)
                                .font(.subheadline.weight(.medium)).lineLimit(2)
                        }
                        ParkingTimerDial(session: session)
                        HStack {
                            Label(session.plate.isEmpty ? tr("我的车辆", "My car", "Kereta saya") : session.plate, systemImage: "car.side")
                            Spacer()
                            Text(session.paidCents.map { money($0) } ?? tr("待确认付款", "Payment unconfirmed", "Bayaran belum disahkan"))
                        }.font(.subheadline.weight(.medium))
                        if !session.spotLabel.isEmpty { Text(session.spotLabel).font(.headline) }
                        HStack(spacing: 12) {
                            if let place = session.place, let lat = place.latitude, let lon = place.longitude {
                                Button {
                                    MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon)))
                                        .openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
                                } label: { Label(tr("找车", "Find car", "Cari kereta"), systemImage: "location.fill") }
                            }
                            Spacer()
                            Button(action: launchTNG) { Label(tr("缴费 / 续费", "Pay / renew", "Bayar / lanjut"), systemImage: "creditcard") }
                        }.buttonStyle(.bordered).tint(parkingAccent).disabled(startingID != nil)
                        Button { openedSession = session } label: {
                            Label(tr("查看车位 · 结束停车", "Parking details · Finish", "Butiran parkir · Tamat"), systemImage: "arrow.right.circle.fill")
                        }.buttonStyle(ParkingActionStyle()).disabled(startingID != nil)
                    }.padding(24)
                        .background(LinearGradient(colors: [parkingAccent.opacity(0.16), Color(uiColor: .secondarySystemGroupedBackground)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 28))
                        .overlay(RoundedRectangle(cornerRadius: 28).stroke(parkingAccent.opacity(0.2)))
                } else {
                    VStack(alignment: .leading, spacing: 16) {
                        Label(tr("第一步 · 选好这次开的车", "1 · Choose your car", "1 · Pilih kereta anda"), systemImage: "checkmark.circle.fill")
                            .font(.caption.weight(.bold)).foregroundStyle(parkingAccent)
                        HStack {
                            Label(tr("我的车辆", "My vehicle", "Kenderaan saya"), systemImage: "car.side.fill").font(.headline)
                            Spacer()
                            if !savedPlates.isEmpty {
                                Menu(tr("换车", "Switch", "Tukar")) {
                                    ForEach(savedPlates, id: \.self) { value in Button(value) { plate = value } }
                                }
                            }
                        }
                        HStack {
                            TextField(tr("输入车牌，自动记住", "Plate — remembered automatically", "Plat — diingati automatik"), text: $plate)
                                .textInputAutocapitalization(.characters).autocorrectionDisabled().font(.title3.bold())
                                .onSubmit { store.rememberPlate(plate) }
                            Button { store.rememberPlate(plate); addingVehicle = false; editingVehicle = true } label: {
                                Image(systemName: "slider.horizontal.3").padding(10).background(.quaternary, in: Circle())
                            }.accessibilityLabel(tr("编辑车辆和照片", "Edit vehicle and photo", "Ubah kenderaan dan foto"))
                                .disabled(ParkingStore.plateKey(plate).isEmpty)
                        }
                        Button {
                            addingVehicle = true; editingVehicle = true
                        } label: {
                            Label(tr("添加车辆", "Add vehicle", "Tambah kenderaan"), systemImage: "plus.circle.fill")
                        }.buttonStyle(.bordered)
                        Divider()
                        Label(tr("第二步 · 确认停在哪里", "2 · Confirm the location", "2 · Sahkan lokasi"), systemImage: "mappin.circle.fill")
                            .font(.caption.weight(.bold)).foregroundStyle(parkingAccent)
                        HStack(alignment: .top) {
                            Image(systemName: "location.fill").foregroundStyle(parkingAccent)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(name.isEmpty ? (locator.busy ? tr("正在查找位置", "Finding your location", "Mencari lokasi anda") : tr("暂未获取位置", "Location not available", "Lokasi belum tersedia")) : name).font(.headline)
                                Text(locator.result == nil ? tr("可重试定位，也可直接开始", "Retry location or start now", "Cuba lokasi lagi atau mula sekarang") : tr("自动定位附近地址，可修改", "Nearby address detected; editable", "Alamat berdekatan dikesan; boleh diubah"))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if locator.busy { ProgressView() }
                            else { Button { name = ""; locator.start(automatic: true) } label: { Image(systemName: "arrow.clockwise") }.accessibilityLabel(tr("重新定位", "Refresh location", "Segarkan lokasi")) }
                        }
                        DisclosureGroup(tr("修改位置 / 补充车位（可选）", "Edit location / add bay (optional)", "Ubah lokasi / tambah petak (pilihan)")) {
                            VStack(spacing: 12) {
                                if let last = store.sessions.first(where: { $0.endedAt != nil && !$0.name.isEmpty && $0.plate == plate }) {
                                    Button(tr("沿用上次停车地点：", "Use previous parking place: ", "Guna tempat parkir terdahulu: ") + last.name) {
                                        name = last.name
                                        // A bay can change on every visit; never silently reuse it.
                                        bay = ""
                                    }
                                }
                                TextField(tr("停车场或地区", "Car park or area", "Tempat atau kawasan"), text: $name)
                                TextField(tr("楼层 / 区域 / 车位号", "Floor / zone / bay", "Tingkat / zon / petak"), text: $bay)
                                Text(tr("楼层和车位号可稍后补充。", "Add floor and bay later if needed.", "Tambah tingkat dan petak kemudian jika perlu.")).font(.caption).foregroundStyle(.secondary)
                            }.padding(.top, 10)
                        }.font(.subheadline)
                    }.padding(20).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 28))
                }
                if startingID != nil {
                    VStack(spacing: 10) {
                        ProgressView(tr("正在保存位置…", "Saving location…", "Menyimpan lokasi…"))
                        Button(tr("跳过定位，继续", "Skip location and continue", "Langkau lokasi dan teruskan")) { locator.cancel(); finishLocation() }
                    }.frame(maxWidth: .infinity)
                }
                DisclosureGroup(tr("查看车辆与地图", "Car & map", "Kereta dan peta")) {
                    ParkingMapCard(session: active ?? previewSession).padding(.top, 12)
                }.padding(18).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
                if let message = locator.message { Text(message).font(.caption).foregroundStyle(.secondary) }
                if !error.isEmpty { Text(error).font(.footnote).foregroundStyle(.red) }
                DisclosureGroup(tr("停车历史", "Parking history", "Sejarah parkir")) {
                    VStack(alignment: .leading, spacing: 16) {
                        TextField(tr("搜索地点、车牌或车位", "Search place, plate or bay", "Cari tempat, plat atau petak"), text: $search)
                        if history.isEmpty { Text(tr("暂无停车记录", "No parking history yet", "Belum ada sejarah parkir")).foregroundStyle(.secondary) }
                        ForEach(history) { session in
                            NavigationLink { ParkingDetail(store: store, session: session) } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(session.name.isEmpty ? tr("停车", "Parking", "Parkir") : session.name).font(.headline)
                                        Text(session.startedAt, style: .date).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(session.paidCents.map { money($0) } ?? "—")
                                    Image(systemName: "chevron.right").font(.caption)
                                }
                            }.disabled(startingID != nil)
                        }
                    }.padding(.top, 16)
                }.padding(20).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
                Text(tr("停车资料仅保存在此设备；付款后请返回核对。", "Parking details stay on this device. Return after paying to review.", "Butiran parkir kekal pada peranti ini. Kembali selepas bayar untuk semakan."))
                    .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
            }.padding(20)
        }.background(Color(uiColor: .systemGroupedBackground))
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: active?.id)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: plate)
    }

    var body: some View {
        homeContent.tint(parkingAccent)
        .safeAreaInset(edge: .bottom) {
            if active == nil {
                VStack(spacing: 10) {
                    Button(tr("停好了 · 去 TNG 缴费", "Parked · Pay in TNG", "Sudah parkir · Bayar di TNG")) { start(tng: true) }
                        .buttonStyle(ParkingActionStyle()).disabled(!ready)
                    Button(tr("不用缴费，只帮我记住车位", "Just remember my spot", "Simpan tempat kereta sahaja")) { start(tng: false) }
                        .font(.subheadline).disabled(!ready)
                }.padding(.horizontal, 20).padding(.vertical, 12).background(.regularMaterial)
            }
        }
        .modifier(ParkingPaymentReturn(store: store, sessionID: active?.id, enabled: openedSession == nil, review: {
            openedSession = active
        }))
        .sheet(isPresented: $editingVehicle) {
            ParkingVehicleEditor(store: store, plate: addingVehicle ? "" : plate,
                vehicle: addingVehicle ? ParkingVehicle() : (store.vehicle(for: plate) ?? ParkingVehicle()),
                adding: addingVehicle, onSaved: { plate = $0 })
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: Binding(get: { openedSession != nil }, set: { if !$0 { openedSession = nil } })) {
            if let session = openedSession { ParkingDetail(store: store, session: session) }
        }
        .task {
            do {
                try store.load(); if plate.isEmpty { plate = savedPlates.first ?? "" }; ready = true
                if active == nil && locator.result == nil && !locator.busy { locator.start(automatic: true) }
            }
            catch { self.error = error.localizedDescription }
        }
        .onChange(of: locator.result) { _, result in
            guard let result else { return }
            locatedAt = Date()
            if name.isEmpty || name == automaticName { name = result.name; automaticName = result.name }
            finishLocation()
        }
        .onChange(of: locator.message) { _, message in if message != nil { finishLocation() } }
        .onDisappear {
            store.rememberPlate(plate)
            locator.cancel(); startingID = nil; goToTNG = false
        }
    }
}

private enum VehicleChoices {
    static func bodyType(brand: String, model: String) -> String? {
        let local: [String: [String: String]] = [
            "Perodua": ["Myvi":"hatchback", "Axia":"hatchback", "Bezza":"sedan", "Ativa":"suv", "Alza":"mpv", "Aruz":"suv", "Viva":"hatchback", "Kancil":"hatchback", "Kelisa":"hatchback", "Kenari":"hatchback", "Kembara":"suv", "Nautica":"suv", "Rusa":"mpv"],
            "Proton": ["Saga":"sedan", "Persona":"sedan", "Iriz":"hatchback", "S70":"sedan", "X50":"suv", "X70":"suv", "X90":"suv", "e.MAS 7":"suv", "Exora":"mpv", "Preve":"sedan", "Suprima S":"hatchback", "Inspira":"sedan", "Waja":"sedan", "Satria":"hatchback", "Putra":"coupe", "Perdana":"sedan", "Gen-2":"hatchback", "Savvy":"hatchback"]
        ]
        if let body = local[brand]?[model] { return body }
        let groups: [(String, String)] = [
            ("pickup", "Hilux|Triton|Navara|D-Max|Ranger|BT-50|F-150|Silverado|Cybertruck|Cannon|Gladiator|R1T|T60|T90|T8|T9"),
            ("mpv", "Alphard|Vellfire|Veloz|Avanza|Innova|Innova Zenix|Hiace|Wish|Estima|Sienta|Odyssey|Freed|Stream|Stepwgn|Serena|Livina|Xpander|Grandis|Ertiga|Biante|Carnival|Staria|Starex|V-Class|Vito|Touran|Sharan|Traveller|M6|D9|009|X9|MIFA 9|G10|G50"),
            ("suv", "HR-V|CR-V|WR-V|BR-V|ZR-V|Corolla Cross|Fortuner|Harrier|RAV4|Land Cruiser|C-HR|bZ4X|X-Trail|Kicks|Juke|Qashqai|Patrol|CX-3|CX-30|CX-5|CX-8|CX-9|CX-60|CX-80|CX-90|ASX|Outlander|Pajero|Pajero Sport|Eclipse Cross|Jimny|Vitara|S-Cross|XV|Crosstrek|Forester|Outback|MU-X|Terios|Rocky|UX|NX|RX|GX|LX|LBX|RZ|X1|X2|X3|X4|X5|X6|X7|iX|iX1|iX3|GLA|GLB|GLC|GLE|GLS|G-Class|EQA|EQB|EQC|Q2|Q3|Q5|Q7|Q8|Tiguan|Touareg|T-Cross|T-Roc|Countryman|XC40|XC60|XC90|EX30|EX90|2008|3008|5008|Koleos|Kona|Tucson|Santa Fe|Palisade|Seltos|Sportage|Sorento|Everest|Model Y|Model X|Atto 3|Sealion 7|Omoda 5|Tiggo 7 Pro|Tiggo 8 Pro|J7|J8|Haval H6|Haval Jolion|Tank 300|Tank 500|Cayenne|Macan|Defender|Discovery|Range Rover|Urus"),
            ("hatchback", "Yaris|Jazz|Fit|Swift|Alto|March|Note|Leaf|Mirage|Mazda2|Polo|Golf|Picanto|Rio|i10|i20|i30|Fiesta|Focus|Dolphin|MG4|Ora Good Cat|Cooper|500|Clio|208|308|C3|C4"),
            ("sedan", "Vios|Camry|Altis|City|Accord|Almera|Sylphy|Sentra|Teana|Attrage|ES|LS|IS|Model 3|Model S|Seal|Ora 07|S60|S90|Passat|Jetta|Arteon|Sonata|Elantra|Cerato|Optima|S70"),
            ("coupe", "86|GR86|Supra|MX-5|BRZ|GT-R|370Z|Z|TT|R8|911|718 Cayman|718 Boxster|Z4|LC|RC|F-Type|Mustang|Camaro|Corvette|Artura|Emira")
        ]
        return groups.first { $0.1.components(separatedBy: "|").contains(model) }?.0
    }
    // Includes older models for existing owners; not an assertion of current sales availability.
    static let brands: [(String, String)] = [
        ("Perodua", "Myvi|Axia|Bezza|Ativa|Alza|Aruz|Viva|Kancil|Kelisa|Kenari|Kembara|Nautica|Rusa"),
        ("Proton", "Saga|Persona|Iriz|S70|X50|X70|X90|e.MAS 7|Exora|Preve|Suprima S|Inspira|Waja|Wira|Iswara|Satria|Putra|Perdana|Gen-2|Savvy"),
        ("Toyota", "Vios|Yaris|Corolla|Corolla Cross|Camry|Altis|Avanza|Veloz|Innova|Innova Zenix|Hilux|Fortuner|Harrier|RAV4|Alphard|Vellfire|Hiace|Land Cruiser|Prius|86|GR86|Supra|C-HR|bZ4X|Wish|Estima|Sienta"),
        ("Honda", "City|City Hatchback|Civic|Accord|HR-V|CR-V|WR-V|BR-V|Jazz|Fit|Freed|Odyssey|Stream|Stepwgn|Insight|e|ZR-V"),
        ("Nissan", "Almera|Sylphy|Sentra|Teana|Latio|Livina|Serena|X-Trail|Kicks|Navara|Leaf|March|Note|Juke|Qashqai|Patrol|GT-R|370Z|Z"),
        ("Mazda", "2|3|6|CX-3|CX-30|CX-5|CX-8|CX-9|CX-60|CX-80|CX-90|MX-5|BT-50|Biante"),
        ("Mitsubishi", "Xpander|Triton|ASX|Outlander|Pajero|Pajero Sport|Lancer|Attrage|Mirage|Grandis|Eclipse Cross"),
        ("Suzuki", "Swift|Jimny|Vitara|S-Cross|Ertiga|Alto|Baleno|Ciaz|Ignis|SX4|Kizashi"),
        ("Subaru", "XV|Crosstrek|Forester|Outback|Impreza|WRX|BRZ|Legacy|Levorg|Solterra"),
        ("Isuzu", "D-Max|MU-X|Trooper"),
        ("Daihatsu", "Mira|Move|Tanto|Terios|Rocky|Sirion|Copen|Gran Max|Xenia|Ayla"),
        ("Lexus", "IS|ES|LS|UX|NX|RX|GX|LX|LBX|LM|LC|RC|RZ|CT"),
        ("BMW", "1 Series|2 Series|3 Series|4 Series|5 Series|6 Series|7 Series|8 Series|X1|X2|X3|X4|X5|X6|X7|i3|i4|i5|i7|iX|iX1|iX3|Z4|M2|M3|M4|M5"),
        ("Mercedes-Benz", "A-Class|B-Class|C-Class|E-Class|S-Class|CLA|CLS|GLA|GLB|GLC|GLE|GLS|G-Class|EQA|EQB|EQC|EQE|EQS|V-Class|Vito|SL|SLC|AMG GT"),
        ("Audi", "A1|A3|A4|A5|A6|A7|A8|Q2|Q3|Q5|Q7|Q8|Q4 e-tron|Q8 e-tron|e-tron GT|TT|R8"),
        ("Volkswagen", "Polo|Golf|Jetta|Passat|Arteon|Tiguan|Touareg|T-Cross|T-Roc|Touran|Sharan|Vento|Beetle|ID.3|ID.4|ID.5|ID.7|ID. Buzz"),
        ("MINI", "Cooper|Clubman|Countryman|Aceman"),
        ("Volvo", "S60|S90|V40|V60|V90|XC40|XC60|XC90|C40|EX30|EX90"),
        ("Peugeot", "208|2008|308|3008|408|5008|508|RCZ|Traveller"),
        ("Renault", "Clio|Captur|Megane|Fluence|Koleos|Kadjar|Scenic|Zoe"),
        ("Citroen", "C3|C4|C5|C3 Aircross|C5 Aircross|Berlingo|Grand C4 Picasso"),
        ("Skoda", "Fabia|Octavia|Superb|Kamiq|Karoq|Kodiaq|Enyaq"),
        ("Hyundai", "i10|i20|i30|Accent|Elantra|Sonata|Kona|Tucson|Santa Fe|Palisade|Staria|Starex|Ioniq|Ioniq 5|Ioniq 6"),
        ("Kia", "Picanto|Rio|Cerato|Forte|K3|K5|Optima|Seltos|Sportage|Sorento|Carnival|Niro|Stinger|EV3|EV6|EV9"),
        ("Ford", "Fiesta|Focus|Mondeo|Mustang|Ranger|Everest|Escape|Kuga|Explorer|F-150|Bronco|Transit"),
        ("Chevrolet", "Spark|Aveo|Sonic|Cruze|Malibu|Captiva|Trax|Trailblazer|Equinox|Tahoe|Suburban|Silverado|Camaro|Corvette"),
        ("Tesla", "Model 3|Model Y|Model S|Model X|Cybertruck"),
        ("BYD", "Atto 3|Dolphin|Seal|Sealion 7|M6|Atto 2|Han|Tang|Song Plus|Yuan Plus|Qin Plus"),
        ("Chery", "Omoda 5|Tiggo 7 Pro|Tiggo 8 Pro|Tiggo 4 Pro|Arrizo 5|Arrizo 8"),
        ("Omoda", "C5|E5|C9"), ("Jaecoo", "J7|J8"),
        ("GWM", "Haval H6|Haval Jolion|Ora Good Cat|Ora 07|Tank 300|Tank 500|Cannon"),
        ("Geely", "Coolray|Boyue|Boyue L|Monjaro|Emgrand|Okavango|Geometry C"),
        ("MG", "MG3|MG4|MG5|ZS|HS|Cyberster"),
        ("GAC", "GS3 Emzoom|GS8|M8|Aion Y Plus|Aion ES"),
        ("XPeng", "G6|G9|P7|X9"), ("Zeekr", "001|007|009|X"),
        ("Nio", "ET5|ET7|ES6|ES8|EC6"), ("Leapmotor", "T03|C10|C11|C16"),
        ("smart", "fortwo|forfour|#1|#3|#5"),
        ("Porsche", "911|718 Cayman|718 Boxster|Cayenne|Macan|Panamera|Taycan"),
        ("Land Rover", "Defender|Discovery|Discovery Sport|Range Rover|Range Rover Sport|Range Rover Evoque|Range Rover Velar"),
        ("Jaguar", "XE|XF|XJ|F-Type|F-Pace|E-Pace|I-Pace"),
        ("Jeep", "Wrangler|Grand Cherokee|Cherokee|Compass|Renegade|Gladiator"),
        ("Fiat", "500|Panda|Tipo|Punto|124 Spider"),
        ("Alfa Romeo", "Giulia|Stelvio|Tonale|Giulietta|159|4C"),
        ("Ferrari", "Roma|Portofino|296|SF90|812|F8|488|458|Purosangue"),
        ("Lamborghini", "Huracan|Aventador|Urus|Revuelto|Gallardo"),
        ("Maserati", "Ghibli|Quattroporte|Levante|Grecale|GranTurismo|MC20"),
        ("Bentley", "Continental GT|Flying Spur|Bentayga|Mulsanne"),
        ("Rolls-Royce", "Ghost|Phantom|Cullinan|Wraith|Dawn|Spectre"),
        ("Aston Martin", "DB9|DB11|DB12|Vantage|DBX|DBS"),
        ("McLaren", "570S|600LT|720S|750S|GT|Artura"),
        ("Lotus", "Elise|Exige|Evora|Emira|Eletre|Emeya"),
        ("Infiniti", "Q50|Q60|Q70|QX50|QX60|QX80"),
        ("Acura", "Integra|TLX|RDX|MDX|NSX"), ("Genesis", "G70|G80|G90|GV60|GV70|GV80"),
        ("Polestar", "1|2|3|4"), ("Saab", "9-3|9-5|900|9000"),
        ("SEAT", "Ibiza|Leon|Arona|Ateca|Tarraco"), ("Cupra", "Born|Formentor|Leon|Ateca|Tavascan"),
        ("Dacia", "Sandero|Duster|Logan|Jogger|Spring"),
        ("Tata", "Tiago|Tigor|Nexon|Harrier|Safari|Punch"),
        ("Mahindra", "Scorpio|XUV700|Thar|Bolero|XUV300"),
        ("Changan", "Alsvin|CS35 Plus|CS55 Plus|CS75 Plus|UNI-T|UNI-K"),
        ("Wuling", "Hongguang|Hongguang Mini EV|Air EV|Bingo|Almaz"),
        ("Maxus", "G10|G50|MIFA 9|T60|T90"), ("JAC", "T8|T9|JS4|JS6"),
        ("BAIC", "X55|BJ40|BJ80"), ("Chrysler", "300|Pacifica|Voyager"),
        ("Dodge", "Charger|Challenger|Durango|Journey"), ("Ram", "1500|2500|3500"),
        ("GMC", "Sierra|Yukon|Acadia|Terrain|Hummer EV"),
        ("Cadillac", "CT4|CT5|XT4|XT5|XT6|Escalade|Lyriq"),
        ("Lincoln", "Navigator|Aviator|Corsair|Nautilus"),
        ("Buick", "Encore|Envision|Enclave|LaCrosse"),
        ("Rivian", "R1T|R1S"), ("Lucid", "Air|Gravity"),
        ("VinFast", "VF 3|VF 5|VF 6|VF 7|VF 8|VF 9"),
        ("Denza", "D9|N7|Z9"), ("Hongqi", "H5|H9|HS5|HS7|E-HS9")
    ]
    static func models(_ brand: String) -> [String] {
        brands.first { $0.0 == brand }?.1.components(separatedBy: "|") ?? []
    }
    static let colours = ["silver", "grey", "white", "pearl", "black", "red", "maroon", "blue", "navy", "teal", "green", "yellow", "orange", "brown", "beige", "gold", "bronze", "purple", "pink"]
    static func colourName(_ id: String) -> String {
        switch id {
        case "silver": return tr("银色", "Silver", "Perak")
        case "grey": return tr("灰色", "Grey", "Kelabu")
        case "white": return tr("白色", "White", "Putih")
        case "pearl": return tr("珍珠白", "Pearl white", "Putih mutiara")
        case "black": return tr("黑色", "Black", "Hitam")
        case "red": return tr("红色", "Red", "Merah")
        case "maroon": return tr("酒红色", "Maroon", "Merah hati")
        case "blue": return tr("蓝色", "Blue", "Biru")
        case "navy": return tr("深蓝色", "Navy", "Biru tua")
        case "teal": return tr("蓝绿色", "Teal", "Biru kehijauan")
        case "green": return tr("绿色", "Green", "Hijau")
        case "yellow": return tr("黄色", "Yellow", "Kuning")
        case "orange": return tr("橙色", "Orange", "Jingga")
        case "brown": return tr("棕色", "Brown", "Coklat")
        case "beige": return tr("米色", "Beige", "Beige")
        case "gold": return tr("金色", "Gold", "Emas")
        case "bronze": return tr("铜色", "Bronze", "Gangsa")
        case "purple": return tr("紫色", "Purple", "Ungu")
        case "pink": return tr("粉红色", "Pink", "Merah jambu")
        default: return id
        }
    }
}

private struct VehicleChoiceList: View {
    let title: String
    let choices: [String]
    @Binding var selection: String
    @State private var search = ""
    @Environment(\.dismiss) private var dismiss
    private var matches: [String] {
        let all = selection.isEmpty || choices.contains(selection) ? choices : [selection] + choices
        return search.isEmpty ? all : all.filter { $0.localizedCaseInsensitiveContains(search) }
    }
    var body: some View {
        List {
            ForEach(matches, id: \.self) { value in
                Button {
                    selection = value
                    dismiss()
                } label: {
                    HStack {
                        Text(value).foregroundStyle(.primary)
                        Spacer()
                        if selection == value { Image(systemName: "checkmark").foregroundStyle(parkingAccent) }
                    }
                }
            }
            if matches.isEmpty {
                Text(tr("没有匹配车型，请尝试其他名称", "No match. Try another name.", "Tiada padanan. Cuba nama lain."))
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(title)
        .searchable(text: $search)
    }
}

private struct ParkingVehicleEditor: View {
    @ObservedObject var store: ParkingStore
    let plate: String
    @State var vehicle: ParkingVehicle
    var adding = false
    var onSaved: (String) -> Void = { _ in }
    @State private var newPlate = ""
    @Environment(\.dismiss) private var dismiss
    @State private var error = ""
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var loadingPhoto = false
    var body: some View {
        NavigationStack {
            Form {
                Section(plate) {
                    if adding {
                        TextField(tr("车牌号码", "Plate number", "Nombor plat"), text: $newPlate)
                            .textInputAutocapitalization(.characters).autocorrectionDisabled()
                    }
                    NavigationLink {
                        VehicleChoiceList(title: tr("选择品牌", "Choose brand", "Pilih jenama"), choices: VehicleChoices.brands.map { $0.0 },
                            selection: Binding(get: { vehicle.brand }, set: {
                                if vehicle.brand != $0 { vehicle.brand = $0; vehicle.model = ""; vehicle.bodyOverride = nil }
                            }))
                    } label: {
                        LabeledContent(tr("品牌", "Brand", "Jenama"), value: vehicle.brand.isEmpty ? tr("请选择", "Choose", "Pilih") : vehicle.brand)
                    }
                    NavigationLink {
                        VehicleChoiceList(title: tr("选择车型", "Choose model", "Pilih model"), choices: VehicleChoices.models(vehicle.brand),
                            selection: Binding(get: { vehicle.model }, set: { vehicle.model = $0; vehicle.bodyOverride = nil }))
                    } label: {
                        LabeledContent(tr("车型", "Model", "Model"), value: vehicle.model.isEmpty ? tr("请选择", "Choose", "Pilih") : vehicle.model)
                    }.disabled(vehicle.brand.isEmpty)
                    Picker(tr("年份（可选）", "Year (optional)", "Tahun (pilihan)"), selection: $vehicle.year) {
                        Text(tr("未选择", "Not selected", "Belum dipilih")).tag("")
                        if !vehicle.year.isEmpty, !(1950...Calendar.current.component(.year, from: Date())).contains(Int(vehicle.year) ?? 0) {
                            Text(vehicle.year).tag(vehicle.year)
                        }
                        ForEach((1950...Calendar.current.component(.year, from: Date())).reversed(), id: \.self) { year in
                            Text(String(year)).tag(String(year))
                        }
                    }
                    Picker(tr("车身类型", "Body type", "Jenis badan"), selection: Binding(get: { vehicle.displayBody }, set: { vehicle.body = $0; vehicle.bodyOverride = $0 })) {
                        Text(tr("通用车型（旧设置）", "Generic (legacy)", "Umum (lama)")).tag("car")
                        Text("Hatchback · 掀背车").tag("hatchback")
                        Text("Sedan · 三厢轿车").tag("sedan")
                        Text("SUV").tag("suv")
                        Text("MPV").tag("mpv")
                        Text(tr("皮卡", "Pickup", "Pikap")).tag("pickup")
                        Text(tr("跑车 / 双门轿跑", "Sports / coupe", "Sport / coupe")).tag("coupe")
                    }
                    Text(tr("常见车型会自动匹配；不同年份或版本有差异时，可在这里调整车身类型。", "Common models match automatically. Adjust the body style here for a different year or variant.", "Model biasa dipadankan automatik. Laraskan jenis badan untuk tahun atau varian berbeza."))
                        .font(.caption).foregroundStyle(.secondary)
                    Picker(tr("车身颜色", "Vehicle colour", "Warna kenderaan"), selection: $vehicle.color) {
                        ForEach(VehicleChoices.colours, id: \.self) { colour in
                            Text(VehicleChoices.colourName(colour)).tag(colour)
                        }
                    }
                }
                Section {
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Label(tr("选择自己的车辆照片", "Choose your vehicle photo", "Pilih foto kenderaan sendiri"), systemImage: "photo")
                    }.disabled(loadingPhoto)
                    if vehicle.photo != nil {
                        Button(tr("移除车辆照片", "Remove vehicle photo", "Buang foto kenderaan")) { vehicle.photo = nil; selectedPhoto = nil }
                    }
                    if loadingPhoto { ProgressView() }
                    ParkingMapCard(session: nil, vehicle: vehicle)
                    Text(tr("示意图按车身类型和颜色显示，不是具体车型的精确复刻。上传自己的照片后优先显示照片。", "The illustration follows body style and colour, not an exact model replica. Your own photo takes priority.", "Ilustrasi mengikut jenis badan dan warna, bukan replika model tepat. Foto sendiri diutamakan."))
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
                        let savedPlate = adding ? ParkingStore.plateKey(newPlate) : plate
                        guard !ParkingStore.plateKey(savedPlate).isEmpty else { return }
                        if adding && (store.vehicle(for: savedPlate) != nil || store.rememberedPlates.contains(where: { ParkingStore.plateKey($0) == savedPlate })) {
                            error = tr("此车牌已存在，请通过换车选择。", "This plate already exists. Select it with Switch.", "Plat ini sudah ada. Pilih melalui Tukar.")
                            return
                        }
                        vehicle.brand = String(vehicle.brand.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))
                        vehicle.model = String(vehicle.model.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
                        vehicle.year = String(vehicle.year.filter(\.isNumber).prefix(4))
                        do { try store.saveVehicle(vehicle, plate: savedPlate); onSaved(savedPlate); dismiss() }
                        catch { self.error = error.localizedDescription }
                    }.disabled(loadingPhoto || (adding && ParkingStore.plateKey(newPlate).isEmpty))
                }
            }
            .task(id: selectedPhoto) {
                guard let selectedPhoto else { return }
                loadingPhoto = true; defer { loadingPhoto = false }
                do {
                    guard let data = try await selectedPhoto.loadTransferable(type: Data.self), data.count <= 20_000_000,
                          let image = UIImage(data: data) else { throw CloudFailure.invalidResponse }
                    let scale = min(1, 900 / max(image.size.width, image.size.height))
                    let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                    let format = UIGraphicsImageRendererFormat(); format.scale = 1
                    let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
                    try Task.checkCancellation()
                    vehicle.photo = resized.jpegData(compressionQuality: 0.75)
                } catch is CancellationError {} catch {
                    self.error = tr("无法读取照片", "Unable to read photo", "Tidak dapat membaca foto")
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
    @State private var editingExpense = false
    private var linkedExpenses: [Expense] { model.ledger.expenses.filter { session.ledgerIDs.contains($0.id) } }
    private func launchTNG() {
        session.awaitingPaymentReview = true
        do { try store.save(session) } catch { message = error.localizedDescription; return }
        openURL(URL(string: "https://visit.tngdigital.com.my/StreetParking")!)
    }
    private func prepareRenewal() {
        guard let difference = session.renewalDifference(expenses: model.ledger.expenses) else {
            message = tr("累计费用没有增加，请核对已有账目。", "The total has not increased. Review existing entries.", "Jumlah tidak meningkat. Semak rekod sedia ada."); return
        }
        editingExpense = false
        var draft = Expense(merchant: session.name.isEmpty ? "Parking" : session.name, cents: difference, date: Date(), category: "交通", source: "手动")
        draft.note = tr("停车续费差额；请核对本次付款金额和时间。", "Parking renewal difference; verify this payment amount and time.", "Perbezaan lanjutan parkir; semak amaun dan masa bayaran ini.")
        expenseDraft = draft
    }
    private func save() { do { try store.save(session); message = tr("已保存", "Saved", "Disimpan") } catch { message = error.localizedDescription } }
    private func confirmPayment() {
        guard until > Date(), until > session.startedAt else { message = tr("请选择未来的结束时间", "Choose a future end time", "Pilih masa tamat akan datang"); return }
        do {
            let cents: Int? = amount.isEmpty ? nil : try toCents(amount)
            if let cents, cents <= 0 { throw LedgerError.invalid(tr("金额必须大于零", "Amount must be positive", "Amaun mesti positif")) }
            var updated = session; updated.paidUntil = until; updated.paidCents = cents; updated.awaitingPaymentReview = false
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
        editingExpense = false
        expenseDraft = draft
    }
    var body: some View {
        Form {
            Section {
                ParkingMapCard(session: session)
            }.listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            Section {
                ParkingTimerDial(session: session)
                if !session.spotLabel.isEmpty { Label(session.spotLabel, systemImage: "mappin.and.ellipse").font(.headline) }
                DisclosureGroup(tr("停车时间详情", "Parking time details", "Butiran masa parkir")) {
                LabeledContent(tr("开始时间", "Start time", "Masa mula")) {
                    Text(session.startedAt, format: .dateTime.month().day().hour().minute())
                }
                if let end = session.endedAt {
                    Text(tr("已结束", "Ended", "Tamat")); Text(end, style: .time)
                }
                }
                Text(session.paidUntil == nil ? tr("缴费待确认", "Payment awaiting confirmation", "Bayaran menunggu pengesahan") : tr("缴费由你确认，未与 TNG 同步", "Payment confirmed by you; not synced with TNG", "Bayaran disahkan oleh anda; tidak disegerak dengan TNG"))
                    .font(.footnote).foregroundStyle(.secondary)
                if let end = session.paidUntil { LabeledContent(tr("已确认的结束时间", "Confirmed end time", "Masa tamat disahkan")) { Text(end, format: .dateTime.month().day().hour().minute()) } }
            }
            Section(tr("我的车位", "My parking spot", "Tempat kereta saya")) {
                DisclosureGroup(tr("车位备注与照片", "Spot notes & photo", "Nota petak dan foto")) {
                TextField(tr("车牌", "Plate", "Plat"), text: $session.plate)
                TextField(tr("停车场或地区", "Car park or area", "Tempat atau kawasan"), text: $session.name)
                Text(session.spotLabel).font(.headline)
                TextField(tr("楼层", "Floor", "Tingkat"), text: Binding(get: { session.floor ?? "" }, set: { session.floor = String($0.prefix(40)) }))
                TextField(tr("区域", "Zone", "Zon"), text: Binding(get: { session.zone ?? "" }, set: { session.zone = String($0.prefix(60)) }))
                TextField(tr("车位号 / 原车位备注", "Bay / previous spot notes", "Petak / nota tempat lama"), text: $session.bay)
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
            }
            if session.endedAt == nil {
                Section(tr("缴费与提醒", "Payment and reminder", "Bayaran dan peringatan")) {
                    Button(tr("前往 TNG 停车缴费", "Open TNG parking", "Buka parkir TNG"), action: launchTNG)
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
                    Text(tr("续费后填写累计金额和新到期时间，再在下方更新原账目或记录续费差额。", "After renewal, enter the cumulative total and new expiry, then update an existing entry or record the difference below.", "Selepas lanjutan, isi jumlah terkumpul dan tamat baharu, kemudian kemas kini rekod atau rekod perbezaan di bawah."))
                        .font(.caption).foregroundStyle(.secondary)
                    Picker(tr("提前提醒", "Remind before", "Ingatkan sebelum"), selection: $session.reminderMinutes) {
                        ForEach([5, 10, 15], id: \.self) { Text("\($0) min").tag($0) }
                    }
                    Button(tr("确认已付款并设置提醒", "Confirm payment and set reminder", "Sahkan bayaran dan tetapkan peringatan"), action: confirmPayment)
                        .buttonStyle(ParkingActionStyle()).disabled(busy)
                }
            }
            if session.endedAt != nil {
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
                    ForEach(linkedExpenses) { entry in
                        Button(tr("查看 / 修改停车账目", "Review / edit parking expense", "Semak / ubah belanja parkir") + " · " + money(entry.cents)) {
                            editingExpense = true; expenseDraft = entry
                        }
                    }
                    if linkedExpenses.count == session.ledgerIDs.count {
                        Button(tr("新增续费差额", "Record renewal difference", "Rekod perbezaan lanjutan"), action: prepareRenewal)
                    }
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
        .modifier(ParkingPaymentReturn(store: store, sessionID: session.id, review: {
            session.awaitingPaymentReview = false
            message = tr("请核对缴费金额和到期时间，再确认并记账。", "Review amount and expiry in Payment and reminder, then confirm and record.", "Semak amaun dan tamat dalam Bayaran dan peringatan, kemudian sahkan dan rekod.")
        }))
        .onChange(of: store.sessions.first(where: { $0.id == session.id })?.awaitingPaymentReview) { _, value in
            session.awaitingPaymentReview = value
        }
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
            ExpenseEditor(original: editingExpense ? draft : nil, initialDraft: editingExpense ? nil : draft, reviewDuplicates: true, onSaved: {
                if !editingExpense {
                    if session.expenseID == nil { session.expenseID = draft.id }
                    else if !session.ledgerIDs.contains(draft.id) { session.renewalExpenseIDs = (session.renewalExpenseIDs ?? []) + [draft.id] }
                }
                session.awaitingPaymentReview = false
                save()
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
