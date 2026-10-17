import SwiftUI
import CoreLocation

@MainActor
final class ExpensePlaceLocator: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var result: ExpensePlace?
    @Published var busy = false
    @Published var message: String?
    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var timeout: Task<Void, Never>?
    private var requestID = UUID()
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
            latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
    }
    func start(automatic: Bool = false) {
        // First permission is requested by the visible location action. Once
        // granted, new forms locate automatically without another confirmation.
        if automatic && manager.authorizationStatus != .authorizedWhenInUse && manager.authorizationStatus != .authorizedAlways { return }
        cancel()
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
                    latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
                self.cancel(); self.result = place
            }
        }
    }
}

struct ExpensePlaceField: View {
    @Binding var place: ExpensePlace?
    var automatic: Bool
    @StateObject private var locator = ExpensePlaceLocator()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var started = false
    @State private var editing = false
    @State private var name = ""
    @State private var address = ""
    var body: some View {
        Section {
            Button {
                locator.cancel(); name = place?.name ?? ""; address = place?.address ?? ""; editing = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "mappin.and.ellipse").foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(place?.name ?? tr("添加消费地点", "Add spending location", "Tambah lokasi belanja"))
                        if let place, !place.address.isEmpty { Text(place.address).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                    }
                    Spacer()
                    if locator.busy { ProgressView().controlSize(.small) }
                    else { Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary) }
                }.contentTransition(.opacity)
            }.buttonStyle(.plain).accessibilityIdentifier("transaction.place.edit")
            Button { locator.start() } label: {
                Label(tr("使用当前位置", "Use current location", "Gunakan lokasi semasa"), systemImage: "location")
            }.disabled(locator.busy).accessibilityIdentifier("transaction.place.locate")
            if let message = locator.message { Text(message).font(.caption).foregroundStyle(.secondary) }
            if place != nil {
                Button(tr("移除地点", "Remove location", "Buang lokasi"), role: .destructive) { locator.cancel(); place = nil }
            }
        } header: { Text(tr("消费地点 · 选填", "Spending location · optional", "Lokasi belanja · pilihan")) } footer: {
            Text(tr("授权后，新账目会自动获取当前位置；地点不对可修改。", "After permission, new entries use your current location automatically. You can edit it.", "Selepas kebenaran, rekod baharu menggunakan lokasi semasa secara automatik. Anda boleh mengubahnya."))
        }
        .task(id: automatic) {
            guard automatic, !started else { return }; started = true
            if place == nil { locator.start(automatic: true) }
        }
        .onDisappear { locator.cancel() }
        .onChange(of: place) { _, value in
            if value != locator.result { locator.cancel() }
        }
        .onChange(of: locator.result) { _, value in
            guard let value else { return }
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { place = value }
        }
        .sheet(isPresented: $editing) {
            NavigationStack {
                Form {
                    TextField(tr("地点名称", "Place name", "Nama tempat"), text: $name)
                    TextField(tr("地址", "Address", "Alamat"), text: $address, axis: .vertical)
                }.navigationTitle(tr("消费地点", "Spending location", "Lokasi belanja"))
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button(tr("取消", "Cancel", "Batal")) { editing = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(tr("完成", "Done", "Selesai")) {
                            let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
                            let a = address.trimmingCharacters(in: .whitespacesAndNewlines)
                            // A manually changed address must not retain an unrelated GPS pin.
                            place = ExpensePlace(name: n.isEmpty ? a : n, address: a,
                                latitude: a == place?.address && n == place?.name ? place?.latitude : nil,
                                longitude: a == place?.address && n == place?.name ? place?.longitude : nil)
                            editing = false
                        }.disabled((name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) || name.count > 500 || address.count > 2000)
                    }
                }
            }
        }
    }
}

struct ExpensePlaceDetails: View {
    let place: ExpensePlace
    private var mapURL: URL? {
        var url = URLComponents(string: "https://maps.apple.com/")!
        url.queryItems = [URLQueryItem(name: "q", value: place.name + " " + place.address)]
        if let lat = place.latitude, let lon = place.longitude {
            url.queryItems?.append(URLQueryItem(name: "ll", value: "\(lat),\(lon)"))
        }
        return url.url
    }
    var body: some View {
        Section(tr("消费地点", "Spending location", "Lokasi belanja")) {
            if let url = mapURL {
                Link(destination: url) {
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
                if let rounding = charges.roundingMinor, rounding != 0 {
                    LabeledContent(tr("尾数调整", "Rounding", "Pembundaran"), value: Currency.display(rounding, charges.currency))
                }
            } header: { Text("SST & Service Charge") } footer: {
                Text(tr("税费已计入付款总额和分账。", "Charges are included in the payment and shares.", "Caj termasuk dalam bayaran dan bahagian."))
            }
        }
    }
}
