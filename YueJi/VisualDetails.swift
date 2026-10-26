import SwiftUI

/// Small visual and motion details shared across screens: the gold of the icon's crescent,
/// the Overview's month dial, a counting amount, a checkmark that draws itself, the goal
/// sweep, one-off symbol effects, category choices with their icons, and the quick-add bar
/// above the tab bar. Everything that moves honours Reduce Motion and the Animations setting.

// MARK: - Gold

/// The gold of the icon's crescent (月), from `generate_icon.py`.
enum MoonGold {
    static let light = Color(red: 1, green: 232 / 255, blue: 170 / 255)
    static let deep = Color(red: 238 / 255, green: 168 / 255, blue: 74 / 255)
    static let glow = Color(red: 1, green: 200 / 255, blue: 110 / 255)
    static let gradient = LinearGradient(colors: [light, deep], startPoint: .top, endPoint: .bottom)
}

// MARK: - The month dial

/// A month's budget against the month itself: how much of the budget is used, and how much
/// of the month has passed. The Overview's month dial draws the two side by side.
struct BudgetPace: Equatable {
    let spent: Int
    let budget: Int
    let days: Int
    /// Days passed, today included: none for a month still to come, all once it has ended.
    let daysPassed: Int
    /// Whether today is in the month.
    let ongoing: Bool

    init(spent: Int, budget: Int, month: Date, now: Date = Date(), calendar: Calendar = InsightCalendar.make()) {
        self.spent = spent
        self.budget = budget
        days = max(1, calendar.range(of: .day, in: .month, for: month)?.count ?? 30)
        guard let interval = calendar.dateInterval(of: .month, for: month) else {
            daysPassed = 0; ongoing = false; return
        }
        ongoing = now >= interval.start && now < interval.end
        if now >= interval.end {
            daysPassed = days
        } else if ongoing {
            let before = calendar.dateComponents([.day], from: interval.start, to: calendar.startOfDay(for: now)).day ?? 0
            daysPassed = min(days, max(1, before + 1))
        } else {
            daysPassed = 0
        }
    }

    /// Budget used: from 0, above 1 when over budget.
    var used: Double { budget > 0 ? Double(max(0, spent)) / Double(budget) : 0 }
    /// The month passed by the end of today, 0–1.
    var elapsed: Double { Double(daysPassed) / Double(days) }
    /// Spending at least ten points ahead of the month, from the 5th, while it runs and
    /// before the budget is used up (the budget's own status says so then).
    var ahead: Bool { ongoing && daysPassed >= 5 && spent < budget && used > elapsed + 0.1 }
    /// How far round the gold thread runs: from the 1st to today's bead, all the way once
    /// the month has ended.
    var thread: Double {
        if ongoing { return Double(daysPassed - 1) / Double(days) }
        return daysPassed >= days ? 1 : 0
    }
}

/// The month as a dial, after the opening's ring of days: a bead for each day around the
/// outside (days gone brighter, today in gold) with a gold thread from the 1st to today,
/// and inside it the budget used as an arc. When the arc runs ahead of the thread, the
/// money is going faster than the month. Its text reads as part of the row beside it.
struct MonthBudgetDial<Center: View>: View {
    let pace: BudgetPace
    let tint: Color
    var size: CGFloat
    let center: Center
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shownUsed = 0.0
    @State private var shownThread = 0.0
    @State private var appeared = false

    init(pace: BudgetPace, tint: Color, size: CGFloat = 132, @ViewBuilder center: () -> Center) {
        self.pace = pace
        self.tint = tint
        self.size = size
        self.center = center()
    }

    private var beadRadius: CGFloat { size / 2 - 4 }
    private var ringRadius: CGFloat { size / 2 - 18 }
    private let lineWidth: CGFloat = 9

    var body: some View {
        ZStack {
            beads
            Circle()
                .trim(from: 0, to: shownThread)
                .stroke(MoonGold.gradient, style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
                .frame(width: beadRadius * 2, height: beadRadius * 2)
                .rotationEffect(.degrees(-90))
            Circle()
                .stroke(tint.opacity(0.16), lineWidth: lineWidth)
                .frame(width: ringRadius * 2, height: ringRadius * 2)
            Circle()
                .trim(from: 0, to: min(shownUsed, 1))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .frame(width: ringRadius * 2, height: ringRadius * 2)
                .rotationEffect(.degrees(-90))
            center
                .frame(width: (ringRadius - lineWidth) * 2)
        }
        .frame(width: size, height: size)
        .animation(reduceMotion ? nil : YueJiMotion.tone, value: tint)
        .task(id: pace) {
            let used = pace.used, thread = pace.thread
            guard !reduceMotion, ElegantMotion.enabled else {
                shownUsed = used; shownThread = thread
                return
            }
            // A new dial draws in from empty; later changes move from where it is.
            if !appeared {
                appeared = true
                do { try await Task.sleep(for: .milliseconds(16)) } catch { return }
            }
            withAnimation(YueJiMotion.meter) { shownUsed = used; shownThread = thread }
        }
    }

    /// The month's days, drawn in one Canvas.
    private var beads: some View {
        let pace = self.pace
        let radius = beadRadius
        return Canvas { context, canvas in
            let centre = CGPoint(x: canvas.width / 2, y: canvas.height / 2)
            for day in 1...pace.days {
                let angle = (Double(day - 1) / Double(pace.days) * 360 - 90) * .pi / 180
                let point = CGPoint(x: centre.x + radius * CGFloat(cos(angle)), y: centre.y + radius * CGFloat(sin(angle)))
                let isToday = pace.ongoing && day == pace.daysPassed
                let width: CGFloat = isToday ? 6.5 : 3.2
                let bead = Path(ellipseIn: CGRect(x: point.x - width / 2, y: point.y - width / 2, width: width, height: width))
                let colour = isToday ? MoonGold.deep : Color.primary.opacity(day <= pace.daysPassed ? 0.42 : 0.14)
                context.fill(bead, with: .color(colour))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - Counting amounts

/// An amount that counts up through the values in between, so every frame shows a real
/// figure: the Overview's total as the app opens.
struct CountingMoney: View {
    let cents: Double
    var body: some View {
        Text(verbatim: "").modifier(CountingMoneyText(cents: cents))
    }
}

private struct CountingMoneyText: ViewModifier, Animatable {
    var cents: Double
    var animatableData: Double {
        get { cents }
        set { cents = newValue }
    }
    func body(content: Content) -> some View {
        Text(money(Int(cents.rounded()))).monospacedDigit()
    }
}

/// The count-up plays once a launch, as the opening hands over; not on every return.
@MainActor enum OverviewCountUp {
    static var played = false
}

// MARK: - A checkmark that draws itself

/// A checkmark drawn stroke by stroke as it appears, for "Saved" and goals reached.
struct DrawnCheckmark: View {
    var lineWidth: CGFloat = 2
    var color: Color = .white
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: CGFloat = 0
    var body: some View {
        CheckmarkShape()
            .trim(from: 0, to: progress)
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            .onAppear {
                guard progress == 0 else { return }
                guard !reduceMotion, ElegantMotion.enabled else { progress = 1; return }
                withAnimation(.easeOut(duration: 0.32).delay(0.14)) { progress = 1 }
            }
            .accessibilityHidden(true)
    }
}

private struct CheckmarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.16, y: rect.minY + rect.height * 0.54))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.41, y: rect.minY + rect.height * 0.78))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.86, y: rect.minY + rect.height * 0.25))
        return path
    }
}

// MARK: - The goal sweep

/// A short arc that runs once around a ring and is gone: a goal reached. Each whole step of
/// `progress` (0 to 1, 1 to 2, …) is one sweep from twelve o'clock all the way round, so
/// adding 1 with an animation plays it again; at whole numbers nothing is drawn. Draw it
/// rotated by -90°, as the rings are.
struct RingSweep: Shape {
    var progress: CGFloat
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }
    func path(in rect: CGRect) -> Path {
        let step = progress - progress.rounded(.down)
        let head = min(1, step * 1.25)
        let tail = max(0, step * 1.25 - 0.25)
        var path = Path()
        guard head > tail else { return path }
        path.addArc(center: CGPoint(x: rect.midX, y: rect.midY), radius: min(rect.width, rect.height) / 2,
                    startAngle: .degrees(Double(tail) * 360), endAngle: .degrees(Double(head) * 360), clockwise: false)
        return path
    }
}

// MARK: - One-off symbol effects

/// One wiggle of the symbols inside when `trigger` changes: a state that wants a glance,
/// such as a budget passing 80% or 100%. A bounce before iOS 18.
struct AttentionWiggle<Trigger: Equatable>: ViewModifier {
    let trigger: Trigger
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ViewBuilder func body(content: Content) -> some View {
        if reduceMotion || !ElegantMotion.enabled {
            content
        } else if #available(iOS 18.0, *) {
            content.symbolEffect(.wiggle, options: .nonRepeating, value: trigger)
        } else {
            content.symbolEffect(.bounce, options: .nonRepeating, value: trigger)
        }
    }
}

/// One bounce of the symbols inside when `trigger` changes.
struct AttentionBounce<Trigger: Equatable>: ViewModifier {
    let trigger: Trigger
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ViewBuilder func body(content: Content) -> some View {
        if reduceMotion || !ElegantMotion.enabled {
            content
        } else {
            content.symbolEffect(.bounce, options: .nonRepeating, value: trigger)
        }
    }
}

// MARK: - Category choices

/// A category as a choice in a picker: its symbol in the category's colour, then its name.
/// Menus show the symbol; navigation pickers show it tinted. VoiceOver reads the name only.
struct CategoryChoiceLabel: View {
    let name: String
    let symbol: String
    let tint: Color
    var body: some View {
        Label {
            Text(categoryLabel(name))
        } icon: {
            Image(systemName: symbol).foregroundStyle(tint).accessibilityHidden(true)
        }
    }
}

extension Ledger {
    func categoryChoice(_ name: String) -> CategoryChoiceLabel {
        CategoryChoiceLabel(name: name, symbol: categorySymbol(name), tint: categoryTint(name))
    }
}

// MARK: - Today's spending in the overview header

struct TodaySpendingRow: View {
    @Environment(\.locale) private var uiLocale
    @EnvironmentObject private var model: LedgerModel
    /// The Overview's eye hides this amount too.
    @AppStorage("hideOverviewAmounts") private var hidden = false
    /// Today's personal spending, counted as the Overview counts the month.
    private var today: Int {
        let calendar = Calendar.current
        return model.overview(in: Date()).entries
            .filter { calendar.isDateInToday($0.date) }
            .reduce(0) { $0 + $1.personalSpending }
    }
    var body: some View {
        let _ = uiLocale.identifier
        let spent = today
            HStack(spacing: 8) {
                Image(systemName: "sun.horizon").foregroundStyle(IslandTheme.accent)
                Text(tr("今日消费", "Spent today", "Belanja hari ini")).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Group {
                    if hidden { Text(DashboardView.maskedAmount) } else { AnimatedMoney(cents: spent) }
                }
                .fontWeight(.semibold)
                .lineLimit(1).minimumScaleFactor(0.7)
            }
            .font(.subheadline)
            .padding(14)
            .background(IslandTheme.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tr("今日消费", "Spent today", "Belanja hari ini"))
        .accessibilityValue(hidden ? tr("今天的金额已隐藏", "Today's amount hidden", "Amaun hari ini disembunyikan")
            : tr("今天 ", "Today ", "Hari ini ") + money(spent))
        .accessibilityIdentifier("overview.todaySpending")
    }
}
