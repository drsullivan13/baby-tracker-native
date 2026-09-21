import XCTest

final class ExtendedAuditTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    @MainActor
    func testSyntheticHistoryEditorsDeletedRecordsAndConflictResolution() {
        let app = launchFixture(named: "history")
        app.tabBars.buttons["History"].tap()
        XCTAssertTrue(app.navigationBars["History"].waitForExistence(timeout: 10))

        let trend = app.staticTexts["Feeding trend"]
        scrollToHittable(trend, in: app, maxSwipes: 12)
        XCTAssertTrue(trend.exists)
        XCTAssertTrue(app.staticTexts["Feed count"].exists)
        XCTAssertTrue(app.staticTexts["Bottle volume"].exists)
        capture(app, named: "10 Synthetic nonempty History trends")

        openActivityEditor(
            in: app, identifier: "historyActivity-custom-completed",
            labelContains: "Tummy time", titlePrefix: "Edit Tummy time",
            screenshotName: "11 Synthetic custom editor"
        )
        openActivityEditor(
            in: app, identifier: "historyActivity-feed-completed",
            labelContains: "Bottle", titlePrefix: "Edit Bottle",
            screenshotName: "12 Synthetic bottle editor"
        )
        openActivityEditor(
            in: app, identifier: "historyActivity-sleep-completed",
            labelContains: "Sleep", titlePrefix: "Edit Sleep",
            screenshotName: "13 Synthetic sleep editor"
        )

        let deleted = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Recently Deleted (")
        ).firstMatch
        scrollToHittable(deleted, in: app, maxSwipes: 12)
        XCTAssertTrue(deleted.waitForExistence(timeout: 5))
        deleted.tap()
        XCTAssertTrue(app.navigationBars["Recently Deleted"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Restore"].waitForExistence(timeout: 5))
        capture(app, named: "14 Synthetic Recently Deleted")
        app.buttons["Restore"].tap()
        XCTAssertTrue(app.staticTexts["Nothing deleted"].waitForExistence(timeout: 5))
        capture(app, named: "15 Synthetic restored record")
        app.buttons["Done"].tap()

        let conflicts = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Review Conflicts (")
        ).firstMatch
        scrollToHittable(conflicts, in: app, maxSwipes: 12)
        XCTAssertTrue(conflicts.waitForExistence(timeout: 5))
        conflicts.tap()
        XCTAssertTrue(app.navigationBars["Review Conflicts"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts[
            "Two phones changed the same item independently. Compare the details and choose the version to keep."
        ].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "Bottle · 110 ml")
        ).firstMatch.exists)
        XCTAssertTrue(app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "Bottle · 125 ml")
        ).firstMatch.exists)
        capture(app, named: "16 Synthetic conflict comparison")

        let chosenVersion = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "Bottle · 125 ml")
        ).firstMatch
        XCTAssertTrue(chosenVersion.waitForExistence(timeout: 5))
        chosenVersion.tap()
        XCTAssertTrue(app.staticTexts["No conflicts"].waitForExistence(timeout: 5))
        capture(app, named: "17 Synthetic conflict chosen")
    }

    @MainActor
    func testSyntheticTrackerArchiveAndFeedValidationAlert() {
        let app = launchFixture(named: "tracker-validation")

        app.tabBars.buttons["Trackers"].tap()
        XCTAssertTrue(app.navigationBars["Trackers"].waitForExistence(timeout: 5))
        let tracker = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "Tummy time")
        ).firstMatch
        XCTAssertTrue(tracker.waitForExistence(timeout: 5))
        tracker.tap()
        XCTAssertTrue(app.navigationBars["Edit Tracker"].waitForExistence(timeout: 5))
        capture(app, named: "18 Synthetic tracker editor")
        let name = app.textFields["Tracker name"]
        XCTAssertTrue(name.exists)
        name.tap()
        name.typeText(" stretches")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.navigationBars["Trackers"].waitForExistence(timeout: 5))
        let editedTracker = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "Tummy time stretches")
        ).firstMatch
        XCTAssertTrue(editedTracker.waitForExistence(timeout: 5))
        editedTracker.tap()
        XCTAssertTrue(app.navigationBars["Edit Tracker"].waitForExistence(timeout: 5))
        app.buttons["Archive Tracker"].tap()
        XCTAssertTrue(app.navigationBars["Trackers"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Archived"].waitForExistence(timeout: 5))
        capture(app, named: "19 Synthetic archived tracker")

        app.tabBars.buttons["Today"].tap()
        XCTAssertTrue(app.buttons["logFeed"].waitForExistence(timeout: 5))
        app.buttons["logFeed"].tap()
        let amount = app.textFields["bottleAmount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        amount.tap()
        amount.typeText("0")
        if app.buttons["Done"].waitForExistence(timeout: 2) {
            app.buttons["Done"].tap()
        }
        let logBottle = app.buttons["logBottle"]
        scrollToHittable(logBottle, in: app, maxSwipes: 6)
        XCTAssertTrue(logBottle.isHittable)
        logBottle.tap()
        XCTAssertTrue(app.alerts["Baby Tracker"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts[
            "Enter a bottle amount greater than zero, or leave the field empty."
        ].exists)
        capture(app, named: "20 Synthetic feed validation alert")
    }

    @MainActor
    func testExplicitEmptySyntheticFixtureShowsOnboarding() {
        let app = XCUIApplication()
        app.launchArguments.append(contentsOf: [
            "--visual-audit-fixture",
            "--visual-audit-fixture-id", "empty-onboarding",
            "--visual-audit-empty"
        ])
        app.launch()

        XCTAssertTrue(app.navigationBars["Baby Tracker"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["startTracking"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.switches["privacyAcknowledgment"].exists)
        XCTAssertFalse(app.buttons["startTracking"].isEnabled)
        capture(app, named: "21 Synthetic empty fixture onboarding")
    }

    @MainActor
    private func launchFixture(named name: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append(contentsOf: [
            "--visual-audit-fixture",
            "--visual-audit-fixture-id", name
        ])
        app.launch()
        XCTAssertTrue(app.buttons["logFeed"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["startTracking"].exists)
        return app
    }

    @MainActor
    private func openActivityEditor(
        in app: XCUIApplication,
        identifier: String,
        labelContains: String,
        titlePrefix: String,
        screenshotName: String
    ) {
        let row = app.buttons.matching(NSPredicate(
            format: "identifier == %@ AND label CONTAINS %@", identifier, labelContains
        )).firstMatch
        scrollToHittable(row, in: app, maxSwipes: 12)
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.isHittable)
        row.tap()
        let title = app.navigationBars.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", titlePrefix)
        ).firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        capture(app, named: screenshotName)
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["History"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func scrollToHittable(
        _ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int
    ) {
        for _ in 0..<maxSwipes {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
    }

    private func capture(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
