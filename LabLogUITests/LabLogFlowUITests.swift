import CoreLocation
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
        // A simulator's simulated location resets on reboot, which made the GPS
        // stamp come back "Not available". Pin it so submit is deterministic.
        XCUIDevice.shared.location = XCUILocation(location: CLLocation(latitude: 6.9271, longitude: 79.8612))
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

    /// Complete a step via its circle and confirm it took. Completed rows
    /// collapse and the list re-lays out, so a quick follow-up tap can miss.
    private func completeStep(_ order: Int) {
        let done = NSPredicate(format: "label == %@", "Step \(order) done")
        for _ in 0..<2 {
            tapNode(order)
            if element("step-node-\(order)").waitForExistence(timeout: 2),
               XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: done, object: element("step-node-\(order)"))],
                              timeout: 3) == .completed {
                return
            }
        }
        XCTFail("Step \(order) did not complete")
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

    /// Tap something that navigates, then wait for the destination. A tap that
    /// lands mid-transition can be dropped (failures 006 and 010), so retry once.
    private func tap(_ id: String, expecting next: String) {
        let source = element(id)
        XCTAssertTrue(source.waitForExistence(timeout: 10), "\(id) not found")
        source.tap()
        if !element(next).waitForExistence(timeout: 6) {
            if source.exists && source.isHittable { source.tap() }
            waitOrDump(element(next), timeout: 10, next)
        }
    }

    /// Wait for an element; on timeout fail with the app's AND SpringBoard's
    /// screen tree in the log (xcodebuild sometimes loses the .xcresult).
    @discardableResult
    private func waitOrDump(_ target: XCUIElement, timeout: TimeInterval, _ what: String) -> Bool {
        if target.waitForExistence(timeout: timeout) { return true }
        XCTFail("\(what) not found.\nAPP:\n\(app.debugDescription)\nSPRINGBOARD:\n\(springboard.debugDescription)")
        return false
    }

    /// Switch tabs and confirm it took: a tab tap right after launch was once
    /// ignored (failure 011, cause not found), so check the title and retry once.
    private func selectTab(_ name: String) {
        let button = app.tabBars.buttons[name]
        XCTAssertTrue(button.waitForExistence(timeout: 10), "\(name) tab missing")
        button.tap()
        if !app.navigationBars[name].waitForExistence(timeout: 3) {
            button.tap()
            waitOrDump(app.navigationBars[name], timeout: 5, "\(name) tab")
        }
    }

    /// Sign in from the Sync tab. Throws XCTSkip when the build has no backend.
    private func signIn(_ email: String, _ password: String) throws {
        selectTab("Sync")
        app.swipeUp() // the account card sits low; bring it above the tab bar
        if element("sign-out").waitForExistence(timeout: 2) {
            element("sign-out").tap()
            app.swipeUp()
        }
        let signInButton = element("sign-in")
        guard signInButton.waitForExistence(timeout: 5) else {
            return XCTFail("No sign-in button. Screen:\n\(app.debugDescription)")
        }
        guard signInButton.isEnabled else { throw XCTSkip("No backend configured in this build") }
        signInButton.tap()
        let emailField = element("email")
        XCTAssertTrue(emailField.waitForExistence(timeout: 5))
        sleep(1) // sheet settles; the email field focuses itself
        emailField.typeText(email)
        let passwordField = element("password")
        passwordField.tap()
        passwordField.typeText(password)
        element("sign-in-submit").tap()
        XCTAssertTrue(element("sign-out").waitForExistence(timeout: 15), "sign-in against Supabase Auth")
        sleep(1) // let the sheet finish dismissing
    }

    private func signOut() {
        selectTab("Sync")
        app.swipeUp()
        if element("sign-out").waitForExistence(timeout: 3) { element("sign-out").tap() }
    }

    /// Wait until the Sync tab reports the outbox drained (tapping Sync now once if needed).
    private func waitUntilSynced() {
        selectTab("Sync")
        app.swipeDown()
        let synced = app.staticTexts["Everything is synced"]
        if !synced.waitForExistence(timeout: 20) {
            if element("sync-now").exists { element("sync-now").tap() }
            waitOrDump(synced, timeout: 20, "Everything is synced")
        }
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

        tap("lab-CHEM201", expecting: "experiment-Acid–Base Titration")
        snap("02-experiments")

        tap("experiment-Acid–Base Titration", expecting: "start-record")
        snap("03-experiment-detail")

        tap("start-record", expecting: "step-1")
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
        // The success state shows for ~1.6 s, so watch for it and for a
        // location prompt at the same time rather than one after the other.
        var sawSuccess = false
        for _ in 0..<50 {
            for title in ["Allow While Using App", "Allow Once"] where springboard.buttons[title].exists {
                springboard.buttons[title].tap()
            }
            if element("submit-success").exists {
                usleep(400_000) // let the success animation land
                snap("10c-submitted-success")
                sawSuccess = true
                break
            }
            usleep(200_000)
        }
        XCTAssertTrue(sawSuccess || app.staticTexts["Submitted record"].exists, "record was not submitted")
        XCTAssertTrue(app.staticTexts["Submission"].waitForExistence(timeout: 10))
        sleep(2) // map tiles
        app.swipeUp()
        snap("11-submitted")

        goBack(times: 3)
        XCTAssertTrue(element("lab-CHEM201").waitForExistence(timeout: 5))
        selectTab("Records")
        sleep(1)
        snap("12-records")

        selectTab("Sync")
        sleep(1)
        snap("13-sync-status")
    }

    /// Timer guard: live row + pill, the interactive dial, the Dynamic Island.
    func testPendulumTimer() {
        XCTAssertTrue(element("lab-PHYS101").waitForExistence(timeout: 10))
        tap("lab-PHYS101", expecting: "experiment-Simple Pendulum")
        tap("experiment-Simple Pendulum", expecting: "start-record")
        tap("start-record", expecting: "step-1")
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
        selectTab("Sync")
        app.swipeUp()
        if element("sign-out").waitForExistence(timeout: 2) { element("sign-out").tap() }
        snap("21-sync-signed-out")
        try signIn("student@lablog.test", "LabLog-Student-1")

        // Create work locally: two steps, one with a photo → record + upload.
        selectTab("Labs")
        tap("lab-PHYS101", expecting: "experiment-Simple Pendulum")
        tap("experiment-Simple Pendulum", expecting: "start-record")
        tap("start-record", expecting: "step-1")
        tapNode(1)
        tapNode(2)
        allowSystemAlertIfShown(["Allow"])
        sleep(2)
        goBack(times: 3)

        waitUntilSynced()
        sleep(1)
        snap("23-synced-to-server")
        signOut()
    }

    /// Lecturer view: a student submits, it syncs, the lecturer reviews it.
    func testLecturerReview() throws {
        try signIn("student@lablog.test", "LabLog-Student-1")

        selectTab("Labs")
        tap("lab-CHEM201", expecting: "experiment-Acid–Base Titration")
        tap("experiment-Acid–Base Titration", expecting: "start-record")
        tap("start-record", expecting: "step-1")
        for order in 1...5 { completeStep(order) }
        element("submit-record").tap()
        XCTAssertTrue(element("confirm-submit").waitForExistence(timeout: 5))
        element("confirm-submit").tap()
        for _ in 0..<50 {
            for title in ["Allow While Using App", "Allow Once"] where springboard.buttons[title].exists {
                springboard.buttons[title].tap()
            }
            if app.staticTexts["Submitted record"].exists { break }
            usleep(200_000)
        }
        XCTAssertTrue(app.staticTexts["Submitted record"].waitForExistence(timeout: 10))
        goBack(times: 3)
        waitUntilSynced()
        signOut()

        try signIn("lecturer@lablog.test", "LabLog-Lecturer-1")
        XCTAssertTrue(app.tabBars.buttons["Review"].waitForExistence(timeout: 5), "lecturer gets a Review tab")
        selectTab("Review")
        sleep(1)
        snap("24-review-home")
        tap("review-Acid–Base Titration", expecting: "submission-student@lablog.test")
        sleep(1)
        snap("25-submissions")
        element("submission-student@lablog.test").tap()
        waitOrDump(app.staticTexts["Procedure"], timeout: 10, "submission detail")
        sleep(3) // photo + map tiles
        snap("26-submission-detail")
        app.swipeUp()
        sleep(2)
        snap("27-submission-detail-location")
        goBack(times: 2)
        signOut()
    }
}
