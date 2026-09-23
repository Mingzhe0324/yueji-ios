import Foundation
import CryptoKit

enum LedgerError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { switch self { case .invalid(let text): return localizedError(text) } }
}
let categories = ["餐饮", "交通", "购物", "账单", "娱乐", "其他"]
func money(_ cents: Int) -> String { String(format: "RM %.2f", Double(cents) / 100) }
func toCents(_ value: String) throws -> Int {
    let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard text.range(of: #"^\d{1,8}(\.\d{1,2})?$"#, options: .regularExpression) != nil,
          let number = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")), number > 0 else {
        throw LedgerError.invalid("请输入大于零、最多两位小数的金额。")
    }
    return NSDecimalNumber(decimal: number * 100).intValue
}
func monthKey(_ date: Date) -> String { let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM"; return f.string(from: date) }
func guessCategory(_ name: String) -> String {
    let rules: [(String, [String])] = [("餐饮", ["餐", "饭", "咖啡", "coffee", "cafe", "food", "kfc", "zus"]), ("交通", ["油", "停车", "petrol", "shell", "parking", "grab"]), ("购物", ["shopee", "lazada", "购物"]), ("账单", ["房租", "电费", "rent", "unifi"]), ("娱乐", ["netflix", "spotify", "电影"])]
    return rules.first { $0.1.contains { name.lowercased().contains($0) } }?.0 ?? "其他"
}
struct Repayment: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var cents: Int
    var date: Date = Date()
    var batchID: String? = nil
}
struct Share: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var name: String
    var cents: Int
    var repayments: [Repayment] = []
    var refundCents: Int? = nil
    var returns: [Repayment]? = nil
    var refunded: Int { refundCents ?? 0 }
    var returned: Int { (returns ?? []).reduce(0) { $0 + $1.cents } }
    var repaid: Int { repayments.reduce(0) { $0 + $1.cents } }
    var owed: Int { cents - refunded - repaid + returned }
}
struct Expense: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var merchant: String
    var cents: Int
    var date: Date = Date()
    var category: String = "其他"
    var source: String = "手动"
    var fuel = false
    var shares: [Share] = []
    var foreign: ForeignAmount? = nil
    var recurringKey: String? = nil
    var refunds: [RefundRecord]? = nil
    var refunded: Int { (refunds ?? []).reduce(0) { $0 + $1.cents } }
    var personalRefund: Int { (refunds ?? []).reduce(0) { $0 + $1.personalCents } }
    var personal: Int { cents - shares.reduce(0) { $0 + $1.cents } - personalRefund }
}
struct Ledger: Codable {
    var version = 3
    var expenses: [Expense] = []
    var budgets: [String: Int] = [:]
    var seenEvents: Set<String> = []
    var rates: [String: RateQuote] = [:]
    var recurring: [RecurringExpense] = []
    var postedRecurring: Set<String> = []
    var dismissedDuplicates: Set<String> = []
    var automationEvents: [AutomationEvent] = []
    var merchantCategories: [String: String] = [:]
    var backupCreatedAt: Date? = nil
    init(version: Int = 3, expenses: [Expense] = [], budgets: [String: Int] = [:], seenEvents: Set<String> = [], rates: [String: RateQuote] = [:], recurring: [RecurringExpense] = [], postedRecurring: Set<String> = []) {
        self.version = version; self.expenses = expenses; self.budgets = budgets; self.seenEvents = seenEvents
        self.rates = rates; self.recurring = recurring; self.postedRecurring = postedRecurring
    }
    enum CodingKeys: String, CodingKey { case version, expenses, budgets, seenEvents, rates, recurring, postedRecurring, dismissedDuplicates, automationEvents, merchantCategories, backupCreatedAt }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let v = try c.decode(Int.self, forKey: .version)
        guard (1...3).contains(v) else { throw LedgerError.invalid("账本格式或版本无效。") }
        version = 3
        expenses = try c.decode([Expense].self, forKey: .expenses)
        budgets = try c.decode([String: Int].self, forKey: .budgets)
        seenEvents = try c.decode(Set<String>.self, forKey: .seenEvents)
        rates = try c.decodeIfPresent([String: RateQuote].self, forKey: .rates) ?? [:]
        recurring = try c.decodeIfPresent([RecurringExpense].self, forKey: .recurring) ?? []
        postedRecurring = try c.decodeIfPresent(Set<String>.self, forKey: .postedRecurring) ?? []
        dismissedDuplicates = try c.decodeIfPresent(Set<String>.self, forKey: .dismissedDuplicates) ?? []
        automationEvents = try c.decodeIfPresent([AutomationEvent].self, forKey: .automationEvents) ?? []
        merchantCategories = try c.decodeIfPresent([String: String].self, forKey: .merchantCategories) ?? [:]
        backupCreatedAt = try c.decodeIfPresent(Date.self, forKey: .backupCreatedAt)
    }
    func validated() throws -> Ledger {
        guard merchantCategories.count <= 50_000,
              merchantCategories.allSatisfy({ !$0.key.isEmpty && $0.key.count <= 200 && categories.contains($0.value) }) else {
            throw LedgerError.invalid("付款或分账数据无效。")
        }
        guard version == 3, expenses.count <= 50_000, Set(expenses.map(\.id)).count == expenses.count,
              budgets.values.allSatisfy({ $0 >= 0 && $0 <= 10_000_000_000 }) else { throw LedgerError.invalid("账本格式或版本无效。") }
        guard rates.count <= 100, recurring.count <= 500, Set(recurring.map(\.id)).count == recurring.count else { throw LedgerError.invalid("账本格式或版本无效。") }
        for (code, quote) in rates { guard Currency.codes.contains(code), code != "MYR" else { throw LedgerError.invalid("币种无效。") }; try quote.validate() }
        for rule in recurring { try rule.validate() }
        guard automationEvents.count <= 100, automationEvents.allSatisfy({ $0.date.timeIntervalSince1970.isFinite && $0.detail.count <= 2000 }) else { throw LedgerError.invalid("账本格式或版本无效。") }
        for e in expenses {
            if let fx = e.foreign { guard try fx.myrCents() == e.cents else { throw LedgerError.invalid("外币金额与换算金额不符。") } }
            guard !e.id.isEmpty, !e.merchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  e.merchant.count <= 200, e.cents > 0, e.cents <= 10_000_000_000,
                  e.date.timeIntervalSince1970.isFinite, categories.contains(e.category), e.shares.count <= 100,
                  Set(e.shares.map(\.id)).count == e.shares.count,
                  Set(e.shares.map { friendKey($0.name) }).count == e.shares.count else { throw LedgerError.invalid("付款或分账数据无效。") }
            for s in e.shares {
                guard !s.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      s.cents >= 0, s.cents <= e.cents, s.refunded >= 0, s.refunded <= s.cents, s.repayments.count <= 10_000,
                      s.repayments.allSatisfy({ $0.cents > 0 && $0.cents <= s.cents && $0.date.timeIntervalSince1970.isFinite }) else { throw LedgerError.invalid("还款不能超过朋友应付金额。") }
                guard (s.returns ?? []).count <= 10_000, (s.returns ?? []).allSatisfy({ $0.cents > 0 && $0.cents <= e.cents && $0.date.timeIntervalSince1970.isFinite }), s.returned <= max(0, s.repaid + s.refunded - s.cents), s.repaid <= s.cents else { throw LedgerError.invalid("还款超出朋友份额。") }
            }
            try validateRefunds(e)
            guard e.personal >= 0 else { throw LedgerError.invalid("朋友份额超过实际付款。") }
        }
        return self
    }
    mutating func addPayment(amount: Double, merchant: String, currency: String, date: Date, eventID: String?) throws -> Bool {
        let code = currency.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard Currency.codes.contains(code), amount.isFinite, amount > 0, amount <= 100_000_000,
              date.timeIntervalSince1970 >= 0, date.timeIntervalSince1970 < 4_102_444_800 else { throw LedgerError.invalid("交易金额或日期无效。") }
        let scale = Currency.scale(code)
        guard abs(amount * Double(scale) - (amount * Double(scale)).rounded()) < 0.00001 else { throw LedgerError.invalid("交易金额或日期无效。") }
        let minor = Int((amount * Double(scale)).rounded())
        let name = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 200 else { throw LedgerError.invalid("未取得商户名称，请检查快捷指令的输入。") }
        let explicit = eventID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // Preserve the v1 MYR fingerprint for migration-safe deduplication.
        let fingerprint = explicit.isEmpty ? "\(Int(date.timeIntervalSince1970))|\(name.lowercased())|\(minor)|\(code)" : explicit
        let key = SHA256.hash(data: Data(fingerprint.utf8)).map { String(format: "%02x", $0) }.joined()
        guard !seenEvents.contains(key) else { return false }
        let fx = try foreignAmount(minor: minor, code: code)
        let value = try fx?.myrCents() ?? minor
        expenses.append(Expense(merchant: name, cents: value, date: date, category: merchantCategories[friendKey(name)] ?? guessCategory(name), source: "Apple Pay", foreign: fx))
        seenEvents.insert(key)
        return true
    }
    mutating func repay(expenseID: String, shareID: String, cents: Int, date: Date) throws {
        guard let ei = expenses.firstIndex(where: { $0.id == expenseID }), let si = expenses[ei].shares.firstIndex(where: { $0.id == shareID }) else { throw LedgerError.invalid("找不到这笔分账，请重新打开。") }
        guard cents > 0, cents <= expenses[ei].shares[si].owed,
              date >= Calendar.current.startOfDay(for: expenses[ei].date), date <= Date() else { throw LedgerError.invalid("请检查还款金额和日期。") }
        expenses[ei].shares[si].repayments.append(Repayment(cents: cents, date: date))
    }
}
func equalShares(total: Int, count: Int, includeMe: Bool) -> [Int] {
    let n = count + (includeMe ? 1 : 0)
    guard count > 0, n > 0 else { return [] }
    return (0..<count).map { total / n + ($0 < total % n ? 1 : 0) }
}
