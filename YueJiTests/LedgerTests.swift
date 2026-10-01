import XCTest
import UIKit
import AVFoundation
@testable import YueJi

final class LedgerTests: XCTestCase {
    @MainActor func testBundledFeedbackSoundsDecodeWithoutPlaying() throws {
        for name in ["LaunchChime", "SavedChime", "GoalChime"] {
            let asset = try XCTUnwrap(NSDataAsset(name: name))
            let player = try AVAudioPlayer(data: asset.data)
            XCTAssertGreaterThan(player.duration, 0.15)
            XCTAssertLessThan(player.duration, 1.1)
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
        XCTAssertEqual(ledger.version, 4); XCTAssertTrue(ledger.recurring.isEmpty); XCTAssertEqual(ledger.budgets["2026-09"], 10000)
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
        XCTAssertEqual(ledger.tngNotices.map(\.status), ["recorded", "transfer"])
        XCTAssertTrue(ledger.tngNotices[0].usesReceivedDate)
        XCTAssertEqual(try LocalStore.decode(LocalStore.encode(ledger)).tngNotices.count, 2)
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
            ("Transfer Successful", "You have paid RM2.55 for Shop."),
            ("Payment", "RM 0.01 has been successfully transferred to FRIEND."),
            ("", "Reload successful RM50"),
            ("", "You received RM2.55")
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
        XCTAssertEqual(ledger.version, 4)
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
