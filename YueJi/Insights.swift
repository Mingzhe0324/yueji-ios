import Foundation
import UserNotifications

/// The calendar the insights count days and months with: Gregorian in the device's time
/// zone, as the Overview's monthly totals are.
enum InsightCalendar {
    static func make(timeZone: TimeZone = .current) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }
}

// MARK: - Year in review

/// One day's personal spending: a cell of the year's calendar heatmap.
struct SpendingDay: Equatable {
    var cents = 0
    /// Entries that day with personal spending.
    var entries = 0
}

struct YearCategoryTotal: Identifiable, Equatable {
    let category: String
    let cents: Int
    var id: String { category }
}

struct YearMerchantTotal: Identifiable, Equatable {
    /// The merchant's key: names grouped ignoring case and spacing.
    let id: String
    let name: String
    let cents: Int
    let payments: Int
}

/// The heatmap's shades: no spending, then four steps from the lightest days to the
/// heaviest. With eight or more days of spending the steps are the year's quartiles, so a
/// few very large days don't wash the rest out; with fewer, quarters of the largest day.
/// The largest day is always the darkest.
struct SpendingHeatScale: Equatable {
    /// Upper bounds of steps 1, 2 and 3 in cents; anything above the last is step 4.
    let bounds: [Int]
    let largest: Int
    init(amounts: [Int]) {
        let spent = amounts.filter { $0 > 0 }.sorted()
        largest = spent.last ?? 0
        guard !spent.isEmpty else { bounds = []; return }
        if spent.count < 8 {
            let top = spent[spent.count - 1]
            bounds = [top / 4, top / 2, top * 3 / 4]
        } else {
            let last = Double(spent.count - 1)
            let quarter: Int = spent[Int((last * 0.25).rounded())]
            let half: Int = spent[Int((last * 0.5).rounded())]
            let threeQuarters: Int = spent[Int((last * 0.75).rounded())]
            bounds = [quarter, half, threeQuarters]
        }
    }
    /// 0 for no spending, then 1 (lightest) to 4 (heaviest).
    func level(_ cents: Int) -> Int {
        guard cents > 0 else { return 0 }
        if cents >= largest { return 4 }
        return min(4, 1 + bounds.filter { cents > $0 }.count)
    }
}

/// A year of personal spending, counted exactly as the Overview counts a month: each
/// expense's personal spending (after friends' shares, refunds and claims) on its own date,
/// with items spread over their categories. Travel books are included, as in the Overview.
struct YearSnapshot: Equatable {
    let year: Int
    /// Personal spending per month, January first.
    var months: [Int] = Array(repeating: 0, count: 12)
    /// Days with spending, keyed by the start of the day.
    var days: [Date: SpendingDay] = [:]
    /// Every category with spending, largest first.
    var categories: [YearCategoryTotal] = []
    /// The five merchants that cost the most, largest first.
    var merchants: [YearMerchantTotal] = []
    var total = 0
    var entries = 0
    /// The previous year up to the same date (all of it, for a past year). Nil when YueJi
    /// has no records from the start of that period, so a part-year never looks like a jump.
    var previousSamePeriod: Int?
    /// The first day counted: the year's start, or the first entry if that came later.
    var trackedFrom: Date?
    /// Days from `trackedFrom` to today (to the year's end for a past year).
    var trackedDays = 0
    /// Calendar months those days touch, for the monthly average.
    var trackedMonths = 0
    /// The year of the earliest entry, the first the year picker offers.
    var earliestYear: Int
    var scale = SpendingHeatScale(amounts: [])

    var daysWithSpending: Int { days.values.filter { $0.cents > 0 }.count }
    var noSpendDays: Int { max(0, trackedDays - daysWithSpending) }
    var monthlyAverage: Int {
        guard trackedMonths > 0 else { return 0 }
        let average = Double(total) / Double(trackedMonths)
        return Int(average.rounded())
    }
    /// The month (1–12) with the most spending; the earlier one on a tie.
    var busiestMonth: Int? {
        var best: Int?
        var most = 0
        for (index, cents) in months.enumerated() where cents > most {
            best = index + 1
            most = cents
        }
        return best
    }
    /// The day with the most spending; the earlier one on a tie.
    var biggestDay: Date? {
        var best: Date?
        var most = 0
        for (day, cell) in days where cell.cents > 0 {
            if cell.cents > most {
                best = day
                most = cell.cents
            } else if cell.cents == most, let current = best, day < current {
                best = day
            }
        }
        return best
    }
    /// Change on the same period of the previous year, as a fraction (0.12 is 12% more).
    var change: Double? {
        guard let previous = previousSamePeriod, previous > 0 else { return nil }
        return Double(total - previous) / Double(previous)
    }

    init(year: Int, earliestYear: Int) {
        self.year = year
        self.earliestYear = earliestYear
    }

    init(ledger: Ledger, year: Int, now: Date = Date(), calendar: Calendar = InsightCalendar.make()) {
        self.year = year
        let firstEntry: Date? = ledger.expenses.map(\.date).min()
        if let firstEntry {
            earliestYear = calendar.component(.year, from: firstEntry)
        } else {
            earliestYear = calendar.component(.year, from: now)
        }
        guard let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
              let end = calendar.date(byAdding: .year, value: 1, to: start) else { return }
        var categoryTotals: [String: Int] = [:]
        var merchantTotals: [String: (name: String, cents: Int, payments: Int)] = [:]
        for entry in ledger.expenses where entry.date >= start && entry.date < end {
            let personal = entry.personalSpending
            guard personal > 0 else { continue }
            months[calendar.component(.month, from: entry.date) - 1] += personal
            total += personal
            entries += 1
            let day = calendar.startOfDay(for: entry.date)
            var cell = days[day] ?? SpendingDay()
            cell.cents += personal
            cell.entries += 1
            days[day] = cell
            for (category, cents) in entry.categoryDistribution(total: personal) {
                categoryTotals[category, default: 0] += cents
            }
            let key = entry.merchantKey
            var merchant = merchantTotals[key] ?? (name: entry.displayName, cents: 0, payments: 0)
            merchant.cents += personal
            merchant.payments += 1
            merchantTotals[key] = merchant
        }
        var categoryList: [YearCategoryTotal] = []
        for (category, cents) in categoryTotals where cents > 0 {
            categoryList.append(YearCategoryTotal(category: category, cents: cents))
        }
        categoryList.sort { left, right in
            if left.cents != right.cents { return left.cents > right.cents }
            return left.category < right.category
        }
        categories = categoryList
        var merchantList: [YearMerchantTotal] = []
        for (key, merchant) in merchantTotals {
            merchantList.append(YearMerchantTotal(id: key, name: merchant.name, cents: merchant.cents, payments: merchant.payments))
        }
        merchantList.sort { left, right in
            if left.cents != right.cents { return left.cents > right.cents }
            return left.name < right.name
        }
        merchants = Array(merchantList.prefix(5))
        var dayAmounts: [Int] = []
        for cell in days.values { dayAmounts.append(cell.cents) }
        scale = SpendingHeatScale(amounts: dayAmounts)

        // The year so far: up to the end of today, or all of it once it has ended.
        guard let earliest = firstEntry, start <= now else { return }
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        let cutoff = min(end, tomorrow)
        let from = max(start, calendar.startOfDay(for: earliest))
        if from < cutoff {
            trackedFrom = from
            trackedDays = calendar.dateComponents([.day], from: from, to: cutoff).day ?? 0
            let lastDay = calendar.date(byAdding: .day, value: -1, to: cutoff) ?? from
            trackedMonths = calendar.component(.month, from: lastDay) - calendar.component(.month, from: from) + 1
        }
        if let previousStart = calendar.date(byAdding: .year, value: -1, to: start),
           let previousEnd = calendar.date(byAdding: .year, value: -1, to: cutoff),
           let grace = calendar.date(byAdding: .day, value: 31, to: previousStart), earliest < grace {
            var previousTotal = 0
            for entry in ledger.expenses where entry.date >= previousStart && entry.date < previousEnd {
                previousTotal += max(0, entry.personalSpending)
            }
            previousSamePeriod = previousTotal
        }
    }
}

extension LedgerProjectionWorker {
    func year(ledger: Ledger, year: Int, now: Date = Date()) throws -> YearSnapshot {
        try Task.checkCancellation()
        let result = YearSnapshot(ledger: ledger, year: year, now: now)
        try Task.checkCancellation()
        return result
    }
    func spendingAlerts(ledger: Ledger, month: Date, now: Date = Date()) throws -> [SpendingAlert] {
        try Task.checkCancellation()
        let result = SpendingAlerts.make(ledger: ledger, month: month, now: now)
        try Task.checkCancellation()
        return result
    }
}

// MARK: - Unusual spending

/// Something different about a month's spending, found by `SpendingAlerts`.
struct SpendingAlert: Identifiable, Equatable {
    enum Kind: Equatable {
        /// All spending, ahead of its usual pace.
        case overall
        /// One category, ahead of its usual pace.
        case category
        /// A category with nothing in the months compared.
        case newCategory
        /// One purchase far above the category's typical purchase.
        case purchase
    }
    let kind: Kind
    /// The category; empty for `overall`.
    var category = ""
    /// Spent in the period, or the purchase's personal amount.
    let cents: Int
    /// The usual amount by this point, or the category's typical purchase.
    let usual: Int
    /// The day of the month compared up to while the month is under way; nil for a whole month.
    var throughDay: Int? = nil
    var expenseID: String? = nil
    var merchant: String? = nil

    var id: String {
        switch kind {
        case .overall: return "overall"
        case .category, .newCategory: return "category:" + category
        case .purchase: return "purchase:" + (expenseID ?? "")
        }
    }
    /// How far above usual, in cents.
    var extra: Int { cents - usual }
    /// Percent above usual, rounded.
    var rise: Int { usual > 0 ? Int((Double(cents - usual) / Double(usual) * 100).rounded()) : 0 }
    /// How many typical purchases this one is.
    var multiple: Double { usual > 0 ? Double(cents) / Double(usual) : 0 }
}

/// Compares a month with the three before it, like for like: up to the same day while the
/// month is under way, whole months once it has ended. Same spending rule as the Overview
/// (personal spending; items by category), leaving out travel books, which have budgets of
/// their own. Needs at least two of those months with entries, so a new ledger stays quiet;
/// the first few days of a month only report single purchases.
enum SpendingAlerts {
    static let monthsCompared = 3
    static let minimumMonthsWithEntries = 2
    /// Paces are compared from this day of the month.
    static let earliestDay = 5
    /// A category is up at 40% and RM 50 over its usual.
    static let categoryRise = 0.4
    static let categoryExtra = 5_000
    /// All spending is up at 25% and RM 100 over its usual.
    static let overallRise = 0.25
    static let overallExtra = 10_000
    /// A category with nothing in the months compared: from RM 100.
    static let newCategoryMinimum = 10_000
    /// A purchase of RM 100 or more and three times the category's typical purchase, which
    /// takes three earlier purchases to judge. Scheduled and renewal payments don't count.
    static let purchaseMinimum = 10_000
    static let purchaseMultiple = 3.0
    static let purchaseHistory = 3
    /// At most this many besides the overall pace.
    static let limit = 3
    /// Alerts the person hid, as "yyyy-MM|id" lines.
    static let dismissedKey = "dismissedSpendingAlerts"

    static func make(ledger: Ledger, month: Date, now: Date = Date(), calendar: Calendar = InsightCalendar.make()) -> [SpendingAlert] {
        guard let current = calendar.dateInterval(of: .month, for: month), current.start <= now else { return [] }
        let ongoing = now < current.end
        let today = calendar.startOfDay(for: now)
        // Days so far, today included, while the month is under way.
        let throughDay: Int? = ongoing ? (calendar.dateComponents([.day], from: current.start, to: today).day ?? 0) + 1 : nil
        let periodEnd = ongoing ? (calendar.date(byAdding: .day, value: 1, to: today) ?? current.end) : current.end
        var previous: [(full: DateInterval, compared: Date)] = []
        for offset in 1...monthsCompared {
            guard let start = calendar.date(byAdding: .month, value: -offset, to: current.start),
                  let full = calendar.dateInterval(of: .month, for: start) else { continue }
            var compared = full.end
            if let throughDay, let cut = calendar.date(byAdding: .day, value: throughDay, to: full.start), cut < full.end {
                compared = cut
            }
            previous.append((full: full, compared: compared))
        }
        guard let earliest = previous.last?.full.start else { return [] }

        var tracked = Set<Int>()
        var spent = 0, usualSum = 0
        var spentByCategory: [String: Int] = [:], usualByCategory: [String: Int] = [:]
        var history: [String: [Int]] = [:]
        var candidates: [Expense] = []
        for entry in ledger.expenses where entry.tripID == nil && entry.date >= earliest && entry.date < periodEnd {
            let personal = entry.personalSpending
            let oneOff = entry.recurringKey == nil && entry.renewalOf == nil
            if entry.date >= current.start {
                guard personal > 0 else { continue }
                spent += personal
                for (category, cents) in entry.categoryDistribution(total: personal) { spentByCategory[category, default: 0] += cents }
                if oneOff { candidates.append(entry) }
                continue
            }
            guard let index = previous.firstIndex(where: { entry.date >= $0.full.start && entry.date < $0.full.end }) else { continue }
            // Any entry shows the month was being kept.
            tracked.insert(index)
            guard personal > 0 else { continue }
            if entry.date < previous[index].compared {
                usualSum += personal
                for (category, cents) in entry.categoryDistribution(total: personal) { usualByCategory[category, default: 0] += cents }
            }
            if oneOff { history[entry.category, default: []].append(personal) }
        }
        let monthsKept = tracked.count
        guard monthsKept >= minimumMonthsWithEntries else { return [] }

        var overall: [SpendingAlert] = []
        var others: [SpendingAlert] = []
        let paceDay: Int = throughDay ?? earliestDay
        if paceDay >= earliestDay {
            let usualSpent = average(usualSum, over: monthsKept)
            if usualSpent > 0, isUp(spent, over: usualSpent, rise: overallRise, extra: overallExtra) {
                overall.append(SpendingAlert(kind: .overall, cents: spent, usual: usualSpent, throughDay: throughDay))
            }
            for (category, cents) in spentByCategory {
                let usualCents = average(usualByCategory[category] ?? 0, over: monthsKept)
                if usualCents == 0 {
                    if cents >= newCategoryMinimum {
                        others.append(SpendingAlert(kind: .newCategory, category: category, cents: cents, usual: 0, throughDay: throughDay))
                    }
                } else if isUp(cents, over: usualCents, rise: categoryRise, extra: categoryExtra) {
                    others.append(SpendingAlert(kind: .category, category: category, cents: cents, usual: usualCents, throughDay: throughDay))
                }
            }
        }
        var purchases: [SpendingAlert] = []
        for entry in candidates {
            let earlier = history[entry.category] ?? []
            guard earlier.count >= purchaseHistory else { continue }
            let typical = median(earlier)
            let personal = entry.personalSpending
            guard typical > 0, personal >= purchaseMinimum, Double(personal) >= Double(typical) * purchaseMultiple else { continue }
            purchases.append(SpendingAlert(kind: .purchase, category: entry.category, cents: personal, usual: typical,
                                           throughDay: throughDay, expenseID: entry.id, merchant: entry.displayName))
        }
        // A large purchase explains its category: show the purchase rather than both.
        var explained = Set<String>()
        for purchase in purchases { explained.insert(purchase.category) }
        var ranked: [SpendingAlert] = []
        for alert in others where !explained.contains(alert.category) { ranked.append(alert) }
        ranked.append(contentsOf: purchases)
        ranked.sort { left, right in
            if left.extra != right.extra { return left.extra > right.extra }
            return left.id < right.id
        }
        return overall + Array(ranked.prefix(limit))
    }

    /// A monthly average over the months kept, rounded to the sen.
    private static func average(_ sum: Int, over months: Int) -> Int {
        guard months > 0 else { return 0 }
        let value = Double(sum) / Double(months)
        return Int(value.rounded())
    }

    /// Whether an amount is at least `rise` (a fraction) and `extra` (cents) above usual.
    private static func isUp(_ cents: Int, over usual: Int, rise: Double, extra: Int) -> Bool {
        let threshold = Double(usual) * (1 + rise)
        return Double(cents) >= threshold && cents - usual >= extra
    }

    static func median(_ values: [Int]) -> Int {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        let middle = sorted.count / 2
        if sorted.count % 2 == 1 { return sorted[middle] }
        return (sorted[middle - 1] + sorted[middle]) / 2
    }

    /// The alerts the person hid for a month, from the stored lines.
    static func dismissed(_ stored: String, month: String) -> Set<String> {
        var result = Set<String>()
        for line in stored.split(separator: "\n") {
            let parts = line.split(separator: "|", maxSplits: 1)
            if parts.count == 2 && String(parts[0]) == month { result.insert(String(parts[1])) }
        }
        return result
    }
    /// The stored lines with one more alert hidden; months older than the last few are dropped.
    static func dismissing(_ id: String, month: String, in stored: String) -> String {
        let oldest = monthKey(Date().addingTimeInterval(-100 * 24 * 3600))
        var lines: [String] = []
        for line in stored.split(separator: "\n") {
            let text = String(line)
            guard let prefix = text.split(separator: "|", maxSplits: 1).first, String(prefix) >= oldest else { continue }
            lines.append(text)
        }
        let added = month + "|" + id
        if !lines.contains(added) { lines.append(added) }
        return lines.joined(separator: "\n")
    }
}

extension SpendingAlert {
    /// "Spending is up 35%", "Food is up 58%", "New spending on Food", "RM 450 at IKEA".
    func title(hidden: Bool = false) -> String {
        let name = categoryLabel(category)
        switch kind {
        case .overall:
            return tr("本月消费比平时多 \(rise)%", "Spending is up \(rise)%", "Belanja naik \(rise)%")
        case .category:
            return tr("\(name)比平时多 \(rise)%", "\(name) is up \(rise)%", "\(name) naik \(rise)%")
        case .newCategory:
            return tr("新的支出：\(name)", "New spending on \(name)", "Belanja baharu: \(name)")
        case .purchase:
            let place = merchant ?? name
            if hidden { return tr("\(place) 的一笔大额消费", "A large purchase at \(place)", "Belian besar di \(place)") }
            return tr("在 \(place) 消费 \(money(cents))", "\(money(cents)) at \(place)", "\(money(cents)) di \(place)")
        }
    }
    /// What it is compared with, in a line.
    func detail(hidden: Bool = false) -> String {
        let name = categoryLabel(category)
        switch kind {
        case .overall, .category:
            if hidden {
                if let day = throughDay {
                    return tr("与前几个月的 1–\(day) 日相比", "Compared with days 1–\(day) of recent months", "Berbanding hari 1–\(day) bulan-bulan lalu")
                }
                return tr("与前几个月相比", "Compared with recent months", "Berbanding bulan-bulan lalu")
            }
            if let day = throughDay {
                return tr("截至 \(day) 日 \(money(cents))；平时约 \(money(usual))",
                          "\(money(cents)) by day \(day); usually about \(money(usual))",
                          "\(money(cents)) hingga hari ke-\(day); biasanya kira-kira \(money(usual))")
            }
            return tr("本月 \(money(cents))；平时约 \(money(usual))",
                      "\(money(cents)) this month; usually about \(money(usual))",
                      "\(money(cents)) bulan ini; biasanya kira-kira \(money(usual))")
        case .newCategory:
            let months = SpendingAlerts.monthsCompared
            if hidden {
                return tr("前 \(months) 个月没有这类消费", "None in the previous \(months) months", "Tiada dalam \(months) bulan sebelumnya")
            }
            return tr("\(money(cents))；前 \(months) 个月没有", "\(money(cents)); none in the previous \(months) months",
                      "\(money(cents)); tiada dalam \(months) bulan sebelumnya")
        case .purchase:
            return tr("约为平常\(name)单笔消费的 \(multipleText) 倍", "About \(multipleText)× a typical \(name) purchase",
                      "Kira-kira \(multipleText)× belian \(name) biasa")
        }
    }
    /// The trailing badge: "+58%", "New", "4.5×".
    var badge: String {
        switch kind {
        case .overall, .category: return "+\(rise)%"
        case .newCategory: return tr("新", "New", "Baharu")
        case .purchase: return multipleText + "×"
        }
    }
    /// The multiple to one decimal, without a trailing ".0".
    var multipleText: String {
        let tenths = Int((multiple * 10).rounded())
        if tenths % 10 == 0 { return String(tenths / 10) }
        return String(tenths / 10) + "." + String(tenths % 10)
    }
}

/// Tells the person about unusual spending this month: at most one notification a day,
/// each alert once a month, never for single purchases (the Overview shows those, and the
/// automatic recording already sent its own notification). On by default; the setting is in
/// Notifications. Foreground notifications become the app's own banner.
actor UnusualSpendingNotifier {
    static let shared = UnusualSpendingNotifier()
    static let enabledKey = "unusualSpendingAlerts"
    static let sentKey = "unusualSpendingSent"
    static let lastSentKey = "unusualSpendingLastSent"
    private var checking = false

    static var enabled: Bool { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }

    /// True for 20 hours after a notification went out.
    static func resting(lastSent: Date?, now: Date) -> Bool {
        guard let lastSent else { return false }
        return now >= lastSent && now.timeIntervalSince(lastSent) < 20 * 3600
    }

    /// The alert to send now, if any: the first one not sent this month, unless one went out
    /// in the last 20 hours.
    static func next(_ alerts: [SpendingAlert], month: String, sent: Set<String>, lastSent: Date?, now: Date) -> SpendingAlert? {
        guard !resting(lastSent: lastSent, now: now) else { return nil }
        for alert in alerts where alert.kind != .purchase && !sent.contains(month + "|" + alert.id) {
            return alert
        }
        return nil
    }

    func check(now: Date = Date()) async {
        guard !checking, Self.enabled else { return }
        checking = true
        defer { checking = false }
        let defaults = UserDefaults.standard
        let month = monthKey(now)
        let lastSent = defaults.object(forKey: Self.lastSentKey) as? Date
        // Runs after every refresh: once today's notification is out, don't read the ledger at all.
        guard !Self.resting(lastSent: lastSent, now: now), let ledger = try? LocalStore.shared.read() else { return }
        let alerts = SpendingAlerts.make(ledger: ledger, month: now, now: now)
        let stored: [String] = defaults.stringArray(forKey: Self.sentKey) ?? []
        let sent = Set(stored.filter { $0.hasPrefix(month + "|") })
        guard let alert = Self.next(alerts, month: month, sent: sent, lastSent: lastSent, now: now) else { return }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard Self.enabled, settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        let content = UNMutableNotificationContent()
        if defaults.bool(forKey: "hideNotificationDetails") {
            content.title = tr("本月消费有变化", "Unusual spending this month", "Belanja luar biasa bulan ini")
            content.body = tr("打开月记，看看本月有什么不同。", "Open YueJi to see what's different this month.", "Buka YueJi untuk melihat apa yang berbeza bulan ini.")
        } else {
            content.title = alert.title()
            content.body = alert.detail()
        }
        content.sound = LedgerNotifications.automationSound
        do {
            try await center.add(UNNotificationRequest(identifier: "yueji.unusual." + month + "." + alert.id, content: content, trigger: nil))
            // Only this month's lines are kept.
            defaults.set(Array(sent) + [month + "|" + alert.id], forKey: Self.sentKey)
            defaults.set(now, forKey: Self.lastSentKey)
        } catch { /* Tried again at a later check; a notification never changes a record. */ }
    }
}
