import Foundation

struct ReimbursementReceipt: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var cents: Int
    var date: Date
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
                  && $0.date.timeIntervalSince1970.isFinite && $0.date >= date && $0.date <= Date() }),
              claim.received <= claim.cents else {
            throw reviewError("请填写报销对象及有效金额。报销不能超过我实际承担的净金额，到账不能超过报销金额；若有退款或分账变动，请先调整报销。", "Enter a recipient and valid amounts. A claim cannot exceed your net share; receipts cannot exceed the claim. Adjust reimbursement before changing refunds or shares.", "Isi penerima dan amaun sah. Tuntutan tidak boleh melebihi bahagian bersih anda; penerimaan tidak boleh melebihi tuntutan. Laraskan tuntutan sebelum menukar pulangan atau bahagian.")
        }
    }
}

extension Ledger {
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
              var claim = expected.reimbursement, receipt.date <= Date() else {
            throw reviewError("账目已改变或到账日期无效，请重新打开。", "Entry changed or receipt date is invalid. Reopen it.", "Rekod berubah atau tarikh penerimaan tidak sah. Buka semula.")
        }
        claim.receipts.append(receipt)
        var entry = expected
        entry.reimbursement = claim
        try entry.validateReimbursement()
        expenses[index] = entry
    }
    mutating func undoReimbursementReceipt(expense expected: Expense, receiptID: String) throws {
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
