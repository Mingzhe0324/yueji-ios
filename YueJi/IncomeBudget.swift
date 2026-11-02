import Foundation
import CryptoKit
import PDFKit

/// Match a complete name phrase, never a substring inside another word.
func transferNameMatches(_ noticeName: String, owner: String) -> Bool {
    let phrase = friendKey(owner)
    guard !phrase.isEmpty else { return false }
    let pattern = "(?<![\\p{L}\\p{N}])" + NSRegularExpression.escapedPattern(for: phrase) + "(?![\\p{L}\\p{N}])"
    return friendKey(noticeName).range(of: pattern, options: .regularExpression) != nil
}

enum MalaysianBanks {
    // Display names checked against PIDM's member-bank directory, October 2026.
    static let conventional = ["Maybank", "CIMB Bank", "Public Bank", "RHB Bank", "Hong Leong Bank", "AmBank", "Affin Bank", "Alliance Bank", "HSBC Malaysia", "OCBC Malaysia", "UOB Malaysia", "Standard Chartered Malaysia", "Bank of China Malaysia", "ICBC Malaysia"]
    static let islamic = ["Maybank Islamic", "CIMB Islamic", "Bank Islam", "Bank Muamalat", "MBSB Bank", "Affin Islamic", "Alliance Islamic", "AmBank Islamic", "Hong Leong Islamic", "HSBC Amanah", "OCBC Al-Amin", "Public Islamic", "RHB Islamic", "Standard Chartered Saadiq", "Al Rajhi Malaysia"]
    static let digital = ["GXBank", "Boost Bank", "AEON Bank", "Ryt Bank", "KAF Digital Bank"]
    static let walletsAndPayments = ["TNG eWallet", "Wise"]
}

/// A manually maintained MYR account. No bank credentials or bank connection.
struct BankAccount: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var name: String
    var openingCents: Int
    /// Opening balance is measured immediately before this time.
    var openingDate: Date
    var institution: String? = nil
    /// Explicit opt-in. Stored with the ledger, so mappings stay account-isolated.
    var automaticSource: String? = nil
    var automaticSuffix: String? = nil
    // Legacy backup fields only. Saved routes no longer trigger automatic transfers.
    var transferDestinationID: String? = nil
    var transferOwnerName: String? = nil
    var transferRuleSince: Date? = nil
}

struct BankTransfer: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var fromAccountID: String
    var toAccountID: String
    var cents: Int
    var date: Date
    var note: String = ""
    var noticeIDs: [String]? = nil
}

extension Ledger {
    mutating func saveBankTransfer(_ transfer: BankTransfer, replacing original: BankTransfer?) throws {
        var copy = self
        if let original {
            guard transfer.id == original.id,
                  let index = copy.bankTransfers.firstIndex(where: { $0.id == original.id }),
                  copy.bankTransfers[index] == original else {
                throw LedgerError.invalid(tr("转账已变化，请重新打开。", "Transfer changed; reopen it.", "Pindahan berubah; buka semula."))
            }
            copy.bankTransfers[index] = transfer
        } else {
            guard !copy.bankTransfers.contains(where: { $0.id == transfer.id }) else {
                throw LedgerError.invalid("Transfer already exists")
            }
            copy.bankTransfers.append(transfer)
        }
        try copy.validateBankAccounts()
        self = copy
    }

    mutating func deleteBankTransfer(_ original: BankTransfer) throws {
        guard let index = bankTransfers.firstIndex(where: { $0.id == original.id }), bankTransfers[index] == original else {
            throw LedgerError.invalid(tr("转账已变化，请重新打开。", "Transfer changed; reopen it.", "Pindahan berubah; buka semula."))
        }
        bankTransfers.remove(at: index)
    }
    mutating func assignApplePayAccount(id: String, accountID: String?) throws {
        guard let index = expenses.firstIndex(where: { $0.id == id && $0.source == "Apple Pay" }),
              expenses[index].paidByFriend == nil,
              accountID == nil || bankAccounts.contains(where: { $0.id == accountID }) else {
            throw LedgerError.invalid("Payment or account no longer available")
        }
        expenses[index].bankAccountID = accountID
        for noticeIndex in tngNotices.indices where tngNotices[noticeIndex].expenseID == id {
            tngNotices[noticeIndex].bankAccountID = accountID
        }
    }

    func automaticBankAccount(source: String, suffix: String?) -> String? {
        guard validFinancialSource(source), source != "银行 / TNG", source != "Apple Pay" else { return nil }
        let key = (financialProvider(source) ?? source).lowercased()
        let candidates = bankAccounts.filter {
            guard let configured = $0.automaticSource else { return false }
            return (financialProvider(configured) ?? configured).lowercased() == key
        }
        if let suffix, !suffix.isEmpty {
            let exact = candidates.filter { $0.automaticSuffix == suffix }
            if exact.count == 1 { return exact[0].id }
            if !exact.isEmpty { return nil }
        }
        // A source-only rule is safe only when it is the sole configured account.
        guard candidates.count == 1, candidates[0].automaticSuffix == nil else { return nil }
        return candidates[0].id
    }

    mutating func assignNoticeAccount(id: String, accountID: String?) throws {
        guard let index = tngNotices.firstIndex(where: { $0.id == id }),
              accountID == nil || bankAccounts.contains(where: { $0.id == accountID }) else {
            throw LedgerError.invalid("Account or notification no longer exists")
        }
        tngNotices[index].bankAccountID = accountID
        if let expenseID = tngNotices[index].expenseID,
           let expenseIndex = expenses.firstIndex(where: { $0.id == expenseID }) {
            expenses[expenseIndex].bankAccountID = expenses[expenseIndex].paidByFriend == nil ? accountID : nil
        }
    }

    func bankBalance(_ account: BankAccount) -> Int {
        var total = account.openingCents
        for transfer in bankTransfers where transfer.date >= account.openingDate {
            if transfer.fromAccountID == account.id { total -= transfer.cents }
            if transfer.toAccountID == account.id { total += transfer.cents }
        }
        for entry in expenses where entry.bankAccountID == account.id && entry.paidByFriend == nil {
            if entry.date >= account.openingDate { total -= entry.cents }
            // A refund follows its original payment account, unless a friend received it.
            for refund in entry.refunds ?? [] where refund.date >= account.openingDate && refund.receivedByMe != false {
                total += refund.cents
            }
        }
        for entry in incomes where entry.bankAccountID == account.id && entry.date >= account.openingDate {
            total += entry.cents
        }
        for notice in tngNotices where notice.bankAccountID == account.id && notice.date >= account.openingDate && notice.expenseID == nil {
            let tngReceipt = (notice.provider == "TNG" || notice.verifiedIncomingBalance == true) && notice.kind == "incoming" &&
                ((notice.status == "pending" && !notice.possibleDuplicate && notice.balanceHeldForReview != true) || ["income", "repayment", "settlement", "ownTransfer"].contains(notice.status)) && notice.resolution == nil
            if notice.isConfirmedIncome || tngReceipt { total += notice.cents ?? 0 }
        }
        return total
    }

    func validateBankAccounts() throws {
        let ids = Set(bankAccounts.map(\.id))
        guard bankTransfers.count <= 10000, Set(bankTransfers.map(\.id)).count == bankTransfers.count else {
            throw LedgerError.invalid("Invalid bank transfers")
        }
        for transfer in bankTransfers {
            if let noticeIDs = transfer.noticeIDs {
                guard noticeIDs.count == 2, Set(noticeIDs).count == 2,
                      noticeIDs.allSatisfy({ id in tngNotices.contains(where: { $0.id == id }) }) else {
                    throw LedgerError.invalid("Invalid transfer notification links")
                }
            }
            guard !transfer.id.isEmpty, transfer.id.count <= 200,
                  transfer.fromAccountID != transfer.toAccountID,
                  ids.contains(transfer.fromAccountID), ids.contains(transfer.toAccountID),
                  (1...10_000_000_000).contains(transfer.cents), transfer.note.count <= 500,
                  transfer.date.timeIntervalSince1970 >= 0, transfer.date.timeIntervalSince1970 < 4_102_444_800 else {
                throw LedgerError.invalid(tr("请选择不同的转出、转入账户并填写有效金额。", "Choose different accounts and a valid amount.", "Pilih akaun berbeza dan amaun yang sah."))
            }
        }
        guard bankAccounts.count <= 100, ids.count == bankAccounts.count else {
            throw LedgerError.invalid("Invalid bank accounts")
        }
        for account in bankAccounts {
            if let destination = account.transferDestinationID {
                guard destination != account.id, ids.contains(destination), account.automaticSource != nil,
                      let owner = account.transferOwnerName, !friendKey(owner).isEmpty, owner.count <= 200,
                      let since = account.transferRuleSince, since.timeIntervalSince1970.isFinite else {
                    throw LedgerError.invalid("Invalid automatic transfer rule")
                }
            }
            if let source = account.automaticSource {
                guard validFinancialSource(source), source != "银行 / TNG", source != "Apple Pay" else { throw LedgerError.invalid("Invalid automatic source") }
            }
            if let suffix = account.automaticSuffix {
                guard account.automaticSource != nil, suffix.range(of: #"^[0-9]{4}$"#, options: .regularExpression) != nil else {
                    throw LedgerError.invalid(tr("账号尾号请输入 4 位数字。", "Enter the last four account digits.", "Masukkan empat digit akhir akaun."))
                }
            }
            guard !account.id.isEmpty, account.id.count <= 200,
                  !account.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  account.name.count <= 80, (account.institution?.count ?? 0) <= 80, (-10_000_000_000...10_000_000_000).contains(account.openingCents),
                  account.openingDate.timeIntervalSince1970 >= 0,
                  account.openingDate.timeIntervalSince1970 < 4_102_444_800 else {
                throw LedgerError.invalid("Invalid bank account")
            }
        }
        for id in expenses.compactMap(\.bankAccountID) + incomes.compactMap(\.bankAccountID) + tngNotices.compactMap(\.bankAccountID) {
            guard ids.contains(id) else { throw LedgerError.invalid("Payment account no longer exists") }
        }
    }
}

/// Genuine income: what a person records by hand or confirms from a bank/TNG notice. Transfers
/// between their own accounts, top-ups, refunds and friend repayments are never income here, so
/// they can never reach a budget.
enum IncomeKind: String, Codable, CaseIterable, Identifiable {
    case salary, freelance, partTime, bonus, allowance, interest, other
    var id: String { rawValue }
    var label: String {
        switch self {
        case .salary: return tr("工资", "Salary", "Gaji")
        case .freelance: return tr("自由职业收入", "Freelance", "Kerja bebas")
        case .partTime: return tr("兼职收入", "Part-time work", "Kerja sambilan")
        case .bonus: return tr("奖金", "Bonus", "Bonus")
        case .allowance: return tr("生活费", "Living allowance", "Wang sara hidup")
        case .interest: return tr("银行利息", "Bank interest", "Faedah bank")
        case .other: return tr("其他收入", "Other income", "Pendapatan lain")
        }
    }
    var symbol: String {
        switch self {
        case .salary: return "briefcase.fill"
        case .freelance: return "laptopcomputer"
        case .partTime: return "clock.fill"
        case .bonus: return "gift.fill"
        case .allowance: return "house.fill"
        case .interest: return "percent"
        case .other: return "plus.circle.fill"
        }
    }
}

/// Income recorded by hand. Bank/TNG income stays an incoming notice confirmed as income.
struct IncomeEntry: Codable, Identifiable, Equatable {
    var bankAccountID: String? = nil
    var id = UUID().uuidString
    /// Employer, client or a short description.
    var source: String
    /// Ringgit; a foreign amount is converted at its own explicit rate.
    var cents: Int
    var date = Date()
    var kind: IncomeKind = .salary
    var foreign: ForeignAmount? = nil
    var note: String? = nil
    var sourceKey: String { IncomeSourceKey.manual(id) }
    func validate() throws {
        guard !id.isEmpty, id.count <= 200, !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, source.count <= 200,
              cents > 0, cents <= 10_000_000_000, date.timeIntervalSince1970 >= 0, date.timeIntervalSince1970 < 4_102_444_800,
              (note?.count ?? 0) <= 2000 else {
            throw reviewError("请填写收入来源和大于零的金额。", "Enter where the income came from and an amount above zero.", "Masukkan sumber pendapatan dan amaun melebihi sifar.")
        }
        if let foreign {
            guard try foreign.myrCents() == cents else {
                throw reviewError("外币金额与换算后的马币金额不符。", "The foreign amount doesn't match its ringgit conversion.", "Amaun asing tidak sepadan dengan penukaran ringgit.")
            }
        }
    }
}

/// Part of one income a person added to one month's budget. It never creates another
/// transaction or changes the income: it only raises that month's budget.
struct BudgetAllocation: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    /// The income it comes from: `IncomeSourceKey.manual` or `IncomeSourceKey.notice`.
    var source: String
    /// The budget month, "yyyy-MM" as `monthKey`.
    var month: String
    /// Ringgit.
    var cents: Int
    /// When it was last set.
    var date = Date()
    /// Set by the automatic allocation setting and not changed since.
    var automatic: Bool? = nil
    var isWellFormed: Bool {
        !id.isEmpty && id.count <= 200 && !source.isEmpty && source.count <= 300 && budgetMonthIsValid(month)
            && cents > 0 && cents <= 10_000_000_000 && date.timeIntervalSince1970.isFinite && date.timeIntervalSince1970 >= 0
    }
}

enum IncomeSourceKey {
    static func manual(_ id: String) -> String { "income:" + id }
    static func notice(_ id: String) -> String { "notice:" + id }
}

/// One income that can fund a budget, whichever way it was recorded.
struct IncomeSource: Identifiable, Equatable {
    let id: String
    let name: String
    let cents: Int
    let date: Date
    let kind: IncomeKind
    let foreign: ForeignAmount?
    let provider: String
}

/// A month's budget: the base the person set plus the income they chose to add.
struct MonthlyBudget: Equatable {
    var base: Int
    var income: Int
    var total: Int { base + income }
    func remaining(spent: Int) -> Int { total - spent }
}

/// How one month's budget changes when an income is edited, deleted or reclassified.
struct BudgetAdjustment: Identifiable, Equatable {
    var id: String { month }
    let month: String
    let before: Int
    let after: Int
    var change: Int { after - before }
}

/// What to tell the person after income is saved or confirmed.
struct IncomeBudgetOutcome: Equatable {
    let source: String
    let name: String
    let cents: Int
    let incomeDate: Date
    /// The month new allocations go to: the current one.
    let month: String
    /// Added by the automatic setting, if it was on.
    let automatic: Int?
    let percent: Int?
    /// Another income already in a budget that may be the same money.
    let duplicateName: String?
}

/// The optional setting: off unless the person turns it on.
enum IncomeBudgetSettings {
    static let enabledKey = "incomeAutoAllocate"
    static let percentKey = "incomeAutoAllocatePercent"
    static let defaultPercent = 50
    static var autoPercent: Int? {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: enabledKey) else { return nil }
        let percent = defaults.object(forKey: percentKey) == nil ? defaultPercent : defaults.integer(forKey: percentKey)
        return (1...100).contains(percent) ? percent : nil
    }
}

func budgetMonthIsValid(_ key: String) -> Bool {
    key.range(of: #"^[0-9]{4}-(0[1-9]|1[0-2])$"#, options: .regularExpression) != nil
}
/// The first day of a "yyyy-MM" budget month in the current calendar.
func budgetMonthDate(_ key: String) -> Date? {
    let parts = key.split(separator: "-")
    guard budgetMonthIsValid(key), parts.count == 2, let year = Int(parts[0]), let month = Int(parts[1]) else { return nil }
    return Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: month, day: 1, hour: 12))
}
func budgetMonthLabel(_ key: String) -> String {
    guard let date = budgetMonthDate(key) else { return key }
    return date.formatted(.dateTime.year().month(.wide).locale(Locale(identifier: AppLanguage.localeID)))
}
func incomeAddedMessage(_ cents: Int, month: String) -> String {
    tr("已将 " + money(cents) + " 加入" + budgetMonthLabel(month) + "预算", money(cents) + " added to the " + budgetMonthLabel(month) + " budget",
       money(cents) + " ditambah ke bajet " + budgetMonthLabel(month))
}
/// One line per month, for confirmations that explain a budget change before it is made.
func budgetAdjustmentSummary(_ adjustments: [BudgetAdjustment]) -> String {
    adjustments.map { change in
        tr(budgetMonthLabel(change.month) + " 预算：", budgetMonthLabel(change.month) + " budget: ", "Bajet " + budgetMonthLabel(change.month) + ": ")
            + "−" + money(change.before - change.after) + " (" + money(change.before) + " → " + money(change.after) + ")"
    }.joined(separator: "\n")
}

extension TNGNotice {
    /// An incoming payment the person confirmed as income. Anything still under review, and
    /// repayments, own transfers, top-ups, refunds and settlements, never are.
    var isConfirmedIncome: Bool {
        kind == "incoming" && status == "income" && settlementID == nil && resolution == nil && (cents ?? 0) > 0
    }
    /// Income confirmed before kinds existed was "other income".
    var confirmedIncomeKind: IncomeKind { incomeKind.flatMap(IncomeKind.init(rawValue:)) ?? .other }
}

extension Ledger {
    /// The income a key names, only while it is genuine income that can fund a budget.
    func incomeSource(_ key: String) -> IncomeSource? {
        if key.hasPrefix("income:") {
            let id = String(key.dropFirst("income:".count))
            guard let entry = incomes.first(where: { $0.id == id }) else { return nil }
            return IncomeSource(id: key, name: entry.source, cents: entry.cents, date: entry.date, kind: entry.kind, foreign: entry.foreign, provider: "手动")
        }
        if key.hasPrefix("notice:") {
            let id = String(key.dropFirst("notice:".count))
            guard let notice = tngNotices.first(where: { $0.id == id }), notice.isConfirmedIncome, let cents = notice.cents else { return nil }
            let party = notice.party?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return IncomeSource(id: key, name: party.isEmpty ? sourceLabel(notice.provider) : party, cents: cents, date: notice.date,
                                kind: notice.confirmedIncomeKind, foreign: nil, provider: notice.provider)
        }
        return nil
    }
    /// Every income that can fund a budget, with its ringgit amount, by key.
    var incomeSourceAmounts: [String: Int] {
        var amounts: [String: Int] = [:]
        for entry in incomes where entry.cents > 0 { amounts[entry.sourceKey] = entry.cents }
        for notice in tngNotices where notice.isConfirmedIncome { amounts[IncomeSourceKey.notice(notice.id)] = notice.cents }
        return amounts
    }
    /// One income's allocations, oldest month first.
    func allocations(for source: String) -> [BudgetAllocation] {
        budgetAllocations.filter { $0.source == source }.sorted { $0.month < $1.month }
    }
    func allocatedTotal(for source: String) -> Int {
        budgetAllocations.reduce(0) { $0 + ($1.source == source ? $1.cents : 0) }
    }
    /// What is left of an income to add to a budget; nothing for anything that isn't income.
    func unallocated(for source: String) -> Int {
        guard let income = incomeSource(source) else { return 0 }
        return max(0, income.cents - allocatedTotal(for: source))
    }
    func incomeAllocated(toMonth key: String) -> Int {
        budgetAllocations.reduce(0) { $0 + ($1.month == key ? $1.cents : 0) }
    }
    /// Base monthly budget + income allocations. Spending rules are unchanged: remaining is this
    /// total less the month's eligible spending (`dailyBudgetSpending`).
    func monthlyBudget(_ key: String) -> MonthlyBudget {
        MonthlyBudget(base: budgets[key] ?? 0, income: incomeAllocated(toMonth: key))
    }
    /// Another income already in a budget with the same ringgit amount within three days: the
    /// same salary seen as a manual entry and a bank notice, say. It needs a person's check.
    func likelyDuplicateIncome(of source: String) -> IncomeSource? {
        guard let income = incomeSource(source) else { return nil }
        let funded = Set(budgetAllocations.map(\.source)).subtracting([source])
        return funded.compactMap { incomeSource($0) }
            .filter { $0.cents == income.cents && abs($0.date.timeIntervalSince(income.date)) <= 3 * 86_400 }
            .sorted { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date }.first
    }

    func validateIncomeBudget() throws {
        let invalid = reviewError("收入或预算分配数据无效。", "Invalid income or budget allocation.", "Data pendapatan atau peruntukan bajet tidak sah.")
        guard incomes.count <= 50_000, Set(incomes.map(\.id)).count == incomes.count else { throw invalid }
        for entry in incomes { try entry.validate() }
        for notice in tngNotices {
            if let kind = notice.incomeKind { guard notice.status == "income", IncomeKind(rawValue: kind) != nil else { throw invalid } }
        }
        guard budgetAllocations.count <= 100_000, Set(budgetAllocations.map(\.id)).count == budgetAllocations.count,
              Set(budgetAllocations.map { $0.source + "|" + $0.month }).count == budgetAllocations.count else { throw invalid }
        let amounts = incomeSourceAmounts
        var totals: [String: Int] = [:]
        for allocation in budgetAllocations {
            // An allocation always belongs to income that still exists and is still income.
            guard allocation.isWellFormed, let amount = amounts[allocation.source] else { throw invalid }
            totals[allocation.source, default: 0] += allocation.cents
            guard (totals[allocation.source] ?? 0) <= amount else {
                throw reviewError("加入预算的金额不能超过收入本身。", "Budget allocations can't exceed the income itself.", "Peruntukan bajet tidak boleh melebihi pendapatan itu sendiri.")
            }
        }
    }

    /// Repairs allocations read from an older or merged backup so the same money can never
    /// count twice: drops ones whose income is gone or no longer income, keeps a single one per
    /// income and month (the larger, never the sum), and trims any total beyond the income,
    /// latest month first. Ledgers written by this app are already consistent.
    func reconcilingBudgetAllocations() -> Ledger {
        guard !budgetAllocations.isEmpty else { return self }
        let amounts = incomeSourceAmounts
        var best: [String: BudgetAllocation] = [:]
        var order: [String] = []
        for allocation in budgetAllocations where allocation.isWellFormed && amounts[allocation.source] != nil {
            let key = allocation.source + "|" + allocation.month
            if let existing = best[key] {
                if allocation.cents > existing.cents { best[key] = allocation }
            } else { best[key] = allocation; order.append(key) }
        }
        var ids = Set<String>()
        var kept = order.compactMap { best[$0] }.filter { ids.insert($0.id).inserted }
        var totals: [String: Int] = [:]
        for allocation in kept { totals[allocation.source, default: 0] += allocation.cents }
        for (source, total) in totals {
            var excess = total - (amounts[source] ?? 0)
            guard excess > 0 else { continue }
            for index in kept.indices.sorted(by: { kept[$0].month > kept[$1].month }) where kept[index].source == source && excess > 0 {
                let cut = min(kept[index].cents, excess)
                kept[index].cents -= cut; excess -= cut
            }
        }
        kept.removeAll { $0.cents <= 0 }
        guard kept != budgetAllocations else { return self }
        var copy = self
        copy.budgetAllocations = kept
        return copy
    }

    /// Sets how much of one income goes to one month's budget; zero removes it. `expected` is the
    /// amount the person saw for that month, so a repeated tap, a second device or a stale screen
    /// can't apply the same change twice.
    @discardableResult
    mutating func setIncomeAllocation(source: String, month: String, cents: Int, expected: Int,
                                      confirmedDistinct: Bool = false, now: Date = Date()) throws -> BudgetAllocation? {
        guard let income = incomeSource(source) else {
            throw reviewError("请先确认这笔钱是收入，再加入预算。", "Confirm this money as income before adding it to a budget.", "Sahkan wang ini sebagai pendapatan sebelum menambahnya ke bajet.")
        }
        guard budgetMonthIsValid(month), cents >= 0, cents <= 10_000_000_000 else {
            throw reviewError("预算月份或金额无效。", "Invalid budget month or amount.", "Bulan atau amaun bajet tidak sah.")
        }
        let index = budgetAllocations.firstIndex { $0.source == source && $0.month == month }
        let current = index.map { budgetAllocations[$0].cents } ?? 0
        guard current == expected else {
            throw reviewError("这笔收入的预算金额已改变，请重新打开后再试。", "This income's budget amount has changed. Reopen it and try again.", "Jumlah bajet daripada pendapatan ini telah berubah. Buka semula dan cuba lagi.")
        }
        guard cents != current else { return index.map { budgetAllocations[$0] } }
        guard allocatedTotal(for: source) - current + cents <= income.cents else {
            throw reviewError("超过了这笔收入尚未加入预算的金额。", "That's more than this income has left to add.", "Amaun melebihi baki pendapatan ini.")
        }
        if allocatedTotal(for: source) == 0, !confirmedDistinct, let other = likelyDuplicateIncome(of: source) {
            throw reviewError("这笔收入可能与已加入预算的「" + other.name + "」是同一笔钱。请核对后确认这是另一笔收入。",
                              "This may be the same money as " + other.name + ", which is already in a budget. Check it, then confirm it's separate income.",
                              "Ini mungkin wang yang sama dengan " + other.name + " yang sudah dalam bajet. Semak, kemudian sahkan ia pendapatan berasingan.")
        }
        var copy = self
        var result: BudgetAllocation?
        if cents == 0 {
            if let index { copy.budgetAllocations.remove(at: index) }
        } else if let index {
            copy.budgetAllocations[index].cents = cents
            copy.budgetAllocations[index].date = now
            copy.budgetAllocations[index].automatic = nil
            result = copy.budgetAllocations[index]
        } else {
            let allocation = BudgetAllocation(source: source, month: month, cents: cents, date: now)
            copy.budgetAllocations.append(allocation)
            result = allocation
        }
        self = try copy.validated()
        return result
    }

    /// Adds the chosen share of newly confirmed income to `now`'s month: once per income, under
    /// the same rules as a person's own allocation. A possible duplicate is left for review.
    @discardableResult
    mutating func autoAllocateIncome(source: String, percent: Int, now: Date = Date()) throws -> BudgetAllocation? {
        guard (1...100).contains(percent), let income = incomeSource(source),
              allocatedTotal(for: source) == 0, likelyDuplicateIncome(of: source) == nil else { return nil }
        let cents = income.cents * percent / 100
        guard cents > 0 else { return nil }
        var copy = self
        guard let allocation = try copy.setIncomeAllocation(source: source, month: monthKey(now), cents: cents, expected: 0, now: now),
              let index = copy.budgetAllocations.firstIndex(where: { $0.id == allocation.id }) else { return nil }
        copy.budgetAllocations[index].automatic = true
        self = try copy.validated()
        return copy.budgetAllocations[index]
    }

    /// Call in the same write that saves or confirms income: applies the automatic setting when
    /// it is on and says what to show. Nil for anything that isn't income.
    mutating func settleNewIncome(source: String, autoPercent: Int?, now: Date = Date()) throws -> IncomeBudgetOutcome? {
        guard let income = incomeSource(source) else { return nil }
        // Interest stays in the account even when automatic budget allocation is on.
        // Explicit allocations remain available from income details.
        guard income.kind != .interest else { return nil }
        let duplicate = allocatedTotal(for: source) == 0 ? likelyDuplicateIncome(of: source) : nil
        var automatic: Int?
        if let autoPercent, duplicate == nil, let allocation = try autoAllocateIncome(source: source, percent: autoPercent, now: now) {
            automatic = allocation.cents
        }
        return IncomeBudgetOutcome(source: source, name: income.name, cents: income.cents, incomeDate: income.date, month: monthKey(now),
                                   automatic: automatic, percent: automatic == nil ? nil : autoPercent, duplicateName: duplicate?.name)
    }

    /// The months an income's allocations shrink by when it becomes `newCents`, latest first,
    /// so an edit can explain the budget change before it is saved.
    func allocationAdjustments(source: String, newCents: Int) -> [BudgetAdjustment] {
        var excess = allocatedTotal(for: source) - max(0, newCents)
        guard excess > 0 else { return [] }
        var result: [BudgetAdjustment] = []
        for allocation in allocations(for: source).reversed() where excess > 0 {
            let cut = min(allocation.cents, excess)
            result.append(BudgetAdjustment(month: allocation.month, before: allocation.cents, after: allocation.cents - cut))
            excess -= cut
        }
        return result
    }
    /// Every allocation an income has, for a deletion or reclassification to explain.
    func allocationRemovals(source: String) -> [BudgetAdjustment] {
        allocations(for: source).reversed().map { BudgetAdjustment(month: $0.month, before: $0.cents, after: 0) }
    }
    private mutating func applyAdjustments(_ adjustments: [BudgetAdjustment], source: String, now: Date) {
        for change in adjustments {
            guard let index = budgetAllocations.firstIndex(where: { $0.source == source && $0.month == change.month }) else { continue }
            if change.after <= 0 { budgetAllocations.remove(at: index) }
            else { budgetAllocations[index].cents = change.after; budgetAllocations[index].date = now }
        }
    }

    /// Saves new manual income. A second save of the same draft is refused, never doubled.
    mutating func addIncome(_ entry: IncomeEntry, autoPercent: Int? = nil, now: Date = Date()) throws -> IncomeBudgetOutcome? {
        try entry.validate()
        guard !incomes.contains(where: { $0.id == entry.id }) else {
            throw reviewError("这笔收入已保存，不能重复保存。", "This income is already saved.", "Pendapatan ini sudah disimpan.")
        }
        var copy = self
        copy.incomes.append(entry)
        let outcome = try copy.settleNewIncome(source: entry.sourceKey, autoPercent: autoPercent, now: now)
        self = try copy.validated()
        return outcome
    }
    /// Saves an edit. A lower amount trims the income's allocations (latest month first) so a
    /// budget never holds more than the income; the result is what the editor explained.
    @discardableResult
    mutating func updateIncome(_ entry: IncomeEntry, replacing original: IncomeEntry, now: Date = Date()) throws -> [BudgetAdjustment] {
        try entry.validate()
        guard entry.id == original.id, let index = incomes.firstIndex(where: { $0.id == original.id }), incomes[index] == original else {
            throw reviewError("记录已改变，请重新打开。", "Record changed. Reopen it.", "Rekod berubah. Buka semula.")
        }
        let adjustments = allocationAdjustments(source: entry.sourceKey, newCents: entry.cents)
        var copy = self
        copy.incomes[index] = entry
        copy.applyAdjustments(adjustments, source: entry.sourceKey, now: now)
        self = try copy.validated()
        return adjustments
    }
    /// Deletes manual income and its allocations together; undo restores both.
    mutating func deleteIncome(_ expected: IncomeEntry) throws -> DeletedLedgerRecord {
        guard let index = incomes.firstIndex(where: { $0.id == expected.id }), incomes[index] == expected else {
            throw reviewError("记录已改变或已删除，请重新打开后再试。", "Record changed or was deleted. Reopen it and try again.", "Rekod berubah atau dipadam. Buka semula dan cuba lagi.")
        }
        var copy = self
        let removed = copy.budgetAllocations.filter { $0.source == expected.sourceKey }
        copy.budgetAllocations.removeAll { $0.source == expected.sourceKey }
        copy.incomes.remove(at: index)
        self = try copy.validated()
        return DeletedLedgerRecord(notices: [], before: [], after: [], incomes: [expected], allocations: removed)
    }
    func incomeEntries(in month: Date, search: String = "") -> [IncomeEntry] {
        let key = monthKey(month)
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return incomes.filter { entry in
            monthKey(entry.date) == key && (query.isEmpty || entry.source.localizedCaseInsensitiveContains(query)
                || (entry.note ?? "").localizedCaseInsensitiveContains(query) || entry.kind.label.localizedCaseInsensitiveContains(query))
        }.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date > $1.date }
    }
}

// MARK: - RHB statement reconciliation
struct StatementRow: Identifiable, Equatable, Sendable {
    let id: String
    let date: Date
    let description: String
    let serial: String
    let debit: Int
    let credit: Int
    let balance: Int
    var detail = ""
    var analysisText: String {
        // Long numeric identifiers are unnecessary for purchase categorization.
        String((description + " " + detail).replacingOccurrences(of: #"\b\d[\d -]{6,}\d\b"#, with: "[redacted]", options: .regularExpression).prefix(1000))
    }
    var cents: Int { debit + credit }
    var isExpense: Bool { debit > 0 && ["DEBITCARD TXN D", "SERVICE CHARGE", "SERVICE FEE", "BANK CHARGES", "SALE DEBIT", "POS PURCHASE", "DEBIT CARD ISSUANCE FEE"].contains(description.uppercased()) }
    var isInterest: Bool { credit > 0 && ["PROFIT CREDIT", "INTEREST CREDIT", "CREDIT INTEREST", "DAILY INTEREST PAYOUT", "HIBAH/PROFIT, , ,"].contains(description.uppercased()) }
}
struct RHBStatement: Sendable {
    var provider: String = "RHB"
    var verificationNote: String = ""
    var reviewOnly: Bool = false
    let accountHash: String
    let suffix: String
    let start: Date
    let end: Date
    let opening: Int
    let closing: Int
    let debitCount: Int
    let creditCount: Int
    let debitTotal: Int
    let creditTotal: Int
    let rows: [StatementRow]
    static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Asia/Kuala_Lumpur")!; return c
    }
    static func hash(_ text: String) -> String { SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined() }
    static func failure() -> Error {
        reviewError("月结单格式或余额校验未通过。请使用已支持版式的完整原始文字版 PDF，不能缺页；本次未写入账目。", "Statement format or balance checks failed. Use a complete original text PDF in a supported layout. No entries were written.", "Format atau semakan baki gagal. Gunakan PDF teks asal lengkap dalam format disokong. Tiada rekod ditulis.")
    }
    func validate() throws {
        guard start <= end, !rows.isEmpty, rows.count <= 500, Set(rows.map(\.id)).count == rows.count,
              debitCount == rows.filter({ $0.debit > 0 }).count, creditCount == rows.filter({ $0.credit > 0 }).count,
              debitTotal == rows.reduce(0, { $0 + $1.debit }), creditTotal == rows.reduce(0, { $0 + $1.credit }),
              opening - debitTotal + creditTotal == closing else { throw Self.failure() }
        var previous = opening, previousDate = start
        for row in rows {
            guard row.date >= previousDate, row.date <= end, row.date >= start,
                  row.debit >= 0, row.credit >= 0, row.debit <= 10_000_000_000, row.credit <= 10_000_000_000,
                  (row.debit > 0) != (row.credit > 0), row.description.count <= 200,
                  !row.description.isEmpty, previous - row.debit + row.credit == row.balance else { throw Self.failure() }
            previous = row.balance; previousDate = row.date
        }
        guard previous == closing else { throw Self.failure() }
    }
    /// Reads only the sampled RHB six-column layout. Amounts and directions are
    /// obtained from column positions, never inferred by an LLM.
    static func read(_ data: Data) throws -> RHBStatement {
        guard data.count <= 10_000_000, let document = PDFDocument(data: data), !document.isLocked,
              (1...20).contains(document.pageCount) else { throw failure() }
        let pages = (0..<document.pageCount).compactMap { document.page(at: $0) }
        guard pages.allSatisfy({ $0.numberOfCharacters <= 60_000 && $0.rotation == 0 }) else { throw failure() }
        let full = pages.compactMap(\.string).joined(separator: "\n")
        if !(full.contains("RHB") && full.contains("B/F BALANCE")) {
            return try AdditionalStatementReader.read(pages)
        }
        func matches(_ pattern: String, _ text: String) -> [NSTextCheckingResult] {
            (try? NSRegularExpression(pattern: pattern).matches(in: text, range: NSRange(location: 0, length: (text as NSString).length))) ?? []
        }
        let flat = full.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        guard full.contains("RHB"), full.contains("Debit"), full.contains("Credit"),
              let period = matches(#"Statement Period\s*/\s*Tempoh Penyata\s*:\s*(\d{2} [A-Za-z]{3} \d{2})\s*[–-]\s*(\d{2} [A-Za-z]{3} \d{2})"#, flat).first else { throw failure() }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar; formatter.timeZone = calendar.timeZone; formatter.dateFormat = "dd MMM yy"; formatter.isLenient = false
        formatter.twoDigitStartDate = calendar.date(from: DateComponents(year: 2000, month: 1, day: 1))
        guard let start = formatter.date(from: (flat as NSString).substring(with: period.range(at: 1))),
              let end = formatter.date(from: (flat as NSString).substring(with: period.range(at: 2))), end >= start,
              end <= Date(), (calendar.dateComponents([.day], from: start, to: end).day ?? 999) <= 366 else { throw failure() }
        // Only one savings account is supported. Hash the number; do not retain
        // the full number, statement holder, address, or YTD profit summary.
        let numbers = matches(#"SAVINGS ACCOUNT-i\s+(\d{8,20})\b"#, flat).map { (flat as NSString).substring(with: $0.range(at: 1)) }
        guard Set(numbers).count == 1, let account = numbers.first else { throw failure() }
        let accountHash = hash("RHB:" + account)
        func moneyValue(_ text: String) throws -> Int {
            let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard clean.range(of: #"^-?(?:\d{1,3}(?:,\d{3})+|\d+)\.\d{2}$"#, options: .regularExpression) != nil,
                  let value = Decimal(string: clean.replacingOccurrences(of: ",", with: ""), locale: Locale(identifier: "en_US_POSIX")), abs(value) <= 100_000_000 else { throw failure() }
            return NSDecimalNumber(decimal: value * 100).intValue
        }
        var rows: [StatementRow] = [], opening: Int?, closing: Int?, counts: (Int, Int)?, totals: (Int, Int)?
        for page in pages {
            try Task.checkCancellation()
            let text = page.string ?? "", ns = text as NSString, bounds = page.bounds(for: .mediaBox)
            guard bounds.width > 0, bounds.height > 0 else { throw failure() }
            func box(_ range: NSRange) -> CGRect { page.selection(for: range)?.bounds(for: page) ?? .zero }
            func cell(_ x1: Double, _ x2: Double, _ band: CGRect) -> String {
                let rect = CGRect(x: bounds.minX + bounds.width * x1, y: band.minY - 0.8,
                                  width: bounds.width * (x2 - x1), height: band.height + 1.6)
                return (page.selection(for: rect)?.string ?? "").split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
            }
            let dateMatches = matches(#"\b\d{2} [A-Za-z]{3}\b"#, text).filter {
                let b = box($0.range); return b.width > 0 && b.minX / bounds.width < 0.13 && b.minX / bounds.width > 0.05
            }.sorted { box($0.range).midY > box($1.range).midY }
            for (index, match) in dateMatches.enumerated() {
                let band = box(match.range), day = ns.substring(with: match.range)
                let description = cell(0.13, 0.45, band), serial = cell(0.45, 0.60, band)
                let debitText = cell(0.60, 0.72, band), creditText = cell(0.72, 0.85, band), balanceText = cell(0.85, 0.95, band)
                let balance = try moneyValue(balanceText)
                if description == "B/F BALANCE" { guard opening == nil else { throw failure() }; opening = balance; continue }
                if description == "C/F BALANCE" { guard closing == nil else { throw failure() }; closing = balance; continue }
                guard closing == nil else { throw failure() }
                let dates = (calendar.component(.year, from: start)...calendar.component(.year, from: end)).compactMap { year in
                    formatter.dateFormat = "dd MMM yyyy"
                    return formatter.date(from: day + " " + String(year))
                }.filter { $0 >= start && $0 <= end }
                guard dates.count == 1, let date = dates.first else { throw failure() }
                let debit = debitText.isEmpty ? 0 : try moneyValue(debitText), credit = creditText.isEmpty ? 0 : try moneyValue(creditText)
                let rowID = "statement:" + hash([accountHash, String(date.timeIntervalSince1970), description, serial, String(debit), String(credit), String(balance)].joined(separator: "|"))
                let nextY = index + 1 < dateMatches.count ? box(dateMatches[index + 1].range).maxY + 1 : band.minY - 40
                let lower = max(nextY, band.minY - 40)
                let detailRect = CGRect(x: bounds.width * 0.13, y: lower, width: bounds.width * 0.32, height: max(0, band.minY - 1 - lower))
                let detail = (page.selection(for: detailRect)?.string ?? "").split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
                rows.append(StatementRow(id: rowID, date: date, description: description, serial: serial, debit: debit, credit: credit, balance: balance, detail: String(detail.prefix(1000))))
            }
            for match in matches("Total Count", text) {
                let band = box(match.range)
                guard counts == nil, let d = Int(cell(0.60, 0.72, band)), let c = Int(cell(0.72, 0.85, band)) else { throw failure() }
                counts = (d,c)
                for m in matches(#"\(RM\)"#, text) {
                    let b = box(m.range)
                    if b.midY < band.midY && band.midY - b.midY < 40 && b.minX / bounds.width > 0.40 {
                        guard totals == nil else { throw failure() }
                        totals = (try moneyValue(cell(0.60, 0.72, b)), try moneyValue(cell(0.72, 0.85, b)))
                    }
                }
            }
        }
        guard let opening, let closing, let counts, let totals else { throw failure() }
        let result = RHBStatement(accountHash: accountHash, suffix: String(account.suffix(4)), start: start, end: end,
                                  opening: opening, closing: closing, debitCount: counts.0, creditCount: counts.1, debitTotal: totals.0, creditTotal: totals.1, rows: rows)
        try result.validate(); return result
    }
}

/// Strict adapters for the supplied layouts. Only transaction columns enter the
/// ledger; document headers, addresses and full account numbers are discarded.
private enum AdditionalStatementReader {
    static func matches(_ pattern: String, _ text: String) -> [NSTextCheckingResult] {
        (try? NSRegularExpression(pattern: pattern).matches(in: text, range: NSRange(location: 0, length: (text as NSString).length))) ?? []
    }
    static func capture(_ pattern: String, _ text: String, _ group: Int = 1) throws -> String {
        guard let m = matches(pattern, text).first else { throw RHBStatement.failure() }
        return (text as NSString).substring(with: m.range(at: group))
    }
    static func amount(_ text: String) throws -> Int {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix(".") { s = "0" + s }
        guard s.range(of: #"^-?(?:\d{1,3}(?:,\d{3})+|\d+)\.\d{2}$"#, options: .regularExpression) != nil,
              let d = Decimal(string: s.replacingOccurrences(of: ",", with: ""), locale: Locale(identifier: "en_US_POSIX")),
              abs(d) <= 100_000_000 else { throw RHBStatement.failure() }
        return NSDecimalNumber(decimal: d * 100).intValue
    }
    static func date(_ text: String, _ format: String) throws -> Date {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = RHBStatement.calendar; f.timeZone = f.calendar.timeZone
        f.dateFormat = format; f.isLenient = false
        f.twoDigitStartDate = f.calendar.date(from: DateComponents(year: 2000, month: 1, day: 1))
        guard let result = f.date(from: text) else { throw RHBStatement.failure() }; return result
    }
    struct Page {
        let pdf: PDFPage
        var text: String { pdf.string ?? "" }
        var bounds: CGRect { pdf.bounds(for: .mediaBox) }
        func box(_ range: NSRange) -> CGRect { pdf.selection(for: range)?.bounds(for: pdf) ?? .zero }
        func cell(_ left: Double, _ right: Double, _ band: CGRect) -> String {
            let r = CGRect(x: bounds.minX + bounds.width * left, y: band.minY - 2.5,
                           width: bounds.width * (right - left), height: band.height + 5)
            return (pdf.selection(for: r)?.string ?? "").split(whereSeparator: \.isWhitespace).joined(separator: " ")
        }
        func label(_ name: String) throws -> CGRect {
            guard let m = matches(NSRegularExpression.escapedPattern(for: name), text).first else { throw RHBStatement.failure() }
            return box(m.range)
        }
        func value(_ name: String, _ left: Double, _ right: Double = 0.96) throws -> Int {
            try amount(cell(left, right, label(name)))
        }
        func entries(_ pattern: String, left: Double, right: Double) -> [NSTextCheckingResult] {
            matches(pattern, text).filter {
                let b = box($0.range), x = (b.minX - bounds.minX) / bounds.width
                return b.width > 0 && x >= left && x < right
            }.sorted { box($0.range).midY > box($1.range).midY }
        }
    }
    static func read(_ pages: [PDFPage]) throws -> RHBStatement {
        let p = pages.map { Page(pdf: $0) }
        let full = p.map(\.text).joined(separator: "\n")
        let flat = full.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard let first = p.first else { throw RHBStatement.failure() }
        let provider: String, number: String, start: Date, end: Date, opening: Int, closing: Int
        var debitTotal: Int?, creditTotal: Int?, debitCount: Int?, creditCount: Int?
        var note = "", reviewOnly = false
        var rows: [StatementRow] = []
        // Single-page layouts are intentionally restricted until multipage
        // samples can verify page continuations and repeated headers.
        if full.contains("AmBank") && full.contains("ACCOUNT SUMMARY") {
            guard p.count == 1, flat.contains("MYR"), flat.contains("1 of 1") else { throw RHBStatement.failure() }
            provider = "AmBank"
            number = try capture(#"^(\d{8,20})$"#, first.cell(0.78, 0.96, first.label("ACCOUNT NO.")))
            let period = #"(\d{2}/\d{2}/\d{4})\s*-\s*(\d{2}/\d{2}/\d{4})"#
            start = try date(capture(period, flat), "dd/MM/yyyy"); end = try date(capture(period, flat, 2), "dd/MM/yyyy")
            opening = try first.value("OPENING BALANCE", 0.75)
            closing = try first.value("CLOSING BALANCE", 0.75)
            debitTotal = try first.value("TOTAL DEBITS", 0.75); creditTotal = try first.value("TOTAL CREDITS", 0.75)
            debitCount = Int(try first.cell(0.55, 0.75, first.label("TOTAL DEBITS")))
            creditCount = Int(try first.cell(0.55, 0.75, first.label("TOTAL CREDITS")))
            guard debitCount != nil, creditCount != nil else { throw RHBStatement.failure() }
            let year = RHBStatement.calendar.component(.year, from: start)
            for m in first.entries(#"\b\d{2}[A-Za-z]{3}\b"#, left: 0.06, right: 0.13) {
                let b = first.box(m.range)
                let d = try date((first.text as NSString).substring(with: m.range) + String(year), "ddMMMyyyy")
                let desc = first.cell(0.133, 0.468, b)
                let dr = first.cell(0.58, 0.70, b), cr = first.cell(0.70, 0.82, b)
                rows.append(StatementRow(id: "", date: d, description: desc, serial: first.cell(0.468, 0.58, b),
                                         debit: dr.isEmpty ? 0 : try amount(dr), credit: cr.isEmpty ? 0 : try amount(cr), balance: try amount(first.cell(0.82, 0.96, b))))
            }
        } else if full.contains("Hong Leong Bank") && full.contains("SAVINGS ACCOUNT STATEMENT") {
            guard p.count == 1, flat.contains("MYR"), matches(#"1\s+of\s+1"#, flat).count == 1 else { throw RHBStatement.failure() }
            provider = "Hong Leong"
            number = try capture(#"A/C No\s*/\s*No Akaun\s*:\s*(\d+)"#, flat)
            let period = #"(\d{2}/\d{2}/\d{2})\s*-\s*(\d{2}/\d{2}/\d{2})"#
            start = try date(capture(period, flat), "dd/MM/yy"); end = try date(capture(period, flat, 2), "dd/MM/yy")
            opening = try first.value("Balance from previous statement", 0.81)
            closing = try first.value("Closing Balance", 0.81)
            debitTotal = try first.value("Total Withdrawals", 0.44, 0.58); creditTotal = try first.value("Total Deposits", 0.44, 0.58)
            debitCount = Int(try first.cell(0.36, 0.42, first.label("Total Withdrawals")))
            creditCount = Int(try first.cell(0.36, 0.42, first.label("Total Deposits")))
            guard debitCount != nil, creditCount != nil else { throw RHBStatement.failure() }
            var running = opening
            // PDFKit can concatenate the date and the adjacent description.
            // Guard against extra digits rather than requiring a word boundary;
            // entries still restricts matches to the physical date column.
            for m in first.entries(#"(?<!\d)\d{2}-\d{2}-\d{4}(?!\d)"#, left: 0.08, right: 0.16) {
                let b = first.box(m.range), dr = first.cell(0.677, 0.81, b), cr = first.cell(0.543, 0.677, b)
                let debit = dr.isEmpty ? 0 : try amount(dr), credit = cr.isEmpty ? 0 : try amount(cr)
                let printed = first.cell(0.81, 0.945, b)
                running = running - debit + credit
                if !printed.isEmpty { guard try amount(printed) == running else { throw RHBStatement.failure() } }
                else { note = "部分逐笔余额未印出，已按借贷计算，并与下一笔印出余额和月结总计核对。" }
                rows.append(StatementRow(id: "", date: try date((first.text as NSString).substring(with: m.range), "dd-MM-yyyy"),
                                         description: first.cell(0.165, 0.543, b), serial: "", debit: debit, credit: credit, balance: running))
            }
        } else if full.contains("Maybank") && full.contains("BEGINNING BALANCE") {
            guard p.count == 1, full.contains("SAVINGS ACCOUNT-I"), !full.contains("USD"), !full.contains("SGD") else { throw RHBStatement.failure() }
            provider = "Maybank"
            number = try capture(#"\b(\d{6}-\d{6})\b"#, flat).replacingOccurrences(of: "-", with: "")
            // The statement date is the rightmost date in the header.
            guard let m = first.entries(#"\b\d{2}/\d{2}/\d{2}\b"#, left: 0.80, right: 0.98).first else { throw RHBStatement.failure() }
            end = try date((first.text as NSString).substring(with: m.range), "dd/MM/yy")
            guard let month = RHBStatement.calendar.dateInterval(of: .month, for: end),
                  RHBStatement.calendar.date(byAdding: .day, value: -1, to: month.end) == end else { throw RHBStatement.failure() }
            start = month.start
            opening = try first.value("BEGINNING BALANCE", 0.80)
            closing = try first.value("ENDING BALANCE", 0.61, 0.78)
            debitTotal = try first.value("TOTAL DEBIT", 0.61, 0.78); creditTotal = try first.value("TOTAL CREDIT", 0.61, 0.78)
            for m in first.entries(#"\b\d{2}/\d{2}/\d{2}\b"#, left: 0.06, right: 0.16) {
                let b = first.box(m.range), signed = first.cell(0.61, 0.78, b)
                guard signed.hasSuffix("+") || signed.hasSuffix("-") else { throw RHBStatement.failure() }
                let value = try amount(String(signed.dropLast()))
                rows.append(StatementRow(id: "", date: try date((first.text as NSString).substring(with: m.range), "dd/MM/yy"),
                                         description: first.cell(0.165, 0.60, b), serial: "", debit: signed.hasSuffix("-") ? value : 0,
                                         credit: signed.hasSuffix("+") ? value : 0, balance: try amount(first.cell(0.79, 0.96, b))))
            }
        } else if flat.contains("YTL Digital Bank") && flat.contains("Main Account / Akaun Utama") {
            guard p.count == 3, full.contains("END OF STATEMENT"), full.contains("MYR") else { throw RHBStatement.failure() }
            provider = "Ryt Bank"
            number = try capture(#"Nombor Akaun Simpanan\s*:\s*(\d{2} \d{4} \d{4})"#, flat).replacingOccurrences(of: " ", with: "")
            let period = #"From (\d{1,2} [A-Za-z]{3} \d{4}) to (\d{1,2} [A-Za-z]{3} \d{4})"#
            start = try date(capture(period, flat), "d MMM yyyy"); end = try date(capture(period, flat, 2), "d MMM yyyy")
            // Summary numbers sit below the Main Savings label baseline.
            let summaryBand = try first.label("Main Savings").offsetBy(dx: 0, dy: -6)
            opening = try amount(first.cell(0.28, 0.38, summaryBand))
            closing = try amount(first.cell(0.82, 0.94, summaryBand))
            let interest = try amount(first.cell(0.40, 0.52, summaryBand).replacingOccurrences(of: "+", with: ""))
            debitTotal = try amount(first.cell(0.54, 0.66, summaryBand))
            creditTotal = try amount(first.cell(0.68, 0.80, summaryBand)) + interest
            let transactions = p[1]
            guard try transactions.value("Opening balance", 0.82) == opening,
                  try transactions.value("Closing balance (MYR)", 0.82) == closing else { throw RHBStatement.failure() }
            for m in transactions.entries(#"\b\d{1,2} [A-Za-z]{3} \d{4}\b"#, left: 0.06, right: 0.18) {
                let b = transactions.box(m.range), desc = transactions.cell(0.20, 0.70, b)
                if desc == "Opening balance" { continue }
                let signed = transactions.cell(0.70, 0.81, b)
                guard signed.hasPrefix("+") || signed.hasPrefix("-") else { throw RHBStatement.failure() }
                let value = try amount(String(signed.dropFirst()))
                rows.append(StatementRow(id: "", date: try date((transactions.text as NSString).substring(with: m.range), "d MMM yyyy"), description: desc, serial: "",
                                         debit: signed.hasPrefix("-") ? value : 0, credit: signed.hasPrefix("+") ? value : 0,
                                         balance: try amount(transactions.cell(0.82, 0.94, b))))
            }
            note = "仅核对 Main Savings 主账户，不包括 Pocket，也不使用汇总 Total 作为主账户余额。"
        } else if full.contains("Wise Payments Malaysia") && full.contains("MYR statement") {
            guard p.count == 1, matches(#"\b1\s*/\s*1\b"#, flat).count == 1 else { throw RHBStatement.failure() }
            provider = "Wise"
            let period = #"(\d{1,2} [A-Za-z]+ \d{4}) \[GMT\+08:00\] - (\d{1,2} [A-Za-z]+ \d{4}) \[GMT\+08:00\]"#
            start = try date(capture(period, flat), "d MMMM yyyy"); end = try date(capture(period, flat, 2), "d MMMM yyyy")
            // Only the sampled one-row incoming layout is accepted. Other Wise
            // layouts require dedicated direction/order tests before import.
            let ids = matches(#"Transaction: ([A-Z]+-[0-9]+)"#, full)
            guard ids.count == 1 else { throw RHBStatement.failure() }
            number = try capture(#"\b(\d{15})\b"#, full)
            let closingText = try capture(#"\]\s*([\d,]+\.\d{2}) MYR"#, flat)
            closing = try amount(closingText)
            let band = try first.label("Received money from")
            guard first.cell(0.73, 0.83, band).isEmpty else { throw RHBStatement.failure() }
            let credit = try amount(first.cell(0.63, 0.73, band))
            guard try amount(first.cell(0.84, 0.95, band)) == closing else { throw RHBStatement.failure() }
            let rowDate = try date(capture(#"(\d{1,2} [A-Za-z]+ \d{4})\s*\| Transaction:"#, flat), "d MMMM yyyy")
            opening = closing - credit
            rows = [StatementRow(id: "", date: rowDate, description: first.cell(0.07, 0.63, band),
                                 serial: (full as NSString).substring(with: ids[0].range(at: 1)), debit: 0, credit: credit, balance: closing)]
            note = "此格式未印期初余额，期初为根据期末与交易推算的值。所有交易留待确认，不能据此认定整月核对通过。"
            reviewOnly = true
        } else { throw RHBStatement.failure() }
        guard start <= end, end <= Date(), (RHBStatement.calendar.dateComponents([.day], from: start, to: end).day ?? 999) <= 366 else { throw RHBStatement.failure() }
        let accountHash = RHBStatement.hash(provider + ":" + number)
        rows = rows.map { row in
            let id = "statement:" + RHBStatement.hash([accountHash, String(row.date.timeIntervalSince1970), row.description, row.serial,
                                                       String(row.debit), String(row.credit), String(row.balance)].joined(separator: "|"))
            return StatementRow(id: id, date: row.date, description: row.description, serial: row.serial, debit: row.debit, credit: row.credit, balance: row.balance, detail: row.detail)
        }
        let result = RHBStatement(provider: provider, verificationNote: note, reviewOnly: reviewOnly,
                                  accountHash: accountHash, suffix: String(number.suffix(4)), start: start, end: end, opening: opening, closing: closing,
                                  debitCount: debitCount ?? rows.filter { $0.debit > 0 }.count,
                                  creditCount: creditCount ?? rows.filter { $0.credit > 0 }.count,
                                  debitTotal: debitTotal ?? rows.reduce(0) { $0 + $1.debit }, creditTotal: creditTotal ?? rows.reduce(0) { $0 + $1.credit }, rows: rows)
        try result.validate(); return result
    }
}

struct StatementImportStamp: Codable, Equatable {
    let batch: String
    let count: Int
    let created: Date
    let noticeHash: String
    let expenseHash: String?
    static func digest<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return RHBStatement.hash(String(decoding: try encoder.encode(value), as: UTF8.self))
    }
    static func read(_ notice: TNGNotice) -> StatementImportStamp? {
        notice.statementImport
    }
}
struct StatementImportResult: Sendable {
    let batch: String
    var added = 0
    var pending = 0
    var skipped = 0
    var matched = 0
    var existingPending = 0
    var possibleDuplicates = 0
}
extension Ledger {
    /// A same-amount posting within three days may be an existing notification,
    /// manual entry, refund or transfer. Ambiguity must never auto-create money.
    func statementMayExist(_ row: StatementRow, accountID: String) -> Bool {
        func near(_ date: Date) -> Bool { abs(RHBStatement.calendar.startOfDay(for: date).timeIntervalSince(row.date)) <= 3 * 86400 }
        func account(_ id: String?) -> Bool { id == nil || id == accountID }
        if tngNotices.contains(where: { account($0.bankAccountID) && $0.cents == row.cents && near($0.date) }) { return true }
        if row.debit > 0 {
            return expenses.contains { $0.paidByFriend == nil && account($0.bankAccountID) && $0.cents == row.cents && near($0.date) } ||
                bankTransfers.contains { $0.fromAccountID == accountID && $0.cents == row.cents && near($0.date) }
        }
        return incomes.contains { account($0.bankAccountID) && $0.cents == row.cents && near($0.date) } ||
            bankTransfers.contains { $0.toAccountID == accountID && $0.cents == row.cents && near($0.date) } ||
            expenses.contains { entry in account(entry.bankAccountID) && (entry.refunds ?? []).contains { $0.receivedByMe != false && $0.cents == row.cents && near($0.date) } }
    }
    func statementBalance(_ account: BankAccount, before cutoff: Date) -> Int? {
        guard account.openingDate <= cutoff else { return nil }
        var copy = self
        copy.bankTransfers.removeAll { $0.date >= cutoff }; copy.incomes.removeAll { $0.date >= cutoff }
        copy.tngNotices.removeAll { $0.date >= cutoff }
        copy.expenses = expenses.map { entry in
            var e = entry; e.refunds = (e.refunds ?? []).filter { $0.date < cutoff }
            if e.date >= cutoff { e.date = account.openingDate.addingTimeInterval(-1) }
            return e
        }
        return copy.bankBalance(account)
    }
    mutating func importStatement(_ statement: RHBStatement, account: BankAccount, categories: [String: String], now: Date = Date()) throws -> StatementImportResult {
        try statement.validate()
        guard bankAccounts.contains(account), financialProvider(account.institution ?? account.automaticSource ?? "") == statement.provider,
              account.automaticSuffix == nil || account.automaticSuffix == statement.suffix else { throw RHBStatement.failure() }
        var copy = self, result = StatementImportResult(batch: UUID().uuidString)
        let count = statement.rows.filter { row in row.date >= account.openingDate && !seenEvents.contains(row.id) && !tngNotices.contains(where: { $0.id == row.id }) }.count
        for row in statement.rows {
            // Day-only statement dates cannot safely be placed after a midday
            // opening balance. Earlier rows are already covered by that balance.
            if row.date < account.openingDate || seenEvents.contains(row.id) || tngNotices.contains(where: { $0.id == row.id }) {
                if row.date >= account.openingDate {
                    if tngNotices.contains(where: { $0.id == row.id && $0.status == "pending" }) { result.existingPending += 1 }
                    else { result.matched += 1 }
                }
                result.skipped += 1; continue
            }
            let possible = statementMayExist(row, accountID: account.id) || statement.rows.contains {
                $0.id != row.id && $0.date == row.date && $0.cents == row.cents && ($0.debit > 0) == (row.debit > 0)
            }
            var notice = TNGNotice(bankAccountID: account.id, id: row.id, body: row.description + "\n" + row.detail + (row.debit > 0 ? "\nDebit: " : "\nCredit: ") + money(row.cents) + "\nStatement balance: " + money(row.balance), title: "RHB statement", date: row.date, usesReceivedDate: false,
                                   kind: row.credit > 0 ? "incoming" : "unknown", status: "pending", cents: row.cents, party: row.description)
            notice.title = statement.provider + " statement"
            notice.sourceBank = statement.provider; notice.accountSuffix = statement.suffix; notice.bankReference = row.id
            notice.balanceHeldForReview = true; notice.possibleDuplicate = possible
            if possible { result.possibleDuplicates += 1 }
            notice.reviewReason = possible ? tr("可能已有相同交易，请核对后处理。", "A matching transaction may already exist. Review first.", "Transaksi sepadan mungkin sudah wujud. Semak dahulu.") : tr("月结单用途待确认。", "Statement purpose needs review.", "Tujuan penyata perlu disemak.")
            var expense: Expense?
            if !possible && !statement.reviewOnly && row.isExpense {
                let suggested = categories[row.analysisText] ?? "其他"
                let category = categoryNames.contains(suggested) ? suggested : "其他"
                expense = Expense(bankAccountID: account.id, id: row.id + ":expense", merchant: statement.provider + " · " + row.description, cents: row.cents, date: row.date, category: category, source: statement.provider, transactionReference: row.id, timeSource: "supplied")
                notice.kind = "payment"; notice.status = "recorded"; notice.expenseID = expense?.id
                result.added += 1
            } else if !possible && !statement.reviewOnly && row.isInterest {
                notice.status = "income"; notice.incomeKind = IncomeKind.interest.rawValue
                result.added += 1
            } else { result.pending += 1 }
            let stamp = StatementImportStamp(batch: result.batch, count: count, created: now, noticeHash: try StatementImportStamp.digest(notice), expenseHash: try expense.map { try StatementImportStamp.digest($0) })
            notice.statementImport = stamp
            if let expense { copy.expenses.append(expense) }
            copy.tngNotices.append(notice); copy.seenEvents.insert(row.id)
        }
        self = try copy.validated(); return result
    }
    mutating func undoStatementImport(batch: String) throws {
        let notices = tngNotices.filter { StatementImportStamp.read($0)?.batch == batch }
        guard !notices.isEmpty else { throw RHBStatement.failure() }
        var copy = self
        for notice in notices {
            guard let stamp = StatementImportStamp.read(notice), stamp.count == notices.count else { throw RHBStatement.failure() }
            var original = notice; original.statementImport = nil
            guard try StatementImportStamp.digest(original) == stamp.noticeHash,
                  !budgetAllocations.contains(where: { $0.source == IncomeSourceKey.notice(notice.id) }),
                  !tngNotices.contains(where: { $0.id != notice.id && ($0.relatedRecordID == notice.id || (notice.expenseID != nil && $0.relatedRecordID == notice.expenseID)) }),
                  !bankTransfers.contains(where: { $0.noticeIDs?.contains(notice.id) == true }) else {
                throw reviewError("本次导入的记录已被修改或用于预算／转账，请先撤销相关处理。", "Imported records were edited or used in budgets/transfers. Undo those changes first.", "Rekod import telah diubah atau digunakan dalam bajet/pindahan. Batalkan perubahan itu dahulu.")
            }
            if let id = notice.expenseID {
                guard let entry = copy.expenses.first(where: { $0.id == id }), try StatementImportStamp.digest(entry) == stamp.expenseHash else { throw RHBStatement.failure() }
                try copy.deleteExpense(entry)
            }
            copy.tngNotices.removeAll { $0.id == notice.id }; copy.seenEvents.remove(notice.id)
        }
        self = try copy.validated()
    }
}
