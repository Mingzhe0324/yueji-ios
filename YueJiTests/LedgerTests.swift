import XCTest
@testable import YueJi

final class LedgerTests: XCTestCase {
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
