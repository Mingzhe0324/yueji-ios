import SwiftUI
import UniformTypeIdentifiers
import UIKit
#if canImport(FoundationModels)
import FoundationModels
#endif

private let ink = Color(uiColor: .systemBlue)
struct GlassPanel<Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @ViewBuilder var content: Content
    var body: some View {
        content.padding(24).frame(maxWidth: .infinity, alignment: .leading)
            .ledgerGlass()
            .overlay(RoundedRectangle(cornerRadius: 26).strokeBorder(.primary.opacity(0.06)))
            .opacity(appeared || reduceMotion ? 1 : 0)
            .offset(y: appeared || reduceMotion ? 0 : 4)
            .onAppear { withAnimation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.94)) { appeared = true } }
    }
}
extension View {
    func ledgerGlass() -> some View { modifier(YueJiGlassSurface()) }

}
struct PageIntroduction: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("YUEJI").font(.caption.weight(.semibold)).tracking(3).foregroundStyle(.secondary)
            Text(title).font(.largeTitle.weight(.bold)).fixedSize(horizontal: false, vertical: true)
            Text(subtitle).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 10)
            .padding(.horizontal, 24)
    }
}
private struct YueJiListSurface: ViewModifier {
    func body(content: Content) -> some View {
        content.listStyle(.insetGrouped).listSectionSpacing(22)
            .scrollContentBackground(.hidden).background(Color(uiColor: .systemGroupedBackground))
    }
}
extension View {
    func yuejiListSurface() -> some View { modifier(YueJiListSurface()) }
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
                VStack(spacing: 24) {
                    PageIntroduction(title: tr("每一笔，心里有数", "A clearer everyday", "Belanja lebih jelas"), subtitle: tr("记录消费，轻松分账。", "Track spending. Share fairly.", "Jejak belanja. Kongsi dengan adil."))
                    MonthPicker(month: monthBinding)
                    spendingCard
                    balancesCard
                    categoriesCard
                    GlassPanel {
                        VStack(alignment: .leading, spacing: 16) {
                            Text(tr("日常工具", "Everyday tools", "Alat harian")).font(.headline)
                            NavigationLink { ReceiptScanView() } label: {
                                SimpleSettingsRow(title: tr("收据分账", "Receipt split", "Bahagi resit"), subtitle: tr("扫一张收据，按各自点的菜分", "Scan a receipt and split by dishes", "Imbas resit, bahagi ikut item"), symbol: "doc.viewfinder", color: .blue)
                            }
                            Divider()
                            NavigationLink { AutomationSetupView() } label: {
                                SimpleSettingsRow(title: tr("自动记账", "Automatic recording", "Rekod automatik"), subtitle: "Apple Pay · TNG", symbol: "bolt.fill", color: .teal)
                            }
                            Divider()
                            NavigationLink { LedgerInsightsView() } label: {
                                SimpleSettingsRow(title: tr("智能查账", "Smart ledger", "Lejar pintar"), subtitle: tr("问账本、看月度回顾", "Ask your ledger and review the month", "Tanya lejar dan semak bulan"), symbol: "sparkle.magnifyingglass", color: .indigo)
                            }
                        }.buttonStyle(.plain)
                    }
                    NavigationLink { OverviewToolsView(month: month) } label: {
                        Label(tr("更多工具", "More tools", "Alat lain"), systemImage: "square.grid.2x2")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }.yuejiPrimaryButton().buttonBorderShape(.capsule)
                }.padding(24).frame(maxWidth: 640).frame(maxWidth: .infinity)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(tr("概览", "Overview", "Ringkasan")).navigationBarTitleDisplayMode(.inline)
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
                    .foregroundStyle(.primary).minimumScaleFactor(0.5).lineLimit(1)
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
                let incoming = model.ledger.tngNotices.filter {
                    $0.kind == "incoming" && $0.status != "ignored" && (!$0.possibleDuplicate || $0.status != "pending") && monthKey($0.date) == monthKey(month)
                }.reduce(0) { $0 + ($1.cents ?? 0) }
                if incoming > 0 {
                    NavigationLink { TNGInboxView() } label: {
                        LabeledContent(tr("TNG 本月收到 · 单独记录", "TNG received this month · separate", "TNG diterima bulan ini · berasingan"), value: "+" + money(incoming))
                            .foregroundStyle(.green)
                    }.buttonStyle(.plain)
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
                Section { PageIntroduction(title: tr("账本", "Your ledger", "Lejar anda"), subtitle: tr("按月份整理，随时回看。", "Organized by month, ready to review.", "Disusun mengikut bulan, mudah disemak.")) }
                    .listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))

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
                .yuejiListSurface().navigationTitle(tr("账本", "Ledger", "Lejar")).navigationBarTitleDisplayMode(.inline).searchable(text: $search, prompt: tr("商户、分类", "Merchant, category", "Peniaga, kategori"))
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
// AI interprets only the user's question. All matching, arithmetic and the
// displayed evidence come from the saved ledger, never from generated text.
struct LedgerInsightQuery {
    let monthOffset: Int
    let category: String
    let merchant: String
    static func matching(_ expenses: [Expense], month: Date, query: LedgerInsightQuery) -> [Expense] {
        guard let date = Calendar.current.date(byAdding: .month, value: query.monthOffset, to: month) else { return [] }
        return expenses.filter { expense in
            monthKey(expense.date) == monthKey(date)
                && (query.category.isEmpty || expense.category == query.category)
                && (query.merchant.isEmpty || expense.merchant.localizedCaseInsensitiveContains(query.merchant))
        }.sorted { $0.date > $1.date }
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable
private struct LedgerQuestionFields {
    @Guide(description: "Months relative to the selected month: 0 for selected or this month, -1 for last month. Only -12 through 0.")
    var monthOffset: Int
    @Guide(description: "Exact category from the provided category list, or an empty string if not mentioned.")
    var category: String
    @Guide(description: "A merchant name mentioned in the question, or an empty string. Never invent a merchant.")
    var merchant: String
    @Guide(description: "True only if the user asks for spending in one month, optionally filtered by category or merchant.")
    var supported: Bool
}

@available(iOS 26.0, *)
@Generable
private struct MerchantAliasGroup {
    @Guide(description: "Two or more exact merchant names from the provided list that may refer to the same brand.")
    var names: [String]
}

@available(iOS 26.0, *)
@Generable
private struct MerchantAliasSuggestions {
    @Guide(description: "Only clear possible brand name variations; omit uncertain or unrelated merchants.")
    var groups: [MerchantAliasGroup]
}

@available(iOS 26.0, *)
private enum LedgerQuestionAI {
    static func parse(_ question: String, categories: [String]) async -> LedgerInsightQuery? {
        guard SystemLanguageModel.default.availability == .available else { return nil }
        let session = LanguageModelSession(instructions: "Extract filters from a question about a person's recorded spending. Do not answer or calculate a number. Months are relative to the user's selected month. Use only a listed category. Do not infer a merchant unless the name appears in the question. If ambiguous or about debt, income, transfers or multiple months, set supported to false.")
        do {
            let response = try await session.respond(to: "Categories: \(categories.joined(separator: ", "))\nQuestion: \(question)", generating: LedgerQuestionFields.self)
            let fields = response.content
            let merchant = fields.merchant.trimmingCharacters(in: .whitespacesAndNewlines)
            guard fields.supported, (-12...0).contains(fields.monthOffset),
                  fields.category.isEmpty || categories.contains(fields.category),
                  merchant.isEmpty || question.localizedCaseInsensitiveContains(merchant) else { return nil }
            return LedgerInsightQuery(monthOffset: fields.monthOffset, category: fields.category, merchant: merchant)
        } catch { return nil }
    }
    static func aliases(_ names: [String]) async -> [[String]]? {
        guard SystemLanguageModel.default.availability == .available, names.count >= 2, names.count <= 80 else { return nil }
        let session = LanguageModelSession(instructions: "Suggest merchant names that may be variants of the same brand. Use only exact names from the input list. Do not assume separate merchants are identical. Never change or combine ledger entries.")
        do {
            let response = try await session.respond(to: "Merchant names:\n" + names.joined(separator: "\n"), generating: MerchantAliasSuggestions.self)
            let allowed = Set(names)
            return Array(response.content.groups.prefix(8)).compactMap { suggestion in
                let group = Array(Set(suggestion.names)).sorted()
                return group.count >= 2 && group.allSatisfy({ allowed.contains($0) }) ? group : nil
            }
        } catch { return nil }
    }
}
#endif

struct LedgerInsightsView: View {
    @EnvironmentObject private var model: LedgerModel
    @State private var month = Date()
    @State private var question = ""
    @State private var matches: [Expense] = []
    @State private var answered = false
    @State private var resultMonth = Date()
    @State private var working = false
    @State private var message = ""
    @State private var editing: Expense?
    @State private var aliasGroups: [[String]] = []
    @State private var lookingForAliases = false
    @State private var aliasMessage = ""

    private var current: [Expense] { model.ledger.expenses.filter { monthKey($0.date) == monthKey(month) } }
    private var previous: [Expense] {
        guard let date = Calendar.current.date(byAdding: .month, value: -1, to: month) else { return [] }
        return model.ledger.expenses.filter { monthKey($0.date) == monthKey(date) }
    }
    private var categoryTotals: [(String, Int)] {
        Dictionary(grouping: current, by: \.category)
            .map { ($0.key, $0.value.reduce(0) { $0 + $1.personal }) }
            .filter { $0.1 > 0 }.sorted { $0.1 > $1.1 }
    }
    private var monthTitle: String { month.formatted(.dateTime.year().month(.wide).locale(Locale(identifier: AppLanguage.localeID))) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageIntroduction(title: tr("智能查账", "Smart ledger", "Lejar pintar"), subtitle: tr("问一句，核对每一笔。", "Ask a question. Check each entry.", "Tanya soalan. Semak setiap rekod."))
                    .padding(.horizontal, -24)
                MonthPicker(month: $month)
                GlassPanel {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(tr("月度回顾", "Monthly review", "Ringkasan bulanan")).font(.headline)
                        let total = current.reduce(0) { $0 + $1.personal }
                        Text(monthTitle + " · " + money(total)).font(.title2.weight(.semibold))
                        Text(tr("我的消费 · ", "My spending · ", "Belanja saya · ") + String(current.count) + tr(" 笔", " entries", " rekod"))
                            .font(.subheadline).foregroundStyle(.secondary)
                        if let top = categoryTotals.first {
                            Text(tr("最多：", "Largest category: ", "Kategori terbesar: ") + top.0 + " · " + money(top.1))
                                .font(.subheadline)
                        }
                        let prior = previous.reduce(0) { $0 + $1.personal }
                        if !current.isEmpty || !previous.isEmpty {
                            Text(tr("上个月：", "Previous month: ", "Bulan lalu: ") + money(prior))
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        Text(tr("依据账本计算；不包含朋友承担的份额。", "Calculated from your ledger; excludes friends’ shares.", "Dikira daripada lejar; tidak termasuk bahagian rakan."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                GlassPanel {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(tr("相似商家", "Similar merchants", "Peniaga serupa")).font(.headline)
                        Text(tr("检查最近 80 个商家名称；账目不会被合并。", "Checks 80 recent merchant names; entries stay separate.", "Semak 80 nama peniaga terkini; rekod kekal berasingan."))
                            .font(.caption).foregroundStyle(.secondary)
                        Button(tr("查找相似名称", "Find similar names", "Cari nama serupa")) {
                            Task { await findAliases() }
                        }.disabled(lookingForAliases).buttonStyle(.bordered)
                        if lookingForAliases { ProgressView() }
                        if !aliasMessage.isEmpty { Text(aliasMessage).font(.caption).foregroundStyle(.secondary) }
                        ForEach(aliasGroups.indices, id: \.self) { index in
                            Text(aliasGroups[index].joined(separator: " · ")).font(.subheadline)
                        }
                    }
                }
                GlassPanel {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(tr("问账本", "Ask your ledger", "Tanya lejar")).font(.headline)
                        TextField(tr("例如：上个月餐饮花了多少？", "E.g. How much did I spend on food last month?", "Contoh: Berapa saya belanja makan bulan lalu?"), text: $question)
                            .textFieldStyle(.roundedBorder).submitLabel(.search).onSubmit { Task { await ask() } }
                        Button {
                            Task { await ask() }
                        } label: {
                            if working { ProgressView() }
                            else { Label(tr("查找记录", "Find entries", "Cari rekod"), systemImage: "sparkle.magnifyingglass") }
                        }
                        .disabled(working || question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .buttonStyle(.borderedProminent)
                        Text(tr("只查询单个月份的消费；AI 不修改账本。", "Ask about spending in one month; AI never edits your ledger.", "Tanya belanja untuk satu bulan; AI tidak mengubah lejar."))
                            .font(.caption).foregroundStyle(.secondary)
                        if !message.isEmpty { Text(message).font(.subheadline).foregroundStyle(.secondary) }
                    }
                }
                if answered {
                    GlassPanel {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(tr("查账结果", "Ledger result", "Hasil carian")).font(.headline)
                            Text(money(matches.reduce(0) { $0 + $1.personal })).font(.title2.weight(.bold))
                            Text(resultMonth.formatted(.dateTime.year().month(.wide).locale(Locale(identifier: AppLanguage.localeID))) + " · " + String(matches.count) + tr(" 笔 · 我的消费", " entries · my spending", " rekod · belanja saya"))
                                .font(.caption).foregroundStyle(.secondary)
                            ForEach(matches) { entry in
                                Divider()
                                Button { editing = entry } label: {
                                    HStack {
                                        VStack(alignment: .leading) {
                                            Text(entry.merchant).foregroundStyle(.primary)
                                            Text(entry.date.formatted(date: .abbreviated, time: .omitted) + " · " + entry.category)
                                                .font(.caption).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Text(money(entry.personal)).foregroundStyle(.primary).monospacedDigit()
                                    }
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                }
            }.padding(24).frame(maxWidth: 640).frame(maxWidth: .infinity)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(tr("智能查账", "Smart ledger", "Lejar pintar"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { ExpenseEditor(original: $0) }
        .onChange(of: month) { _, _ in answered = false; message = "" }
    }

    private func findAliases() async {
        var seen = Set<String>()
        let names = Array(model.ledger.expenses.sorted { $0.date > $1.date }
            .map(\.merchant).filter { seen.insert($0).inserted }.prefix(80))
        lookingForAliases = true
        aliasGroups = []
        aliasMessage = ""
        defer { lookingForAliases = false }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *),
           let groups = await LedgerQuestionAI.aliases(names) {
            aliasGroups = groups
            aliasMessage = groups.isEmpty ? tr("没有找到明显相似的名称。", "No clear similar names found.", "Tiada nama serupa yang jelas.") : ""
            return
        }
        #endif
        aliasMessage = tr("设备端 AI 暂不可用，或商家名称不足两种。", "On-device AI is unavailable or fewer than two merchant names exist.", "AI pada peranti tidak tersedia atau kurang daripada dua nama peniaga.")
    }

    private func ask() async {
        let prompt = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, prompt.count <= 180 else { return }
        working = true
        answered = false
        message = ""
        defer { working = false }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let categories = model.ledger.categoryNames
            if let query = await LedgerQuestionAI.parse(prompt, categories: categories) {
                matches = LedgerInsightQuery.matching(model.ledger.expenses, month: month, query: query)
                resultMonth = Calendar.current.date(byAdding: .month, value: query.monthOffset, to: month) ?? month
                answered = true
                return
            }
        }
        #endif
        message = tr("设备端 AI 不可用，或这个问题暂时无法准确查找。可在账本按月份、商家及分类筛选。", "On-device AI is unavailable or this question cannot be searched reliably. Filter by month, merchant and category in Ledger.", "AI pada peranti tidak tersedia atau soalan ini belum dapat dicari dengan tepat. Tapis mengikut bulan, peniaga dan kategori dalam Lejar.")
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
                Section { PageIntroduction(title: tr("一起吃，各自分", "Shared, fairly", "Kongsi dengan adil"), subtitle: tr("谁应付多少，一目了然。", "See who owes what at a glance.", "Lihat bahagian setiap orang dengan jelas.")) }
                    .listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))

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
            }.listStyle(.insetGrouped).animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.92), value: settled).yuejiListSurface().navigationTitle(tr("朋友分账", "Shared expenses", "Belanja dikongsi")).navigationBarTitleDisplayMode(.inline)
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
                Section { PageIntroduction(title: tr("让月记更适合你", "Make it yours", "Sesuaikan YueJi"), subtitle: tr("外观、提醒与备份，都在这里。", "Appearance, reminders and backups in one place.", "Paparan, peringatan dan sandaran di sini.")) }
                    .listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))

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
            }.yuejiListSurface().navigationTitle(tr("设置", "Settings", "Tetapan")).navigationBarTitleDisplayMode(.inline)
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
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var step = 0
    private var titles: [String] { [
        tr("记下今天的一笔", "Your first expense", "Belanja pertama anda"),
        tr("让收据变得清楚", "A receipt, made clear", "Resit yang lebih jelas"),
        tr("各点各的，也好分", "Different dishes. Easy splits.", "Item berbeza, mudah dibahagi"),
        tr("还了多少，记多少", "Record what comes back", "Rekod amaun dibayar balik"),
        tr("少一点手动输入", "A little less typing", "Kurangkan menaip"),
        tr("照顾预算，也留备份", "Plan and keep a copy", "Rancang dan simpan salinan")
    ] }
    private var details: [String] { [
        tr("概览 → 记一笔。填金额、商家与日期，再保存。", "Overview → Add expense. Enter the amount, merchant and date, then save.", "Ringkasan → Tambah belanja. Isi amaun, peniaga dan tarikh, kemudian simpan."),
        tr("概览 → 拍收据分账。选择照片后，对照收据核对日期、商品和实付总额。", "Overview → Scan and split. Choose a photo, then check the date, items and paid total.", "Ringkasan → Imbas dan bahagi. Pilih foto, kemudian semak tarikh, item dan jumlah akhir."),
        tr("添加朋友，再为每道菜选择谁吃。共享的菜可选多人；税费会随餐费分摊。", "Add friends and choose who had each dish. Shared dishes can have several people; charges follow their food shares.", "Tambah rakan dan pilih pemakan setiap item. Item boleh dikongsi; caj mengikut bahagian makanan."),
        tr("分账 → 选择朋友 → 记录还款。只填本次实际收到的金额，余款会保留。", "Friends → Choose a friend → Record repayment. Enter only what you received; the balance stays outstanding.", "Rakan → Pilih rakan → Rekod bayaran balik. Isi amaun diterima sahaja; baki masih belum dibayar."),
        tr("概览 → 自动记账。选择 Apple Pay 或 TNG，按教程设置快捷指令，再检查运行记录。", "Overview → Automatic recording. Choose Apple Pay or TNG, configure Shortcuts using the guide, then check the activity log.", "Ringkasan → Rekod automatik. Pilih Apple Pay atau TNG, sediakan Pintasan mengikut panduan, kemudian semak log."),
        tr("在概览设置预算。到设置 → 备份与导出保存完整备份，换机时可恢复。", "Set a budget in Overview. Save a full backup in Settings → Backup & export so you can restore it later.", "Tetapkan bajet dalam Ringkasan. Simpan sandaran penuh di Tetapan → Sandaran & eksport untuk dipulihkan kemudian.")
    ] }
    private var motion: Animation? { reduceMotion ? nil : .spring(response: 0.48, dampingFraction: 0.94) }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    HStack {
                        Text("YUEJI").font(.caption.weight(.semibold)).tracking(3)
                        Spacer()
                        Text(String(format: "%02d / %02d", step + 1, titles.count)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }.padding(.top, 8)
                    VStack(spacing: 0) {
                        Capsule().fill(.primary).frame(width: 75, height: 15).padding(.top, 9).padding(.bottom, 8)
                        HStack {
                            Text("9:41").font(.caption.weight(.semibold))
                            Spacer()
                            Image(systemName: "wifi")
                            Image(systemName: "battery.100percent")
                        }.font(.caption2).padding(.horizontal, 24).padding(.bottom, 12)
                        Text([tr("概览", "Overview", "Ringkasan"), tr("收据分账", "Receipt split", "Bahagi resit"), tr("收据分账", "Receipt split", "Bahagi resit"), tr("朋友分账", "Shared expenses", "Belanja dikongsi"), tr("自动记账", "Automatic recording", "Rekod automatik"), tr("概览", "Overview", "Ringkasan")][step])
                            .font(.subheadline.weight(.semibold)).padding(.bottom, 10)
                        ScrollView {
                            GuideDemoScene(step: step).id(step)
                                .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 10)))
                                .padding(12)
                        }.frame(height: 360)
                            .background(Color(uiColor: .systemGroupedBackground))
                        Capsule().fill(.primary).frame(width: 100, height: 4).padding(.vertical, 10)
                    }
                    .frame(maxWidth: 350)
                    .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 39))
                    .overlay(RoundedRectangle(cornerRadius: 39).strokeBorder(.primary.opacity(0.18), lineWidth: 3))
                    .shadow(color: .black.opacity(0.1), radius: 24, y: 12)
                    .accessibilityLabel(tr("自动播放的应用操作演示", "Automatic app walkthrough", "Demonstrasi aplikasi automatik"))
                    VStack(alignment: .leading, spacing: 10) {
                        Text(titles[step]).font(.title.weight(.bold)).fixedSize(horizontal: false, vertical: true)
                        Text(details[step]).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        Text(tr("正在自动演示操作步骤", "Playing the steps automatically", "Langkah dimainkan secara automatik"))
                            .font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 6) {
                        ForEach(titles.indices, id: \.self) { index in
                            Circle().fill(index == step ? Color.primary : Color.secondary.opacity(0.3))
                                .frame(width: 7, height: 7)
                        }
                    }.accessibilityElement(children: .ignore).accessibilityLabel("\(step + 1) / \(titles.count)")
                }.padding(24).frame(maxWidth: 480)
                    .frame(maxWidth: .infinity)
            }.background(Color(uiColor: .systemGroupedBackground))
                .safeAreaInset(edge: .bottom) {
                    HStack(spacing: 14) {
                        Button {
                            dismiss()
                        } label: {
                            HStack {
                                Text(step == titles.count - 1 ? tr("开始使用月记", "Start using YueJi", "Mula menggunakan YueJi") : tr("结束指南", "Close guide", "Tutup panduan"))
                                Spacer()
                                Image(systemName: "arrow.right")
                            }.font(.body.weight(.semibold)).padding(.vertical, 10).padding(.horizontal, 8).frame(maxWidth: .infinity)
                        }.yuejiPrimaryButton().controlSize(.large).buttonBorderShape(.capsule)
                    }.padding(.horizontal, 24).padding(.vertical, 12).background {
                        if reduceTransparency { Color(uiColor: .systemGroupedBackground) }
                        else { Rectangle().fill(.regularMaterial) }
                    }
                }
                .navigationTitle(tr("认识月记", "Meet YueJi", "Kenali YueJi")).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(tr("跳过", "Skip", "Langkau")) { dismiss() } } }
                .task(id: step) {
                    guard step < titles.count - 1 else { return }
                    try? await Task.sleep(for: .seconds(reduceMotion ? 5 : 8))
                    guard !Task.isCancelled else { return }
                    withAnimation(motion) { step += 1 }
                }
        }
    }
}

private struct GuideDemoScene: View {
    let step: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var stage = 0
    @State private var appeared = false
    private var firstOwner: Int { stage == 0 ? 0 : 2 }
    private var secondOwner: Int { 1 }
    private var budget: Double { stage == 0 ? 800 : 1000 }
    private var provider: String { stage == 0 ? "Apple Pay" : "TNG" }
    private var animation: Animation? { reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.92) }
    private var foodShares: [Int] {
        var me = 0
        for (value, owner) in [(1500, firstOwner), (2500, secondOwner)] {
            me += owner == 0 ? value : (owner == 2 ? value / 2 : 0)
        }
        return [me, 4000 - me]
    }
    private var totals: [Int] { (try? ReceiptSplit.allocate(4720, weights: foodShares)) ?? [0, 0] }
    private func line(_ name: String, _ amount: String, symbol: String = "") -> some View {
        HStack(spacing: 10) {
            if !symbol.isEmpty { Image(systemName: symbol).foregroundStyle(Color.accentColor).frame(width: 24) }
            Text(name).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 12)
            Text(amount).monospacedDigit().fontWeight(.medium)
        }.font(.subheadline).padding(.vertical, 7)
    }
    private func action(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol).font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(Color.accentColor, in: Capsule()).foregroundStyle(.white)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label(tr("操作演示", "App walkthrough", "Demonstrasi aplikasi"), systemImage: "play.rectangle")
                .font(.caption.weight(.medium)).foregroundStyle(.secondary)
            Group {
                switch step {
                case 0: expenseDemo
                case 1: receiptDemo
                case 2: splitDemo
                case 3: repaymentDemo
                case 4: automationDemo
                default: budgetDemo
                }
            }
            Text(tr("示例数据 · 不会改动你的账本", "Sample data · Your ledger stays unchanged", "Data contoh · Lejar anda tidak berubah"))
                .font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity)
        }.padding(22).ledgerGlass()
            .overlay(RoundedRectangle(cornerRadius: 26).strokeBorder(Color.primary.opacity(0.05)))
            .opacity(appeared || reduceMotion ? 1 : 0).offset(y: appeared || reduceMotion ? 0 : 6)
            .onAppear { withAnimation(animation) { appeared = true } }
            .task {
                for next in 1...2 {
                    try? await Task.sleep(for: .seconds(reduceMotion ? 1.2 : 2.4))
                    guard !Task.isCancelled else { return }
                    withAnimation(animation) { stage = next }
                }
            }
    }
    private var expenseDemo: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(tr("概览", "Overview", "Ringkasan"), systemImage: "chart.pie.fill").font(.headline)
            if stage == 0 {
                Text(tr("本月消费", "This month", "Bulan ini")).font(.caption).foregroundStyle(.secondary)
                Text("RM 420.00").font(.largeTitle.weight(.semibold)).monospacedDigit()
                action(tr("记一笔", "Add expense", "Tambah belanja"), symbol: "plus")
            } else if stage == 1 {
                line(tr("金额", "Amount", "Amaun"), "RM 18.00")
                line(tr("商家", "Merchant", "Peniaga"), tr("午餐小馆", "Lunch cafe", "Kafe makan tengah hari"))
                line(tr("日期", "Date", "Tarikh"), tr("今天", "Today", "Hari ini"))
                action(tr("保存", "Save", "Simpan"), symbol: "checkmark")
            } else {
                Label(tr("示例已保存", "Sample saved", "Contoh disimpan"), systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                Text("RM 438.00").font(.largeTitle.weight(.semibold)).monospacedDigit()
                line(tr("午餐小馆", "Lunch cafe", "Kafe makan tengah hari"), "RM 18.00", symbol: "fork.knife")
                Text(tr("金额会计入所选日期的月份。", "The expense belongs to the month of its selected date.", "Belanja dikira dalam bulan tarikh yang dipilih.")).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private var receiptDemo: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(tr("收据分账", "Receipt split", "Bahagi resit"), systemImage: "doc.viewfinder").font(.headline)
            VStack(spacing: 5) {
                Text("LUNCH CAFE").font(.caption.weight(.bold)).tracking(2)
                Divider().padding(.vertical, 8)
                HStack { Text("Description"); Spacer(); Text("Amount") }.font(.caption.weight(.semibold)).foregroundStyle(stage > 0 ? Color.accentColor : .secondary)
                line("Chicken rice", "25.00")
                line("Noodles", "15.00")
                Divider()
                line("Total (RM)", "47.20")
            }.padding(16).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(stage > 0 ? Color.accentColor.opacity(0.6) : .clear, lineWidth: 1))
            if stage == 0 { action(tr("扫描收据", "Scan receipt", "Imbas resit"), symbol: "viewfinder") }
            else {
                line(tr("商品小计", "Items subtotal", "Subjumlah item"), "RM 40.00")
                line(tr("税费与服务费", "Tax & service", "Cukai & caj"), "RM 7.20")
                Text(tr("逐项核对：商品取 Description，行金额取 Amount。看不清的内容需手动补充。", "Check each item: Description gives the name, Amount gives the line total. Fill unclear values manually.", "Semak setiap item: Description ialah nama, Amount ialah jumlah item. Isi nilai kabur secara manual.")).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private func dish(_ name: String, amount: String, owner: Int) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            line(name, amount)
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { choice in
                    Text([tr("我", "Me", "Saya"), tr("朋友", "Friend", "Rakan"), tr("共享", "Shared", "Kongsi")][choice])
                        .font(.caption).frame(maxWidth: .infinity).padding(.vertical, 8)
                        .background(choice == owner ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }
    private var splitDemo: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(tr("按各自点的菜", "Split by items", "Bahagi ikut item"), systemImage: "person.2.fill").font(.headline)
            dish(tr("面条", "Noodles", "Mi"), amount: "RM 15.00", owner: firstOwner)
            dish(tr("鸡饭", "Chicken rice", "Nasi ayam"), amount: "RM 25.00", owner: secondOwner)
            Divider()
            VStack(spacing: 2) {
                line(tr("我应付", "I pay", "Saya bayar"), money(totals[0]))
                line(tr("朋友应付", "Friend pays", "Rakan bayar"), money(totals[1]))
            }.contentTransition(.numericText()).animation(animation, value: firstOwner).animation(animation, value: secondOwner)
            Text(tr("已含按餐费分摊的 RM 7.20 税费和服务费。", "Includes RM 7.20 in charges, shared by food cost.", "Termasuk caj RM 7.20 mengikut bahagian makanan.")).font(.caption).foregroundStyle(.secondary)
        }
    }
    private var repaymentDemo: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(tr("朋友明细", "Friend details", "Butiran rakan"), systemImage: "person.crop.circle").font(.headline)
            Text(tr("尚欠", "Outstanding", "Belum dibayar")).font(.caption).foregroundStyle(.secondary)
            Text(stage == 0 ? "RM 29.50" : "RM 19.50").font(.largeTitle.weight(.semibold)).monospacedDigit().contentTransition(.numericText())
            line(tr("本次收到", "Received this time", "Diterima kali ini"), "RM 10.00")
            if stage == 0 { action(tr("记录还款", "Record repayment", "Rekod bayaran"), symbol: "arrow.down.circle") }
            else { Label(tr("示例：还款已扣除，余款保留", "Demo: repayment applied, balance remains", "Demo: bayaran ditolak, baki kekal"), systemImage: "checkmark.circle.fill").font(.subheadline).foregroundStyle(.green) }
        }
    }
    private var automationDemo: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(tr("自动记账", "Automatic recording", "Rekod automatik"), systemImage: "bolt.fill").font(.headline)
            line(tr("付款方式", "Payment method", "Kaedah bayaran"), provider)
            line(tr("打开对应教程", "Open its setup guide", "Buka panduan persediaan"), provider, symbol: "1.circle")
            line(tr("设置快捷指令", "Configure Shortcuts", "Sediakan Pintasan"), "", symbol: "2.circle")
            line(tr("检查运行记录", "Check activity log", "Semak log aktiviti"), "", symbol: "3.circle")
            action(tr("查看设置说明", "View setup instructions", "Lihat panduan persediaan"), symbol: "book")
            if stage > 0 { Text(tr("首次设置后，用一笔真实付款核对日志和账本。此演示不会开启自动记账。", "After setup, verify a real payment in the log and ledger. This demo does not enable recording.", "Selepas persediaan, sahkan bayaran sebenar dalam log dan lejar. Demo ini tidak mengaktifkan rekod.")).font(.caption).foregroundStyle(.secondary) }
        }
    }
    private var budgetDemo: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(tr("本月预算", "Monthly budget", "Bajet bulanan"), systemImage: "chart.bar.fill").font(.headline)
            Text(money(Int(budget) * 100)).font(.largeTitle.weight(.semibold)).monospacedDigit().contentTransition(.numericText())
            ProgressView(value: budget, total: 2000).accessibilityLabel(tr("示例预算", "Sample budget", "Bajet contoh"))
            ProgressView(value: 420, total: budget).tint(.accentColor)
            line(tr("已用", "Spent", "Digunakan"), "RM 420.00")
            Divider()
            action(tr("备份与导出", "Backup & export", "Sandaran & eksport"), symbol: "externaldrive")
            if stage > 0 { Text(tr("设置 → 备份与导出 → 导出完整备份，保存到“文件”。此处仅演示，不会创建备份。", "Settings → Backup & export → Full backup, then save to Files. This demo does not create a backup.", "Tetapan → Sandaran & eksport → Sandaran penuh, kemudian simpan ke Files. Demo ini tidak mencipta sandaran.")).font(.caption).foregroundStyle(.secondary) }
        }
    }
}
