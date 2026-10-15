import XCTest
import UIKit
import AVFoundation
import SwiftUI
@testable import YueJi

final class ExpenseChargeTests: XCTestCase {
    func testSignedReceiptRoundingAndLegacyCharges() throws {
        for (text, expected) in [("-0.02", 11598), ("+0.02", 11602), ("0.00", 11600), ("", 11600)] {
            let charges = try ExpenseCharges.draft(currency: "MYR", subtotal: "100", sst: "6", service: "10", rounding: text)
            XCTAssertEqual(try charges.breakdown().total, expected)
            let original = try purchase()
            let updated = try original.replacingItemCharges(charges, paymentMinor: expected,
                items: original.items ?? [], allowedCategories: categories)
            XCTAssertEqual(updated.items, original.items)
            XCTAssertEqual(updated.personalSpending + updated.shares.reduce(0) { $0 + $1.cents }, expected)
            XCTAssertEqual(try LocalStore.decode(LocalStore.encode(Ledger(expenses: [updated]))).expenses[0], updated)
        }
        let legacy = Data(#"{"currency":"MYR","subtotal":10000,"sstBasisPoints":600,"serviceBasisPoints":1000}"#.utf8)
        let decoded = try JSONDecoder().decode(ExpenseCharges.self, from: legacy)
        XCTAssertNil(decoded.roundingMinor)
        XCTAssertEqual(try decoded.breakdown().total, 11600)
        for invalid in ["-116", "--0.02", "+", "0.001"] {
            XCTAssertThrowsError(try ExpenseCharges.draft(currency: "MYR", subtotal: "100", sst: "6", service: "10", rounding: invalid))
        }
        var overflow = decoded
        overflow.roundingMinor = Int.max
        XCTAssertThrowsError(try overflow.breakdown())
        XCTAssertThrowsError(try ExpenseCharges.draft(currency: "JPY", subtotal: "100", sst: "6", service: "10", rounding: "-0.02"))
    }
    private let date = Date(timeIntervalSince1970: 1_700_000_000)
    private func purchase() throws -> Expense {
        let charges = try ExpenseCharges.draft(currency: "MYR", subtotal: "100", sst: "6", service: "10")
        return try Expense(id: "charged", merchant: "Cafe", cents: 11600, date: date, category: "餐饮",
            items: [ExpenseItem(id: "mine", name: "Lunch", cents: 4000, category: "餐饮", quantity: 2,
                                ownership: ItemOwnership(includesMe: true, friends: [])),
                    ExpenseItem(id: "amy", name: "Supplies", cents: 6000, category: "购物", quantity: 3,
                                ownership: ItemOwnership(includesMe: false, friends: ["Amy"]))],
            charges: charges).applyingItemOwnership()
    }
    func testItemEditorAddsChargesExplicitlyAndKeepsIdentityBasePricesAndHistory() throws {
        let charged = try purchase()
        var original = charged
        original.charges = nil
        original.cents = 10000
        original = try original.applyingItemOwnership()
        original.receiptSummary = "Old receipt"
        let updated = try original.replacingItemCharges(charged.charges, paymentMinor: 11600,
            items: original.items ?? [], allowedCategories: categories)
        _ = try Ledger(expenses: [updated]).validated()
        XCTAssertEqual(updated.id, original.id)
        XCTAssertEqual(updated.date, original.date)
        XCTAssertEqual(updated.items, original.items)
        XCTAssertEqual(updated.shares.map(\.id), original.shares.map(\.id))
        XCTAssertEqual(updated.shares[0].cents, 6960)
        XCTAssertEqual(updated.personalSpending, 4640)
        XCTAssertNil(updated.receiptSummary)
        XCTAssertEqual(try updated.replacingItemCharges(updated.charges, paymentMinor: 11600,
            items: updated.items ?? [], allowedCategories: categories), updated)
        XCTAssertThrowsError(try updated.replacingItemCharges(nil, paymentMinor: 11600,
            items: updated.items ?? [], allowedCategories: categories))
        original.shares[0].repayments = [Repayment(cents: 100, date: date)]
        XCTAssertThrowsError(try original.replacingItemCharges(charged.charges, paymentMinor: 11600,
            items: original.items ?? [], allowedCategories: categories))
        XCTAssertEqual(original.cents, 10000)
        XCTAssertEqual(original.shares[0].repaid, 100)
    }
    func testItemEditorAddsFeesToAutomaticGrossWithoutAddingThemAgain() throws {
        let original = Expense(merchant: "Cafe", cents: 11600, date: date, source: "TNG")
        let charged = try purchase()
        let updated = try original.replacingItemCharges(charged.charges, paymentMinor: original.cents,
            items: charged.items ?? [], allowedCategories: categories)
        XCTAssertEqual(updated.cents, original.cents)
        XCTAssertEqual(updated.source, original.source)
        XCTAssertEqual(updated.id, original.id)
        XCTAssertEqual(updated.personalSpending, 4640)
        XCTAssertEqual(try LocalStore.decode(LocalStore.encode(Ledger(expenses: [updated]))).expenses[0], updated)
    }
    func testItemEditorAppliesForeignGrossWithOriginalQuoteAndBaseItems() throws {
        let quote = RateQuote(value: Decimal(string: "3.2")!, date: date, source: "Manual")
        let original = Expense(merchant: "Cafe", cents: 3200, date: date,
            foreign: ForeignAmount(currency: "SGD", minor: 1000, quote: quote),
            items: [ExpenseItem(name: "Lunch", cents: 1600, category: "餐饮"),
                    ExpenseItem(name: "Paper", cents: 1600, category: "购物")])
        let charges = try ExpenseCharges.draft(currency: "SGD", subtotal: "10", sst: "6", service: "10")
        let updated = try original.replacingItemCharges(charges, paymentMinor: 1160,
            items: original.items ?? [], allowedCategories: categories)
        _ = try Ledger(expenses: [updated]).validated()
        XCTAssertEqual(updated.cents, 3712)
        XCTAssertEqual(updated.itemSubtotalCents, 3200)
        XCTAssertEqual(updated.foreign?.minor, 1160)
        XCTAssertEqual(updated.foreign?.quote, quote)
        XCTAssertEqual(updated.items, original.items)
        XCTAssertEqual(updated.personalAmount(category: "餐饮"), 1856)
        XCTAssertEqual(updated.personalAmount(category: "购物"), 1856)
    }
    func testBothPercentagesUseSubtotalAndRoundSeparately() throws {
        let charges = try ExpenseCharges.draft(currency: "MYR", subtotal: "100", sst: "6%", service: "10")
        let result = try charges.breakdown()
        XCTAssertEqual(result.sst, 600)
        XCTAssertEqual(result.service, 1000)
        XCTAssertEqual(result.total, 11600)
        let small = try ExpenseCharges.draft(currency: "MYR", subtotal: "0.05", sst: "10", service: "10").breakdown()
        XCTAssertEqual(small.sst, 1)
        XCTAssertEqual(small.service, 1)
        XCTAssertEqual(small.total, 7)
        let yen = try ExpenseCharges.draft(currency: "JPY", subtotal: "100", sst: "6", service: "10").breakdown()
        XCTAssertEqual(yen.total, 116)
    }
    func testOptionalPercentagesAndBoundsRejectMalformedMetadata() throws {
        XCTAssertEqual(try ExpenseCharges.percent(""), 0)
        XCTAssertEqual(try ExpenseCharges.percent(" 6.25% "), 625)
        XCTAssertEqual(ExpenseCharges.percentText(625), "6.25")
        XCTAssertEqual(try ExpenseCharges.percent("100"), 10000)
        for input in ["-1", "101", "1.234", "%", "6%%", "NaN", "inf", "1e2", "6,25"] {
            XCTAssertThrowsError(try ExpenseCharges.percent(input), input)
        }
        for charges in [ExpenseCharges(subtotal: 0, sstBasisPoints: 0, serviceBasisPoints: 0),
                        ExpenseCharges(subtotal: Int.max, sstBasisPoints: 0, serviceBasisPoints: 0),
                        ExpenseCharges(subtotal: 100, sstBasisPoints: -1, serviceBasisPoints: 0),
                        ExpenseCharges(subtotal: 100, sstBasisPoints: 0, serviceBasisPoints: 10001),
                        ExpenseCharges(subtotal: 10_000_000_000, sstBasisPoints: 10000, serviceBasisPoints: 10000),
                        ExpenseCharges(currency: "INVALID", subtotal: 100, sstBasisPoints: 0, serviceBasisPoints: 0)] {
            XCTAssertThrowsError(try charges.breakdown())
        }
    }
    func testItemPricesAndQuantitiesStayIntactWhileSharesAndReportsIncludeCharges() throws {
        let entry = try purchase()
        let ledger = try Ledger(expenses: [entry]).validated()
        XCTAssertEqual(entry.itemSubtotalCents, 10000)
        XCTAssertEqual(entry.items?.map(\.cents), [4000, 6000])
        XCTAssertEqual(entry.items?.map(\.unitCents), [2000, 2000])
        XCTAssertEqual(entry.items?.map(\.count), [2, 3])
        XCTAssertEqual(entry.chargedItems.map(\.cents), [4640, 6960])
        XCTAssertEqual(entry.personal, 4640)
        XCTAssertEqual(entry.shares.first?.cents, 6960)
        XCTAssertEqual(entry.personalItemAmounts, ["mine": 4640, "amy": 0])
        XCTAssertEqual(entry.personalAmount(category: "餐饮"), 4640)
        XCTAssertEqual(entry.categoryDistribution(total: 6960, friend: "Amy")["购物"], 6960)
        XCTAssertEqual(ledger.spending(in: date), 4640)
        XCTAssertEqual(OverviewSnapshot(ledger: ledger, month: date).paid, 11600)
        XCTAssertEqual(ExpenseCollectionSnapshot(entries: ledger.expenses).personal, 4640)
        XCTAssertEqual(try entry.replacingItems(entry.items ?? [], allowedCategories: categories), entry)
    }
    func testRefundAndReimbursementUseChargedNetShareWithoutChangingBaseItems() throws {
        var ledger = try Ledger(expenses: [purchase()]).validated()
        let items = ledger.expenses[0].items
        try ledger.addRefund(expenseID: "charged", cents: 1160, date: date)
        XCTAssertEqual(ledger.expenses[0].personal, 4176)
        XCTAssertEqual(ledger.expenses[0].personalItemAmounts.values.reduce(0, +), 4176)
        try ledger.setReimbursement(expense: ledger.expenses[0], claim: ReimbursementClaim(recipient: "Company", cents: 2000))
        XCTAssertEqual(ledger.spending(in: date), 2176)
        XCTAssertEqual(ledger.expenses[0].personalAmount(category: "餐饮"), 2176)
        XCTAssertEqual(ledger.expenses[0].items, items)
        _ = try ledger.validated()
    }
    func testForeignChargesConvertGrossAndSubtotalOnlyOnce() throws {
        let charges = try ExpenseCharges.draft(currency: "SGD", subtotal: "10", sst: "6", service: "10")
        let fx = ForeignAmount(currency: "SGD", minor: 1160, quote: RateQuote(value: Decimal(string: "3.2")!, date: date, source: "Manual"))
        let entry = Expense(merchant: "Cafe", cents: 3712, date: date, shares: [Share(name: "Amy", cents: 1856)], foreign: fx,
            items: [ExpenseItem(id: "one", name: "Lunch", cents: 1600, category: "餐饮"),
                    ExpenseItem(id: "two", name: "Paper", cents: 1600, category: "购物")], charges: charges)
        _ = try Ledger(expenses: [entry]).validated()
        XCTAssertEqual(entry.itemSubtotalCents, 3200)
        XCTAssertEqual(entry.chargedItems.map(\.cents), [1856, 1856])
        XCTAssertEqual(entry.personal, 1856)
        XCTAssertEqual(entry.personalAmount(category: "餐饮"), 928)
        XCTAssertEqual(entry.personalAmount(category: "购物"), 928)
        XCTAssertEqual(try LocalStore.decode(LocalStore.encode(Ledger(expenses: [entry]))).expenses[0], entry)
    }
    func testPaymentMismatchAndGrossItemAmountsAreRejected() throws {
        var entry = try purchase()
        entry.cents = 10000
        XCTAssertThrowsError(try Ledger(expenses: [entry]).validated())
        entry = try purchase()
        entry.charges?.currency = "SGD"
        XCTAssertThrowsError(try entry.validateCharges())
        entry = try purchase()
        entry.items?[0].cents = 5600
        XCTAssertThrowsError(try entry.validateItems())
        var automatic = Expense(merchant: "Cafe", cents: 11600, date: date, source: "TNG")
        automatic.charges = try ExpenseCharges.draft(currency: "MYR", subtotal: "100", sst: "6", service: "10")
        let restored = try LocalStore.decode(LocalStore.encode(Ledger(expenses: [automatic]))).expenses[0]
        XCTAssertEqual(restored.cents, 11600)
        XCTAssertNil(restored.items)
        XCTAssertEqual(restored.personalSpending, 11600)
    }
    func testBackupExportDeleteUndoAndLegacyCompatibility() throws {
        var ledger = try Ledger(expenses: [purchase()]).validated()
        let entry = ledger.expenses[0]
        XCTAssertEqual(try LocalStore.decode(LocalStore.encode(ledger)).expenses[0], entry)
        let csv = String(decoding: ledger.csv(month: nil, splits: false), as: UTF8.self)
        let rows = csv.components(separatedBy: "\r\n").filter { !$0.isEmpty }
        let header = rows[0].components(separatedBy: ",").map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\"\u{FEFF}")) }
        let values = rows[1].components(separatedBy: ",").map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\"")) }
        XCTAssertEqual(header.count, values.count)
        XCTAssertEqual(Array(header.suffix(7)), ["charges_currency", "subtotal_before_charges", "sst_percent", "service_charge_percent", "sst_amount", "service_charge_amount", "rounding_adjustment"])
        XCTAssertEqual(Array(values.suffix(7)), ["MYR", "100.00", "6", "10", "6.00", "10.00", "0.00"])
        XCTAssertEqual(values[5], "116.00")
        let deleted = try ledger.deleteLedgerExpense(entry)
        try ledger.restoreDeletedRecords([deleted])
        XCTAssertEqual(ledger.expenses[0], entry)
        let legacy = Expense(merchant: "Store", cents: 500, date: date,
                             items: [ExpenseItem(name: "Lunch", cents: 500, category: "餐饮")])
        let data = try LocalStore.encode(Ledger(expenses: [legacy]))
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("\"charges\""))
        XCTAssertEqual(try LocalStore.decode(data).expenses[0], legacy)
        XCTAssertEqual(legacy.chargedItems, legacy.items ?? [])
        XCTAssertEqual(legacy.personalSpending, 500)
    }
    func testRoundingConservesEveryCentAndFinancialHistoryLocksChargeChanges() throws {
        XCTAssertEqual(try allocateChargeTotal(5, weights: [1, 1, 1]), [2, 2, 1])
        XCTAssertEqual(try allocateChargeTotal(10_000_000_000, weights: [9_999_999_999, 1]).reduce(0, +), 10_000_000_000)
        XCTAssertThrowsError(try allocateChargeTotal(5, weights: []))
        XCTAssertThrowsError(try allocateChargeTotal(5, weights: [Int.max]))
        var original = try purchase()
        var edited = original
        edited.charges?.sstBasisPoints = 1000
        edited.charges?.serviceBasisPoints = 600
        XCTAssertFalse(edited.sameSettlementTerms(as: original))
        original.shares[0].repayments = [Repayment(cents: 100, date: date)]
        XCTAssertThrowsError(try edited.validateChargeEdit(replacing: original))
        XCTAssertNoThrow(try original.validateChargeEdit(replacing: original))
        var ledger = Ledger(expenses: [Expense(id: "auto", merchant: "Cafe", cents: 11600, date: date, source: "TNG", charges: original.charges)])
        let notice = TNGNotice(id: "notice", body: "You have paid RM116.00 for Cafe.", title: "Payment", date: date,
                              usesReceivedDate: false, kind: "payment", status: "recorded", cents: 11600, party: "Cafe", expenseID: "auto")
        ledger.tngNotices = [notice]
        let before = ledger.expenses
        XCTAssertThrowsError(try ledger.excludeTNG(id: "notice"))
        XCTAssertEqual(ledger.expenses, before)
    }
}

final class ReimbursementTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_700_000_000)
    private func purchase() -> Expense {
        Expense(id: "purchase", merchant: "Office store", cents: 4000, date: date, category: "购物",
                shares: [Share(id: "amy", name: "Amy", cents: 1000)],
                items: [ExpenseItem(id: "food", name: "Lunch", cents: 2000, category: "餐饮"),
                        ExpenseItem(id: "supplies", name: "Paper", cents: 2000, category: "购物")])
    }
    private func claimed() throws -> Ledger {
        var ledger = Ledger(expenses: [purchase()])
        try ledger.setReimbursement(expense: ledger.expenses[0], claim: ReimbursementClaim(recipient: "Company", cents: 2000))
        return try ledger.validated()
    }

    func testClaimExcludesPersonalSpendingAndBudgetsWithoutChangingPaymentOrDebt() throws {
        var ledger = try claimed()
        ledger.budgets[monthKey(date)] = 1500
        let entry = ledger.expenses[0]
        XCTAssertEqual(entry.cents, 4000)
        XCTAssertEqual(entry.paidFromMyAccount, 4000)
        XCTAssertEqual(entry.personal, 3000)
        XCTAssertEqual(entry.personalSpending, 1000)
        XCTAssertEqual(entry.shares, purchase().shares)
        XCTAssertEqual(entry.personalItemAmounts.values.reduce(0, +), 3000)
        XCTAssertEqual(ledger.friendBalances.first?.owed, 1000)
        XCTAssertEqual(ledger.spending(in: date), 1000)
        XCTAssertEqual(entry.personalAmount(category: "餐饮"), 500)
        XCTAssertEqual(entry.personalAmount(category: "购物"), 500)
        XCTAssertNil(BudgetAlertCandidate.make(ledger: ledger, now: date))
        let overview = OverviewSnapshot(ledger: ledger, month: date)
        XCTAssertEqual(overview.personal, 1000)
        XCTAssertEqual(overview.paid, 4000)
        XCTAssertEqual(overview.categoryTotals.values.reduce(0, +), 1000)
        XCTAssertEqual(overview.reimbursementClaimed, 2000)
        XCTAssertEqual(overview.reimbursementOutstanding, 2000)
        XCTAssertEqual(ExpenseCollectionSnapshot(entries: ledger.expenses).personal, 1000)
        let query = LedgerTimelineQuery(revision: 0, month: date, search: "", filter: LedgerFilter(), provider: "all")
        let timeline = try LedgerTimelineSnapshot(ledger: ledger, month: date, query: query)
        XCTAssertEqual(timeline.personal, 1000)
        XCTAssertEqual(timeline.reimbursementOutstanding, 2000)
    }

    func testPartialFullAndUndoReceiptsDoNotAddIncomeOrDeductSpendingAgain() throws {
        var ledger = try claimed()
        let first = ReimbursementReceipt(id: "receipt-1", cents: 1500, date: date.addingTimeInterval(3600))
        try ledger.receiveReimbursement(expense: ledger.expenses[0], receipt: first)
        XCTAssertEqual(ledger.expenses[0].reimbursement?.received, 1500)
        XCTAssertEqual(ledger.expenses[0].reimbursement?.outstanding, 500)
        XCTAssertEqual(ledger.spending(in: date), 1000)
        let second = ReimbursementReceipt(id: "receipt-2", cents: 500, date: date.addingTimeInterval(7200))
        try ledger.receiveReimbursement(expense: ledger.expenses[0], receipt: second)
        XCTAssertEqual(ledger.expenses[0].reimbursement?.outstanding, 0)
        XCTAssertEqual(ledger.spending(in: date), 1000)
        XCTAssertTrue(ledger.tngNotices.isEmpty)
        try ledger.undoReimbursementReceipt(expense: ledger.expenses[0], receiptID: first.id)
        XCTAssertEqual(ledger.expenses[0].reimbursement?.received, 500)
        XCTAssertEqual(ledger.expenses[0].reimbursement?.outstanding, 1500)
        XCTAssertEqual(ledger.expenses[0].personalSpending, 1000)
        _ = try ledger.validated()
    }

    func testBoundsDuplicatesFutureDatesAndStaleWritesAreRejectedWithoutMutation() throws {
        var ledger = try claimed()
        let original = ledger.expenses[0]
        for cents in [-1, 0, 2001] {
            XCTAssertThrowsError(try ledger.receiveReimbursement(expense: original,
                receipt: ReimbursementReceipt(cents: cents, date: date)))
            XCTAssertEqual(ledger.expenses[0], original)
        }
        for timestamp in [date.addingTimeInterval(-1), Date().addingTimeInterval(3600)] {
            XCTAssertThrowsError(try ledger.receiveReimbursement(expense: original,
                receipt: ReimbursementReceipt(cents: 100, date: timestamp)))
            XCTAssertEqual(ledger.expenses[0], original)
        }
        let receipt = ReimbursementReceipt(id: "same", cents: 100, date: date)
        try ledger.receiveReimbursement(expense: original, receipt: receipt)
        let updated = ledger.expenses[0]
        XCTAssertThrowsError(try ledger.receiveReimbursement(expense: original, receipt: receipt))
        XCTAssertThrowsError(try ledger.receiveReimbursement(expense: updated, receipt: receipt))
        XCTAssertThrowsError(try ledger.setReimbursement(expense: updated, claim: nil))
        XCTAssertEqual(ledger.expenses[0], updated)
    }

    func testInvalidClaimsCannotUseFriendsShareOrFriendPaidMoney() throws {
        var ledger = Ledger(expenses: [purchase()])
        for claim in [ReimbursementClaim(recipient: "", cents: 100), ReimbursementClaim(recipient: "Company", cents: 3001),
                      ReimbursementClaim(recipient: "Company", cents: 0), ReimbursementClaim(recipient: "Company", cents: Int.max)] {
            XCTAssertThrowsError(try ledger.setReimbursement(expense: ledger.expenses[0], claim: claim))
            XCTAssertEqual(ledger.expenses[0], purchase())
        }
        ledger.expenses[0].paidByFriend = "Amy"
        XCTAssertThrowsError(try ledger.setReimbursement(expense: ledger.expenses[0], claim: ReimbursementClaim(recipient: "Company", cents: 100)))
    }

    func testRefundMustLeaveEnoughNetShareForClaimAndCanBeAdjustedSafely() throws {
        var ledger = try claimed()
        let original = ledger.expenses[0]
        XCTAssertThrowsError(try ledger.addRefund(expenseID: original.id, cents: 2000, date: date,
                                                 custom: ["owner": 2000, "amy": 0]))
        XCTAssertEqual(ledger.expenses[0], original)
        try ledger.setReimbursement(expense: original, claim: ReimbursementClaim(recipient: "Company", cents: 1000))
        try ledger.addRefund(expenseID: original.id, cents: 2000, date: date, custom: ["owner": 2000, "amy": 0])
        XCTAssertEqual(ledger.expenses[0].personalSpending, 0)
        XCTAssertEqual(ledger.expenses[0].shares[0].cents, 1000)
        _ = try ledger.validated()
    }

    func testBackupCSVAndDeleteUndoKeepReimbursementHistoryAndLegacyRecords() throws {
        var ledger = try claimed()
        try ledger.receiveReimbursement(expense: ledger.expenses[0], receipt: ReimbursementReceipt(id: "received", cents: 500, date: date))
        let restored = try LocalStore.decode(LocalStore.encode(ledger))
        XCTAssertEqual(restored.expenses, ledger.expenses)
        let csv = String(decoding: ledger.csv(month: nil, splits: false), as: UTF8.self)
        XCTAssertTrue(csv.contains("reimbursement_outstanding_MYR"))
        XCTAssertTrue(csv.contains("Company"))
        XCTAssertTrue(csv.contains("received:"))
        let entry = ledger.expenses[0]
        let deleted = try ledger.deleteLedgerExpense(entry)
        XCTAssertTrue(ledger.expenses.isEmpty)
        try ledger.restoreDeletedRecords([deleted])
        XCTAssertEqual(ledger.expenses[0], entry)
        let legacy = purchase()
        let legacyData = try LocalStore.encode(Ledger(expenses: [legacy]))
        XCTAssertFalse(String(decoding: legacyData, as: UTF8.self).contains("reimbursement"))
        XCTAssertNil(try LocalStore.decode(legacyData).expenses[0].reimbursement)
        XCTAssertEqual(legacy.personalSpending, legacy.personal)
    }
    func testExcludingBankNoticeCannotSilentlyDeleteAClaim() throws {
        let entry = Expense(id: "auto", merchant: "Store", cents: 1000, date: date, source: "TNG",
                            reimbursement: ReimbursementClaim(recipient: "Company", cents: 1000))
        let notice = TNGNotice(id: "notification", body: "You have paid RM10.00 for Store.", title: "Payment", date: date,
                              usesReceivedDate: false, kind: "payment", status: "recorded", cents: 1000, party: "Store", expenseID: entry.id)
        var ledger = Ledger(expenses: [entry])
        ledger.tngNotices = [notice]
        XCTAssertThrowsError(try ledger.excludeTNG(id: notice.id))
        XCTAssertEqual(ledger.expenses, [entry])
        XCTAssertEqual(ledger.tngNotices, [notice])
    }
}

final class RepaymentPurchasePreviewTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_700_000_000)
    func testPreviewUsesRealPurchaseDetailsDeduplicatesAndLimitsRows() {
        let one = Expense(id: "one", merchant: "Cafe", entryDescription: "Lunch", cents: 1000, date: date)
        let two = Expense(id: "two", merchant: "Store", cents: 1000, date: date,
                          items: [ExpenseItem(name: "Paper", cents: 1000, category: "购物")])
        let three = Expense(id: "three", merchant: "Taxi", cents: 500, date: date)
        let preview = RepaymentPurchasePreview.make([one, one, two, three])
        XCTAssertEqual(preview?.names, "Cafe · Lunch； Store · Paper")
        XCTAssertEqual(preview?.remaining, 1)
        XCTAssertNil(RepaymentPurchasePreview.make([]))
        XCTAssertEqual(RepaymentPurchasePreview.make([three])?.names, "Taxi")
    }
    func testBankRepaymentLinksOlderPurchasesAndDoesNotGuessUnknownIncoming() throws {
        let purchaseDate = date.addingTimeInterval(-40 * 86400)
        let entry = Expense(id: "purchase", merchant: "Cafe", entryDescription: "Lunch", cents: 1000, date: purchaseDate,
                            shares: [Share(id: "share", name: "Amy", cents: 500,
                                           repayments: [Repayment(id: "repayment", cents: 300, date: date)])])
        var ledger = Ledger(expenses: [entry])
        let repayment = TNGNotice(id: "received", body: "Payment", title: "Received", date: date, usesReceivedDate: false,
                                  kind: "incoming", status: "repayment", cents: 300, party: "Amy", expenseID: nil,
                                  resolvedFriend: "Amy", repaymentIDs: ["repayment", "repayment"])
        var unknown = repayment
        unknown.id = "unlinked"; unknown.repaymentIDs = ["missing"]
        var income = repayment
        income.id = "income"; income.status = "income"; income.repaymentIDs = nil
        ledger.tngNotices = [repayment, unknown, income]
        let query = LedgerTimelineQuery(revision: 0, month: date, search: "", filter: LedgerFilter(), provider: "all")
        let snapshot = try LedgerTimelineSnapshot(ledger: ledger, month: date, query: query)
        XCTAssertEqual(snapshot.repaymentPreviews["received"]?.names, "Cafe · Lunch")
        XCTAssertNil(snapshot.repaymentPreviews["unlinked"])
        XCTAssertNil(snapshot.repaymentPreviews["income"])
        XCTAssertEqual(snapshot.personal, 0)
        XCTAssertEqual(ledger.expenses[0], entry)
    }
    func testLinkedSettlementPreviewUsesOnlyAppliedAuditLines() throws {
        let entry = Expense(id: "purchase", merchant: "Cafe", cents: 1000, date: date,
                            shares: [Share(id: "share", name: "Amy", cents: 500)])
        let unused = Expense(id: "unused", merchant: "Unpaid store", cents: 1000, date: date)
        let settlement = FriendSettlement(id: "settlement", friend: "amy", name: "Amy", date: date,
            lines: [SettlementLine(expense: entry, shareID: "share", before: 500, applied: 300),
                    SettlementLine(expense: unused, shareID: nil, before: 0, applied: 0)], transfer: 300, paymentNoticeID: "notice")
        var ledger = Ledger(expenses: [entry, unused])
        ledger.settlements = [settlement]
        ledger.tngNotices = [TNGNotice(id: "notice", body: "Payment", title: "Received", date: date, usesReceivedDate: false,
            kind: "incoming", status: "settlement", cents: 300, party: "Amy", expenseID: nil, settlementID: "settlement")]
        let query = LedgerTimelineQuery(revision: 0, month: date, search: "", filter: LedgerFilter(), provider: "all")
        let snapshot = try LedgerTimelineSnapshot(ledger: ledger, month: date, query: query)
        XCTAssertEqual(snapshot.repaymentPreviews["notice"]?.names, "Cafe")
        XCTAssertEqual(snapshot.repaymentPreviews["notice"]?.remaining, 0)
        XCTAssertEqual(RepaymentPurchasePreview.make(settlement.lines.filter { $0.applied != 0 }.map(\.expense))?.names, "Cafe")
    }
}

final class EntryDescriptionTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_700_000_000)

    func testOptionalDetailsRoundTripWithoutInventingMerchantOrItems() throws {
        let bare = Expense(merchant: "", cents: 1190, date: date)
        var described = bare
        described.id = "description-only"
        described.entryDescription = "Monthly subscription"
        described.note = "Original note"
        let ledger = try Ledger(expenses: [bare, described]).validated()
        let restored = try LocalStore.decode(LocalStore.encode(ledger))
        XCTAssertEqual(restored.expenses, ledger.expenses)
        XCTAssertEqual(restored.expenses.map(\.personal), [1190, 1190])
        XCTAssertEqual(described.displayName, "Monthly subscription")
        XCTAssertFalse(bare.displayName.isEmpty)
        XCTAssertEqual(described.merchant, "")
        XCTAssertNil(described.items)
    }

    func testLegacyBackupKeepsMerchantAndNoteSeparate() throws {
        let original = Expense(merchant: "Cafe", cents: 500, date: date, note: "Old note")
        let data = try LocalStore.encode(Ledger(expenses: [original]))
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("entryDescription"))
        let restored = try LocalStore.decode(data).expenses[0]
        XCTAssertEqual(restored, original)
        XCTAssertNil(restored.entryDescription)
        XCTAssertEqual(restored.displayName, "Cafe")
    }

    func testDescriptionIsSearchableExportedAndLengthChecked() throws {
        var entry = Expense(merchant: "Cafe", cents: 500, date: date)
        entry.entryDescription = "Lunch with Amy"
        let ledger = Ledger(expenses: [entry])
        XCTAssertEqual(try ledger.filteredEntries(in: date, search: "with Amy", filter: LedgerFilter()).map(\.id), [entry.id])
        let csv = String(decoding: ledger.csv(month: nil, splits: false), as: UTF8.self)
        XCTAssertTrue(csv.contains("entry_description"))
        XCTAssertTrue(csv.contains("Lunch with Amy"))
        entry.entryDescription = String(repeating: "a", count: 2001)
        XCTAssertThrowsError(try Ledger(expenses: [entry]).validated())
    }
}

final class ItemOwnershipAndQuantityTests: XCTestCase {
    func testEditorSnapshotPreservesUnsavedInvalidAndOwnershipChanges() {
        let item = ExpenseItemDraft(name: "Lunch", amount: "12.00", category: "其他")
        let original = ExpenseEditorSnapshot(text: ["Cafe", "12.00"], flags: [false],
                                             date: Date(timeIntervalSince1970: 1_700_000_000),
                                             items: [item], people: [FriendDraft()])
        var edited = original
        XCTAssertEqual(edited, original)
        edited.items[0].amount = "12."
        XCTAssertNotEqual(edited, original, "Invalid or incomplete input must still count as unsaved")
        edited = original; edited.items[0].quantity = 2
        XCTAssertNotEqual(edited, original)
        edited = original; edited.items[0].ownership = ItemOwnership(includesMe: false, friends: ["Amy"])
        XCTAssertNotEqual(edited, original)
        edited = original; edited.people[0].name = "Amy"
        XCTAssertNotEqual(edited, original)
        edited = original; edited.date = original.date.addingTimeInterval(60)
        XCTAssertNotEqual(edited, original)
        edited = original
        XCTAssertEqual(edited, original, "Reverting edits should permit a direct dismissal")
    }
    private let categories = Ledger().categoryNames
    // LocalStore's existing ISO-8601 backup format stores whole seconds.
    // Keep full-record equality meaningful without comparing fractional Date() precision.
    private let backupDate = Date(timeIntervalSince1970: 1_700_000_000)
    private let mine = ItemOwnership(includesMe: true, friends: [])
    private let amy = ItemOwnership(includesMe: false, friends: ["Amy"])

    func testLegacyItemsKeepAmountsSharesAndBackupShape() throws {
        let json = Data(#"{"id":"old","name":"Tea","cents":480,"category":"餐饮"}"#.utf8)
        let item = try JSONDecoder().decode(ExpenseItem.self, from: json)
        XCTAssertEqual(item.count, 1); XCTAssertNil(item.quantity); XCTAssertNil(item.ownership)
        XCTAssertEqual(try ExpenseItemDraft(item).savedItem(), item)
        let original = Expense(merchant: "Old purchase", cents: 480, date: backupDate, shares: [Share(name: "Amy", cents: 240)], items: [item])
        let restored = try LocalStore.decode(LocalStore.encode(Ledger(expenses: [original]))).expenses[0]
        XCTAssertEqual(restored, original)
        XCTAssertEqual(restored.personalItemAmounts["old"], 240)
        let encoded = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(item)) as? [String: Any])
        XCTAssertNil(encoded["quantity"]); XCTAssertNil(encoded["ownership"])
    }

    func testQuantityMultipliesUnitPriceAndRoundTripsWithoutRounding() throws {
        let draft = ExpenseItemDraft(name: "Tea", amount: "4.80", category: "餐饮", quantity: 3, ownership: mine)
        let item = try draft.savedItem()
        XCTAssertEqual(item.cents, 1440); XCTAssertEqual(item.unitCents, 480)
        XCTAssertEqual(try ExpenseItemDraft(item).savedItem(), item)
        let expense = try Expense(merchant: "Cafe", cents: 1440, date: backupDate).replacingItems([item], allowedCategories: categories)
        XCTAssertEqual(try LocalStore.decode(LocalStore.encode(Ledger(expenses: [expense]))).expenses[0], expense)
        for count in [0, -1, 1000, Int.max] {
            var invalid = draft; invalid.quantity = count
            XCTAssertThrowsError(try invalid.savedItem())
        }
        var overflow = draft; overflow.amount = "100000000.00"
        XCTAssertThrowsError(try overflow.savedItem())
        var malformed = item; malformed.cents = 1441
        XCTAssertThrowsError(try Expense(merchant: "Bad", cents: 1441).replacingItems([malformed], allowedCategories: categories))
    }

    func testOwnershipDrivesPersonalFriendAndCategoryAmounts() throws {
        let items = [ExpenseItem(id: "mine", name: "Tea", cents: 480, category: "餐饮", ownership: mine),
                     ExpenseItem(id: "friend", name: "Supplies", cents: 1200, category: "购物", ownership: amy)]
        let entry = try Expense(merchant: "Store", cents: 1680).replacingItems(items, allowedCategories: categories)
        let ledger = try Ledger(expenses: [entry]).validated()
        XCTAssertEqual(entry.personal, 480)
        XCTAssertEqual(entry.shares.first?.cents, 1200)
        XCTAssertEqual(entry.personalItemAmounts, ["mine": 480, "friend": 0])
        XCTAssertEqual(entry.personalAmount(category: "餐饮"), 480)
        XCTAssertEqual(entry.personalAmount(category: "购物"), 0)
        XCTAssertEqual(ledger.friendSpending(friend: "Amy").categories["购物"], 1200)
        XCTAssertEqual(ledger.friendBalances.first?.owed, 1200)
    }

    func testSharedItemsPreserveEveryCentIncludingZeroShares() throws {
        for cents in 1...101 {
            let item = ExpenseItem(name: "Shared", cents: cents, category: "餐饮", ownership: ItemOwnership(includesMe: true, friends: ["Amy", "Ben"]))
            let entry = try Expense(merchant: "Cafe", cents: cents).replacingItems([item], allowedCategories: categories)
            XCTAssertEqual(entry.personal + entry.shares.reduce(0) { $0 + $1.cents }, cents)
            XCTAssertLessThanOrEqual(abs(entry.shares[0].cents - entry.personal), 1)
            _ = try Ledger(expenses: [entry]).validated()
        }
    }

    func testPartialDuplicateAndMissingOwnersCannotSave() throws {
        let base = Expense(merchant: "Cafe", cents: 200)
        let owned = ExpenseItem(name: "Tea", cents: 100, category: "餐饮", ownership: mine)
        let legacy = ExpenseItem(name: "Water", cents: 100, category: "餐饮")
        XCTAssertThrowsError(try base.replacingItems([owned, legacy], allowedCategories: categories))
        for owner in [ItemOwnership(includesMe: false, friends: []), ItemOwnership(includesMe: true, friends: ["Amy", " AMY "]), ItemOwnership(includesMe: false, friends: [" "])] {
            var invalid = owned; invalid.ownership = owner; invalid.cents = 200
            XCTAssertThrowsError(try base.replacingItems([invalid], allowedCategories: categories))
        }
    }

    func testRefundsUseOwnedCategoriesAndProtectHistory() throws {
        let items = [ExpenseItem(id: "me", name: "Lunch", cents: 1000, category: "餐饮", ownership: mine),
                     ExpenseItem(id: "amy", name: "Supplies", cents: 2000, category: "购物", ownership: amy)]
        let entry = try Expense(merchant: "Store", cents: 3000, date: Date().addingTimeInterval(-3600)).replacingItems(items, allowedCategories: categories)
        var ledger = Ledger(expenses: [entry])
        try ledger.addRefund(expenseID: entry.id, cents: 300, date: Date())
        let refunded = ledger.expenses[0]
        XCTAssertEqual(refunded.personalItemAmounts, ["me": 900, "amy": 0])
        XCTAssertEqual(ledger.friendSpending(friend: "Amy").categories["购物"], 1800)
        XCTAssertEqual(try refunded.replacingItems(items, allowedCategories: categories), refunded)
        var changed = items; changed[1].ownership = mine
        XCTAssertThrowsError(try refunded.replacingItems(changed, allowedCategories: categories))
        var repaid = entry
        repaid.shares[0].repayments = [Repayment(cents: 100)]
        XCTAssertThrowsError(try repaid.replacingItems(changed, allowedCategories: categories))
        _ = try ledger.validated()
    }

    func testFriendPaidItemsOnlyUseMeAndThePayer() throws {
        let base = Expense(merchant: "Cafe", cents: 1000, paidByFriend: "Amy")
        let item = ExpenseItem(name: "Lunch", cents: 1000, category: "餐饮", ownership: ItemOwnership(includesMe: true, friends: ["Amy"]))
        let entry = try base.replacingItems([item], allowedCategories: categories)
        XCTAssertEqual(entry.personal, 500); XCTAssertEqual(entry.paidFromMyAccount, 0)
        XCTAssertEqual(entry.shares.first?.name, "Amy")
        _ = try Ledger(expenses: [entry]).validated()
        var other = item; other.ownership = ItemOwnership(includesMe: true, friends: ["Ben"])
        XCTAssertThrowsError(try base.replacingItems([other], allowedCategories: categories))
    }

    func testEditingAutomaticEntryRetainsIdentityAndSplitIDs() throws {
        let original = Expense(id: "auto", merchant: "Store", cents: 1000, source: "TNG", shares: [Share(id: "amy-share", name: "Amy", cents: 500)], transactionReference: "REF123", note: "Keep", tags: ["Legacy"])
        let item = ExpenseItem(name: "Tea", cents: 1000, category: "餐饮", quantity: 2, ownership: amy)
        let entry = try original.replacingItems([item], allowedCategories: categories)
        XCTAssertEqual(entry.id, original.id); XCTAssertEqual(entry.source, original.source)
        XCTAssertEqual(entry.transactionReference, original.transactionReference); XCTAssertEqual(entry.tags, original.tags)
        XCTAssertEqual(entry.shares[0].id, "amy-share"); XCTAssertEqual(entry.shares[0].cents, 1000)
        var corrupt = entry; corrupt.shares[0].cents = 999
        XCTAssertThrowsError(try LocalStore.decode(LocalStore.encode(Ledger(expenses: [corrupt]))))
    }

    func testPendingAutomaticPaymentUsesTheSameOwnershipCalculation() throws {
        for review in [false, true] {
            let date = Date().addingTimeInterval(-60)
            let notice = TNGNotice(id: "owned-notice", body: "Original source text", title: "Payment", date: date,
                                  usesReceivedDate: true, kind: "unknown", status: "pending", cents: 960, party: "Cafe")
            var ledger = Ledger(); ledger.tngNotices = [notice]
            let items = [ExpenseItem(name: "Tea", cents: 960, category: "餐饮", quantity: 2, ownership: amy)]
            if review {
                try ledger.resolveNotice(id: notice.id, purpose: "expense", party: "Cafe", cents: 960, date: date, items: items)
            } else {
                try ledger.confirmTNGExpense(id: notice.id, merchant: "Cafe", cents: 960, date: date, category: "餐饮", items: items)
            }
            let restored = try LocalStore.decode(LocalStore.encode(ledger))
            XCTAssertEqual(restored.expenses[0].personal, 0)
            XCTAssertEqual(restored.expenses[0].shares[0].cents, 960)
            XCTAssertEqual(restored.expenses[0].items, items)
            XCTAssertEqual(restored.tngNotices[0].body, notice.body)
            XCTAssertEqual(restored.tngNotices[0].expenseID, restored.expenses[0].id)
        }
    }
}

final class NotificationBannerTests: XCTestCase {
    @MainActor func testWaitingNoticesSurviveHigherPriorityBannerDismissal() throws {
        let model = LedgerModel(previewLedger: GuideSample.ledger())
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let ledgerBefore = try encoder.encode(model.ledger)
        XCTAssertNil(model.activeBanner)
        model.showSaved(message: "Saved")
        let saved = try XCTUnwrap(model.savedNotice)
        XCTAssertEqual(model.activeBanner, .saved)
        model.newTNGCount = 2
        let imported = model.newTNGToken
        XCTAssertEqual(model.activeBanner, .imported)
        let notice = ForegroundLedgerNotice(title: "Recorded", message: "RM35.00", userInfo: [:])
        model.receiveForegroundNotice(notice)
        XCTAssertEqual(model.activeBanner, .foreground)
        model.dismissForegroundNotice(id: notice.id)
        XCTAssertEqual(model.activeBanner, .imported)
        XCTAssertEqual(model.newTNGCount, 2)
        model.dismissNewTNG(id: imported)
        XCTAssertEqual(model.activeBanner, .saved)
        XCTAssertEqual(model.savedNotice, saved)
        model.dismissSavedNotice(id: saved)
        XCTAssertNil(model.activeBanner)
        XCTAssertEqual(try encoder.encode(model.ledger), ledgerBefore)
    }
    func testAcceptsLeftRightAndUpButRejectsDownAndAmbiguousDiagonals() {
        for direction in [CGFloat(-1), CGFloat(1)] {
            XCTAssertTrue(BannerSwipePolicy.accepts(translation: CGPoint(x: direction * 20, y: 3), velocity: .zero))
            XCTAssertEqual(BannerSwipePolicy.accepts(translation: CGPoint(x: 3, y: direction * 20), velocity: .zero), direction < 0)
            XCTAssertFalse(BannerSwipePolicy.accepts(translation: CGPoint(x: direction * 20, y: 20), velocity: .zero))
            XCTAssertTrue(BannerSwipePolicy.accepts(translation: .zero, velocity: CGPoint(x: direction * 800, y: 20)))
        }
        XCTAssertFalse(BannerSwipePolicy.accepts(translation: .zero, velocity: .zero))
        XCTAssertTrue(BannerSwipePolicy.accepts(translation: .zero, velocity: CGPoint(x: 10, y: -800)))
    }
    func testShortSwipesSnapBackAndCancellationNeverDismisses() {
        for direction in [CGFloat(-1), CGFloat(1)] {
            XCTAssertNil(BannerSwipePolicy.dismissalDirection(offset: direction * 40, velocity: 0, width: 320))
            XCTAssertNil(BannerSwipePolicy.dismissalDirection(offset: direction * 8, velocity: direction * 1000, width: 320))
            XCTAssertNil(BannerSwipePolicy.dismissalDirection(offset: direction * 240, velocity: direction * 1000, width: 320, cancelled: true))
        }
    }
    func testDistanceFlickAndReverseGesturesInBothDirections() {
        for direction in [CGFloat(-1), CGFloat(1)] {
            XCTAssertEqual(BannerSwipePolicy.dismissalDirection(offset: direction * 100, velocity: 0, width: 320), direction)
            XCTAssertEqual(BannerSwipePolicy.dismissalDirection(offset: direction * 20, velocity: direction * 800, width: 320), direction)
            XCTAssertNil(BannerSwipePolicy.dismissalDirection(offset: direction * 110, velocity: -direction * 700, width: 320))
            XCTAssertNil(BannerSwipePolicy.dismissalDirection(offset: direction * 200, velocity: -direction * 2500, width: 320))
            XCTAssertNil(BannerSwipePolicy.dismissalDirection(offset: direction * 100, velocity: 0, width: 520))
            XCTAssertEqual(BannerSwipePolicy.dismissalDirection(offset: direction * 145, velocity: 0, width: 520), direction)
        }
    }
    func testForegroundDestinationRequiresAnExplicitValidRecordReference() {
        let valid = ForegroundLedgerNotice(title: "YueJi", message: "RM5", userInfo: ["recordID": "receipt", "recordKind": "notice"])
        XCTAssertEqual(valid.destination, ["recordID": "receipt", "kind": "notice", "action": "view"])
        let invalid: [[AnyHashable: Any]] = [[:], ["recordID": "", "recordKind": "notice"], ["recordID": "receipt", "recordKind": "unknown"]]
        for info in invalid {
            XCTAssertNil(ForegroundLedgerNotice(title: "YueJi", message: "RM5", userInfo: info).destination)
        }
    }
    @MainActor func testOlderDismissalCannotClearANewerNoticeOrChangeMoneyRecords() throws {
        let model = LedgerModel(previewLedger: GuideSample.ledger())
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let before = try encoder.encode(model.ledger)
        let old = ForegroundLedgerNotice(title: "First", message: "RM5", userInfo: [:])
        let latest = ForegroundLedgerNotice(title: "Second", message: "RM5", userInfo: [:])
        model.receiveForegroundNotice(old); model.receiveForegroundNotice(latest)
        model.dismissForegroundNotice(id: old.id)
        XCTAssertEqual(model.foregroundNotice, latest)
        model.dismissForegroundNotice(id: latest.id)
        XCTAssertNil(model.foregroundNotice)
        model.showSaved(message: "First")
        let oldSaved = try XCTUnwrap(model.savedNotice)
        model.showSaved(message: "Second")
        let latestSaved = try XCTUnwrap(model.savedNotice)
        model.dismissSavedNotice(id: oldSaved)
        XCTAssertEqual(model.savedNotice, latestSaved)
        model.dismissSavedNotice(id: latestSaved)
        XCTAssertNil(model.savedNotice)
        XCTAssertEqual(before, try encoder.encode(model.ledger))
    }
    @MainActor func testRecordSummaryAndInteractionDismissalsArePresentationOnly() {
        let model = LedgerModel(previewLedger: GuideSample.ledger())
        let revision = model.ledgerRevision
        model.newTNGCount = 3
        let token = model.newTNGToken
        model.dismissNewTNG(id: UUID())
        XCTAssertEqual(model.newTNGCount, 3)
        model.setBannerInteraction(id: "old", active: true)
        model.setBannerInteraction(id: "new", active: true)
        model.setBannerInteraction(id: "old", active: false)
        XCTAssertEqual(model.bannerInteraction, "new")
        model.dismissNewTNG(id: token)
        XCTAssertEqual(model.newTNGCount, 0)
        XCTAssertNotEqual(model.newTNGToken, token)
        model.newTNGCount = 1
        model.dismissNewTNG(id: token)
        XCTAssertEqual(model.newTNGCount, 1)
        XCTAssertEqual(model.ledgerRevision, revision)
    }
    @MainActor func testNativeHostTracksFingerCancelsTapAndRestoresAfterCancelledSwipe() throws {
        let gate = BannerInteraction()
        var dismissals = 0
        let controller = SwipeBannerController(content: AnyView(Text("Notice").padding()), interaction: gate,
            reduceMotion: false, onDismiss: { dismissals += 1 }, onInteraction: { _ in })
        controller.loadViewIfNeeded()
        controller.view.frame = CGRect(x: 0, y: 0, width: 320, height: 64)
        controller.view.layoutIfNeeded()
        let card = try XCTUnwrap(controller.children.first?.view)
        controller.beginContact()
        controller.handlePan(state: .began, translation: CGPoint(x: -14, y: 0), velocity: .zero)
        controller.handlePan(state: .changed, translation: CGPoint(x: -80, y: 0), velocity: .zero)
        XCTAssertEqual(card.transform.tx, -80, accuracy: 0.01)
        XCTAssertFalse(gate.canActivate)
        controller.handlePan(state: .cancelled, translation: CGPoint(x: -80, y: 0), velocity: CGPoint(x: -800, y: 0))
        XCTAssertEqual(card.transform, .identity)
        XCTAssertEqual(dismissals, 0)
        controller.beginContact() // A new touch may interrupt the return animation.
        XCTAssertTrue(gate.canActivate)
        controller.movedContact(translation: CGPoint(x: 0, y: 30))
        XCTAssertFalse(gate.canActivate) // A vertical swipe over a button cannot activate it either.
        XCTAssertEqual(dismissals, 0)
        controller.stop()
    }
    @MainActor func testSystemScreensUseNativePresentationInsteadOfAnObscuredBanner() {
        XCTAssertFalse(LedgerNotifications.requiresSystemBanner(UIViewController()))
        XCTAssertTrue(LedgerNotifications.requiresSystemBanner(UIAlertController(title: "Review", message: nil, preferredStyle: .alert)))
        XCTAssertTrue(LedgerNotifications.requiresSystemBanner(UIActivityViewController(activityItems: ["Statement"], applicationActivities: nil)))
    }
    @MainActor func testRapidDismissRequestsCompleteOnceWithoutActivatingBanner() async {
        let gate = BannerInteraction()
        let done = expectation(description: "Banner finished exiting")
        done.assertForOverFulfill = true
        var dismissals = 0
        let controller = SwipeBannerController(content: AnyView(Text("Notice").padding()), interaction: gate,
            reduceMotion: true, onDismiss: { dismissals += 1; done.fulfill() }, onInteraction: { _ in })
        controller.loadViewIfNeeded()
        controller.view.frame = CGRect(x: 0, y: 0, width: 320, height: 64)
        controller.view.layoutIfNeeded()
        gate.dismiss?(); gate.dismiss?()
        XCTAssertFalse(gate.canActivate)
        await fulfillment(of: [done], timeout: 3)
        XCTAssertEqual(dismissals, 1)
        controller.stop()
    }
    @MainActor func testUpwardSwipePausesInteractionBlocksActivationAndReleasesHitArea() async throws {
        let gate = BannerInteraction()
        var contacts: [Bool] = []
        let done = expectation(description: "Upward dismissal completed")
        done.assertForOverFulfill = true
        let controller = SwipeBannerController(content: AnyView(Text("Notice").padding()), interaction: gate,
            reduceMotion: false, onDismiss: { done.fulfill() }, onInteraction: { contacts.append($0) })
        controller.loadViewIfNeeded()
        controller.view.frame = CGRect(x: 0, y: 0, width: 320, height: 64)
        controller.view.layoutIfNeeded()
        let card = try XCTUnwrap(controller.children.first?.view)
        controller.beginContact()
        XCTAssertEqual(contacts, [true])
        controller.handlePan(state: .began, translation: CGPoint(x: 2, y: -15), velocity: .zero)
        controller.handlePan(state: .changed, translation: CGPoint(x: 5, y: -90), velocity: .zero)
        XCTAssertEqual(card.transform.ty, -90, accuracy: 0.01)
        XCTAssertEqual(card.transform.tx, 0, accuracy: 0.01)
        XCTAssertFalse(gate.canActivate)
        controller.handlePan(state: .ended, translation: CGPoint(x: 5, y: -90), velocity: .zero)
        controller.endContact()
        XCTAssertEqual(contacts, [true, false])
        XCTAssertTrue(gate.exiting)
        await fulfillment(of: [done], timeout: 3)
        XCTAssertFalse(controller.view.isUserInteractionEnabled)
        XCTAssertFalse(gate.canActivate)
        controller.stop()
    }
}

final class ExpenseItemPreviewTests: XCTestCase {
    func testPreviewUsesSavedNamesInOrderAndCountsRemainingItemsWithoutChangingMoney() throws {
        for source in ["手动", "TNG"] {
            var entry = Expense(merchant: "Market", cents: 1000, date: Date())
            entry.source = source
            XCTAssertNil(entry.itemPreview)
            entry.items = []
            XCTAssertNil(entry.itemPreview)
            entry.items = [ExpenseItem(name: "Milk", cents: 100, category: "Food")]
            XCTAssertEqual(entry.itemPreview, ExpenseItemPreview(names: "Milk", remaining: 0))
            entry.items?.append(ExpenseItem(name: "Bread\n loaf", cents: 200, category: "Food"))
            XCTAssertEqual(entry.itemPreview, ExpenseItemPreview(names: "Milk · Bread loaf", remaining: 0))
            entry.items?.append(ExpenseItem(name: "Soap", cents: 300, category: "Shopping"))
            entry.items?.append(ExpenseItem(name: "Milk", cents: 400, category: "Food"))
            let original = entry
            XCTAssertEqual(entry.itemPreview, ExpenseItemPreview(names: "Milk · Bread loaf", remaining: 2))
            XCTAssertEqual(entry, original)
            XCTAssertEqual(entry.cents, 1000)
            XCTAssertEqual(entry.categoryDistribution(total: 1000), ["Food": 700, "Shopping": 300])
        }
    }
}

final class ColdLaunchReadinessTests: XCTestCase {
    @MainActor func testColdLaunchUsesSuccessfulSnapshotAndEitherOpeningCompletionOrder() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = LocalStore(folder: folder), worker = LedgerRefreshWorker(store: store)
        let purchase = Expense(merchant: "Saved purchase", cents: 3500, date: Date(timeIntervalSince1970: 1_700_000_000))
        try store.change { $0.expenses = [purchase] }

        for (openingEnabled, openingFinishedBeforeRead) in [(false, false), (true, true), (true, false)] {
            let model = LedgerModel()
            XCTAssertFalse(model.finishLaunchIfReady(openingEnabled: openingEnabled, openingFinished: openingFinishedBeforeRead))
            XCTAssertFalse(model.didFinishLaunch, "Never unlock an empty draft ledger before reading the saved file")
            await model.refresh(postRecurring: false, using: worker)
            XCTAssertTrue(model.loaded)
            XCTAssertEqual(model.ledger.expenses, [purchase])
            if openingEnabled && !openingFinishedBeforeRead {
                XCTAssertFalse(model.finishLaunchIfReady(openingEnabled: true, openingFinished: false))
                XCTAssertFalse(model.didFinishLaunch)
            }
            // No mounted TabView or foreground scene callback is needed to finish.
            let finalOpeningFinished = openingEnabled
            XCTAssertTrue(model.finishLaunchIfReady(openingEnabled: openingEnabled, openingFinished: finalOpeningFinished))
            XCTAssertTrue(model.didFinishLaunch)
            XCTAssertFalse(model.finishLaunchIfReady(openingEnabled: openingEnabled, openingFinished: finalOpeningFinished))
            XCTAssertEqual(model.ledger.expenses, [purchase])
            XCTAssertEqual(try store.read().expenses, [purchase])
        }
    }

    @MainActor func testFailedColdReadKeepsSavedFileLockedUntilSuccessfulRetry() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = LocalStore(folder: folder), worker = LedgerRefreshWorker(store: store)
        let purchase = Expense(merchant: "Keep this record", cents: 1500, date: Date(timeIntervalSince1970: 1_700_000_000))
        try store.change { $0.expenses = [purchase] }
        let file = folder.appendingPathComponent("ledger.json")
        let originalData = try Data(contentsOf: file)
        let unreadable = Data("unreadable ledger".utf8)
        try unreadable.write(to: file)
        let model = LedgerModel()
        await model.refresh(postRecurring: false, using: worker)
        XCTAssertNotNil(model.error)
        XCTAssertFalse(model.loaded)
        XCTAssertFalse(model.finishLaunchIfReady(openingEnabled: false, openingFinished: true))
        XCTAssertFalse(model.didFinishLaunch)
        XCTAssertEqual(try Data(contentsOf: file), unreadable)

        // Restore only this disposable fixture, then exercise the same retry path.
        try originalData.write(to: file)
        model.error = nil
        await model.refresh(postRecurring: false, using: worker)
        XCTAssertNil(model.error)
        XCTAssertTrue(model.finishLaunchIfReady(openingEnabled: false, openingFinished: false))
        XCTAssertEqual(model.ledger.expenses, [purchase])
        XCTAssertEqual(try Data(contentsOf: file), originalData)
    }
}

final class TransactionItemsTests: XCTestCase {
    @MainActor func testItemBindingsFollowIdentityAfterDeletionAndIgnoreLateWrites() {
        let first = ExpenseItemDraft(id: "first", name: "Lunch", amount: "15.00", category: "餐饮")
        let second = ExpenseItemDraft(id: "second", name: "Supplies", amount: "20.00", category: "购物")
        var drafts = [first, second]
        let collection = Binding(get: { drafts }, set: { drafts = $0 })
        let removedBinding = first.binding(in: collection)
        let retainedBinding = second.binding(in: collection)

        drafts.removeFirst()
        // SwiftUI can finish a text or picker callback after a row is removed.
        removedBinding.name.wrappedValue = "Late text"
        removedBinding.category.wrappedValue = "交通"
        XCTAssertEqual(drafts.count, 1)
        XCTAssertEqual(drafts[0].name, "Supplies")
        XCTAssertEqual(drafts[0].category, "购物")
        retainedBinding.amount.wrappedValue = "35.00"
        XCTAssertEqual(drafts[0].id, "second")
        XCTAssertEqual(drafts[0].amount, "35.00")

        drafts.removeAll()
        XCTAssertEqual(retainedBinding.wrappedValue.id, "second")
        retainedBinding.amount.wrappedValue = "99.00"
        XCTAssertTrue(drafts.isEmpty)
        // Replacing all rows must not revive the removed item or redirect a write.
        drafts = [ExpenseItemDraft(id: "third", category: "其他")]
        retainedBinding.name.wrappedValue = "Late update"
        XCTAssertEqual(drafts[0].name, "")
    }

    func testEditingTransactionWithHiddenLegacyTagsPreservesBackupAndReports() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = LocalStore(folder: folder), worker = LedgerRefreshWorker(store: store)
        var expense = purchase()
        expense.tags = ["Trip", "家庭"]
        expense.note = "Legacy note"
        try store.change { $0.expenses = [expense] }
        let before = try store.read()
        let original = try XCTUnwrap(before.expenses.first)
        // General editing starts with the original record; Tags have no UI binding.
        var edited = original
        edited.merchant = "Renamed purchase"
        try await worker.saveExpense(edited, replacing: original, rememberCategory: false)
        let after = try store.read()
        XCTAssertEqual(after.expenses[0].tags, original.tags)
        XCTAssertEqual(after.expenses[0].note, original.note)
        XCTAssertEqual(after.expenses[0].items, original.items)
        XCTAssertEqual(after.expenses[0].cents, original.cents)
        XCTAssertEqual(after.spending(in: date), before.spending(in: date))
        for category in before.categoryNames {
            XCTAssertEqual(after.spending(in: date, category: category), before.spending(in: date, category: category))
        }
        let backup = try LocalStore.decode(LocalStore.exportData(after))
        XCTAssertEqual(backup.expenses, after.expenses)
        XCTAssertEqual(backup.expenses[0].tags, ["Trip", "家庭"])
    }

    private let date = Date(timeIntervalSince1970: 1_700_000_000)
    private var items: [ExpenseItem] {
        [ExpenseItem(id: "lunch-item", name: "Lunch", cents: 1500, category: "餐饮"),
         ExpenseItem(id: "supplies-item", name: "Household supplies", cents: 2000, category: "购物")]
    }
    private func purchase(source: String = "手动") -> Expense {
        Expense(id: "mixed", merchant: "Mixed purchase", cents: 3500, date: date, category: "其他", source: source, items: items)
    }

    func testSharedItemsEditorPreservesNotesHistoryAndSourceAcrossAddEditRemove() async throws {
        for automatic in [false, true] {
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: folder) }
            let store = LocalStore(folder: folder), worker = LedgerRefreshWorker(store: store)
            try store.change { ledger in
                if automatic {
                    _ = try ledger.receiveTNG(body: "You have paid RM35.00 for Shop.", title: "Payment", date: date, eventID: "notes-items")
                    try ledger.setNoticeNote(id: ledger.tngNotices[0].id, note: "旧备注 · Legacy note · Nota lama")
                } else {
                    ledger.expenses = [Expense(merchant: "Shop", cents: 3500, date: date, note: "  Old note\n保留原文  ")]
                }
                ledger.expenses[0].tags = ["Family"]
                ledger.expenses[0].shares = [Share(name: "Amy", cents: 1000, repayments: [Repayment(cents: 200, date: date.addingTimeInterval(60))])]
                try ledger.addRefund(expenseID: ledger.expenses[0].id, cents: 350, date: date.addingTimeInterval(120))
            }
            let initial = try store.read()
            var previous = initial.expenses[0]
            let personal = previous.personal, outstanding = initial.friendBalances.map(\.owed)
            let modified = [ExpenseItem(id: "lunch-item", name: "Dinner", cents: 1000, category: "餐饮"),
                            ExpenseItem(id: "supplies-item", name: "Supplies", cents: 2500, category: "购物")]
            let single = [ExpenseItem(id: "supplies-item", name: "Supplies", cents: 3500, category: "购物")]
            for nextItems in [items, modified, single, []] {
                let edited = try previous.replacingItems(nextItems, allowedCategories: initial.categoryNames)
                try await worker.saveExpense(edited, replacing: previous, rememberCategory: false)
                let after = try store.read()
                XCTAssertEqual(after.expenses.count, 1)
                XCTAssertEqual(after.expenses[0].id, previous.id)
                XCTAssertEqual(after.expenses[0].note, initial.expenses[0].note)
                XCTAssertEqual(after.expenses[0].tags, initial.expenses[0].tags)
                XCTAssertEqual(after.expenses[0].shares, initial.expenses[0].shares)
                XCTAssertEqual(after.expenses[0].refunds, initial.expenses[0].refunds)
                XCTAssertEqual(after.tngNotices, initial.tngNotices)
                XCTAssertEqual(after.seenEvents, initial.seenEvents)
                XCTAssertEqual(after.friendBalances.map(\.owed), outstanding)
                XCTAssertEqual(after.spending(in: date), personal)
                XCTAssertEqual(OverviewSnapshot(ledger: after, month: date).categoryTotals.values.reduce(0, +), personal)
                let backup = try LocalStore.decode(LocalStore.exportData(after))
                XCTAssertEqual(backup.expenses, after.expenses)
                XCTAssertEqual(backup.tngNotices, after.tngNotices)
                previous = after.expenses[0]
            }
        }
    }

    func testSharedItemsEditorRejectsInvalidTotalsAndConcurrentNotesWithoutDataLoss() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = LocalStore(folder: folder), worker = LedgerRefreshWorker(store: store)
        try store.change { ledger in
            _ = try ledger.receiveTNG(body: "You have paid RM35.00 for Shop.", date: date, eventID: "invalid-items-note")
        }
        let original = try XCTUnwrap(store.read().expenses.first)
        XCTAssertThrowsError(try original.replacingItems([ExpenseItem(name: "Incomplete", cents: 1500, category: "餐饮")], allowedCategories: Ledger().categoryNames))
        XCTAssertEqual(try store.read().expenses, [original])
        let valid = try original.replacingItems(items, allowedCategories: Ledger().categoryNames)
        try store.change { try $0.setNoticeNote(id: $0.tngNotices[0].id, note: "Newer note") }
        do { try await worker.saveExpense(valid, replacing: original, rememberCategory: false); XCTFail("A stale item edit must not overwrite newer notes") }
        catch {
            let after = try store.read()
            XCTAssertEqual(after.expenses[0].note, "Newer note")
            XCTAssertEqual(after.tngNotices[0].note, "Newer note")
            XCTAssertNil(after.expenses[0].items)
        }
    }

    func testPendingNotificationCanBeConfirmedWithItemsAndKeepsSourceAndNote() throws {
        for review in [false, true] {
            let notice = TNGNotice(id: "pending-items", body: "Original bank payment description", title: "Bank alert", date: date,
                                   usesReceivedDate: true, kind: "unknown", status: "pending", cents: 3500, party: "Shop", note: "Legacy note")
            var ledger = Ledger()
            ledger.tngNotices = [notice]
            ledger = try ledger.validated()
            if review {
                try ledger.resolveNotice(id: notice.id, purpose: "expense", party: "Shop", cents: 3500, date: date, category: "其他", remember: true, items: items)
            } else {
                try ledger.confirmTNGExpense(id: notice.id, merchant: "Shop", cents: 3500, date: date, category: "其他", remember: true, items: items)
                ledger = try ledger.validated()
            }
            let entry = try XCTUnwrap(ledger.expenses.first)
            XCTAssertEqual(entry.items, items)
            XCTAssertEqual(entry.note, "Legacy note")
            XCTAssertEqual(ledger.expenses.count, 1)
            XCTAssertEqual(ledger.tngNotices[0].body, notice.body)
            XCTAssertEqual(ledger.tngNotices[0].title, notice.title)
            XCTAssertEqual(ledger.tngNotices[0].expenseID, entry.id)
            XCTAssertEqual(ledger.spending(in: date), 3500)
            XCTAssertEqual(ledger.spending(in: date, category: "餐饮"), 1500)
            XCTAssertEqual(ledger.spending(in: date, category: "购物"), 2000)
            XCTAssertTrue(ledger.merchantCategories.isEmpty)
            XCTAssertThrowsError(try ledger.confirmTNGExpense(id: notice.id, merchant: "Shop", cents: 3500, date: date, category: "其他", items: items))
            XCTAssertEqual(ledger.expenses.count, 1)
        }
    }

    func testInvalidItemsLeavePendingNotificationUnchangedInBothConfirmationPaths() throws {
        for review in [false, true] {
            let notice = TNGNotice(id: "pending", body: "Original source text", title: "Payment", date: date,
                                   usesReceivedDate: true, kind: "unknown", status: "pending", cents: 3500, note: "Keep this")
            var ledger = Ledger()
            ledger.tngNotices = [notice]
            ledger = try ledger.validated()
            let invalid = [ExpenseItem(name: "Lunch", cents: 1500, category: "餐饮")]
            if review {
                XCTAssertThrowsError(try ledger.resolveNotice(id: notice.id, purpose: "expense", party: "Edited merchant", cents: 3500, date: date, category: "其他", items: invalid))
            } else {
                XCTAssertThrowsError(try ledger.confirmTNGExpense(id: notice.id, merchant: "Edited merchant", cents: 3500, date: date, category: "其他", items: invalid))
            }
            XCTAssertTrue(ledger.expenses.isEmpty)
            XCTAssertEqual(ledger.tngNotices, [notice])
            XCTAssertTrue(ledger.merchantCategories.isEmpty)
        }
    }

    func testExpenseSourceIndexKeepsOriginalNotificationsSeparateFromLegacyNotes() throws {
        var ledger = Ledger()
        _ = try ledger.receiveTNG(body: "You have paid RM35.00 for Shop.", title: "Original alert", date: date, eventID: "source-index")
        let original = ledger.tngNotices[0]
        try ledger.setNoticeNote(id: original.id, note: "A personal note, not the source")
        ledger.expenses.append(Expense(id: "manual", merchant: "Manual", cents: 100, date: date))
        ledger.expenses[0] = try ledger.expenses[0].replacingItems(items, allowedCategories: ledger.categoryNames)
        let index = LedgerNavigationIndex(ledger: try ledger.validated())
        let detail = try XCTUnwrap(index.detail(id: ledger.expenses[0].id))
        XCTAssertEqual(detail.sourceNotices.count, 1)
        XCTAssertEqual(detail.sourceNotices[0].body, original.body)
        XCTAssertEqual(detail.sourceNotices[0].title, original.title)
        XCTAssertEqual(detail.entry.note, "A personal note, not the source")
        XCTAssertTrue(try XCTUnwrap(index.detail(id: "manual")).sourceNotices.isEmpty)
        ledger.tngNotices.removeAll()
        XCTAssertTrue(try XCTUnwrap(LedgerNavigationIndex(ledger: ledger).detail(id: detail.entry.id)).sourceNotices.isEmpty)
        XCTAssertEqual(ledger.expenses[0].note, detail.entry.note)
    }

    func testItemsEditorCannotSilentlyChangeActiveSettlement() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = LocalStore(folder: folder), worker = LedgerRefreshWorker(store: store)
        try store.change { ledger in
            ledger.expenses = [Expense(merchant: "Lunch", cents: 3500, date: date, shares: [Share(name: "Amy", cents: 1000)], note: "Stored note")]
            let plan = try ledger.settlementPlan(friend: "Amy", selected: Set(ledger.friendDebtItems.map(\.id)), payment: 1000, date: date.addingTimeInterval(60))
            _ = try ledger.confirmSettlement(plan)
        }
        let before = try store.read(), original = try XCTUnwrap(store.read().expenses.first)
        let edited = try original.replacingItems(items, allowedCategories: before.categoryNames)
        do { try await worker.saveExpense(edited, replacing: original, rememberCategory: false); XCTFail("Undo the settlement before editing its items") }
        catch {
            XCTAssertEqual(try store.read().expenses, before.expenses)
            XCTAssertEqual(try store.read().settlements, before.settlements)
        }
    }

    func testRM35ItemsUseTheirCategoriesWithoutCountingParentTwice() throws {
        for source in ["手动", "TNG", "Apple Pay", "Maybank"] {
            let expense = purchase(source: source)
            let ledger = try Ledger(expenses: [expense]).validated()
            let overview = OverviewSnapshot(ledger: ledger, month: date)
            XCTAssertEqual(ledger.expenses.count, 1)
            XCTAssertEqual(overview.personal, 3500)
            XCTAssertEqual(overview.paid, 3500)
            XCTAssertEqual(overview.categoryTotals["餐饮"], 1500)
            XCTAssertEqual(overview.categoryTotals["购物"], 2000)
            XCTAssertEqual(overview.categoryTotals.values.reduce(0, +), 3500)
            XCTAssertEqual(ledger.spending(in: date, category: "其他"), 0)
            XCTAssertEqual(LedgerTimelineItem.grouped(expenses: ledger.expenses, transfers: []).flatMap(\.entries).count, 1)
            XCTAssertEqual(expense.purchaseDirection.formattedAmount(expense.purchaseDisplayCents), "−RM 35.00")
            XCTAssertEqual(try LocalStore.decode(LocalStore.encode(ledger)).expenses, [expense])
        }
    }

    func testItemsAllowRepeatedCategoriesAndPreserveEverySenWithSharesAndRefunds() throws {
        var expense = purchase()
        expense.shares = [Share(name: "Amy", cents: 1400)]
        var ledger = try Ledger(expenses: [expense]).validated()
        XCTAssertEqual(expense.personalItemAmounts, ["lunch-item": 900, "supplies-item": 1200])
        try ledger.addRefund(expenseID: expense.id, cents: 700, date: date.addingTimeInterval(60))
        let refunded = ledger.expenses[0]
        XCTAssertEqual(refunded.personal, 1680)
        XCTAssertEqual(refunded.personalItemAmounts, ["lunch-item": 720, "supplies-item": 960])
        XCTAssertEqual(refunded.categoryDistribution(total: refunded.personal), ["餐饮": 720, "购物": 960])
        XCTAssertEqual(ledger.friendSpending(friend: "Amy").categories.values.reduce(0, +), 1120)
        XCTAssertEqual(refunded.items, items, "Refunds do not erase original item prices")

        var small = Expense(merchant: "Rounding", cents: 3, date: date, shares: [Share(name: "Amy", cents: 1)])
        small.items = [ExpenseItem(id: "a", name: "A", cents: 1, category: "餐饮"),
                       ExpenseItem(id: "b", name: "B", cents: 1, category: "餐饮"),
                       ExpenseItem(id: "c", name: "C", cents: 1, category: "购物")]
        _ = try Ledger(expenses: [small]).validated()
        XCTAssertEqual(small.personalItemAmounts.values.reduce(0, +), 2)
        XCTAssertEqual(small.categoryDistribution(total: small.personal).values.reduce(0, +), 2)
        XCTAssertEqual(small.personalAmount(category: "餐饮"), (small.personalItemAmounts["a"] ?? 0) + (small.personalItemAmounts["b"] ?? 0))
        XCTAssertEqual(small.categorySummary.components(separatedBy: " / ").count, 2)
    }

    func testInvalidItemsRejectTotalsNamesCategoriesIDsAmountsAndDualAllocation() throws {
        func rejects(_ mutate: (inout Expense) -> Void) {
            var expense = purchase(); mutate(&expense)
            XCTAssertThrowsError(try Ledger(expenses: [expense]).validated())
        }
        rejects { $0.items?[0].cents = 1499 }
        rejects { $0.items?[0].name = " \n " }
        rejects { $0.items?[0].category = "Unknown category" }
        rejects { $0.items?[0].id = "supplies-item" }
        rejects { $0.items?[0].cents = 0 }
        rejects { $0.items?[0].cents = -1 }
        rejects { $0.items?[0].cents = Int.max }
        rejects { $0.items?[0].name = String(repeating: "x", count: 201) }
        rejects { $0.items = (0...100).map { ExpenseItem(id: String($0), name: "Item", cents: 1, category: "其他") } }
        rejects { $0.categoryAllocations = [CategoryAllocation(category: "餐饮", cents: 1500), CategoryAllocation(category: "购物", cents: 2000)] }
    }

    func testAutomaticPaymentStaysSavedDuringInvalidItemEditAndReplay() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = LocalStore(folder: folder)
        let body = "You have paid RM35.00 for Shop."
        try store.change { ledger in
            _ = try ledger.receiveTNG(body: body, date: date, eventID: "auto-items")
        }
        let before = try store.read()
        XCTAssertEqual(before.expenses.count, 1)
        XCTAssertNil(before.expenses[0].items)
        XCTAssertThrowsError(try store.change { ledger in
            ledger.expenses[0].items = [ExpenseItem(name: "Incomplete", cents: 1500, category: "餐饮")]
        })
        XCTAssertEqual(try store.read().expenses, before.expenses)
        try store.change { ledger in ledger.expenses[0].items = items }
        try store.change { ledger in
            _ = try ledger.receiveTNG(body: body, date: date.addingTimeInterval(300), eventID: "auto-items")
        }
        let after = try store.read()
        XCTAssertEqual(after.expenses.count, 1)
        XCTAssertEqual(after.expenses[0].id, before.expenses[0].id)
        XCTAssertEqual(after.expenses[0].items, items)
        XCTAssertEqual(after.tngNotices.map(\.expenseID), before.tngNotices.map(\.expenseID))
        XCTAssertEqual(after.spending(in: date), 3500)
        XCTAssertEqual(after.spending(in: date, category: "购物"), 2000)
    }

    func testEditingAndRemovingItemsUpdatesReportsAndSearchWithoutExtraEntries() throws {
        var ledger = try Ledger(expenses: [purchase()]).validated()
        XCTAssertEqual(try ledger.filteredEntries(in: date, search: "household", filter: LedgerFilter()).map(\.id), ["mixed"])
        var filter = LedgerFilter(); filter.category = "购物"
        XCTAssertEqual(try ledger.filteredEntries(in: date, search: "", filter: filter).count, 1)
        ledger.expenses[0].items?[0].name = "Dinner"
        ledger.expenses[0].items?[0].cents = 1000
        ledger.expenses[0].items?[1].cents = 2500
        ledger = try ledger.validated()
        XCTAssertEqual(ledger.spending(in: date, category: "餐饮"), 1000)
        ledger.expenses[0].items?.removeFirst()
        ledger.expenses[0].items?[0].cents = 3500
        ledger = try ledger.validated()
        XCTAssertEqual(ledger.spending(in: date, category: "购物"), 3500)
        XCTAssertEqual(ledger.expenses.count, 1)
        ledger.expenses[0].items = nil; ledger.expenses[0].category = "其他"
        ledger = try ledger.validated()
        XCTAssertEqual(ledger.spending(in: date, category: "其他"), 3500)
        XCTAssertEqual(try ledger.filteredEntries(in: date, search: "household", filter: LedgerFilter()).count, 0)
    }

    func testFriendPaidItemizedPurchaseStaysAnExpenseAfterPartialRepaymentAndUndo() throws {
        var expense = purchase()
        expense.paidByFriend = "Amy"; expense.shares = [Share(id: "amy", name: "Amy", cents: 1400)]
        var ledger = try Ledger(expenses: [expense]).validated()
        XCTAssertEqual(expense.accountDirection, .neutral)
        XCTAssertEqual(expense.paidFromMyAccount, 0)
        XCTAssertEqual(expense.purchaseDirection.formattedAmount(expense.purchaseDisplayCents), "−RM 21.00")
        XCTAssertEqual(ledger.payableToPayer(expense), 2100)
        let plan = try ledger.repaymentPlan(friend: "amy", selected: Set(ledger.friendDebtItems.map(\.id)), payment: 500, date: date.addingTimeInterval(60), direction: .outgoing)
        let id = try ledger.confirmSettlement(plan)
        XCTAssertEqual(ledger.payableToPayer(expense), 1600)
        XCTAssertEqual(ledger.spending(in: date), 2100)
        XCTAssertEqual(OverviewSnapshot(ledger: ledger, month: date).paid, 0)
        XCTAssertEqual(ledger.expenses[0].purchaseDisplayCents, 2100)
        XCTAssertEqual(ledger.expenses[0].items, items)
        XCTAssertEqual(ledger.settlements[0].lines[0].expense.items, items)
        var changed = ledger; changed.expenses[0].items?[0].name = "Different purchase"
        XCTAssertThrowsError(try changed.validated(), "Settled audit details cannot silently change")
        try ledger.undoSettlement(id: id)
        XCTAssertEqual(ledger.payableToPayer(expense), 2100)
        ledger.expenses[0].items?[0].name = "Lunch updated"
        _ = try ledger.validated()
        XCTAssertEqual(ledger.expenses.count, 1)
        XCTAssertEqual(ledger.spending(in: date, category: "餐饮"), 900)
        let finalPlan = try ledger.repaymentPlan(friend: "amy", selected: Set(ledger.friendDebtItems.map(\.id)), payment: 2100, date: date.addingTimeInterval(120), direction: .outgoing)
        try ledger.confirmSettlement(finalPlan)
        XCTAssertEqual(ledger.payableToPayer(ledger.expenses[0]), 0)
        XCTAssertEqual(ledger.expenses[0].purchaseDisplayCents, 2100)
        XCTAssertEqual(ledger.spending(in: date), 2100)
        let restored = try LocalStore.decode(LocalStore.encode(ledger))
        // Backups store whole-second ISO dates; undo uses the current instant.
        let expectedSettlements = ledger.settlements.map { record in
            var expected = record
            if let voidedAt = expected.voidedAt {
                expected.voidedAt = Date(timeIntervalSince1970: voidedAt.timeIntervalSince1970.rounded(.down))
            }
            return expected
        }
        XCTAssertEqual(restored.settlements, expectedSettlements)
        XCTAssertEqual(restored.expenses, ledger.expenses)
    }

    func testEntirelyMineFriendPaidItemsKeepDebtThroughBackupAndUndo() throws {
        var expense = purchase()
        expense.paidByFriend = "Amy"
        // The payer's own share is zero when the purchase is entirely mine.
        expense.shares = [Share(id: "amy", name: "Amy", cents: 0)]
        var ledger = try Ledger(expenses: [expense]).validated()
        XCTAssertEqual(expense.shares[0].cents, 0)
        XCTAssertEqual(expense.purchaseDirection.formattedAmount(expense.purchaseDisplayCents), "−RM 35.00")
        XCTAssertEqual(expense.paidFromMyAccount, 0)
        XCTAssertEqual(ledger.payableToPayer(expense), 3500)
        let plan = try ledger.repaymentPlan(friend: "amy", selected: Set(ledger.friendDebtItems.map(\.id)),
                                            payment: 500, date: date.addingTimeInterval(60), direction: .outgoing)
        let id = try ledger.confirmSettlement(plan)
        ledger = try LocalStore.decode(LocalStore.encode(ledger))
        XCTAssertEqual(ledger.payableToPayer(ledger.expenses[0]), 3000)
        XCTAssertEqual(ledger.expenses, [expense])
        XCTAssertEqual(ledger.settlements[0].lines[0].expense.items, items)
        XCTAssertEqual(OverviewSnapshot(ledger: ledger, month: date).categoryTotals, ["餐饮": 1500, "购物": 2000])
        XCTAssertEqual(ledger.spending(in: date), 3500)
        try ledger.undoSettlement(id: id)
        XCTAssertEqual(ledger.payableToPayer(ledger.expenses[0]), 3500)
        XCTAssertEqual(ledger.spending(in: date), 3500)
        XCTAssertEqual(ledger.expenses.count, 1)
        XCTAssertTrue(ledger.tngNotices.isEmpty)
    }

    func testItemizedExactOffsetKeepsBothPurchasesAndCategoryTotals() throws {
        var mine = purchase(); mine.shares = [Share(name: "Amy", cents: 1750)]
        var friend = purchase(); friend.id = "friend-purchase"
        friend.paidByFriend = "Amy"; friend.shares = [Share(name: "Amy", cents: 1750)]
        var ledger = try Ledger(expenses: [mine, friend]).validated()
        let plan = try ledger.settlementPlan(friend: "amy", selected: Set(ledger.friendDebtItems.map(\.id)), payment: 0, date: date.addingTimeInterval(60))
        let id = try ledger.confirmSettlement(plan)
        XCTAssertEqual(ledger.settlements[0].transfer, 0)
        XCTAssertEqual(ledger.friendBalances[0].owed, 0)
        XCTAssertEqual(ledger.friendBalances[0].payable, 0)
        XCTAssertEqual(ledger.expenses, [mine, friend])
        let overview = OverviewSnapshot(ledger: ledger, month: date)
        XCTAssertEqual(overview.personal, 3500)
        XCTAssertEqual(overview.categoryTotals, ["餐饮": 1500, "购物": 2000])
        XCTAssertTrue(ledger.tngNotices.isEmpty)
        try ledger.undoSettlement(id: id)
        XCTAssertEqual(ledger.friendBalances[0].owed, 1750)
        XCTAssertEqual(ledger.friendBalances[0].payable, 1750)
        XCTAssertEqual(ledger.spending(in: date), 3500)
    }

    func testItemCategoriesRenameDeleteProtectionCSVAndBackupCompatibility() throws {
        var ledger = Ledger(expenses: [purchase()])
        let custom = CustomCategory(name: "Household")
        try ledger.saveCategory(custom)
        ledger.expenses[0].items?[1].category = custom.name
        _ = try ledger.validated()
        XCTAssertThrowsError(try ledger.deleteCategory(custom.id))
        var renamed = custom; renamed.name = "Home supplies"; try ledger.saveCategory(renamed)
        XCTAssertEqual(ledger.expenses[0].items?[1].category, "Home supplies")
        XCTAssertEqual(ledger.spending(in: date, category: "Home supplies"), 2000)
        let exported = String(decoding: ledger.csv(month: date, splits: false), as: UTF8.self)
        XCTAssertTrue(exported.contains("items_MYR"))
        XCTAssertTrue(exported.contains("Household supplies:20.00:Home supplies"))
        let restored = try LocalStore.decode(LocalStore.encode(ledger))
        XCTAssertEqual(restored.version, 6)
        XCTAssertEqual(restored.expenses, ledger.expenses)

        var legacy = purchase(); legacy.items = nil; legacy.note = "Keep me"; legacy.tags = ["Trip"]
        let encoded = try LocalStore.encode(Ledger(expenses: [legacy]))
        for version in 1...5 {
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
            object["version"] = version
            let migrated = try LocalStore.decode(JSONSerialization.data(withJSONObject: object))
            XCTAssertEqual(migrated.version, 6)
            XCTAssertEqual(migrated.expenses, [legacy])
        }
    }

    func testItemizedAutomaticPurchaseCannotBeConvertedToSettlementPayment() throws {
        var debt = purchase(); debt.paidByFriend = "Amy"
        debt.shares = [Share(name: "Amy", cents: 0)]
        var ledger = Ledger(expenses: [debt])
        let plan = try ledger.repaymentPlan(friend: "amy", selected: Set(ledger.friendDebtItems.map(\.id)), payment: 3500, date: date.addingTimeInterval(60), direction: .outgoing)
        let settlementID = try ledger.confirmSettlement(plan)
        var automatic = purchase(source: "TNG"); automatic.id = "auto-purchase"
        ledger.expenses.append(automatic)
        ledger.tngNotices.append(TNGNotice(id: "bank", body: "Payment RM35.00", title: "Payment", date: date.addingTimeInterval(60), usesReceivedDate: false,
                                         kind: "payment", status: "recorded", cents: 3500, party: "Shop", expenseID: automatic.id, sourceBank: "TNG"))
        _ = try ledger.validated()
        XCTAssertThrowsError(try ledger.linkSettlementPayment(settlementID: settlementID, noticeID: "bank"))
        XCTAssertEqual(ledger.expenses.count, 2)
        XCTAssertEqual(ledger.expenses[1].items, items)
        XCTAssertNil(ledger.settlements[0].paymentNoticeID)
    }
}

final class LedgerTests: XCTestCase {
    private var settlementDate: Date { Date(timeIntervalSince1970: 1_700_000_100) }
    private func settlementExample() -> Ledger {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        return Ledger(expenses: [
            Expense(id: "lunch", merchant: "Lunch", cents: 6000, date: date, category: "餐饮", shares: [Share(id: "amy-lunch", name: "Amy", cents: 3000)]),
            Expense(id: "drinks", merchant: "Drinks", cents: 2000, date: date, category: "餐饮", shares: [Share(id: "amy-drinks", name: "Amy", cents: 1000)], paidByFriend: "Amy"),
            Expense(id: "mine", merchant: "Personal purchase", cents: 1500, date: date, category: "购物", shares: [Share(id: "amy-mine", name: "Amy", cents: 0)], paidByFriend: "Amy")
        ])
    }
    private func settlementNotice(id: String = "receipt", cents: Int = 500, kind: String = "incoming", reference: String = "BANK-123") -> TNGNotice {
        TNGNotice(id: id, body: "Bank transfer", title: "Transfer", date: settlementDate, usesReceivedDate: false,
                  kind: kind, status: "pending", cents: cents, party: "Amy", expenseID: nil, sourceBank: "TNG", bankReference: reference)
    }
    private func fullSettlement(_ ledger: inout Ledger, payment: Int = 500) throws -> String {
        let selected = Set(ledger.friendDebtItems.map(\.id))
        let plan = try ledger.settlementPlan(friend: "AMY", selected: selected, payment: payment, date: settlementDate)
        return try ledger.confirmSettlement(plan)
    }

    func testNetSettlementExampleKeepsRM55SpendingAndAllOriginalItems() throws {
        var ledger = try settlementExample().validated()
        let original = ledger.expenses
        XCTAssertEqual(ledger.friendBalances[0].owed, 3000)
        XCTAssertEqual(ledger.friendBalances[0].payable, 2500)
        let snapshot = OverviewSnapshot(ledger: ledger, month: settlementDate)
        XCTAssertEqual(snapshot.personal, 5500)
        XCTAssertEqual(snapshot.paid, 6000)
        let id = try fullSettlement(&ledger)
        XCTAssertEqual(ledger.settlements[0].id, id)
        XCTAssertEqual(ledger.settlements[0].transfer, 500)
        XCTAssertEqual(ledger.settlements[0].lines.count, 3)
        XCTAssertEqual(Set(ledger.settlements[0].lines.map { $0.expense.id }), Set(original.map(\.id)))
        XCTAssertEqual(ledger.friendBalances[0].owed, 0)
        XCTAssertEqual(ledger.friendBalances[0].payable, 0)
        XCTAssertEqual(ledger.expenses, original)
        XCTAssertEqual(ledger.spending(in: settlementDate), 5500)
        XCTAssertTrue(ledger.tngNotices.isEmpty, "Manual settlement must not invent a bank receipt or income")
        XCTAssertEqual(try LocalStore.decode(LocalStore.encode(ledger)).settlements, ledger.settlements)
    }

    func testPartialNetPaymentLeavesRemainderAndUnselectedItemsOutstanding() throws {
        var ledger = settlementExample()
        let selected = Set(ledger.friendDebtItems.map(\.id))
        ledger.expenses.append(Expense(id: "unselected", merchant: "Other lunch", cents: 1000, date: settlementDate,
                                       shares: [Share(name: "Amy", cents: 1000)]))
        let plan = try ledger.settlementPlan(friend: "amy", selected: selected, payment: 200, date: settlementDate)
        XCTAssertEqual(plan.offset, 2500)
        XCTAssertEqual(plan.fullNet, 500)
        try ledger.confirmSettlement(plan)
        XCTAssertEqual(ledger.friendDebtItems.first { $0.expense.id == "lunch" }?.balance, 300)
        XCTAssertEqual(ledger.friendDebtItems.first { $0.expense.id == "unselected" }?.balance, 1000)
        XCTAssertEqual(ledger.friendBalances[0].owed, 1300)
        XCTAssertEqual(ledger.friendBalances[0].payable, 0)
        XCTAssertEqual(ledger.spending(in: settlementDate), 5500)
        let lunch = ledger.expenses[0]
        XCTAssertThrowsError(try ledger.repay(expenseID: lunch.id, shareID: lunch.shares[0].id, cents: 301, date: settlementDate))
        try ledger.repay(expenseID: lunch.id, shareID: lunch.shares[0].id, cents: 300, date: settlementDate)
        XCTAssertEqual(ledger.friendBalances[0].owed, 1000)
        _ = try ledger.validated()
    }

    func testExactOffsetNeedsNoTransferAndKeepsOriginalSpending() throws {
        var ledger = settlementExample()
        ledger.expenses[2].cents = 2000 // Friend-paid personal cost now totals RM30 against RM30 receivable.
        let before = ledger.spending(in: settlementDate)
        let id = try fullSettlement(&ledger, payment: 0)
        XCTAssertEqual(ledger.settlements.first { $0.id == id }?.transfer, 0)
        XCTAssertEqual(ledger.friendBalances[0].owed, 0)
        XCTAssertEqual(ledger.friendBalances[0].payable, 0)
        XCTAssertEqual(ledger.spending(in: settlementDate), before)
        ledger.tngNotices.append(settlementNotice())
        XCTAssertThrowsError(try ledger.linkSettlementPayment(settlementID: id, noticeID: "receipt"))
    }

    func testOffsetsOnlyAndInvalidOrStaleSettlementPreviews() throws {
        var ledger = settlementExample()
        let selected = Set(ledger.friendDebtItems.map(\.id))
        XCTAssertThrowsError(try ledger.settlementPlan(friend: "Amy", selected: selected, payment: 501, date: settlementDate))
        XCTAssertThrowsError(try ledger.settlementPlan(friend: "Amy", selected: selected, payment: 500, date: Date(timeIntervalSince1970: 100)))
        let plan = try ledger.settlementPlan(friend: "Amy", selected: selected, payment: 500, date: settlementDate)
        ledger.expenses[0].merchant = "Edited lunch"
        XCTAssertThrowsError(try ledger.confirmSettlement(plan))
        XCTAssertTrue(ledger.settlements.isEmpty)
        try fullSettlement(&ledger, payment: 0)
        XCTAssertEqual(ledger.friendBalances[0].owed, 500)
        XCTAssertEqual(ledger.friendBalances[0].payable, 0)
    }

    func testSettlementPaymentRequiresConfirmationAndCannotBeAppliedTwice() throws {
        var ledger = settlementExample()
        let id = try fullSettlement(&ledger)
        ledger.tngNotices = [settlementNotice()]
        XCTAssertNil(ledger.settlements[0].paymentNoticeID, "Matching amount must not auto-link")
        try ledger.linkSettlementPayment(settlementID: id, noticeID: "receipt")
        XCTAssertEqual(ledger.tngNotices[0].status, "settlement")
        XCTAssertFalse(ledger.tngNotices.contains { $0.status == "income" })
        XCTAssertEqual(ledger.spending(in: settlementDate), 5500)
        XCTAssertThrowsError(try ledger.linkSettlementPayment(settlementID: id, noticeID: "receipt"))
        ledger.expenses.append(Expense(id: "next", merchant: "Next expense", cents: 500, date: settlementDate, shares: [Share(name: "Amy", cents: 500)]))
        let nextItem = try XCTUnwrap(ledger.friendDebtItems.first { $0.expense.id == "next" })
        let nextPlan = try ledger.settlementPlan(friend: "amy", selected: [nextItem.id], payment: 500, date: settlementDate)
        let nextID = try ledger.confirmSettlement(nextPlan)
        XCTAssertThrowsError(try ledger.linkSettlementPayment(settlementID: nextID, noticeID: "receipt"))
        ledger.tngNotices.append(settlementNotice(id: "duplicate-reference"))
        XCTAssertThrowsError(try ledger.linkSettlementPayment(settlementID: nextID, noticeID: "duplicate-reference", distinctConfirmed: true))
        ledger.tngNotices.append(settlementNotice(id: "independent", reference: "BANK-456"))
        try ledger.linkSettlementPayment(settlementID: nextID, noticeID: "independent")
        _ = try ledger.validated()
    }

    func testUndoSettlementRestoresDebtsAndKeepsOneBankPayment() throws {
        var ledger = settlementExample()
        let original = ledger.expenses
        let id = try fullSettlement(&ledger)
        ledger.tngNotices = [settlementNotice()]
        try ledger.linkSettlementPayment(settlementID: id, noticeID: "receipt")
        XCTAssertThrowsError(try ledger.deleteAutomaticRecord(ledger.tngNotices[0]))
        try ledger.undoSettlement(id: id)
        XCTAssertEqual(ledger.expenses, original)
        XCTAssertEqual(ledger.friendBalances[0].owed, 3000)
        XCTAssertEqual(ledger.friendBalances[0].payable, 2500)
        XCTAssertEqual(ledger.spending(in: settlementDate), 5500)
        XCTAssertEqual(ledger.tngNotices.count, 1)
        XCTAssertEqual(ledger.tngNotices[0].id, "receipt")
        XCTAssertEqual(ledger.tngNotices[0].status, "pending")
        XCTAssertNil(ledger.tngNotices[0].settlementID)
        XCTAssertFalse(ledger.settlements[0].active)
        XCTAssertThrowsError(try ledger.undoSettlement(id: id))
        let replacement = try fullSettlement(&ledger)
        try ledger.linkSettlementPayment(settlementID: replacement, noticeID: "receipt")
        XCTAssertEqual(ledger.tngNotices.count, 1)
        XCTAssertEqual(ledger.spending(in: settlementDate), 5500)
        _ = try ledger.validated()
    }

    func testOutgoingSettlementConvertsAutomaticExpenseAndUndoNeverRecreatesIt() throws {
        var ledger = settlementExample()
        ledger.expenses = [ledger.expenses[2]]
        let item = ledger.friendDebtItems[0]
        let plan = try ledger.settlementPlan(friend: "amy", selected: [item.id], payment: 1500, date: settlementDate)
        let id = try ledger.confirmSettlement(plan)
        let automatic = Expense(id: "automatic-transfer", merchant: "Amy transfer", cents: 1500, date: settlementDate, source: "TNG")
        ledger.expenses.append(automatic)
        var notice = settlementNotice(cents: 1500, kind: "payment")
        notice.status = "recorded"; notice.expenseID = automatic.id
        ledger.tngNotices = [notice]
        XCTAssertEqual(ledger.spending(in: settlementDate), 3000)
        try ledger.linkSettlementPayment(settlementID: id, noticeID: notice.id)
        XCTAssertEqual(ledger.spending(in: settlementDate), 1500)
        XCTAssertEqual(ledger.settlements[0].convertedPayment, automatic)
        XCTAssertEqual(ledger.expenses.count, 1)
        XCTAssertEqual(ledger.friendBalances[0].payable, 0)
        try ledger.undoSettlement(id: id)
        XCTAssertEqual(ledger.spending(in: settlementDate), 1500)
        XCTAssertEqual(ledger.friendBalances[0].payable, 1500)
        XCTAssertEqual(ledger.tngNotices.count, 1)
        XCTAssertEqual(ledger.tngNotices[0].status, "transfer")
        XCTAssertNil(ledger.tngNotices[0].expenseID)
        _ = try ledger.validated()
    }

    func testSettledExpenseEditsAndRefundsRequireExplicitUndo() throws {
        var ledger = settlementExample()
        let id = try fullSettlement(&ledger)
        XCTAssertThrowsError(try ledger.addRefund(expenseID: "lunch", cents: 1000, date: settlementDate))
        XCTAssertThrowsError(try ledger.deleteLedgerExpense(ledger.expenses[0]))
        var changed = ledger
        changed.expenses[0].cents += 100
        XCTAssertThrowsError(try changed.validated())
        changed = ledger; changed.expenses[0].paidByFriend = "Amy"
        XCTAssertThrowsError(try changed.validated())
        changed = ledger; changed.expenses[0].category = "交通"
        XCTAssertThrowsError(try changed.validated())
        changed = ledger; changed.expenses[0].note = "A note is safe to edit"
        XCTAssertNoThrow(try changed.validated())
        try ledger.undoSettlement(id: id)
        try ledger.addRefund(expenseID: "lunch", cents: 1000, date: settlementDate)
        XCTAssertEqual(ledger.spending(in: settlementDate), 5000)
        XCTAssertEqual(ledger.friendBalances[0].owed, 2500)
        _ = try ledger.validated()
    }

    func testRepaymentsAndRefundsAreIncludedInOutstandingNetBalance() throws {
        var ledger = settlementExample()
        try ledger.repay(expenseID: "lunch", shareID: "amy-lunch", cents: 1000, date: settlementDate)
        try ledger.addRefund(expenseID: "lunch", cents: 1000, date: settlementDate)
        XCTAssertEqual(ledger.friendBalances[0].owed, 1500)
        XCTAssertEqual(ledger.friendBalances[0].payable, 2500)
        let id = try fullSettlement(&ledger, payment: 1000)
        XCTAssertEqual(ledger.settlements.first { $0.id == id }?.transfer, -1000)
        XCTAssertEqual(ledger.friendBalances[0].owed, 0)
        XCTAssertEqual(ledger.friendBalances[0].payable, 0)
        XCTAssertEqual(ledger.spending(in: settlementDate), 5000)
    }

    func testLegacyPayerAndV5SettlementBackupRoundTrip() throws {
        var legacy = settlementExample()
        legacy.expenses = [legacy.expenses[0]]
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: LocalStore.encode(legacy)) as? [String: Any])
        object["version"] = 4; object.removeValue(forKey: "settlements")
        let migrated = try LocalStore.decode(JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(migrated.version, 6)
        XCTAssertNil(migrated.expenses[0].paidByFriend)
        XCTAssertEqual(migrated.friendBalances[0].owed, 3000)
        XCTAssertTrue(migrated.settlements.isEmpty)
        var ledger = settlementExample()
        let id = try fullSettlement(&ledger)
        ledger.tngNotices = [settlementNotice()]
        try ledger.linkSettlementPayment(settlementID: id, noticeID: "receipt")
        let restored = try LocalStore.decode(LocalStore.exportData(ledger))
        XCTAssertEqual(restored.expenses, ledger.expenses)
        XCTAssertEqual(restored.settlements, ledger.settlements)
        XCTAssertEqual(restored.friendBalances[0].owed, 0)
        XCTAssertEqual(restored.tngNotices[0].settlementID, id)
    }

    func testFriendPaidOwnershipModesKeepSpendingSeparateFromMyAccount() throws {
        for friendShare in [0, 500, 700, 1000] {
            let expense = Expense(merchant: "Purchase", cents: 1000, date: settlementDate,
                                  shares: [Share(name: "Amy", cents: friendShare)], paidByFriend: "Amy")
            let ledger = try Ledger(expenses: [expense]).validated()
            XCTAssertEqual(ledger.spending(in: settlementDate), 1000 - friendShare)
            XCTAssertEqual(ledger.friendBalances[0].payable, 1000 - friendShare)
            XCTAssertEqual(ledger.friendBalances[0].owed, 0)
            XCTAssertEqual(OverviewSnapshot(ledger: ledger, month: settlementDate).paid, 0)
        }
        XCTAssertEqual(try nonnegativeCents("0.00"), 0)
        XCTAssertThrowsError(try nonnegativeCents("-1"))
    }

    func testSettlementCannotReuseClassifiedReceiptAndLegacyFlowCannotReuseSettlement() throws {
        var ledger = settlementExample()
        let id = try fullSettlement(&ledger)
        var used = settlementNotice(id: "already-income")
        used.status = "income"
        ledger.tngNotices = [used, settlementNotice()]
        XCTAssertThrowsError(try ledger.linkSettlementPayment(settlementID: id, noticeID: "receipt", distinctConfirmed: true))
        ledger.tngNotices.removeAll { $0.id == used.id }
        try ledger.linkSettlementPayment(settlementID: id, noticeID: "receipt")
        ledger.tngNotices.append(settlementNotice(id: "second-notification"))
        XCTAssertThrowsError(try ledger.resolveTNGIncoming(id: "second-notification", purpose: "income", date: settlementDate, distinctConfirmed: true))
        XCTAssertEqual(ledger.tngNotices[1].status, "pending")
    }

    func testAutomaticSettlementPaymentNeverReplaysAfterLinkOrUndo() throws {
        var ledger = settlementExample()
        ledger.expenses = [ledger.expenses[2]]
        let item = ledger.friendDebtItems[0]
        let plan = try ledger.settlementPlan(friend: "amy", selected: [item.id], payment: 1500, date: settlementDate)
        let id = try ledger.confirmSettlement(plan)
        let body = "You have paid RM15.00 to AMY."
        let date = settlementDate.addingTimeInterval(86400)
        let result = try ledger.processTNGNotification(body: body, title: "DuitNow Payment", date: date, eventID: "settlement-bank-payment")
        let noticeID = try XCTUnwrap(result.noticeID)
        try ledger.linkSettlementPayment(settlementID: id, noticeID: noticeID, distinctConfirmed: true)
        _ = try ledger.processTNGNotification(body: body, title: "DuitNow Payment", date: date, eventID: "settlement-bank-payment")
        XCTAssertEqual(ledger.expenses.count, 1)
        XCTAssertEqual(ledger.tngNotices.count, 1)
        try ledger.undoSettlement(id: id)
        _ = try ledger.processTNGNotification(body: body, title: "DuitNow Payment", date: date, eventID: "settlement-bank-payment")
        XCTAssertEqual(ledger.expenses.count, 1)
        XCTAssertEqual(ledger.tngNotices.count, 1)
        XCTAssertEqual(ledger.spending(in: settlementDate), 1500)
    }

    func testSettlementEditFailureLeavesStoredLedgerUntouched() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = LocalStore(folder: folder)
        try store.change { $0 = settlementExample() }
        let loaded = try store.read()
        let plan = try loaded.settlementPlan(friend: "amy", selected: Set(loaded.friendDebtItems.map(\.id)), payment: 500, date: settlementDate)
        try store.change { try $0.confirmSettlement(plan, id: "stored-settlement") }
        let committed = try store.readSnapshot()
        XCTAssertThrowsError(try store.change { $0.expenses[0].cents += 100 })
        XCTAssertEqual(try store.readSnapshot().signature, committed.signature)
        XCTAssertEqual(try store.read().settlements.count, 1)
        XCTAssertEqual(try store.read().friendBalances[0].owed, 0)
        XCTAssertEqual(try store.read().spending(in: settlementDate), 5500)
    }

    func testSettlementBackupRejectsInvalidPaymentLinkAndIntegerOverflow() throws {
        var ledger = settlementExample()
        _ = try fullSettlement(&ledger)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: LocalStore.encode(ledger)) as? [String: Any])
        var records = try XCTUnwrap(object["settlements"] as? [[String: Any]])
        records[0]["transfer"] = Int.min
        object["settlements"] = records
        XCTAssertThrowsError(try LocalStore.decode(JSONSerialization.data(withJSONObject: object)))
        ledger.settlements[0].paymentNoticeID = "missing-bank-record"
        XCTAssertThrowsError(try ledger.validated())
    }

    func testSettlementCannotUseBalancesFromLaterRepaymentsOrRefunds() throws {
        var ledger = settlementExample()
        let repaymentDate = settlementDate.addingTimeInterval(86400)
        try ledger.repay(expenseID: "lunch", shareID: "amy-lunch", cents: 1000, date: repaymentDate)
        let selected = Set(ledger.friendDebtItems.map(\.id))
        XCTAssertThrowsError(try ledger.settlementPlan(friend: "amy", selected: selected, payment: 500, date: settlementDate))
        let plan = try ledger.settlementPlan(friend: "amy", selected: selected, payment: 500, date: repaymentDate)
        let id = try ledger.confirmSettlement(plan)
        ledger.tngNotices = [settlementNotice(cents: 500, kind: "transfer")]
        XCTAssertThrowsError(try ledger.linkSettlementPayment(settlementID: id, noticeID: "receipt"))
    }

    func testFriendPaidRefundTracksWhoReceivedCashWithoutChangingSpendingTwice() throws {
        for receivedByMe in [false, true] {
            var ledger = settlementExample()
            ledger.expenses = [ledger.expenses[1]] // RM20 drinks: my original share is RM10.
            try ledger.addRefund(expenseID: "drinks", cents: 400, date: settlementDate, receivedByMe: receivedByMe)
            XCTAssertEqual(ledger.spending(in: settlementDate), 800)
            // If I received the full RM4, I forward the friend's part as well as settling my own cost.
            XCTAssertEqual(ledger.friendBalances[0].payable, receivedByMe ? 1200 : 800)
            let item = ledger.friendDebtItems[0]
            let plan = try ledger.settlementPlan(friend: "amy", selected: [item.id], payment: abs(item.balance), date: settlementDate)
            try ledger.confirmSettlement(plan)
            XCTAssertEqual(ledger.friendBalances[0].payable, 0)
            XCTAssertEqual(ledger.spending(in: settlementDate), 800)
        }
    }

    func testManualIncomingRepaymentSettlesSelectedDebtWithoutOffsetOrIncome() throws {
        var ledger = try settlementExample().validated()
        let original = ledger.expenses
        let lunch = try XCTUnwrap(ledger.friendDebtItems.first { $0.expense.id == "lunch" })
        let plan = try ledger.repaymentPlan(friend: "amy", selected: [lunch.id], payment: 2000, date: settlementDate, direction: .incoming)
        XCTAssertEqual(plan.offset, 0)
        XCTAssertEqual(plan.transfer, 2000)
        let id = try ledger.confirmSettlement(plan)
        XCTAssertEqual(ledger.friendBalances[0].owed, 1000)
        XCTAssertEqual(ledger.friendBalances[0].payable, 2500, "Receiving a repayment must not offset unselected debts I owe")
        XCTAssertEqual(ledger.settlements[0].lines.map { $0.expense.id }, ["lunch"])
        XCTAssertEqual(ledger.expenses, original)
        XCTAssertEqual(ledger.spending(in: settlementDate), 5500)
        XCTAssertEqual(try ledger.ledgerSettlements(in: settlementDate).map(\.id), [id])
        XCTAssertTrue(ledger.tngNotices.isEmpty, "Manual entry must not fabricate income or a bank notification")
        let restored = try LocalStore.decode(LocalStore.encode(ledger))
        XCTAssertEqual(restored.settlements, ledger.settlements)
        XCTAssertEqual(restored.friendBalances[0].owed, 1000)
    }

    func testManualOutgoingPartialRepaymentLeavesOtherDebtsAndSpendingUnchanged() throws {
        var ledger = settlementExample()
        let original = ledger.expenses
        let drinks = try XCTUnwrap(ledger.friendDebtItems.first { $0.expense.id == "drinks" })
        let plan = try ledger.repaymentPlan(friend: "AMY", selected: [drinks.id], payment: 400, date: settlementDate, direction: .outgoing)
        XCTAssertEqual(plan.offset, 0)
        XCTAssertEqual(plan.transfer, -400)
        let id = try ledger.confirmSettlement(plan)
        XCTAssertEqual(ledger.friendDebtItems.first { $0.expense.id == "drinks" }?.balance, -600)
        XCTAssertEqual(ledger.friendDebtItems.first { $0.expense.id == "mine" }?.balance, -1500)
        XCTAssertEqual(ledger.friendBalances[0].owed, 3000)
        XCTAssertEqual(ledger.friendBalances[0].payable, 2100)
        XCTAssertEqual(ledger.expenses, original)
        XCTAssertEqual(ledger.spending(in: settlementDate), 5500)
        XCTAssertEqual(ledger.settlements[0].accountDirection, .outgoing)
        try ledger.undoSettlement(id: id)
        XCTAssertEqual(ledger.friendBalances[0].payable, 2500)
        XCTAssertTrue(try ledger.ledgerSettlements(in: settlementDate).isEmpty)
        XCTAssertEqual(ledger.expenses, original)
    }

    func testManualRepaymentRejectsWrongDirectionMixedDebtsOverpaymentAndInvalidDate() throws {
        let ledger = settlementExample()
        let lunch = try XCTUnwrap(ledger.friendDebtItems.first { $0.expense.id == "lunch" })
        let drinks = try XCTUnwrap(ledger.friendDebtItems.first { $0.expense.id == "drinks" })
        XCTAssertThrowsError(try ledger.repaymentPlan(friend: "amy", selected: [lunch.id], payment: 100, date: settlementDate, direction: .outgoing))
        XCTAssertThrowsError(try ledger.repaymentPlan(friend: "amy", selected: [drinks.id], payment: 100, date: settlementDate, direction: .incoming))
        XCTAssertThrowsError(try ledger.repaymentPlan(friend: "amy", selected: [lunch.id, drinks.id], payment: 100, date: settlementDate, direction: .incoming))
        XCTAssertThrowsError(try ledger.repaymentPlan(friend: "amy", selected: [drinks.id], payment: 1001, date: settlementDate, direction: .outgoing))
        XCTAssertThrowsError(try ledger.repaymentPlan(friend: "amy", selected: [lunch.id], payment: 0, date: settlementDate, direction: .incoming))
        XCTAssertThrowsError(try ledger.repaymentPlan(friend: "amy", selected: [], payment: 100, date: settlementDate, direction: .incoming))
        XCTAssertThrowsError(try ledger.repaymentPlan(friend: "other friend", selected: [lunch.id], payment: 100, date: settlementDate, direction: .incoming))
        XCTAssertThrowsError(try ledger.repaymentPlan(friend: "amy", selected: [lunch.id], payment: 100, date: Date(timeIntervalSince1970: 100), direction: .incoming))
        XCTAssertThrowsError(try ledger.repaymentPlan(friend: "amy", selected: [lunch.id], payment: 100, date: settlementDate, direction: .neutral))
    }

    func testManualRepaymentCannotConfirmSamePreviewOrPaymentIDTwice() throws {
        var ledger = settlementExample()
        let lunch = try XCTUnwrap(ledger.friendDebtItems.first { $0.expense.id == "lunch" })
        let plan = try ledger.repaymentPlan(friend: "amy", selected: [lunch.id], payment: 1000, date: settlementDate, direction: .incoming)
        try ledger.confirmSettlement(plan, id: "manual-repayment")
        XCTAssertThrowsError(try ledger.confirmSettlement(plan))
        let next = try ledger.repaymentPlan(friend: "amy", selected: [lunch.id], payment: 1000, date: settlementDate, direction: .incoming)
        XCTAssertThrowsError(try ledger.confirmSettlement(next, id: "manual-repayment"))
        XCTAssertEqual(ledger.settlements.count, 1)
        XCTAssertEqual(ledger.friendBalances[0].owed, 2000)
    }

    func testLinkedManualRepaymentAppearsOnceInLedgerAndCannotReusePayment() throws {
        var ledger = settlementExample()
        let lunch = try XCTUnwrap(ledger.friendDebtItems.first { $0.expense.id == "lunch" })
        let plan = try ledger.repaymentPlan(friend: "amy", selected: [lunch.id], payment: 500, date: settlementDate, direction: .incoming)
        let id = try ledger.confirmSettlement(plan)
        var rows = LedgerTimelineItem.grouped(expenses: ledger.expenses, transfers: [], settlements: ledger.settlements).flatMap(\.entries)
        XCTAssertEqual(rows.filter { $0.id == "settlement:" + id }.count, 1)
        ledger.tngNotices = [settlementNotice()]
        try ledger.linkSettlementPayment(settlementID: id, noticeID: "receipt")
        XCTAssertTrue(try ledger.ledgerSettlements(in: settlementDate).isEmpty)
        rows = LedgerTimelineItem.grouped(expenses: ledger.expenses, transfers: ledger.ledgerTNGTransfers(in: settlementDate), settlements: ledger.settlements).flatMap(\.entries)
        XCTAssertEqual(rows.count, 4, "Three original purchases plus one payment, with no duplicate manual row")
        XCTAssertFalse(rows.contains { $0.id == "settlement:" + id })
        XCTAssertEqual(rows.filter { $0.id == "tng:receipt" }.count, 1)
        let next = try ledger.repaymentPlan(friend: "amy", selected: [lunch.id], payment: 500, date: settlementDate, direction: .incoming)
        let nextID = try ledger.confirmSettlement(next)
        XCTAssertThrowsError(try ledger.linkSettlementPayment(settlementID: nextID, noticeID: "receipt"))
        try ledger.undoSettlement(id: nextID)
        try ledger.undoSettlement(id: id)
        rows = LedgerTimelineItem.grouped(expenses: ledger.expenses, transfers: ledger.ledgerTNGTransfers(in: settlementDate), settlements: ledger.settlements).flatMap(\.entries)
        XCTAssertEqual(rows.count, 4)
        XCTAssertEqual(ledger.tngNotices.count, 1)
        XCTAssertEqual(ledger.friendBalances[0].owed, 3000)
        XCTAssertEqual(ledger.spending(in: settlementDate), 5500)
    }

    func testAccountAmountDirectionUsesCashMovementRegardlessOfManualOrAutomaticSource() throws {
        for source in ["手动", "Apple Pay", "TNG", "Maybank"] {
            var expense = Expense(merchant: "Lunch", cents: 6000, source: source)
            XCTAssertEqual(expense.accountDirection, .outgoing)
            XCTAssertEqual(expense.accountDirection.formattedAmount(expense.cents), "−RM 60.00")
            expense.paidByFriend = "Amy"
            XCTAssertEqual(expense.accountDirection, .neutral)
            XCTAssertEqual(expense.accountDirection.formattedAmount(expense.cents), "RM 60.00")
        }
        for source in ["TNG", "Maybank", "手动"] {
            var notice = settlementNotice()
            notice.sourceBank = source
            XCTAssertEqual(notice.accountDirection, .incoming)
            XCTAssertEqual(tngSignedAmount(notice), "+RM 5.00")
            notice.kind = "transfer"
            XCTAssertEqual(notice.accountDirection, .outgoing)
            XCTAssertEqual(tngSignedAmount(notice), "−RM 5.00")
            notice.kind = "unknown"
            XCTAssertEqual(notice.accountDirection, .neutral)
            XCTAssertEqual(tngSignedAmount(notice), "RM 5.00")
        }
        var ledger = settlementExample()
        ledger.expenses[2].cents = 2000
        _ = try fullSettlement(&ledger, payment: 0)
        XCTAssertEqual(ledger.settlements[0].accountDirection, .neutral)
        XCTAssertEqual(ledger.settlements[0].accountDirection.formattedAmount(0), "RM 0.00")
        let rows = LedgerTimelineItem.grouped(expenses: [], transfers: [], settlements: ledger.settlements).flatMap(\.entries)
        XCTAssertEqual(rows.count, 1, "Offset is auditable in the ledger without pretending there was cash movement")
    }

    func testManualSettlementLedgerFiltersUsePaymentMonthAndOriginalDetails() throws {
        var ledger = settlementExample()
        let lunch = try XCTUnwrap(ledger.friendDebtItems.first { $0.expense.id == "lunch" })
        let date = settlementDate.addingTimeInterval(40 * 86400)
        let plan = try ledger.repaymentPlan(friend: "amy", selected: [lunch.id], payment: 500, date: date, direction: .incoming)
        let id = try ledger.confirmSettlement(plan)
        XCTAssertTrue(try ledger.ledgerSettlements(in: settlementDate).isEmpty)
        XCTAssertEqual(try ledger.ledgerSettlements(in: date, search: "Lunch").map(\.id), [id])
        XCTAssertEqual(try ledger.ledgerSettlements(in: date, search: "aMy", filter: LedgerFilter(category: "餐饮", source: "手动", minimum: "5", maximum: "5")).map(\.id), [id])
        XCTAssertTrue(try ledger.ledgerSettlements(in: date, filter: LedgerFilter(category: "交通")).isEmpty)
        XCTAssertTrue(try ledger.ledgerSettlements(in: date, filter: LedgerFilter(source: "TNG")).isEmpty)
        XCTAssertTrue(try ledger.ledgerSettlements(in: date, filter: LedgerFilter(minimum: "6")).isEmpty)
        XCTAssertThrowsError(try ledger.ledgerSettlements(in: date, filter: LedgerFilter(minimum: "6", maximum: "5")))
    }

    func testMonthKeyPreservesGregorianMonthAcrossTimeZonesAndBoundaries() throws {
        let parser = ISO8601DateFormatter()
        for zoneID in ["UTC", "Asia/Kuala_Lumpur", "America/New_York", "Pacific/Kiritimati"] {
            let zone = try XCTUnwrap(TimeZone(identifier: zoneID))
            let legacy = DateFormatter()
            legacy.locale = Locale(identifier: "en_US_POSIX")
            legacy.dateFormat = "yyyy-MM"
            legacy.timeZone = zone
            for instant in ["2025-12-31T16:00:00Z", "2026-01-01T00:00:00Z",
                            "2026-02-28T23:59:59Z", "2026-03-01T00:00:00Z",
                            "2026-03-08T07:00:00Z", "2026-11-01T06:00:00Z",
                            "2028-02-29T23:59:59Z"] {
                let date = try XCTUnwrap(parser.date(from: instant))
                XCTAssertEqual(monthKey(date, timeZone: zone), legacy.string(from: date), "\(zoneID): \(instant)")
            }
        }
    }

    func testNavigationIndexPreservesDebtsLinkedDetailsAndUndo() throws {
        var ledger = try settlementExample().validated()
        let id = try fullSettlement(&ledger)
        var index = LedgerNavigationIndex(ledger: ledger)
        for expense in ledger.expenses {
            let detail = try XCTUnwrap(index.detail(id: expense.id))
            XCTAssertEqual(detail.entry, expense)
            XCTAssertEqual(detail.settlements, ledger.settlements)
            XCTAssertEqual(detail.payableToPayer, ledger.payableToPayer(expense))
            for share in expense.shares {
                XCTAssertEqual(detail.shareBalances[share.id], ledger.outstanding(expense: expense, share: share))
            }
        }
        XCTAssertNil(index.detail(id: "missing"))
        try ledger.undoSettlement(id: id)
        index = LedgerNavigationIndex(ledger: ledger)
        XCTAssertEqual(index.detail(id: "drinks")?.payableToPayer, 1000)
        XCTAssertEqual(index.detail(id: "mine")?.payableToPayer, 1500)
        XCTAssertEqual(index.detail(id: "lunch")?.shareBalances["amy-lunch"], 3000)
        XCTAssertEqual(index.detail(id: "lunch")?.settlements.first?.active, false)
        ledger.expenses.removeAll { $0.id == "lunch" }
        XCTAssertNil(LedgerNavigationIndex(ledger: ledger).detail(id: "lunch"))
    }

    func testTimelineProjectionsReuseRowsAndPreserveFiltersPaymentsAndEdits() async throws {
        let worker = LedgerProjectionWorker()
        var ledger = try settlementExample().validated()
        _ = try fullSettlement(&ledger)
        ledger.tngNotices = [settlementNotice(id: "unlinked-transfer", cents: 200)]
        let query = LedgerTimelineQuery(revision: 1, month: settlementDate, search: "", filter: LedgerFilter(), provider: "all")
        let first = try await worker.timeline(ledger: ledger, month: settlementDate, query: query)
        XCTAssertEqual(first.personal, 5500)
        XCTAssertEqual(first.expenses, try ledger.filteredEntries(in: settlementDate, search: "", filter: LedgerFilter()))
        XCTAssertEqual(first.transfers, ledger.ledgerTNGTransfers(in: settlementDate))
        XCTAssertEqual(first.settlements, try ledger.ledgerSettlements(in: settlementDate))
        let ids = first.days.flatMap { $0.entries.map(\.id) }
        for _ in 0..<30 {
            let repeated = try await worker.timeline(ledger: ledger, month: settlementDate, query: query)
            XCTAssertEqual(repeated.days.flatMap { $0.entries.map(\.id) }, ids)
        }
        let builds = await worker.timelineBuildCount
        XCTAssertEqual(builds, 1, "Repeated navigation must not refilter, resort or regroup the ledger")
        let filtered = LedgerTimelineQuery(revision: 1, month: settlementDate, search: "Personal", filter: LedgerFilter(category: "购物"), provider: "手动")
        let subset = try await worker.timeline(ledger: ledger, month: settlementDate, query: filtered)
        XCTAssertEqual(subset.expenses.map(\.id), ["mine"])
        XCTAssertTrue(subset.transfers.isEmpty)
        let settlementID = ledger.settlements[0].id
        try ledger.undoSettlement(id: settlementID)
        ledger.expenses[2].cents = 1800
        let updated = LedgerTimelineQuery(revision: 2, month: settlementDate, search: "", filter: LedgerFilter(), provider: "all")
        let fresh = try await worker.timeline(ledger: ledger, month: settlementDate, query: updated)
        XCTAssertEqual(fresh.personal, 5800)
        XCTAssertTrue(fresh.settlements.isEmpty)
        XCTAssertEqual(fresh.expenses.first { $0.id == "mine" }?.cents, 1800)
    }

    @MainActor func testNavigationReadModelsInvalidateAfterChangesButIgnoreFeedback() async throws {
        let model = LedgerModel(previewLedger: try settlementExample().validated())
        let query = LedgerTimelineQuery(revision: model.ledgerRevision, month: settlementDate, search: "", filter: LedgerFilter(), provider: "all")
        let first = try await model.timeline(month: settlementDate, query: query)
        XCTAssertEqual(model.expenseDetail(id: "mine")?.payableToPayer, 1500)
        model.showSaved(message: "Saved")
        XCTAssertEqual(model.ledgerRevision, query.revision)
        let repeated = try await model.timeline(month: settlementDate, query: query)
        XCTAssertEqual(repeated.personal, first.personal)
        model.ledger.expenses[2].cents = 1900
        XCTAssertEqual(model.expenseDetail(id: "mine")?.payableToPayer, 1900)
        do {
            _ = try await model.timeline(month: settlementDate, query: query)
            XCTFail("An old query must not return stale rows after an edit")
        } catch is CancellationError { }
        let freshQuery = LedgerTimelineQuery(revision: model.ledgerRevision, month: settlementDate, search: "", filter: LedgerFilter(), provider: "all")
        let fresh = try await model.timeline(month: settlementDate, query: freshQuery)
        XCTAssertEqual(fresh.personal, 5900)
        model.ledger.expenses.removeAll { $0.id == "mine" }
        XCTAssertNil(model.expenseDetail(id: "mine"))
    }

    func testCancelledProjectionDoesNotPublishOrPopulateCache() async throws {
        let worker = LedgerProjectionWorker()
        let ledger = settlementExample()
        let query = LedgerTimelineQuery(revision: 1, month: settlementDate, search: "", filter: LedgerFilter(), provider: "all")
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await worker.timeline(ledger: ledger, month: settlementDate, query: query)
        }
        do { _ = try await task.value; XCTFail("Cancelled work must not return a projection") }
        catch is CancellationError { }
        let builds = await worker.timelineBuildCount
        XCTAssertEqual(builds, 0)
        do {
            _ = try await worker.timeline(ledger: ledger, month: shiftedMonth(settlementDate, by: 1), query: query)
            XCTFail("A query for a different month must not populate the cache")
        } catch is CancellationError { }
    }

    func testOverviewProjectionCachesAndInvalidatesItemCategoryTotals() async throws {
        let now = Date()
        let entry = Expense(merchant: "TNG purchase", cents: 3500, date: now, category: "其他", items: [
            ExpenseItem(name: "Lunch", cents: 1500, category: "餐饮"),
            ExpenseItem(name: "Supplies", cents: 2000, category: "购物")])
        var ledger = Ledger(expenses: [entry])
        let worker = LedgerProjectionWorker()
        let query = LedgerTimelineQuery(revision: 1, month: now, search: "", filter: LedgerFilter(), provider: "all")
        for _ in 0..<20 {
            let summary = try await worker.overview(ledger: ledger, month: now, query: query)
            XCTAssertEqual(summary.personal, 3500)
            XCTAssertEqual(summary.categoryTotals, ["餐饮": 1500, "购物": 2000])
            XCTAssertEqual(summary.entries.map(\.id), [entry.id])
        }
        let builds = await worker.overviewBuildCount
        XCTAssertEqual(builds, 1)
        ledger.expenses[0].items?[1].category = "账单"
        let changedQuery = LedgerTimelineQuery(revision: 2, month: now, search: "", filter: LedgerFilter(), provider: "all")
        let changed = try await worker.overview(ledger: ledger, month: now, query: changedQuery)
        XCTAssertEqual(changed.categoryTotals, ["餐饮": 1500, "账单": 2000])
        XCTAssertEqual(changed.personal, 3500)
        let changedBuilds = await worker.overviewBuildCount
        XCTAssertEqual(changedBuilds, 2)
    }

    func testPreparedFriendAndInboxIndexMatchesLedgerBeforeAndAfterSettlement() throws {
        var ledger = settlementExample()
        let date = settlementDate
        ledger.tngNotices = [
            TNGNotice(id: "income", body: "RM 3.00 received", title: "Received", date: date,
                      usesReceivedDate: true, kind: "incoming", status: "pending", cents: 300, party: "Employer"),
            TNGNotice(id: "pending", body: "RM 5.00 received", title: "Received", date: date,
                      usesReceivedDate: true, kind: "incoming", status: "pending", cents: 500, party: "Amy")]
        // Incoming notices must contain a sender before any accounting operation.
        // Validate the fixture so this test reaches the index/settlement assertions.
        ledger = try ledger.validated()
        try ledger.resolveTNGIncoming(id: "income", purpose: "income", friend: "", date: date, distinctConfirmed: false)
        func check(_ ledger: Ledger) {
            let index = LedgerNavigationIndex(ledger: ledger)
            XCTAssertEqual(index.debts.map(\.id), ledger.friendDebtItems.map(\.id))
            XCTAssertEqual(index.debts.map(\.balance), ledger.friendDebtItems.map(\.balance))
            XCTAssertEqual(index.friends.map(\.owed), ledger.friendBalances.map(\.owed))
            XCTAssertEqual(index.friends.map(\.payable), ledger.friendBalances.map(\.payable))
            XCTAssertEqual(index.friends.map(\.count), ledger.friendBalances.map(\.count))
            XCTAssertEqual(index.debts(friend: "AMY").map(\.id), ledger.friendDebtItems.filter { friendKey($0.friend) == "amy" }.map(\.id))
            XCTAssertEqual(index.incomingReviewCount, 1)
            XCTAssertEqual(index.confirmedIncome, 300)
            XCTAssertEqual(index.pendingNotices.map(\.id), ["pending"])
            XCTAssertEqual(index.notice(id: "income")?.status, "income")
            XCTAssertNil(index.notice(id: "missing"))
            XCTAssertEqual(index.notices.map(\.id), ["income", "pending"])
        }
        check(ledger)
        let plan = try ledger.settlementPlan(friend: "Amy", selected: Set(ledger.friendDebtItems.map(\.id)), payment: 500, date: date)
        let id = try ledger.confirmSettlement(plan)
        check(ledger)
        try ledger.undoSettlement(id: id)
        check(ledger)
    }

    @MainActor func testRapidRepeatedPaymentActionCommitsOnlyOnceAndClearsBusyState() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = LocalStore(folder: folder), worker = LedgerRefreshWorker(store: store)
        let fixture = settlementExample()
        try store.change { $0 = fixture }
        let model = LedgerModel()
        let expenseID = fixture.expenses[0].id, shareID = fixture.expenses[0].shares[0].id, date = Date()
        var completions = 0
        for _ in 0..<12 {
            model.perform(key: "repayment", using: worker, action: {
                try $0.repay(expenseID: expenseID, shareID: shareID, cents: 500, date: date)
            }, completion: { _ in completions += 1 })
        }
        XCTAssertTrue(model.isWorking("repayment"))
        await model.waitForOperation("repayment")
        XCTAssertFalse(model.isWorking("repayment"))
        XCTAssertEqual(completions, 1)
        XCTAssertEqual(model.ledger.expenses[0].shares[0].repayments.count, 1)
        XCTAssertEqual(model.ledger.expenses[0].shares[0].repaid, 500)
        XCTAssertEqual(model.ledger.expenses.reduce(0) { $0 + $1.personal }, 5500)
        XCTAssertEqual(model.ledger.expenses, try store.read().expenses)
        XCTAssertNil(model.error)
    }

    @MainActor func testOverlappingIndependentOperationsPublishLatestSnapshotAndRejectFailedWrite() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = LocalStore(folder: folder), worker = LedgerRefreshWorker(store: store)
        let fixture = settlementExample()
        try store.change { $0 = fixture }
        let model = LedgerModel()
        model.perform(key: "first", using: worker, action: { $0.expenses[0].note = "Lunch note" })
        model.perform(key: "second", using: worker, action: { $0.expenses[1].note = "Drinks note" })
        await model.waitForOperation("first"); await model.waitForOperation("second")
        XCTAssertEqual(model.ledger.expenses, try store.read().expenses)
        XCTAssertEqual(model.ledger.expenses[0].note, "Lunch note")
        XCTAssertEqual(model.ledger.expenses[1].note, "Drinks note")
        let saved = try LocalStore.encode(store.read())
        model.perform(key: "bad", using: worker, action: { ledger -> Void in
            ledger.expenses.removeAll()
            throw LedgerError.invalid("Rejected operation")
        })
        await model.waitForOperation("bad")
        XCTAssertFalse(model.isWorking("bad"))
        XCTAssertNotNil(model.error)
        XCTAssertEqual(try LocalStore.encode(store.read()), saved)
        XCTAssertEqual(model.ledger.expenses, try store.read().expenses)
    }

    func testCancelledBackgroundMutationDoesNotAlterStoredLedger() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = LocalStore(folder: folder), worker = LedgerRefreshWorker(store: store)
        let fixture = settlementExample()
        try store.change { $0 = fixture }
        let task = Task { () -> Bool in
            withUnsafeCurrentTask { $0?.cancel() }
            do { _ = try await worker.mutate { $0.expenses.removeAll() }; return false }
            catch is CancellationError { return true }
            catch { return false }
        }
        let cancelled = await task.value
        XCTAssertTrue(cancelled)
        XCTAssertEqual(try store.read().expenses, fixture.expenses)
    }

    @MainActor func testCancellationAfterCommitStillPublishesSavedRecord() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = LocalStore(folder: folder), worker = LedgerRefreshWorker(store: store)
        let fixture = settlementExample()
        try store.change { $0 = fixture }
        let model = LedgerModel()
        let task = Task {
            try await model.mutate({ ledger in
                ledger.expenses[0].note = "Committed before cancellation"
                withUnsafeCurrentTask { $0?.cancel() }
            }, using: worker)
        }
        try await task.value
        XCTAssertEqual(model.ledger.expenses, try store.read().expenses)
        XCTAssertEqual(model.expenseDetail(id: fixture.expenses[0].id)?.entry.note, "Committed before cancellation")
    }

    func testBackgroundBackupExportPreviewAndRestorePreserveExistingRecords() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = LocalStore(folder: folder), worker = LedgerRefreshWorker(store: store)
        let fixture = settlementExample()
        try store.change { $0 = fixture }
        let data = try await worker.exportBackup()
        let file = folder.appendingPathComponent("test-export.json")
        try data.write(to: file)
        let preview = try await worker.preview(url: file)
        XCTAssertEqual(preview.ledger.expenses, fixture.expenses)
        try store.change { $0.expenses[0].note = "Changed" }
        try await worker.restore(data: preview.data)
        XCTAssertEqual(try store.read().expenses, fixture.expenses)
        let backups = try await worker.backups()
        XCTAssertFalse(backups.isEmpty)
    }

    func testRepeatedIndexedDetailLookupsWithLargeLedgerPerformance() throws {
        let date = settlementDate
        let ledger = Ledger(expenses: (0..<20_000).map { Expense(id: "entry-\($0)", merchant: "Purchase", cents: 1000, date: date) })
        let index = LedgerNavigationIndex(ledger: ledger)
        measure(metrics: [XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric()]) {
            for i in 0..<1_000 {
                let detail = index.detail(id: "entry-\(i % 2 == 0 ? 19_999 : 0)")
                XCTAssertEqual(detail?.entry.cents, 1000)
            }
        }
    }

    func testOverviewSnapshotPreservesSplitsRefundsAndLocalMonthBoundaries() throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "Asia/Kuala_Lumpur"))
        let start = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-30T16:00:00Z"))
        let end = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-31T16:00:00Z"))
        var split = Expense(merchant: "Groceries", cents: 10000, date: start, category: "餐饮",
                            shares: [Share(name: "A", cents: 2500, repayments: [Repayment(cents: 500)], refundCents: 500)],
                            refunds: [RefundRecord(cents: 1500, date: start, personalCents: 1000, shares: [:])],
                            categoryAllocations: [CategoryAllocation(category: "餐饮", cents: 7000), CategoryAllocation(category: "购物", cents: 3000)])
        split.id = "split"
        split.refunds?[0].shares = [split.shares[0].id: 500]
        let later = Expense(merchant: "Dinner", cents: 2000, date: start.addingTimeInterval(3600), category: "餐饮")
        let previous = Expense(merchant: "Previous month", cents: 500, date: start.addingTimeInterval(-1), shares: [Share(name: "B", cents: 200)])
        let next = Expense(merchant: "Next month", cents: 700, date: end)
        var ledger = Ledger(expenses: [previous, split, next, later])
        let received = TNGNotice(body: "Incoming", title: "Bank", date: start, usesReceivedDate: false,
                                 kind: "incoming", status: "income", cents: 1000, party: nil, expenseID: nil)
        var ignored = received; ignored.id = "ignored"; ignored.status = "ignored"
        var duplicate = received; duplicate.id = "duplicate"; duplicate.status = "pending"; duplicate.possibleDuplicate = true
        var nextNotice = received; nextNotice.id = "next"; nextNotice.date = end
        ledger.tngNotices = [received, ignored, duplicate, nextNotice]
        let snapshot = OverviewSnapshot(ledger: ledger, month: start, timeZone: zone)
        XCTAssertEqual(snapshot.entries.map(\.id), [later.id, split.id])
        XCTAssertEqual(snapshot.recent, snapshot.entries)
        XCTAssertEqual(snapshot.personal, 8500)
        XCTAssertEqual(snapshot.paid, 12000)
        XCTAssertEqual(snapshot.refunded, 1500)
        XCTAssertEqual(snapshot.owed, 1700, "Outstanding friends' shares still include other months")
        XCTAssertEqual(snapshot.incoming, 1000)
        for category in ["餐饮", "购物"] {
            XCTAssertEqual(snapshot.categoryTotals[category], [split, later].reduce(0) { $0 + $1.personalAmount(category: category) })
        }
        XCTAssertEqual(snapshot.categoryTotals.values.reduce(0, +), snapshot.personal)
    }

    @MainActor func testOverviewCacheUpdatesAfterEditAndSwitchingMonths() async {
        let now = Date()
        let next = shiftedMonth(now, by: 1)
        let model = LedgerModel(previewLedger: Ledger(expenses: [Expense(merchant: "Lunch", cents: 1000, date: now)]))
        XCTAssertEqual(model.overview(in: now).personal, 1000)
        XCTAssertEqual(model.overview(in: next).personal, 0)
        model.ledger.expenses[0].cents = 1500
        XCTAssertEqual(model.overview(in: now).personal, 1500)
        model.ledger.expenses[0].date = next
        XCTAssertEqual(model.overview(in: now).personal, 0)
        XCTAssertEqual(model.overview(in: next).personal, 1500)
        await model.refresh() // Guide previews must never replace their sample with the real ledger.
        XCTAssertEqual(model.overview(in: next).personal, 1500)
    }

    func testBackgroundExpenseSavePreservesAutomaticLinksAndRejectsStaleEdits() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = LocalStore(folder: folder)
        let worker = LedgerRefreshWorker(store: store)
        try store.change { ledger in
            _ = try ledger.receiveTNG(body: "You have paid RM35.00 for Shop.", date: settlementDate, eventID: "async-items")
            ledger.merchantCategories[friendKey(ledger.expenses[0].merchant)] = "其他"
        }
        let before = try await worker.snapshot(postRecurring: false)
        let original = try XCTUnwrap(before.ledger.expenses.first)
        var edited = original
        edited.items = [ExpenseItem(name: "Lunch", cents: 1500, category: "餐饮"), ExpenseItem(name: "Supplies", cents: 2000, category: "购物")]
        edited.category = "餐饮"
        try await worker.saveExpense(edited, replacing: original, rememberCategory: true)
        let after = try await worker.snapshot(postRecurring: false)
        XCTAssertEqual(after.ledger.expenses, [edited])
        XCTAssertEqual(after.ledger.tngNotices, before.ledger.tngNotices)
        XCTAssertEqual(after.ledger.seenEvents, before.ledger.seenEvents)
        XCTAssertEqual(after.ledger.merchantCategories[friendKey(original.merchant)], "其他", "Item categories must not replace the merchant's default")
        XCTAssertEqual(after.ledger.spending(in: settlementDate), 3500)
        try store.change { $0.expenses[0].note = "Concurrent update" }
        do {
            try await worker.saveExpense(original, replacing: edited, rememberCategory: false)
            XCTFail("A background save must not overwrite a newer edit")
        } catch {
            XCTAssertEqual(try store.read().expenses[0].note, "Concurrent update")
            XCTAssertEqual(try store.read().expenses[0].items, edited.items)
        }
    }

    func testBackgroundExpenseSaveIsAtomicAndRejectsRepeatedIDs() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = LocalStore(folder: folder)
        let worker = LedgerRefreshWorker(store: store)
        var expense = Expense(id: "async-entry", merchant: "Shop", cents: 500, date: settlementDate)
        expense.items = [ExpenseItem(name: "Invalid sum", cents: 400, category: "购物")]
        do { try await worker.saveExpense(expense, replacing: nil, rememberCategory: false); XCTFail("Invalid items must not be committed") }
        catch { XCTAssertTrue(try store.read().expenses.isEmpty) }
        expense.items = [ExpenseItem(name: "Supplies", cents: 500, category: "购物")]
        try await worker.saveExpense(expense, replacing: nil, rememberCategory: false)
        do { try await worker.saveExpense(expense, replacing: nil, rememberCategory: false); XCTFail("Do not save the same entry twice") }
        catch { XCTAssertEqual(try store.read().expenses, [expense]) }
        var invalidEdit = expense; invalidEdit.cents = 600; invalidEdit.category = "购物"
        do { try await worker.saveExpense(invalidEdit, replacing: expense, rememberCategory: true); XCTFail("Invalid edit must not alter the saved purchase") }
        catch { XCTAssertEqual(try store.read().expenses, [expense]); XCTAssertTrue(try store.read().merchantCategories.isEmpty) }
    }

    func testBackgroundSettlementConfirmationRejectsDuplicateAndPreservesSpendingOnUndo() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = LocalStore(folder: folder)
        let worker = LedgerRefreshWorker(store: store)
        try store.change { $0 = settlementExample() }
        let before = try await worker.snapshot(postRecurring: false)
        let plan = try before.ledger.settlementPlan(friend: "amy", selected: Set(before.ledger.friendDebtItems.map(\.id)), payment: 200, date: settlementDate)
        let id = try await worker.confirmSettlement(plan, id: "async-settlement")
        XCTAssertEqual(id, "async-settlement")
        let after = try await worker.snapshot(postRecurring: false)
        XCTAssertEqual(after.ledger.settlements.count, 1)
        XCTAssertEqual(after.ledger.friendBalances[0].owed, 300)
        XCTAssertEqual(after.ledger.friendBalances[0].payable, 0)
        XCTAssertEqual(after.ledger.expenses, before.ledger.expenses)
        XCTAssertEqual(after.ledger.spending(in: settlementDate), 5500)
        do { _ = try await worker.confirmSettlement(plan, id: id); XCTFail("A repeated confirmation must not apply twice") }
        catch { XCTAssertEqual(try store.read().settlements.count, 1) }
        let remaining = Set(after.ledger.friendDebtItems.filter { $0.balance != 0 }.map(\.id))
        let next = try after.ledger.settlementPlan(friend: "amy", selected: remaining, payment: 300, date: settlementDate)
        do { _ = try await worker.confirmSettlement(next, id: id); XCTFail("A new plan must not reuse a committed ID") }
        catch { XCTAssertEqual(try store.read().friendBalances[0].owed, 300) }
        try store.change { try $0.undoSettlement(id: id) }
        let undone = try await worker.snapshot(postRecurring: false)
        XCTAssertEqual(undone.ledger.expenses, before.ledger.expenses)
        XCTAssertEqual(undone.ledger.friendBalances[0].owed, 3000)
        XCTAssertEqual(undone.ledger.friendBalances[0].payable, 2500)
        XCTAssertEqual(undone.ledger.spending(in: settlementDate), 5500)
    }

    func testBackgroundSnapshotsDetectChangesAndPreserveUnreadableLedger() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = LocalStore(folder: folder)
        let worker = LedgerRefreshWorker(store: store)
        try store.change { $0.expenses = [Expense(merchant: "Lunch", cents: 1000)] }
        let first = try await worker.snapshot(postRecurring: false)
        let same = try await worker.snapshot(postRecurring: false)
        XCTAssertEqual(first.signature, same.signature)
        XCTAssertEqual(first.ledger.expenses, same.ledger.expenses)
        try store.change { $0.expenses[0].cents = 1500 }
        let edited = try await worker.snapshot(postRecurring: false)
        XCTAssertNotEqual(first.signature, edited.signature)
        XCTAssertEqual(edited.ledger.expenses[0].cents, 1500)
        let file = folder.appendingPathComponent("ledger.json")
        let corrupt = Data("unreadable ledger".utf8)
        try corrupt.write(to: file)
        do { _ = try await worker.snapshot(postRecurring: true); XCTFail("Must report unreadable data") }
        catch { XCTAssertEqual(try Data(contentsOf: file), corrupt) }
    }

    @MainActor func testOpeningLogoResolvesFromCompiledAssetCatalog() {
        XCTAssertNotNil(UIImage(named: "YueJiLogo"))
    }

    func testLanguageSwitchTranslatesLegacyLabelsWithoutChangingSourceIdentity() {
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: "appLanguage")
        defer {
            if let previous { defaults.set(previous, forKey: "appLanguage") }
            else { defaults.removeObject(forKey: "appLanguage") }
        }
        let legacyReason = "与已有账目的金额、商户和时间相近，请核对是否同一笔。"
        let source = notificationProvider(sourceApp: nil, title: "", body: "")
        for code in ["en", "ms"] {
            defaults.set(code, forKey: "appLanguage")
            XCTAssertEqual(sourceLabel(source), "Bank / TNG")
            XCTAssertEqual(source, "银行 / TNG")
            XCTAssertNil(localizedError(legacyReason).range(of: "[\\p{Han}]", options: .regularExpression))
            XCTAssertNil(localizedError("收款不能记为支出。").range(of: "[\\p{Han}]", options: .regularExpression))
            XCTAssertEqual(sourceLabel("Public Bank"), "Public Bank")
            XCTAssertEqual(categoryLabel("自定义分类"), "自定义分类")
            XCTAssertEqual(localizedAppText("用户自己的备注"), "用户自己的备注")
        }
        defaults.set("zh", forKey: "appLanguage")
        XCTAssertEqual(sourceLabel(source), "银行 / TNG")
        XCTAssertEqual(localizedError(legacyReason), legacyReason)
    }

    @MainActor func testSystemNotificationSoundIsInMainBundleAndDecodes() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "YueJiMoonDrop", withExtension: "wav"))
        let player = try AVAudioPlayer(contentsOf: url)
        XCTAssertEqual(player.duration, 1.08, accuracy: 0.002)
        XCTAssertEqual(player.numberOfChannels, 1)
        XCTAssertEqual(LedgerNotifications.automationSoundName, url.lastPathComponent)
    }

    func testRecoveryAfterCommitDoesNotPostAgain() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = LocalStore(folder: folder)
        let inbox = AutomationInbox(folder: folder.appendingPathComponent("AutomationInbox"))
        let delivery = AutomationDelivery(kind: "notification", body: "You have paid RM11.00 to HOW HAN ENG.", title: "DuitNow Payment")
        try inbox.save(delivery)
        _ = try store.change { try $0.applyDelivery(delivery) }
        // Simulate termination after commit but before inbox cleanup, then relaunch.
        let retained = try XCTUnwrap(AutomationInbox(folder: inbox.folder).pending().first)
        _ = try LocalStore(folder: folder).change { try $0.applyDelivery(retained) }
        let ledger = try store.read()
        XCTAssertEqual(ledger.expenses.count, 1)
        XCTAssertEqual(ledger.expenses[0].cents, 1100)
        XCTAssertEqual(ledger.expenses[0].date.timeIntervalSince1970, delivery.receivedAt.timeIntervalSince1970, accuracy: 1)
        XCTAssertTrue(ledger.tngNotices[0].usesReceivedDate)
        XCTAssertTrue(ledger.seenEvents.contains(delivery.marker))
        try inbox.remove(retained)
        XCTAssertTrue(try inbox.pending().isEmpty)
    }

    func testFailedLedgerWriteRetainsInputAndManualRetryRecovers() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("ledger.json")
        try Data("temporarily unreadable ledger".utf8).write(to: file)
        let store = LocalStore(folder: folder)
        let inbox = AutomationInbox(folder: folder.appendingPathComponent("AutomationInbox"))
        let recovery = AutomationRecovery(store: store, inbox: inbox, sendsNotifications: false)
        let delivery = AutomationDelivery(kind: "notification", body: "You have paid RM11.00 for Cafe.", title: "Payment")
        do { _ = try await recovery.submit(delivery); XCTFail("Expected a storage error") }
        catch {
            // Check the stable recovery error, not text translated for the current UI language.
            guard case LedgerError.invalid(let message) = error else {
                XCTFail("Expected a retained-input recovery error, got: \(error)")
                return
            }
            XCTAssertTrue(message.hasPrefix("交易输入已暂存，等待重试，尚未确认入账："))
        }
        let pending = try XCTUnwrap(inbox.pending().first)
        XCTAssertEqual(pending.id, delivery.id)
        XCTAssertEqual(pending.attempts, 1)
        XCTAssertNotNil(pending.lastError)
        var paused = pending; paused.attempts = 3; paused.lastAttempt = nil
        try inbox.save(paused)
        try LocalStore.encode(Ledger()).write(to: file)
        _ = await recovery.retryPending()
        XCTAssertEqual(try inbox.pending().count, 1)
        XCTAssertTrue(try store.read().expenses.isEmpty)
        let error = await recovery.retryPending(manual: true)
        XCTAssertNil(error)
        XCTAssertTrue(try inbox.pending().isEmpty)
        XCTAssertEqual(try store.read().expenses.count, 1)
    }

    func testThreeSourcesUseSameIdempotentIntake() throws {
        var ledger = Ledger(); let now = Date()
        let inputs = [
            AutomationDelivery(kind: "notification", body: "You have paid RM11.00 to HOW HAN ENG.", title: "DuitNow Payment", date: now),
            AutomationDelivery(kind: "notification", body: "Your transfer of RM0.01 to TEST PERSON is SUCCESSFUL.", title: "Transaction Notice", date: now),
            AutomationDelivery(kind: "applePay", date: now, amount: 15, merchant: "Apple Cafe", currency: "MYR")
        ]
        for input in inputs { XCTAssertTrue(try ledger.applyDelivery(input).shouldNotify) }
        for input in inputs { _ = try ledger.applyDelivery(input) }
        XCTAssertEqual(ledger.expenses.count, 2)
        XCTAssertEqual(ledger.tngNotices.count, 2)
        XCTAssertEqual(ledger.spending(in: now), 2600)
        XCTAssertEqual(ledger.tngNotices.last?.status, "transfer")
    }

    func testFailedConversionDoesNotCommitDeliveryMarker() throws {
        var ledger = Ledger()
        let input = AutomationDelivery(kind: "applePay", date: Date(), amount: 10, merchant: "Foreign Cafe", currency: "SGD")
        XCTAssertThrowsError(try ledger.applyDelivery(input))
        XCTAssertFalse(ledger.seenEvents.contains(input.marker))
        XCTAssertTrue(ledger.expenses.isEmpty)
        ledger.rates["SGD"] = RateQuote(value: 3, date: Date(), source: "test")
        _ = try ledger.applyDelivery(input)
        _ = try ledger.applyDelivery(input)
        XCTAssertEqual(ledger.expenses.count, 1)
        XCTAssertEqual(ledger.expenses[0].cents, 3000)
    }

    func testNotificationVariantsAndUncertainTextAreRetainedSafely() throws {
        XCTAssertEqual(parseTNG("You have paid RM1,234.50 to CAFE", title: "Payment")?.cents, 123450)
        XCTAssertEqual(parseTNG("You have paid RM11.00 for CAFE", title: "DuitNow Payment")?.party, "CAFE")
        XCTAssertNil(parseTNG("You have paid RM1,23.50 to CAFE", title: "Payment"))
        var ledger = Ledger()
        let unknown = AutomationDelivery(kind: "notification", body: "Purchase MYR12.00 at NEW SHOP", title: "HLB Transaction")
        XCTAssertNotNil(try ledger.applyDelivery(unknown).noticeID)
        XCTAssertTrue(ledger.expenses.isEmpty)
        let points = AutomationDelivery(kind: "notification", body: "You've received 11 points from your transaction!", title: "You've just earned 11 points!")
        XCTAssertFalse(try ledger.applyDelivery(points).shouldNotify)
        XCTAssertEqual(ledger.tngNotices.count, 1)
    }

    func testAutoDebitScreenshotRecordsOnceAcrossNotificationLayouts() throws {
        let body = "You have paid RM11.90 for Apple Services."
        let title = "Auto-Debit Payment"
        XCTAssertEqual(parseTNG(body, title: title)?.party, "Apple Services")
        for (input, heading) in [(body, ""), (body, title), (title + "\n" + body, ""), (title + " " + body, "TNG eWallet")] {
            var ledger = Ledger()
            let delivery = AutomationDelivery(kind: "notification", body: input, title: heading,
                                              date: Date(timeIntervalSince1970: 1_700_000_000))
            XCTAssertNotNil(try ledger.applyDelivery(delivery).expenseID)
            _ = try ledger.applyDelivery(delivery)
            XCTAssertEqual(ledger.expenses.count, 1)
            XCTAssertEqual(ledger.expenses.first?.merchant, "Apple Services")
            XCTAssertEqual(ledger.expenses.first?.cents, 1190)
            XCTAssertEqual(ledger.tngNotices.first?.status, "recorded")
            XCTAssertEqual(ledger.automationEvents.first?.outcome, "saved")
        }
        for invalid in ["Your auto-debit payment of RM11.90 is scheduled for tomorrow.",
                        body + " Payment failed.",
                        "You have paid USD11.90 for Apple Services.",
                        "You have paid RM11.90 for Apple Services. Balance RM50.00"] {
            var ledger = Ledger()
            _ = try ledger.processTNGNotification(body: invalid, title: title, date: nil, eventID: nil)
            XCTAssertTrue(ledger.expenses.isEmpty)
        }
    }

    func testScreenshotPaymentTransferAndPoints() throws {
        var ledger = Ledger()
        let payment = try ledger.processTNGNotification(body: "You have paid RM11.00 to HOW HAN ENG.", title: "DuitNow Payment", date: Date(), eventID: nil)
        XCTAssertTrue(payment.accepted)
        XCTAssertNotNil(payment.expenseID)
        XCTAssertEqual(ledger.expenses.first?.cents, 1100)
        XCTAssertEqual(ledger.expenses.first?.merchant, "HOW HAN ENG")
        let transfer = try ledger.processTNGNotification(body: "RM 9.80 has been successfully transferred to TEOH JUN HONG.", title: "Transfer Successful.", date: Date(), eventID: nil)
        XCTAssertTrue(transfer.accepted)
        XCTAssertNil(transfer.expenseID)
        XCTAssertNotNil(transfer.noticeID)
        let points = try ledger.processTNGNotification(body: "You've received 11 points from your transaction! Use them now to redeem great rewards.", title: "You've just earned 11 points!", date: Date(), eventID: nil)
        XCTAssertFalse(points.accepted)
        XCTAssertNil(points.noticeID)
        XCTAssertEqual(ledger.expenses.count, 1)
        XCTAssertEqual(ledger.tngNotices.count, 2)
    }

    func testPointsFilterPreservesMoneyNotifications() throws {
        for title in ["", "You've just earned 11 points!", "TNG eWallet"] {
            let body = "You’ve received 11 points from your transaction!"
            XCTAssertTrue(isNonTransactionNotification(body, title: title))
            XCTAssertFalse(shouldReviewFinancialNotification(body, title: title))
        }
        for body in ["Cashback of RM10.00 credited to your account.",
                     "Payment of RM11.00 successful. You've received 11 points.",
                     "Your purchase of USD10.00 was completed. You received 11 points."] {
            XCTAssertFalse(isNonTransactionNotification(body, title: ""))
            XCTAssertTrue(shouldReviewFinancialNotification(body, title: ""))
        }
    }

    func testCombinedTitleBodyAndCaseVariants() throws {
        let parsed = try XCTUnwrap(parseFinancialNotification("DuitNow Payment\nYou have paid RM11.00 to HOW HAN ENG."))
        XCTAssertEqual(parsed.cents, 1100)
        XCTAssertEqual(parsed.party, "HOW HAN ENG")
        XCTAssertEqual(parseTNG("you have paid RM11.00 to HOW HAN ENG.", title: "DuitNow   Payment")?.kind, "payment")
        XCTAssertNil(parseFinancialNotification("Offer\nYou have paid RM11.00 to HOW HAN ENG."))
        XCTAssertNil(parseFinancialNotification("DuitNow Payment\nPayment failed RM11.00"))
    }

    func testFixedShortcutIDDoesNotHideDifferentTransactions() throws {
        var ledger = Ledger(); let now = Date()
        _ = try ledger.receiveTNG(body: "RM 9.80 has been successfully transferred to TEOH JUN HONG.", title: "Transfer Successful.", date: now, eventID: "TNG")
        _ = try ledger.receiveTNG(body: "You have paid RM11.00 to HOW HAN ENG.", title: "DuitNow Payment", date: now, eventID: "TNG")
        _ = try ledger.receiveTNG(body: "You have paid RM12.00 to HOW HAN ENG.", title: "DuitNow Payment", date: now, eventID: "TNG")
        XCTAssertEqual(ledger.expenses.map(\.cents), [1100, 1200])
        _ = try ledger.receiveTNG(body: "You have paid RM12.00 to HOW HAN ENG.", title: "DuitNow Payment", date: now, eventID: "TNG")
        XCTAssertEqual(ledger.expenses.count, 2)
        XCTAssertEqual(ledger.tngNotices.count, 3)
    }

    func testExcludeReopenReconfirmPreservesNoteWithoutAutomaticSpending() throws {
        var ledger = Ledger(); let now = Date()
        _ = try ledger.receiveTNG(body: "You have paid RM11.00 to HOW HAN ENG.", title: "DuitNow Payment", date: now, eventID: "restore-note")
        let id = try XCTUnwrap(ledger.tngNotices.first?.id)
        try ledger.setNoticeNote(id: id, note: "午餐")
        XCTAssertEqual(ledger.expenses.first?.note, "午餐")
        try ledger.excludeTNG(id: id)
        XCTAssertEqual(ledger.spending(in: now), 0)
        _ = try ledger.receiveTNG(body: "You have paid RM11.00 to HOW HAN ENG.", title: "DuitNow Payment", date: now, eventID: "restore-note")
        XCTAssertTrue(ledger.expenses.isEmpty)
        try ledger.reopenExcludedNotice(id: id)
        XCTAssertEqual(ledger.tngNotices[0].status, "pending")
        XCTAssertNil(ledger.tngNotices[0].expenseID)
        XCTAssertTrue(ledger.expenses.isEmpty)
        try ledger.confirmTNGExpense(id: id, merchant: "HOW HAN ENG", cents: 1100, date: now, category: "餐饮")
        XCTAssertEqual(ledger.spending(in: now), 1100)
        XCTAssertEqual(ledger.expenses.first?.note, "午餐")
        XCTAssertThrowsError(try ledger.confirmTNGExpense(id: id, merchant: "HOW HAN ENG", cents: 1100, date: now, category: "餐饮"))
        let restored = try LocalStore.decode(LocalStore.encode(ledger))
        XCTAssertEqual(restored.tngNotices.first?.note, "午餐")
        XCTAssertEqual(restored.expenses.count, 1)
    }

    func testBankTransferNotesAndExclusionCanBeReopened() throws {
        var ledger = Ledger()
        _ = try ledger.receiveTNG(body: "Your transfer of RM0.01 to TEST PERSON is SUCCESSFUL.", title: "Transaction Notice", date: Date(), eventID: nil)
        let id = try XCTUnwrap(ledger.tngNotices.first?.id)
        try ledger.setNoticeNote(id: id, note: "还朋友的钱")
        XCTAssertTrue(ledger.expenses.isEmpty)
        try ledger.excludeTNG(id: id)
        try ledger.reopenExcludedNotice(id: id)
        XCTAssertEqual(ledger.tngNotices[0].status, "transfer")
        XCTAssertEqual(try LocalStore.decode(LocalStore.encode(ledger)).tngNotices[0].note, "还朋友的钱")
        XCTAssertThrowsError(try ledger.setNoticeNote(id: id, note: String(repeating: "x", count: 2001)))
        XCTAssertEqual(ledger.tngNotices[0].note, "还朋友的钱")
    }

    func testReopeningLinkedExclusionRequiresUndoingResolution() throws {
        var ledger = Ledger()
        _ = try ledger.receiveTNG(body: "You have paid RM11.00 for Cafe.", date: Date(), eventID: nil)
        let id = ledger.tngNotices[0].id
        try ledger.excludeTNG(id: id)
        ledger.tngNotices[0].resolution = "duplicate"
        XCTAssertThrowsError(try ledger.reopenExcludedNotice(id: id))
        XCTAssertEqual(ledger.tngNotices[0].status, "ignored")
    }

    @MainActor func testBundledFeedbackSoundsDecodeWithoutPlaying() throws {
        for name in ["LaunchChime", "SavedChime", "GoalChime", "DeleteCue", "RestoreCue", "DepositCue"] {
            let asset = try XCTUnwrap(NSDataAsset(name: name))
            let player = try AVAudioPlayer(data: asset.data)
            XCTAssertGreaterThan(player.duration, 0.15)
            XCTAssertLessThan(player.duration, name == "LaunchChime" ? 1.7 : 1.2)
            XCTAssertEqual(player.numberOfChannels, 1)
        }
    }

    func testUndoRestoresWholeEntriesAndPreservesNewWrites() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = LocalStore(folder: folder)
        let now = Date()
        let shared = Expense(merchant: "Dinner", cents: 6000, date: now.addingTimeInterval(-3600),
                             shares: [Share(name: "Amy", cents: 3000)], receiptSummary: "Dinner receipt")
        try store.change { ledger in
            ledger.expenses = [shared, Expense(merchant: "Coffee", cents: 500)]
            try ledger.repay(expenseID: shared.id, shareID: shared.shares[0].id, cents: 1000, date: now)
            try ledger.addRefund(expenseID: shared.id, cents: 200, date: now)
        }
        let deleted = try store.read().expenses
        for entry in deleted { try store.change { try $0.deleteExpense(entry) } }
        let newEntry = Expense(merchant: "New purchase", cents: 700)
        try store.change { $0.expenses.append(newEntry) }
        try store.change { try $0.restoreDeletedExpenses(deleted) }
        let reopened = try LocalStore(folder: folder).read()
        XCTAssertEqual(Set(reopened.expenses.map(\.id)), Set(deleted.map(\.id) + [newEntry.id]))
        for entry in deleted { XCTAssertEqual(reopened.expenses.first { $0.id == entry.id }, entry) }
        XCTAssertEqual(reopened.friendBalances.first?.owed, deleted[0].shares[0].owed)
    }

    func testUndoConflictIsAtomic() throws {
        let first = Expense(merchant: "First", cents: 1000)
        let second = Expense(merchant: "Second", cents: 2000)
        var ledger = Ledger(expenses: [second])
        XCTAssertThrowsError(try ledger.restoreDeletedExpenses([first, second]))
        XCTAssertEqual(ledger.expenses, [second])
        XCTAssertThrowsError(try ledger.restoreDeletedExpenses([first, first]))
        XCTAssertEqual(ledger.expenses, [second])
        var invalid = first; invalid.category = "missing-category"
        XCTAssertThrowsError(try ledger.restoreDeletedExpenses([invalid]))
        XCTAssertEqual(ledger.expenses, [second])
    }


    func testDeletePersistsAndUpdatesBalancesWithoutTouchingOtherEntries() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = LocalStore(folder: folder)
        let now = Date()
        let shared = Expense(merchant: "Dinner", cents: 6000, date: now.addingTimeInterval(-3600),
                             shares: [Share(name: "Amy", cents: 3000)])
        let keep = Expense(merchant: "Keep", cents: 500)
        try store.change { ledger in
            ledger.expenses = [shared, keep]
            try ledger.repay(expenseID: shared.id, shareID: shared.shares[0].id, cents: 1000, date: now)
            try ledger.addRefund(expenseID: shared.id, cents: 200, date: now)
        }
        let before = try store.read()
        let target = try XCTUnwrap(before.expenses.first)
        XCTAssertFalse(before.friendBalances.isEmpty)
        try store.change { try $0.deleteExpense(target) }
        let reopened = try LocalStore(folder: folder).read()
        XCTAssertEqual(reopened.expenses.map(\.id), [keep.id])
        XCTAssertEqual(reopened.expenses.reduce(0) { $0 + $1.personal }, 500)
        XCTAssertTrue(reopened.friendBalances.isEmpty)
        let snapshots = try store.backups().map { try LocalStore.decode(Data(contentsOf: $0)) }
        XCTAssertTrue(snapshots.contains { $0.expenses == before.expenses })
    }

    func testDeleteRejectsStaleRecordAndPreservesLatestData() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = LocalStore(folder: folder)
        try store.change { $0.expenses = [Expense(merchant: "Cafe", cents: 1000)] }
        let stale = try XCTUnwrap(store.read().expenses.first)
        try store.change { $0.expenses[0].merchant = "Corrected" }
        XCTAssertThrowsError(try store.change { try $0.deleteExpense(stale) })
        let current = try XCTUnwrap(store.read().expenses.first)
        XCTAssertEqual(current.merchant, "Corrected")
        try store.change { try $0.deleteExpense(current) }
        XCTAssertThrowsError(try store.change { try $0.deleteExpense(current) })
        XCTAssertTrue(try store.read().expenses.isEmpty)
    }

    func testDeleteKeepsAutomationDeduplicationAcrossReload() throws {
        var ledger = Ledger()
        let now = Date()
        XCTAssertTrue(try ledger.addPayment(amount: 12.50, merchant: "Cafe", currency: "MYR", date: now, eventID: "delete-regression"))
        let entry = try XCTUnwrap(ledger.expenses.first)
        ledger.postedRecurring.insert("rule:0")
        ledger.tngNotices = [TNGNotice(body: "Paid Cafe", title: "TNG", date: now,
            usesReceivedDate: true, kind: "payment", status: "recorded", cents: 1250,
            party: "Cafe", expenseID: entry.id)]
        try ledger.deleteExpense(entry)
        var restored = try LocalStore.decode(LocalStore.encode(ledger))
        XCTAssertFalse(try restored.addPayment(amount: 12.50, merchant: "Cafe", currency: "MYR", date: now, eventID: "delete-regression"))
        XCTAssertTrue(restored.expenses.isEmpty)
        XCTAssertTrue(restored.postedRecurring.contains("rule:0"))
        XCTAssertEqual(restored.tngNotices.first?.expenseID, entry.id)
        XCTAssertThrowsError(try restored.confirmTNGExpense(id: restored.tngNotices[0].id,
            merchant: "Cafe", cents: 1250, date: now, category: "其他"))
    }

    @MainActor func testGuideUsesValidIsolatedSampleLedger() throws {
        let sample = try GuideSample.ledger().validated()
        let preview = LedgerModel(previewLedger: sample)
        preview.reload()
        preview.change { $0.expenses.removeAll() }
        XCTAssertTrue(preview.isPreview)
        XCTAssertEqual(preview.ledger.expenses, sample.expenses)
        XCTAssertEqual(preview.ledger.tngNotices, sample.tngNotices)
    }
    func testSavingsPlanRoundingAndCompletion() {
        XCTAssertEqual(SavingsPlanMath.monthly(remaining: 10000, installments: 3), 3334)
        XCTAssertEqual(SavingsPlanMath.months(remaining: 10000, contribution: 3334), 3)
        XCTAssertEqual(SavingsPlanMath.monthly(remaining: 0, installments: 6), 0)
        XCTAssertEqual(SavingsPlanMath.months(remaining: 10000, contribution: 0), 0)
    }
    func testSavingsPlanCalendarEdges() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 1, day: 31)))
        let next = try XCTUnwrap(calendar.date(byAdding: .month, value: 1, to: now))
        XCTAssertEqual(SavingsPlanMath.installments(until: next, from: now, calendar: calendar), 1)
        XCTAssertEqual(SavingsPlanMath.installments(until: now, from: now, calendar: calendar), 0)
        let soon = try XCTUnwrap(calendar.date(byAdding: .day, value: 2, to: now))
        XCTAssertEqual(SavingsPlanMath.installments(until: soon, from: now, calendar: calendar), 1)
    }
    func testSavingsOldBackupAndPlanRoundTrip() throws {
        let old = Data(#"{"id":"old","name":"Laptop","target":300000,"entries":[]}"#.utf8)
        var goal = try JSONDecoder().decode(SavingsGoal.self, from: old)
        XCTAssertNil(goal.deadline); XCTAssertNil(goal.monthlyContribution)
        goal.deadline = Date(timeIntervalSince1970: 1_900_000_000)
        goal.monthlyContribution = 50000
        try goal.validate()
        let restored = try JSONDecoder().decode(SavingsGoal.self, from: JSONEncoder().encode(goal))
        XCTAssertEqual(restored, goal)
        XCTAssertTrue(restored.entries.isEmpty)
        goal.monthlyContribution = -1
        XCTAssertThrowsError(try goal.validate())
        goal.monthlyContribution = 1; goal.deadline = Date(timeIntervalSince1970: .infinity)
        XCTAssertThrowsError(try goal.validate())
    }
    func testMoney() throws {
        XCTAssertEqual(try toCents("18.50"), 1850)
        XCTAssertThrowsError(try toCents("1.234"))
        XCTAssertThrowsError(try toCents("-5"))
        XCTAssertEqual(equalShares(total: 1000, count: 2, includeMe: true), [334, 333])
        XCTAssertEqual(equalShares(total: 1000, count: 2, includeMe: false).reduce(0, +), 1000)
    }
    func testAutomaticPaymentDeduplicatesEvenAfterDeletion() throws {
        var ledger = Ledger()
        let date = Date()
        XCTAssertTrue(try ledger.addPayment(amount: 12.50, merchant: "Coffee", currency: "MYR", date: date, eventID: "bank-one"))
        XCTAssertFalse(try ledger.addPayment(amount: 12.50, merchant: "Coffee", currency: "MYR", date: date, eventID: "bank-one"))
        ledger.expenses = []
        XCTAssertFalse(try ledger.addPayment(amount: 12.50, merchant: "Coffee", currency: "MYR", date: date, eventID: "bank-one"))
        XCTAssertThrowsError(try ledger.addPayment(amount: 12, merchant: "Shop", currency: "USD", date: date, eventID: nil))
        XCTAssertThrowsError(try ledger.addPayment(amount: -.infinity, merchant: "Shop", currency: "MYR", date: date, eventID: nil))
    }
    func testPartialRepaymentDoesNotChangePersonalSpending() throws {
        let now = Date()
        let friend = Share(name: "Amy", cents: 4000)
        let expense = Expense(merchant: "Dinner", cents: 6000, date: now.addingTimeInterval(-3600), shares: [friend])
        var ledger = Ledger(expenses: [expense])
        try ledger.repay(expenseID: expense.id, shareID: friend.id, cents: 1500, date: now)
        XCTAssertEqual(ledger.expenses[0].personal, 2000)
        XCTAssertEqual(ledger.expenses[0].shares[0].owed, 2500)
        XCTAssertThrowsError(try ledger.repay(expenseID: expense.id, shareID: friend.id, cents: 3000, date: now))
        _ = try ledger.validated()
    }
    func testBackupRestoreAndCorruptFileProtection() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = LocalStore(folder: folder)
        XCTAssertTrue(try store.read().expenses.isEmpty)
        try store.change { $0.expenses.append(Expense(merchant: "Food", cents: 2500)) }
        XCTAssertEqual(try store.read().expenses.count, 1)
        let saved = try LocalStore.encode(store.read())
        try store.change { $0.expenses.append(Expense(merchant: "Fuel", cents: 5000)) }
        XCTAssertEqual(try store.backups().count, 2)
        try store.restore(saved)
        XCTAssertEqual(try store.read().expenses.count, 1)
        let file = folder.appendingPathComponent("ledger.json")
        try Data("corrupt".utf8).write(to: file)
        XCTAssertThrowsError(try store.change { $0.expenses = [] })
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "corrupt")
    }
    func testBackupRejectsOversplit() {
        let ledger = Ledger(expenses: [Expense(merchant: "Fuel", cents: 100, shares: [Share(name: "Amy", cents: 101)])])
        XCTAssertThrowsError(try ledger.validated())
    }
}

final class FeatureTests: XCTestCase {
    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c.date(from: DateComponents(year: y, month: m, day: d))!
    }
    func testMonthEndReturnsTo31AndLeapYear() throws {
        var r = RecurringExpense(name: "Rent", minor: 10000, start: date(2024, 1, 31)); r.timeZoneID = "GMT"
        XCTAssertEqual(r.occurrence(1), date(2024, 2, 29))
        XCTAssertEqual(r.occurrence(2), date(2024, 3, 31))
        r.start = date(2024, 2, 29); r.cycle = .yearly
        XCTAssertEqual(r.occurrence(1), date(2025, 2, 28))
        XCTAssertEqual(r.occurrence(4), date(2028, 2, 29))
    }
    func testRecurringIdempotenceAfterDeletionAndPause() throws {
        var r = RecurringExpense(name: "Rent", minor: 10000, start: date(2026, 1, 31)); r.timeZoneID = "GMT"; r.autoPost = true
        var ledger = Ledger(recurring: [r])
        try ledger.postDue(now: date(2026, 3, 31))
        XCTAssertEqual(ledger.expenses.count, 3)
        try ledger.postDue(now: date(2026, 3, 31)); XCTAssertEqual(ledger.expenses.count, 3)
        ledger.expenses.removeAll(); try ledger.postDue(now: date(2026, 3, 31)); XCTAssertTrue(ledger.expenses.isEmpty)
        ledger.recurring[0].active = false
        try ledger.postDue(now: date(2026, 5, 31)); XCTAssertTrue(ledger.expenses.isEmpty)
        ledger.resumeRule(r.id, now: date(2026, 6, 15))
        XCTAssertEqual(ledger.recurring[0].nextDate, date(2026, 6, 30))
        try ledger.postDue(now: date(2026, 6, 30)); XCTAssertEqual(ledger.expenses.count, 1)
    }
    func testWeeklyManualAndMissingFX() throws {
        var weekly = RecurringExpense(name: "Lunch", minor: 1000, start: date(2026, 1, 1), cycle: .weekly); weekly.timeZoneID = "GMT"
        var foreign = RecurringExpense(name: "Cloud", minor: 500, currency: "USD", start: date(2026, 1, 1)); foreign.autoPost = true; foreign.timeZoneID = "GMT"
        var ledger = Ledger(recurring: [weekly, foreign])
        try ledger.postDue(now: date(2026, 1, 15)); XCTAssertTrue(ledger.expenses.isEmpty)
        try ledger.postDue(now: date(2026, 1, 15), only: weekly.id, force: true); XCTAssertEqual(ledger.expenses.count, 3)
        ledger.rates["USD"] = RateQuote(value: 4, date: date(2026, 1, 15), source: "test")
        try ledger.postDue(now: date(2026, 1, 15)); XCTAssertEqual(ledger.expenses.last?.cents, 2000)
    }
    func testCurrencyPrecisionRateDirectionAndSnapshot() throws {
        let q = RateQuote(value: Decimal(string: "4.1234")!, date: Date(), source: "test")
        let fx = ForeignAmount(currency: "USD", minor: 1234, quote: q)
        XCTAssertEqual(try fx.myrCents(), 5088)
        XCTAssertThrowsError(try Currency.parse("100.50", code: "JPY"))
        XCTAssertEqual(try Currency.parse("100", code: "JPY"), 100)
        XCTAssertThrowsError(try parseRate("4abc")); XCTAssertThrowsError(try parseRate("0"))
        var ledger = Ledger(rates: ["USD": q])
        XCTAssertTrue(try ledger.addPayment(amount: 12.34, merchant: "Shop", currency: "USD", date: Date(), eventID: "fx001"))
        ledger.rates["USD"] = RateQuote(value: 5, date: Date(), source: "test")
        XCTAssertEqual(ledger.expenses[0].cents, 5088)
        XCTAssertEqual(ledger.expenses[0].foreign?.quote.value, q.value)
        _ = try ledger.validated()
    }
    func testV1MigrationAndV2RoundTrip() throws {
        let old = Data(#"{"version":1,"expenses":[],"budgets":{"2026-09":10000},"seenEvents":["old"]}"#.utf8)
        var ledger = try LocalStore.decode(old)
        XCTAssertEqual(ledger.version, 6); XCTAssertTrue(ledger.recurring.isEmpty); XCTAssertEqual(ledger.budgets["2026-09"], 10000)
        ledger.recurring = [RecurringExpense(name: "Phone", minor: 3000, start: Date())]
        ledger.rates["SGD"] = RateQuote(value: Decimal(string: "3.2")!, date: date(2026, 1, 1), source: "Manual")
        let restored = try LocalStore.decode(LocalStore.encode(ledger))
        XCTAssertEqual(restored.recurring[0].name, "Phone"); XCTAssertEqual(restored.rates["SGD"], ledger.rates["SGD"])
        XCTAssertTrue(restored.seenEvents.contains("old"))
    }
    func testWalletWithoutRateDoesNotConsumeDedupKey() throws {
        var ledger = Ledger()
        XCTAssertThrowsError(try ledger.addPayment(amount: 10, merchant: "Shop", currency: "SGD", date: Date(), eventID: "pending"))
        XCTAssertTrue(ledger.seenEvents.isEmpty)
        ledger.rates["SGD"] = RateQuote(value: 3, date: Date(), source: "test")
        XCTAssertTrue(try ledger.addPayment(amount: 10, merchant: "Shop", currency: "SGD", date: Date(), eventID: "pending"))
        XCTAssertEqual(ledger.expenses[0].cents, 3000)
    }
}

final class MonthSelectionTests: XCTestCase {
    func testBackdatedEntryStaysInViewedMonthAndClampsDay() throws {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 0)!
        let today = c.date(from: DateComponents(year: 2026, month: 3, day: 31, hour: 14, minute: 30))!
        let feb = shiftedMonth(today, by: -1, calendar: c)
        let result = dateForNewExpense(in: feb, now: today, calendar: c)
        XCTAssertEqual(c.component(.month, from: result), 2)
        XCTAssertEqual(c.component(.day, from: result), 28)
        XCTAssertEqual(c.component(.hour, from: result), 14)
        XCTAssertEqual(dateForNewExpense(in: today, now: today, calendar: c), today)
        let march = shiftedMonth(feb, by: 1, calendar: c)
        XCTAssertEqual(c.component(.month, from: march), 3)
        XCTAssertEqual(c.component(.day, from: march), 1)
        let jan = c.date(from: DateComponents(year: 2026, month: 1, day: 31))!
        XCTAssertEqual(c.component(.year, from: shiftedMonth(jan, by: -1, calendar: c)), 2025)
    }
}

final class AccountingToolsTests: XCTestCase {
    func testPartialAndFullRefundAllocateWithoutDoubleCounting() throws {
        let e = Expense(merchant: "Dinner", cents: 6000, date: Date().addingTimeInterval(-3600), shares: [Share(name: "Amy", cents: 4000)])
        var ledger = Ledger(expenses: [e])
        try ledger.addRefund(expenseID: e.id, cents: 1500, date: Date())
        XCTAssertEqual(ledger.expenses[0].personal, 1500)
        XCTAssertEqual(ledger.expenses[0].shares[0].owed, 3000)
        try ledger.addRefund(expenseID: e.id, cents: 4500, date: Date())
        XCTAssertEqual(ledger.expenses[0].personal, 0)
        XCTAssertEqual(ledger.expenses[0].shares[0].owed, 0)
        XCTAssertThrowsError(try ledger.addRefund(expenseID: e.id, cents: 1, date: Date()))
        _ = try ledger.validated()
        let decoded = try LocalStore.decode(LocalStore.encode(ledger))
        XCTAssertEqual(decoded.expenses[0].refunded, 6000)
    }
    func testRefundOfSettledShareCreatesPayableAndCanBeReturned() throws {
        let friend = Share(name: "Amy", cents: 1000)
        let e = Expense(merchant: "Food", cents: 2000, date: Date().addingTimeInterval(-86400), shares: [friend])
        var ledger = Ledger(expenses: [e])
        try ledger.repay(expenseID: e.id, shareID: friend.id, cents: 1000, date: Date().addingTimeInterval(-100))
        try ledger.addRefund(expenseID: e.id, cents: 2000, date: Date().addingTimeInterval(-10))
        XCTAssertEqual(ledger.expenses[0].shares[0].owed, -1000)
        XCTAssertEqual(ledger.friendBalances[0].payable, 1000)
        try ledger.returnToFriend(expenseID: e.id, shareID: friend.id, cents: 600, date: Date())
        XCTAssertEqual(ledger.expenses[0].shares[0].owed, -400)
        _ = try ledger.validated()
        XCTAssertThrowsError(try ledger.returnToFriend(expenseID: e.id, shareID: friend.id, cents: 401, date: Date()))
        let id = ledger.expenses[0].refunds![0].id
        XCTAssertThrowsError(try ledger.removeRefund(expenseID: e.id, refundID: id))
        XCTAssertEqual(ledger.expenses[0].refunded, 2000) // failed undo must be atomic
    }
    func testRefundPenniesAndLargeAmounts() throws {
        XCTAssertEqual(try allocateRefund(1, capacities: [0, 1, 1]).reduce(0, +), 1)
        XCTAssertEqual(try allocateRefund(3, capacities: [1, 1, 1]), [1, 1, 1])
        let allocation = try allocateRefund(10_000_000_000, capacities: [5_000_000_000, 5_000_000_000])
        XCTAssertEqual(allocation, [5_000_000_000, 5_000_000_000])
    }
    func testBatchRepaymentUsesOldestAndRejectsOverpaymentAtomically() throws {
        let old = Expense(merchant: "Old", cents: 1000, date: Date().addingTimeInterval(-86400), shares: [Share(name: " AMY ", cents: 700)])
        let new = Expense(merchant: "New", cents: 1000, date: Date().addingTimeInterval(-3600), shares: [Share(name: "amy", cents: 800)])
        var ledger = Ledger(expenses: [new, old])
        XCTAssertEqual(ledger.friendBalances.count, 1)
        try ledger.batchRepay(friend: "amy", cents: 1000, date: Date())
        XCTAssertEqual(ledger.expenses[1].shares[0].owed, 0)
        XCTAssertEqual(ledger.expenses[0].shares[0].owed, 500)
        XCTAssertEqual(ledger.expenses[0].shares[0].repayments[0].batchID, ledger.expenses[1].shares[0].repayments[0].batchID)
        XCTAssertThrowsError(try ledger.batchRepay(friend: "amy", cents: 501, date: Date()))
        XCTAssertEqual(ledger.friendBalances[0].owed, 500)
    }
    func testDuplicateReviewDoesNotMergeAndCanDismiss() throws {
        let first = Expense(merchant: "Coffee", cents: 1000, date: Date(), source: "Apple Pay")
        let second = Expense(merchant: "Coffee", cents: 1000, date: Date(), source: "手动")
        var ledger = Ledger(expenses: [first, second])
        let pairs = ledger.duplicatePairs()
        XCTAssertEqual(pairs.count, 1); XCTAssertEqual(ledger.expenses.count, 2)
        ledger.dismissedDuplicates.insert(pairs[0].id)
        XCTAssertTrue(ledger.duplicatePairs().isEmpty)
        let restored = try LocalStore.decode(LocalStore.encode(ledger))
        XCTAssertTrue(restored.duplicatePairs().isEmpty)
    }
    func testFuelEstimateDoesNotTouchLedger() throws {
        let estimate = FuelEstimate(distance: 100, litresPer100km: 8, pricePerLitre: Decimal(string: "2.05")!, parking: 500, toll: 300)
        XCTAssertEqual(try estimate.total(), 2440)
        XCTAssertEqual(equalShares(total: try estimate.total(), count: 2, includeMe: true).reduce(0, +), 1627)
        XCTAssertThrowsError(try FuelEstimate(distance: -1, litresPer100km: 8, pricePerLitre: 2, parking: 0, toll: 0).total())
    }
    func testPreviewExcludesPausedAndPostedAndReportsMissingFX() throws {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone.current
        let start = c.date(from: DateComponents(year: 2027, month: 1, day: 15))!
        let now = c.date(from: DateComponents(year: 2027, month: 1, day: 1))!
        let myr = RecurringExpense(name: "Rent", minor: 10000, start: start)
        var paused = RecurringExpense(name: "Paused", minor: 500, start: start); paused.active = false
        let usd = RecurringExpense(name: "Cloud", minor: 500, currency: "USD", start: start)
        var ledger = Ledger(recurring: [myr, paused, usd])
        let plans = ledger.upcoming(in: start, now: now)
        XCTAssertEqual(plans.count, 2); XCTAssertEqual(plans.compactMap(\.myr).reduce(0, +), 10000)
        ledger.postedRecurring.insert("\(myr.id):0")
        XCTAssertEqual(ledger.upcoming(in: start, now: now).count, 1)
        XCTAssertTrue(ledger.expenses.isEmpty)
    }
    func testAutomationLogsAreBoundedAndSurviveBackup() throws {
        var ledger = Ledger()
        for _ in 0..<110 { ledger.logAutomation(source: "Apple Pay", outcome: "saved") }
        XCTAssertEqual(ledger.automationEvents.count, 100)
        let restored = try LocalStore.decode(LocalStore.encode(ledger))
        XCTAssertEqual(restored.automationEvents.count, 100)
        let old = Data(#"{"version":2,"expenses":[],"budgets":{},"seenEvents":[],"rates":{},"recurring":[],"postedRecurring":[]}"#.utf8)
        XCTAssertTrue(try LocalStore.decode(old).automationEvents.isEmpty)
    }
}

final class FriendSpendingTests: XCTestCase {
    func testCategoryOverviewUsesSharesAndRefundsNotFullPayment() throws {
        let date = Date().addingTimeInterval(-3600)
        let a = Share(name: "Amy", cents: 3000)
        let b = Share(name: " AMY ", cents: 1000)
        let meal = Expense(merchant: "Dinner", cents: 6000, date: date, category: "餐饮", shares: [a])
        let fuel = Expense(merchant: "Trip", cents: 2000, date: date, category: "交通", shares: [b])
        var ledger = Ledger(expenses: [meal, fuel])
        try ledger.addRefund(expenseID: meal.id, cents: 2000, date: Date())
        let before = ledger.friendSpending(friend: "amy")
        XCTAssertEqual(before.net, 3000)
        XCTAssertEqual(before.categories["餐饮"], 2000)
        XCTAssertEqual(before.categories["交通"], 1000)
        XCTAssertEqual(before.refunds, 1000)
        try ledger.batchRepay(friend: "amy", cents: 500, date: Date())
        XCTAssertEqual(ledger.friendSpending(friend: "amy").net, before.net)
        XCTAssertEqual(ledger.friendSpending(friend: "amy").owed, 2500)
        XCTAssertEqual(ledger.friendSpending(friend: "other").net, 0)
        let otherMonth = shiftedMonth(date, by: -2)
        XCTAssertEqual(ledger.friendSpending(friend: "amy", month: otherMonth).net, 0)
    }
}

final class ConvenienceFeatureTests: XCTestCase {
    func testMerchantRuleRoundTripAndAutomaticCategory() throws {
        var ledger = Ledger()
        ledger.merchantCategories[friendKey("  ZUS   Coffee ")] = "娱乐"
        ledger = try LocalStore.decode(LocalStore.encode(ledger))
        XCTAssertTrue(try ledger.addPayment(amount: 12, merchant: "zus coffee", currency: "MYR", date: Date(), eventID: "rule-1"))
        XCTAssertEqual(ledger.expenses.last?.category, "娱乐")
        ledger.merchantCategories.removeAll()
        XCTAssertTrue(try ledger.addPayment(amount: 12, merchant: "zus coffee", currency: "MYR", date: Date(), eventID: "rule-2"))
        XCTAssertEqual(ledger.expenses.last?.category, "餐饮")
        XCTAssertEqual(ledger.expenses.first?.category, "娱乐")
    }
    func testOlderBackupHasNoRulesOrInventedBackupDate() throws {
        let data = try LocalStore.encode(Ledger())
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "merchantCategories"); object.removeValue(forKey: "backupCreatedAt")
        let ledger = try LocalStore.decode(JSONSerialization.data(withJSONObject: object))
        XCTAssertTrue(ledger.merchantCategories.isEmpty)
        XCTAssertNil(ledger.backupCreatedAt)
        XCTAssertNotNil(try LocalStore.decode(LocalStore.exportData(ledger)).backupCreatedAt)
    }
    func testStatementOnlySharesSelectedFriendAndSpendingMonth() throws {
        let now = Date()
        var ledger = Ledger()
        ledger.expenses = [
            Expense(merchant: "VISIBLE-MERCHANT", cents: 2000, date: now, shares: [Share(name: "James", cents: 1000, repayments: [Repayment(cents: 400)]), Share(name: "PRIVATE-FRIEND", cents: 500)]),
            Expense(merchant: "OTHER-MONTH", cents: 1000, date: shiftedMonth(now, by: -1), shares: [Share(name: "James", cents: 500)])
        ]
        let text = ledger.friendStatement(key: friendKey("James"), month: now)
        XCTAssertTrue(text.contains("VISIBLE-MERCHANT"))
        XCTAssertTrue(text.contains(money(600)))
        XCTAssertFalse(text.contains("PRIVATE-FRIEND"))
        XCTAssertFalse(text.contains("OTHER-MONTH"))
    }
    func testRecoveryCopySurvivesSnapshotRotationAndInvalidRestore() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = LocalStore(folder: folder)
        try store.change { $0.expenses.append(Expense(merchant: "Original", cents: 100)) }
        try store.restore(LocalStore.exportData(Ledger()))
        let recovery = try Data(contentsOf: store.recoveryFile)
        XCTAssertEqual(try LocalStore.decode(recovery).expenses.first?.merchant, "Original")
        for i in 0..<35 { try store.change { $0.budgets["2026-09"] = i + 1 } }
        XCTAssertEqual(try Data(contentsOf: store.recoveryFile), recovery)
        XCTAssertThrowsError(try store.restore(Data("bad".utf8)))
        XCTAssertEqual(try Data(contentsOf: store.recoveryFile), recovery)
        XCTAssertEqual(try store.backups().count, 30)
    }
}

final class Version16Tests: XCTestCase {
    func testCustomCategoryRenameKeepsReferencesAndRoundTrips() throws {
        var ledger = Ledger()
        var category = CustomCategory(name: "学费", icon: "book.fill", color: "blue")
        try ledger.saveCategory(category)
        ledger.expenses = [Expense(merchant: "University", cents: 5000, category: "学费")]
        var recurring = RecurringExpense(name: "Fees", minor: 5000, start: Date())
        recurring.category = "学费"; ledger.recurring = [recurring]
        ledger.merchantCategories["university"] = "学费"
        category.name = "教育"; try ledger.saveCategory(category)
        let copy = try LocalStore.decode(LocalStore.encode(ledger))
        XCTAssertEqual(copy.expenses.first?.category, "教育")
        XCTAssertEqual(copy.recurring.first?.category, "教育")
        XCTAssertEqual(copy.merchantCategories["university"], "教育")
        XCTAssertEqual(copy.customCategories.first?.icon, "book.fill")
        XCTAssertThrowsError(try ledger.deleteCategory(category.id))
        XCTAssertThrowsError(try ledger.saveCategory(CustomCategory(name: " 教育 ")))
        XCTAssertThrowsError(try ledger.saveCategory(CustomCategory(name: "餐饮")))
        XCTAssertEqual(categoryLabel("教育"), "教育")
    }
    func testCustomRefundOnlyTargetsChosenFriendAndRejectsOverAllocation() throws {
        let date = Date().addingTimeInterval(-60)
        let friend = Share(name: "James", cents: 1000, repayments: [Repayment(cents: 1000)])
        let other = Share(name: "Jason", cents: 500)
        var ledger = Ledger(expenses: [Expense(merchant: "Trip", cents: 2000, date: date, shares: [friend, other])])
        let id = ledger.expenses[0].id
        try ledger.addRefund(expenseID: id, cents: 400, date: Date(), custom: [friend.id: 400])
        XCTAssertEqual(ledger.expenses[0].personal, 500)
        XCTAssertEqual(ledger.expenses[0].shares[0].owed, -400)
        XCTAssertEqual(ledger.expenses[0].shares[1].owed, 500)
        _ = try ledger.validated()
        let before = try LocalStore.encode(ledger)
        XCTAssertThrowsError(try ledger.addRefund(expenseID: id, cents: 700, date: Date(), custom: [friend.id: 700]))
        XCTAssertThrowsError(try ledger.addRefund(expenseID: id, cents: 100, date: Date(), custom: ["owner": 99]))
        XCTAssertThrowsError(try ledger.addRefund(expenseID: id, cents: 100, date: Date(), custom: ["unknown": 100]))
        XCTAssertEqual(try LocalStore.encode(ledger), before)
    }
    func testMonthComparisonUsesPersonalNetAndRefundMonth() throws {
        let now = Date(), prior = shiftedMonth(now, by: -1)
        var ledger = Ledger(expenses: [Expense(merchant: "Old", cents: 2000, date: prior, category: "餐饮", shares: [Share(name: "James", cents: 1000)]), Expense(merchant: "New", cents: 300, date: now, category: "交通")])
        try ledger.addRefund(expenseID: ledger.expenses[0].id, cents: 200, date: now, custom: ["owner": 200])
        XCTAssertEqual(ledger.spending(in: prior), 800)
        XCTAssertEqual(ledger.spending(in: now), 300)
        XCTAssertEqual(ledger.spending(in: prior, category: "交通"), 0)
    }
    func testFiltersIntersectAndValidateAmountRange() throws {
        let date = Date()
        let ledger = Ledger(expenses: [Expense(merchant: "Shell", cents: 2000, date: date, category: "交通", source: "Apple Pay"), Expense(merchant: "Shell", cents: 3000, date: date, category: "交通"), Expense(merchant: "Old Shell", cents: 2000, date: shiftedMonth(date, by: -1), category: "交通", source: "Apple Pay")])
        let filter = LedgerFilter(category: "交通", source: "Apple Pay", minimum: "20", maximum: "20")
        XCTAssertEqual(try ledger.filteredEntries(in: date, search: "shell", filter: filter).count, 1)
        XCTAssertEqual(try ledger.filteredEntries(in: date, search: "missing", filter: filter).count, 0)
        XCTAssertThrowsError(try LedgerFilter(minimum: "30", maximum: "20").validate())
        XCTAssertThrowsError(try LedgerFilter(minimum: "oops").validate())
        XCTAssertNoThrow(try LedgerFilter(minimum: "0").validate())
    }
    func testTripDefaultsAndOldData() throws {
        var ledger = Ledger()
        ledger.tripDefaults = TripDefaults(consumption: "7.5", price: "2.05", companions: ["James", "Jason"], includeDriver: true)
        let copy = try LocalStore.decode(LocalStore.encode(ledger))
        XCTAssertEqual(copy.tripDefaults, ledger.tripDefaults)
        XCTAssertThrowsError(try TripDefaults(consumption: "7.5", price: "2.05", companions: ["James", " james "], includeDriver: true).validate())
        XCTAssertThrowsError(try TripDefaults(consumption: "101", price: "2.05", companions: [], includeDriver: true).validate())
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: LocalStore.encode(Ledger())) as? [String: Any])
        object.removeValue(forKey: "customCategories"); object.removeValue(forKey: "tripDefaults")
        let old = try LocalStore.decode(JSONSerialization.data(withJSONObject: object))
        XCTAssertTrue(old.customCategories.isEmpty); XCTAssertNil(old.tripDefaults)
    }
    func testCSVQuotesUnicodeFormulaAndSelectedMonth() throws {
        XCTAssertEqual(csvCell("a,\"b\"\nc"), "\"a,\"\"b\"\"\nc\"")
        XCTAssertEqual(csvCell("=SUM(A1)"), "\"'=SUM(A1)\"")
        XCTAssertEqual(csvCell("  @bad"), "\"'  @bad\"")
        let now = Date()
        let ledger = Ledger(expenses: [Expense(merchant: "中文,店", cents: 1000, date: now, shares: [Share(name: "=James", cents: 500)]), Expense(merchant: "OLDER-ONLY", cents: 2000, date: shiftedMonth(now, by: -1))])
        let expense = String(decoding: ledger.csv(month: now, splits: false), as: UTF8.self)
        XCTAssertTrue(expense.hasPrefix("\u{FEFF}")); XCTAssertTrue(expense.contains("中文,店")); XCTAssertFalse(expense.contains("OLDER-ONLY"))
        let split = String(decoding: ledger.csv(month: now, splits: true), as: UTF8.self)
        XCTAssertTrue(split.contains("'=James")); XCTAssertTrue(split.contains("\"5.00\""))
    }
}

final class TNGTests: XCTestCase {
    func testVerifiedSamplesAndUnknownFormats() {
        let payment = parseTNG("You have paid RM2.55 for MySiswaPlace.")
        XCTAssertEqual(payment?.cents, 255); XCTAssertEqual(payment?.party, "MySiswaPlace"); XCTAssertEqual(payment?.kind, "payment")
        let transfer = parseTNG("RM 0.01 has been successfully transferred to CHONG YONG EN.")
        XCTAssertEqual(transfer?.kind, "transfer"); XCTAssertEqual(transfer?.cents, 1)
        for text in ["Payment failed RM2.55", "You received RM2.55", "Reload successful RM50", "You have paid RM-2.55 for Shop.", "You have paid RM2.555 for Shop.", "Offer: You have paid RM2.55 for Shop."] { XCTAssertNil(parseTNG(text)) }
    }
    func testPaymentTransferUnknownAndRoundTrip() throws {
        var ledger = Ledger(); let now = Date()
        _ = try ledger.receiveTNG(body: "You have paid RM2.55 for MySiswaPlace.", date: nil, eventID: nil, now: now)
        _ = try ledger.receiveTNG(body: "RM 0.01 has been successfully transferred to CHONG YONG EN.", date: nil, eventID: nil, now: now)
        _ = try ledger.receiveTNG(body: "Reload successful RM50", date: nil, eventID: nil, now: now)
        XCTAssertEqual(ledger.expenses.count, 1); XCTAssertEqual(ledger.expenses[0].source, "TNG")
        XCTAssertEqual(ledger.spending(in: now), 255)
        XCTAssertEqual(ledger.tngNotices.map(\.status), ["recorded", "transfer", "pending"])
        XCTAssertTrue(ledger.tngNotices[0].usesReceivedDate)
        XCTAssertEqual(try LocalStore.decode(LocalStore.encode(ledger)).tngNotices.count, 3)
    }
    func testPossibleDuplicatePreservedAndCanConfirmDistinctPayment() throws {
        var ledger = Ledger(); let now = Date(); let body = "You have paid RM2.55 for MySiswaPlace."
        _ = try ledger.receiveTNG(body: body, date: now, eventID: nil)
        _ = try ledger.receiveTNG(body: body, date: now.addingTimeInterval(60), eventID: nil)
        XCTAssertEqual(ledger.expenses.count, 1); XCTAssertEqual(ledger.tngNotices.count, 2)
        let id = ledger.tngNotices[1].id
        XCTAssertTrue(ledger.tngNotices[1].possibleDuplicate)
        try ledger.confirmTNGExpense(id: id, merchant: "MySiswaPlace", cents: 255, date: now, category: "餐饮")
        XCTAssertEqual(ledger.expenses.count, 2)
        XCTAssertThrowsError(try ledger.confirmTNGExpense(id: id, merchant: "MySiswaPlace", cents: 255, date: now, category: "餐饮"))
        _ = try ledger.validated()
    }
    func testExplicitIDReplayAndExclusion() throws {
        var ledger = Ledger(); let now = Date(); let body = "You have paid RM2.55 for MySiswaPlace."
        _ = try ledger.receiveTNG(body: body, date: now, eventID: "receipt-1")
        _ = try ledger.receiveTNG(body: body, date: now.addingTimeInterval(90000), eventID: "receipt-1")
        XCTAssertEqual(ledger.tngNotices.count, 1)
        let id = ledger.tngNotices[0].id
        ledger.expenses[0].shares = [Share(name: "James", cents: 100)]
        XCTAssertThrowsError(try ledger.excludeTNG(id: id))
        XCTAssertEqual(ledger.expenses.count, 1)
        ledger.expenses[0].shares = []
        try ledger.excludeTNG(id: id)
        XCTAssertEqual(ledger.expenses.count, 0)
        XCTAssertEqual(ledger.tngNotices[0].status, "ignored")
        _ = try ledger.receiveTNG(body: body, date: now, eventID: "receipt-1")
        XCTAssertTrue(ledger.expenses.isEmpty)
    }
    func testEmptyBodyAndLegacyMigration() throws {
        var ledger = Ledger()
        XCTAssertThrowsError(try ledger.receiveTNG(body: " ", date: nil, eventID: nil))
        XCTAssertTrue(ledger.tngNotices.isEmpty)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: LocalStore.encode(ledger)) as? [String: Any])
        json.removeValue(forKey: "tngNotices")
        XCTAssertTrue(try LocalStore.decode(JSONSerialization.data(withJSONObject: json)).tngNotices.isEmpty)
    }
}


final class BudgetAlertTests: XCTestCase {
    func testThresholdUsesPersonalShareAndRefunds() {
        let now = Date()
        var ledger = Ledger()
        ledger.budgets[monthKey(now)] = 6000
        ledger.expenses = [Expense(merchant: "Dinner", cents: 10000, date: now,
                                   shares: [Share(name: "Amy", cents: 4000)])]
        XCTAssertEqual(BudgetAlertCandidate.make(ledger: ledger, now: now)?.spent, 6000)
        ledger.expenses[0].refunds = [RefundRecord(cents: 100, date: now, personalCents: 100, shares: [:])]
        XCTAssertNil(BudgetAlertCandidate.make(ledger: ledger, now: now))
    }
    func testNoBudgetOrHistoricalSpendingDoesNotAlert() {
        let now = Date()
        let previous = shiftedMonth(now, by: -1)
        var ledger = Ledger()
        ledger.expenses = [Expense(merchant: "Old purchase", cents: 99999, date: previous)]
        ledger.budgets[monthKey(previous)] = 100
        XCTAssertNil(BudgetAlertCandidate.make(ledger: ledger, now: now))
        ledger.budgets[monthKey(now)] = 100
        XCTAssertNil(BudgetAlertCandidate.make(ledger: ledger, now: now))
        ledger.expenses.append(Expense(merchant: "Today", cents: 99, date: now))
        XCTAssertNil(BudgetAlertCandidate.make(ledger: ledger, now: now))
        ledger.expenses[1].cents = 101
        XCTAssertEqual(BudgetAlertCandidate.make(ledger: ledger, now: now)?.budget, 100)
        ledger.budgets.removeValue(forKey: monthKey(now))
        XCTAssertNil(BudgetAlertCandidate.make(ledger: ledger, now: now))
    }
}


final class BudgetPercentageTests: XCTestCase {
    func testCustomPercentAndFractionalCentBoundary() {
        let now = Date()
        var ledger = Ledger()
        ledger.budgets[monthKey(now)] = 100001
        ledger.expenses = [Expense(merchant: "Test", cents: 80000, date: now)]
        XCTAssertNil(BudgetAlertCandidate.make(ledger: ledger, now: now, percent: 80))
        ledger.expenses[0].cents = 80001
        XCTAssertNotNil(BudgetAlertCandidate.make(ledger: ledger, now: now, percent: 80))
        XCTAssertNil(BudgetAlertCandidate.make(ledger: ledger, now: now, percent: 100))
        XCTAssertNil(BudgetAlertCandidate.make(ledger: ledger, now: now, percent: 0))
        XCTAssertNil(BudgetAlertCandidate.make(ledger: ledger, now: now, percent: 201))
        ledger.expenses[0].cents = 200002
        XCTAssertNotNil(BudgetAlertCandidate.make(ledger: ledger, now: now, percent: 200))
    }
}


final class PartialRepaymentRegressionTests: XCTestCase {
    func test1867PartialReceiptLeaves1467() throws {
        let now = Date()
        var ledger = Ledger()
        ledger.expenses = [Expense(merchant: "sandakan", cents: 1867, date: now.addingTimeInterval(-86400), shares: [Share(name: "ye", cents: 1867)])]
        try ledger.batchRepay(friend: "ye", cents: 400, date: now)
        XCTAssertEqual(ledger.friendBalances.first?.owed, 1467)
        XCTAssertEqual(ledger.expenses[0].shares[0].repaid, 400)
        let restored = try LocalStore.decode(LocalStore.encode(ledger))
        XCTAssertEqual(restored.friendSpending(friend: "ye", month: nil).owed, 1467)
    }
    func testFutureExpenseExplainsFailureAndCanBeCorrected() throws {
        let now = Date()
        var ledger = Ledger()
        ledger.expenses = [Expense(merchant: "sandakan", cents: 1867, date: shiftedMonth(now, by: 1), shares: [Share(name: "ye", cents: 1867)])]
        XCTAssertThrowsError(try ledger.batchRepay(friend: "ye", cents: 400, date: now))
        XCTAssertEqual(ledger.expenses[0].shares[0].repaid, 0)
        XCTAssertEqual(ledger.friendSpending(friend: "ye", month: now).owed, 0)
        XCTAssertEqual(ledger.friendSpending(friend: "ye", month: nil).owed, 1867)
        ledger.expenses[0].date = now.addingTimeInterval(-86400)
        try ledger.repay(expenseID: ledger.expenses[0].id, shareID: ledger.expenses[0].shares[0].id, cents: 400, date: now)
        XCTAssertEqual(ledger.friendSpending(friend: "ye", month: nil).owed, 1467)
        XCTAssertThrowsError(try ledger.batchRepay(friend: "ye", cents: 1468, date: now))
        XCTAssertEqual(ledger.expenses[0].shares[0].repaid, 400)
    }
}

final class ReceiptCalculationTests: XCTestCase {
    func testTaxServiceAndDiscountPreserveExactCents() throws {
        let service = try ReceiptCalculation.percentCharge(base: 10000, percent: 10)
        let tax = try ReceiptCalculation.percentCharge(base: 11000, percent: 8)
        let total = try ReceiptCalculation.total(subtotal: 10000, tax: tax, service: service, discount: 500)
        XCTAssertEqual(service, 1000)
        XCTAssertEqual(tax, 880)
        XCTAssertEqual(total, 11380)
        let parts = equalShares(total: total, count: 3, includeMe: false)
        XCTAssertEqual(parts, [3794, 3793, 3793])
        XCTAssertEqual(parts.reduce(0, +), total)
    }
    func testHalfCentRoundingAndInvalidCharges() throws {
        XCTAssertEqual(try ReceiptCalculation.percentCharge(base: 5, percent: 10), 1)
        XCTAssertThrowsError(try ReceiptCalculation.percentCharge(base: 100, percent: -1))
        XCTAssertThrowsError(try ReceiptCalculation.percentCharge(base: 100, percent: 101))
        XCTAssertThrowsError(try ReceiptCalculation.total(subtotal: 100, tax: 0, service: 0, discount: 101))
        XCTAssertThrowsError(try ReceiptCalculation.total(subtotal: 10_000_000_000, tax: 1, service: 0, discount: 0))
    }
    func testReceiptBackupAndOlderMissingOptionalField() throws {
        var ledger = Ledger()
        ledger.expenses = [Expense(merchant: "Cafe", cents: 1080, category: "餐饮", shares: [Share(name: "Friend", cents: 540)], receiptSummary: "Subtotal RM10.00; tax RM0.80")]
        let data = try LocalStore.encode(ledger)
        let restored = try LocalStore.decode(data)
        XCTAssertEqual(restored.expenses[0].receiptSummary, ledger.expenses[0].receiptSummary)
        XCTAssertEqual(restored.friendBalances.first?.owed, 540)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var expenses = try XCTUnwrap(json["expenses"] as? [[String: Any]])
        expenses[0].removeValue(forKey: "receiptSummary")
        json["expenses"] = expenses
        let older = try LocalStore.decode(JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(older.expenses[0].receiptSummary)
        XCTAssertEqual(older.expenses[0].cents, 1080)
        ledger.expenses[0].receiptSummary = String(repeating: "x", count: 20_001)
        XCTAssertThrowsError(try ledger.validated())
    }
}

final class TNGAllowlistTests: XCTestCase {
    func testAdsAndUnsupportedNoticesDoNotChangeLedgerOrConsumeIDs() throws {
        var ledger = Ledger()
        let original = try LocalStore.encode(ledger)
        let notices = [
            ("Promotion", "Get RM10 cashback when you spend RM50 today!"),
            ("Payment", "Payment failed RM2.55"),
            ("", "Offer: You have paid RM2.55 for Shop."),
            ("Promo", "You have paid RM2.55 for Shop."),
            ("", "No transaction information")
        ]
        for (title, body) in notices {
            _ = try ledger.receiveTNG(body: body, title: title, date: nil, eventID: "ignored-event")
            XCTAssertEqual(try LocalStore.encode(ledger), original)
        }
        _ = try ledger.receiveTNG(body: "You have paid RM2.55 for Shop.", title: "Payment", date: nil, eventID: "ignored-event")
        XCTAssertEqual(ledger.expenses.count, 1)
        XCTAssertEqual(ledger.expenses[0].cents, 255)
    }
    func testSuccessfulTransferAndOptionalTitle() {
        let body = "RM 0.01 has been successfully transferred to FRIEND."
        XCTAssertEqual(parseTNG(body, title: "Transfer Successful.")?.kind, "transfer")
        XCTAssertEqual(parseTNG(body)?.cents, 1)
        XCTAssertNil(parseTNG(body, title: "Promotion"))
    }
}

final class TNGIncomingTests: XCTestCase {
    private let body = "RM 0.01 received from CHONG YONG EN for CHONG MING ZHE."
    private let title = "Ka-ching! Incoming Money."
    func testIncomingSampleAndTitleConsistency() {
        let p = parseTNG(body, title: title)
        XCTAssertEqual(p?.kind, "incoming")
        XCTAssertEqual(p?.cents, 1)
        XCTAssertEqual(p?.party, "CHONG YONG EN")
        XCTAssertEqual(p?.recipient, "CHONG MING ZHE")
        XCTAssertEqual(parseTNG(body)?.kind, "incoming")
        XCTAssertNil(parseTNG(body, title: "Payment"))
        XCTAssertNil(parseTNG(body, title: "Promotion"))
        XCTAssertNil(parseTNG("Offer: " + body, title: title))
        XCTAssertNil(parseTNG("RM -0.01 received from A for B.", title: title))
        XCTAssertNil(parseTNG("RM 0.001 received from A for B.", title: title))
    }
    func testIncomingDisplaysPositiveAndOutgoingTransferNegativeWithoutChangingSpending() throws {
        var ledger = Ledger()
        _ = try ledger.receiveTNG(body: body, title: title, date: Date(), eventID: "incoming-sign")
        _ = try ledger.receiveTNG(body: "RM 2.00 has been successfully transferred to FRIEND.", title: "Transfer Successful.", date: Date(), eventID: "outgoing-sign")
        XCTAssertEqual(ledger.tngNotices.map(tngSignedAmount), ["+RM 0.01", "−RM 2.00"])
        XCTAssertTrue(ledger.expenses.isEmpty)
    }
    func testPendingPartialRepaymentRoundTripAndUndo() throws {
        let now = Date()
        var ledger = Ledger()
        ledger.expenses = [Expense(merchant: "Cafe", cents: 2000, date: now.addingTimeInterval(-86400), shares: [Share(name: "CHONG YONG EN", cents: 1867)])]
        _ = try ledger.receiveTNG(body: "RM 4.00 received from CHONG YONG EN for CHONG MING ZHE.", title: title, date: now, eventID: "incoming-1")
        let id = try XCTUnwrap(ledger.tngNotices.first?.id)
        XCTAssertEqual(ledger.tngNotices[0].status, "pending")
        XCTAssertEqual(ledger.friendBalances.first?.owed, 1867)
        XCTAssertEqual(ledger.expenses.count, 1)
        XCTAssertThrowsError(try ledger.confirmTNGExpense(id: id, merchant: "Sender", cents: 400, date: now, category: "其他"))
        try ledger.resolveTNGIncoming(id: id, purpose: "repayment", friend: "CHONG YONG EN", date: now)
        XCTAssertEqual(ledger.friendBalances.first?.owed, 1467)
        XCTAssertEqual(ledger.tngNotices[0].repaymentIDs?.count, 1)
        XCTAssertThrowsError(try ledger.resolveTNGIncoming(id: id, purpose: "repayment", friend: "CHONG YONG EN", date: now))
        var restored = try LocalStore.decode(LocalStore.encode(ledger))
        try restored.batchRepay(friend: "CHONG YONG EN", cents: 100, date: now)
        try restored.reopenTNGIncoming(id: id)
        XCTAssertEqual(restored.friendBalances.first?.owed, 1767)
        XCTAssertEqual(restored.tngNotices[0].status, "pending")
        try restored.resolveTNGIncoming(id: id, purpose: "income", date: now)
        XCTAssertEqual(restored.friendBalances.first?.owed, 1767)
        XCTAssertEqual(restored.spending(in: now), ledger.spending(in: now))
    }
    func testIncomingRepaysOnlyChosenExpenseAndUndoKeepsOtherPayments() throws {
        let now = Date()
        var ledger = Ledger()
        ledger.expenses = [
            Expense(id: "old", merchant: "Older meal", cents: 2000, date: now.addingTimeInterval(-172800), shares: [Share(name: "CHONG YONG EN", cents: 1000)]),
            Expense(id: "chosen", merchant: "New meal", cents: 2000, date: now.addingTimeInterval(-86400), shares: [Share(name: "CHONG YONG EN", cents: 1000)])]
        _ = try ledger.receiveTNG(body: "RM 4.00 received from CHONG YONG EN for CHONG MING ZHE.", title: title, date: now, eventID: "selected-repayment")
        let id = try XCTUnwrap(ledger.tngNotices.first?.id)
        let before = ledger
        let invalidSelections: [Set<String>] = [[], ["missing"], ["chosen", "missing"]]
        for invalid in invalidSelections {
            XCTAssertThrowsError(try ledger.resolveTNGIncoming(id: id, purpose: "repayment", friend: "CHONG YONG EN", date: now, selectedExpenseIDs: invalid))
            XCTAssertEqual(ledger.expenses, before.expenses)
            XCTAssertEqual(ledger.tngNotices, before.tngNotices)
        }
        try ledger.resolveTNGIncoming(id: id, purpose: "repayment", friend: "CHONG YONG EN", date: now, selectedExpenseIDs: ["chosen"])
        XCTAssertEqual(ledger.expenses[0].shares[0].repaid, 0)
        XCTAssertEqual(ledger.expenses[1].shares[0].repaid, 400)
        XCTAssertEqual(ledger.spending(in: now), before.spending(in: now))
        var restored = try LocalStore.decode(LocalStore.encode(ledger))
        try restored.batchRepay(friend: "CHONG YONG EN", cents: 100, date: now, selectedExpenseIDs: ["old"])
        try restored.reopenTNGIncoming(id: id)
        XCTAssertEqual(restored.expenses[0].shares[0].repaid, 100)
        XCTAssertEqual(restored.expenses[1].shares[0].repaid, 0)
        XCTAssertThrowsError(try restored.batchRepay(friend: "CHONG YONG EN", cents: 1001, date: now, selectedExpenseIDs: ["chosen"]))
    }
    func testOverpaymentAndDuplicateAreNotAppliedSilently() throws {
        let now = Date()
        var ledger = Ledger()
        ledger.expenses = [Expense(merchant: "Cafe", cents: 100, date: now.addingTimeInterval(-86400), shares: [Share(name: "A", cents: 100)])]
        let text = "RM 2.00 received from A for B."
        _ = try ledger.receiveTNG(body: text, title: title, date: now, eventID: nil)
        let id = ledger.tngNotices[0].id
        let before = try LocalStore.encode(ledger)
        XCTAssertThrowsError(try ledger.resolveTNGIncoming(id: id, purpose: "repayment", friend: "A", date: now))
        XCTAssertEqual(try LocalStore.encode(ledger), before)
        try ledger.resolveTNGIncoming(id: id, purpose: "ownTransfer", date: now)
        XCTAssertEqual(ledger.friendBalances.first?.owed, 100)
        _ = try ledger.receiveTNG(body: text, title: title, date: now, eventID: nil)
        let duplicate = ledger.tngNotices[1]
        XCTAssertTrue(duplicate.possibleDuplicate)
        XCTAssertThrowsError(try ledger.resolveTNGIncoming(id: duplicate.id, purpose: "income", date: now))
        try ledger.resolveTNGIncoming(id: duplicate.id, purpose: "ignored", date: now)
        XCTAssertEqual(ledger.tngNotices[1].status, "ignored")
    }
}

final class FriendNameNormalizationTests: XCTestCase {
    func testBatchRepaymentAndSummaryAcceptDisplayNamesAndKeys() throws {
        let now = Date()
        for supplied in ["CHONG YONG EN", "chong yong en", "  Chong   Yong\tEn  "] {
            var ledger = Ledger()
            ledger.expenses = [Expense(merchant: "Cafe", cents: 2000, date: now.addingTimeInterval(-86400), shares: [Share(name: "CHONG YONG EN", cents: 1867)])]
            XCTAssertEqual(ledger.friendSpending(friend: supplied).owed, 1867)
            try ledger.batchRepay(friend: supplied, cents: 400, date: now)
            XCTAssertEqual(ledger.friendSpending(friend: supplied).owed, 1467)
            XCTAssertEqual(ledger.expenses[0].shares[0].repaid, 400)
            XCTAssertThrowsError(try ledger.batchRepay(friend: "Different person", cents: 100, date: now))
            XCTAssertEqual(ledger.expenses[0].shares[0].repaid, 400)
        }
    }
}

final class ReceiptParsingTests: XCTestCase {
    func testReceiptWithMalaysianCommaDecimalsAndRounding() {
        let receipt = ScannedReceipt.parse("""
        ROYAL DINING HALL
        Description Amount (RM)
        DAAL CHANA FRY 1.00 @ 25.00 25.00
        PLAIN NAAN 11.00 @ 3.00 33.00
        Sub Total 208.00
        SST 13,73
        Service Charges 20.80
        Total(RM) 242,53
        Rounding Adjustment 0.02
        Net Total(RM) 242.55
        """)
        XCTAssertEqual(receipt.items.map(\.amount), ["25.00", "33.00"])
        XCTAssertEqual(receipt.subtotal, "208.00")
        XCTAssertEqual(receipt.tax, "13.73")
        XCTAssertEqual(receipt.service, "20.80")
        XCTAssertEqual(receipt.rounding, "0.02")
        XCTAssertEqual(receipt.total, "242.55")
    }

    func testReceiptWithThousandSeparators() {
        let receipt = ScannedReceipt.parse("""
        RESTAURANT
        Lobster Salad @138.00 414.00 S
        Subtotal: 67,306.00
        10% Srv Chg: 6,730.60
        GST @6%: 4,442.20
        Amt Due 78,478.80
        """)
        XCTAssertEqual(receipt.subtotal, "67306.00")
        XCTAssertEqual(receipt.service, "6730.60")
        XCTAssertEqual(receipt.tax, "4442.20")
        XCTAssertEqual(receipt.total, "78478.80")
    }
}

final class ReceiptItemSplitTests: XCTestCase {
    func testDateAndSplitLinesWithLeadingQuantityAndWrappedName() throws {
        let receipt = ScannedReceipt.parse("""
        RESTAURANT
        Date 03/11/2025 01:14 PM
        Description Amount (RM)
        DAAL CHANA FRY
        1.00 @ 25.00 25.00
        PLAIN NAAN
        11.00 @ 3.00 33.00
        1 CHICKEN CHEESY 30.00
        KOFTA
        Sub Total
        88.00
        SST 5,28
        Net Total 93.28
        Printed 04/11/2025
        """)
        XCTAssertEqual(receipt.items.map(\.name), ["DAAL CHANA FRY", "PLAIN NAAN", "CHICKEN CHEESY KOFTA"])
        XCTAssertEqual(receipt.items.map(\.amount), ["25.00", "33.00", "30.00"])
        XCTAssertEqual(receipt.subtotal, "88.00")
        let components = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: try XCTUnwrap(receipt.date))
        XCTAssertEqual(components.year, 2025)
        XCTAssertEqual(components.month, 11)
        XCTAssertEqual(components.day, 3)
        XCTAssertNotNil(ScannedReceipt.receiptDate("10 May 17 08:17 PM"))
        XCTAssertNil(ScannedReceipt.receiptDate("31/02/2025"))
        XCTAssertNil(ScannedReceipt.parse("CAFE\nSubtotal 20.00").date)
    }
    func testDifferentDishesAndSharedDishWithProportionalCharges() throws {
        let me = UUID(), friend = UUID()
        let items = [ScannedReceipt.Item(name: "Noodles", amount: "10.00", people: [me]),
                     ScannedReceipt.Item(name: "Rice", amount: "20.00", people: [friend]),
                     ScannedReceipt.Item(name: "Shared side", amount: "5.00", people: [me, friend])]
        let food = try ReceiptSplit.food(items: items, people: [me, friend], subtotal: 3500)
        XCTAssertEqual(food, [1250, 2250])
        // RM3.50 service + RM2.31 tax + RM0.04 rounding.
        let total = try ReceiptSplit.allocate(4085, weights: food)
        XCTAssertEqual(total, [1459, 2626])
        XCTAssertEqual(total.reduce(0, +), 4085)
        XCTAssertEqual(try ReceiptSplit.allocate(3501, weights: [1, 1]), [1751, 1750])
    }
    func testMissingItemsAndMissingAssignmentBlockSaving() throws {
        let me = UUID()
        let item = ScannedReceipt.Item(name: "Lunch", amount: "10.00", people: [me])
        XCTAssertThrowsError(try ReceiptSplit.food(items: [item], people: [me], subtotal: 2000))
        let unassigned = ScannedReceipt.Item(name: "Lunch", amount: "10.00")
        XCTAssertThrowsError(try ReceiptSplit.food(items: [unassigned], people: [me], subtotal: 1000))
        XCTAssertThrowsError(try ReceiptSplit.food(items: [item], people: [UUID()], subtotal: 1000))
        XCTAssertEqual(try ReceiptSplit.allocate(100, weights: [0, 1]), [0, 100])
        XCTAssertEqual(try ReceiptSplit.allocate(9_999_999_999, weights: [5_000_000_000, 4_999_999_999]).reduce(0, +), 9_999_999_999)
    }
}

extension ReceiptItemSplitTests {
    func testCompleteDiningReceiptKeepsZeroItemsAndWrappedNames() {
        let parsed = ScannedReceipt.parse("""
        ROYAL DINING HALL
        Date 03/11/2025 01:14 PM
        Description Amount (RM)
        DAAL CHANA FRY 1.00 @ 25.00 25.00
        PLAIN NAAN 11.00 @ 3.00 33.00
        PALAK PANEER 2.00 @ 25.00 50.00
        CHICKEN CHEESY 1.00 @ 30.00 30.00
        KOFTA
        DAAL MASH FRY 1.00 @ 25.00 25.00
        CH TANDOORI LEG 2.00 @ 15.00 30.00
        PLAIN PARATHA 1.00 @ 5.00 5.00
        SOFT DRINK ( LARGE ) .00 @ 6.00 .00
        COKE
        FRESH LIME JUICE 1.00 @ 10.00 10.00
        MINERAL WATER .00 @ 4.00 .00
        ( LARGE )
        Bill Amount 208.00
        Discount 0.00
        Sub Total 208.00
        SST 13,73
        Service Charges 20.80
        Total(RM) 242,53
        Rounding Adjustment 0.02
        Net Total(RM) 242.55
        """)
        XCTAssertEqual(parsed.items.count, 10)
        XCTAssertEqual(parsed.items[3].name, "CHICKEN CHEESY KOFTA")
        XCTAssertEqual(parsed.items[7].amount, "0.00")
        XCTAssertEqual(parsed.items[9].name, "MINERAL WATER ( LARGE )")
        XCTAssertEqual(parsed.items.reduce(0) { $0 + ((try? optionalMoney($1.amount)) ?? 0) }, 20800)
        XCTAssertEqual(parsed.total, "242.55")
        XCTAssertEqual(ScannedReceipt.parse("Rounding Adjustment -0.02").rounding, "-0.02")
    }
}

final class ReceiptGridTests: XCTestCase {
    private func cell(_ text: String, _ column: Int) -> ReceiptGrid.Cell {
        ReceiptGrid.Cell(text: text, columns: column...column)
    }
    func testWrappedDescriptionAndZeroPricedContinuationsFromRestaurantReceipt() {
        let rows: [[ReceiptGrid.Cell]] = [
            [cell("Description", 0), cell("Qty", 1), cell("Unit price", 2), cell("Amount (RM)", 3)],
            [cell("DAAL CHANA FRY", 0), cell("1.00", 1), cell("25.00", 2), cell("25.00", 3)],
            [cell("PLAIN NAAN", 0), cell("11.00", 1), cell("3.00", 2), cell("33.00", 3)],
            [cell("PALAK PANEER", 0), cell("2.00", 1), cell("25.00", 2), cell("50.00", 3)],
            [cell("CHICKEN CHEESY", 0), cell("1.00", 1), cell("30.00", 2), cell("30.00", 3)],
            [cell("KOFTA", 0)],
            [cell("DAAL MASH FRY", 0), cell("25.00", 3)],
            [cell("CH TANDOORI LEG", 0), cell("30.00", 3)],
            [cell("PLAIN PARATHA", 0), cell("5.00", 3)],
            [cell("SOFT DRINK (LARGE)", 0), cell("6.00", 2), cell(".00", 3)],
            [cell("COKE", 0), cell(".00", 3)],
            [cell("FRESH LIME JUICE", 0), cell("10.00", 3)],
            [cell("MINERAL WATER", 0), cell("4.00", 2), cell(".00", 3)],
            [cell("(LARGE)", 0)],
            [cell("Bill Amount", 0), cell("208.00", 3)],
            [cell("SST", 0), cell("13,73", 3)],
            [cell("Service Charges", 0), cell("20.80", 3)],
            [cell("Rounding Adjustment", 0), cell("0.02", 3)],
            [cell("Net Total(RM)", 0), cell("242.55", 3)]
        ]
        let parsed = ReceiptGrid.parse(rows)
        XCTAssertEqual(parsed.items.count, 10)
        XCTAssertEqual(parsed.items[3].name, "CHICKEN CHEESY KOFTA")
        XCTAssertEqual(parsed.items[7].name, "SOFT DRINK (LARGE) COKE")
        XCTAssertEqual(parsed.items[7].amount, "0.00")
        XCTAssertEqual(parsed.items[9].name, "MINERAL WATER (LARGE)")
        XCTAssertEqual(parsed.items.compactMap { try? toCents($0.amount) }.reduce(0, +), 20800)
        let summary = ScannedReceipt.parse(parsed.summaries.joined(separator: "\n"))
        XCTAssertEqual(summary.subtotal, "208.00")
        XCTAssertEqual(summary.total, "242.55")
    }
    func testMissingItemPriceRemainsVisibleWhenNextItemIsPriced() {
        let parsed = ReceiptGrid.parse([
            [cell("Description", 0), cell("Amount", 1)],
            [cell("Unclear soup", 0)],
            [cell("Rice", 0), cell("12.00", 1)]
        ])
        XCTAssertEqual(parsed.items.map(\.name), ["Unclear soup", "Rice"])
        XCTAssertEqual(parsed.items.map(\.amount), ["", "12.00"])
    }
    func testTwoColumnReceiptsWithPriceAsLineTotalAndMalayLabels() {
        let simple = ReceiptGrid.parse([
            [cell("Item", 0), cell("Price", 1)],
            [cell("Noodles", 0), cell("12.00", 1)],
            [cell("Rice", 0), cell("15.00", 1)],
            [cell("Total", 0), cell("27.00", 1)]
        ])
        XCTAssertEqual(simple.items.map(\.amount), ["12.00", "15.00"])
        let malay = ReceiptGrid.parse([
            [cell("Butiran", 0), cell("Jumlah", 1)],
            [cell("Nasi", 0), cell("8.50", 1)]
        ])
        XCTAssertEqual(malay.items.first?.name, "Nasi")
        XCTAssertEqual(malay.items.first?.amount, "8.50")
    }
    func testAmountColumnWinsOverQuantityAndUnitPriceEvenWhenReordered() {
        let result = ReceiptGrid.parse([
            [cell("Amount (RM)", 0), cell("Description", 1), cell("Unit Price", 2), cell("Qty", 3)],
            [cell("33.00", 0), cell("PLAIN NAAN", 1), cell("3.00", 2), cell("11.00", 3)],
            [cell("30.00", 0), cell("CHICKEN CHEESY\nKOFTA", 1), cell("30.00", 2), cell("1.00", 3)]
        ])
        XCTAssertTrue(result.foundColumns)
        XCTAssertEqual(result.items.map(\.name), ["PLAIN NAAN", "CHICKEN CHEESY KOFTA"])
        XCTAssertEqual(result.items.map(\.amount), ["33.00", "30.00"])
    }
    func testMissingAmountStaysBlankRatherThanTakingUnitPrice() {
        let result = ReceiptGrid.parse([
            [cell("Description", 0), cell("Unit price", 1), cell("Amount", 2)],
            [cell("Lunch", 0), cell("12.00", 1)],
            [cell("Dinner", 0), cell("18.00", 1), cell("18.00 36.00", 2)]
        ])
        XCTAssertEqual(result.items.map(\.amount), ["", ""])
        XCTAssertEqual(result.items.count, 2)
    }
    func testSummaryRowsAreNotFoodAndZeroAmountsArePreserved() {
        let result = ReceiptGrid.parse([
            [cell("Description", 0), cell("Amount (RM)", 1)],
            [cell("Water", 0), cell(".00", 1)],
            [cell("Subtotal", 0), cell("208.00", 1)],
            [cell("SST", 0), cell("13,73", 1)],
            [cell("Net Total", 0), cell("242.55", 1)]
        ])
        XCTAssertEqual(result.items.count, 1)
        XCTAssertEqual(result.items.first?.amount, "0.00")
        XCTAssertEqual(result.summaries.count, 3)
        XCTAssertEqual(ScannedReceipt.parse(result.summaries.joined(separator: "\n")).total, "242.55")
        XCTAssertEqual(ReceiptGrid.amount("RM 1,234.56"), "1234.56")
        XCTAssertNil(ReceiptGrid.amount("3.00 @ 11.00"))
    }
    func testMergedDescriptionAndAmountIsNotGuessed() {
        let result = ReceiptGrid.parse([
            [cell("Description", 0), cell("Amount", 1)],
            [ReceiptGrid.Cell(text: "Lunch 25.00", columns: 0...1)]
        ])
        XCTAssertTrue(result.items.isEmpty)
        XCTAssertFalse(ReceiptGrid.parse([[cell("Lunch", 0), cell("25.00", 1)]]).foundColumns)
    }
}

final class ReceiptRetryTests: XCTestCase {
    func testTextNamesAreRecoveredOnlyWithExactRowAndAmountAgreement() {
        let rows = [ScannedReceipt.Item(name: "", amount: "25.00"), .init(name: "Rice", amount: "33.00")]
        let words = [ScannedReceipt.Item(name: "Soup", amount: "25.00"), .init(name: "Rice", amount: "33.00")]
        XCTAssertEqual(ReceiptOCR.recoverNames(rows, from: words).map(\.name), ["Soup", "Rice"])
        let wrong = [words[0], .init(name: "Rice", amount: "3.00")]
        XCTAssertEqual(ReceiptOCR.recoverNames(rows, from: wrong).map(\.name), ["", "Rice"])
    }
    func testCompleteReconciledPassWinsOverMoreUnreconciledItems() {
        var good = ScannedReceipt()
        good.subtotal = "40.00"; good.tax = "3.20"; good.service = "4.00"; good.total = "47.20"
        good.items = [.init(name: "Noodles", amount: "15.00"), .init(name: "Rice", amount: "25.00")]
        XCTAssertEqual(ReceiptOCR.quality(good), 4)
        var extra = good
        extra.items.append(.init(name: "False extra row", amount: "25.00"))
        XCTAssertLessThan(ReceiptOCR.quality(extra), ReceiptOCR.quality(good))
        var missing = good; missing.items[0].amount = ""
        XCTAssertEqual(ReceiptOCR.quality(missing), 1)
        var noItems = good; noItems.items = []
        XCTAssertEqual(ReceiptOCR.quality(noItems), 0)
        var missingTax = good; missingTax.tax = ""
        XCTAssertEqual(ReceiptOCR.quality(missingTax), 3)
    }
    func testShortHeadersStillUseAmountNotPrice() {
        let parsed = ReceiptGrid.parse([
            [.init(text: "Desc.", columns: 0...0), .init(text: "Price", columns: 1...1), .init(text: "Amt.", columns: 2...2)],
            [.init(text: "Naan", columns: 0...0), .init(text: "3.00", columns: 1...1), .init(text: "33.00", columns: 2...2)]
        ])
        XCTAssertEqual(parsed.items.first?.amount, "33.00")
    }
}

final class SavingsGoalTests: XCTestCase {
    func testSavingsBackupRestoreAndFailedWithdrawalPreservesData() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = LocalStore(folder: folder)
        var goal = SavingsGoal(name: "Computer", target: 100000)
        try goal.record(cents: 20000)
        try goal.record(cents: -2500)
        try store.change {
            $0.savingsGoals = [goal]
            $0.expenses = [Expense(merchant: "Lunch", cents: 1200)]
        }
        let saved = try LocalStore.encode(store.read())
        XCTAssertThrowsError(try store.change { try $0.savingsGoals[0].record(cents: -17501) })
        XCTAssertEqual(try LocalStore.encode(store.read()), saved)
        try store.change { $0.savingsGoals.removeAll() }
        try store.restore(saved)
        let restored = try store.read()
        XCTAssertEqual(restored.savingsGoals.first?.balance, 17500)
        XCTAssertEqual(restored.savingsGoals.first?.entries.map(\.cents), [20000, -2500])
        XCTAssertEqual(restored.expenses.first?.personal, 1200)
    }
    func testOldLedgerMigratesWithoutInventingGoals() throws {
        let data = Data(#"{"version":3,"expenses":[],"budgets":{},"seenEvents":[]}"#.utf8)
        let ledger = try LocalStore.decode(data)
        XCTAssertEqual(ledger.version, 6)
        XCTAssertTrue(ledger.savingsGoals.isEmpty)
    }
    func testSavingsBoundsAndCompletion() throws {
        var goal = SavingsGoal(name: "Books", target: 10000)
        XCTAssertThrowsError(try goal.record(cents: -1))
        XCTAssertThrowsError(try goal.record(cents: 0))
        XCTAssertThrowsError(try goal.record(cents: Int.max))
        XCTAssertTrue(goal.entries.isEmpty)
        try goal.record(cents: 12000)
        XCTAssertEqual(goal.balance, 12000)
        XCTAssertEqual(goal.progress, 1)
        try goal.record(cents: -12000)
        XCTAssertEqual(goal.progress, 0)
        var ledger = Ledger()
        ledger.savingsGoals = [goal, goal]
        XCTAssertThrowsError(try ledger.validated())
        goal.target = 0
        XCTAssertThrowsError(try goal.validate())
    }
}

final class ReceiptColumnDetailTests: XCTestCase {
    func testQuantityAndUnitPriceNeverReplaceLineTotal() {
        func cell(_ text: String, _ column: Int) -> ReceiptGrid.Cell { .init(text: text, columns: column...column) }
        let result = ReceiptGrid.parse([
            [cell("Description", 0), cell("Quantity", 1), cell("Unit Price", 2), cell("Amount", 3)],
            [cell("PLAIN NAAN", 0), cell("11", 1), cell("3.00", 2), cell("33.00", 3)]
        ])
        XCTAssertEqual(result.items.count, 1)
        XCTAssertEqual(result.items.first?.name, "PLAIN NAAN")
        XCTAssertEqual(result.items.first?.quantity, "11")
        XCTAssertEqual(result.items.first?.unitPrice, "3.00")
        XCTAssertEqual(result.items.first?.amount, "33.00")
    }
}
final class TNGNotificationDeliveryTests: XCTestCase {
    func testObservedPaymentTemplateStillRecordsFortyRinggit() throws {
        var ledger = Ledger()
        let result = try ledger.processTNGNotification(body: "You have paid RM40.00 for Maxis Broadband Sdn Bhd.", title: "Payment", date: nil, eventID: "maxis-test")
        XCTAssertTrue(result.accepted)
        XCTAssertEqual(ledger.expenses.first?.cents, 4000)
        XCTAssertEqual(ledger.expenses.first?.merchant, "Maxis Broadband Sdn Bhd")
        XCTAssertEqual(ledger.automationEvents.first?.outcome, "saved")
        _ = try ledger.processTNGNotification(body: "You have paid RM40.00 for Maxis Broadband Sdn Bhd.", title: "Payment", date: nil, eventID: "maxis-test")
        XCTAssertEqual(ledger.expenses.count, 1)
    }
    func testReceivedMoneyTemplatePreservesJointSenderAndRequiresReview() throws {
        let body = "ALICE/BOB has transferred RM 40.00 to you. Tap here to check the transaction details."
        for title in ["", "You've received money!", "You’ve received money!"] {
            let parsed = try XCTUnwrap(parseTNG(body, title: title))
            XCTAssertEqual(parsed.kind, "incoming")
            XCTAssertEqual(parsed.cents, 4000)
            XCTAssertEqual(parsed.party, "ALICE/BOB")
            XCTAssertNil(parsed.recipient)
        }
        XCTAssertNil(parseTNG(body, title: "Payment"))
        XCTAssertNil(parseTNG(body, title: "Promotion"))
        XCTAssertNil(parseTNG(body.replacingOccurrences(of: "40.00", with: "-40.00")))
        XCTAssertNil(parseTNG(body.replacingOccurrences(of: "40.00", with: "40.001")))
        var ledger = Ledger()
        _ = try ledger.processTNGNotification(body: body, title: "You've received money!", date: nil, eventID: nil)
        XCTAssertTrue(ledger.expenses.isEmpty)
        XCTAssertEqual(ledger.tngNotices.first?.status, "pending")
        XCTAssertEqual(ledger.tngNotices.first?.kind, "incoming")
        _ = try ledger.processTNGNotification(body: body, title: "You've received money!", date: nil, eventID: nil)
        XCTAssertEqual(ledger.tngNotices.last?.possibleDuplicate, true)
        XCTAssertTrue(ledger.expenses.isEmpty)
        _ = try ledger.validated()
    }
    func testIgnoredDeliveryLogsWithoutStoringBodyOrConsumingTransactionID() throws {
        var ledger = Ledger()
        for body in ["You have successfully registered your DuitNow ID *******0000.", "You've received 40 points from your transaction! Use them now to redeem great rewards."] {
            let result = try ledger.processTNGNotification(body: body, date: nil, eventID: "not-consumed")
            XCTAssertFalse(result.accepted)
            XCTAssertEqual(ledger.automationEvents.first?.outcome, "ignored")
            XCTAssertFalse(ledger.automationEvents.first?.detail.contains(body) ?? true)
        }
        XCTAssertTrue(ledger.expenses.isEmpty)
        XCTAssertTrue(ledger.tngNotices.isEmpty)
        XCTAssertTrue(ledger.seenEvents.isEmpty)
        _ = try ledger.processTNGNotification(body: "You have paid RM40.00 for Maxis Broadband Sdn Bhd.", date: nil, eventID: "not-consumed")
        XCTAssertEqual(ledger.expenses.count, 1)
        XCTAssertThrowsError(try ledger.processTNGNotification(body: " ", date: nil, eventID: nil))
    }
}

final class LocalSavingsDraftTests: XCTestCase {
    func testChineseTargetAndMonthlyAreSeparate() {
        let d = LocalSavingsDraft.parse("六个月存 RM3000 买电脑，每月存 RM500")
        XCTAssertEqual(d.amount, "3000")
        XCTAssertEqual(d.monthly, "500")
        XCTAssertEqual(d.months, 6)
    }
    func testEnglishAndMalay() {
        let english = LocalSavingsDraft.parse("Save RM3,000 in six months for a computer; RM500 per month")
        XCTAssertEqual(english.amount, "3000")
        XCTAssertEqual(english.monthly, "500")
        XCTAssertEqual(english.months, 6)
        let malay = LocalSavingsDraft.parse("Simpan RM3000 dalam enam bulan untuk komputer")
        XCTAssertEqual(malay.amount, "3000")
        XCTAssertEqual(malay.months, 6)
    }
    func testAmbiguityDoesNotInventMoneyOrDates() {
        XCTAssertEqual(LocalSavingsDraft.parse("RM3000 or RM5000").amount, "")
        XCTAssertEqual(LocalSavingsDraft.parse("USD3000 in 6 months").amount, "")
        XCTAssertEqual(LocalSavingsDraft.parse("每月存 RM500").amount, "")
        XCTAssertEqual(LocalSavingsDraft.parse("每月存 RM500").monthly, "500")
        XCTAssertEqual(LocalSavingsDraft.parse("2027年6月存 RM3000").months, 0)
        XCTAssertEqual(LocalSavingsDraft.parse("买电脑").amount, "")
        XCTAssertEqual(LocalSavingsDraft.parse("RM-50").amount, "")
        XCTAssertEqual(LocalSavingsDraft.parse("RM1.234").amount, "")
    }
}

final class TNGLedgerPresentationTests: XCTestCase {
    func testExistingTransfersAppearWithoutChangingSpending() throws {
        var ledger = Ledger()
        let now = Date()
        _ = try ledger.receiveTNG(body: "RM 20.00 has been successfully transferred to FRIEND.", date: now, eventID: "sent")
        _ = try ledger.receiveTNG(body: "FRIEND has transferred RM40.00 to you.", date: now, eventID: "received")
        XCTAssertEqual(ledger.ledgerTNGTransfers(in: now).count, 2)
        XCTAssertEqual(ledger.ledgerTNGTransfers(in: now, search: "friend").count, 2)
        XCTAssertTrue(ledger.ledgerTNGTransfers(in: now, search: "unrelated").isEmpty)
        XCTAssertTrue(ledger.expenses.isEmpty)
        let previous = try XCTUnwrap(Calendar.current.date(byAdding: .month, value: -1, to: now))
        XCTAssertTrue(ledger.ledgerTNGTransfers(in: previous).isEmpty)
        let outgoing = try XCTUnwrap(ledger.tngNotices.first { $0.kind == "transfer" })
        try ledger.confirmTNGExpense(id: outgoing.id, merchant: "FRIEND", cents: 2000, date: now, category: "其他")
        XCTAssertEqual(ledger.expenses.count, 1)
        XCTAssertEqual(ledger.ledgerTNGTransfers(in: now).count, 1)
        let incoming = try XCTUnwrap(ledger.tngNotices.first { $0.kind == "incoming" })
        try ledger.resolveTNGIncoming(id: incoming.id, purpose: "income", date: now)
        XCTAssertEqual(ledger.ledgerTNGTransfers(in: now).first?.status, "income")
    }
}

final class DuitNowNotificationTests: XCTestCase {
    private let body = "You have successfully transferred RM 0.01 to TEST NAME/SECOND NAME."
    private let title = "DuitNow Transfer is successful!"
    func testScreenshotFormatAndOptionalTitle() throws {
        for heading in [title, ""] {
            let result = try XCTUnwrap(parseTNG(body, title: heading))
            XCTAssertEqual(result.kind, "transfer")
            XCTAssertEqual(result.cents, 1)
            XCTAssertEqual(result.party, "TEST NAME/SECOND NAME")
        }
        XCTAssertNotNil(parseTNG(body.replacingOccurrences(of: " to ", with: " to\n"), title: title))
        for heading in ["Promotion", "Payment", "You've received money!"] {
            XCTAssertNil(parseTNG(body, title: heading))
        }
        for text in [body.replacingOccurrences(of: "0.01", with: "-0.01"),
                     body.replacingOccurrences(of: "0.01", with: "0.001"),
                     body.replacingOccurrences(of: "successfully", with: "unsuccessfully"),
                     "Offer: " + body] {
            XCTAssertNil(parseTNG(text, title: title))
        }
    }
    func testDeliveryAppearsInLedgerAndDeduplicates() throws {
        var ledger = Ledger()
        let date = Date()
        let result = try ledger.processTNGNotification(body: body, title: title, date: date, eventID: "duitnow-test")
        XCTAssertTrue(result.accepted)
        XCTAssertEqual(ledger.ledgerTNGTransfers(in: date).count, 1)
        XCTAssertEqual(ledger.ledgerTNGTransfers(in: date).first?.status, "transfer")
        XCTAssertTrue(ledger.expenses.isEmpty)
        _ = try ledger.processTNGNotification(body: body, title: title, date: date, eventID: "duitnow-test")
        XCTAssertEqual(ledger.tngNotices.count, 1)
    }
}

final class FeedbackPolicyTests: XCTestCase {
    func testNoticeReviewSurvivesRepeatedReadsAndRemovesDeletedItems() {
        var tracker = TNGReviewTracker(observed: nil)
        tracker.observe(["old"])
        XCTAssertTrue(tracker.pending.isEmpty)
        tracker.observe(["old", "new"])
        XCTAssertEqual(tracker.pending, ["new"])
        tracker.observe(["old", "new"])
        XCTAssertEqual(tracker.pending, ["new"])
        tracker = TNGReviewTracker(observed: tracker.observed, pending: tracker.pending)
        tracker.observe(["old", "new", "later"])
        XCTAssertEqual(tracker.pending, ["new", "later"])
        tracker.observe(["old", "later"])
        XCTAssertEqual(tracker.pending, ["later"])
        tracker.pending = []
        tracker.observe(["old", "later"])
        XCTAssertTrue(tracker.pending.isEmpty)
    }
    @MainActor func testSoundModesRespectMasterMuteAndLimitSuccessMode() {
        let cues: [FeedbackSounds.Cue] = [.launch, .saved, .goal, .deleted, .restored, .deposit]
        for cue in cues {
            XCTAssertFalse(FeedbackSounds.permits(cue, mode: "full", enabled: false))
            XCTAssertFalse(FeedbackSounds.permits(cue, mode: "off", enabled: true))
            XCTAssertTrue(FeedbackSounds.permits(cue, mode: "full", enabled: true))
            XCTAssertEqual(FeedbackSounds.permits(cue, mode: "success", enabled: true), cue == .saved || cue == .goal)
        }
    }
}

final class TimelineOrderingTests: XCTestCase {
    func testExpensesAndTransfersShareChronologicalDays() throws {
        let day = Calendar.current.startOfDay(for: Date())
        let expense = Expense(merchant: "Lunch", cents: 1200, date: day.addingTimeInterval(3600))
        let incoming = TNGNotice(body: "test", title: "", date: day.addingTimeInterval(7200), usesReceivedDate: false, kind: "incoming", status: "pending", cents: 500, party: "Friend")
        let groups = LedgerTimelineItem.grouped(expenses: [expense], transfers: [incoming])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].entries.map(\.id), ["tng:" + incoming.id, "expense:" + expense.id])
        var old = incoming
        old.id = "older"
        old.date = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: -1, to: day))
        let days = LedgerTimelineItem.grouped(expenses: [expense], transfers: [old, incoming])
        XCTAssertEqual(days.count, 2)
        XCTAssertGreaterThan(days[0].date, days[1].date)
    }
}

final class FeedbackPresentationTests: XCTestCase {
    func testOnlyTopPresentationShowsSaveAndUndoFeedback() {
        var owners = FeedbackPresentationOwners()
        let detail = UUID(), nested = UUID()
        XCTAssertTrue(owners.isVisible(nil))
        owners.present(detail)
        owners.present(detail)
        XCTAssertEqual(owners.modals.count, 1)
        XCTAssertFalse(owners.isVisible(nil))
        XCTAssertTrue(owners.isVisible(detail))
        owners.present(nested)
        XCTAssertFalse(owners.isVisible(detail))
        XCTAssertTrue(owners.isVisible(nested))
        owners.dismiss(nested)
        XCTAssertTrue(owners.isVisible(detail))
        owners.dismiss(detail)
        XCTAssertTrue(owners.isVisible(nil))
        XCTAssertFalse(owners.isVisible(detail))
    }
    func testDismissalOfUnderlyingModalDoesNotStealOwnership() {
        var owners = FeedbackPresentationOwners()
        let first = UUID(), second = UUID()
        owners.present(first); owners.present(second)
        owners.dismiss(first)
        XCTAssertFalse(owners.isVisible(nil))
        XCTAssertTrue(owners.isVisible(second))
    }
}

final class BankNotificationTests: XCTestCase {
    private let samples: [(String, String, String, String, String, Bool)] = [
        ("Maybank", "Maybank2u: Funds Received", "You've just received RM 0.01 in your account ending ***1234. REF: TESTIN001", "incoming", "", true),
        ("Maybank", "Maybank2u: Transfer", "DuitNow of RM 0.01 to TEST PERSON. Mobile Number : ****5678. REF: TESTOUT001", "transfer", "TEST PERSON", true),
        ("Hong Leong", "Transaction Notice", "HLB: You have received a transfer of RM0.01 into your bank account ending 1234 @01/10/2026 22:44:38", "incoming", "", false),
        ("Hong Leong", "Transaction Notice", "Your transfer of RM0.01 to TEST PERSON is SUCCESSFUL.", "transfer", "TEST PERSON", true),
        ("AmBank", "AmOnline", "AmBank/AmBank Islamic: TEST PERSON transferred MYR0.01 to your current/savings account ***1234 on 01/10/26 22:48", "incoming", "TEST PERSON", false),
        ("AmBank", "AmOnline", "AmBank: RM0.01 DuitNow Transfer to ***5678/TEST PERSON on 01/10/2026 22:46. For queries call AmBank.", "transfer", "TEST PERSON", false),
        ("Ryt Bank", "Your money is in!", "You've received RM0.01 from TEST PERSON on 1/10/2026, 10:55 PM (GMT+8).", "incoming", "TEST PERSON", false),
        ("Ryt Bank", "Nice! Transfer settled!", "You've sent RM0.01 to TEST PERSON on 1/10/2026, 10:54 PM (GMT+8) using your Main Account.", "transfer", "TEST PERSON", false),
        ("RHB", "Funds Received", "You've received MYR 0.01 to your account 1234 on 2026-10-01 22:52:31.", "incoming", "", false)
    ]
    func testNineObservedTemplatesWithAndWithoutTitles() throws {
        for (bank, title, body, kind, party, fallback) in samples {
            for heading in [title, ""] {
                let parsed = try XCTUnwrap(parseFinancialNotification(body, title: heading), bank)
                XCTAssertEqual(parsed.sourceBank, bank)
                XCTAssertEqual(parsed.kind, kind)
                XCTAssertEqual(parsed.cents, 1)
                XCTAssertEqual(parsed.party, party)
                XCTAssertEqual(parsed.transactionDate == nil, fallback)
            }
            XCTAssertNil(parseFinancialNotification(body, title: "Promotion"))
            XCTAssertNil(parseFinancialNotification("Offer: " + body, title: title))
            XCTAssertNil(parseFinancialNotification(body.replacingOccurrences(of: "0.01", with: "-0.01"), title: title))
            XCTAssertNil(parseFinancialNotification(body.replacingOccurrences(of: "0.01", with: "0.001"), title: title))
        }
    }
    func testDatesUseMalaysiaTimezoneAndRejectInvalidDates() throws {
        let expected = ISO8601DateFormatter().date(from: "2026-10-01T14:55:00Z")
        XCTAssertEqual(parseFinancialNotification(samples[6].2)?.transactionDate, expected)
        XCTAssertNil(parseFinancialNotification(samples[6].2.replacingOccurrences(of: "1/10/2026", with: "31/02/2026")))
        XCTAssertNil(parseFinancialNotification(samples[3].2.replacingOccurrences(of: "SUCCESSFUL", with: "FAILED")))
        XCTAssertNil(parseFinancialNotification("You've sent MYR 0.01 to FRIEND.", title: "Funds Received"))
    }
    func testPersistenceAndSourceScopedDeduplication() throws {
        var ledger = Ledger()
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-01T15:00:00Z"))
        for (_, title, body, _, _, _) in samples {
            _ = try ledger.receiveTNG(body: body, title: title, date: now, eventID: nil, now: now)
        }
        XCTAssertEqual(ledger.tngNotices.count, 9)
        XCTAssertTrue(ledger.expenses.isEmpty)
        XCTAssertFalse(ledger.tngNotices.contains { $0.possibleDuplicate })
        XCTAssertTrue(ledger.tngNotices[0].usesReceivedDate)
        XCTAssertFalse(ledger.tngNotices[2].usesReceivedDate)
        _ = try ledger.receiveTNG(body: samples[0].2, title: samples[0].1, date: now, eventID: nil, now: now)
        XCTAssertEqual(ledger.tngNotices.count, 9)
        let decoded = try JSONDecoder().decode(Ledger.self, from: JSONEncoder().encode(ledger.validated()))
        XCTAssertEqual(decoded.tngNotices, ledger.tngNotices)
        let outgoing = ledger.tngNotices[1]
        try ledger.confirmTNGExpense(id: outgoing.id, merchant: "TEST PERSON", cents: 1, date: now, category: "其他")
        XCTAssertEqual(ledger.expenses.first?.source, "Maybank")
        XCTAssertFalse(ledger.ledgerTNGTransfers(in: now).contains { $0.id == outgoing.id })
    }
    func testLegacyTNGDecodesAndStillRecords() throws {
        var ledger = Ledger()
        _ = try ledger.receiveTNG(body: "You have paid RM1.00 for Shop.", date: nil, eventID: "legacy")
        let encoded = try JSONEncoder().encode(ledger)
        let decoded = try JSONDecoder().decode(Ledger.self, from: encoded)
        XCTAssertEqual(decoded.tngNotices.first?.provider, "TNG")
        XCTAssertEqual(decoded.expenses.first?.source, "TNG")
    }
}

final class AutomaticRecordDeletionTests: XCTestCase {
    func testDeleteIncomingPreservesOtherBankAndUndoKeepsNewWrites() throws {
        var ledger = Ledger()
        _ = try ledger.receiveTNG(body: "You've just received RM 0.01 in your account ending ***1234. REF: DELETE001", title: "Maybank2u: Funds Received", date: nil, eventID: nil)
        _ = try ledger.receiveTNG(body: "Your transfer of RM0.01 to TEST PERSON is SUCCESSFUL.", title: "Transaction Notice", date: nil, eventID: nil)
        let original = ledger.tngNotices
        let markers = ledger.seenEvents
        let deleted = try ledger.deleteAutomaticRecord(original[0])
        XCTAssertEqual(ledger.tngNotices, [original[1]])
        XCTAssertEqual(ledger.seenEvents, markers)
        let newEntry = Expense(merchant: "New", cents: 100)
        ledger.expenses.append(newEntry)
        try ledger.restoreDeletedRecords([deleted])
        XCTAssertEqual(Set(ledger.tngNotices.map(\.id)), Set(original.map(\.id)))
        XCTAssertEqual(ledger.expenses, [newEntry])
        XCTAssertThrowsError(try ledger.restoreDeletedRecords([deleted]))
    }
    func testDeletingExpenseAlsoRemovesItsNoticeAndRestoresBoth() throws {
        var ledger = Ledger()
        _ = try ledger.receiveTNG(body: "You have paid RM1.00 for Shop.", date: nil, eventID: "delete-payment")
        let entry = try XCTUnwrap(ledger.expenses.first)
        let notice = try XCTUnwrap(ledger.tngNotices.first)
        let deletion = try ledger.deleteLedgerExpense(entry)
        XCTAssertTrue(ledger.expenses.isEmpty)
        XCTAssertTrue(ledger.tngNotices.isEmpty)
        try ledger.restoreDeletedRecords([deletion])
        XCTAssertEqual(ledger.expenses, [entry])
        XCTAssertEqual(ledger.tngNotices, [notice])
        let second = try ledger.deleteAutomaticRecord(notice)
        XCTAssertTrue(ledger.expenses.isEmpty)
        try ledger.restoreDeletedRecords([second])
        XCTAssertEqual(ledger.expenses, [entry])
    }
    func testDeletingReceiptReversesOnlyItsRepaymentAndUndoChecksConflicts() throws {
        var ledger = Ledger(expenses: [Expense(merchant: "Dinner", cents: 1000, shares: [Share(name: "Amy", cents: 500, repayments: [Repayment(cents: 50)])])])
        _ = try ledger.receiveTNG(body: "You've just received RM 1.00 in your account ending ***1234. REF: REPAY001", title: "Maybank2u: Funds Received", date: nil, eventID: nil)
        let id = try XCTUnwrap(ledger.tngNotices.first?.id)
        try ledger.resolveTNGIncoming(id: id, purpose: "repayment", friend: "Amy", date: Date())
        let before = ledger.expenses
        let notice = try XCTUnwrap(ledger.tngNotices.first)
        let deletion = try ledger.deleteAutomaticRecord(notice)
        XCTAssertEqual(ledger.expenses[0].shares[0].repaid, 50)
        var conflict = ledger
        conflict.expenses[0].merchant = "Changed"
        XCTAssertThrowsError(try conflict.restoreDeletedRecords([deletion]))
        XCTAssertTrue(conflict.tngNotices.isEmpty)
        XCTAssertEqual(conflict.expenses[0].merchant, "Changed")
        let expenseDeletion = try ledger.deleteLedgerExpense(ledger.expenses[0])
        try ledger.restoreDeletedRecords([deletion, expenseDeletion])
        XCTAssertEqual(ledger.expenses, before)
        XCTAssertEqual(ledger.tngNotices, [notice])
    }
}


final class ConsecutiveDeletionTests: XCTestCase {
    func testConsecutiveAutomaticDeletesAndBatchUndoPreserveNewTransactions() throws {
        var ledger = Ledger()
        for index in 0..<10 {
            _ = try ledger.receiveTNG(body: "You've just received RM 0.01 in your account ending ***1234. REF: MULTI\(index)", title: "Maybank2u: Funds Received", date: nil, eventID: nil)
        }
        let originals = ledger.tngNotices
        var undo: [DeletedLedgerRecord] = []
        for original in originals {
            undo.append(try ledger.deleteAutomaticRecord(original))
            XCTAssertFalse(ledger.tngNotices.contains { $0.id == original.id })
        }
        XCTAssertTrue(ledger.tngNotices.isEmpty)
        _ = try ledger.receiveTNG(body: "Your transfer of RM0.01 to NEW PERSON is SUCCESSFUL.", title: "Transaction Notice", date: nil, eventID: nil)
        let newID = try XCTUnwrap(ledger.tngNotices.first?.id)
        try ledger.restoreDeletedRecords(undo)
        XCTAssertEqual(ledger.tngNotices.count, 11)
        XCTAssertEqual(Set(ledger.tngNotices.map(\.id)), Set(originals.map(\.id) + [newID]))
    }
}

final class NotificationBuild58Tests: XCTestCase {
    func testDuitNowAndRFID() throws {
        let paid = try XCTUnwrap(parseTNG("You have paid RM40.00 to JENG PAN MEE.", title: "DuitNow Payment"))
        XCTAssertEqual(paid.cents, 4000)
        XCTAssertEqual(paid.party, "JENG PAN MEE")
        let toll = try XCTUnwrap(parseTNG("RM10.58 was deducted via RFID for toll payment on 04-Oct-2026 17:24", title: "Successful Toll Payment"))
        XCTAssertEqual(toll.cents, 1058)
        XCTAssertEqual(toll.transactionDate, ISO8601DateFormatter().date(from: "2026-10-04T09:24:00Z"))
        XCTAssertNil(parseTNG("RM10.58 was deducted via RFID for toll payment on 31-Feb-2026 17:24", title: "Successful Toll Payment"))
    }
    func testUnknownRetainedAndRoundTrip() throws {
        var ledger = Ledger()
        _ = try ledger.receiveTNG(body: "Purchase successful MYR 12.00 at NEW SHOP", title: "HLB Transaction", date: nil, eventID: nil)
        XCTAssertEqual(ledger.expenses.count, 0)
        XCTAssertEqual(ledger.tngNotices.first?.kind, "unknown")
        XCTAssertEqual(ledger.tngNotices.first?.provider, "Hong Leong")
        let copy = try JSONDecoder().decode(Ledger.self, from: JSONEncoder().encode(ledger))
        XCTAssertEqual(copy.tngNotices.first?.body, ledger.tngNotices.first?.body)
        XCTAssertNotNil(copy.tngNotices.first?.reviewReason)
    }
    func testPromotionsAndFailuresDoNotEnterReview() {
        XCTAssertFalse(shouldReviewFinancialNotification("Payment failed RM40.00", title: "Payment"))
        XCTAssertFalse(shouldReviewFinancialNotification("Offer: pay RM40.00", title: "Promotion"))
        XCTAssertFalse(shouldReviewFinancialNotification("Your OTP is 123456", title: "TNG"))
        XCTAssertTrue(shouldReviewFinancialNotification("Refund RM40.00 credited", title: "Refund"))
    }
}

final class NotificationDuplicateScopeTests: XCTestCase {
    func testCrossSourceDuplicateRemainsPending() throws {
        var ledger = Ledger()
        let now = Date()
        ledger.expenses.append(Expense(merchant: "JENG PAN MEE", cents: 4000, date: now, category: "餐饮", source: "Apple Pay"))
        _ = try ledger.receiveTNG(body: "You have paid RM40.00 to JENG PAN MEE.", title: "DuitNow Payment", date: now.addingTimeInterval(30), eventID: nil)
        XCTAssertEqual(ledger.expenses.count, 1)
        XCTAssertEqual(ledger.tngNotices.first?.status, "pending")
        XCTAssertEqual(ledger.tngNotices.first?.possibleDuplicate, true)
        _ = try ledger.validated()
    }
    func testDifferentMerchantOrLaterPaymentIsRecorded() throws {
        for (merchant, delay) in [("OTHER SHOP", 30.0), ("JENG PAN MEE", 180.0)] {
            var ledger = Ledger()
            let now = Date()
            ledger.expenses.append(Expense(merchant: merchant, cents: 4000, date: now, category: "餐饮", source: "Apple Pay"))
            _ = try ledger.receiveTNG(body: "You have paid RM40.00 to JENG PAN MEE.", title: "DuitNow Payment", date: now.addingTimeInterval(delay), eventID: nil)
            XCTAssertEqual(ledger.expenses.count, 2)
            XCTAssertEqual(ledger.tngNotices.first?.possibleDuplicate, false)
            _ = try ledger.validated()
        }
    }
    func testUnknownNoticeDoesNotRequireParsedTransaction() throws {
        var ledger = Ledger()
        _ = try ledger.receiveTNG(body: "Purchase successful MYR 12.00 at NEW SHOP", title: "HLB Transaction", date: nil, eventID: nil)
        XCTAssertEqual(ledger.tngNotices.count, 1)
        XCTAssertEqual(ledger.tngNotices[0].kind, "unknown")
        XCTAssertTrue(ledger.expenses.isEmpty)
        _ = try ledger.validated()
    }
}

final class AutomaticCategoryNotificationTests: XCTestCase {
    func testDescriptionClassification() {
        XCTAssertEqual(guessCategory("JENG PAN MEE"), "餐饮")
        XCTAssertEqual(guessCategory("RFID Toll"), "交通")
        XCTAssertEqual(guessCategory("Maxis Broadband Sdn Bhd"), "账单")
        XCTAssertEqual(guessCategory("ABC SDN BHD", description: "Payment for electricity bill"), "账单")
        XCTAssertEqual(guessCategory("ABC", description: "GrabFood order"), "餐饮")
        XCTAssertEqual(guessCategory("SHELLFISH"), "其他")
        XCTAssertEqual(guessCategory("Unknown merchant"), "其他")
    }
    func testApplePayDescriptionAndUserRule() throws {
        var ledger = Ledger()
        let now = Date()
        _ = try ledger.addPayment(amount: 12, merchant: "ABC", currency: "MYR", date: now, eventID: "description-1", description: "broadband bill")
        XCTAssertEqual(ledger.expenses.last?.category, "账单")
        XCTAssertEqual(ledger.expenses.last?.receiptSummary, "broadband bill")
        ledger.merchantCategories[friendKey("ABC")] = "购物"
        _ = try ledger.addPayment(amount: 13, merchant: "ABC", currency: "MYR", date: now, eventID: "description-2", description: "broadband bill")
        XCTAssertEqual(ledger.expenses.last?.category, "购物")
        _ = try ledger.validated()
    }
    func testTNGResultContainsPersistedCategoryAndAmount() throws {
        var ledger = Ledger()
        let result = try ledger.processTNGNotification(body: "You have paid RM40.00 to JENG PAN MEE.", title: "DuitNow Payment", date: Date(), eventID: "category-1")
        XCTAssertTrue(result.accepted)
        XCTAssertEqual(ledger.expenses.last?.category, "餐饮")
        XCTAssertTrue(result.message.contains("RM 40.00"))
        XCTAssertTrue(result.message.contains("JENG PAN MEE"))
        XCTAssertTrue(result.message.contains(categoryLabel("餐饮")))
        XCTAssertTrue(result.message.contains("TNG"))
    }
    func testBankTransferDoesNotBecomeExpenseFromBillDescription() throws {
        var ledger = Ledger()
        let result = try ledger.processTNGNotification(body: "Your transfer of RM40.00 to MAXIS BROADBAND is SUCCESSFUL.", title: "Transaction Notice", date: Date(), eventID: "bill-transfer")
        XCTAssertTrue(result.accepted)
        XCTAssertTrue(ledger.expenses.isEmpty)
        XCTAssertEqual(ledger.tngNotices.last?.kind, "transfer")
        XCTAssertTrue(result.message.contains("Hong Leong"))
        XCTAssertTrue(result.message.contains(categoryLabel("账单")))
    }
}

final class AutomationWorkflowTests: XCTestCase {
    private func unknown(_ text: String, in ledger: inout Ledger, date: Date) throws -> String {
        _ = try ledger.receiveTNG(body: text, title: "Transaction", date: date, eventID: nil)
        return try XCTUnwrap(ledger.tngNotices.last?.id)
    }
    func testReferenceDistinguishesConsecutiveRealPayments() throws {
        var ledger = Ledger(); let now = Date()
        let text = "You have paid RM40.00 to JENG PAN MEE."
        _ = try ledger.receiveTNG(body: text, title: "DuitNow Payment", date: now, eventID: "order-111")
        _ = try ledger.receiveTNG(body: text, title: "DuitNow Payment", date: now.addingTimeInterval(10), eventID: "order-222")
        XCTAssertEqual(ledger.expenses.count, 2)
        _ = try ledger.receiveTNG(body: text, title: "DuitNow Payment", date: now.addingTimeInterval(20), eventID: "order-222")
        XCTAssertEqual(ledger.expenses.count, 2)
    }
    func testReverseArrivalAndMerchantNormalization() throws {
        var ledger = Ledger(); let now = Date()
        _ = try ledger.receiveTNG(body: "You have paid RM40.00 for Cafe Sdn. Bhd..", title: "Payment", date: now, eventID: nil)
        XCTAssertFalse(try ledger.addPayment(amount: 40, merchant: "CAFE", currency: "MYR", date: now, eventID: "apple-reverse"))
        XCTAssertEqual(ledger.expenses.count, 1)
        let pending = try XCTUnwrap(ledger.tngNotices.last)
        XCTAssertEqual(pending.provider, "Apple Pay")
        XCTAssertTrue(pending.possibleDuplicate)
        try ledger.dismissDuplicateNotice(id: pending.id, expenseID: ledger.expenses[0].id)
        XCTAssertEqual(ledger.tngNotices.last?.resolution, "duplicate")
        _ = try ledger.validated()
    }
    func testRefundAssociatesOnceAndUndoRestoresTotals() throws {
        var ledger = Ledger(); let now = Date().addingTimeInterval(-60)
        ledger.expenses = [Expense(merchant: "Shop", cents: 5000, date: now.addingTimeInterval(-86400))]
        let id = try unknown("Refund RM10.00 credited", in: &ledger, date: now)
        XCTAssertEqual(ledger.tngNotices.last?.cents, 1000)
        try ledger.resolveNotice(id: id, purpose: "refund", party: "Shop", cents: 1000, date: now, relatedID: ledger.expenses[0].id)
        XCTAssertEqual(ledger.expenses[0].refunded, 1000)
        XCTAssertThrowsError(try ledger.resolveNotice(id: id, purpose: "refund", party: "Shop", cents: 1000, date: now, relatedID: ledger.expenses[0].id))
        try ledger.reopenResolvedNotice(id: id)
        XCTAssertEqual(ledger.expenses[0].refunded, 0)
        XCTAssertEqual(ledger.tngNotices.last?.status, "pending")
    }
    func testExcessRefundLeavesLedgerUnchanged() throws {
        var ledger = Ledger(); let now = Date().addingTimeInterval(-60)
        ledger.expenses = [Expense(merchant: "Shop", cents: 1000, date: now.addingTimeInterval(-100))]
        let id = try unknown("Refund RM20.00 credited", in: &ledger, date: now)
        let before = try LocalStore.encode(ledger)
        XCTAssertThrowsError(try ledger.resolveNotice(id: id, purpose: "refund", party: "Shop", cents: 2000, date: now, relatedID: ledger.expenses[0].id))
        XCTAssertEqual(try LocalStore.encode(ledger), before)
    }
    func testRechargePairExcludedAndUndoReopensBoth() throws {
        var ledger = Ledger(); let now = Date().addingTimeInterval(-60)
        let bank = try unknown("Bank transfer RM50.00 to wallet", in: &ledger, date: now)
        let wallet = try unknown("Reload successful RM50.00", in: &ledger, date: now)
        try ledger.resolveNotice(id: wallet, purpose: "ownTransfer", party: "My TNG wallet", cents: 5000, date: now, relatedID: bank)
        XCTAssertTrue(ledger.expenses.isEmpty)
        XCTAssertTrue(ledger.tngNotices.allSatisfy { $0.resolution == "ownTransfer" && $0.status == "ignored" })
        try ledger.reopenResolvedNotice(id: wallet)
        XCTAssertTrue(ledger.tngNotices.allSatisfy { $0.resolution == nil && $0.status == "pending" })
    }
    func testConfirmedExpenseRemembersMerchantAndCannotReplay() throws {
        var ledger = Ledger(); let now = Date().addingTimeInterval(-60)
        let id = try unknown("Purchase RM20.00 at ABC", in: &ledger, date: now)
        try ledger.resolveNotice(id: id, purpose: "expense", party: "ABC", cents: 2000, date: now, category: "餐饮", remember: true)
        XCTAssertEqual(ledger.merchantCategories[friendKey("ABC")], "餐饮")
        XCTAssertThrowsError(try ledger.resolveNotice(id: id, purpose: "expense", party: "ABC", cents: 2000, date: now, category: "餐饮"))
        XCTAssertEqual(ledger.expenses.count, 1)
    }
    func testUnknownIncomeAndBackupRoundTrip() throws {
        var ledger = Ledger(); let now = Date().addingTimeInterval(-60)
        let id = try unknown("Salary credited RM2000.00", in: &ledger, date: now)
        try ledger.resolveNotice(id: id, purpose: "income", party: "Employer", cents: 200000, date: now)
        let restored = try LocalStore.decode(LocalStore.encode(ledger))
        XCTAssertEqual(restored.tngNotices[0].status, "income")
        XCTAssertTrue(restored.expenses.isEmpty)
    }
    func testAmountExtractionAvoidsBalancesAndMalformedNumbers() {
        XCTAssertEqual(singleNotificationAmount("Refund RM1,234.50 credited"), 123450)
        XCTAssertNil(singleNotificationAmount("RM12.00 paid, balance RM200.00"))
        XCTAssertNil(singleNotificationAmount("RM12.345"))
        XCTAssertNil(singleNotificationAmount("RM-12.00"))
        XCTAssertEqual(notificationReference("REF: TXN-12345"), "TXN-12345")
    }
    func testLogOutcomeAndNotificationTargets() throws {
        var ledger = Ledger()
        let paid = try ledger.processTNGNotification(body: "You have paid RM40.00 to JENG PAN MEE.", title: "DuitNow Payment", date: Date(), eventID: "target-1")
        XCTAssertNotNil(paid.expenseID); XCTAssertNotNil(paid.noticeID)
        XCTAssertEqual(ledger.automationEvents.first?.outcome, "saved")
        let repeated = try ledger.processTNGNotification(body: "You have paid RM40.00 to JENG PAN MEE.", title: "DuitNow Payment", date: Date(), eventID: "target-1")
        XCTAssertNil(repeated.expenseID); XCTAssertNil(repeated.noticeID)
        XCTAssertEqual(ledger.automationEvents.first?.outcome, "duplicate")
        let unknown = try ledger.processTNGNotification(body: "Purchase RM9.00 at NEW", title: "Transaction", date: nil, eventID: nil)
        XCTAssertNil(unknown.expenseID); XCTAssertNotNil(unknown.noticeID)
        XCTAssertEqual(ledger.automationEvents.first?.outcome, "pending")
    }
}

final class ItemsOnlyMigrationTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_700_000_000)
    private func legacyExpense() -> Expense {
        Expense(id: "old-purchase", merchant: "TNG Store", cents: 3500, date: date,
            category: "购物", source: "TNG", categoryAllocations: [
                CategoryAllocation(id: "food-part", category: "餐饮", cents: 1500),
                CategoryAllocation(id: "shopping-part", category: "购物", cents: 2000)])
    }

    func testLegacyCategoryMigrationPreservesRefundsRepaymentsAndAutomaticLink() throws {
        var old = legacyExpense()
        old.foreign = ForeignAmount(currency: "USD", minor: 1750, quote: RateQuote(value: 2, date: date, source: "Manual"))
        old.shares = [Share(id: "amy", name: "Amy", cents: 1000,
            repayments: [Repayment(id: "repayment", cents: 200, date: date.addingTimeInterval(60))], refundCents: 200)]
        old.refunds = [RefundRecord(id: "refund", cents: 600, date: date.addingTimeInterval(120), personalCents: 400, shares: ["amy": 200])]
        old.note = "Keep this note"; old.tags = ["Trip"]
        old.receiptSummary = "Original receipt"; old.transactionReference = "BANK-OLD"
        var ledger = Ledger(expenses: [old], seenEvents: ["bank-event"], postedRecurring: ["schedule-event"])
        ledger.tngNotices = [TNGNotice(id: "bank", body: "Paid RM35.00", title: "Payment", date: date,
            usesReceivedDate: false, kind: "payment", status: "recorded", cents: 3500, party: old.merchant,
            expenseID: old.id, bankReference: "BANK-OLD")]
        let migrated = try LocalStore.decode(LocalStore.encode(ledger))
        var expected = old
        expected.categoryAllocations = nil
        expected.items = [ExpenseItem(id: "food-part", name: "餐饮", cents: 1500, category: "餐饮"),
                          ExpenseItem(id: "shopping-part", name: "购物", cents: 2000, category: "购物")]
        XCTAssertEqual(migrated.expenses, [expected])
        XCTAssertEqual(migrated.tngNotices, ledger.tngNotices)
        XCTAssertEqual(migrated.seenEvents, ledger.seenEvents)
        XCTAssertEqual(migrated.postedRecurring, ledger.postedRecurring)
        XCTAssertEqual(migrated.expenses[0].paidFromMyAccount, 3500)
        XCTAssertEqual(migrated.spending(in: date), 2100)
        XCTAssertEqual(migrated.spending(in: date, category: "餐饮"), 900)
        XCTAssertEqual(migrated.spending(in: date, category: "购物"), 1200)
        XCTAssertEqual(migrated.friendDebtItems.map(\.balance), ledger.friendDebtItems.map(\.balance))
        XCTAssertEqual(migrated.friendSpending(friend: "Amy").categories, ledger.friendSpending(friend: "Amy").categories)
        XCTAssertEqual(OverviewSnapshot(ledger: migrated, month: date).categoryTotals,
                       OverviewSnapshot(ledger: ledger, month: date).categoryTotals)
    }

    func testMigratedItemsPreserveRoundingForEveryPersonalShare() throws {
        for share in 0...3 {
            let old = Expense(id: "tiny", merchant: "Three cents", cents: 3, date: date, category: "餐饮",
                shares: [Share(id: "amy", name: "Amy", cents: share)], categoryAllocations: [
                    CategoryAllocation(id: "first", category: "餐饮", cents: 1),
                    CategoryAllocation(id: "second", category: "购物", cents: 2)])
            let migrated = try Ledger(expenses: [old]).validated().expenses[0]
            XCTAssertEqual(migrated.items?.map(\.id), ["first", "second"])
            for total in 0...3 {
                XCTAssertEqual(migrated.categoryDistribution(total: total), old.categoryDistribution(total: total))
                XCTAssertEqual(migrated.categoryDistribution(total: total).values.reduce(0, +), total)
            }
            XCTAssertEqual(migrated.personalItemAmounts.values.reduce(0, +), old.personal)
        }
    }

    func testMigrationKeepsPartialAndOffsetSettlementsRM55BankLinksAndUndo() throws {
        var lunch = Expense(id: "lunch", merchant: "Lunch", cents: 6000, date: date, category: "餐饮",
            shares: [Share(id: "lunch-amy", name: "Amy", cents: 3000)], categoryAllocations: [
                CategoryAllocation(id: "lunch-food", category: "餐饮", cents: 4000),
                CategoryAllocation(id: "lunch-shopping", category: "购物", cents: 2000)])
        lunch.note = "Do not lose lunch"
        let drinks = Expense(id: "drinks", merchant: "Drinks", cents: 2000, date: date, category: "餐饮",
            shares: [Share(id: "drinks-amy", name: "Amy", cents: 1000)], categoryAllocations: [
                CategoryAllocation(id: "drinks-food", category: "餐饮", cents: 1000),
                CategoryAllocation(id: "drinks-entertainment", category: "娱乐", cents: 1000)], paidByFriend: "Amy")
        let mine = Expense(id: "mine", merchant: "Mine", cents: 1500, date: date, category: "购物",
            shares: [Share(id: "mine-amy", name: "Amy", cents: 0)], paidByFriend: "Amy")
        for payment in [0, 200, 500] {
            var old = Ledger(expenses: [lunch, drinks, mine])
            let settlementDate = date.addingTimeInterval(3600)
            let plan = try old.settlementPlan(friend: "Amy", selected: Set(old.friendDebtItems.map(\.id)), payment: payment, date: settlementDate)
            // Construct the historical audit before normalization, as an old backup did.
            old.settlements = [FriendSettlement(id: "net-settlement", friend: plan.friend, name: plan.name,
                date: plan.date, lines: plan.lines, transfer: plan.transfer, paymentNoticeID: payment == 0 ? nil : "bank")]
            if payment > 0 {
                old.tngNotices = [TNGNotice(id: "bank", body: "Payment received", title: "Incoming", date: settlementDate,
                    usesReceivedDate: false, kind: "incoming", status: "settlement", cents: payment, party: "Amy",
                    bankReference: "NET-PAYMENT", settlementID: "net-settlement")]
            }
            let beforeCategories = OverviewSnapshot(ledger: old, month: date).categoryTotals
            var migrated = try LocalStore.decode(LocalStore.encode(old))
            XCTAssertEqual(migrated.spending(in: date), 5500)
            XCTAssertEqual(OverviewSnapshot(ledger: migrated, month: date).categoryTotals, beforeCategories)
            XCTAssertEqual(migrated.friendBalances[0].owed, 500 - payment)
            XCTAssertEqual(migrated.friendBalances[0].payable, 0)
            XCTAssertEqual(migrated.settlements[0].transfer, payment)
            XCTAssertEqual(migrated.settlements[0].paymentNoticeID, payment == 0 ? nil : "bank")
            XCTAssertEqual(migrated.settlements[0].lines.map(\.before), old.settlements[0].lines.map(\.before))
            XCTAssertEqual(migrated.settlements[0].lines.map(\.applied), old.settlements[0].lines.map(\.applied))
            for line in migrated.settlements[0].lines {
                let entry = try XCTUnwrap(migrated.expenses.first { $0.id == line.expense.id })
                XCTAssertTrue(entry.sameSettlementTerms(as: line.expense))
                XCTAssertNil(line.expense.categoryAllocations)
            }
            let entries = migrated.expenses
            XCTAssertThrowsError(try migrated.addRefund(expenseID: "lunch", cents: 100, date: settlementDate))
            try migrated.undoSettlement(id: "net-settlement")
            XCTAssertEqual(migrated.expenses, entries)
            XCTAssertEqual(migrated.friendBalances[0].owed, 3000)
            XCTAssertEqual(migrated.friendBalances[0].payable, 2500)
            XCTAssertEqual(migrated.tngNotices.count, payment == 0 ? 0 : 1)
            if payment > 0 { XCTAssertEqual(migrated.tngNotices[0].status, "pending") }
            XCTAssertEqual(migrated.spending(in: date), 5500)
            XCTAssertEqual(migrated.expenses[1].purchaseDisplayCents, 1000)
            XCTAssertEqual(migrated.expenses[1].paidFromMyAccount, 0)
        }
    }

    func testVoidedSettlementAndConvertedPaymentAuditsMigrateWithoutExtraSpending() throws {
        var old = Ledger(expenses: [Expense(id: "live", merchant: "Live", cents: 1000, date: date,
            shares: [Share(id: "amy", name: "Amy", cents: 1000)])])
        let plan = try old.settlementPlan(friend: "Amy", selected: Set(old.friendDebtItems.map(\.id)), payment: 1000, date: date)
        var archived = plan.lines[0].expense
        archived.categoryAllocations = [CategoryAllocation(id: "a", category: "餐饮", cents: 600),
                                       CategoryAllocation(id: "b", category: "购物", cents: 400)]
        let archivedLine = SettlementLine(expense: archived, shareID: plan.lines[0].shareID, before: 1000, applied: 1000)
        old.settlements = [FriendSettlement(id: "voided", friend: plan.friend, name: plan.name, date: date,
            lines: [archivedLine], transfer: 1000, voidedAt: date.addingTimeInterval(60), convertedPayment: legacyExpense())]
        let migrated = try LocalStore.decode(LocalStore.encode(old))
        XCTAssertEqual(migrated.expenses, old.expenses)
        XCTAssertEqual(migrated.spending(in: date), old.spending(in: date))
        XCTAssertFalse(migrated.settlements[0].active)
        XCTAssertEqual(migrated.settlements[0].voidedAt, old.settlements[0].voidedAt)
        XCTAssertEqual(migrated.settlements[0].lines[0].expense.items?.map(\.cents), [600, 400])
        XCTAssertNil(migrated.settlements[0].lines[0].expense.categoryAllocations)
        XCTAssertEqual(migrated.settlements[0].convertedPayment?.items?.map(\.cents), [1500, 2000])
        XCTAssertEqual(migrated.settlements[0].convertedPayment?.id, "old-purchase")
    }

    func testAllBackupVersionsMigrateCustomCategoriesAndRemainIdempotent() throws {
        var old = legacyExpense()
        let custom = CustomCategory(name: "Household")
        old.categoryAllocations?[1].category = custom.name
        var ledger = Ledger(expenses: [old]); ledger.customCategories = [custom]
        let data = try LocalStore.encode(ledger)
        for version in 1...6 {
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            object["version"] = version
            let restored = try LocalStore.decode(JSONSerialization.data(withJSONObject: object))
            XCTAssertEqual(restored.version, 6)
            XCTAssertEqual(restored.expenses[0].items?.map(\.category), ["餐饮", "Household"])
            XCTAssertEqual(restored.spending(in: date, category: "Household"), 2000)
            let exported = try LocalStore.exportData(restored)
            let again = try LocalStore.decode(exported)
            XCTAssertEqual(again.expenses, restored.expenses)
            XCTAssertEqual(try again.validated().expenses, restored.expenses)
            let saved = try XCTUnwrap(JSONSerialization.jsonObject(with: exported) as? [String: Any])
            let entries = try XCTUnwrap(saved["expenses"] as? [[String: Any]])
            XCTAssertNil(entries[0]["categoryAllocations"])
            XCTAssertEqual((entries[0]["items"] as? [[String: Any]])?.count, 2)
        }
        let existing = Expense(id: "itemized", merchant: "Already items", cents: 3500, date: date,
            items: [ExpenseItem(id: "real-lunch", name: "Lunch", cents: 1500, category: "餐饮"),
                    ExpenseItem(id: "real-dinner", name: "Dinner", cents: 2000, category: "餐饮")])
        XCTAssertEqual(try Ledger(expenses: [existing]).validated().expenses, [existing])
    }

    func testStorageMigrationPreservesRawFileUntilSaveAndRejectsCorruptRestore() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("ledger.json")
        let old = Ledger(expenses: [legacyExpense()])
        let raw = try LocalStore.encode(old)
        try raw.write(to: file)
        let store = LocalStore(folder: folder)
        let visible = try store.read()
        XCTAssertNil(visible.expenses[0].categoryAllocations)
        XCTAssertEqual(visible.expenses[0].items?.count, 2)
        XCTAssertEqual(try Data(contentsOf: file), raw, "Reading migration must not overwrite the original file")
        try store.change { $0.expenses[0].note = "Saved note" }
        let saved = try store.read()
        XCTAssertEqual(saved.spending(in: date), 3500)
        XCTAssertEqual(saved.expenses[0].category, "购物", "Migration must retain the parent category, even when it is not the first split")
        XCTAssertEqual(saved.expenses[0].note, "Saved note")
        XCTAssertEqual(saved.expenses[0].items, visible.expenses[0].items)
        let bytes = try Data(contentsOf: file)
        var corrupt = old; corrupt.expenses[0].categoryAllocations?[0].cents += 1
        XCTAssertThrowsError(try store.restore(LocalStore.encode(corrupt)))
        XCTAssertEqual(try Data(contentsOf: file), bytes)
        let backups = try store.backups()
        XCTAssertFalse(backups.isEmpty)
        XCTAssertEqual(try LocalStore.decode(Data(contentsOf: XCTUnwrap(backups.first))).spending(in: date), 3500)
    }

    func testOversizedLegacyAllocationIDsBecomeStableValidItemIDs() throws {
        var old = legacyExpense()
        old.categoryAllocations?[0].id = String(repeating: "old-id", count: 100)
        let data = try LocalStore.encode(Ledger(expenses: [old]))
        let first = try LocalStore.decode(data).expenses[0]
        let second = try LocalStore.decode(data).expenses[0]
        XCTAssertEqual(first.items, second.items)
        XCTAssertTrue(first.items?.allSatisfy { $0.id.count <= 200 } == true)
        XCTAssertEqual(first.items?[1].id, "shopping-part")
        XCTAssertEqual(first.categoryDistribution(total: first.personal), old.categoryDistribution(total: old.personal))
    }
}

final class BookkeepingBuild62Tests: XCTestCase {
    private func splitExpense() -> Expense {
        Expense(merchant: "Supermarket", cents: 10000, category: "餐饮", categoryAllocations: [CategoryAllocation(category: "餐饮", cents: 7000), CategoryAllocation(category: "购物", cents: 3000)])
    }
    func testCategorySplitTotalsAndRefundProportions() throws {
        var ledger = Ledger(); var expense = splitExpense()
        expense.date = Date().addingTimeInterval(-3600)
        expense.shares = [Share(name: "Friend", cents: 4000)]
        ledger.expenses = [expense]
        XCTAssertEqual(ledger.spending(in: expense.date, category: "餐饮"), 4200)
        XCTAssertEqual(ledger.spending(in: expense.date, category: "购物"), 1800)
        XCTAssertEqual(ledger.spending(in: expense.date), 6000)
        try ledger.addRefund(expenseID: expense.id, cents: 1000, date: Date())
        XCTAssertEqual(ledger.spending(in: expense.date), 5400)
        XCTAssertEqual(ledger.expenses[0].categoryDistribution(total: ledger.expenses[0].personal).values.reduce(0, +), 5400)
        XCTAssertEqual(ledger.friendSpending(friend: "Friend").categories.values.reduce(0, +), 3600)
        _ = try ledger.validated()
    }
    func testSplitRoundingPreservesEveryCentAndRejectsBadSum() throws {
        var e = Expense(merchant: "Test", cents: 3, category: "餐饮", shares: [Share(name: "A", cents: 1)], categoryAllocations: [CategoryAllocation(category: "餐饮", cents: 1), CategoryAllocation(category: "购物", cents: 2)])
        XCTAssertEqual(e.categoryDistribution(total: e.personal).values.reduce(0, +), 2)
        var ledger = Ledger(expenses: [e]); _ = try ledger.validated()
        e.categoryAllocations?[0].cents = 2; ledger.expenses = [e]
        XCTAssertThrowsError(try ledger.validated())
        ledger.expenses = [splitExpense()]; ledger.expenses[0].categoryAllocations?[1].category = "餐饮"
        XCTAssertThrowsError(try ledger.validated())
    }
    func testCustomCategoryRenameUpdatesAllocations() throws {
        var ledger = Ledger(); let custom = CustomCategory(name: "日用品")
        try ledger.saveCategory(custom)
        var expense = splitExpense(); expense.categoryAllocations?[1].category = custom.name; ledger.expenses = [expense]
        XCTAssertThrowsError(try ledger.deleteCategory(custom.id))
        var renamed = custom; renamed.name = "家庭用品"; try ledger.saveCategory(renamed)
        XCTAssertEqual(ledger.expenses[0].categoryAllocations?[1].category, "家庭用品")
        _ = try ledger.validated()
    }
    func testTagsNotesAndSplitSearch() throws {
        var ledger = Ledger()
        var e = splitExpense(); e.note = "Family lunch"; e.tags = normalizedExpenseTags("槟城旅行, 家庭,槟城旅行")
        ledger.expenses = [e]
        XCTAssertEqual(e.tags?.count, 2)
        var filter = LedgerFilter(); filter.category = "购物"
        XCTAssertEqual(try ledger.filteredEntries(in: e.date, search: "槟城", filter: filter).count, 1)
        XCTAssertEqual(try ledger.filteredEntries(in: e.date, search: "family lunch", filter: filter).count, 1)
        // The existing ISO-8601 backup format stores whole seconds, while Date()
        // includes fractional seconds. Compare every field against that contract.
        e.date = Date(timeIntervalSince1970: 1_759_680_000.75)
        ledger.expenses = [e]
        let copy = try LocalStore.decode(LocalStore.encode(ledger))
        var expected = e
        expected.date = Date(timeIntervalSince1970: 1_759_680_000)
        expected.items = (e.categoryAllocations ?? []).map { ExpenseItem(id: $0.id, name: $0.category, cents: $0.cents, category: $0.category) }
        expected.categoryAllocations = nil
        XCTAssertEqual(copy.expenses[0], expected)
        XCTAssertEqual(copy.expenses[0].date.timeIntervalSince1970, 1_759_680_000)
        XCTAssertEqual(try LocalStore.decode(LocalStore.encode(copy)).expenses, copy.expenses)
        XCTAssertEqual(copy.spending(in: e.date), ledger.spending(in: e.date))
        let exported = String(decoding: ledger.csv(month: nil, splits: false), as: UTF8.self)
        XCTAssertTrue(exported.contains("category_allocations_MYR")); XCTAssertTrue(exported.contains("槟城旅行"))
    }
    func testRemovedFeatureFieldsDoNotPreventBackupRestore() throws {
        var e = splitExpense()
        e.date = Date(timeIntervalSince1970: 1_759_680_000)
        e.note = "Keep this purchase"; e.tags = ["旅行"]
        let ledger = Ledger(expenses: [e])
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: LocalStore.encode(ledger)) as? [String: Any])
        object["paymentAccounts"] = [["id": "legacy", "name": "Wallet", "kind": "wallet", "provider": "TNG", "lastFour": "", "archived": false]]
        object["sourceAccountDefaults"] = ["TNG": "legacy"]
        object["expenseHistory"] = [["id": "old-revision", "expenseID": e.id]]
        object["statementLines"] = [["id": "old-line", "expenseID": e.id]]
        var entries = try XCTUnwrap(object["expenses"] as? [[String: Any]])
        entries[0]["paymentAccountID"] = "legacy"; object["expenses"] = entries
        let restored = try LocalStore.decode(JSONSerialization.data(withJSONObject: object))
        var expected = e
        expected.items = (e.categoryAllocations ?? []).map { ExpenseItem(id: $0.id, name: $0.category, cents: $0.cents, category: $0.category) }
        expected.categoryAllocations = nil
        XCTAssertEqual(restored.expenses, [expected])
        let saved = try XCTUnwrap(JSONSerialization.jsonObject(with: LocalStore.encode(restored)) as? [String: Any])
        for key in ["paymentAccounts", "sourceAccountDefaults", "expenseHistory", "statementLines"] { XCTAssertNil(saved[key]) }
        XCTAssertEqual(restored.spending(in: e.date, category: "购物"), 3000)
    }
}

// Synthetic grammar fixtures exercise universal behavior; they are not claimed
// to be real notification samples from the named banks.
final class UniversalBankAndPaymentTimeTests: XCTestCase {
    func testObservedMyPBFPXPayment() throws {
        let body = "FPX Payment: You have paid RM47.08 to SHOPEE MALAYSIA via MyPB."
        for source in [nil, "MyPB", "Public Bank"] as [String?] {
            var ledger = Ledger()
            let date = Date()
            let result = try ledger.processTNGNotification(body: body, title: "Money Paid", date: date, eventID: "pb-fpx-4708", sourceApp: source)
            XCTAssertNotNil(result.expenseID)
            XCTAssertEqual(ledger.expenses.first?.cents, 4708)
            XCTAssertEqual(ledger.expenses.first?.merchant, "SHOPEE MALAYSIA")
            XCTAssertEqual(ledger.expenses.first?.source, "Public Bank")
            _ = try ledger.processTNGNotification(body: body, title: "Money Paid", date: date, eventID: "pb-fpx-4708", sourceApp: source)
            XCTAssertEqual(ledger.expenses.count, 1)
        }
        XCTAssertEqual(parseFinancialNotification("Money Paid\n" + body)?.party, "SHOPEE MALAYSIA")
        XCTAssertEqual(parseFinancialNotification(body)?.sourceBank, "Public Bank")
    }

    func testSharedPaymentWrappersAcrossEntireProviderDirectory() throws {
        // Synthetic fixtures test shared grammar, not real samples from every bank.
        for (provider, aliases) in financialProviderAliases {
            for alias in aliases {
                let body = "FPX Payment: You have paid RM47.08 to SHOPEE MALAYSIA via " + alias + "."
                let parsed = try XCTUnwrap(parseFinancialNotification(body, title: "Money Paid", sourceApp: provider), alias)
                XCTAssertEqual(parsed.party, "SHOPEE MALAYSIA", alias)
                XCTAssertEqual(parsed.sourceBank, provider, alias)
                XCTAssertEqual(parsed.cents, 4708, alias)
            }
        }
        for prefix in ["FPX Payment", "DuitNow QR Payment", "QR Payment", "Card Payment", "Online Payment"] {
            XCTAssertEqual(parseFinancialNotification(prefix + ": You have paid RM47.08 to SHOP via New Bank.", sourceApp: "New Bank")?.party, "SHOP")
        }
        for body in ["FPX Payment: You have paid RM47.08 to SHOP via MyPB. Payment failed.",
                     "FPX Payment: Approve this payment of RM47.08 to SHOP via MyPB.",
                     "FPX Payment: You have paid USD47.08 to SHOP via MyPB.",
                     "FPX Payment: You have paid RM47.08 to SHOP via MyPB. Available balance RM100.00",
                     "FPX Payment: You have paid RM47.08 to SHOP via Unknown Channel."] {
            XCTAssertNil(parseFinancialNotification(body, title: "Money Paid"), body)
        }
        XCTAssertNil(parseFinancialNotification("FPX Payment: You have paid RM47.08 to SHOP via MyPB.", sourceApp: "CIMB"))
    }
    private let captured = ISO8601DateFormatter().date(from: "2026-10-07T14:26:50Z")!
    private let noon = ISO8601DateFormatter().date(from: "2026-10-07T04:00:00Z")!

    func testAnySourceCanSaveCompletedPaymentAndRoundTrip() throws {
        let sources = ["CIMB", "Public Bank", "HSBC", "OCBC", "UOB", "Standard Chartered", "Affin Bank", "Alliance Bank", "BSN", "Bank Islam", "Bank Rakyat", "GXBank", "Boost Bank", "AEON Bank", "KAF Digital Bank", "A New Bank Not In The Directory"]
        for source in sources {
            var ledger = Ledger()
            var input = AutomationDelivery(kind: "notification", body: "Payment of MYR12.50 at LUNCH CAFE was successful.", title: "Card activity")
            input.sourceApp = source; input.receivedAt = captured
            let result = try ledger.applyDelivery(input)
            XCTAssertNotNil(result.expenseID, source)
            XCTAssertEqual(ledger.expenses.first?.cents, 1250, source)
            XCTAssertEqual(ledger.expenses.first?.merchant, "LUNCH CAFE", source)
            XCTAssertEqual(ledger.expenses.first?.source, source, source)
            XCTAssertEqual(ledger.expenses.first?.date, captured, source)
            XCTAssertTrue(ledger.availableSources.contains(source))
            let restored = try LocalStore.decode(LocalStore.encode(ledger))
            XCTAssertEqual(restored.expenses, ledger.expenses)
            XCTAssertEqual(restored.tngNotices, ledger.tngNotices)
            _ = try ledger.applyDelivery(input)
            XCTAssertEqual(ledger.expenses.count, 1)
        }
    }
    func testMultilingualAndStructuredPayment() throws {
        let cases: [(String, String, Int, String)] = [
            ("Card activity", "You have paid RM5.00 to MHH CUISINE.", 500, "MHH CUISINE"),
            ("Card activity", "Your debit card ending 1234 was charged MYR12.50 at LUNCH CAFE.", 1250, "LUNCH CAFE"),
            ("", "Anda telah membayar RM8.50 kepada KEDAI MAKAN.", 850, "KEDAI MAKAN"),
            ("", "Pembayaran RM8.50 kepada KEDAI MAKAN berjaya.", 850, "KEDAI MAKAN"),
            ("", "您已支付RM8.50给早餐店。", 850, "早餐店"),
            ("Payment successful", "Amount: MYR18.20\nMerchant: FRESH MART\nReference: ABC-123", 1820, "FRESH MART")
        ]
        for (title, body, cents, merchant) in cases {
            let parsed = try XCTUnwrap(parseFinancialNotification(body, title: title, sourceApp: "New Bank"), body)
            XCTAssertEqual(parsed.kind, "payment"); XCTAssertEqual(parsed.cents, cents)
            XCTAssertEqual(parsed.party, merchant); XCTAssertEqual(parsed.sourceBank, "New Bank")
        }
        XCTAssertEqual(parseFinancialNotification("Payment of MYR12.50 at CAFE was successful on 2026-10-07 22:26:50 Ref: ABC123", sourceApp: "CIMB")?.transactionDate, captured)
        XCTAssertNil(parseFinancialNotification("Payment of MYR12.50 at CAFE was successful on 2026-02-31 22:26:50", sourceApp: "CIMB"))
    }
    func testPromotionsAndApprovalsIgnoredButUnclearTransactionsRetained() throws {
        for body in ["Make 2 QR payments with NETS QR and earn up to RM10 cashback.", "Payment failed RM20.00", "Your OTP for payment RM20.00 is 123456", "Approve this transaction of RM20.00", "Payment due RM20.00", "消费满RM20最高返现RM10"] {
            var ledger = Ledger()
            var input = AutomationDelivery(kind: "notification", body: body)
            input.sourceApp = "CIMB"
            let result = try ledger.applyDelivery(input)
            XCTAssertFalse(result.shouldNotify, body)
            XCTAssertTrue(ledger.expenses.isEmpty); XCTAssertTrue(ledger.tngNotices.isEmpty)
        }
        for body in ["Your purchase of USD10.00 was completed.", "Payment of RM10.00 successful. Available balance RM200.00", "Cashback of RM10.00 credited to your account.", "Refund RM10.00 credited.", "Top up RM10.00 successful", "Payment successful", "Purchase successful MYR12.00 at NEW SHOP"] {
            var ledger = Ledger()
            _ = try ledger.processTNGNotification(body: body, date: captured, eventID: nil, sourceApp: "New Bank")
            XCTAssertTrue(ledger.expenses.isEmpty, body)
            XCTAssertEqual(ledger.tngNotices.count, 1, body)
            XCTAssertEqual(ledger.tngNotices.first?.status, "pending")
        }
        XCTAssertFalse(shouldReviewFinancialNotification("No transaction information", title: ""))
        XCTAssertNil(parseFinancialNotification("You've sent MYR0.01 to FRIEND.", title: "Funds Received"))
        XCTAssertNil(parseFinancialNotification("You have paid RM1,23.00 to SHOP.", title: "Card activity", sourceApp: "CIMB"))
    }
    func testTransfersAndIncomingNeverBecomeExpense() throws {
        for (body, kind) in [("You have transferred MYR10.00 to AMY.", "transfer"), ("You have received MYR10.00 from AMY.", "incoming")] {
            var ledger = Ledger()
            _ = try ledger.processTNGNotification(body: body, date: captured, eventID: nil, sourceApp: "New Bank")
            XCTAssertTrue(ledger.expenses.isEmpty)
            XCTAssertEqual(ledger.tngNotices.first?.kind, kind)
            _ = try ledger.validated()
        }
    }
    func testLiveApplePayIgnoresNoonInputAndSurvivesRecovery() throws {
        var input = AutomationDelivery(kind: "applePay", date: noon, amount: 5, merchant: "CAFE")
        input.receivedAt = captured; input.useTransactionDate = false
        let recovered = try JSONDecoder().decode(AutomationDelivery.self, from: JSONEncoder().encode(input))
        var ledger = Ledger()
        _ = try ledger.applyDelivery(recovered)
        XCTAssertEqual(ledger.expenses.first?.date, captured)
        XCTAssertEqual(ledger.expenses.first?.timeSource, "received")
        _ = try ledger.applyDelivery(recovered)
        XCTAssertEqual(ledger.expenses.count, 1)
        XCTAssertEqual(ledger.expenses.first?.date, captured)
        let restored = try LocalStore.decode(LocalStore.encode(ledger))
        XCTAssertEqual(restored.expenses.first?.timeSource, "received")
    }
    func testImportPreservesNoonAndLegacyQueueRemainsCompatible() throws {
        let modes: [Bool?] = [true, nil]
        for mode in modes {
            var input = AutomationDelivery(kind: "applePay", date: noon, amount: 5, merchant: "CAFE")
            input.receivedAt = captured; input.useTransactionDate = mode
            var ledger = Ledger(); _ = try ledger.applyDelivery(input)
            XCTAssertEqual(ledger.expenses.first?.date, noon)
        }
        var missing = AutomationDelivery(kind: "applePay", amount: 5, merchant: "CAFE")
        missing.useTransactionDate = true
        var ledger = Ledger()
        XCTAssertThrowsError(try ledger.applyDelivery(missing))
        missing.useTransactionDate = false; missing.receivedAt = captured
        _ = try ledger.applyDelivery(missing)
        XCTAssertEqual(ledger.expenses.first?.date, captured)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(missing)) as? [String: Any])
        json.removeValue(forKey: "sourceApp"); json.removeValue(forKey: "useTransactionDate")
        let old = try JSONDecoder().decode(AutomationDelivery.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(old.useTransactionDate)
    }
    func testBankAndLiveApplePayDuplicateIsReviewable() throws {
        var ledger = Ledger()
        _ = try ledger.processTNGNotification(body: "Payment of MYR5.00 at CAFE was successful.", date: captured, eventID: nil, sourceApp: "CIMB")
        var input = AutomationDelivery(kind: "applePay", date: noon, amount: 5, merchant: "CAFE")
        input.receivedAt = captured.addingTimeInterval(10); input.useTransactionDate = false
        let result = try ledger.applyDelivery(input)
        XCTAssertNil(result.expenseID); XCTAssertNotNil(result.noticeID)
        XCTAssertEqual(ledger.expenses.count, 1)
        XCTAssertTrue(ledger.tngNotices.last?.possibleDuplicate == true)
    }
    func testSourceBoundsAndAliases() {
        XCTAssertEqual(financialProvider("CIMB OCTO"), "CIMB")
        XCTAssertEqual(parseFinancialNotification("Your transfer of RM10.00 to AMY is SUCCESSFUL.", sourceApp: "CIMB")?.sourceBank, "CIMB")
        XCTAssertNil(parseFinancialNotification("HSBC: Payment of RM10.00 at CAFE was successful.", sourceApp: "CIMB"))
        XCTAssertNil(financialProvider("MAESTRO CAFE"))
        XCTAssertFalse(validFinancialSource("\nCIMB"))
        XCTAssertFalse(validFinancialSource(String(repeating: "a", count: 121)))
        XCTAssertTrue(validFinancialSource("Another Bank"))
    }
}

final class DirectionNotificationSoundTests: XCTestCase {
    func testDirectionFromSavedResultAndNeutralForDuplicateOrUnknown() throws {
        let now = Date()
        var ledger = Ledger()
        let incoming = try ledger.applyDelivery(AutomationDelivery(kind: "notification", body: "RM 10.00 received from AMY for ME.", title: "Ka-ching! Incoming Money.", date: now))
        XCTAssertEqual(incoming.sound, .incoming)
        XCTAssertTrue(ledger.expenses.isEmpty)
        let transfer = try ledger.applyDelivery(AutomationDelivery(kind: "notification", body: "RM 20.00 has been successfully transferred to SAM.", title: "Transfer Successful", date: now))
        XCTAssertEqual(transfer.sound, .outgoing)
        var apple = AutomationDelivery(kind: "applePay", amount: 8, merchant: "CAFE")
        apple.useTransactionDate = false
        let paid = try ledger.applyDelivery(apple)
        XCTAssertEqual(paid.sound, .outgoing)
        XCTAssertNotNil(paid.expenseID)
        let repeatResult = try ledger.applyDelivery(apple)
        XCTAssertEqual(repeatResult.sound, .neutral)
        let duplicate = try ledger.applyDelivery(AutomationDelivery(kind: "notification", body: "RM 10.00 received from AMY for ME.", title: "Ka-ching! Incoming Money.", date: now.addingTimeInterval(15)))
        XCTAssertEqual(duplicate.sound, .neutral)
        let unknown = try ledger.applyDelivery(AutomationDelivery(kind: "notification", body: "Refund RM5.00 credited", date: now))
        XCTAssertEqual(unknown.sound, .neutral)
        let ad = try ledger.applyDelivery(AutomationDelivery(kind: "notification", body: "Make 2 QR payments and earn up to RM10 cashback."))
        XCTAssertFalse(ad.shouldNotify)
        XCTAssertEqual(ad.sound, .neutral)
    }
    @MainActor func testSystemSoundsAreDistinctBundledDecodableFiles() throws {
        let incoming = LedgerNotifications.soundName(for: .incoming)
        let outgoing = LedgerNotifications.soundName(for: .outgoing)
        XCTAssertNotEqual(incoming, outgoing)
        XCTAssertEqual(LedgerNotifications.soundName(for: .neutral), LedgerNotifications.automationSoundName)
        for name in [incoming, outgoing] {
            let url = try XCTUnwrap(Bundle.main.url(forResource: String(name.dropLast(4)), withExtension: "wav"))
            let audio = try AVAudioPlayer(contentsOf: url)
            XCTAssertGreaterThan(audio.duration, 0.7)
            XCTAssertLessThan(audio.duration, 1.2)
            XCTAssertEqual(audio.numberOfChannels, 1)
        }
    }
}
