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
        // A local build reaches the Mac's backend through loopback, whatever its Wi-Fi
        // address is today (failure 015); a hosted build ignores the setting.
        app.launchArguments = ["-UITestInMemoryStore", "-UITestStubCamera", "-LabLogServerHost", "127.0.0.1"]
        // The test account keeps records from earlier tests; only the sign-in test
        // restores them (ADR-028), the others start from an empty phone.
        if !name.contains("testSignInAndSyncToServer") { app.launchArguments.append("-UITestSkipRestore") }
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

    /// Tap a text field and wait for the keyboard before typing: on a loaded
    /// simulator the first tap can land before the field takes focus (017).
    private func focus(_ field: XCUIElement) {
        field.tap()
        if !app.keyboards.firstMatch.waitForExistence(timeout: 4) { field.tap() }
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 4), "keyboard never appeared")
    }

    /// Open the step guide by tapping the step card near its top.
    private func openGuide(_ order: Int) {
        let card = element("step-\(order)")
        scrollIntoView(card)
        let point = card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0)).withOffset(CGVector(dx: 0, dy: 24))
        point.tap()
        if !element("close-guide").waitForExistence(timeout: 5) { point.tap() } // dropped tap (017)
        XCTAssertTrue(element("close-guide").waitForExistence(timeout: 5))
        sleep(1)
    }

    private func closeGuide() {
        element("close-guide").tap()
        sleep(1)
    }

    /// Tap something that navigates, then wait for the destination. A tap that
    /// lands mid-transition can be dropped (failures 006 and 010), so retry.
    private func tap(_ id: String, expecting next: String) {
        let source = element(id)
        XCTAssertTrue(source.waitForExistence(timeout: 10), "\(id) not found")
        source.tap()
        // A slow (loaded) simulator can drop a tap during a transition: retry twice (016, 017).
        for _ in 0..<2 where !element(next).waitForExistence(timeout: 6) {
            if source.exists && source.isHittable { source.tap() }
        }
        waitOrDump(element(next), timeout: 10, next)
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

    /// Local demo accounts (the UI tests run against the local stack).
    /// Accounts: the local stack's demo accounts, or, against the hosted backend,
    /// test-only accounts passed in by `scripts/test-hosted.sh` (its
    /// TEST_RUNNER_LABLOG_TEST_* variables arrive here as LABLOG_TEST_*), so a
    /// test run never touches the demo accounts' data (ADR-030).
    private static let environment = ProcessInfo.processInfo.environment
    private static let isHosted = environment["LABLOG_TEST_HOSTED"] == "1"
    private static func account(_ key: String, _ email: String, _ password: String) -> (email: String, password: String) {
        (environment[key] ?? email, environment["\(key)_PASSWORD"] ?? password)
    }
    private static let student = account("LABLOG_TEST_STUDENT", "student@lablog.test", "LabLog-Student-1")
    private static let student2 = account("LABLOG_TEST_STUDENT2", "student2@lablog.test", "LabLog-Student-2")
    private static let lecturer = account("LABLOG_TEST_LECTURER", "lecturer@lablog.test", "LabLog-Lecturer-1")

    /// The app opens on sign-in (ADR-027): sign in there. A build without a
    /// backend has no sign-in screen; tests that need the server skip then.
    private func signIn(_ account: (email: String, password: String) = student, required: Bool = false) throws {
        let emailField = element("email")
        let labsTab = app.tabBars.buttons["Labs"]
        for _ in 0..<40 where !emailField.exists && !labsTab.exists { usleep(250_000) }
        guard emailField.exists else {
            if required { throw XCTSkip("No backend configured in this build") }
            return
        }
        focus(emailField)
        emailField.typeText(account.email)
        let passwordField = element("password")
        focus(passwordField)
        // Return submits (the keyboard can cover the button on a small screen).
        passwordField.typeText(account.password + "\n")
        let submit = element("sign-in-submit")
        if !labsTab.waitForExistence(timeout: 10), submit.exists, submit.isHittable { submit.tap() }
        waitOrDump(labsTab, timeout: 15, "signed in (sign-in against Supabase Auth)")
    }

    /// Sign out from the Sync tab and confirm the app is back on sign-in.
    private func signOut() {
        selectTab("Sync")
        app.swipeUp()
        guard element("sign-out").waitForExistence(timeout: 3) else { return }
        element("sign-out").tap()
        let confirm = app.alerts.buttons["Sign Out"].firstMatch // only when work hasn't uploaded
        if !confirm.waitForExistence(timeout: 2), !element("email").exists,
           element("sign-out").exists, element("sign-out").isHittable {
            element("sign-out").tap() // a dropped tap (017e)
        }
        if confirm.waitForExistence(timeout: 2) { confirm.tap() }
        XCTAssertTrue(element("email").waitForExistence(timeout: 10), "back on the sign-in screen")
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
    func testTitrationFlow() throws {
        try signIn()
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
        let blocker = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Rinse and fill the burette'")).firstMatch
        blocker.tap()
        if !element("guide-mark-done").waitForExistence(timeout: 5), blocker.exists { blocker.tap() } // dropped tap (017)
        XCTAssertTrue(element("guide-mark-done").waitForExistence(timeout: 5))
        sleep(1)
        snap("07-guide-step")
        tap("guide-mark-done", expecting: "guide-next")
        sleep(1)
        snap("08-guide-done-next")
        closeGuide()

        // Confirm each completion: a tap during the re-layout can be dropped (011, 016).
        completeStep(2)
        completeStep(3)
        sleep(1)
        snap("09-photo-guard")

        // Photo guard: circle opens the camera (stubbed) and completes the step.
        completeStep(4)
        XCTAssertTrue(app.staticTexts["Evidence"].waitForExistence(timeout: 5))
        completeStep(5)

        let observation = element("observation")
        scrollIntoView(observation)
        focus(observation)
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
    /// Retake a photo, note a step, discard the draft, then point the app at
    /// another server address and test it (Sync → Server).
    func testEditingADraftAndServerAddress() throws {
        try signIn()
        tap("lab-CHEM201", expecting: "experiment-Acid–Base Titration")
        tap("experiment-Acid–Base Titration", expecting: "start-record")
        tap("start-record", expecting: "step-1")
        completeStep(1)
        completeStep(2)
        completeStep(3)
        completeStep(4) // the circle opens the (stubbed) camera; the photo completes the step
        XCTAssertTrue(app.staticTexts["1 photo"].waitForExistence(timeout: 5))

        // The toolbar's sync icon explains itself in one sentence.
        tap("sync-indicator", expecting: "sync-status-details")
        sleep(1)
        snap("34-sync-status-popover")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.92)).tap() // dismiss
        XCTAssertTrue(element("sync-status-details").waitForNonExistence(timeout: 5))

        // Retake from the guide; a completed step can't lose its photo.
        openGuide(4)
        let retake = element("guide-retake-photo")
        XCTAssertTrue(retake.waitForExistence(timeout: 5))
        XCTAssertFalse(element("guide-remove-photo").exists, "a completed step keeps its evidence")
        XCTAssertTrue(retake.isHittable, "Retake sits on the photo, clear of the Next button (failure 012)")
        snap("28-guide-evidence")
        retake.tap()
        sleep(1)
        XCTAssertTrue(element("guide-next").exists, "still on Step 4's guide after the retake")

        let note = element("step-note")
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        if !note.isHittable { app.swipeUp(velocity: .slow) }
        focus(note)
        note.typeText("Titre 24.60 mL; faint pink lasted 30 s.")
        sleep(1)
        snap("29-step-note")
        closeGuide()
        XCTAssertTrue(app.staticTexts["1 photo"].waitForExistence(timeout: 5), "the retake replaced the photo")
        snap("30-checklist-with-note")

        // The note was saved with the step.
        openGuide(4)
        XCTAssertEqual(element("step-note").value as? String, "Titre 24.60 mL; faint pink lasted 30 s.")
        closeGuide()

        // Discard the draft from the record's menu.
        element("record-menu").tap()
        let discardItem = app.buttons["Discard draft"]
        XCTAssertTrue(discardItem.waitForExistence(timeout: 5))
        discardItem.tap()
        // iOS 26 alerts expose each button twice to XCUITest (failure 014): take the first.
        let confirm = app.alerts.firstMatch.buttons.matching(identifier: "Discard").firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        snap("31-discard-confirm")
        confirm.tap()
        XCTAssertTrue(element("start-record").waitForExistence(timeout: 5), "back on the experiment")
        selectTab("Records")
        XCTAssertTrue(app.staticTexts["No lab records"].waitForExistence(timeout: 5))

        // Sync → Server: test an address that answers, then one that doesn't.
        selectTab("Sync")
        let row = element("server-row")
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        guard row.isEnabled else {
            // A hosted build has one fixed address: the row shows it and opens nothing (ADR-025).
            if Self.isHosted {
                XCTAssertTrue(row.label.contains("vercel.app"), "the hosted server is shown")
                snap("32b-sync-server-hosted")
            }
            return // or a build without a backend
        }
        snap("32a-sync-server-row")
        row.tap()
        let field = element("server-host")
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        func replaceHost(_ text: String) {
            focus(field) // the keyboard must be up before typing (017)
            let old = (field.value as? String) ?? ""
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count + 2) + text)
        }
        replaceHost("127.0.0.1")
        element("server-test").tap()
        XCTAssertTrue(element("server-ok").waitForExistence(timeout: 12), "local backend answered")
        snap("32-server-settings")
        replaceHost("10.255.255.1")
        element("server-test").tap()
        XCTAssertTrue(element("server-failed").waitForExistence(timeout: 15))
        snap("33-server-unreachable")
        app.navigationBars["Server"].buttons["Cancel"].tap()
    }

    func testPendulumTimer() throws {
        try signIn()
        XCTAssertTrue(element("lab-PHYS101").waitForExistence(timeout: 10))
        tap("lab-PHYS101", expecting: "experiment-Simple Pendulum")
        tap("experiment-Simple Pendulum", expecting: "start-record")
        tap("start-record", expecting: "step-1")
        tapNode(1)
        tapNode(2) // photo (stubbed) → completes step 2 → the 30 s wait starts
        allowSystemAlertIfShown(["Allow"]) // notification permission, asked at the first timer
        sleep(2)
        snap("14-timer-row-and-pill")

        tap("timer-pill", expecting: "timer-dial") // retries a dropped tap (017)
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
        // The app opens on sign-in (ADR-027).
        if element("email").waitForExistence(timeout: 15) {
            sleep(1)
            snap("21-sign-in")
        }
        try signIn(required: true)

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
        sleep(1)
        snap("22-signed-out")

        // Signing out cleared this iPhone; signing back in restores the record from the server (ADR-028).
        try signIn(required: true)
        selectTab("Records")
        XCTAssertTrue(app.staticTexts["Simple Pendulum"].firstMatch.waitForExistence(timeout: 15), "record restored after sign-in")
        sleep(1)
        snap("12b-records-restored")
    }

    /// Lecturers manage labs instead of doing them (ADR-029): create a lab, add an
    /// experiment with step rules, and choose the students who can do it.
    func testLecturerCreatesALab() throws {
        try signIn(Self.lecturer, required: true)
        XCTAssertTrue(app.tabBars.buttons["Review"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.tabBars.buttons["Records"].exists, "lecturers don't do practicals")
        selectTab("Labs")
        sleep(1)
        snap("37-manage-labs")

        let code = "UI\(Int.random(in: 1000...9999))"
        tap("new-lab", expecting: "lab-code")
        focus(element("lab-code"))
        element("lab-code").typeText(code)
        focus(element("lab-name"))
        element("lab-name").typeText("UI Test Lab")
        element("create-lab").tap()
        tap("manage-\(code)", expecting: "add-experiment")

        tap("add-experiment", expecting: "experiment-title")
        focus(element("experiment-title"))
        element("experiment-title").typeText("Heating test\n") // Return puts the keyboard away
        tap("add-step", expecting: "step-title")
        focus(element("step-title"))
        element("step-title").typeText("Weigh the sample")
        element("step-done").tap()
        tap("add-step", expecting: "step-title")
        focus(element("step-title"))
        element("step-title").typeText("Photograph the result\n")
        let photo = app.switches["step-photo"]
        photo.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        element("after-1").tap()
        sleep(1)
        snap("38-step-rules")
        element("step-done").tap()
        XCTAssertTrue(element("draft-step-2").waitForExistence(timeout: 5))
        XCTAssertTrue(element("draft-step-2").label.contains("After 1"), "the step's rules are summarised")
        sleep(1)
        snap("39-new-experiment")
        element("save-experiment").tap()
        XCTAssertTrue(element("edit-Heating test").waitForExistence(timeout: 15), "the experiment is in the lab")

        // Edit it: add a third step after step 2; the existing steps keep their ids.
        tap("edit-Heating test", expecting: "draft-step-2")
        tap("add-step", expecting: "step-title")
        focus(element("step-title"))
        element("step-title").typeText("Clean up")
        element("after-2").tap()
        element("step-done").tap()
        XCTAssertTrue(element("draft-step-3").waitForExistence(timeout: 5))
        element("save-experiment").tap()
        // The row is already there behind the sheet, so wait for its label to change.
        let saved = NSPredicate(format: "label CONTAINS %@", "3 steps")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: saved, object: element("edit-Heating test"))],
                                      timeout: 15), .completed, "the edit is saved")

        tap("choose-students", expecting: "student-\(Self.student2.email)")
        element("student-\(Self.student2.email)").tap()
        element("save-students").tap()
        XCTAssertTrue(app.staticTexts[Self.student2.email].waitForExistence(timeout: 10), "the student can now do the lab")
        sleep(1)
        snap("40-manage-lab")
        goBack()
        signOut()
    }

    /// Lecturer view: a student submits, it syncs, the lecturer reviews it.
    func testLecturerReview() throws {
        try signIn(required: true)

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

        try signIn(Self.lecturer, required: true)
        XCTAssertTrue(app.tabBars.buttons["Review"].waitForExistence(timeout: 5), "lecturer gets a Review tab")
        selectTab("Review")
        sleep(1)
        snap("24-review-home")
        tap("review-Acid–Base Titration", expecting: "submission-\(Self.student.email)")
        sleep(1)
        snap("25-submissions")
        // The newest submission; retry a tap dropped while the list settles (017).
        let submission = element("submission-\(Self.student.email)")
        submission.tap()
        if !app.staticTexts["Procedure"].waitForExistence(timeout: 6), submission.isHittable { submission.tap() }
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
