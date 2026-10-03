import Foundation

/// Thin REST client over the Express backend. Attaches the Supabase JWT.
struct APIClient {
    let baseURL: URL
    var tokenProvider: () async -> String?

    enum APIError: Error { case badStatus(Int), noToken }

    private func request(_ path: String, method: String = "GET", body: Data? = nil) async throws -> Data {
        guard let token = await tokenProvider() else { throw APIError.noToken }
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError.badStatus((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        return data
    }

    private var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    private var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }

    // MARK: Catalog

    func labs() async throws -> [Lab] {
        try decoder.decode([Lab].self, from: try await request("labs"))
    }

    func experiments(labId: UUID) async throws -> [Experiment] {
        try decoder.decode([Experiment].self, from: try await request("labs/\(labId)/experiments"))
    }

    // MARK: Sync

    func sync(_ payload: SyncRequestDTO) async throws -> SyncResponseDTO {
        let body = try encoder.encode(payload)
        return try decoder.decode(SyncResponseDTO.self, from: try await request("sync", method: "POST", body: body))
    }

    func signUpload(recordId: UUID, attachmentId: UUID) async throws -> SignUploadDTO {
        let body = try encoder.encode(["recordId": recordId.uuidString, "attachmentId": attachmentId.uuidString])
        return try decoder.decode(SignUploadDTO.self, from: try await request("attachments/sign", method: "POST", body: body))
    }
}
