import SwiftUI
import UniformTypeIdentifiers

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
                Picker(tr("分类", "Category", "Kategori"), selection: $category) { ForEach(model.ledger.categoryNames, id: \.self) { Text(categoryLabel($0)).tag($0) } }
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
            try r.validate(allowedCategories: model.ledger.categoryNames)
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
    @State private var custom = false
    @State private var allocations: [String: String] = [:]
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
                Section {
                    TextField(tr("实际收到的退款 · MYR", "Refund received · MYR", "Bayaran balik diterima · MYR"), text: $amount).keyboardType(.decimalPad)
                    DatePicker(tr("退款日期", "Refund date", "Tarikh bayaran balik"), selection: $date, displayedComponents: .date)
                    Button(tr("填入剩余全额", "Fill remaining amount", "Isi baki penuh")) { amount = Currency.input(e.cents - e.refunded, "MYR") }.disabled(e.cents == e.refunded)
                    Toggle(tr("指定退款分配", "Custom refund allocation", "Agihan bayaran balik sendiri"), isOn: $custom)
                    if custom {
                        RefundAllocationFields(expense: e, values: $allocations)
                    } else { RefundAllocationPreview(expense: e, amount: amount) }
                    Button(tr("保存退款", "Save refund", "Simpan bayaran balik")) {
                        do {
                            let n = try toCents(amount)
                            let distribution: [String: Int]?
                            if custom { distribution = try allocations.mapValues { try optionalMoney($0) ?? 0 } }
                            else { distribution = nil }
                            try LocalStore.shared.change { try $0.addRefund(expenseID: expenseID, cents: n, date: date, custom: distribution) }
                            amount = ""; allocations = [:]; model.reload()
                        } catch { self.error = error.localizedDescription }
                    }.disabled(e.cents == e.refunded)
                } header: {
                    Text(tr("新增退款", "Add refund", "Tambah bayaran balik"))
                } footer: { Text(tr("默认按各人剩余份额分配；开启指定分配后，填写每人的退款金额，合计须等于退款总额。退款回算原消费月份。朋友已经还款的部分会显示为你需退回的款项。外币退款按实际收到 MYR 填写，最多退至原入账额。", "Default allocation is proportional. Custom amounts must sum to the refund total. Refunds reduce the original spending month. Amounts already repaid by friends become payable back to them. Enter foreign refunds in actual MYR, capped at the original recorded amount.", "Agihan lalai mengikut baki bahagian. Amaun sendiri mesti berjumlah amaun pulangan. Pulangan mengurangkan bulan belanja asal. Amaun yang sudah dibayar rakan perlu dipulangkan kepada mereka. Isi bayaran balik asing dalam MYR sebenar, terhad kepada amaun asal.")) }
                Section(tr("退款历史", "Refund history", "Sejarah bayaran balik")) {
                    ForEach(e.refunds ?? []) { r in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack { Text(dateLabel(r.date)); Spacer(); Text(money(r.cents)); Button(tr("撤销", "Undo", "Batal")) { undo = r } }
                            Text(tr("我的退款：", "My refund: ", "Pulangan saya: ") + money(r.personalCents)).font(.caption)
                            ForEach(e.shares) { share in
                                if let cents = r.shares[share.id], cents > 0 { Text("\(share.name): \(money(cents))").font(.caption) }
                            }
                        }
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
private struct RefundAllocationPreview: View {
    let expense: Expense
    let amount: String

    private struct AllocationRow: Identifiable {
        let id: String
        let label: String
    }

    private var rows: [AllocationRow] {
        guard let cents = try? toCents(amount) else { return [] }
        let friendCapacities: [Int] = expense.shares.map { $0.cents - $0.refunded }
        let capacities: [Int] = [expense.personal] + friendCapacities
        guard let parts = try? allocateRefund(cents, capacities: capacities) else { return [] }
        let ownerTitle: String = tr("减少我的消费：", "Reduces my spending by: ", "Mengurangkan belanja saya: ")
        var result = [AllocationRow(id: "owner", label: ownerTitle + money(parts[0]))]
        for (index, share) in expense.shares.enumerated() {
            let formattedAmount: String = money(parts[index + 1])
            let label: String = "\(share.name): \(formattedAmount)"
            result.append(AllocationRow(id: "friend-" + share.id, label: label))
        }
        return result
    }

    var body: some View {
        ForEach(rows) { row in
            if row.id == "owner" {
                Text(row.label)
            } else {
                Text(row.label).font(.caption)
            }
        }
    }
}

struct FriendSummaryView: View {
    @EnvironmentObject var model: LedgerModel
    @State private var settled = false
    var body: some View {
        List {
            Text(tr("按姓名汇总，忽略大小写和多余空格。同名的不同朋友请使用不同备注名。一次收款按最旧欠款优先分配，不自动抵扣你需退回的款项。", "Grouped by name, ignoring case and extra spaces. Use distinct names for different people. Batch receipts settle oldest debts first and do not offset money you owe back.", "Dikumpulkan mengikut nama tanpa mengira huruf besar dan ruang tambahan. Gunakan nama berbeza untuk individu berlainan. Penerimaan kelompok melangsaikan hutang tertua dahulu tanpa menolak wang yang perlu dipulangkan.")).font(.footnote)
            Picker(tr("显示", "Show", "Papar"), selection: $settled) {
                Text(tr("未结清", "Outstanding", "Belum selesai")).tag(false)
                Text(tr("已结清", "Settled", "Selesai")).tag(true)
            }.pickerStyle(.segmented)
            ForEach(model.ledger.friendBalances.filter { (($0.owed == 0) && ($0.payable == 0)) == settled }) { friend in
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
                Section { NavigationLink(tr("分享朋友账单", "Share friend statement", "Kongsi penyata rakan")) { FriendStatementView(key: key) } }
                Section(friend.name) {
                    LabeledContent(tr("待收", "Receivable", "Belum diterima"), value: money(friend.owed))
                    LabeledContent(tr("我需退给朋友", "I need to return", "Saya perlu pulangkan"), value: money(friend.payable))
                    Text(tr("此金额自动计算，不能直接填写。若朋友已还款，后来商家退款，多收的部分会列在这里；请在下方对应账目点「退回朋友」，记录实际返款。", "Calculated automatically. If a merchant refunds a payment after your friend repays you, their excess payment appears here. Use Return to friend on the entry below to record money returned.", "Dikira automatik. Jika peniaga memulangkan bayaran selepas rakan membayar anda, lebihan muncul di sini. Gunakan Pulangkan kepada rakan pada rekod di bawah untuk merekod wang dipulangkan.")).font(.footnote).foregroundStyle(.secondary)
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
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var model: LedgerModel
    @State private var names = Array(repeating: "", count: 20)
    @State private var initialized = false
    @State private var feedback: String?
    @State private var draft: Expense?
    @State private var distance = ""
    @State private var consumption = ""
    @State private var price = ""
    @State private var parking = ""
    @State private var toll = ""
    @State private var friends = 2
    @State private var includeMe = true
    private var estimate: Int? {
        guard let km = try? parseRate(distance), let litres = try? parseRate(consumption), let unit = try? parseRate(price),
              let p = optionalCost(parking), let t = optionalCost(toll) else { return nil }
        return try? FuelEstimate(distance: km, litresPer100km: litres, pricePerLitre: unit, parking: p, toll: t).total()
    }
    private func shareText(total: Int, values: [Int]) -> String {
        var lines = [tr("行程费用估算", "Trip cost estimate", "Anggaran kos perjalanan"), money(total)]
        for index in values.indices {
            let name = names[index].trimmingCharacters(in: .whitespacesAndNewlines)
            let label = name.isEmpty ? tr("朋友 ", "Friend ", "Rakan ") + String(index + 1) : name
            lines.append(label + ": " + money(values[index]))
        }
        return lines.joined(separator: "\n")
    }
    private func optionalCost(_ text: String) -> Int? { text == "0" || text == "0.00" || text.isEmpty ? 0 : try? toCents(text) }
    var body: some View {
        Form {
            Section(tr("行程估算", "Trip estimate", "Anggaran perjalanan")) {
                TextField(tr("总里程 km（往返请填合计）", "Total km (include return trip)", "Jumlah km (termasuk pergi balik)"), text: $distance).keyboardType(.decimalPad)
                TextField(tr("油耗 L / 100 km", "Fuel use L / 100 km", "Penggunaan L / 100 km"), text: $consumption).keyboardType(.decimalPad)
                TextField(tr("油价 MYR / L", "Fuel price MYR / L", "Harga minyak MYR / L"), text: $price).keyboardType(.decimalPad)
                LabeledContent(tr("停车费 · MYR", "Parking · MYR", "Parkir · MYR")) {
                    TextField(tr("选填", "Optional", "Pilihan"), text: $parking).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                }
                LabeledContent(tr("过路费 · MYR", "Tolls · MYR", "Tol · MYR")) {
                    TextField(tr("选填", "Optional", "Pilihan"), text: $toll).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                }
                Stepper(tr("朋友人数：", "Friends: ", "Bilangan rakan: ") + String(friends), value: $friends, in: 0...20)
                ForEach(0..<friends, id: \.self) { index in
                    TextField(tr("朋友姓名 ", "Friend name ", "Nama rakan ") + String(index + 1), text: $names[index])
                }
                Toggle(tr("司机也参与分摊", "Include driver in split", "Pemandu turut berkongsi"), isOn: $includeMe).disabled(friends == 0)
            }
            Section(tr("常用行程资料", "Trip defaults", "Tetapan perjalanan")) {
                Button(tr("保存油耗、油价和同行朋友", "Save fuel use, price and companions", "Simpan penggunaan minyak, harga dan rakan")) {
                    do {
                        let defaults = TripDefaults(consumption: consumption, price: price, companions: Array(names.prefix(friends)), includeDriver: includeMe)
                        try defaults.validate(); try LocalStore.shared.change { $0.tripDefaults = defaults }; model.reload()
                        feedback = tr("已保存，下次打开自动填入。", "Saved. Applied next time you open the calculator.", "Disimpan. Diisi apabila kalkulator dibuka semula.")
                    } catch { feedback = error.localizedDescription }
                }
                if model.ledger.tripDefaults != nil {
                    Button(tr("清除常用资料", "Clear defaults", "Kosongkan tetapan"), role: .destructive) { model.change { $0.tripDefaults = nil } }
                }
                Text(tr("只保存油耗、油价和同行朋友；里程、停车费及过路费每次重新填写。", "Only fuel use, price and companions are saved. Enter distance, parking and tolls for each trip.", "Hanya penggunaan minyak, harga dan rakan disimpan. Isi jarak, parkir dan tol setiap perjalanan.")).font(.caption)
            }
            if let total = estimate {
                let values = equalShares(total: total, count: friends, includeMe: includeMe)
                Section(tr("估算结果", "Estimated cost", "Kos anggaran")) {
                    LabeledContent(tr("合计", "Total", "Jumlah"), value: money(total))
                    ForEach(values.indices, id: \.self) { index in
                        let title: String = tr("朋友 ", "Friend ", "Rakan ")
                        let formattedAmount: String = money(values[index])
                        Text("\(title)\(index + 1): \(formattedAmount)")
                    }
                    LabeledContent(tr("司机份额", "Driver's share", "Bahagian pemandu"), value: money(total - values.reduce(0, +)))
                    Button {
                        let shares: [Share] = values.indices.map { Share(name: names[$0], cents: values[$0]) }
                        draft = Expense(merchant: tr("行程费用", "Trip cost", "Kos perjalanan"), cents: total, category: "交通", fuel: true, shares: shares)
                    } label: {
                        Label(tr("保存到账本", "Save to ledger", "Simpan ke lejar"), systemImage: "plus.circle")
                    }.disabled(total <= 0)
                    ShareLink(item: shareText(total: total, values: values)) { Label(tr("分享估算", "Share estimate", "Kongsi anggaran"), systemImage: "square.and.arrow.up") }
                }
            } else { Text(tr("填入有效里程、油耗和油价后显示结果。", "Enter valid distance, fuel use and price to calculate.", "Isi jarak, penggunaan dan harga sah untuk mengira.")) }
            Text(tr("停车费和过路费留空按零计算。保存到账本会打开确认页面，可修改行程名称、日期、金额并填写朋友姓名。朋友人数为 0 时全部记为个人花费。若加油或行程付款已经入账，请编辑原账目分账，避免重复计费。", "Blank parking and tolls count as zero. Save to ledger opens a review where you can edit the trip, date, amount and friends' names. With zero friends, the full amount is personal spending. If the fuel or trip payment is already recorded, split the existing entry to avoid double counting.", "Parkir dan tol kosong dikira sifar. Simpan ke lejar membuka semakan nama perjalanan, tarikh, amaun dan nama rakan. Dengan sifar rakan, semua kos ialah belanja sendiri. Jika bayaran minyak atau perjalanan sudah direkod, bahagikan rekod sedia ada supaya tidak dikira dua kali.")).font(.footnote)
        }.navigationTitle(tr("油费计算器", "Fuel calculator", "Kalkulator minyak"))
            .onAppear {
                guard !initialized else { return }; initialized = true
                if let defaults = model.ledger.tripDefaults {
                    consumption = defaults.consumption; price = defaults.price; friends = defaults.companions.count; includeMe = defaults.includeDriver
                    for i in defaults.companions.indices { names[i] = defaults.companions[i] }
                }
            }
            .alert(tr("行程资料", "Trip defaults", "Tetapan perjalanan"), isPresented: Binding(get: { feedback != nil }, set: { if !$0 { feedback = nil } })) { Button("OK") {} } message: { Text(feedback ?? "") }
            .sheet(item: $draft) { entry in
                ExpenseEditor(original: nil, initialDraft: entry, onSaved: { dismiss() })
            }
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
    private func outcome(_ key: String, source: String) -> String {
        switch key {
        case "saved": return tr("成功入账", "Saved", "Disimpan")
        case "duplicate": return tr("已拦截重复", "Duplicate blocked", "Pendua disekat")
        case "checked": return source == "TNG" ? tr("通知已处理", "Notification processed", "Notifikasi diproses") : tr("已检查到期项目", "Schedules checked", "Jadual disemak")
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
                    Text(event.source + " · " + outcome(event.outcome, source: event.source)).font(.headline)
                    Text(dateLabel(event.date, time: true)).font(.caption)
                    if !event.detail.isEmpty { Text(event.detail).font(.footnote).foregroundStyle(event.outcome == "failed" ? Color.red : Color.secondary) }
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
                ForEach(model.ledger.categoryNames, id: \.self) { category in
                    let n = breakdown.categories[category] ?? 0
                    if n > 0 {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack { CategoryBadge(name: category); Spacer(); AnimatedMoney(cents: n) }
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

struct MerchantRulesView: View {
    @EnvironmentObject var model: LedgerModel
    var body: some View {
        List {
            Text(tr("修改已有账目的分类后，会记住该商户。以后 Apple Pay 入账优先使用此规则，历史记录不会批量改变。商户名称忽略大小写与多余空格。", "Changing an entry's category remembers its merchant for future Apple Pay entries. History is unchanged. Names ignore case and extra spaces.", "Mengubah kategori rekod mengingati peniaga untuk Apple Pay seterusnya. Sejarah tidak berubah. Nama mengabaikan huruf besar dan ruang tambahan.")).font(.footnote)
            ForEach(model.ledger.merchantCategories.keys.sorted(), id: \.self) { merchant in
                HStack {
                    Text(merchant); Spacer()
                    Text(categoryLabel(model.ledger.merchantCategories[merchant] ?? "其他"))
                }.swipeActions { Button(role: .destructive) { model.change { $0.merchantCategories.removeValue(forKey: merchant) } } label: { Label(tr("删除规则", "Delete rule", "Padam peraturan"), systemImage: "trash") } }
            }
        }.navigationTitle(tr("商户分类规则", "Merchant rules", "Peraturan peniaga"))
    }
}
struct FriendStatementView: View {
    @EnvironmentObject var model: LedgerModel
    let key: String
    @State private var month = Date()
    @State private var all = false
    private var statement: String { model.ledger.friendStatement(key: key, month: all ? nil : month) }
    var body: some View {
        List {
            Toggle(tr("全部月份", "All months", "Semua bulan"), isOn: $all)
            if !all { MonthPicker(month: $month) }
            Text(statement).textSelection(.enabled)
            ShareLink(item: statement) { Label(tr("分享账单", "Share statement", "Kongsi penyata"), systemImage: "square.and.arrow.up") }
        }.navigationTitle(tr("朋友账单", "Friend statement", "Penyata rakan"))
    }
}
struct RestorePreviewView: View {
    @EnvironmentObject var model: LedgerModel
    @Environment(\.dismiss) private var dismiss
    let preview: RestorePreview
    var onRestored: () -> Void
    @State private var confirm = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section(tr("待恢复的备份", "Backup to restore", "Sandaran untuk dipulihkan")) {
                    LabeledContent(tr("备份时间", "Backup created", "Masa sandaran"), value: preview.ledger.backupCreatedAt.map { dateLabel($0, time: true) } ?? tr("旧备份未记录", "Not recorded in this older backup", "Tidak direkod dalam sandaran lama"))
                    LabeledContent(tr("账目数量", "Entries", "Rekod"), value: String(preview.ledger.expenses.count))
                    LabeledContent(tr("固定消费", "Recurring bills", "Bil berulang"), value: String(preview.ledger.recurring.count))
                    LabeledContent(tr("分类规则", "Category rules", "Peraturan kategori"), value: String(preview.ledger.merchantCategories.count))
                    LabeledContent(tr("自定义分类", "Custom categories", "Kategori sendiri"), value: String(preview.ledger.customCategories.count))
                    if let first = preview.ledger.expenses.map(\.date).min(), let last = preview.ledger.expenses.map(\.date).max() {
                        Text(dateLabel(first) + " — " + dateLabel(last))
                    }
                }
                Section {
                    LabeledContent(tr("当前账目数量", "Current entries", "Rekod semasa"), value: String(model.ledger.expenses.count))
                    Text(tr("恢复会替换账本。当前数据另存为「上次导入前的数据」，不受 30 份备份轮换影响；下次恢复时会更新这份副本。通知设置属于本机设置，不随账本恢复。", "Restoring replaces the ledger. Current data is kept separately as data before last restore, outside the 30-snapshot rotation. The next restore replaces that recovery copy. Notification preferences remain on this device.", "Pemulihan menggantikan lejar. Data semasa disimpan berasingan daripada 30 sandaran sebagai data sebelum pemulihan terakhir. Pemulihan seterusnya menggantikan salinan itu. Pilihan notifikasi kekal pada peranti ini."))
                    Button(tr("恢复这份备份", "Restore this backup", "Pulihkan sandaran ini"), role: .destructive) { confirm = true }
                }
            }.navigationTitle(tr("恢复预览", "Restore preview", "Pratonton pemulihan"))
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(tr("取消", "Cancel", "Batal")) { dismiss() } } }
                .confirmationDialog(tr("确认替换当前账本？", "Replace the current ledger?", "Ganti lejar semasa?"), isPresented: $confirm, titleVisibility: .visible) {
                    Button(tr("确认恢复", "Restore", "Pulihkan"), role: .destructive) {
                        do { try LocalStore.shared.restore(preview.data); model.reload(); onRestored(); dismiss() } catch { self.error = error.localizedDescription }
                    }
                }
                .alert(tr("恢复失败", "Restore failed", "Pemulihan gagal"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") {} } message: { Text(error ?? "") }
        }
    }
}

import UserNotifications
import UIKit

struct NotificationSettingsView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var daily = UserDefaults.standard.bool(forKey: "dailyReminder")
    @State private var results = UserDefaults.standard.bool(forKey: "automationNotifications")
    @AppStorage("hideNotificationDetails") private var hideDetails = false
    @State private var time = Date()
    @State private var busy = false
    @State private var message: String?
    @State private var permission = ""
    var body: some View {
        Form {
            Section {
                Toggle(tr("每日记账提醒", "Daily spending reminder", "Peringatan belanja harian"), isOn: $daily)
                if daily { DatePicker(tr("每天提醒时间", "Daily reminder time", "Masa peringatan harian"), selection: $time, displayedComponents: .hourAndMinute) }
                Toggle(tr("自动记账结果通知", "Automatic recording notifications", "Notifikasi rekod automatik"), isOn: $results)
                Toggle(tr("隐藏通知金额和姓名", "Hide amounts and names", "Sembunyikan amaun dan nama"), isOn: $hideDetails)
                Text(tr("结果通知包含金额、商户和分类；失败时显示原因。只有快捷指令实际调用月记后才能报告结果，无法检测未触发的付款。", "Result notifications include amount, merchant and category, or a failure reason. They require Shortcuts to call YueJi; payments that never trigger it cannot be detected.", "Notifikasi mengandungi amaun, peniaga dan kategori, atau sebab kegagalan. Pintasan mesti memanggil YueJi; bayaran yang tidak mencetuskannya tidak dapat dikesan.")).font(.footnote)
                Button(tr("保存通知设置", "Save notification settings", "Simpan tetapan notifikasi")) {
                    busy = true
                    Task {
                        do {
                            let c = Calendar.current.dateComponents([.hour, .minute], from: time)
                            try await LedgerNotifications.configure(daily: daily, results: results, hour: c.hour ?? 21, minute: c.minute ?? 0)
                            message = tr("设置已保存", "Settings saved", "Tetapan disimpan")
                        } catch { message = error.localizedDescription }
                        await refreshPermission(); busy = false
                    }
                }
                if busy { ProgressView() }
            }.disabled(busy)
            Section {
                Text(permission)
                Button(tr("打开 iPhone 通知设置", "Open iPhone notification settings", "Buka tetapan notifikasi iPhone")) {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) { UIApplication.shared.open(url) }
                }
                Text(tr("每日提醒每天一次，即使当天已有账目也会提醒。系统专注模式或通知摘要可能延后显示。首次开启请允许通知；修改 App 语言后重新保存可更新提醒语言。", "Reminds once daily even if entries already exist. Focus or Scheduled Summary may delay display. Allow notifications when enabling them. Save again after changing app language to update reminder text.", "Mengingatkan sekali sehari walaupun rekod sudah ada. Focus atau ringkasan berjadual mungkin melambatkan paparan. Benarkan notifikasi semasa mengaktifkan. Simpan semula selepas menukar bahasa aplikasi.")).font(.footnote)
            }
        }.navigationTitle(tr("通知与提醒", "Notifications", "Notifikasi"))
            .task {
                let d = UserDefaults.standard
                let minutes = d.object(forKey: "reminderMinutes") == nil ? 21 * 60 : d.integer(forKey: "reminderMinutes")
                time = Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
                await refreshPermission()
            }
            .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await refreshPermission() } } }
            .alert(tr("通知设置", "Notification settings", "Tetapan notifikasi"), isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) { Button("OK") {} } message: { Text(message ?? "") }
    }
    private func refreshPermission() async {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        permission = status == .authorized || status == .provisional
            ? tr("系统通知权限：已允许", "System permission: allowed", "Kebenaran sistem: dibenarkan")
            : tr("系统通知权限：尚未允许", "System permission: not allowed yet", "Kebenaran sistem: belum dibenarkan")
    }
}

struct CategoryBadge: View {
    @EnvironmentObject var model: LedgerModel
    let name: String
    private var custom: CustomCategory? { model.ledger.customCategories.first { $0.name == name } }
    private var symbol: String {
        if let custom { return custom.icon }
        switch name {
        case "餐饮": return "fork.knife"
        case "交通": return "car.fill"
        case "购物": return "bag.fill"
        case "账单": return "doc.text.fill"
        case "娱乐": return "gamecontroller.fill"
        default: return "tag.fill"
        }
    }
    var body: some View {
        Label { Text(categoryLabel(name)) } icon: {
            Image(systemName: symbol).foregroundStyle(categoryColor(custom?.color ?? "teal"))
        }
    }
}
func categoryColor(_ name: String) -> Color {
    switch name { case "blue": return .blue; case "purple": return .purple; case "pink": return .pink; case "orange": return .orange; case "green": return .green; default: return .teal }
}
func categoryColorLabel(_ name: String) -> String {
    switch name {
    case "blue": return tr("蓝色", "Blue", "Biru")
    case "purple": return tr("紫色", "Purple", "Ungu")
    case "pink": return tr("粉色", "Pink", "Merah jambu")
    case "orange": return tr("橙色", "Orange", "Jingga")
    case "green": return tr("绿色", "Green", "Hijau")
    default: return tr("青色", "Teal", "Biru kehijauan")
    }
}
struct CategoriesView: View {
    @EnvironmentObject var model: LedgerModel
    @State private var editing: CustomCategory?
    var body: some View {
        List {
            Section(tr("内置分类", "Built-in categories", "Kategori terbina")) {
                ForEach(categories, id: \.self) { CategoryBadge(name: $0) }
            }
            Section(tr("自定义分类", "Custom categories", "Kategori sendiri")) {
                ForEach(model.ledger.customCategories) { item in
                    Button { editing = item } label: { CategoryBadge(name: item.name) }
                        .swipeActions { Button(role: .destructive) { model.change { try $0.deleteCategory(item.id) } } label: { Label(tr("删除", "Delete", "Padam"), systemImage: "trash") } }
                }
                Button(tr("新增分类", "Add category", "Tambah kategori")) { editing = CustomCategory(name: "") }
            }
            Text(tr("改名会同步已有账目、固定消费和商户规则；正在使用的分类不能直接删除。自定义名称保留你输入的语言。", "Renaming updates entries, recurring bills and merchant rules. Categories in use cannot be deleted. Custom names retain the language you enter.", "Penamaan semula mengemas kini rekod, bil berulang dan peraturan peniaga. Kategori yang digunakan tidak boleh dipadam. Nama sendiri kekal dalam bahasa yang diisi.")).font(.footnote)
        }.navigationTitle(tr("管理分类", "Manage categories", "Urus kategori"))
            .sheet(item: $editing) { CategoryEditor(initial: $0) }
    }
}
struct CategoryEditor: View {
    @EnvironmentObject var model: LedgerModel
    @Environment(\.dismiss) private var dismiss
    let initial: CustomCategory
    @State private var name = ""
    @State private var icon = "tag.fill"
    @State private var color = "teal"
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                TextField(tr("分类名称", "Category name", "Nama kategori"), text: $name)
                Picker(tr("图标", "Icon", "Ikon"), selection: $icon) {
                    ForEach(CustomCategory.icons, id: \.self) { symbol in Image(systemName: symbol).tag(symbol) }
                }
                Picker(tr("颜色", "Color", "Warna"), selection: $color) {
                    ForEach(CustomCategory.colors, id: \.self) { value in Label(categoryColorLabel(value), systemImage: "circle.fill").foregroundStyle(categoryColor(value)).tag(value) }
                }
                Label(name.isEmpty ? tr("分类预览", "Preview", "Pratonton") : name, systemImage: icon).foregroundStyle(categoryColor(color)).font(.title2).padding()
            }.navigationTitle(tr("自定义分类", "Custom category", "Kategori sendiri"))
                .onAppear { name = initial.name; icon = initial.icon; color = initial.color }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button(tr("取消", "Cancel", "Batal")) { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button(tr("保存", "Save", "Simpan")) {
                        do {
                            var item = initial; item.name = name; item.icon = icon; item.color = color
                            try LocalStore.shared.change { try $0.saveCategory(item) }; model.reload(); dismiss()
                        } catch { self.error = error.localizedDescription }
                    } }
                }
                .alert(tr("无法保存", "Unable to save", "Tidak dapat menyimpan"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") {} } message: { Text(error ?? "") }
        }
    }
}
struct SpendingComparisonView: View {
    @EnvironmentObject var model: LedgerModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State var month: Date
    private var previous: Date { shiftedMonth(month, by: -1) }
    var body: some View {
        List {
            MonthPicker(month: $month)
            Section(tr("个人净消费", "Personal net spending", "Belanja bersih peribadi")) {
                ComparisonRow(name: tr("总计", "Total", "Jumlah"), current: model.ledger.spending(in: month), previous: model.ledger.spending(in: previous))
                Text(monthKey(month) + " / " + monthKey(previous)).font(.caption)
                Text(tr("按两个完整自然月内已记录的账目比较；本月未结束时也不会按天折算。退款扣回原消费月份，朋友还款不算收入。", "Compares recorded entries in the two calendar months, without prorating an unfinished month. Refunds reduce the original month; repayments are not income.", "Membandingkan rekod dua bulan kalendar tanpa prorata bulan belum tamat. Pulangan mengurangkan bulan asal; bayaran balik hutang bukan pendapatan.")).font(.footnote)
            }
            Section(tr("分类变化", "Category changes", "Perubahan kategori")) {
                ForEach(model.ledger.categoryNames, id: \.self) { category in
                    let current = model.ledger.spending(in: month, category: category)
                    let prior = model.ledger.spending(in: previous, category: category)
                    if current > 0 || prior > 0 { ComparisonRow(name: categoryLabel(category), current: current, previous: prior) }
                }
            }
        }.navigationTitle(tr("月度对比", "Monthly comparison", "Perbandingan bulanan"))
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: month)
    }
}
private struct ComparisonRow: View {
    let name: String
    let current: Int
    let previous: Int
    private var change: String {
        let difference = current - previous
        if previous == 0 { return current == 0 ? tr("无变化", "No change", "Tiada perubahan") : tr("上月为零，新增 ", "Previous month zero; added ", "Bulan lalu sifar; tambahan ") + money(current) }
        let percent = String(format: "%.1f%%", Double(abs(difference)) / Double(previous) * 100)
        let prefix = difference >= 0 ? "+" : "−"
        return prefix + money(abs(difference)) + " · " + prefix + percent
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(name).font(.headline)
            HStack { Text(tr("所选月", "Selected", "Dipilih")); Spacer(); AnimatedMoney(cents: current) }
            ProgressView(value: Double(current), total: Double(max(1, max(current, previous)))).tint(.teal)
            HStack { Text(tr("上个月", "Previous", "Bulan lalu")); Spacer(); Text(money(previous)) }.foregroundStyle(.secondary)
            ProgressView(value: Double(previous), total: Double(max(1, max(current, previous)))).tint(.gray)
            Text(change).font(.caption).foregroundStyle(current > previous ? Color.orange : Color.secondary)
        }.padding(.vertical, 6)
    }
}
struct AnimatedMoney: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let cents: Int
    var body: some View {
        Text(money(cents)).monospacedDigit()
            .contentTransition(reduceMotion ? .identity : .numericText(value: Double(cents)))
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.28), value: cents)
    }
}
struct LedgerFilterEditor: View {
    @EnvironmentObject var model: LedgerModel
    @Environment(\.dismiss) private var dismiss
    @State var value: LedgerFilter
    let apply: (LedgerFilter) -> Void
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Picker(tr("分类", "Category", "Kategori"), selection: $value.category) {
                    Text(tr("全部", "All", "Semua")).tag("")
                    ForEach(model.ledger.categoryNames, id: \.self) { Text(categoryLabel($0)).tag($0) }
                }
                Picker(tr("来源", "Source", "Sumber"), selection: $value.source) {
                    Text(tr("全部", "All", "Semua")).tag("")
                    ForEach(["手动", "Apple Pay", "TNG", "固定消费"], id: \.self) { Text(sourceLabel($0)).tag($0) }
                }
                TextField(tr("最低金额 · MYR（选填）", "Minimum · MYR (optional)", "Minimum · MYR (pilihan)"), text: $value.minimum).keyboardType(.decimalPad)
                TextField(tr("最高金额 · MYR（选填）", "Maximum · MYR (optional)", "Maksimum · MYR (pilihan)"), text: $value.maximum).keyboardType(.decimalPad)
                Text(tr("按当前月份、原入账总金额 MYR 筛选，包含朋友份额，未扣退款。商户可在账本搜索框输入。", "Filters the selected month by original total MYR, including friends' shares and before refunds. Search merchants in the ledger search field.", "Menapis bulan dipilih mengikut jumlah asal MYR termasuk bahagian rakan sebelum pulangan. Cari peniaga dalam carian lejar.")).font(.footnote)
                Button(tr("清除筛选", "Clear filters", "Kosongkan penapis")) { value = LedgerFilter(); apply(value); dismiss() }
            }.navigationTitle(tr("筛选账目", "Filter entries", "Tapis rekod"))
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button(tr("取消", "Cancel", "Batal")) { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button(tr("应用", "Apply", "Guna")) { do { try value.validate(); apply(value); dismiss() } catch { self.error = error.localizedDescription } } }
                }
                .alert(tr("筛选条件无效", "Invalid filter", "Penapis tidak sah"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") {} } message: { Text(error ?? "") }
        }
    }
}

struct RefundAllocationFields: View {
    let expense: Expense
    @Binding var values: [String: String]
    private func binding(_ key: String) -> Binding<String> {
        Binding(get: { values[key] ?? "" }, set: { values[key] = $0 })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(tr("填写每人的退款 · MYR（留空为零）", "Refund per person · MYR (blank is zero)", "Pulangan setiap orang · MYR (kosong ialah sifar)")).font(.caption)
            LabeledContent(tr("我的退款", "My refund", "Pulangan saya")) {
                TextField(money(expense.personal), text: binding("owner")).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
            }
            Text(tr("我的可退上限：", "My remaining limit: ", "Had baki saya: ") + money(expense.personal)).font(.caption).foregroundStyle(.secondary)
            ForEach(expense.shares) { share in
                LabeledContent(share.name) {
                    TextField(tr("退款金额", "Refund amount", "Amaun pulangan"), text: binding(share.id)).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                }
                Text(tr("可退上限：", "Remaining limit: ", "Had baki: ") + money(share.cents - share.refunded)).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct CSVExportView: View {
    @EnvironmentObject var model: LedgerModel
    @State private var month = Date()
    @State private var all = false
    @State private var splits = false
    @State private var exporting = false
    @State private var document: CSVDocument?
    var body: some View {
        Form {
            Section {
                Toggle(tr("全部月份", "All months", "Semua bulan"), isOn: $all)
                if !all { MonthPicker(month: $month) }
                Picker(tr("导出内容", "Export content", "Kandungan eksport"), selection: $splits) {
                    Text(tr("消费明细", "Expense details", "Butiran belanja")).tag(false)
                    Text(tr("朋友分账明细", "Friend split details", "Butiran bahagian rakan")).tag(true)
                }
                Text(tr("消费明细保留原币金额和汇率；分账明细包含每人的份额、退款、已还、已退回及剩余欠款。所有统计金额使用 MYR。按消费月份选取，还款余额为截至导出时的状态。", "Expenses include original currency and rate. Splits include each person's share, refunds, repayments, returns and outstanding balance in MYR. Filtered by spending month, with balances as of export.", "Belanja termasuk mata wang asal dan kadar. Bahagian termasuk amaun, pulangan, bayaran dan baki setiap rakan dalam MYR. Ditapis mengikut bulan belanja, dengan baki semasa eksport.")).font(.footnote)
                Button {
                    document = CSVDocument(data: model.ledger.csv(month: all ? nil : month, splits: splits)); exporting = true
                } label: { Label(tr("导出 CSV 文件", "Export CSV file", "Eksport fail CSV"), systemImage: "square.and.arrow.up") }
            }
            Text(tr("可用 Excel 打开。CSV 用于查看和整理，不是可恢复的完整备份；完整备份请使用 JSON 导出。", "Opens in Excel. CSV is for review, not full backup restoration; use JSON for backups.", "Boleh dibuka dalam Excel. CSV untuk semakan, bukan pemulihan penuh; gunakan JSON untuk sandaran.")).font(.footnote)
        }.navigationTitle(tr("导出 Excel / CSV", "Export Excel / CSV", "Eksport Excel / CSV"))
            .fileExporter(isPresented: $exporting, document: document, contentType: .commaSeparatedText, defaultFilename: "YueJi-\(splits ? "splits" : "expenses")-\(all ? "all" : monthKey(month))") { result in
                if case .failure(let error) = result { model.error = error.localizedDescription }
            }
    }
}

func tngStatus(_ notice: TNGNotice) -> String {
    switch notice.status {
    case "recorded": return tr("已记消费", "Expense recorded", "Belanja direkod")
    case "transfer": return tr("转账 · 不计消费", "Transfer · excluded", "Pindahan · dikecualikan")
    case "ignored": return tr("已排除消费", "Excluded", "Dikecualikan")
    default: return notice.possibleDuplicate ? tr("疑似重复 · 待确认", "Possible duplicate · review", "Mungkin pendua · semak") : tr("待确认", "Needs review", "Perlu semakan")
    }
}
struct TNGInboxView: View {
    @EnvironmentObject var model: LedgerModel
    @State private var pendingOnly = false
    @State private var clearing = false
    var body: some View {
        List {
            NavigationLink(tr("TNG 接入步骤", "TNG setup", "Persediaan TNG")) { TNGSetupView() }
            Toggle(tr("只看待确认", "Needs review only", "Perlu semakan sahaja"), isOn: $pendingOnly)
            ForEach(model.ledger.tngNotices.filter { !pendingOnly || $0.status == "pending" }.sorted { $0.date > $1.date }) { item in
                NavigationLink { TNGNoticeView(id: item.id) } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(item.party ?? tr("TNG 通知", "TNG notification", "Notifikasi TNG")).font(.headline)
                        Text(tngStatus(item)).foregroundStyle(item.status == "pending" ? Color.orange : Color.secondary)
                        if let cents = item.cents { Text(money(cents)) }
                        Text(dateLabel(item.date, time: true)).font(.caption)
                    }
                }
            }
            if model.ledger.tngNotices.isEmpty { Text(tr("等待快捷指令传入 TNG 通知。", "Waiting for TNG notifications from Shortcuts.", "Menunggu notifikasi TNG daripada Pintasan.")) }
            Button(tr("清理已处理通知", "Clear processed notices", "Kosongkan notifikasi selesai"), role: .destructive) { clearing = true }
        }.navigationTitle(tr("TNG 通知记录", "TNG inbox", "Peti TNG"))
            .confirmationDialog(tr("清理已入账或已排除的通知原文？账本消费不删除；转账和待确认保留。清理后无法用旧原文识别重复，请先导出备份。", "Clear recorded/excluded notices? Expenses stay; transfers and pending notices remain. Old texts will no longer help detect duplicates. Export a backup first.", "Kosongkan notifikasi direkod/dikecualikan? Belanja kekal; pindahan dan semakan disimpan. Teks lama tidak lagi mengesan pendua. Eksport sandaran dahulu."), isPresented: $clearing, titleVisibility: .visible) {
                Button(tr("确认清理", "Clear", "Kosongkan"), role: .destructive) { model.change { $0.tngNotices.removeAll { $0.status == "recorded" || $0.status == "ignored" } } }
            }
    }
}
struct TNGNoticeView: View {
    @EnvironmentObject var model: LedgerModel
    let id: String
    @State private var merchant = ""
    @State private var amount = ""
    @State private var date = Date()
    @State private var category = "其他"
    @State private var initialized = false
    @State private var excluding = false
    @State private var confirming = false
    @State private var editing: Expense?
    @State private var error: String?
    private var notice: TNGNotice? { model.ledger.tngNotices.first { $0.id == id } }
    var body: some View {
        Form {
            if let notice {
                Section {
                    Text(tngStatus(notice)).font(.headline)
                    if !notice.title.isEmpty { Text(notice.title) }
                    Text(notice.body).textSelection(.enabled)
                    Text(dateLabel(notice.date, time: true)).font(.caption)
                    if notice.usesReceivedDate { Text(tr("时间为接收时间，正文没有交易日期。补录旧通知时请修改账目日期。", "Uses received time; body has no transaction date. Edit the entry date when importing an old notice.", "Menggunakan masa diterima; teks tiada tarikh transaksi. Ubah tarikh rekod bagi notifikasi lama.")).font(.caption) }
                    if notice.possibleDuplicate { Text(tr("请对照已有账目，确认是另一笔真实付款后再入账。", "Check existing entries and record only if this is a separate payment.", "Semak rekod sedia ada; rekod hanya jika bayaran berasingan.")).foregroundStyle(.orange) }
                }
                if let expenseID = notice.expenseID {
                    if let entry = model.ledger.expenses.first(where: { $0.id == expenseID }) {
                        ExpenseRow(entry: entry)
                        Button(tr("编辑消费 / 分账", "Edit expense / split", "Edit belanja / bahagian")) { editing = entry }
                    } else { Text(tr("关联消费已删除或排除，不会自动重新入账。", "Linked expense was deleted or excluded; it will not be recreated automatically.", "Belanja berkaitan dipadam atau dikecualikan; tidak dicipta semula secara automatik.")) }
                } else if notice.status != "ignored" {
                    Section(tr("确认记为消费", "Confirm as expense", "Sahkan sebagai belanja")) {
                        TextField(tr("商户 / 用途", "Merchant / purpose", "Peniaga / tujuan"), text: $merchant)
                        TextField("MYR", text: $amount).keyboardType(.decimalPad)
                        DatePicker(tr("交易日期", "Transaction date", "Tarikh transaksi"), selection: $date)
                        Picker(tr("分类", "Category", "Kategori"), selection: $category) { ForEach(model.ledger.categoryNames, id: \.self) { Text(categoryLabel($0)).tag($0) } }
                        Button(tr("计入消费", "Record expense", "Rekod belanja")) { confirming = true }
                    }
                }
                if notice.status != "ignored" {
                    Button(tr("不计消费 / 排除此通知", "Exclude from spending", "Kecualikan daripada belanja"), role: .destructive) { excluding = true }
                }
            }
        }.navigationTitle("TNG")
            .onAppear {
                guard !initialized, let n = notice else { return }; initialized = true
                merchant = n.party ?? ""; amount = n.cents.map { Currency.input($0, "MYR") } ?? ""; date = n.date
                category = model.ledger.merchantCategories[friendKey(merchant)] ?? guessCategory(merchant)
            }
            .sheet(item: $editing) { ExpenseEditor(original: $0) }
            .confirmationDialog(tr("确认新增消费？请先检查是否已有相同付款。", "Record a new expense? Check for an existing payment first.", "Rekod belanja baharu? Semak bayaran sedia ada dahulu."), isPresented: $confirming, titleVisibility: .visible) {
                Button(tr("确认入账", "Record", "Rekod")) {
                    do { let cents = try toCents(amount); try LocalStore.shared.change { try $0.confirmTNGExpense(id: id, merchant: merchant, cents: cents, date: date, category: category) }; model.reload() } catch { self.error = error.localizedDescription }
                }
            }
            .confirmationDialog(tr("排除此通知？如已自动入账，将移除关联消费；已有分账或退款时会阻止操作。", "Exclude this notice? Its linked expense will be removed unless splits or refunds exist.", "Kecualikan notifikasi? Belanja berkaitan dibuang kecuali bahagian atau pulangan wujud."), isPresented: $excluding, titleVisibility: .visible) {
                Button(tr("确认排除", "Exclude", "Kecualikan"), role: .destructive) { do { try LocalStore.shared.change { try $0.excludeTNG(id: id) }; model.reload() } catch { self.error = error.localizedDescription } }
            }
            .alert(tr("无法保存", "Unable to save", "Tidak dapat menyimpan"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") {} } message: { Text(error ?? "") }
    }
}
struct TNGSetupView: View {
    var body: some View {
        List {
            Text(tr("1. 安装此版并打开月记一次。在你已测试成功的 TNG 通知自动化里，添加「记录 TNG 通知」。", "1. Install and open YueJi once. Add Record TNG notification to your working TNG notification automation.", "1. Pasang dan buka YueJi sekali. Tambah Rekod notifikasi TNG dalam automasi TNG yang berfungsi."))
            Text(tr("2. 通知正文选蓝色 Notification → Body，不要传整张截图或手动输入 Body。标题可选；如果能取得通知日期可传入，拿不到就留空使用接收时间。交易标识没有就留空，不能填固定文字。", "2. Map Notification → Body to notification body. Do not pass screenshots or type Body literally. Title and notification date are optional; missing date uses receipt time. Leave transaction ID empty unless a genuine ID is available; never use a constant.", "2. Petakan Notification → Body ke teks notifikasi. Jangan hantar tangkap layar atau taip Body. Tajuk dan tarikh pilihan; tarikh kosong menggunakan masa diterima. Biarkan ID kosong kecuali ID sebenar tersedia; jangan guna nilai tetap."))
            Text(tr("3. 删除原测试的 Text 和 Create Note 动作，设为立即运行并启用。首次允许快捷指令访问月记。", "3. Remove the old Text and Create Note test actions. Enable immediate running and allow access to YueJi when prompted.", "3. Buang tindakan ujian Text dan Create Note. Aktifkan jalan serta-merta dan benarkan akses YueJi apabila diminta."))
            Text(tr("4. 已验证的英文付款自动入账；转账不计消费；其他格式、充值、退款、收款及疑似重复通知先待确认。只支持已验证格式，不会读取 TNG 历史流水。", "4. Verified English payment format records automatically. Transfers are excluded. Other formats, top-ups, refunds, incoming money and suspected duplicates await review. Does not read TNG transaction history.", "4. Format bayaran Inggeris disahkan direkod automatik. Pindahan dikecualikan. Format lain, tambah nilai, pulangan, wang masuk dan pendua menunggu semakan. Tidak membaca sejarah transaksi TNG."))
            Text(tr("5. 在设置开启自动记账结果通知。先核对几笔正常付款，并分别测试锁屏和解锁；通知未送达、自动化未执行或侧载签名过期都会影响记账。", "5. Enable recording-result notifications in Settings. Check real payments with the phone locked and unlocked. Missing notifications, automation not running or expired signing can prevent recording.", "5. Aktifkan notifikasi hasil rekod dalam Tetapan. Semak bayaran ketika telefon dikunci dan dibuka. Notifikasi tiada, automasi tidak berjalan atau tandatangan tamat boleh menghalang rekod."))
        }.navigationTitle(tr("TNG 接入", "TNG setup", "Persediaan TNG"))
    }
}
