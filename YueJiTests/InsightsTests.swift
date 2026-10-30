import XCTest
@testable import YueJi

final class GeminiReceiptDraftTests: XCTestCase {
    private func draft(currency: String = "MYR", total: String = "10.00") throws -> GeminiReceiptDraft {
        let object: [String: Any] = ["merchant": "Cafe", "date": "", "currency": currency,
            "subtotal": "10.00", "tax": "", "service": "", "discount": "", "rounding": "-0.01", "total": total,
            "items": [["name": "Rice", "amount": "10.00"]]]
        return try JSONDecoder().decode(GeminiReceiptDraft.self, from: JSONSerialization.data(withJSONObject: object))
    }
    func testMissingDateAndAmountsRemainMissingForReview() throws {
        let receipt = try draft().reviewedDraft()
        XCTAssertNil(receipt.date)
        XCTAssertEqual(receipt.tax, "")
        XCTAssertEqual(receipt.rounding, "-0.01")
        XCTAssertEqual(receipt.items.first?.amount, "10.00")
        XCTAssertFalse(receipt.scanNotice.isEmpty)
    }
    func testRejectsNonMYRAndMalformedTotals() throws {
        XCTAssertThrowsError(try draft(currency: "USD").reviewedDraft())
        XCTAssertThrowsError(try draft(total: "-10.00").reviewedDraft())
        XCTAssertThrowsError(try draft(total: "10.001").reviewedDraft())
    }
}

final class BankAccountTests: XCTestCase {
    let opening = Date(timeIntervalSince1970: 1_700_000_000)

    func testObservedPublicBankShopeePaymentUpdatesBalanceAndSpendingOnce() throws {
        let body = "FPX Payment: You have paid RM57.14 to Shopee MarketPlace via MyPB."
        for suffix in [nil, "1234"] as [String?] {
            var account = BankAccount(name: "Public Bank", openingCents: 100000, openingDate: opening)
            account.automaticSource = "Public Bank"
            account.automaticSuffix = suffix
            var ledger = Ledger(); ledger.bankAccounts = [account]
            _ = try ledger.receiveTNG(body: body, title: "Money Paid", date: opening, eventID: "pb-shopee-5714")
            let expense = try XCTUnwrap(ledger.expenses.first)
            XCTAssertEqual(expense.merchant, "Shopee MarketPlace")
            XCTAssertEqual(expense.cents, 5714)
            XCTAssertEqual(expense.source, "Public Bank")
            XCTAssertEqual(expense.personalSpending, 5714)
            XCTAssertNil(expense.tripID)
            XCTAssertEqual(monthKey(expense.date), monthKey(opening))
            XCTAssertEqual(expense.bankAccountID, suffix == nil ? account.id : nil)
            XCTAssertEqual(ledger.bankBalance(account), suffix == nil ? 94286 : 100000)
            _ = try ledger.receiveTNG(body: body, title: "Money Paid", date: opening, eventID: "pb-shopee-5714")
            XCTAssertEqual(ledger.expenses.count, 1)
            XCTAssertEqual(ledger.tngNotices.count, 1)
        }
    }

    func testTransferFullNamePhraseMatching() {
        XCTAssertTrue(transferNameMatches("TAN LAY K/CHONG MING ZHE", owner: "chong  ming zhe"))
        XCTAssertFalse(transferNameMatches("CHONG MING ZHENG", owner: "CHONG MING ZHE"))
        XCTAssertFalse(transferNameMatches("CHONG MING", owner: "CHONG MING ZHE"))
        XCTAssertFalse(transferNameMatches("OTHER PERSON", owner: "CHONG MING ZHE"))
    }

    func testTNGReceiptCreditsOnceBeforeIncomeConfirmation() throws {
        var account = BankAccount(name: "TNG", openingCents: 10000, openingDate: opening)
        account.automaticSource = "TNG"
        var ledger = Ledger(); ledger.bankAccounts = [account]
        let body = "OTHER PERSON has transferred RM150.00 to you. Tap here to check the transaction details."
        _ = try ledger.receiveTNG(body: body, title: "You've received money!", date: opening, eventID: "receipt")
        let notice = try XCTUnwrap(ledger.tngNotices.first)
        XCTAssertEqual(ledger.bankBalance(account), 25000)
        XCTAssertFalse(notice.isConfirmedIncome)
        _ = try ledger.receiveTNG(body: body, title: "You've received money!", date: opening, eventID: "receipt-copy")
        XCTAssertEqual(ledger.bankBalance(account), 25000)
        try ledger.resolveTNGIncoming(id: notice.id, purpose: "income", date: opening)
        XCTAssertEqual(ledger.bankBalance(account), 25000)
        try ledger.reopenTNGIncoming(id: notice.id)
        XCTAssertEqual(ledger.bankBalance(account), 25000)
        try ledger.resolveTNGIncoming(id: notice.id, purpose: "ignored", date: opening)
        XCTAssertEqual(ledger.bankBalance(account), 10000)
    }

    func testAutomaticTransferRequiresOptInAndBothNoticesThenCanUndo() throws {
        var source = BankAccount(name: "TNG", openingCents: 10000, openingDate: opening)
        var target = BankAccount(name: "Ryt", openingCents: 20000, openingDate: opening)
        source.automaticSource = "TNG"; target.automaticSource = "Ryt Bank"
        var ledger = Ledger(); ledger.bankAccounts = [source, target]
        let outgoing = "You have successfully transferred RM 0.10 to CHONG MING ZHE."
        let incoming = "You've received RM0.10 from CHONG MING ZHE on 30/10/2026, 6:51 PM (GMT+8)."
        let stamp = try XCTUnwrap(parseBankNotification(incoming, title: "Your money is in!")?.transactionDate)
        source.transferDestinationID = target.id; source.transferOwnerName = "CHONG MING ZHE"
        source.transferRuleSince = stamp.addingTimeInterval(-60)
        ledger.bankAccounts[0] = source
        _ = try ledger.receiveTNG(body: outgoing, title: "DuitNow Transfer is successful!", date: stamp, eventID: "out", now: stamp, sourceApp: "TNG")
        XCTAssertTrue(ledger.bankTransfers.isEmpty)
        _ = try ledger.receiveTNG(body: incoming, title: "Your money is in!", date: stamp, eventID: "in", now: stamp, sourceApp: "Ryt Bank")
        XCTAssertEqual(ledger.bankTransfers.count, 1)
        XCTAssertEqual(ledger.bankBalance(source), 9990)
        XCTAssertEqual(ledger.bankBalance(target), 20010)
        XCTAssertTrue(ledger.expenses.isEmpty)
        XCTAssertTrue(ledger.incomes.isEmpty)
        _ = try ledger.receiveTNG(body: incoming, title: "Your money is in!", date: stamp, eventID: "in", now: stamp, sourceApp: "Ryt Bank")
        XCTAssertEqual(ledger.bankTransfers.count, 1)
        let id = try XCTUnwrap(ledger.bankTransfers.first?.noticeIDs?.first)
        let restored = try JSONDecoder().decode(Ledger.self, from: JSONEncoder().encode(ledger))
        XCTAssertEqual(restored.bankTransfers.count, 1)
        try ledger.reopenResolvedNotice(id: id)
        XCTAssertTrue(ledger.bankTransfers.isEmpty)
        XCTAssertEqual(ledger.bankBalance(source), 10000)
        XCTAssertEqual(ledger.bankBalance(target), 20000)
        ledger.bankAccounts[0].transferDestinationID = nil
        XCTAssertFalse(try ledger.matchAutomaticTransfer(newNoticeID: id))
    }

    func testAutomaticTransferRefusesAmbiguousCandidates() throws {
        var source = BankAccount(name: "TNG", openingCents: 10000, openingDate: opening)
        let target = BankAccount(name: "Ryt", openingCents: 0, openingDate: opening)
        source.automaticSource = "TNG"; source.transferDestinationID = target.id
        source.transferOwnerName = "Owner"; source.transferRuleSince = opening
        var out = TNGNotice(body: "out", title: "", date: opening, usesReceivedDate: false, kind: "transfer", status: "transfer", cents: 10, party: "Owner")
        out.bankAccountID = source.id
        var incoming = TNGNotice(body: "in", title: "", date: opening, usesReceivedDate: false, kind: "incoming", status: "pending", cents: 10, party: "Owner")
        incoming.bankAccountID = target.id
        var another = incoming; another.id = UUID().uuidString
        var ledger = Ledger(); ledger.bankAccounts = [source, target]; ledger.tngNotices = [out, incoming, another]
        XCTAssertFalse(try ledger.matchAutomaticTransfer(newNoticeID: out.id))
        XCTAssertTrue(ledger.bankTransfers.isEmpty)
    }

    func testTransferConservesMoneyAndEditDeleteRecalculateBothAccounts() throws {
        let bank = BankAccount(name: "Maybank", openingCents: 50000, openingDate: opening)
        let wallet = BankAccount(name: "TNG", openingCents: 2000, openingDate: opening)
        var ledger = Ledger(); ledger.bankAccounts = [bank, wallet]
        let transfer = BankTransfer(fromAccountID: bank.id, toAccountID: wallet.id, cents: 10000, date: opening)
        try ledger.saveBankTransfer(transfer, replacing: nil)
        XCTAssertEqual(ledger.bankBalance(bank), 40000)
        XCTAssertEqual(ledger.bankBalance(wallet), 12000)
        XCTAssertEqual(ledger.bankBalance(bank) + ledger.bankBalance(wallet), 52000)
        XCTAssertTrue(ledger.expenses.isEmpty)
        XCTAssertTrue(ledger.incomes.isEmpty)
        var edited = transfer; edited.cents = 5000
        try ledger.saveBankTransfer(edited, replacing: transfer)
        XCTAssertEqual(ledger.bankBalance(bank), 45000)
        XCTAssertEqual(ledger.bankBalance(wallet), 7000)
        XCTAssertThrowsError(try ledger.deleteBankTransfer(transfer))
        try ledger.deleteBankTransfer(edited)
        XCTAssertEqual(ledger.bankBalance(bank), 50000)
        XCTAssertEqual(ledger.bankBalance(wallet), 2000)
    }

    func testTransferValidationIsAtomicAndOpeningCutoffIsPerAccount() throws {
        let bank = BankAccount(name: "Bank", openingCents: 50000, openingDate: opening)
        let wallet = BankAccount(name: "TNG", openingCents: 12000, openingDate: opening.addingTimeInterval(60))
        var ledger = Ledger(); ledger.bankAccounts = [bank, wallet]
        let transfer = BankTransfer(fromAccountID: bank.id, toAccountID: wallet.id, cents: 10000, date: opening)
        var invalid = transfer; invalid.toAccountID = bank.id
        XCTAssertThrowsError(try ledger.saveBankTransfer(invalid, replacing: nil))
        invalid = transfer; invalid.toAccountID = "missing"
        XCTAssertThrowsError(try ledger.saveBankTransfer(invalid, replacing: nil))
        invalid = transfer; invalid.cents = -1
        XCTAssertThrowsError(try ledger.saveBankTransfer(invalid, replacing: nil))
        XCTAssertTrue(ledger.bankTransfers.isEmpty)
        try ledger.saveBankTransfer(transfer, replacing: nil)
        XCTAssertThrowsError(try ledger.saveBankTransfer(transfer, replacing: nil))
        XCTAssertEqual(ledger.bankBalance(bank), 40000)
        XCTAssertEqual(ledger.bankBalance(wallet), 12000)
        let data = try JSONEncoder().encode(ledger)
        let restored = try JSONDecoder().decode(Ledger.self, from: data)
        XCTAssertEqual(restored.bankTransfers, [transfer])
        XCTAssertEqual(restored.bankBalance(bank), 40000)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        legacy.removeValue(forKey: "bankTransfers")
        let old = try JSONDecoder().decode(Ledger.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertTrue(old.bankTransfers.isEmpty)
    }

    func testTNGWithoutSuffixMatchesOnlyAfterSuffixRuleIsCleared() throws {
        var account = BankAccount(name: "TNG", openingCents: 10000, openingDate: opening)
        account.automaticSource = "TNG"
        account.automaticSuffix = "1234"
        var ledger = Ledger(); ledger.bankAccounts = [account]
        _ = try ledger.receiveTNG(body: "You have paid RM6.00 for Shop.", date: opening, eventID: "suffix-missing")
        XCTAssertNil(ledger.expenses.first?.bankAccountID)
        XCTAssertEqual(ledger.bankBalance(account), 10000)
        ledger.bankAccounts[0].automaticSuffix = nil
        _ = try ledger.receiveTNG(body: "You have paid RM8.00 for Cafe.", date: opening.addingTimeInterval(300), eventID: "suffix-cleared")
        XCTAssertEqual(ledger.expenses.last?.bankAccountID, account.id)
        XCTAssertEqual(ledger.bankBalance(account), 9200)
        XCTAssertNil(ledger.expenses.first?.bankAccountID)
    }

    func testAssignExistingApplePayMovesBalanceWithoutDuplicatingPayment() throws {
        let first = BankAccount(name: "First", openingCents: 10000, openingDate: opening)
        let second = BankAccount(name: "Second", openingCents: 5000, openingDate: opening)
        var ledger = Ledger(); ledger.bankAccounts = [first, second]
        _ = try ledger.addPayment(amount: 20, merchant: "Shop", currency: "MYR", date: opening, eventID: "assign-existing")
        let id = try XCTUnwrap(ledger.expenses.first?.id)
        try ledger.assignApplePayAccount(id: id, accountID: first.id)
        XCTAssertEqual(ledger.bankBalance(first), 8000)
        try ledger.assignApplePayAccount(id: id, accountID: second.id)
        XCTAssertEqual(ledger.bankBalance(first), 10000)
        XCTAssertEqual(ledger.bankBalance(second), 3000)
        XCTAssertEqual(ledger.expenses.count, 1)
        XCTAssertThrowsError(try ledger.assignApplePayAccount(id: id, accountID: "missing"))
        XCTAssertEqual(ledger.expenses.first?.bankAccountID, second.id)
        try ledger.assignApplePayAccount(id: id, accountID: nil)
        XCTAssertEqual(ledger.bankBalance(second), 5000)
    }

    func testApplePayAccountSurvivesQueuedDeliveryAndDoesNotDoubleDebit() throws {
        let account = BankAccount(name: "Card account", openingCents: 10000, openingDate: opening)
        var ledger = Ledger(); ledger.bankAccounts = [account]
        var delivery = AutomationDelivery(kind: "applePay", date: opening, eventID: "wallet-route", amount: 20, merchant: "Shop")
        delivery.bankAccountID = account.id
        let decoded = try JSONDecoder().decode(AutomationDelivery.self, from: JSONEncoder().encode(delivery))
        _ = try ledger.applyDelivery(decoded)
        XCTAssertEqual(ledger.expenses.first?.bankAccountID, account.id)
        XCTAssertEqual(ledger.bankBalance(account), 8000)
        _ = try ledger.applyDelivery(decoded)
        XCTAssertEqual(ledger.bankBalance(account), 8000)
    }

    func testApplePayMissingAccountCannotChargeAnotherAccount() throws {
        var ledger = Ledger()
        XCTAssertThrowsError(try ledger.addPayment(amount: 20, merchant: "Shop", currency: "MYR", date: opening, eventID: "missing-card", bankAccountID: "old-account"))
        XCTAssertTrue(ledger.expenses.isEmpty)
        XCTAssertTrue(try ledger.addPayment(amount: 20, merchant: "Shop", currency: "MYR", date: opening, eventID: "legacy-shortcut"))
        XCTAssertNil(ledger.expenses.first?.bankAccountID)
    }

    func testAutomaticPaymentRoutesOnceAndRuleChangesDoNotMoveHistory() throws {
        let wallet = BankAccount(name: "TNG", openingCents: 10000, openingDate: opening, automaticSource: "TNG")
        var ledger = Ledger(); ledger.bankAccounts = [wallet]
        let body = "You have paid RM35.00 for Shop."
        _ = try ledger.receiveTNG(body: body, date: opening, eventID: "route-once")
        XCTAssertEqual(ledger.expenses.first?.bankAccountID, wallet.id)
        XCTAssertEqual(ledger.bankBalance(wallet), 6500)
        _ = try ledger.receiveTNG(body: body, date: opening, eventID: "route-once")
        XCTAssertEqual(ledger.bankBalance(wallet), 6500)
        ledger.bankAccounts[0].automaticSource = nil
        XCTAssertEqual(ledger.bankBalance(wallet), 6500)
        let restored = try LocalStore.decode(LocalStore.encode(ledger))
        XCTAssertEqual(restored.bankBalance(wallet), 6500)
    }

    func testBankSuffixMatchingDoesNotGuessBetweenAccounts() {
        let first = BankAccount(name: "CIMB savings", openingCents: 0, openingDate: opening, automaticSource: "CIMB", automaticSuffix: "1234")
        let second = BankAccount(name: "CIMB current", openingCents: 0, openingDate: opening, automaticSource: "CIMB", automaticSuffix: "5678")
        var ledger = Ledger(); ledger.bankAccounts = [first, second]
        XCTAssertEqual(ledger.automaticBankAccount(source: "CIMB OCTO", suffix: "1234"), first.id)
        XCTAssertNil(ledger.automaticBankAccount(source: "CIMB", suffix: nil))
        XCTAssertNil(ledger.automaticBankAccount(source: "CIMB", suffix: "9999"))
        XCTAssertNil(ledger.automaticBankAccount(source: "Apple Pay", suffix: "1234"))
        ledger.bankAccounts[1].automaticSuffix = "1234"
        XCTAssertNil(ledger.automaticBankAccount(source: "CIMB", suffix: "1234"))
    }

    func testNotificationIncomeRequiresConfirmationAndReopeningReversesBalance() throws {
        let account = BankAccount(name: "Maybank", openingCents: 10000, openingDate: opening)
        var notice = TNGNotice(body: "Income", title: "", date: opening, usesReceivedDate: false, kind: "incoming", status: "pending", cents: 2500, party: "Salary")
        notice.sourceBank = "Maybank"
        notice.bankAccountID = account.id
        var ledger = Ledger(); ledger.bankAccounts = [account]; ledger.tngNotices = [notice]
        XCTAssertEqual(ledger.bankBalance(account), 10000)
        try ledger.resolveTNGIncoming(id: notice.id, purpose: "income", date: opening)
        XCTAssertEqual(ledger.bankBalance(account), 12500)
        try ledger.reopenTNGIncoming(id: notice.id)
        XCTAssertEqual(ledger.bankBalance(account), 10000)
    }

    func testManualNoticeAssignmentUpdatesLinkedExpenseWithoutDoubleCounting() throws {
        let account = BankAccount(name: "TNG", openingCents: 10000, openingDate: opening)
        var ledger = Ledger(); ledger.bankAccounts = [account]
        _ = try ledger.receiveTNG(body: "You have paid RM35.00 for Shop.", date: opening, eventID: "manual-route")
        let notice = try XCTUnwrap(ledger.tngNotices.first)
        XCTAssertEqual(ledger.bankBalance(account), 10000)
        try ledger.assignNoticeAccount(id: notice.id, accountID: account.id)
        XCTAssertEqual(ledger.bankBalance(account), 6500)
        try ledger.assignNoticeAccount(id: notice.id, accountID: nil)
        XCTAssertEqual(ledger.bankBalance(account), 10000)
    }

    func testBalanceUsesFullPaymentNotPersonalShareAndIgnoresOtherAccounts() {
        let account = BankAccount(name: "Maybank", openingCents: 100_000, openingDate: opening)
        var expense = Expense(merchant: "Dinner", cents: 6000, date: opening, shares: [Share(name: "Alex", cents: 3000)])
        expense.bankAccountID = account.id
        var income = IncomeEntry(source: "Salary", cents: 20_000, date: opening)
        income.bankAccountID = account.id
        var ledger = Ledger(expenses: [expense, Expense(merchant: "Unassigned", cents: 5000, date: opening)])
        ledger.bankAccounts = [account]; ledger.incomes = [income]
        XCTAssertEqual(ledger.bankBalance(account), 114_000)
        ledger.expenses[0].cents = 7000
        XCTAssertEqual(ledger.bankBalance(account), 113_000)
        ledger.expenses.removeFirst()
        XCTAssertEqual(ledger.bankBalance(account), 120_000)
    }

    func testOpeningCutoffAndRefundToOriginalAccount() {
        let account = BankAccount(name: "CIMB", openingCents: 5000, openingDate: opening)
        var expense = Expense(merchant: "Before opening", cents: 2000, date: opening.addingTimeInterval(-60))
        expense.bankAccountID = account.id
        expense.refunds = [RefundRecord(cents: 500, date: opening, personalCents: 500, shares: [:])]
        var ledger = Ledger(expenses: [expense]); ledger.bankAccounts = [account]
        XCTAssertEqual(ledger.bankBalance(account), 5500)
        ledger.expenses[0].refunds?[0].receivedByMe = false
        XCTAssertEqual(ledger.bankBalance(account), 5000)
        ledger.expenses[0].date = opening
        ledger.expenses[0].paidByFriend = "Alex"
        XCTAssertEqual(ledger.bankBalance(account), 5000)
    }

    func testAccountsRoundTripAndLegacyBackupDefaults() throws {
        let account = BankAccount(name: "Savings", openingCents: 0, openingDate: opening, institution: "CIMB Bank")
        var ledger = Ledger(); ledger.bankAccounts = [account]
        let restored = try LocalStore.decode(LocalStore.encode(ledger))
        XCTAssertEqual(restored.bankAccounts, [account])
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: LocalStore.encode(ledger)) as? [String: Any])
        var accounts = try XCTUnwrap(object["bankAccounts"] as? [[String: Any]])
        accounts[0].removeValue(forKey: "institution")
        object["bankAccounts"] = accounts
        let legacyAccount = try LocalStore.decode(JSONSerialization.data(withJSONObject: object)).bankAccounts.first
        XCTAssertEqual(legacyAccount?.name, account.name)
        XCTAssertNil(legacyAccount?.institution)
        object.removeValue(forKey: "bankAccounts")
        XCTAssertTrue(try LocalStore.decode(JSONSerialization.data(withJSONObject: object)).bankAccounts.isEmpty)
    }

    func testInvalidOrMissingAccountRejected() throws {
        var ledger = Ledger()
        ledger.bankAccounts = [BankAccount(name: " ", openingCents: 0, openingDate: opening)]
        XCTAssertThrowsError(try ledger.validated())
        ledger.bankAccounts = []
        var expense = Expense(merchant: "Missing account", cents: 100)
        expense.bankAccountID = "missing"
        ledger.expenses = [expense]
        XCTAssertThrowsError(try ledger.validated())
    }
}

final class EverydayToolsTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Kuala_Lumpur")!
        return value
    }
    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }
    func testCalendarIncludesLeapDayAndExcludesNextMonthMidnight() {
        let ledger = Ledger(expenses: [
            Expense(merchant: "Shared lunch", cents: 3000, date: day(2024, 2, 29), shares: [Share(name: "Alex", cents: 1000)]),
            Expense(merchant: "Next month", cents: 5000, date: day(2024, 3, 1))
        ])
        let days = ledger.spendingCalendar(month: day(2024, 2, 15), calendar: calendar)
        XCTAssertEqual(days.count, 29)
        XCTAssertEqual(days.reduce(0) { $0 + $1.total }, 2000)
        XCTAssertEqual(days.last?.entries.count, 1)
        XCTAssertEqual(days.first?.total, 0)
    }
    func testCalendarHandlesDaylightSavingWithoutDroppingDays() {
        var local = Calendar(identifier: .gregorian)
        local.timeZone = TimeZone(identifier: "America/New_York")!
        let month = local.date(from: DateComponents(year: 2026, month: 3, day: 1))!
        let days = Ledger().spendingCalendar(month: month, calendar: local)
        XCTAssertEqual(days.count, 31)
        XCTAssertEqual(Set(days.map(\.date)).count, 31)
        XCTAssertTrue(days.allSatisfy { local.component(.hour, from: $0.date) == 0 })
    }
    func testCoolingListRoundTripsAndOldBackupsDefaultToEmpty() throws {
        let item = CoolingPurchase(name: "Headphones", cents: 25000, createdAt: day(2026, 10, 1), reviewAt: day(2026, 10, 4))
        var ledger = Ledger(); ledger.coolingPurchases = [item]
        let encoded = try LocalStore.encode(ledger)
        XCTAssertEqual(try LocalStore.decode(encoded).coolingPurchases, [item])
        var old = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        old.removeValue(forKey: "coolingPurchases")
        XCTAssertTrue(try LocalStore.decode(JSONSerialization.data(withJSONObject: old)).coolingPurchases.isEmpty)
    }
    func testCoolingDecisionDoesNotCreateExpenseAndRejectsStaleUpdates() throws {
        let item = CoolingPurchase(name: "Headphones", cents: 25000, createdAt: day(2026, 10, 1), reviewAt: day(2026, 10, 4))
        var ledger = Ledger(); ledger.coolingPurchases = [item]
        try ledger.updateCoolingPurchase(item, decision: .buy)
        XCTAssertTrue(ledger.expenses.isEmpty)
        XCTAssertEqual(ledger.coolingPurchases.first?.decision, .buy)
        XCTAssertThrowsError(try ledger.updateCoolingPurchase(item, decision: .declined))
        var invalid = item; invalid.cents = 0
        XCTAssertThrowsError(try invalid.validate())
        invalid = item; invalid.reviewAt = day(2026, 9, 30)
        XCTAssertThrowsError(try invalid.validate())
        ledger.coolingPurchases = [item, item]
        XCTAssertThrowsError(try ledger.validated())
    }
}

final class YearReviewTests: XCTestCase {
    private let calendar = InsightCalendar.make()
    private func day(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    func testYearCountsSpendingExactlyAsTheOverviewDoes() throws {
        let ledger = Ledger(expenses: [
            Expense(merchant: "Lunch", cents: 4000, date: day(2026, 1, 5), category: "餐饮"),
            // Ali's share is not my spending.
            Expense(merchant: "Dinner", cents: 9000, date: day(2026, 1, 5, hour: 20), category: "餐饮",
                    shares: [Share(name: "Ali", cents: 3000)]),
            Expense(merchant: "Aeon", cents: 3200, date: day(2026, 3, 9),
                    items: [ExpenseItem(name: "Lunch", cents: 1600, category: "餐饮"),
                            ExpenseItem(name: "Paper", cents: 1600, category: "购物")]),
            Expense(merchant: "Grab", cents: 1500, date: day(2026, 10, 2), category: "交通"),
            Expense(merchant: "Last year", cents: 9900, date: day(2025, 12, 31)),
        ])
        let year = YearSnapshot(ledger: ledger, year: 2026, now: day(2026, 10, 24))
        for month in 1...12 {
            XCTAssertEqual(year.months[month - 1], OverviewSnapshot(ledger: ledger, month: day(2026, month, 1)).personal, "Month \(month)")
        }
        XCTAssertEqual(year.total, 4000 + 6000 + 3200 + 1500)
        XCTAssertEqual(year.entries, 4)
        let fifth = calendar.startOfDay(for: day(2026, 1, 5))
        XCTAssertEqual(year.days[fifth], SpendingDay(cents: 10000, entries: 2))
        XCTAssertEqual(year.biggestDay, fifth)
        XCTAssertEqual(year.busiestMonth, 1)
        // Items spread over their categories, as in the Overview.
        XCTAssertEqual(year.categories.first { $0.category == "餐饮" }?.cents, 4000 + 6000 + 1600)
        XCTAssertEqual(year.categories.first { $0.category == "购物" }?.cents, 1600)
        XCTAssertEqual(year.merchants.map(\.name), ["Dinner", "Lunch", "Aeon", "Grab"])
        XCTAssertEqual(year.earliestYear, 2025)
        // 1 January to 24 October 2026, with spending on three of those days.
        XCTAssertEqual(year.trackedDays, 297)
        XCTAssertEqual(year.noSpendDays, 294)
        XCTAssertEqual(year.trackedMonths, 10)
        XCTAssertEqual(year.monthlyAverage, 1470)
        // Records only began on the last day of 2025: no comparison with a part-year.
        XCTAssertNil(year.previousSamePeriod)
        XCTAssertNil(year.change)
    }

    func testComparesWithTheSameDatesOfTheYearBefore() throws {
        let ledger = Ledger(expenses: [
            Expense(merchant: "A", cents: 1000, date: day(2025, 1, 10)),
            Expense(merchant: "B", cents: 2000, date: day(2025, 10, 24)),
            Expense(merchant: "After the same date", cents: 5000, date: day(2025, 11, 3)),
            Expense(merchant: "C", cents: 4500, date: day(2026, 2, 1)),
        ])
        let year = YearSnapshot(ledger: ledger, year: 2026, now: day(2026, 10, 24))
        XCTAssertEqual(year.previousSamePeriod, 3000)
        XCTAssertEqual(try XCTUnwrap(year.change), 0.5, accuracy: 0.0001)

        let last = YearSnapshot(ledger: ledger, year: 2025, now: day(2026, 10, 24))
        XCTAssertEqual(last.total, 8000)
        XCTAssertNil(last.previousSamePeriod)
        // A past year counts from its first entry to its end.
        XCTAssertEqual(last.trackedFrom, calendar.startOfDay(for: day(2025, 1, 10)))
        XCTAssertEqual(last.trackedDays, 356)

        let future = YearSnapshot(ledger: ledger, year: 2027, now: day(2026, 10, 24))
        XCTAssertEqual(future.total, 0)
        XCTAssertEqual(future.trackedDays, 0)
        XCTAssertNil(future.previousSamePeriod)
    }

    func testHeatStepsUseQuartilesAndTheLargestDayIsDarkest() {
        let few = SpendingHeatScale(amounts: [0, 1000, 4000])
        XCTAssertEqual(few.level(0), 0)
        XCTAssertEqual(few.level(1000), 1)
        XCTAssertEqual(few.level(2500), 3)
        XCTAssertEqual(few.level(4000), 4)
        // One huge day does not wash the others out.
        let many = SpendingHeatScale(amounts: [100, 200, 300, 400, 500, 600, 700, 800, 100_000])
        XCTAssertEqual(many.level(100), 1)
        XCTAssertEqual(many.level(400), 2)
        XCTAssertEqual(many.level(600), 3)
        XCTAssertEqual(many.level(800), 4)
        XCTAssertEqual(many.level(100_000), 4)
    }

    func testProjectionWorkerPreparesTheSameYear() async throws {
        let ledger = Ledger(expenses: [Expense(merchant: "Tea", cents: 800, date: day(2026, 4, 2))])
        let now = day(2026, 10, 24)
        let prepared = try await LedgerProjectionWorker().year(ledger: ledger, year: 2026, now: now)
        XCTAssertEqual(prepared, YearSnapshot(ledger: ledger, year: 2026, now: now))
    }
}

final class SpendingAlertTests: XCTestCase {
    private let calendar = InsightCalendar.make()
    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }
    private var now: Date { day(2026, 10, 24) }

    /// July to September: RM 300 of food by the 24th and a RM 500 dinner on the 28th, which
    /// a like-for-like comparison on the 24th must leave out; RM 20 of transport and a RM 50
    /// shopping purchase each month.
    private func history() -> [Expense] {
        var entries: [Expense] = []
        for month in [7, 8, 9] {
            entries.append(Expense(merchant: "Kopitiam", cents: 10000, date: day(2026, month, 3), category: "餐饮"))
            entries.append(Expense(merchant: "Kopitiam", cents: 10000, date: day(2026, month, 12), category: "餐饮"))
            entries.append(Expense(merchant: "Kopitiam", cents: 10000, date: day(2026, month, 20), category: "餐饮"))
            entries.append(Expense(merchant: "Steakhouse", cents: 50000, date: day(2026, month, 28), category: "餐饮"))
            entries.append(Expense(merchant: "Grab", cents: 2000, date: day(2026, month, 5), category: "交通"))
            entries.append(Expense(merchant: "Shopee", cents: 5000, date: day(2026, month, 8), category: "购物"))
        }
        return entries
    }

    func testCategoryAheadOfItsUsualPaceBySameDay() async throws {
        let ledger = Ledger(expenses: history() + [
            Expense(merchant: "Kopitiam", cents: 20000, date: day(2026, 10, 2), category: "餐饮"),
            Expense(merchant: "Kopitiam", cents: 20000, date: day(2026, 10, 9), category: "餐饮"),
            Expense(merchant: "Kopitiam", cents: 20000, date: day(2026, 10, 18), category: "餐饮"),
        ])
        let alerts = SpendingAlerts.make(ledger: ledger, month: now, now: now)
        let food = try XCTUnwrap(alerts.first { $0.kind == .category })
        XCTAssertEqual(food.category, "餐饮")
        XCTAssertEqual(food.cents, 60000)
        XCTAssertEqual(food.usual, 30000)
        XCTAssertEqual(food.rise, 100)
        XCTAssertEqual(food.throughDay, 24)
        // All spending is ahead as well, and comes first: RM 600 against RM 370 by the 24th.
        XCTAssertEqual(alerts.first?.kind, .overall)
        XCTAssertEqual(alerts.first?.usual, 37000)
        // RM 200 meals are twice a typical one: not a large purchase.
        XCTAssertFalse(alerts.contains { $0.kind == .purchase })
        XCTAssertFalse(alerts.contains { $0.category == "交通" || $0.category == "购物" })
        // The Overview's projection gives the same answer.
        let prepared = try await LedgerProjectionWorker().spendingAlerts(ledger: ledger, month: now, now: now)
        XCTAssertEqual(prepared, alerts)
    }

    func testQuietWithoutTwoEarlierMonthsOfRecords() {
        let ledger = Ledger(expenses: [
            Expense(merchant: "Kopitiam", cents: 10000, date: day(2026, 9, 3), category: "餐饮"),
            Expense(merchant: "Banquet", cents: 90000, date: day(2026, 10, 10), category: "餐饮"),
        ])
        XCTAssertTrue(SpendingAlerts.make(ledger: ledger, month: now, now: now).isEmpty)
        // A month still to come has nothing to say either.
        XCTAssertTrue(SpendingAlerts.make(ledger: Ledger(expenses: history()), month: day(2026, 12, 1), now: now).isEmpty)
    }

    func testEarlyInTheMonthOnlyALargePurchaseStandsOut() throws {
        let early = day(2026, 10, 3)
        let ledger = Ledger(expenses: history() + [
            Expense(id: "big", merchant: "Ikea", cents: 45000, date: day(2026, 10, 2), category: "购物"),
        ])
        let alerts = SpendingAlerts.make(ledger: ledger, month: early, now: early)
        XCTAssertEqual(alerts.count, 1)
        let purchase = try XCTUnwrap(alerts.first)
        XCTAssertEqual(purchase.kind, .purchase)
        XCTAssertEqual(purchase.expenseID, "big")
        XCTAssertEqual(purchase.merchant, "Ikea")
        XCTAssertEqual(purchase.usual, 5000)
        XCTAssertEqual(purchase.multipleText, "9")
    }

    func testPurchaseExplainsItsCategoryAndScheduledOrTravelSpendingIsLeftOut() {
        let ledger = Ledger(expenses: history() + [
            Expense(id: "sofa", merchant: "Ikea", cents: 60000, date: day(2026, 10, 15), category: "购物"),
            // A renewal is expected, never a surprising purchase.
            Expense(merchant: "Annual plan", cents: 60000, date: day(2026, 10, 16), category: "娱乐", recurringKey: "plan:3"),
            // Travel books have budgets of their own.
            Expense(merchant: "Hotel", cents: 90000, date: day(2026, 10, 17), category: "其他", tripID: "trip"),
        ])
        let alerts = SpendingAlerts.make(ledger: ledger, month: now, now: now)
        XCTAssertTrue(alerts.contains { $0.kind == .purchase && $0.expenseID == "sofa" })
        XCTAssertFalse(alerts.contains { $0.kind == .category && $0.category == "购物" })
        XCTAssertFalse(alerts.contains { $0.category == "其他" })
        XCTAssertFalse(alerts.contains { $0.kind == .purchase && $0.category == "娱乐" })
        XCTAssertTrue(alerts.contains { $0.kind == .newCategory && $0.category == "娱乐" })
        // Hotel spending is not in the overall pace: RM 1,200 of the RM 2,100 recorded.
        XCTAssertEqual(alerts.first { $0.kind == .overall }?.cents, 120000)
    }

    func testHiddenAlertsAreKeptPerMonth() {
        let month = monthKey(Date())
        var stored = SpendingAlerts.dismissing("category:餐饮", month: month, in: "")
        stored = SpendingAlerts.dismissing("overall", month: month, in: stored)
        stored = SpendingAlerts.dismissing("overall", month: month, in: stored)
        XCTAssertEqual(SpendingAlerts.dismissed(stored, month: month), ["category:餐饮", "overall"])
        XCTAssertTrue(SpendingAlerts.dismissed(stored, month: "1999-01").isEmpty)
        XCTAssertFalse(SpendingAlerts.dismissing("overall", month: month, in: "1999-01|overall").contains("1999-01"))
    }

    func testNotificationsAtMostDailyEachOnceAndNeverForPurchases() {
        let month = "2026-10"
        let purchase = SpendingAlert(kind: .purchase, category: "购物", cents: 45000, usual: 5000, expenseID: "big")
        let food = SpendingAlert(kind: .category, category: "餐饮", cents: 60000, usual: 30000, throughDay: 24)
        let overall = SpendingAlert(kind: .overall, cents: 90000, usual: 50000, throughDay: 24)
        XCTAssertEqual(UnusualSpendingNotifier.next([purchase, food], month: month, sent: [], lastSent: nil, now: now), food)
        XCTAssertEqual(UnusualSpendingNotifier.next([overall, food], month: month, sent: ["2026-10|overall"], lastSent: nil, now: now), food)
        XCTAssertNil(UnusualSpendingNotifier.next([food], month: month, sent: [], lastSent: now.addingTimeInterval(-3600), now: now))
        XCTAssertEqual(UnusualSpendingNotifier.next([food], month: month, sent: [], lastSent: now.addingTimeInterval(-21 * 3600), now: now), food)
        XCTAssertNil(UnusualSpendingNotifier.next([purchase], month: month, sent: [], lastSent: nil, now: now))
    }

    func testAlertTextInEnglish() {
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: "appLanguage")
        defer {
            if let previous { defaults.set(previous, forKey: "appLanguage") }
            else { defaults.removeObject(forKey: "appLanguage") }
        }
        defaults.set("en", forKey: "appLanguage")
        let food = SpendingAlert(kind: .category, category: "餐饮", cents: 60000, usual: 30000, throughDay: 24)
        XCTAssertEqual(food.title(), "Food is up 100%")
        XCTAssertEqual(food.detail(), "RM 600.00 by day 24; usually about RM 300.00")
        XCTAssertEqual(food.detail(hidden: true), "Compared with days 1–24 of recent months")
        XCTAssertEqual(food.badge, "+100%")
        let purchase = SpendingAlert(kind: .purchase, category: "购物", cents: 45000, usual: 10000, expenseID: "x", merchant: "Ikea")
        XCTAssertEqual(purchase.title(), "RM 450.00 at Ikea")
        XCTAssertEqual(purchase.title(hidden: true), "A large purchase at Ikea")
        XCTAssertEqual(purchase.detail(), "About 4.5× a typical Shopping purchase")
        XCTAssertEqual(SpendingAlert(kind: .newCategory, category: "娱乐", cents: 12000, usual: 0).badge, "New")
    }

}

final class AutoBackupTests: XCTestCase {
    func testCopiesAreNamedByTimeAndOnlyAutomaticCopiesExpire() {
        let zone = TimeZone(identifier: "Asia/Kuala_Lumpur")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 24, hour: 18, minute: 30, second: 5))!
        XCTAssertEqual(AutoBackupFiles.name(for: date, timeZone: zone), "YueJi-auto-2026-10-24-183005.json")
        let entries = ["YueJi-auto-2026-10-20-090000.json", ".YueJi-auto-2026-10-21-090000.json.icloud",
                       "YueJi-auto-2026-10-22-090000.json", "YueJi-2026-10.json", "notes.txt", "YueJi-auto-broken.json"]
        // iCloud Drive lists a copy that is only in the cloud as a placeholder.
        XCTAssertEqual(AutoBackupFiles.backupName(of: ".YueJi-auto-2026-10-21-090000.json.icloud"), "YueJi-auto-2026-10-21-090000.json")
        XCTAssertNil(AutoBackupFiles.backupName(of: "YueJi-auto-broken.json"))
        XCTAssertNil(AutoBackupFiles.backupName(of: "YueJi-2026-10.json"))
        XCTAssertEqual(AutoBackupFiles.expired(entries, keep: 2), ["YueJi-auto-2026-10-20-090000.json"])
        XCTAssertEqual(Set(AutoBackupFiles.expired(entries, keep: 1)),
                       ["YueJi-auto-2026-10-20-090000.json", ".YueJi-auto-2026-10-21-090000.json.icloud"])
        // The newest copy is never removed.
        XCTAssertEqual(AutoBackupFiles.expired(entries, keep: 0).count, 2)
    }

    func testDueOncePerPeriodAndAfterTheClockMovesBack() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertTrue(AutoBackupPolicy.isDue(now: now, last: now, frequency: .everyChange))
        XCTAssertTrue(AutoBackupPolicy.isDue(now: now, last: nil, frequency: .daily))
        XCTAssertFalse(AutoBackupPolicy.isDue(now: now, last: now.addingTimeInterval(-3600), frequency: .daily))
        XCTAssertTrue(AutoBackupPolicy.isDue(now: now, last: now.addingTimeInterval(-21 * 3600), frequency: .daily))
        XCTAssertFalse(AutoBackupPolicy.isDue(now: now, last: now.addingTimeInterval(-3 * 86400), frequency: .weekly))
        XCTAssertTrue(AutoBackupPolicy.isDue(now: now, last: now.addingTimeInterval(-7 * 86400), frequency: .weekly))
        XCTAssertTrue(AutoBackupPolicy.isDue(now: now, last: now.addingTimeInterval(3600), frequency: .weekly))
    }

    func testCopyRestoresTheLedgerAndLeavesOtherFilesAlone() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let notes = folder.appendingPathComponent("notes.txt")
        try Data("keep me".utf8).write(to: notes)
        let ledger = Ledger(expenses: [Expense(merchant: "Lunch", cents: 1250, date: Date(timeIntervalSince1970: 1_790_000_000))])
        let data = try LocalStore.exportData(ledger)
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        var names: [String] = []
        for offset in 0..<4 {
            names.append(try AutoBackupWriter.write(data, into: folder, now: start.addingTimeInterval(Double(offset) * 86400), keep: 2))
        }
        let remaining = try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
        XCTAssertEqual(remaining, (Array(names.suffix(2)) + ["notes.txt"]).sorted())
        XCTAssertEqual(try Data(contentsOf: notes), Data("keep me".utf8))
        // The same file "Restore from a backup file" reads.
        let restored = try RestorePreview(data: Data(contentsOf: folder.appendingPathComponent(names[3])))
        XCTAssertEqual(restored.ledger.expenses, ledger.expenses)
    }

    func testWriterSkipsAnUnchangedLedgerUntilItChanges() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let folder = root.appendingPathComponent("Backups")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LocalStore(folder: root.appendingPathComponent("Data"))
        try store.change { $0.expenses = [Expense(merchant: "Lunch", cents: 1250, date: Date(timeIntervalSince1970: 1_790_000_000))] }
        let writer = AutoBackupWriter(store: store)
        let bookmark = try folder.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func job(force: Bool = false, hash: String?, days: Double) -> AutoBackupJob {
            AutoBackupJob(bookmark: bookmark, force: force, lastHash: hash, keep: 14, now: now.addingTimeInterval(days * 86400))
        }

        let first = await writer.perform(job(hash: nil, days: 0))
        guard case .saved(let name) = first.outcome else { return XCTFail("Expected a copy, got \(first.outcome)") }
        let again = await writer.perform(job(hash: first.hash, days: 1))
        XCTAssertEqual(again.outcome, .unchanged)
        // "Back up now" always writes one.
        let forced = await writer.perform(job(force: true, hash: first.hash, days: 2))
        guard case .saved = forced.outcome else { return XCTFail("Expected a forced copy, got \(forced.outcome)") }

        try store.change { $0.expenses.append(Expense(merchant: "Dinner", cents: 3000, date: Date(timeIntervalSince1970: 1_790_100_000))) }
        let changed = await writer.perform(job(hash: first.hash, days: 3))
        guard case .saved(let latest) = changed.outcome else { return XCTFail("Expected a copy of the change, got \(changed.outcome)") }
        XCTAssertNotEqual(changed.hash, first.hash)
        XCTAssertEqual(try LocalStore.decode(Data(contentsOf: folder.appendingPathComponent(latest))).expenses.count, 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent(name).path))

        // A folder that has gone is reported, never silently skipped.
        try FileManager.default.removeItem(at: folder)
        let missing = await writer.perform(job(force: true, hash: changed.hash, days: 4))
        guard case .failed = missing.outcome else { return XCTFail("Expected a failure, got \(missing.outcome)") }
    }

    func testRapidBackupsNeverOverwriteAndMalformedDataCannotRotateGoodCopies() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let now = Date(timeIntervalSince1970: 1_800_000_000.125)
        let first = Ledger(expenses: [Expense(merchant: "Lunch", cents: 1250, date: now)])
        var second = first
        second.expenses.append(Expense(merchant: "Dinner", cents: 3000, date: now))
        let a = try AutoBackupWriter.write(LocalStore.exportData(first), into: folder, now: now, keep: 14)
        let b = try AutoBackupWriter.write(LocalStore.exportData(second), into: folder, now: now, keep: 14)
        XCTAssertNotEqual(a, b)
        XCTAssertEqual(AutoBackupFiles.backupName(of: a), a)
        XCTAssertEqual(AutoBackupFiles.backupName(of: "." + b + ".icloud"), b)
        XCTAssertNil(AutoBackupFiles.backupName(of: "YueJi-auto-xxxx-xx-xx-xxxxxx.json"))
        XCTAssertEqual(try LocalStore.decode(Data(contentsOf: folder.appendingPathComponent(a))).expenses.count, 1)
        XCTAssertEqual(try LocalStore.decode(Data(contentsOf: folder.appendingPathComponent(b))).expenses.count, 2)
        XCTAssertThrowsError(try AutoBackupWriter.write(Data("broken".utf8), into: folder, now: now, keep: 1))
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: folder.path)), [a, b])
    }

    func testExternalBackupRestoresAfterAppStorageIsDeleted() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let external = root.appendingPathComponent("iCloudFolder")
        let sandbox = root.appendingPathComponent("AppData")
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let original = LocalStore(folder: sandbox)
        try original.change {
            $0.expenses = [Expense(merchant: "Lunch", cents: 1250, date: Date(timeIntervalSince1970: 1_790_000_000))]
            $0.budgets = ["2026-10": 100000]
            $0.merchantCategories = ["lunch": "餐饮"]
            $0.seenEvents = ["delivery:previous"]
        }
        let expected = try original.read()
        let name = try AutoBackupWriter.write(LocalStore.exportData(expected), into: external, now: Date(), keep: 14)
        // Simulate uninstall: no app files or remembered folder bookmarks survive.
        try FileManager.default.removeItem(at: sandbox)
        let reinstalled = LocalStore(folder: sandbox)
        XCTAssertTrue(try reinstalled.read().expenses.isEmpty)
        let writer = AutoBackupWriter(store: reinstalled)
        do {
            try await writer.validateDestination(external)
            XCTFail("A fresh install must restore before reusing an existing backup folder")
        } catch {
            XCTAssertTrue(FileManager.default.fileExists(atPath: external.appendingPathComponent(name).path))
        }
        let worker = LedgerRefreshWorker(store: reinstalled)
        let preview = try await worker.preview(url: external.appendingPathComponent(name))
        // Selecting and previewing a backup must not change the new installation.
        XCTAssertTrue(try reinstalled.read().expenses.isEmpty)
        try await worker.restore(data: preview.data)
        let restored = try reinstalled.read()
        XCTAssertEqual(restored.expenses, expected.expenses)
        XCTAssertEqual(restored.budgets, expected.budgets)
        XCTAssertEqual(restored.merchantCategories, expected.merchantCategories)
        XCTAssertEqual(restored.seenEvents, expected.seenEvents)
        XCTAssertTrue(FileManager.default.fileExists(atPath: external.appendingPathComponent(name).path))
        try await writer.validateDestination(external)
    }
}
