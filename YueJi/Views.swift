import SwiftUI
import UniformTypeIdentifiers
import UIKit

private let ink = Color(uiColor: .systemBlue)
struct GlassPanel<Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @ViewBuilder var content: Content
    var body: some View {
        content.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 26))
            .overlay(RoundedRectangle(cornerRadius: 26).strokeBorder(.primary.opacity(0.06)))
            .opacity(appeared || reduceMotion ? 1 : 0)
            .offset(y: appeared || reduceMotion ? 0 : 4)
            .onAppear { withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.95)) { appeared = true } }
    }
}
extension View {
    func ledgerGlass() -> some View { modifier(YueJiGlassSurface()) }

}
struct MainView: View {
    @EnvironmentObject var model: LedgerModel
    @Environment(\.scenePhase) private var phase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("completedUsageGuide") private var completedGuide = false
    @State private var showingGuide = false
    @State private var selectedTab = 0
    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView().tag(0).tabItem { Label(tr("概览", "Overview", "Ringkasan"), systemImage: "chart.pie.fill") }
            ExpensesView().tag(1).tabItem { Label(tr("账本", "Ledger", "Lejar"), systemImage: "list.bullet.rectangle") }
            RecurringView().tag(2).tabItem { Label(tr("固定", "Recurring", "Berulang"), systemImage: "repeat") }
            FriendsView().tag(3).tabItem { Label(tr("分账", "Friends", "Rakan"), systemImage: "person.2.fill") }
            SettingsView().tag(4).tabItem { Label(tr("设置", "Settings", "Tetapan"), systemImage: "slider.horizontal.3") }
        }.tint(ink).task { model.reload(postRecurring: false); if !completedGuide { showingGuide = true }; await AutomaticRates.shared.refreshSaved(); model.reload() }
            .sheet(isPresented: $showingGuide, onDismiss: { completedGuide = true }) {
                UsageGuideView()
            }
            .onChange(of: selectedTab) { _, _ in UISelectionFeedbackGenerator().selectionChanged() }
            .overlay(alignment: .top) {
                if model.savedNotice != nil {
                    Label(tr("已保存", "Saved", "Disimpan"), systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(ink)
                        .padding(.horizontal, 20).padding(.vertical, 12).ledgerGlass()
                        .padding(.top, 8).allowsHitTesting(false)
                        .accessibilityLabel(tr("账目已保存", "Entry saved", "Rekod disimpan"))
                        .transition(reduceMotion ? .opacity : .scale(scale: 0.97).combined(with: .opacity))
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: model.savedNotice)
            .task(id: model.savedNotice) {
                guard let token = model.savedNotice else { return }
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
                if model.savedNotice == token { model.savedNotice = nil }
            }
            .onChange(of: phase) { _, value in if value == .active { model.reload(postRecurring: false); Task { await AutomaticRates.shared.refreshSaved(); model.reload() } } }
            .alert(tr("月记", "YueJi", "YueJi"), isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
                Button(tr("知道了", "OK", "OK"), role: .cancel) { model.error = nil }
            } message: { Text(model.error ?? "") }
    }
}
struct MonthPicker: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var month: Date
    var body: some View {
        HStack(spacing: 0) {
            Button { shift(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44).contentShape(Rectangle()) }
                .buttonStyle(.borderless)
                .accessibilityLabel(tr("上个月", "Previous month", "Bulan sebelumnya"))
            Text(month.formatted(.dateTime.year().month(.wide).locale(Locale(identifier: AppLanguage.localeID))))
                .font(.headline).contentTransition(.opacity).frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
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
    private func shift(_ n: Int) { UISelectionFeedbackGenerator().selectionChanged(); withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.9)) { month = shiftedMonth(month, by: n) } }
}
struct DashboardView: View {
    @Namespace private var navigationMotion
    @EnvironmentObject var model: LedgerModel
    @SceneStorage("overviewMonth") private var monthTimestamp = Date().timeIntervalSince1970
    @State private var adding = false
    @State private var budgetText = ""
    @State private var budgeting = false
    private var month: Date { Date(timeIntervalSince1970: monthTimestamp) }
    private var monthBinding: Binding<Date> { Binding(get: { month }, set: { monthTimestamp = $0.timeIntervalSince1970 }) }
    private var entries: [Expense] { model.ledger.expenses.filter { monthKey($0.date) == monthKey(month) } }
    private var personal: Int { entries.reduce(0) { $0 + $1.personal } }
    private var budget: Int { model.ledger.budgets[monthKey(month)] ?? 0 }
    private var owed: Int { model.ledger.expenses.flatMap(\.shares).reduce(0) { $0 + max(0, $1.owed) } }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    MonthPicker(month: monthBinding)
                    spendingCard
                    balancesCard
                    categoriesCard
                    NavigationLink { ReceiptScanView() } label: { DashboardLinkLabel(title: tr("拍收据分账", "Snap receipt & split", "Imbas resit & bahagi"), symbol: "camera") }
                    NavigationLink { AutomationSetupView() } label: {
                        SimpleSettingsRow(title: tr("自动记账", "Automatic recording", "Rekod automatik"), subtitle: "Apple Pay · TNG", symbol: "bolt.fill", color: .teal)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(14)
                            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))
                    }.buttonStyle(.plain)
                    NavigationLink { OverviewToolsView(month: month) } label: {
                        Label(tr("更多工具", "More tools", "Alat lain"), systemImage: "square.grid.2x2")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }.yuejiPrimaryButton().buttonBorderShape(.capsule)
                }.padding(20)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(tr("月记", "YueJi", "YueJi"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        OverviewToolsView(month: month).yuejiZoom(id: "overview-tools", namespace: navigationMotion)
                    } label: {
                        Image(systemName: "ellipsis.circle").yuejiZoomSource(id: "overview-tools", namespace: navigationMotion)
                    }
                        .accessibilityLabel(tr("更多工具", "More tools", "Alat lain"))
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button { adding = true } label: {
                    Label(tr("记一笔", "Add expense", "Tambah belanja"), systemImage: "plus")
                        .font(.headline).frame(maxWidth: .infinity, minHeight: 52)
                        .contentShape(Rectangle())
                }
                .yuejiPrimaryButton().buttonBorderShape(.capsule)
                .padding(.horizontal, 24).padding(.vertical, 10)
                .background(.bar)
            }
            .sheet(isPresented: $adding) { ExpenseEditor(original: nil, initialDate: dateForNewExpense(in: month)) }
            .alert(tr("月度预算 · MYR", "Monthly budget · MYR", "Bajet bulanan · MYR"), isPresented: $budgeting) {
                TextField("1500.00", text: $budgetText).keyboardType(.decimalPad)
                Button(tr("保存", "Save", "Simpan")) { do { let n = try toCents(budgetText); model.change { $0.budgets[monthKey(month)] = n } } catch { model.error = error.localizedDescription } }
                Button(tr("移除预算", "Remove budget", "Buang bajet"), role: .destructive) { model.change { $0.budgets.removeValue(forKey: monthKey(month)) } }
                Button(tr("取消", "Cancel", "Batal"), role: .cancel) {}
            }
        }
    }
    private var spendingCard: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 18) {
                Label(tr("本月 · 我的实际消费", "This month · my spending", "Bulan ini · belanja saya"), systemImage: "chart.pie.fill")
                    .font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                AnimatedMoney(cents: personal, animateOnAppear: true)
                    .font(.system(.largeTitle, design: .default, weight: .bold))
                    .foregroundStyle(ink).minimumScaleFactor(0.5).lineLimit(1)
                Text(tr("已扣除朋友承担的份额和属于你的退款", "After friends’ shares and your refunds", "Selepas bahagian rakan dan bayaran balik anda"))
                    .font(.caption).foregroundStyle(.secondary)
                Divider()
                if budget > 0 {
                    HStack(alignment: .firstTextBaseline) {
                        Text(personal > budget ? tr("超出预算", "Over budget", "Melebihi bajet") : tr("预算剩余", "Budget remaining", "Baki bajet"))
                        Spacer()
                        Text(money(abs(budget - personal))).monospacedDigit().fontWeight(.semibold)
                    }.font(.subheadline)
                    SpendingMeter(value: personal, total: budget, color: personal > budget ? .orange : ink)
                }
                Button { budgetText = budget > 0 ? Currency.input(budget, "MYR") : ""; budgeting = true } label: {
                    Label(budget > 0 ? tr("调整预算", "Edit budget", "Ubah bajet") : tr("设置本月预算", "Set this month’s budget", "Tetapkan bajet bulan ini"), systemImage: "slider.horizontal.3")
                        .font(.subheadline.weight(.medium)).padding(.vertical, 4)
                }
            }
        }
    }
    private var balancesCard: some View {
        GlassPanel {
            VStack(spacing: 16) {
                LabeledContent(tr("本月实际付款", "Paid this month", "Dibayar bulan ini"), value: money(entries.reduce(0) { $0 + $1.cents }))
                if entries.contains(where: { $0.refunded > 0 }) {
                    LabeledContent(tr("这些付款已退金额", "Refunded on these payments", "Bayaran ini dipulangkan"), value: money(entries.reduce(0) { $0 + $1.refunded }))
                }
                Divider()
                NavigationLink { FriendSummaryView() } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Label(tr("朋友待还", "Friends owe", "Hutang rakan"), systemImage: "person.2.fill")
                            Text(tr("全部月份", "All months", "Semua bulan")).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(money(owed)).monospacedDigit().fontWeight(.semibold)
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    }.foregroundStyle(.primary)
                }.buttonStyle(.plain)
            }.font(.subheadline)
        }
    }
    private var categoriesCard: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 18) {
                Text(tr("钱花在哪里", "Where it went", "Ke mana belanja")).font(.headline)
                if personal == 0 {
                    Label(tr("暂无个人消费", "No personal spending yet", "Belum ada belanja peribadi"), systemImage: "leaf")
                        .foregroundStyle(.secondary)
                    Text(tr("记录消费后，这里会显示你的分类占比。", "Your category breakdown will appear here.", "Pecahan kategori anda akan dipaparkan di sini."))
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                ForEach(model.ledger.categoryNames, id: \.self) { category in
                    let value = entries.filter { $0.category == category }.reduce(0) { $0 + $1.personal }
                    if value > 0 {
                        VStack(spacing: 9) {
                            HStack { CategoryBadge(name: category); Spacer(); AnimatedMoney(cents: value).fontWeight(.medium) }.font(.subheadline)
                            SpendingMeter(value: value, total: max(personal, 1), color: ink)
                        }
                    }
                }
            }
        }
    }
}
struct OverviewToolsView: View {
    var month: Date = Date()
    var body: some View {
        List {
            NavigationLink(tr("拍收据分账", "Snap receipt & split", "Imbas resit & bahagi")) { ReceiptScanView() }
            Section(tr("分析", "Insights", "Analisis")) {
                NavigationLink { SpendingComparisonView(month: month) } label: { Label(tr("月度消费对比", "Monthly comparison", "Perbandingan bulanan"), systemImage: "chart.bar.xaxis") }
                NavigationLink { UpcomingView(initialMonth: month) } label: { Label(tr("固定消费预览", "Upcoming bills", "Bil akan datang"), systemImage: "calendar") }
                NavigationLink { DuplicateReviewView() } label: { Label(tr("检查重复账目", "Review duplicates", "Semak pendua"), systemImage: "doc.on.doc") }
            }
            Section {
                NavigationLink(tr("预算与每日提醒", "Budget & daily reminders", "Peringatan bajet & harian")) { NotificationSettingsView() }
            }
        }.navigationTitle(tr("更多工具", "More tools", "Alat lain")).navigationBarTitleDisplayMode(.inline)
    }
}
struct DashboardLinkLabel: View {
    let title: String
    let symbol: String
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).foregroundStyle(ink).frame(width: 28)
            Text(title).foregroundStyle(.primary).frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        }.font(.subheadline).padding(.vertical, 5).contentShape(Rectangle())
    }
}
struct SpendingMeter: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    let value: Int
    let total: Int
    let color: Color
    private var fraction: Double { min(max(Double(value) / Double(max(total, 1)), 0), 1) }
    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(color.opacity(0.10))
                Capsule().fill(color).frame(width: proxy.size.width * (appeared || reduceMotion ? fraction : 0))
            }
        }.frame(height: 7)
            .onAppear { appeared = true }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.35), value: appeared)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: fraction)
            .accessibilityHidden(true)
    }
}
struct ExpenseRow: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let entry: Expense
    private var rowLayout: AnyLayout { typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(alignment: .center, spacing: 12)) }
    var body: some View {
        rowLayout {
            Image(systemName: entry.fuel ? "fuelpump.fill" : entry.recurringKey != nil ? "repeat" : "creditcard.fill")
                .font(.title3).foregroundStyle(ink).frame(width: 42, height: 42)
                .background(ink.opacity(0.08), in: RoundedRectangle(cornerRadius: 14)).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(entry.merchant).font(.headline)
                CategoryBadge(name: entry.category).font(.caption)
                Text("\(sourceLabel(entry.source)) · \(dateLabel(entry.date))").font(.caption).foregroundStyle(.secondary)
                if let fx = entry.foreign { Text(Currency.display(fx.minor, fx.currency) + " · 1 \(fx.currency) = \(fx.quote.text) MYR").font(.caption) }
                if entry.refunded > 0 { Text(tr("已退款：", "Refunded: ", "Dipulangkan: ") + "+" + money(entry.refunded)).font(.caption).foregroundStyle(.green) }
                if entry.receiptSummary != nil { Label(tr("含收据税费", "Receipt charges included", "Termasuk caj resit"), systemImage: "doc.text").font(.caption).foregroundStyle(.secondary) }
                if !entry.shares.isEmpty { Text(tr("我的份额：", "My share: ", "Bahagian saya: ") + money(entry.personal)).font(.caption) }
            }
            if !typeSize.isAccessibilitySize { Spacer(minLength: 8) }
            Text("−" + money(entry.cents)).foregroundStyle(.red).accessibilityLabel(tr("支出 ", "Expense ", "Belanja ") + money(entry.cents)).monospacedDigit().font(.subheadline.weight(.semibold)).multilineTextAlignment(.trailing).layoutPriority(1)
        }.padding(.vertical, 10)
    }
}
private struct LedgerDayGroup: Identifiable {
    let date: Date
    let entries: [Expense]
    var id: Date { date }
}
struct ExpensesView: View {
    @EnvironmentObject var model: LedgerModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var filter = LedgerFilter()
    @State private var filtering = false
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
    private var entries: [Expense] { (try? model.ledger.filteredEntries(in: month, search: search, filter: filter)) ?? [] }
    private var days: [LedgerDayGroup] {
        Dictionary(grouping: entries, by: { Calendar.current.startOfDay(for: $0.date) })
            .map { LedgerDayGroup(date: $0.key, entries: $0.value) }.sorted { $0.date > $1.date }
    }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    MonthPicker(month: monthBinding)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(filter.active || !search.isEmpty ? tr("筛选结果 · 我的消费", "Filtered · my spending", "Ditapis · belanja saya") : tr("本月 · 我的消费", "This month · my spending", "Bulan ini · belanja saya"))
                            .font(.caption).foregroundStyle(.secondary)
                        AnimatedMoney(cents: entries.reduce(0) { $0 + $1.personal })
                            .font(.system(.title2, design: .default, weight: .semibold)).foregroundStyle(ink)
                        HStack {
                            Text(String(entries.count) + tr(" 笔记录", " entries", " rekod")).font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button { filtering = true } label: { Label(filter.active ? tr("筛选已启用", "Filters active", "Penapis aktif") : tr("筛选", "Filter", "Tapis"), systemImage: "line.3.horizontal.decrease.circle") }
                                .buttonStyle(.borderless).font(.subheadline)
                        }
                    }.padding(.vertical, 6)
                }
                if entries.isEmpty {
                    ContentUnavailableView {
                        Label(tr("暂无记录", "No entries", "Tiada rekod"), systemImage: "tray")
                    } description: {
                        Text(filter.active || !search.isEmpty
                             ? tr("试试其他关键词，或清除筛选。", "Try another search or clear your filters.", "Cuba carian lain atau kosongkan penapis.")
                             : tr("为这个月记一笔，日期会保留在所选月份。", "Add an expense for the selected month.", "Tambah belanja untuk bulan dipilih."))
                    } actions: {
                        if filter.active || !search.isEmpty {
                            Button(tr("清除筛选与搜索", "Clear filters and search", "Kosongkan penapis dan carian")) { filter = LedgerFilter(); search = "" }
                        } else {
                            Button(tr("记一笔", "Add expense", "Tambah belanja")) { adding = true }.yuejiPrimaryButton()
                        }
                    }.listRowBackground(Color.clear)
                }
                ForEach(days) { day in
                    Section {
                        ForEach(day.entries) { entry in
                            Button { editing = entry } label: { ExpenseRow(entry: entry).foregroundStyle(.primary) }
                                .swipeActions { Button(tr("删除", "Delete", "Padam"), role: .destructive) { deleting = entry } }
                        }
                    } header: { Text(dateLabel(day.date)) }
                }
            }.listStyle(.insetGrouped).animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: filter)
                .sheet(isPresented: $filtering) { LedgerFilterEditor(value: filter) { filter = $0 } }
                .navigationTitle(tr("账本", "Ledger", "Lejar")).searchable(text: $search, prompt: tr("商户、分类", "Merchant, category", "Peniaga, kategori"))
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            NavigationLink(tr("TNG 通知 / 待确认", "TNG inbox / review", "Peti TNG / semakan")) { TNGInboxView() }
                            NavigationLink(tr("检查重复账目", "Review possible duplicates", "Semak rekod pendua")) { DuplicateReviewView() }
                        } label: { Image(systemName: "ellipsis.circle") }
                            .accessibilityLabel(tr("更多工具", "More tools", "Alat lain"))
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { adding = true } label: { Image(systemName: "plus") }
                            .accessibilityLabel(tr("记一笔", "Add expense", "Tambah belanja"))
                    }
                }
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
    var startWithSplit = false
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
    @State private var rateLoading = false
    @State private var rateNote = ""
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
                if let summary = (original ?? initialDraft)?.receiptSummary {
                    Section(tr("收据税费", "Receipt charges", "Caj resit")) { Text(summary).font(.caption) }
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
                        if rateLoading { ProgressView() }
                        if !rateNote.isEmpty { Text(rateNote).font(.caption).foregroundStyle(.secondary) }
                        Text("1 \(currency) = ? MYR").font(.caption)
                        TextField(tr("汇率", "Exchange rate", "Kadar pertukaran"), text: $rate).keyboardType(.decimalPad).disabled(rateLoading)
                        Text(tr("可填写银行实际汇率。保存后不会随参考汇率变化。", "You may enter your bank's actual rate. Saved entries will not change with market rates.", "Anda boleh isi kadar sebenar bank. Rekod disimpan tidak berubah mengikut kadar pasaran.")).font(.caption)
                        if let n = try? total() { LabeledContent(tr("换算为", "Converted to", "Ditukar kepada"), value: money(n)) }
                    }
                    DatePicker(tr("日期", "Date", "Tarikh"), selection: $date, displayedComponents: [.date, .hourAndMinute])
                    Picker(tr("分类", "Category", "Kategori"), selection: $category) { ForEach(model.ledger.categoryNames, id: \.self) { Text(categoryLabel($0)).tag($0) } }
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
            }.navigationTitle(tr("记账 / 分账", "Expense / split", "Belanja / pembahagian")).navigationBarTitleDisplayMode(.inline).presentationDragIndicator(.visible).presentationCornerRadius(28)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(tr("取消", "Cancel", "Batal")) { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button(tr("保存", "Save", "Simpan")) { commit() }.disabled(rateLoading) } }
                .onAppear { load() }
                .task(id: currency) {
                    guard original == nil, currency != "MYR" else { return }
                    rateLoading = true; defer { rateLoading = false }
                    do {
                        if let q = try await AutomaticRates.shared.refresh(currency) {
                            try Task.checkCancellation()
                            rate = q.text; rateDate = q.date; rateSource = q.source
                            rateNote = q.source + " · " + dateLabel(q.date)
                        }
                    } catch {
                        if !Task.isCancelled { rateNote = tr("更新失败，已保留现有汇率，请核对日期。", "Refresh failed. Review the existing rate and date.", "Kemas kini gagal. Semak kadar dan tarikh sedia ada.") }
                    }
                }
                .alert(tr("无法保存", "Unable to save", "Tidak dapat menyimpan"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") {} } message: { Text(error ?? "") }
        }
    }
    private func load() {
        guard !initialized else { return }; initialized = true
        if original == nil { date = initialDate; splitting = startWithSplit }
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
            if entry.cents != n || currency != "MYR" { entry.receiptSummary = nil }
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
            model.reload(); model.showSaved(); dismiss(); onSaved?()
        } catch { self.error = error.localizedDescription }
    }
}
struct RepayTarget: Identifiable { var id: String { share.id }; let expense: Expense; let share: Share }
struct FriendsView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject var model: LedgerModel
    @State private var settled = false
    @State private var adding = false
    private var balances: [FriendBalance] { model.ledger.friendBalances }
    private var visible: [FriendBalance] { balances.filter { ($0.owed == 0 && $0.payable == 0) == settled } }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(tr("朋友还欠你", "Friends owe you", "Rakan berhutang kepada anda")).font(.subheadline).foregroundStyle(.secondary)
                        AnimatedMoney(cents: balances.reduce(0) { $0 + $1.owed }).font(.system(.title, design: .default, weight: .bold)).foregroundStyle(ink)
                        let payable = balances.reduce(0) { $0 + $1.payable }
                        if payable > 0 { Text(tr("你需退回：", "You owe back: ", "Anda perlu pulangkan: ") + money(payable)).font(.subheadline).foregroundStyle(.orange) }
                        Text(tr("全部月份 · 点朋友查看明细和记录还款", "All months · tap a friend to settle up", "Semua bulan · ketik rakan untuk bayar balik")).font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 8)
                }
                Section {
                    Picker(tr("显示", "Show", "Papar"), selection: $settled) {
                        Text(tr("未结清", "Outstanding", "Belum selesai")).tag(false)
                        Text(tr("已结清", "Settled", "Selesai")).tag(true)
                    }.pickerStyle(.segmented).listRowBackground(Color.clear).listRowInsets(EdgeInsets())
                }
                Section {
                    if visible.isEmpty {
                        ContentUnavailableView(settled ? tr("还没有结清记录", "No settled balances", "Tiada baki selesai") : tr("目前没有待收款", "Nothing outstanding", "Tiada baki tertunggak"), systemImage: "person.2", description: Text(tr("新增代垫，或到账本为已有付款开启分账。", "Add an advance, or split an existing payment in Ledger.", "Tambah pendahuluan, atau bahagi bayaran sedia ada dalam Lejar.")))
                    }
                    ForEach(visible) { friend in
                        NavigationLink { FriendDetailView(key: friend.id) } label: { FriendBalanceRow(friend: friend) }
                    }
                }
                Section {
                    NavigationLink { FuelCalculatorView() } label: { SimpleSettingsRow(title: tr("行程分摊", "Split a trip", "Bahagi perjalanan"), subtitle: tr("油费、停车费、过路费", "Fuel, parking and tolls", "Minyak, parkir dan tol"), symbol: "car.fill", color: .teal) }
                    NavigationLink { SplitHistoryView() } label: { Label(tr("全部分账记录", "All split entries", "Semua rekod pembahagian"), systemImage: "list.bullet.rectangle") }
                }
            }.listStyle(.insetGrouped).animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.92), value: settled).navigationTitle(tr("朋友分账", "Shared expenses", "Belanja dikongsi"))
                .toolbar { Button { adding = true } label: { Label(tr("新增代垫", "Add advance", "Tambah pendahuluan"), systemImage: "plus") } }
                .sheet(isPresented: $adding) { ExpenseEditor(original: nil, startWithSplit: true) }
        }
    }
}
struct FriendBalanceRow: View {
    let friend: FriendBalance
    var body: some View {
        HStack(spacing: 14) {
            Text(String(friend.name.prefix(1)).uppercased()).font(.headline)
                .frame(width: 44, height: 44).foregroundStyle(.teal)
                .background(Color.teal.opacity(0.12), in: Circle()).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(friend.name).font(.headline)
                Text(friend.owed == 0 && friend.payable == 0 ? tr("已结清", "Settled", "Selesai") : tr("待收：", "To collect: ", "Belum diterima: ") + money(friend.owed))
                    .font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
                if friend.payable > 0 { Text(tr("需退回：", "To return: ", "Perlu pulang: ") + money(friend.payable)).font(.caption).foregroundStyle(.orange) }
            }
        }.padding(.vertical, 8)
    }
}
struct SplitHistoryView: View {
    @EnvironmentObject var model: LedgerModel
    @State private var target: RepayTarget?
    @State private var editing: Expense?
    @State private var undo: (String, String, String, Bool)?
    @State private var settled = false
    var body: some View {
        List {
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
            }.navigationTitle(tr("分账记录", "Split history", "Sejarah pembahagian")).navigationBarTitleDisplayMode(.inline)
                .sheet(item: $editing) { ExpenseEditor(original: $0) }
                .sheet(item: $target) { RepaymentView(target: $0) }
                .confirmationDialog(tr("撤销还款？", "Undo repayment?", "Batalkan bayaran balik?"), isPresented: Binding(get: { undo != nil }, set: { if !$0 { undo = nil } }), titleVisibility: .visible) {
                    Button(tr("撤销", "Undo", "Batal"), role: .destructive) {
                        if let (ei, si, ri, isReturn) = undo { model.change { ledger in if let e = ledger.expenses.firstIndex(where: { $0.id == ei }), let s = ledger.expenses[e].shares.firstIndex(where: { $0.id == si }) { if isReturn { ledger.expenses[e].shares[s].returns?.removeAll { $0.id == ri } } else { ledger.expenses[e].shares[s].repayments.removeAll { $0.id == ri } } } } }; undo = nil
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
            }.navigationTitle(tr("记录还款", "Repayment", "Bayaran balik")).navigationBarTitleDisplayMode(.inline).presentationDragIndicator(.visible).presentationCornerRadius(28)
                .onAppear { amount = Currency.input(abs(target.share.owed), "MYR") }
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(tr("取消", "Cancel", "Batal")) { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button(tr("保存", "Save", "Simpan")) { do { let n = try toCents(amount); try LocalStore.shared.change { if target.share.owed < 0 { try $0.returnToFriend(expenseID: target.expense.id, shareID: target.share.id, cents: n, date: date) } else { try $0.repay(expenseID: target.expense.id, shareID: target.share.id, cents: n, date: date) } }; model.reload(); model.showSaved(); dismiss() } catch { self.error = error.localizedDescription } } } }
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
            List {
                Section {
                    NavigationLink { appearancePage } label: {
                        SimpleSettingsRow(title: tr("外观与语言", "Appearance & language", "Paparan & bahasa"), subtitle: tr("让月记更适合你", "Make YueJi feel like yours", "Sesuaikan YueJi untuk anda"), symbol: "circle.lefthalf.filled", color: .indigo)
                    }
                    NavigationLink { NotificationSettingsView() } label: {
                        SimpleSettingsRow(title: tr("提醒与通知", "Reminders & notifications", "Peringatan & notifikasi"), subtitle: tr("预算、每日记账", "Budget and daily reminders", "Bajet dan peringatan harian"), symbol: "bell.fill", color: .orange)
                    }
                } header: { Text(tr("个人偏好", "Personalize", "Peribadikan")) }
                Section {
                    NavigationLink { AutomationSetupView() } label: {
                        SimpleSettingsRow(title: tr("自动记账", "Automatic recording", "Rekod automatik"), subtitle: "Apple Pay · TNG", symbol: "bolt.fill", color: .teal)
                    }
                    NavigationLink { categoriesPage } label: {
                        SimpleSettingsRow(title: tr("分类与规则", "Categories & rules", "Kategori & peraturan"), subtitle: tr("整理每一笔消费", "Keep spending organized", "Susun setiap belanja"), symbol: "square.grid.2x2.fill", color: .blue)
                    }
                    NavigationLink { RatesView() } label: {
                        SimpleSettingsRow(title: tr("币种与汇率", "Currencies & rates", "Mata wang & kadar"), subtitle: tr("统计币种 MYR", "Totals in MYR", "Jumlah dalam MYR"), symbol: "globe", color: .green)
                    }
                } header: { Text(tr("记账设置", "Recording", "Rekod")) }
                Section {
                    NavigationLink { backupPage } label: {
                        SimpleSettingsRow(title: tr("备份与导出", "Backups & export", "Sandaran & eksport"), subtitle: tr("备份、恢复、导出账单", "Save, restore and export", "Simpan, pulih dan eksport"), symbol: "externaldrive.fill", color: .indigo)
                    }
                    NavigationLink { aboutPage } label: {
                        SimpleSettingsRow(title: tr("关于月记", "About YueJi", "Tentang YueJi"), subtitle: installedVersionLabel, symbol: "info.circle.fill", color: .gray)
                    }
                    NavigationLink { OverviewToolsView() } label: {
                        SimpleSettingsRow(title: tr("更多工具", "More tools", "Alat lain"), subtitle: tr("月度对比、消费预览与查重", "Comparisons, upcoming bills & duplicates", "Perbandingan, bil & pendua"), symbol: "square.grid.2x2.fill", color: .blue)
                    }
                    NavigationLink { UsageGuideView() } label: {
                        SimpleSettingsRow(title: tr("使用指南", "Getting started", "Panduan penggunaan"), subtitle: tr("记账、自动化与朋友还款", "Expenses, automation and repayments", "Belanja, automasi dan bayaran balik"), symbol: "book.fill", color: .green)
                    }
                } header: { Text(tr("数据与帮助", "Data & help", "Data & bantuan")) }
            }.listStyle(.insetGrouped).navigationTitle(tr("设置", "Settings", "Tetapan"))
                .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: "YueJi-\(monthKey(Date()))") { if case .failure(let e) = $0 { model.error = e.localizedDescription } }
                .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                    do { let url = try result.get(); let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }; let data = try Data(contentsOf: url); restorePreview = try RestorePreview(data: data) } catch { model.error = error.localizedDescription }
                }
                .sheet(item: $restorePreview) { preview in
                    RestorePreviewView(preview: preview) { loadBackups() }
                }
        }
    }
    private var appearancePage: some View {
        Form {
            Section {
                    Picker(tr("语言", "Language", "Bahasa"), selection: $language) {
                        Text(tr("跟随系统", "System default", "Ikut sistem")).tag("system")
                        Text("简体中文").tag("zh"); Text("English").tag("en"); Text("Bahasa Melayu").tag("ms")
                    }
                    Picker(tr("外观", "Appearance", "Paparan"), selection: $appearance) {
                        Text(tr("跟随系统", "System default", "Ikut sistem")).tag("system")
                        Text(tr("浅色模式", "Light mode", "Mod cerah")).tag("light")
                        Text(tr("深色模式", "Dark mode", "Mod gelap")).tag("dark")
                    }

            }
        }.navigationTitle(tr("外观与语言", "Appearance & language", "Paparan & bahasa"))
    }
    private var categoriesPage: some View {
        List {
            NavigationLink(tr("管理分类", "Manage categories", "Urus kategori")) { CategoriesView() }
            NavigationLink(tr("商户分类规则", "Merchant category rules", "Peraturan kategori peniaga")) { MerchantRulesView() }
        }.navigationTitle(tr("分类与规则", "Categories & rules", "Kategori & peraturan"))
    }
    private var backupPage: some View {
        Form {
                Section(tr("数据与备份", "Data & backups", "Data & sandaran")) {
                    Text(tr("每次修改前保留旧版，最多 30 份本地备份。卸载会删除本地数据，请定期导出到文件或 iCloud Drive。", "Keeps up to 30 local snapshots before changes. Uninstalling deletes local data. Export to Files or iCloud Drive regularly.", "Menyimpan sehingga 30 sandaran tempatan sebelum perubahan. Nyahpasang memadam data tempatan. Eksport ke Files atau iCloud Drive secara berkala.")).font(.footnote)
                    NavigationLink(tr("导出 Excel / CSV", "Export Excel / CSV", "Eksport Excel / CSV")) { CSVExportView() }
                    Button(tr("导出完整备份", "Export full backup", "Eksport sandaran penuh")) { do { document = LedgerDocument(data: try LocalStore.exportData(LocalStore.shared.read())); exporting = true } catch { model.error = error.localizedDescription } }
                    Button(tr("恢复 JSON 备份", "Restore JSON backup", "Pulihkan sandaran JSON")) { importing = true }
                    if FileManager.default.fileExists(atPath: LocalStore.shared.recoveryFile.path) {
                        Button(tr("恢复上次导入前的数据", "Recover data before last restore", "Pulihkan data sebelum pemulihan terakhir")) {
                            do { restorePreview = try RestorePreview(data: Data(contentsOf: LocalStore.shared.recoveryFile)) } catch { model.error = error.localizedDescription }
                        }
                    }
                    DisclosureGroup(tr("本机历史备份", "Local snapshot history", "Sejarah sandaran tempatan")) {
                    ForEach(backups, id: \.self) { url in Button { do { restorePreview = try RestorePreview(data: Data(contentsOf: url)) } catch { model.error = error.localizedDescription } } label: {
                        Text(tr("恢复：", "Restore: ", "Pulihkan: ") + backupTitle(url))
                    } }
                    }
                }

        }.navigationTitle(tr("备份与导出", "Backups & export", "Sandaran & eksport")).onAppear { loadBackups() }
    }
    private var aboutPage: some View {
        List {
            Text(installedVersionLabel)
            Text(tr("免费侧载签名每 7 天需要刷新；过期会影响 App 和自动记账。", "Free sideload signing needs renewal every 7 days. Expiry affects the app and automatic recording.", "Tandatangan sideload percuma perlu diperbaharui setiap 7 hari. Tamat tempoh menjejaskan aplikasi dan rekod automatik."))
        }.navigationTitle(tr("关于月记", "About YueJi", "Tentang YueJi"))
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
        }.navigationTitle(tr("Apple Pay 接入", "Apple Pay setup", "Persediaan Apple Pay")).navigationBarTitleDisplayMode(.inline)
    }
}

private var installedVersionLabel: String {
    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
    return "YueJi · \(version ?? "-") (\(build ?? "-"))"
}

struct CSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}


struct SimpleSettingsRow: View {
    let title: String
    let subtitle: String
    let symbol: String
    let color: Color
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).font(.body.weight(.medium))
                .foregroundStyle(.white).frame(width: 34, height: 34)
                .background(color.gradient, in: RoundedRectangle(cornerRadius: 8))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.body).foregroundStyle(.primary)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 6)
    }
}


struct AutomationSetupView: View {
    var body: some View {
        List {
            Section {
                NavigationLink { ShortcutHelpView() } label: {
                    SimpleSettingsRow(title: "Apple Pay", subtitle: tr("付款后记录消费", "Record after payment", "Rekod selepas bayaran"), symbol: "creditcard.fill", color: .blue)
                }
                NavigationLink { TNGInboxView() } label: {
                    SimpleSettingsRow(title: "TNG eWallet", subtitle: tr("通知接入与待确认", "Notification setup & review", "Persediaan notifikasi & semakan"), symbol: "bell.badge.fill", color: .teal)
                }
            } footer: { Text(tr("先在快捷指令完成设置，再用实际运行记录确认结果。", "Set up Shortcuts, then verify actual results in the log.", "Sediakan Pintasan, kemudian sahkan hasil sebenar dalam log.")) }
            Section {
                NavigationLink(tr("查看运行记录", "View activity log", "Lihat log aktiviti")) { AutomationStatusView() }
            }
        }.navigationTitle(tr("自动记账", "Automatic recording", "Rekod automatik")).navigationBarTitleDisplayMode(.inline)
    }
}
private struct YueJiPrimaryButton: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 26.0, *), !reduceTransparency {
            content.buttonStyle(.glass)
        } else { content.buttonStyle(.borderedProminent) }
    }
}
extension View {
    func yuejiPrimaryButton() -> some View { modifier(YueJiPrimaryButton()) }
}


private struct YueJiGlassSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ViewBuilder func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 26))
        } else if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 26))
        } else {
            content.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 26))
        }
    }
}


private struct YueJiZoomDestination: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let id: String
    let namespace: Namespace.ID
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 18.0, *), !reduceMotion {
            content.navigationTransition(.zoom(sourceID: id, in: namespace))
        } else { content }
    }
}
private struct YueJiZoomSource: ViewModifier {
    let id: String
    let namespace: Namespace.ID
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.matchedTransitionSource(id: id, in: namespace)
        } else { content }
    }
}
extension View {
    func yuejiZoom(id: String, namespace: Namespace.ID) -> some View {
        modifier(YueJiZoomDestination(id: id, namespace: namespace))
    }
    func yuejiZoomSource(id: String, namespace: Namespace.ID) -> some View {
        modifier(YueJiZoomSource(id: id, namespace: namespace))
    }
}


struct UsageGuideView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step = 0
    private var titles: [String] { [tr("记下自己的消费", "Track your spending", "Jejak belanja anda"), tr("连接自动记账", "Connect automatic recording", "Sambungkan rekod automatik"), tr("朋友分账与还款", "Split and settle", "Bahagi dan bayar balik"), tr("预算与备份", "Budget and back up", "Bajet dan sandaran"), tr("拍收据分账", "Scan and split", "Imbas dan bahagi"), tr("自动更新参考价格", "Automatic reference prices", "Harga rujukan automatik"), tr("本机 AI 助手", "On-device AI", "AI pada peranti")] }
    private var symbols: [String] { ["plus.circle.fill", "bolt.fill", "person.2.fill", "externaldrive.fill", "camera.fill", "arrow.triangle.2.circlepath", "sparkles"] }
    private var details: [String] { [
        tr("在概览点「记一笔」，填写金额、商户和日期。补记旧消费时先切换月份，保存前核对日期。", "Tap Add expense in Overview. Enter amount, merchant and date. For past spending, select the month and check the date before saving.", "Ketik Tambah belanja. Isi amaun, peniaga dan tarikh. Untuk belanja lalu, pilih bulan dan semak tarikh."),
        tr("从「自动记账」进入 Apple Pay 或 TNG 教程，在快捷指令完成设置。查看运行记录并核对账本，打开教程不代表已经接入。", "Open Automatic recording for Apple Pay or TNG instructions. Configure Shortcuts, then verify the activity log and ledger. Opening a guide does not enable recording.", "Buka Rekod automatik untuk panduan Apple Pay atau TNG. Sediakan Pintasan, kemudian semak log dan lejar."),
        tr("已有付款请到账本编辑并开启分账，避免重复记账。朋友可以分次还款：输入本次实际收到的金额。收款日期不能早于消费日期。", "Split an existing payment by editing it in Ledger to avoid duplicates. Friends can repay in parts: enter only what you received. Receipt date cannot precede the expense.", "Edit bayaran sedia ada dalam Lejar untuk membahagi tanpa pendua. Rakan boleh bayar sebahagian; isi amaun diterima sahaja. Tarikh penerimaan tidak boleh mendahului belanja."),
        tr("在概览设置预算，在提醒设置选择提醒比例。定期到「备份与导出」保存完整备份；卸载 App 会删除本机数据。", "Set a budget in Overview and an alert percentage in notification settings. Export full backups regularly; uninstalling removes local data.", "Tetapkan bajet dalam Ringkasan dan peratus peringatan dalam tetapan. Eksport sandaran penuh berkala; nyahpasang memadam data tempatan."),
        tr("在概览选择拍收据分账，拍照或选照片。核对小计、税费和总额，再选择朋友。付款已入账时关联原付款，避免重复。", "Open Scan and split in Overview. Take or choose a photo, review subtotal, charges and total, then select friends. Link an existing payment to avoid duplicates.", "Buka Imbas dan bahagi. Ambil atau pilih foto, semak subjumlah, caj dan jumlah, kemudian pilih rakan. Pautkan bayaran asal untuk mengelakkan pendua."),
        tr("选择外币时自动获取汇率；油费计算器自动获取所选油品的官方价格。会显示数据日期，断网时保留缓存。历史账目不会随汇率改变。", "Selecting a currency fetches its reference rate. The fuel calculator fetches official prices for your fuel type. Check the data date; offline caches remain. Existing entries keep their original rates.", "Memilih mata wang mengambil kadar rujukan. Kalkulator minyak mengambil harga rasmi. Semak tarikh data; cache kekal di luar talian. Kadar rekod lama tidak berubah."),
        tr("从概览打开 AI 消费助手，可询问预算建议，并选择每天在概览显示一条建议。需要设备支持并启用 Apple Intelligence；建议不会自动修改账目。", "Open the AI assistant from Overview for budget advice. Optionally show one daily suggestion in Overview. Requires enabled Apple Intelligence on a compatible device. Suggestions never edit records.", "Buka pembantu AI untuk cadangan bajet. Pilih cadangan harian dalam Ringkasan jika mahu. Memerlukan Apple Intelligence aktif pada peranti serasi. Cadangan tidak mengubah rekod.")
    ] }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Image(systemName: symbols[step]).font(.largeTitle).foregroundStyle(.blue).accessibilityHidden(true)
                    Text(titles[step]).font(.largeTitle.bold())
                    Text(details[step]).font(.body).foregroundStyle(.secondary)
                    ProgressView(value: Double(step + 1), total: Double(titles.count))
                    Text("\(step + 1) / \(titles.count)").font(.caption).foregroundStyle(.secondary)
                    if step > 0 { Button(tr("上一步", "Back", "Kembali")) { withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { step -= 1 } } }
                    Button(step == titles.count - 1 ? tr("开始使用", "Get started", "Mula") : tr("下一步", "Next", "Seterusnya")) {
                        if step == titles.count - 1 { dismiss() }
                        else { withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { step += 1 } }
                    }.yuejiPrimaryButton().controlSize(.large)
                }.padding(24)
            }.navigationTitle(tr("欢迎使用月记", "Welcome to YueJi", "Selamat datang ke YueJi")).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(tr("跳过", "Skip", "Langkau")) { dismiss() } } }
        }
    }
}
