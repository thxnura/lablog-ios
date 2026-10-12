import Foundation

/// Everything the app needs from the backend. A protocol so the SyncEngine can
/// be unit-tested against a fake, with no network.
protocol LabLogAPI {
    func labs() async throws -> [Lab]
    func experiments(labId: UUID) async throws -> [Experiment]
    func experimentDetail(id: UUID) async throws -> ExperimentDetailDTO
    func sync(_ payload: SyncRequestDTO) async throws -> SyncResponseDTO
    func signUpload(recordId: UUID, attachmentId: UUID) async throws -> SignUploadDTO
    func uploadPhoto(_ data: Data, to signed: SignUploadDTO) async throws
}

enum APIError: LocalizedError, Equatable {
    case notSignedIn
    case badStatus(Int, String?)
    case invalidURL

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            "Sign in to sync with the server."
        case .badStatus(let code, let message):
            "Server returned \(code)\(message.map { ": \($0)" } ?? "")"
        case .invalidURL:
            "The upload URL from the server was invalid."
        }
    }
}

/// Thin REST client over the Express backend (`<base>/api/...`). Attaches the
/// Supabase JWT from `tokenProvider` to every request.
struct APIClient: LabLogAPI {
    let baseURL: URL
    var tokenProvider: () async -> String?
    var session: URLSession = .shared

    private func request(_ path: String, method: String = "GET", body: Data? = nil) async throws -> Data {
        guard let token = await tokenProvider() else { throw APIError.notSignedIn }
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = method
        req.timeoutInterval = 20
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body

        let (data, response) = try await session.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200..<300).contains(status) else {
            let message = try? JSONDecoder().decode(APIErrorBody.self, from: data).error
            throw APIError.badStatus(status, message)
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
        try decoder.decode([Experiment].self, from: try await request("labs/\(labId.uuidString.lowercased())/experiments"))
    }

    func experimentDetail(id: UUID) async throws -> ExperimentDetailDTO {
        try decoder.decode(ExperimentDetailDTO.self, from: try await request("experiments/\(id.uuidString.lowercased())"))
    }

    // MARK: Sync

    func sync(_ payload: SyncRequestDTO) async throws -> SyncResponseDTO {
        let body = try encoder.encode(payload)
        return try decoder.decode(SyncResponseDTO.self, from: try await request("sync", method: "POST", body: body))
    }

    func signUpload(recordId: UUID, attachmentId: UUID) async throws -> SignUploadDTO {
        let body = try encoder.encode([
            "recordId": recordId.uuidString.lowercased(),
            "attachmentId": attachmentId.uuidString.lowercased(),
            "contentType": "image/jpeg",
        ])
        return try decoder.decode(SignUploadDTO.self, from: try await request("attachments/sign", method: "POST", body: body))
    }

    /// PUTs the JPEG straight to Supabase Storage via the signed URL — the
    /// photo never passes through (or bloats) the Express API.
    func uploadPhoto(_ data: Data, to signed: SignUploadDTO) async throws {
        guard let url = URL(string: signed.signedUrl) else { throw APIError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "PUT"
        req.timeoutInterval = 60
        req.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        let (body, response) = try await session.upload(for: req, from: data)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200..<300).contains(status) else {
            throw APIError.badStatus(status, String(data: body, encoding: .utf8))
        }
    }
}
