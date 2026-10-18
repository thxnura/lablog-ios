import UIKit

/// Photo evidence on disk. Photos are written here the moment they are taken
/// (offline-first) and uploaded later by the SyncEngine. Files live in
/// Application Support, not tmp, so the OS never purges unsynced evidence.
enum EvidenceStore {
    enum EvidenceError: LocalizedError {
        case encodingFailed
        case missingFile(String)

        var errorDescription: String? {
            switch self {
            case .encodingFailed: "Could not encode the photo as JPEG."
            case .missingFile(let name): "Photo \(name) is missing from the device."
            }
        }
    }

    /// Longest edge kept for evidence photos — readable, and small enough to sync on lab Wi-Fi.
    static let maxPixelSize: CGFloat = 1600

    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Evidence", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Downscales, JPEG-encodes and saves the photo. Returns the file name to store.
    static func save(_ image: UIImage, id: UUID) throws -> String {
        guard let data = downscaled(image).jpegData(compressionQuality: 0.7) else {
            throw EvidenceError.encodingFailed
        }
        let fileName = "\(id.uuidString).jpg"
        try data.write(to: directory.appendingPathComponent(fileName), options: .atomic)
        return fileName
    }

    /// Saves a photo downloaded from the server (already a JPEG).
    static func save(data: Data, id: UUID) throws -> String {
        let fileName = "\(id.uuidString).jpg"
        try data.write(to: directory.appendingPathComponent(fileName), options: .atomic)
        return fileName
    }

    static func data(for fileName: String) throws -> Data {
        let url = directory.appendingPathComponent(fileName)
        guard let data = FileManager.default.contents(atPath: url.path) else {
            throw EvidenceError.missingFile(fileName)
        }
        return data
    }

    /// Deletes a photo file (a retake, a removed photo or a discarded draft).
    static func delete(_ fileName: String) {
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(fileName))
    }

    static func image(for fileName: String) -> UIImage? {
        UIImage(contentsOfFile: directory.appendingPathComponent(fileName).path)
    }

    private static func downscaled(_ image: UIImage) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxPixelSize else { return image }
        let scale = maxPixelSize / longest
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
