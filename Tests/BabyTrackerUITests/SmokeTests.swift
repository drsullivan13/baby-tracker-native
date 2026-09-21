import XCTest

final class SmokeTests: XCTestCase {
    @MainActor
    func testPrivateOnboardingAndLoggingSurviveRelaunch() throws {
        let app = XCUIApplication()
        launchPastOnboarding(app)
        XCTAssertTrue(app.buttons["logFeed"].waitForExistence(timeout: 10))
        app.buttons["logFeed"].tap()
        let amount = app.textFields["bottleAmount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        amount.tap()
        amount.typeText("83")
        app.buttons["Done"].tap()
        let save = app.buttons["logBottle"]
        if !save.isHittable { app.swipeUp() }
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()
        XCTAssertTrue(amount.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["logDiaper"].waitForExistence(timeout: 5))
        app.buttons["logDiaper"].tap()
        XCTAssertTrue(app.buttons["diaperBoth"].waitForExistence(timeout: 5))
        app.buttons["diaperBoth"].tap()
        XCTAssertTrue(app.buttons["logFeed"].waitForExistence(timeout: 5))
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Synthetic dashboard"
        shot.lifetime = .keepAlways
        add(shot)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["logFeed"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["startTracking"].exists)
        app.tabBars.buttons["History"].tap()
        let savedBottle = app.buttons.matching(NSPredicate(
            format: "identifier == %@ AND label CONTAINS %@",
            "historyActivity-feed-completed", "83 ml"
        )).firstMatch
        for _ in 0..<12 {
            if savedBottle.exists && savedBottle.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(savedBottle.exists)
        XCTAssertTrue(savedBottle.isHittable)
    }

    @MainActor
    func testCompletedSleepEditorCannotRestartTimer() throws {
        let app = XCUIApplication()
        launchPastOnboarding(app)

        XCTAssertTrue(app.buttons["logSleep"].waitForExistence(timeout: 10))
        app.buttons["logSleep"].tap()
        XCTAssertTrue(app.navigationBars["Log sleep"].waitForExistence(timeout: 5))
        app.buttons["Save"].tap()

        let stop = app.buttons["Stop"].firstMatch
        XCTAssertTrue(stop.waitForExistence(timeout: 5))
        stop.tap()

        openCompletedSleepEditor(in: app)
        XCTAssertFalse(app.switches["Timer is running"].exists)
        XCTAssertFalse(app.otherElements["activityRunningStatus"].exists)
        XCTAssertEqual(app.switches["Has end time"].value as? String, "1")
        app.buttons["Save"].tap()

        app.terminate()
        launchPastOnboarding(app)
        openCompletedSleepEditor(in: app)
        XCTAssertFalse(app.switches["Timer is running"].exists)
        XCTAssertFalse(app.otherElements["activityRunningStatus"].exists)
        XCTAssertEqual(app.switches["Has end time"].value as? String, "1")
    }

    @MainActor
    private func launchPastOnboarding(_ app: XCUIApplication) {
        app.launch()
        if app.buttons["startTracking"].waitForExistence(timeout: 5) {
            let toggle = app.switches["privacyAcknowledgment"]
            for _ in 0..<6 {
                if toggle.exists && toggle.isHittable { break }
                app.swipeUp()
            }
            XCTAssertTrue(toggle.waitForExistence(timeout: 5))
            toggle.switches.firstMatch.tap()
            XCTAssertTrue(app.buttons["startTracking"].isEnabled)
            app.buttons["startTracking"].tap()
        }
        XCTAssertTrue(app.buttons["logFeed"].waitForExistence(timeout: 10))
    }

    @MainActor
    private func openCompletedSleepEditor(in app: XCUIApplication) {
        app.tabBars.buttons["History"].tap()
        let sleep = app.buttons["historyActivity-sleep-completed"].firstMatch
        for _ in 0..<8 {
            if sleep.exists && sleep.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(sleep.waitForExistence(timeout: 5))
        XCTAssertTrue(sleep.isHittable)
        sleep.tap()
        XCTAssertTrue(app.navigationBars["Edit Sleep"].waitForExistence(timeout: 5))
    }
}
