import XCTest
import UIKit
@testable import YueJi

final class IncomeBudgetTests: XCTestCase {
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

    func testNativeOtherBankLayoutsAndMissingPrintedBalance() throws {
        for provider in ["Hong Leong", "Maybank", "Ryt Bank", "Wise"] {
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
            let result = try RHBStatement.read(data)
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
