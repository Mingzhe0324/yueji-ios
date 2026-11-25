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
    var accountDirection: AccountDirection { transfer > 0 ? .incoming : (transfer < 0 ? .outgoing : .neutral) }
    var paymentTitle: String {
        if transfer > 0 { return tr("朋友还款", "Friend repayment", "Bayaran balik daripada rakan") }
        if transfer < 0 { return tr("还给朋友", "Repayment to friend", "Bayaran balik kepada rakan") }
        return tr("债务抵扣", "Debt offset", "Tolakan hutang")
    }
}

extension Expense {
    /// Reconstruct refund terms at a settlement without rewriting its audit snapshot.
    /// Only later, appended refunds may differ; original amounts and shares stay locked.
    func atSettlementRefunds(_ snapshot: Expense, date: Date) -> Expense? {
        let old = snapshot.refunds ?? [], current = refunds ?? []
        guard current.count >= old.count, Array(current.prefix(old.count)) == old,
              current.dropFirst(old.count).allSatisfy({ $0.date >= Calendar.current.startOfDay(for: date) }) else { return nil }
        var copy = self
        copy.refunds = snapshot.refunds
        for i in copy.shares.indices {
            let shareID = copy.shares[i].id
            copy.shares[i].refundCents = old.reduce(0) { $0 + ($1.shares[shareID] ?? 0) }
        }
        return copy.sameSettlementTerms(as: snapshot) ? copy : nil
    }
    var payerLabel: String { paidByFriend ?? tr("我", "Me", "Saya") }
    func sameSettlementTerms(as other: Expense) -> Bool {
        id == other.id && merchant == other.merchant && cents == other.cents && date == other.date
        && category == other.category && categoryAllocations == other.categoryAllocations && (items ?? []) == (other.items ?? [])
        && paidByFriend == other.paidByFriend && foreign == other.foreign
        && charges == other.charges && isLoan == other.isLoan
        && (refunds ?? []) == (other.refunds ?? []) && shares.count == other.shares.count
        && zip(shares, other.shares).allSatisfy { pair in
            pair.0.id == pair.1.id && pair.0.name == pair.1.name && pair.0.cents == pair.1.cents && pair.0.refunded == pair.1.refunded
        }
    }
}

extension Ledger {
    mutating func confirmManualSettlement(_ plan: SettlementPlan, id: String, accountID: String?) throws -> String {
        if plan.transfer == 0 { return try confirmSettlement(plan, id: id) }
        guard let accountID, let account = bankAccounts.first(where: { $0.id == accountID }), plan.date >= account.openingDate,
              !tngNotices.contains(where: { $0.id == id }), !settlements.contains(where: { $0.id == id }) else {
            throw settlementError("请选择实际收付款账户，并核对日期。", "Choose the actual payment account and check the date.", "Pilih akaun bayaran sebenar dan semak tarikh.")
        }
        var copy = self
        var notice = TNGNotice(bankAccountID: accountID, id: id, body: "Manual settlement", title: "", date: plan.date, usesReceivedDate: false, kind: plan.transfer > 0 ? "incoming" : "transfer", status: "pending", cents: abs(plan.transfer), party: plan.name)
        notice.sourceBank = "手动"; notice.balanceHeldForReview = true
        copy.tngNotices.append(notice)
        let result = try copy.confirmNoticeNetSettlement(noticeID: id, plan: plan)
        self = copy
        return result
    }

    /// A manual receipt uses the same purpose/reimbursement/debt confirmation as a notification.
    mutating func addManualReceipt(id: String, sender: String, cents: Int, date: Date, accountID: String) throws -> String {
        let name = sender.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, id.count <= 200, !name.isEmpty, name.count <= 200,
              (1...10_000_000_000).contains(cents), date.timeIntervalSince1970.isFinite,
              date.timeIntervalSince1970 >= 0, date <= Date(),
              let account = bankAccounts.first(where: { $0.id == accountID }), date >= account.openingDate else {
            throw settlementError("请填写转账人、实际金额、日期和到账账户。", "Enter the sender, actual amount, date and receiving account.", "Isi pengirim, amaun sebenar, tarikh dan akaun penerima.")
        }
        if let existing = tngNotices.first(where: { $0.id == id }) {
            guard existing.provider == "手动", existing.party == name, existing.cents == cents, existing.date == date, existing.bankAccountID == accountID else { throw LedgerError.invalid("Receipt changed") }
            return id
        }
        var notice = TNGNotice(bankAccountID: accountID, id: id, body: "Manual receipt", title: "", date: date, usesReceivedDate: false, kind: "incoming", status: "pending", cents: cents, party: name)
        notice.sourceBank = "手动"; notice.balanceHeldForReview = true
        notice.possibleDuplicate = tngNotices.contains { $0.kind == "incoming" && $0.status != "ignored" && $0.bankAccountID == accountID && $0.cents == cents && abs($0.date.timeIntervalSince(date)) <= 86400 && friendKey($0.party ?? "") == friendKey(name) }
        var copy = self; copy.tngNotices.append(notice)
        self = try copy.validated()
        return id
    }

    func requireUnpaidLoan(_ entry: Expense) throws {
        guard !entry.isLoan || entry.shares.allSatisfy({ $0.repayments.isEmpty && ($0.returns ?? []).isEmpty }) else {
            throw LedgerError.invalid(tr("请先撤销还款，再删除借款。", "Undo repayments before deleting the loan.", "Batalkan bayaran balik sebelum memadam pinjaman."))
        }
    }
    /// Manual lending and all bank/TNG notices share one atomic write and one debt record.
    @discardableResult
    mutating func recordLoan(borrower: String, cents: Int, date: Date, accountID: String?,
                             replacing original: Expense? = nil, noticeID: String? = nil,
                             distinctConfirmed: Bool = false) throws -> String {
        let borrower = borrower.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !borrower.isEmpty, borrower.count <= 200, cents > 0, cents <= 10_000_000_000,
              date.timeIntervalSince1970.isFinite, date.timeIntervalSince1970 >= 0, date <= Date(),
              accountID == nil || bankAccounts.contains(where: { $0.id == accountID }) else {
            throw LedgerError.invalid(tr("请核对借款人、金额、日期和付款账户。", "Review borrower, amount, date and payment account.", "Semak peminjam, amaun, tarikh dan akaun bayaran."))
        }
        var copy = self
        var previous = original
        var noticeIndex: Int?
        if let noticeID {
            guard let n = tngNotices.firstIndex(where: { $0.id == noticeID }),
                  ["payment", "transfer", "unknown"].contains(tngNotices[n].kind),
                  ["pending", "transfer", "recorded"].contains(tngNotices[n].status),
                  tngNotices[n].resolution == nil, tngNotices[n].settlementID == nil,
                  !tngNotices[n].possibleDuplicate || distinctConfirmed else {
                throw LedgerError.invalid(tr("通知已处理或方向不符，请重新核对。", "Notification changed or has the wrong direction. Review it again.", "Notifikasi berubah atau arahnya salah. Semak semula."))
            }
            try requireUnusedPaymentReference(tngNotices[n])
            if let expenseID = tngNotices[n].expenseID {
                guard original == nil, let entry = expenses.first(where: { $0.id == expenseID }), !entry.isLoan else {
                    throw LedgerError.invalid("Record changed. Reopen it.")
                }
                previous = entry
            } else if original != nil { throw LedgerError.invalid("Record changed. Reopen it.") }
            noticeIndex = n
        }
        if let previous {
            guard expenses.first(where: { $0.id == previous.id }) == previous,
                  previous.paidByFriend == nil, previous.refunded == 0, previous.reimbursement == nil,
                  (previous.items ?? []).isEmpty, previous.charges == nil, previous.foreign == nil,
                  previous.recurringKey == nil, !hasActiveSettlement(expenseID: previous.id),
                  previous.isLoan || previous.shares.isEmpty else {
                throw LedgerError.invalid(tr("账目已有分账或其他关联，请先处理原账目。", "This entry has splits or other links. Review the original entry first.", "Rekod mempunyai bahagian atau pautan lain. Semak rekod asal dahulu."))
            }
            if previous.shares.contains(where: { !$0.repayments.isEmpty || !($0.returns ?? []).isEmpty }) {
                guard previous.cents == cents, previous.date == date, previous.shares.first?.name == borrower else {
                    throw LedgerError.invalid(tr("请先撤销还款，再修改借款人、金额或日期。", "Undo repayments before changing borrower, amount or date.", "Batalkan bayaran balik sebelum menukar peminjam, amaun atau tarikh."))
                }
            }
        }
        var entry = previous ?? Expense(merchant: borrower, cents: cents, date: date)
        entry.loan = true; entry.merchant = borrower; entry.cents = cents; entry.date = date
        entry.bankAccountID = accountID
        var share = (previous?.isLoan == true ? previous?.shares.first : nil) ?? Share(name: borrower, cents: cents)
        share.name = borrower; share.cents = cents; entry.shares = [share]
        if let n = noticeIndex {
            entry.source = tngNotices[n].provider
            entry.transactionReference = tngNotices[n].bankReference
            entry.note = previous?.note ?? tngNotices[n].note
            entry.place = previous?.place ?? tngNotices[n].place
            copy.tngNotices[n].kind = "payment"; copy.tngNotices[n].status = "recorded"
            copy.tngNotices[n].expenseID = entry.id; copy.tngNotices[n].bankAccountID = accountID
            copy.tngNotices[n].cents = cents; copy.tngNotices[n].date = date; copy.tngNotices[n].party = borrower
        }
        if let index = copy.expenses.firstIndex(where: { $0.id == entry.id }) { copy.expenses[index] = entry }
        else { copy.expenses.append(entry) }
        // Editing an existing loan keeps its original notification/account in sync.
        for n in copy.tngNotices.indices where copy.tngNotices[n].expenseID == entry.id {
            copy.tngNotices[n].bankAccountID = accountID
            copy.tngNotices[n].cents = cents; copy.tngNotices[n].date = date
        }
        self = try copy.validated()
        return entry.id
    }

    /// Debt entry timestamps may be later than the payment when entered afterwards.
    /// Use the same calendar-day eligibility as settlementPlan, not minute order.
    func noticeSettlementPlan(noticeID: String, friend: String, roundingCents: Int = 0) throws -> SettlementPlan {
        guard let notice = tngNotices.first(where: { $0.id == noticeID }), let cents = notice.cents,
              ["incoming", "payment", "transfer"].contains(notice.kind) else {
            throw settlementError("请先核对转账金额与收付款方向。", "Review the payment amount and direction first.", "Semak amaun dan arah bayaran dahulu.")
        }
        let selected = Set(friendDebtItems.filter {
            friendKey($0.friend) == friendKey(friend) && $0.balance != 0 &&
            Calendar.current.startOfDay(for: $0.expense.date) <= notice.date
        }.map(\.id))
        guard (0...100).contains(roundingCents), cents > roundingCents else { throw LedgerError.invalid("Invalid settlement rounding") }
        let plan = try settlementPlan(friend: friend, selected: selected, payment: cents - roundingCents, date: notice.date)
        guard roundingCents == 0 || abs(plan.fullNet) == cents - roundingCents else { throw LedgerError.invalid("Rounding must settle the remaining net debt exactly.") }
        guard plan.transfer == (notice.kind == "incoming" ? cents - roundingCents : -(cents - roundingCents)) else {
            throw settlementError("转账方向与这位朋友的净欠款相反，请核对所选朋友。", "The payment direction is opposite to this friend's net debt. Check the selected friend.", "Arah bayaran bertentangan dengan hutang bersih rakan ini. Semak rakan dipilih.")
        }
        return plan
    }

    func noticeSettlementRounding(noticeID: String, friend: String) -> Int {
        guard let notice = tngNotices.first(where: { $0.id == noticeID }), let cents = notice.cents else { return 0 }
        let net = friendDebtItems.filter {
            friendKey($0.friend) == friendKey(friend) && Calendar.current.startOfDay(for: $0.expense.date) <= notice.date
        }.reduce(0) { $0 + $1.balance }
        let difference = cents - abs(net)
        guard (1...100).contains(difference), (try? noticeSettlementPlan(noticeID: noticeID, friend: friend, roundingCents: difference)) != nil else { return 0 }
        return difference
    }

    /// Offset both sides and consume the received bank payment in one write.
    mutating func confirmIncomingNetSettlement(noticeID: String, plan: SettlementPlan, distinctConfirmed: Bool = false) throws -> String {
        guard let notice = tngNotices.first(where: { $0.id == noticeID }), notice.kind == "incoming",
              notice.status == "pending", plan.transfer > 0, plan.transfer == notice.cents else {
            throw LedgerError.invalid("Receipt changed. Review the net settlement again.")
        }
        return try confirmNoticeNetSettlement(noticeID: noticeID, plan: plan, distinctConfirmed: distinctConfirmed)
    }

    /// Apply both debt sides and the actual payment atomically, for either direction.
    mutating func confirmNoticeNetSettlement(noticeID: String, plan: SettlementPlan, distinctConfirmed: Bool = false, roundingCents: Int = 0) throws -> String {
        guard let notice = tngNotices.first(where: { $0.id == noticeID }),
              (0...100).contains(roundingCents),
              roundingCents == 0 || (abs(plan.fullNet) == abs(plan.transfer) && noticeSettlementRounding(noticeID: noticeID, friend: plan.friend) == roundingCents),
              plan.transfer != 0, abs(plan.transfer) + roundingCents == notice.cents,
              plan.transfer > 0 ? notice.kind == "incoming" : ["payment", "transfer"].contains(notice.kind),
              let accountID = notice.bankAccountID, bankAccounts.contains(where: { $0.id == accountID }) else {
            throw settlementError("请核对付款方向、金额并分配账户。", "Check the payment direction, amount and account.", "Semak arah bayaran, amaun dan akaun.")
        }
        var copy = self
        let id = try copy.confirmSettlement(plan)
        if let n = copy.tngNotices.firstIndex(where: { $0.id == noticeID }) { copy.tngNotices[n].settlementRoundingCents = roundingCents > 0 ? roundingCents : nil }
        try copy.linkSettlementPayment(settlementID: id, noticeID: noticeID, distinctConfirmed: distinctConfirmed)
        self = copy
        return id
    }

    /// Normalize live expenses and audit snapshots together. Amounts, dates, debt
    /// applications, bank links and settlement identities are never changed.
    func migratingLegacyCategorySplits() throws -> Ledger {
        guard expenses.contains(where: { $0.hasLegacyCategorySplits }) || settlements.contains(where: {
            $0.lines.contains(where: { $0.expense.hasLegacyCategorySplits }) || $0.convertedPayment?.hasLegacyCategorySplits == true
        }) else { return self }
        var copy = self
        copy.expenses = try expenses.map { try $0.migratingLegacyCategorySplits() }
        copy.settlements = try settlements.map { record in
            let lines = try record.lines.map { line in
                SettlementLine(expense: try line.expense.migratingLegacyCategorySplits(),
                               shareID: line.shareID, before: line.before, applied: line.applied)
            }
            return FriendSettlement(id: record.id, friend: record.friend, name: record.name,
                date: record.date, lines: lines, transfer: record.transfer, voidedAt: record.voidedAt,
                paymentNoticeID: record.paymentNoticeID,
                convertedPayment: try record.convertedPayment?.migratingLegacyCategorySplits())
        }
        try copy.validateBookkeeping()
        try copy.validateSettlements()
        return copy
    }

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
    func friendRefundItems(friend: String) -> [FriendDebtItem] {
        friendDebtItems.filter {
            friendKey($0.friend) == friendKey(friend) && $0.balance < 0
            && $0.expense.paidByFriend == nil && $0.expense.refunded > 0 && $0.shareID != nil
        }
    }
    func friendRefundPlan(friend: String, selected: Set<String>, cents: Int, date: Date) throws -> SettlementPlan {
        let eligible = Set(friendRefundItems(friend: friend).map(\.id))
        guard !selected.isEmpty, selected.isSubset(of: eligible) else {
            throw settlementError("请选择需要退钱的原账单。", "Choose the original expenses with money to return.", "Pilih belanja asal dengan wang yang perlu dipulangkan.")
        }
        return try repaymentPlan(friend: friend, selected: selected, payment: cents, date: date, direction: .outgoing)
    }
    func payableToPayer(_ expense: Expense) -> Int {
        guard expense.paidByFriend != nil else { return 0 }
        return max(0, expense.owingToPayer + (settledAmounts[FriendDebtItem.key(expense.id, nil)] ?? 0))
    }
    func hasActiveSettlement(expenseID: String) -> Bool {
        settlements.contains { $0.active && $0.lines.contains { $0.expense.id == expenseID && $0.applied != 0 } }
    }
    func requireUnsettledExpense(_ id: String) throws {
        guard !hasActiveSettlement(expenseID: id) else {
            throw settlementError("此账目已参与结算。请先撤销相关结算，再修改或删除；新增退款可直接记录。", "This expense is in a settlement. Undo its settlements before editing or deleting. New refunds can be recorded directly.", "Belanja ini dalam penyelesaian. Batalkan penyelesaian sebelum mengedit atau memadam. Bayaran balik baharu boleh dicatat terus.")
        }
    }
    /// Manual repayments settle only debts in the chosen direction, without offsetting other items.
    func repaymentPlan(friend: String, selected: Set<String>, payment: Int, date: Date, direction: AccountDirection) throws -> SettlementPlan {
        let items = friendDebtItems.filter { selected.contains($0.id) }
        guard direction != .neutral, payment > 0,
              items.allSatisfy({ direction == .incoming ? $0.balance > 0 : $0.balance < 0 }) else {
            throw settlementError("请选择与还款方向一致的未结欠款，并输入大于零的金额。", "Select outstanding debts in the repayment direction and enter a positive amount.", "Pilih hutang belum selesai mengikut arah bayaran balik dan masukkan amaun positif.")
        }
        return try settlementPlan(friend: friend, selected: selected, payment: payment, date: date)
    }
    func ledgerSettlements(in month: Date, search: String = "", filter: LedgerFilter = LedgerFilter()) throws -> [FriendSettlement] {
        try filter.validate()
        let low = try optionalMoney(filter.minimum), high = try optionalMoney(filter.maximum)
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let period = monthKey(month)
        return settlements.filter { record in
            guard record.active, record.paymentNoticeID == nil, monthKey(record.date) == period,
                  filter.source.isEmpty || filter.source == "手动",
                  filter.category.isEmpty || record.lines.contains(where: { $0.expense.hasCategory(filter.category) }) else { return false }
            let amount = abs(record.transfer)
            if let low, amount < low { return false }
            if let high, amount > high { return false }
            let text = record.name + " " + record.paymentTitle + " " + record.lines.map { $0.expense.merchant + " " + $0.expense.categorySummary }.joined(separator: " ")
            return query.isEmpty || text.localizedCaseInsensitiveContains(query)
        }.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date > $1.date }
    }
    func settlementPlan(friend: String, selected: Set<String>, payment: Int, date: Date) throws -> SettlementPlan {
        let key = friendKey(friend)
        let items = friendDebtItems.filter { friendKey($0.friend) == key && selected.contains($0.id) }
        guard !selected.isEmpty, selected.count <= 200, items.count == selected.count,
              items.allSatisfy({ $0.balance != 0 }),
              date.timeIntervalSince1970.isFinite, date.timeIntervalSince1970 >= 0, date <= Date(), payment >= 0 else {
            throw settlementError("选择未结清账目，结算日期不能早于相关消费、退款或还款，不能晚于今天。", "Select outstanding items. Settlement must be on or after their expenses, refunds and repayments, and no later than today.", "Pilih rekod belum selesai. Tarikh penyelesaian mesti selepas belanja, pulangan dan bayaran hutang berkaitan, dan tidak lewat daripada hari ini.")
        }
        if let laterItem = items.first(where: { latestDebtDate($0) > date }) {
            let earliest = dateLabel(latestDebtDate(laterItem))
            throw settlementError(
                "「\(laterItem.expense.displayName)」有 \(earliest) 的消费、退款或还款记录，晚于本次付款日期。请核对原账单的相关日期。",
                "\(laterItem.expense.displayName) has an expense, refund or repayment dated \(earliest), after this payment. Check the dates on the original entry.",
                "\(laterItem.expense.displayName) mempunyai belanja, pulangan atau bayaran bertarikh \(earliest), selepas bayaran ini. Semak tarikh rekod asal.")
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
            copy.tngNotices[n].settlementRoundingCents = nil
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
            $0.id != notice.id && (["recorded", "repayment", "reimbursement", "income", "ownTransfer", "settlement"].contains($0.status) || $0.resolution == "ownTransfer")
            && paymentIdentity($0) == identity
        }) else { throw settlementError("该银行交易参考编号已入账或用于还款、收入、转账或其他结算。请先撤销原确认。", "This bank reference is already recorded or used for a repayment, income, transfer or settlement. Undo the original confirmation first.", "Rujukan bank ini telah direkod atau digunakan untuk bayaran hutang, pendapatan, pindahan atau penyelesaian. Batalkan pengesahan asal dahulu.") }
    }
    mutating func linkSettlementPayment(settlementID: String, noticeID: String, distinctConfirmed: Bool = false) throws {
        guard let s = settlements.firstIndex(where: { $0.id == settlementID }), settlements[s].active,
              settlements[s].paymentNoticeID == nil, let n = tngNotices.firstIndex(where: { $0.id == noticeID }) else {
            throw settlementError("此结算或付款已关联，请重新查看。", "Settlement or payment is already linked. Reopen it.", "Penyelesaian atau bayaran telah dipautkan. Buka semula.")
        }
        let record = settlements[s], notice = tngNotices[n]
        guard record.transfer != 0, notice.cents == abs(record.transfer) + (notice.settlementRoundingCents ?? 0), notice.settlementID == nil,
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
                  (expense.items ?? []).isEmpty, expense.reimbursement == nil, expense.charges == nil,
                  expense.refunded == 0, expense.recurringKey == nil, expense.cents == notice.cents, expense.source == notice.provider,
                  !hasActiveSettlement(expenseID: expenseID), tngNotices.filter({ $0.expenseID == expenseID }).count == 1 else {
                throw settlementError("此自动付款已有物品、分账、退款、报销、税费或其他关联。请先处理原账目。", "This automatic payment has items, splits, refunds, reimbursement, charges or other links. Resolve the original entry first.", "Bayaran automatik ini mempunyai item, bahagian, pulangan, tuntutan, caj atau pautan lain. Selesaikan rekod asal dahulu.")
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
        var applied: [String: Int] = [:]
        var paymentIDs = Set<String>(), identities = Set<String>()
        // Dates have day precision in the editor. Preserve confirmation order
        // within a day, including notices recorded later with an earlier time.
        let ordered = settlements.enumerated().sorted {
            let lhs = Calendar.current.startOfDay(for: $0.element.date)
            let rhs = Calendar.current.startOfDay(for: $1.element.date)
            return lhs == rhs ? $0.offset < $1.offset : lhs < rhs
        }.map(\.element)
        for record in ordered {
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
                try snapshot.validateCharges()
                try snapshot.validateItems()
                guard snapshot.cents > 0, snapshot.cents <= 10_000_000_000, snapshot.shares.count <= 100,
                      snapshot.shares.allSatisfy({ $0.cents >= 0 && $0.cents <= snapshot.cents }),
                      (snapshot.refunds ?? []).count <= 10_000,
                      (snapshot.refunds ?? []).allSatisfy({ $0.personalCents >= 0 && $0.personalCents <= snapshot.cents }),
                      snapshot.personal >= 0, snapshot.merchant.count <= 200,
                      snapshot.date.timeIntervalSince1970 >= 0, snapshot.date.timeIntervalSince1970 < 4_102_444_800 else { throw invalidSettlementData() }
                guard abs(line.before) <= 10_000_000_000, abs(line.applied) <= abs(line.before),
                      line.applied == 0 || (line.applied > 0) == (line.before > 0), !line.expense.id.isEmpty else { throw invalidSettlementData() }
                guard record.active, line.applied != 0 else { continue }
                guard let current = byID[line.expense.id],
                      let expense = current.atSettlementRefunds(line.expense, date: record.date) else {
                    throw settlementError("已结算账目的金额、日期、分类、物品、付款人、分账或退款发生改变。请先撤销相关结算。", "A settled expense's amount, date, category, items, payer, shares or refunds changed. Undo its settlements first.", "Amaun, tarikh, kategori, item, pembayar, bahagian atau pulangan belanja diselesaikan berubah. Batalkan penyelesaian dahulu.")
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
                let available = base - (applied[line.id] ?? 0)
                guard line.applied > 0 ? available >= line.applied : available <= line.applied else { throw invalidSettlementData() }
                applied[line.id, default: 0] += line.applied
            }
            if record.active, let payment = record.paymentNoticeID {
                guard paymentIDs.insert(payment).inserted, let notice = tngNotices.first(where: { $0.id == payment }),
                      notice.settlementID == record.id, notice.status == "settlement", notice.expenseID == nil,
                      notice.resolution == nil, (notice.repaymentIDs ?? []).isEmpty,
                      record.transfer != 0, notice.cents == abs(record.transfer) + (notice.settlementRoundingCents ?? 0),
                      notice.settlementRoundingCents == nil || abs(record.transfer) == abs(net),
                      notice.date >= Calendar.current.startOfDay(for: record.date),
                      (record.transfer > 0 ? notice.kind == "incoming" : ["payment", "transfer"].contains(notice.kind)) else { throw invalidSettlementData() }
                if let identity = paymentIdentity(notice) { guard identities.insert(identity).inserted else { throw invalidSettlementData() } }
                try requireUnusedPaymentReference(notice)
            }
        }
        for notice in tngNotices where notice.settlementID != nil || notice.status == "settlement" {
            guard settlements.contains(where: { $0.active && $0.id == notice.settlementID && $0.paymentNoticeID == notice.id }) else { throw invalidSettlementData() }
        }
    }
}
