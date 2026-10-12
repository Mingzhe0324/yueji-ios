import XCTest

final class TransactionFormTests: XCTestCase {
    private var runningApp: XCUIApplication?
    override func setUpWithError() throws { continueAfterFailure = false }

    override func tearDownWithError() throws {
        if let app = runningApp {
            if (testRun?.failureCount ?? 0) > 0 {
                let state = app.state
                let hierarchy = "UI failure: app state = \(state)\n" + (state == .runningForeground ? app.debugDescription : "App is not in the foreground; no accessibility snapshot is available.")
                print(hierarchy)
                let attachment = XCTAttachment(string: hierarchy)
                attachment.name = "App accessibility hierarchy at failure"
                attachment.lifetime = .keepAlways
                add(attachment)
                if state == .runningForeground {
                    let screenshot = XCTAttachment(screenshot: app.screenshot())
                    screenshot.name = "App screen at failure"
                    screenshot.lifetime = .keepAlways
                    add(screenshot)
                }
            }
            app.terminate()
        }
        runningApp = nil
        try super.tearDownWithError()
    }

    func testFirstAddItemImmediatelyAfterLaunchWithOpening() {
        verifyFirstAddItem(opening: true)
    }

    func testFirstAddItemImmediatelyAfterLaunchWithoutOpening() {
        verifyFirstAddItem(opening: false)
    }

    private func verifyFirstAddItem(opening: Bool) {
        let app = XCUIApplication()
        runningApp = app
        // Standard UserDefaults launch overrides, no app-only test code or saved
        // ledger fixtures. Leave the normal startup refresh/rate tasks enabled.
        app.launchArguments = ["-appLanguage", "en", "-completedUsageGuide", "YES",
                               "-openingAnimationEnabled", opening ? "YES" : "NO",
                               "-automaticSystemAlertsBuild65", "YES", "-automationNotifications", "NO"]
        app.launch()
        // Identify the actual control independently of the accessibility role
        // chosen by the system's SwiftUI button style/container.
        let newEntry = app.descendants(matching: .any).matching(identifier: "overview.manualEntry").firstMatch
        XCTAssertTrue(newEntry.waitForExistence(timeout: 20), "Overview Add Entry is absent after launch; app state = \(app.state)")
        XCTAssertTrue(newEntry.isHittable, "Overview Add Entry exists but cannot be tapped after launch")
        // No warm-up tap or delay after the launch screen becomes interactive.
        newEntry.tap()
        let amount = app.textFields["transaction.amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        reveal(amount, in: app); amount.tap(); amount.typeText("35.00")
        finishKeyboard(in: app)
        let merchant = app.textFields["transaction.merchant"]
        reveal(merchant, in: app); merchant.tap(); merchant.typeText("Unsaved purchase")
        finishKeyboard(in: app)

        let category = app.descendants(matching: .any)["transaction.category"].firstMatch
        reveal(category, in: app); category.tap()
        let food = app.staticTexts["Food"].firstMatch
        XCTAssertTrue(food.waitForExistence(timeout: 5)); food.tap()

        let disclosure = app.descendants(matching: .any)["transaction.items.toggle"].firstMatch
        reveal(disclosure, in: app); disclosure.tap()
        let add = app.buttons["transaction.item.add"]
        reveal(add, in: app); add.tap()
        let names = app.textFields.matching(identifier: "transaction.item.name")
        let itemOpened = names.firstMatch.waitForExistence(timeout: 5)
        // These distinguish a terminated app from a dismissed editor.
        XCTAssertEqual(app.state, .runningForeground, "Add Item terminated the app")
        XCTAssertTrue(app.navigationBars["New entry"].exists, "Add Item dismissed the transaction form")
        XCTAssertTrue(itemOpened, "The first Add Item tap did not open an item")
        XCTAssertEqual(names.count, 1)
        names.firstMatch.tap(); names.firstMatch.typeText("Lunch")
        finishKeyboard(in: app)

        // Item category navigation must return to the same unsaved form.
        let itemCategory = app.descendants(matching: .any)["transaction.item.category"].firstMatch
        reveal(itemCategory, in: app); itemCategory.tap()
        let shopping = app.staticTexts["Shopping"].firstMatch
        XCTAssertTrue(shopping.waitForExistence(timeout: 5)); shopping.tap()
        XCTAssertEqual(names.firstMatch.value as? String, "Lunch")
        reveal(add, in: app); add.tap(); reveal(add, in: app); add.tap()
        XCTAssertEqual(names.count, 3)

        // Removing rows must not redirect retained field/picker bindings.
        let remove = app.buttons.matching(identifier: "transaction.item.remove").firstMatch
        reveal(remove, in: app); remove.tap()
        XCTAssertEqual(names.count, 2)
        reveal(names.firstMatch, in: app)
        names.firstMatch.tap(); names.firstMatch.typeText("Supplies")
        finishKeyboard(in: app)
        XCTAssertEqual(names.firstMatch.value as? String, "Supplies")
        reveal(merchant, in: app, above: true)
        XCTAssertEqual(merchant.value as? String, "Unsaved purchase")
        reveal(amount, in: app, above: true)
        XCTAssertEqual(amount.value as? String, "35.00")
        XCTAssertFalse(app.staticTexts["Tags"].exists)
        XCTAssertTrue(app.navigationBars["New entry"].exists)
        app.navigationBars.buttons["Cancel"].tap()
        XCTAssertTrue(newEntry.waitForExistence(timeout: 5))
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication, above: Bool = false) {
        for _ in 0..<6 {
            if element.exists && element.isHittable { return }
            if above { app.swipeDown() } else { app.swipeUp() }
        }
        XCTAssertTrue(element.exists && element.isHittable, "Could not reach \(element)")
    }

    private func finishKeyboard(in app: XCUIApplication) {
        let done = app.toolbars.buttons["Done"].firstMatch
        if done.exists { done.tap() }
    }
}
