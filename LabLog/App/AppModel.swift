import Foundation
import Observation
import SwiftData
import UserNotifications

/// Composition root: builds every service once and wires them together.
/// Injected into the view tree with `.environment(app)`.
@MainActor
@Observable
final class AppModel {
    /// Where the backend is; the Sync tab can change the host at runtime.
    let endpoint: ServerEndpoint
    var config: AppConfig { endpoint.config }
    /// The host currently in use (observable, for the Sync tab).
    private(set) var serverHost: String?
    let store: LocalStore
    let auth: AuthService
    let reachability: Reachability
    let sync: SyncEngine
    let location: LocationService
    let container: ModelContainer
    /// nil when the build has no backend configured.
    let api: LabLogAPI?
    let timers = StepTimerCoordinator()

    /// Set by a Live Activity / notification tap; RootView navigates to the
    /// record and the capture screen opens the step's guide, then clears it.
    var pendingDeepLink: LabLogDeepLink?
    /// The record whose capture screen is on screen (deep links to it just open the guide).
    @ObservationIgnored var visibleRecordId: UUID?

    @ObservationIgnored private let notificationRouter = NotificationRouter()

    init(config: AppConfig = .fromBundle(), inMemory: Bool = false) {
        let container: ModelContainer
        do {
            container = try SwiftDataStore.makeContainer(inMemory: inMemory)
        } catch {
            fatalError("Could not open the local database: \(error)")
        }
        let store = SwiftDataStore(container: container)
        // A host chosen in the Sync tab outlives relaunches. UI tests start
        // clean but can pass `-LabLogServerHost 127.0.0.1` (the simulator always
        // reaches the Mac there), so they don't depend on its Wi-Fi address (failure 015).
        let launchHost = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)[Self.serverHostKey] as? String
        let savedHost = launchHost ?? (inMemory ? nil : UserDefaults.standard.string(forKey: Self.serverHostKey))
        let endpoint = ServerEndpoint(built: config, host: config.isBackendConfigured ? savedHost : nil)
        let auth = AuthService(endpoint: endpoint)
        let reachability = Reachability()

        let api: LabLogAPI? = config.apiBaseURL.map { _ in
            APIClient(endpoint: endpoint, tokenProvider: { await auth.validAccessToken() })
        }

        self.endpoint = endpoint
        self.serverHost = endpoint.config.apiBaseURL?.host()
        self.api = api
        self.container = container
        self.store = store
        self.auth = auth
        self.reachability = reachability
        self.location = LocationService()
        self.sync = SyncEngine(
            api: api,
            store: store,
            isOnline: { reachability.isOnline },
            isSignedIn: { auth.isSignedIn },
        )

        CatalogSeed.installIfNeeded(into: store)
        // An empty in-memory store has no records, so nothing from an earlier run applies.
        if inMemory { StepTimerCoordinator.clearAll() }

        UNUserNotificationCenter.current().delegate = notificationRouter
        notificationRouter.onOpenURL = { [weak self] url in self?.open(url) }
        // Live Activity "Mark done" buttons run in this process (LiveActivityIntent).
        LiveActivityBridge.completeStep = { [weak self] recordId, stepId in
            self?.completeStep(recordId: recordId, stepId: stepId) ?? false
        }
    }

    /// Called once at launch.
    func start() {
        reachability.onBecameOnline = { [weak self] in
            Task { await self?.refreshAndSync() }
        }
        reachability.start()
        Task { await refreshAndSync() }
        // Re-check activities left over from a previous run (step done, record submitted…).
        for recordId in Set(activeTimerRecordIds()) {
            refreshTimers(recordId: recordId)
        }
    }

    /// `lablog://record/<id>?step=<id>` from the Dynamic Island or a notification.
    func open(_ url: URL) {
        guard let link = LabLogDeepLink(url: url), store.record(id: link.recordId) != nil else { return }
        pendingDeepLink = link
    }

    /// The one place a step is completed outside the checklist (step guide,
    /// Live Activity button). The constraint engine has the final say.
    @discardableResult
    func completeStep(recordId: UUID, stepId: UUID) -> Bool {
        guard let record = store.record(id: recordId), record.status == .draft else { return false }
        let steps = store.steps(experimentId: record.experimentId)
        guard let step = steps.first(where: { $0.id == stepId }) else { return false }
        let completions = store.completions(recordId: recordId)
        if completions.contains(where: { $0.stepId == stepId }) { return true }

        let context = StepConstraintEngine.Context(
            completedStepIds: Set(completions.map(\.stepId)),
            attachedPhotoStepIds: Set(store.attachments(recordId: recordId).compactMap(\.stepId)),
            completionTimes: Dictionary(completions.map { ($0.stepId, $0.completedAt) }, uniquingKeysWith: { a, _ in a }),
            now: Date(),
        )
        guard StepConstraintEngine().isUnlocked(step, context: context) else { return false }

        store.addCompletion(StepCompletion(id: UUID(), recordId: recordId, stepId: stepId, completedAt: Date()))
        timers.stepCompleted(recordId: recordId, stepId: stepId)
        didChangeLocally()
        refreshTimers(recordId: recordId)
        return true
    }

    /// Start/stop the Dynamic Island timer to match this record's checklist.
    func refreshTimers(recordId: UUID) {
        guard let record = store.record(id: recordId),
              let experiment = store.experiment(id: record.experimentId) else { return }
        let lab = store.labs().first { $0.id == experiment.labId }
        timers.refresh(record: record, experiment: experiment, lab: lab,
                       steps: store.steps(experimentId: record.experimentId),
                       completions: store.completions(recordId: recordId))
    }

    private func activeTimerRecordIds() -> [UUID] {
        StepTimerCoordinator.activeRecordIds()
    }

    static let serverHostKey = "LabLogServerHost"

    /// Point the app at the backend on another host (nil → the build's own).
    /// Same backend, same session; only the address changes.
    func setServerHost(_ host: String?) {
        let trimmed = host?.trimmingCharacters(in: .whitespaces)
        let custom = (trimmed?.isEmpty ?? true) || trimmed == endpoint.defaultConfig.apiBaseURL?.host() ? nil : trimmed
        endpoint.setHost(custom)
        if let custom {
            UserDefaults.standard.set(custom, forKey: Self.serverHostKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.serverHostKey)
        }
        serverHost = endpoint.config.apiBaseURL?.host()
        Task { await refreshAndSync() }
    }

    /// Throw away a draft: its timer stops and, if the server may already
    /// have it, a tombstone syncs the delete.
    func discardDraft(recordId: UUID) {
        guard store.record(id: recordId)?.status == .draft else { return }
        timers.endAll(recordId: recordId)
        store.discardDraft(id: recordId, sendTombstone: config.isBackendConfigured)
        didChangeLocally()
    }

    /// Pull the latest catalog, then push the outbox.
    func refreshAndSync() async {
        await sync.refreshCatalog()
        await sync.sync()
    }

    /// Something was written locally: update the badge and try to push it.
    func didChangeLocally() {
        sync.refreshPendingCount()
        Task { await sync.sync() }
    }
}
