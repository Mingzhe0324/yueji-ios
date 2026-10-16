import SwiftUI
import UniformTypeIdentifiers
import UIKit

private let ink = Color(uiColor: .systemBlue)
enum YueJiMotion {
    static let standard = Animation.smooth(duration: 0.24)
    static let detail = Animation.smooth(duration: 0.32)
    static let month = Animation.smooth(duration: 0.42)
    static let meter = Animation.smooth(duration: 0.45)
    static let rows = Animation.smooth(duration: 0.34)
    static let banner = Animation.spring(duration: 0.42, bounce: 0.12)
    static let tone = Animation.easeInOut(duration: 0.55)
}

struct EditorSaveLabel: View {
    let saving: Bool
    var body: some View {
        Text(tr("保存", "Save", "Simpan"))
            // Preserve the label's layout while the async save is running.
            .opacity(saving ? 0 : 1)
            .overlay {
                if saving { ProgressView().controlSize(.small).allowsHitTesting(false) }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(saving ? tr("正在保存", "Saving", "Menyimpan") : tr("保存", "Save", "Simpan"))
    }
}

extension View {
    func ledgerGlass() -> some View { modifier(YueJiGlassSurface()) }

}
struct PageIntroduction: View {
    @Environment(\.locale) private var uiLocale
    let title: String
    let subtitle: String
    var body: some View {
        let _ = uiLocale.identifier
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.largeTitle.weight(.bold)).fixedSize(horizontal: false, vertical: true)
            Text(subtitle).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
            .padding(.horizontal, 20)
    }
}
private struct YueJiBarAppearance: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        content
            // Keep native chrome in the same resolved theme as the page. A
            // visible background keeps the requested bar scheme in effect at
            // scroll edges as well as when content is beneath the bar.
            .toolbarColorScheme(scheme, for: .navigationBar, .tabBar)
            .toolbarBackground(.visible, for: .navigationBar, .tabBar)
    }
}
private struct YueJiListSurface: ViewModifier {
    func body(content: Content) -> some View {
        content.listStyle(.insetGrouped)
            .scrollDismissesKeyboard(.interactively)
            .scrollContentBackground(.hidden)
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .modifier(YueJiBarAppearance())
            .modifier(YueJiScrollEdge())
    }
}
private struct YueJiScrollEdge: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 26.0, *), !reduceTransparency {
            // Let the system dissolve scrolling content beneath floating
            // controls instead of drawing another rectangular material panel.
            content.scrollEdgeEffectStyle(.soft, for: .bottom)
        } else { content }
    }
}
extension View {
    func yuejiListSurface() -> some View { modifier(YueJiListSurface()) }
    func yuejiPageSurface() -> some View {
        scrollDismissesKeyboard(.interactively)
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .modifier(YueJiBarAppearance())
            .modifier(YueJiScrollEdge())
    }
    func yuejiUpdating(_ updating: Bool) -> some View {
        overlay(alignment: .topTrailing) {
            if updating {
                ProgressView().controlSize(.small).padding(12)
                    .accessibilityLabel(tr("正在更新", "Updating", "Mengemas kini"))
                    .allowsHitTesting(false)
            }
        }
    }
    func yuejiSheetSurface() -> some View {
        modifier(YueJiSheetSurface())
    }
}
private struct YueJiSheetSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 26.0, *), !reduceTransparency {
            // Let the system choose the sheet's curvature and material.
            content.presentationDragIndicator(.visible)
                .modifier(YueJiBarAppearance())
        } else if #available(iOS 26.0, *) {
            content.presentationDragIndicator(.visible)
                .presentationBackground(Color(uiColor: .systemGroupedBackground))
                .modifier(YueJiBarAppearance())
        } else {
            content.presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
                .presentationBackground(Color(uiColor: .systemGroupedBackground))
                .modifier(YueJiBarAppearance())
        }
    }
}
private struct YueJiTabBarMotion: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            // Keep tab navigation in its own safe area, away from transaction actions.
            content.tabBarMinimizeBehavior(.never)
        } else { content }
    }
}

private struct YueJiActionBarSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    func body(content: Content) -> some View {
        content.background {
            if reduceTransparency { Color(uiColor: .systemGroupedBackground) }
            // The capsule buttons already provide their own native material.
            // Keep this safe-area spacer clear during normal scrolling.
        }
    }
}

struct MainView: View {
    @Environment(\.locale) private var uiLocale
    @EnvironmentObject var model: LedgerModel
    @Environment(\.scenePhase) private var phase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("completedUsageGuide") private var completedGuide = false
    @AppStorage("openingAnimationEnabled") private var openingEnabled = true
    @State private var showingGuide = false
    @State private var selectedTab = 0
    @State private var showingNewTNG = false
    @State private var pendingInbox = false
    @State private var notificationDestination: NotificationDestination?
    @State private var logoFinished = false
    private func finishLaunchIfReady() {
        withAnimation(reduceMotion ? nil : YueJiMotion.standard) {
            _ = model.finishLaunchIfReady(openingEnabled: openingEnabled, openingFinished: logoFinished)
        }
    }
    private func openPendingNotification() {
        guard model.loaded, model.didFinishLaunch, !showingGuide, !showingNewTNG, notificationDestination == nil,
              model.feedbackOwners.isVisible(nil),
              let value = UserDefaults.standard.dictionary(forKey: "pendingNotificationDestination"),
              let recordID = value["recordID"] as? String, let kind = value["kind"] as? String else { return }
        notificationDestination = NotificationDestination(recordID: recordID, kind: kind, action: value["action"] as? String ?? "view")
        UserDefaults.standard.removeObject(forKey: "pendingNotificationDestination")
    }
    private func openPendingInbox() {
        guard pendingInbox, model.didFinishLaunch, !showingGuide, !showingNewTNG,
              notificationDestination == nil, model.feedbackOwners.isVisible(nil) else { return }
        pendingInbox = false; showingNewTNG = true
    }
    private var savedExpiration: BannerExpirationKey {
        BannerExpirationKey(id: model.savedNotice, paused: phase != .active || !model.didFinishLaunch ||
            model.error != nil || model.activeBanner != .saved ||
            model.bannerInteraction == model.savedNotice?.uuidString)
    }
    private var undoExpirationPaused: Bool {
        phase != .active || !model.didFinishLaunch || model.error != nil
    }
    private var foregroundExpiration: BannerExpirationKey {
        BannerExpirationKey(id: model.foregroundNotice?.id, paused: phase != .active || !model.didFinishLaunch || model.error != nil ||
            model.activeBanner != .foreground ||
            model.bannerInteraction == model.foregroundNotice?.id.uuidString)
    }
    private var importedExpiration: BannerExpirationKey {
        BannerExpirationKey(id: model.newTNGCount > 0 ? model.newTNGToken : nil,
            paused: phase != .active || !model.didFinishLaunch || model.error != nil || model.activeBanner != .imported ||
                model.bannerInteraction == model.newTNGToken.uuidString)
    }
    private var tabs: some View {
        TabView(selection: $selectedTab) {
            DashboardView().ledgerFeedback().modifier(YueJiBarAppearance()).tag(0).tabItem { Label(tr("概览", "Overview", "Ringkasan"), systemImage: "chart.pie.fill") }
            ExpensesView(isActive: selectedTab == 1).ledgerFeedback().modifier(YueJiBarAppearance()).tag(1).tabItem { Label(tr("账本", "Ledger", "Lejar"), systemImage: "list.bullet.rectangle") }
            RecurringView().ledgerFeedback().modifier(YueJiBarAppearance()).tag(2).tabItem { Label(tr("固定", "Recurring", "Berulang"), systemImage: "repeat") }
            FriendsView().ledgerFeedback().modifier(YueJiBarAppearance()).tag(3).tabItem { Label(tr("分账", "Friends", "Rakan"), systemImage: "person.2.fill") }
            SettingsView().ledgerFeedback().modifier(YueJiBarAppearance()).tag(4).tabItem { Label(tr("设置", "Settings", "Tetapan"), systemImage: "slider.horizontal.3") }
        }.tint(ink).modifier(YueJiTabBarMotion())
    }
    var body: some View {
        let _ = uiLocale.identifier
        ZStack {
            Color("LaunchBackground").ignoresSafeArea()
            // Prepare the real screens beneath the opaque logo, before fading it away.
            if model.loaded || model.didFinishLaunch {
                tabs
                    .allowsHitTesting(model.didFinishLaunch)
                    .accessibilityHidden(!model.didFinishLaunch)
                    .transition(.identity)
            } else if !openingEnabled {
                ProgressView(tr("正在读取账本", "Loading ledger", "Memuatkan lejar"))
                    .accessibilityIdentifier("launch.loading")
            }
            if !model.didFinishLaunch && openingEnabled {
                OpeningAnimationView(sound: !model.isPreview) {
                    logoFinished = true
                    finishLaunchIfReady()
                }
                .transition(.opacity).zIndex(1)
            }
        }
            .task(id: phase) {
                if phase != .active { FeedbackSounds.shared.stop() }
                // The first read must run even before scene activation arrives.
                // Later background/inactive transitions do not reload the ledger.
                guard phase == .active || !model.loaded else { return }
                await model.refresh()
                guard !Task.isCancelled else { return }
                finishLaunchIfReady()
                openPendingNotification()
            }
            .onChange(of: model.loaded) { _, loaded in
                if loaded { finishLaunchIfReady() }
            }
            .task(id: model.didFinishLaunch && phase == .active) {
                guard model.didFinishLaunch, phase == .active, !model.isPreview else { return }
                // Defer permission prompts, recovery and network updates until the opening ends.
                await LedgerNotifications.prepareAutomaticResultsAuthorization()
                guard !Task.isCancelled else { return }
                if let error = await AutomationRecovery.shared.retryPending() { model.error = error }
                guard !Task.isCancelled else { return }
                await model.refresh(postRecurring: false)
                openPendingNotification()
                await AutomaticRates.shared.refreshSaved()
                guard !Task.isCancelled else { return }
                await model.refresh(postRecurring: false)
                openPendingNotification()
            }
            .onChange(of: model.didFinishLaunch) { _, finished in
                if finished && !completedGuide && UserDefaults.standard.object(forKey: "pendingNotificationDestination") == nil { showingGuide = true }
                if finished { openPendingNotification() }
            }
            .sheet(isPresented: $showingGuide, onDismiss: { completedGuide = true; openPendingNotification(); openPendingInbox() }) {
                UsageGuideView().yuejiSheetSurface().ledgerFeedback(modal: true)
            }
            .onChange(of: selectedTab) { _, _ in
                FeedbackHaptics.selection()
                model.savedNotice = nil
            }
            .onChange(of: model.feedbackOwners.modals.last) { _, _ in openPendingNotification(); openPendingInbox() }
            .onReceive(NotificationCenter.default.publisher(for: .init("YueJiShowInbox"))) { _ in
                guard !showingNewTNG, !pendingInbox else { return }
                pendingInbox = true; openPendingInbox()
            }
            .onReceive(NotificationCenter.default.publisher(for: .init("YueJiForegroundNotice"))) { event in
                guard let notice = event.object as? ForegroundLedgerNotice else { return }
                model.receiveForegroundNotice(notice)
                Task { await model.refresh(postRecurring: false) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .init("YueJiNotificationDestination"))) { _ in
                Task { await model.refresh(postRecurring: false); openPendingNotification() }
            }
            .sheet(item: $notificationDestination, onDismiss: { openPendingNotification(); openPendingInbox() }) { target in
                NotificationDestinationView(target: target).environmentObject(model)
            }
            .sheet(isPresented: $showingNewTNG, onDismiss: { openPendingNotification() }) {
                NavigationStack { TNGInboxView().toolbar { ToolbarItem(placement: .confirmationAction) {
                    Button(tr("完成", "Done", "Selesai")) { showingNewTNG = false }
                } } }.yuejiSheetSurface().ledgerFeedback(modal: true)
            }
            .task(id: undoExpirationPaused) { model.pauseUndoExpiry(undoExpirationPaused) }
            .task(id: savedExpiration) {
                guard !savedExpiration.paused, let token = savedExpiration.id else { return }
                do { try await Task.sleep(for: .seconds(BannerTiming.duration)) } catch { return }
                model.dismissSavedNotice(id: token)
            }
            .task(id: foregroundExpiration) {
                guard !foregroundExpiration.paused, let token = foregroundExpiration.id else { return }
                do { try await Task.sleep(for: .seconds(BannerTiming.duration)) } catch { return }
                model.dismissForegroundNotice(id: token)
            }
            .task(id: importedExpiration) {
                guard !importedExpiration.paused, let token = importedExpiration.id else { return }
                do { try await Task.sleep(for: .seconds(BannerTiming.duration)) } catch { return }
                model.dismissNewTNG(id: token)
            }
            .alert(tr("月记", "YueJi", "YueJi"), isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
                if !model.loaded {
                    Button(tr("重试", "Retry", "Cuba lagi")) {
                        model.error = nil
                        Task { await model.refresh(); finishLaunchIfReady() }
                    }
                }
                Button(tr("知道了", "OK", "OK"), role: .cancel) { model.error = nil }
            } message: { Text(model.error ?? "") }
    }
}
struct MonthPicker: View {
    @Environment(\.locale) private var uiLocale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Binding var month: Date
    @State private var direction = 1
    private var monthLabel: String { month.formatted(.dateTime.year().month(.wide).locale(Locale(identifier: AppLanguage.localeID))) }
    private var labelTransition: AnyTransition {
        reduceMotion ? .identity : .asymmetric(
            insertion: .opacity.combined(with: .offset(x: CGFloat(direction) * 16)),
            removal: .opacity.combined(with: .offset(x: CGFloat(direction) * -16)))
    }
    @ViewBuilder var body: some View {
        let _ = uiLocale.identifier
        if #available(iOS 26.0, *), !reduceTransparency {
            GlassEffectContainer(spacing: 12) { controls }
        } else {
            controls.padding(3)
                .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
    private var controls: some View {
        HStack(spacing: 0) {
            Button { shift(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                .yuejiSecondaryButton().buttonBorderShape(.circle)
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel(tr("上个月", "Previous month", "Bulan sebelumnya"))
            ZStack {
                Text(monthLabel).font(.subheadline.weight(.semibold))
                    .lineLimit(1).minimumScaleFactor(0.75)
                    .id(monthKey(month)).transition(labelTransition)
            }.animation(reduceMotion ? nil : YueJiMotion.month, value: monthKey(month))
                .frame(maxWidth: .infinity, minHeight: 44).clipped().contentShape(Rectangle())
                .accessibilityElement(children: .ignore).accessibilityLabel(monthLabel)
                .simultaneousGesture(DragGesture(minimumDistance: 25).onEnded { value in
                    let dx = value.translation.width, dy = value.translation.height
                    guard abs(dx) > 45, abs(dx) > abs(dy) * 1.5 else { return }
                    shift(dx < 0 ? 1 : -1)
                })
                .accessibilityHint(tr("左右滑动切换月份", "Swipe left or right to change month", "Leret kiri atau kanan untuk menukar bulan"))
            Button { shift(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                .yuejiSecondaryButton().buttonBorderShape(.circle)
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel(tr("下个月", "Next month", "Bulan seterusnya"))
        }
    }
    private func shift(_ n: Int) {
        direction = n
        FeedbackHaptics.selection()
        // Animate the label, amounts and bars locally; keep page/keyboard layout stable.
        withTransaction(Transaction(animation: nil)) { month = shiftedMonth(month, by: n) }
    }
}
struct DashboardView: View {
    @Environment(\.locale) private var uiLocale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var guideFocus: String? = nil
    @Namespace private var navigationMotion
    @EnvironmentObject var model: LedgerModel
    @SceneStorage("overviewMonth") private var monthTimestamp = Date().timeIntervalSince1970
    @State private var path = NavigationPath()
    @State private var adding = false
    @State private var editingExpense: Expense?
    @State private var deletingExpense: Expense?
    @State private var budgetText = ""
    @State private var budgeting = false
    private var month: Date { model.isPreview ? Date() : Date(timeIntervalSince1970: monthTimestamp) }
    private var monthBinding: Binding<Date> { Binding(get: { month }, set: { monthTimestamp = $0.timeIntervalSince1970 }) }
    @State private var summary = OverviewSnapshot()
    @State private var loadedSummary: LedgerTimelineQuery?
    private var entries: [Expense] { summary.entries }
    private var personal: Int { summary.personal }
    private var budget: Int { model.ledger.budgets[monthKey(month)] ?? 0 }
    private var budgetTint: Color {
        guard budget > 0 else { return ink }
        if personal > budget { return .red }
        return Double(personal) / Double(budget) >= 0.8 ? .orange : ink
    }
    private var budgetStatus: String {
        if personal > budget { return tr("超出预算", "Over budget", "Melebihi bajet") }
        if personal == budget { return tr("已达预算", "Budget reached", "Bajet dicapai") }
        if Double(personal) / Double(max(budget, 1)) >= 0.8 { return tr("接近预算", "Approaching limit", "Menghampiri had") }
        return tr("预算充足", "On track", "Dalam bajet")
    }
    private var budgetSymbol: String {
        personal >= budget ? "exclamationmark.circle.fill" : (Double(personal) / Double(max(budget, 1)) >= 0.8 ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
    }
    private var budgetUsageText: String {
        String(budget > 0 ? personal * 100 / budget : 0) + tr("% 已使用", "% used", "% digunakan")
    }
    private var owed: Int { summary.owed }
    var body: some View {
        let _ = uiLocale.identifier
        let requestedMonth = month
        let summaryQuery = model.overviewQuery(month: requestedMonth)
        NavigationStack(path: $path) {
            ScrollViewReader { guideScroll in
            List {
                Section {
                    MonthPicker(month: monthBinding)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))

                }
                Section {
                    spendingCard
                }
                PendingBookkeepingCard()
                quickActions
                recentCard
                Section {
                    NavigationLink { SavingsGoalsView() } label: {
                        VStack(alignment: .leading, spacing: 12) {
                            Label(tr("储蓄目标", "Savings goals", "Matlamat simpanan"), systemImage: "target").font(.headline)
                            if let goal = model.ledger.savingsGoals.first(where: { $0.balance < $0.target }) ?? model.ledger.savingsGoals.first {
                                HStack { Text(goal.name); Spacer(); Text(money(goal.balance)).monospacedDigit() }
                                ProgressView(value: goal.progress).tint(.blue)
                                    .animation(reduceMotion ? nil : YueJiMotion.standard, value: goal.progress)
                            } else {
                                Text(tr("为想做的事，存下第一笔。", "Set aside your first contribution.", "Asingkan simpanan pertama anda.")).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }.padding(.vertical, 8)
                    }
                }
                balancesCard
                categoriesCard
                Section {
                    NavigationLink { OverviewToolsView(month: month) } label: {
                        Label(tr("更多工具", "More tools", "Alat lain"), systemImage: "square.grid.2x2")
                    }
                }
            }.yuejiListSurface()
            .navigationDestination(for: LedgerExpenseDestination.self) { destination in
                ExpenseDetailView(id: destination.id, embeddedInNavigation: true)
                    .expenseCardDestination(id: destination.id, namespace: navigationMotion)
            }
            .task(id: summaryQuery) {
                guard loadedSummary != summaryQuery else { return }
                do {
                    let fresh = try await model.preparedOverview(month: requestedMonth, query: summaryQuery)
                    guard !Task.isCancelled, model.overviewQuery(month: month) == summaryQuery else { return }
                    // Animate the completed snapshot, never a stale/intermediate month.
                    let changingMonth = loadedSummary.map { $0.month != summaryQuery.month } ?? false
                    let changingEmptyState = loadedSummary != nil && (summary.entries.isEmpty != fresh.entries.isEmpty)
                    let returningRows = model.restoredFeedback.map {
                        $0.date.timeIntervalSinceNow > -3 && !$0.expenseIDs.intersection(Set(fresh.entries.map(\.id))).subtracting(Set(summary.entries.map(\.id))).isEmpty
                    } ?? false
                    withAnimation(!reduceMotion && (changingMonth || changingEmptyState || returningRows) ? YueJiMotion.month : nil) {
                        summary = fresh; loadedSummary = summaryQuery
                    }
                } catch is CancellationError { return }
                catch { model.error = error.localizedDescription }
            }
            .task(id: guideFocus) {
                guard model.isPreview, let guideFocus else { return }
                do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
                withAnimation(.easeInOut(duration: 0.85)) { guideScroll.scrollTo(guideFocus, anchor: .center) }
            }
            .navigationTitle(tr("概览", "Overview", "Ringkasan")).navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        OverviewToolsView(month: month).yuejiZoom(id: "overview-tools", namespace: navigationMotion)
                    } label: {
                        Image(systemName: "ellipsis").yuejiZoomSource(id: "overview-tools", namespace: navigationMotion)
                    }
                        .accessibilityLabel(tr("更多工具", "More tools", "Alat lain"))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { guard !adding else { return }; adding = true } label: {
                        Image(systemName: "plus").frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel(tr("记一笔", "Add entry", "Tambah rekod"))
                    .accessibilityIdentifier("overview.manualEntry")
                    .guideTarget("dashboard.add")
                }
            }
            .toolbar(.hidden, for: .bottomBar)
            .sheet(isPresented: $adding) {
                ExpenseEditor(original: nil, initialDate: dateForNewExpense(in: month))
            }
            .sheet(item: $editingExpense) { ExpenseEditor(original: $0) }
            .modifier(ExpenseDeletionConfirmation(expense: $deletingExpense))
            .alert(tr("月度预算 · MYR", "Monthly budget · MYR", "Bajet bulanan · MYR"), isPresented: $budgeting) {
                TextField("1500.00", text: $budgetText).keyboardType(.decimalPad)
                Button(tr("保存", "Save", "Simpan")) { do { let n = try toCents(budgetText); let key = monthKey(month); model.change { $0.budgets[key] = n } } catch { model.error = error.localizedDescription } }
                Button(tr("移除预算", "Remove budget", "Buang bajet"), role: .destructive) { let key = monthKey(month); model.change { $0.budgets.removeValue(forKey: key) } }
                Button(tr("取消", "Cancel", "Batal"), role: .cancel) {}
            }
            }
        }
    }
    private var recentEntries: [Expense] { summary.recent }
    private var recentCard: some View {
        Section {
            if recentEntries.isEmpty {
                Text(tr("这个月还没有账目，记下第一笔吧。", "No entries this month. Add your first expense.", "Tiada rekod bulan ini. Tambah belanja pertama anda."))
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
            ForEach(recentEntries) { entry in
                NavigationLink(value: LedgerExpenseDestination(id: entry.id)) {
                    ExpenseRow(entry: entry).foregroundStyle(.primary)
                        .expenseCardSource(id: entry.id, namespace: navigationMotion)
                }
                .modifier(ExpenseContextActions(entry: entry,
                    edit: { guard !adding, editingExpense == nil else { return }; editingExpense = entry },
                    delete: { deletingExpense = entry }))
            }
        } header: {
            Text(tr("最近账目", "Recent entries", "Rekod terkini"))
        } footer: {
            Text(tr("所选月份", "Selected month", "Bulan dipilih"))
        }
    }
    private var quickActions: some View {
        Section {
            NavigationLink { AutomationSetupView() } label: {
                SimpleSettingsRow(title: tr("自动记账", "Automation", "Automasi"), subtitle: "TNG · Bank · Apple Pay", symbol: "bolt.fill", color: .blue)
            }
            NavigationLink { ReceiptScanView() } label: {
                SimpleSettingsRow(title: tr("扫描收据", "Scan receipt", "Imbas resit"), subtitle: tr("拍下，核对，记好", "Scan, review, save", "Imbas, semak, simpan"), symbol: "doc.viewfinder", color: .teal)
            }.guideTarget("dashboard.receipt")
        }
    }
    private var spendingCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Label(tr("本月个人消费", "Personal spending", "Belanja peribadi"), systemImage: "chart.pie.fill")
                    .font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Text("MYR").font(.footnote.weight(.semibold)).foregroundStyle(ink)
                    .padding(.horizontal, 9).padding(.vertical, 5).background(ink.opacity(0.08), in: Capsule())
            }
            AnimatedMoney(cents: personal)
                .font(.largeTitle.bold())
                .foregroundStyle(.primary).minimumScaleFactor(0.5).lineLimit(1)
            Text(summary.reimbursementClaimed > 0
                 ? tr("已扣除朋友份额、个人退款与报销金额", "After friends’ shares, your refunds and claims", "Selepas bahagian rakan, pulangan dan tuntutan anda")
                 : tr("已扣除朋友份额与个人退款", "After friends’ shares and your refunds", "Selepas bahagian rakan dan pulangan anda"))
                .font(.footnote).foregroundStyle(.secondary)
            if summary.reimbursementClaimed > 0 {
                NavigationLink { ReimbursementsView() } label: {
                    LabeledContent(tr("本月账目待报销", "Outstanding claims on this month's entries", "Tuntutan rekod bulan ini belum diterima"), value: money(summary.reimbursementOutstanding))
                        .font(.subheadline)
                }
            }
            Divider().overlay(ink.opacity(0.04))
            if budget > 0 {
                ViewThatFits(in: .horizontal) {
                    HStack {
                        Text(personal > budget ? tr("超出预算", "Over budget", "Melebihi bajet") : tr("预算剩余", "Remaining", "Baki bajet"))
                        Spacer(minLength: 16)
                        AnimatedMoney(cents: abs(budget - personal)).fontWeight(.semibold)
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        Text(personal > budget ? tr("超出预算", "Over budget", "Melebihi bajet") : tr("预算剩余", "Remaining", "Baki bajet"))
                        AnimatedMoney(cents: abs(budget - personal)).fontWeight(.semibold)
                    }
                }.font(.subheadline).foregroundStyle(budgetTint)
                SpendingMeter(value: personal, total: budget, color: budgetTint)
                budgetStatusBadge
            }
            HStack {
                Text(String(entries.count) + tr(" 笔消费", " expenses", " belanja")).font(.footnote).foregroundStyle(.secondary)
                Spacer()
                Button { budgetText = budget > 0 ? Currency.input(budget, "MYR") : ""; budgeting = true } label: {
                    Label(budget > 0 ? tr("调整预算", "Edit budget", "Ubah bajet") : tr("设置预算", "Set budget", "Tetapkan bajet"), systemImage: "slider.horizontal.3")
                        .font(.subheadline.weight(.medium)).frame(minHeight: 44)
                }.buttonStyle(.borderless)
            }
        }.padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading)
            .animation(reduceMotion ? nil : YueJiMotion.tone, value: budgetTint)
    }
    private var budgetStatusBadge: some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                Label(budgetStatus, systemImage: budgetSymbol)
                Spacer(minLength: 12)
                Text(budgetUsageText).monospacedDigit()
            }
            VStack(alignment: .leading, spacing: 6) {
                Label(budgetStatus, systemImage: budgetSymbol)
                Text(budgetUsageText).monospacedDigit()
            }
        }.font(.caption.weight(.medium)).foregroundStyle(.primary)
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(budgetTint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentTransition(.opacity)
    }
    private var balancesCard: some View {
        Section(tr("收支明细", "Payment details", "Butiran bayaran")) {
            LabeledContent(tr("我付的本月消费款", "Purchases paid by me", "Belanja dibayar oleh saya"), value: money(summary.paid))
            if summary.refunded > 0 {
                LabeledContent(tr("这些付款已退金额", "Refunded on these payments", "Bayaran ini dipulangkan"), value: money(summary.refunded))
            }
            let incoming = summary.incoming
            if incoming > 0 {
                NavigationLink { TNGInboxView() } label: {
                    LabeledContent(tr("银行 / TNG 本月收到", "Bank / TNG received this month", "Bank / TNG diterima bulan ini"), value: "+" + money(incoming))
                        .foregroundStyle(.green)
                }
            }
            NavigationLink { FriendSummaryView() } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(tr("朋友待还", "Friends owe", "Hutang rakan"), systemImage: "person.2.fill")
                        Text(tr("全部月份", "All months", "Semua bulan")).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(money(owed)).monospacedDigit().fontWeight(.semibold)
                }.foregroundStyle(.primary)
            }
        }
    }
    private var categoriesCard: some View {
        SpendingCategoryBreakdown(totals: summary.categoryTotals, total: personal, month: month)
    }
}

private struct SpendingCategoryBreakdown: View {
    @Environment(\.locale) private var uiLocale
    @EnvironmentObject private var model: LedgerModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let totals: [String: Int]
    let total: Int
    let month: Date
    var body: some View {
        let _ = uiLocale.identifier
        Section(tr("钱花在哪里", "Where it went", "Ke mana belanja")) {
            if total == 0 {
                Label(tr("暂无个人消费", "No personal spending yet", "Belum ada belanja peribadi"), systemImage: "leaf")
                    .foregroundStyle(.secondary)
                Text(tr("记录消费后，这里会显示你的分类占比。", "Your category breakdown will appear here.", "Pecahan kategori anda akan dipaparkan di sini."))
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                AnimatedMoney(cents: total).font(.title2.weight(.semibold)).padding(.vertical, 6)
            }
            ForEach(model.ledger.categoryNames, id: \.self) { category in
                let value = totals[category] ?? 0
                if value > 0 {
                    NavigationLink {
                        CategoryPaymentsView(category: category, month: month)
                    } label: {
                        VStack(spacing: 9) {
                            HStack {
                                CategoryBadge(name: category)
                                Spacer()
                                AnimatedMoney(cents: value).fontWeight(.semibold)
                            }.font(.subheadline)
                            SpendingMeter(value: value, total: max(total, 1), color: model.ledger.categoryTint(category))
                        }.foregroundStyle(.primary).frame(minHeight: 44).contentShape(Rectangle())
                    }.buttonStyle(.borderless)
                        .accessibilityIdentifier("overview.category.select." + category)
                        .transition(reduceMotion ? .identity : .opacity)
                }
            }
        }
    }
}

struct CategoryPaymentsView: View {
    @Environment(\.locale) private var uiLocale
    @EnvironmentObject var model: LedgerModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let category: String
    let month: Date
    private var tint: Color { model.ledger.categoryTint(category) }
    @State private var summary = OverviewSnapshot()
    @State private var entries: [Expense] = []
    @State private var loadedQuery: LedgerTimelineQuery?
    var body: some View {
        let _ = uiLocale.identifier
        let query = model.overviewQuery(month: month)
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    CategoryBadge(name: category).font(.headline)
                    Text(month.formatted(.dateTime.year().month(.wide).locale(Locale(identifier: AppLanguage.localeID))))
                        .font(.subheadline).foregroundStyle(.secondary)
                    AnimatedMoney(cents: summary.categoryTotals[category] ?? 0)
                        .font(.largeTitle.bold()).foregroundStyle(tint)
                        .lineLimit(1).minimumScaleFactor(0.5)
                    if loadedQuery == query {
                        Text(String(format: "%.1f%%", Double(summary.categoryTotals[category] ?? 0) / Double(max(summary.personal, 1)) * 100))
                            .font(.headline).monospacedDigit().foregroundStyle(tint)
                            .accessibilityIdentifier("category.spending.percent")
                    }
                    Text(tr("我的分类消费", "My category spending", "Belanja kategori saya"))
                        .font(.caption).foregroundStyle(.secondary)
                    Text(String(entries.count) + tr(" 笔付款", " payments", " bayaran")).font(.caption).foregroundStyle(.secondary)
                }.padding(.vertical, 8)
            } footer: {
                Text(tr("分类合计是扣除退款后的个人份额；付款记录显示整笔金额。", "The category total is your share after refunds; payment records show the full payment amount.", "Jumlah kategori ialah bahagian anda selepas pulangan; rekod bayaran menunjukkan amaun penuh."))
            }
            Section(tr("付款记录", "Payments", "Bayaran")) {
                if entries.isEmpty && loadedQuery == query {
                    ContentUnavailableView(tr("暂无记录", "No entries", "Tiada rekod"), systemImage: "tray")
                }
                ForEach(entries) { entry in
                    NavigationLink { ExpenseDetailView(id: entry.id, embeddedInNavigation: true) } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            ExpenseRow(entry: entry)
                            LabeledContent(tr("此分类 · 我的份额", "This category · my share", "Kategori ini · bahagian saya")) {
                                TransactionAmount(cents: entry.personalAmount(category: category), direction: .outgoing)
                            }.font(.caption)
                        }
                    }.foregroundStyle(.primary)
                }
            }
        }.yuejiListSurface()
            .tint(tint)
            .navigationTitle(categoryLabel(category)).navigationBarTitleDisplayMode(.inline)
            .refreshable { await model.refresh(postRecurring: false) }
            .yuejiUpdating(loadedQuery != query)
            .task(id: query) {
                guard loadedQuery != query else { return }
                do {
                    let fresh = try await model.preparedOverview(month: month, query: query)
                    guard !Task.isCancelled, model.overviewQuery(month: month) == query else { return }
                    summary = fresh; entries = fresh.entries.filter { $0.hasCategory(category) }; loadedQuery = query
                } catch is CancellationError { return }
                catch { model.error = error.localizedDescription }
            }
    }
}
struct OverviewToolsView: View {
    @Environment(\.locale) private var uiLocale
    var month: Date = Date()
    var body: some View {
        let _ = uiLocale.identifier
        List {
            Section(tr("日常工具", "Everyday tools", "Alat harian")) {
                NavigationLink { ReimbursementsView() } label: { Label(tr("报销管理", "Reimbursements", "Tuntutan bayaran balik"), systemImage: "doc.text") }
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
    @Environment(\.locale) private var uiLocale
    let title: String
    let symbol: String
    var body: some View {
        let _ = uiLocale.identifier
        HStack(spacing: 12) {
            Image(systemName: symbol).foregroundStyle(ink).frame(width: 28)
            Text(title).foregroundStyle(.primary).frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        }.font(.subheadline).padding(.vertical, 5).contentShape(Rectangle())
    }
}
struct ReceiptDetailsDisclosure: View {
    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let summary: String
    @State private var expanded = false
    var body: some View {
        let _ = locale.identifier
        DisclosureGroup(isExpanded: $expanded.animation(reduceMotion ? nil : YueJiMotion.month)) {
            if expanded { ReceiptPaper(summary: summary) }
        } label: {
            Text(tr("查看明细", "View details", "Lihat butiran"))
        }.accessibilityIdentifier("transaction.receipt.expand")
    }
}

private struct ReceiptPaper: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let summary: String
    @State private var revealed = false
    // Bound the number of animated views while preserving every character of
    // long legacy summaries in the final block. No receipt data is reparsed.
    private var blocks: [String] {
        let lines = summary.components(separatedBy: "\n")
        guard lines.count > 40 else { return lines }
        return Array(lines.prefix(40)) + [lines.dropFirst(40).joined(separator: "\n")]
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { index, line in
                Text(line.isEmpty ? " " : line).font(.subheadline).monospacedDigit()
                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    .opacity(reduceMotion || revealed ? 1 : 0)
                    .offset(y: reduceMotion || revealed ? 0 : 8)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.25).delay(Double(min(index, 8)) * 0.025), value: revealed)
            }
        }.padding(.vertical, 12)
            .task {
                guard !reduceMotion else { revealed = true; return }
                do { try await Task.sleep(for: .milliseconds(16)) } catch { return }
                revealed = true
            }
    }
}

struct SpendingMeter: View {
    @Environment(\.locale) private var uiLocale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    let value: Int
    let total: Int
    let color: Color
    @State private var displayedFraction = 0.0
    private var fraction: Double { min(max(Double(value) / Double(max(total, 1)), 0), 1) }
    var body: some View {
        let _ = uiLocale.identifier
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(color.opacity(contrast == .increased ? 0.30 : (colorScheme == .dark ? 0.22 : 0.10)))
                Capsule().fill(color).frame(width: proxy.size.width * (reduceMotion ? fraction : displayedFraction))
            }
        }.frame(height: 7)
            .animation(reduceMotion ? nil : YueJiMotion.tone, value: color)
            .task(id: fraction) {
                guard !reduceMotion else { displayedFraction = fraction; return }
                // Give a new lazy row one frame at zero before revealing its
                // share. Later updates animate from the current rendered value.
                if displayedFraction == 0 {
                    do { try await Task.sleep(for: .milliseconds(16)) } catch { return }
                }
                guard !Task.isCancelled else { return }
                withAnimation(YueJiMotion.meter) { displayedFraction = fraction }
            }
            .onChange(of: reduceMotion) { _, _ in
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { displayedFraction = fraction }
            }
            .accessibilityHidden(true)
    }
}
extension AccountDirection {
    var amountColor: Color { self == .incoming ? .green : (self == .outgoing ? .red : .primary) }
}
/// Use the same signs and colors for manual entries, bank notices and settlements.
struct TransactionAmount: View {
    @Environment(\.locale) private var uiLocale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let cents: Int
    let direction: AccountDirection
    var body: some View {
        let _ = uiLocale.identifier
        Text(direction.formattedAmount(cents)).foregroundStyle(direction.amountColor).monospacedDigit()
            .contentTransition(reduceMotion ? .identity : .numericText(value: direction == .outgoing ? -Double(cents) : Double(cents)))
            .animation(reduceMotion ? nil : YueJiMotion.standard, value: cents)
    }
}
struct ExpenseRow: View {
    @Environment(\.locale) private var uiLocale
    @EnvironmentObject private var model: LedgerModel
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    let entry: Expense
    private var symbol: String {
        if entry.fuel { return "fuelpump.fill" }
        if entry.recurringKey != nil { return "repeat" }
        return model.ledger.categorySymbol(entry.category)
    }
    private var categoryColor: Color {
        model.ledger.categoryTint(entry.category)
    }
    private var rowLayout: AnyLayout { typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(alignment: .top, spacing: 12)) }
    private var headingLayout: AnyLayout { typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4)) : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12)) }
    private var purchaseAmount: some View {
        TransactionAmount(cents: entry.purchaseDisplayCents, direction: entry.purchaseDirection)
            .accessibilityLabel((entry.paidByFriend == nil ? tr("购买总额 ", "Purchase total ", "Jumlah pembelian ") : tr("我的消费 ", "My spending ", "Belanja saya ")) + entry.purchaseDirection.formattedAmount(entry.purchaseDisplayCents))
            .font(.body.weight(.semibold)).monospacedDigit().fixedSize(horizontal: true, vertical: false)
    }
    var body: some View {
        let _ = uiLocale.identifier
        rowLayout {
            Image(systemName: symbol)
                .font(.body.weight(.semibold)).foregroundStyle(categoryColor).frame(width: 44, height: 44)
                .background(categoryColor.opacity(colorScheme == .dark ? 0.20 : 0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(categoryColor.opacity(contrast == .increased ? 0.45 : (colorScheme == .dark ? 0.25 : 0.10)), lineWidth: 0.5) }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                headingLayout {
                    Text(entry.displayName).font(.body.weight(.semibold)).lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                    if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
                    purchaseAmount
                }
                if !entry.merchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   let description = entry.entryDescription, !description.isEmpty {
                    Text(description).font(.subheadline).foregroundStyle(.secondary)
                        .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                }
                if let preview = entry.itemPreview {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(preview.names).lineLimit(1)
                            if preview.remaining > 0 { Text(preview.moreLabel).fixedSize() }
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(preview.names).lineLimit(2)
                            if preview.remaining > 0 { Text(preview.moreLabel) }
                        }
                    }.font(.subheadline).foregroundStyle(.secondary)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("transaction.items.preview")
                }
                Text(entry.categorySummary + " · " + dateLabel(entry.date)).font(.caption).foregroundStyle(.secondary).lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                if let payer = entry.paidByFriend { Text(tr("朋友付款：", "Paid by friend: ", "Dibayar oleh rakan: ") + payer).font(.footnote).foregroundStyle(.secondary) }
                if entry.refunded > 0 { Text(tr("购买退款：", "Purchase refunded: ", "Pembelian dipulangkan: ") + money(entry.refunded)).font(.footnote).foregroundStyle(.secondary) }
                if !entry.shares.isEmpty {
                    HStack {
                        Text(tr("我的份额：", "My share: ", "Bahagian saya: "))
                        TransactionAmount(cents: entry.personal, direction: .outgoing)
                    }.font(.footnote)
                }
                if let claim = entry.reimbursement {
                    ReimbursementStatusBadge(claim: claim)
                        .accessibilityIdentifier("transaction.reimbursement.status")
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(.vertical, 10)
            .modifier(RestoredRecordHighlight(recordID: entry.id))
    }
}

private struct RestoredRecordHighlight: ViewModifier {
    @EnvironmentObject private var model: LedgerModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let recordID: String
    var notice = false
    @State private var highlighted = false
    func body(content: Content) -> some View {
        content.overlay {
            RoundedRectangle(cornerRadius: 14).fill(Color.accentColor.opacity(highlighted ? 0.14 : 0))
                .allowsHitTesting(false).accessibilityHidden(true)
        }
        .task(id: model.restoredFeedback?.id) {
            highlighted = false
            guard let feedback = model.restoredFeedback,
                  feedback.date.timeIntervalSinceNow > -3,
                  (notice ? feedback.noticeIDs : feedback.expenseIDs).contains(recordID) else { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { highlighted = true }
            do { try await Task.sleep(for: .milliseconds(450)) }
            catch { highlighted = false; return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.9)) { highlighted = false }
        }
    }
}
private struct ExpenseContextActions: ViewModifier {
    @Environment(\.locale) private var uiLocale
    let entry: Expense
    let edit: () -> Void
    let delete: () -> Void
    func body(content: Content) -> some View {
        let _ = uiLocale.identifier
        content
            .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 20, style: .continuous))
            .contextMenu {
                Button(tr("编辑", "Edit", "Edit"), systemImage: "pencil", action: edit)
                Button(tr("删除", "Delete", "Padam"), systemImage: "trash", role: .destructive, action: delete)
            } preview: {
                ExpenseRow(entry: entry)
                    .padding(20).frame(idealWidth: 320, maxWidth: 360)
                    .fixedSize(horizontal: false, vertical: true)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
                    .accessibilityElement(children: .combine)
            }
    }
}

private struct LedgerFilterChip: View {
    @Environment(\.locale) private var uiLocale
    let title: String
    let remove: () -> Void
    var body: some View {
        let _ = uiLocale.identifier
        Button(action: remove) {
            HStack(spacing: 6) {
                Text(title)
                Image(systemName: "xmark.circle.fill").accessibilityHidden(true)
            }.font(.subheadline).padding(.horizontal, 12).padding(.vertical, 9)
                .background(Color.accentColor.opacity(0.10), in: Capsule())
                .frame(minHeight: 44)
        }.buttonStyle(.borderless)
            .accessibilityLabel(tr("移除筛选：", "Remove filter: ", "Buang penapis: ") + title)
    }
}

private struct LedgerInlineFilters: View {
    @Environment(\.locale) private var uiLocale
    @EnvironmentObject private var model: LedgerModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @Binding var filter: LedgerFilter
    @Binding var provider: String
    @Binding var expanded: Bool
    let advanced: () -> Void
    var body: some View {
        let _ = uiLocale.identifier
        if expanded {
            VStack(spacing: 12) {
                Picker(tr("分类", "Category", "Kategori"), selection: $filter.category) {
                    Text(tr("全部", "All", "Semua")).tag("")
                    ForEach(model.ledger.categoryNames, id: \.self) { Text(categoryLabel($0)).tag($0) }
                }.pickerStyle(.menu).accessibilityIdentifier("ledger.filters.category")
                Picker(tr("来源", "Source", "Sumber"), selection: $provider) {
                    Text(tr("全部来源", "All sources", "Semua sumber")).tag("all")
                    ForEach(model.ledger.availableSources, id: \.self) { Text(sourceLabel($0)).tag($0) }
                }.pickerStyle(.menu).accessibilityIdentifier("ledger.filters.source")
                let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout())
                layout {
                    Button(tr("金额与更多条件", "Amount & more filters", "Amaun dan penapis lain"), action: advanced)
                        .accessibilityIdentifier("ledger.filters.advanced")
                    if !typeSize.isAccessibilitySize { Spacer() }
                    Button(tr("完成", "Done", "Selesai")) { collapse() }
                }.buttonStyle(.borderless).font(.subheadline)
            }.buttonStyle(.borderless).padding(.vertical, 6)
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: -12)))
        }
        if filter.active || provider != "all" {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    if !filter.category.isEmpty {
                        LedgerFilterChip(title: categoryLabel(filter.category)) { filter.category = "" }
                    }
                    if provider != "all" {
                        LedgerFilterChip(title: sourceLabel(provider)) { provider = "all" }
                    }
                    if !filter.source.isEmpty {
                        LedgerFilterChip(title: tr("账目来源：", "Entry source: ", "Sumber rekod: ") + sourceLabel(filter.source)) { filter.source = "" }
                    }
                    if !filter.minimum.isEmpty {
                        LedgerFilterChip(title: "≥ RM " + filter.minimum) { filter.minimum = "" }
                    }
                    if !filter.maximum.isEmpty {
                        LedgerFilterChip(title: "≤ RM " + filter.maximum) { filter.maximum = "" }
                    }
                }
            }.scrollIndicators(.hidden).accessibilityIdentifier("ledger.filters.chips")
                .transition(.opacity)
        }
    }
    private func collapse() {
        withAnimation(reduceMotion ? nil : YueJiMotion.rows) { expanded = false }
    }
}

private enum LedgerSheetRoute: Identifiable {
    case new(Date), filter, edit(Expense)
    var id: String {
        switch self {
        case .new: return "manual-entry"
        case .filter: return "filters"
        case .edit(let entry): return "edit-" + entry.id
        }
    }
}
private struct LedgerExpenseDestination: Hashable { let id: String }

struct ExpensesView: View {
    @Environment(\.locale) private var uiLocale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject var model: LedgerModel
    var isActive: Bool = true
    @State private var filter = LedgerFilter()
    @State private var filtersExpanded = false
    @State private var providerFilter = "all"
    @State private var deletingNotice: TNGNotice?
    @Namespace private var expenseTransition
    @State private var sheet: LedgerSheetRoute?
    @State private var path = NavigationPath()
    @SceneStorage("ledgerMonth") private var monthTimestamp = Date().timeIntervalSince1970
    private var month: Date {
        get { model.isPreview ? Date() : Date(timeIntervalSince1970: monthTimestamp) }
        nonmutating set { monthTimestamp = newValue.timeIntervalSince1970 }
    }
    private var monthBinding: Binding<Date> { Binding(get: { month }, set: { month = $0 }) }
    @State private var search = ""
    @State private var deleting: Expense?
    @State private var timeline = LedgerTimelineSnapshot()
    @State private var loadedQuery: LedgerTimelineQuery?
    private var query: LedgerTimelineQuery {
        LedgerTimelineQuery(revision: model.ledgerRevision, month: month, search: search, filter: filter, provider: providerFilter)
    }
    var body: some View {
        let _ = uiLocale.identifier
        let requestedMonth = month
        let query = self.query
        let days = timeline.days
        NavigationStack(path: $path) {
            List {
                Section {
                    MonthPicker(month: monthBinding)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(filter.active || !search.isEmpty || providerFilter != "all" ? tr("筛选结果 · 我的消费", "Filtered · my spending", "Ditapis · belanja saya") : tr("本月 · 我的消费", "This month · my spending", "Bulan ini · belanja saya"))
                            .font(.caption).foregroundStyle(.secondary)
                        AnimatedMoney(cents: timeline.personal)
                            .font(.system(.title2, design: .default, weight: .semibold)).foregroundStyle(ink)
                        if timeline.reimbursementOutstanding > 0 {
                            Text(tr("待报销垫付款：", "Outstanding advances: ", "Pendahuluan belum diterima: ") + money(timeline.reimbursementOutstanding))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        HStack {
                            Text(String(timeline.count) + tr(" 笔记录", " entries", " rekod")).font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button {
                                withAnimation(reduceMotion ? nil : YueJiMotion.rows) { filtersExpanded.toggle() }
                            } label: { Label(filter.active || providerFilter != "all" ? tr("筛选已启用", "Filters active", "Penapis aktif") : tr("筛选", "Filter", "Tapis"), systemImage: "line.3.horizontal.decrease.circle") }
                                .buttonStyle(.borderless).font(.subheadline).guideTarget("ledger.filter")
                                .accessibilityIdentifier("ledger.filters.toggle")
                                .accessibilityValue(filtersExpanded ? tr("已展开", "Expanded", "Dikembangkan") : tr("已收起", "Collapsed", "Diruntuhkan"))
                        }
                    }.padding(.vertical, 6)
                    LedgerInlineFilters(filter: $filter, provider: $providerFilter, expanded: $filtersExpanded) {
                        if sheet == nil { sheet = .filter }
                    }
                    .animation(reduceMotion ? nil : YueJiMotion.rows, value: filter)
                    .animation(reduceMotion ? nil : YueJiMotion.rows, value: providerFilter)
                }
                if timeline.count == 0 && loadedQuery != nil {
                    ContentUnavailableView {
                        Label(tr("暂无记录", "No entries", "Tiada rekod"), systemImage: "tray")
                    } description: {
                        Text(filter.active || !search.isEmpty || providerFilter != "all"
                             ? tr("试试其他关键词，或清除筛选。", "Try another search or clear your filters.", "Cuba carian lain atau kosongkan penapis.")
                             : tr("为这个月记一笔，日期会保留在所选月份。", "Add an expense for the selected month.", "Tambah belanja untuk bulan dipilih."))
                    } actions: {
                        if filter.active || !search.isEmpty || providerFilter != "all" {
                            Button(tr("清除筛选与搜索", "Clear filters and search", "Kosongkan penapis dan carian")) { filter = LedgerFilter(); search = ""; providerFilter = "all" }
                        } else {
                            Button(tr("记一笔", "Add entry", "Tambah rekod")) { if sheet == nil { sheet = .new(dateForNewExpense(in: month)) } }.yuejiPrimaryButton()
                        }
                    }.listRowBackground(Color.clear).transition(.opacity)
                }
                ForEach(days) { day in
                    Section {
                        ForEach(day.entries) { item in
                            switch item {
                            case .settlement(let record):
                                NavigationLink { SettlementDetailView(id: record.id) } label: {
                                    SettlementPaymentRow(record: record)
                                }
                            case .transfer(let notice):
                                NavigationLink { TNGTimelineDetail(notice: notice) } label: {
                                    TNGTimelineRow(notice: notice, repaymentPreview: timeline.repaymentPreviews[notice.id])
                                        .modifier(RestoredRecordHighlight(recordID: notice.id, notice: true))
                                }
                                .modifier(AutomaticRecordDeleteActions { deletingNotice = notice })
                            case .expense(let entry):
                            NavigationLink(value: LedgerExpenseDestination(id: entry.id)) {
                                ExpenseRow(entry: entry).foregroundStyle(.primary)
                            }
                                .guideTarget(entry.id == "guide-lunch" ? "ledger.expense" : "ledger.other")
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button { deleting = entry } label: {
                                        Label(tr("删除", "Delete", "Padam"), systemImage: "trash")
                                    }.tint(.red)
                                }
                                .modifier(ExpenseContextActions(entry: entry,
                                    edit: { if sheet == nil { sheet = .edit(entry) } },
                                    delete: { deleting = entry }))
                            }
                        }
                    } header: { Text(dateLabel(day.date)) }
                }
            }.listStyle(.insetGrouped)
                .navigationDestination(for: LedgerExpenseDestination.self) { destination in
                    ExpenseDetailView(id: destination.id, embeddedInNavigation: true)
                }
                .task(id: isActive ? query : nil) {
                    guard isActive, loadedQuery != query else { return }
                    do {
                        let fresh = try await model.timeline(month: requestedMonth, query: query)
                        guard !Task.isCancelled, isActive, self.query == query else { return }
                        // Commit only the latest completed result. Animate structural
                        // changes, not every search keystroke or background refresh.
                        let changingSelection = loadedQuery.map {
                            $0.month != query.month || $0.filter != query.filter || $0.provider != query.provider
                        } ?? false
                        let changingEmptyState = loadedQuery != nil && (timeline.count == 0) != (fresh.count == 0)
                        let returningRows = model.restoredFeedback.map { feedback in
                            let expenses = feedback.expenseIDs.intersection(Set(fresh.expenses.map(\.id))).subtracting(Set(timeline.expenses.map(\.id)))
                            let notices = feedback.noticeIDs.intersection(Set(fresh.transfers.map(\.id))).subtracting(Set(timeline.transfers.map(\.id)))
                            return feedback.date.timeIntervalSinceNow > -3 && (!expenses.isEmpty || !notices.isEmpty)
                        } ?? false
                        withAnimation(!reduceMotion && (changingSelection || changingEmptyState || returningRows) ? YueJiMotion.month : nil) {
                            timeline = fresh
                            loadedQuery = query
                        }
                    } catch is CancellationError { return }
                    catch {
                        guard !Task.isCancelled, isActive, self.query == query else { return }
                        timeline = LedgerTimelineSnapshot(); loadedQuery = query
                        model.error = error.localizedDescription
                    }
                }
                .refreshable { await model.refresh(postRecurring: false) }
                .sheet(item: $sheet) { route in
                    switch route {
                    case .filter:
                        LedgerFilterEditor(value: filter) { value in
                            filter = value
                        }
                            .presentationDetents([.medium, .large])
                            .ledgerFeedback(modal: true)
                    case .new(let date): ExpenseEditor(original: nil, initialDate: date)
                    case .edit(let expense): ExpenseEditor(original: expense)
                    }
                }
                .yuejiListSurface().navigationTitle(tr("账本", "Ledger", "Lejar")).navigationBarTitleDisplayMode(.large).searchable(text: $search, prompt: tr("商户、分类、转账对象", "Merchant, category, transfer party", "Peniaga, kategori, pihak pindahan"))
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            NavigationLink(tr("银行 / TNG 通知", "Bank / TNG inbox", "Peti bank / TNG")) { TNGInboxView() }
                            NavigationLink(tr("检查重复账目", "Review possible duplicates", "Semak rekod pendua")) { DuplicateReviewView() }
                        } label: { Image(systemName: "ellipsis.circle") }
                            .accessibilityLabel(tr("更多工具", "More tools", "Alat lain"))
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { if sheet == nil { sheet = .new(dateForNewExpense(in: month)) } } label: { Image(systemName: "plus") }
                            .accessibilityLabel(tr("记一笔", "Add entry", "Tambah rekod"))
                            .yuejiZoomSource(id: "new-expense", namespace: expenseTransition)
                    }
                }
                .modifier(ExpenseDeletionConfirmation(expense: $deleting))
                .modifier(AutomaticRecordDeletionConfirmation(notice: $deletingNotice))
        }
    }
}
private struct TNGTimelineDetail: View {
    @Environment(\.locale) private var uiLocale
    let notice: TNGNotice
    var body: some View {
        let _ = uiLocale.identifier
        Group { if notice.kind == "incoming" { TNGIncomingView(id: notice.id) } else { TNGNoticeView(id: notice.id) } }
    }
}
struct TNGTimelineRow: View {
    @Environment(\.locale) private var uiLocale
    let notice: TNGNotice
    var repaymentPreview: RepaymentPurchasePreview? = nil
    @Environment(\.dynamicTypeSize) private var textSize
    private var movementLabel: String {
        if notice.status == "repayment" { return tr("朋友还款", "Friend repayment", "Bayaran balik rakan") }
        if notice.status == "settlement" { return tr("还款／结算", "Repayment / settlement", "Bayaran balik / penyelesaian") }
        switch notice.accountDirection {
        case .incoming: return tr("转入", "Incoming", "Masuk")
        case .outgoing: return tr("转出", "Outgoing", "Keluar")
        case .neutral: return tr("方向待确认", "Direction unconfirmed", "Arah belum disahkan")
        }
    }
    var body: some View {
        let _ = uiLocale.identifier
        let layout = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
        layout {
            VStack(alignment: .leading, spacing: 6) {
                Text(sourceLabel(notice.provider) + (notice.accountSuffix.map { " · ••••" + $0 } ?? "") + " · " + movementLabel)
                    .font(.headline).fixedSize(horizontal: false, vertical: true)
                if let party = notice.party, !party.isEmpty {
                    Text((notice.accountDirection == .incoming ? tr("来自：", "From: ", "Daripada: ") : (notice.accountDirection == .outgoing ? tr("给：", "To: ", "Kepada: ") : tr("交易对象：", "Party: ", "Pihak: "))) + party)
                        .font(.subheadline).fixedSize(horizontal: false, vertical: true)
                }
                if let repaymentPreview {
                    Text(tr("用于：", "For: ", "Untuk: ") + repaymentPreview.label)
                        .font(.subheadline).foregroundStyle(.secondary).lineLimit(3)
                        .accessibilityIdentifier("ledger.repayment.purchases")
                }
                Text(dateLabel(notice.date, time: true) + (notice.usesReceivedDate ? tr(" · 接收时间", " · received time", " · masa diterima") : ""))
                    .font(.caption).foregroundStyle(.secondary)
                Label(tngStatus(notice), systemImage: notice.status == "pending" ? "clock" : "checkmark.circle.fill")
                    .font(.caption2.weight(.medium)).foregroundStyle(notice.status == "pending" ? Color.orange : Color.secondary)
                    .padding(.horizontal, 7).padding(.vertical, 3).background(.quaternary, in: Capsule())
            }
            if !textSize.isAccessibilitySize { Spacer(minLength: 8) }
            TransactionAmount(cents: notice.cents ?? 0, direction: notice.accountDirection).font(.headline).layoutPriority(1)
        }.padding(.vertical, 8)
    }
}
struct ExpenseDetailView: View {
    @Environment(\.locale) private var uiLocale
    let id: String
    var embeddedInNavigation = false
    @EnvironmentObject private var model: LedgerModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @Namespace private var detailTransition
    @State private var editing: TransactionEditorRoute?
    @State private var editorPresented = false
    @State private var returnedAfterDeletion = false
    @State private var deleting: Expense?
    @State private var compactTitle = false
    // Hold the last real content until the native dismissal has finished.
    @State private var lastVisibleDetail: ExpenseDetailSnapshot?

    var body: some View {
        let _ = uiLocale.identifier
        Group {
            if embeddedInNavigation { detailContent }
            else { NavigationStack { detailContent }.yuejiSheetSurface() }
        }
    }
    private var detailContent: some View {
        let liveDetail = model.expenseDetail(id: id)
        let detail = liveDetail ?? lastVisibleDetail
        return List {
                if let detail {
                    let entry = detail.entry
                    Section {
                        ExpenseDetailHero(entry: entry, compact: $compactTitle)
                    }
                    if let description = entry.entryDescription, !description.isEmpty {
                    Section(tr("账目信息", "Entry information", "Maklumat rekod")) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(tr("账目名称／描述", "Name / description", "Nama / penerangan")).font(.caption).foregroundStyle(.secondary)
                                Text(description).textSelection(.enabled)
                            }.accessibilityIdentifier("transaction.description.detail")
                    }
                    }
                    SavedTransactionItemsSection(entry: entry, presentationAllowed: !editorPresented && deleting == nil) { selectedID in
                        guard !editorPresented, editing == nil, deleting == nil else { return }
                        editorPresented = true
                        editing = .items(entry, selectedID: selectedID)
                    }
                    ExpenseChargeDetails(entry: entry)
                    Section(tr("付款详情", "Payment details", "Butiran bayaran")) {
                        if entry.personalSpending != entry.purchaseDisplayCents || !entry.shares.isEmpty {
                            LabeledContent(tr("我的实际消费", "My spending", "Belanja saya")) { TransactionAmount(cents: entry.personalSpending, direction: .outgoing) }
                        }
                        if entry.paidByFriend != nil {
                            LabeledContent(tr("购买总额", "Purchase total", "Jumlah pembelian")) { TransactionAmount(cents: entry.cents, direction: .outgoing) }
                            LabeledContent(tr("我尚欠付款朋友", "I still owe the payer", "Saya masih berhutang kepada pembayar"), value: money(detail.payableToPayer))
                            if let payer = entry.paidByFriend {
                                NavigationLink(tr("\(payer) 的余额", "\(payer)'s balance", "Baki \(payer)")) { FriendDetailView(key: friendKey(payer)) }
                            }
                        }
                        if entry.refunded > 0 {
                            LabeledContent(tr("已退款", "Refunded", "Dipulangkan"), value: money(entry.refunded))
                        }
                        NavigationLink(tr("退款记录", "Refunds", "Bayaran balik")) { RefundsView(expenseID: id) }
                        DisclosureGroup(tr("更多付款信息", "More payment information", "Maklumat bayaran lanjut")) {
                        LabeledContent(tr("来源", "Source", "Sumber"), value: sourceLabel(entry.source))
                        LabeledContent(tr("付款人", "Paid by", "Dibayar oleh"), value: entry.payerLabel)
                        LabeledContent {
                            TransactionAmount(cents: entry.paidFromMyAccount, direction: entry.accountDirection)
                        } label: { Text(tr("我账户的原付款", "Original payment from my account", "Bayaran asal daripada akaun saya")) }
                        if entry.timeSource == "received" {
                            Text(tr("此时间是月记收到自动化的时刻，可能稍晚于付款。若需精确到银行交易时间，可在编辑中调整。", "This is when YueJi received the automation and may be later than payment. Edit it to match the bank transaction time if needed.", "Masa ini ialah ketika YueJi menerima automasi dan mungkin lewat sedikit. Edit mengikut masa transaksi bank jika perlu.")).font(.footnote).foregroundStyle(.secondary)
                        }
                        if let fx = entry.foreign {
                            LabeledContent(tr("原币金额", "Original amount", "Amaun asal"), value: Currency.display(fx.minor, fx.currency))
                            LabeledContent(tr("汇率", "Exchange rate", "Kadar pertukaran"), value: "1 \(fx.currency) = \(fx.quote.text) MYR")
                        }
                        ForEach(detail.sourceNotices) { notice in
                            DisclosureGroup(tr("通知原文", "Original notification", "Notifikasi asal")) {
                                if !notice.title.isEmpty { Text(notice.title).textSelection(.enabled) }
                                Text(notice.body).textSelection(.enabled)
                            }
                        }
                        }
                    }
                    Section(tr("报销", "Reimbursement", "Tuntutan bayaran balik")) {
                        NavigationLink { ReimbursementDetailView(expenseID: entry.id) } label: {
                            Label(entry.reimbursement?.status ?? tr("设置报销", "Set up reimbursement", "Tetapkan tuntutan"), systemImage: "doc.text")
                        }.accessibilityIdentifier("transaction.reimbursement.open")
                            .disabled(entry.paidByFriend != nil)
                        if let claim = entry.reimbursement {
                            LabeledContent(tr("报销对象", "Reimbursed by", "Dibayar balik oleh"), value: claim.recipient)
                            LabeledContent(tr("待到账", "Outstanding", "Belum diterima"), value: money(claim.outstanding))
                        }
                    }
                    if !entry.shares.isEmpty {
                        Section(tr("朋友分账", "Shared expenses", "Belanja dikongsi")) {
                            ForEach(entry.shares) { share in
                                VStack(alignment: .leading, spacing: 8) {
                                    LabeledContent(share.name, value: money(share.cents)).font(.headline)
                                    LabeledContent(tr("已还", "Repaid", "Telah dibayar"), value: money(share.repaid))
                                    if entry.paidByFriend == nil {
                                        let balance = detail.shareBalances[share.id] ?? 0
                                        LabeledContent(balance < 0 ? tr("需退给朋友", "Return to friend", "Pulangkan kepada rakan") : tr("待还", "Outstanding", "Belum dibayar"), value: money(abs(balance)))
                                    }
                                }.font(.subheadline).padding(.vertical, 6)
                            }
                        }
                    }
                    if !detail.settlements.isEmpty {
                    Section(tr("关联结算", "Linked settlements", "Penyelesaian dipautkan")) {
                        ForEach(detail.settlements) { record in
                            NavigationLink(dateLabel(record.date) + (record.active ? "" : tr(" · 已撤销", " · Undone", " · Dibatalkan"))) { SettlementDetailView(id: record.id) }
                        }
                    }
                    }
                    if let receipt = entry.receiptSummary {
                        Section(tr("收据明细", "Receipt details", "Butiran resit")) {
                            ReceiptDetailsDisclosure(summary: receipt)
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
                ToolbarItem(placement: .principal) {
                    ExpenseDetailTitle(entry: detail?.entry, compact: compactTitle)
                }
                if !embeddedInNavigation {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("关闭", "Close", "Tutup")) { dismiss() }
                }
                }
            }
            // Retain tab navigation; reserve a separate row above it for transaction actions.
            .toolbar(.visible, for: .tabBar)
            .toolbar(.hidden, for: .bottomBar)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let entry = detail?.entry {
                    let layout = typeSize.isAccessibilitySize
                        ? AnyLayout(VStackLayout(spacing: 12))
                        : AnyLayout(HStackLayout(spacing: 16))
                    layout {
                        Button {
                            guard !editorPresented, editing == nil else { return }
                            editorPresented = true
                            editing = .expense(entry)
                        } label: {
                            Label(tr("编辑", "Edit", "Edit"), systemImage: "pencil")
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .fixedSize(horizontal: false, vertical: true)
                        }.yuejiPrimaryButton().buttonBorderShape(.capsule).disabled(liveDetail == nil || model.deletionInFlight || editorPresented)
                            .accessibilityIdentifier("transaction.edit")
                            .yuejiZoomSource(id: "expense-edit-" + id, namespace: detailTransition)
                        Button(role: .destructive) { deleting = entry } label: {
                            Label(tr("删除", "Delete", "Padam"), systemImage: "trash")
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .fixedSize(horizontal: false, vertical: true)
                        }.yuejiSecondaryButton().buttonBorderShape(.capsule).tint(.red).disabled(liveDetail == nil || model.deletionInFlight || editorPresented)
                            .accessibilityIdentifier("transaction.delete")
                    }
                    .padding(.horizontal, 20).padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .modifier(YueJiActionBarSurface())
                }
            }
            .sheet(item: $editing, onDismiss: {
                editorPresented = false
                dismissDeletedDetailIfReady()
            }) { route in
                switch route {
                case .expense(let entry):
                    ExpenseEditor(original: entry)
                        .yuejiZoom(id: "expense-edit-" + id, namespace: detailTransition)
                case .items(let entry, let selectedID):
                    ExpenseItemsEditor(original: entry, selectedID: selectedID)
                }
            }
            .onChange(of: editing?.id) { _, value in if value != nil { editorPresented = true } }
            .modifier(ExpenseDeletionConfirmation(expense: $deleting))
            .onAppear { if let liveDetail, lastVisibleDetail?.entry.id != liveDetail.entry.id { lastVisibleDetail = liveDetail } }
            .onChange(of: model.ledgerRevision) { _, _ in
                if let current = model.expenseDetail(id: id) { lastVisibleDetail = current }
                else { dismissDeletedDetailIfReady() }
            }
            .transaction { transaction in
                if liveDetail == nil { transaction.animation = nil }
            }
    }
    private func dismissDeletedDetailIfReady() {
        guard !returnedAfterDeletion, !editorPresented, editing == nil, model.expense(id: id) == nil else { return }
        returnedAfterDeletion = true
        dismiss()
    }

}

private struct ExpenseDetailHero: View {
    @Environment(\.locale) private var uiLocale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let entry: Expense
    @Binding var compact: Bool
    var body: some View {
        let _ = uiLocale.identifier
        let motion = !reduceMotion
        VStack(spacing: 12) {
            Text(entry.paidByFriend == nil ? tr("实付总额", "Payment total", "Jumlah bayaran") : tr("我的份额", "My share", "Bahagian saya"))
                .font(.caption).foregroundStyle(.secondary)
            TransactionAmount(cents: entry.purchaseDisplayCents, direction: entry.purchaseDirection)
                .font(.largeTitle.bold()).minimumScaleFactor(0.6).lineLimit(1)
            if entry.paidByFriend != nil {
                Text(tr("朋友代付 · 我的账户未付款", "Friend paid · no payment from my account", "Rakan membayar · tiada bayaran daripada akaun saya"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text(entry.displayName).font(.title3.weight(.semibold)).multilineTextAlignment(.center)
            Text(entry.categorySummary).font(.subheadline).foregroundStyle(.secondary)
            Text(dateLabel(entry.date, time: true) + entry.timeSourceSuffix).font(.subheadline).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity).padding(.vertical, 20)
            // Visual-only interpolation cannot change the List row's height or
            // trigger financial projections on every scroll frame.
            .visualEffect { content, geometry in
                let travel = max(0, -geometry.frame(in: .scrollView(axis: .vertical)).minY)
                let progress = motion ? min(1, travel / max(1, geometry.size.height)) : 0
                return content.scaleEffect(1 - progress * 0.08, anchor: .top)
                    .opacity(Double(1 - progress * 0.65))
            }
            .onGeometryChange(for: Bool.self) { geometry in
                geometry.frame(in: .scrollView(axis: .vertical)).maxY < 52
            } action: { compact = $0 }
            .accessibilityIdentifier("transaction.detail.header")
    }
}

private struct ExpenseDetailTitle: View {
    @Environment(\.locale) private var uiLocale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    let entry: Expense?
    let compact: Bool
    var body: some View {
        let _ = uiLocale.identifier
        ZStack {
            Text(tr("账目详情", "Entry details", "Butiran rekod")).font(.headline)
                .opacity(compact && entry != nil ? 0 : 1)
                .accessibilityHidden(compact && entry != nil)
            if let entry {
                VStack(spacing: 2) {
                    Text(entry.displayName).font(.subheadline.weight(.semibold)).lineLimit(1)
                    if !typeSize.isAccessibilitySize {
                        TransactionAmount(cents: entry.purchaseDisplayCents, direction: entry.purchaseDirection)
                            .font(.caption.weight(.medium)).lineLimit(1)
                    }
                }.opacity(compact ? 1 : 0)
                    .offset(y: reduceMotion || compact ? 0 : 6)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(entry.displayName + ", " + entry.purchaseDirection.formattedAmount(entry.purchaseDisplayCents))
                    .accessibilityHidden(!compact)
            }
        }.frame(maxWidth: 240).frame(height: 44)
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .animation(reduceMotion ? nil : YueJiMotion.standard, value: compact)
            .allowsHitTesting(false)
            .accessibilityIdentifier("transaction.detail.compactTitle")
    }
}

/// A captured presenting value survives the dialog resetting its binding.
private struct ExpenseDeletionConfirmation: ViewModifier {
    @EnvironmentObject private var model: LedgerModel
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
                Task {
                    do { try await model.deleteExpense(entry); onDeleted() }
                    catch { failure = error.localizedDescription }
                }
            }
            Button(tr("取消", "Cancel", "Batal"), role: .cancel) {}
        } message: { entry in
            Text(entry.displayName + " · " + money(entry.cents) + "\n" + tr(
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

struct ExpenseEditorSnapshot: Equatable {
    var text: [String]
    var flags: [Bool]
    var date: Date
    var items: [ExpenseItemDraft]
    var people: [FriendDraft]
}

extension View {
    func editorDismissal(hasChanges: Bool, saving: Bool, confirming: Binding<Bool>, discard: @escaping () -> Void) -> some View {
        self.background {
                EditorDismissObserver(blocked: hasChanges || saving) {
                    if hasChanges && !saving { confirming.wrappedValue = true }
                }.frame(width: 0, height: 0)
            }
            // A confirmationDialog can become a popover that omits its cancel
            // button. An alert keeps both choices visible in every size class.
            .alert(tr("放弃未保存的修改？", "Discard changes?", "Buang perubahan?"), isPresented: confirming) {
                Button(tr("放弃修改", "Discard changes", "Buang perubahan"), role: .destructive, action: discard)
                Button(tr("继续编辑", "Keep editing", "Terus edit"), role: .cancel) {}
            } message: {
                Text(tr("修改尚未保存。继续编辑可保留当前填写的内容。", "Your changes have not been saved. Keep editing to retain your input.", "Perubahan belum disimpan. Teruskan mengedit untuk mengekalkan input."))
            }
    }
}

/// Observe the system sheet's rejected swipe instead of adding a competing drag
/// gesture to the Form. Forward dismissal callbacks so SwiftUI retains ownership
/// of presentation bindings, and restore its delegate when the observer leaves.
private struct EditorDismissObserver: UIViewControllerRepresentable {
    var blocked: Bool
    var attempted: () -> Void
    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.blocked = blocked
        controller.attempted = attempted
        controller.install()
        DispatchQueue.main.async { [weak controller] in controller?.install() }
    }
    static func dismantleUIViewController(_ controller: Controller, coordinator: ()) { controller.uninstall() }

    final class Controller: UIViewController, UIAdaptivePresentationControllerDelegate {
        var blocked = false
        var attempted: (() -> Void)?
        private weak var observed: UIPresentationController?
        private weak var previous: (any UIAdaptivePresentationControllerDelegate)?
        private var previousModalInPresentation = false
        private var removed = false
        override func loadView() { view = UIView(); view.isUserInteractionEnabled = false }
        override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); install() }
        override func didMove(toParent parent: UIViewController?) { super.didMove(toParent: parent); if parent != nil { install() } }
        override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); install() }
        func install() {
            guard !removed else { return }
            var ancestor: UIViewController? = self
            while let candidate = ancestor {
                // Contained navigation controllers can report their ancestor's
                // presenter. Install only on the actual presented controller.
                if let presenter = candidate.presentingViewController,
                   presenter.presentedViewController === candidate,
                   let presentation = candidate.presentationController,
                   presentation.presentedViewController === candidate {
                    if observed !== presentation {
                        restore()
                        observed = presentation
                        previous = presentation.delegate
                        previousModalInPresentation = candidate.isModalInPresentation
                        #if DEBUG
                        print("Editor dismissal observer attached to presented sheet")
                        #endif
                    } else if presentation.delegate !== self {
                        previous = presentation.delegate
                    }
                    // This observer owns both the dismissal restriction and its
                    // attempted-dismiss callback. A simultaneous SwiftUI
                    // interactiveDismissDisabled modifier can replace the delegate.
                    candidate.isModalInPresentation = blocked
                    presentation.delegate = self
                    return
                }
                ancestor = candidate.parent
            }
        }
        func uninstall() {
            removed = true
            restore()
            attempted = nil
        }
        private func restore() {
            if let observed, observed.delegate === self {
                observed.delegate = previous
                observed.presentedViewController.isModalInPresentation = previousModalInPresentation
            }
        }
        func presentationControllerShouldDismiss(_ presentationController: UIPresentationController) -> Bool { !blocked }
        func presentationControllerDidAttemptToDismiss(_ presentationController: UIPresentationController) {
            #if DEBUG
            print("Editor dismissal observer received attempted dismissal")
            #endif
            DispatchQueue.main.async { [weak self] in self?.attempted?() }
        }
        func presentationControllerWillDismiss(_ presentationController: UIPresentationController) {
            previous?.presentationControllerWillDismiss?(presentationController)
        }
        func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
            previous?.presentationControllerDidDismiss?(presentationController)
        }
    }
}

struct FriendDraft: Identifiable, Equatable {
    var id: String; var name: String; var amount: String; var repayments: [Repayment]
    init(_ s: Share = Share(name: "", cents: 0)) { id = s.id; name = s.name; amount = Currency.input(s.cents, "MYR"); repayments = s.repayments }
}
struct ExpenseEditor: View {
    @Environment(\.locale) private var uiLocale
    @EnvironmentObject var model: LedgerModel
    @Environment(\.dismiss) private var dismiss
    let original: Expense?
    var initialDate: Date = Date()
    var initialDraft: Expense? = nil
    var startWithSplit = false
    var onSaved: (() -> Void)? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var foreignExpanded = false
    @FocusState private var focusedField: ExpenseInputField?
    @State private var deleting: Expense?
    @State private var name = ""
    @State private var entryDescription = ""
    @State private var reimbursementEnabled = false
    @State private var reimbursementRecipient = ""
    @State private var reimbursementAmount = ""
    @State private var amount = ""
    @State private var chargesEnabled = false
    @State private var chargeSubtotal = ""
    @State private var sstPercent = ""
    @State private var servicePercent = ""
    @State private var chargeRounding = ""
    @State private var currency = "MYR"
    @State private var rate = ""
    @State private var rateDate = Date()
    @State private var rateSource = "Manual"
    @State private var date = Date()
    @State private var category = "其他"
    @State private var rememberCategory = true
    @State private var itemDrafts: [ExpenseItemDraft] = []
    @State private var splitting = false
    @State private var entryType = "expense"
    @State private var friendPays = false
    @State private var payerName = ""
    @State private var friendPaidMode = "equal"
    @State private var friendShareText = ""
    @State private var fuel = false
    @State private var equal = true
    @State private var includeMe = true
    @State private var people = [FriendDraft()]
    @State private var error: String?
    @State private var initialized = false
    @State private var saving = false
    @State private var rateLoading = false
    @State private var rateRequest = UUID()
    @State private var rateNote = ""
    @State private var initialSnapshot: ExpenseEditorSnapshot?
    @State private var confirmingDiscard = false
    private var snapshot: ExpenseEditorSnapshot {
        ExpenseEditorSnapshot(text: [name, entryDescription, amount, currency, rate, category, entryType, payerName, friendPaidMode, friendShareText, reimbursementRecipient, reimbursementAmount, chargeSubtotal, sstPercent, servicePercent, chargeRounding],
                              flags: [rememberCategory, splitting, friendPays, fuel, equal, includeMe, reimbursementEnabled, chargesEnabled],
                              date: date, items: itemDrafts, people: people)
    }
    private var hasChanges: Bool { initialSnapshot.map { $0 != snapshot } ?? false }
    private func requestClose() {
        guard !saving else { return }
        finishKeyboard()
        if hasChanges { confirmingDiscard = true } else { dismiss() }
    }
    private func foreign() throws -> ForeignAmount? {
        if currency == "MYR" { return nil }
        let value = try parseRate(rate)
        return ForeignAmount(currency: currency, minor: try Currency.parse(amount, code: currency), quote: RateQuote(value: value, date: rateDate, source: rateSource))
    }
    private func total() throws -> Int { if let fx = try foreign() { return try fx.myrCents() }; return try toCents(amount) }
    private var chargesDraft: ExpenseCharges? {
        guard chargesEnabled else { return nil }
        return try? ExpenseCharges.draft(currency: currency, subtotal: chargeSubtotal, sst: sstPercent, service: servicePercent, rounding: chargeRounding)
    }
    private var itemBase: Int { chargesDraft.flatMap { try? $0.myrSubtotal(foreign: try? foreign()) } ?? ((try? total()) ?? 0) }
    var body: some View {
        let _ = uiLocale.identifier
        NavigationStack {
            if original == nil && initialDraft == nil && entryType == "settlement" {
                ManualSettlementEntryView(entryType: $entryType, initialDate: initialDate)
            } else {
            Form {
                if original == nil && initialDraft == nil { ManualEntryTypeSection(selection: $entryType) }
                paymentSection
                chargeSection
                payerSection
                merchantSection
                ExpenseItemsFields(items: $itemDrafts, totalCents: itemBase, defaultCategory: category, savedTransaction: original != nil, sharedFocus: $focusedField, friendNames: people.map(\.name), payer: friendPays ? payerName : nil, charges: chargesDraft, foreign: try? foreign())
                currencySection
                friendSplitSection
                reimbursementSection
                if let original {
                    if model.ledger.hasActiveSettlement(expenseID: original.id) {
                        Section {
                            Text(tr("此账目已参与结算。修改金额、日期、付款人、分类、物品、分账或退款前，请先撤销相关结算。", "This expense is settled. Undo its settlements before changing amount, date, payer, category, items, shares or refunds.", "Belanja ini telah diselesaikan. Batalkan penyelesaian sebelum menukar amaun, tarikh, pembayar, kategori, item, bahagian atau pulangan."))
                            ForEach(model.ledger.settlements.filter { $0.active && $0.lines.contains { $0.expense.id == original.id && $0.applied != 0 } }) { record in
                                NavigationLink(tr("查看结算", "View settlement", "Lihat penyelesaian")) { SettlementDetailView(id: record.id) }
                            }
                        }
                    }
                    Section { NavigationLink(tr("退款记录", "Refunds", "Bayaran balik")) { RefundsView(expenseID: original.id) } }
                    if original.refunded > 0 { Text(tr("已有退款，金额、日期和分账已锁定。需修改时先撤销相关退款。", "Refunds exist. Amount, date and splits are locked. Undo refunds before changing these.", "Bayaran balik wujud. Amaun, tarikh dan pembahagian dikunci. Batalkan bayaran balik sebelum mengubahnya.")).font(.footnote).foregroundStyle(.secondary) }
                }
                if let summary = (original ?? initialDraft)?.receiptSummary {
                    Section(tr("收据税费", "Receipt charges", "Caj resit")) {
                        ReceiptDetailsDisclosure(summary: summary)
                        ShareLink(item: summary) { Label(tr("分享明细", "Share details", "Kongsi butiran"), systemImage: "square.and.arrow.up") }
                    }
                }
                if let original {
                    Section {
                        Button(role: .destructive) { deleting = original } label: {
                            Label(tr("删除这笔账目", "Delete this entry", "Padam rekod ini"), systemImage: "trash")
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                }
            }.yuejiListSurface().scrollDismissesKeyboard(.interactively)
                .disabled(saving)
                .modifier(ExpenseDeletionConfirmation(expense: $deleting, onDeleted: { dismiss() }))
                .navigationTitle(original == nil ? tr("新增账目", "New entry", "Rekod baharu") : tr("编辑账目", "Edit expense", "Edit belanja")).navigationBarTitleDisplayMode(.inline).yuejiSheetSurface()
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(tr("取消", "Cancel", "Batal")) { requestClose() }.disabled(saving) }; ToolbarItem(placement: .confirmationAction) { Button { beginSave() } label: {
                    EditorSaveLabel(saving: saving)
                }.yuejiPrimaryButton().disabled(rateLoading || saving) } }
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button(tr("完成", "Done", "Selesai")) { finishKeyboard() }
                    }
                }
                .onAppear { load() }
                .task(id: currency) {
                    guard !model.isPreview else { return }
                    let request = UUID(), code = currency, submittedRate = rate
                    rateRequest = request
                    guard original == nil, code != "MYR" else { rateLoading = false; return }
                    rateLoading = true; defer { if rateRequest == request { rateLoading = false } }
                    do {
                        if let q = try await AutomaticRates.shared.refresh(code) {
                            try Task.checkCancellation()
                            guard currency == code, rateRequest == request else { return }
                            if rate == submittedRate { rate = q.text; rateDate = q.date; rateSource = q.source }
                            rateNote = q.source + " · " + dateLabel(q.date)
                        }
                    } catch {
                        if !Task.isCancelled { rateNote = tr("更新失败，已保留现有汇率，请核对日期。", "Refresh failed. Review the existing rate and date.", "Kemas kini gagal. Semak kadar dan tarikh sedia ada.") }
                    }
                }
                .alert(tr("无法保存", "Unable to save", "Tidak dapat menyimpan"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button(tr("重试", "Retry", "Cuba lagi")) { beginSave() }; Button(tr("继续编辑", "Keep editing", "Terus edit"), role: .cancel) {} } message: { Text(error ?? "") }
            }
        }.ledgerFeedback(modal: true)
            .editorDismissal(hasChanges: hasChanges, saving: saving, confirming: $confirmingDiscard, discard: { dismiss() })
    }
    private var paymentSection: some View {
        Section(tr("实际付款", "Payment", "Bayaran")) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(currency).font(.headline).foregroundStyle(.secondary)
                TextField("0.00", text: $amount)
                    .keyboardType(.decimalPad).focused($focusedField, equals: .amount)
                    .accessibilityIdentifier("transaction.amount")
                    .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                    .monospacedDigit().padding(.vertical, 12)
                    .accessibilityLabel(tr("付款金额", "Payment amount", "Amaun bayaran"))
            }
            if currency != "MYR", let converted = try? total() {
                LabeledContent(tr("折合 MYR", "Equivalent in MYR", "Nilai dalam MYR"), value: money(converted))
                    .font(.subheadline)
            }
        }.disabled((original?.refunded ?? 0) > 0)
    }
    private var reimbursementSection: some View {
        ReimbursementDraftFields(enabled: $reimbursementEnabled, recipient: $reimbursementRecipient,
                                 amount: $reimbursementAmount,
                                 canRemove: (original?.reimbursement?.receipts.isEmpty ?? true), friendPaid: friendPays,
                                 sharedFocus: $focusedField)
    }
    private var chargeSection: some View {
        ExpenseChargeFields(enabled: $chargesEnabled, subtotal: $chargeSubtotal, sst: $sstPercent, service: $servicePercent, rounding: $chargeRounding,
                            currency: currency, actualMinor: try? Currency.parse(amount, code: currency), applyTotal: { minor in
                                amount = Currency.input(minor, currency)
                                focusedField = nil
                            }, sharedFocus: $focusedField)
            .disabled((original?.chargeEditsLocked ?? false) || (original.map { model.ledger.hasActiveSettlement(expenseID: $0.id) } ?? false))
            .onChange(of: chargesEnabled) { _, enabled in
                if enabled, original == nil, initialDraft == nil, chargeSubtotal.isEmpty { chargeSubtotal = amount }
            }
    }
    private var payerSection: some View {
        Section {
            Picker(tr("付款人", "Payer", "Pembayar"), selection: $friendPays) {
                Text(tr("我付款", "Paid by me", "Dibayar oleh saya")).tag(false)
                Text(tr("朋友付款", "Paid by a friend", "Dibayar oleh rakan")).tag(true)
            }
            if friendPays {
                TextField(tr("付款朋友姓名", "Paying friend's name", "Nama rakan pembayar"), text: $payerName)
                if !model.friends.isEmpty {
                    Menu(tr("选择已有朋友", "Choose existing friend", "Pilih rakan sedia ada")) {
                        ForEach(model.friends) { friend in Button(friend.name) { payerName = friend.name } }
                    }
                }
            }
        } header: {
            Text(tr("谁付款", "Who paid", "Siapa membayar"))
        } footer: { Text(tr("消费按个人份额计算；朋友代付不会计入我账户的付款。", "Spending uses your personal share. A friend's payment does not count as money leaving your account.", "Belanja menggunakan bahagian anda. Bayaran rakan tidak dikira sebagai wang keluar daripada akaun anda.")) }
            .disabled((original?.refunded ?? 0) > 0 || (original.map { model.ledger.hasActiveSettlement(expenseID: $0.id) } ?? false))
    }
    private var merchantSection: some View {
        Section(tr("账目信息", "Entry information", "Maklumat rekod")) {
            VStack(alignment: .leading, spacing: 6) {
                Text(tr("商户 · 选填", "Merchant · optional", "Peniaga · pilihan")).font(.caption).foregroundStyle(.secondary)
                TextField(tr("商户（选填）", "Merchant (optional)", "Peniaga (pilihan)"), text: $name)
                    .accessibilityIdentifier("transaction.merchant")
                    .focused($focusedField, equals: .merchant).submitLabel(.done)
                    .onSubmit { finishKeyboard() }
            }.padding(.vertical, 4)
            VStack(alignment: .leading, spacing: 6) {
                Text(tr("账目名称／描述 · 选填", "Name / description · optional", "Nama / penerangan · pilihan")).font(.caption).foregroundStyle(.secondary)
                TextField(tr("账目名称／描述（选填）", "Name / description (optional)", "Nama / penerangan (pilihan)"), text: $entryDescription, axis: .vertical)
                    .lineLimit(1...4)
                    .focused($focusedField, equals: .entryDescription)
                    .accessibilityIdentifier("transaction.description")
            }.padding(.vertical, 4)
            // Keep this navigation row mounted when the first item is inserted.
            // Removing it in the same Form update can invalidate native navigation.
            Picker(tr("分类", "Category", "Kategori"), selection: $category) {
                ForEach(model.ledger.categoryNames, id: \.self) { item in
                    Text(categoryLabel(item)).tag(item)
                }
            }.pickerStyle(.navigationLink).disabled(!itemDrafts.isEmpty)
                .accessibilityIdentifier("transaction.category")
            Text(tr("填写物品后，消费按每件物品的分类统计。", "When items are entered, spending uses each item's category.", "Apabila item diisi, belanja menggunakan kategori setiap item."))
                .font(.footnote).foregroundStyle(.secondary)
        }.disabled((original?.refunded ?? 0) > 0)
    }
    private var currencySection: some View {
        Section {
            Toggle(tr("以后此商户使用这个分类", "Use this category for this merchant next time", "Guna kategori ini untuk peniaga ini lain kali"), isOn: $rememberCategory)
                .disabled(!itemDrafts.isEmpty || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            DatePicker(tr("日期", "Date", "Tarikh"), selection: $date, displayedComponents: [.date, .hourAndMinute])
            DisclosureGroup(isExpanded: $foreignExpanded.animation(reduceMotion ? nil : YueJiMotion.standard)) {
                Picker(tr("币种", "Currency", "Mata wang"), selection: Binding(get: { currency }, set: { code in
                    currency = code
                    if let q = model.ledger.rates[code] { rate = q.text; rateDate = q.date; rateSource = q.source }
                    else { rate = ""; rateSource = "Manual"; rateDate = Date() }
                })) { ForEach(Currency.codes, id: \.self) { Text($0).tag($0) } }
                if currency != "MYR" {
                    if rateLoading { ProgressView() }
                    if !rateNote.isEmpty { Text(rateNote).font(.footnote).foregroundStyle(.secondary) }
                    Text("1 \(currency) = ? MYR").font(.footnote).foregroundStyle(.secondary)
                    TextField(tr("汇率", "Exchange rate", "Kadar pertukaran"), text: $rate).keyboardType(.decimalPad).focused($focusedField, equals: .rate).disabled(rateLoading)
                    Text(tr("可填写银行实际汇率。保存后不会随参考汇率变化。", "You may enter your bank's actual rate. Saved entries will not change with market rates.", "Anda boleh isi kadar sebenar bank. Rekod disimpan tidak berubah mengikut kadar pasaran.")).font(.footnote).foregroundStyle(.secondary)
                    if let n = try? total() { LabeledContent(tr("换算为", "Converted to", "Ditukar kepada"), value: money(n)) }
                }
            } label: {
                LabeledContent(tr("外币与汇率", "Currency and rate", "Mata wang dan kadar"), value: currency)
            }
        }.disabled((original?.refunded ?? 0) > 0)
    }
    private var friendSplitSection: some View {
        Section {
            if !itemDrafts.contains(where: { $0.ownership != nil }) {
            if friendPays {
                Picker(tr("归属与分摊", "Ownership and split", "Pemilikan dan pembahagian"), selection: $friendPaidMode) {
                    Text(tr("各半", "Equal halves", "Separuh sama rata")).tag("equal")
                    Text(tr("自定金额", "Custom amounts", "Amaun tersuai")).tag("custom")
                    Text(tr("全是我的", "Entirely mine", "Sepenuhnya milik saya")).tag("mine")
                    Text(tr("全是朋友的", "Entirely my friend's", "Sepenuhnya milik rakan")).tag("friend")
                }
                if friendPaidMode == "custom" { TextField(tr("朋友自己的份额 · MYR", "Friend's own share · MYR", "Bahagian rakan sendiri · MYR"), text: $friendShareText).keyboardType(.decimalPad) }
                if let total = try? total(), let theirs = try? friendPaidShare(total) {
                    LabeledContent(tr("我的原始份额", "My original share", "Bahagian asal saya"), value: money(total - theirs))
                    LabeledContent(tr("朋友自己的份额", "Friend's own share", "Bahagian rakan sendiri"), value: money(theirs))
                }
            } else {
            Button(tr("全是我的", "Entirely mine", "Sepenuhnya milik saya")) { splitting = false }
            Button(tr("全是朋友的", "Entirely my friend's", "Sepenuhnya milik rakan")) { splitting = true; equal = true; includeMe = false; people = Array(people.prefix(1)) }
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
            }
            }
        } footer: { if splitting && !itemDrafts.contains(where: { $0.ownership != nil }) { Text(tr("分账和还款金额使用 MYR。已有付款请编辑分账，避免重复新增。", "Shares and repayments use MYR. Edit an existing payment to split it without duplicating it.", "Bahagian dan bayaran balik menggunakan MYR. Edit bayaran sedia ada untuk mengelakkan pendua.")) } }
            .disabled((original?.refunded ?? 0) > 0)
            .animation(reduceMotion ? nil : YueJiMotion.standard, value: splitting)
            .animation(reduceMotion ? nil : YueJiMotion.standard, value: people.count)
    }
    private func load() {
        guard !initialized else { return }; initialized = true
        defer { initialSnapshot = snapshot }
        if original == nil { date = initialDate; splitting = startWithSplit }
        if let e = original ?? initialDraft {
            name = e.merchant; date = e.date; category = e.category; fuel = e.fuel
            entryDescription = e.entryDescription ?? ""
            if let claim = e.reimbursement {
                reimbursementEnabled = true
                reimbursementRecipient = claim.recipient
                reimbursementAmount = Currency.input(claim.cents, "MYR")
            }
            friendPays = e.paidByFriend != nil; payerName = e.paidByFriend ?? ""
            if friendPays { friendPaidMode = "custom"; friendShareText = Currency.input(e.shares.first?.cents ?? 0, "MYR") }
            itemDrafts = (e.items ?? []).map(ExpenseItemDraft.init)
            splitting = !e.shares.isEmpty; equal = e.shares.isEmpty
            if splitting { people = e.shares.map(FriendDraft.init) }
            currency = e.foreign?.currency ?? "MYR"; amount = Currency.input(e.foreign?.minor ?? e.cents, currency)
            if let charges = e.charges {
                chargesEnabled = true
                chargeSubtotal = Currency.input(charges.subtotal, charges.currency)
                sstPercent = ExpenseCharges.percentText(charges.sstBasisPoints)
                servicePercent = ExpenseCharges.percentText(charges.serviceBasisPoints)
                chargeRounding = Currency.input(charges.roundingMinor ?? 0, charges.currency)
            }
            foreignExpanded = currency != "MYR"
            if let fx = e.foreign { rate = fx.quote.text; rateDate = fx.quote.date; rateSource = fx.quote.source }
        }
    }
    private func friendPaidShare(_ total: Int) throws -> Int {
        switch friendPaidMode {
        case "mine": return 0
        case "friend": return total
        case "equal": return equalShares(total: total, count: 1, includeMe: true)[0]
        default:
            let amount = try nonnegativeCents(friendShareText)
            guard amount <= total else { throw settlementError("份额不能超过总额。", "Share cannot exceed the total.", "Bahagian tidak boleh melebihi jumlah.") }
            return amount
        }
    }
    private func finishKeyboard() {
        if focusedField != nil {
            // The item fields and transaction fields have one SwiftUI focus owner.
            // Do not also force UIKit resignation while SwiftUI reconciles its focus.
            focusedField = nil
        } else {
            // Friend/payer fields do not participate in the explicit focus chain.
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
    }
    private func beginSave() {
        guard !saving else { return }
        finishKeyboard()
        saving = true
        Task { @MainActor in
            await Task.yield()
            await commit()
            saving = false
        }
    }
    private func commit() async {
        do {
            let n = try total(); var entry = original ?? initialDraft ?? Expense(merchant: "", cents: n)
            if entry.cents != n || currency != "MYR" { entry.receiptSummary = nil }
            if let original, original.date != date { entry.timeSource = "edited" }
            entry.merchant = name.trimmingCharacters(in: .whitespacesAndNewlines); entry.cents = n; entry.date = date; entry.category = category; entry.fuel = fuel
            let description = entryDescription.trimmingCharacters(in: .whitespacesAndNewlines)
            entry.entryDescription = description.isEmpty ? nil : description
            var fx = try foreign()
            if let old = original?.foreign, old.currency == currency, old.quote.text == rate { fx?.quote = old.quote }
            else if let saved = model.ledger.rates[currency], saved.text == rate { fx?.quote = saved }
            else if fx != nil { fx?.quote.source = "Manual"; fx?.quote.date = Date() }
            entry.foreign = fx
            let previousCharges = entry.charges
            entry.charges = chargesEnabled ? try ExpenseCharges.draft(currency: currency, subtotal: chargeSubtotal, sst: sstPercent, service: servicePercent, rounding: chargeRounding) : nil
            if entry.charges != previousCharges { entry.receiptSummary = nil }
            try entry.validateCharges()
            entry.paidByFriend = friendPays ? payerName.trimmingCharacters(in: .whitespacesAndNewlines) : nil
            let savedItems = try itemDrafts.map { try $0.savedItem() }
            let byItem = savedItems.contains { $0.ownership != nil }
            if let original, original.refunded > 0 {
                guard entry.cents == original.cents, entry.date == original.date, entry.foreign == original.foreign, entry.paidByFriend == original.paidByFriend else { throw reviewError("已有退款，请先撤销退款再修改金额或日期。", "Undo refunds before changing amount or date.", "Batalkan bayaran balik sebelum mengubah amaun atau tarikh.") }
            }
            if !byItem {
            if !splitting && (original?.shares.contains { !$0.repayments.isEmpty } ?? false) { throw LedgerError.invalid(tr("请先撤销已有还款。", "Undo repayments before removing the split.", "Batalkan bayaran balik sebelum membuang pembahagian.")) }
            if friendPays {
                guard !(original?.shares.contains { !$0.repayments.isEmpty || !($0.returns ?? []).isEmpty } ?? false) else { throw settlementError("请先撤销已有还款再更改付款人。", "Undo existing repayments before changing payer.", "Batalkan bayaran sedia ada sebelum menukar pembayar.") }
                entry.shares = [Share(id: people.first?.id ?? UUID().uuidString, name: payerName.trimmingCharacters(in: .whitespacesAndNewlines), cents: try friendPaidShare(n))]
            } else if splitting {
                let values: [Int]
                if equal { values = equalShares(total: n, count: people.count, includeMe: includeMe) }
                else { values = try people.map { p in if p.amount == "0" || p.amount == "0.00" { return 0 }; return try toCents(p.amount) } }
                entry.shares = zip(people, values).map { p, v in Share(id: p.id, name: p.name.trimmingCharacters(in: .whitespacesAndNewlines), cents: v, repayments: p.repayments) }
                guard !entry.shares.contains(where: { $0.repayments.contains { $0.date < Calendar.current.startOfDay(for: date) } }) else { throw LedgerError.invalid(tr("付款日期不能晚于还款。", "Payment date cannot be after repayment.", "Tarikh bayaran tidak boleh selepas bayaran balik.")) }
            } else { entry.shares = [] }
            }
            entry = try entry.replacingItems(savedItems, allowedCategories: model.ledger.categoryNames)
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
            if reimbursementEnabled {
                entry.reimbursement = ReimbursementClaim(recipient: reimbursementRecipient.trimmingCharacters(in: .whitespacesAndNewlines),
                    cents: try toCents(reimbursementAmount),
                    receipts: entry.reimbursement?.receipts ?? [])
            } else {
                guard entry.reimbursement?.receipts.isEmpty ?? true else {
                    throw reviewError("请先撤销到账记录，再取消报销。", "Undo receipts before removing reimbursement.", "Batalkan penerimaan sebelum membuang tuntutan.")
                }
                entry.reimbursement = nil
            }
            try entry.validateReimbursement()
            try await LedgerRefreshWorker.shared.saveExpense(entry, replacing: original, rememberCategory: rememberCategory && itemDrafts.isEmpty)
            await model.refresh(postRecurring: false)
            model.showSaved(message: tr("已记 ", "Recorded ", "Direkod ") + money(n), firstEntry: original == nil); dismiss(); onSaved?()
        } catch { self.error = error.localizedDescription; FeedbackHaptics.error() }
    }
}
struct RepayTarget: Identifiable { var id: String { share.id }; let expense: Expense; let share: Share }
struct FriendsView: View {
    @Environment(\.locale) private var uiLocale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject var model: LedgerModel
    @State private var settled = false
    @State private var adding = false
    private var balances: [FriendBalance] { model.friends }
    private var visible: [FriendBalance] { balances.filter { ($0.owed == 0 && $0.payable == 0) == settled } }
    var body: some View {
        let _ = uiLocale.identifier
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(tr("朋友还欠你", "Friends owe you", "Rakan berhutang kepada anda")).font(.subheadline).foregroundStyle(.secondary)
                        AnimatedMoney(cents: balances.reduce(0) { $0 + $1.owed }).font(.system(.title, design: .default, weight: .bold)).foregroundStyle(ink)
                        let payable = balances.reduce(0) { $0 + $1.payable }
                        if payable > 0 { Text(tr("我欠朋友：", "I owe friends: ", "Saya berhutang kepada rakan: ") + money(payable)).font(.subheadline).foregroundStyle(.orange) }
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
            }.yuejiListSurface().navigationTitle(tr("朋友分账", "Shared expenses", "Belanja dikongsi")).navigationBarTitleDisplayMode(.large)
                .toolbar { Button { adding = true } label: { Label(tr("新增代垫", "Add advance", "Tambah pendahuluan"), systemImage: "plus") } }
                .sheet(isPresented: $adding) { ExpenseEditor(original: nil, startWithSplit: true) }
        }
    }
}
struct FriendBalanceRow: View {
    @Environment(\.locale) private var uiLocale
    let friend: FriendBalance
    var body: some View {
        let _ = uiLocale.identifier
        HStack(spacing: 14) {
            Text(String(friend.name.prefix(1)).uppercased()).font(.headline)
                .frame(width: 44, height: 44).foregroundStyle(.teal)
                .background(Color.teal.opacity(0.12), in: Circle()).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(friend.name).font(.headline)
                if friend.owed == 0 && friend.payable == 0 {
                    Label(tr("已结清", "Settled", "Selesai"), systemImage: "checkmark.circle").font(.subheadline).foregroundStyle(.secondary)
                } else {
                    HStack { Text(tr("待收：", "To collect: ", "Belum diterima: ")); AnimatedMoney(cents: friend.owed) }
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                HStack { Text(tr("我欠朋友：", "I owe them: ", "Saya berhutang: ")); AnimatedMoney(cents: friend.payable) }.font(.caption).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(settlementDirection(friend.owed - friend.payable, name: friend.name))
                    AnimatedMoney(cents: abs(friend.owed - friend.payable))
                }.font(.caption).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 8)
    }
}
struct RepaymentView: View {
    @Environment(\.locale) private var uiLocale
    @EnvironmentObject var model: LedgerModel
    @Environment(\.dismiss) private var dismiss
    let target: RepayTarget
    @State private var amount = ""
    @State private var date = Date()
    @State private var error: String?
    @State private var initialized = false
    @State private var saving = false
    private var balance: Int {
        model.expenseDetail(id: target.expense.id)?.shareBalances[target.share.id] ?? 0
    }

    var body: some View {
        let _ = uiLocale.identifier
        NavigationStack {
            Form {
                LabeledContent(target.share.name, value: money(abs(balance)))
                TextField(balance < 0 ? tr("退回金额 · MYR", "Amount returned · MYR", "Amaun dipulangkan · MYR") : tr("收到金额 · MYR", "Amount received · MYR", "Amaun diterima · MYR"), text: $amount).keyboardType(.decimalPad)
                DatePicker(tr("还款日期", "Repayment date", "Tarikh bayaran balik"), selection: $date, displayedComponents: .date)
                Text(tr("还款只减少欠款，不重复计作收入。", "Repayments reduce debt and are not counted as new income.", "Bayaran balik mengurangkan hutang dan bukan pendapatan baharu."))
            }.yuejiListSurface().navigationTitle(tr("记录还款", "Repayment", "Bayaran balik")).navigationBarTitleDisplayMode(.inline).yuejiSheetSurface()
                .disabled(saving).interactiveDismissDisabled(saving)
                .onAppear { if !initialized { initialized = true; amount = Currency.input(abs(balance), "MYR") } }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button(tr("取消", "Cancel", "Batal")) { dismiss() }.disabled(saving) }
                    ToolbarItem(placement: .confirmationAction) { Button(action: save) { SaveActionLabel(saving: saving) }.yuejiPrimaryButton().disabled(saving) }
                }
                .alert(tr("无法保存", "Unable to save", "Tidak dapat menyimpan"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") {} } message: { Text(error ?? "") }
        }
    }
    private func save() {
        guard !saving else { return }
        do {
            let n = try toCents(amount), recordedDate = date, capturedTarget = target, returning = balance < 0
            saving = true
            Task {
                defer { saving = false }
                do {
                    try await model.mutate { ledger in
                        if returning { try ledger.returnToFriend(expenseID: capturedTarget.expense.id, shareID: capturedTarget.share.id, cents: n, date: recordedDate) }
                        else { try ledger.repay(expenseID: capturedTarget.expense.id, shareID: capturedTarget.share.id, cents: n, date: recordedDate) }
                    }
                    model.showSaved(); dismiss()
                } catch { self.error = error.localizedDescription }
            }
        } catch { self.error = error.localizedDescription }
    }
}
struct SaveActionLabel: View {
    @Environment(\.locale) private var uiLocale
    let saving: Bool
    var body: some View {
        let _ = uiLocale.identifier
        EditorSaveLabel(saving: saving)
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
    @Environment(\.locale) private var uiLocale
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
    @State private var backupBusy = false
    @State private var backupTask: Task<Void, Never>?
    @State private var backupRequest = UUID()
    var body: some View {
        let _ = uiLocale.identifier
        NavigationStack {
            if guideDestination == "appearance" { appearancePage }
            else if guideDestination == "categories" { categoriesPage }
            else if guideDestination == "backup" { backupPage }
            else if guideDestination == "about" { aboutPage }
            else {
            List {
                Section {
                    HStack(spacing: 16) {
                        Image("YueJiLogo").renderingMode(.original).resizable().scaledToFit().frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(tr("月记 YueJi", "YueJi", "YueJi")).font(.title3.weight(.semibold))
                            Text(tr("让每一笔，都清楚。", "Clarity in every entry.", "Jelas dalam setiap rekod.")).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 8)
                }


                Section {
                    NavigationLink { appearancePage } label: {
                        SimpleSettingsRow(title: tr("外观与语言", "Appearance & language", "Paparan & bahasa"), subtitle: tr("让月记更适合你", "Make YueJi feel like yours", "Sesuaikan YueJi untuk anda"), symbol: "circle.lefthalf.filled", color: .indigo)
                    }.guideTarget("settings.appearance")
                    NavigationLink { NotificationSettingsView() } label: {
                        SimpleSettingsRow(title: tr("提醒与通知", "Reminders & notifications", "Peringatan & notifikasi"), subtitle: tr("记账结果、每日提醒和预算", "Saved entries, daily reminders and budget", "Rekod, peringatan harian dan bajet"), symbol: "bell.fill", color: .orange)
                    }
                } header: { Text(tr("使用习惯", "Your preferences", "Pilihan anda")) }
                Section {
                    NavigationLink { AutomationSetupView() } label: {
                        SimpleSettingsRow(title: tr("自动记账", "Automatic recording", "Rekod automatik"), subtitle: "Apple Pay · TNG · Bank", symbol: "bolt.fill", color: .teal)
                    }
                    NavigationLink { categoriesPage } label: {
                        SimpleSettingsRow(title: tr("消费分类", "Spending categories", "Kategori belanja"), subtitle: tr("整理每一笔消费", "Keep spending organized", "Susun setiap belanja"), symbol: "square.grid.2x2.fill", color: .blue)
                    }
                    NavigationLink { RatesView() } label: {
                        SimpleSettingsRow(title: tr("外币记账", "Foreign currency", "Mata wang asing"), subtitle: tr("把外币消费换算成马币", "Convert spending to ringgit", "Tukar belanja kepada ringgit"), symbol: "globe", color: .green)
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
                        SimpleSettingsRow(title: tr("使用指南", "Getting started", "Panduan penggunaan"), subtitle: tr("一步步学会使用月记", "Learn YueJi step by step", "Belajar YueJi langkah demi langkah"), symbol: "book.fill", color: .green)
                    }
                } header: { Text(tr("备份与帮助", "Backups & help", "Sandaran & bantuan")) }
            }.yuejiListSurface().navigationTitle(tr("设置", "Settings", "Tetapan")).navigationBarTitleDisplayMode(.large)
                .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: "YueJi-\(monthKey(Date()))") { if case .failure(let e) = $0 { model.error = e.localizedDescription } }
                .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                    do { previewBackup(try result.get()) } catch { model.error = error.localizedDescription }
                }
                .sheet(isPresented: $showingUsageGuide) { UsageGuideView().yuejiSheetSurface().ledgerFeedback(modal: true) }
                .sheet(item: $restorePreview) { preview in
                    RestorePreviewView(preview: preview) { loadBackups() }.ledgerFeedback(modal: true)
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
        }.yuejiListSurface().navigationTitle(tr("外观与语言", "Appearance & language", "Paparan & bahasa"))
    }
    private var categoriesPage: some View {
        List {
            NavigationLink(tr("管理分类", "Manage categories", "Urus kategori")) { CategoriesView() }
            NavigationLink(tr("记住商户分类", "Remember merchant categories", "Ingat kategori peniaga")) { MerchantRulesView() }
        }.yuejiListSurface().navigationTitle(tr("消费分类", "Spending categories", "Kategori belanja"))
    }
    private var backupPage: some View {
        Form {
                Section(tr("保管好你的账本", "Keep your ledger safe", "Simpan lejar dengan selamat")) {
                    Text(tr("换手机或卸载前，请先把完整备份存到「文件」或 iCloud Drive。", "Save a complete backup to Files or iCloud Drive before changing phones or uninstalling.", "Simpan sandaran lengkap ke Files atau iCloud Drive sebelum menukar telefon atau menyahpasang.")).font(.footnote)
                    NavigationLink(tr("导出账单表格", "Export a spreadsheet", "Eksport hamparan")) { CSVExportView() }
                    Button(tr("保存一份完整备份", "Save a complete backup", "Simpan sandaran lengkap")) { exportBackup() }
                    Button(tr("从备份文件恢复", "Restore from a backup file", "Pulihkan daripada fail sandaran")) { if !backupBusy { importing = true } }
                    if FileManager.default.fileExists(atPath: LocalStore.shared.recoveryFile.path) {
                        Button(tr("恢复上次导入前的数据", "Recover data before last restore", "Pulihkan data sebelum pemulihan terakhir")) {
                            previewBackup(LocalStore.shared.recoveryFile)
                        }
                    }
                    DisclosureGroup(tr("找回较早的账本", "Recover an earlier ledger", "Pulihkan lejar terdahulu")) {
                    ForEach(backups, id: \.self) { url in Button { previewBackup(url) } label: {
                        Text(tr("恢复：", "Restore: ", "Pulihkan: ") + backupTitle(url))
                    } }
                    }
                }

        }.yuejiListSurface().disabled(backupBusy)
            .overlay { if backupBusy { ProgressView().accessibilityLabel(tr("正在处理备份", "Processing backup", "Memproses sandaran")).allowsHitTesting(false) } }
            .navigationTitle(tr("备份与导出", "Backups & export", "Sandaran & eksport")).onAppear { loadBackups() }
            .onDisappear { backupTask?.cancel(); backupRequest = UUID(); backupBusy = false }
    }
    private var aboutPage: some View {
        List {
            Text(installedVersionLabel)
            Text(tr("如果通过 AltStore 安装，请按时刷新月记，以免无法打开或中断自动记账。", "If installed with AltStore, refresh YueJi on time to keep the app and automatic recording available.", "Jika dipasang melalui AltStore, segarkan YueJi tepat pada masanya supaya aplikasi dan rekod automatik terus tersedia."))
        }.yuejiListSurface().navigationTitle(tr("关于月记", "About YueJi", "Tentang YueJi"))
    }
    private func loadBackups() {
        guard !model.isPreview else { return }
        Task {
            do { backups = try await LedgerRefreshWorker.shared.backups() }
            catch { model.error = error.localizedDescription }
        }
    }
    private func previewBackup(_ url: URL) {
        guard !backupBusy, restorePreview == nil else { return }
        let request = UUID(); backupRequest = request; backupBusy = true
        backupTask = Task {
            defer { if backupRequest == request { backupBusy = false } }
            do {
                let preview = try await LedgerRefreshWorker.shared.preview(url: url)
                guard !Task.isCancelled, backupRequest == request else { return }
                restorePreview = preview
            } catch is CancellationError { return }
            catch { if !Task.isCancelled, backupRequest == request { model.error = error.localizedDescription } }
        }
    }
    private func exportBackup() {
        guard !backupBusy else { return }
        let request = UUID(); backupRequest = request; backupBusy = true
        backupTask = Task {
            defer { if backupRequest == request { backupBusy = false } }
            do {
                let data = try await LedgerRefreshWorker.shared.exportBackup()
                guard !Task.isCancelled, backupRequest == request else { return }
                document = LedgerDocument(data: data); exporting = true
            } catch is CancellationError { return }
            catch { if !Task.isCancelled, backupRequest == request { model.error = error.localizedDescription } }
        }
    }
    private func backupTitle(_ url: URL) -> String { guard let s = url.lastPathComponent.split(separator: "-").first, let ms = Double(s) else { return url.lastPathComponent }; return dateLabel(Date(timeIntervalSince1970: ms / 1000), time: true) }
}
struct ShortcutHelpView: View {
    @Environment(\.locale) private var uiLocale
    var body: some View {
        let _ = uiLocale.identifier
        ShortcutSetupGuide(provider: .applePay)
    }
}

enum ShortcutSetupProvider: Equatable { case applePay, tng }

struct ShortcutSetupGuide: View {
    @Environment(\.locale) private var uiLocale
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
        let _ = uiLocale.identifier
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
                                    }.yuejiSecondaryButton().buttonBorderShape(.capsule)
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
    @Environment(\.locale) private var uiLocale
    let title: String
    let subtitle: String
    let symbol: String
    let color: Color
    var body: some View {
        let _ = uiLocale.identifier
        HStack(spacing: 14) {
            Image(systemName: symbol).font(.body.weight(.medium))
                .foregroundStyle(.white).frame(width: 34, height: 34)
                .background(color, in: RoundedRectangle(cornerRadius: 8))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.body).foregroundStyle(.primary)
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 6)
    }
}


struct AutomationSetupView: View {
    @Environment(\.locale) private var uiLocale
    var body: some View {
        let _ = uiLocale.identifier
        List {
            Section {
                NavigationLink { ShortcutHelpView() } label: {
                    SimpleSettingsRow(title: "Apple Pay", subtitle: tr("付款后记录消费", "Record after payment", "Rekod selepas bayaran"), symbol: "creditcard.fill", color: .blue)
                }.guideTarget("automation.apple")
                NavigationLink { TNGInboxView() } label: {
                    SimpleSettingsRow(title: tr("银行与 TNG", "Banks and TNG", "Bank dan TNG"), subtitle: tr("设置付款记录，确认收到的交易", "Set up recording and review transactions", "Sediakan rekod dan semak transaksi"), symbol: "bell.badge.fill", color: .teal)
                }.guideTarget("automation.tng")
            } footer: { Text(tr("跟着说明在「快捷指令」设置一次。之后收到的付款资料会交给月记处理。", "Follow the steps in Shortcuts once. Payment details it receives can then be sent to YueJi.", "Ikut langkah dalam Pintasan sekali. Butiran bayaran yang diterima kemudian boleh dihantar ke YueJi.")) }
            Section {
                NavigationLink(tr("最近自动记账", "Recent automatic entries", "Rekod automatik terkini")) { AutomationStatusView() }
            }
        }.yuejiListSurface().navigationTitle(tr("自动记账", "Automatic recording", "Rekod automatik")).navigationBarTitleDisplayMode(.inline)
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
private struct YueJiSecondaryButton: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 26.0, *), !reduceTransparency {
            content.buttonStyle(.glass)
        } else { content.buttonStyle(.bordered) }
    }
}
extension View {
    func yuejiPrimaryButton() -> some View { modifier(YueJiPrimaryButton()) }
    func yuejiSecondaryButton() -> some View { modifier(YueJiSecondaryButton()) }
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


// Opt in only the read-only transaction route. Editor sheets retain the system
// sheet transition and its adaptive-presentation delegate for unsaved drafts.
private struct ExpenseCardDestination: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let id: String
    let namespace: Namespace.ID
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 18.0, *), !reduceMotion {
            content.navigationTransition(.zoom(sourceID: id, in: namespace))
        } else { content }
    }
}

private struct ExpenseCardSource: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let id: String
    let namespace: Namespace.ID
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 18.0, *), !reduceMotion {
            content.matchedTransitionSource(id: id, in: namespace)
        } else { content }
    }
}

private struct YueJiZoomDestination: ViewModifier {
    let id: String
    let namespace: Namespace.ID
    func body(content: Content) -> some View { content }
}

private struct YueJiZoomSource: ViewModifier {
    let id: String
    let namespace: Namespace.ID
    func body(content: Content) -> some View { content }
}
// Existing guide/source IDs remain stable; navigation uses the native system transitions.

extension View {
    func expenseCardDestination(id: String, namespace: Namespace.ID) -> some View {
        modifier(ExpenseCardDestination(id: id, namespace: namespace))
    }
    func expenseCardSource(id: String, namespace: Namespace.ID) -> some View {
        modifier(ExpenseCardSource(id: id, namespace: namespace))
    }
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
    @Environment(\.locale) private var uiLocale
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
        let _ = uiLocale.identifier
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
        case 2: return tng ? tr("第三步：正文接 Body，标题接 Title。", "3. Connect Body and Title.", "3. Sambungkan Body dan Title.") : tr("第三步：连接金额和商户；时间默认取自动化接收时刻。", "3. Connect amount and merchant; time defaults to automation receipt.", "3. Sambung amaun dan peniaga; masa lalai ialah masa automasi diterima.")
        case 3: return tr("第四步：按系统选项允许自动运行。", "4. Enable automatic runs using the system options.", "4. Benarkan jalan automatik mengikut pilihan sistem.")
        default: return tr("最后：回月记核对运行结果。演示不会替你启用。", "Finally, check YueJi's activity log. This demo does not enable it.", "Akhir sekali, semak log YueJi. Demo ini tidak mengaktifkannya.")
        }
    }
}

private struct GuideTouchIndicator: View {
    @Environment(\.locale) private var uiLocale
    let phase: Int
    let action: GuideGesture
    let measured: CGRect
    private var destination: CGPoint {
        CGPoint(x: measured.midX, y: measured.minY + measured.height * action.position)
    }
    var body: some View {
        let _ = uiLocale.identifier
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
    @Environment(\.locale) private var uiLocale
    let screen: GuideScreen
    let action: GuideGesture?
    let gesturePhase: Int
    @State private var measuredTargets: [String: CGRect] = [:]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        let _ = uiLocale.identifier
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
    @Environment(\.locale) private var uiLocale
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
        let _ = uiLocale.identifier
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
                    if provider == .applePay {
                        divider(); row(tr("时间", "Time", "Masa"), tr("自动取接收时刻", "Use received time", "Masa diterima"))
                        divider(); row(tr("使用指定交易时间", "Use supplied time", "Guna masa diberikan"), tr("关闭 · 仅补录时开启", "Off · enable for imports", "Tutup · buka untuk import"))
                    }
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
/// Code-native mascot layers keep eyes and body independent and crisp at any size.
private struct MoonBody: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0.56, y: 0.08))
        p.addCurve(to: CGPoint(x: 0.12, y: 0.70), control1: CGPoint(x: 0.13, y: 0.08), control2: CGPoint(x: -0.04, y: 0.40))
        p.addCurve(to: CGPoint(x: 0.80, y: 0.86), control1: CGPoint(x: 0.23, y: 1.03), control2: CGPoint(x: 0.60, y: 1.03))
        p.addCurve(to: CGPoint(x: 0.94, y: 0.52), control1: CGPoint(x: 0.92, y: 0.77), control2: CGPoint(x: 0.99, y: 0.49))
        p.addCurve(to: CGPoint(x: 0.48, y: 0.53), control1: CGPoint(x: 0.82, y: 0.65), control2: CGPoint(x: 0.62, y: 0.65))
        p.addCurve(to: CGPoint(x: 0.56, y: 0.08), control1: CGPoint(x: 0.33, y: 0.40), control2: CGPoint(x: 0.37, y: 0.21))
        p.closeSubpath()
        return p.applying(CGAffineTransform(scaleX: r.width, y: r.height)).applying(CGAffineTransform(translationX: r.minX, y: r.minY))
    }
}

enum MoonGesture: String { case hello, dance, star, cuddle }

struct MoonBuddy: View {
    @Environment(\.locale) private var uiLocale
    var size: CGFloat = 100
    var celebrating = false
    var animated = true
    var reaction: UUID? = nil
    var gesture: MoonGesture = .hello
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("playfulAnimations") private var playful = true
    @State private var lift: CGFloat = 0
    @State private var stretch: CGFloat = 1
    @State private var tilt = 0.0
    @State private var blink = false
    @State private var sparkle = false
    private let navy = Color(red: 0.04, green: 0.08, blue: 0.22)
    private var motion: Bool { animated && playful && !reduceMotion }
    private var animationKey: String { "\(motion)-\(gesture.rawValue)-\(reaction?.uuidString ?? "once")" }
    var body: some View {
        let _ = uiLocale.identifier
        ZStack {
            Ellipse().fill(Color.blue.opacity(0.12)).frame(width: size * 0.62, height: size * 0.07)
                .blur(radius: size * 0.035).offset(y: size * 0.46).scaleEffect(lift < 0 ? 0.82 : 1)
            ZStack {
                MoonBody().fill(LinearGradient(colors: [Color(red: 1, green: 1, blue: 0.91), Color(red: 1, green: 0.89, blue: 0.53), Color(red: 1, green: 0.74, blue: 0.23)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .shadow(color: Color.orange.opacity(0.2), radius: size * 0.04, y: size * 0.025)
                Ellipse().fill(Color.orange.opacity(0.35)).frame(width: size * 0.09, height: size * 0.065).offset(x: -size * 0.24, y: size * 0.22)
                Ellipse().fill(Color.orange.opacity(0.35)).frame(width: size * 0.09, height: size * 0.065).offset(x: size * 0.15, y: size * 0.29)
                eye.offset(x: -size * 0.15, y: size * 0.17)
                eye.offset(x: size * 0.065, y: size * 0.23)
                Path { p in
                    p.move(to: CGPoint(x: size * 0.40, y: size * 0.76))
                    p.addQuadCurve(to: CGPoint(x: size * 0.50, y: size * 0.79), control: CGPoint(x: size * 0.435, y: size * 0.85))
                }.stroke(navy, style: StrokeStyle(lineWidth: size * 0.028, lineCap: .round))
                Image(systemName: "sparkle").font(.system(size: size * 0.23, weight: .medium))
                    .foregroundStyle(Color(red: 1, green: 0.83, blue: 0.30))
                    .shadow(color: .yellow.opacity(0.3), radius: size * 0.04)
                    .scaleEffect(sparkle ? 1.18 : 0.85).rotationEffect(.degrees(sparkle ? 12 : -8))
                    .offset(x: size * 0.22, y: -size * 0.17)
                if celebrating {
                    ForEach(0..<6, id: \.self) { i in
                        let angle = Double(i) * .pi / 3
                        Image(systemName: "sparkle").font(.system(size: size * 0.075))
                            .foregroundStyle(i.isMultiple(of: 2) ? Color.orange : Color.blue)
                            .offset(x: cos(angle) * size * (sparkle ? 0.58 : 0.35), y: sin(angle) * size * (sparkle ? 0.55 : 0.32))
                            .opacity(sparkle ? 1 : 0)
                    }
                }
            }.frame(width: size, height: size)
                .scaleEffect(x: 2 - stretch, y: stretch, anchor: .bottom)
                .rotationEffect(.degrees(tilt)).offset(y: lift)
        }.frame(width: size, height: size)
            .accessibilityHidden(true)
            .task(id: animationKey) {
                lift = 0; stretch = 1; tilt = 0; blink = false; sparkle = !motion
                guard motion else { return }
                do {
                    withAnimation(.easeInOut(duration: 0.12)) { stretch = 0.90 }
                    try await Task.sleep(for: .milliseconds(120))
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.6)) {
                        lift = -size * (celebrating ? 0.15 : 0.065); stretch = 1.04; tilt = -8; sparkle = true
                    }
                    try await Task.sleep(for: .milliseconds(240))
                    withAnimation(.spring(response: 0.36, dampingFraction: 0.57)) { lift = 0; stretch = 1; tilt = 4 }
                    try await Task.sleep(for: .milliseconds(200))
                    withAnimation(.easeInOut(duration: 0.10)) { blink = true }
                    try await Task.sleep(for: .milliseconds(120))
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { blink = false; tilt = 0 }
                    switch gesture {
                    case .hello: break
                    case .dance:
                        for beat in 0..<6 {
                            try await Task.sleep(for: .milliseconds(150))
                            withAnimation(.spring(response: 0.22, dampingFraction: 0.55)) {
                                tilt = beat.isMultiple(of: 2) ? -19 : 19
                                lift = beat.isMultiple(of: 2) ? -size * 0.10 : 0
                                stretch = beat.isMultiple(of: 2) ? 1.07 : 0.94
                            }
                        }
                    case .star:
                        withAnimation(.spring(response: 0.65, dampingFraction: 0.65)) {
                            tilt = 360; lift = -size * 0.18; sparkle = true
                        }
                        try await Task.sleep(for: .milliseconds(650))
                    case .cuddle:
                        withAnimation(.easeInOut(duration: 0.3)) { blink = true; stretch = 0.88; tilt = -12 }
                        try await Task.sleep(for: .milliseconds(650))
                    }
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                        lift = 0; stretch = 1; tilt = 0; blink = false
                    }
                } catch { return }
            }
    }
    private var eye: some View {
        Ellipse().fill(navy).frame(width: size * 0.06, height: size * 0.09)
            .overlay(alignment: .topTrailing) {
                Circle().fill(.white).frame(width: size * 0.017, height: size * 0.017).padding(size * 0.01)
            }.scaleEffect(y: blink ? 0.12 : 1)
    }
}

private struct NotificationBannerCard: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let title: String
    var message: String = ""
    var symbol = "checkmark.circle.fill"
    var color = Color.green
    let interaction: BannerInteraction
    var actionTitle: String? = nil
    var actionEnabled = true
    var action: (() -> Void)? = nil
    private var label: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: symbol).font(.title3.weight(.medium)).foregroundStyle(color)
                .frame(width: 28, height: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold)).lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                if !message.isEmpty && message != title {
                    Text(message).font(.footnote).foregroundStyle(.secondary).lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.foregroundStyle(.primary).frame(minHeight: 44)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
        HStack(spacing: 4) {
            if let action, actionTitle == nil {
                Button { if interaction.canActivate { action() } } label: { label.contentShape(Rectangle()) }
                    .buttonStyle(.plain).accessibilityLabel(title + (message.isEmpty ? "" : ". " + message))
                    .accessibilityAction { if !interaction.exiting { action() } }
            } else { label.accessibilityElement(children: .ignore).accessibilityLabel(title + (message.isEmpty ? "" : ". " + message)) }
            if !typeSize.isAccessibilitySize { explicitAction }
            Button { if interaction.canActivate { interaction.dismiss?() } } label: {
                Image(systemName: "xmark").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel(tr("关闭提示", "Dismiss notice", "Tutup notis"))
                .accessibilityAction { interaction.dismiss?() }
        }
        if typeSize.isAccessibilitySize { explicitAction.padding(.leading, 40) }
        }.padding(.leading, 12).padding(.trailing, 4).padding(.vertical, 6)
            .modifier(NotificationBannerSurface())
            .accessibilityElement(children: .contain)
            .accessibilityHint(tr("向左、向右或向上滑动可关闭提示。", "Swipe left, right, or up to dismiss.", "Leret ke kiri, kanan atau atas untuk menutup."))
            .accessibilityAction(named: Text(tr("关闭提示", "Dismiss notice", "Tutup notis"))) { interaction.dismiss?() }
            .accessibilityAction(.escape) { interaction.dismiss?() }
    }
    @ViewBuilder private var explicitAction: some View {
        if let actionTitle, let action {
            Button { if interaction.canActivate { action() } } label: {
                Text(actionTitle).font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 8).frame(minWidth: 44, minHeight: 44)
            }.buttonStyle(.plain).foregroundStyle(Color.accentColor).disabled(!actionEnabled)
                .accessibilityAction { if actionEnabled && !interaction.exiting { action() } }
        }
    }
}

private struct OpeningAnimationView: View {
    @Environment(\.locale) private var uiLocale
    var sound = true
    var onFinished: () -> Void
    @Environment(\.scenePhase) private var phase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("playfulAnimations") private var playful = true
    @State private var entered = false
    @State private var playedSound = false
    private var animates: Bool { playful && !reduceMotion }
    var body: some View {
        let _ = uiLocale.identifier
        ZStack {
            Color("LaunchBackground").ignoresSafeArea()
            VStack(spacing: 20) {
                Image("YueJiLogo").resizable().scaledToFit().frame(width: 112, height: 112)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .shadow(color: .black.opacity(0.12), radius: 14, y: 8)
                    .accessibilityHidden(true)
                VStack(spacing: 6) {
                    Text(tr("月记", "YueJi", "YueJi")).font(.largeTitle.bold())
                    Text(tr("让每一笔，都清楚。", "Clarity in every entry.", "Jelas dalam setiap rekod."))
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }.padding(24)
            .scaleEffect(entered || !animates ? 1 : 0.96)
            .offset(y: entered || !animates ? 0 : 6)
        }
        .task {
            // Finishing the optional opening must not depend on scene callbacks.
            // Give the initial logo frame time to appear without blocking the UI.
            do { try await Task.sleep(for: .milliseconds(30)) } catch { return }
            withAnimation(animates ? YueJiMotion.detail : nil) { entered = true }
            do { try await Task.sleep(for: .milliseconds(animates ? 350 : 100)) }
            catch { return }
            guard !Task.isCancelled else { return }
            onFinished()
        }
        .task(id: phase) {
            // Sound still waits for foreground activation; screen readiness does not.
            guard phase == .active, sound, !playedSound else { return }
            FeedbackSounds.shared.play(.launch)
            playedSound = true
        }
        .accessibilityElement(children: .ignore).accessibilityLabel(tr("月记 YueJi", "YueJi", "YueJi"))
    }
}


/// Exactly one presentation layer renders feedback: the top modal, or the main page.
private struct LedgerFeedbackHost: ViewModifier {
    @EnvironmentObject private var model: LedgerModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var owner = UUID()
    var modal = false
    private var visible: Bool { model.feedbackOwners.isVisible(modal ? owner : nil) }
    private var bannerTransition: AnyTransition {
        reduceMotion ? .opacity : .asymmetric(
            insertion: .offset(y: -32).combined(with: .opacity),
            // UIKit has already moved a swiped banner offscreen. Do not run
            // a second directional exit or make the outgoing card reappear.
            removal: .opacity.animation(.easeOut(duration: 0.14)))
    }
    private var topIdentity: String? {
        guard visible, model.didFinishLaunch else { return nil }
        if model.activeBanner == .undo { return model.undoToken.uuidString }
        if let notice = model.foregroundNotice { return notice.id.uuidString }
        if model.newTNGCount > 0 { return model.newTNGToken.uuidString }
        if model.undoEntries.isEmpty { return model.savedNotice?.uuidString }
        return nil
    }
    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                // Keep the navigation bar's Back/Close and trailing buttons fully reachable.
                topBanner.frame(maxWidth: 520).padding(.horizontal, 20).padding(.top, 52)
                    .animation(reduceMotion ? .easeOut(duration: 0.14) : YueJiMotion.banner, value: topIdentity)
            }
            .onAppear { if modal { model.feedbackOwners.present(owner) } }
            .onDisappear { if modal { model.feedbackOwners.dismiss(owner) } }
    }
    @ViewBuilder private var topBanner: some View {
        if visible, model.didFinishLaunch {
            if model.activeBanner == .undo {
                let token = model.undoToken
                SwipeDismissBanner(onDismiss: { model.dismissDeletionFeedback(id: token) },
                    onInteraction: { model.setBannerInteraction(id: token.uuidString, active: $0) }) { interaction in
                    NotificationBannerCard(title: String(model.undoEntries.count) + tr(" 笔已删除", " deleted", " dipadam"),
                        symbol: "trash", color: .gray, interaction: interaction,
                        actionTitle: tr("撤销", "Undo", "Batal padam"), actionEnabled: !model.deletionInFlight,
                        action: { Task { await model.undoDeletion() } })
                }.id(token).transition(bannerTransition)
            } else if let notice = model.foregroundNotice {
                SwipeDismissBanner(onDismiss: { model.dismissForegroundNotice(id: notice.id) },
                    onInteraction: { model.setBannerInteraction(id: notice.id.uuidString, active: $0) }) { interaction in
                    NotificationBannerCard(title: notice.title, message: notice.message, symbol: "bell.badge.fill", color: .blue,
                        interaction: interaction, action: notice.destination == nil ? nil : {
                            guard model.foregroundNotice?.id == notice.id, let destination = notice.destination else { return }
                            model.dismissForegroundNotice(id: notice.id)
                            UserDefaults.standard.set(destination, forKey: "pendingNotificationDestination")
                            NotificationCenter.default.post(name: .init("YueJiNotificationDestination"), object: nil)
                        })
                }.id(notice.id).transition(bannerTransition)
            } else if model.newTNGCount > 0 {
                let token = model.newTNGToken
                SwipeDismissBanner(onDismiss: { model.dismissNewTNG(id: token) },
                    onInteraction: { model.setBannerInteraction(id: token.uuidString, active: $0) }) { interaction in
                    NotificationBannerCard(title: model.newTNGCount == 1
                        ? tr("新增 1 笔记录", "1 new record", "1 rekod baharu")
                        : tr("新增 \(model.newTNGCount) 笔记录", "\(model.newTNGCount) new records", "\(model.newTNGCount) rekod baharu"),
                        message: tr("银行 · TNG", "Bank · TNG", "Bank · TNG"),
                        symbol: "tray.and.arrow.down", color: .blue, interaction: interaction, action: {
                            guard model.newTNGToken == token, model.newTNGCount > 0 else { return }
                            model.dismissNewTNG(id: token)
                            NotificationCenter.default.post(name: .init("YueJiShowInbox"), object: nil)
                        })
                }.id(token).transition(bannerTransition)
            } else if model.undoEntries.isEmpty, let token = model.savedNotice {
                SwipeDismissBanner(onDismiss: { model.dismissSavedNotice(id: token) },
                    onInteraction: { model.setBannerInteraction(id: token.uuidString, active: $0) }) { interaction in
                    NotificationBannerCard(title: model.feedbackMessage, interaction: interaction)
                }.id(token).transition(bannerTransition)
            }
        }
    }
}

extension View {
    func ledgerFeedback(modal: Bool = false) -> some View { modifier(LedgerFeedbackHost(modal: modal)) }
}


struct AutomaticRecordDeletion: ViewModifier {
    @EnvironmentObject private var model: LedgerModel
    @Environment(\.dismiss) private var dismiss
    let notice: TNGNotice?
    var detail = false
    @State private var confirming = false
    @State private var failure: String?
    private var deleteButton: some View {
        Button(role: .destructive) { confirming = true } label: {
            Label(tr("删除", "Delete", "Padam"), systemImage: "trash")
        }.disabled(notice == nil)
    }
    func body(content: Content) -> some View {
        content
            .toolbar { if detail { ToolbarItem(placement: .topBarTrailing) { deleteButton } } }
            .confirmationDialog(tr("删除这笔自动记录？", "Delete this automatic record?", "Padam rekod automatik ini?"), isPresented: $confirming, titleVisibility: .visible) {
                Button(tr("删除", "Delete", "Padam"), role: .destructive) {
                    guard let notice else { return }
                    Task {
                        do { try await model.deleteAutomaticRecord(notice); if detail { dismiss() } }
                        catch { failure = error.localizedDescription }
                    }
                }
                Button(tr("取消", "Cancel", "Batal"), role: .cancel) {}
            } message: {
                Text(tr("关联消费及其分账、退款会一并删除；此收款生成的还款也会撤销。其他银行的记录不受影响。删除后可撤销。", "Linked expenses, splits and refunds are deleted; repayments created by this receipt are reversed. Other bank records stay. You can undo this deletion.", "Belanja, bahagian dan pulangan berkaitan dipadam; bayaran rakan daripada penerimaan ini dibatalkan. Rekod bank lain kekal. Pemadaman boleh dibatalkan."))
            }
            .alert(tr("无法删除", "Unable to delete", "Tidak dapat memadam"), isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
                Button("OK", role: .cancel) { failure = nil }
            } message: { Text(failure ?? "") }
    }
}


/// Swipe only requests confirmation; the stable list owns the dialog.
struct AutomaticRecordDeleteActions: ViewModifier {
    let request: () -> Void
    func body(content: Content) -> some View {
        content
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(action: request) {
                    Label(tr("删除", "Delete", "Padam"), systemImage: "trash")
                }.tint(.red)
            }
            .contextMenu {
                Button(tr("删除", "Delete", "Padam"), systemImage: "trash", role: .destructive, action: request)
            }
    }
}
struct AutomaticRecordDeletionConfirmation: ViewModifier {
    @EnvironmentObject private var model: LedgerModel
    @Binding var notice: TNGNotice?
    @State private var failure: String?
    func body(content: Content) -> some View {
        content.confirmationDialog(
            tr("删除这笔自动记录？", "Delete this automatic record?", "Padam rekod automatik ini?"),
            isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } }),
            titleVisibility: .visible, presenting: notice
        ) { selected in
            Button(tr("删除", "Delete", "Padam"), role: .destructive) {
                Task {
                    do { try await model.deleteAutomaticRecord(selected) }
                    catch { failure = error.localizedDescription }
                }
            }
            Button(tr("取消", "Cancel", "Batal"), role: .cancel) {}
        } message: { selected in
            Text(sourceLabel(selected.provider) + " · " + money(selected.cents ?? 0) + "\n" + tr(
                "关联消费及分账、退款会一并删除；此收款生成的还款也会撤销。其他银行记录保留，删除后可撤销。",
                "Linked expenses, splits and refunds are deleted; repayments from this receipt are reversed. Other bank records stay. Deletion can be undone.",
                "Belanja, bahagian dan pulangan berkaitan dipadam; bayaran daripada penerimaan ini dibatalkan. Rekod bank lain kekal. Pemadaman boleh dibatalkan."))
        }
        .alert(tr("无法删除", "Unable to delete", "Tidak dapat memadam"), isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button("OK", role: .cancel) { failure = nil }
        } message: { Text(failure ?? "") }
    }
}


struct NotificationDestination: Identifiable {
    let id = UUID()
    let recordID: String
    let kind: String
    let action: String
}
struct NotificationDestinationView: View {
    @Environment(\.locale) private var uiLocale
    @EnvironmentObject var model: LedgerModel
    @Environment(\.dismiss) private var dismiss
    let target: NotificationDestination
    var body: some View {
        let _ = uiLocale.identifier
        Group {
            if target.kind == "expense", let entry = model.expense(id: target.recordID) {
                if target.action == "category" { ExpenseEditor(original: entry) }
                else { ExpenseDetailView(id: entry.id) }
            } else {
                NavigationStack {
                    Group {
                        if let notice = model.notice(id: target.recordID) {
                            if notice.kind == "incoming" { TNGIncomingView(id: notice.id) }
                            else if ["pending", "transfer"].contains(notice.status) { FinancialNoticeReviewView(id: notice.id) }
                            else { TNGNoticeView(id: notice.id) }
                        } else { Text(tr("这笔记录已删除或清理。", "This record has been deleted or cleared.", "Rekod ini telah dipadam atau dikosongkan.")) }
                    }.toolbar { ToolbarItem(placement: .confirmationAction) { Button(tr("完成", "Done", "Selesai")) { dismiss() } } }
                }
            }
        }.yuejiSheetSurface().ledgerFeedback(modal: true)
    }
}

#if DEBUG
/// Renders the actual screens with isolated sample data; never reads or writes the user's ledger.
private struct YueJiDesignPreviews: PreviewProvider {
    @MainActor static var previews: some View {
        Group {
            DashboardView().preferredColorScheme(.light).previewDisplayName("Overview · Light")
            DashboardView().preferredColorScheme(.dark).previewDisplayName("Overview · Dark")
            ExpensesView().preferredColorScheme(.light).previewDisplayName("Ledger · Light")
            SettingsView().preferredColorScheme(.dark).previewDisplayName("Settings · Dark")
            ExpenseEditor(original: nil).preferredColorScheme(.light).previewDisplayName("New expense · Light")
            ExpenseEditor(original: GuideSample.ledger().expenses.first).preferredColorScheme(.dark).previewDisplayName("Edit expense · Dark")
            ExpenseDetailView(id: "guide-lunch").preferredColorScheme(.dark).previewDisplayName("Entry details · Dark")
            ExpenseEditor(original: nil).environment(\.dynamicTypeSize, .accessibility3).previewDisplayName("New expense · Large text")
            DashboardView().environment(\.dynamicTypeSize, .accessibility3).previewDisplayName("Overview · Large text")
        }.environmentObject(LedgerModel(previewLedger: GuideSample.ledger()))
    }
}
#endif
