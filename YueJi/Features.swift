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
    func validate() throws {
        guard !id.isEmpty, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 200,
              Currency.codes.contains(currency), minor > 0, minor <= 10_000_000_000, categories.contains(category),
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
    mutating func addRefund(expenseID: String, cents: Int, date: Date) throws {
        guard let i = expenses.firstIndex(where: { $0.id == expenseID }), date <= Date(), date >= Calendar.current.startOfDay(for: expenses[i].date) else { throw LedgerError.invalid("交易金额或日期无效。") }
        let e = expenses[i]
        let allocation = try allocateRefund(cents, capacities: [e.personal] + e.shares.map { $0.cents - $0.refunded })
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
