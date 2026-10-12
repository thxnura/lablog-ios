import XCTest

/// End-to-end walk through the student flow. Each step attaches a screenshot
/// (kept in the .xcresult) — these feed the report's UI/UX section.
///
/// Launch arguments:
///   -UITestInMemoryStore  fresh database every run
///   -UITestStubCamera     generated photo instead of the system camera
final class LabLogFlowUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-UITestInMemoryStore", "-UITestStubCamera"]
        app.launch()
    }

    private func snap(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    /// Steps near the bottom can sit under the floating Submit bar, where a
    /// centre tap lands on the bar instead. Scroll the card into the clear band
    /// between the navigation bar and the bottom bar, then tap near its top.
    private func tapStep(_ order: Int) {
        let step = element("step-\(order)")
        XCTAssertTrue(step.waitForExistence(timeout: 5))
        let navBottom = app.navigationBars.firstMatch.frame.maxY + 8
        let bar = element("submit-record")
        let barTop = (bar.exists ? bar.frame.minY : app.frame.maxY) - 16
        var attempts = 0
        while attempts < 6 {
            let top = step.frame.minY
            if top + 44 > barTop {
                app.swipeUp(velocity: .slow)
            } else if top < navBottom {
                app.swipeDown(velocity: .slow)
            } else {
                break
            }
            attempts += 1
        }
        step.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0)).withOffset(CGVector(dx: 0, dy: 24)).tap()
    }

    private func goBack(times: Int = 1) {
        for _ in 0..<times {
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
    }

    /// Branching DAG experiment: locked step → reason, photo guard, submit.
    func testTitrationFlow() {
        XCTAssertTrue(element("lab-CHEM201").waitForExistence(timeout: 10))
        snap("01-labs")

        element("lab-CHEM201").tap()
        XCTAssertTrue(element("experiment-Acid–Base Titration").waitForExistence(timeout: 5))
        snap("02-experiments")

        element("experiment-Acid–Base Titration").tap()
        XCTAssertTrue(element("start-record").waitForExistence(timeout: 5))
        snap("03-experiment-detail")

        element("start-record").tap()
        XCTAssertTrue(element("step-1").waitForExistence(timeout: 5))
        sleep(1)
        snap("04-checklist-new")

        // Step 4 needs Steps 1 and 3 → tapping it explains why it's locked.
        tapStep(4)
        XCTAssertTrue(element("toast").waitForExistence(timeout: 3))
        snap("05-locked-step-reason")

        tapStep(2)
        tapStep(3)
        tapStep(1)
        sleep(1) // let the row transitions settle
        snap("06-photo-guard")

        // Photo guard: tapping opens the camera (stubbed) and completes the step.
        tapStep(4)
        XCTAssertTrue(app.staticTexts["Evidence"].waitForExistence(timeout: 5))
        tapStep(5)

        let observation = element("observation")
        observation.tap()
        observation.typeText("Endpoint at 24.60 mL, faint pink persisted for 30 s. Concordant titres: 24.60, 24.55 mL.")
        if app.buttons["Done"].exists { app.buttons["Done"].tap() }
        sleep(1)
        snap("07-ready-to-submit")

        element("submit-record").tap()
        app.buttons["Submit"].firstMatch.tap()
        allowLocationIfAsked()
        XCTAssertTrue(app.staticTexts["Submission"].waitForExistence(timeout: 20))
        sleep(2) // map tiles
        app.swipeUp()
        snap("08-submitted")

        goBack(times: 3)
        XCTAssertTrue(element("lab-CHEM201").waitForExistence(timeout: 5))
        app.tabBars.buttons["Records"].tap()
        sleep(1)
        snap("09-records")

        app.tabBars.buttons["Sync"].tap()
        sleep(1)
        snap("10-sync-status")
    }

    /// Timer guard: the countdown is shown live on the row; home shows "Continue".
    func testPendulumTimer() {
        XCTAssertTrue(element("lab-PHYS101").waitForExistence(timeout: 10))
        element("lab-PHYS101").tap()
        element("experiment-Simple Pendulum").tap()
        element("start-record").tap()
        XCTAssertTrue(element("step-1").waitForExistence(timeout: 5))
        tapStep(1)
        tapStep(2) // photo (stubbed) → completes step 2, starts the 30 s timer
        sleep(3)
        snap("11-timer-guard")

        goBack(times: 3)
        XCTAssertTrue(element("resume-card").waitForExistence(timeout: 5))
        sleep(1)
        snap("12-home-continue")
    }

    private func allowLocationIfAsked() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.buttons["Allow While Using App"]
        if allow.waitForExistence(timeout: 5) {
            allow.tap()
        }
    }
}
