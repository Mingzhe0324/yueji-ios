import SwiftUI
import CoreLocation
import MapKit

/// Only a precisely named, geotagged Commons file with a supported license is shown.
/// No account data or device GPS is sent; the query uses the selected public POI.
enum CommonsMerchantPhotos {
    struct Metadata: Decodable { let value: String }
    struct Coordinate: Decodable { let lat: Double; let lon: Double }
    struct Info: Decodable {
        let thumburl: String?
        let descriptionurl: String?
        let mime: String?
        let extmetadata: [String: Metadata]?
    }
    struct Page: Decodable {
        let title: String
        let coordinates: [Coordinate]?
        let imageinfo: [Info]?
    }
    struct Response: Decodable {
        struct Query: Decodable { let pages: [Page]? }
        struct Failure: Decodable { let code: String }
        let query: Query?
        let error: Failure?
    }
    struct Photo {
        let imageURL: URL
        let sourceURL: URL
        let licenseURL: URL
        let title: String
        let author: String
        let credit: String
        let license: String
    }
    static func plain(_ html: String) -> String {
        html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    static func safeURL(_ text: String?, host: String, prefix: String) -> URL? {
        guard let text, let url = URL(string: text), url.scheme == "https", url.host == host,
              url.user == nil, url.password == nil, url.port == nil, url.path.hasPrefix(prefix) else { return nil }
        return url
    }
    static func photo(_ page: Page, place: ExpensePlace) -> Photo? {
        guard place.valid, place.applePlaceID != nil, let lat = place.latitude, let lon = place.longitude,
              page.coordinates?.contains(where: { point in
                  point.lat.isFinite && point.lon.isFinite && (-90...90).contains(point.lat) && (-180...180).contains(point.lon) &&
                  CLLocation(latitude: lat, longitude: lon).distance(from: CLLocation(latitude: point.lat, longitude: point.lon)) <= 150
              }) == true,
              let info = page.imageinfo?.first, ["image/jpeg", "image/png"].contains(info.mime ?? ""),
              let meta = info.extmetadata else { return nil }
        let name = MerchantMatching.key(place.name)
        let object = plain(meta["ObjectName"]?.value ?? "")
        let filename = (String(page.title.dropFirst(page.title.hasPrefix("File:") ? 5 : 0)) as NSString).deletingPathExtension
        guard name.count >= 5, matchesName(object, merchant: place.name) || matchesName(filename, merchant: place.name) else { return nil }
        let author = plain(meta["Artist"]?.value ?? "")
        let credit = plain(meta["Credit"]?.value ?? "")
        let license = plain(meta["LicenseShortName"]?.value ?? "")
        guard !author.isEmpty, author.count <= 2000, credit.count <= 2000, license.count <= 100,
              plain(meta["Restrictions"]?.value ?? "").isEmpty,
              let imageURL = safeURL(info.thumburl, host: "upload.wikimedia.org", prefix: "/wikipedia/commons/"),
              let sourceURL = safeURL(info.descriptionurl, host: "commons.wikimedia.org", prefix: "/wiki/File:"),
              let licenseURL = safeURL(meta["LicenseUrl"]?.value, host: "creativecommons.org", prefix: "/") else { return nil }
        let allowed = ["/licenses/by/4.0/", "/licenses/by-sa/4.0/", "/licenses/by/3.0/", "/licenses/by-sa/3.0/",
                       "/licenses/by/2.0/", "/licenses/by-sa/2.0/", "/licenses/by/2.5/", "/licenses/by-sa/2.5/",
                       "/publicdomain/zero/1.0/"]
        guard !license.isEmpty, allowed.contains(licenseURL.path.hasSuffix("/") ? licenseURL.path : licenseURL.path + "/") else { return nil }
        return Photo(imageURL: imageURL, sourceURL: sourceURL, licenseURL: licenseURL,
                     title: String(page.title.prefix(500)), author: author, credit: credit, license: license)
    }
    /// Accept a full store name followed by photo/date suffixes, never a partial brand match.
    static func matchesName(_ title: String, merchant: String) -> Bool {
        func words(_ value: String) -> String {
            value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
                .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
        }
        let name = words(merchant), candidate = words(title)
        guard name.count >= 5 else { return false }
        if candidate == name { return true }
        guard candidate.hasPrefix(name + " ") else { return false }
        let suffix = candidate.dropFirst(name.count + 1).split(separator: " ")
        let photoWords: Set<String> = ["exterior", "interior", "entrance", "facade", "front", "storefront", "view", "photo", "店面", "外观", "入口"]
        return !suffix.isEmpty && suffix.allSatisfy { photoWords.contains(String($0)) || $0.allSatisfy(\.isNumber) }
    }
    static func queryURL(_ place: ExpensePlace) -> URL? {
        guard place.valid, place.applePlaceID != nil, let lat = place.latitude, let lon = place.longitude else { return nil }
        var url = URLComponents(string: "https://commons.wikimedia.org/w/api.php")!
        let params = ["action": "query", "format": "json", "formatversion": "2", "generator": "geosearch",
                      "ggscoord": "\(lat)|\(lon)", "ggsradius": "150", "ggsnamespace": "6", "ggslimit": "50", "ggsprimary": "all",
                      "prop": "coordinates|imageinfo", "coprimary": "all", "colimit": "max",
                      "iiprop": "url|mime|extmetadata", "iiurlwidth": "800", "maxlag": "5",
                      "iiextmetadatafilter": "ObjectName|Artist|Credit|LicenseShortName|LicenseUrl|Restrictions"]
        url.queryItems = params.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        return url.url
    }
    static func fetch(_ url: URL, maximum: Int) async throws -> Data {
        var request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 12)
        request.setValue("YueJi/1.68 (https://github.com/Mingzhe0324/yueji-ios)", forHTTPHeaderField: "User-Agent")
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              response.url?.host == url.host, response.expectedContentLength <= Int64(maximum) else { throw URLError(.badServerResponse) }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < maximum else { throw URLError(.dataLengthExceedsMaximum) }
            data.append(byte)
        }
        return data
    }
}

private struct CommonsMerchantPhotoCard: View {
    let place: ExpensePlace
    @AppStorage("commonsMerchantPhotos") private var enabled = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var image: UIImage?
    @State private var photo: CommonsMerchantPhotos.Photo?
    @State private var loading = false
    @State private var unavailable = false
    @State private var foundNearbyFiles = false
    @State private var retry = 0
    private var emptyMessage: String {
        if CommonsMerchantPhotos.queryURL(place) == nil {
            return tr("请先匹配或选择具体店铺，才能查询照片。", "Match or select a specific store before looking for photos.", "Padankan atau pilih kedai sebelum mencari foto.")
        }
        if unavailable {
            return tr("照片请求失败，可稍后重试；地图仍可使用。", "Photo request failed. Try again later; the map remains available.", "Permintaan foto gagal. Cuba lagi nanti; peta masih tersedia.")
        }
        if foundNearbyFiles {
            return tr("附近有开放图片，但店名、位置或授权未通过核对，因此不展示。", "Nearby files found, but name, location or license checks did not pass.", "Fail berdekatan ditemui, tetapi semakan nama, lokasi atau lesen gagal.")
        }
        return tr("Commons 在此店铺附近未返回带坐标的照片，保留地图。", "Commons returned no geotagged photos near this store; keeping the map.", "Commons tiada foto berkoordinat berdekatan kedai ini; peta dikekalkan.")
    }
    private var requestID: String { enabled ? (CommonsMerchantPhotos.queryURL(place)?.absoluteString ?? "") + place.name + String(retry) : "" }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(tr("自动查找开放店铺照片", "Find open-license store photos", "Cari foto kedai berlesen terbuka"), isOn: $enabled)
                .font(.subheadline)
            Text(tr("向 Wikimedia 查询所选店铺坐标；不会发送账目或金额。照片可能较旧，并非每家店都有。", "Queries Wikimedia with the selected store coordinates, never entries or amounts. Photos may be old or unavailable.", "Mencari di Wikimedia dengan koordinat kedai, bukan rekod atau amaun. Foto mungkin lama atau tiada."))
                .font(.caption).foregroundStyle(.secondary)
            if enabled {
                if loading {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16).fill(.quaternary)
                        ProgressView(tr("正在查找照片…", "Looking for photos…", "Mencari foto…"))
                    }.frame(height: 140).accessibilityElement(children: .combine)
                }
                if let image, let photo {
                    Image(uiImage: image).resizable().scaledToFit()
                        .frame(maxWidth: .infinity).clipShape(RoundedRectangle(cornerRadius: 16))
                        .accessibilityLabel(place.name + " · Wikimedia Commons")
                        .transition(.opacity)
                    Text(photo.title).font(.caption.weight(.medium))
                    Text(photo.author).font(.caption)
                    if !photo.credit.isEmpty { Text(photo.credit).font(.caption).foregroundStyle(.secondary) }
                    HStack {
                        Link("Wikimedia Commons", destination: photo.sourceURL)
                        Spacer()
                        Link(photo.license, destination: photo.licenseURL)
                    }.font(.caption)
                    Text(tr("按名称及附近坐标匹配，非店铺官方验证照片。", "Matched by name and nearby coordinates; not verified by the store.", "Dipadankan mengikut nama dan koordinat; bukan disahkan kedai."))
                        .font(.caption2).foregroundStyle(.secondary)
                } else if !loading {
                    Text(emptyMessage)
                        .font(.caption).foregroundStyle(.secondary)
                    if unavailable {
                        Button(tr("重试照片", "Retry photos", "Cuba semula foto")) { retry += 1 }
                            .font(.caption)
                    }
                }
            }
        }.padding(18).background(.background, in: RoundedRectangle(cornerRadius: 22))
            .animation(reduceMotion || !ElegantMotion.enabled ? nil : .easeInOut(duration: 0.2), value: image != nil)
            .task(id: requestID) {
                image = nil; photo = nil; unavailable = false; loading = false; foundNearbyFiles = false
                guard enabled, let url = CommonsMerchantPhotos.queryURL(place) else { return }
                loading = true
                do {
                    try await Task.sleep(for: .milliseconds(400))
                    let data = try await CommonsMerchantPhotos.fetch(url, maximum: 1_500_000)
                    let response = try JSONDecoder().decode(CommonsMerchantPhotos.Response.self, from: data)
                    guard response.error == nil else { throw URLError(.badServerResponse) }
                    try Task.checkCancellation()
                    foundNearbyFiles = !(response.query?.pages ?? []).isEmpty
                    let candidates = (response.query?.pages ?? []).compactMap { CommonsMerchantPhotos.photo($0, place: place) }
                    for result in candidates.sorted(by: { $0.title < $1.title }).prefix(3) {
                        do {
                            let bytes = try await CommonsMerchantPhotos.fetch(result.imageURL, maximum: 4_000_000)
                            guard let decoded = UIImage(data: bytes) else { throw URLError(.cannotDecodeContentData) }
                            try Task.checkCancellation()
                            photo = result; image = decoded; unavailable = false
                            break
                        } catch {
                            try Task.checkCancellation()
                            unavailable = true
                        }
                    }
                    try Task.checkCancellation(); loading = false
                } catch {
                    guard !Task.isCancelled else { return }
                    loading = false; unavailable = true
                }
            }
    }
}

struct MerchantMatchInput: Equatable {
    var name: String
    var address: String
    var latitude: Double?
    var longitude: Double?
    var accuracy: Double?
    var capturedAt: Date?
    var transactionDate: Date?
    var remembered: [ExpensePlace]
    var receiptAddress: String
    var receiptPhone: String
}

@MainActor
final class ExpenseMerchantMatcher: ObservableObject {
    @Published var loading = false
    @Published var message: String?
    @Published var candidates: [ExpensePlace] = []
    @Published var automatic: ExpensePlace?
    private var generation = UUID()
    private let geocoder = CLGeocoder()
    private var search: MKLocalSearch?

    func cancel() {
        generation = UUID()
        geocoder.cancelGeocode(); search?.cancel(); search = nil
        loading = false; message = nil; candidates = []; automatic = nil
    }

    func find(_ input: MerchantMatchInput) async {
        guard #available(iOS 18.0, *) else { return }
        let token = generation
        let name = input.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let address = input.address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty || !address.isEmpty || input.latitude != nil else { return }
        loading = true
        do {
            try await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled, generation == token else { return }
            var anchor: CLLocation?
            var precise = false
            if let lat = input.latitude, let lon = input.longitude,
               CLLocationCoordinate2DIsValid(CLLocationCoordinate2D(latitude: lat, longitude: lon)) {
                anchor = CLLocation(latitude: lat, longitude: lon)
                precise = MerchantMatching.reliableAnchor(accuracy: input.accuracy,
                    capturedAt: input.capturedAt, transactionDate: input.transactionDate)
            } else if !address.isEmpty {
                // An address lookup failure must not prevent a merchant-name search.
                let marks = (try? await geocoder.geocodeAddressString(address)) ?? []
                guard !Task.isCancelled, generation == token else { return }
                // A city or ambiguous address can suggest places, but cannot auto-link one.
                if marks.count == 1 {
                    anchor = marks.first?.location
                    precise = marks.first?.thoroughfare != nil && marks.first?.subThoroughfare != nil
                        && MerchantMatching.reliableAnchor(accuracy: input.accuracy,
                            capturedAt: input.capturedAt, transactionDate: input.transactionDate)
                }
            }
            let operation: MKLocalSearch
            let nearbyMemory = input.remembered.filter { place in
                guard let anchor, let lat = place.latitude, let lon = place.longitude else { return false }
                return anchor.distance(from: CLLocation(latitude: lat, longitude: lon)) <= 500
            }
            let rememberedNames = Set(nearbyMemory.map { $0.name })
            let searchName = rememberedNames.count == 1 ? (rememberedNames.first ?? name) : name
            if nearbyMemory.count > 1 { precise = false }
            if name.isEmpty, let anchor {
                operation = MKLocalSearch(request: MKLocalPointsOfInterestRequest(center: anchor.coordinate, radius: 500))
            } else {
                let request = MKLocalSearch.Request()
                request.naturalLanguageQuery = [searchName, address].filter { !$0.isEmpty }.joined(separator: " ")
                request.resultTypes = .pointOfInterest
                if let anchor {
                    request.region = MKCoordinateRegion(center: anchor.coordinate, latitudinalMeters: 1000, longitudinalMeters: 1000)
                }
                operation = MKLocalSearch(request: request)
            }
            search = operation
            let response = try await operation.start()
            guard !Task.isCancelled, generation == token else { return }
            var places: [ExpensePlace] = []
            var ranked: [MerchantMatchCandidate] = []
            var seen = Set<String>()
            for item in response.mapItems {
                guard let id = item.identifier?.rawValue, let title = item.name,
                      seen.insert(id).inserted else { continue }
                let coordinate = item.placemark.coordinate
                let distance = anchor?.distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)) ?? .infinity
                if anchor != nil && distance > 500 { continue }
                places.append(ExpensePlace(name: title, address: item.placemark.title ?? "",
                    latitude: coordinate.latitude, longitude: coordinate.longitude, applePlaceID: id))
                ranked.append(MerchantMatchCandidate(id: id, name: title, distance: distance,
                    address: item.placemark.title ?? "", phone: item.phoneNumber ?? ""))
            }
            loading = false; search = nil
            if precise, let id = MerchantMatching.automaticID(name: searchName, candidates: ranked),
               let candidate = ranked.first(where: { $0.id == id }),
               (nearbyMemory.isEmpty || nearbyMemory.contains(where: { $0.applePlaceID == id })),
               MerchantMatching.receiptAgrees(address: input.receiptAddress, phone: input.receiptPhone, candidate: candidate) {
                automatic = places.first { $0.applePlaceID == id }
            } else {
                candidates = Array(places.prefix(6))
                message = places.isEmpty
                    ? tr("没有找到对应店铺，可保留地点或搜索店名。", "No matching place found. Keep this location or search by name.", "Tiada tempat sepadan. Kekalkan lokasi atau cari nama kedai.")
                    : tr("资料尚未完全核对，请确认地址与分店后选择。", "Details are not fully verified. Confirm the address and branch before choosing.", "Butiran belum disahkan sepenuhnya. Sahkan alamat dan cawangan sebelum memilih.")
            }
        } catch {
            guard !Task.isCancelled, generation == token else { return }
            loading = false; search = nil
            message = tr("暂时无法匹配店铺，仍可保存地点或搜索店名。", "Matching unavailable. You can still save the location or search by name.", "Padanan tidak tersedia. Anda masih boleh simpan lokasi atau cari nama kedai.")
        }
    }
}

@MainActor
final class ExpensePlaceLocator: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    @Published var result: ExpensePlace?
    @Published var busy = false
    @Published var message: String?
    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var timeout: Task<Void, Never>?
    private var requestID = UUID()
    private var automaticRequest = false
    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    }
    static func recentPlace() -> ExpensePlace? {
        // Background automations never prompt, wait for GPS, or reuse an old fix.
        let manager = CLLocationManager()
        guard manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways,
              let location = manager.location, location.horizontalAccuracy >= 0,
              location.horizontalAccuracy <= 100, abs(location.timestamp.timeIntervalSinceNow) < 30 else { return nil }
        return ExpensePlace(name: tr("记录时的位置", "Location at recording", "Lokasi ketika direkod"),
            latitude: location.coordinate.latitude, longitude: location.coordinate.longitude,
            accuracyMeters: location.horizontalAccuracy, capturedAt: location.timestamp)
    }
    func start(automatic: Bool = false) {
        // New-entry presentation requests permission once through the system.
        // A denied permission never prevents entering or saving an expense.
        cancel()
        automaticRequest = automatic
        busy = true; message = nil; result = nil
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
        else { requestIfAllowed() }
    }
    func cancel() {
        requestID = UUID(); timeout?.cancel(); timeout = nil
        manager.stopUpdatingLocation(); geocoder.cancelGeocode(); busy = false
    }
    private func requestIfAllowed() {
        guard busy else { return }
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
            timeout?.cancel()
            timeout = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(20)) } catch { return }
                guard let self, self.busy else { return }
                self.cancel()
                self.message = tr("暂时无法定位，可重试或手动填写。", "Location unavailable. Retry or enter a place.", "Lokasi tidak tersedia. Cuba lagi atau isi tempat.")
            }
        case .denied, .restricted:
            cancel()
            message = tr("未开启定位，可手动填写，或在系统设置允许定位。", "Enter a place manually, or allow location in Settings.", "Isi tempat sendiri atau benarkan lokasi dalam Tetapan.")
        default: break
        }
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) { requestIfAllowed() }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard busy else { return }
        cancel()
        message = tr("暂时无法定位，可重试或手动填写。", "Location unavailable. Retry or enter a place.", "Lokasi tidak tersedia. Cuba lagi atau isi tempat.")
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard busy, let location = locations.last, location.horizontalAccuracy >= 0,
              abs(location.timestamp.timeIntervalSinceNow) < 60 else { return }
        let token = requestID
        geocoder.reverseGeocodeLocation(location) { [weak self] marks, _ in
            Task { @MainActor in
                guard let self, self.busy, self.requestID == token else { return }
                let mark = marks?.first
                let address = [mark?.thoroughfare, mark?.locality, mark?.administrativeArea, mark?.country]
                    .compactMap { $0 }.joined(separator: ", ")
                let place = ExpensePlace(name: mark?.name ?? tr("当前位置", "Current location", "Lokasi semasa"), address: address,
                    latitude: location.coordinate.latitude, longitude: location.coordinate.longitude,
                    accuracyMeters: location.horizontalAccuracy, capturedAt: self.automaticRequest ? location.timestamp : nil)
                self.cancel(); self.result = place
            }
        }
    }
}

struct ExpensePlaceField: View {
    @Binding var place: ExpensePlace?
    @ObservedObject var locator: ExpensePlaceLocator
    var notice: String? = nil
    let edit: () -> Void
    var body: some View {
        Section {
            Button {
                locator.cancel(); edit()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "mappin.and.ellipse").foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(place?.name ?? tr("添加消费地点", "Add spending location", "Tambah lokasi belanja"))
                        if let place, !place.address.isEmpty { Text(place.address).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                        Text(locator.busy ? tr("正在获取地点…", "Finding location…", "Mencari lokasi…") :
                            (place == nil ? tr("未记录地点", "No location recorded", "Tiada lokasi direkod") :
                                ((place?.accuracyMeters ?? 0) > 100 ? tr("大约位置 · 可修改", "Approximate location · editable", "Lokasi anggaran · boleh diubah") : tr("已记录地点 · 可修改", "Location recorded · editable", "Lokasi direkod · boleh diubah"))))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if locator.busy { ProgressView().controlSize(.small) }
                    else { Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary) }
                }.contentTransition(.opacity)
            }.buttonStyle(.plain).accessibilityIdentifier("transaction.place.edit")
            Button { locator.start() } label: {
                Label(tr("重新定位", "Locate again", "Cari lokasi semula"), systemImage: "location")
            }.disabled(locator.busy).accessibilityIdentifier("transaction.place.locate")
            if let message = locator.message { Text(message).font(.caption).foregroundStyle(.secondary) }
            if let notice { Text(notice).font(.caption).foregroundStyle(.secondary) }
            if place != nil {
                Button(tr("移除地点", "Remove location", "Buang lokasi"), role: .destructive) { locator.cancel(); place = nil }
            }
        } header: { Text(tr("消费地点 · 选填", "Spending location · optional", "Lokasi belanja · pilihan")) } footer: {
            Text(tr("授权后，新账目会自动获取当前位置；地点不对可修改。", "After permission, new entries use your current location automatically. You can edit it.", "Selepas kebenaran, rekod baharu menggunakan lokasi semasa secara automatik. Anda boleh mengubahnya."))
        }
    }
}

struct ExpensePlaceDetails: View {
    let place: ExpensePlace
    let open: () -> Void
    var body: some View {
        Section(tr("消费地点", "Spending location", "Lokasi belanja")) {
                Button(action: open) {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(place.name)
                            if !place.address.isEmpty { Text(place.address).font(.caption).foregroundStyle(.secondary) }
                        }
                    } icon: { Image(systemName: "mappin.and.ellipse") }
                }.accessibilityIdentifier("transaction.place.detail")
        }
    }
}

/// The map owns a local draft. Panning, searching and cancellation never write
/// the ledger; only Done in an editor returns a selected place to its parent.
struct ExpensePlaceDestination: Identifiable {
    let id = UUID()
    let place: ExpensePlace
    let merchant: String
    let transactionDate: Date
    var receiptAddress: String = ""
    var receiptPhone: String = ""
}

struct ExpensePlaceMapSheet: View {
    @EnvironmentObject private var model: LedgerModel
    let initial: ExpensePlace?
    var merchantHint: String = ""
    var transactionDate: Date?
    var receiptAddress: String
    var receiptPhone: String
    var onSave: ((ExpensePlace) -> Void)?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var position: MapCameraPosition = .automatic
    @State private var center: CLLocationCoordinate2D?
    @State private var selected: ExpensePlace?
    @State private var name = ""
    @State private var address = ""
    @State private var query = ""
    @State private var results: [MKMapItem] = []
    @State private var search: MKLocalSearch?
    @State private var searchTask: Task<Void, Never>?
    @State private var searchID = UUID()
    @State private var searching = false
    @State private var message: String?
    @FocusState private var searchFocused: Bool
    @State private var initialized = false
    @State private var confirmingDiscard = false
    @StateObject private var mapLocator = ExpensePlaceLocator()
    @State private var movingMap = false
    @State private var visible = false
    @StateObject private var merchantMatcher = ExpenseMerchantMatcher()
    init(initial: ExpensePlace?, merchantHint: String = "", transactionDate: Date? = nil, receiptAddress: String = "", receiptPhone: String = "", onSave: ((ExpensePlace) -> Void)? = nil) {
        self.initial = initial
        self.merchantHint = merchantHint
        self.transactionDate = transactionDate
        self.receiptAddress = receiptAddress
        self.receiptPhone = receiptPhone
        self.onSave = onSave
        _selected = State(initialValue: initial)
        _name = State(initialValue: initial?.name ?? "")
        _address = State(initialValue: initial?.address ?? "")
        if let lat = initial?.latitude, let lon = initial?.longitude {
            let coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            if CLLocationCoordinate2DIsValid(coordinate) {
                _position = State(initialValue: .region(MKCoordinateRegion(center: coordinate,
                    latitudinalMeters: 800, longitudinalMeters: 800)))
                _center = State(initialValue: coordinate)
            }
        }
    }
    private var matchInput: MerchantMatchInput? {
        guard visible, initialized, draft.applePlaceID == nil else { return nil }
        let generic = ["地图选点", "Selected on map", "Dipilih pada peta", "当前位置", "Current location", "Lokasi semasa", "记录时的位置", "Location at recording", "Lokasi ketika direkod"]
        let typedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let hint = merchantHint.trimmingCharacters(in: .whitespacesAndNewlines)
        // Reverse-geocoded names often describe a street/building, not the merchant.
        let recordedLocation = typedName == selected?.name && selected?.accuracyMeters != nil
        let expected = recordedLocation && !hint.isEmpty ? hint
            : (!typedName.isEmpty && !generic.contains(typedName) ? typedName : hint)
        let sameAddress = address.trimmingCharacters(in: .whitespacesAndNewlines) == selected?.address
        return MerchantMatchInput(name: expected, address: address, latitude: sameAddress ? selected?.latitude : nil,
                                  longitude: sameAddress ? selected?.longitude : nil,
                                  accuracy: sameAddress ? selected?.accuracyMeters : nil,
                                  capturedAt: sameAddress ? selected?.capturedAt : nil,
                                  transactionDate: transactionDate,
                                  remembered: MerchantMatching.confirmedPlaces(merchant: hint, expenses: model.ledger.expenses),
                                  receiptAddress: receiptAddress, receiptPhone: receiptPhone)
    }
    private var googleMapsURL: URL? {
        let place = draft
        var query = [place.name, place.address].filter { !$0.isEmpty }.joined(separator: " ")
        if query.isEmpty, let lat = place.latitude, let lon = place.longitude { query = "\(lat),\(lon)" }
        guard !query.isEmpty else { return nil }
        var components = URLComponents(string: "https://www.google.com/maps/search/")
        components?.queryItems = [URLQueryItem(name: "api", value: "1"), URLQueryItem(name: "query", value: query)]
        return components?.url
    }
    private var editing: Bool { onSave != nil }
    private var hasChanges: Bool { editing && initialized && draft != (initial ?? ExpensePlace(name: "")) }
    private var coordinate: CLLocationCoordinate2D? {
        guard let lat = draft.latitude, let lon = draft.longitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
    private var draft: ExpensePlace {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let a = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let unchanged = n == selected?.name && a == selected?.address
        return ExpensePlace(name: n.isEmpty ? a : n, address: a,
            latitude: unchanged ? selected?.latitude : nil, longitude: unchanged ? selected?.longitude : nil,
            accuracyMeters: unchanged ? selected?.accuracyMeters : nil,
            capturedAt: unchanged ? selected?.capturedAt : nil,
            applePlaceID: unchanged ? selected?.applePlaceID : nil,
            userConfirmed: unchanged ? selected?.userConfirmed : nil)
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(draft.name.isEmpty ? merchantHint : draft.name).font(.title2.weight(.semibold))
                        if !draft.address.isEmpty { Text(draft.address).font(.subheadline).foregroundStyle(.secondary) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    matchStatus
                    if editing || coordinate != nil {
                        mapCard.transition(.opacity)
                    } else if merchantMatcher.loading {
                        VStack(spacing: 14) {
                            Image(systemName: "map").font(.largeTitle).foregroundStyle(.secondary)
                            ProgressView(tr("正在查找店铺位置", "Finding store location", "Mencari lokasi kedai"))
                        }.frame(maxWidth: .infinity).frame(height: 300)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 24))
                            .transition(.opacity)
                    }
                    merchantSuggestions
                    CommonsMerchantPhotoCard(place: draft)
                    if !receiptAddress.isEmpty || !receiptPhone.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(tr("收据上的店铺资料", "Store details on receipt", "Butiran kedai pada resit")).font(.headline)
                            if !receiptAddress.isEmpty { Text(receiptAddress) }
                            if !receiptPhone.isEmpty { Text(receiptPhone) }
                        }.font(.subheadline).frame(maxWidth: .infinity, alignment: .leading).padding(18)
                    }
                    if #available(iOS 18.0, *) {
                        AppleMerchantCard(placeID: draft.applePlaceID, automaticallyPresent: false)
                    }
                    if let url = googleMapsURL {
                        Link(destination: url) {
                            Label(tr("去 Google Maps 看照片", "View photos on Google Maps", "Lihat foto di Google Maps"), systemImage: "arrow.up.right.square")
                                .font(.subheadline).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 10)
                        }.accessibilityIdentifier("place.googleMaps")
                        Text(tr("打开 Google Maps 搜索此店铺，照片以店铺收录情况为准。", "Opens Google Maps to search this place; photos depend on availability.", "Membuka Google Maps untuk mencari tempat ini; foto bergantung pada ketersediaan."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if editing || draft.applePlaceID == nil { searchPanel }
                    if editing {
                        VStack(alignment: .leading, spacing: 14) {
                            Text(tr("地点信息", "Place details", "Butiran tempat")).font(.headline)
                            TextField(tr("地点名称", "Place name", "Nama tempat"), text: $name)
                                .accessibilityIdentifier("place.name")
                            Divider()
                            TextField(tr("地址", "Address", "Alamat"), text: $address, axis: .vertical)
                                .lineLimit(2...4).accessibilityIdentifier("place.address")
                            Text(tr("选择分店并保存账目后，下次相同商户会优先参考这次确认。", "Choose a branch and save the entry to remember this merchant match.", "Pilih cawangan dan simpan rekod untuk mengingati padanan peniaga ini."))
                                .font(.caption).foregroundStyle(.secondary)
                        }.padding(18).background(.background, in: RoundedRectangle(cornerRadius: 22))
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            if draft != initial {
                                Text(tr("当前为店铺预览，不会修改账目中保存的地点。", "Place preview; the saved transaction location is unchanged.", "Pratonton tempat; lokasi transaksi yang disimpan tidak berubah."))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            if draft.latitude == nil {
                                Text(tr("此地点没有坐标，可搜索查看；不会更改原账目。", "This place has no saved pin. Search to preview without changing the entry.", "Tempat ini tiada pin. Cari untuk pratonton tanpa mengubah rekod."))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(18)
                    }
                }.padding(16)
                    .animation(reduceMotion || !ElegantMotion.enabled ? nil : .easeInOut(duration: 0.22), value: merchantMatcher.loading)
                    .animation(reduceMotion || !ElegantMotion.enabled ? nil : .easeInOut(duration: 0.22), value: draft.applePlaceID)
            }
            .background(IslandTheme.paper)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(tr("消费地点", "Spending location", "Lokasi belanja"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(editing ? tr("取消", "Cancel", "Batal") : tr("完成", "Done", "Selesai"), systemImage: "xmark") {
                        if hasChanges { confirmingDiscard = true } else { dismiss() }
                    }
                }
                if editing {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(tr("完成", "Done", "Selesai"), systemImage: "checkmark") { onSave?(draft); dismiss() }
                            .disabled(draft.name.isEmpty || !draft.valid).accessibilityIdentifier("place.save")
                    }
                }
            }
            .onAppear {
                visible = true
                guard !initialized else { return }
                select(initial, animated: false)
                query = [initial?.name, initial?.address].compactMap { $0 }.joined(separator: " ")
                initialized = true
            }
            .onDisappear { visible = false; cancelSearch(); merchantMatcher.cancel(); mapLocator.cancel(); movingMap = false }
            .task(id: matchInput) {
                merchantMatcher.cancel()
                guard let input = matchInput else { return }
                await merchantMatcher.find(input)
                guard !Task.isCancelled, visible, matchInput == input, let matched = merchantMatcher.automatic else { return }
                select(matched, animated: true)
            }
            .onChange(of: mapLocator.result) { _, value in
                guard visible, let value else { return }
                cancelSearch(); results = []; searchFocused = false
                select(value, animated: true)
                FeedbackHaptics.selection()
            }
            .onChange(of: name) { _, _ in if mapLocator.busy { mapLocator.cancel() } }
            .onChange(of: address) { _, _ in if mapLocator.busy { mapLocator.cancel() } }
            .editorDismissal(hasChanges: hasChanges, saving: false, confirming: $confirmingDiscard) { dismiss() }
        }.presentationDragIndicator(.visible)
    }
    private var matchStatus: some View {
        let confirmed = draft.userConfirmed == true && draft.applePlaceID != nil
        let matched = draft.applePlaceID != nil
        let title = merchantMatcher.loading ? tr("正在匹配", "Matching", "Memadankan")
            : confirmed ? tr("已确认分店", "Confirmed branch", "Cawangan disahkan")
            : matched ? tr("已匹配 · 可核对", "Matched · review details", "Sepadan · semak butiran")
            : !receiptAddress.isEmpty ? tr("地址待核对", "Address needs review", "Alamat perlu disemak")
            : tr("待选分店", "Choose a branch", "Pilih cawangan")
        let tint: Color = confirmed ? IncomeStyle.tint : matched ? .blue : .orange
        return Label(title, systemImage: confirmed ? "checkmark.seal.fill" : matched ? "mappin.circle.fill" : "magnifyingglass")
            .font(.subheadline.weight(.medium)).foregroundStyle(tint)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(tint.opacity(0.12), in: Capsule())
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("place.matchStatus")
    }
    private var mapCard: some View {
        VStack(spacing: 0) {
            Map(position: $position, interactionModes: [.pan, .zoom, .rotate]) {
                if let coordinate { Marker(selected?.name ?? "", coordinate: coordinate).tint(IslandPalette.coral) }
            }
            .mapStyle(.standard(elevation: .flat))
            .mapControls { MapCompass(); MapScaleView() }
            .onMapCameraChange(frequency: .continuous) { _ in
                guard editing, position.positionedByUser, !movingMap else { return }
                mapLocator.cancel(); merchantMatcher.cancel()
                movingMap = true
            }
            .onMapCameraChange(frequency: .onEnd) { context in
                center = context.region.center
                if movingMap { movingMap = false; FeedbackHaptics.selection() }
            }
            .overlay {
                if editing {
                    ZStack {
                        Circle().fill(.primary.opacity(0.15)).frame(width: 10, height: 5)
                            .scaleEffect(movingMap && !reduceMotion ? 0.7 : 1)
                        Image(systemName: "mappin.circle.fill")
                            .font(.system(size: 36)).symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .blue)
                            .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                            .offset(y: movingMap && !reduceMotion ? -31 : -23)
                    }
                    .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.82), value: movingMap)
                    .allowsHitTesting(false).accessibilityHidden(true)
                }
            }
            .frame(height: 300)
            .accessibilityIdentifier("place.map")
            if editing {
                Button {
                    guard let center else { return }
                    cancelSearch(); mapLocator.cancel(); results = []
                    select(ExpensePlace(name: tr("地图选点", "Selected on map", "Dipilih pada peta"),
                        latitude: center.latitude, longitude: center.longitude), animated: false)
                } label: {
                    Label(tr("移动地图后，使用中心位置", "Use map center", "Gunakan pusat peta"), systemImage: "mappin.and.ellipse")
                        .font(.subheadline.weight(.medium)).frame(maxWidth: .infinity).padding(16)
                }.disabled(center == nil || movingMap).accessibilityIdentifier("place.useCenter")
                Divider()
                Button {
                    merchantMatcher.cancel(); cancelSearch(); searchFocused = false; mapLocator.start()
                } label: {
                    HStack(spacing: 8) {
                        if mapLocator.busy { ProgressView().controlSize(.small) }
                        else { Image(systemName: "location.fill") }
                        Text(tr("重新定位", "Locate again", "Cari lokasi semula"))
                    }.font(.subheadline.weight(.medium)).frame(maxWidth: .infinity).padding(14)
                }.disabled(mapLocator.busy).accessibilityIdentifier("place.relocate")
                if let message = mapLocator.message {
                    Text(message).font(.caption).foregroundStyle(.secondary).padding(.horizontal, 16).padding(.bottom, 12)
                }
            }
        }.background(.background, in: RoundedRectangle(cornerRadius: 24))
            .clipShape(RoundedRectangle(cornerRadius: 24))
    }
    private var merchantSuggestions: some View {
        VStack(alignment: .leading, spacing: 10) {
            if merchantMatcher.loading {
                HStack { ProgressView().controlSize(.small); Text(tr("正在匹配附近店铺…", "Matching nearby places…", "Memadankan tempat berdekatan…")).font(.subheadline) }
            }
            if let message = merchantMatcher.message { Text(message).font(.caption).foregroundStyle(.secondary) }
            ForEach(merchantMatcher.candidates.indices, id: \.self) { index in
                let place = merchantMatcher.candidates[index]
                Button {
                    merchantMatcher.cancel(); cancelSearch(); mapLocator.cancel(); select(place, animated: true)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(place.name).font(.subheadline.weight(.medium))
                        Text(place.address).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
                }.buttonStyle(.plain)
            }
        }.padding(merchantMatcher.loading || merchantMatcher.message != nil || !merchantMatcher.candidates.isEmpty ? 16 : 0)
            .background(.background, in: RoundedRectangle(cornerRadius: 22))
    }
    private var searchPanel: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(tr("搜索商户或地址", "Search places or addresses", "Cari tempat atau alamat"), text: $query)
                    .focused($searchFocused).submitLabel(.search).onSubmit { runSearch() }
                    .accessibilityIdentifier("place.search")
                Button { runSearch() } label: {
                    if searching { ProgressView() } else { Image(systemName: "arrow.right.circle.fill").font(.title2) }
                }.accessibilityLabel(tr("搜索", "Search", "Cari"))
                    .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || searching)
            }
            if let message { Text(message).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading) }
            ForEach(results.indices, id: \.self) { index in
                let item = results[index]
                Divider()
                Button {
                    merchantMatcher.cancel(); cancelSearch(); mapLocator.cancel(); searchFocused = false
                    var chosen = ExpensePlace(name: item.name ?? tr("所选地点", "Selected place", "Tempat dipilih"),
                        address: item.placemark.title ?? "", latitude: item.placemark.coordinate.latitude,
                        longitude: item.placemark.coordinate.longitude)
                    if #available(iOS 18.0, *) { chosen.applePlaceID = item.identifier?.rawValue }
                    select(chosen, animated: true)
                    results = []
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.name ?? "").font(.subheadline.weight(.medium))
                        Text(item.placemark.title ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
                }.buttonStyle(.plain)
            }
        }.padding(18).background(.background, in: RoundedRectangle(cornerRadius: 22))
            .onChange(of: query) { _, _ in cancelSearch(); results = []; message = nil }
    }
    private func select(_ place: ExpensePlace?, animated: Bool) {
        selected = place; name = place?.name ?? ""; address = place?.address ?? ""
        if let coordinate {
            let region = MKCoordinateRegion(center: coordinate, latitudinalMeters: 800, longitudinalMeters: 800)
            withAnimation(animated && !reduceMotion ? .easeInOut(duration: 0.35) : nil) { position = .region(region) }
        }
    }
    private func cancelSearch() {
        searchID = UUID(); search?.cancel(); searchTask?.cancel(); search = nil; searchTask = nil; searching = false
    }
    private func runSearch() {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        merchantMatcher.cancel(); cancelSearch(); mapLocator.cancel(); searchFocused = false; message = nil; searching = true
        let token = searchID
        let request = MKLocalSearch.Request(); request.naturalLanguageQuery = text
        if let center { request.region = MKCoordinateRegion(center: center, latitudinalMeters: 10_000, longitudinalMeters: 10_000) }
        let operation = MKLocalSearch(request: request); search = operation
        searchTask = Task { @MainActor in
            do {
                let response = try await operation.start()
                guard visible, !Task.isCancelled, token == searchID else { return }
                results = Array(response.mapItems.prefix(6)); searching = false
                if results.isEmpty { message = tr("没有找到地点，可修改搜索或手动填写。", "No places found. Try another search or enter the address.", "Tiada tempat ditemui. Cuba carian lain atau isi alamat.") }
            } catch {
                guard visible, !Task.isCancelled, token == searchID else { return }
                searching = false
                message = tr("搜索暂时不可用，仍可手动填写或在地图选点。", "Search unavailable. You can still enter a place or select a map point.", "Carian tidak tersedia. Isi tempat atau pilih titik pada peta.")
            }
        }
    }
}

@available(iOS 18.0, *)
private struct AppleMerchantCard: View {
    let placeID: String?
    var automaticallyPresent = false
    @State private var automaticallyPresentedID: String?
    @State private var presentedItem: MKMapItem?
    @State private var request: MKMapItemRequest?
    @State private var generation = UUID()
    @State private var loading = false
    @State private var message: String?
    @State private var task: Task<Void, Never>?
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if placeID != nil {
                Button(action: open) {
                    HStack(spacing: 12) {
                        Image(systemName: "storefront").font(.title2).foregroundStyle(.tint)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(tr("店铺资料与照片", "Place details & photos", "Butiran & foto tempat")).font(.headline)
                            Text(tr("由 Apple 提供 · 照片视店铺收录情况而定", "Provided by Apple · photos when available", "Disediakan Apple · foto jika tersedia"))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if loading { ProgressView().controlSize(.small) }
                        else { Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary) }
                    }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain).disabled(loading).accessibilityIdentifier("place.appleDetails")
            } else {
                Label(tr("搜索并选择具体店铺，可查看 Apple 提供的资料与可用照片。", "Search and choose a specific place to view Apple's details and available photos.", "Cari dan pilih tempat untuk melihat butiran Apple dan foto yang tersedia."), systemImage: "storefront")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
        }.padding(18).background(.background, in: RoundedRectangle(cornerRadius: 22))
            .mapItemDetailSheet(item: $presentedItem, displaysMap: true)
            .task(id: placeID) {
                cancel(); presentedItem = nil; message = nil
                guard automaticallyPresent, let placeID, automaticallyPresentedID != placeID else { return }
                automaticallyPresentedID = placeID
                open()
            }
            .onDisappear { cancel() }
    }
    private func cancel() {
        generation = UUID(); request?.cancel(); task?.cancel(); request = nil; task = nil; loading = false
    }
    private func open() {
        guard let placeID, let identifier = MKMapItem.Identifier(rawValue: placeID) else { return }
        cancel(); message = nil; loading = true
        let token = generation
        let operation = MKMapItemRequest(mapItemIdentifier: identifier)
        request = operation
        task = Task { @MainActor in
            do {
                let item = try await operation.mapItem
                guard !Task.isCancelled, token == generation else { return }
                loading = false; presentedItem = item
            } catch {
                guard !Task.isCancelled, token == generation else { return }
                loading = false
                message = tr("暂时无法加载店铺资料，请重试。账目不会受到影响。", "Place details are unavailable. Try again; your entry is unchanged.", "Butiran tempat tidak tersedia. Cuba lagi; rekod tidak berubah.")
            }
        }
    }
}

struct ExpenseChargeFields: View {
    @Binding var enabled: Bool
    @Binding var subtotal: String
    @Binding var sst: String
    @Binding var service: String
    @Binding var rounding: String
    let currency: String
    let actualMinor: Int?
    let applyTotal: (Int) -> Void
    var sharedFocus: FocusState<ExpenseInputField?>.Binding? = nil
    @FocusState private var localFocus: ExpenseInputField?
    private var focus: FocusState<ExpenseInputField?>.Binding { sharedFocus ?? $localFocus }
    private var draft: ExpenseCharges? { try? ExpenseCharges.draft(currency: currency, subtotal: subtotal, sst: sst, service: service, rounding: rounding) }
    var body: some View {
        Section {
            Toggle(tr("填写 SST／服务费", "Add SST / service charge", "Isi SST / caj perkhidmatan"), isOn: $enabled)
                .accessibilityIdentifier("transaction.charges.enabled")
            if enabled {
                LabeledContent(tr("税前小计", "Subtotal before charges", "Subtotal sebelum caj")) {
                    TextField("0.00", text: $subtotal).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                        .focused(focus, equals: .chargeSubtotal)
                        .accessibilityIdentifier("transaction.charges.subtotal")
                }
                percentageRow("SST", value: $sst, field: .sstPercent, identifier: "transaction.charges.sst")
                percentageRow(tr("服务费", "Service Charge", "Caj perkhidmatan"), value: $service, field: .servicePercent, identifier: "transaction.charges.service")
                LabeledContent(tr("尾数调整（±）", "Rounding (+ / −)", "Pembundaran (+ / −)")) {
                    TextField("0.00", text: $rounding).keyboardType(.numbersAndPunctuation).multilineTextAlignment(.trailing)
                        .focused(focus, equals: .chargeRounding)
                        .accessibilityIdentifier("transaction.charges.rounding")
                }
                if let draft, let calculation = try? draft.breakdown() {
                    LabeledContent("SST \(ExpenseCharges.percentText(draft.sstBasisPoints))%", value: Currency.display(calculation.sst, currency))
                    LabeledContent("Service Charge \(ExpenseCharges.percentText(draft.serviceBasisPoints))%", value: Currency.display(calculation.service, currency))
                    LabeledContent(tr("含税费总额", "Total with charges", "Jumlah termasuk caj"), value: Currency.display(calculation.total, currency))
                        .fontWeight(.semibold).monospacedDigit()
                        .accessibilityIdentifier("transaction.charges.total")
                    Button(tr("使用计算出的付款总额", "Use calculated payment total", "Gunakan jumlah bayaran dikira")) {
                        applyTotal(calculation.total)
                    }.disabled(actualMinor == calculation.total)
                        .accessibilityIdentifier("transaction.charges.apply")
                    if let actualMinor, actualMinor != calculation.total {
                        LabeledContent(actualMinor > calculation.total
                            ? tr("实付比计算总额多", "Payment exceeds calculated total", "Bayaran melebihi jumlah dikira")
                            : tr("实付比计算总额少", "Payment is below calculated total", "Bayaran kurang daripada jumlah dikira"),
                            value: Currency.display(abs(actualMinor - calculation.total), currency))
                            .foregroundStyle(.orange).monospacedDigit()
                            .accessibilityIdentifier("transaction.charges.difference")
                        Button(tr("检查尾数调整", "Check rounding", "Semak pembundaran")) {
                            focus.wrappedValue = .chargeRounding
                        }.buttonStyle(.borderless)
                        Text(tr("请核对实际付款与含税费总额。", "Check the actual payment against the total with charges.", "Semak bayaran sebenar dengan jumlah termasuk caj."))
                            .font(.footnote).foregroundStyle(.orange)
                    }
                } else if !subtotal.isEmpty || !sst.isEmpty || !service.isEmpty {
                    Text(tr("请填写正数小计及 0–100 的百分比，百分比最多两位小数。", "Enter a positive subtotal and percentages from 0 to 100, with up to two decimal places.", "Isi subtotal positif dan peratus 0 hingga 100, dengan sehingga dua tempat perpuluhan."))
                        .font(.footnote).foregroundStyle(.orange)
                }
            }
        } header: { Text("SST & Service Charge · \(currency)") } footer: {
            if enabled {
                Text(tr("两项都按税前小计计算，再加收据上的尾数调整（例如 -0.02）。物品填税前单价，税费和尾数按比例分摊。", "Both charges use the subtotal, then receipt rounding is added (for example -0.02). Enter base item prices; charges and rounding are allocated proportionally.", "Kedua-dua caj menggunakan subtotal, kemudian pembundaran resit ditambah (contohnya -0.02). Isi harga asas item; caj dan pembundaran diagihkan berkadar."))
            }
        }
    }
    private func percentageRow(_ title: String, value: Binding<String>, field: ExpenseInputField, identifier: String) -> some View {
        LabeledContent(title) {
            HStack(spacing: 6) {
                TextField("0", text: value).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    .focused(focus, equals: field).accessibilityIdentifier(identifier)
                    .accessibilityLabel(title + " %")
                Text("%").foregroundStyle(.secondary)
            }
        }
    }
}

struct ExpenseChargeDetails: View {
    @Environment(\.locale) private var locale
    let entry: Expense
    var body: some View {
        let _ = locale.identifier
        if let charges = entry.charges, let calculation = try? charges.breakdown() {
            Section {
                LabeledContent(tr("税前小计", "Subtotal before charges", "Subtotal sebelum caj"), value: Currency.display(charges.subtotal, charges.currency))
                LabeledContent("SST \(ExpenseCharges.percentText(charges.sstBasisPoints))%", value: Currency.display(calculation.sst, charges.currency))
                LabeledContent("Service Charge \(ExpenseCharges.percentText(charges.serviceBasisPoints))%", value: Currency.display(calculation.service, charges.currency))
                LabeledContent(tr("尾数调整", "Rounding", "Pembundaran"), value: Currency.display(charges.roundingMinor ?? 0, charges.currency))
                Divider()
                LabeledContent(tr("含税费合计", "Calculated total", "Jumlah dikira"), value: Currency.display(calculation.total, charges.currency))
                let actual = entry.foreign?.minor ?? entry.cents
                LabeledContent(tr("实付金额", "Amount paid", "Amaun dibayar"), value: Currency.display(actual, charges.currency)).fontWeight(.semibold)
                if actual != calculation.total {
                    LabeledContent(tr("差额（实付 − 合计）", "Difference (paid − total)", "Perbezaan (dibayar − jumlah)"),
                        value: Currency.display(actual - calculation.total, charges.currency)).foregroundStyle(.orange)
                }
            } header: { Text("SST & Service Charge") } footer: {
                Text(tr("税费已计入付款总额和分账。", "Charges are included in the payment and shares.", "Caj termasuk dalam bayaran dan bahagian."))
            }.monospacedDigit()
        }
    }
}
