import SwiftUI
import CoreLocation
import MapKit

struct MerchantMatchInput: Equatable {
    var name: String
    var address: String
    var latitude: Double?
    var longitude: Double?
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
        do {
            try await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled, generation == token else { return }
            loading = true
            var anchor: CLLocation?
            var precise = false
            if let lat = input.latitude, let lon = input.longitude,
               CLLocationCoordinate2DIsValid(CLLocationCoordinate2D(latitude: lat, longitude: lon)) {
                anchor = CLLocation(latitude: lat, longitude: lon); precise = true
            } else if !address.isEmpty {
                let marks = try await geocoder.geocodeAddressString(address)
                guard !Task.isCancelled, generation == token else { return }
                // A city or ambiguous address can suggest places, but cannot auto-link one.
                if marks.count == 1 {
                    anchor = marks.first?.location
                    precise = marks.first?.thoroughfare != nil
                }
            }
            let operation: MKLocalSearch
            if name.isEmpty, let anchor {
                operation = MKLocalSearch(request: MKLocalPointsOfInterestRequest(center: anchor.coordinate, radius: 500))
            } else {
                let request = MKLocalSearch.Request()
                request.naturalLanguageQuery = [name, address].filter { !$0.isEmpty }.joined(separator: " ")
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
                ranked.append(MerchantMatchCandidate(id: id, name: title, distance: distance))
            }
            loading = false; search = nil
            if precise, let id = MerchantMatching.automaticID(name: name, candidates: ranked) {
                automatic = places.first { $0.applePlaceID == id }
            } else {
                candidates = Array(places.prefix(6))
                message = places.isEmpty
                    ? tr("没有找到对应店铺，可保留地点或搜索店名。", "No matching place found. Keep this location or search by name.", "Tiada tempat sepadan. Kekalkan lokasi atau cari nama kedai.")
                    : tr("请选择正确店铺，避免关联到附近其他商户。", "Choose the correct place from nearby matches.", "Pilih kedai yang betul daripada padanan berdekatan.")
            }
        } catch {
            guard !Task.isCancelled, generation == token else { return }
            loading = false; search = nil
            message = tr("暂时无法匹配店铺，仍可保存地点或搜索店名。", "Matching unavailable. You can still save the location or search by name.", "Padanan tidak tersedia. Anda masih boleh simpan lokasi atau cari nama kedai.")
        }
    }
}

@MainActor
final class ExpensePlaceLocator: NSObject, ObservableObject, CLLocationManagerDelegate {
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
}

struct ExpensePlaceMapSheet: View {
    let initial: ExpensePlace?
    var merchantHint: String = ""
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
    init(initial: ExpensePlace?, merchantHint: String = "", onSave: ((ExpensePlace) -> Void)? = nil) {
        self.initial = initial
        self.merchantHint = merchantHint
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
        let expected = typedName != selected?.name && !generic.contains(typedName) ? typedName : merchantHint
        let sameAddress = address.trimmingCharacters(in: .whitespacesAndNewlines) == selected?.address
        return MerchantMatchInput(name: expected, address: address, latitude: sameAddress ? selected?.latitude : nil,
                                  longitude: sameAddress ? selected?.longitude : nil)
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
            applePlaceID: unchanged ? selected?.applePlaceID : nil)
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    mapCard
                    merchantSuggestions
                    if #available(iOS 18.0, *) {
                        AppleMerchantCard(placeID: draft.applePlaceID)
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
                        }.padding(18).background(.background, in: RoundedRectangle(cornerRadius: 22))
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(draft.name).font(.title3.weight(.semibold))
                            Text(draft.address).font(.subheadline).foregroundStyle(.secondary)
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
            }
            .background(IslandTheme.paper)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(tr("消费地点", "Spending location", "Lokasi belanja"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(editing ? tr("取消", "Cancel", "Batal") : tr("完成", "Done", "Selesai")) {
                        if hasChanges { confirmingDiscard = true } else { dismiss() }
                    }
                }
                if editing {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(tr("完成", "Done", "Selesai")) { onSave?(draft); dismiss() }
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
            .onChange(of: placeID) { _, _ in cancel(); presentedItem = nil; message = nil }
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
