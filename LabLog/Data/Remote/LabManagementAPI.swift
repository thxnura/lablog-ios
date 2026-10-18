import Foundation

/// Lecturer-only endpoints under `/api/manage` (ADR-029): create labs and
/// experiments, and choose which students can do each lab.
protocol LabManagementAPI {
    func managedLabs() async throws -> [ManagedLabDTO]
    func createLab(code: String, name: String) async throws -> CreatedLabDTO
    /// Returns the experiment as the catalog has it (server step ids), so the
    /// app adds it locally at once instead of refetching the whole catalog.
    func createExperiment(labId: UUID, _ experiment: NewExperimentDTO) async throws -> ExperimentDetailDTO
    /// Edits an experiment in place; steps sent with their id keep it.
    func updateExperiment(id: UUID, _ experiment: NewExperimentDTO) async throws -> ExperimentDetailDTO
    func students() async throws -> [StudentDTO]
    func setStudents(labId: UUID, studentIds: [UUID]) async throws
}

/// `GET /api/manage/labs` — a lab as a lecturer manages it.
struct ManagedLabDTO: Decodable, Identifiable, Hashable {
    let id: UUID
    let name: String
    let code: String
    /// A seeded course lab: every student can do it, so there's no enrolment.
    let isOpenToAll: Bool
    let experimentCount: Int
    let studentIds: [UUID]
}

struct CreatedLabDTO: Decodable {
    let id: UUID
    let name: String
    let code: String
}

struct StudentDTO: Decodable, Identifiable, Hashable {
    let id: UUID
    let email: String
}

/// `POST /api/manage/labs/:labId/experiments`. Steps are numbered by position;
/// `prerequisites` lists the numbers of the steps that must be done first.
struct NewExperimentDTO: Encodable, Equatable {
    struct NewStep: Encodable, Equatable {
        /// An existing step's id when editing (keeps students' work on it); nil for a new step.
        var id: UUID? = nil
        let title: String
        let instruction: String?
        let requiresPhoto: Bool
        let minDurationSeconds: Int?
        let prerequisites: [Int]
    }

    let title: String
    let description: String?
    let steps: [NewStep]
}

extension APIClient: LabManagementAPI {
    private struct NewLab: Encodable { let code: String; let name: String }
    private struct Enrolment: Encodable { let studentIds: [String] }

    func managedLabs() async throws -> [ManagedLabDTO] {
        try JSONDecoder().decode([ManagedLabDTO].self, from: try await request("manage/labs"))
    }

    func createLab(code: String, name: String) async throws -> CreatedLabDTO {
        let body = try JSONEncoder().encode(NewLab(code: code, name: name))
        return try JSONDecoder().decode(CreatedLabDTO.self, from: try await request("manage/labs", method: "POST", body: body))
    }

    func createExperiment(labId: UUID, _ experiment: NewExperimentDTO) async throws -> ExperimentDetailDTO {
        let body = try JSONEncoder().encode(experiment)
        let path = "manage/labs/\(labId.uuidString.lowercased())/experiments"
        return try JSONDecoder().decode(ExperimentDetailDTO.self, from: try await request(path, method: "POST", body: body))
    }

    func updateExperiment(id: UUID, _ experiment: NewExperimentDTO) async throws -> ExperimentDetailDTO {
        let body = try JSONEncoder().encode(experiment)
        let path = "manage/experiments/\(id.uuidString.lowercased())"
        return try JSONDecoder().decode(ExperimentDetailDTO.self, from: try await request(path, method: "PUT", body: body))
    }

    func students() async throws -> [StudentDTO] {
        try JSONDecoder().decode([StudentDTO].self, from: try await request("manage/students"))
    }

    func setStudents(labId: UUID, studentIds: [UUID]) async throws {
        let body = try JSONEncoder().encode(Enrolment(studentIds: studentIds.map { $0.uuidString.lowercased() }))
        _ = try await request("manage/labs/\(labId.uuidString.lowercased())/students", method: "PUT", body: body)
    }
}
