import SwiftUI
import Charts

// MARK: - Heatmap colours and layout

/// The heatmap's single-hue scale: the app tint in four steps over a neutral fill for days
/// without spending. Opacity steps over the card keep lightness in order in light and dark
/// mode alike. Days still to come are fainter still.
enum HeatPalette {
    static let steps: [Double] = [0.22, 0.42, 0.66, 1.0]
    static func color(level: Int) -> Color {
        level <= 0 ? Color(uiColor: .tertiarySystemFill) : IslandTheme.accent.opacity(steps[min(level, 4) - 1])
    }
    static let upcoming = Color(uiColor: .quaternarySystemFill)
}

/// Where a month's days fall in a week grid.
struct HeatMonthLayout: Equatable {
    let month: Int
    let start: Date
    let days: Int
    /// Empty cells before the 1st.
    let leading: Int
    init(year: Int, month: Int, calendar: Calendar) {
        self.month = month
        start = calendar.date(from: DateComponents(year: year, month: month, day: 1)) ?? Date()
        days = calendar.range(of: .day, in: .month, for: start)?.count ?? 30
        leading = (calendar.component(.weekday, from: start) - calendar.firstWeekday + 7) % 7
    }
    func date(day: Int, calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: day - 1, to: start) ?? start
    }
}

/// The insights' calendar for display: the same days as the counts, with the device's first
/// weekday and the app's language for names.
private func heatDisplayCalendar() -> Calendar {
    var calendar = InsightCalendar.make()
    calendar.locale = Locale(identifier: AppLanguage.localeID)
    calendar.firstWeekday = Calendar.current.firstWeekday
    return calendar
}

// MARK: - Year in review

/// The year's spending at a glance: the total against the year before, a calendar heatmap
/// of every day, the chosen month's calendar with each day's entries, the months as bars,
/// highlights, and where the money went. Amounts follow the Overview's eye.
struct YearReviewView: View {
    @Environment(\.locale) private var uiLocale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var model: LedgerModel
    @AppStorage("hideOverviewAmounts") private var hidden = false
    @ScaledMetric(relativeTo: .largeTitle) private var heroSize: CGFloat = 40
    @State private var year: Int
    @State private var month: Int
    @State private var selectedDay: Date?
    @State private var dayEntries: [Expense] = []
    @State private var snapshot: YearSnapshot?
    @State private var loaded: YearQuery?

    private struct YearQuery: Equatable {
        let revision: Int
        let year: Int
        let locale: String
        let day: String
    }

    init(month: Date = Date()) {
        let calendar = InsightCalendar.make()
        _year = State(initialValue: calendar.component(.year, from: month))
        _month = State(initialValue: calendar.component(.month, from: month))
    }

    private var calendar: Calendar { heatDisplayCalendar() }
    private var currentYear: Int { InsightCalendar.make().component(.year, from: Date()) }
    private var earliestYear: Int { min(snapshot?.earliestYear ?? year, year) }
    private func amountText(_ cents: Int) -> String { hidden ? DashboardView.maskedAmount : money(cents) }
    private func monthName(_ month: Int) -> String { calendar.standaloneMonthSymbols[month - 1] }

    var body: some View {
        let _ = uiLocale.identifier
        // Today's date is part of the query, so the year so far moves on at midnight.
        let query = YearQuery(revision: model.ledgerRevision, year: year, locale: AppLanguage.localeID, day: dayKey(Date()))
        ScrollViewReader { scroller in
            List {
                Section {
                    yearPicker
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    hero
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 8, trailing: 20))
                }
                if let snapshot, snapshot.year == year {
                    if snapshot.total == 0 {
                        Section {
                            IslandEmptyState(title: tr("这一年还没有消费", "No spending this year", "Tiada belanja tahun ini"),
                                             message: tr("记下消费后，这里会显示全年的每一天。", "Once you record spending, every day of the year shows here.", "Selepas anda merekod belanja, setiap hari dalam tahun dipaparkan di sini."))
                                .listRowBackground(Color.clear)
                        }
                    } else {
                        heatmapSection(snapshot)
                        monthSection(snapshot)
                        monthsChartSection(snapshot)
                        highlightsSection(snapshot) { day in
                            select(day, toggle: false)
                            withAnimation(reduceMotion ? nil : YueJiMotion.detail) { scroller.scrollTo("year.month", anchor: .top) }
                        }
                        categoriesSection(snapshot)
                        merchantsSection(snapshot)
                    }
                } else {
                    Section { Color.clear.frame(height: 360).accessibilityHidden(true) }
                        .listRowBackground(Color.clear)
                }
            }
        }
        .yuejiListSurface()
        .navigationTitle(tr("年度回顾", "Year in review", "Imbasan tahunan")).navigationBarTitleDisplayMode(.inline)
        .refreshable { await model.refresh(postRecurring: false) }
        .yuejiUpdating(loaded != query)
        .task(id: query) {
            guard loaded != query else { return }
            do {
                let fresh = try await model.preparedYear(year)
                guard !Task.isCancelled, fresh.year == year else { return }
                withAnimation(reduceMotion || snapshot?.year != year ? nil : YueJiMotion.content) {
                    snapshot = fresh; loaded = query
                }
                refreshDayEntries()
            } catch is CancellationError { return }
            catch { model.error = error.localizedDescription }
        }
    }

    private func dayKey(_ date: Date) -> String {
        let parts = InsightCalendar.make().dateComponents([.year, .month, .day], from: date)
        return "\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
    }

    // MARK: Header

    private var yearPicker: some View {
        HStack(spacing: 0) {
            GlassIconButton(symbol: "chevron.left") { shift(-1) }
                .disabled(year <= earliestYear)
                .accessibilityLabel(tr("上一年", "Previous year", "Tahun sebelumnya"))
            Text(String(year))
                .font(.headline).monospacedDigit()
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentTransition(reduceMotion ? .identity : .numericText(value: Double(year)))
                .accessibilityAddTraits(.isHeader)
            GlassIconButton(symbol: "chevron.right") { shift(1) }
                .disabled(year >= currentYear)
                .accessibilityLabel(tr("下一年", "Next year", "Tahun seterusnya"))
        }
    }

    private func shift(_ offset: Int) {
        let next = min(max(year + offset, earliestYear), currentYear)
        guard next != year else { return }
        FeedbackHaptics.selection()
        withAnimation(reduceMotion ? nil : YueJiMotion.content) { year = next }
        selectedDay = nil
        dayEntries = []
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(tr("\(String(year)) 年个人消费", "Personal spending in \(String(year))", "Belanja peribadi \(String(year))"))
                .font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                .textCase(.uppercase)
            Group {
                if hidden {
                    Text(DashboardView.maskedAmount).accessibilityLabel(tr("金额已隐藏", "Amount hidden", "Amaun disembunyikan"))
                } else {
                    AnimatedMoney(cents: snapshot?.year == year ? (snapshot?.total ?? 0) : 0)
                }
            }
            .font(.system(size: heroSize, weight: .bold))
            .lineLimit(1).minimumScaleFactor(0.5)
            if let snapshot, snapshot.year == year {
                if let change = snapshot.change {
                    comparison(change)
                }
                Text(String(snapshot.entries) + tr(" 笔消费", " expenses", " belanja"))
                    .font(.footnote.weight(.medium)).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Spending more than the year before is a gentle caution; less is good news.
    private func comparison(_ change: Double) -> some View {
        let percent = Int((abs(change) * 100).rounded())
        let previous = String(year - 1)
        let sameDate = year == currentYear
        let text: String
        if percent == 0 {
            text = sameDate ? tr("与 \(previous) 年同期持平", "Level with \(previous) to this date", "Sama dengan \(previous) hingga tarikh ini")
                : tr("与 \(previous) 年持平", "Level with \(previous)", "Sama dengan \(previous)")
        } else if change > 0 {
            text = sameDate ? tr("比 \(previous) 年同期多 \(percent)%", "\(percent)% more than \(previous) to this date", "\(percent)% lebih daripada \(previous) hingga tarikh ini")
                : tr("比 \(previous) 年多 \(percent)%", "\(percent)% more than \(previous)", "\(percent)% lebih daripada \(previous)")
        } else {
            text = sameDate ? tr("比 \(previous) 年同期少 \(percent)%", "\(percent)% less than \(previous) to this date", "\(percent)% kurang daripada \(previous) hingga tarikh ini")
                : tr("比 \(previous) 年少 \(percent)%", "\(percent)% less than \(previous)", "\(percent)% kurang daripada \(previous)")
        }
        let symbol = percent == 0 ? "equal.circle.fill" : (change > 0 ? "arrow.up.right.circle.fill" : "arrow.down.right.circle.fill")
        let tint: Color = percent == 0 ? .secondary : (change > 0 ? IslandPalette.pumpkin : IslandPalette.mint)
        return Label(text, systemImage: symbol)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(tint)
    }

    // MARK: Heatmap

    private func heatmapSection(_ snapshot: YearSnapshot) -> some View {
        let calendar = self.calendar
        let today = Date()
        return Section {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 14) {
                ForEach(Array(1...12), id: \.self) { item in
                    let layout = HeatMonthLayout(year: year, month: item, calendar: calendar)
                    Button { chooseMonth(item) } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(calendar.shortStandaloneMonthSymbols[item - 1])
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(item == month ? IslandTheme.accent : Color.secondary)
                            HeatMiniMonth(layout: layout, snapshot: snapshot, calendar: calendar, today: today)
                        }
                        .padding(6)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(item == month ? IslandTheme.accent.opacity(0.1) : Color.clear))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(miniMonthLabel(item, snapshot: snapshot))
                    .accessibilityHint(tr("显示这个月的每一天", "Shows this month's days", "Tunjukkan hari-hari bulan ini"))
                    .accessibilityAddTraits(item == month ? .isSelected : [])
                }
            }
            .padding(.vertical, 6)
            HeatLegend()
        } header: {
            DashboardSectionHeader(title: tr("每一天", "Every day", "Setiap hari"))
        } footer: {
            Text(tr("颜色越深，当天花得越多。点按月份查看每一天。", "Darker days cost more. Tap a month to see its days.", "Hari lebih gelap kos lebih. Ketik bulan untuk melihat hari-harinya."))
        }
    }

    private func miniMonthLabel(_ item: Int, snapshot: YearSnapshot) -> String {
        let spentDays = snapshot.days.filter { calendar.component(.month, from: $0.key) == item && $0.value.cents > 0 }.count
        let english = spentDays == 1 ? "1 day with spending" : "\(spentDays) days with spending"
        let days = tr("\(spentDays) 天有消费", english, "\(spentDays) hari berbelanja")
        var parts = [monthName(item)]
        if !hidden { parts.append(amountText(snapshot.months[item - 1])) }
        parts.append(days)
        return parts.joined(separator: ", ")
    }

    private func chooseMonth(_ item: Int, haptic: Bool = true) {
        guard item != month else { return }
        if haptic { FeedbackHaptics.selection() }
        withAnimation(reduceMotion ? nil : YueJiMotion.standard) {
            month = item
            selectedDay = nil
            dayEntries = []
        }
    }

    // MARK: Month calendar

    private func monthSection(_ snapshot: YearSnapshot) -> some View {
        let calendar = self.calendar
        let layout = HeatMonthLayout(year: year, month: month, calendar: calendar)
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let weekdays = (0..<7).map { symbols[(calendar.firstWeekday - 1 + $0) % 7] }
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
        let today = Date()
        return Section {
            VStack(spacing: 8) {
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(Array(weekdays.enumerated()), id: \.offset) { _, symbol in
                        Text(symbol).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    }
                    .accessibilityHidden(true)
                    ForEach(0..<layout.leading, id: \.self) { _ in
                        Color.clear.frame(height: 38).accessibilityHidden(true)
                    }
                    ForEach(Array(1...layout.days), id: \.self) { day in
                        dayCell(day, layout: layout, snapshot: snapshot, today: today)
                    }
                }
            }
            .padding(.vertical, 6)
            // Where "Biggest day" scrolls to.
            .id("year.month")
            if let selectedDay, calendar.component(.month, from: selectedDay) == month,
               calendar.component(.year, from: selectedDay) == year {
                let cell = snapshot.days[selectedDay] ?? SpendingDay()
                LabeledContent {
                    Text(cell.cents > 0 ? amountText(cell.cents) : tr("没有消费", "No spending", "Tiada belanja"))
                        .monospacedDigit().fontWeight(.semibold)
                } label: {
                    Text(selectedDay.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: AppLanguage.localeID))))
                }
                ForEach(dayEntries) { entry in
                    NavigationLink { ExpenseDetailView(id: entry.id, embeddedInNavigation: true) } label: {
                        ExpenseRow(entry: entry)
                    }.foregroundStyle(.primary)
                }
            }
        } header: {
            DashboardSectionHeader(title: monthName(month))
        } footer: {
            if selectedDay == nil {
                Text(tr("点按某一天，查看当天的账目。", "Tap a day to see its entries.", "Ketik satu hari untuk melihat rekodnya."))
            }
        }
    }

    private func dayCell(_ day: Int, layout: HeatMonthLayout, snapshot: YearSnapshot, today: Date) -> some View {
        let date = layout.date(day: day, calendar: calendar)
        let cell = snapshot.days[date] ?? SpendingDay()
        let level = snapshot.scale.level(cell.cents)
        let upcoming = date > today
        let isToday = calendar.isDate(date, inSameDayAs: today)
        let selected = selectedDay == date
        let dayName = date.formatted(.dateTime.day().month(.wide).locale(Locale(identifier: AppLanguage.localeID)))
        let spoken: String
        if cell.cents <= 0 { spoken = tr("没有消费", "no spending", "tiada belanja") }
        else if hidden { spoken = tr("有消费", "spending", "ada belanja") }
        else { spoken = amountText(cell.cents) }
        return Button { select(date) } label: {
            Text(String(day))
                .font(.footnote.weight(isToday ? .bold : .medium)).monospacedDigit()
                .foregroundStyle(level >= 3 ? Color.white : (upcoming ? Color.secondary : Color.primary))
                .frame(maxWidth: .infinity, minHeight: 38)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(upcoming ? HeatPalette.upcoming : HeatPalette.color(level: level)))
                .overlay {
                    if selected {
                        RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(IslandTheme.accent, lineWidth: 2.5)
                    } else if isToday {
                        RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Color.primary.opacity(0.45), lineWidth: 1)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .disabled(upcoming)
        .accessibilityLabel(dayName + ", " + spoken)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// Selects a day; tapping the selected day again clears it.
    private func select(_ date: Date, toggle: Bool = true) {
        FeedbackHaptics.selection()
        let day = calendar.startOfDay(for: date)
        withAnimation(reduceMotion ? nil : YueJiMotion.standard) {
            month = calendar.component(.month, from: day)
            selectedDay = toggle && selectedDay == day ? nil : day
        }
        refreshDayEntries()
    }

    /// The selected day's entries, newest first. Every entry of the day is listed; the cell
    /// counts only personal spending.
    private func refreshDayEntries() {
        guard let selectedDay else { dayEntries = []; return }
        let calendar = self.calendar
        dayEntries = model.ledger.expenses.filter { calendar.isDate($0.date, inSameDayAs: selectedDay) }
            .sorted { $0.date == $1.date ? $0.id < $1.id : $0.date > $1.date }
    }

    // MARK: Months

    private func monthsChartSection(_ snapshot: YearSnapshot) -> some View {
        Section {
            YearMonthsChart(months: snapshot.months, selected: month, average: snapshot.trackedMonths >= 2 ? snapshot.monthlyAverage : nil,
                            hidden: hidden, calendar: calendar) { chosen in chooseMonth(chosen, haptic: false) }
                .padding(.vertical, 8)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(tr("每月消费", "Spending by month", "Belanja mengikut bulan"))
                .accessibilityValue(monthsAccessibilityValue(snapshot))
        } header: {
            DashboardSectionHeader(title: tr("每个月", "By month", "Mengikut bulan"))
        } footer: {
            Text(tr("点按柱形选择月份", "Tap a bar to choose that month", "Ketik bar untuk memilih bulan itu"))
        }
    }

    private func monthsAccessibilityValue(_ snapshot: YearSnapshot) -> String {
        guard !hidden else { return tr("金额已隐藏", "Amount hidden", "Amaun disembunyikan") }
        var parts: [String] = []
        for (index, cents) in snapshot.months.enumerated() {
            parts.append(monthName(index + 1) + " " + money(cents))
        }
        return parts.joined(separator: ", ")
    }

    // MARK: Highlights

    private func highlightsSection(_ snapshot: YearSnapshot, jump: @escaping (Date) -> Void) -> some View {
        Section {
            LabeledContent {
                Text(amountText(snapshot.monthlyAverage)).monospacedDigit()
            } label: {
                Label(tr("月均消费", "Monthly average", "Purata bulanan"), systemImage: "calendar")
            }
            if let busiest = snapshot.busiestMonth {
                LabeledContent {
                    Text(monthName(busiest) + " · " + amountText(snapshot.months[busiest - 1])).monospacedDigit()
                } label: {
                    Label(tr("花得最多的月份", "Busiest month", "Bulan paling banyak"), systemImage: "flame")
                }
            }
            if let day = snapshot.biggestDay, let cell = snapshot.days[day] {
                Button { jump(day) } label: {
                    LabeledContent {
                        Text(dateLabel(day) + " · " + amountText(cell.cents)).monospacedDigit()
                    } label: {
                        Label(tr("花得最多的一天", "Biggest day", "Hari paling banyak"), systemImage: "star")
                    }
                    .foregroundStyle(.primary)
                }
                .accessibilityHint(tr("在日历中显示这一天", "Shows this day in the calendar", "Tunjukkan hari ini dalam kalendar"))
            }
            LabeledContent {
                Text(tr("\(snapshot.noSpendDays) / \(snapshot.trackedDays) 天", "\(snapshot.noSpendDays) of \(snapshot.trackedDays) days",
                        "\(snapshot.noSpendDays) daripada \(snapshot.trackedDays) hari")).monospacedDigit()
            } label: {
                Label(tr("零消费日", "No-spend days", "Hari tanpa belanja"), systemImage: "leaf")
            }
        } header: {
            DashboardSectionHeader(title: tr("亮点", "Highlights", "Sorotan"))
        } footer: {
            Text(tr("与概览一致：扣除朋友份额、个人退款与报销，包括旅行账本。零消费日从你在月记的第一笔记录算起。",
                    "As in the Overview: after friends' shares, your refunds and claims, travel books included. No-spend days count from your first entry in YueJi.",
                    "Seperti Ringkasan: selepas bahagian rakan, pulangan dan tuntutan anda, termasuk buku perjalanan. Hari tanpa belanja dikira dari rekod pertama anda dalam YueJi."))
        }
    }

    // MARK: Categories and merchants

    private func categoriesSection(_ snapshot: YearSnapshot) -> some View {
        Section {
            ForEach(snapshot.categories) { item in
                let tint = model.ledger.categoryTint(item.category)
                HStack(spacing: 12) {
                    IslandIconTile(symbol: model.ledger.categorySymbol(item.category), color: tint, size: 36)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(categoryLabel(item.category)).font(.body.weight(.semibold))
                            Spacer(minLength: 8)
                            Text(amountText(item.cents)).font(.body.weight(.semibold)).monospacedDigit()
                        }
                        SpendingMeter(value: item.cents, total: max(snapshot.total, 1), color: tint)
                        Text(share(item.cents, of: snapshot.total)).font(.caption).monospacedDigit().foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)
            }
        } header: {
            DashboardSectionHeader(title: tr("钱花在哪里", "Where it went", "Ke mana belanja"))
        }
    }

    @ViewBuilder private func merchantsSection(_ snapshot: YearSnapshot) -> some View {
        if !snapshot.merchants.isEmpty {
            Section {
                ForEach(Array(snapshot.merchants.enumerated()), id: \.element.id) { index, merchant in
                    HStack(spacing: 12) {
                        Text(String(index + 1))
                            .font(.subheadline.weight(.bold)).monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 22)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(merchant.name).font(.body.weight(.semibold)).lineLimit(1)
                            Text(merchant.payments == 1 ? tr("1 笔付款", "1 payment", "1 bayaran") : String(merchant.payments) + tr(" 笔付款", " payments", " bayaran"))
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        Text(amountText(merchant.cents)).font(.body.weight(.semibold)).monospacedDigit()
                    }
                    .padding(.vertical, 2)
                    .accessibilityElement(children: .combine)
                }
            } header: {
                DashboardSectionHeader(title: tr("常去的商户", "Top merchants", "Peniaga utama"))
            }
        }
    }

    private func share(_ cents: Int, of total: Int) -> String {
        String(format: "%.0f%%", Double(cents) / Double(max(total, 1)) * 100)
    }
}

/// One month of the year's heatmap: a small week grid, drawn in one Canvas because the
/// year shows twelve of them. Today has an outline.
private struct HeatMiniMonth: View {
    let layout: HeatMonthLayout
    let snapshot: YearSnapshot
    let calendar: Calendar
    let today: Date
    var body: some View {
        Canvas { context, size in
            let gap: CGFloat = 2
            let cell = max(1, min((size.width - gap * 6) / 7, (size.height - gap * 5) / 6))
            for day in 1...layout.days {
                let index = layout.leading + day - 1
                let rect = CGRect(x: CGFloat(index % 7) * (cell + gap), y: CGFloat(index / 7) * (cell + gap), width: cell, height: cell)
                let date = layout.date(day: day, calendar: calendar)
                let shape = Path(roundedRect: rect, cornerRadius: cell * 0.28, style: .continuous)
                let fill = date > today ? HeatPalette.upcoming
                    : HeatPalette.color(level: snapshot.scale.level(snapshot.days[date]?.cents ?? 0))
                context.fill(shape, with: .color(fill))
                if calendar.isDate(date, inSameDayAs: today) {
                    context.stroke(shape, with: .color(.primary), lineWidth: 1)
                }
            }
        }
        .aspectRatio(7.0 / 6.0, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

/// "Less ▢▢▢▢▢ More", the heatmap's key.
private struct HeatLegend: View {
    var body: some View {
        HStack(spacing: 4) {
            Spacer(minLength: 0)
            Text(tr("少", "Less", "Kurang")).font(.caption2).foregroundStyle(.secondary)
            ForEach(0..<5, id: \.self) { level in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(HeatPalette.color(level: level))
                    .frame(width: 12, height: 12)
            }
            Text(tr("多", "More", "Lebih")).font(.caption2).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tr("颜色从浅到深表示消费从少到多", "Lighter to darker means less to more spending", "Lebih cerah ke lebih gelap bermaksud kurang ke lebih belanja"))
    }
}

/// Twelve months as bars in the app tint, as the Overview's trend draws six: the chosen
/// month solid with its amount above, the rest lighter, and a dashed line at the monthly
/// average once two months are counted. Sliding a finger across shows each month's value
/// with a light tick; letting go (or tapping) chooses that month.
private struct YearMonthsChart: View {
    let months: [Int]
    let selected: Int
    let average: Int?
    var hidden = false
    let calendar: Calendar
    var onSelect: (Int) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The month under the finger while scrubbing; it stands in for the chosen month.
    @GestureState private var scrubbed: Int?

    private struct Bar: Identifiable {
        let month: Int
        let cents: Int
        var id: Int { month }
    }
    private var bars: [Bar] { months.enumerated().map { Bar(month: $0.offset + 1, cents: $0.element) } }
    private func label(_ month: Int) -> String { calendar.shortStandaloneMonthSymbols[month - 1] }
    /// The axis shows the one-letter names; the bars keep the unique short ones.
    private func axisLabel(_ name: String) -> String {
        guard let index = calendar.shortStandaloneMonthSymbols.firstIndex(of: name) else { return name }
        return calendar.veryShortStandaloneMonthSymbols[index]
    }

    var body: some View {
        let emphasized = scrubbed ?? selected
        Chart {
            ForEach(bars) { bar in
                BarMark(x: .value("Month", label(bar.month)),
                        y: .value("Spent", Double(bar.cents) / 100),
                        width: .ratio(0.62))
                    .cornerRadius(4)
                    .foregroundStyle(bar.month == emphasized ? IslandTheme.accent : IslandTheme.accent.opacity(0.28))
                    .annotation(position: .top, spacing: 4) {
                        if bar.month == emphasized && !hidden && bar.cents > 0 {
                            Text(money(bar.cents))
                                .font(.caption2.weight(.semibold)).monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
            }
            if let average, average > 0 {
                RuleMark(y: .value("Average", Double(average) / 100))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(Color.secondary)
                    .annotation(position: .top, alignment: .leading, spacing: 2) {
                        Text(hidden ? tr("月均", "Avg", "Purata") : tr("月均 ", "Avg ", "Purata ") + money(average))
                            .font(.caption2.weight(.medium)).monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .chartXAxis {
            AxisMarks { value in
                AxisValueLabel {
                    if let name = value.as(String.self) { Text(axisLabel(name)) }
                }
            }
        }
        .chartYAxis(hidden ? .hidden : .automatic)
        .chartOverlay { proxy in
            GeometryReader { geometry in
                // Simultaneous, so a vertical drag that starts on the chart still scrolls the page.
                Rectangle().fill(Color.clear).contentShape(Rectangle())
                    .simultaneousGesture(DragGesture(minimumDistance: 0)
                        .updating($scrubbed) { value, state, _ in
                            state = isChartScrub(value.translation) ? month(at: value.location, proxy: proxy, geometry: geometry) : nil
                        }
                        .onEnded { value in
                            guard isChartScrub(value.translation),
                                  let chosen = month(at: value.location, proxy: proxy, geometry: geometry) else { return }
                            onSelect(chosen)
                        })
                    .accessibilityHidden(true)
            }
        }
        .frame(height: 190)
        .onChange(of: scrubbed) { _, value in if value != nil { FeedbackHaptics.selection() } }
        .animation(reduceMotion ? nil : YueJiMotion.content, value: selected)
        .animation(reduceMotion ? nil : .smooth(duration: 0.16), value: scrubbed)
        .animation(reduceMotion ? nil : YueJiMotion.content, value: months)
    }
    /// The month of the bar under a point of the chart.
    private func month(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) -> Int? {
        guard let plot = proxy.plotFrame else { return nil }
        let x = location.x - geometry[plot].origin.x
        guard let name: String = proxy.value(atX: x) else { return nil }
        return bars.first { label($0.month) == name }?.month
    }
}

// MARK: - Unusual spending

/// The Overview's "Worth a look" card: what is different about the month's spending
/// compared with the months before it, at most a few lines. Hidden when there is nothing
/// unusual. Each line opens its category or purchase; swiping hides it for the month.
struct UnusualSpendingSection: View {
    @Environment(\.locale) private var uiLocale
    @AppStorage(SpendingAlerts.dismissedKey) private var dismissed = ""
    let alerts: [SpendingAlert]
    let month: Date
    var hidden = false

    private var key: String { monthKey(month) }
    private var visible: [SpendingAlert] {
        let hiddenIDs = SpendingAlerts.dismissed(dismissed, month: key)
        return alerts.filter { !hiddenIDs.contains($0.id) }
    }

    var body: some View {
        let _ = uiLocale.identifier
        if !visible.isEmpty {
            Section {
                ForEach(visible) { alert in
                    row(alert)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(tr("隐藏", "Hide", "Sembunyi"), systemImage: "eye.slash") { hide(alert) }
                                .tint(.gray)
                        }
                        .contextMenu {
                            Button(tr("本月不再显示", "Hide for this month", "Sembunyikan bulan ini"), systemImage: "eye.slash") { hide(alert) }
                        }
                        .accessibilityAction(named: Text(tr("本月不再显示", "Hide for this month", "Sembunyikan bulan ini"))) { hide(alert) }
                }
            } header: {
                DashboardSectionHeader(title: tr("值得留意", "Worth a look", "Perlu perhatian"))
            } footer: {
                Text(tr("与前 3 个月同期相比；不含旅行账本。左滑可隐藏。",
                        "Compared with the same days of the last 3 months; travel books aren't included. Swipe to hide.",
                        "Berbanding hari yang sama dalam 3 bulan lalu; buku perjalanan tidak termasuk. Leret untuk sembunyi."))
            }
        }
    }

    @ViewBuilder private func row(_ alert: SpendingAlert) -> some View {
        switch alert.kind {
        case .purchase:
            if let id = alert.expenseID {
                NavigationLink { ExpenseDetailView(id: id, embeddedInNavigation: true) } label: { label(alert) }
            } else { label(alert) }
        case .category, .newCategory:
            NavigationLink { CategoryPaymentsView(category: alert.category, month: month) } label: { label(alert) }
        case .overall:
            NavigationLink { SpendingComparisonView(month: month) } label: { label(alert) }
        }
    }

    private func label(_ alert: SpendingAlert) -> some View {
        AlertRowLabel(alert: alert, hidden: hidden)
    }

    private func hide(_ alert: SpendingAlert) {
        FeedbackHaptics.selection()
        dismissed = SpendingAlerts.dismissing(alert.id, month: key, in: dismissed)
    }
}

private struct AlertRowLabel: View {
    @EnvironmentObject private var model: LedgerModel
    @Environment(\.colorScheme) private var scheme
    let alert: SpendingAlert
    let hidden: Bool
    private var symbol: String {
        alert.kind == .overall ? "chart.line.uptrend.xyaxis" : model.ledger.categorySymbol(alert.category)
    }
    private var tint: Color {
        alert.kind == .overall ? IslandPalette.pumpkin : model.ledger.categoryTint(alert.category)
    }
    var body: some View {
        HStack(spacing: 12) {
            IslandIconTile(symbol: symbol, color: tint, size: 36)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(alert.title(hidden: hidden)).font(.body.weight(.semibold)).lineLimit(2)
                Text(alert.detail(hidden: hidden)).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 8)
            Text(alert.badge)
                .font(.footnote.weight(.semibold)).monospacedDigit()
                .foregroundStyle(IslandPalette.pumpkin)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(IslandPalette.pumpkin.opacity(scheme == .dark ? 0.22 : 0.12), in: Capsule())
                .accessibilityHidden(true)
        }
        .foregroundStyle(.primary)
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
