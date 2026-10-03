import SwiftUI
import PhotosUI

/// Camera capture for step evidence. Presents the system camera and returns the
/// saved local file URL (stored offline, uploaded later by the SyncEngine).
///
/// Requires `NSCameraUsageDescription` in Info.plist.
struct CameraPicker: UIViewControllerRepresentable {
    var onCaptured: (URL) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onCaptured: onCaptured) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onCaptured: (URL) -> Void
        init(onCaptured: @escaping (URL) -> Void) { self.onCaptured = onCaptured }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            defer { picker.dismiss(animated: true) }
            guard let image = info[.originalImage] as? UIImage,
                  let data = image.jpegData(compressionQuality: 0.8) else { return }
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).appendingPathExtension("jpg")
            try? data.write(to: url)
            onCaptured(url)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}
