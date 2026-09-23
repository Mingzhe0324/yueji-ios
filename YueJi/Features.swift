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
