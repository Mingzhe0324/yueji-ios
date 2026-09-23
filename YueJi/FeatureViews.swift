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
                    NavigationLink(tr("本月固定消费预览", "Preview this month's bills", "Pratonton bil bulan ini")) { UpcomingView(initialMonth: Date()) }
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

struct DuplicateReviewView: View {
    @EnvironmentObject var model: LedgerModel
    @State private var deleting: Expense?
    var body: some View {
        List {
            Text(tr("相同原币金额、24 小时内同商户，或同日不同来源的记录会列为疑似重复。这里只提示，不自动合并或删除。最多显示 200 组。", "Same original amount and merchant within 24 hours, or different sources on the same day, are flagged. Nothing is merged or deleted automatically. Up to 200 pairs.", "Amaun asal dan peniaga sama dalam 24 jam, atau sumber berbeza pada hari sama, ditandakan. Tiada gabungan atau pemadaman automatik. Sehingga 200 pasangan.")).font(.footnote)
            let pairs = model.ledger.duplicatePairs()
            if pairs.isEmpty { ContentUnavailableView(tr("暂无疑似重复", "No suspected duplicates", "Tiada pendua disyaki"), systemImage: "checkmark.circle") }
            ForEach(pairs) { pair in
                Section {
                    ExpenseRow(entry: pair.first)
                    Button(tr("删除上面这笔", "Delete the entry above", "Padam rekod di atas"), role: .destructive) { deleting = pair.first }
                    ExpenseRow(entry: pair.second)
                    Button(tr("删除上面这笔", "Delete the entry above", "Padam rekod di atas"), role: .destructive) { deleting = pair.second }
                    Button(tr("这是两笔不同消费", "These are separate payments", "Ini dua bayaran berbeza")) { model.change { $0.dismissedDuplicates.insert(pair.id) } }
                }
            }
            Button(tr("重新检查已忽略的项目", "Review dismissed pairs again", "Semak semula pasangan diabaikan")) { model.change { $0.dismissedDuplicates = [] } }
        }.navigationTitle(tr("重复账目检查", "Duplicate review", "Semakan pendua"))
            .confirmationDialog(tr("删除此账目及其分账、还款和退款？无法自动合并这些资料。", "Delete this entry and its splits, repayments and refunds? These cannot be merged automatically.", "Padam rekod serta pembahagian dan bayaran baliknya? Data ini tidak dapat digabungkan automatik."), isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                Button(tr("确认删除", "Delete", "Padam"), role: .destructive) { if let e = deleting { model.change { $0.expenses.removeAll { $0.id == e.id } } }; deleting = nil }
            }
    }
}
struct RefundsView: View {
    @EnvironmentObject var model: LedgerModel
    let expenseID: String
    @State private var amount = ""
    @State private var date = Date()
    @State private var undo: RefundRecord?
    @State private var error: String?
    private var expense: Expense? { model.ledger.expenses.first { $0.id == expenseID } }
    var body: some View {
        Form {
            if let e = expense {
                Section(e.merchant) {
                    LabeledContent(tr("原付款", "Original payment", "Bayaran asal"), value: money(e.cents))
                    LabeledContent(tr("已退款", "Refunded", "Dipulangkan"), value: money(e.refunded))
                    LabeledContent(tr("净消费（含朋友）", "Net cost (all shares)", "Kos bersih (semua bahagian)"), value: money(e.cents - e.refunded))
                }
                Section(tr("新增退款", "Add refund", "Tambah bayaran balik")) {
                    TextField(tr("实际收到的退款 · MYR", "Refund received · MYR", "Bayaran balik diterima · MYR"), text: $amount).keyboardType(.decimalPad)
                    DatePicker(tr("退款日期", "Refund date", "Tarikh bayaran balik"), selection: $date, displayedComponents: .date)
                    Button(tr("填入剩余全额", "Fill remaining amount", "Isi baki penuh")) { amount = Currency.input(e.cents - e.refunded, "MYR") }.disabled(e.cents == e.refunded)
                    if let n = try? toCents(amount), let parts = try? allocateRefund(n, capacities: [e.personal] + e.shares.map({ $0.cents - $0.refunded })) {
                        Text(tr("减少我的消费：", "Reduces my spending by: ", "Mengurangkan belanja saya: ") + money(parts[0]))
                        ForEach(Array(e.shares.enumerated()), id: \.element.id) { index, share in Text(share.name + ": " + money(parts[index + 1])).font(.caption) }
                    }
                    Button(tr("保存退款", "Save refund", "Simpan bayaran balik")) {
                        do { let n = try toCents(amount); try LocalStore.shared.change { try $0.addRefund(expenseID: expenseID, cents: n, date: date) }; amount = ""; model.reload() } catch { self.error = error.localizedDescription }
                    }.disabled(e.cents == e.refunded)
                } footer: { Text(tr("退款按各人剩余份额分配，并回算到原消费月份。朋友已经还款的部分会显示为你需退回的款项。外币退款按实际收到 MYR 填写，最多退至原入账额。", "Refunds are allocated proportionally to remaining shares and reduce the original spending month. Amounts already repaid by friends become payable back to them. Enter foreign refunds in actual MYR, capped at the original recorded amount.", "Bayaran balik diagih mengikut baki bahagian dan mengurangkan bulan belanja asal. Amaun yang sudah dibayar rakan perlu dipulangkan kepada mereka. Isi bayaran balik asing dalam MYR sebenar, terhad kepada amaun asal.")) }
                Section(tr("退款历史", "Refund history", "Sejarah bayaran balik")) {
                    ForEach(e.refunds ?? []) { r in
                        HStack { Text(dateLabel(r.date)); Spacer(); Text(money(r.cents)); Button(tr("撤销", "Undo", "Batal")) { undo = r } }
                    }
                }
            } else { Text(tr("记录已删除", "Entry was deleted", "Rekod telah dipadam")) }
        }.navigationTitle(tr("退款记录", "Refunds", "Bayaran balik"))
            .alert(tr("退款", "Refund", "Bayaran balik"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") {} } message: { Text(error ?? "") }
            .confirmationDialog(tr("撤销退款？若已退钱给朋友，请先核对返款记录。", "Undo refund? Check any money already returned to friends first.", "Batalkan bayaran balik? Semak wang yang sudah dipulangkan kepada rakan dahulu."), isPresented: Binding(get: { undo != nil }, set: { if !$0 { undo = nil } }), titleVisibility: .visible) {
                Button(tr("撤销", "Undo", "Batal"), role: .destructive) { if let r = undo { model.change { try $0.removeRefund(expenseID: expenseID, refundID: r.id) } }; undo = nil }
            }
    }
}
struct FriendSummaryView: View {
    @EnvironmentObject var model: LedgerModel
    var body: some View {
        List {
            Text(tr("按姓名汇总，忽略大小写和多余空格。同名的不同朋友请使用不同备注名。一次收款按最旧欠款优先分配，不自动抵扣你需退回的款项。", "Grouped by name, ignoring case and extra spaces. Use distinct names for different people. Batch receipts settle oldest debts first and do not offset money you owe back.", "Dikumpulkan mengikut nama tanpa mengira huruf besar dan ruang tambahan. Gunakan nama berbeza untuk individu berlainan. Penerimaan kelompok melangsaikan hutang tertua dahulu tanpa menolak wang yang perlu dipulangkan.")).font(.footnote)
            ForEach(model.ledger.friendBalances) { friend in
                NavigationLink { FriendDetailView(key: friend.id) } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(friend.name).font(.headline)
                        Text(tr("朋友待还：", "They owe: ", "Hutang rakan: ") + money(friend.owed))
                        if friend.payable > 0 { Text(tr("我需退回：", "I owe back: ", "Saya perlu pulangkan: ") + money(friend.payable)).foregroundStyle(.orange) }
                    }
                }
            }
        }.navigationTitle(tr("朋友欠款汇总", "Friend balances", "Baki rakan"))
    }
}
struct FriendDetailView: View {
    @EnvironmentObject var model: LedgerModel
    let key: String
    @State private var amount = ""
    @State private var date = Date()
    @State private var target: RepayTarget?
    @State private var error: String?
    var body: some View {
        Form {
            if let friend = model.ledger.friendBalances.first(where: { $0.id == key }) {
                Section { NavigationLink(tr("消费概览 · 花在哪里", "Spending overview · by category", "Ringkasan belanja · mengikut kategori")) { FriendSpendingView(friend: key) } }
                Section(friend.name) {
                    LabeledContent(tr("待收", "Receivable", "Belum diterima"), value: money(friend.owed))
                    LabeledContent(tr("需退回", "Payable back", "Perlu dipulangkan"), value: money(friend.payable))
                    TextField(tr("本次收到 · MYR", "Received now · MYR", "Diterima kini · MYR"), text: $amount).keyboardType(.decimalPad)
                    DatePicker(tr("收到日期", "Date received", "Tarikh diterima"), selection: $date, displayedComponents: .date)
                    Button(tr("分配到最旧欠款", "Allocate to oldest debts", "Agih kepada hutang tertua")) {
                        do { let n = try toCents(amount); try LocalStore.shared.change { try $0.batchRepay(friend: key, cents: n, date: date) }; model.reload(); amount = "" } catch { self.error = error.localizedDescription }
                    }.disabled(friend.owed == 0)
                }
                ForEach(model.ledger.expenses.filter { $0.shares.contains { friendKey($0.name) == key } }.sorted { $0.date < $1.date }) { e in
                    ForEach(e.shares.filter { friendKey($0.name) == key }) { share in
                        Section(e.merchant) {
                            Text(dateLabel(e.date) + " · " + money(share.owed))
                            if share.owed != 0 { Button(share.owed > 0 ? tr("单笔还款", "Repay this entry", "Bayar rekod ini") : tr("退回朋友", "Return to friend", "Pulangkan kepada rakan")) { target = RepayTarget(expense: e, share: share) } }
                        }
                    }
                }
            }
        }.navigationTitle(tr("欠款明细", "Balance details", "Butiran baki"))
            .sheet(item: $target) { RepaymentView(target: $0) }
            .alert(tr("无法保存", "Unable to save", "Tidak dapat menyimpan"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") {} } message: { Text(error ?? "") }
    }
}
struct FuelCalculatorView: View {
    @State private var distance = ""
    @State private var consumption = ""
    @State private var price = ""
    @State private var parking = "0"
    @State private var toll = "0"
    @State private var friends = 2
    @State private var includeMe = true
    private var estimate: Int? {
        guard let km = try? parseRate(distance), let litres = try? parseRate(consumption), let unit = try? parseRate(price),
              let p = optionalCost(parking), let t = optionalCost(toll) else { return nil }
        return try? FuelEstimate(distance: km, litresPer100km: litres, pricePerLitre: unit, parking: p, toll: t).total()
    }
    private func optionalCost(_ text: String) -> Int? { text == "0" || text == "0.00" || text.isEmpty ? 0 : try? toCents(text) }
    var body: some View {
        Form {
            Section(tr("行程估算", "Trip estimate", "Anggaran perjalanan")) {
                TextField(tr("总里程 km（往返请填合计）", "Total km (include return trip)", "Jumlah km (termasuk pergi balik)"), text: $distance).keyboardType(.decimalPad)
                TextField(tr("油耗 L / 100 km", "Fuel use L / 100 km", "Penggunaan L / 100 km"), text: $consumption).keyboardType(.decimalPad)
                TextField(tr("油价 MYR / L", "Fuel price MYR / L", "Harga minyak MYR / L"), text: $price).keyboardType(.decimalPad)
                TextField(tr("停车费 MYR", "Parking MYR", "Parkir MYR"), text: $parking).keyboardType(.decimalPad)
                TextField(tr("过路费 MYR", "Tolls MYR", "Tol MYR"), text: $toll).keyboardType(.decimalPad)
                Stepper(tr("朋友人数：", "Friends: ", "Bilangan rakan: ") + String(friends), value: $friends, in: 1...20)
                Toggle(tr("司机也参与分摊", "Include driver in split", "Pemandu turut berkongsi"), isOn: $includeMe)
            }
            if let total = estimate {
                let values = equalShares(total: total, count: friends, includeMe: includeMe)
                Section(tr("估算结果", "Estimated cost", "Kos anggaran")) {
                    LabeledContent(tr("合计", "Total", "Jumlah"), value: money(total))
                    ForEach(Array(values.enumerated()), id: \.offset) { i, cents in Text(tr("朋友 ", "Friend ", "Rakan ") + String(i + 1) + ": " + money(cents)) }
                    LabeledContent(tr("司机份额", "Driver's share", "Bahagian pemandu"), value: money(total - values.reduce(0, +)))
                    ShareLink(item: tr("行程费用估算", "Trip cost estimate", "Anggaran kos perjalanan") + "\n" + money(total) + "\n" + values.enumerated().map { "\($0.offset + 1): \(money($0.element))" }.joined(separator: "\n")) { Label(tr("分享估算", "Share estimate", "Kongsi anggaran"), systemImage: "square.and.arrow.up") }
                }
            } else { Text(tr("填入有效里程、油耗和油价后显示结果。", "Enter valid distance, fuel use and price to calculate.", "Isi jarak, penggunaan dan harga sah untuk mengira.")) }
            Text(tr("只计算和分享估算，不新增消费或欠款。实际付款请在已有加油 / 行程账目中分账，避免重复计算。", "Calculates and shares an estimate only; creates no expense or debt. Split the existing fuel/trip payment to avoid double counting.", "Mengira dan berkongsi anggaran sahaja; tidak mencipta belanja atau hutang. Bahagikan bayaran minyak/perjalanan sedia ada untuk elak kiraan berganda.")).font(.footnote)
        }.navigationTitle(tr("油费计算器", "Fuel calculator", "Kalkulator minyak"))
    }
}
struct UpcomingView: View {
    @EnvironmentObject var model: LedgerModel
    var initialMonth: Date
    @State private var month = Date()
    var body: some View {
        List {
            MonthPicker(month: $month)
            let upcoming = model.ledger.upcoming(in: month)
            LabeledContent(tr("尚未入账的预计金额", "Estimated unrecorded total", "Anggaran belum direkod"), value: money(upcoming.compactMap(\.myr).reduce(0, +)))
            if upcoming.contains(where: { $0.myr == nil }) { Text(tr("部分外币缺少汇率，未计入上方合计。", "Some foreign entries lack rates and are excluded from the total.", "Sesetengah rekod asing tiada kadar dan tidak termasuk jumlah.")).foregroundStyle(.orange) }
            if upcoming.isEmpty { Text(tr("所选月份没有未来待记项目。", "No upcoming entries in this month.", "Tiada rekod akan datang dalam bulan ini.")) }
            ForEach(upcoming) { charge in
                VStack(alignment: .leading, spacing: 6) {
                    Text(charge.name).font(.headline)
                    Text(dateLabel(charge.date) + " · " + Currency.display(charge.minor, charge.currency))
                    if let n = charge.myr, charge.currency != "MYR" { Text("≈ " + money(n)).font(.caption) }
                }
            }
            Text(tr("仅预览今天及以后、未入账且未暂停的固定项目；不会计入实际花费。逾期未记项目请在固定页检查。", "Preview of active, unrecorded schedules from today onward; excluded from actual spending. Review overdue entries in Recurring.", "Pratonton jadual aktif belum direkod mulai hari ini; tidak termasuk belanja sebenar. Semak rekod tertunggak dalam Berulang.")).font(.footnote)
        }.navigationTitle(tr("固定消费预览", "Upcoming bills", "Bil akan datang")).onAppear { month = initialMonth }
    }
}
struct AutomationStatusView: View {
    @EnvironmentObject var model: LedgerModel
    private func outcome(_ key: String) -> String {
        switch key {
        case "saved": return tr("成功入账", "Saved", "Disimpan")
        case "duplicate": return tr("已拦截重复", "Duplicate blocked", "Pendua disekat")
        case "checked": return tr("已检查到期项目", "Schedules checked", "Jadual disemak")
        default: return tr("失败", "Failed", "Gagal")
        }
    }
    var body: some View {
        List {
            Section {
                if let last = model.ledger.automationEvents.first(where: { $0.source == "Apple Pay" && $0.outcome == "saved" }) {
                    LabeledContent(tr("最近成功接收", "Last successful receipt", "Penerimaan berjaya terakhir"), value: dateLabel(last.date, time: true))
                } else { Text(tr("尚无成功接收日志", "No successful receipt logged yet", "Belum ada log penerimaan berjaya")) }
                Button(tr("刷新", "Refresh", "Muat semula")) { model.reload() }
                Text(tr("显示实际调用记录，不代表快捷指令已启用或签名仍有效。App 无法检测没有触发的交易，也无法判断是否漏账。最多保留 100 条；日志写入失败时无法留痕。", "Shows actual action calls, not whether Shortcuts is enabled or signing is valid. The app cannot detect transactions that never triggered or establish completeness. Keeps 100 events; storage failure may prevent logging.", "Memaparkan panggilan tindakan sebenar, bukan status pengaktifan Pintasan atau tandatangan. Aplikasi tidak dapat mengesan transaksi yang tidak tercetus atau memastikan kelengkapan. Menyimpan 100 peristiwa; kegagalan storan boleh menghalang log.")).font(.footnote)
            }
            ForEach(model.ledger.automationEvents) { event in
                VStack(alignment: .leading, spacing: 6) {
                    Text(event.source + " · " + outcome(event.outcome)).font(.headline)
                    Text(dateLabel(event.date, time: true)).font(.caption)
                    if !event.detail.isEmpty { Text(event.detail).font(.footnote).foregroundStyle(.red) }
                }
            }
        }.navigationTitle(tr("自动记账状态", "Automation status", "Status automasi"))
    }
}


struct FriendSpendingView: View {
    @EnvironmentObject var model: LedgerModel
    let friend: String
    @State private var month = Date()
    @State private var allMonths = false
    private var breakdown: FriendSpending { model.ledger.friendSpending(friend: friend, month: allMonths ? nil : month) }
    private var name: String { model.ledger.friendBalances.first { $0.id == friend }?.name ?? friend }
    var body: some View {
        List {
            Section {
                Toggle(tr("全部月份", "All months", "Semua bulan"), isOn: $allMonths)
                if !allMonths { MonthPicker(month: $month) }
                LabeledContent(tr("净消费份额", "Net spending share", "Bahagian belanja bersih"), value: money(breakdown.net))
                LabeledContent(tr("已分配退款", "Refunds allocated", "Bayaran balik diagih"), value: money(breakdown.refunds))
                LabeledContent(tr("尚欠我", "Still owes me", "Masih berhutang saya"), value: money(breakdown.owed))
                LabeledContent(tr("我需退回", "I owe back", "Saya perlu pulangkan"), value: money(breakdown.payable))
                Text(tr("按这位朋友在你记录的账目中的份额统计，不代表他的全部个人消费。退款回算原消费月份，还款不会改变花费分类。", "Uses this friend's share of entries in your ledger, not all their personal spending. Refunds reduce the original month; repayments do not change categories.", "Menggunakan bahagian rakan dalam lejar anda, bukan semua belanja peribadinya. Bayaran balik mengurangkan bulan asal; pembayaran hutang tidak mengubah kategori.")).font(.footnote)
            }
            Section(tr("分别花在哪里", "Where the money went", "Ke mana wang dibelanjakan")) {
                if breakdown.net == 0 { Text(tr("暂无净消费", "No net spending", "Tiada belanja bersih")) }
                ForEach(categories, id: \.self) { category in
                    let n = breakdown.categories[category] ?? 0
                    if n > 0 {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack { Text(categoryLabel(category)); Spacer(); Text(money(n)) }
                            ProgressView(value: Double(n), total: Double(max(breakdown.net, 1)))
                        }
                    }
                }
            }
            Section(tr("消费明细", "Spending entries", "Butiran belanja")) {
                ForEach(model.ledger.expenses.filter { e in
                    (allMonths || monthKey(e.date) == monthKey(month)) && e.shares.contains { friendKey($0.name) == friend }
                }.sorted { $0.date > $1.date }) { e in
                    let share = e.shares.filter { friendKey($0.name) == friend }.reduce(0) { $0 + $1.cents - $1.refunded }
                    VStack(alignment: .leading) {
                        HStack { Text(e.merchant); Spacer(); Text(money(share)) }
                        Text(dateLabel(e.date) + " · " + categoryLabel(e.category)).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }.navigationTitle(name)
    }
}
