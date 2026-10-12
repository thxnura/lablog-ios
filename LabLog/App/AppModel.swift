import Foundation
import Observation
import SwiftData

/// Composition root: builds every service once and wires them together.
/// Injected into the view tree with `.environment(app)`.
@MainActor
@Observable
final class AppModel {
    let config: AppConfig
    let store: LocalStore
    let auth: AuthService
    let reachability: Reachability
    let sync: SyncEngine
    let location: LocationService
    let container: ModelContainer

    init(config: AppConfig = .fromBundle(), inMemory: Bool = false) {
        let container: ModelContainer
        do {
            container = try SwiftDataStore.makeContainer(inMemory: inMemory)
        } catch {
            fatalError("Could not open the local database: \(error)")
        }
        let store = SwiftDataStore(container: container)
        let auth = AuthService(config: config)
        let reachability = Reachability()

        let api: LabLogAPI? = config.apiBaseURL.map { baseURL in
            APIClient(baseURL: baseURL, tokenProvider: { await auth.validAccessToken() })
        }

        self.config = config
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
    }

    /// Called once at launch.
    func start() {
        reachability.onBecameOnline = { [weak self] in
            Task { await self?.refreshAndSync() }
        }
        reachability.start()
        Task { await refreshAndSync() }
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
