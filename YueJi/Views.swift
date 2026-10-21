import SwiftUI
import UniformTypeIdentifiers
import UIKit

private let ink = IslandTheme.accent

/// The app's visual tokens: Apple's own system colours, so every screen matches iOS 26/27
/// exactly, in light and dark mode. (The "Island" names are historical.)
enum IslandTheme {
    /// The app tint: the system blue, the accent of Apple's iOS 27 UI kit (#0088FF).
    static let accent = Color(uiColor: .systemBlue)
    /// Text/icons drawn on top of `accent` fills.
    static let onAccent = Color.white
    /// The system grouped background and its panels, as in Settings and Wallet.
    static let paper = Color(uiColor: .systemGroupedBackground)
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
    static let line = Color(uiColor: .separator)
}

/// Icon and category colours: the system palette, as in Settings and Apple Card.
/// Financial meaning (income green, spending red) stays separate.
enum IslandPalette {
    static let leaf = Color(uiColor: .systemIndigo)
    static let mint = Color(uiColor: .systemGreen)
    static let lagoon = Color(uiColor: .systemTeal)
    static let sky = Color(uiColor: .systemBlue)
    static let lavender = Color(uiColor: .systemPurple)
    static let berry = Color(uiColor: .systemPink)
    static let coral = Color(uiColor: .systemRed)
    static let pumpkin = Color(uiColor: .systemOrange)
    static let pebble = Color(uiColor: .systemGray)
}

/// Every list, page and sheet sits on the system grouped background.
/// Static: nothing here moves or takes touches.
struct IslandBackdrop: View {
    var body: some View {
        IslandTheme.paper
            .ignoresSafeArea().allowsHitTesting(false).accessibilityHidden(true)
    }
}

/// The tabs' root pages sit on the page of the kit's Mobile Banking app: the system grouped
/// background lit by three soft glows, rose at the top trailing corner, green on the leading
/// side and amber lower down, brighter on black than on light grey. Static and decorative;
/// Reduce Transparency and Increase Contrast keep the plain background.
struct AmbientGlowBackdrop: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        IslandTheme.paper
            .overlay {
                if !reduceTransparency && contrast != .increased {
                    GeometryReader { proxy in
                        let width = proxy.size.width, height = proxy.size.height
                        let dark = scheme == .dark
                        glow(Color(uiColor: .systemRed), strength: dark ? 0.42 : 0.16, diameter: width)
                            .position(x: width * 0.92, y: height * 0.06)
                        glow(Color(uiColor: .systemGreen), strength: dark ? 0.26 : 0.12, diameter: width * 0.9)
                            .position(x: width * 0.02, y: height * 0.34)
                        glow(Color(uiColor: .systemYellow), strength: dark ? 0.24 : 0.14, diameter: width * 0.9)
                            .position(x: width, y: height * 0.7)
                    }
                }
            }
            .ignoresSafeArea().allowsHitTesting(false).accessibilityHidden(true)
    }
    private func glow(_ color: Color, strength: Double, diameter: CGFloat) -> some View {
        Circle()
            .fill(RadialGradient(colors: [color.opacity(strength), color.opacity(0)],
                                 center: .center, startRadius: 0, endRadius: diameter / 2))
            .frame(width: diameter, height: diameter)
    }
}

/// The app's one motion language: calm, short springs with little or no overshoot, so
/// movement feels smooth and connected and never gets in the way. Prefer these over
/// one-off timings.
enum YueJiMotion {
    // Layout: rows, months, detail panels. No overshoot.
    static let standard = Animation.smooth(duration: 0.24)
    static let detail = Animation.smooth(duration: 0.32)
    static let month = Animation.smooth(duration: 0.42)
    static let rows = Animation.smooth(duration: 0.34)
    static let tone = Animation.easeInOut(duration: 0.55)
    /// Text and labels that change in place.
    static let content = Animation.smooth(duration: 0.35)
    /// Button and control presses.
    static let press = Animation.spring(duration: 0.22, bounce: 0.15)
    /// Chips, badges and small reveals.
    static let pop = Animation.spring(duration: 0.4, bounce: 0.15)
    /// Cards and empty states appearing.
    static let entrance = Animation.spring(duration: 0.55, bounce: 0.1)
    static let banner = Animation.spring(duration: 0.45, bounce: 0.12)
    /// Gauges, bars and charts filling.
    static let meter = Animation.spring(duration: 0.8, bounce: 0.08)
}

/// Move only the completed monthly summary, keeping navigation and row identity stable.
private struct MonthSummaryMotion: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let month: String?
    @State private var previousMonth: String?
    @State private var offset: CGFloat = 0
    @State private var opacity = 1.0
    func body(content: Content) -> some View {
        content.offset(x: reduceMotion ? 0 : offset).opacity(reduceMotion ? 1 : opacity)
            .task(id: month) {
                let previous = previousMonth
                previousMonth = month
                guard !reduceMotion, let previous, let month, previous != month else { return }
                var immediate = Transaction(animation: nil)
                immediate.disablesAnimations = true
                withTransaction(immediate) {
                    offset = month > previous ? 12 : -12
                    opacity = 0.75
                }
                do { try await Task.sleep(for: .milliseconds(16)) } catch {
                    withTransaction(immediate) { offset = 0; opacity = 1 }
                    return
                }
                withAnimation(YueJiMotion.standard) { offset = 0; opacity = 1 }
            }
    }
}

struct EditorSaveLabel: View {
    let saving: Bool
    var body: some View {
        // A checkmark, as sheets confirm in iOS 27 (Apple's UI kit); the accessibility
        // label stays "Save" for VoiceOver and UI tests.
        Image(systemName: "checkmark").fontWeight(.semibold)
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
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            // Liquid Glass: the system draws floating glass bars over the content with
            // its own scroll-edge effect, exactly as in iOS 26/27. MainView also sets the
            // app's light/dark choice on the window, so the bars always follow it.
            content.toolbarColorScheme(scheme, for: .navigationBar, .tabBar)
        } else {
            content
                // Keep native chrome in the same resolved theme as the page. A
                // visible background keeps the requested bar scheme in effect at
                // scroll edges as well as when content is beneath the bar.
                .toolbarColorScheme(scheme, for: .navigationBar, .tabBar)
                .toolbarBackground(.visible, for: .navigationBar, .tabBar)
        }
    }
}
/// The subtitle under a large title, as in iOS 26/27 and Apple's iOS 27 UI kit.
/// Earlier systems show the title alone.
private struct YueJiNavigationSubtitle: ViewModifier {
    let text: String
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.navigationSubtitle(Text(text))
        } else { content }
    }
}
extension View {
    func yuejiSubtitle(_ text: String) -> some View { modifier(YueJiNavigationSubtitle(text: text)) }
}
private struct YueJiListSurface: ViewModifier {
    /// The tabs' root pages get the kit's softly lit page; other lists stay plain.
    var glow = false
    func body(content: Content) -> some View {
        content.listStyle(.insetGrouped)
            .scrollDismissesKeyboard(.interactively)
            .scrollContentBackground(.hidden)
            .background { if glow { AmbientGlowBackdrop() } else { IslandBackdrop() } }
            .tint(IslandTheme.accent)
            .modifier(YueJiBarAppearance())
            .modifier(YueJiScrollEdge())
    }
}
/// Plain, edge-to-edge rows, as in Messages in the iOS 27 Builder kit, over the same softly
/// lit page as the other tabs: for the ledger's running list of payments. Its rows need
/// `.listRowBackground(Color.clear)` so the page shows through them.
private struct YueJiPlainListSurface: ViewModifier {
    func body(content: Content) -> some View {
        content.listStyle(.plain)
            .scrollDismissesKeyboard(.interactively)
            .scrollContentBackground(.hidden)
            .background { AmbientGlowBackdrop() }
            .tint(IslandTheme.accent)
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
    /// A tab's root list: the grouped list over the kit's softly lit page.
    func yuejiDashboardSurface() -> some View { modifier(YueJiListSurface(glow: true)) }
    func yuejiPlainListSurface() -> some View { modifier(YueJiPlainListSurface()) }
    func yuejiPageSurface() -> some View {
        scrollDismissesKeyboard(.interactively)
            .background(IslandBackdrop())
            .tint(IslandTheme.accent)
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
                .presentationBackground(IslandTheme.paper)
                .modifier(YueJiBarAppearance())
        } else {
            content.presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
                .presentationBackground(IslandTheme.paper)
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
            if reduceTransparency { IslandTheme.paper }
            // The capsule buttons already provide their own native material.
            // Keep this safe-area spacer clear during normal scrolling.
        }
    }
}

/// Opens Ledger on a month, as the Overview's "View all" does for its recent entries.
struct LedgerMonthRequest: Equatable {
    let month: Date
    let id = UUID()
}

struct MainView: View {
    @Environment(\.locale) private var uiLocale
    @EnvironmentObject var model: LedgerModel
    @Environment(\.scenePhase) private var phase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("completedUsageGuide") private var completedGuide = false
    @AppStorage("openingAnimationEnabled") private var openingEnabled = true
    @AppStorage("appAppearance") private var appearance = "system"
    @State private var showingGuide = false
    @State private var selectedTab = 0
    @State private var ledgerMonthRequest: LedgerMonthRequest?
    @State private var showingNewTNG = false
    @State private var pendingInbox = false
    @State private var notificationDestination: NotificationDestination?
    @State private var logoFinished = false
    private func finishLaunchIfReady() {
        withAnimation(reduceMotion ? nil : YueJiMotion.standard) {
            _ = model.finishLaunchIfReady(openingEnabled: openingEnabled, openingFinished: logoFinished)
        }
    }
    /// Apply the app's light/dark choice to the app window as well, so chrome UIKit draws
    /// (the glass bars, the status bar, alerts) always follows it, not only SwiftUI views.
    private func applyWindowAppearance(_ value: String) {
        let style: UIUserInterfaceStyle = value == "dark" ? .dark : (value == "light" ? .light : .unspecified)
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in scene.windows where window.windowLevel == .normal && window.overrideUserInterfaceStyle != style {
                window.overrideUserInterfaceStyle = style
            }
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
            DashboardView(openLedger: { month in
                ledgerMonthRequest = LedgerMonthRequest(month: month)
                selectedTab = 1
            }).ledgerFeedback().modifier(YueJiBarAppearance()).tag(0).tabItem { Label(tr("概览", "Overview", "Ringkasan"), systemImage: "chart.pie.fill") }
            ExpensesView(isActive: selectedTab == 1, monthRequest: $ledgerMonthRequest).ledgerFeedback().modifier(YueJiBarAppearance()).tag(1).tabItem { Label(tr("账本", "Ledger", "Lejar"), systemImage: "list.bullet.rectangle.fill") }
            RecurringView().ledgerFeedback().modifier(YueJiBarAppearance()).tag(2).tabItem { Label(tr("固定", "Recurring", "Berulang"), systemImage: "arrow.triangle.2.circlepath") }
            FriendsView().ledgerFeedback().modifier(YueJiBarAppearance()).tag(3).tabItem { Label(tr("分账", "Friends", "Rakan"), systemImage: "person.2.fill") }
            SettingsView().ledgerFeedback().modifier(YueJiBarAppearance()).tag(4).tabItem { Label(tr("设置", "Settings", "Tetapan"), systemImage: "gearshape.fill") }
        }.tint(ink).modifier(YueJiTabBarMotion())
    }
    var body: some View {
        let _ = uiLocale.identifier
        ZStack {
            Color("LaunchBackground").ignoresSafeArea()
            // Mount native navigation/toolbars in their interactive state. Mounting
            // them under allowsHitTesting(false), then flipping it at logo removal,
            // can leave the first toolbar button non-hittable on a cold launch.
            if model.didFinishLaunch {
                tabs
                    .transition(.identity)
            } else if !openingEnabled {
                YueJiLoadingView()
                    .accessibilityIdentifier("launch.loading")
            }
            if !model.didFinishLaunch && openingEnabled {
                OpeningAnimationView(sound: !model.isPreview, ready: model.loaded) {
                    logoFinished = true
                    finishLaunchIfReady()
                }
                // The departing visual layer must not intercept the ready toolbar, for
                // touches or for accessibility hit-testing.
                .allowsHitTesting(false)
                .accessibilityHidden(logoFinished)
                .transition(.opacity).zIndex(1)
                // Tap anywhere to skip. This catcher is separate from the fading layer and
                // leaves instantly (identity transition) when the app is ready, so it can
                // never cover the toolbar. Before the ledger loads, skipping just ends the
                // opening as soon as loading completes.
                Color.clear.contentShape(Rectangle()).ignoresSafeArea()
                    .onTapGesture {
                        logoFinished = true
                        // Let the opening leave the accessibility tree first, then finish.
                        Task { @MainActor in finishLaunchIfReady() }
                    }
                    .accessibilityHidden(true)
                    .transition(.identity).zIndex(2)
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
            .onChange(of: appearance, initial: true) { _, value in applyWindowAppearance(value) }
            .task(id: model.didFinishLaunch && phase == .active) {
                guard model.didFinishLaunch, phase == .active, !model.isPreview else { return }
                // Defer permission prompts, recovery and network updates until the opening ends.
                await LedgerNotifications.prepareAutomaticResultsAuthorization()
                await LedgerNotifications.refreshDailyReminder()
                // Reminders already fired make way for the next ones, in the current language.
                await RenewalReminders.sync(model.ledger)
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
                    Button(tr("完成", "Done", "Selesai"), systemImage: "checkmark") { showingNewTNG = false }
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
    @Environment(\.colorScheme) private var scheme
    @Binding var month: Date
    @State private var direction = 1
    @State private var choosingMonth = false
    @State private var selectedDate = Date()
    private var monthLabel: String { month.formatted(.dateTime.year().month(.wide).locale(Locale(identifier: AppLanguage.localeID))) }
    private var labelTransition: AnyTransition {
        reduceMotion ? .identity : .asymmetric(
            insertion: .opacity.combined(with: .offset(x: CGFloat(direction) * 16)),
            removal: .opacity.combined(with: .offset(x: CGFloat(direction) * -16)))
    }
    @ViewBuilder var body: some View {
        let _ = uiLocale.identifier
        // Glass chevrons either side of the month; on iOS 26 and later they share one
        // glass container, so they blend and morph like the system's own controls.
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 12) { controls }
        } else {
            controls
        }
    }
    private var controls: some View {
        HStack(spacing: 0) {
            GlassIconButton(symbol: "chevron.left") { shift(-1) }
                .accessibilityLabel(tr("上个月", "Previous month", "Bulan sebelumnya"))
            ZStack {
                Text(monthLabel).font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1).minimumScaleFactor(0.75)
                    .id(monthKey(month)).transition(labelTransition)
            }.animation(reduceMotion ? nil : YueJiMotion.month, value: monthKey(month))
                .frame(maxWidth: .infinity, minHeight: 44).clipped().contentShape(Rectangle())
                .accessibilityElement(children: .ignore).accessibilityLabel(monthLabel)
                .onTapGesture { selectedDate = month; choosingMonth = true }
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { selectedDate = month; choosingMonth = true }
                .simultaneousGesture(DragGesture(minimumDistance: 25).onEnded { value in
                    let dx = value.translation.width, dy = value.translation.height
                    guard abs(dx) > 45, abs(dx) > abs(dy) * 1.5 else { return }
                    shift(dx < 0 ? 1 : -1)
                })
                .accessibilityHint(tr("左右滑动切换月份", "Swipe left or right to change month", "Leret kiri atau kanan untuk menukar bulan"))
            GlassIconButton(symbol: "chevron.right") { shift(1) }
                .accessibilityLabel(tr("下个月", "Next month", "Bulan seterusnya"))
        }
        .sheet(isPresented: $choosingMonth) {
            NavigationStack {
                Form {
                    DatePicker(tr("选择月份", "Choose month", "Pilih bulan"), selection: $selectedDate, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                    Button(tr("回到本月", "Back to this month", "Kembali ke bulan ini")) { choose(Date()) }
                }.yuejiListSurface()
                    .navigationTitle(tr("月份", "Month", "Bulan")).navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button(tr("取消", "Cancel", "Batal"), systemImage: "xmark") { choosingMonth = false } }
                        ToolbarItem(placement: .confirmationAction) { Button(tr("完成", "Done", "Selesai"), systemImage: "checkmark") { choose(selectedDate) } }
                    }
            }.presentationDetents([.large]).yuejiSheetSurface()
        }
    }
    private func choose(_ value: Date) {
        direction = value >= month ? 1 : -1
        month = value; choosingMonth = false
        FeedbackHaptics.selection()
    }
    private func shift(_ n: Int) {
        direction = n
        FeedbackHaptics.selection()
        // Animate the label, amounts and bars locally; keep page/keyboard layout stable.
        withTransaction(Transaction(animation: nil)) { month = shiftedMonth(month, by: n) }
    }
}
/// Pages the Overview's quick actions and section links open.
private enum OverviewRoute: Hashable { case receipt, automation, savings, travel, comparison(Date) }

struct DashboardView: View {
    @Environment(\.locale) private var uiLocale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var guideFocus: String? = nil
    /// Shows Ledger on the given month; "View all" on the recent entries calls it.
    var openLedger: (Date) -> Void = { _ in }
    @Namespace private var navigationMotion
    @EnvironmentObject var model: LedgerModel
    @SceneStorage("overviewMonth") private var monthTimestamp = Date().timeIntervalSince1970
    /// Hides the spending summary's amounts and the trend values.
    @AppStorage("hideOverviewAmounts") private var hideAmounts = false
    /// The header amount, larger than a title like a banking app's balance; scales with Dynamic Type.
    @ScaledMetric(relativeTo: .largeTitle) private var heroSize: CGFloat = 44
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
    @State private var trend: [SpendingTrendPoint] = []
    @State private var loadedTrend: LedgerTimelineQuery?
    private var entries: [Expense] { summary.entries }
    private var personal: Int { summary.personal }
    private var budgetSpent: Int { entries.filter { $0.tripID == nil }.reduce(0) { $0 + $1.personalSpending } }
    private var budget: Int { model.ledger.budgets[monthKey(month)] ?? 0 }
    private var budgetTint: Color {
        guard budget > 0 else { return ink }
        if budgetSpent > budget { return .red }
        return Double(budgetSpent) / Double(budget) >= 0.8 ? .orange : ink
    }
    private var budgetStatus: String {
        if budgetSpent > budget { return tr("超出预算", "Over budget", "Melebihi bajet") }
        if budgetSpent == budget { return tr("已达预算", "Budget reached", "Bajet dicapai") }
        if Double(budgetSpent) / Double(max(budget, 1)) >= 0.8 { return tr("接近预算", "Approaching limit", "Menghampiri had") }
        return tr("预算充足", "On track", "Dalam bajet")
    }
    private var budgetSymbol: String {
        budgetSpent >= budget ? "exclamationmark.circle.fill" : (Double(budgetSpent) / Double(max(budget, 1)) >= 0.8 ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
    }
    private var budgetUsageText: String {
        String(budget > 0 ? budgetSpent * 100 / budget : 0) + tr("% 已使用", "% used", "% digunakan")
    }
    private var owed: Int { summary.owed }
    /// The trend shows the latest six months while the selected month is among them, so
    /// tapping a bar keeps the bars in place; older months show the six ending there.
    private var trendEnd: Date {
        let calendar = Calendar.current
        let now = Date()
        guard let selected = calendar.dateInterval(of: .month, for: month)?.start,
              let current = calendar.dateInterval(of: .month, for: now)?.start,
              let gap = calendar.dateComponents([.month], from: selected, to: current).month else { return month }
        return (0..<6).contains(gap) ? now : month
    }
    static let maskedAmount = "RM ••••"
    private var hiddenAmountLabel: String { tr("金额已隐藏", "Amount hidden", "Amaun disembunyikan") }
    @ViewBuilder private func amount(_ cents: Int) -> some View {
        if hideAmounts {
            Text(Self.maskedAmount).accessibilityLabel(hiddenAmountLabel)
        } else {
            AnimatedMoney(cents: cents)
        }
    }
    private func amountText(_ cents: Int) -> String { hideAmounts ? Self.maskedAmount : money(cents) }
    var body: some View {
        let _ = uiLocale.identifier
        let requestedMonth = month
        let summaryQuery = model.overviewQuery(month: requestedMonth)
        let trendMonth = trendEnd
        let trendQuery = model.overviewQuery(month: trendMonth)
        NavigationStack(path: $path) {
            ScrollViewReader { guideScroll in
            List {
                // The header sits on the page itself, like a banking app's balance: month,
                // amount and quick actions, then the cards.
                Section {
                    MonthPicker(month: monthBinding)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    overviewHero
                        .modifier(MonthSummaryMotion(month: loadedSummary?.month))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 4, trailing: 20))
                    quickActions
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 10, leading: 8, bottom: 6, trailing: 8))
                }
                // The budget sits right under the actions; the latest entries and charts
                // follow, each card under a bold heading with "View all" where there is
                // more, as in the kit's Mobile Banking. Pending notices stay reachable from
                // the automation settings.
                budgetSection
                recentCard
                travelSection
                categoriesCard
                trendSection
                savingsSection
                balancesCard
            }.yuejiDashboardSurface()
            .navigationDestination(for: LedgerExpenseDestination.self) { destination in
                ExpenseDetailView(id: destination.id, embeddedInNavigation: true)
            }
            .navigationDestination(for: OverviewRoute.self) { route in
                switch route {
                case .receipt: ReceiptScanView()
                case .automation: AutomationSetupView()
                case .savings: SavingsGoalsView()
                case .travel: TravelBooksView()
                case .comparison(let month): SpendingComparisonView(month: month)
                }
            }
            .task(id: summaryQuery) {
                guard loadedSummary != summaryQuery else { return }
                do {
                    let fresh = try await model.preparedOverview(month: requestedMonth, query: summaryQuery)
                    guard !Task.isCancelled, model.overviewQuery(month: month) == summaryQuery else { return }
                    // Animate the completed snapshot, never a stale/intermediate month.
                    let changingMonth = loadedSummary.map { $0.month != summaryQuery.month } ?? false
                    let changingEmptyState = loadedSummary != nil && (summary.entries.isEmpty != fresh.entries.isEmpty)
                    let removingRows = loadedSummary?.month == summaryQuery.month &&
                        !Set(summary.entries.map(\.id)).subtracting(Set(fresh.entries.map(\.id))).isEmpty
                    let returningRows = model.restoredFeedback.map {
                        $0.date.timeIntervalSinceNow > -3 && !$0.expenseIDs.intersection(Set(fresh.entries.map(\.id))).subtracting(Set(summary.entries.map(\.id))).isEmpty
                    } ?? false
                    withAnimation(!reduceMotion && (changingMonth || changingEmptyState || returningRows || removingRows) ? YueJiMotion.rows : nil) {
                        summary = fresh; loadedSummary = summaryQuery
                    }
                } catch is CancellationError { return }
                catch { model.error = error.localizedDescription }
            }
            .task(id: trendQuery) {
                guard loadedTrend != trendQuery else { return }
                do {
                    let points = try await model.preparedSpendingTrend(endingAt: trendMonth)
                    guard !Task.isCancelled, model.overviewQuery(month: trendEnd) == trendQuery else { return }
                    withAnimation(reduceMotion || loadedTrend == nil ? nil : YueJiMotion.content) {
                        trend = points; loadedTrend = trendQuery
                    }
                } catch {
                    // Supplementary: a cancelled or stale request waits for the next one, and the
                    // monthly summary above already reports ledger errors.
                    return
                }
            }
            .task(id: guideFocus) {
                guard model.isPreview, let guideFocus else { return }
                do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
                withAnimation(.easeInOut(duration: 0.85)) { guideScroll.scrollTo(guideFocus, anchor: .center) }
            }
            .navigationTitle(tr("概览", "Overview", "Ringkasan")).navigationBarTitleDisplayMode(.large)
            .yuejiSubtitle(Date().formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: AppLanguage.localeID))))
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
                }
                .modifier(ExpenseContextActions(entry: entry,
                    edit: { guard !adding, editingExpense == nil else { return }; editingExpense = entry },
                    delete: { deletingExpense = entry }))
            }
        } header: {
            DashboardSectionHeader(title: tr("最近账目", "Recent entries", "Rekod terkini"),
                                   actionTitle: recentEntries.isEmpty ? nil : viewAllTitle) {
                openLedger(month)
            }
        } footer: {
            Text(tr("所选月份", "Selected month", "Bulan dipilih"))
        }
    }
    private var viewAllTitle: String { tr("查看全部", "View all", "Lihat semua") }
    /// Shortcuts as round glass buttons, like the quick actions of the kit's Mobile Banking
    /// app, over the hairline that ends its header.
    private var quickActions: some View {
        HStack(alignment: .top, spacing: 4) {
            QuickActionButton(title: tr("扫描收据", "Scan receipt", "Imbas resit"), symbol: "doc.viewfinder", tint: IslandPalette.lagoon) {
                path.append(OverviewRoute.receipt)
            }.guideTarget("dashboard.receipt")
            QuickActionButton(title: tr("自动记账", "Automation", "Automasi"), symbol: "bolt.fill", tint: IslandPalette.sky) {
                path.append(OverviewRoute.automation)
            }
            QuickActionButton(title: budget > 0 ? tr("调整预算", "Edit budget", "Ubah bajet") : tr("设置预算", "Set budget", "Tetapkan bajet"),
                              symbol: "gauge.with.dots.needle.67percent", tint: IslandPalette.pumpkin) {
                editBudget()
            }
            QuickActionButton(title: tr("储蓄目标", "Savings", "Simpanan"), symbol: "target", tint: IslandPalette.berry) {
                path.append(OverviewRoute.savings)
            }
        }
        .padding(.bottom, 16)
        .overlay(alignment: .bottom) { Divider().padding(.horizontal, 12).accessibilityHidden(true) }
    }
    private func editBudget() {
        budgetText = budget > 0 ? Currency.input(budget, "MYR") : ""
        budgeting = true
    }
    /// The month's personal spending as a banking app shows a balance (the kit's Mobile
    /// Banking): a caption, the amount in large type with the eye that hides it where the
    /// kit keeps the account photo, and what the amount already leaves out.
    private var overviewHero: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(tr("本月个人消费", "Personal spending", "Belanja peribadi"))
                        .font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    amount(personal)
                        .font(.system(size: heroSize, weight: .bold))
                        .foregroundStyle(.primary).minimumScaleFactor(0.5).lineLimit(1)
                }
                Spacer(minLength: 8)
                GlassIconButton(symbol: hideAmounts ? "eye.slash" : "eye") {
                    withAnimation(reduceMotion ? nil : YueJiMotion.content) { hideAmounts.toggle() }
                    FeedbackHaptics.selection()
                }
                .accessibilityLabel(hideAmounts ? tr("显示金额", "Show amounts", "Tunjuk amaun") : tr("隐藏金额", "Hide amounts", "Sembunyi amaun"))
            }
            Text(summary.reimbursementClaimed > 0
                 ? tr("已扣除朋友份额、个人退款与报销金额", "After friends’ shares, your refunds and claims", "Selepas bahagian rakan, pulangan dan tuntutan anda")
                 : tr("已扣除朋友份额与个人退款", "After friends’ shares and your refunds", "Selepas bahagian rakan dan pulangan anda"))
                .font(.footnote).foregroundStyle(.secondary)
            Text(String(entries.count) + tr(" 笔消费", " expenses", " belanja"))
                .font(.footnote.weight(.medium)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    /// The month's budget as the system capacity gauge (the kit's progress bar), with travel
    /// kept apart and claims still to come back.
    private var budgetSection: some View {
        Section {
            if budget > 0 {
                VStack(alignment: .leading, spacing: 12) {
                    Gauge(value: Double(min(budgetSpent, budget)), in: 0...Double(max(budget, 1))) {
                        Text(budgetSpent > budget ? tr("超出预算", "Over budget", "Melebihi bajet") : tr("预算剩余", "Remaining", "Baki bajet"))
                    } currentValueLabel: {
                        Text(amountText(abs(budget - budgetSpent))).monospacedDigit()
                    }
                    .gaugeStyle(.linearCapacity)
                    .tint(budgetTint)
                    .font(.subheadline)
                    .animation(reduceMotion ? nil : YueJiMotion.meter, value: budgetSpent)
                    HStack {
                        Label(budgetStatus, systemImage: budgetSymbol).foregroundStyle(budgetTint)
                        Spacer(minLength: 12)
                        Text(budgetUsageText).monospacedDigit().foregroundStyle(.secondary)
                    }
                    .font(.footnote.weight(.medium))
                    .contentTransition(.opacity)
                }
                .padding(.vertical, 6)
                .animation(reduceMotion ? nil : YueJiMotion.tone, value: budgetTint)
            } else {
                Button(action: editBudget) {
                    Label(tr("设置每月预算", "Set a monthly budget", "Tetapkan bajet bulanan"), systemImage: "gauge.with.dots.needle.33percent")
                }
            }
            if personal != budgetSpent {
                LabeledContent(tr("旅行消费 · 独立预算", "Travel · separate budget", "Perjalanan · bajet berasingan"), value: amountText(personal - budgetSpent))
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            if summary.reimbursementClaimed > 0 {
                NavigationLink { ReimbursementsView() } label: {
                    LabeledContent(tr("本月账目待报销", "Outstanding claims on this month's entries", "Tuntutan rekod bulan ini belum diterima"), value: amountText(summary.reimbursementOutstanding))
                        .font(.subheadline)
                }
            }
        } header: {
            DashboardSectionHeader(title: tr("预算", "Budget", "Bajet"),
                                   actionTitle: budget > 0 ? tr("调整", "Edit", "Ubah") : nil) {
                editBudget()
            }
        }
    }
    /// Trips keep their own budgets, so they sit beside the monthly budget: the trip under
    /// way (else the next one, else the latest) as a card row against its budget, with every
    /// travel book under "View all".
    private var travelSection: some View {
        Section {
            if let trip = featuredTrip {
                let spent = model.ledger.tripSpending(trip.id)
                NavigationLink { TravelBookDetail(id: trip.id) } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 12) {
                            IslandIconTile(symbol: "suitcase.rolling.fill", color: IslandPalette.sky, size: 40)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(trip.name).font(.body.weight(.semibold)).lineLimit(1)
                                Text((trip.destination.isEmpty ? "" : trip.destination + " · ") + dateLabel(trip.start) + " – " + dateLabel(trip.end))
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer(minLength: 8)
                            Text(amountText(spent) + (trip.budget > 0 ? " / " + amountText(trip.budget) : ""))
                                .font(.subheadline.weight(.semibold)).monospacedDigit()
                        }
                        if trip.budget > 0 {
                            SpendingMeter(value: spent, total: trip.budget, color: spent > trip.budget ? .orange : IslandPalette.sky)
                        }
                    }.padding(.vertical, 6)
                }
            } else {
                NavigationLink { TravelBooksView() } label: {
                    HStack(spacing: 12) {
                        IslandIconTile(symbol: "suitcase.rolling.fill", color: IslandPalette.sky, size: 40)
                            .accessibilityHidden(true)
                        Text(tr("给旅行单独的预算，不占日常月预算。", "Give a trip its own budget, apart from the monthly one.", "Beri perjalanan bajet sendiri, berasingan daripada bajet bulanan."))
                            .font(.subheadline).foregroundStyle(.secondary)
                    }.padding(.vertical, 6)
                }
            }
        } header: {
            DashboardSectionHeader(title: tr("旅行账本", "Travel books", "Buku perjalanan"),
                                   actionTitle: model.ledger.trips.isEmpty ? nil : viewAllTitle) {
                path.append(OverviewRoute.travel)
            }
        }
    }
    /// The trip under way today, else the next one to start, else the one that ended last.
    private var featuredTrip: TravelBook? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let trips = model.ledger.trips
        if let current = trips.first(where: { calendar.startOfDay(for: $0.start) <= today && today <= calendar.startOfDay(for: $0.end) }) {
            return current
        }
        if let next = trips.filter({ calendar.startOfDay(for: $0.start) > today }).min(by: { $0.start < $1.start }) {
            return next
        }
        return trips.max(by: { $0.end < $1.end })
    }
    /// The goal still being saved for (else the first) as a card row, with every goal under
    /// "View all".
    private var savingsSection: some View {
        Section {
            NavigationLink { SavingsGoalsView() } label: {
                HStack(spacing: 12) {
                    IslandIconTile(symbol: "target", color: IslandPalette.berry, size: 40)
                        .accessibilityHidden(true)
                    if let goal = model.ledger.savingsGoals.first(where: { $0.balance < $0.target }) ?? model.ledger.savingsGoals.first {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(goal.name).font(.body.weight(.semibold)).lineLimit(1)
                                Spacer(minLength: 8)
                                Text(money(goal.balance)).font(.subheadline.weight(.semibold)).monospacedDigit()
                            }
                            SpendingMeter(value: goal.balance, total: max(1, goal.target),
                                          color: goal.balance >= goal.target ? .green : ink)
                            Text(tr("目标 ", "Target ", "Sasaran ") + money(goal.target))
                                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        }
                    } else {
                        Text(tr("为想做的事，存下第一笔。", "Set aside your first contribution.", "Asingkan simpanan pertama anda.")).font(.subheadline).foregroundStyle(.secondary)
                    }
                }.padding(.vertical, 6)
            }
        } header: {
            DashboardSectionHeader(title: tr("储蓄目标", "Savings goals", "Matlamat simpanan"),
                                   actionTitle: model.ledger.savingsGoals.count > 1 ? viewAllTitle : nil) {
                path.append(OverviewRoute.savings)
            }
        }
    }
    private var trendSection: some View {
        Section {
            if trend.isEmpty {
                Color.clear.frame(height: 180).accessibilityHidden(true)
            } else {
                SpendingTrendChart(points: trend, selected: month, hidden: hideAmounts) { chosen in
                    // Same as the month picker: amounts and bars animate locally, layout stays put.
                    withTransaction(Transaction(animation: nil)) { monthTimestamp = chosen.timeIntervalSince1970 }
                }
                .padding(.vertical, 8)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(tr("消费趋势", "Spending trend", "Trend perbelanjaan"))
                .accessibilityValue(trendAccessibilityValue)
            }
        } header: {
            DashboardSectionHeader(title: tr("消费趋势", "Spending trend", "Trend perbelanjaan"),
                                   actionTitle: tr("对比", "Compare", "Banding")) {
                path.append(OverviewRoute.comparison(month))
            }
        } footer: {
            Text(tr("近六个月 · 点按柱形查看该月", "Six months · tap a bar to view that month", "Enam bulan · ketik bar untuk melihat bulan itu"))
        }
    }
    private var trendAccessibilityValue: String {
        guard !hideAmounts else { return hiddenAmountLabel }
        let locale = Locale(identifier: AppLanguage.localeID)
        let parts: [String] = trend.map { point in
            point.month.formatted(.dateTime.month(.wide).locale(locale)) + " " + money(point.cents)
        }
        return parts.joined(separator: ", ")
    }
    private var balancesCard: some View {
        Section {
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
        } header: {
            DashboardSectionHeader(title: tr("收支明细", "Payment details", "Butiran bayaran"))
        }
    }
    private var categoriesCard: some View {
        SpendingCategoryBreakdown(totals: summary.categoryTotals, total: personal, month: month, hidden: hideAmounts)
    }
}

private struct SpendingCategoryBreakdown: View {
    @Environment(\.locale) private var uiLocale
    @EnvironmentObject private var model: LedgerModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    let totals: [String: Int]
    let total: Int
    let month: Date
    /// The Overview's eye: masks the card's amount like the header's.
    var hidden = false
    var body: some View {
        let _ = uiLocale.identifier
        Section {
            if total == 0 {
                Label(tr("暂无个人消费", "No personal spending yet", "Belum ada belanja peribadi"), systemImage: "leaf")
                    .foregroundStyle(.secondary)
                Text(tr("记录消费后，这里会显示你的分类占比。", "Your category breakdown will appear here.", "Pecahan kategori anda akan dipaparkan di sini."))
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                // The expenses card of the kit's Mobile Banking app: the month's spending
                // and its dates beside the donut, then each category's share as a chip.
                VStack(alignment: .leading, spacing: 16) {
                    summaryLayout {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(tr("消费", "Spending", "Belanja")).font(.headline)
                            Text(monthRange).font(.footnote).foregroundStyle(.secondary)
                            Group {
                                if hidden {
                                    Text(DashboardView.maskedAmount)
                                        .accessibilityLabel(tr("金额已隐藏", "Amount hidden", "Amaun disembunyikan"))
                                } else {
                                    AnimatedMoney(cents: total)
                                }
                            }
                            .font(.title.weight(.bold)).lineLimit(1).minimumScaleFactor(0.6)
                            .padding(.top, 10)
                        }
                        .accessibilityElement(children: .combine)
                        if !typeSize.isAccessibilitySize { Spacer(minLength: 8) }
                        SpendingDonutChart(slices: slices)
                    }
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(slices.sorted { $0.cents > $1.cents }) { slice in
                                CategoryShareChip(text: share(slice.cents) + " " + categoryLabel(slice.category), color: slice.color)
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                    // The rows below read the same shares.
                    .accessibilityHidden(true)
                }
                .padding(.vertical, 8)
            }
            // One row per category, as Messages lists conversations: the category's tinted
            // icon, its name and share of the month, and the amount.
            ForEach(model.ledger.categoryNames, id: \.self) { category in
                let value = totals[category] ?? 0
                if value > 0 {
                    NavigationLink {
                        CategoryPaymentsView(category: category, month: month)
                    } label: {
                        HStack(spacing: 12) {
                            IslandIconTile(symbol: model.ledger.categorySymbol(category), color: model.ledger.categoryTint(category), size: 36)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(categoryLabel(category)).font(.body.weight(.semibold))
                                Text(share(value)).font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            AnimatedMoney(cents: value).font(.body.weight(.semibold))
                        }.foregroundStyle(.primary).frame(minHeight: 44).contentShape(Rectangle())
                    }.buttonStyle(.borderless)
                        .accessibilityIdentifier("overview.category.select." + category)
                        .transition(reduceMotion ? .identity : .opacity)
                }
            }
        } header: {
            DashboardSectionHeader(title: tr("钱花在哪里", "Where it went", "Ke mana belanja"))
        }
    }
    /// The amount beside the donut; stacked above it at accessibility text sizes.
    private var summaryLayout: AnyLayout {
        typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 16))
    }
    /// The month's dates, as the kit's card shows its period: the current month runs to today.
    private var monthRange: String {
        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(of: .month, for: month) else { return "" }
        let last = calendar.date(byAdding: .day, value: -1, to: interval.end) ?? interval.start
        let end = min(last, max(interval.start, Date()))
        let style = Date.FormatStyle().day().month(.abbreviated).locale(Locale(identifier: AppLanguage.localeID))
        return interval.start.formatted(style) + " – " + end.formatted(style.year())
    }
    private var slices: [CategorySlice] {
        model.ledger.categoryNames.compactMap { category in
            let value = totals[category] ?? 0
            return value > 0 ? CategorySlice(category: category, cents: value, color: model.ledger.categoryTint(category)) : nil
        }
    }
    private func share(_ value: Int) -> String {
        String(format: "%.0f%%", Double(value) / Double(max(total, 1)) * 100)
    }
}

struct CategoryPaymentsView: View {
    @Environment(\.locale) private var uiLocale
    @EnvironmentObject var model: LedgerModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    let category: String
    let month: Date
    private var tint: Color { model.ledger.categoryTint(category) }
    @State private var summary = OverviewSnapshot()
    @State private var entries: [Expense] = []
    /// The category's month by merchant, for the donut and its rows.
    @State private var merchants: [MerchantSlice] = []
    /// The merchant tapped in the donut or its rows; the payments narrow to it.
    @State private var selectedMerchant: String?
    @State private var loadedQuery: LedgerTimelineQuery?
    private var selectedSlice: MerchantSlice? { merchants.first { $0.id == selectedMerchant } }
    /// All the category's payments, or with a merchant selected exactly the ones behind its
    /// sector, so the list matches the row's payment count.
    private var shownEntries: [Expense] {
        guard let selectedSlice else { return entries }
        return entries.filter {
            selectedSlice.merchants.contains(MerchantSlice.key(for: $0)) && $0.personalAmount(category: category) > 0
        }
    }
    var body: some View {
        let _ = uiLocale.identifier
        let query = model.overviewQuery(month: month)
        List {
            Section {
                // The category's own expenses card: its total beside the donut of where it
                // went, merchant by merchant.
                headerLayout {
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
                    }
                    if !merchants.isEmpty {
                        if !typeSize.isAccessibilitySize { Spacer(minLength: 8) }
                        MerchantDonutChart(slices: merchants, selection: $selectedMerchant)
                    }
                }.padding(.vertical, 8)
            } footer: {
                Text(tr("分类合计是扣除退款后的个人份额；付款记录显示整笔金额。", "The category total is your share after refunds; payment records show the full payment amount.", "Jumlah kategori ialah bahagian anda selepas pulangan; rekod bayaran menunjukkan amaun penuh."))
            }
            if !merchants.isEmpty {
                // The donut's legend and its figures: one row per merchant, largest first.
                Section(tr("按商户", "By merchant", "Mengikut peniaga")) {
                    ForEach(merchants) { slice in merchantRow(slice) }
                }
            }
            Section {
                if shownEntries.isEmpty && loadedQuery == query {
                    IslandEmptyState(title: tr("暂无记录", "No entries", "Tiada rekod")).listRowBackground(Color.clear)
                }
                ForEach(shownEntries) { entry in
                    NavigationLink { ExpenseDetailView(id: entry.id, embeddedInNavigation: true) } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            ExpenseRow(entry: entry)
                            LabeledContent(tr("此分类 · 我的份额", "This category · my share", "Kategori ini · bahagian saya")) {
                                TransactionAmount(cents: entry.personalAmount(category: category), direction: .outgoing)
                            }.font(.caption)
                        }
                    }.foregroundStyle(.primary)
                }
            } header: {
                Text(selectedSlice.map { tr("付款记录 · ", "Payments · ", "Bayaran · ") + $0.name } ?? tr("付款记录", "Payments", "Bayaran"))
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
                    summary = fresh; entries = fresh.entries.filter { $0.hasCategory(category) }
                    merchants = MerchantSlice.split(entries, category: category)
                    // A merchant whose payments were all deleted or moved leaves the selection.
                    if let selected = selectedMerchant, !merchants.contains(where: { $0.id == selected }) { selectedMerchant = nil }
                    loadedQuery = query
                } catch is CancellationError { return }
                catch { model.error = error.localizedDescription }
            }
    }
    /// The total beside the donut; stacked above it at accessibility text sizes.
    private var headerLayout: AnyLayout {
        typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 16))
    }
    private func share(_ cents: Int) -> String {
        String(format: "%.0f%%", Double(cents) / Double(max(merchants.reduce(0) { $0 + $1.cents }, 1)) * 100)
    }
    /// A merchant's row, the donut's legend: its colour, name and payments, its share and
    /// amount. Tapping it selects it in the donut and narrows the payments to it; tapping it
    /// again shows them all.
    private func merchantRow(_ slice: MerchantSlice) -> some View {
        let selected = slice.id == selectedMerchant
        let payments = slice.payments == 1
            ? tr("1 笔付款", "1 payment", "1 bayaran")
            : String(slice.payments) + tr(" 笔付款", " payments", " bayaran")
        return Button {
            FeedbackHaptics.selection()
            withAnimation(reduceMotion ? nil : YueJiMotion.standard) { selectedMerchant = selected ? nil : slice.id }
        } label: {
            HStack(spacing: 12) {
                Circle().fill(slice.color).frame(width: 12, height: 12)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(slice.name).font(.body.weight(.semibold)).lineLimit(2)
                    Text(payments + " · " + share(slice.cents))
                        .font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Text(money(slice.cents)).font(.body.weight(.semibold)).monospacedDigit()
                if selected {
                    Image(systemName: "checkmark").font(.body.weight(.semibold)).foregroundStyle(tint)
                        .accessibilityHidden(true)
                }
            }
            .foregroundStyle(.primary).frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityHint(selected
            ? tr("显示这个分类的全部付款", "Shows all of this category's payments", "Tunjukkan semua bayaran kategori ini")
            : tr("只显示这家商户的付款", "Shows only this merchant's payments", "Tunjukkan bayaran peniaga ini sahaja"))
    }
}
struct OverviewToolsView: View {
    @Environment(\.locale) private var uiLocale
    var month: Date = Date()
    var body: some View {
        let _ = uiLocale.identifier
        List {
            Section(tr("日常工具", "Everyday tools", "Alat harian")) {
                NavigationLink { ReimbursementsView() } label: { IslandRowLabel(title: tr("报销管理", "Reimbursements", "Tuntutan bayaran balik"), symbol: "doc.text.fill", color: IslandPalette.lavender) }
                NavigationLink { ReceiptScanView() } label: { IslandRowLabel(title: tr("拍收据分账", "Snap receipt & split", "Imbas resit & bahagi"), symbol: "doc.viewfinder", color: IslandPalette.lagoon) }
                    .guideTarget("dashboard.receipt")
                NavigationLink { AutomationSetupView() } label: { IslandRowLabel(title: tr("自动记账", "Automatic recording", "Rekod automatik"), symbol: "bolt.fill", color: IslandPalette.sky) }
            }
            Section(tr("分析", "Insights", "Analisis")) {
                NavigationLink { SpendingComparisonView(month: month) } label: { IslandRowLabel(title: tr("月度消费对比", "Monthly comparison", "Perbandingan bulanan"), symbol: "chart.bar.xaxis", color: IslandPalette.mint) }
                NavigationLink { UpcomingView(initialMonth: month) } label: { IslandRowLabel(title: tr("固定消费预览", "Upcoming bills", "Bil akan datang"), symbol: "calendar", color: IslandPalette.pumpkin) }
                NavigationLink { DuplicateReviewView() } label: { IslandRowLabel(title: tr("检查重复账目", "Review duplicates", "Semak pendua"), symbol: "doc.on.doc.fill", color: IslandPalette.berry) }
            }
            Section {
                NavigationLink { NotificationSettingsView() } label: { IslandRowLabel(title: tr("预算与每日提醒", "Budget & daily reminders", "Peringatan bajet & harian"), symbol: "bell.fill", color: IslandPalette.coral) }
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
            IslandIconTile(symbol: symbol, color: IslandPalette.leaf, size: 28, filled: true).accessibilityHidden(true)
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
    // Bound the number of text views while preserving every character of
    // long legacy summaries in the final block. No receipt data is reparsed.
    private var blocks: [String] {
        let lines = summary.components(separatedBy: "\n")
        guard lines.count > 40 else { return lines }
        return Array(lines.prefix(40)) + [lines.dropFirst(40).joined(separator: "\n")]
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, line in
                Text(line.isEmpty ? " " : line).font(.subheadline).monospacedDigit()
                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            }
        }.padding(.vertical, 12)
            .opacity(reduceMotion || revealed ? 1 : 0)
            .offset(y: reduceMotion || revealed ? 0 : 6)
            .animation(reduceMotion ? nil : YueJiMotion.standard, value: revealed)
            .task {
                guard !reduceMotion else { revealed = true; return }
                do { try await Task.sleep(for: .milliseconds(16)) } catch { return }
                revealed = true
            }
    }
}

/// The system progress bar, tinted per category or goal.
struct SpendingMeter: View {
    @Environment(\.locale) private var uiLocale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let value: Int
    let total: Int
    let color: Color
    @State private var displayedFraction = 0.0
    private var fraction: Double { min(max(Double(value) / Double(max(total, 1)), 0), 1) }
    var body: some View {
        let _ = uiLocale.identifier
        ProgressView(value: reduceMotion ? fraction : displayedFraction)
            .progressViewStyle(.linear)
            .tint(color)
            .animation(reduceMotion ? nil : YueJiMotion.tone, value: color)
            .task(id: fraction) {
                guard !reduceMotion else { displayedFraction = fraction; return }
                // Give a new lazy row one frame at zero before revealing its
                // share. Later updates animate from the current rendered value.
                if displayedFraction == 0 {
                    do { try await Task.sleep(for: .milliseconds(16)) } catch { return }
                }
                guard !Task.isCancelled else { return }
                // A calm fill with almost no overshoot.
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
    /// Overrides the direction colour when a screen needs a single text colour.
    var tint: Color? = nil
    var body: some View {
        let _ = uiLocale.identifier
        Text(direction.formattedAmount(cents)).foregroundStyle(tint ?? direction.amountColor).monospacedDigit()
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
            IslandIconTile(symbol: symbol, color: categoryColor, size: 44)
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
                    .background(IslandTheme.card, in: RoundedRectangle(cornerRadius: 20))
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

/// The filters in use, as chips under the ledger summary; each chip removes its filter.
/// Filters are chosen from the toolbar's filter menu.
private struct LedgerActiveFilters: View {
    @Environment(\.locale) private var uiLocale
    @Binding var filter: LedgerFilter
    @Binding var provider: String
    var body: some View {
        let _ = uiLocale.identifier
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
    /// A month to show, from the Overview's "View all"; cleared once shown.
    var monthRequest: Binding<LedgerMonthRequest?> = .constant(nil)
    @State private var filter = LedgerFilter()
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
    private var filtering: Bool { filter.active || providerFilter != "all" }
    private func clearFilters() {
        withAnimation(reduceMotion ? nil : YueJiMotion.rows) { filter = LedgerFilter(); providerFilter = "all" }
    }
    var body: some View {
        let _ = uiLocale.identifier
        let requestedMonth = month
        let query = self.query
        let days = timeline.days
        NavigationStack(path: $path) {
            List {
                // The month and its total head the list like a balance; the payments follow
                // as plain rows, as Messages lists conversations.
                Section {
                    MonthPicker(month: monthBinding)
                        .listRowSeparator(.hidden)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(filtering || !search.isEmpty ? tr("筛选结果 · 我的消费", "Filtered · my spending", "Ditapis · belanja saya") : tr("本月 · 我的消费", "This month · my spending", "Bulan ini · belanja saya"))
                            .font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        AnimatedMoney(cents: timeline.personal)
                            .font(.largeTitle.bold()).foregroundStyle(.primary)
                            .minimumScaleFactor(0.6).lineLimit(1)
                        if timeline.reimbursementOutstanding > 0 {
                            Text(tr("待报销垫付款：", "Outstanding advances: ", "Pendahuluan belum diterima: ") + money(timeline.reimbursementOutstanding))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Text(String(timeline.count) + tr(" 笔记录", " entries", " rekod")).font(.footnote).foregroundStyle(.secondary)
                    }.padding(.vertical, 6)
                    .modifier(MonthSummaryMotion(month: loadedQuery?.month))
                    .listRowSeparator(.hidden)
                    LedgerActiveFilters(filter: $filter, provider: $providerFilter)
                        .animation(reduceMotion ? nil : YueJiMotion.rows, value: filter)
                        .animation(reduceMotion ? nil : YueJiMotion.rows, value: providerFilter)
                        .listRowSeparator(.hidden)
                }
                .listRowBackground(Color.clear)
                if timeline.count == 0 && loadedQuery != nil {
                    let filtered = filter.active || !search.isEmpty || providerFilter != "all"
                    IslandEmptyState(title: tr("暂无记录", "No entries", "Tiada rekod"),
                        message: filtered
                             ? tr("试试其他关键词，或清除筛选。", "Try another search or clear your filters.", "Cuba carian lain atau kosongkan penapis.")
                             : tr("为这个月记一笔，日期会保留在所选月份。", "Add an expense for the selected month.", "Tambah belanja untuk bulan dipilih."),
                        mood: filtered ? .worried : .sleepy) {
                        if filter.active || !search.isEmpty || providerFilter != "all" {
                            Button(tr("清除筛选与搜索", "Clear filters and search", "Kosongkan penapis dan carian")) { filter = LedgerFilter(); search = ""; providerFilter = "all" }
                        } else {
                            Button(tr("记一笔", "Add entry", "Tambah rekod")) { if sheet == nil { sheet = .new(dateForNewExpense(in: month)) } }.yuejiPrimaryButton()
                        }
                    }.listRowBackground(Color.clear).listRowSeparator(.hidden).transition(.opacity)
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
                                // Two round actions, as in the kit's Messages swipe actions.
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button { deleting = entry } label: {
                                        Label(tr("删除", "Delete", "Padam"), systemImage: "trash")
                                    }.tint(.red)
                                    Button { if sheet == nil { sheet = .edit(entry) } } label: {
                                        Label(tr("编辑", "Edit", "Edit"), systemImage: "pencil")
                                    }.tint(.indigo)
                                }
                                .modifier(ExpenseContextActions(entry: entry,
                                    edit: { if sheet == nil { sheet = .edit(entry) } },
                                    delete: { deleting = entry }))
                            }
                        }
                    } header: { Text(dateLabel(day.date)) }
                    .listRowBackground(Color.clear)
                }
            }
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
                        let removingRows = loadedQuery?.month == query.month && !changingSelection && loadedQuery?.search == query.search && (
                            !Set(timeline.expenses.map(\.id)).subtracting(Set(fresh.expenses.map(\.id))).isEmpty ||
                            !Set(timeline.transfers.map(\.id)).subtracting(Set(fresh.transfers.map(\.id))).isEmpty ||
                            timeline.count > fresh.count)
                        let returningRows = model.restoredFeedback.map { feedback in
                            let expenses = feedback.expenseIDs.intersection(Set(fresh.expenses.map(\.id))).subtracting(Set(timeline.expenses.map(\.id)))
                            let notices = feedback.noticeIDs.intersection(Set(fresh.transfers.map(\.id))).subtracting(Set(timeline.transfers.map(\.id)))
                            return feedback.date.timeIntervalSinceNow > -3 && (!expenses.isEmpty || !notices.isEmpty)
                        } ?? false
                        withAnimation(!reduceMotion && (changingSelection || changingEmptyState || returningRows || removingRows) ? YueJiMotion.rows : nil) {
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
                .yuejiPlainListSurface().navigationTitle(tr("账本", "Ledger", "Lejar")).navigationBarTitleDisplayMode(.large)
                .yuejiSubtitle(month.formatted(.dateTime.year().month(.wide).locale(Locale(identifier: AppLanguage.localeID))))
                .searchable(text: $search, prompt: tr("商户、分类、转账对象", "Merchant, category, transfer party", "Peniaga, kategori, pihak pindahan"))
                .toolbar {
                    // A glass menu with checkmarks, like the filter menu of the kit's Messages.
                    ToolbarItem(placement: .topBarLeading) {
                        Menu {
                            Picker(selection: $filter.category) {
                                Text(tr("全部分类", "All categories", "Semua kategori")).tag("")
                                ForEach(model.ledger.categoryNames, id: \.self) { Text(categoryLabel($0)).tag($0) }
                            } label: {
                                Label(tr("分类", "Category", "Kategori"), systemImage: "square.grid.2x2")
                            }.pickerStyle(.menu)
                            Picker(selection: $providerFilter) {
                                Text(tr("全部来源", "All sources", "Semua sumber")).tag("all")
                                ForEach(model.ledger.availableSources, id: \.self) { Text(sourceLabel($0)).tag($0) }
                            } label: {
                                Label(tr("来源", "Source", "Sumber"), systemImage: "tray.full")
                            }.pickerStyle(.menu)
                            Divider()
                            Button { if sheet == nil { sheet = .filter } } label: {
                                Label(tr("金额与更多条件", "Amount & more filters", "Amaun dan penapis lain"), systemImage: "slider.horizontal.3")
                            }
                            if filtering {
                                Button(role: .destructive) { clearFilters() } label: {
                                    Label(tr("清除筛选", "Clear filters", "Kosongkan penapis"), systemImage: "xmark.circle")
                                }
                            }
                        } label: {
                            Image(systemName: filtering ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                        }
                        .accessibilityLabel(filtering ? tr("筛选已启用", "Filters active", "Penapis aktif") : tr("筛选", "Filter", "Tapis"))
                        .accessibilityIdentifier("ledger.filters.toggle")
                        .guideTarget("ledger.filter")
                    }
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
                .onChange(of: monthRequest.wrappedValue, initial: true) { _, request in
                    guard let request else { return }
                    path = NavigationPath()
                    month = request.month
                    monthRequest.wrappedValue = nil
                }
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
struct ExpenseDescriptionDetails: View {
    let entry: Expense
    var identifier = "transaction.description.detail"
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(tr("账目名称／描述", "Name / description", "Nama / penerangan")).font(.caption).foregroundStyle(.secondary)
            let description = (entry.entryDescription ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            Text(description.isEmpty ? tr("未填写", "Not entered", "Belum diisi") : description)
                .foregroundStyle(description.isEmpty ? Color.secondary : Color.primary)
                .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            if let note = entry.note, !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(tr("备注", "Note", "Nota")).font(.caption).foregroundStyle(.secondary)
                Text(note).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).accessibilityIdentifier(identifier)
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
    @State private var copiedDraft: Expense?
    @State private var mapDestination: ExpensePlaceDestination?
    /// A possible subscription being confirmed for Recurring.
    @State private var addingSubscription: SubscriptionCandidate?
    /// The suggestion just hidden here, offered back for a few seconds.
    @State private var hiddenSuggestion: SubscriptionCandidate?
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
                    // Where a payment's notification about a subscription leads: the schedule it
                    // renewed, or the possible subscription it may be part of.
                    if let key = entry.renewalOf, let schedule = model.ledger.recurring.first(where: { $0.owns(key) }) {
                        Section {
                            NavigationLink { RecurringDetailView(ruleID: schedule.id) } label: {
                                Label(tr("\(schedule.name) 的续费", "Renewal of \(schedule.name)", "Pembaharuan \(schedule.name)"), systemImage: "arrow.triangle.2.circlepath")
                            }
                        }
                    } else if let candidate = model.ledger.subscriptionCandidate(forExpense: entry.id) {
                        Section(candidate.kind.label) {
                            SubscriptionSuggestionRow(candidate: candidate) {
                                addingSubscription = candidate
                            } dismiss: {
                                model.change { [id = candidate.id] in $0.dismissedSubscriptions.insert(id) }
                                hiddenSuggestion = candidate
                            }
                        }
                    } else if let hidden = hiddenSuggestion {
                        Section {
                            HStack {
                                Text(tr("已隐藏“\(hidden.name)”", "Hid “\(hidden.name)”", "“\(hidden.name)” disembunyikan"))
                                    .font(.subheadline).foregroundStyle(.secondary)
                                Spacer()
                                Button(tr("撤销", "Undo", "Buat asal")) {
                                    model.change { [id = hidden.id] in $0.dismissedSubscriptions.remove(id) }
                                    hiddenSuggestion = nil
                                }.buttonStyle(.borderless).fontWeight(.semibold)
                            }
                        }
                    }
                    Section(tr("账目信息", "Entry information", "Maklumat rekod")) {
                        ExpenseDescriptionDetails(entry: entry)
                    }
                    SavedTransactionItemsSection(entry: entry, presentationAllowed: !editorPresented && deleting == nil) { selectedID in
                        guard !editorPresented, editing == nil, deleting == nil else { return }
                        editorPresented = true
                        editing = .items(entry, selectedID: selectedID)
                    }
                    ExpenseChargeDetails(entry: entry)
                    if let trip = model.ledger.trips.first(where: { $0.id == entry.tripID }) {
                        Section(tr("旅行账本", "Travel book", "Buku perjalanan")) {
                            NavigationLink(trip.name) { TravelBookDetail(id: trip.id) }
                        }
                    }
                    if let place = entry.place {
                        ExpensePlaceDetails(place: place) {
                            mapDestination = ExpensePlaceDestination(place: place, merchant: entry.merchant)
                        }
                    }
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
                    IslandEmptyState(title: tr("账目已删除", "Entry deleted", "Rekod dipadam"), mood: .sad)
                        .listRowBackground(Color.clear)
                }
            }
            .yuejiListSurface().navigationTitle(tr("账目详情", "Entry details", "Butiran rekod"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    ExpenseDetailTitle(entry: detail?.entry, compact: compactTitle)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if let entry = liveDetail?.entry {
                        Button { copiedDraft = entry.duplicateDraft() } label: {
                            Label(tr("复制账目", "Duplicate entry", "Salin rekod"), systemImage: "doc.on.doc")
                        }.disabled(editorPresented || model.deletionInFlight)
                            .accessibilityIdentifier("transaction.duplicate")
                    }
                }
                if !embeddedInNavigation {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("关闭", "Close", "Tutup"), systemImage: "xmark") { dismiss() }
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
            .sheet(item: $copiedDraft) { entry in ExpenseEditor(original: nil, initialDraft: entry) }
            .sheet(item: $addingSubscription) { candidate in RecurringEditor(original: nil, candidate: candidate).ledgerFeedback(modal: true) }
            .task(id: hiddenSuggestion?.id) {
                guard hiddenSuggestion != nil else { return }
                do { try await Task.sleep(for: .seconds(8)) } catch { return }
                hiddenSuggestion = nil
            }
            .sheet(item: $mapDestination) { destination in
                ExpensePlaceMapSheet(initial: destination.place, merchantHint: destination.merchant, onSave: nil)
            }
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

/// The entry's summary, Apple Card style: category icon, amount, name, category, date.
private struct ExpenseDetailHero: View {
    @Environment(\.locale) private var uiLocale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var model: LedgerModel
    let entry: Expense
    @Binding var compact: Bool
    private var symbol: String {
        if entry.fuel { return "fuelpump.fill" }
        if entry.recurringKey != nil { return "repeat" }
        return model.ledger.categorySymbol(entry.category)
    }
    var body: some View {
        let _ = uiLocale.identifier
        let motion = !reduceMotion
        VStack(spacing: 12) {
            // Large, in the contact photo's place in the kit's Messages details.
            IslandIconTile(symbol: symbol, color: model.ledger.categoryTint(entry.category), size: 72)
                .accessibilityHidden(true)
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

struct ExpenseEditorSnapshot: Codable, Equatable {
    var text: [String]
    var flags: [Bool]
    var date: Date
    var items: [ExpenseItemDraft]
    var people: [FriendDraft]
    var place: ExpensePlace? = nil
    var tripID: String? = nil
}

struct SavedExpenseDraft: Codable {
    var version = 1
    var base: Expense?
    var seed: Expense?
    var fields: ExpenseEditorSnapshot
    var rateDate: Date
    var rateSource: String
    var updated = Date()
    var supported: Bool { version == 1 && fields.text.count == 16 && fields.flags.count == 8 && fields.items.count <= 100 && fields.people.count <= 100 }
}

enum ExpenseDraftStorage {
    static func key(_ id: String?) -> String { "expense-draft-v1." + (id ?? "new") }
    static func read(_ id: String?, defaults: UserDefaults = .standard) -> SavedExpenseDraft? {
        guard let data = defaults.data(forKey: key(id)), let draft = try? JSONDecoder().decode(SavedExpenseDraft.self, from: data), draft.supported else { return nil }
        return draft
    }
    static func write(_ draft: SavedExpenseDraft, id: String?, defaults: UserDefaults = .standard) {
        guard draft.supported, let data = try? JSONEncoder().encode(draft) else { return }
        defaults.set(data, forKey: key(id))
    }
    static func remove(_ id: String?, defaults: UserDefaults = .standard) { defaults.removeObject(forKey: key(id)) }
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

struct FriendDraft: Codable, Identifiable, Equatable {
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
    @State private var place: ExpensePlace?
    @State private var tripID: String?
    @StateObject private var placeLocator = ExpensePlaceLocator()
    @State private var editingPlace = false
    @State private var startedLocation = false
    @State private var placeNotice: String?
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
    @Environment(\.scenePhase) private var phase
    @State private var recoverable: SavedExpenseDraft?
    @State private var draftSeed: Expense?
    @State private var resumedDraft = false
    @State private var draftFinished = false
    private var snapshot: ExpenseEditorSnapshot {
        ExpenseEditorSnapshot(text: [name, entryDescription, amount, currency, rate, category, entryType, payerName, friendPaidMode, friendShareText, reimbursementRecipient, reimbursementAmount, chargeSubtotal, sstPercent, servicePercent, chargeRounding],
                              flags: [rememberCategory, splitting, friendPays, fuel, equal, includeMe, reimbursementEnabled, chargesEnabled],
                              date: date, items: itemDrafts, people: people, place: place, tripID: tripID)
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
                if let saved = recoverable {
                    Section(tr("未保存的草稿", "Unsaved draft", "Draf belum disimpan")) {
                        Text(dateLabel(saved.updated, time: true)).font(.caption).foregroundStyle(.secondary)
                        if saved.base == original {
                            Button(tr("继续填写", "Resume draft", "Sambung draf")) { restoreDraft(saved) }
                                .accessibilityIdentifier("transaction.draft.resume")
                        } else {
                            Text(tr("原账目已更新，旧草稿不能覆盖新记录。", "This entry has changed; the old draft cannot overwrite it.", "Rekod telah berubah; draf lama tidak boleh menimpanya."))
                        }
                        Button(tr("放弃旧草稿", "Discard old draft", "Buang draf lama"), role: .destructive) {
                            ExpenseDraftStorage.remove(original?.id); recoverable = nil
                        }
                    }
                }
                if original == nil && initialDraft == nil { ManualEntryTypeSection(selection: $entryType) }
                paymentSection
                chargeSection
                payerSection
                merchantSection
                if !model.ledger.trips.isEmpty {
                    Section(tr("旅行账本", "Travel book", "Buku perjalanan")) {
                        Picker(tr("预算归属", "Budget", "Bajet"), selection: $tripID) {
                            Text(tr("日常月预算", "Daily monthly budget", "Bajet bulanan harian")).tag(String?.none)
                            ForEach(model.ledger.trips) { trip in Text(trip.name).tag(Optional(trip.id)) }
                        }
                        Text(tr("旅行只扣独立预算，个人总支出仍会保留。", "Travel uses its own budget and remains in total spending.", "Perjalanan menggunakan bajet sendiri dan kekal dalam jumlah belanja."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                ExpensePlaceField(place: $place, locator: placeLocator, notice: placeNotice) {
                    finishKeyboard(); editingPlace = true
                }
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
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(tr("取消", "Cancel", "Batal"), systemImage: "xmark") { requestClose() }.disabled(saving) }; ToolbarItem(placement: .confirmationAction) { Button { beginSave() } label: {
                    EditorSaveLabel(saving: saving)
                }.yuejiPrimaryButton().disabled(rateLoading || saving || recoverable != nil) } }
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button(tr("完成", "Done", "Selesai")) { finishKeyboard() }
                    }
                }
                .onAppear { load() }
                .onChange(of: snapshot) { _, _ in persistDraft() }
                .onChange(of: phase) { _, value in if value != .active { persistDraft() } }
                .task(id: currency) {
                    guard !model.isPreview else { return }
                    let request = UUID(), code = currency, submittedRate = rate
                    rateRequest = request
                    guard original == nil, !resumedDraft, code != "MYR" else { rateLoading = false; return }
                    rateLoading = true; defer { if rateRequest == request { rateLoading = false } }
                    do {
                        if let q = try await AutomaticRates.shared.refresh(code) {
                            try Task.checkCancellation()
                            guard !resumedDraft, currency == code, rateRequest == request else { return }
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
            .task(id: initialized && recoverable == nil) {
                guard initialized, recoverable == nil, !startedLocation, original == nil,
                      !resumedDraft, !model.isPreview else { return }
                guard abs(date.timeIntervalSinceNow) < 300 else {
                    placeNotice = tr("补记账目不会使用当前位置，请按需选择消费地点。", "Past entries do not use your current location. Choose a place if needed.", "Rekod lama tidak menggunakan lokasi semasa. Pilih tempat jika perlu.")
                    return
                }
                startedLocation = true
                if place == nil { placeLocator.start(automatic: true) }
            }
            .onDisappear { placeLocator.cancel() }
            .onChange(of: place) { _, value in
                if value != placeLocator.result { placeLocator.cancel() }
            }
            .onChange(of: placeLocator.result) { _, value in
                guard let value, !editingPlace, !saving, !draftFinished else { return }
                guard original != nil || value.belongsToRecordingTime(date) else { return }
                placeNotice = nil
                // Automatic metadata alone must not make an untouched form dirty.
                if value.capturedAt != nil { initialSnapshot?.place = value }
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { place = value }
            }
            .onChange(of: date) { _, value in
                guard initialized, original == nil else { return }
                if abs(value.timeIntervalSinceNow) > 300 { placeLocator.cancel() }
                if let place, !place.belongsToRecordingTime(value) {
                    self.place = nil; initialSnapshot?.place = nil
                    placeNotice = tr("日期已改变，已移除当前自动定位，避免记错消费地点。可手动选择地点。", "Date changed. The automatic location was removed; you can select the purchase location.", "Tarikh berubah. Lokasi automatik dibuang; anda boleh memilih lokasi belanja.")
                }
            }
            .sheet(isPresented: $editingPlace) {
                ExpensePlaceMapSheet(initial: place, merchantHint: name) { value in
                    placeNotice = nil
                    var chosen = value
                    chosen.capturedAt = nil // An explicit map choice is not an automatic recording-time guess.
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { place = chosen }
                }
            }
            .editorDismissal(hasChanges: hasChanges, saving: saving, confirming: $confirmingDiscard, discard: {
                finishDraft(); dismiss()
            })
    }
    private func persistDraft() {
        guard initialized, !model.isPreview, !draftFinished, recoverable == nil else { return }
        guard hasChanges else { ExpenseDraftStorage.remove(original?.id); return }
        ExpenseDraftStorage.write(SavedExpenseDraft(base: original, seed: draftSeed,
            fields: snapshot, rateDate: rateDate, rateSource: rateSource), id: original?.id)
    }
    private func finishDraft() {
        draftFinished = true
        if !model.isPreview { ExpenseDraftStorage.remove(original?.id) }
    }
    private func restoreDraft(_ draft: SavedExpenseDraft) {
        place = draft.fields.place
        tripID = draft.fields.tripID
        guard draft.supported, draft.base == original else { return }
        let t = draft.fields.text, f = draft.fields.flags
        name = t[0]; entryDescription = t[1]; amount = t[2]; currency = t[3]; rate = t[4]
        category = t[5]; entryType = t[6]; payerName = t[7]; friendPaidMode = t[8]; friendShareText = t[9]
        reimbursementRecipient = t[10]; reimbursementAmount = t[11]; chargeSubtotal = t[12]
        sstPercent = t[13]; servicePercent = t[14]; chargeRounding = t[15]
        rememberCategory = f[0]; splitting = f[1]; friendPays = f[2]; fuel = f[3]; equal = f[4]
        includeMe = f[5]; reimbursementEnabled = f[6]; chargesEnabled = f[7]
        date = draft.fields.date; itemDrafts = draft.fields.items; people = draft.fields.people
        rateDate = draft.rateDate; rateSource = draft.rateSource; foreignExpanded = currency != "MYR"
        draftSeed = draft.seed; resumedDraft = true; recoverable = nil
    }
    private var paymentSection: some View {
        Section(tr("实际付款", "Payment", "Bayaran")) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(currency).font(.headline).foregroundStyle(.secondary)
                TextField("0.00", text: $amount)
                    .keyboardType(.decimalPad).focused($focusedField, equals: .amount)
                    .accessibilityIdentifier("transaction.amount")
                    .font(.system(.largeTitle, weight: .semibold))
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
        draftSeed = initialDraft
        if !model.isPreview { recoverable = ExpenseDraftStorage.read(original?.id) }
        if original == nil { date = initialDate; splitting = startWithSplit }
        if let e = original ?? initialDraft {
            name = e.merchant; date = e.date; category = e.category; fuel = e.fuel
            entryDescription = e.entryDescription ?? ""
            place = e.place
            tripID = e.tripID
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
            let n = try total(); var entry = original ?? draftSeed ?? Expense(merchant: "", cents: n)
            if entry.cents != n || currency != "MYR" { entry.receiptSummary = nil }
            if let original, original.date != date { entry.timeSource = "edited" }
            entry.merchant = name.trimmingCharacters(in: .whitespacesAndNewlines); entry.cents = n; entry.date = date; entry.category = category; entry.fuel = fuel
            let description = entryDescription.trimmingCharacters(in: .whitespacesAndNewlines)
            entry.entryDescription = description.isEmpty ? nil : description
            entry.place = place
            entry.tripID = tripID
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
            if draftSeed != nil && splitting {
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
            finishDraft()
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
    private var unsettled: Int { balances.filter { $0.owed > 0 || $0.payable > 0 }.count }
    var body: some View {
        let _ = uiLocale.identifier
        NavigationStack {
            List {
                // What friends owe, on the page itself like a balance (the kit's Mobile Banking).
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .center, spacing: 12) {
                            Text(tr("朋友还欠你", "Friends owe you", "Rakan berhutang kepada anda"))
                                .font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                                .textCase(.uppercase)
                            Spacer(minLength: 8)
                            let waiting = Array(balances.filter { $0.owed > 0 || $0.payable > 0 }.prefix(4))
                            if !waiting.isEmpty {
                                HStack(spacing: -8) {
                                    ForEach(waiting) { friend in
                                        IslandAvatar(name: friend.name, size: 28)
                                            .overlay(Circle().strokeBorder(IslandTheme.paper, lineWidth: 2))
                                    }
                                }.accessibilityHidden(true)
                            }
                        }
                        AnimatedMoney(cents: balances.reduce(0) { $0 + $1.owed })
                            .font(.largeTitle.bold()).foregroundStyle(.primary)
                            .minimumScaleFactor(0.6).lineLimit(1)
                        let payable = balances.reduce(0) { $0 + $1.payable }
                        if payable > 0 {
                            Text(tr("我欠朋友：", "I owe friends: ", "Saya berhutang kepada rakan: ") + money(payable))
                                .font(.subheadline).foregroundStyle(.orange)
                        }
                        Text(tr("全部月份 · 点朋友查看明细和记录还款", "All months · tap a friend to settle up", "Semua bulan · ketik rakan untuk bayar balik"))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 4, trailing: 20))
                }
                Section {
                    Picker(tr("显示", "Show", "Papar"), selection: $settled) {
                        Text(tr("未结清", "Outstanding", "Belum selesai")).tag(false)
                        Text(tr("已结清", "Settled", "Selesai")).tag(true)
                    }.pickerStyle(.segmented).listRowBackground(Color.clear).listRowInsets(EdgeInsets())
                }
                Section {
                    if visible.isEmpty {
                        IslandEmptyState(title: settled ? tr("还没有结清记录", "No settled balances", "Tiada baki selesai") : tr("目前没有待收款", "Nothing outstanding", "Tiada baki tertunggak"),
                            message: tr("新增代垫，或到账本为已有付款开启分账。", "Add an advance, or split an existing payment in Ledger.", "Tambah pendahuluan, atau bahagi bayaran sedia ada dalam Lejar."),
                            mood: settled ? .sleepy : .excited)
                            .listRowBackground(Color.clear)
                    }
                    ForEach(visible) { friend in
                        NavigationLink { FriendDetailView(key: friend.id) } label: { FriendBalanceRow(friend: friend) }
                            .guideTarget(friend.id == "amy" ? "friends.person" : "friends.other")
                    }
                } header: {
                    DashboardSectionHeader(title: settled ? tr("已结清", "Settled", "Selesai") : tr("朋友", "Friends", "Rakan"))
                }
                Section {
                    NavigationLink { FuelCalculatorView() } label: { SimpleSettingsRow(title: tr("行程分摊", "Split a trip", "Bahagi perjalanan"), subtitle: tr("油费、停车费、过路费", "Fuel, parking and tolls", "Minyak, parkir dan tol"), symbol: "car.fill", color: IslandPalette.lagoon) }
                    NavigationLink { SplitHistoryView() } label: { IslandRowLabel(title: tr("全部分账记录", "All split entries", "Semua rekod pembahagian"), symbol: "list.bullet.rectangle.fill", color: IslandPalette.lavender) }
                } header: {
                    DashboardSectionHeader(title: tr("分账工具", "Split tools", "Alat pembahagian"))
                }
            }.yuejiDashboardSurface().navigationTitle(tr("朋友分账", "Shared expenses", "Belanja dikongsi")).navigationBarTitleDisplayMode(.large)
                .yuejiSubtitle(tr("\(unsettled) 位待结清", "\(unsettled) to settle up", "\(unsettled) belum selesai"))
                .toolbar { Button { adding = true } label: { Label(tr("新增代垫", "Add advance", "Tambah pendahuluan"), systemImage: "plus") } }
                .sheet(isPresented: $adding) { ExpenseEditor(original: nil, startWithSplit: true) }
        }
    }
}
/// A friend as Messages lists a conversation: avatar, name with the net amount beside it,
/// and one line saying who pays whom.
struct FriendBalanceRow: View {
    @Environment(\.locale) private var uiLocale
    let friend: FriendBalance
    private var net: Int { friend.owed - friend.payable }
    private var settled: Bool { friend.owed == 0 && friend.payable == 0 }
    private var netColor: Color { settled || net == 0 ? .secondary : (net > 0 ? .green : .orange) }
    private var status: String {
        if settled { return tr("已结清", "Settled", "Selesai") }
        if friend.owed > 0 && friend.payable > 0 {
            return tr("待收 ", "To collect ", "Belum diterima ") + money(friend.owed) + " · " + tr("我欠 ", "I owe ", "Saya berhutang ") + money(friend.payable)
        }
        return settlementDirection(net, name: friend.name)
    }
    var body: some View {
        let _ = uiLocale.identifier
        HStack(spacing: 12) {
            IslandAvatar(name: friend.name, settled: settled)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(friend.name).font(.headline).lineLimit(1)
                    Spacer(minLength: 8)
                    AnimatedMoney(cents: abs(net)).font(.subheadline.weight(.semibold)).foregroundStyle(netColor)
                }
                Text(status).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
            }
        }.padding(.vertical, 4)
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
                    ToolbarItem(placement: .cancellationAction) { Button(tr("取消", "Cancel", "Batal"), systemImage: "xmark") { dismiss() }.disabled(saving) }
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
    @AppStorage("playfulAnimations") private var playful = true
    @AppStorage("animationSounds") private var sounds = true
    @AppStorage("feedbackHaptics") private var haptics = true
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
                // The app's own card, centred like the contact header in the kit's Messages.
                Section {
                    VStack(spacing: 8) {
                        Image("YueJiLogo").renderingMode(.original).resizable().scaledToFit().frame(width: 84, height: 84)
                            .clipShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 19, style: .continuous).strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5))
                            .accessibilityHidden(true)
                        Text(tr("月记 YueJi", "YueJi", "YueJi")).font(.title2.bold())
                        Text(tr("让每一笔，都清楚。", "Clarity in every entry.", "Jelas dalam setiap rekod.")).font(.subheadline).foregroundStyle(.secondary)
                    }
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .listRowBackground(Color.clear)
                }


                Section {
                    NavigationLink { appearancePage } label: {
                        SimpleSettingsRow(title: tr("外观与语言", "Appearance & language", "Paparan & bahasa"), subtitle: tr("让月记更适合你", "Make YueJi feel like yours", "Sesuaikan YueJi untuk anda"), symbol: "circle.lefthalf.filled", color: IslandPalette.lavender)
                    }.guideTarget("settings.appearance")
                    NavigationLink { NotificationSettingsView() } label: {
                        SimpleSettingsRow(title: tr("提醒与通知", "Reminders & notifications", "Peringatan & notifikasi"), subtitle: tr("记账结果、每日提醒和预算", "Saved entries, daily reminders and budget", "Rekod, peringatan harian dan bajet"), symbol: "bell.fill", color: IslandPalette.pumpkin)
                    }
                } header: { Text(tr("使用习惯", "Your preferences", "Pilihan anda")) }
                Section {
                    NavigationLink { AutomationSetupView() } label: {
                        SimpleSettingsRow(title: tr("自动记账", "Automatic recording", "Rekod automatik"), subtitle: "Apple Pay · TNG · Bank", symbol: "bolt.fill", color: IslandPalette.lagoon)
                    }
                    NavigationLink { categoriesPage } label: {
                        SimpleSettingsRow(title: tr("消费分类", "Spending categories", "Kategori belanja"), subtitle: tr("整理每一笔消费", "Keep spending organized", "Susun setiap belanja"), symbol: "square.grid.2x2.fill", color: IslandPalette.sky)
                    }
                    NavigationLink { RatesView() } label: {
                        SimpleSettingsRow(title: tr("外币记账", "Foreign currency", "Mata wang asing"), subtitle: tr("把外币消费换算成马币", "Convert spending to ringgit", "Tukar belanja kepada ringgit"), symbol: "globe", color: IslandPalette.mint)
                    }
                } header: { Text(tr("记账设置", "Recording", "Rekod")) }
                Section {
                    NavigationLink { backupPage } label: {
                        SimpleSettingsRow(title: tr("备份与导出", "Backups & export", "Sandaran & eksport"), subtitle: tr("备份、恢复、导出账单", "Save, restore and export", "Simpan, pulih dan eksport"), symbol: "externaldrive.fill", color: IslandPalette.lavender)
                    }.guideTarget("settings.backup")
                    NavigationLink { aboutPage } label: {
                        SimpleSettingsRow(title: tr("关于月记", "About YueJi", "Tentang YueJi"), subtitle: installedVersionLabel, symbol: "info.circle.fill", color: IslandPalette.pebble)
                    }
                    NavigationLink { OverviewToolsView() } label: {
                        SimpleSettingsRow(title: tr("更多工具", "More tools", "Alat lain"), subtitle: tr("月度对比、消费预览与查重", "Comparisons, upcoming bills & duplicates", "Perbandingan, bil & pendua"), symbol: "square.grid.2x2.fill", color: IslandPalette.sky)
                    }
                    Button { showingUsageGuide = true } label: {
                        SimpleSettingsRow(title: tr("使用指南", "Getting started", "Panduan penggunaan"), subtitle: tr("一步步学会使用月记", "Learn YueJi step by step", "Belajar YueJi langkah demi langkah"), symbol: "book.fill", color: IslandPalette.mint)
                    }
                } header: { Text(tr("备份与帮助", "Backups & help", "Sandaran & bantuan")) }
            }.yuejiDashboardSurface().navigationTitle(tr("设置", "Settings", "Tetapan")).navigationBarTitleDisplayMode(.large)
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
            Section {
                Toggle(tr("动画", "Animations", "Animasi"), isOn: $playful)
                Toggle(tr("音效", "Sound effects", "Kesan bunyi"), isOn: $sounds)
                Toggle(tr("触感反馈", "Haptics", "Haptik"), isOn: $haptics)
            } header: {
                Text(tr("动画与反馈", "Motion & feedback", "Gerakan & maklum balas"))
            } footer: {
                Text(tr("开启系统“减弱动态效果”或低电量模式时，动画会自动减少。", "Animations are reduced automatically with Reduce Motion or Low Power Mode.", "Animasi dikurangkan secara automatik dengan Kurangkan Gerakan atau Mod Kuasa Rendah."))
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
                IslandEmptyState(title: tr("需要通知触发器", "Notification trigger required", "Pencetus notifikasi diperlukan"),
                                 message: tr("此演示使用 iOS 27 的通知自动化。当前系统没有这个入口时，可继续手动记账。", "This walkthrough uses iOS 27 notification automations. If your system does not have this trigger, use manual recording.", "Panduan ini menggunakan automasi notifikasi iOS 27. Jika pencetus tiada, guna rekod manual."),
                                 mood: .worried)
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
        .background(IslandBackdrop())
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
            IslandIconTile(symbol: symbol, color: color, size: 36, filled: true)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.body.weight(.semibold)).foregroundStyle(.primary)
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
                    SimpleSettingsRow(title: "Apple Pay", subtitle: tr("付款后记录消费", "Record after payment", "Rekod selepas bayaran"), symbol: "creditcard.fill", color: IslandPalette.sky)
                }.guideTarget("automation.apple")
                NavigationLink { TNGInboxView() } label: {
                    SimpleSettingsRow(title: tr("银行与 TNG", "Banks and TNG", "Bank dan TNG"), subtitle: tr("设置付款记录，确认收到的交易", "Set up recording and review transactions", "Sediakan rekod dan semak transaksi"), symbol: "bell.badge.fill", color: IslandPalette.lagoon)
                }.guideTarget("automation.tng")
            } footer: { Text(tr("跟着说明在「快捷指令」设置一次。之后收到的付款资料会交给月记处理。", "Follow the steps in Shortcuts once. Payment details it receives can then be sent to YueJi.", "Ikut langkah dalam Pintasan sekali. Butiran bayaran yang diterima kemudian boleh dihantar ke YueJi.")) }
            Section {
                NavigationLink(tr("最近自动记账", "Recent automatic entries", "Rekod automatik terkini")) { AutomationStatusView() }
            }
        }.yuejiListSurface().navigationTitle(tr("自动记账", "Automatic recording", "Rekod automatik")).navigationBarTitleDisplayMode(.inline)
    }
}
/// Apple's own Liquid Glass buttons on iOS 26 and later, so presses, highlights and
/// morphing are exactly the system's; standard bordered buttons otherwise.
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
            content.background(IslandTheme.card, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        } else if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        } else {
            content.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        }
    }
}

// Transaction details use standard push/pop from every entry point, including Overview.
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
    @Environment(\.dynamicTypeSize) private var typeSize
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
            .background(IslandBackdrop())
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
            .background(IslandTheme.paper)
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
            .background(IslandTheme.paper)
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
        .background(IslandTheme.paper)
    }

    private func heading(_ text: String) -> some View {
        Text(text).font(.system(size: 28, weight: .bold)).frame(maxWidth: .infinity, alignment: .leading)
    }
    private func section<Content: View>(_ title: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title { Text(title).font(.footnote.weight(.semibold)).foregroundStyle(.secondary).padding(.leading, 4) }
            VStack(spacing: 0) { content() }
                .background(IslandTheme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.primary.opacity(0.05), lineWidth: 1))
                .shadow(color: .black.opacity(0.05), radius: 8, y: 3)
        }
    }
    private func row(_ name: String, _ value: String = "", icon: String = "", target: String? = nil, tint: Color = IslandTheme.accent) -> some View {
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
                let icons = ["chart.pie.fill", "list.bullet.rectangle.fill", "arrow.triangle.2.circlepath", "person.2.fill", "gearshape.fill"]
                let labels = [tr("概览", "Overview", "Ringkasan"), tr("账本", "Ledger", "Lejar"), tr("固定", "Recurring", "Berulang"), tr("分账", "Split", "Bahagi"), tr("设置", "Settings", "Tetapan")]
                VStack(spacing: 4) {
                    Image(systemName: icons[index]).font(.system(size: 19))
                    Text(labels[index]).font(.system(size: 10))
                }
                .foregroundStyle(selected == index ? IslandTheme.accent : Color.secondary)
                .frame(maxWidth: .infinity)
            }
        }.padding(.top, 10).frame(height: 62).background(IslandTheme.paper)
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


private struct NotificationBannerCard: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let title: String
    var message: String = ""
    var symbol = "checkmark"
    var color = IslandPalette.mint
    let interaction: BannerInteraction
    var actionTitle: String? = nil
    var actionEnabled = true
    var action: (() -> Void)? = nil
    /// The app logo, like a system notification, with the status symbol as a small badge.
    @ViewBuilder private var badge: some View {
        if typeSize.isAccessibilitySize {
            Image(systemName: symbol).font(.title3.weight(.semibold)).foregroundStyle(color)
                .frame(width: 28, height: 32)
        } else {
            Image("YueJiLogo").resizable().scaledToFit().frame(width: 38, height: 38)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: symbol).font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(color))
                        .overlay(Circle().strokeBorder(IslandTheme.card, lineWidth: 2))
                        .offset(x: 5, y: 5)
                }
                .padding(.trailing, 4).padding(.bottom, 4)
        }
    }
    private var label: some View {
        HStack(alignment: .center, spacing: 12) {
            badge.accessibilityHidden(true)
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

/// The opening's steps, in order.
private enum OpeningStage: Int, Comparable {
    /// The first frame: only the background, as the system launch screen.
    case start
    /// Blue Liquid Glass droplets form around the centre.
    case drops
    /// The droplets flow together into one glass moon, the moon of the app icon.
    case merged
    /// The icon's gold crescent and three entries appear on the glass and the wordmark
    /// sharpens in from a blur.
    case moon
    /// The reveal: the moon and wordmark zoom towards the viewer as the app fades in.
    case departing
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// One Liquid Glass droplet of the opening. The first is the core that swells into the
/// moon; the others form around it and flow into it.
private struct OpeningDrop: Identifiable {
    let id: Int
    /// Where it forms: degrees clockwise from the trailing side, and points out.
    let angle: Double
    let distance: CGFloat
    let size: CGFloat
    static let all = [
        OpeningDrop(id: 0, angle: 0, distance: 0, size: 30),
        OpeningDrop(id: 1, angle: -112, distance: 112, size: 30),
        OpeningDrop(id: 2, angle: -38, distance: 96, size: 20),
        OpeningDrop(id: 3, angle: 18, distance: 124, size: 36),
        OpeningDrop(id: 4, angle: 82, distance: 100, size: 24),
        OpeningDrop(id: 5, angle: 146, distance: 118, size: 32),
        OpeningDrop(id: 6, angle: 208, distance: 90, size: 18),
    ]
}

/// The icon's lit crescent (月): the moon's disc minus a disc of 0.98 its radius, centred
/// 0.45 of its radius away up and to the right (38°), as `generate_icon.py` draws it.
/// Inset by `rounding`, so a round-joined stroke twice that wide rounds the horns.
private struct OpeningCrescent: Shape {
    var rounding: CGFloat = 0
    func path(in rect: CGRect) -> Path {
        let r = min(rect.width, rect.height) / 2
        let angle = 38 * Double.pi / 180
        let disc = Self.circle(CGPoint(x: rect.midX, y: rect.midY), r - rounding)
        let cut = Self.circle(CGPoint(x: rect.midX + r * 0.45 * CGFloat(cos(angle)),
                                      y: rect.midY - r * 0.45 * CGFloat(sin(angle))), r * 0.98 + rounding)
        return disc.subtracting(cut)
    }
    private static func circle(_ centre: CGPoint, _ radius: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2))
    }
}

/// The opening, in the Liquid Glass of iOS 26/27, about 1 s to the reveal: on the tabs'
/// softly lit page, blue glass droplets form around the centre and flow together into the
/// glass moon of the app icon, merging like liquid because they share one glass container.
/// The icon's gold crescent and three white entries appear on the glass while the wordmark
/// sharpens in from a blur. Once the ledger has loaded, the moon and wordmark zoom towards
/// the viewer and MainView fades the opening into the app. Before iOS 26, and with Reduce
/// Transparency, the droplets are solid blue; with Animations off or Reduce Motion only the
/// finished moon and wordmark show.
private struct OpeningAnimationView: View {
    @Environment(\.locale) private var uiLocale
    var sound = true
    /// Whether the ledger has loaded. The reveal waits for it, so it never opens onto a blank screen.
    var ready = true
    var onFinished: () -> Void
    @Environment(\.scenePhase) private var phase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @AppStorage("playfulAnimations") private var playful = true
    @State private var playedSound = false
    @State private var stage = OpeningStage.start
    @State private var finished = false
    /// Mirrors `ready` so the running sequence sees updates while it waits.
    @State private var ledgerReady = false
    /// True from the moment the reveal starts (or the opening ends).
    @State private var revealed = false
    private var animates: Bool { playful && !reduceMotion }
    /// The step to draw: without animation, the finished moon straight away.
    private var shown: OpeningStage { animates ? stage : .moon }
    /// The moon's diameter once the droplets have merged.
    private static let moonSize: CGFloat = 116
    /// The icon's three entries in units of the moon's radius: rows from the centre,
    /// lengths, thickness and their shared leading edge (from `generate_icon.py`).
    private static let entryRows: [CGFloat] = [-0.403, -0.097, 0.208]
    private static let entryLengths: [CGFloat] = [0.944, 0.75, 0.556]
    private static let entryThickness: CGFloat = 0.144
    private static let entryLeading: CGFloat = -0.33
    /// The icon's shadow colour and gold.
    private static let ink = Color(red: 6 / 255, green: 26 / 255, blue: 80 / 255)
    private static let gold = LinearGradient(colors: [Color(red: 1, green: 232 / 255, blue: 170 / 255),
                                                      Color(red: 238 / 255, green: 168 / 255, blue: 74 / 255)],
                                             startPoint: .top, endPoint: .bottom)
    var body: some View {
        let _ = uiLocale.identifier
        ZStack {
            Color("LaunchBackground")
            // The tabs' lit page, so the opening hands over to the Overview seamlessly.
            AmbientGlowBackdrop()
                .opacity(shown > .start ? 1 : 0)
                .animation(.smooth(duration: 0.45), value: shown)
            ZStack {
                droplets
                moonDetail(shown: shown >= .moon)
                wordmark(shown: shown >= .moon)
                    .offset(y: Self.moonSize / 2 + 44)
            }
            // The zoom into the app.
            .scaleEffect(stage == .departing ? 2.2 : 1)
            .opacity(stage == .departing ? 0 : 1)
            .animation(.easeIn(duration: 0.28), value: stage)
        }
        .ignoresSafeArea()
        // Skipping is handled by MainView: this layer never takes touches.
        .onChange(of: ready, initial: true) { _, value in ledgerReady = value }
        .task {
            // Finishing the optional opening must not depend on scene callbacks.
            // Give the initial frame time to appear without blocking the UI.
            do {
                try await Task.sleep(for: .milliseconds(30))
                guard animates else {
                    try await Task.sleep(for: .milliseconds(100))
                    finish(); return
                }
                // Each layer animates its own part of every step (see the views below).
                stage = .drops
                try await Task.sleep(for: .milliseconds(210))
                stage = .merged
                try await Task.sleep(for: .milliseconds(360))
                stage = .moon
                try await Task.sleep(for: .milliseconds(400))
                // Hold while the ledger loads: the reveal only opens onto real content.
                while !ledgerReady { try await Task.sleep(for: .milliseconds(50)) }
                stage = .departing
                // Let the zoom get going before MainView fades the opening into the app.
                try await Task.sleep(for: .milliseconds(70))
                finish()
            } catch { return }
        }
        .task(id: phase) {
            // Sound still waits for foreground activation; screen readiness does not.
            guard phase == .active, sound, !playedSound else { return }
            FeedbackSounds.shared.play(.launch)
            playedSound = true
        }
        .accessibilityElement(children: .ignore).accessibilityLabel(tr("月记 YueJi", "YueJi", "YueJi"))
        .accessibilityAction { finish() }
        // Once the app is being revealed, leave the accessibility tree immediately. Otherwise
        // the full-screen element lingers during the fade-out and makes the newly mounted
        // toolbar (Add Entry) look covered to accessibility hit-testing and UI tests.
        .accessibilityHidden(revealed)
    }
    private func finish() {
        guard !finished else { return }
        finished = true
        revealed = true
        onFinished()
    }
    /// The droplets share one glass container on iOS 26 and later, so they blend and merge
    /// like liquid as they meet, exactly as the system's own glass does; solid blue circles
    /// otherwise.
    @ViewBuilder private var droplets: some View {
        if #available(iOS 26.0, *), !reduceTransparency {
            GlassEffectContainer(spacing: 24) {
                dropletField { size in
                    Color.clear.frame(width: size, height: size)
                        .glassEffect(.regular.tint(IslandTheme.accent), in: Circle())
                }
            }
        } else {
            dropletField { size in
                Circle().fill(IslandTheme.accent.gradient).frame(width: size, height: size)
            }
        }
    }
    /// Lays the droplets out for the current step: they pop up around the centre, then flow
    /// into it, the core swelling into the moon with a slight wobble while the others sink in.
    private func dropletField<Drop: View>(@ViewBuilder _ drop: @escaping (CGFloat) -> Drop) -> some View {
        ZStack {
            ForEach(OpeningDrop.all) { item in
                drop(dropSize(item))
                    .offset(shown < .merged ? place(item.angle, item.distance) : .zero)
                    // Solid droplets sink beneath the core instead of showing through it.
                    .zIndex(item.id == 0 ? 1 : 0)
                    .animation(shown == .drops
                               ? Animation.spring(duration: 0.32, bounce: 0.32).delay(Double(item.id) * 0.015)
                               : Animation.spring(duration: 0.48, bounce: 0.22).delay(Double(item.id) * 0.02), value: shown)
            }
        }
        // Room for every droplet, so the glass container never clips one.
        .frame(width: 320, height: 320)
    }
    private func dropSize(_ drop: OpeningDrop) -> CGFloat {
        if shown < .drops { return 0 }
        if shown < .merged { return drop.size }
        return drop.id == 0 ? Self.moonSize : drop.size * 0.6
    }
    /// The icon's moon on the glass: three white entries (记) left-aligned just clear of the
    /// gold crescent (月) in front, placed as in the icon.
    private func moonDetail(shown: Bool) -> some View {
        let r = Self.moonSize / 2
        let rounding = r * 0.033
        return ZStack {
            ForEach(0..<3, id: \.self) { index in
                let length = r * Self.entryLengths[index]
                Capsule().fill(Color.white)
                    .frame(width: length, height: r * Self.entryThickness)
                    .shadow(color: Self.ink.opacity(0.25), radius: 2, y: 1)
                    .position(x: r + r * Self.entryLeading + length / 2, y: r + r * Self.entryRows[index])
                    .offset(x: shown ? 0 : -10)
                    .opacity(shown ? 1 : 0)
                    .animation(.smooth(duration: 0.3).delay(0.04 + Double(index) * 0.04), value: shown)
            }
            OpeningCrescent(rounding: rounding)
                .fill(Self.gold)
                .overlay {
                    OpeningCrescent(rounding: rounding)
                        .stroke(Self.gold, style: StrokeStyle(lineWidth: rounding * 2, lineJoin: .round))
                }
                .shadow(color: Self.ink.opacity(0.35), radius: r * 0.05, x: r * 0.028, y: r * 0.05)
                .scaleEffect(shown ? 1 : 0.8)
                .opacity(shown ? 1 : 0)
                .animation(.spring(duration: 0.4, bounce: 0.18), value: shown)
        }
        .frame(width: Self.moonSize, height: Self.moonSize)
    }
    /// The name, sharpening in from a blur as the moon completes.
    private func wordmark(shown: Bool) -> some View {
        Text(tr("月记", "YueJi", "YueJi"))
            .font(.system(size: 34, weight: .bold))
            .foregroundStyle(.primary)
            .blur(radius: shown ? 0 : 10)
            .scaleEffect(shown ? 1 : 1.08)
            .opacity(shown ? 1 : 0)
            .animation(.smooth(duration: 0.4), value: shown)
    }
    /// A point at the angle (degrees clockwise from the trailing side) and distance from the centre.
    private func place(_ angle: Double, _ distance: CGFloat) -> CGSize {
        let radians = angle * .pi / 180
        return CGSize(width: CGFloat(cos(radians)) * distance, height: CGFloat(sin(radians)) * distance)
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
            // Drops in from the top, like a system notification.
            insertion: .move(edge: .top).combined(with: .opacity),
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
                        symbol: "trash", color: IslandPalette.pebble, interaction: interaction,
                        actionTitle: tr("撤销", "Undo", "Batal padam"), actionEnabled: !model.deletionInFlight,
                        action: { Task { await model.undoDeletion() } })
                }.id(token).transition(bannerTransition)
            } else if let notice = model.foregroundNotice {
                SwipeDismissBanner(onDismiss: { model.dismissForegroundNotice(id: notice.id) },
                    onInteraction: { model.setBannerInteraction(id: notice.id.uuidString, active: $0) }) { interaction in
                    NotificationBannerCard(title: notice.title, message: notice.message, symbol: "bell.badge.fill", color: IslandPalette.sky,
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
                        symbol: "tray.and.arrow.down.fill", color: IslandPalette.lagoon, interaction: interaction, action: {
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
            if target.kind == "recurring" {
                // A renewal reminder opens its schedule.
                NavigationStack {
                    RecurringDetailView(ruleID: target.recordID)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button(tr("完成", "Done", "Selesai"), systemImage: "checkmark") { dismiss() } } }
                }
            } else if target.kind == "expense", let entry = model.expense(id: target.recordID) {
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
                    }.toolbar { ToolbarItem(placement: .confirmationAction) { Button(tr("完成", "Done", "Selesai"), systemImage: "checkmark") { dismiss() } } }
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
