import XCTest
import UIKit
import AVFoundation
@testable import YueJi

final class LedgerTests: XCTestCase {
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
        catch { XCTAssertTrue(error.localizedDescription.contains("暂存")) }
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
        XCTAssertEqual(copy.expenses[0], expected)
        XCTAssertEqual(copy.expenses[0].date.timeIntervalSince1970, 1_759_680_000)
        XCTAssertEqual(try LocalStore.encode(copy), try LocalStore.encode(ledger))
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
        XCTAssertEqual(restored.expenses, [e])
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
