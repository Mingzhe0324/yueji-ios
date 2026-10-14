import Foundation
import CryptoKit

enum LedgerError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { switch self { case .invalid(let text): return localizedError(text) } }
}
let categories = ["餐饮", "交通", "购物", "账单", "娱乐", "其他"]
func money(_ cents: Int) -> String { String(format: "RM %.2f", Double(cents) / 100) }
/// Direction of actual money in my account, independent of entry source or debt ownership.
enum AccountDirection: String {
    case incoming, outgoing, neutral
    func formattedAmount(_ cents: Int) -> String {
        let sign = self == .incoming ? "+" : (self == .outgoing ? "−" : "")
        return sign + money(cents)
    }
}
func toCents(_ value: String) throws -> Int {
    let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard text.range(of: #"^\d{1,8}(\.\d{1,2})?$"#, options: .regularExpression) != nil,
          let number = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")), number > 0 else {
        throw LedgerError.invalid("请输入大于零、最多两位小数的金额。")
    }
    return NSDecimalNumber(decimal: number * 100).intValue
}
func monthKey(_ date: Date, timeZone: TimeZone = .current) -> String {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    let parts = calendar.dateComponents([.year, .month], from: date)
    return String(format: "%04d-%02d", locale: Locale(identifier: "en_US_POSIX"), parts.year ?? 0, parts.month ?? 0)
}
/// Offline description classifier shared by every automatic payment source.
/// User merchant rules are applied by the caller before this fallback.
func guessCategory(_ name: String, description: String = "") -> String {
    func normalized(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
    }
    let text = " " + normalized(name + " " + description) + " "
    let rules: [(String, [String])] = [
        ("账单", ["electricity", "water bill", "utility bill", "broadband", "internet bill", "phone bill", "postpaid", "tenaga nasional", "tnb", "air selangor", "indah water", "iwk", "unifi", "maxis", "celcom", "digi", "celcomdigi", "u mobile", "yes telco", "rental", "rent", "房租", "电费", "水费", "网费", "电话费", "账单"]),
        ("餐饮", ["pan mee", "restaurant", "restoran", "kedai makan", "kopitiam", "mamak", "cafe", "coffee", "food", "grabfood", "foodpanda", "kfc", "mcdonald", "mcdonalds", "mcd", "zus", "tealive", "starbucks", "pizza", "bakery", "nasi", "ramen", "sushi", "餐", "饭", "咖啡", "面馆"]),
        ("交通", ["rfid", "toll", "parking", "petrol", "petronas", "petron", "shell", "caltex", "bhp", "grab", "rapidkl", "ktm", "lrt", "mrt", "油", "停车", "过路费"]),
        ("购物", ["shopee", "lazada", "supermarket", "groceries", "grocery", "lotus", "aeon", "mydin", "econsave", "jaya grocer", "99 speedmart", "watsons", "guardian", "uniqlo", "购物", "超市"]),
        ("娱乐", ["netflix", "spotify", "cinema", "gsc", "tgv", "steam", "disney", "youtube premium", "电影", "游戏"])
    ]
    for (category, words) in rules {
        for word in words {
            // Latin words use boundaries: "shellfish" must not match "shell".
            let isCJK = word.unicodeScalars.contains { $0.value >= 0x4E00 && $0.value <= 0x9FFF }
            if text.contains(isCJK ? word : " " + normalized(word) + " ") { return category }
        }
    }
    return "其他"
}

func automaticExpenseDetail(_ entry: Expense) -> String {
    let amount = entry.foreign.map { Currency.display($0.minor, $0.currency) + " (" + money(entry.cents) + ")" } ?? money(entry.cents)
    return sourceLabel(entry.source) + " · " + amount + "\n" + entry.merchant + " · " + entry.categorySummary + "\n" + dateLabel(entry.date, time: true) + entry.timeSourceSuffix
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
    var entryDescription: String? = nil
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
    var transactionReference: String? = nil
    var categoryAllocations: [CategoryAllocation]? = nil // Legacy backup input only; validated ledgers migrate it to items.
    var note: String? = nil
    var tags: [String]? = nil
    var timeSource: String? = nil // received, supplied, notification, edited; nil in older backups
    var paidByFriend: String? = nil // Missing in legacy records: paid by me.
    var items: [ExpenseItem]? = nil // Optional: automatic entries are saved before itemization.
    var reimbursement: ReimbursementClaim? = nil
    var charges: ExpenseCharges? = nil
    var accountDirection: AccountDirection { paidByFriend == nil ? .outgoing : .neutral }
    var displayName: String {
        let merchantName = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        if !merchantName.isEmpty { return merchantName }
        let description = entryDescription?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return description.isEmpty ? tr("未命名账目", "Untitled entry", "Rekod tanpa nama") : description
    }
    // Purchase presentation is distinct from account movement when a friend pays.
    var purchaseDisplayCents: Int { paidByFriend == nil ? cents : personal }
    var purchaseDirection: AccountDirection { .outgoing }
    var paidFromMyAccount: Int { paidByFriend == nil ? cents : 0 }
    var refunded: Int { (refunds ?? []).reduce(0) { $0 + $1.cents } }
    var personalRefund: Int { (refunds ?? []).reduce(0) { $0 + $1.personalCents } }
    var personal: Int { cents - shares.reduce(0) { $0 + $1.cents } - personalRefund }
    // A refund paid into my account must still be forwarded to the friend who funded it.
    var owingToPayer: Int { personal + (paidByFriend == nil ? 0 : (refunds ?? []).filter { $0.receivedByMe == true }.reduce(0) { $0 + $1.cents }) }
}
struct Ledger: Codable {
    var version = 6
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
    var settlements: [FriendSettlement] = []
    init(version: Int = 6, expenses: [Expense] = [], budgets: [String: Int] = [:], seenEvents: Set<String> = [], rates: [String: RateQuote] = [:], recurring: [RecurringExpense] = [], postedRecurring: Set<String> = []) {
        self.version = version; self.expenses = expenses; self.budgets = budgets; self.seenEvents = seenEvents
        self.rates = rates; self.recurring = recurring; self.postedRecurring = postedRecurring
    }
    enum CodingKeys: String, CodingKey { case version, expenses, budgets, seenEvents, rates, recurring, postedRecurring, dismissedDuplicates, automationEvents, merchantCategories, backupCreatedAt, customCategories, tripDefaults, tngNotices, savingsGoals, settlements }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let v = try c.decode(Int.self, forKey: .version)
        guard (1...6).contains(v) else { throw LedgerError.invalid("账本格式或版本无效。") }
        version = 6
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
        settlements = try c.decodeIfPresent([FriendSettlement].self, forKey: .settlements) ?? []
    }
    func validated() throws -> Ledger {
        try validateBookkeeping()
        guard savingsGoals.count <= 100, Set(savingsGoals.map(\.id)).count == savingsGoals.count else { throw LedgerError.invalid("储蓄目标无效 / Invalid savings goals") }
        for goal in savingsGoals { try goal.validate() }
        guard tngNotices.count <= 5000, tngNotices.reduce(0, { $0 + $1.body.utf8.count + $1.title.utf8.count }) <= 8_000_000, Set(tngNotices.map(\.id)).count == tngNotices.count else { throw LedgerError.invalid("账本格式或版本无效。") }
        for n in tngNotices {
            guard (n.resolution == nil || ["ownTransfer", "refund", "duplicate"].contains(n.resolution!)), (n.relatedRecordID?.count ?? 0) <= 200, (n.relatedRefundID?.count ?? 0) <= 200, (n.reviewReason?.count ?? 0) <= 1000, (n.aiSuggestion?.count ?? 0) <= 1000, validFinancialSource(n.provider),
                  (n.accountSuffix?.count ?? 0) <= 4, (n.bankReference?.count ?? 0) <= 500 else { throw LedgerError.invalid("Invalid notification source") }
            guard (n.recipient?.count ?? 0) <= 200, (n.resolvedFriend?.count ?? 0) <= 200,
                  (n.repaymentIDs?.count ?? 0) <= 50_000,
                  n.kind != "incoming" || (n.cents != nil && n.party != nil && n.expenseID == nil && ["pending", "ignored", "repayment", "income", "ownTransfer", "settlement"].contains(n.status)),
                  !["repayment", "income", "ownTransfer"].contains(n.status) || n.kind == "incoming" else { throw LedgerError.invalid("Invalid incoming record") }

            guard !n.id.isEmpty, !n.body.isEmpty, n.body.count <= 8000, n.title.count <= 500, (n.note?.count ?? 0) <= 2000,
                  n.date.timeIntervalSince1970 >= 0, n.date.timeIntervalSince1970 < 4_102_444_800,
                  ["payment", "transfer", "incoming", "unknown"].contains(n.kind), ["recorded", "transfer", "pending", "ignored", "repayment", "income", "ownTransfer", "settlement"].contains(n.status),
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
        guard version == 6, expenses.count <= 50_000, Set(expenses.map(\.id)).count == expenses.count,
              budgets.values.allSatisfy({ $0 >= 0 && $0 <= 10_000_000_000 }) else { throw LedgerError.invalid("账本格式或版本无效。") }
        guard rates.count <= 100, recurring.count <= 500, Set(recurring.map(\.id)).count == recurring.count else { throw LedgerError.invalid("账本格式或版本无效。") }
        for (code, quote) in rates { guard Currency.codes.contains(code), code != "MYR" else { throw LedgerError.invalid("币种无效。") }; try quote.validate() }
        for rule in recurring { try rule.validate(allowedCategories: categoryNames) }
        guard automationEvents.count <= 100, automationEvents.allSatisfy({ $0.date.timeIntervalSince1970.isFinite && $0.detail.count <= 2000 }) else { throw LedgerError.invalid("账本格式或版本无效。") }
        for e in expenses {
            if let payer = e.paidByFriend {
                guard !friendKey(payer).isEmpty, payer.count <= 200, e.shares.count == 1,
                      friendKey(e.shares[0].name) == friendKey(payer), e.shares[0].repayments.isEmpty,
                      (e.shares[0].returns ?? []).isEmpty else { throw settlementError("朋友付款请在你和付款人之间分摊，已有还款须先撤销。", "Split friend-paid purchases between you and the payer. Undo existing repayments before changing payer.", "Bahagikan belanja dibayar rakan antara anda dan pembayar. Batalkan bayaran sedia ada sebelum menukar pembayar.") }
            }
            if let fx = e.foreign { guard try fx.myrCents() == e.cents else { throw LedgerError.invalid("外币金额与换算金额不符。") } }
            guard !e.id.isEmpty, (e.entryDescription?.count ?? 0) <= 2000,
                  e.merchant.count <= 200, (e.transactionReference?.count ?? 0) <= 500, (e.receiptSummary?.count ?? 0) <= 20_000, e.cents > 0, e.cents <= 10_000_000_000,
                  (e.timeSource == nil || ["received", "supplied", "notification", "edited"].contains(e.timeSource!)),
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
        try validateSettlements()
        return try migratingLegacyCategorySplits()
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
        try requireUnsettledExpense(expected.id)
        guard let index = expenses.firstIndex(where: { $0.id == expected.id }),
              expenses[index] == expected else {
            throw LedgerError.invalid(tr("账目已改变或已删除，请重新打开后再试。", "Entry changed or was deleted. Reopen it and try again.", "Rekod berubah atau dipadam. Buka semula dan cuba lagi."))
        }
        expenses.remove(at: index)
    }

    mutating func addPayment(amount: Double, merchant: String, currency: String, date: Date, eventID: String?, description: String = "") throws -> Bool {
        guard description.count <= 2000 else { throw LedgerError.invalid("交易描述过长。") }
        let code = currency.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard Currency.codes.contains(code), amount.isFinite, amount > 0, amount <= 100_000_000,
              date.timeIntervalSince1970 >= 0, date.timeIntervalSince1970 < 4_102_444_800 else { throw LedgerError.invalid("交易金额或日期无效。") }
        let scale = Currency.scale(code)
        guard abs(amount * Double(scale) - (amount * Double(scale)).rounded()) < 0.00001 else { throw LedgerError.invalid("交易金额或日期无效。") }
        let minor = Int((amount * Double(scale)).rounded())
        let name = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 200 else { throw LedgerError.invalid("未取得商户名称，请检查快捷指令的输入。") }
        let explicit = eventID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard explicit.count <= 500 else { throw LedgerError.invalid("交易标识过长。") }
        // Preserve the v1 MYR fingerprint for migration-safe deduplication.
        let fingerprint = explicit.isEmpty ? "\(Int(date.timeIntervalSince1970))|\(name.lowercased())|\(minor)|\(code)" : explicit
        let key = SHA256.hash(data: Data(fingerprint.utf8)).map { String(format: "%02x", $0) }.joined()
        guard !seenEvents.contains(key) else { return false }
        let fx = try foreignAmount(minor: minor, code: code)
        let value = try fx?.myrCents() ?? minor
        if expenses.contains(where: { old in
            (old.source != "Apple Pay" || (explicit.isEmpty && old.transactionReference == nil)) && old.source != "手动" && old.source != "固定消费" &&
            old.cents == value && abs(old.date.timeIntervalSince(date)) <= 120 &&
            merchantIdentity(old.merchant) == merchantIdentity(name)
        }) {
            guard tngNotices.count < 5000 else { throw LedgerError.invalid("通知记录已达上限。") }
            var notice = TNGNotice(body: "Apple Pay: " + name + " " + money(value) + " " + description,
                                   title: "Apple Pay", date: date, usesReceivedDate: false, kind: "payment", status: "pending", cents: value, party: name, possibleDuplicate: true)
            notice.sourceBank = "Apple Pay"
            notice.bankReference = explicit.isEmpty ? nil : explicit
            notice.reviewReason = "与已有账目的金额、商户和时间相近，请核对是否同一笔。"
            tngNotices.append(notice)
            seenEvents.insert(key)
            return false
        }
        expenses.append(Expense(merchant: name, entryDescription: description.isEmpty ? nil : description, cents: value, date: date, category: merchantCategories[friendKey(name)] ?? guessCategory(name, description: description), source: "Apple Pay", foreign: fx, receiptSummary: description.isEmpty ? nil : description, transactionReference: explicit.isEmpty ? nil : explicit))
        seenEvents.insert(key)
        return true
    }
    mutating func repay(expenseID: String, shareID: String, cents: Int, date: Date) throws {
        guard let ei = expenses.firstIndex(where: { $0.id == expenseID }), let si = expenses[ei].shares.firstIndex(where: { $0.id == shareID }) else { throw LedgerError.invalid("找不到这笔分账，请重新打开。") }
        guard expenses[ei].paidByFriend == nil, cents > 0, cents <= outstanding(expense: expenses[ei], share: expenses[ei].shares[si]) else { throw reviewError("还款须大于零且不能超过尚欠金额。", "Repayment must be positive and no more than the balance.", "Bayaran balik mesti positif dan tidak melebihi baki.") }
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
    var resolution: String? = nil
    var relatedRecordID: String? = nil
    var relatedRefundID: String? = nil
    var reviewReason: String? = nil
    var aiSuggestion: String? = nil
    var sourceBank: String? = nil
    var accountSuffix: String? = nil
    var bankReference: String? = nil
    var note: String? = nil
    var settlementID: String? = nil
    var provider: String { sourceBank ?? "TNG" }
    var accountDirection: AccountDirection {
        switch kind { case "incoming": return .incoming; case "payment", "transfer": return .outgoing; default: return .neutral }
    }
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
    notice.accountDirection.formattedAmount(notice.cents ?? 0)
}
func notificationText(_ value: String) -> String {
    value.replacingOccurrences(of: "\u{200B}", with: "")
        .replacingOccurrences(of: "\u{FEFF}", with: "")
        .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
}
func notificationTitleKey(_ value: String) -> String {
    friendKey(notificationText(value)).replacingOccurrences(of: "’", with: "'")
        .trimmingCharacters(in: .punctuationCharacters)
}
let tngNotificationTitles = ["duitnow payment", "payment", "auto-debit payment", "successful toll payment", "transfer successful", "duitnow transfer is successful", "ka-ching! incoming money", "you've received money"]
let tngAppTitles = ["tng", "tng ewallet", "touch 'n go ewallet", "touch n go ewallet"]

func parseTNG(_ body: String, title: String = "") -> TNGParsed? {
    let suppliedTitle = notificationTitleKey(title)
    // A trigger may provide the app name instead of the notification heading.
    // The body must still match an entire verified transaction template.
    let titleKey = tngAppTitles.contains(suppliedTitle) ? "" : suppliedTitle
    guard titleKey.isEmpty || tngNotificationTitles.contains(titleKey) else { return nil }
    let text = notificationText(body)
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
        ("payment", "duitnow payment", #"\AYou have paid RM\s*((?:[0-9]{1,3}(?:,[0-9]{3})+|[0-9]+)(?:\.[0-9]{2})?) to (.{1,200}?)\.?\z"#),
        ("payment", "payment", #"\AYou have paid RM\s*((?:[0-9]{1,3}(?:,[0-9]{3})+|[0-9]+)(?:\.[0-9]{2})?) for (.{1,200}?)\.?\z"#),
        ("transfer", "transfer successful", #"\ARM\s*((?:[0-9]{1,3}(?:,[0-9]{3})+|[0-9]+)(?:\.[0-9]{2})?) has been successfully transferred to (.{1,200}?)\.?\z"#),
        ("transfer", "duitnow transfer is successful", #"\AYou have successfully transferred RM\s*((?:[0-9]{1,3}(?:,[0-9]{3})+|[0-9]+)(?:\.[0-9]{2})?) to (.{1,200}?)\.?\z"#)
    ]
    for (kind, expectedTitle, pattern) in patterns {
        guard titleKey.isEmpty || titleKey == expectedTitle || (kind == "payment" && ["payment", "duitnow payment", "auto-debit payment"].contains(titleKey)) else { continue }
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let amountRange = Range(match.range(at: 1), in: text), let nameRange = Range(match.range(at: 2), in: text),
              let cents = try? toCents(String(text[amountRange]).replacingOccurrences(of: ",", with: "")) else { continue }
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
            (notice.kind == "incoming" || notice.kind == "transfer" || notice.settlementID != nil || notice.status == "transfer") &&
            notice.status != "ignored" && notice.expenseID == nil &&
            Calendar.current.isDate(notice.date, equalTo: month, toGranularity: .month) &&
            (query.isEmpty || ((notice.party ?? "") + " " + (notice.recipient ?? "") + " " + notice.provider + " " + tngSignedAmount(notice)).localizedCaseInsensitiveContains(query))
        }.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date > $1.date }
    }
    /// Logs delivery independently from whether a supported transaction was recognized.
    /// Unknown transaction-like bodies are retained for review without posting expenses.
    mutating func processTNGNotification(body: String, title: String = "", date: Date?, eventID: String?, sourceApp: String? = nil) throws -> (accepted: Bool, message: String, expenseID: String?, noticeID: String?) {
        let previousCount = tngNotices.count
        var message = try receiveTNG(body: body, title: title, date: date, eventID: eventID, sourceApp: sourceApp)
        if tngNotices.count > previousCount, let notice = tngNotices.last, notice.status != "recorded" {
            let amount = notice.cents.map(money) ?? tr("金额待确认", "Amount to review", "Amaun untuk semakan")
            let party = notice.party ?? String(notice.body.prefix(100))
            message += "\n" + sourceLabel(notice.provider) + " · " + amount + "\n" + party + "\n" + dateLabel(notice.date, time: true)
            if notice.kind == "transfer" {
                let suggested = merchantCategories[friendKey(party)] ?? guessCategory(party, description: notice.body)
                message += "\n" + tr("建议分类（用途待确认）：", "Suggested category (purpose unconfirmed): ", "Cadangan kategori (tujuan belum disahkan): ") + categoryLabel(suggested)
            }
        }
        let parsed = parseFinancialNotification(body, title: title, sourceApp: sourceApp)
        let accepted = parsed != nil
        let savedNotice = tngNotices.count > previousCount ? tngNotices.last : nil
        let outcome: String
        if let notice = savedNotice {
            outcome = notice.status == "recorded" ? "saved" : (notice.possibleDuplicate ? "duplicate" : "pending")
        } else { outcome = accepted ? "duplicate" : "ignored" }
        logAutomation(source: savedNotice?.provider ?? parsed?.sourceBank ?? "银行 / TNG", outcome: outcome, detail: message)
        return (accepted, message, savedNotice?.expenseID, savedNotice?.id)
    }
    mutating func receiveTNG(body: String, title: String = "", date: Date?, eventID: String?, now: Date = Date(), sourceApp: String? = nil) throws -> String {
        if let sourceApp, !sourceApp.isEmpty, !validFinancialSource(sourceApp) { throw LedgerError.invalid("通知来源名称无效。") }
        let text = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 8000, title.count <= 500 else {
            throw reviewError("通知正文为空或过长，请把 TNG 通知的 Body 传入。", "Notification body is empty or too long. Pass the TNG notification Body.", "Teks notifikasi kosong atau terlalu panjang. Hantar Body notifikasi TNG.")
        }
        // Supported templates can post transactions; unknown financial text stays pending.
        guard let verified = parseFinancialNotification(text, title: title, sourceApp: sourceApp) else {
            guard shouldReviewFinancialNotification(text, title: title) else {
                return tr("已忽略：推广、验证码、失败或非交易通知。", "Ignored: promotion, OTP, failure or non-transaction notice.", "Diabaikan: promosi, OTP, kegagalan atau bukan transaksi.")
            }
            let timestamp = date ?? now
            let explicitReference = eventID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard explicitReference.count <= 500 else { throw LedgerError.invalid("交易标识过长。") }
            let reference = notificationReference(text) ?? (explicitReference.isEmpty ? nil : explicitReference)
            let provider = notificationProvider(sourceApp: sourceApp, title: title, body: text)
            if let reference, tngNotices.contains(where: { $0.provider == provider && $0.bankReference == reference }) {
                return tr("此交易编号的通知已保留，未重复添加。", "A notice with this transaction ID is already kept. No duplicate was added.", "Notifikasi dengan ID transaksi ini telah disimpan. Tiada pendua ditambah.")
            }
            guard timestamp.timeIntervalSince1970 >= 0, timestamp.timeIntervalSince1970 < 4_102_444_800 else { throw LedgerError.invalid("交易日期无效。") }
            guard tngNotices.count < 5000 else { throw LedgerError.invalid("通知记录已达上限。") }
            if tngNotices.contains(where: { $0.kind == "unknown" && $0.body == text && $0.title == title && abs($0.date.timeIntervalSince(timestamp)) < 300 }) {
                return tr("相同未识别通知已保留，未重复添加。", "The same unrecognised notification is already kept. No duplicate was added.", "Notifikasi tidak dikenal pasti yang sama telah disimpan. Tiada pendua ditambah.")
            }
            var notice = TNGNotice(body: text, title: title, date: timestamp, usesReceivedDate: true, kind: "unknown", status: "pending", cents: nil, party: nil)
            notice.reviewReason = financialReviewReason(text)
            notice.sourceBank = provider
            notice.cents = singleNotificationAmount(text)
            notice.bankReference = reference
            tngNotices.append(notice)
            return tr("交易通知已保留待确认，未计入消费。", "Transaction notification kept for review; excluded from spending.", "Notifikasi transaksi disimpan untuk semakan; tidak dikira sebagai belanja.")
        }
        let timestamp = verified.transactionDate ?? date ?? now
        guard timestamp.timeIntervalSince1970 >= 0, timestamp.timeIntervalSince1970 < 4_102_444_800 else { throw LedgerError.invalid("交易金额或日期无效。") }
        let explicit = eventID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard explicit.count <= 500 else { throw LedgerError.invalid("交易金额或日期无效。") }
        let referenceKey = verified.reference.map { "bank:" + verified.sourceBank + ":" + verified.kind + ":" + (verified.accountSuffix ?? "") + ":" + $0 }
        let identity = referenceKey ?? (explicit.isEmpty ? nil : (verified.sourceBank == "TNG" ? explicit : verified.sourceBank + ":" + verified.kind + ":" + explicit))
        let eventKey = identity.map { "tng:" + SHA256.hash(data: Data($0.utf8)).map { String(format: "%02x", $0) }.joined() }
        // A constant Shortcut input must not suppress unrelated payments forever.
        // Verified bank references remain authoritative; external IDs also require matching content.
        if let eventKey, seenEvents.contains(eventKey), verified.reference != nil || !tngNotices.contains(where: {
            $0.provider == verified.sourceBank && $0.bankReference == explicit
        }) || tngNotices.contains(where: {
            $0.provider == verified.sourceBank && $0.bankReference == explicit &&
            $0.kind == verified.kind && $0.cents == verified.cents &&
            merchantIdentity($0.party ?? "") == merchantIdentity(verified.party)
        }) { return tr("相同交易标识及交易内容已处理，未重复记录。", "This transaction was already processed.", "Transaksi ini sudah diproses.") }
        guard tngNotices.count < 5000 else { throw reviewError("TNG 通知记录已达上限，请先导出备份并清理已处理通知。", "TNG inbox is full. Export a backup and clear processed notices.", "Peti TNG penuh. Eksport sandaran dan kosongkan notifikasi selesai.") }
        let parsed: TNGParsed? = verified
        let partyKey = merchantIdentity(verified.party)
        let suppliedReference = verified.reference ?? (explicit.isEmpty ? nil : explicit)
        let crossSourceDuplicate = expenses.contains { old in
            guard old.source != verified.sourceBank, old.source != "手动", old.source != "固定消费", old.cents == verified.cents else { return false }
            let sameName = !partyKey.isEmpty && merchantIdentity(old.merchant) == partyKey
            let sameReference = suppliedReference.map { $0.count >= 6 && old.transactionReference == $0 } ?? false
            return (sameName || sameReference) && abs(old.date.timeIntervalSince(timestamp)) <= 120
        }
        let duplicate = tngNotices.contains { old in
            guard old.provider == verified.sourceBank, old.accountSuffix == verified.accountSuffix else { return false }
            if let previous = old.bankReference, let current = suppliedReference, previous != current { return false }
            let window: TimeInterval = verified.transactionDate != nil || date != nil ? 120 : 300
            guard abs(old.date.timeIntervalSince(timestamp)) <= window else { return false }
            if friendKey(old.body) == friendKey(text) { return true }
            return old.kind == verified.kind && old.cents == verified.cents && merchantIdentity(old.party ?? "") == partyKey
        }
        var notice = TNGNotice(body: text, title: title, date: timestamp, usesReceivedDate: verified.transactionDate == nil && (verified.sourceBank != "TNG" || date == nil), kind: parsed?.kind ?? "unknown", status: "pending", cents: parsed?.cents, party: parsed?.party, possibleDuplicate: duplicate || crossSourceDuplicate, recipient: parsed?.recipient, sourceBank: verified.sourceBank == "TNG" ? nil : verified.sourceBank, accountSuffix: verified.accountSuffix, bankReference: suppliedReference)
        if let parsed, !duplicate, !crossSourceDuplicate {
            if parsed.kind == "payment" {
                let entry = Expense(merchant: parsed.party, cents: parsed.cents, date: timestamp, category: merchantCategories[friendKey(parsed.party)] ?? guessCategory(parsed.party, description: title + " " + text), source: parsed.sourceBank, transactionReference: suppliedReference, timeSource: verified.transactionDate == nil ? "notification" : "supplied")
                expenses.append(entry); notice.expenseID = entry.id; notice.status = "recorded"
            } else if parsed.kind == "transfer" { notice.status = "transfer" }
        }
        tngNotices.append(notice)
        if let eventKey { seenEvents.insert(eventKey) }
        if notice.kind == "incoming" { return tr("收款已显示在账本，待确认用途；尚未抵扣欠款或计入收入。", "Incoming money is in your ledger for review; no debt or income changed.", "Wang diterima menunggu semakan; hutang dan pendapatan belum berubah.") }
        if duplicate || crossSourceDuplicate { return tr("疑似重复，已保留待确认，未再次计入消费。", "Possible duplicate retained for review, not added to spending.", "Kemungkinan pendua disimpan untuk semakan, tidak ditambah kepada belanja.") }
        if notice.status == "recorded", let expenseID = notice.expenseID,
           let entry = expenses.first(where: { $0.id == expenseID }) {
            return tr("已记消费\n", "Expense recorded\n", "Belanja direkod\n") + automaticExpenseDetail(entry)
        }
        if notice.status == "transfer" { return tr("转出已显示在账本，尚未计入消费。", "Outgoing transfer is in your ledger, excluded from spending.", "Pindahan disimpan, tidak dikira sebagai belanja.") }
        return tr("通知已保存到待确认，未计入消费。", "Notification saved for review, excluded from spending.", "Notifikasi disimpan untuk semakan, tidak dikira sebagai belanja.")
    }
    mutating func confirmTNGExpense(id: String, merchant: String, cents: Int, date: Date, category: String, remember: Bool = false, items: [ExpenseItem] = []) throws {
        guard let i = tngNotices.firstIndex(where: { $0.id == id }), tngNotices[i].expenseID == nil, tngNotices[i].kind != "incoming", ["pending", "transfer"].contains(tngNotices[i].status),
              cents > 0, cents <= 10_000_000_000, !merchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              merchant.count <= 200, categoryNames.contains(category), date.timeIntervalSince1970 >= 0, date.timeIntervalSince1970 < 4_102_444_800 else { throw LedgerError.invalid("付款或分账数据无效。") }
        var expense = Expense(merchant: merchant.trimmingCharacters(in: .whitespacesAndNewlines), cents: cents, date: date, category: category, source: tngNotices[i].provider, transactionReference: tngNotices[i].bankReference)
        expense.timeSource = date == tngNotices[i].date ? (tngNotices[i].usesReceivedDate ? (tngNotices[i].provider == "Apple Pay" ? "received" : "notification") : "supplied") : "edited"
        expense.note = tngNotices[i].note
        expense = try expense.replacingItems(items, allowedCategories: categoryNames)
        expenses.append(expense); tngNotices[i].expenseID = expense.id; tngNotices[i].status = "recorded"
        if remember && items.isEmpty { merchantCategories[friendKey(expense.merchant)] = category }
    }
    mutating func excludeTNG(id: String) throws {
        guard let i = tngNotices.firstIndex(where: { $0.id == id }) else { return }
        guard tngNotices[i].settlementID == nil else { throw settlementError("请先在结算详情撤销结算。", "Undo the settlement from its details first.", "Batalkan penyelesaian daripada butirannya dahulu.") }
        guard tngNotices[i].resolution == nil else { throw LedgerError.invalid("请先撤销已有退款或转账关联。") }
        if tngNotices[i].kind == "incoming" {
            guard tngNotices[i].status == "pending" else { throw LedgerError.invalid("Reopen incoming review before excluding") }
        }
        if let expenseID = tngNotices[i].expenseID, let entry = expenses.first(where: { $0.id == expenseID }) {
            guard entry.shares.isEmpty, (entry.refunds ?? []).isEmpty, entry.reimbursement == nil, entry.charges == nil else {
                throw reviewError("此账目已有分账、退款、报销或税费，请先在账本处理，避免丢失记录。", "Resolve existing splits, refunds, reimbursement or charges in the ledger first.", "Selesaikan bahagian, pulangan, tuntutan atau caj dalam lejar dahulu.")
            }
            expenses.removeAll { $0.id == expenseID }
            tngNotices[i].note = entry.note
        }
        tngNotices[i].status = "ignored" // Keep linkage as a tombstone: no accidental replay.
    }
    mutating func reopenExcludedNotice(id: String) throws {
        guard let i = tngNotices.firstIndex(where: { $0.id == id }),
              tngNotices[i].status == "ignored", tngNotices[i].resolution == nil else {
            throw LedgerError.invalid("通知已改变；有关联的记录请先撤销关联。")
        }
        if let linked = tngNotices[i].expenseID, expenses.contains(where: { $0.id == linked }) {
            throw LedgerError.invalid("关联消费仍存在，请先核对，避免重复入账。")
        }
        // Explicit user action reopens review, never silently recreates spending.
        tngNotices[i].expenseID = nil
        tngNotices[i].status = tngNotices[i].kind == "transfer" ? "transfer" : "pending"
    }
    mutating func setNoticeNote(id: String, note: String) throws {
        guard note.count <= 2000, let i = tngNotices.firstIndex(where: { $0.id == id }) else {
            throw LedgerError.invalid("备注最多 2000 字，或通知已删除。")
        }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        tngNotices[i].note = trimmed.isEmpty ? nil : trimmed
        if let linked = tngNotices[i].expenseID, let e = expenses.firstIndex(where: { $0.id == linked }) {
            expenses[e].note = tngNotices[i].note
        }
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
        if purpose != "ignored" { try requireUnusedPaymentReference(tngNotices[i]) }
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
        guard tngNotices.first(where: { $0.id == id })?.settlementID == nil else { throw settlementError("请先在结算详情撤销结算。", "Undo the settlement from its details first.", "Batalkan penyelesaian daripada butirannya dahulu.") }
        if tngNotices.first(where: { $0.id == id })?.resolution != nil {
            try reopenResolvedNotice(id: id); return
        }
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
    case expense(Expense), transfer(TNGNotice), settlement(FriendSettlement)
    var id: String { switch self { case .expense(let e): return "expense:" + e.id; case .transfer(let n): return "tng:" + n.id; case .settlement(let s): return "settlement:" + s.id } }
    var date: Date { switch self { case .expense(let e): return e.date; case .transfer(let n): return n.date; case .settlement(let s): return s.date } }
}
struct LedgerDayGroup: Identifiable {
    let date: Date
    let entries: [LedgerTimelineItem]
    var id: Date { date }
}

extension LedgerTimelineItem {
    static func grouped(expenses: [Expense], transfers: [TNGNotice], settlements: [FriendSettlement] = []) -> [LedgerDayGroup] {
        // A linked bank receipt already represents the payment. Never show a second cash record.
        let manual = settlements.filter { $0.active && $0.paymentNoticeID == nil }
        let items = expenses.map(Self.expense) + transfers.map(Self.transfer) + manual.map(Self.settlement)
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
private func parseKnownFinancialNotification(_ body: String, title: String = "") -> TNGParsed? {
    if let bank = parseBankNotification(body, title: title) { return bank }
    if let tng = parseTNG(body, title: title) { return tng }
    // Some automations pass Title + newline + Body as one value.
    // Only unwrap an exact known title and still require a complete verified body.
    let lines = body.split(separator: "\n", maxSplits: 1).map(String.init)
    if lines.count == 2 {
        let heading = lines[0].trimmingCharacters(in: .whitespacesAndNewlines)
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || friendKey(title) == friendKey(heading) {
            if let parsed = parseBankNotification(lines[1], title: heading) ?? parseTNG(lines[1], title: heading) { return parsed }
        }
    }
    // TNG title and body may also arrive joined by spaces or with an app-name
    // heading. Strip only a known title at the start; never scan arbitrary prose.
    let text = notificationText(body)
    let suppliedTitle = notificationTitleKey(title)
    for heading in tngNotificationTitles {
        guard suppliedTitle.isEmpty || suppliedTitle == heading || tngAppTitles.contains(suppliedTitle),
              text.lowercased().hasPrefix(heading + " ") else { continue }
        let remainder = String(text.dropFirst(heading.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        if let parsed = parseTNG(remainder, title: heading) { return parsed }
    }
    return nil
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
        guard expected.settlementID == nil else { throw settlementError("请先撤销此付款关联的结算，再删除银行记录。", "Undo the linked settlement before deleting this bank payment.", "Batalkan penyelesaian dipautkan sebelum memadam bayaran bank ini.") }
        guard expected.resolution != "refund", expected.resolution != "ownTransfer" else { throw LedgerError.invalid("请先在通知详情撤销关联，再删除通知。") }
        return try deleteLedgerRecord(noticeIDs: [expected.id], expenseID: expected.expenseID)
    }
    mutating func deleteLedgerExpense(_ expected: Expense) throws -> DeletedLedgerRecord {
        try requireUnsettledExpense(expected.id)
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
/// Removes formatting and common legal suffixes only; no fuzzy name matching.
func merchantIdentity(_ name: String) -> String {
    let words = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
    return words.filter { !["sdn", "bhd", "berhad", "ltd", "limited"].contains($0) }.joined(separator: " ")
}
func singleNotificationAmount(_ body: String) -> Int? {
    let pattern = #"(?i)(?<![A-Za-z0-9])(?:RM|MYR)\s*((?:[0-9]{1,3}(?:,[0-9]{3})+|[0-9]+)(?:\.[0-9]{2})?)(?![0-9.,])"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
    let matches = regex.matches(in: body, range: NSRange(body.startIndex..., in: body))
    guard matches.count == 1, let range = Range(matches[0].range(at: 1), in: body) else { return nil }
    return try? toCents(String(body[range]).replacingOccurrences(of: ",", with: ""))
}
func notificationReference(_ body: String) -> String? {
    let pattern = #"(?i)\b(?:ref(?:erence)?|transaction\s+id)\s*[:#]\s*([A-Z0-9-]{3,100})"#
    guard let regex = try? NSRegularExpression(pattern: pattern),
          let match = regex.firstMatch(in: body, range: NSRange(body.startIndex..., in: body)),
          let range = Range(match.range(at: 1), in: body) else { return nil }
    return String(body[range])
}

extension Ledger {
    /// Atomic user-confirmed resolution. Original notification text is retained.
    mutating func resolveNotice(id: String, purpose: String, party: String, cents: Int, date: Date,
                                category: String = "其他", remember: Bool = false, relatedID: String? = nil, items: [ExpenseItem] = []) throws {
        guard let i = tngNotices.firstIndex(where: { $0.id == id }),
              ["pending", "transfer"].contains(tngNotices[i].status), tngNotices[i].expenseID == nil,
              cents > 0, cents <= 10_000_000_000, date.timeIntervalSince1970 >= 0, date <= Date(),
              !party.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, party.count <= 200 else {
            throw LedgerError.invalid("通知已处理，或金额、名称、日期无效。")
        }
        var copy = self
        copy.tngNotices[i].cents = cents
        copy.tngNotices[i].party = party
        copy.tngNotices[i].date = date
        switch purpose {
        case "expense":
            guard copy.tngNotices[i].kind != "incoming" else { throw LedgerError.invalid("收款不能记为支出。") }
            try copy.confirmTNGExpense(id: id, merchant: party, cents: cents, date: date, category: category, remember: remember, items: items)
        case "income":
            copy.tngNotices[i].kind = "incoming"
            copy.tngNotices[i].status = "pending"
            try copy.resolveTNGIncoming(id: id, purpose: "income", date: date, distinctConfirmed: true)
        case "ownTransfer":
            copy.tngNotices[i].status = "ignored"
            copy.tngNotices[i].resolution = "ownTransfer"
            if let relatedID, !relatedID.isEmpty {
                guard let j = copy.tngNotices.firstIndex(where: { $0.id == relatedID }), j != i,
                      ["pending", "transfer"].contains(copy.tngNotices[j].status), copy.tngNotices[j].expenseID == nil,
                      copy.tngNotices[j].cents == cents else { throw LedgerError.invalid("关联通知已变化或金额不同，请重新选择。") }
                copy.tngNotices[j].status = "ignored"
                copy.tngNotices[j].resolution = "ownTransfer"
                copy.tngNotices[j].relatedRecordID = id
                copy.tngNotices[i].relatedRecordID = relatedID
            }
        case "refund":
            guard let relatedID else { throw LedgerError.invalid("请选择原消费。") }
            try copy.addRefund(expenseID: relatedID, cents: cents, date: date, receivedByMe: true)
            guard let entry = copy.expenses.first(where: { $0.id == relatedID }), let refund = entry.refunds?.last else { throw LedgerError.invalid("退款保存失败。") }
            copy.tngNotices[i].status = "ignored"
            copy.tngNotices[i].resolution = "refund"
            copy.tngNotices[i].relatedRecordID = relatedID
            copy.tngNotices[i].relatedRefundID = refund.id
        default: throw LedgerError.invalid("请选择有效用途。")
        }
        copy.logAutomation(source: copy.tngNotices[i].provider, outcome: "resolved", detail: purpose + " · " + money(cents) + " · " + party)
        self = try copy.validated()
    }
    mutating func dismissDuplicateNotice(id: String, expenseID: String) throws {
        guard let i = tngNotices.firstIndex(where: { $0.id == id }), tngNotices[i].status == "pending",
              tngNotices[i].expenseID == nil, let entry = expenses.first(where: { $0.id == expenseID }),
              entry.cents == tngNotices[i].cents else { throw LedgerError.invalid("通知或账目已改变。") }
        tngNotices[i].status = "ignored"
        tngNotices[i].resolution = "duplicate"
        tngNotices[i].relatedRecordID = expenseID
    }
    mutating func reopenResolvedNotice(id: String) throws {
        guard let i = tngNotices.firstIndex(where: { $0.id == id }), let resolution = tngNotices[i].resolution else { throw LedgerError.invalid("通知已改变。") }
        var copy = self
        if resolution == "refund", let entryID = copy.tngNotices[i].relatedRecordID, let refundID = copy.tngNotices[i].relatedRefundID {
            try copy.removeRefund(expenseID: entryID, refundID: refundID)
        }
        if resolution == "ownTransfer", let otherID = copy.tngNotices[i].relatedRecordID,
           let j = copy.tngNotices.firstIndex(where: { $0.id == otherID && $0.relatedRecordID == id }) {
            copy.tngNotices[j].status = "pending"; copy.tngNotices[j].resolution = nil; copy.tngNotices[j].relatedRecordID = nil
        }
        copy.tngNotices[i].status = "pending"; copy.tngNotices[i].resolution = nil
        copy.tngNotices[i].relatedRecordID = nil; copy.tngNotices[i].relatedRefundID = nil
        self = try copy.validated()
    }
}


struct CategoryAllocation: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var category: String
    var cents: Int
}
struct ExpenseItem: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var name: String
    var cents: Int
    var category: String
    var quantity: Int? = nil // Missing in old records means one, without rewriting their amounts.
    var ownership: ItemOwnership? = nil // Missing preserves the original whole-transaction split.
    var count: Int { quantity ?? 1 }
    var unitCents: Int { cents / max(1, count) }
    var personalGross: Int { ownership.map { cents - $0.friendAmounts(cents: cents).reduce(0, +) } ?? cents }
    func friendGross(_ name: String) -> Int {
        guard let ownership, let index = ownership.friends.firstIndex(where: { friendKey($0) == friendKey(name) }) else { return 0 }
        return ownership.friendAmounts(cents: cents)[index]
    }
}
struct ItemOwnership: Codable, Equatable {
    var includesMe: Bool
    var friends: [String]
    var label: String {
        let names = (includesMe ? [tr("我", "Me", "Saya")] : []) + friends
        return names.isEmpty ? tr("未选择", "Not selected", "Belum dipilih") : names.joined(separator: tr("、", ", ", ", "))
    }
    func friendAmounts(cents: Int) -> [Int] { equalShares(total: cents, count: friends.count, includeMe: includesMe) }
    func validate() throws {
        guard includesMe || !friends.isEmpty, friends.count <= 100,
              friends.allSatisfy({ !friendKey($0).isEmpty && $0.count <= 200 }),
              Set(friends.map(friendKey)).count == friends.count else {
            throw reviewError("请选择物品归属，朋友姓名不能重复。", "Choose who the item belongs to, with distinct friend names.", "Pilih pemilik item dengan nama rakan yang berbeza.")
        }
    }
}
struct ExpenseItemPreview: Equatable {
    let names: String
    let remaining: Int
    var moreLabel: String { tr("另有 \(remaining) 件", "+\(remaining) more", "+\(remaining) lagi") }
}
struct RepaymentPurchasePreview: Equatable {
    let names: String
    let remaining: Int
    var label: String {
        names + (remaining > 0 ? tr(" · 另 \(remaining) 笔", " · +\(remaining) more", " · +\(remaining) lagi") : "")
    }
    static func make(_ entries: [Expense]) -> RepaymentPurchasePreview? {
        var seen = Set<String>()
        let purchases = entries.filter { seen.insert($0.id).inserted }
        guard !purchases.isEmpty else { return nil }
        let names = purchases.prefix(2).map { entry -> String in
            let description = (entry.entryDescription ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let detail: String? = !description.isEmpty ? description : entry.itemPreview.map { $0.names + ($0.remaining > 0 ? " · " + $0.moreLabel : "") }
            guard let detail, detail != entry.displayName else { return entry.displayName }
            let merchant = entry.merchant.trimmingCharacters(in: .whitespacesAndNewlines)
            return merchant.isEmpty ? detail : merchant + " · " + detail
        }.joined(separator: "； ")
        return RepaymentPurchasePreview(names: names, remaining: max(0, purchases.count - 2))
    }
}
extension Expense {
    /// Only actual saved purchase names belong in the row, never inferred categories.
    var itemPreview: ExpenseItemPreview? {
        let names = (items ?? []).map { $0.name.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ") }
            .filter { !$0.isEmpty }
        guard !names.isEmpty else { return nil }
        return ExpenseItemPreview(names: names.prefix(2).joined(separator: " · "), remaining: max(0, names.count - 2))
    }
    var hasLegacyCategorySplits: Bool { !(categoryAllocations ?? []).isEmpty }

    /// Preserve order and capacities so proportional shares/refunds keep every cent.
    /// Legacy splits did not store purchase names; retain each category as its name.
    func migratingLegacyCategorySplits() throws -> Expense {
        guard hasLegacyCategorySplits else { return self }
        try validateLegacyCategorySplits()
        guard (items ?? []).isEmpty else {
            throw reviewError("旧分类拆分与物品明细不能同时存在。", "Legacy category splits and items cannot coexist.", "Pecahan kategori lama dan item tidak boleh wujud serentak.")
        }
        let parts = categoryAllocations ?? []
        var reservedIDs = Set(parts.filter { $0.id.count <= 200 }.map(\.id))
        var copy = self
        copy.items = parts.enumerated().map { index, part in
            var itemID = part.id
            // Older allocation IDs had no length cap. Preserve ordinary IDs and
            // derive stable, collision-free item IDs for oversized legacy inputs.
            if itemID.count > 200 {
                let digest = SHA256.hash(data: Data(itemID.utf8)).map { String(format: "%02x", $0) }.joined()
                itemID = "legacy-\(index)-" + digest
                while reservedIDs.contains(itemID) { itemID += "_" }
                reservedIDs.insert(itemID)
            }
            return ExpenseItem(id: itemID, name: part.category, cents: part.cents, category: part.category)
        }
        copy.categoryAllocations = nil
        try copy.validateItems()
        return copy
    }

    func validateLegacyCategorySplits(allowedCategories: [String]? = nil) throws {
        guard let parts = categoryAllocations, !parts.isEmpty else { return }
        guard (2...20).contains(parts.count), Set(parts.map(\.id)).count == parts.count,
              Set(parts.map(\.category)).count == parts.count,
              parts.allSatisfy({ !$0.id.isEmpty && !$0.category.isEmpty && $0.category.count <= 200
                  && (allowedCategories?.contains($0.category) ?? true) && $0.cents > 0 && $0.cents <= 10_000_000_000 }),
              parts.reduce(0, { $0 + $1.cents }) == cents else {
            throw LedgerError.invalid("分类金额合计必须等于付款 MYR 总额，分类不能重复。")
        }
    }

    var allocatedCategories: [CategoryAllocation] {
        if let items, !items.isEmpty {
            return chargedItems.map { CategoryAllocation(id: $0.id, category: $0.category, cents: $0.cents) }
        }
        if let parts = categoryAllocations, !parts.isEmpty { return parts }
        return [CategoryAllocation(id: "single", category: category, cents: cents)]
    }
    var categorySummary: String {
        var seen = Set<String>()
        return allocatedCategories.filter { seen.insert($0.category).inserted }.map { categoryLabel($0.category) }.joined(separator: " / ")
    }
    var personalItemAmounts: [String: Int] {
        guard let items, !items.isEmpty else { return [:] }
        let byItem = usesItemOwnership
        let amounts = (try? allocateRefund(personal, capacities: chargedItems.map { byItem ? $0.personalGross : $0.cents })) ?? Array(repeating: 0, count: items.count)
        return Dictionary(uniqueKeysWithValues: zip(items, amounts).map { ($0.0.id, $0.1) })
    }
    func validateItems(allowedCategories: [String]? = nil) throws {
        guard let items, !items.isEmpty else { return }
        guard items.count <= 100, Set(items.map(\.id)).count == items.count,
              (categoryAllocations ?? []).isEmpty,
              items.allSatisfy({ !$0.id.isEmpty && $0.id.count <= 200 && !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.name.count <= 200
                  && !$0.category.isEmpty && $0.category.count <= 200 && (allowedCategories?.contains($0.category) ?? true)
                  && (1...999).contains($0.count) && $0.cents % $0.count == 0
                  && $0.cents > 0 && $0.cents <= 10_000_000_000 }),
              items.reduce(0, { $0 + $1.cents }) == itemSubtotalCents else {
            throw reviewError("请填写每件物品的名称、正数金额和分类；物品合计必须等于税前小计（未填税费时为交易总额）。", "Enter a name, positive amount and category for each item. Items must equal the subtotal, or the payment total when no charges are entered.", "Isi nama, amaun positif dan kategori setiap item. Jumlah item mesti sama dengan subtotal, atau jumlah bayaran tanpa caj.")
        }
        if usesItemOwnership {
            guard items.allSatisfy({ $0.ownership != nil }) else {
                throw reviewError("请为每件物品选择归属，或全部沿用整笔分账。", "Assign every item, or keep the whole-transaction split for all items.", "Tetapkan pemilik setiap item atau gunakan pembahagian transaksi untuk semua item.")
            }
            for item in items { try item.ownership?.validate() }
            let expected = itemFriendTotals
            guard shares.allSatisfy({ $0.cents == expected[friendKey($0.name), default: 0] }),
                  expected.allSatisfy({ key, amount in shares.contains { friendKey($0.name) == key && $0.cents == amount } }) else {
                throw reviewError("物品归属与分账金额不一致，请重新编辑物品。", "Item ownership and shares do not match. Edit the items again.", "Pemilikan item dan bahagian tidak sepadan. Edit item semula.")
            }
        }
    }
    /// Allocate net spending within the selected person's item capacities; legacy entries retain proportional splits.
    func categoryDistribution(total: Int, friend: String? = nil) -> [String: Int] {
        let parts = allocatedCategories
        guard total >= 0, total <= cents, !parts.isEmpty else { return [:] }
        let capacities = usesItemOwnership ? chargedItems.map { item in friend.map { item.friendGross($0) } ?? item.personalGross } : parts.map(\.cents)
        let amounts = (try? allocateRefund(total, capacities: capacities)) ?? Array(repeating: 0, count: parts.count)
        var result: [String: Int] = [:]
        for (part, amount) in zip(parts, amounts) { result[part.category, default: 0] += amount }
        return result
    }
    func personalAmount(category name: String) -> Int { categoryDistribution(total: personalSpending)[name] ?? 0 }
    func hasCategory(_ name: String) -> Bool { allocatedCategories.contains { $0.category == name } }
}
extension Ledger {
    func validateBookkeeping() throws {
        for e in expenses {
            try e.validateCharges()
            try e.validateItems(allowedCategories: categoryNames)
            try e.validateReimbursement()
            guard (e.note?.count ?? 0) <= 2000, (e.tags?.count ?? 0) <= 20,
                  (e.tags ?? []).allSatisfy({ !friendKey($0).isEmpty && $0.count <= 40 }),
                  Set((e.tags ?? []).map(friendKey)).count == (e.tags?.count ?? 0) else { throw LedgerError.invalid("备注或标签无效。") }
            try e.validateLegacyCategorySplits(allowedCategories: categoryNames)
        }
    }
}

extension Expense {
    var usesItemOwnership: Bool { (items ?? []).contains { $0.ownership != nil } }
    var itemFriendTotals: [String: Int] {
        var result: [String: Int] = [:]
        for item in chargedItems {
            guard let owner = item.ownership else { continue }
            for (name, amount) in zip(owner.friends, owner.friendAmounts(cents: item.cents)) {
                result[friendKey(name), default: 0] += amount
            }
        }
        return result
    }
    func applyingItemOwnership() throws -> Expense {
        guard usesItemOwnership else { return self }
        guard let items, items.count <= 100, items.allSatisfy({ $0.cents > 0 && $0.cents <= 10_000_000_000 }) else {
            throw reviewError("请检查物品数量和金额。", "Check item count and amounts.", "Semak bilangan dan amaun item.")
        }
        var copy = self
        var names: [String] = []
        for item in items {
            guard let owner = item.ownership else {
                throw reviewError("请为每件物品选择归属。", "Choose ownership for every item.", "Pilih pemilik bagi setiap item.")
            }
            try owner.validate()
            for name in owner.friends where !names.contains(where: { friendKey($0) == friendKey(name) }) { names.append(name) }
        }
        if let payer = paidByFriend {
            guard names.allSatisfy({ friendKey($0) == friendKey(payer) }) else {
                throw reviewError("朋友付款的账目只能分给自己和付款人。", "Friend-paid purchases can only be split between you and the payer.", "Belanja dibayar rakan hanya boleh dibahagi antara anda dan pembayar.")
            }
            names = [payer]
        }
        let totals = itemFriendTotals
        // Keep IDs and repayment/refund history, including zero-value old shares.
        copy.shares = shares.map { share in var next = share; next.cents = totals[friendKey(share.name), default: 0]; return next }
        for name in names where !copy.shares.contains(where: { friendKey($0.name) == friendKey(name) }) {
            copy.shares.append(Share(name: name, cents: totals[friendKey(name), default: 0]))
        }
        if let payer = paidByFriend { copy.shares = copy.shares.filter { friendKey($0.name) == friendKey(payer) } }
        return copy
    }
    /// Item edits retain the purchase identity, source metadata, legacy notes and debt history.
    func replacingItems(_ newItems: [ExpenseItem], allowedCategories: [String]) throws -> Expense {
        var copy = self
        copy.items = newItems.isEmpty ? nil : newItems
        copy.categoryAllocations = nil
        if copy.items != items, let first = newItems.first { copy.category = first.category }
        if usesItemOwnership || copy.usesItemOwnership {
            let previous = items ?? []
            let allocationChanged = previous.count != newItems.count || zip(previous, newItems).contains { old, new in
                old.id != new.id || old.cents != new.cents || old.ownership != new.ownership
            }
            if allocationChanged && (refunded > 0 || shares.contains { !$0.repayments.isEmpty || !($0.returns ?? []).isEmpty }) {
                throw reviewError("请先撤销已有退款或还款，再修改物品分账。", "Undo refunds or repayments before changing item splits.", "Batalkan pulangan atau bayaran balik sebelum menukar pembahagian item.")
            }
        }
        copy = try copy.applyingItemOwnership()
        try copy.validateItems(allowedCategories: allowedCategories)
        return copy
    }
}

// Bank names improve labels only. Acceptance is not restricted to this directory.
let financialProviderAliases: [(String, [String])] = [
    ("TNG", ["tng ewallet", "touch 'n go", "touch n go", "tng"]),
    ("Maybank", ["maybank", "maybank2u", "mae"]),
    ("Hong Leong", ["hong leong", "hlb connect", "hlb"]),
    ("AmBank", ["ambank", "amonline"]), ("Ryt Bank", ["ryt bank", "ryt"]), ("RHB", ["rhb"]),
    ("CIMB", ["cimb", "cimb octo", "cimb clicks"]),
    ("Public Bank", ["public bank", "public islamic", "mypb", "pbe", "pb engage"]),
    ("HSBC", ["hsbc"]), ("OCBC", ["ocbc"]), ("UOB", ["uob", "uob tmrw"]),
    ("Standard Chartered", ["standard chartered", "sc mobile", "sc saadiq"]),
    ("Affin Bank", ["affin", "affinalways"]), ("Alliance Bank", ["alliance bank", "allianceonline"]),
    ("BSN", ["bsn", "mybsn", "bank simpanan nasional"]),
    ("Bank Islam", ["bank islam", "bimb", "bimb mobile"]),
    ("Bank Rakyat", ["bank rakyat", "irakyat"]), ("Bank Muamalat", ["bank muamalat", "imuamalat"]),
    ("MBSB Bank", ["mbsb", "m journey"]), ("Agrobank", ["agrobank", "agronet"]),
    ("Al Rajhi", ["al rajhi", "alrajhi", "rize"]),
    ("GXBank", ["gxbank", "gx bank"]), ("Boost Bank", ["boost bank"]),
    ("AEON Bank", ["aeon bank"]), ("KAF Digital Bank", ["kaf digital bank", "kaf digital"]),
    ("Bank of China", ["bank of china", "boc malaysia"]),
    ("ICBC", ["icbc", "industrial and commercial bank of china"]),
    ("China Construction Bank", ["china construction bank", "ccb malaysia"]),
    ("Citibank", ["citibank", "citi mobile"]), ("Bank Pertama", ["co-opbank pertama", "coopbank pertama", "cbp"]),
    ("Bangkok Bank", ["bangkok bank"]), ("BNP Paribas", ["bnp paribas"]),
    ("Deutsche Bank", ["deutsche bank"]), ("Bank of America", ["bank of america"]),
    ("J.P. Morgan", ["j.p. morgan", "jpmorgan"]), ("MUFG", ["mufg"]),
    ("Mizuho", ["mizuho"]), ("Sumitomo Mitsui", ["sumitomo mitsui", "smbc"]),
    ("India International Bank", ["india international bank", "iibm"]),
    ("Kuwait Finance House", ["kuwait finance house", "kfh"])
]
func validFinancialSource(_ name: String) -> Bool {
    !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && name.count <= 120 &&
    name.rangeOfCharacter(from: .controlCharacters) == nil
}
func financialProvider(_ text: String) -> String? {
    for (name, aliases) in financialProviderAliases {
        for alias in aliases {
            let pattern = #"(?i)(?<![\p{L}\p{N}])"# + NSRegularExpression.escapedPattern(for: alias) + #"(?![\p{L}\p{N}])"#
            if text.range(of: pattern, options: .regularExpression) != nil { return name }
        }
    }
    return nil
}
func notificationProvider(sourceApp: String?, title: String, body: String) -> String {
    if let raw = sourceApp?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty, validFinancialSource(raw) {
        return financialProvider(raw) ?? raw
    }
    if let provider = financialProvider(title) { return provider }
    if let channel = notificationChannel(body), let provider = exactFinancialProvider(channel.name) { return provider }
    // Do not infer the sender bank from a merchant or recipient mentioned later.
    let prefix = String(notificationText(body).prefix(120))
    if let colon = prefix.firstIndex(of: ":"), let provider = financialProvider(String(prefix[..<colon])) { return provider }
    for (name, aliases) in financialProviderAliases {
        if aliases.contains(where: { prefix.lowercased().hasPrefix($0 + ":") || prefix.lowercased().hasPrefix($0 + " ") }) { return name }
    }
    return "银行 / TNG"
}
// A trailing delivery channel is metadata, never part of the merchant name.
func exactFinancialProvider(_ name: String) -> String? {
    let key = notificationTitleKey(name)
    return financialProviderAliases.first { provider, aliases in
        notificationTitleKey(provider) == key || aliases.contains { notificationTitleKey($0) == key }
    }?.0
}
func notificationChannel(_ body: String) -> (name: String, range: Range<String.Index>)? {
    let pattern = #"\s+(?:via|through|melalui)\s+([^!?\n]{1,120}?)\.?\z"#
    guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
          let match = regex.firstMatch(in: body, range: NSRange(body.startIndex..., in: body)),
          let name = Range(match.range(at: 1), in: body), let range = Range(match.range, in: body) else { return nil }
    return (String(body[name]).trimmingCharacters(in: .whitespaces), range)
}
extension Ledger {
    var availableSources: [String] {
        Array(Set(["手动", "Apple Pay", "TNG", "固定消费", "账单补录"] + expenses.map(\.source) + tngNotices.map(\.provider))).sorted()
    }
}
func notificationMatches(_ text: String, _ pattern: String) -> Bool {
    text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
}
func isNonTransactionNotification(_ body: String, title: String) -> Bool {
    let text = notificationText(title + " " + body)
    // Points receipts also say "received" and "transaction", but are not money.
    // Keep notices with currency amounts eligible for payment/cashback review.
    let pointsReceipt = notificationMatches(text, #"\b[0-9][0-9,]*(?:\.[0-9]+)?\s+(?:reward\s+)?points\b"#)
    let monetaryAmount = notificationMatches(text, #"(?:RM|MYR|USD|SGD|EUR|GBP|CNY|RMB|JPY|AUD|THB|IDR|INR|HKD)\s*[0-9]|[$€£¥]\s*[0-9]"#)
    if pointsReceipt && !monetaryAmount { return true }
    if notificationMatches(text, #"\b(?:otp|tac|verification code|one[- ]time (?:password|code)|securetac|approve (?:this |the )?(?:payment|transaction)|payment request|request to pay)\b|验证码|动态密码|请求付款|批准交易|kod pengesahan"#) { return true }
    if notificationMatches(text, #"\b(?:(?:payment|transaction|purchase|transfer) (?:has |was |is )?(?:failed|declined|pending|rejected|cancelled)|unsuccessful|pending payment|not (?:paid|successful)|failed to (?:pay|transfer)|scheduled payment|payment (?:due|reminder))\b|付款失败|交易失败|交易取消|待付款|付款请求|交易待处理|pembayaran gagal|transaksi gagal|bayaran tertunggak"#) { return true }
    if notificationMatches(text, #"\b(?:promotion|promo|cashback offer|reward points)\b|\boffer\s*:|限时优惠|促销|验证码|优惠活动|promosi"#) { return true }
    let reward = notificationMatches(text, #"\b(?:cash\s?back|rewards?|discounts?|vouchers?|points)\b|返现|回扣|优惠券|pulangan tunai|ganjaran|diskaun"#)
    let invitation = notificationMatches(text, #"\b(?:earn|get|enjoy|win|unlock|up to|stand a chance|when you (?:spend|pay)|make\s+\d+\s+(?:qr\s+)?payments?|dapatkan|sehingga|nikmati)\b|最高|可获|有机会|消费满"#)
    return reward && invitation
}
func shouldReviewFinancialNotification(_ body: String, title: String) -> Bool {
    guard !isNonTransactionNotification(body, title: title) else { return false }
    let text = notificationText(title + " " + body)
    // Retain unfamiliar transaction formats even if the amount is absent or foreign.
    let financial = notificationMatches(text, #"\b(?:charged|spent|paid|payment|transfer|received|deducted|credited|debited|refund|reversed|reload|top[- ]?up|purchase|transaction|cash\s?back|bayaran|pembayaran|pemindahan|pindahan|diterima|dibayar|dikreditkan|didebitkan|transaksi|pulangan)\b|付款|支付|消费|扣款|转账|转入|收款|入账|退款|充值|交易|返现"#)
    let amountMentioned = notificationMatches(text, #"(?:RM|MYR|USD|SGD|EUR|GBP|CNY|RMB|JPY|AUD|THB|IDR|INR|HKD)\s*[0-9]|[$€£¥]\s*[0-9]"#)
    let completed = notificationMatches(text, #"\b(?:(?:payment|purchase|transfer|transaction) (?:successful|completed)|(?:you have|you've) (?:paid|received|sent)|(?:was|has been) (?:charged|debited|credited))\b|付款成功|支付成功|交易成功|pembayaran berjaya|transaksi berjaya"#)
    return financial && (amountMentioned || completed)
}
func financialReviewReason(_ body: String) -> String {
    if notificationMatches(body, #"\b(?:refund|cash\s?back|reversal|reload|top[- ]?up)\b|退款|返现|充值|pulangan tunai"#) {
        return "可能是退款、返现或充值，请确认用途；未计入消费。"
    }
    if singleNotificationAmount(body) == nil {
        return "金额缺失、含多个金额或不是单一马币金额，请核对原文与币种；未计入消费。"
    }
    return "已收到交易通知，但成功状态、交易类型或商户尚未完全确认；请核对原文，未计入消费。"
}

/// Existing observed templates first; source-independent grammar second.
func parseFinancialNotification(_ body: String, title: String = "", sourceApp: String? = nil) -> TNGParsed? {
    guard body.count <= 8000, title.count <= 500, !isNonTransactionNotification(body, title: title) else { return nil }
    // Some automation bridges supply the visible heading and body together.
    if title.isEmpty, let newline = body.firstIndex(of: "\n") {
        let heading = String(body[..<newline]).trimmingCharacters(in: .whitespacesAndNewlines)
        if ["money paid", "payment", "fpx payment", "card payment", "payment successful"].contains(notificationTitleKey(heading)) {
            return parseFinancialNotification(String(body[body.index(after: newline)...]), title: heading, sourceApp: sourceApp)
        }
    }
    if let sourceApp, !sourceApp.isEmpty, !validFinancialSource(sourceApp) { return nil }
    let provider = notificationProvider(sourceApp: sourceApp, title: title, body: body)
    if notificationChannel(notificationText(body)) != nil {
        return parseGenericBankNotification(body, title: title, provider: provider)
    }
    if let parsed = parseKnownFinancialNotification(body, title: title) {
        if parsed.kind == "payment" {
            guard singleNotificationAmount(body) == parsed.cents,
                  !notificationMatches(body, #"\b(?:USD|SGD|EUR|GBP|CNY|RMB|JPY|AUD|THB|IDR|INR|HKD)\s*[0-9]"#),
                  !notificationMatches(parsed.party, #"\b(?:please|click|tap|if you|when you|cashback|credited|received|pending|failed|declined)\b|[!?\n]"#) else { return nil }
        }
        if parsed.sourceBank == "TNG", provider != "银行 / TNG", provider != "TNG" {
            return parseGenericBankNotification(body, title: title, provider: provider)
        }
        // Different banks can share wording. Re-evaluate with the generic rules,
        // which still reject explicit bank-name or direction contradictions.
        if parsed.sourceBank != "TNG", provider != "银行 / TNG", parsed.sourceBank != provider {
            return parseGenericBankNotification(body, title: title, provider: provider)
        }
        return parsed
    }
    return parseGenericBankNotification(body, title: title, provider: provider)
}

/// These are generic grammars, not claimed samples from individual banks.
/// Only complete, single-MYR, completed payments are eligible for auto posting.
func parseGenericBankNotification(_ body: String, title: String, provider: String) -> TNGParsed? {
    guard !isNonTransactionNotification(body, title: title), let cents = singleNotificationAmount(body) else { return nil }
    let combined = title + " " + body
    if let headingBank = financialProvider(title), provider != "银行 / TNG", headingBank != provider { return nil }
    // Other currency, credit-card repayment, cashback, refunds, reloads and
    // ambiguous account debits must not become ordinary purchases.
    guard !notificationMatches(combined, #"\b(?:USD|SGD|EUR|GBP|CNY|RMB|JPY|AUD|THB|IDR|INR|HKD|refund|reversal|reversed|cash\s?back|reload|top[- ]?up|credit card (?:bill|payment)|loan (?:payment|repayment)|repayment)\b|退款|返现|充值|信用卡还款|pinjaman|pulangan tunai"#) else { return nil }
    var text = notificationText(body)
    if let colon = text.firstIndex(of: ":"), text.distance(from: text.startIndex, to: colon) <= 80 {
        let prefix = String(text[..<colon])
        if let prefixBank = financialProvider(prefix), provider != "银行 / TNG", prefixBank != provider { return nil }
        let paymentHeading = notificationMatches(prefix, #"\A(?:(?:FPX|DuitNow QR|QR|Card|Debit Card|Online) )?Payment\z"#)
        if financialProvider(prefix) != nil || notificationTitleKey(prefix) == notificationTitleKey(provider) || paymentHeading {
            text = String(text[text.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        }
    }
    let reference = notificationReference(text)
    if reference != nil {
        text = text.replacingOccurrences(of: #"\s+(?:ref(?:erence)?|transaction\s+id)\s*[:#]\s*[A-Z0-9-]{3,100}\.?\z"#, with: "", options: [.regularExpression, .caseInsensitive])
    }
    if let channel = notificationChannel(text) {
        let channelBank = exactFinancialProvider(channel.name)
        guard channelBank != nil || notificationTitleKey(channel.name) == notificationTitleKey(provider) else { return nil }
        guard provider == "银行 / TNG" || channelBank == provider || notificationTitleKey(channel.name) == notificationTitleKey(provider) else { return nil }
        text.removeSubrange(channel.range)
    }
    // Parse only unambiguous numeric date+time suffixes, in Malaysia time.
    var date: Date?
    let datePattern = #"\s+(?:on|at|date\s*:|pada)\s+(\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}(?::\d{2})?|\d{2}/\d{2}/\d{4} \d{2}:\d{2}(?::\d{2})?)\.?\z"#
    if let regex = try? NSRegularExpression(pattern: datePattern, options: .caseInsensitive),
       let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
       let dateRange = Range(match.range(at: 1), in: text), let suffix = Range(match.range, in: text) {
        let raw = String(text[dateRange])
        for format in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "dd/MM/yyyy HH:mm:ss", "dd/MM/yyyy HH:mm"] {
            let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = Calendar(identifier: .gregorian); formatter.timeZone = TimeZone(identifier: "Asia/Kuala_Lumpur")
            formatter.dateFormat = format; formatter.isLenient = false
            if let value = formatter.date(from: raw), formatter.string(from: value) == raw { date = value; break }
        }
        guard date != nil else { return nil }
        text.removeSubrange(suffix)
    }
    let amount = #"(?:RM|MYR)\s*((?:[0-9]{1,3}(?:,[0-9]{3})+|[0-9]+)(?:\.[0-9]{2})?)"#
    let party = #"(.{1,200}?)"#
    let rules: [(String, String)] = [
        ("payment", #"\A(?:You have |You've |You )?(?:successfully )?paid "# + amount + #" (?:to|at|for) "# + party + #"\.?\z"#),
        ("payment", #"\A(?:Your )?(?:card |debit card )?(?:payment|purchase)(?: of)? "# + amount + #" (?:at|to|for) "# + party + #" (?:was |is |has been )?(?:successful|completed|approved)\.?\z"#),
        ("payment", #"\A(?:Successful|Completed) (?:card )?(?:payment|purchase)(?: of)? "# + amount + #" (?:at|to|for) "# + party + #"\.?\z"#),
        ("payment", #"\A(?:You have |You've |You )?spent "# + amount + #" (?:at|on) "# + party + #"\.?\z"#),
        ("payment", #"\AYour (?:(?:credit|debit) )?card (?:ending (?:in )?|\*+)[0-9]{4} (?:was |has been )?charged "# + amount + #" at "# + party + #"\.?\z"#),
        ("payment", #"\A"# + amount + #" (?:was |has been )charged to your (?:(?:credit|debit) )?card (?:ending (?:in )?|\*+)[0-9]{4} at "# + party + #"\.?\z"#),
        ("payment", #"\A(?:Anda telah |Anda )?(?:berjaya )?(?:membayar|bayar) "# + amount + #" (?:kepada|di|untuk) "# + party + #"\.?\z"#),
        ("payment", #"\A(?:Pembayaran|Bayaran|Pembelian)(?: sebanyak)? "# + amount + #" (?:kepada|di|untuk) "# + party + #" (?:telah )?berjaya\.?\z"#),
        ("payment", #"\A(?:您|你)?(?:已成功支付|已支付|已付款)\s*"# + amount + #"\s*(?:给|至|到)\s*"# + party + #"[。.]?\z"#),
        ("transfer", #"\A(?:You have |You've |You )?(?:successfully )?(?:sent|transferred) "# + amount + #" to "# + party + #"\.?\z"#),
        ("transfer", #"\A(?:Your )?(?:DuitNow )?transfer(?: of)? "# + amount + #" to "# + party + #" (?:was |is |has been )?(?:successful|completed)\.?\z"#),
        ("incoming", #"\A(?:You have |You've |You )?(?:successfully )?received "# + amount + #" from "# + party + #"\.?\z"#),
        ("incoming", #"\A"# + amount + #" (?:has been |was )?(?:received|credited) from "# + party + #"\.?\z"#)
    ]
    for (kind, pattern) in rules {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let nameRange = Range(match.range(at: 2), in: text) else { continue }
        let merchant = String(text[nameRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !merchant.isEmpty, merchant.rangeOfCharacter(from: .letters) != nil,
              !notificationMatches(merchant, #"\b(?:on|at|date|ref|balance|available|pending|failed|declined)\s*[:\d]|\b(?:please|click|tap|if you|when you|payment|transaction|credited|received|transfer|account)\b|[!?\n]|\d{1,4}[-/]\d{1,2}[-/]\d{1,4}"#) else { return nil }
        if kind != "incoming", notificationMatches(title, #"\b(?:received|incoming|credited)\b|收款|转入"#) { return nil }
        if kind == "incoming", notificationMatches(title, #"\b(?:sent|outgoing|payment|transfer successful)\b|付款|转出"#) { return nil }
        if kind == "payment", notificationMatches(combined, #"\b(?:transfer|received|credited|sent|savings|deposit|withdrawal)\b|转账|转入|收款|存款|提款|pindahan|pemindahan"#) { return nil }
        return TNGParsed(kind: kind, cents: cents, party: merchant, sourceBank: provider, transactionDate: date, reference: reference)
    }
    // Structured receipts must explicitly state success and a payment/purchase.
    // Never infer spending from a bare "Transaction successful" or account debit.
    let lines = (title + "\n" + body).components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    guard lines.contains(where: { notificationMatches($0, #"\A(?:(?:card )?(?:payment|purchase) (?:successful|completed)|pembayaran berjaya|付款成功|支付成功)\.?\z"#) }),
          !notificationMatches(combined, #"\b(?:transfer|received|credited|sent|deposit|withdrawal)\b|转账|收款|充值"#) else { return nil }
    var merchants: [String] = []; var amounts: [Int] = []
    for line in lines {
        if notificationMatches(line, #"\A(?:merchant|paid to|商户|商家|peniaga)\s*[:：]"#), let colon = line.firstIndex(where: { $0 == ":" || $0 == "：" }) {
            merchants.append(String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces))
        }
        if notificationMatches(line, #"\A(?:amount|paid amount|金额|付款金额|amaun|jumlah)\s*[:：]\s*(?:RM|MYR)\s*[0-9,.]+\z"#), let value = singleNotificationAmount(line) { amounts.append(value) }
        // Any unhandled substantive field stays pending instead of guessing.
        let allowed = line == title || notificationMatches(line, #"\A(?:(?:card )?(?:payment|purchase) (?:successful|completed)|pembayaran berjaya|付款成功|支付成功)\.?\z|\A(?:merchant|paid to|商户|商家|peniaga|amount|paid amount|金额|付款金额|amaun|jumlah|ref(?:erence)?|transaction id)\s*[:：]"#)
        if !allowed { return nil }
    }
    guard merchants.count == 1, amounts == [cents], let merchant = merchants.first,
          !merchant.isEmpty, merchant.count <= 200 else { return nil }
    return TNGParsed(kind: "payment", cents: cents, party: merchant, sourceBank: provider, reference: reference)
}

extension Expense {
    var timeSourceSuffix: String {
        switch timeSource {
        case "received": return tr(" · 自动化接收时间", " · automation received time", " · masa automasi diterima")
        case "notification": return tr(" · 通知时间", " · notification time", " · masa notifikasi")
        case "supplied": return tr(" · 提供的交易时间", " · supplied transaction time", " · masa transaksi diberikan")
        case "edited": return tr(" · 已手动调整", " · edited", " · diubah")
        default: return ""
        }
    }
}
