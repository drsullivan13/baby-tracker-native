import XCTest

final class VisualAuditTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    @MainActor
    func testVisualAuditCapturesCoreSurfaces() throws {
        let app = XCUIApplication()
        launchPastOnboarding(app)

        capture(app, named: "01 Dashboard")
        XCTAssertTrue(app.buttons["logFeed"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["logDiaper"].exists)
        XCTAssertTrue(app.buttons["logSleep"].exists)

        openAndCaptureSheet(app, actionID: "logFeed", navigationTitle: "Feed", screenshotName: "02 Feed sheet") {
            XCTAssertTrue(app.textFields["bottleAmount"].exists)
            XCTAssertTrue(app.buttons["logBottle"].exists)
        }
        openAndCaptureSheet(app, actionID: "logDiaper", navigationTitle: "Diaper", screenshotName: "03 Diaper sheet") {
            XCTAssertTrue(app.buttons["diaperWet"].exists)
            XCTAssertTrue(app.buttons["diaperDirty"].exists)
        }
        openAndCaptureSheet(app, actionID: "logSleep", navigationTitle: "Log sleep", screenshotName: "04 Sleep sheet") {
            XCTAssertTrue(app.buttons["Save"].exists)
        }

        app.tabBars.buttons["History"].tap()
        XCTAssertTrue(app.navigationBars["History"].waitForExistence(timeout: 5))
        capture(app, named: "05 History")
        let timeline = app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH %@", "Timeline")).firstMatch
        scrollToHittable(timeline, in: app, maxSwipes: 12)
        XCTAssertTrue(timeline.exists)
        capture(app, named: "05b History timeline")

        app.tabBars.buttons["Trackers"].tap()
        XCTAssertTrue(app.navigationBars["Trackers"].waitForExistence(timeout: 5))
        let newTracker = app.buttons["New tracker"]
        XCTAssertTrue(newTracker.waitForExistence(timeout: 5))
        newTracker.tap()
        XCTAssertTrue(app.navigationBars["New Tracker"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["Tracker name"].exists)
        capture(app, named: "06 New tracker")
        app.buttons["Cancel"].tap()

        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        let pair = app.buttons["Pair a Device"].firstMatch
        scrollToHittable(pair, in: app, maxSwipes: 12)
        XCTAssertTrue(pair.waitForExistence(timeout: 5))
        capture(app, named: "07 Settings")
        pair.tap()
        XCTAssertTrue(app.navigationBars["Private sharing"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Show pairing QR code"].exists)
        XCTAssertTrue(app.buttons["Scan partner’s code"].exists)
        capture(app, named: "08 Pairing")
        app.buttons["Done"].tap()
    }

    @MainActor
    func testVisualAuditCapturesDashboardAtAccessibilityXXXL() throws {
        let app = XCUIApplication()
        app.launchArguments.append(contentsOf: [
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL"
        ])
        launchPastOnboarding(app)

        XCTAssertTrue(app.buttons["logFeed"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["logDiaper"].exists)
        XCTAssertTrue(app.buttons["logSleep"].exists)
        capture(app, named: "09 Dashboard accessibility XXXL")
        scrollToHittable(app.buttons["logFeed"], in: app, maxSwipes: 8)
        app.buttons["logFeed"].tap()
        XCTAssertTrue(app.navigationBars["Feed"].waitForExistence(timeout: 5))
        capture(app, named: "10 Feed accessibility XXXL")
        scrollToHittable(app.buttons["logBottle"], in: app, maxSwipes: 10)
        XCTAssertTrue(app.buttons["logBottle"].isHittable)
        capture(app, named: "11 Bottle accessibility XXXL")
        app.buttons["Cancel"].tap()
    }

    @MainActor
    private func launchPastOnboarding(_ app: XCUIApplication) {
        app.launch()
        if app.buttons["startTracking"].waitForExistence(timeout: 5) {
            let toggle = app.switches["privacyAcknowledgment"]
            scrollToHittable(toggle, in: app, maxSwipes: 12)
            XCTAssertTrue(toggle.waitForExistence(timeout: 5))
            XCTAssertTrue(toggle.isHittable)
            if toggle.switches.firstMatch.exists { toggle.switches.firstMatch.tap() }
            else { toggle.tap() }
            let start = app.buttons["startTracking"]
            XCTAssertTrue(start.waitForExistence(timeout: 5))
            XCTAssertTrue(start.isEnabled)
            scrollToHittable(start, in: app, maxSwipes: 12)
            start.tap()
        }
        XCTAssertTrue(app.buttons["logFeed"].waitForExistence(timeout: 10))
    }

    @MainActor
    private func openAndCaptureSheet(
        _ app: XCUIApplication,
        actionID: String,
        navigationTitle: String,
        screenshotName: String,
        assertions: () -> Void
    ) {
        let action = app.buttons[actionID]
        XCTAssertTrue(action.waitForExistence(timeout: 5))
        action.tap()
        XCTAssertTrue(app.navigationBars[navigationTitle].waitForExistence(timeout: 5))
        assertions()
        capture(app, named: screenshotName)
        let cancel = app.buttons["Cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        cancel.tap()
        XCTAssertTrue(app.buttons["logFeed"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func scrollToHittable(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int) {
        for _ in 0..<maxSwipes where !element.isHittable {
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
