import Foundation

/// Outbox-based sync. Records are written locally first (source of truth while
/// offline); the engine flushes pending records to the backend on reconnect.
///
/// Flow: upload pending photos (signed URL) → POST /sync → mark each record
/// synced/failed from the response. Client UUIDs make retries idempotent.
@Observable
final class SyncEngine {
    enum Status: Equatable { case idle, syncing, failed(String) }

    private(set) var status: Status = .idle
    private(set) var pendingCount = 0

    private let api: APIClient
    private let store: LocalStore

    init(api: APIClient, store: LocalStore) {
        self.api = api
        self.store = store
    }

    func refreshPendingCount() {
        pendingCount = store.pendingRecords().count
    }

    /// Flush the outbox. Safe to call repeatedly; no-op when nothing pending.
    func sync() async {
        let pending = store.pendingRecords()
        guard !pending.isEmpty else { status = .idle; return }
        status = .syncing

        do {
            // 1. Upload any pending photos first, recording their storage paths.
            for record in pending {
                for attachment in store.pendingAttachments(recordId: record.id) {
                    let signed = try await api.signUpload(recordId: record.id, attachmentId: attachment.id)
                    try await uploadPhoto(attachment: attachment, to: signed)
                    store.markAttachmentSynced(attachment.id, storagePath: signed.storagePath)
                }
            }

            // 2. Push the records in one idempotent batch.
            let payload = SyncRequestDTO(records: pending.map(store.makeDTO))
            let response = try await api.sync(payload)

            // 3. Reconcile per-item results.
            for result in response.results {
                store.applySyncResult(id: result.id, synced: result.status == "synced")
            }
            refreshPendingCount()
            status = .idle
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    private func uploadPhoto(attachment: Attachment, to signed: SignUploadDTO) async throws {
        guard let localPath = attachment.localPath,
              let data = FileManager.default.contents(atPath: localPath),
              let url = URL(string: signed.signedUrl) else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "PUT"
        req.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        req.httpBody = data
        _ = try await URLSession.shared.data(for: req)
    }
}
