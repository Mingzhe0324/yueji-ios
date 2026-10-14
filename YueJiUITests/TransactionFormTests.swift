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

    func testSavedItemFirstTapAfterColdLaunchWithOpening() {
        verifySavedItemEditing(opening: true)
    }

    func testSavedItemFirstTapAfterColdLaunchWithoutOpening() {
        verifySavedItemEditing(opening: false)
    }

    private func verifySavedItemEditing(opening: Bool) {
        let app = XCUIApplication()
        runningApp = app
        app.launchArguments = ["-appLanguage", "en", "-completedUsageGuide", "YES",
                               "-openingAnimationEnabled", opening ? "YES" : "NO",
                               "-automaticSystemAlertsBuild65", "YES", "-automationNotifications", "NO"]
        app.launch()
        let addEntry = app.descendants(matching: .any)["overview.manualEntry"].firstMatch
        XCTAssertTrue(addEntry.waitForExistence(timeout: 20))
        addEntry.tap()
        let merchantName = "Item regression " + UUID().uuidString.prefix(8)
        let amount = app.textFields["transaction.amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        amount.tap(); amount.typeText("35.00"); finishKeyboard(in: app)
        let merchant = app.textFields["transaction.merchant"]
        reveal(merchant, in: app); merchant.tap(); merchant.typeText(merchantName); finishKeyboard(in: app)
        let addItem = app.buttons["transaction.item.add"]
        let name = app.textFields["transaction.item.name"].firstMatch
        let itemAmount = app.textFields["transaction.item.amount"].firstMatch
        app.navigationBars.buttons["Save"].tap()
        waitUntilGone(app.navigationBars["New entry"])
        XCTAssertTrue(addEntry.waitForExistence(timeout: 10))

        // Saved fixture created through the real UI; startup refreshes stay enabled.
        app.terminate(); app.launch()
        XCTAssertTrue(addEntry.waitForExistence(timeout: 20))
        let purchase = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", merchantName)).firstMatch
        // Match the recording: Overview -> saved purchase without items -> Add items.
        reveal(purchase, in: app); purchase.tap()
        XCTAssertTrue(app.navigationBars["Entry details"].waitForExistence(timeout: 5))
        let editItems = app.buttons["transaction.items.edit"]
        for shouldSave in [false, true] {
            reveal(editItems, in: app); editItems.tap()
            let editor = app.navigationBars["Edit items"]
            XCTAssertTrue(editor.waitForExistence(timeout: 5), "Saved empty transaction dismissed its item editor")
            if !shouldSave {
                dragSheetToDismiss(in: app)
                waitUntilGone(editor)
                XCTAssertTrue(app.navigationBars["Entry details"].exists)
                editItems.tap()
                XCTAssertTrue(editor.waitForExistence(timeout: 5))
            }
            reveal(addItem, in: app); addItem.tap()
            reveal(name, in: app); name.tap(); name.typeText("Original item"); finishKeyboard(in: app)
            reveal(itemAmount, in: app); itemAmount.tap(); itemAmount.typeText("35.00"); finishKeyboard(in: app)
            XCTAssertTrue(editor.exists)
            XCTAssertEqual(name.value as? String, "Original item")
            editor.buttons[shouldSave ? "Save" : "Cancel"].tap()
            if !shouldSave { confirmDiscard(in: app) }
            waitUntilGone(editor)
            XCTAssertTrue(app.navigationBars["Entry details"].exists)
            if !shouldSave {
                XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "transaction.item.open.")).count, 0)
            }
        }
        app.navigationBars["Entry details"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(addEntry.waitForExistence(timeout: 5))
        let ledger = app.tabBars.buttons["Ledger"]
        ledger.tap()
        reveal(purchase, in: app); purchase.tap()
        XCTAssertTrue(app.navigationBars["Entry details"].waitForExistence(timeout: 5))
        let item = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "transaction.item.open.")).firstMatch

        for attempt in 0..<3 {
            // Exact reported sequence: scroll a saved detail, then ONE item tap.
            reveal(item, in: app); item.tap()
            let editor = app.navigationBars["Edit items"]
            XCTAssertTrue(editor.waitForExistence(timeout: 5), "First tap failed on attempt \(attempt)")
            XCTAssertEqual(app.state, .runningForeground, "App crashed instead of presenting items")
            XCTAssertTrue(name.waitForExistence(timeout: 5))
            XCTAssertEqual(name.value as? String, attempt == 2 ? "Original item saved" : "Original item")
            XCTAssertEqual(itemAmount.value as? String, "35.00")
            reveal(name, in: app); name.tap(); name.typeText(attempt == 1 ? " saved" : " unsaved")
            finishKeyboard(in: app)
            // A dirty sheet drag asks for confirmation and retains the draft.
            dragSheetToDismiss(in: app)
            let discardAlert = app.alerts["Discard changes?"]
            XCTAssertTrue(discardAlert.waitForExistence(timeout: 5))
            let keepEditing = discardAlert.buttons["Keep editing"]
            XCTAssertTrue(keepEditing.waitForExistence(timeout: 5))
            keepEditing.tap()
            XCTAssertTrue(editor.exists)
            XCTAssertTrue((name.value as? String)?.contains(attempt == 1 ? " saved" : " unsaved") == true)
            let category = app.descendants(matching: .any)["transaction.item.category"].firstMatch
            reveal(category, in: app); category.tap()
            XCTAssertTrue(app.navigationBars["Category"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.navigationBars["Belongs to"].exists, "Category tap must not also open ownership")
            let shopping = app.buttons["Shopping"].firstMatch
            XCTAssertTrue(shopping.waitForExistence(timeout: 5))
            let alreadySelected = shopping.isSelected
            shopping.tap()
            // On the final reopen Shopping is already saved. The native Picker
            // can stay on Category when tapping its selected choice; use Back
            // only for that unchanged selection, then verify the retained draft.
            let categoryPage = app.navigationBars["Category"]
            if alreadySelected && categoryPage.exists {
                XCTAssertTrue(shopping.isSelected)
                categoryPage.buttons["BackButton"].tap()
            }
            XCTAssertTrue(editor.waitForExistence(timeout: 5))
            XCTAssertTrue((name.value as? String)?.contains(attempt == 1 ? " saved" : " unsaved") == true)

            if attempt == 1 {
                // Invalid new row must keep all input and must not save a duplicate.
                reveal(addItem, in: app); addItem.tap()
                editor.buttons["Save"].tap()
                XCTAssertTrue(app.alerts["Unable to save"].waitForExistence(timeout: 5))
                app.alerts.buttons["OK"].tap()
                let names = app.textFields.matching(identifier: "transaction.item.name")
                XCTAssertEqual(names.count, 2)
                let remove = app.buttons.matching(identifier: "transaction.item.remove").element(boundBy: 1)
                reveal(remove, in: app); remove.tap()
                XCTAssertEqual(names.count, 1)
                editor.buttons["Save"].tap()
            } else {
                editor.buttons["Cancel"].tap()
                confirmDiscard(in: app)
            }
            waitUntilGone(editor)
            XCTAssertTrue(app.navigationBars["Entry details"].waitForExistence(timeout: 10), "Save/cancel reset ledger navigation")
            XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "transaction.item.open.")).count, 1)
        }
        app.navigationBars["Entry details"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Ledger"].waitForExistence(timeout: 5))
        XCTAssertTrue(purchase.waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", merchantName)).count, 1)
        // Remove only the unique record this test created and verify the return.
        purchase.tap()
        let delete = app.buttons["transaction.delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5)); delete.tap()
        let confirmDelete = app.sheets.buttons["Delete"].firstMatch
        XCTAssertTrue(confirmDelete.waitForExistence(timeout: 5)); confirmDelete.tap()
        waitUntilGone(app.navigationBars["Entry details"])
        XCTAssertTrue(app.navigationBars["Ledger"].waitForExistence(timeout: 10))
        waitUntilGone(purchase)
        app.tabBars.buttons["Settings"].tap()
        let categories = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Spending categories")).firstMatch
        reveal(categories, in: app)
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Tags & projects")).firstMatch.exists)
        categories.tap()
        XCTAssertTrue(app.navigationBars["Spending categories"].waitForExistence(timeout: 5))
    }

    private func waitUntilGone(_ element: XCUIElement) {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 10), .completed, "Unexpectedly retained \(element)")
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
        let tabBar = app.tabBars.firstMatch
        XCTAssertLessThanOrEqual(newEntry.frame.maxY, tabBar.frame.minY,
                                 "Add Entry's accessible target must not extend behind the tab bar")
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
        // Navigation-style Picker choices are buttons in the native iOS hierarchy.
        let food = app.buttons["Food"].firstMatch
        XCTAssertTrue(food.waitForExistence(timeout: 5), "Food category choice is absent from the native picker"); food.tap()

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
        XCTAssertEqual(names.firstMatch.value as? String, "Lunch", "Keyboard Done must retain the item draft")

        // Exercise the item's decimal keyboard as well as its name keyboard.
        let itemAmount = app.textFields["transaction.item.amount"].firstMatch
        reveal(itemAmount, in: app); itemAmount.tap(); itemAmount.typeText("35.00")
        finishKeyboard(in: app)
        XCTAssertEqual(itemAmount.value as? String, "35.00", "Keyboard Done must retain the item amount")

        // Item category navigation must return to the same unsaved form.
        let itemCategory = app.descendants(matching: .any)["transaction.item.category"].firstMatch
        reveal(itemCategory, in: app); itemCategory.tap()
        XCTAssertTrue(app.navigationBars["Category"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars["Belongs to"].exists, "Category tap must not also open ownership")
        let shopping = app.buttons["Shopping"].firstMatch
        XCTAssertTrue(shopping.waitForExistence(timeout: 5), "Shopping category choice is absent from the native picker"); shopping.tap()
        XCTAssertEqual(names.firstMatch.value as? String, "Lunch")
        let ownership = app.descendants(matching: .any)["transaction.item.ownership"].firstMatch
        reveal(ownership, in: app); ownership.tap()
        let owners = app.navigationBars["Belongs to"]
        XCTAssertTrue(owners.waitForExistence(timeout: 5))
        app.buttons["Me"].firstMatch.tap()
        owners.buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["New entry"].waitForExistence(timeout: 5))
        XCTAssertEqual(names.firstMatch.value as? String, "Lunch", "Choosing ownership must retain the unsaved item")
        XCTAssertEqual(itemAmount.value as? String, "35.00")
        dragSheetToDismiss(in: app)
        let discardAlert = app.alerts["Discard changes?"]
        XCTAssertTrue(discardAlert.waitForExistence(timeout: 5))
        let keepDraft = discardAlert.buttons["Keep editing"]
        XCTAssertTrue(keepDraft.waitForExistence(timeout: 5))
        keepDraft.tap()
        XCTAssertEqual(names.firstMatch.value as? String, "Lunch")
        XCTAssertEqual(itemAmount.value as? String, "35.00")
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
        confirmDiscard(in: app)
        XCTAssertTrue(newEntry.waitForExistence(timeout: 5))
        newEntry.tap()
        let cleanEditor = app.navigationBars["New entry"]
        XCTAssertTrue(cleanEditor.waitForExistence(timeout: 5))
        dragSheetToDismiss(in: app)
        waitUntilGone(cleanEditor)
        XCTAssertTrue(newEntry.waitForExistence(timeout: 5))
    }

    private func dragSheetToDismiss(in app: XCUIApplication) {
        // swipeDown() on a 54-point navigation bar does not reliably cross the
        // sheet's dismissal threshold. Exercise the actual native grabber with
        // a screen-relative drag, for both unchanged and dirty editors.
        let grabber = app.buttons["Sheet Grabber"].firstMatch
        XCTAssertTrue(grabber.waitForExistence(timeout: 5), "Native sheet grabber is missing")
        XCTAssertTrue(grabber.isHittable, "Native sheet grabber is not interactive")
        let start = grabber.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85))
        print("Dismissing sheet from grabber \(grabber.frame) toward lower screen \(app.frame)")
        start.press(forDuration: 0.1, thenDragTo: end)
    }

    private func confirmDiscard(in app: XCUIApplication) {
        let alert = app.alerts["Discard changes?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        XCTAssertTrue(alert.buttons["Keep editing"].exists)
        let discard = alert.buttons["Discard changes"]
        XCTAssertTrue(discard.waitForExistence(timeout: 5))
        discard.tap()
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication, above: Bool = false) {
        for _ in 0..<8 {
            // Large navigation titles collapse while scrolling. Measure again
            // rather than retaining the initial, taller navigation-bar bounds.
            let viewport = unobscuredContent(in: app)
            guard viewport.height > 80 else {
                XCTFail("No usable scroll area: \(viewport)")
                return
            }
            var distance = viewport.height * (above ? 0.35 : -0.35)
            if element.exists {
                let frame = element.frame
                // A partly exposed row can be hittable while its tap point lies
                // beneath Edit/Delete or the tab bar. Reveal the whole target.
                if !frame.isEmpty && viewport.contains(frame) && element.isHittable { return }
                if !frame.isEmpty {
                    let correction = viewport.midY - frame.midY
                    let limit = viewport.height * 0.35
                    distance = min(limit, max(-limit, correction))
                    if abs(distance) < 24 { distance = above ? 24 : -24 }
                }
            }
            // Drag within the scrollable content, away from fixed Add/Edit
            // buttons. Short corrections avoid flinging a row past the top,
            // then past the footer again on the next attempt.
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let start = origin.withOffset(CGVector(dx: viewport.midX, dy: viewport.midY - distance / 2))
            let end = origin.withOffset(CGVector(dx: viewport.midX, dy: viewport.midY + distance / 2))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        let viewport = unobscuredContent(in: app)
        XCTAssertTrue(element.exists && element.isHittable && viewport.contains(element.frame),
                      "Could not fully reveal \(element) above the screen controls; viewport=\(viewport), target=\(element.exists ? element.frame : .zero)")
    }

    private func unobscuredContent(in app: XCUIApplication) -> CGRect {
        let screen = app.frame
        // An editor sheet covers the underlying tab bar and detail actions.
        // Query its navigation bar directly instead of probing hidden controls.
        let editorBar = app.navigationBars.matching(NSPredicate(
            format: "identifier == 'New entry' OR identifier == 'Edit items'")).firstMatch
        if editorBar.exists && editorBar.isHittable {
            let top = editorBar.frame.maxY
            return CGRect(x: screen.minX, y: top, width: screen.width, height: max(0, screen.maxY - top))
        }
        var top = screen.minY
        var bottom = screen.maxY
        for bar in app.navigationBars.allElementsBoundByIndex where bar.isHittable {
            top = max(top, bar.frame.maxY)
        }
        let tabBar = app.tabBars.firstMatch
        if tabBar.exists && tabBar.isHittable { bottom = min(bottom, tabBar.frame.minY) }
        for id in ["transaction.edit", "transaction.delete", "overview.manualEntry"] {
            let control = app.buttons[id].firstMatch
            if control.exists && control.isHittable { bottom = min(bottom, control.frame.minY - 12) }
        }
        return CGRect(x: screen.minX, y: top, width: screen.width, height: max(0, bottom - top))
    }

    private func finishKeyboard(in app: XCUIApplication) {
        let done = app.toolbars.buttons["Done"].firstMatch
        if done.exists {
            done.tap()
            let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == false"), object: done)
            XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 5), .completed,
                           "Keyboard Done remained interactive after dismissal")
        }
    }
}
