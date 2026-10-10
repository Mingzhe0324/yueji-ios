import Foundation

func settlementError(_ zh: String, _ en: String, _ ms: String) -> LedgerError {
    LedgerError.invalid(tr(zh, en, ms))
}
private func invalidSettlementData() -> LedgerError {
    settlementError("结算资料无效。请核对关联的账目和付款，或恢复有效备份。", "Invalid settlement data. Review the linked expenses and payments, or restore a valid backup.", "Data penyelesaian tidak sah. Semak belanja dan bayaran dipautkan, atau pulihkan sandaran sah.")
}
func nonnegativeCents(_ text: String) throws -> Int {
    let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if value.range(of: #"^\d{1,8}(\.\d{1,2})?$"#, options: .regularExpression) != nil,
       let number = Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")), number == 0 { return 0 }
    return try toCents(value)
}

/// Positive balances are owed to me; negative balances are owed by me.
struct FriendDebtItem: Identifiable {
    let expense: Expense
    let shareID: String?
    let friend: String
    let balance: Int
    var id: String { Self.key(expense.id, shareID) }
    static func key(_ expenseID: String, _ shareID: String?) -> String {
        "\(expenseID.utf8.count):\(expenseID):" + (shareID.map { "friend:\($0)" } ?? "owner")
    }
}

struct SettlementLine: Codable, Equatable, Identifiable {
    let expense: Expense // Audit snapshot; the original expense stays in the ledger.
    let shareID: String?
    let before: Int
    let applied: Int // Signed amount of debt discharged, including offsets.
    var id: String { FriendDebtItem.key(expense.id, shareID) }
}

struct SettlementPlan: Equatable {
    let friend: String
    let name: String
    let date: Date
    let lines: [SettlementLine]
    let transfer: Int // Positive: received; negative: paid. Zero: offset only.
    var receivable: Int { lines.reduce(0) { $0 + max(0, $1.before) } }
    var payable: Int { lines.reduce(0) { $0 + max(0, -$1.before) } }
    var fullNet: Int { receivable - payable }
    var offset: Int { min(receivable, payable) }
}

struct FriendSettlement: Codable, Equatable, Identifiable {
    var id = UUID().uuidString
    let friend: String
    let name: String
    let date: Date
    let lines: [SettlementLine]
    let transfer: Int
    var voidedAt: Date? = nil
    var paymentNoticeID: String? = nil
    var convertedPayment: Expense? = nil // Retain a misclassified automatic payment for audit, not spending.
    var active: Bool { voidedAt == nil }
}

extension Expense {
    var payerLabel: String { paidByFriend ?? tr("我", "Me", "Saya") }
    func sameSettlementTerms(as other: Expense) -> Bool {
        id == other.id && merchant == other.merchant && cents == other.cents && date == other.date
        && category == other.category && categoryAllocations == other.categoryAllocations
        && paidByFriend == other.paidByFriend && foreign == other.foreign
        && (refunds ?? []) == (other.refunds ?? []) && shares.count == other.shares.count
        && zip(shares, other.shares).allSatisfy { pair in
            pair.0.id == pair.1.id && pair.0.name == pair.1.name && pair.0.cents == pair.1.cents && pair.0.refunded == pair.1.refunded
        }
    }
}

extension Ledger {
    private var settledAmounts: [String: Int] {
        var result: [String: Int] = [:]
        for record in settlements where record.active {
            for line in record.lines { result[line.id, default: 0] += line.applied }
        }
        return result
    }
    var friendDebtItems: [FriendDebtItem] {
        let applied = settledAmounts
        return expenses.flatMap { expense -> [FriendDebtItem] in
            if let payer = expense.paidByFriend {
                let key = FriendDebtItem.key(expense.id, nil)
                return [FriendDebtItem(expense: expense, shareID: nil, friend: payer,
                                       balance: -expense.owingToPayer - (applied[key] ?? 0))]
            }
            return expense.shares.map { share in
                FriendDebtItem(expense: expense, shareID: share.id, friend: share.name,
                               balance: share.owed - (applied[FriendDebtItem.key(expense.id, share.id)] ?? 0))
            }
        }.sorted { $0.expense.date == $1.expense.date ? $0.id < $1.id : $0.expense.date < $1.expense.date }
    }
    func outstanding(expense: Expense, share: Share) -> Int {
        guard expense.paidByFriend == nil else { return 0 }
        return share.owed - (settledAmounts[FriendDebtItem.key(expense.id, share.id)] ?? 0)
    }
    func hasActiveSettlement(expenseID: String) -> Bool {
        settlements.contains { $0.active && $0.lines.contains { $0.expense.id == expenseID && $0.applied != 0 } }
    }
    func requireUnsettledExpense(_ id: String) throws {
        guard !hasActiveSettlement(expenseID: id) else {
            throw settlementError("此账目已参与结算。请先在朋友页面撤销相关结算，再修改或退款。", "This expense is in a settlement. Undo its settlements on the friend's page before editing, deleting or refunding it.", "Belanja ini dalam penyelesaian. Batalkan penyelesaian di halaman rakan sebelum mengedit, memadam atau memulangkannya.")
        }
    }
    func settlementPlan(friend: String, selected: Set<String>, payment: Int, date: Date) throws -> SettlementPlan {
        let key = friendKey(friend)
        let items = friendDebtItems.filter { friendKey($0.friend) == key && selected.contains($0.id) }
        guard !selected.isEmpty, selected.count <= 200, items.count == selected.count,
              items.allSatisfy({ $0.balance != 0 && latestDebtDate($0) <= date }),
              date.timeIntervalSince1970.isFinite, date.timeIntervalSince1970 >= 0, date <= Date(), payment >= 0 else {
            throw settlementError("选择未结清账目，结算日期不能早于相关消费、退款或还款，不能晚于今天。", "Select outstanding items. Settlement must be on or after their expenses, refunds and repayments, and no later than today.", "Pilih rekod belum selesai. Tarikh penyelesaian mesti selepas belanja, pulangan dan bayaran hutang berkaitan, dan tidak lewat daripada hari ini.")
        }
        let receivable = items.reduce(0) { $0 + max(0, $1.balance) }
        let payable = items.reduce(0) { $0 + max(0, -$1.balance) }
        let net = receivable - payable
        guard payment <= abs(net) else { throw settlementError("实际转账不能超过抵扣后的净额。", "Payment cannot exceed the net balance after offsetting.", "Bayaran tidak boleh melebihi baki bersih selepas tolakan.") }
        var collect = min(receivable, payable) + (net > 0 ? payment : 0)
        var pay = min(receivable, payable) + (net < 0 ? payment : 0)
        var lines: [SettlementLine] = []
        for item in items {
            let amount: Int
            if item.balance > 0 { amount = min(item.balance, collect); collect -= amount }
            else { amount = -min(-item.balance, pay); pay += amount }
            lines.append(SettlementLine(expense: item.expense, shareID: item.shareID, before: item.balance, applied: amount))
        }
        guard lines.contains(where: { $0.applied != 0 }) else { throw settlementError("请输入转账金额或选择可抵扣的双方欠款。", "Enter a payment or select debts in both directions to offset.", "Masukkan bayaran atau pilih hutang kedua-dua arah untuk ditolak.") }
        return SettlementPlan(friend: key, name: items[0].friend, date: date, lines: lines, transfer: net >= 0 ? payment : -payment)
    }
    private func latestDebtDate(_ item: FriendDebtItem) -> Date {
        var dates = [item.expense.date] + (item.expense.refunds ?? []).map(\.date)
        if let share = item.expense.shares.first(where: { $0.id == item.shareID }) {
            dates += share.repayments.map(\.date) + (share.returns ?? []).map(\.date)
        }
        dates += settlements.filter { $0.active && $0.lines.contains { $0.id == item.id && $0.applied != 0 } }.map(\.date)
        return Calendar.current.startOfDay(for: dates.max() ?? item.expense.date)
    }
    @discardableResult mutating func confirmSettlement(_ plan: SettlementPlan, id: String = UUID().uuidString) throws -> String {
        let fresh = try settlementPlan(friend: plan.friend, selected: Set(plan.lines.map(\.id)), payment: abs(plan.transfer), date: plan.date)
        guard fresh == plan, !settlements.contains(where: { $0.id == id }) else {
            throw settlementError("账目或余额已改变，请重新预览结算。", "Entries or balances changed. Review the settlement again.", "Rekod atau baki berubah. Semak penyelesaian semula.")
        }
        var copy = self
        copy.settlements.append(FriendSettlement(id: id, friend: plan.friend, name: plan.name, date: plan.date, lines: plan.lines, transfer: plan.transfer))
        self = try copy.validated()
        return id
    }
    mutating func undoSettlement(id: String) throws {
        guard let i = settlements.firstIndex(where: { $0.id == id }), settlements[i].active else {
            throw settlementError("结算已撤销或不存在。", "Settlement was already undone or is missing.", "Penyelesaian telah dibatalkan atau tiada.")
        }
        var copy = self
        copy.settlements[i].voidedAt = Date()
        if let noticeID = copy.settlements[i].paymentNoticeID,
           let n = copy.tngNotices.firstIndex(where: { $0.id == noticeID && $0.settlementID == id }) {
            copy.tngNotices[n].settlementID = nil
            copy.tngNotices[n].status = copy.tngNotices[n].kind == "incoming" ? "pending" : "transfer"
            // Keep the same bank record. Never recreate the misclassified expense or replay automation.
        }
        self = try copy.validated()
    }
    func paymentIdentity(_ notice: TNGNotice) -> String? {
        guard let reference = notice.bankReference, !reference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return friendKey(notice.provider) + ":" + reference.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }
    func requireUnusedPaymentReference(_ notice: TNGNotice) throws {
        guard let identity = paymentIdentity(notice) else { return }
        guard !tngNotices.contains(where: {
            $0.id != notice.id && ["recorded", "repayment", "income", "ownTransfer", "settlement"].contains($0.status)
            && paymentIdentity($0) == identity
        }) else { throw settlementError("该银行交易参考编号已入账或用于还款、收入、转账或其他结算。请先撤销原确认。", "This bank reference is already recorded or used for a repayment, income, transfer or settlement. Undo the original confirmation first.", "Rujukan bank ini telah direkod atau digunakan untuk bayaran hutang, pendapatan, pindahan atau penyelesaian. Batalkan pengesahan asal dahulu.") }
    }
    mutating func linkSettlementPayment(settlementID: String, noticeID: String, distinctConfirmed: Bool = false) throws {
        guard let s = settlements.firstIndex(where: { $0.id == settlementID }), settlements[s].active,
              settlements[s].paymentNoticeID == nil, let n = tngNotices.firstIndex(where: { $0.id == noticeID }) else {
            throw settlementError("此结算或付款已关联，请重新查看。", "Settlement or payment is already linked. Reopen it.", "Penyelesaian atau bayaran telah dipautkan. Buka semula.")
        }
        let record = settlements[s], notice = tngNotices[n]
        guard record.transfer != 0, notice.cents == abs(record.transfer), notice.settlementID == nil,
              notice.resolution == nil, (notice.repaymentIDs ?? []).isEmpty,
              ["pending", "transfer", "recorded"].contains(notice.status),
              (record.transfer > 0 ? notice.kind == "incoming" : ["payment", "transfer"].contains(notice.kind)),
              !notice.possibleDuplicate || distinctConfirmed,
              notice.date <= Date(),
              notice.date >= Calendar.current.startOfDay(for: record.date) else {
            throw settlementError("请核对付款金额、方向、日期及是否重复。只能关联尚未使用的付款。", "Check amount, direction, date and duplicates. Only an unused payment can be linked.", "Semak amaun, arah, tarikh dan pendua. Hanya bayaran belum digunakan boleh dipautkan.")
        }
        try requireUnusedPaymentReference(notice)
        var copy = self
        if let expenseID = notice.expenseID, let expense = expenses.first(where: { $0.id == expenseID }) {
            guard notice.status == "recorded", expense.paidByFriend == nil, expense.shares.isEmpty,
                  expense.refunded == 0, expense.recurringKey == nil, expense.cents == abs(record.transfer), expense.source == notice.provider,
                  !hasActiveSettlement(expenseID: expenseID), tngNotices.filter({ $0.expenseID == expenseID }).count == 1 else {
                throw settlementError("此自动付款已有分账、退款或其他关联。请先处理原账目。", "This automatic payment has splits, refunds or other links. Resolve the original entry first.", "Bayaran automatik ini mempunyai bahagian, pulangan atau pautan lain. Selesaikan rekod asal dahulu.")
            }
            copy.settlements[s].convertedPayment = expense
            copy.expenses.removeAll { $0.id == expenseID }
        }
        copy.settlements[s].paymentNoticeID = noticeID
        copy.tngNotices[n].expenseID = nil
        copy.tngNotices[n].status = "settlement"
        copy.tngNotices[n].settlementID = settlementID
        self = try copy.validated()
    }
    func validateSettlements() throws {
        guard settlements.count <= 10_000, Set(settlements.map(\.id)).count == settlements.count else { throw invalidSettlementData() }
        let byID = Dictionary(expenses.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var applied: [String: Int] = [:], bases: [String: Int] = [:]
        var paymentIDs = Set<String>(), identities = Set<String>()
        for record in settlements {
            guard !record.id.isEmpty, record.id.count <= 200, !record.friend.isEmpty, record.friend == friendKey(record.friend),
                  record.name.count <= 200, friendKey(record.name) == record.friend, (1...200).contains(record.lines.count),
                  Set(record.lines.map(\.id)).count == record.lines.count, record.date.timeIntervalSince1970 >= 0,
                  record.date.timeIntervalSince1970 < 4_102_444_800,
                  record.transfer.magnitude <= 2_000_000_000_000,
                  record.lines.allSatisfy({ $0.before.magnitude <= 10_000_000_000 && $0.applied.magnitude <= 10_000_000_000 }),
                  record.lines.reduce(0, { $0 + $1.applied }) == record.transfer,
                  record.lines.contains(where: { $0.applied != 0 }) else { throw invalidSettlementData() }
            let receivable = record.lines.reduce(0) { $0 + max(0, $1.before) }
            let payable = record.lines.reduce(0) { $0 + max(0, -$1.before) }
            let net = receivable - payable
            guard abs(record.transfer) <= abs(net), record.transfer == 0 || (record.transfer > 0) == (net > 0),
                  record.lines.reduce(0, { $0 + max(0, $1.applied) }) == min(receivable, payable) + max(0, record.transfer),
                  record.lines.reduce(0, { $0 + max(0, -$1.applied) }) == min(receivable, payable) + max(0, -record.transfer) else { throw invalidSettlementData() }
            for line in record.lines {
                let snapshot = line.expense
                guard snapshot.cents > 0, snapshot.cents <= 10_000_000_000, snapshot.shares.count <= 100,
                      snapshot.shares.allSatisfy({ $0.cents >= 0 && $0.cents <= snapshot.cents }),
                      (snapshot.refunds ?? []).count <= 10_000,
                      (snapshot.refunds ?? []).allSatisfy({ $0.personalCents >= 0 && $0.personalCents <= snapshot.cents }),
                      snapshot.personal >= 0, snapshot.merchant.count <= 200,
                      snapshot.date.timeIntervalSince1970 >= 0, snapshot.date.timeIntervalSince1970 < 4_102_444_800 else { throw invalidSettlementData() }
                guard abs(line.before) <= 10_000_000_000, abs(line.applied) <= abs(line.before),
                      line.applied == 0 || (line.applied > 0) == (line.before > 0), !line.expense.id.isEmpty else { throw invalidSettlementData() }
                guard record.active, line.applied != 0 else { continue }
                guard let expense = byID[line.expense.id], expense.sameSettlementTerms(as: line.expense) else {
                    throw settlementError("已结算账目的金额、日期、分类、付款人、分账或退款发生改变。请先撤销相关结算。", "A settled expense's amount, date, category, payer, shares or refunds changed. Undo its settlements first.", "Amaun, tarikh, kategori, pembayar, bahagian atau pulangan belanja diselesaikan berubah. Batalkan penyelesaian dahulu.")
                }
                guard record.date >= Calendar.current.startOfDay(for: expense.date) else { throw invalidSettlementData() }
                let base: Int
                if let shareID = line.shareID {
                    guard expense.paidByFriend == nil, let share = expense.shares.first(where: { $0.id == shareID }), friendKey(share.name) == record.friend else { throw invalidSettlementData() }
                    base = share.owed
                } else {
                    guard expense.paidByFriend.map(friendKey) == record.friend else { throw invalidSettlementData() }
                    base = -expense.owingToPayer
                }
                applied[line.id, default: 0] += line.applied
                bases[line.id] = base
            }
            if record.active, let payment = record.paymentNoticeID {
                guard paymentIDs.insert(payment).inserted, let notice = tngNotices.first(where: { $0.id == payment }),
                      notice.settlementID == record.id, notice.status == "settlement", notice.expenseID == nil,
                      notice.resolution == nil, (notice.repaymentIDs ?? []).isEmpty,
                      record.transfer != 0, notice.cents == abs(record.transfer),
                      notice.date >= Calendar.current.startOfDay(for: record.date),
                      (record.transfer > 0 ? notice.kind == "incoming" : ["payment", "transfer"].contains(notice.kind)) else { throw invalidSettlementData() }
                if let identity = paymentIdentity(notice) { guard identities.insert(identity).inserted else { throw invalidSettlementData() } }
                try requireUnusedPaymentReference(notice)
            }
        }
        for (key, amount) in applied {
            let base = bases[key] ?? 0
            guard (amount > 0 ? base >= amount : base <= amount) else { throw invalidSettlementData() }
        }
        for notice in tngNotices where notice.settlementID != nil || notice.status == "settlement" {
            guard settlements.contains(where: { $0.active && $0.id == notice.settlementID && $0.paymentNoticeID == notice.id }) else { throw invalidSettlementData() }
        }
    }
}
