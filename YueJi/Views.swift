import SwiftUI
import UniformTypeIdentifiers
import UIKit

private let ink = Color(uiColor: UIColor { traits in
    traits.userInterfaceStyle == .dark ? UIColor(red: 0.45, green: 0.82, blue: 0.94, alpha: 1) : UIColor(red: 0.10, green: 0.26, blue: 0.37, alpha: 1)
})
struct GlassPanel<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View { content.padding(20).frame(maxWidth: .infinity, alignment: .leading).ledgerGlass() }
}
extension View {
    @ViewBuilder func ledgerGlass() -> some View {
        if #available(iOS 26.0, *) { self.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 26)) }
        else { self.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26)) }
    }
}
struct MainView: View {
    @EnvironmentObject var model: LedgerModel
    @Environment(\.scenePhase) private var phase
    var body: some View {
        TabView {
            DashboardView().tabItem { Label(tr("概览", "Overview", "Ringkasan"), systemImage: "chart.pie.fill") }
            ExpensesView().tabItem { Label(tr("账本", "Ledger", "Lejar"), systemImage: "list.bullet.rectangle") }
            RecurringView().tabItem { Label(tr("固定", "Recurring", "Berulang"), systemImage: "repeat") }
            FriendsView().tabItem { Label(tr("分账", "Friends", "Rakan"), systemImage: "person.2.fill") }
            SettingsView().tabItem { Label(tr("设置", "Settings", "Tetapan"), systemImage: "slider.horizontal.3") }
        }.tint(ink).task { model.reload() }
            .onChange(of: phase) { _, value in if value == .active { model.reload() } }
            .alert(tr("月记", "YueJi", "YueJi"), isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
                Button(tr("知道了", "OK", "OK"), role: .cancel) { model.error = nil }
            } message: { Text(model.error ?? "") }
    }
}
struct MonthPicker: View {
    @Binding var month: Date
    var body: some View {
        HStack(spacing: 0) {
            Button { shift(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44).contentShape(Rectangle()) }
                .buttonStyle(.borderless)
                .accessibilityLabel(tr("上个月", "Previous month", "Bulan sebelumnya"))
            Text(month.formatted(.dateTime.year().month(.wide).locale(Locale(identifier: AppLanguage.localeID))))
                .font(.headline).frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 25).onEnded { value in
                    let dx = value.translation.width, dy = value.translation.height
                    guard abs(dx) > 45, abs(dx) > abs(dy) * 1.5 else { return }
                    shift(dx < 0 ? 1 : -1)
                })
                .accessibilityHint(tr("左右滑动切换月份", "Swipe left or right to change month", "Leret kiri atau kanan untuk menukar bulan"))
            Button { shift(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44).contentShape(Rectangle()) }
                .buttonStyle(.borderless)
                .accessibilityLabel(tr("下个月", "Next month", "Bulan seterusnya"))
        }
    }
    private func shift(_ n: Int) { month = shiftedMonth(month, by: n) }
}
struct DashboardView: View {
    @EnvironmentObject var model: LedgerModel
    @SceneStorage("overviewMonth") private var monthTimestamp = Date().timeIntervalSince1970
    private var month: Date {
        get { Date(timeIntervalSince1970: monthTimestamp) }
        nonmutating set { monthTimestamp = newValue.timeIntervalSince1970 }
    }
    private var monthBinding: Binding<Date> { Binding(get: { month }, set: { month = $0 }) }
    @State private var adding = false
    @State private var budgetText = ""
    @State private var budgeting = false
    private var entries: [Expense] { model.ledger.expenses.filter { monthKey($0.date) == monthKey(month) } }
    private var personal: Int { entries.reduce(0) { $0 + $1.personal } }
    private var budget: Int { model.ledger.budgets[monthKey(month)] ?? 0 }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    MonthPicker(month: monthBinding)
                    NavigationLink { UpcomingView(initialMonth: month) } label: { Label(tr("查看固定消费预览", "Preview upcoming bills", "Pratonton bil akan datang"), systemImage: "calendar") }
                    NavigationLink { DuplicateReviewView() } label: { Label(tr("检查重复账目", "Review possible duplicates", "Semak rekod pendua"), systemImage: "doc.on.doc") }
                    GlassPanel {
                        VStack(alignment: .leading, spacing: 15) {
                            Label(tr("我的月度消费", "My monthly spending", "Belanja bulanan saya"), systemImage: "sparkles").foregroundStyle(.secondary)
                            Text(money(personal)).font(.system(size: 38, weight: .semibold, design: .rounded)).minimumScaleFactor(0.5).lineLimit(1)
                            if budget > 0 {
                                ProgressView(value: min(Double(personal) / Double(budget), 1))
                                Text((personal > budget ? tr("超出预算：", "Over budget: ", "Melebihi bajet: ") : tr("剩余预算：", "Remaining: ", "Baki: ")) + money(abs(budget - personal)))
                            }
                            Button(tr("设置月度预算", "Monthly budget", "Bajet bulanan")) { budgetText = budget > 0 ? Currency.input(budget, "MYR") : ""; budgeting = true }
                        }
                    }
                    GlassPanel {
                        VStack(spacing: 12) {
                            LabeledContent(tr("实际付款", "Total paid", "Jumlah dibayar"), value: money(entries.reduce(0) { $0 + $1.cents }))
                            if entries.contains(where: { $0.refunded > 0 }) {
                                LabeledContent(tr("原月消费已退金额", "Refunds against this month's spending", "Bayaran balik belanja bulan ini"), value: money(entries.reduce(0) { $0 + $1.refunded }))
                                Text(tr("个人消费已扣除属于你的退款。", "Personal spending already excludes your refund share.", "Belanja peribadi sudah menolak bahagian bayaran balik anda.")).font(.caption)
                            }
                            LabeledContent(tr("朋友待还 · 全部月份", "Friends owe · all months", "Hutang rakan · semua bulan"), value: money(model.ledger.expenses.flatMap(\.shares).reduce(0) { $0 + max(0, $1.owed) }))
                        }
                    }
                    GlassPanel {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(tr("钱花在哪里", "Spending by category", "Belanja mengikut kategori")).font(.headline)
                            if entries.isEmpty { Text(tr("这个月还没有记录", "No entries this month", "Tiada rekod bulan ini")).foregroundStyle(.secondary) }
                            ForEach(categories, id: \.self) { category in
                                let value = entries.filter { $0.category == category }.reduce(0) { $0 + $1.personal }
                                if value > 0 {
                                    HStack { Text(categoryLabel(category)); Spacer(); Text(money(value)) }
                                    ProgressView(value: Double(value), total: Double(max(personal, 1)))
                                }
                            }
                        }
                    }
                    Button { adding = true } label: { Label(tr("记一笔 / 朋友代垫", "Add expense / advance", "Tambah belanja / pendahuluan"), systemImage: "plus").frame(maxWidth: .infinity).padding(12) }.buttonStyle(.borderedProminent)
                    Text(tr("统计、预算和朋友欠款统一使用 MYR；外币账目保留入账时的汇率。", "Totals, budgets and friend balances use MYR. Foreign entries keep their original exchange rate.", "Jumlah, bajet dan hutang rakan menggunakan MYR. Rekod asing mengekalkan kadar asal.")).font(.footnote).foregroundStyle(.secondary)
                }.padding()
            }.background(LinearGradient(colors: [.cyan.opacity(0.15), .blue.opacity(0.06), .mint.opacity(0.14)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .navigationTitle(tr("月记", "YueJi", "YueJi"))
                .sheet(isPresented: $adding) { ExpenseEditor(original: nil, initialDate: dateForNewExpense(in: month)) }
                .alert(tr("月度预算 · MYR", "Monthly budget · MYR", "Bajet bulanan · MYR"), isPresented: $budgeting) {
                    TextField("1500.00", text: $budgetText).keyboardType(.decimalPad)
                    Button(tr("保存", "Save", "Simpan")) { do { let n = try toCents(budgetText); model.change { $0.budgets[monthKey(month)] = n } } catch { model.error = error.localizedDescription } }
                    Button(tr("移除预算", "Remove budget", "Buang bajet"), role: .destructive) { model.change { $0.budgets.removeValue(forKey: monthKey(month)) } }
                    Button(tr("取消", "Cancel", "Batal"), role: .cancel) {}
                }
        }
    }
}
struct ExpenseRow: View {
    let entry: Expense
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: entry.fuel ? "fuelpump.fill" : entry.recurringKey != nil ? "repeat" : "creditcard.fill").foregroundStyle(ink)
            VStack(alignment: .leading, spacing: 5) {
                Text(entry.merchant).font(.headline)
                Text("\(categoryLabel(entry.category)) · \(sourceLabel(entry.source)) · \(dateLabel(entry.date))").font(.caption).foregroundStyle(.secondary)
                if let fx = entry.foreign { Text(Currency.display(fx.minor, fx.currency) + " · 1 \(fx.currency) = \(fx.quote.text) MYR").font(.caption) }
                if entry.refunded > 0 { Text(tr("已退款：", "Refunded: ", "Dipulangkan: ") + money(entry.refunded)).font(.caption).foregroundStyle(.green) }
                if !entry.shares.isEmpty { Text(tr("我的份额：", "My share: ", "Bahagian saya: ") + money(entry.personal)).font(.caption) }
            }
            Spacer(); Text(money(entry.cents)).monospacedDigit().font(.subheadline)
        }.padding(.vertical, 5)
    }
}
struct ExpensesView: View {
    @EnvironmentObject var model: LedgerModel
    @SceneStorage("ledgerMonth") private var monthTimestamp = Date().timeIntervalSince1970
    private var month: Date {
        get { Date(timeIntervalSince1970: monthTimestamp) }
        nonmutating set { monthTimestamp = newValue.timeIntervalSince1970 }
    }
    private var monthBinding: Binding<Date> { Binding(get: { month }, set: { month = $0 }) }
    @State private var search = ""
    @State private var adding = false
    @State private var editing: Expense?
    @State private var deleting: Expense?
    var body: some View {
        NavigationStack {
            List {
                MonthPicker(month: monthBinding)
                NavigationLink(tr("检查重复账目", "Review possible duplicates", "Semak rekod pendua")) { DuplicateReviewView() }
                let entries = model.ledger.expenses.filter { monthKey($0.date) == monthKey(month) && (search.isEmpty || $0.merchant.localizedCaseInsensitiveContains(search) || categoryLabel($0.category).localizedCaseInsensitiveContains(search)) }.sorted { $0.date > $1.date }
                if entries.isEmpty { ContentUnavailableView(tr("暂无记录", "No entries", "Tiada rekod"), systemImage: "tray") }
                ForEach(entries) { e in
                    Button { editing = e } label: { ExpenseRow(entry: e).foregroundStyle(.primary) }
                        .swipeActions { Button(tr("删除", "Delete", "Padam"), role: .destructive) { deleting = e } }
                }
            }.navigationTitle(tr("账本", "Ledger", "Lejar")).searchable(text: $search, prompt: tr("商户、分类", "Merchant, category", "Peniaga, kategori"))
                .toolbar { Button { adding = true } label: { Image(systemName: "plus") } }
                .sheet(isPresented: $adding) { ExpenseEditor(original: nil, initialDate: dateForNewExpense(in: month)) }
                .sheet(item: $editing) { ExpenseEditor(original: $0) }
                .confirmationDialog(tr("删除付款及其分账和还款？", "Delete payment, splits and repayments?", "Padam bayaran, pembahagian dan bayaran balik?"), isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                    Button(tr("删除", "Delete", "Padam"), role: .destructive) { if let e = deleting { model.change { $0.expenses.removeAll { $0.id == e.id } } }; deleting = nil }
                }
        }
    }
}
struct FriendDraft: Identifiable {
    var id: String; var name: String; var amount: String; var repayments: [Repayment]
    init(_ s: Share = Share(name: "", cents: 0)) { id = s.id; name = s.name; amount = Currency.input(s.cents, "MYR"); repayments = s.repayments }
}
struct ExpenseEditor: View {
    @EnvironmentObject var model: LedgerModel
    @Environment(\.dismiss) private var dismiss
    let original: Expense?
    var initialDate: Date = Date()
    var initialDraft: Expense? = nil
    var onSaved: (() -> Void)? = nil
    @State private var name = ""
    @State private var amount = ""
    @State private var currency = "MYR"
    @State private var rate = ""
    @State private var rateDate = Date()
    @State private var rateSource = "Manual"
    @State private var date = Date()
    @State private var category = "其他"
    @State private var splitting = false
    @State private var fuel = false
    @State private var equal = true
    @State private var includeMe = true
    @State private var people = [FriendDraft()]
    @State private var error: String?
    @State private var initialized = false
    private func foreign() throws -> ForeignAmount? {
        if currency == "MYR" { return nil }
        let value = try parseRate(rate)
        return ForeignAmount(currency: currency, minor: try Currency.parse(amount, code: currency), quote: RateQuote(value: value, date: rateDate, source: rateSource))
    }
    private func total() throws -> Int { if let fx = try foreign() { return try fx.myrCents() }; return try toCents(amount) }
    var body: some View {
        NavigationStack {
            Form {
                if let original {
                    Section { NavigationLink(tr("退款记录", "Refunds", "Bayaran balik")) { RefundsView(expenseID: original.id) } }
                    if original.refunded > 0 { Text(tr("已有退款，金额、日期和分账已锁定。需修改时先撤销相关退款。", "Refunds exist. Amount, date and splits are locked. Undo refunds before changing these.", "Bayaran balik wujud. Amaun, tarikh dan pembahagian dikunci. Batalkan bayaran balik sebelum mengubahnya.")).font(.caption) }
                }
                Section(tr("实际付款", "Payment", "Bayaran")) {
                    TextField(tr("商户 / 行程", "Merchant / trip", "Peniaga / perjalanan"), text: $name)
                    Picker(tr("币种", "Currency", "Mata wang"), selection: Binding(get: { currency }, set: { code in
                        currency = code
                        if let q = model.ledger.rates[code] { rate = q.text; rateDate = q.date; rateSource = q.source }
                        else { rate = ""; rateSource = "Manual"; rateDate = Date() }
                    })) { ForEach(Currency.codes, id: \.self) { Text($0).tag($0) } }
                    TextField(tr("原币金额", "Original amount", "Amaun asal"), text: $amount).keyboardType(.decimalPad)
                    if currency != "MYR" {
                        Text("1 \(currency) = ? MYR").font(.caption)
                        TextField(tr("汇率", "Exchange rate", "Kadar pertukaran"), text: $rate).keyboardType(.decimalPad)
                        Text(tr("可填写银行实际汇率。保存后不会随参考汇率变化。", "You may enter your bank's actual rate. Saved entries will not change with market rates.", "Anda boleh isi kadar sebenar bank. Rekod disimpan tidak berubah mengikut kadar pasaran.")).font(.caption)
                        if let n = try? total() { LabeledContent(tr("换算为", "Converted to", "Ditukar kepada"), value: money(n)) }
                    }
                    DatePicker(tr("日期", "Date", "Tarikh"), selection: $date, displayedComponents: [.date, .hourAndMinute])
                    Picker(tr("分类", "Category", "Kategori"), selection: $category) { ForEach(categories, id: \.self) { Text(categoryLabel($0)).tag($0) } }
                }.disabled((original?.refunded ?? 0) > 0)
                Section {
                    Toggle(tr("朋友分账", "Split with friends", "Bahagi dengan rakan"), isOn: $splitting)
                    if splitting {
                        Toggle(tr("行程油费", "Trip fuel cost", "Kos minyak perjalanan"), isOn: $fuel).onChange(of: fuel) { _, value in if value { category = "交通" } }
                        Picker(tr("分摊方式", "Split method", "Cara pembahagian"), selection: $equal) { Text(tr("平均", "Equal", "Sama rata")).tag(true); Text(tr("自定", "Custom", "Tersuai")).tag(false) }.pickerStyle(.segmented)
                        if equal { Toggle(tr("我也参与分摊", "Include my share", "Termasuk bahagian saya"), isOn: $includeMe) }
                        ForEach($people) { $p in
                            HStack {
                                TextField(tr("朋友姓名", "Friend's name", "Nama rakan"), text: $p.name)
                                if !equal { TextField("MYR", text: $p.amount).keyboardType(.decimalPad) }
                                Button(role: .destructive) { people.removeAll { $0.id == p.id } } label: { Image(systemName: "minus.circle") }.disabled(!p.repayments.isEmpty || people.count == 1)
                            }
                        }
                        Button(tr("添加朋友", "Add friend", "Tambah rakan")) { people.append(FriendDraft()) }
                        if equal, let n = try? total() {
                            let values = equalShares(total: n, count: people.count, includeMe: includeMe)
                            ForEach(Array(values.enumerated()), id: \.offset) { i, v in Text("\(people[i].name): \(money(v))") }
                            Text(tr("我的份额：", "My share: ", "Bahagian saya: ") + money(n - values.reduce(0, +)))
                        }
                    }
                } footer: { Text(tr("分账和还款金额使用 MYR。已有付款请编辑分账，避免重复新增。", "Shares and repayments use MYR. Edit an existing payment to split it without duplicating it.", "Bahagian dan bayaran balik menggunakan MYR. Edit bayaran sedia ada untuk mengelakkan pendua.")) }.disabled((original?.refunded ?? 0) > 0)
            }.navigationTitle(tr("记账 / 分账", "Expense / split", "Belanja / pembahagian"))
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(tr("取消", "Cancel", "Batal")) { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button(tr("保存", "Save", "Simpan")) { commit() } } }
                .onAppear { load() }
                .alert(tr("无法保存", "Unable to save", "Tidak dapat menyimpan"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") {} } message: { Text(error ?? "") }
        }
    }
    private func load() {
        guard !initialized else { return }; initialized = true
        if original == nil { date = initialDate }
        if let e = original ?? initialDraft {
            name = e.merchant; date = e.date; category = e.category; fuel = e.fuel
            splitting = !e.shares.isEmpty; equal = e.shares.isEmpty
            if splitting { people = e.shares.map(FriendDraft.init) }
            currency = e.foreign?.currency ?? "MYR"; amount = Currency.input(e.foreign?.minor ?? e.cents, currency)
            if let fx = e.foreign { rate = fx.quote.text; rateDate = fx.quote.date; rateSource = fx.quote.source }
        }
    }
    private func commit() {
        do {
            let n = try total(); var entry = original ?? initialDraft ?? Expense(merchant: "", cents: n)
            entry.merchant = name.trimmingCharacters(in: .whitespacesAndNewlines); entry.cents = n; entry.date = date; entry.category = category; entry.fuel = fuel
            var fx = try foreign()
            if let old = original?.foreign, old.currency == currency, old.quote.text == rate { fx?.quote = old.quote }
            else if let saved = model.ledger.rates[currency], saved.text == rate { fx?.quote = saved }
            else if fx != nil { fx?.quote.source = "Manual"; fx?.quote.date = Date() }
            entry.foreign = fx
            if let original, original.refunded > 0 {
                guard entry.cents == original.cents, entry.date == original.date, entry.foreign == original.foreign else { throw reviewError("已有退款，请先撤销退款再修改金额或日期。", "Undo refunds before changing amount or date.", "Batalkan bayaran balik sebelum mengubah amaun atau tarikh.") }
            }
            if !splitting && (original?.shares.contains { !$0.repayments.isEmpty } ?? false) { throw LedgerError.invalid(tr("请先撤销已有还款。", "Undo repayments before removing the split.", "Batalkan bayaran balik sebelum membuang pembahagian.")) }
            if splitting {
                let values: [Int]
                if equal { values = equalShares(total: n, count: people.count, includeMe: includeMe) }
                else { values = try people.map { p in if p.amount == "0" || p.amount == "0.00" { return 0 }; return try toCents(p.amount) } }
                entry.shares = zip(people, values).map { p, v in Share(id: p.id, name: p.name.trimmingCharacters(in: .whitespacesAndNewlines), cents: v, repayments: p.repayments) }
                guard !entry.shares.contains(where: { $0.repayments.contains { $0.date < Calendar.current.startOfDay(for: date) } }) else { throw LedgerError.invalid(tr("付款日期不能晚于还款。", "Payment date cannot be after repayment.", "Tarikh bayaran tidak boleh selepas bayaran balik.")) }
            } else { entry.shares = [] }
            if let original, original.refunded > 0 {
                guard entry.shares.map(\.id) == original.shares.map(\.id), zip(entry.shares, original.shares).allSatisfy({ pair in pair.0.cents == pair.1.cents && pair.0.name == pair.1.name }) else { throw reviewError("已有退款，请先撤销退款再修改分账。", "Undo refunds before changing splits.", "Batalkan bayaran balik sebelum mengubah pembahagian.") }
                entry.shares = original.shares
            }
            if initialDraft != nil && splitting {
                let names = entry.shares.map { friendKey($0.name) }
                guard !names.contains(""), Set(names).count == names.count else {
                    throw reviewError("请填写每位朋友的姓名，且姓名不能重复。", "Enter a distinct name for each friend.", "Isi nama berbeza bagi setiap rakan.")
                }
            }
            try LocalStore.shared.change { ledger in
                if let original {
                    guard let i = ledger.expenses.firstIndex(where: { $0.id == original.id }), ledger.expenses[i] == original else { throw LedgerError.invalid(tr("记录已改变，请重新打开。", "Record changed. Reopen it.", "Rekod berubah. Buka semula.")) }
                    ledger.expenses[i] = entry
                    if original.category != entry.category {
                        ledger.merchantCategories[friendKey(entry.merchant)] = entry.category
                    }
                } else if !ledger.expenses.contains(where: { $0.id == entry.id }) {
                    ledger.expenses.append(entry)
                }
            }
            model.reload(); dismiss(); onSaved?()
        } catch { self.error = error.localizedDescription }
    }
}
struct RepayTarget: Identifiable { var id: String { share.id }; let expense: Expense; let share: Share }
struct FriendsView: View {
    @EnvironmentObject var model: LedgerModel
    @State private var target: RepayTarget?
    @State private var editing: Expense?
    @State private var undo: (String, String, String, Bool)?
    @State private var settled = false
    var body: some View {
        NavigationStack {
            List {
                NavigationLink(tr("按朋友汇总 / 一次还多笔", "Balances / batch repayment", "Baki / bayaran balik kelompok")) { FriendSummaryView() }
                NavigationLink(tr("油费计算器", "Fuel calculator", "Kalkulator minyak")) { FuelCalculatorView() }
                Picker(tr("显示", "Show", "Papar"), selection: $settled) {
                    Text(tr("未结清", "Outstanding", "Belum selesai")).tag(false)
                    Text(tr("已结清", "Settled", "Selesai")).tag(true)
                }.pickerStyle(.segmented)
                let entries = model.ledger.expenses.filter { e in e.shares.contains { ($0.owed == 0) == settled } }.sorted { $0.date > $1.date }
                if entries.isEmpty { ContentUnavailableView(tr("暂无分账", "No shared expenses", "Tiada belanja dikongsi"), systemImage: "person.2", description: Text(tr("在账本中编辑一笔付款，开启朋友分账。", "Edit a payment in Ledger and enable splitting.", "Edit bayaran dalam Lejar dan aktifkan pembahagian."))) }
                ForEach(entries) { e in
                    Section {
                        ForEach(e.shares.filter { ($0.owed == 0) == settled }) { s in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack { Text(s.name).font(.headline); Spacer(); Text(s.owed == 0 ? tr("已结清", "Settled", "Selesai") : money(s.owed)) }
                                Text(tr("应付 / 已还：", "Share / repaid: ", "Bahagian / dibayar: ") + money(s.cents) + " / " + money(s.repaid)).font(.caption)
                                if s.owed != 0 { Button(s.owed > 0 ? tr("记录还款", "Record repayment", "Rekod bayaran balik") : tr("退回朋友款项", "Return money to friend", "Pulangkan wang kepada rakan")) { target = RepayTarget(expense: e, share: s) } }
                                if s.owed < 0 { Text(tr("你需退回朋友：", "You need to return: ", "Anda perlu pulangkan: ") + money(-s.owed)).font(.caption).foregroundStyle(.orange) }
                                ForEach(s.returns ?? []) { r in HStack { Text(tr("已退回：", "Returned: ", "Dipulangkan: ") + money(r.cents) + " · " + dateLabel(r.date)).font(.caption); Spacer(); Button(tr("撤销", "Undo", "Batal")) { undo = (e.id, s.id, r.id, true) } } }
                                ForEach(s.repayments) { r in HStack { Text(dateLabel(r.date) + " · " + money(r.cents)).font(.caption); Spacer(); Button(tr("撤销", "Undo", "Batal")) { undo = (e.id, s.id, r.id, false) } } }
                            }
                        }
                        Button(tr("编辑分账", "Edit split", "Edit pembahagian")) { editing = e }
                    } header: { Text(e.merchant) } footer: { Text(tr("我的份额：", "My share: ", "Bahagian saya: ") + money(e.personal)) }
                }
            }.navigationTitle(tr("朋友分账", "Shared expenses", "Belanja dikongsi"))
                .sheet(item: $editing) { ExpenseEditor(original: $0) }
                .sheet(item: $target) { RepaymentView(target: $0) }
                .confirmationDialog(tr("撤销还款？", "Undo repayment?", "Batalkan bayaran balik?"), isPresented: Binding(get: { undo != nil }, set: { if !$0 { undo = nil } }), titleVisibility: .visible) {
                    Button(tr("撤销", "Undo", "Batal"), role: .destructive) {
                        if let (ei, si, ri, isReturn) = undo { model.change { ledger in if let e = ledger.expenses.firstIndex(where: { $0.id == ei }), let s = ledger.expenses[e].shares.firstIndex(where: { $0.id == si }) { if isReturn { ledger.expenses[e].shares[s].returns?.removeAll { $0.id == ri } } else { ledger.expenses[e].shares[s].repayments.removeAll { $0.id == ri } } } } }; undo = nil
                    }
                }
        }
    }
}
struct RepaymentView: View {
    @EnvironmentObject var model: LedgerModel
    @Environment(\.dismiss) private var dismiss
    let target: RepayTarget
    @State private var amount = ""
    @State private var date = Date()
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                LabeledContent(target.share.name, value: money(abs(target.share.owed)))
                TextField(target.share.owed < 0 ? tr("退回金额 · MYR", "Amount returned · MYR", "Amaun dipulangkan · MYR") : tr("收到金额 · MYR", "Amount received · MYR", "Amaun diterima · MYR"), text: $amount).keyboardType(.decimalPad)
                DatePicker(tr("还款日期", "Repayment date", "Tarikh bayaran balik"), selection: $date, displayedComponents: .date)
                Text(tr("还款只减少欠款，不重复计作收入。", "Repayments reduce debt and are not counted as new income.", "Bayaran balik mengurangkan hutang dan bukan pendapatan baharu."))
            }.navigationTitle(tr("记录还款", "Repayment", "Bayaran balik"))
                .onAppear { amount = Currency.input(abs(target.share.owed), "MYR") }
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(tr("取消", "Cancel", "Batal")) { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button(tr("保存", "Save", "Simpan")) { do { let n = try toCents(amount); try LocalStore.shared.change { if target.share.owed < 0 { try $0.returnToFriend(expenseID: target.expense.id, shareID: target.share.id, cents: n, date: date) } else { try $0.repay(expenseID: target.expense.id, shareID: target.share.id, cents: n, date: date) } }; model.reload(); dismiss() } catch { self.error = error.localizedDescription } } } }
                .alert(tr("无法保存", "Unable to save", "Tidak dapat menyimpan"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") {} } message: { Text(error ?? "") }
        }
    }
}
struct LedgerDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
struct SettingsView: View {
    @EnvironmentObject var model: LedgerModel
    @AppStorage("appLanguage") private var language = "system"
    @AppStorage("appAppearance") private var appearance = "system"
    @State private var exporting = false
    @State private var importing = false
    @State private var document: LedgerDocument?
    @State private var restorePreview: RestorePreview?
    @State private var backups: [URL] = []
    var body: some View {
        NavigationStack {
            Form {
                Section(tr("偏好设置", "Preferences", "Pilihan")) {
                    Picker(tr("语言", "Language", "Bahasa"), selection: $language) {
                        Text(tr("跟随系统", "System default", "Ikut sistem")).tag("system")
                        Text("简体中文").tag("zh"); Text("English").tag("en"); Text("Bahasa Melayu").tag("ms")
                    }
                    Picker(tr("外观", "Appearance", "Paparan"), selection: $appearance) {
                        Text(tr("跟随系统", "System default", "Ikut sistem")).tag("system")
                        Text(tr("浅色模式", "Light mode", "Mod cerah")).tag("light")
                        Text(tr("深色模式", "Dark mode", "Mod gelap")).tag("dark")
                    }
                    NavigationLink(tr("通知与每日提醒", "Notifications & daily reminder", "Notifikasi & peringatan harian")) { NotificationSettingsView() }
                    NavigationLink(tr("商户分类规则", "Merchant category rules", "Peraturan kategori peniaga")) { MerchantRulesView() }
                    NavigationLink(tr("币种与汇率", "Currencies & rates", "Mata wang & kadar")) { RatesView() }
                    Text(tr("统计本位币：MYR", "Accounting currency: MYR", "Mata wang perakaunan: MYR")).font(.caption)
                }
                Section("Apple Pay") {
                    NavigationLink(tr("自动记账状态", "Automation status", "Status automasi")) { AutomationStatusView() }
                    Text(tr("安装后在快捷指令配置交易自动化，传入金额、商户、币种和时间。App 不会直接读取钱包历史。", "After installation, configure a Transaction automation in Shortcuts with amount, merchant, currency and date. The app cannot read Wallet history directly.", "Selepas pemasangan, tetapkan automasi Transaction dalam Pintasan dengan amaun, peniaga, mata wang dan tarikh. Aplikasi tidak membaca sejarah Wallet secara langsung."))
                    Text(tr("外币自动记账需先保存该币种汇率；缺失汇率会报错，不会偷偷按 MYR 入账。", "Save a rate before recording foreign Apple Pay payments. A missing rate causes an error, never a silent MYR conversion.", "Simpan kadar sebelum merekod Apple Pay asing. Kadar yang tiada menghasilkan ralat, bukan penukaran MYR secara senyap.")).font(.footnote)
                    NavigationLink(tr("接入步骤", "Setup steps", "Langkah persediaan")) { ShortcutHelpView() }
                }
                Section(tr("数据与备份", "Data & backups", "Data & sandaran")) {
                    Text(tr("每次修改前保留旧版，最多 30 份本地备份。卸载会删除本地数据，请定期导出到文件或 iCloud Drive。", "Keeps up to 30 local snapshots before changes. Uninstalling deletes local data. Export to Files or iCloud Drive regularly.", "Menyimpan sehingga 30 sandaran tempatan sebelum perubahan. Nyahpasang memadam data tempatan. Eksport ke Files atau iCloud Drive secara berkala.")).font(.footnote)
                    Button(tr("导出完整备份", "Export full backup", "Eksport sandaran penuh")) { do { document = LedgerDocument(data: try LocalStore.exportData(LocalStore.shared.read())); exporting = true } catch { model.error = error.localizedDescription } }
                    Button(tr("恢复 JSON 备份", "Restore JSON backup", "Pulihkan sandaran JSON")) { importing = true }
                    if FileManager.default.fileExists(atPath: LocalStore.shared.recoveryFile.path) {
                        Button(tr("恢复上次导入前的数据", "Recover data before last restore", "Pulihkan data sebelum pemulihan terakhir")) {
                            do { restorePreview = try RestorePreview(data: Data(contentsOf: LocalStore.shared.recoveryFile)) } catch { model.error = error.localizedDescription }
                        }
                    }
                    ForEach(backups, id: \.self) { url in Button { do { restorePreview = try RestorePreview(data: Data(contentsOf: url)) } catch { model.error = error.localizedDescription } } label: {
                        Text(tr("恢复：", "Restore: ", "Pulihkan: ") + backupTitle(url))
                    } }
                }
                Section(tr("版本", "Version", "Versi")) {
                    Text(installedVersionLabel)
                    Text(tr("免费侧载签名每 7 天需要刷新；过期会影响 App 和自动记账。", "Free sideload signing needs renewal every 7 days. Expiry affects the app and automatic recording.", "Tandatangan sideload percuma perlu diperbaharui setiap 7 hari. Tamat tempoh menjejaskan aplikasi dan rekod automatik.")).font(.footnote)
                }
            }.navigationTitle(tr("设置", "Settings", "Tetapan")).onAppear { loadBackups() }
                .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: "YueJi-\(monthKey(Date()))") { if case .failure(let e) = $0 { model.error = e.localizedDescription } }
                .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                    do { let url = try result.get(); let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }; let data = try Data(contentsOf: url); restorePreview = try RestorePreview(data: data) } catch { model.error = error.localizedDescription }
                }
                .sheet(item: $restorePreview) { preview in
                    RestorePreviewView(preview: preview) { loadBackups() }
                }
        }
    }
    private func loadBackups() { do { backups = try LocalStore.shared.backups() } catch { model.error = error.localizedDescription } }
    private func backupTitle(_ url: URL) -> String { guard let s = url.lastPathComponent.split(separator: "-").first, let ms = Double(s) else { return url.lastPathComponent }; return dateLabel(Date(timeIntervalSince1970: ms / 1000), time: true) }
}
struct ShortcutHelpView: View {
    var body: some View {
        List {
            Text(tr("1. 先打开月记一次，再在快捷指令中搜索「记录 Apple Pay 支出」。", "1. Open YueJi once, then find ‘Record Apple Pay expense’ in Shortcuts.", "1. Buka YueJi sekali, kemudian cari ‘Rekod belanja Apple Pay’ dalam Pintasan."))
            Text(tr("2. 普通快捷指令先测试：0.01、测试商户、MYR、当前日期、标识 test-001。重复运行相同标识只记一笔。", "2. Test a regular shortcut: 0.01, Test merchant, MYR, current date, ID test-001. Reusing the ID should not duplicate it.", "2. Uji pintasan biasa: 0.01, Peniaga ujian, MYR, tarikh semasa, ID test-001. ID sama tidak patut menghasilkan pendua."))
            Text(tr("3. 新建交易自动化，选择付款卡片及立即运行，把实际交易字段传给记账动作。不要保留测试金额。", "3. Create a Transaction automation, select your card and immediate running, and map actual payment fields to the action. Remove test values.", "3. Cipta automasi Transaction, pilih kad dan jalan serta-merta, kemudian petakan medan bayaran sebenar. Buang nilai ujian."))
            Text(tr("4. 原始交易标识优先用于去重，没有时用原始交易时间。用当前时间重跑可能重复。", "4. Prefer the original transaction ID for deduplication, otherwise its original date. Rerunning with the current date may duplicate entries.", "4. Utamakan ID transaksi asal untuk elak pendua, atau tarikh asalnya. Mengulang dengan tarikh semasa boleh menghasilkan pendua."))
            Text(tr("5. 外币先在设置保存汇率。对照一次真实付款验证金额。不同卡片、Apple Watch 和线上付款分别测试。", "5. Save foreign rates in Settings first. Verify an actual payment against the ledger. Test each card, Apple Watch and online payments separately.", "5. Simpan kadar asing dalam Tetapan dahulu. Sahkan bayaran sebenar dengan lejar. Uji setiap kad, Apple Watch dan bayaran dalam talian secara berasingan."))
            Text(tr("不能回溯漏记交易或自动处理退款。重启后先解锁一次；系统限制与签名失效可能使自动化无法运行。", "Missed payments and refunds are not recovered automatically. Unlock once after restart. System restrictions or expired signing may prevent execution.", "Bayaran terlepas dan bayaran balik tidak dipulihkan automatik. Buka kunci selepas mula semula. Sekatan sistem atau tandatangan tamat tempoh boleh menghalang pelaksanaan."))
        }.navigationTitle(tr("Apple Pay 接入", "Apple Pay setup", "Persediaan Apple Pay"))
    }
}

private var installedVersionLabel: String {
    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
    return "YueJi · \(version ?? "-") (\(build ?? "-"))"
}
