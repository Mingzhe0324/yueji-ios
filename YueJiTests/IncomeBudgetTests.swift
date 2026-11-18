import XCTest
import UIKit
import PDFKit
@testable import YueJi

final class IncomeBudgetTests: XCTestCase {
    func testRefundUsesActualReceivingAccountForManualAndNotificationFlows() throws {
        let date = Date().addingTimeInterval(-120)
        for friendPaid in [false, true] {
            for automatic in [false, true] {
                var ledger = Ledger()
                let bank = BankAccount(name: "Bank", openingCents: 10000, openingDate: date.addingTimeInterval(-3600))
                let wallet = BankAccount(name: "Wallet", openingCents: 2000, openingDate: bank.openingDate)
                ledger.bankAccounts = [bank, wallet]
                let entry = Expense(bankAccountID: friendPaid ? nil : bank.id, merchant: "Shop", cents: 4000, date: date,
                                    shares: friendPaid ? [Share(name: "James", cents: 0)] : [], paidByFriend: friendPaid ? "James" : nil)
                ledger.expenses = [entry]
                let refundDate = date.addingTimeInterval(60)
                if automatic {
                    let notice = TNGNotice(bankAccountID: wallet.id, body: "Refund received", title: "", date: refundDate,
                                          usesReceivedDate: false, kind: "incoming", status: "pending", cents: 1000, party: "Shop")
                    ledger.tngNotices = [notice]
                    try ledger.resolveNotice(id: notice.id, purpose: "refund", party: "Shop", cents: 1000, date: refundDate, relatedID: entry.id)
                } else {
                    try ledger.addRefund(expenseID: entry.id, cents: 1000, date: refundDate, receivedByMe: true, bankAccountID: wallet.id)
                }
                ledger = try JSONDecoder().decode(Ledger.self, from: JSONEncoder().encode(ledger)).validated()
                XCTAssertEqual(ledger.bankBalance(bank), friendPaid ? 10000 : 6000)
                XCTAssertEqual(ledger.bankBalance(wallet), 3000, "Credit the actual receiver once, not the purchase account")
                let statementRow = StatementRow(id: "refund-row", date: refundDate, description: "Refund", serial: "1", debit: 0, credit: 1000, balance: 3000)
                XCTAssertTrue(ledger.statementMayExist(statementRow, accountID: wallet.id))
                XCTAssertFalse(ledger.statementMayExist(statementRow, accountID: bank.id), "Do not hide a different bank's receipt as this wallet refund")
                XCTAssertEqual(ledger.statementBalance(wallet, before: refundDate), 2000)
                XCTAssertEqual(ledger.statementBalance(wallet, before: refundDate.addingTimeInterval(1)), 3000)
                XCTAssertEqual(ledger.spending(in: date), 3000)
                if friendPaid { XCTAssertEqual(ledger.payableToPayer(ledger.expenses[0]), 4000, "The friend has not received this refund") }
                if automatic {
                    try ledger.reopenResolvedNotice(id: ledger.tngNotices[0].id)
                    // Reopened imported money awaits review and retains its original notification behavior.
                    try ledger.resolveTNGIncoming(id: ledger.tngNotices[0].id, purpose: "ignored", date: refundDate)
                } else {
                    try ledger.removeRefund(expenseID: entry.id, refundID: try XCTUnwrap(ledger.expenses[0].refunds?.first?.id))
                }
                XCTAssertEqual(ledger.bankBalance(wallet), 2000)
                XCTAssertEqual(ledger.bankBalance(bank), friendPaid ? 10000 : 6000)
                XCTAssertEqual(ledger.spending(in: date), 4000)
            }
        }
    }

    func testRefundToFriendDoesNotCreditMeAndMissingRefundAccountRemainsReviewable() throws {
        let date = Date().addingTimeInterval(-120)
        let bank = BankAccount(name: "Bank", openingCents: 10000, openingDate: date.addingTimeInterval(-3600))
        var ledger = Ledger(); ledger.bankAccounts = [bank]
        let entry = Expense(merchant: "Shop", cents: 4000, date: date, shares: [Share(name: "James", cents: 0)], paidByFriend: "James")
        ledger.expenses = [entry]
        XCTAssertThrowsError(try ledger.addRefund(expenseID: entry.id, cents: 1000, date: date, receivedByMe: false, bankAccountID: bank.id))
        XCTAssertNil(ledger.expenses[0].refunds)
        try ledger.addRefund(expenseID: entry.id, cents: 1000, date: date, receivedByMe: false)
        XCTAssertEqual(ledger.bankBalance(bank), 10000)
        XCTAssertEqual(ledger.payableToPayer(ledger.expenses[0]), 3000)
        let notice = TNGNotice(body: "Refund to me", title: "", date: date, usesReceivedDate: false, kind: "incoming", status: "pending", cents: 500, party: "Shop")
        ledger.tngNotices = [notice]
        try ledger.resolveNotice(id: notice.id, purpose: "refund", party: "Shop", cents: 500, date: date, relatedID: entry.id)
        XCTAssertEqual(BookkeepingReviewItem.items(in: ledger).first?.reason, .account)
        XCTAssertEqual(ledger.bankBalance(bank), 10000)
        try ledger.assignNoticeAccount(id: notice.id, accountID: bank.id)
        XCTAssertEqual(ledger.bankBalance(bank), 10500)
        XCTAssertEqual(ledger.payableToPayer(ledger.expenses[0]), 3000)
        XCTAssertTrue(BookkeepingReviewItem.items(in: ledger).isEmpty)
        _ = try ledger.validated()
        var invalid = ledger; invalid.bankAccounts = []
        XCTAssertThrowsError(try invalid.validated(), "A refund must not point to a deleted account")
    }

    func testLegacyRefundStillUsesOriginalAccountAndRejectsInvalidExplicitDestination() throws {
        let date = Date().addingTimeInterval(-120)
        let bank = BankAccount(name: "Bank", openingCents: 10000, openingDate: date.addingTimeInterval(-3600))
        var ledger = Ledger(); ledger.bankAccounts = [bank]
        let entry = Expense(bankAccountID: bank.id, merchant: "Shop", cents: 4000, date: date)
        ledger.expenses = [entry]
        XCTAssertThrowsError(try ledger.addRefund(expenseID: entry.id, cents: 500, date: date, bankAccountID: "missing"))
        XCTAssertNil(ledger.expenses[0].refunds)
        try ledger.addRefund(expenseID: entry.id, cents: 1000, date: date)
        ledger = try JSONDecoder().decode(Ledger.self, from: JSONEncoder().encode(ledger)).validated()
        XCTAssertNil(ledger.expenses[0].refunds?[0].bankAccountID)
        XCTAssertEqual(ledger.bankBalance(bank), 7000)
    }

    func testTNGOCRRowsValidateAcrossPagesAndSaveWithoutChangingBalances() throws {
        let statement = try TNGStatementReader.parse(header: tngHeader(), pages: tngOCRPages())
        XCTAssertEqual(statement.provider, "TNG")
        XCTAssertTrue(statement.reviewOnly)
        XCTAssertEqual(statement.opening, 10000)
        XCTAssertEqual(statement.closing, 11000)
        XCTAssertEqual(statement.rows.count, 3) // Zero-valued row is checked, not posted.
        XCTAssertEqual(statement.debitTotal, 1000)
        XCTAssertEqual(statement.creditTotal, 2000)
        XCTAssertEqual(statement.suffix, "1234")
        let account = BankAccount(name: "Wallet", openingCents: 10000, openingDate: statement.start, institution: "TNG eWallet")
        var ledger = Ledger(); ledger.bankAccounts = [account]
        let result = try ledger.importStatement(statement, account: account, categories: [:])
        XCTAssertEqual(result.pending, 3)
        XCTAssertEqual(result.added, 0)
        XCTAssertEqual(ledger.bankBalance(account), 10000)
        XCTAssertTrue(ledger.tngNotices.allSatisfy { $0.balanceHeldForReview == true && $0.sourceBank == "TNG" })
        ledger = try JSONDecoder().decode(Ledger.self, from: JSONEncoder().encode(ledger))
        XCTAssertEqual(try ledger.importStatement(statement, account: account, categories: [:]).skipped, 3)
        XCTAssertEqual(ledger.tngNotices.count, 3)
        try ledger.undoStatementImport(batch: result.batch)
        XCTAssertTrue(ledger.tngNotices.isEmpty)
        XCTAssertEqual(ledger.bankBalance(account), 10000)
        var card = account; card.institution = "TNG Card"; ledger.bankAccounts = [card]
        XCTAssertThrowsError(try ledger.importStatement(statement, account: card, categories: [:]))
    }

    func testTNGOCRRejectsMissingRowsAmountsWrongTypesAndBrokenBalanceChain() throws {
        let header = try tngHeader()
        var pages = tngOCRPages()
        pages[1][5][0] = .init(text: "RM109.99", top: 0.08)
        XCTAssertThrowsError(try TNGStatementReader.parse(header: header, pages: pages))
        pages = tngOCRPages(); pages[0][4].removeLast()
        XCTAssertThrowsError(try TNGStatementReader.parse(header: header, pages: pages))
        pages = tngOCRPages(); pages[0][0].removeLast()
        XCTAssertThrowsError(try TNGStatementReader.parse(header: header, pages: pages))
        pages = tngOCRPages(); pages[0][2][1] = .init(text: "Receive from Wallet", top: 0.52)
        XCTAssertThrowsError(try TNGStatementReader.parse(header: header, pages: pages))
        pages = tngOCRPages(); pages[0][1][1] = .init(text: "Failed", top: 0.52)
        XCTAssertThrowsError(try TNGStatementReader.parse(header: header, pages: pages))
        pages = tngOCRPages(); pages[0][4][0] = .init(text: "RM20.00", top: 0.75)
        XCTAssertThrowsError(try TNGStatementReader.parse(header: header, pages: pages))
        pages = tngOCRPages(); pages[0][0][0] = .init(text: "31/02/2026", top: 0.42)
        XCTAssertThrowsError(try TNGStatementReader.parse(header: header, pages: pages))
        pages = tngOCRPages(); pages[0][5][0] = .init(text: "RM120.00", top: 0.42, confidence: 0.1)
        XCTAssertThrowsError(try TNGStatementReader.parse(header: header, pages: pages))
        XCTAssertThrowsError(try TNGStatementReader.parse(header: header, pages: [tngOCRPages()[1], tngOCRPages()[0]]))
    }

    func testTNGOCRNumericNormalizationNeverGuessesMissingDigitsOrDecimals() throws {
        XCTAssertEqual(try TNGStatementReader.amount("RM I,OOO.Ol"), 100001)
        XCTAssertEqual(try TNGStatementReader.amount("RM0.00"), 0)
        for bad in ["RM100", "RM1.0", "RM1,00.00", "RM-10.00", "10.00", "RM1S.00", "RM10.00 RM20.00"] {
            XCTAssertThrowsError(try TNGStatementReader.amount(bad), bad)
        }
        XCTAssertTrue(try TNGStatementReader.incoming("DUITNOW_RECEI VEFROM"))
        XCTAssertFalse(try TNGStatementReader.incoming("DUITNOW_TRANS FERTO"))
        XCTAssertThrowsError(try TNGStatementReader.incoming("Refund pending"))
    }

    func testNativeTNGImagePDFRecognizesUprightAndSidewaysMultipageExport() throws {
        for sideways in [false, true] {
            let pdf = syntheticTNGPDF(sideways: sideways)
            XCTAssertEqual(PDFDocument(data: pdf)?.page(at: 0)?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "", "")
            let statement = try RHBStatement.read(pdf, expectedProvider: "TNG")
            XCTAssertEqual(statement.provider, "TNG")
            XCTAssertEqual(statement.suffix, "1234")
            XCTAssertEqual(statement.rows.count, 3)
            XCTAssertEqual(statement.opening, 10000)
            XCTAssertEqual(statement.closing, 11000)
            XCTAssertTrue(statement.reviewOnly)
        }
    }

    private func tngHeader() throws -> TNGStatementReader.Header {
        .init(wallet: "10000000001234", start: try TNGStatementReader.date("1 September 2026", format: "d MMMM yyyy"),
              end: try TNGStatementReader.date("30 September 2026", format: "d MMMM yyyy"))
    }
    private func tngOCRPages() -> [[[TNGStatementReader.Line]]] {
        func page(_ records: [(Double, [String])]) -> [[TNGStatementReader.Line]] {
            (0..<6).map { column in records.map { .init(text: $0.1[column], top: $0.0) } }
        }
        return [page([
            (0.42, ["01/09/2026", "Success", "Receive from Wallet", "Sender", "RM20.00", "RM120.00"]),
            (0.52, ["02/09/2026", "Success", "Payment", "Cafe", "RM7.00", "RM113.00"])
        ]), page([
            (0.08, ["03/09/2026", "Success", "Transfer to Wallet", "Fund Transfer", "RM3.00", "RM110.00"]),
            (0.18, ["04/09/2026", "Success", "PayDirect Payment", "Parking", "RM0.00", "RM110.00"])
        ])]
    }
    /// Generated fictitious raster pages; never embed a user's financial PDF.
    private func syntheticTNGPDF(sideways: Bool) -> Data {
        let pageSize = CGSize(width: 792, height: 612)
        let format = UIGraphicsImageRendererFormat(); format.scale = 3; format.opaque = true
        let images = (0..<2).map { index in
            UIGraphicsImageRenderer(size: pageSize, format: format).image { context in
                UIColor.white.setFill(); context.fill(CGRect(origin: .zero, size: pageSize))
                func text(_ value: String, _ x: Double, _ y: Double, size: CGFloat = 9) {
                    (value as NSString).draw(at: CGPoint(x: x * 792, y: y * 612), withAttributes: [.font: UIFont.systemFont(ofSize: size), .foregroundColor: UIColor.black])
                }
                if index == 0 {
                    text("TNG WALLET TRANSACTION HISTORY", 0.345, 0.204, size: 12)
                    text("Registered Name", 0.024, 0.250); text("TEST USER", 0.225, 0.250)
                    text("Wallet ID", 0.024, 0.274); text("10000000001234", 0.225, 0.274)
                    text("Transaction Period", 0.024, 0.356)
                    text("1 September 2026 - 30 September 2026", 0.225, 0.356)
                    for (column, title) in ["Date", "Status", "Transaction Type", "Description", "Amount (RM)", "Wallet Balance"].enumerated() {
                        text(title, TNGStatementReader.columns[column].0 + 0.002, 0.397)
                    }
                }
                for column in 0..<6 {
                    for line in tngOCRPages()[index][column] {
                        text(line.text, TNGStatementReader.columns[column].0 + 0.002, line.top)
                    }
                }
                text("This is a system generated email. Thank you.", 0.024, 0.89)
            }
        }
        let bounds = CGRect(x: 0, y: 0, width: sideways ? 612 : 792, height: sideways ? 792 : 612)
        return UIGraphicsPDFRenderer(bounds: bounds).pdfData { context in
            for image in images {
                context.beginPage(); context.cgContext.saveGState()
                if sideways { context.cgContext.translateBy(x: 0, y: 792); context.cgContext.rotate(by: -.pi / 2) }
                image.draw(in: CGRect(origin: .zero, size: pageSize))
                context.cgContext.restoreGState()
            }
        }
    }

    func testSingleOwnTransferNotificationUpdatesBothAccountsForBankAndTNG() throws {
        for provider in ["TNG", "CIMB"] {
            for incoming in [true, false] {
                let (base, from, to, date) = ownTransferFixture()
                var ledger = base
                let notice = ownTransferNotice(incoming: incoming, accountID: incoming ? to.id : from.id, date: date, provider: provider)
                ledger.tngNotices = [notice]
                try ledger.resolveOwnAccountTransfer(noticeIDs: [notice.id], fromAccountID: from.id, toAccountID: to.id,
                                                     cents: 1000, date: date, note: "Top-up")
                XCTAssertEqual(ledger.bankBalance(from), 9000)
                XCTAssertEqual(ledger.bankBalance(to), 3000)
                XCTAssertEqual(ledger.bankTransfers.count, 1)
                XCTAssertEqual(ledger.bankTransfers[0].noticeIDs, [notice.id])
                XCTAssertEqual(ledger.bankTransfers[0].note, "Top-up")
                XCTAssertTrue(ledger.incomes.isEmpty)
                XCTAssertTrue(ledger.expenses.isEmpty)
                XCTAssertFalse(ledger.tngNotices[0].isConfirmedIncome)
                XCTAssertEqual(ledger.tngNotices[0].resolution, "ownTransfer")
                let restored = try JSONDecoder().decode(Ledger.self, from: JSONEncoder().encode(ledger)).validated()
                XCTAssertEqual(restored.bankBalance(from) + restored.bankBalance(to), 12000)
                XCTAssertThrowsError(try ledger.resolveOwnAccountTransfer(noticeIDs: [notice.id], fromAccountID: from.id,
                    toAccountID: to.id, cents: 1000, date: date))
                XCTAssertEqual(ledger.bankTransfers.count, 1)
            }
        }
    }

    func testLaterOppositeNotificationLinksOriginalTransferInEitherArrivalOrder() throws {
        for incomingFirst in [true, false] {
            let (base, from, to, date) = ownTransferFixture()
            var ledger = base
            let first = ownTransferNotice(incoming: incomingFirst, accountID: incomingFirst ? to.id : from.id, date: date)
            let later = ownTransferNotice(incoming: !incomingFirst, accountID: incomingFirst ? from.id : to.id, date: date.addingTimeInterval(20))
            ledger.tngNotices = [first]
            try ledger.resolveOwnAccountTransfer(noticeIDs: [first.id], fromAccountID: from.id, toAccountID: to.id, cents: 1000, date: date)
            let transferID = try XCTUnwrap(ledger.bankTransfers.first?.id)
            ledger.tngNotices.append(later)
            try ledger.resolveOwnAccountTransfer(noticeIDs: [later.id], fromAccountID: from.id, toAccountID: to.id,
                                                 cents: 1000, date: date, existingTransferID: transferID)
            XCTAssertEqual(ledger.bankTransfers.count, 1)
            XCTAssertEqual(ledger.bankTransfers[0].noticeIDs?.count, 2)
            XCTAssertEqual(ledger.bankBalance(from), 9000)
            XCTAssertEqual(ledger.bankBalance(to), 3000)
            ledger = try JSONDecoder().decode(Ledger.self, from: JSONEncoder().encode(ledger)).validated()
            try ledger.reopenResolvedNotice(id: later.id)
            XCTAssertTrue(ledger.bankTransfers.isEmpty)
            XCTAssertEqual(ledger.bankBalance(from), 10000)
            XCTAssertEqual(ledger.bankBalance(to), 2000)
            XCTAssertTrue(ledger.tngNotices.allSatisfy { $0.status == "pending" && $0.resolution == nil && $0.balanceHeldForReview == true })
            // Reconfirming after undo restores exactly one pair of balance movements.
            try ledger.resolveOwnAccountTransfer(noticeIDs: [first.id, later.id], fromAccountID: from.id, toAccountID: to.id, cents: 1000, date: date)
            XCTAssertEqual(ledger.bankBalance(from), 9000)
            XCTAssertEqual(ledger.bankBalance(to), 3000)
        }
    }

    func testRecordedPaymentCanBecomeOwnTransferWithoutDoubleDebit() throws {
        let (base, from, to, date) = ownTransferFixture()
        var ledger = base
        _ = try ledger.receiveTNG(body: "You have paid RM10.00 for WALLET.", title: "Payment", date: date, eventID: nil, sourceApp: "TNG")
        let id = try XCTUnwrap(ledger.tngNotices.first?.id)
        try ledger.assignNoticeAccount(id: id, accountID: from.id)
        XCTAssertEqual(ledger.expenses.count, 1)
        XCTAssertEqual(ledger.bankBalance(from), 9000)
        try ledger.resolveOwnAccountTransfer(noticeIDs: [id], fromAccountID: from.id, toAccountID: to.id, cents: 1000, date: date)
        XCTAssertTrue(ledger.expenses.isEmpty)
        XCTAssertNil(ledger.tngNotices[0].expenseID)
        XCTAssertEqual(ledger.bankBalance(from), 9000)
        XCTAssertEqual(ledger.bankBalance(to), 3000)
        let transfer = try XCTUnwrap(ledger.bankTransfers.first)
        try ledger.deleteBankTransfer(transfer)
        XCTAssertEqual(ledger.bankBalance(from), 10000)
        XCTAssertEqual(ledger.bankBalance(to), 2000)
    }

    func testManualTransferCanAcquireReceiptAndKeepsLinkedAmountImmutable() throws {
        let (base, from, to, date) = ownTransferFixture()
        var ledger = base
        let transfer = BankTransfer(fromAccountID: from.id, toAccountID: to.id, cents: 1000, date: date)
        try ledger.saveBankTransfer(transfer, replacing: nil)
        let notice = ownTransferNotice(incoming: true, accountID: to.id, date: date)
        ledger.tngNotices = [notice]
        try ledger.resolveOwnAccountTransfer(noticeIDs: [notice.id], fromAccountID: from.id, toAccountID: to.id,
                                             cents: 1000, date: date, existingTransferID: transfer.id)
        XCTAssertEqual(ledger.bankBalance(from), 9000)
        XCTAssertEqual(ledger.bankBalance(to), 3000)
        let linked = try XCTUnwrap(ledger.bankTransfers.first)
        var changed = linked; changed.cents = 2000
        XCTAssertThrowsError(try ledger.saveBankTransfer(changed, replacing: linked))
        changed = linked; changed.date = date.addingTimeInterval(-1)
        XCTAssertThrowsError(try ledger.saveBankTransfer(changed, replacing: linked))
        XCTAssertThrowsError(try ledger.assignNoticeAccount(id: notice.id, accountID: from.id))
        let third = BankAccount(name: "Other bank", openingCents: 5000, openingDate: from.openingDate)
        ledger.bankAccounts.append(third)
        changed = linked; changed.toAccountID = third.id
        try ledger.saveBankTransfer(changed, replacing: linked)
        XCTAssertEqual(ledger.tngNotices[0].bankAccountID, third.id)
        XCTAssertEqual(ledger.bankBalance(to), 2000)
        XCTAssertEqual(ledger.bankBalance(third), 6000)
    }

    func testOwnTransferRejectsWrongAccountsAmountsSameSideAndUsedReferencesAtomically() throws {
        let (base, from, to, date) = ownTransferFixture()
        var ledger = base
        var notice = ownTransferNotice(incoming: true, accountID: to.id, date: date)
        notice.bankReference = "REF-OWN-123"
        ledger.tngNotices = [notice]
        XCTAssertThrowsError(try ledger.resolveOwnAccountTransfer(noticeIDs: [notice.id], fromAccountID: to.id, toAccountID: from.id, cents: 1000, date: date))
        XCTAssertThrowsError(try ledger.resolveOwnAccountTransfer(noticeIDs: [notice.id], fromAccountID: from.id, toAccountID: to.id, cents: 999, date: date))
        XCTAssertThrowsError(try ledger.resolveOwnAccountTransfer(noticeIDs: [notice.id], fromAccountID: to.id, toAccountID: to.id, cents: 1000, date: date))
        var sameSide = notice; sameSide.id = UUID().uuidString; sameSide.bankReference = nil
        ledger.tngNotices.append(sameSide)
        XCTAssertThrowsError(try ledger.resolveOwnAccountTransfer(noticeIDs: [notice.id, sameSide.id], fromAccountID: from.id, toAccountID: to.id, cents: 1000, date: date))
        XCTAssertEqual(ledger.tngNotices, [notice, sameSide])
        XCTAssertTrue(ledger.bankTransfers.isEmpty)
        ledger.tngNotices.removeLast()
        try ledger.resolveOwnAccountTransfer(noticeIDs: [notice.id], fromAccountID: from.id, toAccountID: to.id, cents: 1000, date: date)
        var replay = notice; replay.id = UUID().uuidString
        ledger.tngNotices.append(replay)
        let before = ledger.tngNotices
        XCTAssertThrowsError(try ledger.resolveOwnAccountTransfer(noticeIDs: [replay.id], fromAccountID: from.id, toAccountID: to.id, cents: 1000, date: date))
        XCTAssertThrowsError(try ledger.requireUnusedPaymentReference(replay))
        XCTAssertEqual(ledger.tngNotices, before)
        XCTAssertEqual(ledger.bankTransfers.count, 1)
    }

    func testOwnTransferRepairsLegacyOneSidedClassificationAndRespectsOpeningCutoff() throws {
        let (base, from, originalTo, date) = ownTransferFixture()
        var ledger = base
        var to = originalTo; to.openingDate = date.addingTimeInterval(1)
        ledger.bankAccounts = [from, to]
        var notice = ownTransferNotice(incoming: true, accountID: to.id, date: date)
        notice.status = "ownTransfer"
        ledger.tngNotices = [notice]
        try ledger.resolveOwnAccountTransfer(noticeIDs: [notice.id], fromAccountID: from.id, toAccountID: to.id, cents: 1000, date: date)
        XCTAssertEqual(ledger.bankBalance(from), 9000)
        XCTAssertEqual(ledger.bankBalance(to), 2000) // Already included in the opening balance.
    }

    func testUnknownTransferRequiresExplicitDirectionAndDuplicateReview() throws {
        let (base, from, to, date) = ownTransferFixture()
        var ledger = base
        var notice = ownTransferNotice(incoming: true, accountID: to.id, date: date)
        notice.kind = "unknown"; notice.bankAccountID = nil; notice.possibleDuplicate = true
        ledger.tngNotices = [notice]
        XCTAssertThrowsError(try ledger.resolveOwnAccountTransfer(noticeIDs: [notice.id], fromAccountID: from.id, toAccountID: to.id, cents: 1000, date: date, distinctConfirmed: true))
        XCTAssertThrowsError(try ledger.resolveOwnAccountTransfer(noticeIDs: [notice.id], fromAccountID: from.id, toAccountID: to.id, cents: 1000, date: date, unknownIsIncoming: true))
        XCTAssertEqual(ledger.tngNotices, [notice])
        try ledger.resolveOwnAccountTransfer(noticeIDs: [notice.id], fromAccountID: from.id, toAccountID: to.id, cents: 1000, date: date,
                                             distinctConfirmed: true, unknownIsIncoming: true)
        XCTAssertEqual(ledger.tngNotices[0].kind, "incoming")
        XCTAssertEqual(ledger.bankBalance(from), 9000)
        XCTAssertEqual(ledger.bankBalance(to), 3000)
    }

    private func ownTransferFixture() -> (Ledger, BankAccount, BankAccount, Date) {
        let date = Date().addingTimeInterval(-60)
        let from = BankAccount(name: "Bank", openingCents: 10000, openingDate: date.addingTimeInterval(-3600))
        let to = BankAccount(name: "TNG", openingCents: 2000, openingDate: from.openingDate)
        var ledger = Ledger(); ledger.bankAccounts = [from, to]
        return (ledger, from, to, date)
    }

    private func ownTransferNotice(incoming: Bool, accountID: String, date: Date, provider: String = "TNG") -> TNGNotice {
        TNGNotice(bankAccountID: accountID, body: incoming ? "Received RM10.00" : "Transferred RM10.00", title: "Transfer", date: date,
                  usesReceivedDate: false, kind: incoming ? "incoming" : "transfer", status: incoming ? "pending" : "transfer",
                  cents: 1000, party: "Me", sourceBank: provider)
    }

    func testRepairMissingAccountsUsesRulesWithoutDoubleDeduction() throws {
        let date = Date().addingTimeInterval(-60)
        let wallet = BankAccount(name: "TNG", openingCents: 10000, openingDate: date.addingTimeInterval(-3600), institution: "TNG eWallet", automaticSource: "TNG")
        let other = BankAccount(name: "Other", openingCents: 20000, openingDate: wallet.openingDate)
        var ledger = Ledger()
        _ = try ledger.receiveTNG(body: "You have paid RM10.00 for CAFE.", title: "Payment", date: date, eventID: nil, sourceApp: "TNG")
        XCTAssertEqual(ledger.expenses.count, 1)
        XCTAssertNil(ledger.expenses[0].bankAccountID)
        ledger.bankAccounts = [wallet, other]
        XCTAssertEqual(try ledger.reconcileAutomaticAccounts(), 1)
        XCTAssertEqual(ledger.expenses[0].bankAccountID, wallet.id)
        XCTAssertEqual(ledger.bankBalance(wallet), 9000)
        XCTAssertEqual(try ledger.reconcileAutomaticAccounts(), 0)
        XCTAssertEqual(ledger.bankBalance(wallet), 9000)
        try ledger.assignNoticeAccount(id: ledger.tngNotices[0].id, accountID: other.id)
        XCTAssertEqual(try ledger.reconcileAutomaticAccounts(), 0)
        XCTAssertEqual(ledger.bankBalance(other), 19000)
        XCTAssertEqual(ledger.bankBalance(wallet), 10000)
    }

    func testAccountRepairSkipsAmbiguityOldDatesAndDuplicates() throws {
        let date = Date().addingTimeInterval(-60)
        let first = BankAccount(name: "CIMB", openingCents: 10000, openingDate: date, automaticSource: "CIMB", automaticSuffix: "1234")
        var second = first; second.id = UUID().uuidString
        var ledger = Ledger(); ledger.bankAccounts = [first, second]
        let notice = TNGNotice(body: "Paid RM10", title: "", date: date, usesReceivedDate: false, kind: "payment", status: "pending", cents: 1000, party: "Cafe", sourceBank: "CIMB", accountSuffix: "1234")
        ledger.tngNotices = [notice]
        XCTAssertEqual(try ledger.reconcileAutomaticAccounts(), 0)
        ledger.bankAccounts = [first]
        ledger.tngNotices[0].date = date.addingTimeInterval(-1)
        XCTAssertEqual(try ledger.reconcileAutomaticAccounts(), 0)
        ledger.tngNotices[0].date = date; ledger.tngNotices[0].possibleDuplicate = true
        XCTAssertEqual(try ledger.reconcileAutomaticAccounts(), 0)
        ledger.tngNotices[0].possibleDuplicate = false; ledger.tngNotices[0].accountSuffix = "5678"
        XCTAssertEqual(try ledger.reconcileAutomaticAccounts(), 0)
        ledger.tngNotices[0].accountSuffix = "1234"
        XCTAssertEqual(try ledger.reconcileAutomaticAccounts(), 1)
        XCTAssertEqual(ledger.bankBalance(first), 10000) // Linking is not confirmation of an unclear payment.
    }

    func testGrabVisaChargeRequiresCardBindingAndDeduplicatesBooking() throws {
        let date = Date()
        let body = "Your Visa 1234 has been charged MYR 38.74 for booking TEST001-ABC123."
        let parsed = try XCTUnwrap(parseFinancialNotification(body, title: "Grab", sourceApp: "Grab"))
        XCTAssertEqual(parsed.sourceBank, "Grab Card")
        XCTAssertEqual(parsed.accountSuffix, "1234")
        XCTAssertEqual(parsed.reference, "TEST001-ABC123")
        XCTAssertEqual(parsed.cents, 3874)
        let wrapped = "Your Visa 1234 has been charged MYR 38.74\nfor booking TEST001-\nABC123."
        XCTAssertEqual(parseFinancialNotification(wrapped, title: "Grab", sourceApp: "Grab")?.reference, parsed.reference)
        XCTAssertNil(parseFinancialNotification(body, title: "Grab", sourceApp: "GrabPay"))
        var ledger = Ledger()
        _ = try ledger.receiveTNG(body: body, title: "Grab", date: date, eventID: nil, sourceApp: "Grab")
        XCTAssertTrue(ledger.expenses.isEmpty)
        XCTAssertEqual(ledger.tngNotices.first?.status, "pending")
        let card = BankAccount(name: "Visa", openingCents: 10000, openingDate: date.addingTimeInterval(-3600), institution: "Maybank", automaticSource: "Grab Card", automaticSuffix: "1234")
        let wallet = BankAccount(name: "GrabPay", openingCents: 5000, openingDate: date.addingTimeInterval(-3600), institution: "GrabPay", automaticSource: "Grab Card", automaticSuffix: "1234")
        ledger = Ledger(); ledger.bankAccounts = [card, wallet]
        for _ in 0..<2 {
            _ = try ledger.receiveTNG(body: body, title: "Grab", date: date, eventID: nil, sourceApp: "Grab")
        }
        XCTAssertEqual(ledger.expenses.count, 1)
        XCTAssertEqual(ledger.bankBalance(card), 6126)
        XCTAssertEqual(ledger.bankBalance(wallet), 5000)
        _ = try ledger.receiveTNG(body: wrapped, title: "Grab", date: date, eventID: nil, sourceApp: "Grab")
        XCTAssertEqual(ledger.expenses.count, 1, "Line wrapping must not duplicate a card charge")
        XCTAssertEqual(ledger.bankBalance(card), 6126)
        XCTAssertNil(ledger.automaticBankAccount(source: "Grab Card", suffix: "9999"))
        var second = card; second.id = UUID().uuidString; ledger.bankAccounts.append(second)
        XCTAssertNil(ledger.automaticBankAccount(source: "Grab Card", suffix: "1234"))
        let hold = "You'll only be charged the final amount once the service is complete. Any unused amount will be returned to your payment method."
        XCTAssertNil(parseFinancialNotification(hold, title: "RM38.74 is currently on hold", sourceApp: "Grab"))
        XCTAssertFalse(shouldReviewFinancialNotification(hold, title: "RM38.74 is currently on hold"))
        XCTAssertNil(parseFinancialNotification(body + " Payment failed.", title: "Grab", sourceApp: "Grab"))
    }
    func testAdditionalWalletPaymentsLinkOnlyTheirConfiguredAccount() throws {
        // Synthetic shared-grammar fixtures, not claimed provider notification samples.
        let date = Date()
        let providers = ["GrabPay", "ShopeePay", "AEON Bank"]
        let accounts = providers.map { BankAccount(name: $0, openingCents: 10000, openingDate: date.addingTimeInterval(-3600), institution: $0, automaticSource: $0) }
        for (index, provider) in providers.enumerated() {
            var ledger = Ledger(); ledger.bankAccounts = accounts
            _ = try ledger.receiveTNG(body: "You have paid RM12.50 at CAFE", title: "Payment", date: date, eventID: nil, sourceApp: provider)
            XCTAssertEqual(ledger.expenses.count, 1)
            XCTAssertEqual(ledger.expenses.first?.bankAccountID, accounts[index].id)
            for (other, account) in accounts.enumerated() {
                XCTAssertEqual(ledger.bankBalance(account), other == index ? 8750 : 10000)
            }
            for body in ["Your order of RM12.50 is ready", "Top up of RM12.50 successful", "Refund of RM12.50 received", "Payment of RM12.50 at CAFE is pending"] {
                XCTAssertNil(parseFinancialNotification(body, sourceApp: provider))
            }
        }
        XCTAssertEqual(exactFinancialProvider("grab pay"), "GrabPay")
        XCTAssertEqual(exactFinancialProvider("shopee pay"), "ShopeePay")
        XCTAssertNil(exactFinancialProvider("Grab"))
        XCTAssertNil(exactFinancialProvider("Shopee"))
        XCTAssertNil(parseFinancialNotification("ShopeePay: You have paid RM12.50 at CAFE", sourceApp: "GrabPay"))
        XCTAssertTrue(MalaysianBanks.walletsAndPayments.contains("GrabPay"))
        XCTAssertTrue(MalaysianBanks.walletsAndPayments.contains("ShopeePay"))
        XCTAssertTrue(MalaysianBanks.digital.contains("AEON Bank"))
    }
    func testPinduoduoOnlinePaymentAssociatesConfiguredTNGWallet() throws {
        let date = Date()
        let wallet = BankAccount(name: "TNG", openingCents: 10000, openingDate: date.addingTimeInterval(-3600), institution: "TNG eWallet", automaticSource: "TNG")
        for automatic in [false, true] {
            var ledger = Ledger(); ledger.bankAccounts = [wallet]
            _ = try ledger.receiveTNG(body: "You have paid RM2.54 at PINDUODUO", title: "Payment", date: date, eventID: nil, sourceApp: "TNG", automaticBalances: automatic)
            XCTAssertEqual(ledger.expenses.count, 1)
            XCTAssertEqual(ledger.expenses.first?.bankAccountID, wallet.id)
            XCTAssertEqual(ledger.expenses.first?.cents, 254)
            XCTAssertEqual(ledger.tngNotices.first?.bankAccountID, wallet.id)
            XCTAssertEqual(ledger.bankBalance(wallet), 9746)
        }
        var ledger = Ledger()
        let message = try ledger.receiveTNG(body: "You have paid RM2.54 at PINDUODUO", title: "Payment", date: date, eventID: nil, sourceApp: "TNG")
        XCTAssertNil(ledger.expenses.first?.bankAccountID)
        XCTAssertNotNil(ledger.tngNotices.first?.reviewReason)
        XCTAssertTrue(message.contains(try XCTUnwrap(ledger.tngNotices.first?.reviewReason)))
    }
    func testLanguageResolutionAndProtectedInterpolation() {
        XCTAssertEqual(AppLanguage.resolve("zh-TW"), "zh-Hant")
        XCTAssertEqual(AppLanguage.resolve("zh-Hans-MY"), "zh")
        XCTAssertEqual(AppLanguage.resolve("pt-PT"), "pt-BR")
        XCTAssertEqual(AppLanguage.resolve("ar-SA"), "ar")
        XCTAssertEqual(AppLanguage.resolve("unknown"), "en")
        XCTAssertEqual(AppLanguage.options.filter { !$0.bundled }.count, 12)
        let merchant = "Shop ⟦1⟧"
        let phrase = LocalizedPhrase("Paid \(merchant): \("RM 12.30")")
        XCTAssertEqual(phrase.template, "Paid ⟦0⟧: ⟦1⟧")
        XCTAssertEqual(phrase.render("⟦1⟧ — ⟦0⟧"), "RM 12.30 — Shop ⟦1⟧")
        XCTAssertEqual(phrase.render("missing amount"), "Paid Shop ⟦1⟧: RM 12.30")
        XCTAssertTrue(phrase.render(phrase.template, isolate: true).contains("\u{2068}RM 12.30\u{2069}"))
        XCTAssertFalse(LanguagePacks.validTranslation("⟦0⟧ ⟦0⟧", for: phrase.template))
        XCTAssertFalse(LanguagePacks.validTranslation("⟦0⟧ ⟦2⟧", for: phrase.template))
        XCTAssertFalse(LanguagePacks.validTranslation(" ", for: "Save"))
    }

    func testLanguagePackPersistsOnlyBundledTemplatesAndFallsBack() throws {
        XCTAssertGreaterThan(LanguagePacks.templates.count, 1800, "Language templates must be in the app bundle")
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let packs = LanguagePacks(directory: folder)
        XCTAssertEqual(packs.translation("Save", language: "fr"), "Save")
        try packs.save(["Save": "Enregistrer", "Private merchant 123": "Must not persist"], language: "fr")
        let reloaded = LanguagePacks(directory: folder)
        XCTAssertEqual(reloaded.translation("Save", language: "fr"), "Enregistrer")
        XCTAssertEqual(reloaded.count("fr"), 1)
        XCTAssertEqual(reloaded.translation("Private merchant 123", language: "fr"), "Private merchant 123")
        XCTAssertEqual(reloaded.translation("Save", language: "en"), "Save")
        try Data("broken JSON".utf8).write(to: folder.appendingPathComponent("ja.json"))
        XCTAssertFalse(LanguagePacks(directory: folder).hasPack("ja"))
    }

    func testTNGCardHasSeparateBalanceAndNeverMatchesWalletNotices() throws {
        let date = Date(timeIntervalSince1970: 1_780_000_000)
        let wallet = BankAccount(name: "Wallet", openingCents: 10000, openingDate: date, institution: "TNG eWallet", automaticSource: "TNG")
        let card = BankAccount(name: "My TNG card", openingCents: 2000, openingDate: date, institution: "TNG Card", automaticSource: "TNG")
        var ledger = Ledger()
        ledger.bankAccounts = [wallet, card]
        XCTAssertTrue(MalaysianBanks.walletsAndPayments.contains("TNG Card"))
        XCTAssertEqual(ledger.automaticBankAccount(source: "TNG", suffix: nil), wallet.id)
        try ledger.saveBankTransfer(BankTransfer(fromAccountID: wallet.id, toAccountID: card.id, cents: 1000, date: date), replacing: nil)
        XCTAssertEqual(ledger.bankBalance(wallet), 9000)
        XCTAssertEqual(ledger.bankBalance(card), 3000)
        var fare = Expense(merchant: "Parking", cents: 300, date: date)
        fare.bankAccountID = card.id
        ledger.expenses.append(fare)
        XCTAssertEqual(ledger.bankBalance(card), 2700)
        XCTAssertEqual(ledger.bankBalance(wallet), 9000)
    }

    func testBudgetSavingsUsesOverviewSpendingAndExcludesFutureAndUnsetMonths() throws {
        let january = noon(2026, 1, 15), february = noon(2026, 2, 15)
        var travel = Expense(merchant: "Trip", cents: 9000, date: january)
        travel.tripID = "trip"
        var ledger = Ledger(expenses: [Expense(merchant: "Lunch", cents: 3000, date: january),
                                       Expense(merchant: "Groceries", cents: 12000, date: february), travel],
                            budgets: [monthKey(january): 10000, monthKey(february): 10000,
                                      monthKey(noon(2026, 12, 1)): 10000])
        ledger.budgetAllocations = [BudgetAllocation(source: "income", month: monthKey(january), cents: 2000)]
        let rows = ledger.budgetSavings(year: 2026, now: noon(2026, 3, 10))
        XCTAssertEqual(rows.count, 12)
        XCTAssertEqual(rows[0].spent, 3000)
        XCTAssertEqual(rows[0].remaining, 9000)
        XCTAssertEqual(rows[1].remaining, -2000)
        XCTAssertTrue(rows[2].isCurrent)
        XCTAssertFalse(rows[2].included)
        XCTAssertTrue(rows[11].isFuture)
        XCTAssertFalse(rows[11].included)
        XCTAssertEqual(rows.filter(\.included).reduce(0) { $0 + $1.remaining }, 7000)
        ledger.budgets[monthKey(noon(2026, 3, 1))] = 0
        let updated = ledger.budgetSavings(year: 2026, now: noon(2026, 3, 10))
        XCTAssertTrue(updated[2].included)
        XCTAssertEqual(updated[2].remaining, 0)
        XCTAssertTrue(ledger.budgetSavings(year: 2027, now: noon(2026, 3, 10)).allSatisfy { !$0.included })
    }

    private func noon(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    func testAllowanceConfirmationPersistsAndNeverCreditsVerifiedReceiptTwice() throws {
        let date = noon(2026, 6, 10)
        for alreadyCredited in [false, true] {
            let account = BankAccount(name: "Public Bank", openingCents: 10000, openingDate: date.addingTimeInterval(-60))
            var notice = TNGNotice(body: "Living allowance", title: "", date: date, usesReceivedDate: false,
                                   kind: "incoming", status: "pending", cents: 50000, party: "Family")
            notice.sourceBank = "Public Bank"
            notice.bankAccountID = account.id
            notice.verifiedIncomingBalance = alreadyCredited
            var ledger = Ledger()
            ledger.bankAccounts = [account]; ledger.tngNotices = [notice]
            XCTAssertEqual(ledger.bankBalance(account), alreadyCredited ? 60000 : 10000)
            try ledger.resolveTNGIncoming(id: notice.id, purpose: "income", date: date, incomeKind: .allowance)
            XCTAssertEqual(ledger.bankBalance(account), 60000)
            XCTAssertEqual(ledger.incomeSource(IncomeSourceKey.notice(notice.id))?.kind, .allowance)
            XCTAssertTrue(ledger.incomes.isEmpty)
            XCTAssertTrue(ledger.budgetAllocations.isEmpty)
            let restored = try LocalStore.decode(LocalStore.encode(ledger))
            XCTAssertEqual(restored.tngNotices.first?.confirmedIncomeKind, .allowance)
            XCTAssertEqual(restored.bankBalance(account), 60000)
        }
    }

    func testManualIncomeRaisesTheBudgetWithoutChangingIncomeOrSpending() throws {
        let now = noon(2026, 6, 15)
        let key = monthKey(now)
        var ledger = Ledger(expenses: [Expense(merchant: "Lunch", cents: 4000, date: now)], budgets: [key: 150000])
        let salary = IncomeEntry(source: "Acme Sdn Bhd", cents: 30000, date: now, kind: .salary)
        let outcome = try ledger.addIncome(salary, now: now)
        XCTAssertEqual(outcome?.cents, 30000)
        XCTAssertEqual(outcome?.month, key)
        XCTAssertNil(outcome?.automatic)
        XCTAssertNil(outcome?.duplicateName)
        // Saving income alone never changes the budget: the person chooses.
        XCTAssertEqual(ledger.monthlyBudget(key), MonthlyBudget(base: 150000, income: 0))

        try ledger.setIncomeAllocation(source: salary.sourceKey, month: key, cents: 30000, expected: 0, now: now)
        let budget = ledger.monthlyBudget(key)
        XCTAssertEqual(budget.total, 180000)
        // Base + income allocations − eligible spending = remaining.
        XCTAssertEqual(budget.remaining(spent: ledger.dailyBudgetSpending(in: now)), 176000)
        // No second income, no new transaction, same amounts and the same base budget.
        XCTAssertEqual(ledger.incomes, [salary])
        XCTAssertEqual(ledger.expenses.count, 1)
        XCTAssertEqual(ledger.dailyBudgetSpending(in: now), 4000)
        XCTAssertEqual(ledger.budgets[key], 150000)
        XCTAssertEqual(ledger.unallocated(for: salary.sourceKey), 0)
        XCTAssertThrowsError(try ledger.setIncomeAllocation(source: salary.sourceKey, month: key, cents: 30001, expected: 30000))
        XCTAssertEqual(ledger.monthlyBudget(key).total, 180000)
    }

    func testBankInterestCreditsAccountWithoutAutomaticBudgetAllocation() throws {
        let date = noon(2026, 6, 15)
        let account = BankAccount(name: "Public Bank", openingCents: 10000, openingDate: date.addingTimeInterval(-60))
        var ledger = Ledger(); ledger.bankAccounts = [account]
        let entry = IncomeEntry(bankAccountID: account.id, source: "Public Bank interest", cents: 123, date: date, kind: .interest)
        XCTAssertNil(try ledger.addIncome(entry, autoPercent: 100, now: date))
        XCTAssertEqual(ledger.bankBalance(account), 10123)
        XCTAssertTrue(ledger.budgetAllocations.isEmpty)
        XCTAssertThrowsError(try ledger.addIncome(entry, autoPercent: 100, now: date))
        XCTAssertEqual(ledger.bankBalance(account), 10123)
        let restored = try LocalStore.decode(LocalStore.encode(ledger))
        XCTAssertEqual(restored.incomes.first?.kind, .interest)
        XCTAssertEqual(restored.bankBalance(account), 10123)
        // An explicit later budget choice is still permitted.
        try ledger.setIncomeAllocation(source: entry.sourceKey, month: monthKey(date), cents: 100, expected: 0, now: date)
        XCTAssertEqual(ledger.bankBalance(account), 10123)
        XCTAssertEqual(ledger.monthlyBudget(monthKey(date)).income, 100)
    }

    func testCapturedBankIncomeIsOfferedOnlyAfterItsPurposeIsConfirmed() throws {
        let received = noon(2026, 6, 25)
        let key = monthKey(received)
        let body = "You've just received RM 2500.00 in your account ending ***1234. REF: SALARY001"
        var ledger = Ledger()
        _ = try ledger.receiveTNG(body: body, title: "Maybank2u: Funds Received", date: received, eventID: nil)
        let notice = try XCTUnwrap(ledger.tngNotices.first)
        XCTAssertEqual(notice.kind, "incoming")
        XCTAssertEqual(notice.status, "pending")
        let source = IncomeSourceKey.notice(notice.id)
        // Still under review: not income, so nothing can go into a budget yet.
        XCTAssertNil(ledger.incomeSource(source))
        XCTAssertEqual(ledger.unallocated(for: source), 0)
        XCTAssertThrowsError(try ledger.setIncomeAllocation(source: source, month: key, cents: 100, expected: 0))
        XCTAssertNil(try ledger.settleNewIncome(source: source, autoPercent: 100, now: received))
        XCTAssertTrue(ledger.budgetAllocations.isEmpty)
        // The same notification again is not a second record to allocate.
        _ = try ledger.receiveTNG(body: body, title: "Maybank2u: Funds Received", date: received, eventID: nil)
        XCTAssertEqual(ledger.tngNotices.count, 1)

        try ledger.resolveTNGIncoming(id: notice.id, purpose: "income", date: received, incomeKind: .salary)
        let outcome = try ledger.settleNewIncome(source: source, autoPercent: nil, now: received)
        XCTAssertEqual(outcome?.cents, 250000)
        XCTAssertEqual(ledger.incomeSource(source)?.kind, .salary)
        try ledger.setIncomeAllocation(source: source, month: key, cents: 100000, expected: 0, now: received)
        XCTAssertEqual(ledger.monthlyBudget(key).income, 100000)
        XCTAssertEqual(ledger.unallocated(for: source), 150000)
        XCTAssertEqual(ledger.tngNotices.first?.cents, 250000)
        XCTAssertTrue(ledger.expenses.isEmpty)
        XCTAssertTrue(ledger.incomes.isEmpty, "Bank income stays a notice; no manual copy is made")
    }

    func testRepaymentsTransfersTopUpsRefundsAndUnclearNoticesNeverFundABudget() throws {
        let date = noon(2026, 6, 10)
        var ledger = Ledger(expenses: [Expense(id: "cafe", merchant: "Cafe", cents: 5000, date: date)])
        ledger.tngNotices = [
            TNGNotice(id: "own", body: "RM 50.00 received", title: "Received", date: date, usesReceivedDate: true, kind: "incoming", status: "pending", cents: 5000, party: "Me"),
            TNGNotice(id: "refund", body: "Refund RM 20.00", title: "Refund", date: date, usesReceivedDate: true, kind: "incoming", status: "pending", cents: 2000, party: "Cafe"),
            TNGNotice(id: "unclear", body: "RM 30.00 credited", title: "Bank", date: date, usesReceivedDate: true, kind: "unknown", status: "pending", cents: 3000, party: nil)]
        ledger = try ledger.validated()
        try ledger.resolveTNGIncoming(id: "own", purpose: "ownTransfer", date: date)
        try ledger.resolveNotice(id: "refund", purpose: "refund", party: "Cafe", cents: 2000, date: date, relatedID: "cafe")
        for id in ["own", "refund", "unclear"] {
            let source = IncomeSourceKey.notice(id)
            XCTAssertNil(ledger.incomeSource(source), id)
            XCTAssertNil(try ledger.autoAllocateIncome(source: source, percent: 100, now: date), id)
            XCTAssertNil(try ledger.settleNewIncome(source: source, autoPercent: 100, now: date), id)
            XCTAssertThrowsError(try ledger.setIncomeAllocation(source: source, month: monthKey(date), cents: 100, expected: 0), id)
        }
        XCTAssertTrue(ledger.budgetAllocations.isEmpty)
        XCTAssertEqual(ledger.monthlyBudget(monthKey(date)).income, 0)
        // Even a crafted record for an own transfer is refused.
        var crafted = ledger
        crafted.budgetAllocations = [BudgetAllocation(source: IncomeSourceKey.notice("own"), month: monthKey(date), cents: 100)]
        XCTAssertThrowsError(try crafted.validated())
        // An income type only belongs to confirmed income.
        var mislabelled = ledger
        mislabelled.tngNotices[0].incomeKind = IncomeKind.salary.rawValue
        XCTAssertThrowsError(try mislabelled.validated())
    }

    func testIncomeConfirmedBeforeThisUpdateCountsAsOtherIncome() throws {
        let date = noon(2026, 5, 2)
        var ledger = Ledger()
        ledger.tngNotices = [TNGNotice(id: "old", body: "RM 120.00 received", title: "Received", date: date, usesReceivedDate: true, kind: "incoming", status: "income", cents: 12000, party: "Client")]
        ledger = try ledger.validated()
        let income = try XCTUnwrap(ledger.incomeSource(IncomeSourceKey.notice("old")))
        XCTAssertEqual(income.kind, .other)
        XCTAssertEqual(income.name, "Client")
        XCTAssertEqual(ledger.unallocated(for: income.id), 12000)
    }

    func testPartialAllocationsCanBeAddedReducedAndUndone() throws {
        let now = noon(2026, 7, 5)
        let key = monthKey(now), next = monthKey(shiftedMonth(now, by: 1))
        var ledger = Ledger(budgets: [key: 100000])
        let gig = IncomeEntry(source: "Design client", cents: 30000, date: now, kind: .freelance)
        _ = try ledger.addIncome(gig, now: now)
        let source = gig.sourceKey
        try ledger.setIncomeAllocation(source: source, month: key, cents: 10000, expected: 0, now: now)
        XCTAssertEqual(ledger.unallocated(for: source), 20000)
        // Adding more to the same month keeps one allocation for that month.
        try ledger.setIncomeAllocation(source: source, month: key, cents: 25000, expected: 10000, now: now)
        XCTAssertEqual(ledger.allocations(for: source).map(\.cents), [25000])
        XCTAssertEqual(ledger.monthlyBudget(key).total, 125000)
        XCTAssertThrowsError(try ledger.setIncomeAllocation(source: source, month: key, cents: 30001, expected: 25000))
        try ledger.setIncomeAllocation(source: source, month: next, cents: 5000, expected: 0, now: now)
        XCTAssertEqual(ledger.unallocated(for: source), 0)
        XCTAssertThrowsError(try ledger.setIncomeAllocation(source: source, month: next, cents: 5001, expected: 5000))
        // Reduce, then undo, without touching the income itself.
        try ledger.setIncomeAllocation(source: source, month: key, cents: 5000, expected: 25000, now: now)
        XCTAssertEqual(ledger.monthlyBudget(key), MonthlyBudget(base: 100000, income: 5000))
        try ledger.setIncomeAllocation(source: source, month: key, cents: 0, expected: 5000, now: now)
        XCTAssertEqual(ledger.monthlyBudget(key), MonthlyBudget(base: 100000, income: 0))
        XCTAssertEqual(ledger.allocations(for: source).map(\.month), [next])
        XCTAssertEqual(ledger.incomes, [gig])
        XCTAssertEqual(ledger.unallocated(for: source), 25000)
    }

    func testRepeatedTapsStaleScreensAndCrossSourceDuplicatesNeverDoubleCount() throws {
        let now = noon(2026, 8, 28)
        let key = monthKey(now)
        var ledger = Ledger()
        let salary = IncomeEntry(source: "Employer", cents: 300000, date: now, kind: .salary)
        _ = try ledger.addIncome(salary, now: now)
        XCTAssertThrowsError(try ledger.addIncome(salary, now: now), "The same draft saved twice is one income")
        XCTAssertEqual(ledger.incomes.count, 1)
        try ledger.setIncomeAllocation(source: salary.sourceKey, month: key, cents: 300000, expected: 0, now: now)
        // A second tap from a screen that still showed nothing allocated is refused.
        XCTAssertThrowsError(try ledger.setIncomeAllocation(source: salary.sourceKey, month: key, cents: 300000, expected: 0, now: now))
        XCTAssertEqual(ledger.monthlyBudget(key).income, 300000)

        // The same salary also arrives from the bank and is confirmed as income.
        let paid = now.addingTimeInterval(3600)
        ledger.tngNotices = [TNGNotice(id: "bank-salary", body: "RM 3000.00 received", title: "Funds Received", date: paid, usesReceivedDate: true, kind: "incoming", status: "pending", cents: 300000, party: "Employer")]
        ledger = try ledger.validated()
        try ledger.resolveTNGIncoming(id: "bank-salary", purpose: "income", date: paid, incomeKind: .salary)
        let bank = IncomeSourceKey.notice("bank-salary")
        let outcome = try ledger.settleNewIncome(source: bank, autoPercent: 100, now: now)
        XCTAssertEqual(outcome?.duplicateName, "Employer")
        XCTAssertNil(outcome?.automatic, "A possible duplicate is never added automatically")
        XCTAssertThrowsError(try ledger.setIncomeAllocation(source: bank, month: key, cents: 300000, expected: 0, now: now))
        XCTAssertEqual(ledger.monthlyBudget(key).income, 300000)
        // Only after the person checks it is separate income.
        try ledger.setIncomeAllocation(source: bank, month: key, cents: 300000, expected: 0, confirmedDistinct: true, now: now)
        XCTAssertEqual(ledger.monthlyBudget(key).income, 600000)

        // Two records for one income and month, or more than the income, never validate.
        var doubled = ledger
        doubled.budgetAllocations.append(BudgetAllocation(source: salary.sourceKey, month: key, cents: 1))
        XCTAssertThrowsError(try doubled.validated())
        var over = ledger
        over.budgetAllocations.append(BudgetAllocation(source: salary.sourceKey, month: monthKey(shiftedMonth(now, by: 1)), cents: 1))
        XCTAssertThrowsError(try over.validated())
        var reused = ledger
        reused.budgetAllocations.append(BudgetAllocation(id: ledger.budgetAllocations[0].id, source: bank, month: monthKey(shiftedMonth(now, by: 1)), cents: 1))
        XCTAssertThrowsError(try reused.validated())
    }

    func testEditingIncomeExplainsThenTrimsItsAllocationsLatestMonthFirst() throws {
        let now = noon(2026, 9, 3)
        let september = monthKey(now), october = monthKey(shiftedMonth(now, by: 1))
        var ledger = Ledger(budgets: [september: 100000])
        let bonus = IncomeEntry(source: "Year-end bonus", cents: 50000, date: now, kind: .bonus)
        _ = try ledger.addIncome(bonus, now: now)
        try ledger.setIncomeAllocation(source: bonus.sourceKey, month: september, cents: 20000, expected: 0, now: now)
        try ledger.setIncomeAllocation(source: bonus.sourceKey, month: october, cents: 30000, expected: 0, now: now)
        var edited = bonus
        edited.cents = 35000
        edited.source = "Bonus (after tax)"
        let explained = ledger.allocationAdjustments(source: bonus.sourceKey, newCents: edited.cents)
        XCTAssertEqual(explained, [BudgetAdjustment(month: october, before: 30000, after: 15000)])
        let applied = try ledger.updateIncome(edited, replacing: bonus, now: now)
        XCTAssertEqual(applied, explained)
        XCTAssertEqual(ledger.allocations(for: bonus.sourceKey).map(\.cents), [20000, 15000])
        XCTAssertEqual(ledger.incomes, [edited])

        var smaller = edited
        smaller.cents = 5000
        XCTAssertEqual(ledger.allocationAdjustments(source: bonus.sourceKey, newCents: 5000), [
            BudgetAdjustment(month: october, before: 15000, after: 0),
            BudgetAdjustment(month: september, before: 20000, after: 5000)])
        try ledger.updateIncome(smaller, replacing: edited, now: now)
        XCTAssertEqual(ledger.allocations(for: bonus.sourceKey).map(\.month), [september])
        XCTAssertEqual(ledger.monthlyBudget(september), MonthlyBudget(base: 100000, income: 5000))
        XCTAssertEqual(ledger.monthlyBudget(october).income, 0)
        // A larger amount leaves allocations alone; an edit of an outdated copy is refused.
        XCTAssertTrue(ledger.allocationAdjustments(source: bonus.sourceKey, newCents: 90000).isEmpty)
        XCTAssertThrowsError(try ledger.updateIncome(smaller, replacing: edited, now: now))
    }

    func testDeletingIncomeRemovesItsAllocationsAndUndoRestoresBothOnce() throws {
        let now = noon(2026, 6, 20)
        let key = monthKey(now)
        var ledger = Ledger(budgets: [key: 100000])
        let tutoring = IncomeEntry(source: "Weekend tutoring", cents: 20000, date: now, kind: .partTime)
        _ = try ledger.addIncome(tutoring, now: now)
        try ledger.setIncomeAllocation(source: tutoring.sourceKey, month: key, cents: 20000, expected: 0, now: now)
        XCTAssertEqual(ledger.allocationRemovals(source: tutoring.sourceKey), [BudgetAdjustment(month: key, before: 20000, after: 0)])
        let deleted = try ledger.deleteIncome(tutoring)
        XCTAssertTrue(ledger.incomes.isEmpty)
        XCTAssertTrue(ledger.budgetAllocations.isEmpty)
        XCTAssertEqual(ledger.monthlyBudget(key).total, 100000)
        try ledger.restoreDeletedRecords([deleted])
        XCTAssertEqual(ledger.incomes, [tutoring])
        XCTAssertEqual(ledger.monthlyBudget(key).total, 120000)
        XCTAssertThrowsError(try ledger.restoreDeletedRecords([deleted]), "Undo never restores twice")
        XCTAssertEqual(ledger.monthlyBudget(key).total, 120000)

        // Deleting confirmed bank income takes its allocation with it; undo brings both back.
        ledger.tngNotices = [TNGNotice(id: "pay", body: "RM 100.00 received", title: "Funds Received", date: now, usesReceivedDate: true, kind: "incoming", status: "pending", cents: 10000, party: "Shop")]
        ledger = try ledger.validated()
        try ledger.resolveTNGIncoming(id: "pay", purpose: "income", date: now)
        try ledger.setIncomeAllocation(source: IncomeSourceKey.notice("pay"), month: key, cents: 4000, expected: 0, now: now)
        let notice = try XCTUnwrap(ledger.tngNotices.first)
        let removed = try ledger.deleteAutomaticRecord(notice)
        XCTAssertEqual(removed.allocations.map(\.cents), [4000])
        XCTAssertEqual(ledger.monthlyBudget(key).income, 20000)
        try ledger.restoreDeletedRecords([removed])
        XCTAssertEqual(ledger.monthlyBudget(key).income, 24000)
    }

    func testReclassifyingConfirmedIncomeTakesItOutOfTheBudget() throws {
        let date = noon(2026, 6, 12)
        let key = monthKey(date)
        var ledger = Ledger(budgets: [key: 50000])
        ledger.tngNotices = [TNGNotice(id: "in", body: "RM 80.00 received", title: "Received", date: date, usesReceivedDate: true, kind: "incoming", status: "pending", cents: 8000, party: "Amy")]
        ledger = try ledger.validated()
        let source = IncomeSourceKey.notice("in")
        try ledger.resolveTNGIncoming(id: "in", purpose: "income", date: date, incomeKind: .other)
        try ledger.setIncomeAllocation(source: source, month: key, cents: 8000, expected: 0, now: date)
        XCTAssertEqual(ledger.monthlyBudget(key).total, 58000)
        XCTAssertEqual(ledger.allocationRemovals(source: source), [BudgetAdjustment(month: key, before: 8000, after: 0)])
        try ledger.reopenTNGIncoming(id: "in")
        XCTAssertEqual(ledger.tngNotices.first?.status, "pending")
        XCTAssertNil(ledger.tngNotices.first?.incomeKind)
        XCTAssertTrue(ledger.budgetAllocations.isEmpty)
        XCTAssertEqual(ledger.monthlyBudget(key).total, 50000)
        XCTAssertEqual(ledger.tngNotices.first?.cents, 8000)
        // Confirmed instead as money from the person's own account, it can't fund a budget.
        try ledger.resolveTNGIncoming(id: "in", purpose: "ownTransfer", date: date)
        XCTAssertNil(ledger.incomeSource(source))
        XCTAssertNil(ledger.tngNotices.first?.incomeKind)
    }

    func testOlderIncomeGoesToTheCurrentMonthAndMonthsStayApart() throws {
        let august = noon(2026, 8, 31)
        let late = Calendar.current.date(bySettingHour: 23, minute: 50, second: 0, of: august)!
        let october = noon(2026, 10, 1)
        var ledger = Ledger(budgets: [monthKey(august): 100000, monthKey(october): 100000])
        let overtime = IncomeEntry(source: "Overtime", cents: 12000, date: late, kind: .salary)
        let saved = try ledger.addIncome(overtime, now: october)
        let outcome = try XCTUnwrap(saved)
        // Allocated to the month it is added in, and the prompt knows the income is older.
        XCTAssertEqual(outcome.month, monthKey(october))
        XCTAssertEqual(monthKey(outcome.incomeDate), monthKey(august))
        XCTAssertNotEqual(IncomeBudgetPrompt(outcome: outcome).message, "")
        try ledger.setIncomeAllocation(source: overtime.sourceKey, month: outcome.month, cents: 12000, expected: 0, now: october)
        XCTAssertEqual(ledger.monthlyBudget(monthKey(october)).total, 112000)
        XCTAssertEqual(ledger.monthlyBudget(monthKey(august)).total, 100000)
        XCTAssertEqual(ledger.monthlyBudget(monthKey(shiftedMonth(august, by: 1))).income, 0)
        XCTAssertThrowsError(try ledger.setIncomeAllocation(source: overtime.sourceKey, month: "2026-13", cents: 1, expected: 0))
        XCTAssertEqual(budgetMonthDate("2026-02").map { monthKey($0) }, "2026-02")
        XCTAssertNil(budgetMonthDate("2026-2"))
        XCTAssertFalse(budgetMonthIsValid("2026-00"))
    }

    func testBackupRoundTripKeepsAllocationsAndRestoringNeverDoubleCounts() throws {
        let now = noon(2026, 6, 15)
        let key = monthKey(now), next = monthKey(shiftedMonth(now, by: 1))
        var ledger = Ledger(budgets: [key: 100000])
        let salary = IncomeEntry(source: "Employer", cents: 50000, date: now, kind: .salary, note: "June")
        _ = try ledger.addIncome(salary, now: now)
        try ledger.setIncomeAllocation(source: salary.sourceKey, month: key, cents: 20000, expected: 0, now: now)
        let backup = try LocalStore.exportData(ledger)
        let restored = try LocalStore.decode(backup)
        XCTAssertEqual(restored.incomes, ledger.incomes)
        XCTAssertEqual(restored.budgetAllocations, ledger.budgetAllocations)
        XCTAssertEqual(restored.monthlyBudget(key).total, 120000)

        // Restoring the same backup twice replaces, never adds.
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = LocalStore(folder: folder)
        try store.restore(backup)
        try store.restore(backup)
        let stored = try store.read()
        XCTAssertEqual(stored.budgetAllocations, ledger.budgetAllocations)
        XCTAssertEqual(stored.monthlyBudget(key).total, 120000)

        // A hand-merged backup: one allocation twice, a second one for the same income and
        // month, one for income that no longer exists, and more than the income in total.
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: LocalStore.encode(ledger)) as? [String: Any])
        var rows = try XCTUnwrap(object["budgetAllocations"] as? [[String: Any]])
        let first = rows[0]
        var second = first; second["id"] = "second"; second["cents"] = 45000
        var later = first; later["id"] = "later"; later["month"] = next; later["cents"] = 30000
        var orphan = first; orphan["id"] = "orphan"; orphan["source"] = IncomeSourceKey.manual("gone")
        rows += [first, second, later, orphan]
        object["budgetAllocations"] = rows
        let repaired = try LocalStore.decode(JSONSerialization.data(withJSONObject: object))
        // One per income and month (the larger, never the sum), trimmed to the income from the latest month.
        XCTAssertEqual(repaired.budgetAllocations.map(\.month), [key, next])
        XCTAssertEqual(repaired.budgetAllocations.map(\.cents), [45000, 5000])
        XCTAssertEqual(repaired.allocatedTotal(for: salary.sourceKey), salary.cents)
        XCTAssertNoThrow(try repaired.validated())

        // An older backup without the new keys loads with nothing allocated.
        object.removeValue(forKey: "budgetAllocations")
        object.removeValue(forKey: "incomes")
        let legacy = try LocalStore.decode(JSONSerialization.data(withJSONObject: object))
        XCTAssertTrue(legacy.incomes.isEmpty)
        XCTAssertTrue(legacy.budgetAllocations.isEmpty)
        XCTAssertEqual(legacy.monthlyBudget(key), MonthlyBudget(base: 100000, income: 0))
    }

    func testAutomaticAllocationAddsTheChosenShareOnceAndOnlyForIncome() throws {
        let now = noon(2026, 6, 15)
        let key = monthKey(now)
        var ledger = Ledger(budgets: [key: 100000])
        let salary = IncomeEntry(source: "Employer", cents: 30001, date: now, kind: .salary)
        let outcome = try ledger.addIncome(salary, autoPercent: 30, now: now)
        XCTAssertEqual(outcome?.automatic, 9000, "30% of RM300.01, rounded down to the sen")
        XCTAssertEqual(outcome?.percent, 30)
        XCTAssertEqual(ledger.budgetAllocations.count, 1)
        XCTAssertEqual(ledger.budgetAllocations.first?.automatic, true)
        XCTAssertEqual(ledger.monthlyBudget(key).income, 9000)
        // Never twice for the same income.
        XCTAssertNil(try ledger.autoAllocateIncome(source: salary.sourceKey, percent: 30, now: now))
        let again = try ledger.settleNewIncome(source: salary.sourceKey, autoPercent: 30, now: now)
        XCTAssertNil(again?.automatic)
        XCTAssertEqual(ledger.monthlyBudget(key).income, 9000)
        // Off, out of range, or less than one sen: nothing is added.
        let tiny = IncomeEntry(source: "Survey", cents: 1, date: now, kind: .other)
        XCTAssertNil(try ledger.addIncome(tiny, autoPercent: 50, now: now)?.automatic)
        let off = IncomeEntry(source: "Shop sale", cents: 7000, date: now, kind: .other)
        XCTAssertNil(try ledger.addIncome(off, autoPercent: nil, now: now)?.automatic)
        XCTAssertNil(try ledger.autoAllocateIncome(source: off.sourceKey, percent: 0, now: now))
        XCTAssertNil(try ledger.autoAllocateIncome(source: off.sourceKey, percent: 101, now: now))
        XCTAssertEqual(ledger.monthlyBudget(key).income, 9000)
        // Changing an automatic allocation makes it the person's own.
        try ledger.setIncomeAllocation(source: salary.sourceKey, month: key, cents: 5000, expected: 9000, now: now)
        XCTAssertNil(ledger.allocations(for: salary.sourceKey).first?.automatic)
        // Bank money still under review is never allocated automatically.
        ledger.tngNotices = [TNGNotice(id: "pending", body: "RM 1000.00 received", title: "Received", date: now, usesReceivedDate: true, kind: "incoming", status: "pending", cents: 100000, party: "Unknown")]
        ledger = try ledger.validated()
        XCTAssertNil(try ledger.settleNewIncome(source: IncomeSourceKey.notice("pending"), autoPercent: 100, now: now))
        XCTAssertEqual(ledger.monthlyBudget(key).income, 5000)
    }

    func testForeignIncomeFundsTheBudgetOnlyInConvertedRinggit() throws {
        let now = noon(2026, 6, 15)
        let key = monthKey(now)
        var ledger = Ledger()
        let fx = ForeignAmount(currency: "USD", minor: 10000, quote: RateQuote(value: Decimal(string: "4.4")!, date: now, source: "Manual"))
        let myr = try fx.myrCents()
        XCTAssertEqual(myr, 44000)
        let usd = IncomeEntry(source: "Upwork", cents: myr, date: now, kind: .freelance, foreign: fx)
        _ = try ledger.addIncome(usd, now: now)
        XCTAssertThrowsError(try ledger.setIncomeAllocation(source: usd.sourceKey, month: key, cents: 44001, expected: 0))
        try ledger.setIncomeAllocation(source: usd.sourceKey, month: key, cents: 44000, expected: 0, now: now)
        XCTAssertEqual(ledger.monthlyBudget(key).income, 44000)
        // The foreign amount is never treated as ringgit.
        var unconverted = usd
        unconverted.id = UUID().uuidString
        unconverted.cents = 10000
        XCTAssertThrowsError(try ledger.addIncome(unconverted, now: now))
    }

    func testBudgetAlertUsesBaseBudgetPlusIncome() throws {
        let now = Date()
        let key = monthKey(now)
        var ledger = Ledger(expenses: [Expense(merchant: "Groceries", cents: 9000, date: now)], budgets: [key: 10000])
        XCTAssertNotNil(BudgetAlertCandidate.make(ledger: ledger, now: now, percent: 80))
        let pay = IncomeEntry(source: "Part-time", cents: 5000, date: now, kind: .partTime)
        _ = try ledger.addIncome(pay, now: now)
        try ledger.setIncomeAllocation(source: pay.sourceKey, month: key, cents: 5000, expected: 0, now: now)
        XCTAssertEqual(ledger.monthlyBudget(key).remaining(spent: ledger.dailyBudgetSpending(in: now)), 6000)
        XCTAssertNil(BudgetAlertCandidate.make(ledger: ledger, now: now, percent: 80))
        XCTAssertEqual(BudgetAlertCandidate.make(ledger: ledger, now: now, percent: 60)?.budget, 15000)
    }

    func testLedgerTimelineListsManualIncomeWithoutCountingItAsSpending() throws {
        let now = noon(2026, 6, 15)
        var ledger = Ledger(expenses: [Expense(merchant: "Lunch", cents: 1500, date: now)])
        let salary = IncomeEntry(source: "Employer", cents: 300000, date: now, kind: .salary)
        _ = try ledger.addIncome(salary, now: now)
        func timeline(search: String = "", filter: LedgerFilter = LedgerFilter(), provider: String = "all") throws -> LedgerTimelineSnapshot {
            try LedgerTimelineSnapshot(ledger: ledger, month: now, query: LedgerTimelineQuery(revision: 1, month: now, search: search, filter: filter, provider: provider))
        }
        let all = try timeline()
        XCTAssertEqual(all.incomes.map(\.id), [salary.id])
        XCTAssertEqual(all.personal, 1500)
        XCTAssertEqual(all.count, 2)
        XCTAssertTrue(all.days.flatMap(\.entries).contains { $0.id == "income:" + salary.id })
        var food = LedgerFilter()
        food.category = "餐饮"
        XCTAssertTrue(try timeline(filter: food).incomes.isEmpty)
        XCTAssertEqual(try timeline(search: "employer").incomes.count, 1)
        XCTAssertTrue(try timeline(provider: "TNG").incomes.isEmpty)
        XCTAssertEqual(try timeline(provider: "手动").incomes.count, 1)
    }

    @MainActor func testIncomePromptIsNonBlockingAndLeavesTheLedgerUnchanged() throws {
        let model = LedgerModel(previewLedger: GuideSample.ledger())
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let before = try encoder.encode(model.ledger)
        model.showSaved(message: "Saved")
        let outcome = IncomeBudgetOutcome(source: IncomeSourceKey.manual("x"), name: "Employer", cents: 30000, incomeDate: Date(),
                                          month: monthKey(Date()), automatic: nil, percent: nil, duplicateName: nil)
        model.presentIncomeOutcome(outcome)
        let prompt = try XCTUnwrap(model.incomePrompt)
        XCTAssertNil(model.savedNotice, "The prompt replaces the plain Saved banner")
        XCTAssertEqual(model.activeBanner, .income)
        XCTAssertTrue(prompt.title.contains(money(30000)))
        let notice = ForegroundLedgerNotice(title: "Recorded", message: "RM35.00", userInfo: [:])
        model.receiveForegroundNotice(notice)
        XCTAssertEqual(model.activeBanner, .foreground)
        model.dismissForegroundNotice(id: notice.id)
        XCTAssertEqual(model.activeBanner, .income, "A waiting prompt survives a higher-priority banner")
        model.chooseIncomeAmount(prompt)
        XCTAssertNil(model.incomePrompt)
        XCTAssertEqual(model.allocationRequest?.source, outcome.source)
        XCTAssertNil(model.allocationRequest?.presenter)
        model.allocationRequest = nil
        model.presentIncomeOutcome(outcome)
        let second = try XCTUnwrap(model.incomePrompt)
        model.dismissIncomePrompt(id: UUID())
        XCTAssertNotNil(model.incomePrompt, "A stale dismissal is ignored")
        model.dismissIncomePrompt(id: second.id)
        XCTAssertNil(model.activeBanner)
        XCTAssertEqual(try encoder.encode(model.ledger), before)
    }
}

extension IncomeBudgetTests {
    private func statementFixture() -> (BankAccount, RHBStatement) {
        let start = RHBStatement.calendar.date(from: DateComponents(year: 2026, month: 7, day: 1))!
        let account = BankAccount(name: "RHB", openingCents: 100000, openingDate: start, institution: "RHB Bank", automaticSource: "RHB", automaticSuffix: "1234")
        let rows = [
            StatementRow(id: "statement:a", date: start, description: "DEBITCARD TXN D", serial: "1", debit: 1000, credit: 0, balance: 99000),
            StatementRow(id: "statement:b", date: start.addingTimeInterval(86400), description: "PROFIT CREDIT", serial: "2", debit: 0, credit: 123, balance: 99123),
            StatementRow(id: "statement:c", date: start.addingTimeInterval(2 * 86400), description: "MB FUND TRF DR", serial: "3", debit: 2000, credit: 0, balance: 97123),
            StatementRow(id: "statement:d", date: start.addingTimeInterval(3 * 86400), description: "RPP INWD INST C", serial: "4", debit: 0, credit: 3000, balance: 100123)
        ]
        return (account, RHBStatement(accountHash: "sample", suffix: "1234", start: start, end: start.addingTimeInterval(30 * 86400), opening: 100000, closing: 100123, debitCount: 2, creditCount: 2, debitTotal: 3000, creditTotal: 3123, rows: rows))
    }
    func testStatementFirstThenNotificationIsHeldAndReconciliationExplainsPending() throws {
        var (account, statement) = statementFixture()
        account.automaticSuffix = nil
        var ledger = Ledger(); ledger.bankAccounts = [account]
        let firstReview = ledger.statementReconciliation(statement, account: account)
        XCTAssertEqual(firstReview.missing.count, 4)
        XCTAssertEqual(firstReview.openingDifference, 0)
        _ = try ledger.importStatement(statement, account: account, categories: [:])
        let before = ledger.bankBalance(account)
        let parsed = TNGParsed(kind: "payment", cents: 1000, party: "Cafe", sourceBank: "RHB", accountSuffix: "1234")
        XCTAssertTrue(ledger.hasCrossSourcePaymentCandidate(parsed, date: statement.start.addingTimeInterval(3600)))
        _ = try ledger.receiveTNG(body: "You have paid RM10.00 to Cafe.", title: "Payment", date: statement.start.addingTimeInterval(3600), eventID: "later-card", sourceApp: "RHB")
        XCTAssertEqual(ledger.bankBalance(account), before)
        XCTAssertTrue(ledger.tngNotices.last?.possibleDuplicate == true)
        let review = ledger.statementReconciliation(statement, account: account)
        XCTAssertTrue(review.missing.isEmpty)
        XCTAssertEqual(review.pending.count, 3)
        let duplicate = try XCTUnwrap(ledger.tngNotices.last)
        let entry = try XCTUnwrap(ledger.expenses.first)
        try ledger.dismissDuplicateNotice(id: duplicate.id, expenseID: entry.id)
        XCTAssertEqual(ledger.bankBalance(account), before)
        XCTAssertEqual(ledger.tngNotices.last?.relatedRecordID, entry.id)
        try ledger.reopenResolvedNotice(id: duplicate.id)
        XCTAssertEqual(ledger.bankBalance(account), before)
    }

    func testDelayedCrossSourceCandidateUsesAccountAndNeverMergesOnAmountAlone() throws {
        let now = Date().addingTimeInterval(-60)
        var ledger = Ledger()
        let account = BankAccount(name: "Bank", openingCents: 10000, openingDate: now.addingTimeInterval(-864000), automaticSource: "RHB")
        let other = BankAccount(name: "Other", openingCents: 0, openingDate: account.openingDate)
        ledger.bankAccounts = [account, other]
        ledger.expenses = [Expense(bankAccountID: account.id, merchant: "Grab", cents: 4188, date: now.addingTimeInterval(-86400), source: "Grab Card")]
        let payment = TNGParsed(kind: "payment", cents: 4188, party: "Grab", sourceBank: "RHB")
        XCTAssertTrue(ledger.hasCrossSourcePaymentCandidate(payment, date: now))
        ledger.expenses[0].bankAccountID = other.id
        XCTAssertFalse(ledger.hasCrossSourcePaymentCandidate(payment, date: now))
        ledger.expenses[0].bankAccountID = account.id; ledger.expenses[0].merchant = "Different shop"
        XCTAssertFalse(ledger.hasCrossSourcePaymentCandidate(payment, date: now))
        XCTAssertEqual(ledger.expenses.count, 1)
    }

    func testManualReceiptAndLaterNotificationCanBeLinkedWithoutSecondCredit() throws {
        let now = Date().addingTimeInterval(-60)
        var ledger = Ledger()
        let account = BankAccount(name: "Bank", openingCents: 0, openingDate: now.addingTimeInterval(-86400), automaticSource: "RHB")
        ledger.bankAccounts = [account]
        let id = try ledger.addManualReceipt(id: "receipt", sender: "James", cents: 1000, date: now, accountID: account.id)
        try ledger.resolveTNGIncoming(id: id, purpose: "income", date: now)
        var later = TNGNotice(bankAccountID: account.id, body: "Received", title: "", date: now, usesReceivedDate: false, kind: "incoming", status: "pending", cents: 1000, party: "James", possibleDuplicate: true)
        later.sourceBank = "RHB"; ledger.tngNotices.append(later)
        XCTAssertEqual(ledger.duplicateNoticeCandidates(later).map(\.id), [id])
        try ledger.dismissDuplicateTransactionNotice(id: later.id, originalNoticeID: id)
        XCTAssertEqual(ledger.bankBalance(account), 1000)
        XCTAssertThrowsError(try ledger.dismissDuplicateTransactionNotice(id: later.id, originalNoticeID: id))
        try ledger.reopenResolvedNotice(id: later.id)
        XCTAssertEqual(ledger.bankBalance(account), 1000)
    }

    func testManualFriendPaymentThenBankNotificationDoesNotDebitTwice() throws {
        let date = Date().addingTimeInterval(-120)
        var ledger = Ledger()
        let account = BankAccount(name: "Bank", openingCents: 10000, openingDate: date.addingTimeInterval(-86400), automaticSource: "RHB")
        ledger.bankAccounts = [account]
        ledger.expenses = [Expense(merchant: "Utilities", cents: 4040, date: date, shares: [Share(name: "James", cents: 0)], paidByFriend: "James")]
        let plan = try ledger.repaymentPlan(friend: "James", selected: Set(ledger.friendDebtItems.map(\.id)), payment: 4040, date: date, direction: .outgoing)
        _ = try ledger.confirmManualSettlement(plan, id: "manual-payment", accountID: account.id)
        _ = try ledger.receiveTNG(body: "You have paid RM40.40 to CHA JING YUAN.", title: "Payment", date: date.addingTimeInterval(60), eventID: "bank-payment", sourceApp: "RHB")
        let notification = try XCTUnwrap(ledger.tngNotices.last)
        XCTAssertTrue(notification.possibleDuplicate)
        XCTAssertEqual(notification.status, "pending")
        XCTAssertEqual(ledger.expenses.count, 1)
        XCTAssertEqual(ledger.bankBalance(account), 5960)
        try ledger.dismissDuplicateTransactionNotice(id: notification.id, originalNoticeID: "manual-payment")
        ledger = try JSONDecoder().decode(Ledger.self, from: JSONEncoder().encode(ledger)).validated()
        XCTAssertEqual(ledger.bankBalance(account), 5960)
        XCTAssertTrue(ledger.friendDebtItems.allSatisfy { $0.balance == 0 })
        try ledger.reopenResolvedNotice(id: notification.id)
        XCTAssertEqual(ledger.bankBalance(account), 5960)
    }

    func testAccountTransferTimelineShowsBothAccountsAsOneNonSpendingEntry() throws {
        let now = Date().addingTimeInterval(-60)
        var ledger = Ledger()
        let from = BankAccount(name: "Bank", openingCents: 10000, openingDate: now.addingTimeInterval(-86400))
        let to = BankAccount(name: "Wallet", openingCents: 0, openingDate: from.openingDate)
        ledger.bankAccounts = [from, to]
        let transfer = BankTransfer(fromAccountID: from.id, toAccountID: to.id, cents: 2000, date: now)
        try ledger.saveBankTransfer(transfer, replacing: nil)
        let query = LedgerTimelineQuery(revision: 1, month: now, search: "Wallet", filter: LedgerFilter(), provider: "all")
        let timeline = try LedgerTimelineSnapshot(ledger: ledger, month: now, query: query)
        XCTAssertEqual(timeline.count, 1)
        XCTAssertEqual(timeline.days.first?.spending, 0)
        XCTAssertEqual(timeline.days.first?.entries.first?.id, "account-transfer:" + transfer.id)
        XCTAssertEqual(ledger.bankBalance(from), 8000)
        XCTAssertEqual(ledger.bankBalance(to), 2000)
        var linked = transfer; linked.noticeIDs = ["out", "in"]
        let notices = ["out", "in"].map { TNGNotice(id: $0, body: "Transfer", title: "", date: now, usesReceivedDate: false, kind: "transfer", status: "transfer", cents: 2000) }
        let days = LedgerTimelineItem.grouped(expenses: [], transfers: notices, accountTransfers: [linked])
        XCTAssertEqual(days.flatMap(\.entries).count, 1)
    }
    func testStatementImportAddsSafeEntriesHoldsTransfersAndCanUndoAfterReload() throws {
        let (account, statement) = statementFixture()
        var ledger = Ledger(); ledger.bankAccounts = [account]
        let before = try LocalStore.encode(ledger)
        let result = try ledger.importStatement(statement, account: account, categories: [:])
        XCTAssertEqual(result.added, 2); XCTAssertEqual(result.pending, 2); XCTAssertEqual(result.skipped, 0)
        XCTAssertEqual(ledger.bankBalance(account), 99123)
        XCTAssertEqual(ledger.expenses.count, 1)
        XCTAssertTrue(ledger.incomes.isEmpty); XCTAssertTrue(ledger.budgetAllocations.isEmpty)
        XCTAssertEqual(ledger.tngNotices.first(where: { $0.id == "statement:b" })?.confirmedIncomeKind, .interest)
        XCTAssertTrue(ledger.tngNotices.filter { $0.status == "pending" }.allSatisfy { $0.balanceHeldForReview == true })
        XCTAssertEqual(ledger.statementBalance(account, before: statement.start.addingTimeInterval(86400)), 99000)
        let again = try ledger.importStatement(statement, account: account, categories: [:])
        XCTAssertEqual(again.skipped, 4); XCTAssertEqual(ledger.bankBalance(account), 99123)
        XCTAssertEqual(again.matched, 2)
        XCTAssertEqual(again.existingPending, 2)
        XCTAssertEqual(again.added, 0)
        ledger = try LocalStore.decode(LocalStore.encode(ledger))
        try ledger.undoStatementImport(batch: result.batch)
        XCTAssertEqual(ledger.bankBalance(account), 100000)
        XCTAssertEqual(try LocalStore.encode(ledger), before)
    }
    func testStatementPossibleExistingPaymentDoesNotDoubleDebit() throws {
        let (account, statement) = statementFixture()
        let expense = Expense(bankAccountID: account.id, merchant: "Existing purchase", cents: 1000, date: statement.start.addingTimeInterval(3600))
        var ledger = Ledger(expenses: [expense]); ledger.bankAccounts = [account]
        let result = try ledger.importStatement(statement, account: account, categories: [:])
        XCTAssertEqual(result.added, 1); XCTAssertEqual(result.pending, 3)
        XCTAssertEqual(ledger.expenses, [expense]); XCTAssertEqual(ledger.bankBalance(account), 99123)
        XCTAssertEqual(ledger.tngNotices.first?.possibleDuplicate, true)
    }
    func testStatementRejectsWrongAccountOrCorruptBalancesAtomically() throws {
        let (account, statement) = statementFixture()
        var wrong = account; wrong.automaticSuffix = "5678"
        var ledger = Ledger(); ledger.bankAccounts = [wrong]
        XCTAssertThrowsError(try ledger.importStatement(statement, account: wrong, categories: [:]))
        ledger.bankAccounts = [account]
        let bad = RHBStatement(accountHash: statement.accountHash, suffix: statement.suffix, start: statement.start, end: statement.end, opening: statement.opening, closing: statement.closing + 1, debitCount: 2, creditCount: 2, debitTotal: 3000, creditTotal: 3123, rows: statement.rows)
        XCTAssertThrowsError(try ledger.importStatement(bad, account: account, categories: [:]))
        XCTAssertTrue(ledger.expenses.isEmpty); XCTAssertTrue(ledger.tngNotices.isEmpty)
        XCTAssertEqual(ledger.bankBalance(account), 100000)
    }
    func testStatementUndoRefusesEditedOrPartlyDeletedBatchWithoutPartialRemoval() throws {
        let (account, statement) = statementFixture()
        var ledger = Ledger(); ledger.bankAccounts = [account]
        let result = try ledger.importStatement(statement, account: account, categories: [:])
        ledger.expenses[0].merchant = "Edited"
        let before = try LocalStore.encode(ledger)
        XCTAssertThrowsError(try ledger.undoStatementImport(batch: result.batch))
        XCTAssertEqual(try LocalStore.encode(ledger), before)
        ledger.tngNotices.removeLast()
        XCTAssertThrowsError(try ledger.undoStatementImport(batch: result.batch))
        XCTAssertEqual(ledger.tngNotices.count, 3)
    }
    func testStatementOpeningTimeSkipsCoveredDay() throws {
        var (account, statement) = statementFixture()
        account.openingDate = statement.start.addingTimeInterval(3600)
        var ledger = Ledger(); ledger.bankAccounts = [account]
        let result = try ledger.importStatement(statement, account: account, categories: [:])
        XCTAssertEqual(result.skipped, 1); XCTAssertEqual(result.added, 1)
        XCTAssertTrue(ledger.expenses.isEmpty); XCTAssertEqual(ledger.bankBalance(account), 100123)
    }
}

extension IncomeBudgetTests {
    /// Synthetic six-column PDF: never commit a customer's bank statement.
    private func syntheticStatementPDF(closing: String = "991.23") -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 595, height: 842))
        return renderer.pdfData { context in
            context.beginPage()
            let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 9)]
            func text(_ value: String, _ x: Double, _ y: Double) {
                (value as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: attributes)
            }
            text("RHB", 40, 30)
            text("Statement Period / Tempoh Penyata : 01 Jul 26 - 31 Jul 26", 40, 50)
            text("PRO SAVINGS ACCOUNT-i 123456781234", 40, 70)
            text("Debit", 370, 100); text("Credit", 440, 100); text("Balance", 510, 100)
            func row(_ y: Double, _ date: String, _ name: String, _ serial: String, _ debit: String, _ credit: String, _ balance: String) {
                text(date, 40, y); text(name, 85, y); text(serial, 280, y)
                text(debit, 370, y); text(credit, 440, y); text(balance, 510, y)
            }
            row(130, "01 Jul", "B/F BALANCE", "", "", "", "1,000.00")
            row(160, "02 Jul", "DEBITCARD TXN D", "1001", "10.00", "", "990.00")
            row(190, "31 Jul", "PROFIT CREDIT", "1002", "", "1.23", "991.23")
            row(220, "31 Jul", "C/F BALANCE", "", "", "", closing)
            text("Total Count", 280, 250); text("1", 370, 250); text("1", 440, 250)
            text("(RM)", 280, 270); text("10.00", 370, 270); text("1.23", 440, 270)
            text("YTD profit 9.99", 40, 310)
        }
    }
    func testNativePDFParserIgnoresSummaryAndChecksRunningTotals() throws {
        let statement = try RHBStatement.read(syntheticStatementPDF())
        XCTAssertEqual(statement.rows.count, 2)
        XCTAssertEqual(statement.rows.map(\.debit), [1000, 0])
        XCTAssertEqual(statement.rows.map(\.credit), [0, 123])
        XCTAssertEqual(statement.closing, 99123)
        XCTAssertEqual(statement.suffix, "1234")
        XCTAssertFalse(statement.accountHash.contains("123456781234"))
        XCTAssertThrowsError(try RHBStatement.read(syntheticStatementPDF(closing: "991.24")))
        XCTAssertThrowsError(try RHBStatement.read(Data("not a PDF".utf8)))
    }
    func testStatementClassificationRedactsAccountIdentifiers() {
        let row = StatementRow(id: "x", date: Date(), description: "DEBITCARD TXN D", serial: "", debit: 1, credit: 0, balance: 0, detail: "SHOP 1234 5678 9012 3456")
        XCTAssertFalse(row.analysisText.contains("1234"))
        XCTAssertTrue(row.analysisText.contains("SHOP"))
    }
}

extension IncomeBudgetTests {
    func testAdditionalStatementProviderGuardAndReviewOnlyImport() throws {
        XCTAssertEqual(financialProvider("Wise"), "Wise")
        XCTAssertEqual(financialProvider("Wise Payments Malaysia"), "Wise")
        XCTAssertNil(financialProvider("Otherwise"))
        var (account, statement) = statementFixture()
        statement.provider = "Wise"
        var ledger = Ledger(); ledger.bankAccounts = [account]
        XCTAssertThrowsError(try ledger.importStatement(statement, account: account, categories: [:]))
        account.institution = "Wise"; account.automaticSource = "Wise"
        ledger.bankAccounts = [account]
        statement.reviewOnly = true
        let result = try ledger.importStatement(statement, account: account, categories: [:])
        XCTAssertEqual(result.added, 0)
        XCTAssertEqual(result.pending, 4)
        XCTAssertEqual(ledger.bankBalance(account), account.openingCents)
        XCTAssertTrue(ledger.tngNotices.allSatisfy { $0.sourceBank == "Wise" && $0.title == "Wise statement" })
        let again = try ledger.importStatement(statement, account: account, categories: [:])
        XCTAssertEqual(again.skipped, 4)
        try ledger.undoStatementImport(batch: result.batch)
        XCTAssertTrue(ledger.tngNotices.isEmpty)
    }

    private func syntheticAmBankPDF(closing: String = "10.02") -> Data {
        UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 600, height: 840)).pdfData { context in
            context.beginPage()
            func text(_ s: String, _ x: CGFloat, _ y: CGFloat) {
                (s as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: [.font: UIFont.systemFont(ofSize: 8)])
            }
            text("AmBank ACCOUNT SUMMARY", 30, 30)
            text("ACCOUNT NO. / NO. AKAUN:", 300, 60); text("999999991234", 470, 60)
            text("STATEMENT DATE / TARIKH PENYATA: 01/09/2026 - 30/09/2026", 30, 90)
            text("MYR 1 of 1", 30, 110)
            text("OPENING BALANCE", 30, 160); text("0.00", 520, 160)
            text("TOTAL DEBITS", 30, 180); text("0", 420, 180); text("0.00", 520, 180)
            text("TOTAL CREDITS", 30, 200); text("2", 420, 200); text("10.02", 520, 200)
            text("CLOSING BALANCE", 30, 220); text(closing, 520, 220)
            text("02Sep", 42, 280); text("DuitNow CR TRF", 85, 280); text("10.00", 450, 280); text("10.00", 520, 280)
            text("30Sep", 42, 310); text("HIBAH/PROFIT, , ,", 85, 310); text("0.02", 450, 310); text("10.02", 520, 310)
        }
    }

    func testNativeAmBankStatementChecksTotalsAndProfit() throws {
        let statement = try RHBStatement.read(syntheticAmBankPDF())
        XCTAssertEqual(statement.provider, "AmBank")
        XCTAssertEqual(statement.suffix, "1234")
        XCTAssertEqual(statement.rows.count, 2)
        XCTAssertEqual(statement.rows.last?.credit, 2)
        XCTAssertEqual(statement.rows.last?.isInterest, true)
        XCTAssertEqual(statement.rows.first?.isInterest, false)
        XCTAssertEqual(statement.closing, 1002)
        XCTAssertThrowsError(try RHBStatement.read(syntheticAmBankPDF(closing: "10.03")))
    }

    func testNativeHongLeongLayoutAndMissingPrintedBalance() throws { try checkNativeStatementLayout("Hong Leong") }
    func testNativeMaybankLayout() throws { try checkNativeStatementLayout("Maybank") }
    func testNativeRytLayout() throws { try checkNativeStatementLayout("Ryt Bank") }
    func testNativeWiseLayout() throws { try checkNativeStatementLayout("Wise") }
    private func checkNativeStatementLayout(_ provider: String, file: StaticString = #filePath, line: UInt = #line) throws {
            let data = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 600, height: 840)).pdfData { context in
                context.beginPage()
                func text(_ s: String, _ x: CGFloat, _ y: CGFloat) {
                    (s as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: [.font: UIFont.systemFont(ofSize: 8)])
                }
                switch provider {
                case "Hong Leong":
                    text("Hong Leong Bank SAVINGS ACCOUNT STATEMENT MYR 1 of 1", 30, 30)
                    text("A/C No / No Akaun : 9999991234", 30, 60)
                    text("01/09/26 - 30/09/26", 30, 90)
                    text("Balance from previous statement", 100, 140); text("100.00", 520, 140)
                    text("02-09-2026", 52, 180); text("POS Purchase", 101, 180); text("10.00", 430, 180)
                    text("03-09-2026", 52, 210); text("POS Purchase", 101, 210); text("20.00", 430, 210); text("70.00", 520, 210)
                    text("Total Withdrawals", 30, 300); text("2", 225, 300); text("30.00", 290, 300)
                    text("Total Deposits", 30, 320); text("0", 225, 320); text("0.00", 290, 320)
                    text("Closing Balance", 380, 320); text("70.00", 520, 320)
                case "Maybank":
                    text("Maybank SAVINGS ACCOUNT-I", 30, 30)
                    text("30/09/26", 510, 60); text("999999-991234", 450, 90)
                    text("BEGINNING BALANCE", 100, 140); text("100.00", 520, 140)
                    text("02/09/26", 52, 180); text("SALE DEBIT", 101, 180); text("30.00-", 410, 180); text("70.00", 520, 180)
                    text("ENDING BALANCE", 100, 300); text("70.00", 410, 300)
                    text("TOTAL CREDIT", 100, 320); text("0.00", 410, 320)
                    text("TOTAL DEBIT", 100, 340); text("30.00", 410, 340)
                case "Ryt Bank":
                    text("YTL Digital Bank MYR", 30, 30)
                    text("From 1 Sep 2026 to 30 Sep 2026", 30, 60)
                    text("Nombor Akaun Simpanan : 99 9999 1234", 30, 90)
                    text("Main Savings", 40, 160)
                    text("1.00", 200, 166); text("+0.01", 270, 166); text("0.00", 360, 166); text("0.00", 440, 166); text("1.01", 530, 166)
                    text("Ryt Pocket 999.00", 40, 200)
                    context.beginPage()
                    text("Main Account / Akaun Utama", 30, 30)
                    text("1 Sep 2026", 46, 100); text("Opening balance", 125, 100); text("1.00", 530, 100)
                    text("20 Sep 2026", 46, 160); text("Daily interest payout", 125, 160); text("+0.01", 445, 160); text("1.01", 530, 160)
                    text("Closing balance (MYR)", 340, 220); text("1.01", 530, 220)
                    text("END OF STATEMENT", 200, 280)
                    context.beginPage(); text("Notes", 30, 30)
                default:
                    text("Wise Payments Malaysia MYR statement", 30, 30)
                    text("1 October 2026 [GMT+08:00] - 31 October 2026 [GMT+08:00]", 30, 60)
                    text("999999999991234", 310, 100)
                    text("MYR on 31 October 2026 [GMT+08:00] 0.01 MYR", 30, 140)
                    text("Received money from SAMPLE", 45, 200); text("0.01", 400, 200); text("0.01", 530, 200)
                    text("1 October 2026 | Transaction: TRANSFER-123 | Reference: Test", 45, 220)
                    text("1 / 1", 540, 800)
                }
            }
            let result: RHBStatement
            do { result = try RHBStatement.read(data) }
            catch {
                XCTFail("\(provider) synthetic PDF: \(error)", file: file, line: line)
                // Synthetic fixture only: expose PDFKit's extraction in CI to
                // distinguish text ordering from column/balance failures.
                if let document = PDFDocument(data: data) {
                    print("Synthetic \(provider) PDF text: \(document.string ?? "<empty>")")
                }
                return
            }
            XCTAssertEqual(result.provider, provider)
            XCTAssertEqual(result.suffix, "1234")
            switch provider {
            case "Hong Leong":
                XCTAssertEqual(result.rows.map(\.balance), [9000, 7000])
                XCTAssertFalse(result.verificationNote.isEmpty)
            case "Maybank": XCTAssertEqual(result.rows.first?.debit, 3000)
            case "Ryt Bank": XCTAssertEqual(result.closing, 101); XCTAssertEqual(result.rows.first?.isInterest, true)
            default: XCTAssertEqual(result.opening, 0); XCTAssertTrue(result.reviewOnly)
            }
    }

    func testOverlappingStatementSkipsExistingRowsAndSameDaySameAmountsNeedReview() throws {
        let (account, full) = statementFixture()
        let partial = RHBStatement(accountHash: full.accountHash, suffix: full.suffix, start: full.start, end: full.end,
                                   opening: 100000, closing: 99123, debitCount: 1, creditCount: 1, debitTotal: 1000, creditTotal: 123, rows: Array(full.rows.prefix(2)))
        var ledger = Ledger(); ledger.bankAccounts = [account]
        _ = try ledger.importStatement(partial, account: account, categories: [:])
        let second = try ledger.importStatement(full, account: account, categories: [:])
        XCTAssertEqual(second.skipped, 2); XCTAssertEqual(second.added, 0); XCTAssertEqual(second.pending, 2)
        XCTAssertEqual(ledger.bankBalance(account), 99123)
        let rows = [
            StatementRow(id: "repeat:1", date: full.start, description: "DEBITCARD TXN D", serial: "1", debit: 1000, credit: 0, balance: 99000),
            StatementRow(id: "repeat:2", date: full.start, description: "DEBITCARD TXN D", serial: "2", debit: 1000, credit: 0, balance: 98000)
        ]
        let repeated = RHBStatement(accountHash: full.accountHash, suffix: full.suffix, start: full.start, end: full.end,
                                    opening: 100000, closing: 98000, debitCount: 2, creditCount: 0, debitTotal: 2000, creditTotal: 0, rows: rows)
        var fresh = Ledger(); fresh.bankAccounts = [account]
        let result = try fresh.importStatement(repeated, account: account, categories: [:])
        XCTAssertEqual(result.pending, 2); XCTAssertEqual(result.added, 0)
        XCTAssertEqual(fresh.bankBalance(account), 100000)
    }
    func testStatementUndoRefusesConfirmedPendingReceipt() throws {
        let (account, statement) = statementFixture()
        var ledger = Ledger(); ledger.bankAccounts = [account]
        let result = try ledger.importStatement(statement, account: account, categories: [:])
        try ledger.resolveNotice(id: "statement:d", purpose: "income", party: "Allowance", cents: 3000, date: statement.rows[3].date, incomeKind: .allowance)
        XCTAssertEqual(ledger.bankBalance(account), 102123)
        let before = try LocalStore.encode(ledger)
        XCTAssertThrowsError(try ledger.undoStatementImport(batch: result.batch))
        XCTAssertEqual(try LocalStore.encode(ledger), before)
    }
}
