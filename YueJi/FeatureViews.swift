import SwiftUI

struct RatesView: View {
    @EnvironmentObject var model: LedgerModel
    @State private var currency = "USD"
    @State private var rate = ""
    @State private var quote: RateQuote?
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        Form {
            Section {
                Picker(tr("币种", "Currency", "Mata wang"), selection: $currency) { ForEach(Currency.codes.filter { $0 != "MYR" }, id: \.self) { Text($0).tag($0) } }.disabled(busy)
                    .onChange(of: currency) { _, _ in load() }
                Text("1 \(currency) = ? MYR").font(.headline)
                TextField(tr("每单位外币折合 MYR", "MYR per foreign unit", "MYR bagi setiap unit asing"), text: $rate).keyboardType(.decimalPad)
                Button(tr("获取参考汇率", "Fetch reference rate", "Dapatkan kadar rujukan")) {
                    busy = true; let code = currency
                    Task { @MainActor in
                        defer { busy = false }
                        do { let q = try await FXService.fetch(code); quote = q; rate = q.text } catch { self.error = error.localizedDescription }
                    }
                }.disabled(busy)
                if busy { ProgressView() }
                if let q = quote { Text(q.source + " · " + dateLabel(q.date)).font(.caption) }
                Button(tr("保存汇率", "Save rate", "Simpan kadar")) { save() }.disabled(busy)
            } footer: {
                Text(tr("联网仅查询币种，不发送账目。Frankfurter 提供每日参考汇率，并非银行实时成交价。可手动填写实际汇率，断网可用已保存汇率。", "Only currency codes are sent online, never your ledger. Frankfurter provides daily reference rates, not live bank rates. You can enter actual rates manually and use saved rates offline.", "Hanya kod mata wang dihantar dalam talian, bukan lejar. Frankfurter menyediakan kadar rujukan harian, bukan kadar langsung bank. Isi kadar sebenar secara manual dan guna kadar disimpan di luar talian."))
            }
            Section(tr("已保存 · 用于未来入账", "Saved · for future entries", "Disimpan · untuk rekod akan datang")) {
                ForEach(model.ledger.rates.keys.sorted(), id: \.self) { code in
                    if let q = model.ledger.rates[code] {
                        VStack(alignment: .leading) {
                            Text("1 \(code) = \(q.text) MYR")
                            Text(q.source + " · " + dateLabel(q.date)).font(.caption).foregroundStyle(.secondary)
                            if Date().timeIntervalSince(q.date) > 7 * 86400 { Text(tr("超过 7 天，请检查是否需要更新。", "Over 7 days old. Check before using.", "Lebih 7 hari. Semak sebelum digunakan.")).font(.caption).foregroundStyle(.orange) }
                        }
                    }
                }
                Text(tr("历史账目保留原汇率，不会重算。固定消费补记时采用当前保存的汇率，请检查较早月份的补记。", "Existing entries keep their rates. Recurring catch-up uses the currently saved rate; review entries for older periods.", "Rekod sedia ada mengekalkan kadarnya. Rekod berulang tertunggak menggunakan kadar simpanan semasa; semak tempoh lama.")).font(.footnote)
            }
        }.navigationTitle(tr("币种与汇率", "Currencies & rates", "Mata wang & kadar")).onAppear { load() }
            .alert(tr("汇率", "Exchange rate", "Kadar pertukaran"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") {} } message: { Text(error ?? "") }
    }
    private func load() { quote = model.ledger.rates[currency]; rate = quote?.text ?? "" }
    private func save() {
        do {
            let value = try parseRate(rate)
            let q = quote?.value == value ? quote! : RateQuote(value: value, date: Date(), source: "Manual")
            try q.validate(); try LocalStore.shared.change { $0.rates[currency] = q }; quote = q; model.reload()
        } catch { self.error = error.localizedDescription }
    }
}
struct RecurringView: View {
    @EnvironmentObject var model: LedgerModel
    @State private var adding = false
    @State private var editing: RecurringExpense?
    @State private var deleting: RecurringExpense?
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(tr("房租、电话费、订阅等。自动入账在打开 App 或运行「补记固定消费」快捷指令时执行；不会自动付款。", "Rent, phone bills and subscriptions. Auto-recording runs when you open the app or run ‘Post recurring expenses’ in Shortcuts. It never makes payments.", "Sewa, bil telefon dan langganan. Rekod automatik berjalan apabila aplikasi dibuka atau Pintasan ‘Rekod belanja berulang’ dijalankan. Ia tidak membuat bayaran."))
                }
                if model.ledger.recurring.isEmpty { ContentUnavailableView(tr("还没有固定消费", "No recurring expenses", "Tiada belanja berulang"), systemImage: "repeat") }
                ForEach(model.ledger.recurring.sorted { $0.nextDate < $1.nextDate }) { r in
                    Section {
                        Button { editing = r } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack { Text(r.name).font(.headline); Spacer(); Text(Currency.display(r.minor, r.currency)) }
                                Text(r.cycle.label + " · " + categoryLabel(r.category)).font(.caption)
                                Text((r.active ? tr("下次：", "Next: ", "Seterusnya: ") : tr("已暂停 · ", "Paused · ", "Dijeda · ")) + dateLabel(r.nextDate)).font(.caption)
                                Text(r.autoPost ? tr("到期自动入账", "Auto-record when due", "Rekod automatik apabila tiba") : tr("手动确认入账", "Manual recording", "Rekod manual")).font(.caption).foregroundStyle(.secondary)
                            }.foregroundStyle(.primary)
                        }
                        if r.currency != "MYR", model.ledger.rates[r.currency] == nil { Text(tr("缺少汇率：保存汇率后才能入账。", "Rate missing: save a rate before recording.", "Kadar tiada: simpan kadar sebelum merekod.")).foregroundStyle(.orange).font(.caption) }
                        if r.active && r.nextDate <= Date() {
                            Button(tr("补记已到期项目", "Record due occurrences", "Rekod tempoh yang tiba")) { model.change { try $0.postDue(only: r.id, force: true) } }
                        }
                        Button(r.active ? tr("暂停", "Pause", "Jeda") : tr("恢复（跳过暂停期间）", "Resume (skip paused periods)", "Sambung (langkau tempoh dijeda)")) {
                            model.change { ledger in if r.active { if let i = ledger.recurring.firstIndex(where: { $0.id == r.id }) { ledger.recurring[i].active = false } } else { ledger.resumeRule(r.id) } }
                        }
                    }.swipeActions { Button(tr("删除", "Delete", "Padam"), role: .destructive) { deleting = r } }
                }
            }.navigationTitle(tr("固定消费", "Recurring expenses", "Belanja berulang"))
                .toolbar { Button { adding = true } label: { Image(systemName: "plus") } }
                .sheet(isPresented: $adding) { RecurringEditor(original: nil) }
                .sheet(item: $editing) { RecurringEditor(original: $0) }
                .confirmationDialog(tr("删除固定项目？已入账记录会保留。", "Delete schedule? Recorded entries will stay.", "Padam jadual? Rekod sedia ada dikekalkan."), isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                    Button(tr("删除", "Delete", "Padam"), role: .destructive) { if let r = deleting { model.change { $0.recurring.removeAll { $0.id == r.id } } }; deleting = nil }
                }
        }
    }
}
struct RecurringEditor: View {
    @EnvironmentObject var model: LedgerModel
    @Environment(\.dismiss) private var dismiss
    let original: RecurringExpense?
    @State private var name = ""
    @State private var amount = ""
    @State private var currency = "MYR"
    @State private var category = "账单"
    @State private var start = Date()
    @State private var cycle: RepeatCycle = .monthly
    @State private var autoPost = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                TextField(tr("名称，例如房租", "Name, e.g. rent", "Nama, contoh sewa"), text: $name)
                Picker(tr("币种", "Currency", "Mata wang"), selection: $currency) { ForEach(Currency.codes, id: \.self) { Text($0).tag($0) } }
                TextField(tr("金额", "Amount", "Amaun"), text: $amount).keyboardType(.decimalPad)
                Picker(tr("分类", "Category", "Kategori"), selection: $category) { ForEach(categories, id: \.self) { Text(categoryLabel($0)).tag($0) } }
                Picker(tr("周期", "Repeat", "Ulang"), selection: $cycle) { ForEach(RepeatCycle.allCases, id: \.self) { Text($0.label).tag($0) } }.disabled(original != nil)
                DatePicker(tr("首次日期", "First date", "Tarikh pertama"), selection: $start, displayedComponents: .date).disabled(original != nil)
                Toggle(tr("到期自动入账", "Automatically record when due", "Rekod automatik apabila tiba"), isOn: $autoPost)
                Text(tr("如果 Apple Pay 已自动记录这笔费用，请关闭此开关，避免重复。固定消费并非银行扣款确认。", "Turn this off if Apple Pay already records this bill, to avoid duplicates. A schedule is not confirmation of a bank charge.", "Matikan jika Apple Pay sudah merekod bil ini untuk elak pendua. Jadual bukan pengesahan caj bank.")).font(.footnote)
                Text(tr("编辑金额只影响未来未入账项目。更改周期或首次日期请暂停旧项目，再新增。每月 31 日会在短月份落到月底。", "Amount edits affect unrecorded occurrences only. To change cycle or start date, pause this schedule and create another. The 31st uses month-end in shorter months.", "Perubahan amaun hanya untuk tempoh belum direkod. Untuk ubah kitaran atau tarikh mula, jeda jadual ini dan cipta baharu. Tarikh 31 menggunakan hujung bulan bagi bulan pendek.")).font(.footnote)
            }.navigationTitle(tr("固定消费", "Recurring expense", "Belanja berulang"))
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(tr("取消", "Cancel", "Batal")) { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button(tr("保存", "Save", "Simpan")) { save() } } }
                .onAppear { if let r = original { name = r.name; currency = r.currency; amount = Currency.input(r.minor, r.currency); category = r.category; start = r.start; cycle = r.cycle; autoPost = r.autoPost } }
                .alert(tr("无法保存", "Unable to save", "Tidak dapat menyimpan"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") {} } message: { Text(error ?? "") }
        }
    }
    private func save() {
        do {
            let minor = try Currency.parse(amount, code: currency)
            var r = original ?? RecurringExpense(name: "", minor: minor, start: start)
            r.name = name.trimmingCharacters(in: .whitespacesAndNewlines); r.minor = minor; r.currency = currency; r.category = category; r.cycle = cycle; r.autoPost = autoPost
            try r.validate()
            try LocalStore.shared.change { ledger in
                if let original {
                    guard let i = ledger.recurring.firstIndex(where: { $0.id == original.id }), ledger.recurring[i] == original else { throw LedgerError.invalid(tr("项目已改变，请重新打开。", "Schedule changed. Reopen it.", "Jadual berubah. Buka semula.")) }
                    ledger.recurring[i] = r
                } else { ledger.recurring.append(r) }
            }
            model.reload(); dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
