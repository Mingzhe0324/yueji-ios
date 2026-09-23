import SwiftUI
import UniformTypeIdentifiers

private let ink = Color(red: 0.10, green: 0.26, blue: 0.37)
struct GlassPanel<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View { content.padding(20).frame(maxWidth: .infinity, alignment: .leading).ledgerGlass() }
}
extension View {
    @ViewBuilder func ledgerGlass() -> some View {
        if #available(iOS 26.0, *) { self.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 26)) }
        else { self.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26)).overlay(RoundedRectangle(cornerRadius: 26).stroke(.white.opacity(0.6))) }
    }
}
struct MainView: View {
    @EnvironmentObject var model: LedgerModel
    @Environment(\.scenePhase) private var phase
    var body: some View {
        TabView {
            DashboardView().tabItem { Label("概览", systemImage: "chart.pie.fill") }
            ExpensesView().tabItem { Label("账本", systemImage: "list.bullet.rectangle") }
            FriendsView().tabItem { Label("分账", systemImage: "person.2.fill") }
            SettingsView().tabItem { Label("设置", systemImage: "slider.horizontal.3") }
        }
        .tint(ink).task { model.reload() }
        .onChange(of: phase) { _, newPhase in if newPhase == .active { model.reload() } }
        .alert("月记", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("知道了", role: .cancel) { model.error = nil }
        } message: { Text(model.error ?? "") }
    }
}
struct MonthPicker: View {
    @Binding var month: Date
    var body: some View {
        HStack {
            Button { month = Calendar.current.date(byAdding: .month, value: -1, to: month)! } label: { Image(systemName: "chevron.left").padding(8) }.accessibilityLabel("上个月")
            Spacer(); Text(month.formatted(.dateTime.year().month(.wide))).font(.headline); Spacer()
            Button { month = Calendar.current.date(byAdding: .month, value: 1, to: month)! } label: { Image(systemName: "chevron.right").padding(8) }.accessibilityLabel("下个月")
        }
    }
}
struct DashboardView: View {
    @EnvironmentObject var model: LedgerModel
    @State private var month = Date()
    @State private var adding = false
    @State private var budgetText = ""
    @State private var budgeting = false
    private var entries: [Expense] { model.ledger.expenses.filter { monthKey($0.date) == monthKey(month) } }
    private var personal: Int { entries.reduce(0) { $0 + $1.personal } }
    private var paid: Int { entries.reduce(0) { $0 + $1.cents } }
    private var budget: Int { model.ledger.budgets[monthKey(month)] ?? 0 }
    private var owed: Int { model.ledger.expenses.flatMap(\.shares).reduce(0) { $0 + $1.owed } }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    MonthPicker(month: $month)
                    GlassPanel {
                        VStack(alignment: .leading, spacing: 15) {
                            Label("我的月度消费", systemImage: "sparkles").foregroundStyle(.secondary)
                            Text(money(personal)).font(.system(size: 40, weight: .semibold, design: .rounded)).minimumScaleFactor(0.6).lineLimit(1)
                            if budget > 0 {
                                ProgressView(value: min(Double(personal) / Double(budget), 1))
                                Text(personal > budget ? "超出预算 \(money(personal - budget))" : "还可花 \(money(budget - personal))").font(.subheadline)
                            }
                            Button(budget > 0 ? "修改预算" : "设置月度预算") { budgetText = budget > 0 ? String(format: "%.2f", Double(budget) / 100) : ""; budgeting = true }.font(.subheadline)
                        }
                    }
                    HStack(alignment: .top) {
                        metric("实际付款", value: money(paid))
                        metric("朋友待还 · 全部", value: money(owed))
                    }
                    GlassPanel {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("钱花在哪里").font(.headline)
                            if entries.isEmpty { Text("记下第一笔，分类统计就会出现在这里。").foregroundStyle(.secondary) }
                            ForEach(categories, id: \.self) { category in
                                let value = entries.filter { $0.category == category }.reduce(0) { $0 + $1.personal }
                                if value > 0 {
                                    HStack { Text(category); Spacer(); Text(money(value)).monospacedDigit() }
                                    ProgressView(value: Double(value), total: Double(max(personal, 1)))
                                }
                            }
                        }
                    }
                    Button { adding = true } label: { Label("记一笔 / 朋友代垫", systemImage: "plus").frame(maxWidth: .infinity).padding(12) }.buttonStyle(.borderedProminent)
                    Text("朋友应付的份额不会算作你的消费。还款只减少欠款，不重复计入收入。").font(.footnote).foregroundStyle(.secondary)
                }.padding()
            }
            .background(LinearGradient(colors: [Color.cyan.opacity(0.15), Color.blue.opacity(0.06), Color.mint.opacity(0.14)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .navigationTitle("月记")
            .sheet(isPresented: $adding) { ExpenseEditor(original: nil) }
            .alert("月度预算 · RM", isPresented: $budgeting) {
                TextField("例如 1500", text: $budgetText).keyboardType(.decimalPad)
                Button("保存") { do { let value = try toCents(budgetText); model.change { $0.budgets[monthKey(month)] = value } } catch { model.error = error.localizedDescription } }
                Button("取消", role: .cancel) {}
            }
        }
    }
    private func metric(_ label: String, value: String) -> some View {
        GlassPanel { VStack(alignment: .leading, spacing: 8) { Text(label).font(.caption).foregroundStyle(.secondary); Text(value).font(.headline).monospacedDigit().minimumScaleFactor(0.7).lineLimit(1) } }
    }
}
struct ExpenseRow: View {
    let entry: Expense
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: entry.fuel ? "fuelpump.fill" : entry.source == "Apple Pay" ? "creditcard.fill" : "receipt").foregroundStyle(ink).frame(width: 32)
            VStack(alignment: .leading, spacing: 5) {
                Text(entry.merchant).font(.headline)
                Text("\(entry.category) · \(entry.source) · \(entry.date.formatted(date: .abbreviated, time: .omitted))").font(.caption).foregroundStyle(.secondary)
                if !entry.shares.isEmpty { Text("我的份额 \(money(entry.personal))").font(.caption).foregroundStyle(.secondary) }
            }
            Spacer(); Text(money(entry.cents)).monospacedDigit().font(.subheadline)
        }.padding(.vertical, 5)
    }
}
struct ExpensesView: View {
    @EnvironmentObject var model: LedgerModel
    @State private var month = Date()
    @State private var search = ""
    @State private var adding = false
    @State private var editing: Expense?
    @State private var deleting: Expense?
    var body: some View {
        NavigationStack {
            List {
                MonthPicker(month: $month)
                let entries = model.ledger.expenses.filter { monthKey($0.date) == monthKey(month) && (search.isEmpty || $0.merchant.localizedCaseInsensitiveContains(search) || $0.category.contains(search)) }.sorted { $0.date > $1.date }
                if entries.isEmpty { ContentUnavailableView("暂无记录", systemImage: "tray", description: Text("Apple Pay 自动入账或手动记录后，会在这里显示。")) }
                ForEach(entries) { e in
                    Button { editing = e } label: { ExpenseRow(entry: e).foregroundStyle(.primary) }
                        .swipeActions { Button("删除", role: .destructive) { deleting = e } }
                }
            }.navigationTitle("账本").searchable(text: $search, prompt: "搜索商户、分类")
                .toolbar { Button { adding = true } label: { Image(systemName: "plus") }.accessibilityLabel("新增消费") }
                .sheet(isPresented: $adding) { ExpenseEditor(original: nil) }
                .sheet(item: $editing) { ExpenseEditor(original: $0) }
                .confirmationDialog("删除付款及其分账、还款记录？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                    Button("删除", role: .destructive) { if let deleting { model.change { $0.expenses.removeAll { $0.id == deleting.id } } }; deleting = nil }
                }
        }
    }
}
struct FriendDraft: Identifiable {
    var id: String
    var name: String
    var amount: String
    var repayments: [Repayment]
    init(_ share: Share = Share(name: "", cents: 0)) { id = share.id; name = share.name; amount = String(format: "%.2f", Double(share.cents) / 100); repayments = share.repayments }
}
struct ExpenseEditor: View {
    @EnvironmentObject var model: LedgerModel
    @Environment(\.dismiss) private var dismiss
    let original: Expense?
    @State private var name = ""
    @State private var amount = ""
    @State private var date = Date()
    @State private var category = "其他"
    @State private var splitting = false
    @State private var fuel = false
    @State private var equal = true
    @State private var includeMe = true
    @State private var people: [FriendDraft] = [FriendDraft()]
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section("实际付款") {
                    TextField(fuel ? "行程，例如 UMS → 市区" : "商户 / 消费内容", text: $name)
                    TextField("金额 · RM", text: $amount).keyboardType(.decimalPad)
                    DatePicker("日期", selection: $date, displayedComponents: [.date, .hourAndMinute])
                    Picker("分类", selection: $category) { ForEach(categories, id: \.self) { Text($0) } }
                }
                Section {
                    Toggle("朋友分账", isOn: $splitting)
                    if splitting {
                        Toggle("这是行程油费", isOn: $fuel).onChange(of: fuel) { _, value in if value { category = "交通" } }
                        Picker("分摊方式", selection: $equal) { Text("平均分摊").tag(true); Text("自定金额").tag(false) }.pickerStyle(.segmented)
                        if equal { Toggle("我也参与分摊", isOn: $includeMe) }
                        ForEach($people) { $person in
                            VStack(alignment: .leading) {
                                HStack {
                                    TextField("朋友姓名", text: $person.name)
                                    Button(role: .destructive) { people.removeAll { $0.id == person.id } } label: { Image(systemName: "minus.circle") }.disabled(!person.repayments.isEmpty || people.count == 1)
                                }
                                if !equal { TextField("朋友应付 · RM", text: $person.amount).keyboardType(.decimalPad) }
                                if !person.repayments.isEmpty { Text("已还 \(money(person.repayments.reduce(0) { $0 + $1.cents }))；如需移除，请先撤销还款。").font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                        Button("添加朋友") { people.append(FriendDraft()) }
                        if let total = try? toCents(amount), equal {
                            let values = equalShares(total: total, count: people.count, includeMe: includeMe)
                            Text("我的份额 \(money(total - values.reduce(0, +)))").font(.headline)
                            ForEach(Array(values.enumerated()), id: \.offset) { index, value in Text("\(people[index].name.isEmpty ? "朋友 \(index + 1)" : people[index].name)：\(money(value))").font(.subheadline) }
                        }
                    }
                } footer: { Text("已有 Apple Pay 付款请直接编辑该记录分账。油费请使用实际支出，避免把已记录的加油金额再新增一次。") }
            }.navigationTitle(original == nil ? "记一笔" : "编辑 / 分账")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("保存") { commit() } } }
                .onAppear { if let e = original { name = e.merchant; amount = String(format: "%.2f", Double(e.cents) / 100); date = e.date; category = e.category; fuel = e.fuel; splitting = !e.shares.isEmpty; equal = e.shares.isEmpty; if splitting { people = e.shares.map(FriendDraft.init) } } }
                .alert("无法保存", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("知道了", role: .cancel) {} } message: { Text(error ?? "") }
        }
    }
    private func commit() {
        do {
            let total = try toCents(amount)
            var entry = original ?? Expense(merchant: "", cents: total)
            entry.merchant = name.trimmingCharacters(in: .whitespacesAndNewlines); entry.cents = total; entry.date = date; entry.category = category; entry.fuel = fuel
            if !splitting && (original?.shares.contains { !$0.repayments.isEmpty } ?? false) { throw LedgerError.invalid("已有还款，不能直接关闭分账；请先撤销还款。") }
            if splitting {
                let values: [Int]
                if equal { values = equalShares(total: total, count: people.count, includeMe: includeMe) }
                else { values = try people.map { person in
                    if person.amount == "0" || person.amount == "0.00" { return 0 }
                    return try toCents(person.amount)
                } }
                entry.shares = zip(people, values).map { p, value in Share(id: p.id, name: p.name.trimmingCharacters(in: .whitespacesAndNewlines), cents: value, repayments: p.repayments) }
                guard !entry.shares.contains(where: { $0.repayments.contains { $0.date < Calendar.current.startOfDay(for: date) } }) else { throw LedgerError.invalid("付款日期不能晚于已有还款日期。") }
            } else { entry.shares = [] }
            try LocalStore.shared.change { ledger in
                if let original {
                    guard let index = ledger.expenses.firstIndex(where: { $0.id == original.id }), ledger.expenses[index] == original else { throw LedgerError.invalid("这笔记录已改变，请重新打开后编辑。") }
                    ledger.expenses[index] = entry
                } else { ledger.expenses.append(entry) }
            }
            model.reload(); dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
struct RepayTarget: Identifiable { var id: String { share.id }; let expense: Expense; let share: Share }
struct FriendsView: View {
    @EnvironmentObject var model: LedgerModel
    @State private var target: RepayTarget?
    @State private var editing: Expense?
    @State private var adding = false
    @State private var undo: (String, String, String)?
    var body: some View {
        NavigationStack {
            List {
                let shared = model.ledger.expenses.filter { !$0.shares.isEmpty }.sorted { $0.date > $1.date }
                Section { LabeledContent("全部月份待还", value: money(shared.flatMap(\.shares).reduce(0) { $0 + $1.owed })) }
                if shared.isEmpty { ContentUnavailableView("还没有朋友分账", systemImage: "person.2", description: Text("编辑已有付款并开启朋友分账，或新增实际代垫。")) }
                ForEach(shared) { e in
                    Section {
                        ForEach(e.shares) { s in
                            VStack(alignment: .leading, spacing: 9) {
                                HStack { Text(s.name).font(.headline); Spacer(); Text(s.owed == 0 ? "已结清" : "待还 \(money(s.owed))") }
                                Text("应付 \(money(s.cents)) · 已还 \(money(s.repaid))").font(.caption).foregroundStyle(.secondary)
                                if s.owed > 0 { Button("记录还款") { target = RepayTarget(expense: e, share: s) } }
                                ForEach(s.repayments) { r in
                                    HStack { Text("\(r.date.formatted(date: .abbreviated, time: .omitted)) · \(money(r.cents))").font(.caption); Spacer(); Button("撤销") { undo = (e.id, s.id, r.id) }.font(.caption) }
                                }
                            }.padding(.vertical, 5)
                        }
                        Button("修改这笔分账") { editing = e }
                    } header: { Text(e.merchant) } footer: { Text("实付 \(money(e.cents)) · 我的份额 \(money(e.personal))") }
                }
            }.navigationTitle("朋友分账")
                .toolbar { Button { adding = true } label: { Image(systemName: "plus") } }
                .sheet(isPresented: $adding) { ExpenseEditor(original: nil) }
                .sheet(item: $editing) { ExpenseEditor(original: $0) }
                .sheet(item: $target) { RepaymentView(target: $0) }
                .confirmationDialog("撤销这笔还款？", isPresented: Binding(get: { undo != nil }, set: { if !$0 { undo = nil } }), titleVisibility: .visible) { Button("撤销还款", role: .destructive) { if let (ei, si, ri) = undo { model.change { ledger in if let e = ledger.expenses.firstIndex(where: { $0.id == ei }), let s = ledger.expenses[e].shares.firstIndex(where: { $0.id == si }) { ledger.expenses[e].shares[s].repayments.removeAll { $0.id == ri } } } }; undo = nil } }
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
                LabeledContent(target.share.name, value: "待还 \(money(target.share.owed))")
                TextField("本次收到 · RM", text: $amount).keyboardType(.decimalPad)
                DatePicker("还款日期", selection: $date, displayedComponents: .date)
                Text("还款减少欠款，不会作为新收入。")
            }.navigationTitle("记录还款").onAppear { amount = String(format: "%.2f", Double(target.share.owed) / 100) }
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("保存") { do { let cents = try toCents(amount); try LocalStore.shared.change { try $0.repay(expenseID: target.expense.id, shareID: target.share.id, cents: cents, date: date) }; model.reload(); dismiss() } catch { self.error = error.localizedDescription } } } }
                .alert("无法保存", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("知道了") {} } message: { Text(error ?? "") }
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
    @State private var exporting = false
    @State private var importing = false
    @State private var document: LedgerDocument?
    @State private var pendingRestore: Data?
    @State private var backups: [URL] = []
    var body: some View {
        NavigationStack {
            Form {
                Section("Apple Pay 自动记账") {
                    Label("已提供原生快捷指令动作", systemImage: "bolt.circle.fill")
                    Text("动作名称：记录 Apple Pay 支出").font(.subheadline)
                    Text("App 不会直接读取钱包交易。请在快捷指令设置「交易」自动化，把付款金额、商户、币种和交易时间传给这个动作。").font(.footnote).foregroundStyle(.secondary)
                    if let latest = model.ledger.expenses.filter({ $0.source == "Apple Pay" }).max(by: { $0.date < $1.date }) { LabeledContent("最近接收", value: latest.date.formatted(date: .abbreviated, time: .shortened)) }
                    else { Text("尚无 Apple Pay 入账，请按安装指南进行实机测试。").foregroundStyle(.secondary) }
                    NavigationLink("查看设置步骤") { ShortcutHelpView() }
                }
                Section("数据与备份") {
                    Text("数据保存在本机。每次更改前自动保留上一版本，最多 30 份；这不是跨设备云同步。卸载 App 会删除本地账本和历史备份。").font(.footnote)
                    Button("导出完整备份到文件 / iCloud Drive") { do { document = LedgerDocument(data: try LocalStore.encode(LocalStore.shared.read())); exporting = true } catch { model.error = error.localizedDescription } }
                    Button("恢复 JSON 备份") { importing = true }
                    Button("刷新历史备份") { loadBackups() }
                    ForEach(backups.prefix(30), id: \.self) { url in
                        Button { do { pendingRestore = try Data(contentsOf: url) } catch { model.error = error.localizedDescription } } label: { HStack { Text(backupTitle(url)); Spacer(); Text("恢复").foregroundStyle(ink) } }
                    }
                }
                Section("当前版本") {
                    Text("月记 · 原生 iPhone App · 1.0")
                    Text("仅支持 MYR。TNG 手动记账。无需原网页的密钥或后台令牌。").font(.footnote)
                    Text("免费侧载安装通常需要每 7 天刷新签名。签名过期时 App 与自动化可能无法运行，请及时刷新并定期导出备份。").font(.footnote).foregroundStyle(.secondary)
                }
            }.navigationTitle("设置").onAppear { loadBackups() }
                .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: "月记-\(monthKey(Date()))") { result in if case .failure(let error) = result { model.error = error.localizedDescription } }
                .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                    do { let url = try result.get(); let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }; let data = try Data(contentsOf: url); _ = try LocalStore.decode(data); pendingRestore = data } catch { model.error = error.localizedDescription }
                }
                .confirmationDialog("用此备份替换账本？当前数据会先保留为历史备份。", isPresented: Binding(get: { pendingRestore != nil }, set: { if !$0 { pendingRestore = nil } }), titleVisibility: .visible) {
                    Button("确认恢复", role: .destructive) { if let data = pendingRestore { do { try LocalStore.shared.restore(data); model.reload(); loadBackups() } catch { model.error = error.localizedDescription } }; pendingRestore = nil }
                }
        }
    }
    private func loadBackups() { do { backups = try LocalStore.shared.backups() } catch { model.error = error.localizedDescription } }
    private func backupTitle(_ url: URL) -> String { guard let part = url.lastPathComponent.split(separator: "-").first, let ms = Double(part) else { return "历史备份" }; return Date(timeIntervalSince1970: ms / 1000).formatted(date: .abbreviated, time: .standard) }
}
struct ShortcutHelpView: View {
    var body: some View {
        List {
            Section("先测试动作能否写入") {
                Text("1. 安装后先打开月记一次。")
                Text("2. 在快捷指令新建普通快捷指令，搜索「月记」→「记录 Apple Pay 支出」。")
                Text("3. 测试金额 0.01、商户 测试、币种 MYR、交易时间 当前日期、交易标识 test-001。运行后打开账本检查；同一标识再运行应不重复记账。测试后可删除该笔。")
            }
            Section("再接 Apple Pay") {
                Text("4. 自动化 → 新建 → 交易 / Transaction → 选择付款卡片，并选择立即运行（如系统提供）。")
                Text("5. 添加「记录 Apple Pay 支出」，从快捷指令输入选取 Amount、Merchant、Currency、Date 等实际可用字段，不要填死测试金额。")
                Text("6. 原始交易标识存在时直接使用；没有时保留原始交易时间供去重。日期缺失可用当前日期作为接收时间，但重跑可能重复入账。金额缺失时不要启用自动入账。")
                Text("7. 做一次实际的小额付款，对照钱包金额与账本记录。确认无误后日常使用。Apple Watch、线上付款及不同卡片触发行为要分别测试。")
            }
            Section("边界") {
                Text("只记录传入的成功消费，不自动回溯历史交易、不自动处理退款或失败交易。MYR 以外的币种会拒绝入账。")
                Text("通知 / 交易字段由 iOS 和卡片提供。安装完成不代表自动化已配置。重启后需先解锁一次；不能保证所有锁屏、系统限制场景都执行成功。")
            }
        }.navigationTitle("Apple Pay 接入")
    }
}
