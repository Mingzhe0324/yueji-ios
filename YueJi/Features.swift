import Foundation

func parseRate(_ input: String) throws -> Decimal {
    let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard text.range(of: #"^\d{1,6}(\.\d{1,12})?$"#, options: .regularExpression) != nil,
          let value = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")), value > 0, value <= 100_000 else { throw LedgerError.invalid("汇率必须大于零。") }
    return value
}

// Accounting base is MYR. Existing integer cents and friend balances remain MYR.
enum Currency {
    static let codes = ["MYR", "SGD", "USD", "CNY", "THB", "IDR", "JPY", "KRW", "EUR", "GBP", "AUD", "HKD", "TWD"]
    static func scale(_ code: String) -> Int { ["JPY", "KRW"].contains(code) ? 1 : 100 }
    static func parse(_ text: String, code: String) throws -> Int {
        guard codes.contains(code) else { throw LedgerError.invalid("币种无效。") }
        let cents = try toCents(text)
        if scale(code) == 1 { guard cents % 100 == 0 else { throw LedgerError.invalid("此币种只接受整数金额。") }; return cents / 100 }
        return cents
    }
    static func input(_ minor: Int, _ code: String) -> String { scale(code) == 1 ? String(minor) : String(format: "%.2f", Double(minor) / 100) }
    static func display(_ minor: Int, _ code: String) -> String { "\(code) \(input(minor, code))" }
}
struct RateQuote: Codable, Equatable {
    var value: Decimal // MYR per 1 unit of foreign currency, never the inverse.
    var date: Date
    var source: String
    func validate() throws {
        guard !value.isNaN, value > 0, value <= 100_000, date.timeIntervalSince1970.isFinite else { throw LedgerError.invalid("汇率必须大于零。") }
    }
    var text: String { NSDecimalNumber(decimal: value).stringValue }
}
struct ForeignAmount: Codable, Equatable {
    var currency: String
    var minor: Int
    var quote: RateQuote
    func myrCents() throws -> Int {
        guard Currency.codes.contains(currency), currency != "MYR", minor > 0, minor <= 10_000_000_000 else { throw LedgerError.invalid("交易金额或日期无效。") }
        try quote.validate()
        var raw = Decimal(minor) / Decimal(Currency.scale(currency)) * quote.value * 100
        var rounded = Decimal()
        NSDecimalRound(&rounded, &raw, 0, .plain)
        guard !rounded.isNaN, rounded >= 1, rounded <= 10_000_000_000 else { throw LedgerError.invalid("换算金额超出范围或不足一仙。") }
        return NSDecimalNumber(decimal: rounded).intValue
    }
}
enum RepeatCycle: String, Codable, CaseIterable {
    case weekly, monthly, yearly
    var label: String { switch self { case .weekly: return tr("每周", "Weekly", "Mingguan"); case .monthly: return tr("每月", "Monthly", "Bulanan"); case .yearly: return tr("每年", "Yearly", "Tahunan") } }
}
struct RecurringExpense: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var name: String
    var minor: Int
    var currency = "MYR"
    var category = "账单"
    var start: Date
    var cycle: RepeatCycle = .monthly
    var timeZoneID = TimeZone.current.identifier
    var autoPost = false
    var active = true
    var nextIndex = 0
    var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: timeZoneID) ?? .current; return c }
    func occurrence(_ index: Int) -> Date? {
        guard index >= 0, index < 10_000 else { return nil }
        let c = calendar
        if cycle == .weekly { return c.date(byAdding: .day, value: index * 7, to: c.startOfDay(for: start)) }
        let original = c.dateComponents([.year, .month, .day], from: start)
        guard let anchor = c.date(from: DateComponents(year: original.year, month: original.month, day: 1)),
              let month = c.date(byAdding: .month, value: index * (cycle == .yearly ? 12 : 1), to: anchor),
              let range = c.range(of: .day, in: .month, for: month) else { return nil }
        return c.date(byAdding: .day, value: min(original.day ?? 1, range.count) - 1, to: month)
    }
    var nextDate: Date { occurrence(nextIndex) ?? start }
    func validate(allowedCategories: [String] = categories) throws {
        guard !id.isEmpty, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 200,
              Currency.codes.contains(currency), minor > 0, minor <= 10_000_000_000, allowedCategories.contains(category),
              start.timeIntervalSince1970 >= 0, start.timeIntervalSince1970 < 4_102_444_800,
              TimeZone(identifier: timeZoneID) != nil, nextIndex >= 0, nextIndex < 10_000 else { throw LedgerError.invalid("固定消费资料无效。") }
    }
}
extension Ledger {
    func foreignAmount(minor: Int, code: String) throws -> ForeignAmount? {
        if code == "MYR" { return nil }
        guard let quote = rates[code] else { throw LedgerError.invalid("请先在汇率设置保存该币种的汇率。") }
        let fx = ForeignAmount(currency: code, minor: minor, quote: quote)
        _ = try fx.myrCents()
        return fx
    }
    // Called on app activation or the explicit Shortcuts action. Never claims an exact background timer.
    mutating func postDue(now: Date = Date(), only ruleID: String? = nil, force: Bool = false) throws {
        for i in recurring.indices {
            guard recurring[i].active, ruleID == nil || recurring[i].id == ruleID,
                  recurring[i].autoPost || force else { continue }
            // Missing FX leaves this rule pending; it does not block unrelated Apple Pay/MYR entries.
            if recurring[i].currency != "MYR", rates[recurring[i].currency] == nil { continue }
            var count = 0
            while let date = recurring[i].occurrence(recurring[i].nextIndex), date <= now, count < 600 {
                let key = "\(recurring[i].id):\(recurring[i].nextIndex)"
                if !postedRecurring.contains(key) {
                    let rule = recurring[i]
                    let fx = try foreignAmount(minor: rule.minor, code: rule.currency)
                    let cents = try fx?.myrCents() ?? rule.minor
                    expenses.append(Expense(merchant: rule.name, cents: cents, date: date, category: rule.category, source: "固定消费", foreign: fx, recurringKey: key))
                    postedRecurring.insert(key)
                }
                recurring[i].nextIndex += 1; count += 1
            }
        }
    }
    mutating func resumeRule(_ id: String, now: Date = Date()) {
        guard let i = recurring.firstIndex(where: { $0.id == id }) else { return }
        // Paused periods are skipped, not charged retroactively on resume.
        let today = recurring[i].calendar.startOfDay(for: now)
        while let date = recurring[i].occurrence(recurring[i].nextIndex), date < today { recurring[i].nextIndex += 1 }
        recurring[i].active = true
    }
}
struct FXService {
    struct Response: Decodable { let base: String; let quote: String; let rate: Decimal; let date: String }
    static func fetch(_ currency: String) async throws -> RateQuote {
        guard Currency.codes.contains(currency), currency != "MYR",
              let url = URL(string: "https://api.frankfurter.dev/v2/rate/\(currency.lowercased())/myr") else { throw LedgerError.invalid("币种无效。") }
        var request = URLRequest(url: url); request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200, data.count < 100_000 else { throw LedgerError.invalid("无法获取汇率，请手动填写或稍后重试。") }
        let r = try JSONDecoder().decode(Response.self, from: data)
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(secondsFromGMT: 0); f.dateFormat = "yyyy-MM-dd"
        guard r.base.uppercased() == currency, r.quote.uppercased() == "MYR", let date = f.date(from: r.date) else { throw LedgerError.invalid("汇率服务返回的数据无效。") }
        let quote = RateQuote(value: r.rate, date: date, source: "Frankfurter"); try quote.validate(); return quote
    }
}

// Calendar month navigation must not drift from Jan 31 to Feb 28 to Mar 28.
func shiftedMonth(_ month: Date, by offset: Int, calendar: Calendar = .current) -> Date {
    guard let anchor = calendar.dateInterval(of: .month, for: month)?.start else { return month }
    return calendar.date(byAdding: .month, value: offset, to: anchor) ?? month
}
// New entries inherit the viewed month; existing entries always retain their own date.
func dateForNewExpense(in month: Date, now: Date = Date(), calendar: Calendar = .current) -> Date {
    if calendar.isDate(month, equalTo: now, toGranularity: .month) { return now }
    guard let interval = calendar.dateInterval(of: .month, for: month),
          let days = calendar.range(of: .day, in: .month, for: month) else { return month }
    let today = calendar.dateComponents([.day, .hour, .minute, .second], from: now)
    let day = min(today.day ?? 1, days.count)
    guard let target = calendar.date(byAdding: .day, value: day - 1, to: interval.start) else { return month }
    return calendar.date(bySettingHour: today.hour ?? 12, minute: today.minute ?? 0, second: today.second ?? 0, of: target) ?? target
}

struct RefundRecord: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var cents: Int
    var date: Date
    var personalCents: Int
    var shares: [String: Int]
}
struct AutomationEvent: Codable, Identifiable {
    var id = UUID().uuidString
    var date = Date() // Actual receipt/execution time, not transaction date.
    var source: String
    var outcome: String // saved / duplicate / checked / failed
    var detail: String
}
struct DuplicatePair: Identifiable {
    let first: Expense; let second: Expense
    var id: String { [first.id, second.id].sorted().joined(separator: "|") }
}
struct FriendBalance: Identifiable {
    let id: String; var name: String; var owed: Int = 0; var payable: Int = 0; var count: Int = 0
}
func friendKey(_ name: String) -> String { name.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ").lowercased() }
func reviewError(_ zh: String, _ en: String, _ ms: String) -> LedgerError { .invalid(tr(zh, en, ms)) }

// Integer proportional allocation with deterministic remainder assignment and exact sum.
func allocateRefund(_ cents: Int, capacities: [Int]) throws -> [Int] {
    guard cents > 0, !capacities.isEmpty, capacities.count <= 101,
          capacities.allSatisfy({ $0 >= 0 && $0 <= 10_000_000_000 }) else { throw LedgerError.invalid("交易金额或日期无效。") }
    let total = capacities.reduce(0, +)
    guard cents <= total else { throw reviewError("退款超过可退金额。", "Refund exceeds remaining amount.", "Bayaran balik melebihi baki amaun.") }
    // Decimal avoids Int64 multiplication overflow on imported large values.
    var parts = capacities.map { cap -> Int in
        var raw = Decimal(cents) * Decimal(cap) / Decimal(total); var rounded = Decimal()
        NSDecimalRound(&rounded, &raw, 0, .down); return NSDecimalNumber(decimal: rounded).intValue
    }
    var remainder = cents - parts.reduce(0, +)
    for i in parts.indices where remainder > 0 && parts[i] < capacities[i] { parts[i] += 1; remainder -= 1 }
    return parts
}
func validateRefunds(_ e: Expense) throws {
    let refunds = e.refunds ?? []
    guard refunds.count <= 10_000, Set(refunds.map(\.id)).count == refunds.count else { throw LedgerError.invalid("账本格式或版本无效。") }
    for r in refunds {
        guard r.cents > 0, r.cents <= e.cents, r.personalCents >= 0, r.personalCents <= r.cents,
              r.shares.count <= e.shares.count, r.shares.allSatisfy({ key, value in value >= 0 && value <= r.cents && e.shares.contains(where: { $0.id == key }) }),
              r.personalCents + r.shares.values.reduce(0, +) == r.cents,
              r.date >= Calendar.current.startOfDay(for: e.date), r.date.timeIntervalSince1970.isFinite else { throw reviewError("退款资料无效。", "Invalid refund details.", "Butiran bayaran balik tidak sah.") }
    }
    guard e.refunded <= e.cents else { throw LedgerError.invalid("付款或分账数据无效。") }
    for s in e.shares {
        guard s.refunded >= 0, s.refunded <= s.cents, s.refunded == refunds.reduce(0, { $0 + ($1.shares[s.id] ?? 0) }) else { throw LedgerError.invalid("付款或分账数据无效。") }
    }
}
extension Ledger {
    mutating func addRefund(expenseID: String, cents: Int, date: Date, custom: [String: Int]? = nil) throws {
        guard let i = expenses.firstIndex(where: { $0.id == expenseID }), date <= Date(), date >= Calendar.current.startOfDay(for: expenses[i].date) else { throw LedgerError.invalid("交易金额或日期无效。") }
        let e = expenses[i]
        let allocation: [Int]
        if let custom {
            let keys = ["owner"] + e.shares.map(\.id)
            let capacities = [e.personal] + e.shares.map { $0.cents - $0.refunded }
            guard custom.keys.allSatisfy({ keys.contains($0) }), cents > 0 else { throw LedgerError.invalid("付款或分账数据无效。") }
            let values = keys.map { custom[$0] ?? 0 }
            guard zip(values, capacities).allSatisfy({ $0.0 >= 0 && $0.0 <= $0.1 }), values.reduce(0, +) == cents else {
                throw reviewError("分配合计必须等于退款金额，且不能超过各人的可退份额。", "Allocation must equal the refund and stay within each person's remaining share.", "Jumlah agihan mesti sama dengan bayaran balik dan tidak melebihi baki bahagian setiap orang.")
            }
            allocation = values
        } else {
            allocation = try allocateRefund(cents, capacities: [e.personal] + e.shares.map { $0.cents - $0.refunded })
        }
        var amounts: [String: Int] = [:]
        for j in e.shares.indices { amounts[e.shares[j].id] = allocation[j + 1] }
        let record = RefundRecord(cents: cents, date: date, personalCents: allocation[0], shares: amounts)
        expenses[i].refunds = (e.refunds ?? []) + [record]
        for j in e.shares.indices { expenses[i].shares[j].refundCents = e.shares[j].refunded + allocation[j + 1] }
    }
    mutating func removeRefund(expenseID: String, refundID: String) throws {
        guard let i = expenses.firstIndex(where: { $0.id == expenseID }), let r = expenses[i].refunds?.first(where: { $0.id == refundID }) else { return }
        var next = self
        next.expenses[i].refunds?.removeAll { $0.id == refundID }
        for j in next.expenses[i].shares.indices { next.expenses[i].shares[j].refundCents = next.expenses[i].shares[j].refunded - (r.shares[next.expenses[i].shares[j].id] ?? 0) }
        _ = try next.validated(); self = next
    }
    mutating func returnToFriend(expenseID: String, shareID: String, cents: Int, date: Date) throws {
        guard let i = expenses.firstIndex(where: { $0.id == expenseID }), let j = expenses[i].shares.firstIndex(where: { $0.id == shareID }),
              cents > 0, cents <= -expenses[i].shares[j].owed, date <= Date(),
              date >= ((expenses[i].refunds ?? []).map(\.date).max() ?? expenses[i].date) else { throw LedgerError.invalid("请检查还款金额和日期。") }
        expenses[i].shares[j].returns = (expenses[i].shares[j].returns ?? []) + [Repayment(cents: cents, date: date)]
    }
    var friendBalances: [FriendBalance] {
        var result: [String: FriendBalance] = [:]
        for e in expenses { for s in e.shares {
            let key = friendKey(s.name)
            var b = result[key] ?? FriendBalance(id: key, name: s.name)
            b.owed += max(0, s.owed); b.payable += max(0, -s.owed); b.count += 1; result[key] = b
        } }
        return result.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    mutating func batchRepay(friend: String, cents: Int, date: Date) throws {
        guard cents > 0, date <= Date() else { throw LedgerError.invalid("请检查还款金额和日期。") }
        let indices = expenses.indices.sorted { expenses[$0].date == expenses[$1].date ? expenses[$0].id < expenses[$1].id : expenses[$0].date < expenses[$1].date }
        let eligible = indices.flatMap { i in expenses[i].shares.indices.compactMap { j -> (Int, Int)? in
            friendKey(expenses[i].shares[j].name) == friend && expenses[i].shares[j].owed > 0 && Calendar.current.startOfDay(for: expenses[i].date) <= date ? (i, j) : nil
        } }
        guard cents <= eligible.reduce(0, { $0 + expenses[$1.0].shares[$1.1].owed }) else { throw LedgerError.invalid("请检查还款金额和日期。") }
        var remaining = cents; let batch = UUID().uuidString
        for (i, j) in eligible where remaining > 0 {
            let part = min(remaining, expenses[i].shares[j].owed)
            expenses[i].shares[j].repayments.append(Repayment(cents: part, date: date, batchID: batch)); remaining -= part
        }
    }
    func duplicatePairs(limit: Int = 200) -> [DuplicatePair] {
        // Compare within same original-currency amount bucket; no O(n²) full-ledger scan.
        let groups = Dictionary(grouping: expenses) { e in "\(e.foreign?.currency ?? "MYR")|\(e.foreign?.minor ?? e.cents)" }
        var pairs: [DuplicatePair] = []
        for key in groups.keys.sorted() {
            let items = groups[key]!.sorted { $0.date < $1.date }
            for i in items.indices {
                for j in (i + 1)..<items.count {
                    let a = items[i], b = items[j]
                    if b.date.timeIntervalSince(a.date) > 86400 { break }
                    let sameName = friendKey(a.merchant) == friendKey(b.merchant)
                    let crossSource = a.source != b.source && Calendar.current.isDate(a.date, inSameDayAs: b.date)
                    guard sameName || crossSource else { continue }
                    let pair = DuplicatePair(first: a, second: b)
                    if !dismissedDuplicates.contains(pair.id) { pairs.append(pair) }
                    if pairs.count >= limit { return pairs }
                }
            }
        }
        return pairs
    }
    mutating func logAutomation(source: String, outcome: String, detail: String = "") {
        automationEvents.insert(AutomationEvent(source: source, outcome: outcome, detail: String(detail.prefix(2000))), at: 0)
        automationEvents = Array(automationEvents.prefix(100))
    }
}
struct PlannedCharge: Identifiable {
    let id: String; let name: String; let date: Date; let currency: String; let minor: Int; let myr: Int?
}
extension Ledger {
    func upcoming(in month: Date, now: Date = Date()) -> [PlannedCharge] {
        guard let range = Calendar.current.dateInterval(of: .month, for: month) else { return [] }
        var result: [PlannedCharge] = []
        for r in recurring where r.active {
            var index = r.nextIndex
            while let d = r.occurrence(index), d < range.end {
                if d >= max(Calendar.current.startOfDay(for: now), range.start), !postedRecurring.contains("\(r.id):\(index)") {
                    let converted: Int? = r.currency == "MYR" ? r.minor : (try? foreignAmount(minor: r.minor, code: r.currency)?.myrCents())
                    result.append(PlannedCharge(id: "\(r.id):\(index)", name: r.name, date: d, currency: r.currency, minor: r.minor, myr: converted))
                }
                index += 1
            }
        }
        return result.sorted { $0.date < $1.date }
    }
}
struct FuelEstimate {
    let distance: Decimal; let litresPer100km: Decimal; let pricePerLitre: Decimal; let parking: Int; let toll: Int
    func total() throws -> Int {
        guard distance > 0, distance <= 100_000, litresPer100km > 0, litresPer100km <= 100, pricePerLitre > 0, pricePerLitre <= 1000,
              parking >= 0, parking <= 100_000_000, toll >= 0, toll <= 100_000_000 else { throw LedgerError.invalid("交易金额或日期无效。") }
        var raw = distance * litresPer100km * pricePerLitre + Decimal(parking + toll)
        var rounded = Decimal(); NSDecimalRound(&rounded, &raw, 0, .plain)
        return NSDecimalNumber(decimal: rounded).intValue // km * L/100km * RM/L * 100 sen
    }
}


struct FriendSpending {
    var net = 0
    var refunds = 0
    var owed = 0
    var payable = 0
    var categories: [String: Int] = [:]
}
extension Ledger {
    func friendSpending(friend: String, month: Date? = nil) -> FriendSpending {
        var result = FriendSpending()
        for e in expenses where month == nil || monthKey(e.date) == monthKey(month!) {
            for s in e.shares where friendKey(s.name) == friend {
                let net = s.cents - s.refunded
                result.net += net; result.refunds += s.refunded
                result.owed += max(0, s.owed); result.payable += max(0, -s.owed)
                result.categories[e.category, default: 0] += net
            }
        }
        return result
    }
}

struct RestorePreview: Identifiable {
    let id = UUID()
    let data: Data
    let ledger: Ledger
    init(data: Data) throws { self.ledger = try LocalStore.decode(data); self.data = data }
}

extension Ledger {
    func friendStatement(key: String, month: Date?) -> String {
        let name = friendBalances.first { $0.id == key }?.name ?? key
        let period = month.map(monthKey) ?? tr("全部月份", "All months", "Semua bulan")
        var lines = [tr("月记 · 朋友账单", "YueJi · Friend statement", "YueJi · Penyata rakan"), name, period, "MYR"]
        var net = 0, paid = 0, returned = 0, owed = 0, payable = 0
        let entries = expenses.filter { month == nil || monthKey($0.date) == monthKey(month!) }.sorted { $0.date < $1.date }
        for e in entries {
            for s in e.shares where friendKey(s.name) == key {
                net += s.cents - s.refunded; paid += s.repaid; returned += s.returned
                owed += max(0, s.owed); payable += max(0, -s.owed)
                lines.append("\n\(dateLabel(e.date)) · \(e.merchant) · \(categoryLabel(e.category))")
                lines.append(tr("份额 / 退款：", "Share / refund: ", "Bahagian / pulangan: ") + money(s.cents) + " / " + money(s.refunded))
                lines.append(tr("已还 / 已退回：", "Repaid / returned: ", "Dibayar / dipulangkan: ") + money(s.repaid) + " / " + money(s.returned))
                for r in s.repayments { lines.append("  \(dateLabel(r.date)) · " + tr("还款 ", "Repayment ", "Bayaran ") + money(r.cents)) }
                for r in s.returns ?? [] { lines.append("  \(dateLabel(r.date)) · " + tr("返款 ", "Returned ", "Dipulangkan ") + money(r.cents)) }
            }
        }
        lines.append("\n" + tr("净消费：", "Net spending: ", "Belanja bersih: ") + money(net))
        lines.append(tr("已还：", "Repaid: ", "Dibayar: ") + money(paid))
        lines.append(tr("已退回：", "Returned: ", "Dipulangkan: ") + money(returned))
        lines.append(tr("朋友待还：", "Still owed by friend: ", "Baki hutang rakan: ") + money(owed))
        lines.append(tr("我需退给朋友：", "I need to return: ", "Saya perlu pulangkan: ") + money(payable))
        lines.append(tr("按消费月份筛选，包含这些消费截至目前的所有还款和返款。", "Filtered by spending month; includes all repayments and returns for these entries to date.", "Ditapis mengikut bulan belanja; termasuk semua bayaran dan pulangan rekod ini setakat kini."))
        return lines.joined(separator: "\n")
    }
}

import UserNotifications

final class LedgerNotifications: NSObject, UNUserNotificationCenterDelegate {
    static let shared = LedgerNotifications()
    static let dailyID = "yueji.daily-reminder"
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }
    static func configure(daily: Bool, results: Bool, hour: Int, minute: Int) async throws {
        let center = UNUserNotificationCenter.current()
        if daily || results {
            guard try await center.requestAuthorization(options: [.alert, .sound]) else {
                throw reviewError("通知未获允许，请到 iPhone 设置开启月记通知。", "Notifications are not allowed. Enable YueJi notifications in iPhone Settings.", "Notifikasi tidak dibenarkan. Aktifkan notifikasi YueJi dalam Tetapan iPhone.")
            }
        }
        if daily {
            let content = UNMutableNotificationContent()
            content.title = tr("今天的消费记好了吗？", "Have you recorded today's spending?", "Sudah rekod belanja hari ini?")
            content.body = tr("打开月记，补上今天的消费，也检查自动记账有没有遗漏。", "Open YueJi to record today's spending and check for missing automatic entries.", "Buka YueJi untuk merekod belanja hari ini dan semak rekod automatik yang terlepas.")
            content.sound = .default
            var components = DateComponents(); components.hour = hour; components.minute = minute
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            try await center.add(UNNotificationRequest(identifier: dailyID, content: content, trigger: trigger))
        } else { center.removePendingNotificationRequests(withIdentifiers: [dailyID]) }
        let defaults = UserDefaults.standard
        defaults.set(daily, forKey: "dailyReminder"); defaults.set(results, forKey: "automationNotifications")
        defaults.set(hour * 60 + minute, forKey: "reminderMinutes")
    }
    static func result(title: String, body: String) async {
        guard UserDefaults.standard.bool(forKey: "automationNotifications") else { return }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        let content = UNMutableNotificationContent(); content.title = title; content.body = UserDefaults.standard.bool(forKey: "hideNotificationDetails") ? tr("请打开月记查看处理结果。", "Open YueJi to view the result.", "Buka YueJi untuk melihat hasil.") : body; content.sound = .default
        // Notification failure must never roll back or retry a successfully recorded payment.
        try? await center.add(UNNotificationRequest(identifier: "yueji.result." + UUID().uuidString, content: content, trigger: nil))
    }
}

struct CustomCategory: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var name: String
    var icon: String = "tag.fill"
    var color: String = "teal"
    static let icons = ["tag.fill", "book.fill", "airplane", "cross.case.fill", "pawprint.fill", "house.fill", "gift.fill", "sportscourt.fill", "car.fill", "heart.fill"]
    static let colors = ["teal", "blue", "purple", "pink", "orange", "green"]
    func validate() throws {
        guard !id.isEmpty, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 30,
              Self.icons.contains(icon), Self.colors.contains(color) else { throw LedgerError.invalid("付款或分账数据无效。") }
    }
}
struct TripDefaults: Codable, Equatable {
    var consumption: String
    var price: String
    var companions: [String]
    var includeDriver: Bool
    func validate() throws {
        let c = try parseRate(consumption), p = try parseRate(price)
        guard c <= 100, p <= 1000, companions.count <= 20,
              companions.allSatisfy({ !friendKey($0).isEmpty && $0.count <= 80 }),
              Set(companions.map(friendKey)).count == companions.count else {
            throw reviewError("请检查油耗、油价和朋友姓名，姓名不能重复。", "Check fuel use, price and unique friend names.", "Semak penggunaan minyak, harga dan nama rakan yang unik.")
        }
    }
}
extension Ledger {
    var categoryNames: [String] { categories + customCategories.map(\.name) }
    mutating func saveCategory(_ category: CustomCategory) throws {
        var value = category; value.name = value.name.trimmingCharacters(in: .whitespacesAndNewlines)
        try value.validate()
        guard !(categories + customCategories.filter { $0.id != value.id }.map(\.name)).map(friendKey).contains(friendKey(value.name)) else {
            throw reviewError("分类名称已存在。", "Category name already exists.", "Nama kategori sudah wujud.")
        }
        if let i = customCategories.firstIndex(where: { $0.id == value.id }) {
            let old = customCategories[i].name
            for j in expenses.indices where expenses[j].category == old { expenses[j].category = value.name }
            for j in recurring.indices where recurring[j].category == old { recurring[j].category = value.name }
            for key in Array(merchantCategories.keys) where merchantCategories[key] == old { merchantCategories[key] = value.name }
            customCategories[i] = value
        } else { customCategories.append(value) }
    }
    mutating func deleteCategory(_ id: String) throws {
        guard let value = customCategories.first(where: { $0.id == id }) else { return }
        guard !expenses.contains(where: { $0.category == value.name }), !recurring.contains(where: { $0.category == value.name }), !merchantCategories.values.contains(value.name) else {
            throw reviewError("此分类仍被账目、固定消费或商户规则使用，请先修改这些记录的分类。", "This category is used by entries, schedules or merchant rules. Reassign them before deleting it.", "Kategori digunakan oleh rekod, jadual atau peraturan peniaga. Tukar kategori dahulu.")
        }
        customCategories.removeAll { $0.id == id }
    }
    func spending(in month: Date, category: String? = nil) -> Int {
        expenses.filter { monthKey($0.date) == monthKey(month) && (category == nil || $0.category == category) }.reduce(0) { $0 + $1.personal }
    }
}
func optionalMoney(_ value: String) throws -> Int? {
    let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
    if text.isEmpty { return nil }
    if text == "0" || text == "0.00" { return 0 }
    return try toCents(text)
}
struct LedgerFilter: Equatable {
    var category = ""
    var source = ""
    var minimum = ""
    var maximum = ""
    func validate() throws {
        let low = try optionalMoney(minimum), high = try optionalMoney(maximum)
        if let low, let high, low > high { throw reviewError("最低金额不能高于最高金额。", "Minimum cannot exceed maximum.", "Minimum tidak boleh melebihi maksimum.") }
    }
    var active: Bool { self != LedgerFilter() }
}

// Quote every cell and neutralize formula-like user strings for spreadsheet applications.
func csvCell(_ value: String) -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    let formula = trimmed.first.map { "=+-@".contains($0) } ?? false
    let safe = formula || value.hasPrefix("\t") || value.hasPrefix("\r") ? "'" + value : value
    return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
}
func csvData(_ rows: [[String]]) -> Data {
    let text = "\u{FEFF}" + rows.map { $0.map(csvCell).joined(separator: ",") }.joined(separator: "\r\n") + "\r\n"
    return Data(text.utf8)
}
extension Ledger {
    func csv(month: Date?, splits: Bool) -> Data {
        let entries = expenses.filter { month == nil || monthKey($0.date) == monthKey(month!) }.sorted { $0.date < $1.date }
        let formatter = ISO8601DateFormatter()
        var rows: [[String]]
        if splits {
            rows = [["expense_id", "date", "merchant", "category", "friend", "share_MYR", "refund_MYR", "repaid_MYR", "returned_MYR", "owed_MYR", "payable_back_MYR"]]
            for e in entries { for s in e.shares {
                rows.append([e.id, formatter.string(from: e.date), e.merchant, categoryLabel(e.category), s.name, Currency.input(s.cents, "MYR"), Currency.input(s.refunded, "MYR"), Currency.input(s.repaid, "MYR"), Currency.input(s.returned, "MYR"), Currency.input(max(0, s.owed), "MYR"), Currency.input(max(0, -s.owed), "MYR")])
            } }
        } else {
            rows = [["expense_id", "date", "merchant", "category", "source", "paid_MYR", "refund_MYR", "personal_net_MYR", "original_currency", "original_amount", "rate_to_MYR"]]
            for e in entries {
                let currency = e.foreign?.currency ?? "MYR"
                let amount = Currency.input(e.foreign?.minor ?? e.cents, currency)
                rows.append([e.id, formatter.string(from: e.date), e.merchant, categoryLabel(e.category), sourceLabel(e.source), Currency.input(e.cents, "MYR"), Currency.input(e.refunded, "MYR"), Currency.input(e.personal, "MYR"), currency, amount, e.foreign?.quote.text ?? "1"])
            }
        }
        return csvData(rows)
    }
}


extension Ledger {
    func filteredEntries(in month: Date, search: String, filter: LedgerFilter) throws -> [Expense] {
        try filter.validate()
        let low = try optionalMoney(filter.minimum), high = try optionalMoney(filter.maximum)
        let period = monthKey(month)
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return expenses.filter { e in
            guard monthKey(e.date) == period,
                  filter.category.isEmpty || filter.category == e.category,
                  filter.source.isEmpty || filter.source == e.source else { return false }
            if let low, e.cents < low { return false }
            if let high, e.cents > high { return false }
            return query.isEmpty || e.merchant.localizedCaseInsensitiveContains(query) || categoryLabel(e.category).localizedCaseInsensitiveContains(query)
        }.sorted { $0.date > $1.date }
    }
}
