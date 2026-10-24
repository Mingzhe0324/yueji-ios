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
            bounds = [largest / 4, largest / 2, largest * 3 / 4]
        } else {
            bounds = [0.25, 0.5, 0.75].map { spent[Int((Double(spent.count - 1) * $0).rounded())] }
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
    var monthlyAverage: Int { trackedMonths > 0 ? Int((Double(total) / Double(trackedMonths)).rounded()) : 0 }
    /// The month (1–12) with the most spending; the earlier one on a tie.
    var busiestMonth: Int? {
        var best: Int?
        for index in months.indices where months[index] > 0 && months[index] > (best.map { months[$0 - 1] } ?? 0) {
            best = index + 1
        }
        return best
    }
    /// The day with the most spending; the earlier one on a tie.
    var biggestDay: Date? {
        days.max { $0.value.cents != $1.value.cents ? $0.value.cents < $1.value.cents : $0.key > $1.key }?.key
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
        let earliest = ledger.expenses.map(\.date).min()
        earliestYear = earliest.map { calendar.component(.year, from: $0) } ?? calendar.component(.year, from: now)
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
        categories = categoryTotals.filter { $0.value > 0 }
            .map { YearCategoryTotal(category: $0.key, cents: $0.value) }
            .sorted { $0.cents == $1.cents ? $0.category < $1.category : $0.cents > $1.cents }
        merchants = Array(merchantTotals
            .map { YearMerchantTotal(id: $0.key, name: $0.value.name, cents: $0.value.cents, payments: $0.value.payments) }
            .sorted { $0.cents == $1.cents ? $0.name < $1.name : $0.cents > $1.cents }
            .prefix(5))
        scale = SpendingHeatScale(amounts: days.values.map(\.cents))

        // The year so far: up to the end of today, or all of it once it has ended.
        guard let earliest, start <= now else { return }
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
            previousSamePeriod = ledger.expenses.reduce(0) { sum, entry in
                entry.date >= previousStart && entry.date < previousEnd ? sum + max(0, entry.personalSpending) : sum
            }
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
        let throughDay = ongoing ? (calendar.dateComponents([.day], from: current.start, to: today).day ?? 0) + 1 : nil
        let periodEnd = ongoing ? (calendar.date(byAdding: .day, value: 1, to: today) ?? current.end) : current.end
        var previous: [(full: DateInterval, compared: Date)] = []
        for offset in 1...monthsCompared {
            guard let start = calendar.date(byAdding: .month, value: -offset, to: current.start),
                  let full = calendar.dateInterval(of: .month, for: start) else { continue }
            let cut = throughDay.flatMap { calendar.date(byAdding: .day, value: $0, to: full.start) }
            previous.append((full: full, compared: min(cut ?? full.end, full.end)))
        }
        guard let earliest = previous.map({ $0.full.start }).min() else { return [] }

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
        guard tracked.count >= minimumMonthsWithEntries else { return [] }
        func usual(_ sum: Int) -> Int { Int((Double(sum) / Double(tracked.count)).rounded()) }
        func isUp(_ cents: Int, over usual: Int, rise: Double, extra: Int) -> Bool {
            Double(cents) >= Double(usual) * (1 + rise) && cents - usual >= extra
        }

        var overall: [SpendingAlert] = []
        var others: [SpendingAlert] = []
        if (throughDay ?? earliestDay) >= earliestDay {
            let usualSpent = usual(usualSum)
            if usualSpent > 0, isUp(spent, over: usualSpent, rise: overallRise, extra: overallExtra) {
                overall.append(SpendingAlert(kind: .overall, cents: spent, usual: usualSpent, throughDay: throughDay))
            }
            for (category, cents) in spentByCategory {
                let usualCents = usual(usualByCategory[category] ?? 0)
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
        let explained = Set(purchases.map(\.category))
        others.removeAll { explained.contains($0.category) }
        let ranked = (others + purchases).sorted { $0.extra == $1.extra ? $0.id < $1.id : $0.extra > $1.extra }
        return overall + Array(ranked.prefix(limit))
    }

    static func median(_ values: [Int]) -> Int {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        let middle = sorted.count / 2
        return sorted.count % 2 == 1 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2
    }

    /// The alerts the person hid for a month, from the stored lines.
    static func dismissed(_ stored: String, month: String) -> Set<String> {
        Set(stored.split(separator: "\n").compactMap { line -> String? in
            let parts = line.split(separator: "|", maxSplits: 1)
            return parts.count == 2 && parts[0] == month ? String(parts[1]) : nil
        })
    }
    /// The stored lines with one more alert hidden; months older than the last few are dropped.
    static func dismissing(_ id: String, month: String, in stored: String) -> String {
        let keep = stored.split(separator: "\n").map(String.init).filter { line in
            guard let prefix = line.split(separator: "|", maxSplits: 1).first else { return false }
            return String(prefix) >= monthKey(Date().addingTimeInterval(-100 * 24 * 3600))
        }
        let line = month + "|" + id
        return (keep.contains(line) ? keep : keep + [line]).joined(separator: "\n")
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
        let rounded = (multiple * 10).rounded() / 10
        return rounded == rounded.rounded() ? String(Int(rounded)) : String(format: "%.1f", rounded)
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
        return alerts.first { $0.kind != .purchase && !sent.contains(month + "|" + $0.id) }
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
        let sent = Set((defaults.stringArray(forKey: Self.sentKey) ?? []).filter { $0.hasPrefix(month + "|") })
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
        LedgerNotifications.attachThumbnail("Budget", to: content)
        do {
            try await center.add(UNNotificationRequest(identifier: "yueji.unusual." + month + "." + alert.id, content: content, trigger: nil))
            // Only this month's lines are kept.
            defaults.set(Array(sent) + [month + "|" + alert.id], forKey: Self.sentKey)
            defaults.set(now, forKey: Self.lastSentKey)
        } catch { /* Tried again at a later check; a notification never changes a record. */ }
    }
}
