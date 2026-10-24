import Foundation

/// Genuine income: what a person records by hand or confirms from a bank/TNG notice. Transfers
/// between their own accounts, top-ups, refunds and friend repayments are never income here, so
/// they can never reach a budget.
enum IncomeKind: String, Codable, CaseIterable, Identifiable {
    case salary, freelance, partTime, bonus, other
    var id: String { rawValue }
    var label: String {
        switch self {
        case .salary: return tr("工资", "Salary", "Gaji")
        case .freelance: return tr("自由职业收入", "Freelance", "Kerja bebas")
        case .partTime: return tr("兼职收入", "Part-time work", "Kerja sambilan")
        case .bonus: return tr("奖金", "Bonus", "Bonus")
        case .other: return tr("其他收入", "Other income", "Pendapatan lain")
        }
    }
    var symbol: String {
        switch self {
        case .salary: return "briefcase.fill"
        case .freelance: return "laptopcomputer"
        case .partTime: return "clock.fill"
        case .bonus: return "gift.fill"
        case .other: return "plus.circle.fill"
        }
    }
}

/// Income recorded by hand. Bank/TNG income stays an incoming notice confirmed as income.
struct IncomeEntry: Codable, Identifiable, Equatable {
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
