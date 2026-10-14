# Failure Log & AI Decision Records

> **Graded requirement** (from the brief): *"document your process of implementation. If you
> used AI for certain parts you need to provide prompts and show the failures and errors that
> you got during your implementation."*
>
> Keep this live. Every time you hit an error, add an entry **with a screenshot**. Every time
> you use AI, record the **prompt**, what it produced, and whether it worked.

## How to use this file
- **Screenshots** go in `docs/screenshots/` and are linked from entries here.
- One entry per meaningful failure OR AI interaction. Don't batch at the end.
- Capture: Xcode build errors, runtime crashes, failed network calls, Supabase errors,
  sync bugs, constraint-logic edge cases.

---

## Template — copy for each entry

```
### [YYYY-MM-DD] <short title>
**Type:** build error | runtime crash | network | supabase | sync | logic | AI-prompt
**What I was doing:** …
**Error / output:**
    <paste the exact error text>
**Screenshot:** ![desc](screenshots/NNN-slug.png)
**Cause:** …
**Fix:** …
**AI prompt used (if any):**
    > <the exact prompt>
**AI result:** worked | partially | failed — <what happened>
```

---

## Entries

### [2026-10-12] Domain struct `Observation` shadowed Apple's Observation module
**Type:** build error
**What I was doing:** First build of the new `LabLog.xcodeproj` (`xcodebuild test`, iPhone 17 Pro simulator, Xcode 27.0 / Swift 6.4).
**Error / output:**
    macro expansion @Observable:1:49: error: 'Observable' is not a member type of struct 'LabLog.Observation'
    |1 | extension Reachability: nonisolated Observation.Observable {
    macro expansion @Observable:1:70: error: type 'Observation' has no member 'ObservationRegistrar'
    Entities.swift:63:8: note: 'Observation' declared here
    ** TEST FAILED **
**Screenshot:** ![error](screenshots/001-observation-shadows-module.png) (made from the exact xcodebuild output). Full compiler output: [`screenshots/001-observation-shadows-module.log`](screenshots/001-observation-shadows-module.log).
**Cause:** The `@Observable` macro (used by `Reachability` and `SyncEngine`) expands to fully-qualified names like `Observation.Observable` and `Observation.ObservationRegistrar`. Our domain entity was also called `Observation`, so inside the `LabLog` module the name resolved to our struct instead of Apple's `Observation` module, and the macro output stopped compiling.
**Fix:** Renamed the domain entity to `LabObservation` (`Entities.swift`, `LocalStore.addObservation`). The wire DTO (`SyncObservationDTO`) and the backend's `observations` JSON key are unchanged. Lesson: don't give domain types the same name as a system module (`Observation`, `Foundation`, `Network`, …).
**AI prompt used (if any):**
    > check the status of this project and install the app in my iphone
**AI result:** worked — Claude Code found the cause from the compiler notes and proposed the rename; rebuild passed (3/3 `StepConstraintEngineTests` green).

### [2026-10-12] SwiftData ModelContainer freed while its context was in use (test host crash loop)
**Type:** runtime crash
**What I was doing:** First run of the new `SwiftDataStoreTests` / `SyncEngineTests` (in-memory SwiftData).
**Error / output:**
    Exception Type:  EXC_BREAKPOINT (SIGTRAP)
    3  LabLog.debug.dylib  SwiftDataStore.hasCatalog()  (SwiftDataStore.swift:32)
    5  LabLog.debug.dylib  static CatalogSeed.installIfNeeded(into:)  (CatalogSeed.swift:101)
    6  LabLogTests         SwiftDataStoreTests.setUp()  (SwiftDataStoreTests.swift:12)
    Restarting after unexpected exit, crash, or test timeout; … (16 restarts)
On the Mac this showed up as a repeating "LabLog quit unexpectedly" dialog.
**Screenshot:** ![crash](screenshots/002-swiftdata-container-released.png) (from the crash report + xcodebuild output; raw: [`002-swiftdata-container-released.log`](screenshots/002-swiftdata-container-released.log)). _TODO: also save my screenshot of the macOS dialog as `screenshots/002-lablog-quit-unexpectedly.png`._
**Cause:** `SwiftDataStore` kept only `container.mainContext`. A `ModelContext` doesn't retain its `ModelContainer`, so in the tests (where nothing else held it) the container was freed and the next fetch trapped. The app only escaped because `AppModel` happened to hold the container too.
**Fix:** The store now keeps a strong reference to the `ModelContainer`. Re-ran: 28/28 unit tests pass with no crash.
**AI prompt used:**
    > i get this error repetatively
**AI result:** worked. Claude read the `.ips` crash report, found the cause and applied a one-line ownership fix.

### [2026-10-12] Badge text wrapped / disappeared; Sync "Network" row far too tall
**Type:** logic (UI layout)
**What I was doing:** Reviewing the UI-test screenshots of the first full build.
**Error / output:** The "Pending" badge wrapped to "Pend-ing" in the Records list. The Network row on the Sync screen was about 4× the normal height. The first fix (`.fixedSize()` on the badge `Label`) made the word disappear, leaving only the icon.
**Screenshot:** before ![wrap](screenshots/003-badge-wraps-before.png) · attempt 2 ![icon only](screenshots/003-badge-icon-only-attempt2.png) · after ![fixed](screenshots/003-badge-wraps-after.png) · Sync row before ![tall](screenshots/003-network-row-tall-before.png) / after ![ok](screenshots/003-network-row-tall-after.png)
**Cause:** SwiftUI's automatic `Label` style adapts to its container. In a tight List row it collapsed to icon-only. Inside `LabeledContent` it laid out as a stacked title/subtitle pair.
**Fix:** Use an explicit `HStack { Image; Text }` with `.lineLimit(1).fixedSize()` for badges and the Network value.
**AI result:** partially. The first fix was wrong (icon only); the second worked.

### [2026-10-14] Flaky lecturer UI test: tab tap ignored, step tapped mid-layout
**Type:** logic (UI test)
**What I was doing:** Adding `testLecturerReview`: the student submits, it syncs, and the lecturer reviews it in the new Review tab.
**Error / output:**
    Run A: failed - No sign-in button  (dump: still on the Labs tab although "Sync" was tapped at 6.31 s)
    Run B: LabLogFlowUITests.swift:343: XCTAssertTrue failed  (no confirm sheet: Step 5 never completed, so Submit stayed disabled)
**Screenshot:** ![flaky](screenshots/011-flaky-lecturer-ui-test.png) (raw: [`011-flaky-lecturer-ui-test.log`](screenshots/011-flaky-lecturer-ui-test.log))
**Cause:** A: the tab tap was sent but ignored right after launch. I didn't find the root cause; the same first step passed in the previous run. B: completed steps collapse and the list re-lays out, so the next circle tap landed while rows were still moving.
**Fix:** `selectTab(_:)` checks the navigation title and retries once. `completeStep(_:)` taps a circle, then waits until it reads "Step N done" (retrying once). Run C passed.
**AI prompt used:**
    > ok do next ones
**AI result:** partially. The lecturer view worked first time; the test needed two hardening rounds.

### [2026-10-14] GPS stamp "Not available" in test runs; flaky submit UI test
**Type:** logic (UI test / test environment)
**What I was doing:** Reviewing the report figures. The receipt from the last full UI run read "Location: Not available", although on 12 Oct the same flow produced coordinates and a map.
**Error / output:**
    Receipt: Location  Not available
    Run A: LabLogFlowUITests.swift:111: XCTAssertTrue failed            (no "start-record" after the tap)
    Run B: LabLogFlowUITests.swift:93: failed - submit-success not found  (yet the screen showed 'Submitted record' and 'Location, 6.9271, 79.8612')
**Screenshot:** ![not available](screenshots/010-location-not-available.png) ![runs](screenshots/010-gps-reset-and-flaky-submit.png) (raw: [`010-gps-reset-and-flaky-submit.log`](screenshots/010-gps-reset-and-flaky-submit.log))
**Cause:** Not an app bug. The simulator had been restarted since 12 Oct, so it no longer had a simulated location. The app did what it was designed to do: after a 10 s timeout, submit without a location. Once a location was set, two test bugs showed. A navigation tap on the cold-booted simulator was dropped. And because the GPS fix was now instant, the 1.6 s success screen came and went while the test was still waiting for a permission prompt.
**Fix:** The UI tests pin the location themselves (`XCUIDevice.shared.location`), retry a navigation tap once (`tap(_:expecting:)`), and watch for the success screen and any prompt in one polling loop. On failure, they print the app's and SpringBoard's screen trees. GPS verified: the receipt shows "6.9271, 79.8612" with the map.
**AI prompt used:**
    > ok do next ones
**AI result:** worked. Found while checking the report figures.

### [2026-10-14] Backend couldn't start: port 3000 already in use
**Type:** runtime crash (backend)
**What I was doing:** Starting the Express API (`npm run dev`) to connect the app to a local Supabase stack for the first real end-to-end sync.
**Error / output:**
    Error: listen EADDRINUSE: address already in use :::3000
      code: 'EADDRINUSE', address: '::', port: 3000
    $ curl http://192.168.1.8:3000/api/health  →  thxnura.labs Next.js 404 page
**Screenshot:** ![port](screenshots/008-port-3000-in-use.png) (raw: [`008-port-3000-in-use.log`](screenshots/008-port-3000-in-use.log))
**Cause:** Port 3000 (the default in `.env.example`) was already taken on my Mac by another project's Next.js dev server. The health check reached that site instead of LabLog.
**Fix:** The local setup script now writes `PORT=3100` by default (configurable with `--port`) and generates the matching iOS `Secrets.xcconfig`. I didn't touch the other server.
**AI prompt used:**
    > yes continue and do next build
**AI result:** worked.

### [2026-10-14] Flaky sign-in UI test (three different failures)
**Type:** logic (UI test)
**What I was doing:** Adding `testSignInAndSyncToServer`, which signs in as the demo student and checks the outbox drains to the real backend.
**Error / output:** Run 1: `LabLogFlowUITests.swift:227: XCTAssertTrue failed` (no sign-in button). Run 2: `Failed to tap "lab-PHYS101" … No matches found`. Run 3: `Failed to synthesize event: Neither element nor any descendant has keyboard focus`.
**Screenshot:** ![flaky](screenshots/009-flaky-sign-in-ui-test.png) (raw: [`009-flaky-sign-in-ui-test.log`](screenshots/009-flaky-sign-in-ui-test.log))
**Cause:** Run 1 is uncertain; a hierarchy dump in the next run showed the button half under the floating tab bar. Run 2: the test tapped the Labs tab while the sign-in sheet was still dismissing. Run 3: tapping the email field during the sheet animation didn't give it keyboard focus.
**Fix:** In the app, the sign-in sheet now focuses the email field itself (a UX gain: the keyboard is up straight away). In the test: scroll the account card into view, wait for the sheet to settle and for the Labs list to appear, and print the screen hierarchy on failure, because `xcodebuild` keeps hanging after failures and losing the `.xcresult`. Run 4 passed, and the record, 2 steps and the photo were confirmed in Postgres and Storage.
**AI result:** partially. It took three attempts.

### [2026-10-12] Submit confirmation rendered as a popover pointing at a step card (UX)
**Type:** logic (UI/UX)
**What I was doing:** Submitting a record on my iPhone (iOS 27.2, dark mode).
**Error / output:** The `.confirmationDialog("Submit this lab record?")` appeared as a floating popover near the top, with its arrow pointing at the Step 1 card. It looked broken, and it didn't show what was being submitted.
**Screenshot:** _TODO: save my iPhone screenshot as `screenshots/007-submit-popover.png`._ After: ![review sheet](screenshots/ui/ui-10b-review-submit.png) ![success](screenshots/ui/ui-10c-submitted-success.png)
**Cause:** On recent iOS, a confirmation dialog attached to a large container is presented as a popover anchored to that view, not as an action sheet from the button.
**Fix:** Replaced it with `SubmitReviewSheet`: a summary of steps, photos, observation and location; a warning if there is no observation; one primary "Submit lab record" button and a "Keep editing" option; then an animated "Submitted" state that closes itself. (ADR-017)
**AI prompt used:**
    > this submit dialog look ugly, fix it, also make dynamic island more good with details and make proffesional
**AI result:** worked. Verified in UI-test screenshots.

### [2026-10-12] Flaky timer UI test (tap during push; island press deep-linked)
**Type:** logic (UI test)
**What I was doing:** Re-running `testPendulumTimer` to recapture screenshots.
**Error / output:** Run A: `Failed to tap "start-record" Any: No matches found`. Run B: `LabLogFlowUITests.swift:207: XCTAssertTrue failed` (waiting for `timer-pill` after returning to the app).
**Screenshot:** ![flaky](screenshots/006-flaky-pendulum-ui-test.png) (raw: [`006-flaky-pendulum-ui-test.log`](screenshots/006-flaky-pendulum-ui-test.log))
**Cause:** A: the test tapped the experiment and then Start before the navigation push had finished. B: the long-press that expands the Dynamic Island also registered as a tap. That opened the app through the Live Activity's deep link, which opened the step guide over the timer pill. That part is correct app behaviour; the test didn't expect it.
**Fix:** Added `waitForExistence` before each tap in the flow, and the test now closes the guide if the island press opened it.
**AI result:** worked after both fixes.

### [2026-10-12] Container accessibilityIdentifier overrode every child's identifier
**Type:** logic (UI test / accessibility)
**What I was doing:** Running the UI tests after adding the step guide sheet and the Live Activity timer.
**Error / output:**
    LabLogFlowUITests.swift:63: error: -[LabLogUITests.LabLogFlowUITests testTitrationFlow] : XCTAssertTrue failed
    LabLogFlowUITests.swift:176: error: -[LabLogUITests.LabLogFlowUITests testPendulumTimer] : XCTAssertTrue failed
    (debug description) Button …, identifier: 'step-guide', label: 'Close guide'
**Screenshot:** ![ids](screenshots/005-accessibility-id-overrides-children.png) (raw: [`005-accessibility-id-overrides-children.log`](screenshots/005-accessibility-id-overrides-children.log))
**Cause:** The guide sheet *did* open. But I had put `.accessibilityIdentifier("step-guide")` on the sheet's root view, and SwiftUI pushes a container's identifier down onto its children, replacing their own (`close-guide`, `guide-mark-done`, `timer-dial`). The tests waited for ids that no longer existed.
**Second instance (same run, pendulum test):** the record header card had `.accessibilityElement(children: .combine)` applied *after* the floating timer pill was overlaid on it. That merged the pill into the header, so the whole header (`label: '2, of 4, Simple Pendulum…'`) carried the `timer-pill` identifier, and the test tapped the header's centre instead of the pill. This was also wrong for VoiceOver users, because the pill wasn't a separate button.
**Fix:** Removed the container-level identifiers (guide sheet, evidence section, submission receipt). Moved `.accessibilityElement(children: .combine)` before the pill overlay so the pill stays its own button. Re-ran: both UI tests pass. Lesson: only put identifiers on leaf elements, and combine accessibility children before overlaying controls.
**AI prompt used:**
    > add more interactibe animations like when timer goes show them in dynamic island and show interactive timer, and when we click step add step guide as well
**AI result:** partially. The feature built cleanly first time, but this mistake failed both UI tests until it was fixed.

### [2026-10-12] UI test tapped the floating Submit bar instead of Step 4 (+ xcodebuild hang)
**Type:** logic (UI test)
**What I was doing:** Running the UI tests after the visual redesign (ADR-013).
**Error / output:**
    LabLogFlowUITests.swift:56: error: -[LabLogUITests.LabLogFlowUITests testTitrationFlow] : XCTAssertTrue failed
    (waiting for the "toast" element after tapping step-4)
After the failure, `xcodebuild` stayed alive for more than 10 minutes and had to be killed, which also lost the automatic failure screenshot in the .xcresult.
**Screenshot:** ![ui test](screenshots/004-ui-test-tap-under-bottom-bar.png) (raw: [`004-ui-test-tap-under-bottom-bar.log`](screenshots/004-ui-test-tap-under-bottom-bar.log))
**Cause:** The redesign pins Submit to a floating bottom bar. Step 4's card sat partly under it, and XCUITest taps an element's centre, so the tap landed on the disabled Submit button. A real user would scroll first, so this is a test bug, not an app bug.
**Fix:** A `tapStep(_:)` helper scrolls each card into the clear band between the navigation bar and the bottom bar, then taps near the card's top.
**AI prompt used:**
    > its look too much basic, make ui ux more like other porffesional app design with apple design skills
**AI result:** partially. The redesign shipped, but it broke this test until the helper was added.

### [2026-10-12] AI: build the full app
**Type:** AI-prompt
**AI prompt used:**
    > it shows scaffold ready, wire lab view and other stuff, build the full app, and if u detect errors, those should be screenshoted and make a doc
**AI result:** partially. Claude built the SwiftData store, outbox SyncEngine (photos first, batches of ≤100, per-item results, backoff 2→32 s), Supabase sign-in, the bundled catalog, all screens, camera + GPS wiring, 28 unit tests and 2 UI tests, and fixed backend contract mismatches (ADR-014). The first test run crashed (entry above). Errors and screenshots were also collected in a shared doc.

### [2026-10-12] AI: create the Xcode project and install on device
**Type:** AI-prompt
**What I was doing:** The repo only had source files (no `.xcodeproj`), so nothing could build or run.
**AI prompt used:**
    > check the status of this project and install the app in my iphone
**AI result:** worked — Claude Code wrote `LabLog.xcodeproj` (file-system-synchronized groups, shared `LabLog` scheme, generated Info.plist with camera + location usage strings), ran the unit tests on the simulator, built and signed it with my Personal Team (automatic signing, `-allowProvisioningUpdates`), and installed + launched it on my iPhone 17 Pro (iOS 27.2) with `xcrun devicectl`. The app installed fine but only shows the placeholder `RootView`, because the screens aren't wired up yet. See ADR-007.

<!-- Add entries below as you build. Example shape:

### [2026-10-04] SwiftData @Model could not reference struct Step
**Type:** build error
**What I was doing:** Making the LocalStore back onto SwiftData.
**Error / output:**
    Type 'Step' does not conform to protocol 'PersistentModel'
**Screenshot:** ![error](screenshots/001-swiftdata-model.png)
**Cause:** Tried to persist the plain Domain struct directly.
**Fix:** Added separate @Model classes that mirror the Domain structs; map at the store boundary.
**AI prompt used:**
    > How do I persist a plain Swift struct with SwiftData without making it a @Model?
**AI result:** partially — suggested a mapping layer, which I adopted.
-->
