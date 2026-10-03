# LabLog — iOS

**Digital Practical Lab Book** — offline-first iOS app (SE5070 Enterprise Mobility, Edtech).
Students work through a precedence-constrained experiment checklist, attach photo evidence,
and submit location-stamped lab records that sync to the backend when back online.

## Source layout

```
LabLog/
  App/            app entry + DI
  Features/       screens (LabList, ExperimentDetail, RecordCapture, SyncStatus)
  Components/
    ExperimentChecklist/   ★ custom component (precedence-constrained checklist)
  Domain/
    Entities/     plain model structs
    Constraints/  StepConstraintEngine (pure, unit-tested) ★ constraint design
  Data/
    Local/        LocalStore protocol (back with SwiftData)
    Remote/       APIClient + wire DTOs
    Sync/         SyncEngine (outbox) + Reachability (NWPathMonitor)
  Hardware/       CameraService, LocationService
LabLogTests/      StepConstraintEngineTests
docs/             decision-records.md, failure-log.md, screenshots/
```

## Getting it into Xcode

These are **source files**; the binary `.xcodeproj` is created in Xcode:

1. Xcode → New Project → iOS App → name **LabLog**, interface **SwiftUI**, storage **SwiftData**.
2. Delete the template `ContentView`/`App` file and **add the `LabLog/` folder** (Add Files → Create groups).
3. Add a **unit test target** and include `LabLogTests/`.
4. Info.plist keys:
   - `NSCameraUsageDescription` — "Photograph your experiment setup and results."
   - `NSLocationWhenInUseUsageDescription` — "Stamp your lab record with your location."
5. Add a `Secrets.xcconfig` (git-ignored) with your Supabase URL + anon key for Auth.
6. Implement `SwiftDataStore: LocalStore` (@Model classes mirroring `Domain/Entities`).

## Key pieces to defend in the viva

- **`StepConstraintEngine`** — precedence DAG + photo/timer guards, all in one pure type.
- **`ExperimentChecklist`** — custom component with documented properties & events.
- **`SyncEngine`** — offline outbox, idempotent upserts, signed-URL photo upload.

Backend: see the `lablog-backend` repo.
