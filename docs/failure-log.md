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
