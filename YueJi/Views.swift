import SwiftUI
import UniformTypeIdentifiers
import UIKit

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
    var guideFocus: String? = nil
    @Namespace private var navigationMotion
    @EnvironmentObject var model: LedgerModel
    @SceneStorage("overviewMonth") private var monthTimestamp = Date().timeIntervalSince1970
    @State private var adding = false
    @State private var budgetText = ""
    @State private var budgeting = false
    private var month: Date { model.isPreview ? Date() : Date(timeIntervalSince1970: monthTimestamp) }
    private var monthBinding: Binding<Date> { Binding(get: { month }, set: { monthTimestamp = $0.timeIntervalSince1970 }) }
    private var entries: [Expense] { model.ledger.expenses.filter { monthKey($0.date) == monthKey(month) } }
    private var personal: Int { entries.reduce(0) { $0 + $1.personal } }
    private var budget: Int { model.ledger.budgets[monthKey(month)] ?? 0 }
    private var owed: Int { model.ledger.expenses.flatMap(\.shares).reduce(0) { $0 + max(0, $1.owed) } }
    var body: some View {
        NavigationStack {
            ScrollViewReader { guideScroll in
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
                            }.guideTarget("dashboard.receipt").id("dashboard.receipt")
                            Divider()
                            NavigationLink { AutomationSetupView() } label: {
                                SimpleSettingsRow(title: tr("自动记账", "Automatic recording", "Rekod automatik"), subtitle: "Apple Pay · TNG", symbol: "bolt.fill", color: .teal)
                            }

                        }.buttonStyle(.plain)
                    }
                    NavigationLink { OverviewToolsView(month: month) } label: {
                        Label(tr("更多工具", "More tools", "Alat lain"), systemImage: "square.grid.2x2")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }.yuejiPrimaryButton().buttonBorderShape(.capsule)
                }.padding(24).frame(maxWidth: 640).frame(maxWidth: .infinity)
            }
            .task(id: guideFocus) {
                guard model.isPreview, let guideFocus else { return }
                do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
                withAnimation(.easeInOut(duration: 0.85)) { guideScroll.scrollTo(guideFocus, anchor: .center) }
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
                .guideTarget("dashboard.add")
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
        get { model.isPreview ? Date() : Date(timeIntervalSince1970: monthTimestamp) }
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
                                .buttonStyle(.borderless).font(.subheadline).guideTarget("ledger.filter")
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
                                .guideTarget(entry.id == "guide-lunch" ? "ledger.expense" : "ledger.other")
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
                    Toggle(tr("朋友分账", "Split with friends", "Bahagi dengan rakan"), isOn: $splitting).guideTarget("expense.split")
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
                    guard !model.isPreview else { return }
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
                            .guideTarget(friend.id == "amy" ? "friends.person" : "friends.other")
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
    var guideDestination: String? = nil
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
            if guideDestination == "appearance" { appearancePage }
            else if guideDestination == "categories" { categoriesPage }
            else if guideDestination == "backup" { backupPage }
            else if guideDestination == "about" { aboutPage }
            else {
            List {
                Section { PageIntroduction(title: tr("让月记更适合你", "Make it yours", "Sesuaikan YueJi"), subtitle: tr("外观、提醒与备份，都在这里。", "Appearance, reminders and backups in one place.", "Paparan, peringatan dan sandaran di sini.")) }
                    .listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))

                Section {
                    NavigationLink { appearancePage } label: {
                        SimpleSettingsRow(title: tr("外观与语言", "Appearance & language", "Paparan & bahasa"), subtitle: tr("让月记更适合你", "Make YueJi feel like yours", "Sesuaikan YueJi untuk anda"), symbol: "circle.lefthalf.filled", color: .indigo)
                    }.guideTarget("settings.appearance")
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
                    }.guideTarget("settings.backup")
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
    private func loadBackups() { guard !model.isPreview else { return }; do { backups = try LocalStore.shared.backups() } catch { model.error = error.localizedDescription } }
    private func backupTitle(_ url: URL) -> String { guard let s = url.lastPathComponent.split(separator: "-").first, let ms = Double(s) else { return url.lastPathComponent }; return dateLabel(Date(timeIntervalSince1970: ms / 1000), time: true) }
}
struct ShortcutHelpView: View {
    var previewStep: Int? = nil
    var body: some View { ShortcutSetupGuide(provider: .applePay, previewStep: previewStep) }
}

enum ShortcutSetupProvider: Equatable { case applePay, tng }

struct ShortcutSetupGuide: View {
    let provider: ShortcutSetupProvider
    var previewStep: Int? = nil
    @EnvironmentObject private var model: LedgerModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @StateObject private var demo = LedgerModel(previewLedger: GuideSample.ledger())
    @State private var step = 0
    @State private var gesturePhase = 0
    @State private var gestureStep = 0
    private var modern: Bool { ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27 }
    private var title: String { provider == .applePay ? tr("Apple Pay 设置演示", "Apple Pay walkthrough", "Panduan Apple Pay") : tr("TNG 设置演示", "TNG walkthrough", "Panduan TNG") }
    private var actionName: String { provider == .applePay ? tr("记录 Apple Pay 支出", "Record Apple Pay expense", "Rekod belanja Apple Pay") : tr("记录 TNG 通知", "Record TNG notification", "Rekod notifikasi TNG") }
    private var headings: [String] { [tr("添加月记动作", "Add YueJi's action", "Tambah tindakan YueJi"), tr("选择触发方式", "Choose the trigger", "Pilih pencetus"), tr("接好交易资料", "Connect the fields", "Sambungkan medan"), tr("允许自动运行", "Allow automatic runs", "Benarkan jalan automatik"), tr("回月记核对", "Check in YueJi", "Semak dalam YueJi")] }
    private var selection: Binding<Int> { Binding(get: { step }, set: { step = $0 }) }
    private var unavailable: Bool { provider == .tng && !modern }
    private var chapter: GuideChapter? { GuideChapter.all.first { $0.id == (provider == .applePay ? "applePay" : "tng") } }
    private func action(for page: Int) -> GuideGesture? {
        guard let chapter else { return nil }
        return GuideGesture.actions(chapter: chapter, stage: page + 1).dropFirst(gestureStep).first
    }
    var body: some View {
        Group {
            if let previewStep {
                ScrollView { slide(previewStep).padding(24) }
            } else if unavailable {
                ContentUnavailableView(tr("需要通知触发器", "Notification trigger required", "Pencetus notifikasi diperlukan"), systemImage: "bell.badge", description: Text(tr("此演示使用 iOS 27 的通知自动化。当前系统没有这个入口时，可继续手动记账。", "This walkthrough uses iOS 27 notification automations. If your system does not have this trigger, use manual recording.", "Panduan ini menggunakan automasi notifikasi iOS 27. Jika pencetus tiada, guna rekod manual.")))
            } else {
                GeometryReader { geometry in
                    TabView(selection: selection) {
                        ForEach(0..<5) { index in
                            ScrollView {
                                VStack(spacing: 18) {
                                    GuideScreenFrame(screen: provider == .applePay ? .applePay(index) : .tngSetup(index), action: index == step ? action(for: index) : nil, gesturePhase: index == step ? gesturePhase : 0)
                                        .environmentObject(demo)
                                        .frame(height: min(470, max(280, geometry.size.height * 0.65)))
                                    Text(headings[index]).font(.title2.bold())
                                    Text(note(index)).font(.subheadline).foregroundStyle(.secondary)
                                        .lineLimit(3)
                                    Button(tr("打开快捷指令", "Open Shortcuts", "Buka Pintasan")) {
                                        if let url = URL(string: "shortcuts://") { openURL(url) }
                                    }.buttonStyle(.bordered).buttonBorderShape(.capsule)
                                }
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 26).padding(.vertical, 16)
                                .frame(maxWidth: .infinity)
                            }.tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .always))
                    .indexViewStyle(.page(backgroundDisplayMode: .always))
                }
            }
        }
        .background(Color(uiColor: .systemBackground))
        .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
        .task(id: "\(step)-\(scenePhase)") {
            gesturePhase = 0
            gestureStep = 0
            guard previewStep == nil, !model.isPreview, !unavailable, scenePhase == .active, let chapter else { return }
            let actions = GuideGesture.actions(chapter: chapter, stage: step + 1)
            if actions.isEmpty {
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
            } else {
                for index in actions.indices {
                    guard !Task.isCancelled else { return }
                    gestureStep = index
                    gesturePhase = 0
                    do { try await Task.sleep(for: .milliseconds(260)) } catch { return }
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.65)) { gesturePhase = 1 }
                    do { try await Task.sleep(for: .milliseconds(720)) } catch { return }
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.28)) { gesturePhase = 2 }
                    do { try await Task.sleep(for: .milliseconds(480)) } catch { return }
                }
            }
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.42)) { step = (step + 1) % 5 }
        }
    }

    private func row(_ label: String, _ value: String = "", focused: Bool = false, symbol: String = "") -> some View {
        HStack(spacing: 10) {
            if !symbol.isEmpty { Image(systemName: symbol).foregroundStyle(.blue) }
            Text(label).foregroundStyle(.primary)
            Spacer(minLength: 10)
            Text(value).foregroundStyle(focused ? Color.blue : .secondary).multilineTextAlignment(.trailing)
            if focused { Image(systemName: "hand.tap.fill").foregroundStyle(.blue).accessibilityHidden(true) }
        }.font(.subheadline).padding(14)
            .background(focused ? Color.blue.opacity(0.08) : Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(focused ? Color.blue.opacity(0.35) : .clear))
    }

    private func slide(_ index: Int) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(headings[index]).font(.title2.bold()).fixedSize(horizontal: false, vertical: true)
            Label(tr("快捷指令设置示意", "Shortcuts setup illustration", "Ilustrasi tetapan Pintasan"), systemImage: "square.stack.3d.up.fill")
                .font(.caption).foregroundStyle(.secondary)
            VStack(spacing: 12) {
                switch index {
                case 0:
                    row(tr("快捷指令", "Shortcuts", "Pintasan"), "+", focused: true, symbol: "square.stack.3d.up.fill")
                    row(tr("搜索操作", "Search actions", "Cari tindakan"), "月记 / YueJi", focused: true, symbol: "magnifyingglass")
                    row(actionName, "", focused: true, symbol: provider == .applePay ? "creditcard.fill" : "bell.badge.fill")
                case 1:
                    row(modern ? tr("编辑", "Edit", "Edit") : tr("快捷指令", "Shortcuts", "Pintasan"), tr("自动化", "Automation", "Automasi"), focused: true)
                    if provider == .applePay {
                        row(tr("触发方式", "Trigger", "Pencetus"), tr("交易", "Transaction", "Transaksi"), focused: true, symbol: "creditcard")
                        row(tr("卡片", "Card", "Kad"), tr("选择付款卡片", "Choose your card", "Pilih kad"), focused: true)
                    } else {
                        row(tr("触发方式", "Trigger", "Pencetus"), tr("通知", "Notification", "Notifikasi"), focused: true, symbol: "bell")
                        row("App", "TNG eWallet", focused: true)
                    }
                case 2:
                    Text(actionName).font(.headline).frame(maxWidth: .infinity, alignment: .leading)
                    if provider == .applePay {
                        row(tr("金额", "Amount", "Amaun"), tr("交易金额变量", "Transaction amount", "Amaun transaksi"), focused: true)
                        row(tr("商户", "Merchant", "Peniaga"), tr("商户变量", "Merchant variable", "Pemboleh ubah peniaga"), focused: true)
                        row(tr("币种", "Currency", "Mata wang"), tr("交易币种", "Transaction currency", "Mata wang transaksi"))
                        row(tr("交易时间", "Transaction date", "Tarikh transaksi"), tr("原交易时间", "Original transaction date", "Tarikh transaksi asal"))
                    } else {
                        row(tr("通知正文", "Notification body", "Teks notifikasi"), tr("通知的正文变量", "Notification text variable", "Pemboleh ubah teks notifikasi"), focused: true)
                        row(tr("通知标题（可选）", "Title (optional)", "Tajuk (pilihan)"), tr("通知标题变量", "Notification title", "Tajuk notifikasi"))
                        row(tr("通知时间（可选）", "Date (optional)", "Tarikh (pilihan)"), tr("通知时间变量", "Notification date", "Tarikh notifikasi"))
                    }
                case 3:
                    if modern {
                        row(tr("编辑", "Edit", "Edit"), "ⓘ", focused: true)
                        row(tr("隐私", "Privacy", "Privasi"), tr("锁定时允许运行", "Allow Running When Locked", "Benarkan ketika dikunci"), focused: true)
                    } else {
                        row(tr("运行方式", "Run mode", "Cara jalan"), tr("立即运行", "Run Immediately", "Jalan serta-merta"), focused: true)
                    }
                    row(tr("系统请求访问月记时", "When access to YueJi is requested", "Apabila akses YueJi diminta"), tr("允许", "Allow", "Benarkan"), focused: true)
                default:
                    row(provider == .applePay ? "Apple Pay" : "TNG eWallet", tr("传入资料", "Pass event data", "Hantar data"), symbol: "arrow.down")
                    row("月记 / YueJi", tr("运行记录", "Activity log", "Log aktiviti"), focused: true, symbol: "list.bullet.rectangle")
                    row(tr("账本", "Ledger", "Lejar"), tr("核对金额和商户", "Check amount and merchant", "Semak amaun dan peniaga"), symbol: "checkmark.circle")
                }
            }.padding(16).ledgerGlass().guideTarget("shortcut.steps")
            Text(note(index)).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if index == 4 && previewStep == nil {
                NavigationLink(tr("查看运行记录", "View activity log", "Lihat log aktiviti")) { AutomationStatusView() }
                if provider == .tng { NavigationLink(tr("打开 TNG 待确认", "Open TNG review", "Buka semakan TNG")) { TNGInboxView() } }
            }
        }.frame(maxWidth: 560).frame(maxWidth: .infinity)
    }

    private func note(_ index: Int) -> String {
        switch index {
        case 0: return tr("先打开月记一次，再添加这个动作。", "Open YueJi once before adding its action.", "Buka YueJi sekali sebelum menambah tindakannya.")
        case 1: return provider == .applePay
            ? tr("用 Wallet 的交易触发；不同卡片和付款方式需分别核对。", "Use the Wallet transaction trigger; verify each card and payment method.", "Guna pencetus transaksi Wallet; semak setiap kad dan cara bayaran.")
            : tr("iOS 27：选择 TNG 为通知来源。设置筛选时别漏掉需要记录的收款通知。", "On iOS 27, choose TNG as the notification source. Filters must also include incoming money if needed.", "Pada iOS 27, pilih TNG sebagai sumber. Penapis perlu termasuk wang masuk jika diperlukan.")
        case 2: return tr("点参数选择真实输入变量。交易标识拿不到就留空，不要填固定文字。", "Select actual input variables. Leave transaction ID empty unless a genuine ID is available.", "Pilih pemboleh ubah input sebenar. Biarkan ID kosong jika ID sebenar tiada.")
        case 3: return tr("按系统提供的选项启用并保存；演示本身不会激活自动化。", "Enable and save using the options your system provides. This walkthrough does not activate an automation.", "Aktifkan dan simpan mengikut pilihan sistem. Panduan ini tidak mengaktifkan automasi.")
        default: return provider == .applePay
            ? tr("对照实际记录确认成功；未触发的交易和退款仍需补记。", "Verify against actual records; missed events and refunds still need review.", "Sahkan dengan rekod sebenar; peristiwa terlepas dan pulangan perlu disemak.")
            : tr("已识别付款记为支出；收款显示＋并等待确认用途。不支持的格式可能被忽略。", "Recognized payments are expenses; incoming money shows + and awaits purpose review. Unsupported formats may be ignored.", "Bayaran dikenal pasti ialah belanja; wang masuk bertanda + menunggu semakan. Format lain mungkin diabaikan.")
        }
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
                }.guideTarget("automation.apple")
                NavigationLink { TNGInboxView() } label: {
                    SimpleSettingsRow(title: "TNG eWallet", subtitle: tr("通知接入与待确认", "Notification setup & review", "Persediaan notifikasi & semakan"), symbol: "bell.badge.fill", color: .teal)
                }.guideTarget("automation.tng")
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

private enum GuideScreen: Hashable {
    case overview, receiptEntry, tools, newExpense, foreignExpense, ledger, filter, editExpense, refund, receipt(Int), splitEditor
    case friends, friendSummary, friendDetail, repayment, history, friendSpending, statement, trip
    case recurring, recurringEditor, upcoming, comparison, duplicates
    case automation, applePay(Int), tng, tngPayment, tngIncoming, tngSetup(Int), logs
    case settings, appearance, notifications, categoriesMenu, categories, categoryEditor, rules, rates
    case backups, csv, restore, about
}

private struct GuideChapter: Identifiable {
    let id: String
    let title: String
    let path: String
    let detail: String
    let screens: [GuideScreen]
    static var all: [GuideChapter] {
        [
            .init(id: "expense", title: tr("记一笔", "Add an expense", "Tambah belanja"), path: "", detail: tr("点“记一笔”，填写金额、商家和日期。", "Tap Add expense, then enter an amount, merchant and date.", "Ketik Tambah belanja, isi amaun, peniaga dan tarikh."), screens: [.overview, .newExpense]),
            .init(id: "ledger", title: tr("看账本", "Find an entry", "Cari rekod"), path: "", detail: tr("到账本查找记录，再按需要筛选。", "Find entries in Ledger and narrow them down with filters.", "Cari rekod dalam Lejar dan tapis jika perlu."), screens: [.ledger, .filter]),
            .init(id: "receipt", title: tr("扫描收据", "Scan a receipt", "Imbas resit"), path: "", detail: tr("选照片后核对金额和日期，再按菜品分给每个人。画面使用示例收据数据。", "Choose a photo, check the amounts and date, then assign each item. This demonstration uses sample data.", "Pilih foto, semak amaun dan tarikh, lalu bahagi item. Demonstrasi menggunakan data contoh."), screens: [.receiptEntry, .receipt(0), .receipt(1), .receipt(2), .receipt(3), .receipt(4)]),
            .init(id: "split", title: tr("朋友分账", "Split with friends", "Bahagi bersama rakan"), path: "", detail: tr("从账本打开一笔消费，再按各自份额分账。", "Open an entry in Ledger and assign each friend's share.", "Buka rekod dalam Lejar dan tetapkan bahagian setiap rakan."), screens: [.ledger, .editExpense, .splitEditor]),
            .init(id: "repayment", title: tr("朋友还款", "Record a repayment", "Rekod bayaran rakan"), path: "", detail: tr("打开朋友的欠款，按实际收到的金额记录还款。", "Open a friend's balance and record the amount received.", "Buka baki rakan dan rekod amaun yang diterima."), screens: [.friends, .friendDetail, .repayment]),
            .init(id: "recurring", title: tr("固定消费", "Recurring bills", "Belanja berulang"), path: "", detail: tr("新增计划，设置金额、周期和开始日期。", "Add a schedule with its amount, frequency and start date.", "Tambah jadual bersama amaun, kekerapan dan tarikh mula."), screens: [.recurring, .recurringEditor]),
            .init(id: "applePay", title: tr("Apple Pay 自动记账", "Apple Pay automation", "Automasi Apple Pay"), path: "", detail: tr("在快捷指令选交易触发器，接入月记动作，并核对运行结果。系统画面为设置示意。", "Choose a transaction trigger in Shortcuts, connect YueJi's action and check the result. The system setup is illustrated.", "Pilih pencetus transaksi dalam Pintasan, sambung tindakan YueJi dan semak hasil. Tetapan sistem ialah ilustrasi."), screens: [.automation, .applePay(0), .applePay(1), .applePay(2), .applePay(3), .applePay(4)]),
            .init(id: "tng", title: tr("TNG 自动记账", "TNG automation", "Automasi TNG"), path: "", detail: tr("在快捷指令选通知触发器，接入月记动作；收到款项记为＋并由你确认。系统画面为设置示意。", "Choose a notification trigger and YueJi's action; incoming money appears as + for your review. The system setup is illustrated.", "Pilih pencetus notifikasi dan tindakan YueJi; wang masuk bertanda + untuk disemak. Tetapan sistem ialah ilustrasi."), screens: [.automation, .tngSetup(0), .tngSetup(1), .tngSetup(2), .tngSetup(3), .tngSetup(4), .tng, .tngIncoming]),
            .init(id: "settings", title: tr("外观与语言", "Appearance and language", "Paparan dan bahasa"), path: "", detail: tr("在设置中选择语言和外观。", "Choose a language and appearance in Settings.", "Pilih bahasa dan paparan dalam Tetapan."), screens: [.settings, .appearance]),
            .init(id: "backup", title: tr("备份账本", "Back up your ledger", "Sandarkan lejar"), path: "", detail: tr("从设置打开备份与导出，先保存一份完整备份。", "Open Backups & export in Settings to save a full backup.", "Buka Sandaran & eksport dalam Tetapan untuk menyimpan sandaran penuh."), screens: [.settings, .backups])
        ]
    }
}

enum GuideSample {
    static func ledger() -> Ledger {
        let date = Calendar.current.startOfDay(for: Date())
        let lunch = Expense(id: "guide-lunch", merchant: "Lunch Cafe", cents: 4664, date: date, category: "餐饮", shares: [Share(id: "guide-amy", name: "Amy", cents: 1749)])
        var ledger = Ledger(expenses: [lunch, Expense(id: "guide-shop", merchant: "Shopee", cents: 5667, date: date, category: "购物")])
        ledger.budgets[monthKey(date)] = 100000
        ledger.recurring = [RecurringExpense(id: "guide-recurring", name: "Internet", minor: 9900, start: date)]
        ledger.merchantCategories = ["lunch cafe": "餐饮"]
        ledger.rates["USD"] = RateQuote(value: 4.2, date: date, source: "Demo")
        ledger.tngNotices = [TNGNotice(id: "guide-incoming", body: "RM 10.00 received from Amy for Me.", title: "Ka-ching! Incoming Money.", date: date, usesReceivedDate: false, kind: "incoming", status: "pending", cents: 1000, party: "Amy", recipient: "Me")]
        ledger.tngNotices.append(TNGNotice(id: "guide-payment", body: "Payment of RM 18.00 to Lunch Cafe", title: "Payment", date: date, usesReceivedDate: false, kind: "payment", status: "pending", cents: 1800, party: "Lunch Cafe"))
        ledger.tripDefaults = TripDefaults(consumption: "6.5", price: "2.00", companions: ["Amy"], includeDriver: true)
        return ledger
    }
}

struct UsageGuideView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var preview = LedgerModel(previewLedger: GuideSample.ledger())
    @State private var page = 0
    @State private var stage = 0
    @State private var gesturePhase = 0
    @State private var gestureStep = 0
    private var chapters: [GuideChapter] { GuideChapter.all }
    private var selection: Binding<Int> {
        Binding(get: { page }, set: { next in page = next; stage = 0 })
    }
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                TabView(selection: selection) {
                    ForEach(Array(chapters.enumerated()), id: \.element.id) { index, chapter in
                        ScrollView {
                            VStack(spacing: 22) {
                                if abs(index - page) <= 1 {
                                    GuideScreenFrame(screen: chapter.screens[min(index == page ? stage : 0, chapter.screens.count - 1)], action: index == page ? GuideGesture.actions(chapter: chapter, stage: stage).dropFirst(gestureStep).first : nil, gesturePhase: index == page ? gesturePhase : 0)
                                        .environmentObject(preview)
                                        .frame(height: min(480, max(280, geometry.size.height * 0.65)))
                                } else {
                                    Color.clear.frame(height: min(480, max(280, geometry.size.height * 0.65)))
                                }
                                VStack(spacing: 10) {
                                    Text(chapter.title).font(.title2.bold())
                                    Text(chapter.detail).font(.subheadline).foregroundStyle(.secondary)
                                }
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityElement(children: .combine)
                            }
                            .padding(.horizontal, 28).padding(.top, 12).padding(.bottom, 52)
                            .frame(maxWidth: 560).frame(maxWidth: .infinity)
                        }.tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))
            }
            .background(Color(uiColor: .systemBackground))
            .navigationTitle(tr("认识月记", "Meet YueJi", "Kenali YueJi")).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "chevron.left") }
                        .accessibilityLabel(tr("关闭指南", "Close guide", "Tutup panduan"))
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        ForEach(Array(chapters.enumerated()), id: \.element.id) { index, chapter in
                            Button(chapter.title) { selection.wrappedValue = index }
                        }
                    } label: { Image(systemName: "list.bullet") }
                        .accessibilityLabel(tr("目录", "Contents", "Kandungan"))
                }
            }
            .task(id: "\(page)-\(stage)-\(scenePhase)") {
                gesturePhase = 0
                gestureStep = 0
                guard scenePhase == .active else { return }
                let actions = GuideGesture.actions(chapter: chapters[page], stage: stage)
                if actions.isEmpty {
                    do { try await Task.sleep(for: .seconds(2)) } catch { return }
                } else {
                    for index in actions.indices {
                        guard !Task.isCancelled else { return }
                        gestureStep = index
                        gesturePhase = 0
                        do { try await Task.sleep(for: .milliseconds(260)) } catch { return }
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.65)) { gesturePhase = 1 }
                        do { try await Task.sleep(for: .milliseconds(720)) } catch { return }
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.28)) { gesturePhase = 2 }
                        do { try await Task.sleep(for: .milliseconds(480)) } catch { return }
                    }
                }
                guard !Task.isCancelled else { return }
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.42)) {
                    stage = (stage + 1) % chapters[page].screens.count
                }
            }
        }
    }
}

// Preview markers measure the very same controls rendered by the app. The hand
// follows their layout, including localized text and Dynamic Type sizes.
struct GuideTargetKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
extension View {
    func guideTarget(_ key: String) -> some View {
        background(GeometryReader { proxy in
            Color.clear.preference(key: GuideTargetKey.self, value: [key: proxy.frame(in: .named("guidePreview"))])
        })
    }
}

private struct GuideGesture {
    let start: CGPoint
    let target: CGPoint
    let targetID: String
    let position: CGFloat
    let swipe: Bool
    static func actions(chapter: GuideChapter, stage: Int) -> [GuideGesture] {
        guard chapter.screens.indices.contains(stage) else { return [] }
        let points: [(String, CGFloat, CGFloat, CGFloat)]
        var swipe = false
        switch (chapter.id, stage) {
        case ("expense", 0): points = [("dashboard.add", 195, 665, 0.5)]
        case ("ledger", 0): points = [("ledger.filter", 300, 268, 0.5)]
        case ("receipt", 0): points = [("dashboard.receipt", 145, 375, 0.5)]
        case ("receipt", 1): points = [("receipt.photo", 145, 212, 0.5)]
        case ("receipt", 2): points = [("receipt.merchant", 285, 148, 0.5), ("receipt.date", 285, 235, 0.5), ("receipt.total", 285, 360, 0.5)]
        case ("receipt", 3): points = [("receipt.people", 195, 470, 0.5)]; swipe = true
        case ("receipt", 4): points = [("receipt.item0", 140, 200, 0.5), ("receipt.item1", 140, 300, 0.5), ("receipt.items", 195, 470, 0.5)]
        case ("split", 0): points = [("ledger.expense", 164, 370, 0.5)]
        case ("split", 1): points = [("expense.split", 245, 440, 0.5)]
        case ("repayment", 0): points = [("friends.person", 146, 380, 0.5)]
        case ("repayment", 1): points = [("friend.repay", 158, 350, 0.5)]
        case ("recurring", 0): points = [("recurring.add", 355, 55, 0.5)]
        case ("applePay", 0): points = [("automation.apple", 150, 156, 0.5)]
        case ("tng", 0): points = [("automation.tng", 150, 242, 0.5)]
        case ("applePay", 1...5), ("tng", 1...5): points = [("shortcut.steps", 200, 140, 0.25), ("shortcut.steps", 200, 210, 0.50), ("shortcut.steps", 200, 280, 0.75)]
        case ("tng", 6): points = [("tng.incoming", 140, 300, 0.5)]
        case ("settings", 0): points = [("settings.appearance", 145, 185, 0.5)]
        case ("backup", 0): points = [("settings.backup", 145, 570, 0.5)]
        default: return []
        }
        return points.map { key, x, y, relative in
            let point = CGPoint(x: x, y: y)
            return GuideGesture(start: swipe ? CGPoint(x: x, y: y + 120) : CGPoint(x: x + 70, y: y + 95), target: point, targetID: key, position: relative, swipe: swipe)
        }
    }
}

private struct GuideTouchIndicator: View {
    let phase: Int
    let action: GuideGesture
    let measured: CGRect?
    private var destination: CGPoint {
        guard let measured, measured.width > 0, measured.height > 0 else { return action.target }
        return CGPoint(x: measured.midX, y: measured.minY + measured.height * action.position)
    }
    var body: some View {
        ZStack {
            if phase == 2 && !action.swipe {
                Circle().stroke(.blue.opacity(0.55), lineWidth: 2)
                    .frame(width: 62, height: 62)
                    .transition(.scale.combined(with: .opacity))
            }
            Circle().fill(.white.opacity(0.86))
                .frame(width: 46, height: 46)
                .overlay(Circle().strokeBorder(.blue.opacity(0.55), lineWidth: 1.5))
                .shadow(color: .black.opacity(0.17), radius: 9, y: 4)
                .overlay(Image(systemName: "hand.point.up.left.fill")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.blue))
                .scaleEffect(phase == 2 && !action.swipe ? 0.78 : 1)
        }
        .position(phase == 1 ? (action.swipe ? CGPoint(x: destination.x, y: destination.y + 120) : CGPoint(x: destination.x + 70, y: destination.y + 95)) : destination)
        .accessibilityHidden(true)
    }
}

private struct GuideScreenFrame: View {
    let screen: GuideScreen
    let action: GuideGesture?
    let gesturePhase: Int
    @State private var measuredTargets: [String: CGRect] = [:]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        GeometryReader { geometry in
            let scale = min(geometry.size.width / 410, geometry.size.height / 820)
            VStack(spacing: 0) {
                HStack {
                    Text("9:41").font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Capsule().fill(.primary).frame(width: 88, height: 24)
                    Spacer()
                    Image(systemName: "wifi")
                    Image(systemName: "battery.100percent")
                }.padding(.horizontal, 25).frame(height: 38)
                ZStack {
                    GuideActualScreen(screen: screen)
                        .id(screen)
                        .transition(reduceMotion ? .identity : .asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
                    if let action, gesturePhase > 0 {
                        GuideTouchIndicator(phase: gesturePhase, action: action, measured: measuredTargets[action.targetID])
                    }
                }.frame(width: 390, height: 740).clipped()
                    .coordinateSpace(name: "guidePreview")
                    .onPreferenceChange(GuideTargetKey.self) { measuredTargets = $0 }
                Capsule().fill(.primary).frame(width: 125, height: 5)
                    .frame(height: 22)
            }
            .frame(width: 390, height: 800)
            .background(Color(uiColor: .systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 42))
            .overlay(RoundedRectangle(cornerRadius: 42).strokeBorder(Color.primary.opacity(0.85), lineWidth: 5))
            .padding(10)
            .scaleEffect(scale)
            .frame(width: geometry.size.width, height: geometry.size.height)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

// The five root screens and their tab labels are the same views used by MainView.
// MainView's live-data, rates and first-launch tasks are deliberately not invoked.
private struct GuideRootScreen: View {
    let tab: Int
    var body: some View {
        TabView(selection: .constant(tab)) {
            DashboardView().tag(0).tabItem { Label(tr("概览", "Overview", "Ringkasan"), systemImage: "chart.pie.fill") }
            ExpensesView().tag(1).tabItem { Label(tr("账本", "Ledger", "Lejar"), systemImage: "list.bullet.rectangle") }
            RecurringView().tag(2).tabItem { Label(tr("固定", "Recurring", "Berulang"), systemImage: "repeat") }
            FriendsView().tag(3).tabItem { Label(tr("分账", "Friends", "Rakan"), systemImage: "person.2.fill") }
            SettingsView().tag(4).tabItem { Label(tr("设置", "Settings", "Tetapan"), systemImage: "slider.horizontal.3") }
        }.tabViewStyle(.automatic)
    }
}

private struct GuideActualScreen: View {
    @EnvironmentObject private var model: LedgerModel
    let screen: GuideScreen
    private var expense: Expense { model.ledger.expenses[0] }
    var body: some View {
        Group {
            switch screen {
            case .overview: GuideRootScreen(tab: 0)
            case .receiptEntry: DashboardView(guideFocus: "dashboard.receipt")
            case .ledger: GuideRootScreen(tab: 1)
            case .recurring: GuideRootScreen(tab: 2)
            case .friends: GuideRootScreen(tab: 3)
            case .settings: GuideRootScreen(tab: 4)
            case .newExpense: ExpenseEditor(original: nil, initialDraft: Expense(merchant: "Lunch Cafe", cents: 1800, category: "餐饮"))
            case .foreignExpense:
                ExpenseEditor(original: nil, initialDraft: Expense(merchant: "Book shop", cents: 4200, category: "购物", foreign: ForeignAmount(currency: "USD", minor: 1000, quote: RateQuote(value: 4.2, date: Date(), source: "Demo"))))
            case .categoryEditor: CategoryEditor(initial: CustomCategory(name: tr("学习", "Study", "Belajar"), icon: "book.fill"))
            case .editExpense: ExpenseEditor(original: expense)
            case .splitEditor: ExpenseEditor(original: expense, startWithSplit: true)
            case .filter: LedgerFilterEditor(value: LedgerFilter()) { _ in }
            case .repayment: RepaymentView(target: RepayTarget(expense: expense, share: expense.shares[0]))
            case .recurringEditor: RecurringEditor(original: nil)
            case .appearance: SettingsView(guideDestination: "appearance")
            case .categoriesMenu: SettingsView(guideDestination: "categories")
            case .backups: SettingsView(guideDestination: "backup")
            case .about: SettingsView(guideDestination: "about")
            case .restore:
                if let data = try? LocalStore.encode(model.ledger), let preview = try? RestorePreview(data: data) {
                    RestorePreviewView(preview: preview) { }
                }
            default:
                NavigationStack { destination }
            }
        }.id(screen)
    }
    @ViewBuilder private var destination: some View {
        switch screen {
        case .tools: OverviewToolsView()
        case .friendSummary: FriendSummaryView()
        case .tngPayment: TNGNoticeView(id: "guide-payment")
        case .refund: RefundsView(expenseID: expense.id)
        case .receipt(let section): ReceiptScanView(guideSection: section)
        case .friendDetail: FriendDetailView(key: "amy")
        case .history: SplitHistoryView()
        case .friendSpending: FriendSpendingView(friend: "amy")
        case .statement: FriendStatementView(key: "amy")
        case .trip: FuelCalculatorView()
        case .upcoming: UpcomingView(initialMonth: Date())
        case .comparison: SpendingComparisonView(month: Date())
        case .duplicates: DuplicateReviewView()
        case .automation: AutomationSetupView()
        case .applePay(let step): ShortcutHelpView(previewStep: step)
        case .tng: TNGInboxView()
        case .tngIncoming: TNGIncomingView(id: "guide-incoming")
        case .tngSetup(let step): TNGSetupView(previewStep: step)
        case .logs: AutomationStatusView()
        case .notifications: NotificationSettingsView()
        case .categories: CategoriesView()
        case .rules: MerchantRulesView()
        case .rates: RatesView()
        case .csv: CSVExportView()
        default: EmptyView()
        }
    }
}
