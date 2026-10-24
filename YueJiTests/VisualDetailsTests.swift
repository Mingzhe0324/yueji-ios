import XCTest
import SwiftUI
@testable import YueJi

final class VisualDetailsTests: XCTestCase {
    private let calendar = InsightCalendar.make()
    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    func testAmountsGroupThousandsAndSmallAmountsReadAsBefore() throws {
        XCTAssertEqual(money(0), "RM 0.00")
        XCTAssertEqual(money(5), "RM 0.05")
        XCTAssertEqual(money(60000), "RM 600.00")
        XCTAssertEqual(money(100000), "RM 1,000.00")
        XCTAssertEqual(money(1470000), "RM 14,700.00")
        XCTAssertEqual(money(123456789), "RM 1,234,567.89")
        XCTAssertEqual(money(-50), "RM -0.50")
        XCTAssertEqual(money(-123456), "RM -1,234.56")
        XCTAssertEqual(AccountDirection.outgoing.formattedAmount(123456), "\u{2212}RM 1,234.56")
        XCTAssertEqual(Currency.display(1234567, "JPY"), "JPY 1,234,567")
        XCTAssertEqual(Currency.display(123456, "USD"), "USD 1,234.56")
        XCTAssertEqual(Currency.display(1590, "MYR"), "MYR 15.90")
        // Editing never groups: text fields read their own value back.
        XCTAssertEqual(Currency.input(123456, "USD"), "1234.56")
        XCTAssertEqual(try toCents(Currency.input(123456, "MYR")), 123456)
    }

    func testMonthDialCountsTheMonthToToday() {
        let october = day(2026, 10, 1)
        let pace = BudgetPace(spent: 62000, budget: 100000, month: october, now: day(2026, 10, 24))
        XCTAssertEqual(pace.days, 31)
        XCTAssertEqual(pace.daysPassed, 24)
        XCTAssertTrue(pace.ongoing)
        XCTAssertEqual(pace.used, 0.62, accuracy: 0.0001)
        XCTAssertEqual(pace.elapsed, 24.0 / 31, accuracy: 0.0001)
        // The gold thread ends at today's bead.
        XCTAssertEqual(pace.thread, 23.0 / 31, accuracy: 0.0001)
        XCTAssertFalse(pace.ahead)

        let ended = BudgetPace(spent: 0, budget: 100000, month: day(2026, 9, 1), now: day(2026, 10, 24))
        XCTAssertEqual(ended.daysPassed, 30)
        XCTAssertFalse(ended.ongoing)
        XCTAssertEqual(ended.elapsed, 1)
        XCTAssertEqual(ended.thread, 1)

        let coming = BudgetPace(spent: 0, budget: 100000, month: day(2026, 12, 1), now: day(2026, 10, 24))
        XCTAssertEqual(coming.daysPassed, 0)
        XCTAssertEqual(coming.elapsed, 0)
        XCTAssertEqual(coming.thread, 0)
    }

    func testAheadOfTheMonthOnlyWhenClearlyFasterAndStillWithinBudget() {
        let october = day(2026, 10, 1)
        // RM 600 of RM 1,000 by the 10th: 60% used with 32% of the month gone.
        XCTAssertTrue(BudgetPace(spent: 60000, budget: 100000, month: october, now: day(2026, 10, 10)).ahead)
        // Too early in the month to say.
        XCTAssertFalse(BudgetPace(spent: 60000, budget: 100000, month: october, now: day(2026, 10, 3)).ahead)
        // Within ten points of the month.
        XCTAssertFalse(BudgetPace(spent: 40000, budget: 100000, month: october, now: day(2026, 10, 10)).ahead)
        // Over budget says so itself.
        let over = BudgetPace(spent: 120000, budget: 100000, month: october, now: day(2026, 10, 10))
        XCTAssertFalse(over.ahead)
        XCTAssertEqual(over.used, 1.2, accuracy: 0.0001)
    }

    func testLedgerDaysAddUpToTheMonthsPersonalSpending() {
        let date = day(2026, 10, 24)
        let lunch = Expense(merchant: "Lunch", cents: 4000, date: date, category: "餐饮")
        // Ali's share is not my spending.
        let dinner = Expense(merchant: "Dinner", cents: 9000, date: date.addingTimeInterval(3600), category: "餐饮",
                             shares: [Share(name: "Ali", cents: 3000)])
        let earlier = Expense(merchant: "Grab", cents: 1500, date: day(2026, 10, 2), category: "交通")
        let salary = IncomeEntry(source: "Acme Sdn Bhd", cents: 300000, date: date, kind: .salary)
        let days = LedgerTimelineItem.grouped(expenses: [lunch, dinner, earlier], transfers: [], incomes: [salary])
        // Income on the same day doesn't count as spending.
        XCTAssertEqual(days.first?.spending, 4000 + 6000)
        XCTAssertEqual(days.map(\.spending).reduce(0, +), [lunch, dinner, earlier].reduce(0) { $0 + $1.personalSpending })
    }

    func testDonutTapsFindTheirSector() {
        let plot = CGRect(x: 0, y: 0, width: 100, height: 100)
        let sectors: [(id: String, cents: Int)] = [(id: "a", cents: 100), (id: "b", cents: 300)]
        // Just past twelve o'clock on the ring: the first quarter is "a".
        XCTAssertEqual(DonutHitTest.sector(at: CGPoint(x: 55, y: 10), in: plot, sectors: sectors), "a")
        // Six o'clock is past the first quarter.
        XCTAssertEqual(DonutHitTest.sector(at: CGPoint(x: 50, y: 90), in: plot, sectors: sectors), "b")
        // The middle and the corners hit nothing.
        XCTAssertNil(DonutHitTest.sector(at: CGPoint(x: 50, y: 50), in: plot, sectors: sectors))
        XCTAssertNil(DonutHitTest.sector(at: CGPoint(x: 2, y: 2), in: plot, sectors: sectors))
        XCTAssertNil(DonutHitTest.sector(at: CGPoint(x: 55, y: 10), in: plot, sectors: []))
    }

    func testSidewaysDragsAndTapsScrubAndScrollingDoesNot() {
        XCTAssertTrue(isChartScrub(.zero))
        XCTAssertTrue(isChartScrub(CGSize(width: 60, height: 20)))
        // A tap that wobbled a little.
        XCTAssertTrue(isChartScrub(CGSize(width: 2, height: 8)))
        XCTAssertFalse(isChartScrub(CGSize(width: 5, height: 40)))
    }

    func testGoalSweepDrawsOnlyWhileItRuns() {
        let rect = CGRect(x: 0, y: 0, width: 100, height: 100)
        XCTAssertTrue(RingSweep(progress: 0).path(in: rect).isEmpty)
        XCTAssertFalse(RingSweep(progress: 0.5).path(in: rect).isEmpty)
        XCTAssertTrue(RingSweep(progress: 1).path(in: rect).isEmpty)
        // Each whole step is one more sweep.
        XCTAssertFalse(RingSweep(progress: 1.5).path(in: rect).isEmpty)
        XCTAssertTrue(RingSweep(progress: 2).path(in: rect).isEmpty)
    }
}
