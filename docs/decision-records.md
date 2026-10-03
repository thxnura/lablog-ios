# Decision Records (ADRs)

> One short entry per real design decision. Format: **Context → Decision → Consequences.**
> Add an entry each coding session — examiners can tell when these are backfilled.
> This file feeds the "Outline major decisions taken" grading line.

---

## ADR-001 — Native iOS (Swift/SwiftUI) over cross-platform
**Context.** Brief allows RN/Flutter/native. Target is a single platform for the viva.
**Decision.** Native iOS with SwiftUI; local persistence via SwiftData.
**Consequences.** First-class camera/location APIs and offline storage; no cross-platform reach (acceptable for a single-device demo).

## ADR-002 — Custom Express API in front of Supabase (not direct BaaS)
**Context.** Brief rewards a "custom backend". Supabase alone would be BaaS.
**Decision.** Express + TypeScript service layer; app talks to Express, Express talks to Supabase with the service-role key.
**Consequences.** Real validation/auth/business-rule layer to defend in viva; one extra hop to run and deploy.

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

<!-- ADR-00N — <title>
**Context.** …
**Decision.** …
**Consequences.** …
-->
