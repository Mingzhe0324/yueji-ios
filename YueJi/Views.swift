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
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(.primary.opacity(0.05)))
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
            .modifier(YueJiEntrance())
    }
}
private struct YueJiListSurface: ViewModifier {
    func body(content: Content) -> some View {
        content.listStyle(.insetGrouped).listSectionSpacing(22)
            .scrollContentBackground(.hidden).background(Color(uiColor: .systemGroupedBackground))
            .modifier(YueJiEntrance())
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
    @AppStorage("hasSeenMoonOpening") private var hasSeenOpening = false
    @State private var showingGuide = false
    @State private var selectedTab = 0
    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView().tag(0).tabItem { Label(tr("概览", "Overview", "Ringkasan"), systemImage: "chart.pie.fill") }
            ExpensesView().tag(1).tabItem { Label(tr("账本", "Ledger", "Lejar"), systemImage: "list.bullet.rectangle") }
            RecurringView().tag(2).tabItem { Label(tr("固定", "Recurring", "Berulang"), systemImage: "repeat") }
            FriendsView().tag(3).tabItem { Label(tr("分账", "Friends", "Rakan"), systemImage: "person.2.fill") }
            SettingsView().tag(4).tabItem { Label(tr("设置", "Settings", "Tetapan"), systemImage: "slider.horizontal.3") }
        }.tint(ink)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: selectedTab)
            .overlay {
                if !model.didFinishLaunch {
                    OpeningAnimationView(compact: hasSeenOpening).transition(.opacity)
                }
            }
            .task {
                model.reload(postRecurring: false)
                if !model.didFinishLaunch {
                    if !reduceMotion { do { try await Task.sleep(for: .milliseconds(hasSeenOpening ? 650 : 1550)) } catch { return } }
                    hasSeenOpening = true
                    withAnimation(.easeOut(duration: reduceMotion ? 0.15 : 0.3)) { model.didFinishLaunch = true }
                }
                if !completedGuide { showingGuide = true }
                await AutomaticRates.shared.refreshSaved(); model.reload()
            }
            .sheet(isPresented: $showingGuide, onDismiss: { completedGuide = true }) {
                UsageGuideView()
            }
            .onChange(of: selectedTab) { _, _ in UISelectionFeedbackGenerator().selectionChanged() }
            .overlay(alignment: .top) {
                if !model.undoEntries.isEmpty {
                    HStack(spacing: 16) {
                        Label(String(model.undoEntries.count) + tr(" 笔已删除", " deleted", " dipadam"), systemImage: "trash")
                            .font(.subheadline.weight(.medium))
                        Button(tr("撤销", "Undo", "Batal padam")) {
                            withAnimation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.88)) { model.undoDeletion() }
                        }.font(.subheadline.bold()).frame(minWidth: 44, minHeight: 44)
                    }
                    .padding(.horizontal, 16).ledgerGlass().padding(.horizontal, 24).padding(.top, 8)
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                } else if model.savedNotice != nil {
                    Label(tr("已保存", "Saved", "Disimpan"), systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(ink)
                        .padding(.horizontal, 20).padding(.vertical, 12).ledgerGlass()
                        .padding(.top, 8).allowsHitTesting(false)
                        .accessibilityLabel(tr("账目已保存", "Entry saved", "Rekod disimpan"))
                        .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .scale(scale: 0.92)).combined(with: .opacity))
                }
            }
            .animation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.82), value: model.savedNotice)
            .animation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.88), value: model.undoEntries.count)
            .task(id: model.savedNotice) {
                guard let token = model.savedNotice else { return }
                do { try await Task.sleep(for: .seconds(4.5)) } catch { return }
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
    @State private var reviewing: Expense?
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
                    recentCard
                    NavigationLink { SavingsGoalsView() } label: {
                        GlassPanel {
                            VStack(alignment: .leading, spacing: 12) {
                                Label(tr("储蓄目标", "Savings goals", "Matlamat simpanan"), systemImage: "target").font(.headline)
                                if let goal = model.ledger.savingsGoals.first(where: { $0.balance < $0.target }) ?? model.ledger.savingsGoals.first {
                                    HStack { Text(goal.name); Spacer(); Text(money(goal.balance)).monospacedDigit() }
                                    ProgressView(value: goal.progress).tint(.blue)
                                } else {
                                    Text(tr("为想做的事，存下第一笔。", "Set aside your first contribution.", "Asingkan simpanan pertama anda.")).font(.subheadline).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }.buttonStyle(.plain)
                    DisclosureGroup(tr("收支与分类明细", "Payment & category details", "Butiran bayaran & kategori")) {
                        VStack(spacing: 16) { balancesCard; categoriesCard }.padding(.top, 12)
                    }.font(.subheadline.weight(.medium))
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
            .sheet(item: $reviewing) { entry in
                ExpenseDetailView(id: entry.id).yuejiZoom(id: entry.id, namespace: navigationMotion)
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
    private var recentCard: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(tr("最近账目", "Recent entries", "Rekod terkini")).font(.headline)
                    Spacer()
                    Text(tr("所选月份", "Selected month", "Bulan dipilih")).font(.caption).foregroundStyle(.secondary)
                }
                let recent = Array(entries.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date > $1.date }.prefix(3))
                if recent.isEmpty {
                    Text(tr("这个月还没有账目，记下第一笔吧。", "No entries this month. Add your first expense.", "Tiada rekod bulan ini. Tambah belanja pertama anda."))
                        .font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 12)
                }
                ForEach(recent) { entry in
                    Button { reviewing = entry } label: { ExpenseRow(entry: entry) }
                        .buttonStyle(.plain).yuejiZoomSource(id: entry.id, namespace: navigationMotion)
                    if entry.id != recent.last?.id { Divider() }
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
            Section(tr("日常工具", "Everyday tools", "Alat harian")) {
                NavigationLink { ReceiptScanView() } label: { Label(tr("拍收据分账", "Snap receipt & split", "Imbas resit & bahagi"), systemImage: "doc.viewfinder") }
                    .guideTarget("dashboard.receipt")
                NavigationLink { AutomationSetupView() } label: { Label(tr("自动记账", "Automatic recording", "Rekod automatik"), systemImage: "bolt.fill") }
            }
            Section(tr("分析", "Insights", "Analisis")) {
                NavigationLink { SpendingComparisonView(month: month) } label: { Label(tr("月度消费对比", "Monthly comparison", "Perbandingan bulanan"), systemImage: "chart.bar.xaxis") }
                NavigationLink { UpcomingView(initialMonth: month) } label: { Label(tr("固定消费预览", "Upcoming bills", "Bil akan datang"), systemImage: "calendar") }
                NavigationLink { DuplicateReviewView() } label: { Label(tr("检查重复账目", "Review duplicates", "Semak pendua"), systemImage: "doc.on.doc") }
            }
            Section {
                NavigationLink(tr("预算与每日提醒", "Budget & daily reminders", "Peringatan bajet & harian")) { NotificationSettingsView() }
            }
        }.yuejiListSurface().navigationTitle(tr("更多工具", "More tools", "Alat lain")).navigationBarTitleDisplayMode(.inline)
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
                Text(dateLabel(entry.date)).font(.caption).foregroundStyle(.secondary)
                if entry.refunded > 0 { Text(tr("已退款：", "Refunded: ", "Dipulangkan: ") + "+" + money(entry.refunded)).font(.caption).foregroundStyle(.green) }
                if !entry.shares.isEmpty { Text(tr("我的份额：", "My share: ", "Bahagian saya: ") + money(entry.personal)).font(.caption) }
            }
            if !typeSize.isAccessibilitySize { Spacer(minLength: 8) }
            Text("−" + money(entry.cents)).foregroundStyle(.primary).accessibilityLabel(tr("支出 ", "Expense ", "Belanja ") + money(entry.cents)).monospacedDigit().font(.subheadline.weight(.semibold)).multilineTextAlignment(.trailing).layoutPriority(1)
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
    @State private var reviewing: Expense?
    @Namespace private var expenseTransition
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
                            Button { reviewing = entry } label: { ExpenseRow(entry: entry).foregroundStyle(.primary) }
                                .guideTarget(entry.id == "guide-lunch" ? "ledger.expense" : "ledger.other")
                                .yuejiZoomSource(id: entry.id, namespace: expenseTransition)
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) { deleting = entry } label: {
                                        Label(tr("删除", "Delete", "Padam"), systemImage: "trash")
                                    }
                                }
                                .contextMenu {
                                    Button(tr("编辑", "Edit", "Edit"), systemImage: "pencil") { editing = entry }
                                    Button(tr("删除", "Delete", "Padam"), systemImage: "trash", role: .destructive) { deleting = entry }
                                }
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
                .sheet(item: $reviewing) { entry in
                    ExpenseDetailView(id: entry.id).yuejiZoom(id: entry.id, namespace: expenseTransition)
                }
                .sheet(item: $editing) { ExpenseEditor(original: $0) }
                .modifier(ExpenseDeletionConfirmation(expense: $deleting))
                .animation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.88), value: entries.map(\.id))
        }
    }
}
struct ExpenseDetailView: View {
    let id: String
    @EnvironmentObject private var model: LedgerModel
    @Environment(\.dismiss) private var dismiss
    @State private var editing: Expense?
    @State private var deleting: Expense?
    private var entry: Expense? { model.ledger.expenses.first { $0.id == id } }

    var body: some View {
        NavigationStack {
            List {
                if let entry {
                    Section {
                        VStack(spacing: 12) {
                            CategoryBadge(name: entry.category).font(.subheadline)
                            Text(money(entry.cents)).font(.system(.largeTitle, design: .rounded, weight: .bold))
                                .monospacedDigit().minimumScaleFactor(0.6).lineLimit(1)
                            Text(entry.merchant).font(.title3.weight(.semibold)).multilineTextAlignment(.center)
                            Text(dateLabel(entry.date, time: true)).font(.subheadline).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity).padding(.vertical, 20)
                    }
                    Section(tr("付款详情", "Payment details", "Butiran bayaran")) {
                        LabeledContent(tr("来源", "Source", "Sumber"), value: sourceLabel(entry.source))
                        LabeledContent(tr("我的实际消费", "My spending", "Belanja saya"), value: money(entry.personal))
                        if let fx = entry.foreign {
                            LabeledContent(tr("原币金额", "Original amount", "Amaun asal"), value: Currency.display(fx.minor, fx.currency))
                            LabeledContent(tr("汇率", "Exchange rate", "Kadar pertukaran"), value: "1 \(fx.currency) = \(fx.quote.text) MYR")
                        }
                        if entry.refunded > 0 {
                            LabeledContent(tr("已退款", "Refunded", "Dipulangkan"), value: money(entry.refunded))
                        }
                        NavigationLink(tr("退款记录", "Refunds", "Bayaran balik")) { RefundsView(expenseID: id) }
                    }
                    if !entry.shares.isEmpty {
                        Section(tr("朋友分账", "Shared expenses", "Belanja dikongsi")) {
                            ForEach(entry.shares) { share in
                                VStack(alignment: .leading, spacing: 8) {
                                    LabeledContent(share.name, value: money(share.cents)).font(.headline)
                                    LabeledContent(tr("已还", "Repaid", "Telah dibayar"), value: money(share.repaid))
                                    LabeledContent(share.owed < 0 ? tr("需退给朋友", "Return to friend", "Pulangkan kepada rakan") : tr("待还", "Outstanding", "Belum dibayar"), value: money(abs(share.owed)))
                                }.font(.subheadline).padding(.vertical, 6)
                            }
                        }
                    }
                    if let receipt = entry.receiptSummary {
                        Section(tr("收据明细", "Receipt details", "Butiran resit")) {
                            DisclosureGroup(tr("查看明细", "View details", "Lihat butiran")) {
                                Text(receipt).font(.subheadline).textSelection(.enabled).padding(.vertical, 8)
                            }
                            ShareLink(item: receipt) { Label(tr("分享明细", "Share details", "Kongsi butiran"), systemImage: "square.and.arrow.up") }
                        }
                    }
                } else {
                    ContentUnavailableView(tr("账目已删除", "Entry deleted", "Rekod dipadam"), systemImage: "tray")
                }
            }
            .yuejiListSurface().navigationTitle(tr("账目详情", "Entry details", "Butiran rekod"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("关闭", "Close", "Tutup")) { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let entry {
                    HStack(spacing: 16) {
                        Button { editing = entry } label: {
                            Label(tr("编辑", "Edit", "Edit"), systemImage: "pencil")
                                .frame(maxWidth: .infinity, minHeight: 48)
                        }.yuejiPrimaryButton().buttonBorderShape(.capsule)
                        Button(role: .destructive) { deleting = entry } label: {
                            Label(tr("删除", "Delete", "Padam"), systemImage: "trash")
                                .frame(minWidth: 72, minHeight: 48)
                        }.buttonStyle(.bordered).buttonBorderShape(.capsule)
                    }.padding(.horizontal, 24).padding(.vertical, 10).background(.bar)
                }
            }
            .sheet(item: $editing) { ExpenseEditor(original: $0) }
            .modifier(ExpenseDeletionConfirmation(expense: $deleting, onDeleted: { dismiss() }))
            .onChange(of: entry == nil) { _, missing in if missing { dismiss() } }
        }
        .presentationDragIndicator(.visible).presentationCornerRadius(28)
    }
}

/// A captured presenting value survives the dialog resetting its binding.
private struct ExpenseDeletionConfirmation: ViewModifier {
    @EnvironmentObject private var model: LedgerModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var expense: Expense?
    var onDeleted: () -> Void = {}
    @State private var failure: String?

    func body(content: Content) -> some View {
        content.confirmationDialog(
            tr("删除这笔账目？", "Delete this entry?", "Padam rekod ini?"),
            isPresented: Binding(get: { expense != nil }, set: { if !$0 { expense = nil } }),
            titleVisibility: .visible, presenting: expense
        ) { entry in
            Button(tr("删除", "Delete", "Padam"), role: .destructive) {
                guard !model.isPreview else { return }
                do {
                    try withAnimation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.88)) {
                        try model.deleteExpense(entry)
                    }
                    onDeleted()
                } catch { failure = error.localizedDescription }
            }
            Button(tr("取消", "Cancel", "Batal"), role: .cancel) {}
        } message: { entry in
            Text(entry.merchant + " · " + money(entry.cents) + "\n" + tr(
                "关联的分账、还款和退款也会删除，统计会同步更新。",
                "Linked splits, repayments and refunds will also be deleted. Totals will update.",
                "Pembahagian, bayaran rakan dan bayaran balik berkaitan turut dipadam. Jumlah akan dikemas kini."))
        }
        .alert(tr("无法删除", "Unable to delete", "Tidak dapat memadam"),
               isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button("OK", role: .cancel) { failure = nil }
        } message: { Text(failure ?? "") }
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var deleting: Expense?
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
                    Section(tr("收据税费", "Receipt charges", "Caj resit")) { Text(summary).font(.caption); ShareLink(item: summary) { Label(tr("分享明细", "Share details", "Kongsi butiran"), systemImage: "square.and.arrow.up") } }
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
                if let original {
                    Section {
                        Button(role: .destructive) { deleting = original } label: {
                            Label(tr("删除这笔账目", "Delete this entry", "Padam rekod ini"), systemImage: "trash")
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                }
            }
                .animation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.88), value: splitting)
                .animation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.88), value: people.count)
                .modifier(ExpenseDeletionConfirmation(expense: $deleting, onDeleted: { dismiss() }))
                .navigationTitle(tr("记账 / 分账", "Expense / split", "Belanja / pembahagian")).navigationBarTitleDisplayMode(.inline).presentationDragIndicator(.visible).presentationCornerRadius(28)
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
                .sheet(item: $editing) { ExpenseDetailView(id: $0.id) }
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
    @State private var showingUsageGuide = false
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
                    Button { showingUsageGuide = true } label: {
                        SimpleSettingsRow(title: tr("使用指南", "Getting started", "Panduan penggunaan"), subtitle: tr("记账、自动化与朋友还款", "Expenses, automation and repayments", "Belanja, automasi dan bayaran balik"), symbol: "book.fill", color: .green)
                    }
                } header: { Text(tr("数据与帮助", "Data & help", "Data & bantuan")) }
            }.yuejiListSurface().navigationTitle(tr("设置", "Settings", "Tetapan")).navigationBarTitleDisplayMode(.inline)
                .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: "YueJi-\(monthKey(Date()))") { if case .failure(let e) = $0 { model.error = e.localizedDescription } }
                .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                    do { let url = try result.get(); let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }; let data = try Data(contentsOf: url); restorePreview = try RestorePreview(data: data) } catch { model.error = error.localizedDescription }
                }
                .sheet(isPresented: $showingUsageGuide) { UsageGuideView() }
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
    var body: some View { ShortcutSetupGuide(provider: .applePay) }
}

enum ShortcutSetupProvider: Equatable { case applePay, tng }

struct ShortcutSetupGuide: View {
    let provider: ShortcutSetupProvider
    @EnvironmentObject private var model: LedgerModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @State private var step = 0
    @State private var gesturePhase = 0
    @State private var gestureStep = 0
    private var modern: Bool { ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27 }
    private var title: String { provider == .applePay ? tr("Apple Pay 设置演示", "Apple Pay walkthrough", "Panduan Apple Pay") : tr("TNG 设置演示", "TNG walkthrough", "Panduan TNG") }
    private var selection: Binding<Int> { Binding(get: { step }, set: { step = $0 }) }
    private var unavailable: Bool { provider == .tng && !modern }
    private var chapter: GuideChapter? { GuideChapter.all.first { $0.id == (provider == .applePay ? "applePay" : "tng") } }
    private func action(for page: Int) -> GuideGesture? {
        guard let chapter else { return nil }
        return GuideGesture.actions(chapter: chapter, stage: page + 1).dropFirst(gestureStep).first
    }
    var body: some View {
        Group {
            if unavailable {
                ContentUnavailableView(tr("需要通知触发器", "Notification trigger required", "Pencetus notifikasi diperlukan"), systemImage: "bell.badge", description: Text(tr("此演示使用 iOS 27 的通知自动化。当前系统没有这个入口时，可继续手动记账。", "This walkthrough uses iOS 27 notification automations. If your system does not have this trigger, use manual recording.", "Panduan ini menggunakan automasi notifikasi iOS 27. Jika pencetus tiada, guna rekod manual.")))
            } else {
                GeometryReader { geometry in
                    TabView(selection: selection) {
                        ForEach(0..<5) { index in
                            VStack(spacing: 18) {
                                    GuideScreenFrame(screen: provider == .applePay ? .applePay(index) : .tngSetup(index), action: index == step ? action(for: index) : nil, gesturePhase: index == step ? gesturePhase : 0)
                                        .frame(height: min(470, max(280, geometry.size.height * 0.65)))
                                    Text(provider == .applePay ? tr("启用 Apple Pay 自动记账", "Set up Apple Pay recording", "Sediakan rekod Apple Pay") : tr("启用 TNG 自动记账", "Set up TNG recording", "Sediakan rekod TNG"))
                                        .font(.title2.bold())
                                    Text(GuideCue.text(provider == .applePay ? .applePay(index) : .tngSetup(index)))
                                        .font(.headline).foregroundStyle(.secondary).lineLimit(3)
                                    Button(tr("打开快捷指令", "Open Shortcuts", "Buka Pintasan")) {
                                        if let url = URL(string: "shortcuts://") { openURL(url) }
                                    }.buttonStyle(.bordered).buttonBorderShape(.capsule)
                                }
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 26).padding(.vertical, 16)
                                .frame(maxWidth: .infinity)
                            .tag(index)
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
            guard !model.isPreview, !unavailable, scenePhase == .active, step < 4, let chapter else { return }
            let actions = GuideGesture.actions(chapter: chapter, stage: step + 1)
            if actions.isEmpty {
                do { try await Task.sleep(for: .seconds(4.5)) } catch { return }
            } else {
                for index in actions.indices {
                    guard !Task.isCancelled else { return }
                    gestureStep = index
                    gesturePhase = 0
                    do { try await Task.sleep(for: .milliseconds(1200)) } catch { return }
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.65)) { gesturePhase = 1 }
                    do { try await Task.sleep(for: .milliseconds(720)) } catch { return }
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.28)) { gesturePhase = 2 }
                    do { try await Task.sleep(for: .milliseconds(480)) } catch { return }
                }
            }
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.42)) { step += 1 }
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
            content.buttonStyle(.glassProminent)
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
    case overview, receiptEntry, tools, newExpense, foreignExpense, ledger, filter, expenseDetail, editExpense, refund, receipt(Int), splitEditor
    case friends, friendSummary, friendDetail, repayment, repaymentDone, history, friendSpending, statement, trip
    case recurring, recurringEditor, upcoming, comparison, duplicates
    case automation, applePay(Int), tng, tngPayment, tngIncoming, tngSetup(Int), logs
    case settings, appearance, notifications, categoriesMenu, categories, categoryEditor, rules, rates
    case backups, csv, restore, about
    case savedExpense, filteredLedger
}

private struct GuideChapter: Identifiable {
    let id: String
    let title: String
    let path: String
    let detail: String
    let screens: [GuideScreen]
    static var all: [GuideChapter] {
        [
            .init(id: "expense", title: tr("记一笔", "Add an expense", "Tambah belanja"), path: "", detail: tr("点“记一笔”，填写金额、商家和日期。", "Tap Add expense, then enter an amount, merchant and date.", "Ketik Tambah belanja, isi amaun, peniaga dan tarikh."), screens: [.overview, .newExpense, .savedExpense]),
            .init(id: "ledger", title: tr("看账本", "Find an entry", "Cari rekod"), path: "", detail: tr("到账本查找记录，再按需要筛选。", "Find entries in Ledger and narrow them down with filters.", "Cari rekod dalam Lejar dan tapis jika perlu."), screens: [.ledger, .filter, .filteredLedger]),
            .init(id: "receipt", title: tr("扫描收据", "Scan a receipt", "Imbas resit"), path: "", detail: tr("选照片后核对金额和日期，再按菜品分给每个人。画面使用示例收据数据。", "Choose a photo, check the amounts and date, then assign each item. This demonstration uses sample data.", "Pilih foto, semak amaun dan tarikh, lalu bahagi item. Demonstrasi menggunakan data contoh."), screens: [.receiptEntry, .receipt(0), .receipt(1), .receipt(2), .receipt(3), .receipt(4)]),
            .init(id: "split", title: tr("朋友分账", "Split with friends", "Bahagi bersama rakan"), path: "", detail: tr("从账本打开一笔消费，再按各自份额分账。", "Open an entry in Ledger and assign each friend's share.", "Buka rekod dalam Lejar dan tetapkan bahagian setiap rakan."), screens: [.ledger, .expenseDetail, .editExpense, .splitEditor, .friends]),
            .init(id: "repayment", title: tr("朋友还款", "Record a repayment", "Rekod bayaran rakan"), path: "", detail: tr("打开朋友的欠款，按实际收到的金额记录还款。", "Open a friend's balance and record the amount received.", "Buka baki rakan dan rekod amaun yang diterima."), screens: [.friends, .friendDetail, .repaymentDone]),
            .init(id: "recurring", title: tr("固定消费", "Recurring bills", "Belanja berulang"), path: "", detail: tr("新增计划，设置金额、周期和开始日期。", "Add a schedule with its amount, frequency and start date.", "Tambah jadual bersama amaun, kekerapan dan tarikh mula."), screens: [.recurring, .recurringEditor, .recurring]),
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
    @State private var page = 0
    @State private var stage = 0
    @State private var gesturePhase = 0
    @State private var gestureStep = 0
    private var chapters: [GuideChapter] { GuideChapter.all }
    private var selection: Binding<Int> {
        Binding(get: { page }, set: { next in page = next; stage = 0 })
    }
    private func stepLabel(index: Int, count: Int) -> String {
        let current = index == page ? stage : 0
        let label = current == 0 ? tr("从这里开始", "Start here", "Mula di sini") : (current == count - 1 ? tr("查看结果", "See the result", "Lihat hasil") : tr("跟着操作", "Follow the action", "Ikut langkah"))
        return "\(current + 1) / \(count) · " + label
    }
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                TabView(selection: selection) {
                    ForEach(Array(chapters.enumerated()), id: \.element.id) { index, chapter in
                        VStack(spacing: 22) {
                                if abs(index - page) <= 1 {
                                    GuideScreenFrame(screen: chapter.screens[min(index == page ? stage : 0, chapter.screens.count - 1)], action: index == page ? GuideGesture.actions(chapter: chapter, stage: stage).dropFirst(gestureStep).first : nil, gesturePhase: index == page ? gesturePhase : 0)
                                        .frame(height: min(480, max(280, geometry.size.height * 0.65)))
                                } else {
                                    Color.clear.frame(height: min(480, max(280, geometry.size.height * 0.65)))
                                }
                                VStack(spacing: 10) {
                                    Text(chapter.title).font(.title2.bold())
                                    Text(stepLabel(index: index, count: chapter.screens.count))
                                        .font(.caption).foregroundStyle(.secondary)
                                    Text(GuideCue.text(chapter.screens[min(index == page ? stage : 0, chapter.screens.count - 1)])).font(.headline).foregroundStyle(.secondary)
                                }
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityElement(children: .combine)
                            }
                            .padding(.horizontal, 28).padding(.top, 12).padding(.bottom, 52)
                            .frame(maxWidth: 560).frame(maxWidth: .infinity)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))
            }
            .background(Color(uiColor: .systemBackground))
            .navigationTitle(tr("认识月记", "Meet YueJi", "Kenali YueJi")).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel(tr("关闭指南", "Close guide", "Tutup panduan"))
                }

            }
            .task(id: "\(page)-\(stage)-\(scenePhase)") {
                gesturePhase = 0
                gestureStep = 0
                guard scenePhase == .active, stage + 1 < chapters[page].screens.count else { return }
                let actions = GuideGesture.actions(chapter: chapters[page], stage: stage)
                if actions.isEmpty {
                    do { try await Task.sleep(for: .seconds(4.5)) } catch { return }
                } else {
                    for index in actions.indices {
                        guard !Task.isCancelled else { return }
                        gestureStep = index
                        gesturePhase = 0
                        do { try await Task.sleep(for: .milliseconds(1200)) } catch { return }
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.65)) { gesturePhase = 1 }
                        do { try await Task.sleep(for: .milliseconds(720)) } catch { return }
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.28)) { gesturePhase = 2 }
                        do { try await Task.sleep(for: .milliseconds(480)) } catch { return }
                    }
                }
                guard !Task.isCancelled else { return }
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.42)) {
                    stage += 1
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
    let targetID: String
    let position: CGFloat
    let swipe: Bool
    static func actions(chapter: GuideChapter, stage: Int) -> [GuideGesture] {
        let target: String
        switch (chapter.id, stage) {
        case ("expense", 0): target = "dashboard.add"
        case ("ledger", 0): target = "ledger.filter"
        case ("receipt", 0): target = "dashboard.receipt"
        case ("receipt", 1): target = "receipt.photo"
        case ("split", 0): target = "ledger.expense"
        case ("split", 1): target = "detail.edit"
        case ("split", 2): target = "expense.split"
        case ("repayment", 0): target = "friends.person"
        case ("repayment", 1): target = "friend.repay"
        case ("recurring", 0): target = "recurring.add"
        case ("applePay", 0): target = "automation.apple"
        case ("tng", 0): target = "automation.tng"
        case ("tng", 6): target = "tng.incoming"
        case ("settings", 0): target = "settings.appearance"
        case ("backup", 0): target = "settings.backup"
        default: return [] // Reading and reviewing are not tap actions.
        }
        return [GuideGesture(targetID: target, position: 0.5, swipe: false)]
    }
}

private enum GuideCue {
    static func text(_ screen: GuideScreen) -> String {
        switch screen {
        case .overview: return tr("点“记一笔”，开始记录消费。", "Tap Add expense to start an entry.", "Ketik Tambah belanja untuk bermula.")
        case .newExpense: return tr("填写商家、金额和日期，这就是一笔消费。", "Enter the merchant, amount and date for this expense.", "Isi peniaga, amaun dan tarikh belanja.")
        case .ledger: return tr("在账本找到记录，可打开查看或筛选。", "Find an entry in Ledger to review or filter.", "Cari rekod dalam Lejar untuk semak atau tapis.")
        case .filter: return tr("用金额范围和分账状态缩小查找范围。", "Narrow the results by amount and split status.", "Tapis hasil mengikut amaun dan status pembahagian.")
        case .receiptEntry: return tr("在概览的“更多工具”打开“收据分账”。", "Open Receipt split in Overview’s More tools.", "Buka Bahagi resit dalam Alat lain di Ringkasan.")
        case .receipt(0): return tr("选择一张完整的收据照片。", "Choose a photo of the full receipt.", "Pilih foto resit yang lengkap.")
        case .receipt(1): return tr("先核对日期、税费和实付总额。", "Check the date, charges and paid total first.", "Semak tarikh, caj dan jumlah akhir dahulu.")
        case .receipt(2): return tr("添加一起吃的朋友，选择按菜品分账。", "Add your friends and choose to split by items.", "Tambah rakan dan pilih bahagi mengikut item.")
        case .receipt(3): return tr("每道菜分给吃它的人，共享菜可选多人。", "Assign each dish to the people who had it.", "Agihkan setiap hidangan kepada pemakannya.")
        case .receipt(4): return tr("这里显示每人应付，税费已计入。", "Each person's total includes their share of charges.", "Jumlah setiap orang termasuk bahagian cajnya.")
        case .expenseDetail: return tr("先查看账目详情，再点“编辑”。", "Review the entry, then tap Edit.", "Semak rekod, kemudian ketik Edit.")
        case .editExpense: return tr("开启这笔消费的“朋友分账”。", "Enable splitting for this expense.", "Aktifkan pembahagian untuk belanja ini.")
        case .splitEditor: return tr("填好朋友份额，剩下的就是你的消费。", "Set each friend's share; the remainder is yours.", "Tetapkan bahagian rakan; bakinya milik anda.")
        case .friends: return tr("点朋友，查看他还欠多少。", "Tap a friend to see their outstanding balance.", "Ketik rakan untuk melihat baki hutangnya.")
        case .friendDetail: return tr("收到 RM 10 后，记录这次收款。", "After receiving RM 10, record the repayment.", "Selepas menerima RM 10, rekod bayaran itu.")
        case .repaymentDone: return tr("已收 RM 10，Amy 剩余欠款为 RM 7.49。", "RM 10 received. Amy now owes RM 7.49.", "RM 10 diterima. Amy masih berhutang RM 7.49.")
        case .recurring: return tr("新增一项固定消费。", "Add a recurring expense.", "Tambah belanja berulang.")
        case .recurringEditor: return tr("设置金额、周期和开始日期。", "Set its amount, frequency and start date.", "Tetapkan amaun, kekerapan dan tarikh mula.")
        case .applePay(let step): return shortcut(step, tng: false)
        case .tngSetup(let step): return shortcut(step, tng: true)
        case .automation: return tr("选择你要设置的自动记账方式。", "Choose the recording method to set up.", "Pilih cara rekod yang ingin disediakan.")
        case .tng: return tr("点开待确认的收款通知。", "Open the incoming payment for review.", "Buka wang masuk untuk semakan.")
        case .tngIncoming: return tr("收到的钱显示＋，再确认这笔钱的用途。", "Incoming money shows +. Confirm what it is for.", "Wang masuk bertanda +. Sahkan tujuannya.")
        case .settings: return tr("从设置打开你需要的选项。", "Open the option you need in Settings.", "Buka pilihan yang diperlukan dalam Tetapan.")
        case .appearance: return tr("在这里选择语言与浅色、深色外观。", "Choose your language and light or dark appearance.", "Pilih bahasa serta paparan cerah atau gelap.")
        case .savedExpense: return tr("保存后，新消费会出现在账本。", "After saving, the new expense appears in your ledger.", "Selepas disimpan, belanja baharu muncul dalam lejar.")
        case .filteredLedger: return tr("应用筛选后，只显示符合条件的记录。", "After applying filters, only matching entries appear.", "Selepas menapis, hanya rekod sepadan dipaparkan.")
        case .backups: return tr("完整备份用于恢复，CSV 用于查看账单。", "Use a full backup to restore; CSV to view statements.", "Sandaran penuh untuk pemulihan; CSV untuk penyata.")
        default: return tr("查看结果，再左右滑动浏览其他主题。", "Review the result, then swipe to another topic.", "Semak hasil, kemudian leret ke topik lain.")
        }
    }
    private static func shortcut(_ step: Int, tng: Bool) -> String {
        switch step {
        case 0: return tr("第一步：在快捷指令添加月记动作。", "1. Add YueJi's action in Shortcuts.", "1. Tambah tindakan YueJi dalam Pintasan.")
        case 1: return tng ? tr("第二步：选通知触发器，来源设为 TNG。", "2. Choose a notification trigger from TNG.", "2. Pilih pencetus notifikasi daripada TNG.") : tr("第二步：选交易触发器和付款卡片。", "2. Choose a transaction trigger and your card.", "2. Pilih pencetus transaksi dan kad anda.")
        case 2: return tr("第三步：把输入变量接到月记参数。", "3. Connect the input variables to YueJi's fields.", "3. Sambungkan pemboleh ubah ke medan YueJi.")
        case 3: return tr("第四步：按系统选项允许自动运行。", "4. Enable automatic runs using the system options.", "4. Benarkan jalan automatik mengikut pilihan sistem.")
        default: return tr("最后：回月记核对运行结果。演示不会替你启用。", "Finally, check YueJi's activity log. This demo does not enable it.", "Akhir sekali, semak log YueJi. Demo ini tidak mengaktifkannya.")
        }
    }
}

private struct GuideTouchIndicator: View {
    let phase: Int
    let action: GuideGesture
    let measured: CGRect
    private var destination: CGPoint {
        CGPoint(x: measured.midX, y: measured.minY + measured.height * action.position)
    }
    var body: some View {
        ZStack {
            if phase == 2 && !action.swipe {
                Circle().stroke(.blue.opacity(0.55), lineWidth: 2)
                    .frame(width: 62, height: 62)
                    .transition(.scale.combined(with: .opacity))
            }
            Circle().fill(.white.opacity(0.70))
                .frame(width: 44, height: 44)
                .overlay(Circle().strokeBorder(.gray.opacity(0.32), lineWidth: 1))
                .shadow(color: .black.opacity(0.14), radius: 9, y: 3)
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
                    GuideDemoScene(screen: screen)
                        .id(screen)
                        .transition(reduceMotion ? .identity : .asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
                    if let action, gesturePhase > 0, let measured = measuredTargets[action.targetID], measured.height > 0 {
                        GuideTouchIndicator(phase: gesturePhase, action: action, measured: measured)
                            .transition(reduceMotion ? .identity : .opacity.combined(with: .scale(scale: 0.7)))
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


// A read-only Tips scene. It borrows the app's labels and workflow, while keeping
// editor toolbars, sheets, keyboards and system menus out of the demonstration.
private struct GuideDemoScene: View {
    let screen: GuideScreen
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var title: String {
        switch screen {
        case .overview: return tr("概览", "Overview", "Ringkasan")
        case .receiptEntry: return tr("更多工具", "More tools", "Alat lain")
        case .expenseDetail: return tr("账目详情", "Entry details", "Butiran rekod")
        case .newExpense, .editExpense, .splitEditor: return tr("记账 / 分账", "Expense / split", "Belanja / pembahagian")
        case .ledger, .savedExpense, .filteredLedger: return tr("账本", "Ledger", "Lejar")
        case .filter: return tr("筛选", "Filters", "Penapis")
        case .receipt(_): return tr("收据分账", "Receipt split", "Bahagi resit")
        case .friends: return tr("朋友分账", "Shared expenses", "Belanja dikongsi")
        case .friendDetail, .repayment, .repaymentDone: return tr("欠款明细", "Balance details", "Butiran baki")
        case .recurring, .recurringEditor: return tr("固定消费", "Recurring expenses", "Belanja berulang")
        case .automation: return tr("自动记账", "Automatic recording", "Rekod automatik")
        case .applePay(_), .tngSetup(_): return tr("快捷指令 · 设置示意", "Shortcuts · illustration", "Pintasan · ilustrasi")
        case .tng, .tngIncoming: return tr("TNG 通知记录", "TNG inbox", "Peti TNG")
        case .settings: return tr("设置", "Settings", "Tetapan")
        case .appearance: return tr("外观与语言", "Appearance & language", "Paparan & bahasa")
        case .backups: return tr("备份与导出", "Backups & export", "Sandaran & eksport")
        default: return tr("月记", "YueJi", "YueJi")
        }
    }
    private var tab: Int? {
        switch screen {
        case .overview: return 0
        case .ledger, .savedExpense, .filteredLedger: return 1
        case .recurring: return 2
        case .friends: return 3
        case .settings: return 4
        default: return nil
        }
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if tab == nil { Image(systemName: "chevron.left").frame(width: 42, alignment: .leading) }
                Spacer(minLength: 0)
                Text(title).font(.system(size: 17, weight: .semibold)).lineLimit(1)
                Spacer(minLength: 0)
                if tab == nil { Color.clear.frame(width: 42) }
            }
            .padding(.horizontal, 18).frame(height: 52)
            .background(Color(uiColor: .systemBackground))
            ScrollViewReader { reader in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) { content }
                        .padding(.horizontal, 20).padding(.vertical, 18)
                }
                .scrollIndicators(.hidden)
                .task(id: screen) {
                    if screen == .receiptEntry {
                        do { try await Task.sleep(for: .milliseconds(360)) } catch { return }
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.8)) {
                            reader.scrollTo("demo.receipt", anchor: .center)
                        }
                    } else if screen == .receipt(3) {
                        do { try await Task.sleep(for: .seconds(3)) } catch { return }
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.7)) {
                            reader.scrollTo("demo.items", anchor: .center)
                        }
                    }
                }
            }
            if let tab { tabs(selected: tab) }
        }
        .frame(width: 390, height: 740)
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private func heading(_ text: String) -> some View {
        Text(text).font(.system(size: 28, weight: .bold)).frame(maxWidth: .infinity, alignment: .leading)
    }
    private func section<Content: View>(_ title: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title { Text(title).font(.footnote.weight(.semibold)).foregroundStyle(.secondary).padding(.leading, 4) }
            VStack(spacing: 0) { content() }
                .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 18))
        }
    }
    private func row(_ name: String, _ value: String = "", icon: String = "", target: String? = nil, tint: Color = .blue) -> some View {
        HStack(spacing: 12) {
            if !icon.isEmpty {
                Image(systemName: icon).font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(tint).frame(width: 26)
            }
            Text(name).lineLimit(2)
            Spacer(minLength: 10)
            if !value.isEmpty { Text(value).foregroundStyle(.secondary).lineLimit(2).multilineTextAlignment(.trailing) }
        }
        .font(.system(size: 20))
        .padding(.horizontal, 15).frame(minHeight: 53)
        .guideTarget(target ?? "demo.decorative")
    }
    private func divider() -> some View { Divider().padding(.leading, 16) }
    private func tabs(selected: Int) -> some View {
        HStack {
            ForEach(0..<5) { index in
                let icons = ["chart.pie.fill", "list.bullet.rectangle", "repeat", "person.2.fill", "slider.horizontal.3"]
                let labels = [tr("概览", "Overview", "Ringkasan"), tr("账本", "Ledger", "Lejar"), tr("固定", "Recurring", "Berulang"), tr("分账", "Split", "Bahagi"), tr("设置", "Settings", "Tetapan")]
                VStack(spacing: 4) {
                    Image(systemName: icons[index]).font(.system(size: 19))
                    Text(labels[index]).font(.system(size: 10))
                }
                .foregroundStyle(selected == index ? Color.blue : Color.secondary)
                .frame(maxWidth: .infinity)
            }
        }.padding(.top, 10).frame(height: 62).background(Color(uiColor: .systemBackground))
    }
    @ViewBuilder private var content: some View {
        switch screen {
        case .overview:
            heading(tr("每一笔，心里有数", "A clearer everyday", "Belanja lebih jelas"))
            section {
                row(tr("本月 · 我的实际消费", "This month · my spending", "Bulan ini · belanja saya"), "RM 85.82", icon: "chart.pie.fill")
                divider(); row(tr("预算剩余", "Budget remaining", "Baki bajet"), "RM 914.18")
            }
            section(tr("最近账目", "Recent entries", "Rekod terkini")) { row("Lunch Cafe", "RM 29.15"); divider(); row("Coffee", "RM 12.50") }
            section { row(tr("储蓄目标", "Savings goals", "Matlamat simpanan"), icon: "target") }
            section { row(tr("更多工具", "More tools", "Alat lain"), icon: "square.grid.2x2") }
            section { row(tr("记一笔", "Add expense", "Tambah belanja"), icon: "plus", target: "dashboard.add") }
        case .receiptEntry:
            heading(tr("更多工具", "More tools", "Alat lain"))
            section(tr("日常工具", "Everyday tools", "Alat harian")) {
                row(tr("收据分账", "Receipt split", "Bahagi resit"), icon: "doc.viewfinder", target: "dashboard.receipt").id("demo.receipt")
                divider(); row(tr("自动记账", "Automatic recording", "Rekod automatik"), "Apple Pay · TNG", icon: "bolt.fill")
            }
        case .expenseDetail:
            heading(tr("账目详情", "Entry details", "Butiran rekod"))
            section { row("Lunch Cafe", "RM 29.15"); divider(); row(tr("日期", "Date", "Tarikh"), dateLabel(Date())) }
            section { row(tr("编辑", "Edit", "Edit"), icon: "pencil", target: "detail.edit"); divider(); row(tr("删除", "Delete", "Padam"), icon: "trash", tint: .red) }
        case .newExpense:
            heading(tr("记一笔", "Add expense", "Tambah belanja"))
            section(tr("实际付款", "Payment", "Bayaran")) {
                row(tr("商户 / 行程", "Merchant / trip", "Peniaga / perjalanan"), "Lunch Cafe")
                divider(); row(tr("原币金额", "Amount", "Amaun"), "RM 18.00")
                divider(); row(tr("日期", "Date", "Tarikh"), dateLabel(Date()))
                divider(); row(tr("分类", "Category", "Kategori"), tr("餐饮", "Dining", "Makanan"))
            }
            section { row(tr("朋友分账", "Split with friends", "Bahagi dengan rakan"), "○") }
        case .savedExpense:
            heading(tr("账本", "Your ledger", "Lejar anda"))
            section { row("Lunch Cafe", "RM 18.00", icon: "checkmark.circle.fill", tint: .green) }
        case .filteredLedger:
            heading(tr("账本", "Your ledger", "Lejar anda"))
            section { row(tr("餐饮", "Dining", "Makanan"), icon: "line.3.horizontal.decrease.circle"); divider(); row("Lunch Cafe", "RM 29.15") }
        case .ledger:
            heading(tr("账本", "Your ledger", "Lejar anda"))
            section {
                row(tr("本月 · 我的消费", "This month · my spending", "Bulan ini · belanja saya"), "RM 85.82")
                divider()
                row(tr("筛选", "Filter", "Tapis"), icon: "line.3.horizontal.decrease.circle", target: "ledger.filter")
            }
            section(tr("今天", "Today", "Hari ini")) {
                row("Lunch Cafe", "RM 46.64", icon: "fork.knife", target: "ledger.expense")
                divider(); row("Shopee", "RM 56.67", icon: "bag")
            }
        case .filter:
            heading(tr("查找账目", "Find entries", "Cari rekod"))
            section {
                row(tr("商户、分类", "Merchant, category", "Peniaga, kategori"), tr("餐饮", "Dining", "Makanan"), icon: "magnifyingglass")
                divider(); row(tr("金额范围", "Amount range", "Julat amaun"), "RM 0 – 100")
                divider(); row(tr("分账状态", "Split status", "Status pembahagian"), tr("全部", "All", "Semua"))
            }
        case .receipt(let step): receiptContent(step)
        case .editExpense, .splitEditor:
            heading(tr("朋友分账", "Split with friends", "Bahagi bersama rakan"))
            section(tr("实际付款", "Payment", "Bayaran")) {
                row("Lunch Cafe", "RM 46.64")
                divider(); row(tr("朋友分账", "Split with friends", "Bahagi dengan rakan"), screen == .splitEditor ? "●" : "○", target: "expense.split")
            }
            if screen == .splitEditor {
                section {
                    row(tr("分摊方式", "Split method", "Cara pembahagian"), tr("自定", "Custom", "Tersuai"))
                    divider(); row("Amy", "RM 17.49")
                    divider(); row(tr("我的份额", "My share", "Bahagian saya"), "RM 29.15")
                }
            }
        case .friends:
            heading(tr("一起吃，各自分", "Shared, fairly", "Kongsi dengan adil"))
            section {
                row(tr("朋友还欠你", "Friends owe you", "Rakan berhutang"), "RM 17.49")
            }
            section(tr("未结清", "Outstanding", "Belum selesai")) {
                row("Amy", "RM 17.49", icon: "person.crop.circle", target: "friends.person")
            }
        case .friendDetail:
            heading("Amy")
            section {
                row(tr("待收", "Receivable", "Belum diterima"), "RM 17.49")
                divider(); row(tr("本次收到", "Received now", "Diterima kini"), "RM 10.00")
                divider(); row(tr("记录收款", "Record money received", "Rekod wang diterima"), icon: "arrow.down.circle", target: "friend.repay")
            }
        case .repayment:
            heading(tr("记录还款", "Record repayment", "Rekod bayaran"))
            section {
                row("Amy", "RM 17.49")
                divider(); row(tr("本次收到", "Received now", "Diterima kini"), "RM 10.00")
                divider(); row(tr("收到日期", "Date received", "Tarikh diterima"), dateLabel(Date()))
                divider(); row(tr("收款后尚欠", "Balance after receipt", "Baki selepas penerimaan"), "RM 7.49")
            }
        case .repaymentDone:
            heading("Amy")
            section {
                row(tr("待收", "Receivable", "Belum diterima"), "RM 7.49")
                divider(); row(tr("本次已收", "Received", "Diterima"), "RM 10.00", icon: "checkmark.circle", tint: .green)
            }
        case .recurring:
            heading(tr("固定消费", "Recurring expenses", "Belanja berulang"))
            section {
                row(tr("本月安排", "This month's plan", "Rancangan bulan ini"), icon: "calendar")
                divider(); row("Internet", "RM 99.00", icon: "repeat")
                divider(); row(tr("添加固定消费", "Add recurring expense", "Tambah belanja berulang"), icon: "plus", target: "recurring.add")
            }
        case .recurringEditor:
            heading(tr("新增固定消费", "Add recurring expense", "Tambah belanja berulang"))
            section {
                row(tr("名称", "Name", "Nama"), "Internet")
                divider(); row(tr("金额", "Amount", "Amaun"), "RM 99.00")
                divider(); row(tr("周期", "Frequency", "Kekerapan"), tr("每月", "Monthly", "Bulanan"))
                divider(); row(tr("首次日期", "Start date", "Tarikh mula"), dateLabel(Date()))
            }
        case .automation:
            heading(tr("自动记账", "Automatic recording", "Rekod automatik"))
            section {
                row("Apple Pay", tr("付款后记录", "Record after payment", "Rekod selepas bayaran"), icon: "creditcard", target: "automation.apple")
                divider(); row("TNG eWallet", tr("通知接入", "Notifications", "Notifikasi"), icon: "bell.badge", target: "automation.tng")
            }
        case .applePay(let step): shortcut(provider: .applePay, step: step)
        case .tngSetup(let step): shortcut(provider: .tng, step: step)
        case .tng:
            heading(tr("TNG 待确认", "TNG to review", "TNG perlu disemak"))
            section {
                row("Amy", "+ RM 10.00", icon: "arrow.down.circle", target: "tng.incoming", tint: .green)
                divider(); row("Lunch Cafe", "− RM 18.00", icon: "arrow.up.circle")
            }
        case .tngIncoming:
            heading(tr("收到款项", "Incoming money", "Wang masuk"))
            section {
                row("Amy", "+ RM 10.00", icon: "arrow.down.circle", tint: .green)
                divider(); row(tr("朋友还款", "Friend repayment", "Bayaran rakan"), icon: "person.2")
                divider(); row(tr("其他收入", "Other income", "Pendapatan lain"), icon: "plus.circle")
            }
        case .settings:
            heading(tr("让月记更适合你", "Make it yours", "Sesuaikan YueJi"))
            section {
                row(tr("外观与语言", "Appearance & language", "Paparan dan bahasa"), icon: "circle.lefthalf.filled", target: "settings.appearance")
                divider(); row(tr("提醒与通知", "Reminders & notifications", "Peringatan"), icon: "bell")
            }
            section {
                row(tr("自动记账", "Automatic recording", "Rekod automatik"), icon: "bolt")
                divider(); row(tr("备份与导出", "Backups & export", "Sandaran & eksport"), icon: "externaldrive", target: "settings.backup")
            }
        case .appearance:
            heading(tr("外观与语言", "Appearance & language", "Paparan dan bahasa"))
            section {
                row(tr("语言", "Language", "Bahasa"), tr("简体中文", "Chinese", "Cina"))
                divider(); row(tr("外观", "Appearance", "Paparan"), tr("跟随系统", "System", "Sistem"))
            }
        case .backups:
            heading(tr("备份与导出", "Backups & export", "Sandaran & eksport"))
            section {
                row(tr("完整备份", "Full backup", "Sandaran penuh"), "JSON", icon: "externaldrive")
                divider(); row(tr("导出账单", "Export statements", "Eksport penyata"), "CSV", icon: "square.and.arrow.up")
            }
        default: heading(tr("月记", "YueJi", "YueJi"))
        }
    }
    @ViewBuilder private func receiptContent(_ step: Int) -> some View {
        switch step {
        case 0:
            heading(tr("一张收据，分得清楚", "One receipt. Clear shares.", "Satu resit, bahagian jelas."))
            section {
                row(tr("扫描收据", "Scan receipt", "Imbas resit"), icon: "doc.viewfinder")
                divider()
                row(tr("选择收据照片", "Choose receipt photo", "Pilih foto resit"), icon: "photo", target: "receipt.photo")
            }
        case 1:
            heading(tr("核对收据", "Review receipt", "Semak resit"))
            section {
                row(tr("商家", "Merchant", "Peniaga"), "RESTAURANT KHAN JEE", target: "receipt.merchant")
                divider(); row(tr("消费日期", "Receipt date", "Tarikh resit"), "03/11/2025", target: "receipt.date")
                divider(); row(tr("商品小计", "Items subtotal", "Subjumlah item"), "RM 208.00")
                divider(); row(tr("税费（SST）", "Tax (SST)", "Cukai SST"), "RM 13.73")
                divider(); row(tr("服务费", "Service charge", "Caj perkhidmatan"), "RM 20.80")
                divider(); row(tr("舍入调整", "Rounding", "Pembundaran"), "RM 0.02")
                divider(); row(tr("实付总额", "Paid total", "Jumlah akhir"), "RM 242.55", target: "receipt.total")
            }
        case 2:
            heading(tr("谁一起吃？", "Who is sharing?", "Siapa berkongsi?"))
            section {
                row(tr("包括我", "Include me", "Termasuk saya"), "✓")
                divider(); row(tr("朋友姓名", "Friend's name", "Nama rakan"), "Amy")
                divider(); row(tr("添加朋友", "Add friend", "Tambah rakan"), icon: "person.badge.plus", target: "receipt.people")
                divider(); row(tr("怎样分账", "Split method", "Cara bahagi"), tr("按各自点的菜", "By items", "Ikut item"))
            }
        case 3:
            heading(tr("菜品明细", "Items", "Butiran item"))
            section {
                row("DAAL CHANA FRY", "RM 25.00", target: "receipt.item0")
                divider(); row("PLAIN NAAN", "RM 33.00", target: "receipt.item1")
                divider(); row("PALAK PANEER", "RM 50.00")
                divider(); row("CHICKEN CHEESY KOFTA", "RM 30.00")
                divider(); row("DAAL MASH FRY", "RM 25.00")
                divider(); row("CH TANDOORI LEG", "RM 30.00")
                divider(); row("PLAIN PARATHA", "RM 5.00")
                divider(); row("FRESH LIME JUICE", "RM 10.00")
                divider(); row(tr("谁吃这道菜？", "Who had this?", "Siapa makan ini?"), "Amy", icon: "person.2")
                divider(); row(tr("补上漏掉的商品", "Add missing item", "Tambah item tertinggal"), icon: "plus", target: "receipt.items")
                    .id("demo.items")
            }
        case 4:
            heading(tr("每人应付", "Each person pays", "Bayaran setiap orang"))
            section {
                row(tr("商品合计", "Items total", "Jumlah item"), "RM 208.00")
                divider(); row(tr("税费和服务费", "Tax and service", "Cukai dan caj"), "RM 34.53")
                divider(); row(tr("舍入调整", "Rounding", "Pembundaran"), "RM 0.02")
            }
            section {
                row(tr("我", "Me", "Saya"), "RM 125.94", icon: "person.fill")
                divider(); row("Amy", "RM 116.61", icon: "person.fill")
                divider(); row(tr("实付总额", "Paid total", "Jumlah akhir"), "RM 242.55")
            }
        default: EmptyView()
        }
    }
    @ViewBuilder private func shortcut(provider: ShortcutSetupProvider, step: Int) -> some View {
        let action = provider == .applePay ? tr("记录 Apple Pay 支出", "Record Apple Pay expense", "Rekod belanja Apple Pay") : tr("记录 TNG 通知", "Record TNG notification", "Rekod notifikasi TNG")
        heading(provider == .applePay ? "Apple Pay" : "TNG eWallet")
        section(tr("快捷指令设置示意", "Shortcuts setup illustration", "Ilustrasi tetapan Pintasan")) {
            VStack(spacing: 0) {
                switch step {
                case 0:
                    row(tr("快捷指令", "Shortcuts", "Pintasan"), "+", icon: "square.stack.3d.up")
                    divider(); row(tr("搜索操作", "Search actions", "Cari tindakan"), "月记 / YueJi", icon: "magnifyingglass")
                    divider(); row(action, icon: "bolt")
                case 1:
                    row(tr("编辑", "Edit", "Edit"), tr("自动化", "Automation", "Automasi"), icon: "slider.horizontal.3")
                    divider(); row(tr("触发方式", "Trigger", "Pencetus"), provider == .applePay ? tr("交易", "Transaction", "Transaksi") : tr("通知", "Notification", "Notifikasi"), icon: provider == .applePay ? "creditcard" : "bell")
                    divider(); row(provider == .applePay ? tr("选择卡片", "Choose card", "Pilih kad") : "App", provider == .applePay ? "Apple Pay" : "TNG eWallet")
                case 2:
                    row(action, icon: "square.stack.3d.up")
                    divider(); row(provider == .applePay ? tr("金额", "Amount", "Amaun") : tr("通知正文", "Notification body", "Teks notifikasi"), tr("输入变量", "Input variable", "Pemboleh ubah"))
                    divider(); row(provider == .applePay ? tr("商户", "Merchant", "Peniaga") : tr("通知时间", "Notification date", "Tarikh notifikasi"), tr("输入变量", "Input variable", "Pemboleh ubah"))
                case 3:
                    row(tr("编辑", "Edit", "Edit"), "ⓘ", icon: "slider.horizontal.3")
                    divider(); row(tr("隐私", "Privacy", "Privasi"), tr("锁定时允许运行", "Allow Running When Locked", "Benarkan semasa dikunci"), icon: "lock.shield")
                    divider(); row(tr("系统请求访问月记时", "When access is requested", "Apabila akses diminta"), tr("允许", "Allow", "Benarkan"))
                default:
                    row(provider == .applePay ? "Apple Pay" : "TNG eWallet", tr("传入资料", "Pass event data", "Hantar data"), icon: "arrow.down")
                    divider(); row(tr("月记运行记录", "YueJi activity log", "Log aktiviti YueJi"), icon: "list.bullet.rectangle")
                    divider(); row(tr("核对金额与商户", "Check amount and merchant", "Semak amaun dan peniaga"), icon: "checkmark.circle")
                }
            }.guideTarget("shortcut.steps")
        }
    }
}


private struct YueJiEntrance: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var entered = false
    func body(content: Content) -> some View {
        content.opacity(entered || reduceMotion ? 1 : 0)
            .offset(y: entered || reduceMotion ? 0 : 7)
            .onAppear { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.32)) { entered = true } }
    }
}
private struct OpeningAnimationView: View {
    let compact: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var gathered = false
    @State private var revealed = false
    @State private var titled = false
    private let night = Color(red: 0.025, green: 0.045, blue: 0.11)
    var body: some View {
        ZStack {
            night.ignoresSafeArea()
            RadialGradient(colors: [Color.blue.opacity(revealed ? 0.28 : 0.04), night], center: .center, startRadius: 12, endRadius: 310).ignoresSafeArea()
            VStack(spacing: 30) {
                ZStack {
                    Circle().fill(Color.cyan.opacity(0.15)).frame(width: 160, height: 160).blur(radius: 30)
                        .scaleEffect(revealed ? 1.15 : 0.45).opacity(revealed ? 1 : 0)
                    if !compact && !reduceMotion {
                        ForEach(0..<24, id: \.self) { index in
                            let angle = Double(index) * .pi * 2 / 24
                            Circle().fill(Color(red: 0.7, green: 0.86, blue: 1))
                                .frame(width: index % 3 == 0 ? 4 : 2, height: index % 3 == 0 ? 4 : 2)
                                .offset(x: cos(angle) * (gathered ? 42 : 145), y: sin(angle) * (gathered ? 42 : 145))
                                .opacity(revealed ? 0 : 0.85)
                        }
                    }
                    Circle().trim(from: 0.08, to: revealed ? 0.92 : 0.08)
                        .stroke(AngularGradient(colors: [.clear, .cyan.opacity(0.65), .white.opacity(0.8), .clear], center: .center), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                        .frame(width: 150, height: 150).rotationEffect(.degrees(-110))
                    Image(systemName: "moon.fill")
                        .font(.system(size: 76, weight: .ultraLight))
                        .foregroundStyle(LinearGradient(colors: [.white, Color(red: 0.62, green: 0.8, blue: 1)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .shadow(color: .cyan.opacity(0.3), radius: 20)
                        .scaleEffect(revealed ? 1 : 0.82).opacity(revealed || reduceMotion ? 1 : 0)
                }.frame(width: 280, height: 230)
                VStack(spacing: 12) {
                    Text("月记").font(.system(size: 34, weight: .medium, design: .rounded)).tracking(8)
                    Text("YUEJI").font(.system(size: 10, weight: .medium)).tracking(6).foregroundStyle(.white.opacity(0.55))
                }.foregroundStyle(.white).opacity(titled || reduceMotion ? 1 : 0)
                    .offset(y: titled || reduceMotion ? 0 : 8)
            }.offset(y: -24)
        }
        .task {
            if reduceMotion { revealed = true; titled = true; return }
            if compact {
                withAnimation(.easeOut(duration: 0.4)) { revealed = true; titled = true }
                return
            }
            withAnimation(.easeInOut(duration: 0.55)) { gathered = true }
            do { try await Task.sleep(for: .milliseconds(380)) } catch { return }
            withAnimation(.spring(response: 0.65, dampingFraction: 0.88)) { revealed = true }
            UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.5)
            do { try await Task.sleep(for: .milliseconds(270)) } catch { return }
            withAnimation(.easeOut(duration: 0.45)) { titled = true }
        }
        .accessibilityElement(children: .ignore).accessibilityLabel("月记 YueJi")
    }
}
