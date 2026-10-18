# Decision Records (ADRs)

Every significant design decision taken while building LabLog, in the order it was made, as
**Context → Decision → Consequences**. The report summarises the most important ones (§3.2).

---

## ADR-001 — Native iOS (Swift/SwiftUI) over cross-platform
**Context.** The brief allows React Native, Flutter or native. The app targets a single platform.
**Decision.** Native iOS with SwiftUI; local persistence via SwiftData.
**Consequences.** First-class camera/location APIs and offline storage; no cross-platform reach (acceptable for a single-device demo).

## ADR-002 — Custom Express API in front of Supabase (not direct BaaS)
**Context.** The brief asks for a backend service. Supabase alone would be a backend-as-a-service with the rules living in the client.
**Decision.** Express + TypeScript service layer; app talks to Express, Express talks to Supabase with the service-role key.
**Consequences.** A real validation, authorisation and business-rule layer; one extra hop to run and deploy.

## ADR-003 — Local store is the source of truth while offline
**Context.** Lab Wi-Fi is unreliable; the app must work fully offline.
**Decision.** UI reads/writes SwiftData only; the network is a background sync concern (outbox pattern).
**Consequences.** Zero-connectivity usability; needs an explicit sync/reconcile step.

## ADR-004 — Client-generated UUIDs + idempotent upserts
**Context.** Flaky connections cause retries that could duplicate records.
**Decision.** Every record/step/photo gets a UUID on-device; backend upserts by id.
**Consequences.** Safe retries; ids must be created at entity-creation time, not at sync time.

## ADR-005 — Photos via Storage signed URLs, not base64 in JSON
**Context.** Photos are large; embedding them bloats the sync payload.
**Decision.** Request a signed upload URL, PUT the file to Supabase Storage, sync only the path.
**Consequences.** Lean sync payloads; two-step upload to orchestrate in the SyncEngine.

## ADR-006 — Constraint logic centralised in a pure engine
**Context.** The "Step N+1 after Step N" rule must be correct and testable.
**Decision.** `StepConstraintEngine` (pure, unit-tested) is the single source of unlock truth; views never re-implement it.
**Consequences.** One place to reason about correctness; views depend on the engine.

## ADR-007 — Xcode project committed to the repo; Personal Team signing
**Context.** The repo had only source folders, and the README told me to build the project by hand in Xcode. That can't be reproduced or reviewed, and nothing could be built from the command line. I also need to run on a real iPhone to demo the camera and GPS.
**Decision.** Commit `LabLog.xcodeproj` using Xcode's file-system-synchronized groups, so every file under `LabLog/` and `LabLogTests/` is picked up automatically with no per-file project entries. Add a shared `LabLog` scheme (Run + Test). Set the Info.plist keys (`NSCameraUsageDescription`, `NSLocationWhenInUseUsageDescription`) as build settings instead of a hand-edited plist. Bundle id `com.thxnura.LabLog`, iOS 17.0 minimum (needed for `@Observable` and `ContentUnavailableView`), iPhone only, portrait. Swift 5 language mode with the default (nonisolated) actor isolation, so the scaffold compiles unchanged; moving to Swift 6 strict concurrency is a later decision. Sign automatically with my free Personal Team.
**Consequences.** Anyone can clone and build with `xcodebuild` or Xcode, and adding a Swift file needs no project edits. The free Personal Team profile expires after **7 days**, so I must rebuild from Xcode before the viva or the app won't launch. The team is also limited to 3 sideloaded apps per device.

## ADR-008 — Bundle the catalog with the same ids as the server seed
**Context.** Before signing in, a student opening the app for the first time (maybe offline, in the lab) would see an empty app.
**Decision.** Ship `CatalogSeed` with the app, using the same UUIDs as `lablog-backend/db/seed.sql`. Install it if the device has no catalog. A server refresh replaces it once the student is online and signed in.
**Consequences.** Usable offline from the first launch, and records still sync to the right server rows. `CatalogSeed` and `seed.sql` must be kept in step, and a unit test checks that every bundled step graph is valid.

## ADR-009 — Record revision counter guards in-flight edits
**Context.** A sync request takes time. If the student edits a record while the request is in flight and the response then marks it `synced`, that edit never reaches the server.
**Decision.** Every local edit increments `LabRecord.revision`. The SyncEngine sends the revision it read, and `applySyncResult` only marks the record `synced` if the revision is unchanged; otherwise the record goes back to `pendingUpdate`.
**Consequences.** No lost updates, and it is covered by the `testEditDuringSyncKeepsRecordPending` unit test. It costs one integer column.

## ADR-010 — Supabase Auth over REST, optional sign-in, Keychain session
**Context.** The Express API needs a Supabase JWT. The Supabase Swift SDK is a large dependency for two calls (password sign-in and refresh).
**Decision.** `AuthService` calls GoTrue's `/auth/v1/token` with `URLSession`, stores the session in the Keychain, and refreshes it a minute before expiry. Sign-in is never required to use the app; only sync needs it.
**Consequences.** No third-party dependency, and the token flow is small enough to read and reason about. Supabase features beyond password and refresh grants would have to be added by hand.

## ADR-011 — Evidence photos: Application Support, relative names, downscaled
**Context.** The scaffold wrote photos to `tmp`, which iOS may purge before sync, and kept absolute paths, which break when the app container moves between installs.
**Decision.** `EvidenceStore` writes `<attachmentId>.jpg` into Application Support/Evidence. It downscales to a longest edge of 1600 px, uses JPEG quality 0.7, and stores only the file name.
**Consequences.** Evidence survives until it is uploaded, and uploads stay small on lab Wi-Fi. If a file does go missing, `markAttachmentLost` stops it from blocking the record forever.

## ADR-012 — Validate the step graph before using it (Kahn's algorithm)
**Context.** Steps form a DAG defined on the server. A typo (a cycle, or a prerequisite id that doesn't exist) would make an experiment impossible to finish.
**Decision.** `StepConstraintEngine.validate` reports self-dependencies, unknown prerequisites, and cycles, which it finds with Kahn's topological sort. `refreshCatalog` skips any experiment that has issues.
**Consequences.** Students never see an experiment they can't finish. Bad catalog data is logged instead of shipped. The algorithm is unit-tested: topological order, cycle detection, and dangling edges.

## ADR-013 — Design system and a timeline-style checklist
**Context.** The first build used stock Lists and looked generic. The UX criterion is worth 20%, and a student mid-experiment must see what to do next at a glance.
**Decision.** Add a small design system (`DesignSystem/Theme.swift`): semantic colours, a discipline palette, a 4-pt spacing grid, card surfaces, and critically damped springs by default, with bounce only when a step completes. The `ExperimentChecklist` becomes a timeline: a node rail with connectors, collapsed completed steps, a live timer ring, and inline photo thumbnails. Capture mode hides the tab bar and pins Submit to a floating bottom bar. Reduce Motion turns off the scale and bounce effects.
**Consequences.** One consistent look everywhere, and the next actionable step is always the most visible thing. More custom view code to maintain, and UI tests have to scroll cards clear of the floating bar (failure 004).

## ADR-014 — The API speaks camelCase; photo uploads are idempotent
**Context.** Review found that catalog endpoints returned raw Postgres rows (`lab_id`, `requires_photo`…) while the iOS decoders and the sync contract use camelCase. It also found that a retried photo upload to the same deterministic path would fail with "already exists".
**Decision.** Map rows to camelCase in `catalog.service.ts`; experiment detail returns `{…experiment, steps}` sorted by order. Call `createSignedUploadUrl(path, { upsert: true })`.
**Consequences.** One JSON convention end to end, and photo retries are safe, matching ADR-004. The mapping layer must be updated whenever a column is added.

## ADR-015 — Timed steps run as a Live Activity (Dynamic Island + Lock Screen)
**Context.** Timer guards (e.g. "Allow to dissolve (5 min)") make students wait. Mid-wait they put the phone down or switch apps, and they had no way to know when the step unlocked.
**Decision.** A widget extension (`LabLogWidgets`) draws a `StepTimerAttributes` Live Activity: a countdown and progress ring in the Dynamic Island (compact, minimal and expanded) and on the Lock Screen. The countdown uses `Text(timerInterval:)` / `ProgressView(timerInterval:)`, so the system keeps it live with no app updates; `staleDate` = end time flips it to "Ready". `StepTimerCoordinator` starts and ends the activity from the same precedence + duration rules as `StepConstraintEngine`. A "Mark done" button (`CompleteTimedStepIntent`, a `LiveActivityIntent`) runs in the app process through `LiveActivityBridge` and still has to pass the constraint engine. A local notification fires when the wait ends; notification permission is requested at the first timer, not at launch. A tap on the island or the notification deep-links (`lablog://record/<id>?step=<id>`) to the step guide.
**Consequences.** Students can leave the app during a wait and still see the countdown, and nothing can be completed early from the island. It adds a second target and shared code (`Shared/`), and the extension needs its own App ID under the free Personal Team.

## ADR-016 — Step guide; circle = quick action, card = guide
**Context.** A one-line instruction isn't enough to teach a procedure. Also, tapping a whole row to complete a step made accidental completions easy.
**Decision.** Each step can carry a `StepGuide` (how-to sub-steps, a safety note, the expected result). It is stored in new optional SwiftData fields and new `steps` columns (migration `002_step_guides.sql`), and the bundled catalog version is bumped so existing installs pick it up. In `ExperimentChecklist`, tapping the status circle is the quick action (complete / photo / explain lock); tapping the card fires the new `onStepSelected` event, which opens `StepGuideSheet`. The guide shows what blocks the step (tap a blocker to jump to its guide), an interactive timer dial (tap to switch between remaining time and ready-at), and the one action that moves the step forward, all through the constraint engine. A haptic fires when a timer guard runs out.
**Consequences.** Better teaching and fewer accidental taps, and the circle-vs-row pattern is familiar from Reminders. Guide content lives in two places (`CatalogSeed` and `seed.sql`); both are generated from one script so they stay identical, and a unit test checks every bundled step has a guide.

## ADR-017 — Review-and-submit sheet; richer Live Activity
**Context.** Submitting is the one irreversible action in the app, but the system confirmation dialog showed no detail and rendered as a misplaced popover. The first Live Activity only showed a countdown, with no sense of overall progress or what comes next.
**Decision.** Submission goes through `SubmitReviewSheet`. It shows what will be handed in (steps, photos, observation, location stamp), warns if there is no observation, has one primary action, and ends in an animated success state with a haptic. The Live Activity gains overall progress (step X of N plus progress dots), the lab name, start and ready times, an "Up next" line, a Guide link, and a distinct ready state (green "Wait over" with a prominent Mark done).
**Consequences.** Students confirm with full information (Apple's Agency principle: confirm only irreversible actions, with context). The island is useful at a glance. `StepTimerAttributes` carries more fields, and the coordinator updates the activity when other steps finish during a wait.

## ADR-018 — Local Supabase stack for real end-to-end testing
**Context.** Sync was only unit-tested against a fake API. The schema and seed had never run on a real Postgres, and there was no hosted Supabase project yet.
**Decision.** Run the Supabase stack locally with the CLI in Docker: Postgres, Auth (GoTrue), Storage and the API gateway, skipping services LabLog doesn't use. `supabase/` points at `db/schema.sql` and `db/seed.sql`, so `db/` stays the single source of truth, and it declares the private `evidence` bucket. `npm run local:setup [--host <LAN IP>] [--port 3100]` writes `.env`, creates demo student and lecturer accounts, and prints the iOS `Secrets.xcconfig`. `npm run test:e2e` runs 10 HTTP tests against the real stack, and a UI test signs in from the app and syncs.
**Consequences.** The whole path (app → signed upload → API → Postgres + Storage) is proven, and a demo can run on a laptop with no internet connection. Moving to a hosted project means running the same SQL and changing `.env` and `Secrets.xcconfig`. Docker must be running.

## ADR-019 — Lecturer role in app_metadata; ownership checks on sync
**Context.** `GET /api/records` returned every submission to any signed-in user. Also, because sync upserts by client UUID, a student who learned another student's record id could overwrite its owner.
**Decision.** The role comes from the JWT user's `app_metadata.role`, which only the service role can set, so students can't promote themselves. `requireRole('lecturer')` guards `/records`, and the `experimentId` query is validated as a UUID (422 otherwise). Before any upsert, `assertOwnership` refuses a record id owned by another student (403) and child ids (completions, observations, attachments) that belong to another record (409). The lecturer response is camelCase, with the student's email and 1-hour signed URLs for photos in the private bucket.
**Consequences.** Idempotent retries still work for the owner, and hijacking is blocked. E2E tests cover both, plus the 403 for students. It costs one extra lookup per record per sync.

## ADR-020 — In-app lecturer review, live from the API
**Context.** Lecturers could only review submissions through the API, which is hard to demo and incomplete as a product. A complete product needs the lecturer's side too.
**Decision.** Signed-in lecturers get a **Review** tab: experiments → submissions (student, time, steps done, photos, located) → a detail screen (stats, the step timeline with completion times and photos, the observation, a map). The app reads the role from the JWT's `app_metadata` only to decide what to *show*; the API still enforces `requireRole('lecturer')`. Submissions are fetched live and not cached offline, because lecturers review at a desk and the data belongs to other users. Photos use the API's 1-hour signed URLs. The API normalises timestamps to ISO 8601 UTC so the app's decoder is predictable.
**Consequences.** Both roles are demonstrable end to end in the app (covered by a UI test). The review screens need a connection, and signed URLs expire after an hour (pull to refresh).

## ADR-021 — The server address can change at runtime; storage URLs follow the caller
**Context.** The app's server address was compiled in from `Secrets.xcconfig` as the Mac's home-Wi-Fi IP (192.168.1.8). At a demo elsewhere the Mac gets another address, or campus Wi-Fi blocks devices from reaching each other. A rebuild would then be needed, and sync would fail in front of the examiner. The backend also built photo upload and download links from its own `SUPABASE_URL`, so those would still point at the old IP.
**Decision.** Sync → Server lets the student type the Mac's address. **Test connection** checks both the API (`/health`) and Supabase Auth, and the choice persists. The app keeps a thread-safe `ServerEndpoint` that `APIClient` and `AuthService` read on every request, so a change applies immediately without signing out (same Supabase project, new address). On the backend, `SUPABASE_URL` is loopback (127.0.0.1), and `forClient()` rewrites storage URLs to the host the app actually called, but only for a local or private-network Supabase. A hosted Supabase URL is untouched. `npm run local:setup` no longer bakes a LAN IP into `.env`.
**Consequences.** Moving networks, including the iPhone's own hotspot, needs one edit in the app and nothing on the Mac. A backend e2e test covers the rewrite and unit tests cover host replacement and validation. The address is still typed by hand; Bonjour discovery would remove that step.

## ADR-022 — Discarding a draft syncs a tombstone
**Context.** Drafts couldn't be deleted. A draft that was already synced also exists on the server, so deleting it only on the phone would leave an orphan that comes back nowhere but still sits in the database.
**Decision.** Discarding asks for confirmation. A draft the server has never received (`pendingCreate`), or any draft when the build has no server, is deleted on the phone straight away. Otherwise the record becomes a **tombstone**: its children and photo files are deleted locally, `deletedAt` is set, and it stays in the outbox, hidden from every screen. The next sync sends `deleted: true`. The API deletes the draft (children cascade, photo files removed) and treats "already gone" as success, so a retried tombstone is idempotent. It refuses submitted records (409) and other students' records (403). When the tombstone syncs, the phone purges it.
**Consequences.** Deletes are offline-first like every other write and can't be lost on a bad connection. Submitted records stay immutable evidence. The outbox count briefly includes the tombstone.

## ADR-023 — Retaking photos and per-step notes; the payload carries the full photo set
**Context.** Photos could only be added, so a blurry evidence photo was permanent. Steps also had nowhere for readings, although the model and API already had a `note` on each completion.
**Decision.** The step guide shows the step's photo with **Retake**. A retake saves the new photo first, then deletes the old one. **Remove** only appears while the step isn't done: a completed photo step is an invariant ("done ⇒ has evidence"), so its photo can be replaced but not removed. On the server, a record's sync payload now carries its full set of uploaded photos, and the API deletes any rows and files missing from it. Completed steps get a note field, debounced and capped at 2,000 characters to match the API. The note shows on the checklist row (`ChecklistRow` gains a `note` property), in the guide and in the lecturer's timeline. Drafts only: the store ignores photo and note edits on submitted records.
**Consequences.** Evidence can be corrected without leaving stale files in Storage, and the constraint engine's photo guard can't be bypassed after the fact. Covered by store unit tests, backend e2e tests ("a retaken photo replaces the old one") and a UI test. Deleting what is "missing" is only safe if ids compare reliably: the first version compared them as strings, and the app's upper-case UUIDs never matched Postgres's lower case, so every new photo was deleted (failure 018). The API now normalises ids to lower case at the boundary, and an e2e test sends them in upper case.

## ADR-024 — A quiet sync indicator instead of an "Online" pill
**Context.** Every main screen had a toolbar capsule reading "● Online 1". It announced the normal state all the time, the bare number didn't say what it counted, and on iOS 26 it sat as a pill inside the toolbar's own glass capsule. It looked unfinished.
**Decision.** The toolbar shows one sync icon whose state comes from a pure `SyncIndicatorState`: a check cloud when everything is synced (no text), an upload cloud with the outbox size while records wait, a pulsing sync icon while syncing, a warning cloud on failure, and a crossed-out cloud with the word **Offline**, the only state that gets a word. Signed out with records waiting is the same upload cloud in orange, not a person icon: next to the ••• button a person icon read as an account button. Tapping it opens a small popover that explains the status in one sentence ("2 records are saved on this iPhone and will upload when you're back online") with **Sync now** when that helps. Live reachability wins over a stale engine status.
**Consequences.** The common case is calm, and the unusual cases are explicit, as in Apple's own apps. The rules are unit-tested (`SyncIndicatorStateTests`). The detailed status still lives on the Sync tab.

