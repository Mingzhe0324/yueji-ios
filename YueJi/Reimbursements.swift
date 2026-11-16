import Foundation

struct ReimbursementAllocation: Equatable, Identifiable {
    let expenseID: String
    let outstanding: Int
    let cents: Int
    var id: String { expenseID }
}

struct ReimbursementReceipt: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var cents: Int
    var date: Date
    var noticeID: String? = nil
    var roundingCents: Int? = nil
}

struct ReimbursementClaim: Codable, Equatable {
    var recipient: String
    var cents: Int
    var receipts: [ReimbursementReceipt] = []
    var received: Int { receipts.reduce(0) { $0 + $1.cents } }
    var outstanding: Int { max(0, cents - received) }
    var status: String {
        if received == 0 { return tr("待报销", "Awaiting reimbursement", "Menunggu bayaran balik") }
        if outstanding > 0 { return tr("部分到账", "Partially received", "Sebahagian diterima") }
        return tr("已收齐", "Fully received", "Diterima sepenuhnya")
    }
}

extension Expense {
    /// Keep personal liability/refund and friend debt maths separate from reports.
    var reimbursementExcluded: Int { reimbursement?.cents ?? 0 }
    var personalSpending: Int { personal - reimbursementExcluded }
    func validateReimbursement() throws {
        guard let claim = reimbursement else { return }
        guard paidByFriend == nil, !claim.recipient.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              claim.recipient.count <= 200, claim.cents > 0, claim.cents <= 10_000_000_000,
              claim.cents <= personal, claim.receipts.count <= 500,
              Set(claim.receipts.map(\.id)).count == claim.receipts.count,
              claim.receipts.allSatisfy({ !$0.id.isEmpty && $0.id.count <= 200 && $0.cents > 0 && $0.cents <= claim.cents
                  && ($0.roundingCents == nil || ($0.noticeID == nil && ($0.roundingCents ?? 0) > 0 && ($0.roundingCents ?? 0) <= 10_000_000_000 - $0.cents))
                  && $0.date.timeIntervalSince1970.isFinite && $0.date >= date && $0.date <= Date() }),
              claim.received <= claim.cents else {
            throw reviewError("请填写报销对象及有效金额。报销不能超过我实际承担的净金额，到账不能超过报销金额；若有退款或分账变动，请先调整报销。", "Enter a recipient and valid amounts. A claim cannot exceed your net share; receipts cannot exceed the claim. Adjust reimbursement before changing refunds or shares.", "Isi penerima dan amaun sah. Tuntutan tidak boleh melebihi bahagian bersih anda; penerimaan tidak boleh melebihi tuntutan. Laraskan tuntutan sebelum menukar pulangan atau bahagian.")
        }
    }
}

extension Ledger {
    func requireUnlinkedReimbursement(_ expense: Expense) throws {
        guard !(expense.reimbursement?.receipts.contains { $0.noticeID != nil } ?? false) else {
            throw reviewError("请先撤销关联的报销收款，再删除原账目。", "Undo the linked reimbursement receipt before deleting this entry.", "Batalkan penerimaan tuntutan dipautkan sebelum memadam rekod ini.")
        }
    }
    func openReimbursements(on date: Date) -> [Expense] {
        expenses.filter { ($0.reimbursement?.outstanding ?? 0) > 0 && $0.date <= date }
            .sorted { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date }
    }

    // Suggestions never post money. Exact recipient identity comes first; amount
    // alone cannot identify a payer or choose between several plausible claims.
    func suggestedReimbursements(party: String, cents: Int, date: Date) -> Set<String> {
        let key = friendKey(party)
        guard !key.isEmpty, cents > 0 else { return [] }
        let matches = openReimbursements(on: date).filter { friendKey($0.reimbursement?.recipient ?? "") == key }
        let exact = matches.filter { $0.reimbursement?.outstanding == cents }
        if exact.count == 1 { return [exact[0].id] }
        if exact.count > 1 { return [] }
        if matches.count == 1 { return [matches[0].id] }
        if matches.count > 1, matches.reduce(0, { $0 + ($1.reimbursement?.outstanding ?? 0) }) == cents {
            return Set(matches.map(\.id))
        }
        return []
    }

    func reimbursementRounding(cents: Int, date: Date, selected: Set<String>) -> Int {
        guard cents > 0, !selected.isEmpty else { return 0 }
        let entries = openReimbursements(on: date).filter { selected.contains($0.id) }
        guard entries.count == selected.count else { return 0 }
        return max(0, cents - entries.reduce(0) { $0 + ($1.reimbursement?.outstanding ?? 0) })
    }

    func previewReimbursement(cents: Int, date: Date, selected: Set<String>, roundingCents: Int = 0) throws -> [ReimbursementAllocation] {
        let entries = openReimbursements(on: date).filter { selected.contains($0.id) }
        guard cents > 0, cents <= 10_000_000_000, date <= Date(), !selected.isEmpty,
              entries.count == selected.count, roundingCents >= 0, roundingCents < cents,
              roundingCents == 0 || roundingCents == reimbursementRounding(cents: cents, date: date, selected: selected) else { throw LedgerError.invalid("Select valid outstanding claims") }
        var remaining = cents - roundingCents
        var lines: [ReimbursementAllocation] = []
        for entry in entries {
            let outstanding = entry.reimbursement?.outstanding ?? 0
            let applied = min(remaining, outstanding)
            guard applied > 0 else { throw LedgerError.invalid("Remove claims that receive no money") }
            lines.append(ReimbursementAllocation(expenseID: entry.id, outstanding: outstanding, cents: applied))
            remaining -= applied
        }
        guard remaining == 0 else { throw LedgerError.invalid("Receipt exceeds selected outstanding claims") }
        return lines
    }

    mutating func setReimbursement(expense expected: Expense, claim: ReimbursementClaim?) throws {
        guard let index = expenses.firstIndex(where: { $0.id == expected.id }), expenses[index] == expected else {
            throw reviewError("账目已改变，请重新打开。", "Entry changed. Reopen it.", "Rekod berubah. Buka semula.")
        }
        if let old = expected.reimbursement {
            guard claim?.receipts == old.receipts || (claim == nil && old.receipts.isEmpty) else {
                throw reviewError("请先撤销到账记录，再取消报销。", "Undo receipts before removing reimbursement.", "Batalkan penerimaan sebelum membuang tuntutan.")
            }
        } else if !(claim?.receipts.isEmpty ?? true) {
            throw reviewError("请先保存报销，再记录到账。", "Save the claim before recording receipts.", "Simpan tuntutan sebelum merekod penerimaan.")
        }
        var entry = expected
        entry.reimbursement = claim
        try entry.validateReimbursement()
        expenses[index] = entry
    }
    mutating func receiveReimbursement(expense expected: Expense, receipt: ReimbursementReceipt) throws {
        guard let index = expenses.firstIndex(where: { $0.id == expected.id }), expenses[index] == expected,
              var claim = expected.reimbursement, receipt.date <= Date(),
              receipt.roundingCents == nil || receipt.cents == claim.outstanding else {
            throw reviewError("账目已改变或到账日期无效，请重新打开。", "Entry changed or receipt date is invalid. Reopen it.", "Rekod berubah atau tarikh penerimaan tidak sah. Buka semula.")
        }
        claim.receipts.append(receipt)
        var entry = expected
        entry.reimbursement = claim
        try entry.validateReimbursement()
        expenses[index] = entry
    }
    mutating func undoReimbursementReceipt(expense expected: Expense, receiptID: String) throws {
        if let receipt = expected.reimbursement?.receipts.first(where: { $0.id == receiptID }),
           let noticeID = receipt.noticeID {
            guard expenses.contains(expected), tngNotices.contains(where: { $0.id == noticeID && $0.status == "reimbursement" }) else {
                throw LedgerError.invalid("Receipt changed. Reopen it.")
            }
            try reopenTNGIncoming(id: noticeID)
            return
        }
        guard let index = expenses.firstIndex(where: { $0.id == expected.id }), expenses[index] == expected,
              var claim = expected.reimbursement,
              claim.receipts.contains(where: { $0.id == receiptID }) else {
            throw reviewError("到账记录已改变，请重新打开。", "Receipt changed. Reopen it.", "Penerimaan berubah. Buka semula.")
        }
        claim.receipts.removeAll { $0.id == receiptID }
        var entry = expected
        entry.reimbursement = claim
        try entry.validateReimbursement()
        expenses[index] = entry
    }
}
