import XCTest

/// End-to-end walk through the student flow. Each step attaches a screenshot
/// (kept in the .xcresult) — these feed the report's UI/UX section.
///
/// Launch arguments:
///   -UITestInMemoryStore  fresh database every run
///   -UITestStubCamera     generated photo instead of the system camera
final class LabLogFlowUITests: XCTestCase {
    private var app: XCUIApplication!
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-UITestInMemoryStore", "-UITestStubCamera"]
        app.launch()
    }

    private func snap(_ name: String, wholeScreen: Bool = false) {
        let shot = wholeScreen ? XCUIScreen.main.screenshot() : app.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    /// Scroll an element into the clear band between the navigation bar and
    /// the floating Submit bar (a centre tap under the bar hits the bar).
    private func scrollIntoView(_ target: XCUIElement) {
        XCTAssertTrue(target.waitForExistence(timeout: 5))
        let navBottom = app.navigationBars.firstMatch.frame.maxY + 8
        let bar = element("submit-record")
        let barTop = (bar.exists ? bar.frame.minY : app.frame.maxY) - 16
        for _ in 0..<6 {
            let top = target.frame.minY
            if top + 44 > barTop {
                app.swipeUp(velocity: .slow)
            } else if top < navBottom {
                app.swipeDown(velocity: .slow)
            } else {
                return
            }
        }
    }

    /// Quick action: tap the step's status circle.
    private func tapNode(_ order: Int) {
        let node = element("step-node-\(order)")
        scrollIntoView(node)
        node.tap()
    }

    /// Open the step guide by tapping the step card near its top.
    private func openGuide(_ order: Int) {
        let card = element("step-\(order)")
        scrollIntoView(card)
        card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0)).withOffset(CGVector(dx: 0, dy: 24)).tap()
        XCTAssertTrue(element("close-guide").waitForExistence(timeout: 5))
        sleep(1)
    }

    private func closeGuide() {
        element("close-guide").tap()
        sleep(1)
    }

    private func goBack(times: Int = 1) {
        for _ in 0..<times {
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
    }

    private func allowSystemAlertIfShown(_ buttons: [String], timeout: TimeInterval = 4) {
        for title in buttons {
            let button = springboard.buttons[title]
            if button.waitForExistence(timeout: timeout) {
                button.tap()
                return
            }
        }
    }

    /// Branching DAG experiment: locked step → reason, step guide, photo guard, submit.
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

        // Circle on Step 4 (needs Steps 1 and 3) → explains why it's locked.
        tapNode(4)
        XCTAssertTrue(element("toast").waitForExistence(timeout: 3))
        snap("05-locked-step-reason")

        // Card on Step 4 → the guide lists what's blocking it…
        openGuide(4)
        snap("06-guide-locked")
        // …tap a blocker to jump to its guide, and complete it from there.
        app.buttons.containing(NSPredicate(format: "label CONTAINS 'Rinse and fill the burette'")).firstMatch.tap()
        XCTAssertTrue(element("guide-mark-done").waitForExistence(timeout: 5))
        sleep(1)
        snap("07-guide-step")
        element("guide-mark-done").tap()
        XCTAssertTrue(element("guide-next").waitForExistence(timeout: 5))
        sleep(1)
        snap("08-guide-done-next")
        closeGuide()

        tapNode(2)
        tapNode(3)
        sleep(1)
        snap("09-photo-guard")

        // Photo guard: circle opens the camera (stubbed) and completes the step.
        tapNode(4)
        XCTAssertTrue(app.staticTexts["Evidence"].waitForExistence(timeout: 5))
        tapNode(5)

        let observation = element("observation")
        scrollIntoView(observation)
        observation.tap()
        observation.typeText("Endpoint at 24.60 mL, faint pink persisted for 30 s. Concordant titres: 24.60, 24.55 mL.")
        if app.buttons["Done"].exists { app.buttons["Done"].tap() }
        sleep(1)
        snap("10-ready-to-submit")

        element("submit-record").tap()
        XCTAssertTrue(element("confirm-submit").waitForExistence(timeout: 5))
        sleep(1)
        snap("10b-review-submit")
        element("confirm-submit").tap()
        allowSystemAlertIfShown(["Allow While Using App", "Allow Once"])
        XCTAssertTrue(element("submit-success").waitForExistence(timeout: 20))
        snap("10c-submitted-success")
        XCTAssertTrue(app.staticTexts["Submission"].waitForExistence(timeout: 10))
        sleep(2) // map tiles
        app.swipeUp()
        snap("11-submitted")

        goBack(times: 3)
        XCTAssertTrue(element("lab-CHEM201").waitForExistence(timeout: 5))
        app.tabBars.buttons["Records"].tap()
        sleep(1)
        snap("12-records")

        app.tabBars.buttons["Sync"].tap()
        sleep(1)
        snap("13-sync-status")
    }

    /// Timer guard: live row + pill, the interactive dial, the Dynamic Island.
    func testPendulumTimer() {
        XCTAssertTrue(element("lab-PHYS101").waitForExistence(timeout: 10))
        element("lab-PHYS101").tap()
        // Wait for each push to finish; tapping mid-transition is flaky.
        XCTAssertTrue(element("experiment-Simple Pendulum").waitForExistence(timeout: 5))
        element("experiment-Simple Pendulum").tap()
        XCTAssertTrue(element("start-record").waitForExistence(timeout: 5))
        element("start-record").tap()
        XCTAssertTrue(element("step-1").waitForExistence(timeout: 5))
        tapNode(1)
        tapNode(2) // photo (stubbed) → completes step 2 → the 30 s wait starts
        allowSystemAlertIfShown(["Allow"]) // notification permission, asked at the first timer
        sleep(2)
        snap("14-timer-row-and-pill")

        element("timer-pill").tap()
        XCTAssertTrue(element("timer-dial").waitForExistence(timeout: 5))
        sleep(2)
        snap("15-timer-dial")
        element("timer-dial").tap()
        sleep(1)
        snap("16-timer-dial-ready-at")
        closeGuide()

        // Leave the app: the countdown continues in the Dynamic Island.
        XCUIDevice.shared.press(.home)
        sleep(3)
        snap("17-dynamic-island-compact", wholeScreen: true)
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.025)).press(forDuration: 1.2)
        sleep(2)
        snap("18-dynamic-island-expanded", wholeScreen: true)

        // Notification Centre shows the Lock Screen presentation.
        XCUIDevice.shared.press(.home)
        sleep(1)
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.005))
            .press(forDuration: 0.1, thenDragTo: springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.7)))
        sleep(2)
        snap("19-lock-screen-live-activity", wholeScreen: true)
        XCUIDevice.shared.press(.home)

        app.activate()
        // Pressing the island can also count as a tap: it deep-links into the
        // step guide (intended behaviour). Close it if it opened.
        if element("close-guide").waitForExistence(timeout: 3) { closeGuide() }
        XCTAssertTrue(element("timer-pill").waitForExistence(timeout: 10))
        goBack(times: 3)
        XCTAssertTrue(element("resume-card").waitForExistence(timeout: 5))
        sleep(1)
        snap("20-home-continue")
    }
    /// Real round trip: sign in as the demo student, complete steps (incl. a
    /// photo), and watch the outbox drain to the backend. Needs
    /// Config/Secrets.xcconfig + `supabase start` + `npm run dev` in
    /// lablog-backend; skipped otherwise.
    func testSignInAndSyncToServer() throws {
        app.tabBars.buttons["Sync"].tap()
        // The account card sits low on the screen; bring it above the tab bar.
        app.swipeUp()
        if element("sign-out").waitForExistence(timeout: 2) {
            element("sign-out").tap()
            app.swipeUp()
        }
        let signIn = element("sign-in")
        guard signIn.waitForExistence(timeout: 5) else {
            // Put the screen in the log: xcodebuild sometimes hangs after a
            // failure and the .xcresult (with its hierarchy) is lost.
            return XCTFail("No sign-in button. Screen:\n\(app.debugDescription)")
        }
        guard signIn.isEnabled else { throw XCTSkip("No backend configured in this build") }
        snap("21-sync-signed-out")

        signIn.tap()
        let email = element("email")
        XCTAssertTrue(email.waitForExistence(timeout: 5))
        sleep(1) // sheet settles; the email field focuses itself
        email.typeText("student@lablog.test")
        let password = element("password")
        password.tap()
        password.typeText("LabLog-Student-1")
        snap("22-sign-in")
        element("sign-in-submit").tap()
        XCTAssertTrue(element("sign-out").waitForExistence(timeout: 15), "sign-in against Supabase Auth")

        // Create work locally: two steps, one with a photo → record + upload.
        sleep(1) // let the sign-in sheet finish dismissing
        app.tabBars.buttons["Labs"].tap()
        XCTAssertTrue(element("lab-PHYS101").waitForExistence(timeout: 10))
        element("lab-PHYS101").tap()
        XCTAssertTrue(element("experiment-Simple Pendulum").waitForExistence(timeout: 5))
        element("experiment-Simple Pendulum").tap()
        XCTAssertTrue(element("start-record").waitForExistence(timeout: 5))
        element("start-record").tap()
        tapNode(1)
        tapNode(2)
        allowSystemAlertIfShown(["Allow"])
        sleep(2)
        goBack(times: 3)

        app.tabBars.buttons["Sync"].tap()
        app.swipeDown()
        let synced = app.staticTexts["Everything is synced"]
        if !synced.waitForExistence(timeout: 20) {
            element("sync-now").tap()
            XCTAssertTrue(synced.waitForExistence(timeout: 20), "outbox drained to the server")
        }
        sleep(1)
        snap("23-synced-to-server")
        app.swipeUp()
        element("sign-out").tap()
    }
}
