# LabLog — iOS

**Digital Practical Lab Book** — offline-first iOS app (SE5070 Enterprise Mobility, Edtech).
Students work through a precedence-constrained experiment checklist, attach photo evidence,
and submit location-stamped lab records that sync to the backend when back online.

## Source layout

```
LabLog/
  App/            LabLogApp, AppModel (composition root), AppConfig, RootView (tabs)
  DesignSystem/   Theme tokens (colour, spacing, radius, motion) + shared components
  Features/       LabList (home), ExperimentList, ExperimentDetail, RecordCapture,
                  Records, SyncStatus, Auth
  Components/
    ExperimentChecklist/   ★ custom component (timeline, precedence-constrained)
    SyncStateBadge         status / sync / connectivity chips
  Domain/
    Entities/     plain model structs
    Constraints/  StepConstraintEngine (pure, unit-tested) ★ constraint design
  Data/
    Local/        LocalStore protocol, SwiftDataStore (+ @Model types), CatalogSeed,
                  EvidenceStore (photos on disk)
    Remote/       APIClient (LabLogAPI), DTOs, AuthService (Supabase GoTrue), Keychain
    Sync/         SyncEngine (outbox) + Reachability (NWPathMonitor)
  Hardware/       CameraPicker, LocationService
  LiveActivity/   StepTimerCoordinator (starts/ends the timer activity, "ready" notification)
  Assets.xcassets AppIcon (original artwork), AccentColor
Shared/           compiled into app + widget: StepTimerAttributes, CompleteTimedStepIntent,
                  Discipline palette, deep links
LabLogWidgets/    widget extension: Dynamic Island + Lock Screen Live Activity
Config/           LabLog.xcconfig, Secrets.example.xcconfig, Info.plist, LabLogWidgets-Info.plist
LabLogTests/      constraint engine, SwiftDataStore, SyncEngine, Live Activity/guide tests (36)
LabLogUITests/    end-to-end flows + screenshots, incl. Dynamic Island (2)
docs/             decision-records.md, failure-log.md, screenshots/
```

## Building & running

Open `LabLog.xcodeproj` (scheme **LabLog**). The `LabLog/` and `LabLogTests/` folders are
file-system-synchronized, so new `.swift` files are picked up automatically. Camera and
location usage strings are set in the target's build settings (see ADR-007).

```sh
# unit tests (simulator)
xcodebuild test -project LabLog.xcodeproj -scheme LabLog \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'

# build + install on a connected iPhone
xcodebuild build -project LabLog.xcodeproj -scheme LabLog \
  -destination 'platform=iOS,id=<UDID>' -allowProvisioningUpdates
xcrun devicectl device install app --device <UDID> \
  <DerivedData>/Build/Products/Debug-iphoneos/LabLog.app
```

Signing uses a free Personal Team, so the profile expires after 7 days. Re-run from
Xcode before a demo.

Without `Config/Secrets.xcconfig` the app runs in on-device mode with the bundled
catalog. To sync, copy `Config/Secrets.example.xcconfig` to `Config/Secrets.xcconfig`
and set the backend URL (your Mac's LAN IP + `/api`), the Supabase URL and the anon key.

UI-test screenshots: run the `LabLogUITests` with `-resultBundlePath`, then
`xcrun xcresulttool export attachments --path <bundle> --output-path <dir>`.

## Key pieces to defend in the viva

- **`StepConstraintEngine`** — precedence DAG + photo/timer guards, all in one pure type.
- **`ExperimentChecklist`** — custom component with documented properties & events.
- **`SyncEngine`** — offline outbox, idempotent upserts, signed-URL photo upload.

Backend: see the `lablog-backend` repo.
