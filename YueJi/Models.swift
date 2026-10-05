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
    let rules: [(String, [String])] = [("餐饮", ["餐", "饭", "咖啡", "coffee", "cafe", "food", "kfc", "zus", "pan mee"]), ("交通", ["油", "停车", "petrol", "shell", "parking", "grab", "rfid", "toll"]), ("购物", ["shopee", "lazada", "购物"]), ("账单", ["房租", "电费", "rent", "unifi"]), ("娱乐", ["netflix", "spotify", "电影"])]
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
    var receiptSummary: String? = nil
    var refunded: Int { (refunds ?? []).reduce(0) { $0 + $1.cents } }
    var personalRefund: Int { (refunds ?? []).reduce(0) { $0 + $1.personalCents } }
    var personal: Int { cents - shares.reduce(0) { $0 + $1.cents } - personalRefund }
}
struct Ledger: Codable {
    var version = 4
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
    var customCategories: [CustomCategory] = []
    var tripDefaults: TripDefaults? = nil
    var savingsGoals: [SavingsGoal] = []
    var tngNotices: [TNGNotice] = []
    init(version: Int = 4, expenses: [Expense] = [], budgets: [String: Int] = [:], seenEvents: Set<String> = [], rates: [String: RateQuote] = [:], recurring: [RecurringExpense] = [], postedRecurring: Set<String> = []) {
        self.version = version; self.expenses = expenses; self.budgets = budgets; self.seenEvents = seenEvents
        self.rates = rates; self.recurring = recurring; self.postedRecurring = postedRecurring
    }
    enum CodingKeys: String, CodingKey { case version, expenses, budgets, seenEvents, rates, recurring, postedRecurring, dismissedDuplicates, automationEvents, merchantCategories, backupCreatedAt, customCategories, tripDefaults, tngNotices, savingsGoals }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let v = try c.decode(Int.self, forKey: .version)
        guard (1...4).contains(v) else { throw LedgerError.invalid("账本格式或版本无效。") }
        version = 4
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
        customCategories = try c.decodeIfPresent([CustomCategory].self, forKey: .customCategories) ?? []
        tripDefaults = try c.decodeIfPresent(TripDefaults.self, forKey: .tripDefaults)
        savingsGoals = try c.decodeIfPresent([SavingsGoal].self, forKey: .savingsGoals) ?? []
        tngNotices = try c.decodeIfPresent([TNGNotice].self, forKey: .tngNotices) ?? []
    }
    func validated() throws -> Ledger {
        guard savingsGoals.count <= 100, Set(savingsGoals.map(\.id)).count == savingsGoals.count else { throw LedgerError.invalid("储蓄目标无效 / Invalid savings goals") }
        for goal in savingsGoals { try goal.validate() }
        guard tngNotices.count <= 5000, tngNotices.reduce(0, { $0 + $1.body.utf8.count + $1.title.utf8.count }) <= 8_000_000, Set(tngNotices.map(\.id)).count == tngNotices.count else { throw LedgerError.invalid("账本格式或版本无效。") }
        for n in tngNotices {
            guard (n.reviewReason?.count ?? 0) <= 1000, (n.aiSuggestion?.count ?? 0) <= 1000, ["TNG", "银行 / TNG", "Maybank", "Hong Leong", "AmBank", "Ryt Bank", "RHB"].contains(n.provider),
                  (n.accountSuffix?.count ?? 0) <= 4, (n.bankReference?.count ?? 0) <= 200 else { throw LedgerError.invalid("Invalid notification source") }
            guard (n.recipient?.count ?? 0) <= 200, (n.resolvedFriend?.count ?? 0) <= 200,
                  (n.repaymentIDs?.count ?? 0) <= 50_000,
                  n.kind != "incoming" || (n.cents != nil && n.party != nil && n.expenseID == nil && ["pending", "ignored", "repayment", "income", "ownTransfer"].contains(n.status)),
                  !["repayment", "income", "ownTransfer"].contains(n.status) || n.kind == "incoming" else { throw LedgerError.invalid("Invalid incoming record") }

            guard !n.id.isEmpty, !n.body.isEmpty, n.body.count <= 8000, n.title.count <= 500,
                  n.date.timeIntervalSince1970 >= 0, n.date.timeIntervalSince1970 < 4_102_444_800,
                  ["payment", "transfer", "incoming", "unknown"].contains(n.kind), ["recorded", "transfer", "pending", "ignored", "repayment", "income", "ownTransfer"].contains(n.status),
                  n.cents == nil || (n.cents! > 0 && n.cents! <= 10_000_000_000), (n.party?.count ?? 0) <= 200 else { throw LedgerError.invalid("账本格式或版本无效。") }
        }
        guard customCategories.count <= 100,
              Set(customCategories.map(\.id)).count == customCategories.count,
              Set(categoryNames.map(friendKey)).count == categoryNames.count else { throw LedgerError.invalid("付款或分账数据无效。") }
        for category in customCategories { try category.validate() }
        try tripDefaults?.validate()
        guard merchantCategories.count <= 50_000,
              merchantCategories.allSatisfy({ !$0.key.isEmpty && $0.key.count <= 200 && categoryNames.contains($0.value) }) else {
            throw LedgerError.invalid("付款或分账数据无效。")
        }
        guard version == 4, expenses.count <= 50_000, Set(expenses.map(\.id)).count == expenses.count,
              budgets.values.allSatisfy({ $0 >= 0 && $0 <= 10_000_000_000 }) else { throw LedgerError.invalid("账本格式或版本无效。") }
        guard rates.count <= 100, recurring.count <= 500, Set(recurring.map(\.id)).count == recurring.count else { throw LedgerError.invalid("账本格式或版本无效。") }
        for (code, quote) in rates { guard Currency.codes.contains(code), code != "MYR" else { throw LedgerError.invalid("币种无效。") }; try quote.validate() }
        for rule in recurring { try rule.validate(allowedCategories: categoryNames) }
        guard automationEvents.count <= 100, automationEvents.allSatisfy({ $0.date.timeIntervalSince1970.isFinite && $0.detail.count <= 2000 }) else { throw LedgerError.invalid("账本格式或版本无效。") }
        for e in expenses {
            if let fx = e.foreign { guard try fx.myrCents() == e.cents else { throw LedgerError.invalid("外币金额与换算金额不符。") } }
            guard !e.id.isEmpty, !e.merchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  e.merchant.count <= 200, (e.receiptSummary?.count ?? 0) <= 20_000, e.cents > 0, e.cents <= 10_000_000_000,
                  e.date.timeIntervalSince1970.isFinite, categoryNames.contains(e.category), e.shares.count <= 100,
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
    mutating func restoreDeletedExpenses(_ entries: [Expense]) throws {
        guard Set(entries.map(\.id)).count == entries.count,
              !entries.contains(where: { item in expenses.contains { $0.id == item.id } }) else {
            throw LedgerError.invalid(tr("账目已存在，无法重复恢复。", "Entry already exists. Cannot restore a duplicate.", "Rekod sudah wujud. Tidak dapat memulihkan pendua."))
        }
        var restored = self
        restored.expenses.append(contentsOf: entries)
        self = try restored.validated()
    }

    /// Keep automation and recurring deduplication markers so deletion stays deleted.
    mutating func deleteExpense(_ expected: Expense) throws {
        guard let index = expenses.firstIndex(where: { $0.id == expected.id }),
              expenses[index] == expected else {
            throw LedgerError.invalid(tr("账目已改变或已删除，请重新打开后再试。", "Entry changed or was deleted. Reopen it and try again.", "Rekod berubah atau dipadam. Buka semula dan cuba lagi."))
        }
        expenses.remove(at: index)
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
        guard cents > 0, cents <= expenses[ei].shares[si].owed else { throw reviewError("还款须大于零且不能超过尚欠金额。", "Repayment must be positive and no more than the balance.", "Bayaran balik mesti positif dan tidak melebihi baki.") }
        guard Calendar.current.startOfDay(for: date) <= Calendar.current.startOfDay(for: Date()) else { throw reviewError("收款日期不能在未来。", "Receipt date cannot be in the future.", "Tarikh penerimaan tidak boleh pada masa depan.") }
        guard date >= Calendar.current.startOfDay(for: expenses[ei].date) else { throw reviewError("还款日期早于消费日期，请检查并编辑原账目的日期。", "Repayment precedes the expense. Check and edit the original expense date.", "Bayaran balik mendahului belanja. Semak dan edit tarikh belanja asal.") }
        expenses[ei].shares[si].repayments.append(Repayment(cents: cents, date: date))
    }
}
func equalShares(total: Int, count: Int, includeMe: Bool) -> [Int] {
    let n = count + (includeMe ? 1 : 0)
    guard count > 0, n > 0 else { return [] }
    return (0..<count).map { total / n + ($0 < total % n ? 1 : 0) }
}

struct TNGNotice: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var body: String
    var title: String
    var date: Date
    var usesReceivedDate: Bool
    var kind: String // payment, transfer, incoming, unknown
    var status: String // recorded, transfer, pending, ignored, repayment, income, ownTransfer
    var cents: Int?
    var party: String?
    var expenseID: String?
    var possibleDuplicate = false
    var recipient: String? = nil
    var resolvedFriend: String? = nil
    var repaymentIDs: [String]? = nil
    var reviewReason: String? = nil
    var aiSuggestion: String? = nil
    var sourceBank: String? = nil
    var accountSuffix: String? = nil
    var bankReference: String? = nil
    var provider: String { sourceBank ?? "TNG" }
}
struct TNGParsed {
    let kind: String
    let cents: Int
    let party: String
    var recipient: String? = nil
    var sourceBank: String = "TNG"
    var transactionDate: Date? = nil
    var accountSuffix: String? = nil
    var reference: String? = nil
}
// A confirmed incoming notification changes the wallet in the positive
// direction even if its purpose (repayment, income, own transfer) is pending.
func tngSignedAmount(_ notice: TNGNotice) -> String {
    (notice.kind == "incoming" ? "+" : "−") + money(notice.cents ?? 0)
}
func parseTNG(_ body: String, title: String = "") -> TNGParsed? {
    let titleKey = friendKey(title).replacingOccurrences(of: "’", with: "'").trimmingCharacters(in: .punctuationCharacters)
    guard ["", "payment", "duitnow payment", "successful toll payment", "transfer successful", "duitnow transfer is successful", "ka-ching! incoming money", "you've received money"].contains(titleKey) else { return nil }
    let text = body.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    if titleKey.isEmpty || titleKey == "ka-ching! incoming money" {
        let pattern = #"\ARM\s*([0-9]+(?:\.[0-9]{2})?) received from (.{1,200}?) for (.{1,200})\.\z"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let a = Range(match.range(at: 1), in: text), let f = Range(match.range(at: 2), in: text),
           let t = Range(match.range(at: 3), in: text), let cents = try? toCents(String(text[a])) {
            let sender = String(text[f]).trimmingCharacters(in: .whitespacesAndNewlines)
            let recipient = String(text[t]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !sender.isEmpty && !recipient.isEmpty { return TNGParsed(kind: "incoming", cents: cents, party: sender, recipient: recipient) }
        }
    }
    // Verified received-money template. A slash remains part of the sender name.
    if titleKey.isEmpty || titleKey == "you've received money" {
        let pattern = #"\A(.{1,200}?) has transferred RM\s*([0-9]+(?:\.[0-9]{2})?) to you\.(?: Tap here to check the transaction details\.)?\z"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let senderRange = Range(match.range(at: 1), in: text),
           let amountRange = Range(match.range(at: 2), in: text),
           let cents = try? toCents(String(text[amountRange])) {
            let sender = String(text[senderRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !sender.isEmpty { return TNGParsed(kind: "incoming", cents: cents, party: sender) }
        }
    }
    if titleKey.isEmpty || titleKey == "successful toll payment" {
        let pattern = #"\ARM\s*([0-9]+(?:\.[0-9]{2})?) was deducted via RFID for toll payment on ([0-9]{2}-[A-Za-z]{3}-[0-9]{4} [0-9]{2}:[0-9]{2})\z"#
        if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let a = Range(match.range(at: 1), in: text), let d = Range(match.range(at: 2), in: text),
           let cents = try? toCents(String(text[a])), cents > 0 {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.timeZone = TimeZone(identifier: "Asia/Kuala_Lumpur")
            formatter.dateFormat = "dd-MMM-yyyy HH:mm"
            formatter.isLenient = false
            let raw = String(text[d])
            if let date = formatter.date(from: raw), formatter.string(from: date).lowercased() == raw.lowercased() {
                return TNGParsed(kind: "payment", cents: cents, party: "RFID Toll", transactionDate: date)
            }
        }
    }
    let patterns = [
        ("payment", "duitnow payment", #"\AYou have paid RM\s*([0-9]+(?:\.[0-9]{2})?) to (.{1,200})\.\z"#),
        ("payment", "payment", #"\AYou have paid RM\s*([0-9]+(?:\.[0-9]{2})?) for (.{1,200})\.\z"#),
        ("transfer", "transfer successful", #"\ARM\s*([0-9]+(?:\.[0-9]{2})?) has been successfully transferred to (.{1,200})\.\z"#),
        ("transfer", "duitnow transfer is successful", #"\AYou have successfully transferred RM\s*([0-9]+(?:\.[0-9]{2})?) to (.{1,200})\.\z"#)
    ]
    for (kind, expectedTitle, pattern) in patterns {
        guard titleKey.isEmpty || titleKey == expectedTitle else { continue }
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let amountRange = Range(match.range(at: 1), in: text), let nameRange = Range(match.range(at: 2), in: text),
              let cents = try? toCents(String(text[amountRange])) else { continue }
        let party = String(text[nameRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        if !party.isEmpty { return TNGParsed(kind: kind, cents: cents, party: party) }
    }
    return nil
}
extension Ledger {
    /// Presents existing notices without creating expenses or changing balances.
    func ledgerTNGTransfers(in month: Date, search: String = "") -> [TNGNotice] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return tngNotices.filter { notice in
            (notice.kind == "incoming" || notice.kind == "transfer") &&
            notice.status != "ignored" && notice.expenseID == nil &&
            Calendar.current.isDate(notice.date, equalTo: month, toGranularity: .month) &&
            (query.isEmpty || ((notice.party ?? "") + " " + (notice.recipient ?? "") + " " + notice.provider + " " + tngSignedAmount(notice)).localizedCaseInsensitiveContains(query))
        }.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date > $1.date }
    }
    /// Logs delivery independently from whether a supported transaction was recognized.
    /// Unknown transaction-like bodies are retained for review without posting expenses.
    mutating func processTNGNotification(body: String, title: String = "", date: Date?, eventID: String?) throws -> (accepted: Bool, message: String) {
        let message = try receiveTNG(body: body, title: title, date: date, eventID: eventID)
        let parsed = parseFinancialNotification(body, title: title)
        let accepted = parsed != nil
        logAutomation(source: parsed?.sourceBank ?? "银行 / TNG", outcome: accepted ? "checked" : (shouldReviewFinancialNotification(body, title: title) ? "pending" : "ignored"), detail: message)
        return (accepted, message)
    }
    mutating func receiveTNG(body: String, title: String = "", date: Date?, eventID: String?, now: Date = Date()) throws -> String {
        let text = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 8000, title.count <= 500 else {
            throw reviewError("通知正文为空或过长，请把 TNG 通知的 Body 传入。", "Notification body is empty or too long. Pass the TNG notification Body.", "Teks notifikasi kosong atau terlalu panjang. Hantar Body notifikasi TNG.")
        }
        // Supported templates can post transactions; unknown financial text stays pending.
        guard let verified = parseFinancialNotification(text, title: title) else {
            guard shouldReviewFinancialNotification(text, title: title) else {
                return tr("已忽略：推广、验证码、失败或非交易通知。", "Ignored: promotion, OTP, failure or non-transaction notice.", "Diabaikan: promosi, OTP, kegagalan atau bukan transaksi.")
            }
            let timestamp = date ?? now
            guard timestamp.timeIntervalSince1970 >= 0, timestamp.timeIntervalSince1970 < 4_102_444_800 else { throw LedgerError.invalid("交易日期无效。") }
            guard tngNotices.count < 5000 else { throw LedgerError.invalid("通知记录已达上限。") }
            if tngNotices.contains(where: { $0.kind == "unknown" && $0.body == text && $0.title == title && abs($0.date.timeIntervalSince(timestamp)) < 300 }) {
                return "相同未识别通知已保留，未重复添加。"
            }
            var notice = TNGNotice(body: text, title: title, date: timestamp, usesReceivedDate: true, kind: "unknown", status: "pending", cents: nil, party: nil)
            notice.reviewReason = "格式尚未识别；可能是付款、收款、充值或退款。请核对原文，未计入消费。"
            notice.sourceBank = financialProvider(title + " " + text) ?? "银行 / TNG"
            tngNotices.append(notice)
            return "交易通知已保留待确认，未计入消费。"
        }
        let timestamp = verified.transactionDate ?? date ?? now
        guard timestamp.timeIntervalSince1970 >= 0, timestamp.timeIntervalSince1970 < 4_102_444_800 else { throw LedgerError.invalid("交易金额或日期无效。") }
        let explicit = eventID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard explicit.count <= 500 else { throw LedgerError.invalid("交易金额或日期无效。") }
        let referenceKey = verified.reference.map { "bank:" + verified.sourceBank + ":" + verified.kind + ":" + (verified.accountSuffix ?? "") + ":" + $0 }
        let identity = referenceKey ?? (explicit.isEmpty ? nil : (verified.sourceBank == "TNG" ? explicit : verified.sourceBank + ":" + verified.kind + ":" + explicit))
        let eventKey = identity.map { "tng:" + SHA256.hash(data: Data($0.utf8)).map { String(format: "%02x", $0) }.joined() }
        if let eventKey, seenEvents.contains(eventKey) { return tr("相同交易标识已处理，未重复记录。", "This transaction ID was already processed.", "ID transaksi ini sudah diproses.") }
        guard tngNotices.count < 5000 else { throw reviewError("TNG 通知记录已达上限，请先导出备份并清理已处理通知。", "TNG inbox is full. Export a backup and clear processed notices.", "Peti TNG penuh. Eksport sandaran dan kosongkan notifikasi selesai.") }
        let parsed: TNGParsed? = verified
        let partyKey = friendKey(verified.party)
        let crossSourceDuplicate = expenses.contains { old in
            guard old.source != verified.sourceBank, old.cents == verified.cents else { return false }
            guard !partyKey.isEmpty, friendKey(old.merchant) == partyKey else { return false }
            return abs(old.date.timeIntervalSince(timestamp)) <= 120
        }
        let duplicate = tngNotices.contains { old in
            old.provider == verified.sourceBank && old.accountSuffix == verified.accountSuffix &&
            abs(old.date.timeIntervalSince(timestamp)) <= (verified.transactionDate != nil || date != nil ? 120 : 300) &&
            (friendKey(old.body) == friendKey(text) || (parsed != nil && old.kind == parsed?.kind && old.cents == parsed?.cents && friendKey(old.party ?? "") == friendKey(parsed?.party ?? "")))
        }
        var notice = TNGNotice(body: text, title: title, date: timestamp, usesReceivedDate: verified.transactionDate == nil && (verified.sourceBank != "TNG" || date == nil), kind: parsed?.kind ?? "unknown", status: "pending", cents: parsed?.cents, party: parsed?.party, possibleDuplicate: duplicate || crossSourceDuplicate, recipient: parsed?.recipient, sourceBank: verified.sourceBank == "TNG" ? nil : verified.sourceBank, accountSuffix: verified.accountSuffix, bankReference: verified.reference)
        if let parsed, !duplicate, !crossSourceDuplicate {
            if parsed.kind == "payment" {
                let entry = Expense(merchant: parsed.party, cents: parsed.cents, date: timestamp, category: merchantCategories[friendKey(parsed.party)] ?? guessCategory(parsed.party), source: parsed.sourceBank)
                expenses.append(entry); notice.expenseID = entry.id; notice.status = "recorded"
            } else if parsed.kind == "transfer" { notice.status = "transfer" }
        }
        tngNotices.append(notice)
        if let eventKey { seenEvents.insert(eventKey) }
        if notice.kind == "incoming" { return tr("收款已显示在账本，待确认用途；尚未抵扣欠款或计入收入。", "Incoming money is in your ledger for review; no debt or income changed.", "Wang diterima menunggu semakan; hutang dan pendapatan belum berubah.") }
        if duplicate || crossSourceDuplicate { return tr("疑似重复，已保留待确认，未再次计入消费。", "Possible duplicate retained for review, not added to spending.", "Kemungkinan pendua disimpan untuk semakan, tidak ditambah kepada belanja.") }
        if notice.status == "recorded" { return tr("已记消费：", "Expense recorded: ", "Belanja direkod: ") + money(notice.cents ?? 0) + " · " + (notice.party ?? "") }
        if notice.status == "transfer" { return tr("转出已显示在账本，尚未计入消费。", "Outgoing transfer is in your ledger, excluded from spending.", "Pindahan disimpan, tidak dikira sebagai belanja.") }
        return tr("通知已保存到待确认，未计入消费。", "Notification saved for review, excluded from spending.", "Notifikasi disimpan untuk semakan, tidak dikira sebagai belanja.")
    }
    mutating func confirmTNGExpense(id: String, merchant: String, cents: Int, date: Date, category: String) throws {
        guard let i = tngNotices.firstIndex(where: { $0.id == id }), tngNotices[i].expenseID == nil, tngNotices[i].kind != "incoming",
              cents > 0, cents <= 10_000_000_000, !merchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              merchant.count <= 200, categoryNames.contains(category), date.timeIntervalSince1970 >= 0, date.timeIntervalSince1970 < 4_102_444_800 else { throw LedgerError.invalid("付款或分账数据无效。") }
        let expense = Expense(merchant: merchant.trimmingCharacters(in: .whitespacesAndNewlines), cents: cents, date: date, category: category, source: tngNotices[i].provider)
        expenses.append(expense); tngNotices[i].expenseID = expense.id; tngNotices[i].status = "recorded"
    }
    mutating func excludeTNG(id: String) throws {
        guard let i = tngNotices.firstIndex(where: { $0.id == id }) else { return }
        if tngNotices[i].kind == "incoming" {
            guard tngNotices[i].status == "pending" else { throw LedgerError.invalid("Reopen incoming review before excluding") }
        }
        if let expenseID = tngNotices[i].expenseID, let entry = expenses.first(where: { $0.id == expenseID }) {
            guard entry.shares.isEmpty, (entry.refunds ?? []).isEmpty else {
                throw reviewError("此账目已有分账或退款，请先在账本处理，避免丢失记录。", "Resolve existing splits or refunds in the ledger first.", "Selesaikan bahagian atau pulangan dalam lejar dahulu.")
            }
            expenses.removeAll { $0.id == expenseID }
        }
        tngNotices[i].status = "ignored" // Keep linkage as a tombstone: no accidental replay.
    }
}

extension Ledger {
    mutating func resolveTNGIncoming(id: String, purpose: String, friend: String = "", date: Date, distinctConfirmed: Bool = false) throws {
        guard let i = tngNotices.firstIndex(where: { $0.id == id }), tngNotices[i].kind == "incoming",
              tngNotices[i].status == "pending", let cents = tngNotices[i].cents,
              ["repayment", "income", "ownTransfer", "ignored"].contains(purpose),
              date.timeIntervalSince1970 >= 0, date <= Date(),
              !tngNotices[i].possibleDuplicate || distinctConfirmed || purpose == "ignored" else {
            throw reviewError("请核对收款日期、用途及是否重复。", "Check receipt date, purpose and duplicate status.", "Semak tarikh, tujuan dan status pendua.")
        }
        var copy = self
        if purpose == "repayment" {
            let key = friendKey(friend)
            guard !key.isEmpty else { throw LedgerError.invalid("Select a friend") }
            let before = Set(copy.expenses.flatMap { $0.shares.flatMap { $0.repayments.map(\.id) } })
            try copy.batchRepay(friend: key, cents: cents, date: date)
            copy.tngNotices[i].repaymentIDs = copy.expenses.flatMap { $0.shares.flatMap { $0.repayments.map(\.id) } }.filter { !before.contains($0) }
            copy.tngNotices[i].resolvedFriend = key
        }
        copy.tngNotices[i].date = date
        copy.tngNotices[i].status = purpose
        self = try copy.validated()
    }
    mutating func reopenTNGIncoming(id: String) throws {
        guard let i = tngNotices.firstIndex(where: { $0.id == id }), tngNotices[i].kind == "incoming", tngNotices[i].status != "pending" else { throw LedgerError.invalid("Record changed") }
        var copy = self
        let ids = Set(copy.tngNotices[i].repaymentIDs ?? [])
        for e in copy.expenses.indices {
            for s in copy.expenses[e].shares.indices {
                copy.expenses[e].shares[s].repayments.removeAll { ids.contains($0.id) }
            }
        }
        copy.tngNotices[i].repaymentIDs = nil; copy.tngNotices[i].resolvedFriend = nil; copy.tngNotices[i].status = "pending"
        self = try copy.validated()
    }
}

struct SavingsEntry: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var cents: Int
    var date = Date()
}
struct SavingsGoal: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var name: String
    var target: Int
    var entries: [SavingsEntry] = []
    var deadline: Date? = nil
    var monthlyContribution: Int? = nil
    var balance: Int { entries.reduce(0) { $0 + $1.cents } }
    var progress: Double { min(1, Double(balance) / Double(max(1, target))) }
    func validate() throws {
        guard !id.isEmpty, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              name.count <= 80, target > 0, target <= 10_000_000_000, entries.count <= 10000,
              Set(entries.map(\.id)).count == entries.count else { throw LedgerError.invalid("储蓄目标无效 / Invalid savings goal") }
        if let deadline {
            guard deadline.timeIntervalSince1970.isFinite, deadline.timeIntervalSince1970 >= 0,
                  deadline.timeIntervalSince1970 <= 32_503_680_000 else { throw LedgerError.invalid("目标日期无效 / Invalid deadline") }
        }
        if let monthlyContribution {
            guard monthlyContribution > 0, monthlyContribution <= 10_000_000_000 else { throw LedgerError.invalid("每月金额无效 / Invalid monthly amount") }
        }
        var running = 0
        for entry in entries {
            guard !entry.id.isEmpty, entry.cents != 0, entry.cents >= -10_000_000_000, entry.cents <= 10_000_000_000,
                  entry.date.timeIntervalSince1970.isFinite, entry.date.timeIntervalSince1970 >= 0 else { throw LedgerError.invalid("储蓄记录无效 / Invalid savings entry") }
            running += entry.cents
            guard running >= 0, running <= 10_000_000_000 else { throw LedgerError.invalid("取出金额不能超过已存金额 / Withdrawal exceeds savings") }
        }
    }
    mutating func record(cents: Int) throws {
        var next = self
        next.entries.append(SavingsEntry(cents: cents))
        try next.validate()
        self = next
    }
}

// Integer cents; first contribution is one month after the preview date.
enum SavingsPlanMath {
    static func installments(until deadline: Date, from now: Date, calendar: Calendar = .current) -> Int {
        let start = calendar.startOfDay(for: now)
        let end = calendar.startOfDay(for: deadline)
        guard end > start else { return 0 }
        return max(1, calendar.dateComponents([.month], from: start, to: end).month ?? 0)
    }
    static func monthly(remaining: Int, installments: Int) -> Int {
        guard remaining > 0, installments > 0 else { return 0 }
        return remaining / installments + (remaining % installments == 0 ? 0 : 1)
    }
    static func months(remaining: Int, contribution: Int) -> Int {
        monthly(remaining: remaining, installments: contribution)
    }
}

/// Tracks arrivals across launches; an initial install establishes a baseline.
struct TNGReviewTracker {
    var observed: Set<String>?
    var pending: Set<String> = []
    mutating func observe(_ current: Set<String>) {
        pending.formIntersection(current)
        if let observed { pending.formUnion(current.subtracting(observed)) }
        observed = current
    }
}

enum LedgerTimelineItem: Identifiable {
    case expense(Expense), transfer(TNGNotice)
    var id: String { switch self { case .expense(let e): return "expense:" + e.id; case .transfer(let n): return "tng:" + n.id } }
    var date: Date { switch self { case .expense(let e): return e.date; case .transfer(let n): return n.date } }
}
struct LedgerDayGroup: Identifiable {
    let date: Date
    let entries: [LedgerTimelineItem]
    var id: Date { date }
}

extension LedgerTimelineItem {
    static func grouped(expenses: [Expense], transfers: [TNGNotice]) -> [LedgerDayGroup] {
        let items = expenses.map(Self.expense) + transfers.map(Self.transfer)
        return Dictionary(grouping: items, by: { Calendar.current.startOfDay(for: $0.date) })
            .map { LedgerDayGroup(date: $0.key, entries: $0.value.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date > $1.date }) }
            .sorted { $0.date > $1.date }
    }
}

struct FeedbackPresentationOwners {
    private(set) var modals: [UUID] = []
    mutating func present(_ id: UUID) {
        guard !modals.contains(id) else { return }
        modals.append(id)
    }
    mutating func dismiss(_ id: UUID) { modals.removeAll { $0 == id } }
    func isVisible(_ id: UUID?) -> Bool { modals.last == id }
}

/// Only the nine observed bank templates; unrelated notifications are never posted.
func parseFinancialNotification(_ body: String, title: String = "") -> TNGParsed? {
    if let bank = parseBankNotification(body, title: title) { return bank }
    return parseTNG(body, title: title)
}

func parseBankNotification(_ body: String, title: String = "") -> TNGParsed? {
    let text = body.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ").replacingOccurrences(of: "’", with: "'")
    let heading = title.trimmingCharacters(in: .whitespacesAndNewlines)
    struct Rule {
        let bank: String, title: String, kind: String, pattern: String
        let amount: Int
        var party = 0
        var account = 0
        var reference = 0
        var date = 0
        var format = ""
    }
    let rules: [Rule] = [
        Rule(bank: "Maybank", title: "Maybank2u: Funds Received", kind: "incoming", pattern: #"\AYou've just received RM\s*([0-9]+(?:\.[0-9]{2})?) in your account ending \*{3}([0-9]{4})\. REF: ([A-Za-z0-9]+)\z"#, amount: 1, account: 2, reference: 3),
        Rule(bank: "Maybank", title: "Maybank2u: Transfer", kind: "transfer", pattern: #"\ADuitNow of RM\s*([0-9]+(?:\.[0-9]{2})?) to (.{1,200}?)\. Mobile Number : \*{4}[0-9]{4}\. REF: ([A-Za-z0-9]+)\z"#, amount: 1, party: 2, reference: 3),
        Rule(bank: "Hong Leong", title: "Transaction Notice", kind: "incoming", pattern: #"\AHLB: You have received a transfer of RM\s*([0-9]+(?:\.[0-9]{2})?) into your bank account ending ([0-9]{4}) @([0-9]{2}/[0-9]{2}/[0-9]{4} [0-9]{2}:[0-9]{2}:[0-9]{2})\z"#, amount: 1, account: 2, date: 3, format: "dd/MM/yyyy HH:mm:ss"),
        Rule(bank: "Hong Leong", title: "Transaction Notice", kind: "transfer", pattern: #"\AYour transfer of RM\s*([0-9]+(?:\.[0-9]{2})?) to (.{1,200}?) is SUCCESSFUL\.\z"#, amount: 1, party: 2),
        Rule(bank: "AmBank", title: "AmOnline", kind: "incoming", pattern: #"\AAmBank/AmBank Islamic: (.{1,200}?) transferred MYR\s*([0-9]+(?:\.[0-9]{2})?) to your current/savings account \*{3}([0-9]{4}) on ([0-9]{2}/[0-9]{2}/[0-9]{2} [0-9]{2}:[0-9]{2})\z"#, amount: 2, party: 1, account: 3, date: 4, format: "dd/MM/yy HH:mm"),
        Rule(bank: "AmBank", title: "AmOnline", kind: "transfer", pattern: #"\AAmBank: RM\s*([0-9]+(?:\.[0-9]{2})?) DuitNow Transfer to \*{3}[0-9]{4}/(.{1,200}?) on ([0-9]{2}/[0-9]{2}/[0-9]{4} [0-9]{2}:[0-9]{2})\. For queries call AmBank\.\z"#, amount: 1, party: 2, date: 3, format: "dd/MM/yyyy HH:mm"),
        Rule(bank: "Ryt Bank", title: "Your money is in!", kind: "incoming", pattern: #"\AYou've received RM\s*([0-9]+(?:\.[0-9]{2})?) from (.{1,200}?) on ([0-9]{1,2}/[0-9]{1,2}/[0-9]{4}, [0-9]{1,2}:[0-9]{2} [AP]M) \(GMT\+8\)\.\z"#, amount: 1, party: 2, date: 3, format: "d/M/yyyy, h:mm a"),
        Rule(bank: "Ryt Bank", title: "Nice! Transfer settled!", kind: "transfer", pattern: #"\AYou've sent RM\s*([0-9]+(?:\.[0-9]{2})?) to (.{1,200}?) on ([0-9]{1,2}/[0-9]{1,2}/[0-9]{4}, [0-9]{1,2}:[0-9]{2} [AP]M) \(GMT\+8\) using your Main Account\.\z"#, amount: 1, party: 2, date: 3, format: "d/M/yyyy, h:mm a"),
        Rule(bank: "RHB", title: "Funds Received", kind: "incoming", pattern: #"\AYou've received MYR\s*([0-9]+(?:\.[0-9]{2})?) to your account ([0-9]{4}) on ([0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2})\.\z"#, amount: 1, account: 2, date: 3, format: "yyyy-MM-dd HH:mm:ss")
    ]
    for rule in rules {
        guard heading.isEmpty || heading == rule.title,
              let regex = try? NSRegularExpression(pattern: rule.pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { continue }
        func field(_ index: Int) -> String? {
            guard index > 0, let range = Range(match.range(at: index), in: text) else { return nil }
            return String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let amount = field(rule.amount), let cents = try? toCents(amount), cents > 0, cents <= 10_000_000_000 else { continue }
        var date: Date?
        if rule.date > 0 {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.timeZone = TimeZone(identifier: "Asia/Kuala_Lumpur")
            formatter.dateFormat = rule.format
            formatter.isLenient = false
            formatter.twoDigitStartDate = Date(timeIntervalSince1970: 946684800)
            guard let raw = field(rule.date), let parsed = formatter.date(from: raw), formatter.string(from: parsed) == raw else { continue }
            date = parsed
        }
        return TNGParsed(kind: rule.kind, cents: cents, party: field(rule.party) ?? "", sourceBank: rule.bank, transactionDate: date, accountSuffix: field(rule.account), reference: field(rule.reference))
    }
    return nil
}


/// A narrow undo delta: never replace the full ledger or automation history.
struct DeletedLedgerRecord {
    var notices: [TNGNotice]
    var before: [Expense]
    var after: [Expense]
}
extension Ledger {
    mutating func deleteAutomaticRecord(_ expected: TNGNotice) throws -> DeletedLedgerRecord {
        guard tngNotices.contains(expected) else { throw LedgerError.invalid("Record changed; reopen and try again.") }
        return try deleteLedgerRecord(noticeIDs: [expected.id], expenseID: expected.expenseID)
    }
    mutating func deleteLedgerExpense(_ expected: Expense) throws -> DeletedLedgerRecord {
        guard expenses.contains(expected) else { throw LedgerError.invalid("Record changed; reopen and try again.") }
        return try deleteLedgerRecord(noticeIDs: Set(tngNotices.filter { $0.expenseID == expected.id }.map(\.id)), expenseID: expected.id)
    }
    private mutating func deleteLedgerRecord(noticeIDs: Set<String>, expenseID: String?) throws -> DeletedLedgerRecord {
        var copy = self
        let notices = tngNotices.filter { noticeIDs.contains($0.id) || (expenseID != nil && $0.expenseID == expenseID) }
        let repayments = Set(notices.flatMap { $0.repaymentIDs ?? [] })
        let affected = expenses.filter { $0.id == expenseID || $0.shares.contains { $0.repayments.contains { repayments.contains($0.id) } } }
        copy.expenses.removeAll { $0.id == expenseID }
        for e in copy.expenses.indices {
            for s in copy.expenses[e].shares.indices {
                copy.expenses[e].shares[s].repayments.removeAll { repayments.contains($0.id) }
            }
        }
        let ids = Set(notices.map(\.id))
        copy.tngNotices.removeAll { ids.contains($0.id) }
        let affectedIDs = Set(affected.map(\.id))
        let delta = DeletedLedgerRecord(notices: notices, before: affected, after: copy.expenses.filter { affectedIDs.contains($0.id) })
        self = try copy.validated()
        return delta
    }
    mutating func restoreDeletedRecords(_ records: [DeletedLedgerRecord]) throws {
        var copy = self
        for record in records.reversed() {
            let ids = Set(record.before.map(\.id))
            let current = copy.expenses.filter { ids.contains($0.id) }
            guard current.count == record.after.count, current.allSatisfy({ record.after.contains($0) }),
                  !copy.tngNotices.contains(where: { n in record.notices.contains { $0.id == n.id } }) else {
                throw LedgerError.invalid(tr("关联账目已改变，无法安全撤销删除。", "Related entries changed; deletion cannot be safely undone.", "Rekod berkaitan berubah; pemadaman tidak dapat dibatalkan dengan selamat."))
            }
            copy.expenses.removeAll { ids.contains($0.id) }
            copy.expenses.append(contentsOf: record.before)
            copy.tngNotices.append(contentsOf: record.notices)
        }
        self = try copy.validated()
    }
}

// Shared fallback for banks and TNG. Never guesses a financial posting.
func financialProvider(_ text: String) -> String? {
    let key = text.lowercased()
    for (name, aliases) in [("Maybank", ["maybank", "maybank2u", "mae"]), ("Hong Leong", ["hong leong", "hlb"]), ("AmBank", ["ambank", "amonline"]), ("Ryt Bank", ["ryt"]), ("RHB", ["rhb"])] {
        if aliases.contains(where: { key.contains($0) }) { return name }
    }
    return nil
}
func shouldReviewFinancialNotification(_ body: String, title: String) -> Bool {
    let text = (title + " " + body).lowercased()
    let excluded = ["otp", "verification code", "one-time", "promotion", "promo", "offer:", "cashback offer", "reward points", "payment failed", "transaction failed", "unsuccessful", "declined", "pending payment"]
    guard !excluded.contains(where: { text.contains($0) }),
          text.range(of: #"(?:RM|MYR)\s*[0-9]+(?:\.[0-9]{2})?(?![0-9.])"#, options: [.regularExpression, .caseInsensitive]) != nil else { return false }
    return ["paid", "payment", "transfer", "received", "deducted", "credited", "debited", "refund", "reversed", "reload", "top-up", "top up", "purchase", "transaction"].contains(where: { text.contains($0) })
}
