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
        }.navigationTitle(tr("币种与汇率", "Currencies & rates", "Mata wang & kadar")).navigationBarTitleDisplayMode(.inline).onAppear { load() }
            .task(id: currency) {
                guard !model.isPreview else { return }
                busy = true; defer { busy = false }
                do {
                    if let q = try await AutomaticRates.shared.refresh(currency) {
                        try Task.checkCancellation(); quote = q; rate = q.text; model.reload()
                    }
                } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
            }
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject var model: LedgerModel
    @State private var adding = false
    @State private var editing: RecurringExpense?
    @State private var deleting: RecurringExpense?
    @State private var paused = false
    private var rules: [RecurringExpense] {
        model.ledger.recurring.filter { $0.active != paused }.sorted { $0.nextDate < $1.nextDate }
    }
    var body: some View {
        NavigationStack {
            List {
                Section { PageIntroduction(title: tr("让日常有条理", "A little more organized", "Harian lebih teratur"), subtitle: tr("固定消费，提前安排。", "Keep recurring expenses in view.", "Rancang belanja berulang.")) }
                    .listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))

                Section {
                    NavigationLink { UpcomingView(initialMonth: Date()) } label: {
                        SimpleSettingsRow(title: tr("本月安排", "This month's plan", "Rancangan bulan ini"), subtitle: tr("房租、账单与订阅", "Rent, bills and subscriptions", "Sewa, bil dan langganan"), symbol: "calendar", color: .teal)
                    }
                } footer: { Text(tr("这里只记账，不会替你付款。", "Records expenses; never makes payments.", "Merekod belanja; tidak membuat bayaran.")) }
                Section {
                    Picker(tr("显示", "Show", "Papar"), selection: $paused) {
                        Text(tr("进行中", "Active", "Aktif")).tag(false)
                        Text(tr("已暂停", "Paused", "Dijeda")).tag(true)
                    }.pickerStyle(.segmented).listRowBackground(Color.clear).listRowInsets(EdgeInsets())
                }
                if rules.isEmpty {
                    ContentUnavailableView {
                        Label(paused ? tr("没有暂停的项目", "No paused schedules", "Tiada jadual dijeda") : tr("把固定开销交给月记", "Keep track of regular bills", "Jejak bil tetap anda"), systemImage: "calendar.badge.clock")
                    } description: {
                        Text(tr("设置金额和周期，每次到期更好记。", "Set an amount and a repeat schedule.", "Tetapkan amaun dan jadual berulang."))
                    } actions: {
                        Button(tr("添加固定消费", "Add recurring expense", "Tambah belanja berulang")) { adding = true }.yuejiPrimaryButton()
                    }.listRowBackground(Color.clear)
                }
                ForEach(rules) { rule in
                    Section {
                        RecurringScheduleRow(rule: rule, edit: { editing = rule }, delete: { deleting = rule })
                    }
                }
            }.listStyle(.insetGrouped).animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.92), value: paused).yuejiListSurface().navigationTitle(tr("固定消费", "Recurring expenses", "Belanja berulang")).navigationBarTitleDisplayMode(.inline)
                .toolbar { Button { adding = true } label: { Image(systemName: "plus") }.guideTarget("recurring.add").accessibilityLabel(tr("添加固定消费", "Add recurring expense", "Tambah belanja berulang")) }
                .sheet(isPresented: $adding) { RecurringEditor(original: nil) }
                .sheet(item: $editing) { RecurringEditor(original: $0) }
                .confirmationDialog(tr("删除固定项目？已入账记录会保留。", "Delete schedule? Recorded entries will stay.", "Padam jadual? Rekod sedia ada dikekalkan."), isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                    Button(tr("删除", "Delete", "Padam"), role: .destructive) { if let rule = deleting { model.change { $0.recurring.removeAll { $0.id == rule.id } } }; deleting = nil }
                }
        }
    }
}
struct RecurringScheduleRow: View {
    @EnvironmentObject var model: LedgerModel
    @Environment(\.dynamicTypeSize) private var typeSize
    let rule: RecurringExpense
    let edit: () -> Void
    let delete: () -> Void
    private var layout: AnyLayout { typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 12)) }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button(action: edit) {
                layout {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(rule.name).font(.headline)
                        Text(rule.cycle.label + " · " + categoryLabel(rule.category)).font(.caption).foregroundStyle(.secondary)
                    }
                    if !typeSize.isAccessibilitySize { Spacer() }
                    Text(Currency.display(rule.minor, rule.currency)).font(.headline).monospacedDigit()
                }.foregroundStyle(.primary).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain)
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Label(rule.active ? dateLabel(rule.nextDate) : tr("已暂停", "Paused", "Dijeda"), systemImage: rule.active ? "calendar" : "pause.circle")
                        .font(.subheadline)
                    Text(rule.autoPost ? tr("到期记账 · 打开 App 时处理", "Auto-record · when app opens", "Rekod automatik · apabila aplikasi dibuka") : tr("到期后手动入账", "Record manually when due", "Rekod manual apabila tiba"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Menu {
                    Button(tr("编辑", "Edit", "Edit"), action: edit)
                    Button(rule.active ? tr("暂停", "Pause", "Jeda") : tr("恢复（跳过暂停期间）", "Resume (skip paused periods)", "Sambung (langkau tempoh dijeda)")) {
                        model.change { ledger in
                            if rule.active {
                                if let i = ledger.recurring.firstIndex(where: { $0.id == rule.id }) { ledger.recurring[i].active = false }
                            } else { ledger.resumeRule(rule.id) }
                        }
                    }
                    Button(tr("删除", "Delete", "Padam"), role: .destructive, action: delete)
                } label: { Image(systemName: "ellipsis.circle").frame(width: 44, height: 44) }
                    .buttonStyle(.borderless).accessibilityLabel(tr("项目操作", "Schedule actions", "Tindakan jadual"))
            }
            if rule.currency != "MYR", model.ledger.rates[rule.currency] == nil {
                NavigationLink { RatesView() } label: { Label(tr("先设置汇率", "Set a rate first", "Tetapkan kadar dahulu"), systemImage: "exclamationmark.circle") }
                    .foregroundStyle(.orange).font(.caption)
            }
            if rule.active && rule.nextDate <= Date() {
                Button(tr("记录已到期消费", "Record due expenses", "Rekod belanja tiba")) { model.change { try $0.postDue(only: rule.id, force: true) } }
                    .buttonStyle(.borderless).font(.subheadline.weight(.semibold))
            }
        }.padding(.vertical, 8)
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
    @State private var rateBusy = false
    @State private var rateStatus = ""
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                TextField(tr("名称，例如房租", "Name, e.g. rent", "Nama, contoh sewa"), text: $name)
                Picker(tr("币种", "Currency", "Mata wang"), selection: $currency) { ForEach(Currency.codes, id: \.self) { Text($0).tag($0) } }
                if rateBusy { ProgressView() }
                if !rateStatus.isEmpty { Text(rateStatus).font(.caption).foregroundStyle(.secondary) }
                TextField(tr("金额", "Amount", "Amaun"), text: $amount).keyboardType(.decimalPad)
                Picker(tr("分类", "Category", "Kategori"), selection: $category) { ForEach(model.ledger.categoryNames, id: \.self) { Text(categoryLabel($0)).tag($0) } }
                Picker(tr("周期", "Repeat", "Ulang"), selection: $cycle) { ForEach(RepeatCycle.allCases, id: \.self) { Text($0.label).tag($0) } }.disabled(original != nil)
                DatePicker(tr("首次日期", "First date", "Tarikh pertama"), selection: $start, displayedComponents: .date).disabled(original != nil)
                Toggle(tr("到期自动入账", "Automatically record when due", "Rekod automatik apabila tiba"), isOn: $autoPost)
                Text(tr("如果 Apple Pay 已自动记录这笔费用，请关闭此开关，避免重复。固定消费并非银行扣款确认。", "Turn this off if Apple Pay already records this bill, to avoid duplicates. A schedule is not confirmation of a bank charge.", "Matikan jika Apple Pay sudah merekod bil ini untuk elak pendua. Jadual bukan pengesahan caj bank.")).font(.footnote)
                DisclosureGroup(tr("周期与修改说明", "Schedule details", "Butiran jadual")) {
                Text(tr("编辑金额只影响未来未入账项目。更改周期或首次日期请暂停旧项目，再新增。每月 31 日会在短月份落到月底。", "Amount edits affect unrecorded occurrences only. To change cycle or start date, pause this schedule and create another. The 31st uses month-end in shorter months.", "Perubahan amaun hanya untuk tempoh belum direkod. Untuk ubah kitaran atau tarikh mula, jeda jadual ini dan cipta baharu. Tarikh 31 menggunakan hujung bulan bagi bulan pendek.")).font(.footnote)
                }
            }.navigationTitle(tr("固定消费", "Recurring expense", "Belanja berulang")).navigationBarTitleDisplayMode(.inline).presentationDragIndicator(.visible).presentationCornerRadius(28)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(tr("取消", "Cancel", "Batal")) { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button(tr("保存", "Save", "Simpan")) { save() }.disabled(rateBusy) } }
                .onAppear { if let r = original { name = r.name; currency = r.currency; amount = Currency.input(r.minor, r.currency); category = r.category; start = r.start; cycle = r.cycle; autoPost = r.autoPost } }
                .task(id: currency) {
                guard !model.isPreview else { return }
                    guard currency != "MYR" else { rateStatus = ""; return }
                    rateBusy = true; defer { rateBusy = false }
                    do {
                        if let q = try await AutomaticRates.shared.refresh(currency) {
                            try Task.checkCancellation()
                            rateStatus = q.source + " · " + dateLabel(q.date)
                            model.reload(postRecurring: false)
                        }
                    } catch {
                        if !Task.isCancelled { rateStatus = tr("汇率更新失败，请在币种与汇率中核对缓存。", "Rate refresh failed. Review cached rates in settings.", "Kemas kini kadar gagal. Semak kadar cache dalam tetapan.") }
                    }
                }
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
            model.reload(); model.showSaved(); dismiss()
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
        }.navigationTitle(tr("重复账目检查", "Duplicate review", "Semakan pendua")).navigationBarTitleDisplayMode(.inline)
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
        }.navigationTitle(tr("退款记录", "Refunds", "Bayaran balik")).navigationBarTitleDisplayMode(.inline)
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
            DisclosureGroup(tr("如何汇总", "How balances work", "Cara baki dikira")) {
            Text(tr("按姓名汇总，忽略大小写和多余空格。同名的不同朋友请使用不同备注名。一次收款按最旧欠款优先分配，不自动抵扣你需退回的款项。", "Grouped by name, ignoring case and extra spaces. Use distinct names for different people. Batch receipts settle oldest debts first and do not offset money you owe back.", "Dikumpulkan mengikut nama tanpa mengira huruf besar dan ruang tambahan. Gunakan nama berbeza untuk individu berlainan. Penerimaan kelompok melangsaikan hutang tertua dahulu tanpa menolak wang yang perlu dipulangkan.")).font(.footnote)
            }
            Picker(tr("显示", "Show", "Papar"), selection: $settled) {
                Text(tr("未结清", "Outstanding", "Belum selesai")).tag(false)
                Text(tr("已结清", "Settled", "Selesai")).tag(true)
            }.pickerStyle(.segmented)
            ForEach(model.ledger.friendBalances.filter { (($0.owed == 0) && ($0.payable == 0)) == settled }) { friend in
                NavigationLink { FriendDetailView(key: friend.id) } label: {
                    FriendBalanceRow(friend: friend)
                }
            }
        }.navigationTitle(tr("朋友欠款汇总", "Friend balances", "Baki rakan")).navigationBarTitleDisplayMode(.inline)
    }
}
struct FriendDetailView: View {
    @EnvironmentObject var model: LedgerModel
    let key: String
    @State private var amount = ""
    @State private var date = Date()
    @State private var editing: Expense?
    @State private var target: RepayTarget?
    @State private var error: String?
    var body: some View {
        Form {
            if let friend = model.ledger.friendBalances.first(where: { $0.id == key }) {
                Section { NavigationLink(tr("消费概览 · 花在哪里", "Spending overview · by category", "Ringkasan belanja · mengikut kategori")) { FriendSpendingView(friend: key) } }
                Section { NavigationLink(tr("分享朋友账单", "Share friend statement", "Kongsi penyata rakan")) { FriendStatementView(key: key) } }
                Section(friend.name) {
                    LabeledContent(tr("待收", "Receivable", "Belum diterima"), value: money(friend.owed))
                    if friend.payable > 0 {
                    LabeledContent(tr("我需退给朋友", "I need to return", "Saya perlu pulangkan"), value: money(friend.payable))
                    DisclosureGroup(tr("为什么需要退回？", "Why return money?", "Mengapa perlu pulangkan?")) {
                    Text(tr("此金额自动计算，不能直接填写。若朋友已还款，后来商家退款，多收的部分会列在这里；请在下方对应账目点「退回朋友」，记录实际返款。", "Calculated automatically. If a merchant refunds a payment after your friend repays you, their excess payment appears here. Use Return to friend on the entry below to record money returned.", "Dikira automatik. Jika peniaga memulangkan bayaran selepas rakan membayar anda, lebihan muncul di sini. Gunakan Pulangkan kepada rakan pada rekod di bawah untuk merekod wang dipulangkan.")).font(.footnote).foregroundStyle(.secondary)
                    }
                    }
                    TextField(tr("本次收到 · MYR", "Received now · MYR", "Diterima kini · MYR"), text: $amount).keyboardType(.decimalPad)
                    DatePicker(tr("收到日期", "Date received", "Tarikh diterima"), selection: $date, in: ...Date(), displayedComponents: .date)
                    if let received = try? toCents(amount), received <= friend.owed {
                        LabeledContent(tr("收款后尚欠", "Balance after receipt", "Baki selepas penerimaan"), value: money(friend.owed - received))
                    }
                    Button(tr("记录收款", "Record money received", "Rekod wang diterima")) {
                        do { let n = try toCents(amount); try LocalStore.shared.change { try $0.batchRepay(friend: key, cents: n, date: date) }; model.reload(); model.showSaved(); amount = "" } catch { self.error = error.localizedDescription }
                    }.disabled(friend.owed == 0).guideTarget("friend.repay")
                    Text(tr("收到的款项会优先抵扣最早的欠款。", "Receipts settle the oldest outstanding entries first.", "Penerimaan melangsaikan hutang tertua dahulu.")).font(.caption).foregroundStyle(.secondary)
                }
                ForEach(model.ledger.expenses.filter { $0.shares.contains { friendKey($0.name) == key } }.sorted { $0.date < $1.date }) { e in
                    ForEach(e.shares.filter { friendKey($0.name) == key }) { share in
                        Section(e.merchant) {
                            Text(dateLabel(e.date) + " · " + money(share.owed))
                            if Calendar.current.startOfDay(for: e.date) > Calendar.current.startOfDay(for: date) {
                                Label(tr("消费日期晚于收款日期，请核对", "Expense is later than receipt; check date", "Belanja selepas penerimaan; semak tarikh"), systemImage: "calendar.badge.exclamationmark")
                                    .font(.caption).foregroundStyle(.orange)
                            }
                            Button(tr("编辑原账目 / 日期", "Edit expense / date", "Edit belanja / tarikh")) { editing = e }
                            if share.owed != 0 { Button(share.owed > 0 ? tr("单笔还款", "Repay this entry", "Bayar rekod ini") : tr("退回朋友", "Return to friend", "Pulangkan kepada rakan")) { target = RepayTarget(expense: e, share: share) } }
                        }
                    }
                }
            }
        }.navigationTitle(tr("欠款明细", "Balance details", "Butiran baki")).navigationBarTitleDisplayMode(.inline)
            .sheet(item: $editing) { ExpenseEditor(original: $0) }
            .sheet(item: $target) { RepaymentView(target: $0) }
            .alert(tr("无法保存", "Unable to save", "Tidak dapat menyimpan"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") {} } message: { Text(error ?? "") }
    }
}
struct FuelCalculatorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var model: LedgerModel
    @State private var names = Array(repeating: "", count: 20)
    @State private var initialized = false
    @AppStorage("autoFuelPrice") private var autoPrice = true
    @AppStorage("fuelType") private var fuelType = "ron95"
    @State private var fuelStatus = ""
    @State private var fetchingFuel = false
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
                Toggle(tr("自动获取官方油价", "Automatic official fuel price", "Harga minyak rasmi automatik"), isOn: $autoPrice)
                if autoPrice {
                    Picker(tr("油品 / 地区", "Fuel / region", "Minyak / wilayah"), selection: $fuelType) { ForEach(FuelPriceService.types, id: \.self) { Text(FuelPriceService.label($0)).tag($0) } }
                    if fetchingFuel { ProgressView() }
                    Text(fuelStatus).font(.caption).foregroundStyle(.secondary)
                    Text(tr("BUDI95 请仅在自己符合资格且本次适用时选择。", "Choose BUDI95 only if eligible and applicable to this purchase.", "Pilih BUDI95 hanya jika layak dan terpakai untuk pembelian ini.")).font(.caption)
                }
                TextField(tr("油价 MYR / L", "Fuel price MYR / L", "Harga minyak MYR / L"), text: $price).keyboardType(.decimalPad).disabled(autoPrice)
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
            Text(tr("停车费和过路费留空按零计算。保存到账本会打开确认页面，可修改行程名称、日期、金额并填写朋友姓名。朋友人数为 0 时全部记为个人花费。若加油或行程付款已经入账，请编辑原账目分账，避免重复计费。", "Blank parking and tolls count as zero. Save to ledger opens a review where you can edit the trip, date, amount and friends' names. With zero friends, the full amount is personal spending. If the fuel or trip payment is already recorded, split the existing entry to avoid double counting.", "Parkir dan tol kosong dikira sifar. Simpan ke lejar membuka semakan nama perjalanan, tarikh, amaun dan nama rakan. Dengan sifar rakan, semua kos ialah belanja sendiri. Jika bayaran minyak atau perjalanan sudah direkod, bahagikan rekod sedia ada supaya tidak dikira dua kali.")).font(.footnote)
        }.navigationTitle(tr("油费计算器", "Fuel calculator", "Kalkulator minyak")).navigationBarTitleDisplayMode(.inline)
            .onAppear {
                guard !initialized else { return }; initialized = true
                if let defaults = model.ledger.tripDefaults {
                    consumption = defaults.consumption; price = defaults.price; friends = defaults.companions.count; includeMe = defaults.includeDriver
                    for i in defaults.companions.indices { names[i] = defaults.companions[i] }
                }
            }
            .task(id: fuelType + String(autoPrice)) {
                guard !model.isPreview else { return }
                guard autoPrice else { return }
                let type = fuelType
                fetchingFuel = true; defer { fetchingFuel = false }
                if let q = FuelPriceService.cached(type) {
                    price = NSDecimalNumber(decimal: q.price).stringValue
                    fuelStatus = "data.gov.my · " + q.effective + tr(" · 缓存", " · cached", " · cache")
                } else { price = "" }
                do {
                    let q = try await FuelPriceService.fetch(type); try Task.checkCancellation()
                    price = NSDecimalNumber(decimal: q.price).stringValue
                    fuelStatus = "MOF / data.gov.my · " + q.effective
                } catch {
                    if !Task.isCancelled { fuelStatus += tr(" · 更新失败，请检查缓存日期", " · refresh failed; check cache date", " · kemas kini gagal; semak tarikh cache") }
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
        }.navigationTitle(tr("固定消费预览", "Upcoming bills", "Bil akan datang")).navigationBarTitleDisplayMode(.inline).onAppear { month = initialMonth }
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
        }.navigationTitle(tr("自动记账状态", "Automation status", "Status automasi")).navigationBarTitleDisplayMode(.inline)
    }
}


struct FriendSpendingView: View {
    @EnvironmentObject var model: LedgerModel
    let friend: String
    @State private var month = Date()
    @State private var allMonths = true
    private var breakdown: FriendSpending { model.ledger.friendSpending(friend: friend, month: allMonths ? nil : month) }
    private var total: FriendSpending { model.ledger.friendSpending(friend: friend, month: nil) }
    private var name: String { model.ledger.friendBalances.first { $0.id == friend }?.name ?? friend }
    var body: some View {
        List {
            Section(tr("当前欠款 · 全部月份", "Current balance · all months", "Baki semasa · semua bulan")) {
                LabeledContent(tr("尚欠我", "Still owes me", "Masih berhutang saya"), value: money(total.owed))
                LabeledContent(tr("我需退回", "I owe back", "Saya perlu pulangkan"), value: money(total.payable))
            }
            Section {
                Toggle(tr("全部月份", "All months", "Semua bulan"), isOn: $allMonths)
                if !allMonths { MonthPicker(month: $month) }
                LabeledContent(tr("净消费份额", "Net spending share", "Bahagian belanja bersih"), value: money(breakdown.net))
                LabeledContent(tr("已分配退款", "Refunds allocated", "Bayaran balik diagih"), value: money(breakdown.refunds))
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
        }.navigationTitle(tr("商户分类规则", "Merchant rules", "Peraturan peniaga")).navigationBarTitleDisplayMode(.inline)
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
        }.navigationTitle(tr("朋友账单", "Friend statement", "Penyata rakan")).navigationBarTitleDisplayMode(.inline)
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
                    LabeledContent(tr("储蓄目标", "Savings goals", "Matlamat simpanan"), value: String(preview.ledger.savingsGoals.count))
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
            }.navigationTitle(tr("恢复预览", "Restore preview", "Pratonton pemulihan")).navigationBarTitleDisplayMode(.inline).presentationDragIndicator(.visible).presentationCornerRadius(28)
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
    @AppStorage("budgetAlerts") private var budgetAlerts = false
    @AppStorage("budgetAlertPercent") private var budgetPercent = 100
    @AppStorage("hideNotificationDetails") private var hideDetails = false
    @State private var time = Date()
    @State private var busy = false
    @State private var message: String?
    @State private var permission = ""
    var body: some View {
        Form {
            Section {
                Toggle(tr("达到月度预算时提醒", "Alert when monthly budget is reached", "Maklum apabila bajet bulanan dicapai"), isOn: $budgetAlerts)
                if budgetAlerts {
                    Stepper(value: $budgetPercent, in: 1...200) {
                        LabeledContent(tr("提醒比例", "Alert at", "Ingatkan pada"), value: "\(budgetPercent)%")
                    }
                    Text(tr("例如预算 RM1,000，设为 80% 时，个人消费达到 RM800 就提醒。", "For a RM1,000 budget, 80% alerts at RM800 of personal spending.", "Bagi bajet RM1,000, 80% mengingatkan pada belanja peribadi RM800."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text(tr("预算开关和比例即时保存。每月最多提醒一次，修改比例不重置本月提醒；仅计算本月个人净消费。", "Budget toggle and percentage save immediately. One alert per month; changing the percentage does not reset it. Uses this month's net personal spending.", "Suis dan peratus bajet disimpan serta-merta. Sekali sebulan; perubahan peratus tidak menetapkan semula peringatan. Menggunakan belanja peribadi bersih bulan ini."))
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section(tr("其他通知", "Other notifications", "Notifikasi lain")) {
                Toggle(tr("每日记账提醒", "Daily spending reminder", "Peringatan belanja harian"), isOn: $daily)
                if daily { DatePicker(tr("每天提醒时间", "Daily reminder time", "Masa peringatan harian"), selection: $time, displayedComponents: .hourAndMinute) }
                Toggle(tr("自动记账结果通知", "Automatic recording notifications", "Notifikasi rekod automatik"), isOn: $results)
                Toggle(tr("隐藏通知金额和姓名", "Hide amounts and names", "Sembunyikan amaun dan nama"), isOn: $hideDetails)
                Text(tr("结果通知包含金额、商户和分类；失败时显示原因。只有快捷指令实际调用月记后才能报告结果，无法检测未触发的付款。", "Result notifications include amount, merchant and category, or a failure reason. They require Shortcuts to call YueJi; payments that never trigger it cannot be detected.", "Notifikasi mengandungi amaun, peniaga dan kategori, atau sebab kegagalan. Pintasan mesti memanggil YueJi; bayaran yang tidak mencetuskannya tidak dapat dikesan.")).font(.footnote)
                Button(tr("保存其他通知设置", "Save other notification settings", "Simpan tetapan notifikasi lain")) {
                    busy = true
                    Task {
                        do {
                            let c = Calendar.current.dateComponents([.hour, .minute], from: time)
                            try await LedgerNotifications.configure(daily: daily, results: results, hour: c.hour ?? 21, minute: c.minute ?? 0, budgetAlerts: budgetAlerts)
                            await BudgetAlertService.shared.check()
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
        }.navigationTitle(tr("通知与提醒", "Notifications", "Notifikasi")).navigationBarTitleDisplayMode(.inline)
            .task {
                let d = UserDefaults.standard
                let minutes = d.object(forKey: "reminderMinutes") == nil ? 21 * 60 : d.integer(forKey: "reminderMinutes")
                time = Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
                await refreshPermission()
            }
            .onChange(of: budgetAlerts) { _, enabled in
                if enabled { Task { await enableBudgetAlerts() } }
            }
            .onChange(of: budgetPercent) { _, _ in
                Task { await BudgetAlertService.shared.check() }
            }
            .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await refreshPermission() } } }
            .alert(tr("通知设置", "Notification settings", "Tetapan notifikasi"), isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) { Button("OK") {} } message: { Text(message ?? "") }
    }
    private func enableBudgetAlerts() async {
        do {
            let allowed = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            if !allowed {
                message = tr("偏好已保存，但系统通知未获允许。请在 iPhone 设置开启月记通知。", "Preference saved, but system notifications are blocked. Enable YueJi notifications in iPhone Settings.", "Pilihan disimpan tetapi notifikasi sistem disekat. Aktifkan notifikasi YueJi dalam Tetapan iPhone.")
            }
            await refreshPermission()
            await BudgetAlertService.shared.check()
        } catch { message = error.localizedDescription }
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
        }.navigationTitle(tr("管理分类", "Manage categories", "Urus kategori")).navigationBarTitleDisplayMode(.inline)
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
            }.navigationTitle(tr("自定义分类", "Custom category", "Kategori sendiri")).navigationBarTitleDisplayMode(.inline).presentationDragIndicator(.visible).presentationCornerRadius(28)
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
        }.navigationTitle(tr("月度对比", "Monthly comparison", "Perbandingan bulanan")).navigationBarTitleDisplayMode(.inline)
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
    @State private var appeared = false
    let cents: Int
    var animateOnAppear = false
    var body: some View {
        Text(money(cents)).monospacedDigit()
            .contentTransition(reduceMotion ? .identity : .numericText(value: Double(cents)))
            .animation(reduceMotion ? nil : .spring(response: 0.46, dampingFraction: 0.9), value: cents)
            .opacity(!animateOnAppear || appeared || reduceMotion ? 1 : 0)
            .scaleEffect(!animateOnAppear || appeared || reduceMotion ? 1 : 0.96, anchor: .leading)
            .animation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.9), value: appeared)
            .onAppear { appeared = true }
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
            }.navigationTitle(tr("筛选账目", "Filter entries", "Tapis rekod")).navigationBarTitleDisplayMode(.inline).presentationDragIndicator(.visible).presentationCornerRadius(28)
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
        }.navigationTitle(tr("导出 Excel / CSV", "Export Excel / CSV", "Eksport Excel / CSV")).navigationBarTitleDisplayMode(.inline)
            .fileExporter(isPresented: $exporting, document: document, contentType: .commaSeparatedText, defaultFilename: "YueJi-\(splits ? "splits" : "expenses")-\(all ? "all" : monthKey(month))") { result in
                if case .failure(let error) = result { model.error = error.localizedDescription }
            }
    }
}

func tngStatus(_ notice: TNGNotice) -> String {
    switch notice.status {
    case "recorded": return tr("已记消费", "Expense recorded", "Belanja direkod")
    case "repayment": return tr("已确认为朋友还款", "Confirmed repayment", "Bayaran balik disahkan")
    case "income": return tr("其他收入", "Other income", "Pendapatan lain")
    case "ownTransfer": return tr("自己账户转入", "Own-account transfer", "Pindahan akaun sendiri")
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
            Section(tr("收款概览 · 全部月份", "Incoming summary · all months", "Ringkasan wang masuk · semua bulan")) {
                LabeledContent(tr("待确认收款", "Incoming to review", "Wang masuk untuk semakan"), value: String(model.ledger.tngNotices.filter { $0.kind == "incoming" && $0.status == "pending" }.count))
                LabeledContent(tr("已确认其他收入", "Confirmed other income", "Pendapatan lain disahkan"), value: money(model.ledger.tngNotices.filter { $0.kind == "incoming" && $0.status == "income" }.reduce(0) { $0 + ($1.cents ?? 0) }))
                Text(tr("其他收入保存在这里，不抵扣消费或预算；朋友还款不算收入。", "Other income is stored here, without reducing expenses or budget usage. Repayments are not income.", "Pendapatan lain disimpan di sini tanpa mengurangkan belanja atau bajet. Bayaran balik bukan pendapatan.")).font(.caption)
            }
            Toggle(tr("只看待确认", "Needs review only", "Perlu semakan sahaja"), isOn: $pendingOnly)
            ForEach(model.ledger.tngNotices.filter { !pendingOnly || $0.status == "pending" }.sorted { $0.date > $1.date }) { item in
                NavigationLink { if item.kind == "incoming" { TNGIncomingView(id: item.id) } else { TNGNoticeView(id: item.id) } } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(item.party ?? tr("TNG 通知", "TNG notification", "Notifikasi TNG")).font(.headline)
                        Text(tngStatus(item)).foregroundStyle(item.status == "pending" ? Color.orange : Color.secondary)
                        if item.cents != nil { Text(tngSignedAmount(item)).foregroundStyle(item.kind == "incoming" ? Color.green : Color.primary) }
                        Text(dateLabel(item.date, time: true)).font(.caption)
                    }
                }.guideTarget(item.kind == "incoming" ? "tng.incoming" : "tng.payment")
            }
            if model.ledger.tngNotices.isEmpty { Text(tr("等待快捷指令传入 TNG 通知。", "Waiting for TNG notifications from Shortcuts.", "Menunggu notifikasi TNG daripada Pintasan.")) }
            Button(tr("清理已处理通知", "Clear processed notices", "Kosongkan notifikasi selesai"), role: .destructive) { clearing = true }
        }.navigationTitle(tr("TNG 通知记录", "TNG inbox", "Peti TNG")).navigationBarTitleDisplayMode(.inline)
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
    var body: some View { ShortcutSetupGuide(provider: .tng) }
}

import Vision
import VisionKit
#if canImport(FoundationModels)
import FoundationModels
#endif
import CoreImage
import PhotosUI
import UIKit

struct ScannedReceipt {
    struct Item: Identifiable {
        var id = UUID()
        var name: String
        var amount: String
        var people: Set<UUID> = []
        var quantity = ""
        var unitPrice = ""
    }
    var merchant = ""
    var date: Date?
    var subtotal = ""
    var tax = ""
    var service = ""
    var discount = ""
    var rounding = ""
    var total = ""
    var items: [Item] = []
    var scanNotice = ""

    static func receiptDate(_ text: String) -> Date? {
        let formats = [(#"\b\d{4}-\d{1,2}-\d{1,2}\b"#, "yyyy-M-d"),
                       (#"\b\d{1,2}/\d{1,2}/\d{4}\b"#, "d/M/yyyy"),
                       (#"\b\d{1,2}-\d{1,2}-\d{4}\b"#, "d-M-yyyy"),
                       (#"\b\d{1,2}/\d{1,2}/\d{2}\b"#, "d/M/yy"),
                       (#"\b\d{1,2}[ -][A-Za-z]{3}[ -]\d{2,4}\b"#, "d MMM yy")]
        for (pattern, format) in formats {
            guard let range = text.range(of: pattern, options: .regularExpression) else { continue }
            let value = String(text[range]).replacingOccurrences(of: "-", with: format.contains("MMM") ? " " : "-")
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.isLenient = false
            formatter.dateFormat = format
            formatter.twoDigitStartDate = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2000, month: 1, day: 1))
            if let date = formatter.date(from: value) { return date }
        }
        return nil
    }

    static func parse(_ text: String) -> ScannedReceipt {
        var result = ScannedReceipt()
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        result.merchant = lines.first(where: { $0.rangeOfCharacter(from: .letters) != nil }) ?? ""
        let dated = lines.filter { $0.lowercased().contains("date") && !$0.lowercased().contains("printed") }
        result.date = (dated + lines).compactMap { receiptDate($0) }.first
        let regex = try! NSRegularExpression(pattern: #"(?<![\d.,])([+-]?(?:\d[\d,.]*)?[.,]\d{2})(?!\d)"#)
        var inItems = false
        var finishedItems = false
        var pendingName = ""
        var pendingField = ""
        var totalPriority = 0
        func field(_ line: String) -> String {
            let l = line.lowercased().replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            if l.contains("rounding") || l.contains("round off") { return "rounding" }
            if l.contains("sub total") || l.contains("subtotal") { return "subtotal" }
            if l.contains("net total") || l.contains("grand total") || l.contains("amt due") || l.contains("amount due") { return "final" }
            if l.contains("service") || l.contains("srv chg") || l.contains("svc chg") { return "service" }
            if l.range(of: #"\b(sst|gst|tax)\b"#, options: .regularExpression) != nil { return "tax" }
            if l.contains("discount") { return "discount" }
            if l.contains("bill amount") { return "subtotal" }
            if l.contains("total") && !l.contains("qty") && !l.contains("quantity") { return "total" }
            return ""
        }
        for (lineIndex, line) in lines.enumerated() {
            let lower = line.lowercased()
            if receiptDate(line) != nil || lower.contains("printed") { continue }
            if lower.contains("description") || lower.contains("item name") || lower == "qty" || lower.contains("unit price") {
                inItems = true; pendingName = ""; continue
            }
            if lower == "amount (rm)" || lower == "amount" || lower == "price" { continue }
            // Registration numbers, contact details and table numbers are not purchases.
            if lower.contains("sst#") || lower.contains("gst id") || lower.contains("tel") || lower.contains("table") || lower.contains("check:") || lower.contains("cover:") || lower.contains("www.") || lower.contains("@gmail") { continue }
            let kind = field(line)
            let matches = regex.matches(in: line, range: NSRange(line.startIndex..., in: line))
            guard let last = matches.last, let range = Range(last.range(at: 1), in: line) else {
                if !kind.isEmpty { pendingField = kind; finishedItems = true; pendingName = ""; continue }
                if !finishedItems && inItems && line.rangeOfCharacter(from: .letters) != nil && !lower.contains("amount") {
                    let next = lineIndex + 1 < lines.count ? lines[lineIndex + 1] : ""
                    let nextHasAmount = regex.firstMatch(in: next, range: NSRange(next.startIndex..., in: next)) != nil
                    let nextIsNumbers = next.replacingOccurrences(of: "RM", with: "", options: .caseInsensitive).rangeOfCharacter(from: .letters) == nil
                    if nextHasAmount && nextIsNumbers {
                        pendingName = pendingName.isEmpty ? line : pendingName + " " + line
                    } else if pendingName.isEmpty, let i = result.items.indices.last {
                        result.items[i].name += " " + line
                    } else { pendingName = pendingName.isEmpty ? line : pendingName + " " + line }
                }
                continue
            }
            let token = String(line[range])
            guard let decimal = token.lastIndex(where: { $0 == "." || $0 == "," }) else { continue }
            let integer = token[..<decimal].filter(\.isNumber)
            let value = (token.hasPrefix("-") ? "-" : "") + (integer.isEmpty ? "0" : String(integer)) + "." + token[token.index(after: decimal)...]
            let effective = kind.isEmpty ? pendingField : kind
            pendingField = ""
            if !effective.isEmpty {
                finishedItems = true; pendingName = ""
                switch effective {
                case "subtotal": result.subtotal = value
                case "tax": result.tax = value
                case "service": result.service = value
                case "discount": result.discount = value
                case "rounding": result.rounding = value
                case "final": result.total = value; totalPriority = 2
                case "total": if totalPriority < 2 { result.total = value; totalPriority = 1 }
                default: break
                }
                continue
            }
            guard !finishedItems else { continue }
            let firstRange = Range(matches[0].range(at: 1), in: line)!
            var label = String(line[..<firstRange.lowerBound]).replacingOccurrences(of: #"\bRM\s*$"#, with: "", options: [.regularExpression, .caseInsensitive])
            label = label.replacingOccurrences(of: #"^\s*\d+\s+"#, with: "", options: .regularExpression)
            label = label.replacingOccurrences(of: #"\s+\d+(?:[.,]\d+)?\s*@?\s*$|\s*@\s*$"#, with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces)
            let name = [pendingName, label].filter { !$0.isEmpty }.joined(separator: " ")
            guard name.rangeOfCharacter(from: .letters) != nil else { continue }
            inItems = true; pendingName = ""
            result.items.append(Item(name: name, amount: value))
        }
        return result
    }
}

struct ReceiptPerson: Identifiable {
    var id = UUID()
    var name: String
}

// Largest-remainder allocation conserves every cent, including shared dishes and charges.
enum ReceiptSplit {
    static func allocate(_ total: Int, weights: [Int]) throws -> [Int] {
        guard !weights.isEmpty, weights.allSatisfy({ $0 >= 0 && $0 <= 10_000_000_000 }),
              total >= 0, total <= 10_000_000_000, weights.reduce(0, +) > 0 else { throw LedgerError.invalid("Invalid receipt amount") }
        let sum = weights.reduce(0, +)
        let exact = weights.map { Decimal(total) * Decimal($0) / Decimal(sum) }
        var parts = exact.map { value -> Int in
            var v = value; var rounded = Decimal(); NSDecimalRound(&rounded, &v, 0, .down)
            return NSDecimalNumber(decimal: rounded).intValue
        }
        let order = weights.indices.sorted {
            let a = exact[$0] - Decimal(parts[$0]), b = exact[$1] - Decimal(parts[$1])
            return a == b ? $0 < $1 : a > b
        }
        for i in order.prefix(total - parts.reduce(0, +)) { parts[i] += 1 }
        return parts
    }
    static func food(items: [ScannedReceipt.Item], people: [UUID], subtotal: Int) throws -> [Int] {
        guard !items.isEmpty, !people.isEmpty, Set(people).count == people.count else {
            throw reviewError("请添加商品和参与者。", "Add items and people.", "Tambah item dan peserta.")
        }
        var result = Array(repeating: 0, count: people.count)
        var sum = 0
        for item in items {
            let cents = try optionalMoney(item.amount) ?? 0
            guard !item.amount.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !item.name.trimmingCharacters(in: .whitespaces).isEmpty else {
                throw reviewError("请填写商品名称和金额。", "Enter each item name and amount.", "Isi nama dan amaun setiap item.")
            }
            let owners = people.indices.filter { item.people.contains(people[$0]) }
            guard cents == 0 || (!owners.isEmpty && item.people.isSubset(of: Set(people))) else {
                throw reviewError("请为每道菜选择由谁付款。", "Choose who pays for each item.", "Pilih pembayar setiap item.")
            }
            sum += cents
            if cents > 0 {
                let parts = try allocate(cents, weights: Array(repeating: 1, count: owners.count))
                for (offset, index) in owners.enumerated() { result[index] += parts[offset] }
            }
        }
        guard sum == subtotal else {
            throw reviewError("商品合计与小计不一致，请补上漏识别的商品或修正金额。", "Items do not match the subtotal. Add missing items or correct amounts.", "Jumlah item berbeza daripada subjumlah. Tambah item tertinggal atau betulkan amaun.")
        }
        return result
    }
}

// Preserve column identity until Description and Amount are mapped.
struct ReceiptGrid {
    struct Cell {
        let text: String
        let columns: ClosedRange<Int>
    }
    struct Result {
        var items: [ScannedReceipt.Item] = []
        var summaries: [String] = []
        var foundColumns = false
    }
    static func normalized(_ text: String) -> String {
        text.lowercased().replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    static func summaryLabel(_ text: String) -> Bool {
        normalized(text).range(of: #"^(?:sub\s*total|bill amount|net total|grand total|total|amount due|amt due|sst|gst|tax|service|srv chg|svc chg|discount|rounding|round off|\d+\s*%\s*(?:srv|svc|service|tax|gst|sst))\b"#, options: .regularExpression) != nil
    }
    // One monetary value per Amount cell. Never substitute Unit Price or Quantity.
    static func amount(_ text: String) -> String? {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"^(?:RM|MYR)\s*"#, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"\s+[A-Za-z]$"#, with: "", options: .regularExpression)
        guard clean.range(of: #"^[+-]?(?:\d{1,3}(?:,\d{3})+|\d*)[.,]\d{2}$"#, options: .regularExpression) != nil,
              let separator = clean.lastIndex(where: { $0 == "." || $0 == "," }) else { return nil }
        let integer = clean[..<separator].filter(\.isNumber)
        return (clean.hasPrefix("-") ? "-" : "") + (integer.isEmpty ? "0" : String(integer)) + "." + clean[clean.index(after: separator)...]
    }
    static func parse(_ rows: [[Cell]]) -> Result {
        var result = Result()
        var descriptionColumn: Int?
        var amountColumn: Int?
        var unitPriceColumn: Int?
        var quantityColumn: Int?
        var reachedSummary = false
        var pendingName = ""
        var previousZeroWithUnitPrice = false
        for row in rows {
            let ordered = row.sorted { $0.columns.lowerBound < $1.columns.lowerBound }
            if let first = ordered.first(where: { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }), summaryLabel(first.text) {
                result.summaries.append(ordered.map(\.text).joined(separator: " "))
                reachedSummary = true; pendingName = ""; previousZeroWithUnitPrice = false
                continue
            }
            var header = false
            for cell in ordered {
                let label = normalized(cell.text)
                if ["description", "desc", "desc.", "item description", "item", "item name", "items", "product", "particulars", "butiran", "keterangan", "商品", "品名", "名称"].contains(label) {
                    // A merged description+price cell cannot establish a trustworthy column.
                    if cell.columns.count == 1 { descriptionColumn = cell.columns.lowerBound }
                    header = true
                }
                if ["amount", "amt", "amt.", "amount (rm)", "amount(rm)", "amt (rm)", "line total", "total (rm)", "jumlah", "jumlah (rm)", "金额", "总价"].contains(label) {
                    amountColumn = cell.columns.upperBound
                    header = true
                }
                if ["qty", "quantity", "数量", "kuantiti"].contains(label) { quantityColumn = cell.columns.lowerBound; header = true }
                if ["price", "harga", "unit price", "unit cost", "harga seunit", "单价"].contains(label) {
                    unitPriceColumn = cell.columns.lowerBound
                    header = true
                }
            }
            // On two-column receipts Price is the paid line amount. On receipts
            // with Quantity or Unit Price it cannot be used as the Amount column.
            if header && amountColumn == nil, let d = descriptionColumn, let p = unitPriceColumn,
               d != p && Set(ordered.flatMap { Array($0.columns) }).count == 2 {
                amountColumn = p
                unitPriceColumn = nil
            }
            if header { reachedSummary = false; pendingName = ""; previousZeroWithUnitPrice = false; continue }
            guard !reachedSummary, let d = descriptionColumn, let a = amountColumn, d != a else { continue }
            result.foundColumns = true
            let description = ordered.first { $0.columns.contains(d) && !$0.columns.contains(a) }?.text
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let amountText = ordered.first { $0.columns.lowerBound == a && $0.columns.upperBound == a }?.text ?? ""
            if description.isEmpty && amountText.isEmpty { continue }
            let value = amount(amountText) ?? ""
            let hasUnitPrice = unitPriceColumn.map { column in
                ordered.contains { $0.columns.contains(column) && !$0.columns.contains(a) && amount($0.text) != nil }
            } ?? false
            if value.isEmpty && amountText.isEmpty && !description.isEmpty {
                // Wrapped descriptions often occupy their own table row. An already
                // priced item owns the following description-only continuation.
                if !result.items.isEmpty && pendingName.isEmpty && !result.items[result.items.count - 1].amount.isEmpty {
                    result.items[result.items.count - 1].name += " " + description
                } else {
                    pendingName = [pendingName, description].filter { !$0.isEmpty }.joined(separator: " ")
                }
                continue
            }
            if value == "0.00" && previousZeroWithUnitPrice && !hasUnitPrice && !description.isEmpty && pendingName.isEmpty && !result.items.isEmpty {
                result.items[result.items.count - 1].name += " " + description
                previousZeroWithUnitPrice = false
                continue
            }
            if !pendingName.isEmpty && !description.isEmpty {
                result.items.append(ScannedReceipt.Item(name: pendingName, amount: ""))
                pendingName = ""
            }
            let name = [pendingName, description].filter { !$0.isEmpty }.joined(separator: " ")
            pendingName = ""
            // Retain ambiguous incomplete rows for explicit review.
            var item = ScannedReceipt.Item(name: name, amount: value)
            if let q = quantityColumn, let raw = ordered.first(where: { $0.columns == (q...q) })?.text,
               raw.range(of: #"^\d+(?:[.]\d+)?$"#, options: .regularExpression) != nil { item.quantity = raw }
            if let u = unitPriceColumn, u != a, let raw = ordered.first(where: { $0.columns == (u...u) })?.text { item.unitPrice = amount(raw) ?? "" }
            result.items.append(item)
            previousZeroWithUnitPrice = value == "0.00" && hasUnitPrice
        }
        if !pendingName.isEmpty { result.items.append(ScannedReceipt.Item(name: pendingName, amount: "")) }
        return result
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable
struct ReceiptAIItem {
    @Guide(description: "Full description on the receipt, including wrapped continuation lines")
    var name: String
    @Guide(description: "Printed line amount from the Amount column, including two decimal places")
    var amount: String
}

@available(iOS 26.0, *)
@Generable
struct ReceiptAIItems {
    @Guide(description: "Every purchased line item in printed order; exclude subtotal, service, tax and final total")
    var items: [ReceiptAIItem]
}

@available(iOS 26.0, *)
enum ReceiptAI {
    // The model receives text only; no receipt image, credentials or bank data
    // leave the device. A generated answer is used only when it reconciles.
    static func interpret(_ transcript: String, base: ScannedReceipt) async -> ScannedReceipt? {
        guard SystemLanguageModel.default.availability == .available,
              transcript.count <= 10_000, !base.subtotal.isEmpty, !base.total.isEmpty else { return nil }
        let session = LanguageModelSession(instructions: "Read receipt OCR text. Return only printed food or product descriptions and their line totals. Join wrapped descriptions. Never invent an item, amount, unit price or tax. Keep original item order. A line amount is different from quantity and unit price.")
        do {
            let response = try await session.respond(to: "Receipt:\n\(transcript)", generating: ReceiptAIItems.self)
            let suggestions = response.content.items
            guard !suggestions.isEmpty, suggestions.count <= 80 else { return nil }
            let evidence = Set(transcript.uppercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty })
            var candidate = base
            candidate.items = []
            for suggestion in suggestions {
                let name = suggestion.name.trimmingCharacters(in: .whitespacesAndNewlines)
                let tokens = name.uppercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
                guard !tokens.isEmpty, name.count <= 200,
                      tokens.allSatisfy({ evidence.contains($0) }),
                      !ReceiptGrid.summaryLabel(name),
                      let amount = ReceiptGrid.amount(suggestion.amount),
                      let cents = try? toCents(amount), cents >= 0 else { return nil }
                candidate.items.append(ScannedReceipt.Item(name: name, amount: amount))
            }
            guard ReceiptOCR.quality(candidate) == 4 else { return nil }
            candidate.scanNotice = tr("设备端 AI 已整理商品；请对照照片核对名称和每项金额。", "On-device AI organized the items. Check every name and amount against the photo.", "AI pada peranti menyusun item. Semak setiap nama dan amaun pada foto.")
            return candidate
        } catch { return nil }
    }
}
#endif

struct ReceiptOCR {
    // Use the plain-text pass only to restore a missing label when every row
    // already lines up with the table's Amount column in the same order.
    static func recoverNames(_ table: [ScannedReceipt.Item], from text: [ScannedReceipt.Item]) -> [ScannedReceipt.Item] {
        guard table.count == text.count, !table.isEmpty else { return table }
        for index in table.indices {
            guard table[index].amount == text[index].amount,
                  !text[index].name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return table }
            if !table[index].name.isEmpty && ReceiptGrid.normalized(table[index].name) != ReceiptGrid.normalized(text[index].name) {
                return table
            }
        }
        return table.indices.map { index in
            var item = table[index]
            if item.name.isEmpty { item.name = text[index].name }
            return item
        }
    }
    // Compare complete passes; never stitch purchases from different passes together.
    static func quality(_ receipt: ScannedReceipt) -> Int {
        guard !receipt.items.isEmpty else { return 0 }
        let values = receipt.items.compactMap { item -> Int? in
            guard !item.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !item.amount.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return try? optionalMoney(item.amount)
        }
        guard values.count == receipt.items.count else { return 1 }
        guard let base = try? toCents(receipt.subtotal), values.reduce(0, +) == base else { return 2 }
        do {
            let tax = try optionalMoney(receipt.tax) ?? 0, service = try optionalMoney(receipt.service) ?? 0
            let discount = try optionalMoney(receipt.discount) ?? 0
            let raw = receipt.rounding.trimmingCharacters(in: .whitespacesAndNewlines)
            let rounding = (try optionalMoney(raw.hasPrefix("-") ? String(raw.dropFirst()) : raw) ?? 0) * (raw.hasPrefix("-") ? -1 : 1)
            let calculated = try ReceiptCalculation.total(subtotal: base, tax: tax, service: service, discount: discount) + rounding
            return calculated == (try toCents(receipt.total)) ? 4 : 3
        } catch { return 3 }
    }
    private static func enhanced(_ data: Data) -> Data? {
        guard let image = CIImage(data: data, options: [.applyOrientationProperty: true]),
              image.extent.width * image.extent.height <= 60_000_000 else { return nil }
        let adjusted = image.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0, kCIInputContrastKey: 1.15])
            .applyingFilter("CISharpenLuminance", parameters: [kCIInputSharpnessKey: 0.3])
        return CIContext().jpegRepresentation(of: adjusted, colorSpace: CGColorSpaceCreateDeviceRGB(), options: [:])
    }
    static func scan(_ data: Data) async throws -> ScannedReceipt {
        var best: ScannedReceipt?
        if #available(iOS 26.0, *) {
            do { best = try await structured(data) }
            catch is CancellationError { throw CancellationError() }
            catch { }
            // Faded printing may respond differently to contrast enhancement.
            if best == nil || quality(best!) < 4 {
                try Task.checkCancellation()
                if let image = await Task.detached(priority: .userInitiated, operation: { enhanced(data) }).value {
                    do {
                        let retry = try await structured(image)
                        if best == nil || quality(retry) > quality(best!) { best = retry }
                    } catch is CancellationError { throw CancellationError() }
                    catch { }
                }
            }
        }
        if best == nil || quality(best!) < 4 {
            do {
                let transcript = try await read(data)
                var text = ScannedReceipt.parse(transcript)
                if quality(text) == 4 {
                    text.scanNotice = tr("商品与总额已核对，请对照照片确认名称和日期。", "Items and totals balance. Check names and date against the photo.", "Item dan jumlah sepadan. Semak nama dan tarikh dengan foto.")
                    best = text
                } else if best == nil || quality(text) > quality(best!) {
                    // Show uncertain items for correction, never treat a partial
                    // text pass as an automatically verified receipt.
                    text.scanNotice = tr("识别不完整，请对照照片修正漏项和金额。", "Reading is incomplete. Check missing items and amounts against the photo.", "Bacaan tidak lengkap. Semak item dan amaun pada foto.")
                    best = text
                }
                #if canImport(FoundationModels)
                if #available(iOS 26.0, *), quality(best ?? text) < 4,
                   let interpreted = await ReceiptAI.interpret(transcript, base: best ?? text) {
                    best = interpreted
                }
                #endif
            } catch is CancellationError { throw CancellationError() }
            catch { if best == nil { throw error } }
        }
        guard var receipt = best else { throw LedgerError.invalid("No receipt found") }
        if quality(receipt) < 4 && receipt.scanNotice.isEmpty {
            receipt.scanNotice = tr("识别金额尚未对齐，请对照照片核对漏项、税费和总额。", "Amounts do not reconcile yet. Check missing items, charges and total against the photo.", "Amaun belum sepadan. Semak item, caj dan jumlah pada foto.")
        }
        return receipt
    }
    @available(iOS 26.0, *)
    private static func structured(_ data: Data) async throws -> ScannedReceipt {
        let observations = try await RecognizeDocumentsRequest().perform(on: data)
        guard let document = observations.first?.document else { throw LedgerError.invalid("No receipt found") }
        let text = document.text.transcript
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw LedgerError.invalid("No receipt found") }
        var receipt = ScannedReceipt.parse(text)
        let textItems = receipt.items
        receipt.items = []
        var candidates: [ReceiptGrid.Result] = []
        var summaries: [String] = []
        for table in document.tables {
            let rows = table.rows.enumerated().map { index, row in
                row.filter { $0.rowRange.lowerBound == index }.map {
                    ReceiptGrid.Cell(text: $0.content.text.transcript, columns: $0.columnRange)
                }
            }
            let candidate = ReceiptGrid.parse(rows)
            summaries += candidate.summaries
            if candidate.foundColumns { candidates.append(candidate) }
        }
        let totals = ScannedReceipt.parse(summaries.joined(separator: "\n"))
        if !totals.subtotal.isEmpty { receipt.subtotal = totals.subtotal }
        if !totals.tax.isEmpty { receipt.tax = totals.tax }
        if !totals.service.isEmpty { receipt.service = totals.service }
        if !totals.discount.isEmpty { receipt.discount = totals.discount }
        if !totals.rounding.isEmpty { receipt.rounding = totals.rounding }
        if !totals.total.isEmpty { receipt.total = totals.total }
        // A second table may contain payment details. Select an item table only
        // when it is the sole candidate or uniquely balances the receipt.
        if candidates.count == 1 {
            receipt.items = recoverNames(candidates[0].items, from: textItems)
        } else if candidates.count > 1 {
            let matches = candidates.map { recoverNames($0.items, from: textItems) }
                .filter { rows in
                    guard let subtotal = try? toCents(receipt.subtotal), !rows.isEmpty else { return false }
                    let cents = rows.compactMap { row -> Int? in
                        guard !row.name.isEmpty, !row.amount.isEmpty else { return nil }
                        return try? toCents(row.amount)
                    }
                    return cents.count == rows.count && cents.reduce(0, +) == subtotal
                }
            if matches.count == 1 { receipt.items = matches[0] }
        }
        if receipt.items.isEmpty {
            receipt.scanNotice = tr("没有可靠配对 Description 与 Amount，请重拍或补充商品。", "Description and Amount could not be matched reliably. Retake or add items.", "Description dan Amount tidak dapat dipadankan dengan pasti. Ambil semula atau tambah item.")
        } else if receipt.items.contains(where: { $0.name.isEmpty || $0.amount.isEmpty }) {
            receipt.scanNotice = tr("部分商品的名称或金额不清楚，已留空，请对照照片补上。", "Some names or amounts are unclear and left blank. Fill them from the photo.", "Sesetengah nama atau amaun tidak jelas dan dibiarkan kosong. Isi berdasarkan foto.")
        }
        return receipt
    }

    static func read(_ data: Data) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            try VNImageRequestHandler(data: data).perform([request])
            let observations = request.results ?? []
            let heights = observations.map { $0.boundingBox.height }.sorted()
            let tolerance: CGFloat = heights.isEmpty ? 0.005 : max(0.002, heights[heights.count / 2] * 0.55)
            // Correct the overall tilt before matching names to their amount column.
            let slopes: [CGFloat] = observations.compactMap { observation in
                guard let candidate = observation.topCandidates(1).first,
                      let box = try? candidate.boundingBox(for: candidate.string.startIndex..<candidate.string.endIndex),
                      box.topRight.x - box.topLeft.x > 0.08 else { return nil }
                return (box.topRight.y - box.topLeft.y) / (box.topRight.x - box.topLeft.x)
            }.sorted()
            let slope: CGFloat = slopes.isEmpty ? 0 : slopes[slopes.count / 2]
            let blocks = observations.compactMap { observation -> (CGFloat, CGFloat, String)? in
                guard let text = observation.topCandidates(1).first?.string else { return nil }
                let box = observation.boundingBox
                return (box.midY - slope * box.midX, box.minX, text)
            }.sorted { $0.0 == $1.0 ? $0.1 < $1.1 : $0.0 > $1.0 }
            var rows: [[(CGFloat, CGFloat, String)]] = []
            for block in blocks {
                if let last = rows.indices.last, abs(rows[last][0].0 - block.0) < tolerance { rows[last].append(block) }
                else { rows.append([block]) }
            }
            return rows.map { $0.sorted { $0.1 < $1.1 }.map { $0.2 }.joined(separator: "  ") }.joined(separator: "\n")
        }.value
    }
}
struct ReceiptCamera: UIViewControllerRepresentable {
    let receive: (Result<Data?, Error>) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(receive: receive) }
    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }
    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}
    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let receive: (Result<Data?, Error>) -> Void
        init(receive: @escaping (Result<Data?, Error>) -> Void) { self.receive = receive }
        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) { receive(.success(nil)) }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) { receive(.failure(error)) }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            guard scan.pageCount == 1 else {
                receive(.failure(reviewError("一次请扫描一张收据，避免把不同付款合在一起。", "Scan one receipt at a time so separate payments are not combined.", "Imbas satu resit pada satu masa supaya bayaran tidak bercampur.")))
                return
            }
            let image = scan.imageOfPage(at: 0)
            guard let data = image.jpegData(compressionQuality: 0.96) else {
                receive(.failure(LedgerError.invalid("Unable to read receipt image"))); return
            }
            receive(.success(data))
        }
    }
}

struct ReceiptScanView: View {
    @Environment(\.accessibilityReduceMotion) private var guideReduceMotion
    var guideSection: Int? = nil
    @EnvironmentObject var model: LedgerModel
    @State private var photo: PhotosPickerItem?
    @State private var camera = false
    @State private var busy = false
    @State private var merchant = ""
    @State private var subtotal = ""
    @State private var tax = ""
    @State private var service = ""
    @State private var discount = ""
    @State private var rounding = ""
    @State private var printedTotal = ""
    @State private var items: [ScannedReceipt.Item] = []
    @State private var friends: [ReceiptPerson] = []
    @State private var myID = UUID()
    @State private var includeMe = true
    @State private var byItem = true
    @State private var date = Date()
    @State private var dateMissing = false
    @State private var existingID = ""
    @State private var error: String?
    @State private var reviewed = false
    @State private var scanNotice = ""
    @State private var hasReceipt = false
    @State private var receiptImage: UIImage?
    @State private var comparingItem: ScannedReceipt.Item?

    private var people: [ReceiptPerson] {
        (includeMe ? [ReceiptPerson(id: myID, name: tr("我", "Me", "Saya"))] : []) + friends
    }
    private func costs() throws -> (base: Int, total: Int) {
        let base = try toCents(subtotal)
        let t = try optionalMoney(tax) ?? 0, fee = try optionalMoney(service) ?? 0
        let off = try optionalMoney(discount) ?? 0
        let text = rounding.trimmingCharacters(in: .whitespaces)
        let adjustment = (try optionalMoney(text.hasPrefix("-") ? String(text.dropFirst()) : text) ?? 0) * (text.hasPrefix("-") ? -1 : 1)
        let total = try ReceiptCalculation.total(subtotal: base, tax: t, service: fee, discount: off) + adjustment
        guard total > 0, total <= 10_000_000_000 else { throw LedgerError.invalid("Invalid receipt total") }
        return (base, total)
    }
    private func breakdown() throws -> (food: [Int], totals: [Int]) {
        let amounts = try costs()
        guard try toCents(printedTotal) == amounts.total else {
            throw reviewError("小计加税费、减折扣及加舍入后，与实付总额不一致，请核对。", "Subtotal, charges, discount and rounding do not match the paid total.", "Subjumlah, caj, diskaun dan pembundaran tidak sepadan dengan jumlah akhir.")
        }
        guard !people.isEmpty, friends.count <= 20,
              friends.allSatisfy({ !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
              Set(friends.map { friendKey($0.name) }).count == friends.count else {
            throw reviewError("请填写朋友姓名，姓名不能重复。", "Enter a unique name for each friend.", "Isi nama unik untuk setiap rakan.")
        }
        let food: [Int]
        if byItem { food = try ReceiptSplit.food(items: items, people: people.map(\.id), subtotal: amounts.base) }
        else { food = try ReceiptSplit.allocate(amounts.base, weights: Array(repeating: 1, count: people.count)) }
        let weights = byItem ? food : Array(repeating: 1, count: people.count)
        return (food, try ReceiptSplit.allocate(amounts.total, weights: weights))
    }
    private var matching: [Expense] {
        guard let total = try? toCents(printedTotal) else { return [] }
        return model.ledger.expenses.filter { $0.cents == total && $0.foreign == nil && $0.shares.isEmpty && $0.refunded == 0 }.sorted { $0.date > $1.date }
    }
    private func amountRow(_ title: String, _ value: Binding<String>, signed: Bool = false) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text("RM").foregroundStyle(.secondary)
            TextField("0.00", text: value).keyboardType(signed ? .numbersAndPunctuation : .decimalPad)
                .multilineTextAlignment(.trailing).frame(minWidth: 75, maxWidth: 130)
                .accessibilityLabel(title)
        }
    }
    private var captureSection: some View {
        Section {
            Button { camera = true } label: { Label(tr("扫描收据", "Scan receipt", "Imbas resit"), systemImage: "doc.viewfinder") }
                .disabled(!VNDocumentCameraViewController.isSupported || busy)
            PhotosPicker(selection: $photo, matching: .images) { Label(tr("选择收据照片", "Choose receipt photo", "Pilih foto resit"), systemImage: "photo") }.disabled(busy).guideTarget("receipt.photo")
            Text(tr("把整张收据放入画面，调整四角再保存；每次只扫描一张。", "Fit the full receipt in the frame, adjust its corners, then save. Scan one page at a time.", "Letakkan seluruh resit dalam bingkai, laraskan penjuru dan simpan. Imbas satu halaman sahaja.")).font(.caption).foregroundStyle(.secondary)
            if busy { ProgressView(tr("正在识别并核对金额…", "Reading and checking amounts…", "Membaca dan menyemak amaun…")) }
            if let receiptImage {
                DisclosureGroup(tr("查看收据照片", "View receipt photo", "Lihat foto resit")) {
                    Image(uiImage: receiptImage).resizable().scaledToFit().accessibilityLabel(tr("原收据照片", "Receipt photo", "Foto resit"))
                }
            }
        }
    }
    private var reviewSection: some View {
        Section(tr("1. 核对收据", "1. Review receipt", "1. Semak resit")) {
            LabeledContent(tr("商家", "Merchant", "Peniaga")) {
                TextField(tr("商家名称", "Merchant name", "Nama peniaga"), text: $merchant).multilineTextAlignment(.trailing).guideTarget("receipt.merchant")
            }
            DatePicker(tr("消费日期", "Receipt date", "Tarikh resit"), selection: Binding(get: { date }, set: { date = $0; dateMissing = false }), displayedComponents: .date).guideTarget("receipt.date")
            if dateMissing { Text(tr("没有识别到日期，请按收据调整日期。", "Date not found. Set the date shown on the receipt.", "Tarikh tidak dikesan. Tetapkan tarikh pada resit.")).font(.caption).foregroundStyle(.orange) }
            amountRow(tr("商品小计", "Items subtotal", "Subjumlah item"), $subtotal)
            amountRow(tr("税费（SST / GST）", "Tax (SST / GST)", "Cukai (SST / GST)"), $tax)
            amountRow(tr("服务费", "Service charge", "Caj perkhidmatan"), $service)
            DisclosureGroup(tr("折扣与舍入", "Discount & rounding", "Diskaun & pembundaran")) {
                amountRow(tr("折扣", "Discount", "Diskaun"), $discount)
                amountRow(tr("舍入调整（可为负数）", "Rounding (+ / −)", "Pembundaran (+ / −)"), $rounding, signed: true)
            }
            amountRow(tr("实付总额", "Paid total", "Jumlah akhir"), $printedTotal).guideTarget("receipt.total")
            Text(tr("金额均为 RM；请对照照片核对。", "All amounts are in RM. Check against your photo.", "Semua amaun dalam RM. Semak dengan foto.")).font(.caption).foregroundStyle(.secondary)
        }
    }
    private var peopleSection: some View {
        Section(tr("2. 谁一起吃？", "2. Who is sharing?", "2. Siapa berkongsi?")) {
            Toggle(tr("包括我", "Include me", "Termasuk saya"), isOn: $includeMe)
                .onChange(of: includeMe) { _, value in if !value { for i in items.indices { items[i].people.remove(myID) } } }
            ForEach($friends) { $friend in
                HStack {
                    TextField(tr("朋友姓名", "Friend's name", "Nama rakan"), text: $friend.name)
                    Button(role: .destructive) {
                        for i in items.indices { items[i].people.remove(friend.id) }
                        friends.removeAll { $0.id == friend.id }
                    } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
                        .accessibilityLabel(tr("移除朋友", "Remove friend", "Buang rakan"))
                }
            }
            Button(tr("添加朋友", "Add friend", "Tambah rakan")) { friends.append(ReceiptPerson(name: "")) }.disabled(friends.count >= 20).guideTarget("receipt.people")
            Picker(tr("怎样分账", "Split method", "Cara bahagi"), selection: $byItem) {
                Text(tr("按各自点的菜", "By items", "Ikut item")).tag(true)
                Text(tr("全部均分", "Split equally", "Sama rata")).tag(false)
            }.pickerStyle(.segmented)
        }
    }
    private func itemRow(_ item: Binding<ScannedReceipt.Item>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                TextField(tr("菜名 / 商品名", "Item name", "Nama item"), text: item.name, axis: .vertical)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel(tr("商品名称", "Item name", "Nama item"))
                Text("RM").foregroundStyle(.secondary)
                TextField("0.00", text: item.amount).keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing).frame(width: 72)
                    .accessibilityLabel(tr("这项金额", "Line total", "Jumlah item"))
                Button(role: .destructive) { items.removeAll { $0.id == item.wrappedValue.id } } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
                    .accessibilityLabel(tr("删除商品", "Remove item", "Buang item"))
            }
            DisclosureGroup(tr("数量与单价（可选）", "Quantity & unit price (optional)", "Kuantiti & harga seunit (pilihan)")) {
                HStack {
                    TextField(tr("数量", "Quantity", "Kuantiti"), text: item.quantity).keyboardType(.decimalPad)
                    Text("× RM").foregroundStyle(.secondary)
                    TextField(tr("单价", "Unit price", "Harga seunit"), text: item.unitPrice).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                }
                Text(tr("分账按这项金额计算；有折扣时请以收据金额为准。", "Splits use the line total, including any item discount.", "Pembahagian menggunakan jumlah item termasuk diskaun.")).font(.caption).foregroundStyle(.secondary)
            }
            if receiptImage != nil {
                Button { comparingItem = item.wrappedValue } label: {
                    Label(tr("对照原收据", "Compare with receipt", "Banding dengan resit"), systemImage: "viewfinder")
                }.font(.caption).buttonStyle(.borderless)
            }
            if item.wrappedValue.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || item.wrappedValue.amount.isEmpty {
                Text(tr("请对照照片补上名称或金额", "Check the photo for the missing name or amount", "Semak foto untuk nama atau amaun yang tiada"))
                    .font(.caption).foregroundStyle(.orange)
            }
            if let index = items.firstIndex(where: { $0.id == item.wrappedValue.id }), index > 0,
               (item.wrappedValue.amount.isEmpty || ((try? toCents(item.wrappedValue.amount)) == 0 && (try? toCents(items[index - 1].amount)) == 0)) {
                Button(tr("与上一项合并名称", "Join name with previous item", "Gabung nama dengan item sebelumnya")) {
                    let continuation = items[index].name.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !continuation.isEmpty {
                        items[index - 1].name = [items[index - 1].name, continuation].filter { !$0.isEmpty }.joined(separator: " ")
                        items.remove(at: index)
                    }
                }.font(.caption).buttonStyle(.borderless)
            }
            if byItem {
                Menu {
                    ForEach(people) { person in
                        Button {
                            if item.wrappedValue.people.contains(person.id) { item.wrappedValue.people.remove(person.id) }
                            else { item.wrappedValue.people.insert(person.id) }
                        } label: {
                            Label(person.name.isEmpty ? tr("请先填写姓名", "Enter name first", "Isi nama dahulu") : person.name,
                                  systemImage: item.wrappedValue.people.contains(person.id) ? "checkmark.circle.fill" : "circle")
                        }.disabled(person.name.isEmpty)
                    }
                    Button(tr("大家共享", "Everyone shares", "Semua berkongsi")) { item.wrappedValue.people = Set(people.map(\.id)) }
                } label: {
                    let selected = people.filter { item.wrappedValue.people.contains($0.id) }.map(\.name).joined(separator: "、")
                    Label(selected.isEmpty ? tr("谁吃这道菜？", "Who had this?", "Siapa makan ini?") : selected, systemImage: "person.2")
                }
            }
        }.padding(.vertical, 4)
    }
    private var itemsSection: some View {
        Section(tr("3. 菜品明细", "3. Items", "3. Butiran item")) {
            if !scanNotice.isEmpty { Text(scanNotice).font(.caption).foregroundStyle(.orange) }
            if let receiptImage {
                DisclosureGroup(tr("对照收据照片", "Compare receipt photo", "Banding foto resit")) {
                    Image(uiImage: receiptImage).resizable().scaledToFit()
                }
            }
            ForEach($items) { item in
                itemRow(item).guideTarget("receipt.item\(items.firstIndex(where: { $0.id == item.wrappedValue.id }) ?? 0)")
            }
            Button(tr("补上漏掉的商品", "Add missing item", "Tambah item tertinggal")) { items.append(ScannedReceipt.Item(name: "", amount: "")) }.guideTarget("receipt.items")
            if !items.isEmpty {
                let sum = items.reduce(0) { $0 + ((try? optionalMoney($1.amount)) ?? 0) }
                LabeledContent(tr("商品合计", "Items total", "Jumlah item"), value: money(sum))
                if let base = try? toCents(subtotal), base != sum {
                    Text(tr("与小计相差：", "Difference from subtotal: ", "Beza daripada subjumlah: ") + money(base - sum)).foregroundStyle(.orange).font(.caption)
                }
            }
            if byItem { Text(tr("共享的菜可选择多人；所选的人均分这道菜。", "Select several people for a shared dish; they split that item equally.", "Pilih beberapa orang untuk berkongsi item sama rata.")).font(.caption).foregroundStyle(.secondary) }
        }
    }
    private var resultSection: some View {
        Section(tr("4. 每人应付", "4. Each person pays", "4. Bayaran setiap orang")) {
            if let result = try? breakdown() {
                ForEach(Array(people.enumerated()), id: \.element.id) { index, person in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack { Text(person.name).font(.headline); Spacer(); AnimatedMoney(cents: result.totals[index]).font(.title3.bold()) }
                        if byItem {
                            ForEach(items.filter { $0.people.contains(person.id) }) { item in
                                HStack(alignment: .top) {
                                    Text(item.name).fixedSize(horizontal: false, vertical: true)
                                    Spacer()
                                    Text(money(itemShare(item, person: person.id))).monospacedDigit()
                                }.font(.subheadline)
                            }
                        } else { Text(tr("全部商品均分", "All items split equally", "Semua item dibahagi sama rata")).font(.subheadline) }
                        Divider()
                        LabeledContent(tr("餐费", "Food", "Makanan"), value: money(result.food[index]))
                        LabeledContent(tr("税费、折扣及舍入", "Charges, discount & rounding", "Caj, diskaun & pembundaran"), value: money(result.totals[index] - result.food[index]))
                            .foregroundStyle(.secondary)
                    }.padding(14).background(Color.blue.opacity(0.04), in: RoundedRectangle(cornerRadius: 18))
                }
                ShareLink(item: splitSummary(result)) {
                    Label(tr("分享分账明细", "Share split details", "Kongsi butiran pembahagian"), systemImage: "square.and.arrow.up")
                }.disabled(!reviewed)

                Text(tr("税费、服务费、折扣和舍入按餐费比例分摊，尾数自动补齐。", "Charges, discounts and rounding follow each person's food share; cents are balanced automatically.", "Caj, diskaun dan pembundaran mengikut bahagian makanan; baki sen diseimbangkan.")).font(.caption).foregroundStyle(.secondary)
            } else {
                Text(validationMessage).font(.caption).foregroundStyle(.orange)
            }
            if !matching.isEmpty || !existingID.isEmpty {
                Picker(tr("保存到", "Save to", "Simpan ke"), selection: $existingID) {
                    Text(tr("新增账目", "New expense", "Belanja baharu")).tag("")
                    ForEach(matching) { entry in Text(entry.merchant + " · " + dateLabel(entry.date)).tag(entry.id) }
                }
                Text(tr("这笔付款已入账？选原账目，避免重复。", "Already recorded? Choose the original payment to avoid duplicates.", "Sudah direkod? Pilih bayaran asal supaya tidak berganda.")).font(.caption)
            }
            Toggle(tr("已核对日期、商品和金额", "Date, items and amounts checked", "Tarikh, item dan amaun disemak"), isOn: $reviewed)
            Button(tr("保存分账", "Save split", "Simpan pembahagian")) { save() }.disabled(!reviewed || busy || (try? breakdown()) == nil)
        }
    }
    private func itemShare(_ item: ScannedReceipt.Item, person: UUID) -> Int {
        let owners = people.filter { item.people.contains($0.id) }
        guard let index = owners.firstIndex(where: { $0.id == person }),
              let cents = try? optionalMoney(item.amount), cents > 0,
              let parts = try? ReceiptSplit.allocate(cents, weights: Array(repeating: 1, count: owners.count)) else { return 0 }
        return parts[index]
    }
    private func splitSummary(_ result: (food: [Int], totals: [Int])) -> String {
        var lines = [merchant, dateLabel(date), tr("实付总额：", "Paid total: ", "Jumlah akhir: ") + printedTotal + " MYR"]
        for (index, person) in people.enumerated() {
            lines.append("\n" + person.name + " · " + money(result.totals[index]))
            if byItem {
                for item in items where item.people.contains(person.id) {
                    lines.append(item.name + " · " + money(itemShare(item, person: person.id)))
                }
            } else { lines.append(tr("全部商品均分", "All items split equally", "Semua item dibahagi sama rata")) }
            lines.append(tr("餐费：", "Food: ", "Makanan: ") + money(result.food[index]))
            lines.append(tr("税费、折扣及舍入：", "Charges, discount & rounding: ", "Caj, diskaun & pembundaran: ") + money(result.totals[index] - result.food[index]))
        }
        return lines.joined(separator: "\n")
    }
    private var validationMessage: String {
        do { _ = try breakdown(); return "" } catch { return error.localizedDescription }
    }
    private var reviewKey: String {
        let fields = [merchant, subtotal, tax, service, discount, rounding, printedTotal, existingID, String(date.timeIntervalSince1970), String(includeMe), String(byItem)]
        let rows = items.map { $0.id.uuidString + $0.name + $0.amount + $0.quantity + $0.unitPrice + $0.people.map(\.uuidString).sorted().joined(separator: ",") }
        return (fields + rows + friends.map { $0.id.uuidString + $0.name }).joined(separator: "|")
    }
    var body: some View {
        ScrollViewReader { proxy in
        Form {
            Section { PageIntroduction(title: tr("一张收据，分得清楚", "One receipt. Clear shares.", "Satu resit, bahagian jelas."), subtitle: tr("先核对，再分给一起吃的人。", "Review first, then share with your table.", "Semak dahulu, kemudian bahagi bersama.")) }
                .listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            captureSection.id(0)
            if hasReceipt {
                reviewSection.id(1)
                peopleSection.id(2)
                itemsSection.id(3)
                resultSection.id(4)
            }
        }.navigationTitle(tr("收据分账", "Receipt split", "Bahagi resit")).navigationBarTitleDisplayMode(.inline)
            .animation(guideReduceMotion ? nil : .easeInOut(duration: 0.25), value: items.count)
            .animation(guideReduceMotion ? nil : .easeInOut(duration: 0.25), value: friends.count)
            .sheet(item: $comparingItem) { item in
                if let receiptImage { ReceiptComparisonView(image: receiptImage, item: item) }
            }
            .onChange(of: reviewKey) { _, _ in reviewed = false }
            .sheet(isPresented: $camera) {
                ReceiptCamera { result in
                    camera = false
                    switch result {
                    case .success(let data): if let data { Task { await recognize(data) } }
                    case .failure(let failure): error = failure.localizedDescription
                    }
                }
            }
            .onChange(of: photo) { _, item in
                Task { do { if let data = try await item?.loadTransferable(type: Data.self) { await recognize(data) } } catch { self.error = error.localizedDescription } }
            }
            .alert(tr("收据", "Receipt", "Resit"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") {} } message: { Text(error ?? "") }
            .task(id: guideSection) {
                guard model.isPreview, let section = guideSection else { return }
                if section > 0 {
                    let amy = ReceiptPerson(name: "Amy")
                    merchant = "Lunch Cafe"; subtotal = "40.00"; tax = "2.64"; service = "4.00"
                    discount = "0.00"; rounding = "0.00"; printedTotal = "46.64"
                    friends = [amy]
                    items = [ScannedReceipt.Item(name: "Chicken rice", amount: "25.00", people: [myID]),
                             ScannedReceipt.Item(name: "Noodles", amount: "15.00", people: [amy.id])]
                    hasReceipt = true
                }
                do { try await Task.sleep(for: .milliseconds(section == 2 ? 400 : 200)) } catch { return }
                withAnimation(guideReduceMotion ? nil : .easeInOut(duration: 0.8)) {
                    proxy.scrollTo(section, anchor: .top)
                }
            }
        }

    }
    @MainActor private func recognize(_ data: Data) async {
        guard !busy else { return }
        busy = true; reviewed = false; defer { busy = false }
        do {
            guard data.count < 25_000_000 else { throw LedgerError.invalid("Image too large") }
            let receipt = try await ReceiptOCR.scan(data)
            scanNotice = receipt.scanNotice
            merchant = receipt.merchant; subtotal = receipt.subtotal; tax = receipt.tax
            service = receipt.service; discount = receipt.discount; rounding = receipt.rounding
            printedTotal = receipt.total; items = receipt.items; date = receipt.date ?? Date()
            dateMissing = receipt.date == nil; existingID = ""; hasReceipt = true; receiptImage = UIImage(data: data)
        } catch { self.error = error.localizedDescription }
    }
    private func save() {
        do {
            let result = try breakdown(), total = try toCents(printedTotal)
            guard !merchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw LedgerError.invalid("Enter merchant") }
            let shares = people.enumerated().compactMap { index, person -> Share? in
                guard person.id != myID, result.totals[index] > 0 else { return nil }
                return Share(name: person.name.trimmingCharacters(in: .whitespacesAndNewlines), cents: result.totals[index])
            }
            var details = items.map { item -> String in
                let owners = byItem ? people.filter { item.people.contains($0.id) } : people
                return item.name + " · RM " + item.amount + " → " + owners.map(\.name).joined(separator: ", ")
            }
            details.append("Subtotal RM \(subtotal); tax RM \(tax.isEmpty ? "0.00" : tax); service RM \(service.isEmpty ? "0.00" : service); discount RM \(discount.isEmpty ? "0.00" : discount); rounding RM \(rounding.isEmpty ? "0.00" : rounding)")
            for (i, person) in people.enumerated() { details.append(person.name + ": " + money(result.totals[i])) }
            let summary = details.joined(separator: "\n") + "\n\n" + splitSummary(result)
            guard summary.count <= 20_000 else { throw reviewError("收据明细过长，请缩短商品或朋友名称。", "Receipt details are too long. Shorten item or friend names.", "Butiran resit terlalu panjang. Pendekkan nama item atau rakan.") }
            if !existingID.isEmpty {
                guard let original = matching.first(where: { $0.id == existingID }) else { throw LedgerError.invalid("Re-select the original payment") }
                try LocalStore.shared.change { ledger in
                    guard let i = ledger.expenses.firstIndex(where: { $0.id == original.id }), ledger.expenses[i] == original else { throw LedgerError.invalid("Record changed. Reopen it.") }
                    ledger.expenses[i].shares = shares; ledger.expenses[i].receiptSummary = summary
                    ledger.expenses[i].date = date
                }
            } else {
                let expense = Expense(merchant: merchant, cents: total, date: date, category: "餐饮", source: "Receipt", shares: shares, receiptSummary: summary)
                try LocalStore.shared.change { $0.expenses.append(expense) }
            }
            model.reload(); model.showSaved(); hasReceipt = false; photo = nil; receiptImage = nil; items = []; existingID = ""; reviewed = false
        } catch { self.error = error.localizedDescription }
    }
}

struct TNGIncomingView: View {
    @EnvironmentObject var model: LedgerModel
    let id: String
    @State private var purpose = ""
    @State private var friend = ""
    @State private var date = Date()
    @State private var distinct = false
    @State private var initialized = false
    @State private var confirm = false
    @State private var reopen = false
    @State private var error: String?
    private var notice: TNGNotice? { model.ledger.tngNotices.first { $0.id == id } }
    private var friends: [FriendBalance] { model.ledger.friendBalances.filter { $0.owed > 0 } }
    var body: some View {
        Form {
            if let n = notice {
                Section {
                    Text("+" + money(n.cents ?? 0)).font(.title.bold()).foregroundStyle(.green)
                    LabeledContent(tr("转账人", "Sender", "Pengirim"), value: n.party ?? "—")
                    LabeledContent(tr("收款人", "Recipient", "Penerima"), value: n.recipient ?? "—")
                    Text(tngStatus(n))
                    DisclosureGroup(tr("通知原文", "Original notification", "Notifikasi asal")) { Text(n.body).textSelection(.enabled) }
                }
                if n.status == "pending" { reviewSection }
                else {
                    Section {
                        Text(dateLabel(n.date, time: true))
                        if let key = n.resolvedFriend { Text(tr("还款对象：", "Repayment to: ", "Bayaran balik kepada: ") + key) }
                        Text(tr("这是已确认的收款用途。若另行撤销或删除了账本还款，当前欠款请以朋友明细为准。", "This records the confirmed purpose. If repayments were separately deleted or undone, check friend details for the current balance.", "Ini merekod tujuan disahkan. Jika bayaran balik dipadam berasingan, semak butiran rakan untuk baki semasa.")).font(.caption)
                        Button(tr("撤销确认 / 重新分类", "Undo confirmation / reclassify", "Batal pengesahan / klasifikasi semula"), role: .destructive) { reopen = true }
                    }
                }
            } else { Text(tr("记录不存在", "Record not found", "Rekod tidak ditemui")) }
        }.navigationTitle(tr("待确认收款", "Incoming money", "Wang diterima")).navigationBarTitleDisplayMode(.inline)
            .onAppear { if !initialized, let n = notice { initialized = true; date = n.date } }
            .confirmationDialog(tr("确认此收款用途？", "Confirm this purpose?", "Sahkan tujuan ini?"), isPresented: $confirm, titleVisibility: .visible) {
                Button(tr("确认保存", "Confirm and save", "Sahkan dan simpan")) { save() }
            } message: { Text(tr("朋友还款会抵扣所选朋友最早的欠款；请勿重复确认已手动记录的还款。", "Repayment settles the selected friend's oldest debts. Do not duplicate a repayment already recorded manually.", "Bayaran balik melangsaikan hutang tertua rakan. Jangan gandakan bayaran yang direkod manual.")) }
            .confirmationDialog(tr("撤销后将移除此收款生成的还款，恢复待确认；其他还款保留。", "Undo repayments created by this receipt and return it to review? Other repayments stay.", "Batalkan bayaran balik daripada penerimaan ini dan semak semula? Bayaran lain kekal."), isPresented: $reopen, titleVisibility: .visible) {
                Button(tr("撤销确认", "Undo confirmation", "Batal pengesahan"), role: .destructive) {
                    do { try LocalStore.shared.change { try $0.reopenTNGIncoming(id: id) }; model.reload(); purpose = ""; friend = ""; distinct = false }
                    catch { self.error = error.localizedDescription }
                }
            }
            .alert(tr("无法保存", "Unable to save", "Tidak dapat menyimpan"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") {} } message: { Text(error ?? "") }
    }
    private var reviewSection: some View {
        Section(tr("这笔钱是什么用途？", "What is this money for?", "Apakah tujuan wang ini?")) {
            Picker(tr("用途", "Purpose", "Tujuan"), selection: $purpose) {
                Text(tr("请选择", "Choose", "Pilih")).tag("")
                Text(tr("朋友还款", "Friend repayment", "Bayaran balik rakan")).tag("repayment")
                Text(tr("其他收入", "Other income", "Pendapatan lain")).tag("income")
                Text(tr("自己账户转入", "Own-account transfer", "Pindahan akaun sendiri")).tag("ownTransfer")
                Text(tr("忽略", "Ignore", "Abaikan")).tag("ignored")
            }
            if purpose == "repayment" {
                Picker(tr("朋友", "Friend", "Rakan"), selection: $friend) {
                    Text(tr("请选择朋友", "Choose a friend", "Pilih rakan")).tag("")
                    ForEach(friends) { f in Text(f.name + " · " + money(f.owed)).tag(f.id) }
                }
                if let n = notice, let match = friends.first(where: { $0.id == friendKey(n.party ?? "") }) {
                    Button(tr("同名推荐：", "Name match: ", "Nama sepadan: ") + match.name) { friend = match.id }
                }
                if let selected = friends.first(where: { $0.id == friend }), let cents = notice?.cents {
                    if cents <= selected.owed { LabeledContent(tr("确认后尚欠", "Balance after confirmation", "Baki selepas pengesahan"), value: money(selected.owed - cents)) }
                    else { Text(tr("收款超过此朋友欠款，不能全部记为还款。请先核对用途；本版不支持将一笔收款拆成多种用途。", "Receipt exceeds this friend's debt. Review its purpose; splitting one receipt across purposes is not supported yet.", "Amaun melebihi hutang rakan. Semak tujuan; pemisahan satu penerimaan kepada beberapa tujuan belum disokong.")).foregroundStyle(.orange) }
                }
                Text(tr("按整笔收款抵扣欠款，支持未还清；如果此前已手动记过这笔还款，请选忽略。", "Applies the full receipt to debt; partial debt repayment is supported. Ignore if this receipt was already recorded manually.", "Gunakan seluruh penerimaan untuk hutang; bayaran separa hutang disokong. Abaikan jika sudah direkod manual.")).font(.caption)
            }
            DatePicker(tr("实际收到日期", "Date received", "Tarikh diterima"), selection: $date, in: ...Date())
            Text(tr("通知未提供交易日期，默认使用接收时间。收入单独保存在 TNG 收款记录，自己账户转入不计收入；两者不改变消费预算。", "Notification has no transaction date, so received time is used. Income stays in TNG receipt records; own transfers are not income. Neither changes spending budgets.", "Notifikasi tiada tarikh transaksi, jadi masa diterima digunakan. Pendapatan disimpan dalam rekod TNG; pindahan sendiri bukan pendapatan. Kedua-duanya tidak mengubah bajet belanja.")).font(.caption)
            if notice?.possibleDuplicate == true {
                Toggle(tr("已核对：这是另一笔真实收款", "Checked: this is a separate receipt", "Disemak: ini penerimaan berasingan"), isOn: $distinct)
            }
            Button(tr("确认用途", "Confirm purpose", "Sahkan tujuan")) { confirm = true }
                .disabled(purpose.isEmpty || (purpose == "repayment" && friend.isEmpty) || (notice?.possibleDuplicate == true && !distinct && purpose != "ignored"))
        }
    }
    private func save() {
        do {
            try LocalStore.shared.change { try $0.resolveTNGIncoming(id: id, purpose: purpose, friend: friend, date: date, distinctConfirmed: distinct) }
            model.reload(); model.showSaved()
        } catch { self.error = error.localizedDescription }
    }
}

struct SavingsGoalsView: View {
    @EnvironmentObject private var model: LedgerModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var adding = false
    var body: some View {
        List {
            Section {
                Text(tr("为想做的事，慢慢存起来。", "Save for something that matters to you.", "Simpan untuk sesuatu yang bermakna."))
                    .font(.title2.bold()).padding(.vertical, 12)
            }.listRowBackground(Color.clear)
            if model.ledger.savingsGoals.isEmpty {
                ContentUnavailableView(tr("第一个储蓄目标", "Your first savings goal", "Matlamat simpanan pertama"), systemImage: "target", description: Text(tr("例如新电脑、旅行或学习用品。", "For a computer, a trip or school supplies.", "Untuk komputer, perjalanan atau alat belajar.")))
                Button(tr("创建目标", "Create goal", "Cipta matlamat")) { adding = true }
            }
            ForEach(model.ledger.savingsGoals) { goal in
                NavigationLink { SavingsGoalDetail(id: goal.id) } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(goal.name).font(.headline)
                            Spacer()
                            if goal.balance >= goal.target { Image(systemName: "checkmark.seal.fill").foregroundStyle(.green) }
                        }
                        Text(money(goal.balance) + " / " + money(goal.target)).font(.subheadline).monospacedDigit()
                        ProgressView(value: goal.progress).tint(goal.balance >= goal.target ? .green : .blue)
                            .animation(reduceMotion ? nil : .easeInOut(duration: 0.6), value: goal.progress)
                    }.padding(.vertical, 8)
                }
            }
            Section {
                Text(tr("这里记录你已存下的钱；不会移动资金，也不计入消费或收入。", "Track money you have set aside. No funds are moved and spending or income totals are unchanged.", "Jejak wang yang diasingkan. Tiada wang dipindahkan atau perubahan jumlah belanja dan pendapatan."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .yuejiListSurface().navigationTitle(tr("储蓄目标", "Savings goals", "Matlamat simpanan"))
        .toolbar { Button { adding = true } label: { Image(systemName: "plus") }.accessibilityLabel(tr("创建目标", "Create goal", "Cipta matlamat")) }
        .sheet(isPresented: $adding) { SavingsGoalEditor() }
    }
}

private struct SavingsGoalEditor: View {
    var original: SavingsGoal? = nil
    @EnvironmentObject private var model: LedgerModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var amount = ""
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                TextField(tr("目标名称", "Goal name", "Nama matlamat"), text: $name)
                TextField(tr("目标金额 · RM", "Target amount · RM", "Amaun sasaran · RM"), text: $amount).keyboardType(.decimalPad)
            }
            .navigationTitle(tr("储蓄目标", "Savings goal", "Matlamat simpanan"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(tr("取消", "Cancel", "Batal")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button(tr("保存", "Save", "Simpan")) { save() } }
            }
            .onAppear { name = original?.name ?? ""; amount = original.map { Currency.input($0.target, "MYR") } ?? "" }
            .alert(tr("无法保存", "Unable to save", "Tidak dapat menyimpan"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") {} } message: { Text(error ?? "") }
        }
    }
    private func save() {
        do {
            let target = try toCents(amount)
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            try LocalStore.shared.change { ledger in
                if let original {
                    guard let index = ledger.savingsGoals.firstIndex(where: { $0.id == original.id }) else { throw LedgerError.invalid("目标已不存在 / Goal no longer exists") }
                    ledger.savingsGoals[index].name = trimmed
                    ledger.savingsGoals[index].target = target
                } else { ledger.savingsGoals.append(SavingsGoal(name: trimmed, target: target)) }
            }
            model.reload(postRecurring: false); model.showSaved(); dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

private struct SavingsGoalDetail: View {
    let id: String
    @EnvironmentObject private var model: LedgerModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var editing = false
    @State private var deleting = false
    @State private var recording = false
    @State private var withdrawing = false
    @State private var amount = ""
    @State private var error: String?
    @State private var celebrated = false
    private var goal: SavingsGoal? { model.ledger.savingsGoals.first { $0.id == id } }
    var body: some View {
        List {
            if let goal {
                Section {
                    VStack(spacing: 18) {
                        ZStack {
                            Circle().stroke(Color.blue.opacity(0.1), lineWidth: 12)
                            Circle().trim(from: 0, to: CGFloat(goal.progress))
                                .stroke(goal.balance >= goal.target ? Color.green : .blue, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                                .animation(reduceMotion ? nil : .spring(response: 0.75, dampingFraction: 0.9), value: goal.balance)
                            VStack(spacing: 5) {
                                Text("\(Int(goal.progress * 100))%") .font(.largeTitle.bold()).contentTransition(.numericText())
                                Text(goal.balance >= goal.target ? tr("已达成", "Reached", "Tercapai") : tr("已存下", "Saved", "Disimpan")).font(.caption).foregroundStyle(.secondary)
                            }
                        }.frame(width: 170, height: 170).padding(.top, 12)
                        AnimatedMoney(cents: goal.balance).font(.title.bold())
                        Text(tr("目标 ", "Target ", "Sasaran ") + money(goal.target)).foregroundStyle(.secondary)
                        Text(tr("还差 ", "Remaining ", "Baki ") + money(max(0, goal.target - goal.balance))).font(.subheadline)
                        if celebrated {
                            Label(tr("目标达成！", "Goal reached!", "Matlamat tercapai!"), systemImage: "checkmark.seal.fill")
                                .foregroundStyle(.green).font(.headline)
                                .transition(reduceMotion ? .opacity : .scale(scale: 0.8).combined(with: .opacity))
                        }
                        HStack {
                            Button(tr("存入", "Add savings", "Tambah simpanan")) { withdrawing = false; amount = ""; recording = true }
                                .buttonStyle(.borderedProminent)
                            Button(tr("取出", "Withdraw", "Keluarkan")) { withdrawing = true; amount = ""; recording = true }
                                .buttonStyle(.bordered).disabled(goal.balance == 0)
                        }
                    }.frame(maxWidth: .infinity).padding(.vertical, 10)
                }
                Section(tr("储蓄记录", "Savings history", "Sejarah simpanan")) {
                    if goal.entries.isEmpty { Text(tr("记录第一笔存入吧。", "Record your first contribution.", "Rekod simpanan pertama anda.")) }
                    ForEach(goal.entries.reversed()) { entry in
                        HStack {
                            Text(dateLabel(entry.date, time: true)).font(.subheadline)
                            Spacer()
                            Text((entry.cents > 0 ? "+ " : "− ") + money(abs(entry.cents)))
                                .monospacedDigit().foregroundStyle(entry.cents > 0 ? Color.green : .secondary)
                        }
                    }
                }
            }
        }
        .yuejiListSurface().navigationTitle(goal?.name ?? "")
        .toolbar {
            Menu {
                Button(tr("编辑目标", "Edit goal", "Edit matlamat")) { editing = true }
                Button(tr("删除目标", "Delete goal", "Padam matlamat"), role: .destructive) { deleting = true }
            } label: { Image(systemName: "ellipsis.circle") }
        }
        .sheet(isPresented: $editing) { if let goal { SavingsGoalEditor(original: goal) } }
        .alert(withdrawing ? tr("记录取出 · RM", "Record withdrawal · RM", "Rekod pengeluaran · RM") : tr("记录存入 · RM", "Record savings · RM", "Rekod simpanan · RM"), isPresented: $recording) {
            TextField("0.00", text: $amount).keyboardType(.decimalPad)
            Button(tr("确认", "Confirm", "Sahkan")) { record() }
            Button(tr("取消", "Cancel", "Batal"), role: .cancel) {}
        }
        .alert(tr("无法保存", "Unable to save", "Tidak dapat menyimpan"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") {} } message: { Text(error ?? "") }
        .confirmationDialog(tr("删除目标及全部储蓄记录？", "Delete this goal and its savings history?", "Padam matlamat dan sejarahnya?"), isPresented: $deleting, titleVisibility: .visible) {
            Button(tr("删除目标", "Delete goal", "Padam matlamat"), role: .destructive) {
                do { try LocalStore.shared.change { $0.savingsGoals.removeAll { $0.id == id } }; model.reload(postRecurring: false); dismiss() }
                catch { self.error = error.localizedDescription }
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.85), value: celebrated)
    }
    private func record() {
        do {
            let cents = try toCents(amount)
            guard cents > 0 else { throw LedgerError.invalid("金额必须大于零 / Enter an amount above zero") }
            let reached = try LocalStore.shared.change { ledger -> Bool in
                guard let index = ledger.savingsGoals.firstIndex(where: { $0.id == id }) else { throw LedgerError.invalid("目标已不存在 / Goal no longer exists") }
                let before = ledger.savingsGoals[index].balance >= ledger.savingsGoals[index].target
                try ledger.savingsGoals[index].record(cents: withdrawing ? -cents : cents)
                return !before && ledger.savingsGoals[index].balance >= ledger.savingsGoals[index].target
            }
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.5)) { model.reload(postRecurring: false); celebrated = reached }
            model.showSaved()
        } catch { self.error = error.localizedDescription }
    }
}


private struct ReceiptComparisonView: View {
    let image: UIImage
    let item: ScannedReceipt.Item
    @Environment(\.dismiss) private var dismiss
    @State private var region: UIImage?
    @State private var searching = true
    @State private var zoom: CGFloat = 1
    var body: some View {
        NavigationStack {
            ScrollView([.horizontal, .vertical]) {
                VStack(alignment: .leading, spacing: 18) {
                    Text(item.name.isEmpty ? tr("待核对商品", "Item to review", "Item untuk disemak") : item.name).font(.headline)
                    Text(tr("这项金额：RM ", "Line total: RM ", "Jumlah item: RM ") + item.amount)
                    if searching { ProgressView() }
                    if let region {
                        Text(tr("对应区域（请核对）", "Matching area — please check", "Kawasan sepadan — sila semak")).font(.caption)
                        Image(uiImage: region).resizable().scaledToFit()
                    } else if !searching {
                        Text(tr("未能可靠定位，请对照下方完整收据。", "Could not locate a unique match. Check the full receipt below.", "Tiada padanan unik. Semak resit penuh di bawah.")).font(.caption).foregroundStyle(.secondary)
                    }
                    Slider(value: $zoom, in: 1...3) { Text(tr("放大照片", "Zoom photo", "Zum foto")) }
                    Image(uiImage: image).resizable().scaledToFit().frame(width: 320 * zoom)
                }.frame(width: 320 * zoom, alignment: .leading).padding(20)
            }
            .navigationTitle(tr("对照收据", "Compare receipt", "Banding resit")).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(tr("关闭", "Close", "Tutup")) { dismiss() } } }
            .task {
                let renderer = UIGraphicsImageRenderer(size: image.size)
                let normalized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: image.size)) }
                guard let cg = normalized.cgImage else { searching = false; return }
                let name = item.name
                let crop = await Task.detached(priority: .userInitiated) { () -> CGImage? in
                    let request = VNRecognizeTextRequest()
                    request.recognitionLevel = .accurate
                    guard !name.isEmpty, (try? VNImageRequestHandler(cgImage: cg).perform([request])) != nil else { return nil }
                    let key = ReceiptGrid.normalized(name)
                    let matches = (request.results ?? []).filter {
                        guard let text = $0.topCandidates(1).first?.string else { return false }
                        let value = ReceiptGrid.normalized(text)
                        return key.count >= 4 && (value.contains(key) || (value.count >= 6 && key.hasPrefix(value)))
                    }
                    guard matches.count == 1, let box = matches.first?.boundingBox else { return nil }
                    let top = max(0, 1 - box.maxY - box.height)
                    let bottom = min(1, 1 - box.minY + box.height * 2)
                    return cg.cropping(to: CGRect(x: 0, y: top * Double(cg.height), width: Double(cg.width), height: (bottom - top) * Double(cg.height)).integral)
                }.value
                guard !Task.isCancelled else { return }
                region = crop.map { UIImage(cgImage: $0) }; searching = false
            }
        }
    }
}
