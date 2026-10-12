import SwiftUI
import UIKit

/// Camera capture for step evidence. Presents the system camera (or the photo
/// library where there is no camera, e.g. the Simulator) and hands back the
/// image; the caller saves it via `EvidenceStore` so it survives offline.
///
/// Requires `NSCameraUsageDescription` in Info.plist.
struct CameraPicker: UIViewControllerRepresentable {
    var onCaptured: (UIImage) -> Void
    var onCancel: () -> Void = {}

    static var isCameraAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = Self.isCameraAvailable ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onCaptured: onCaptured, onCancel: onCancel) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onCaptured: (UIImage) -> Void
        let onCancel: () -> Void

        init(onCaptured: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) {
            self.onCaptured = onCaptured
            self.onCancel = onCancel
        }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                onCaptured(image)
            } else {
                onCancel()
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCancel()
        }
    }
}

#if DEBUG
/// UI-test seam: with the `-UITestStubCamera` launch argument the app skips the
/// system camera (which UI tests can't drive) and uses a generated image.
enum CameraStub {
    static var isEnabled: Bool { ProcessInfo.processInfo.arguments.contains("-UITestStubCamera") }

    static func image() -> UIImage {
        let size = CGSize(width: 800, height: 600)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor.systemTeal.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            let text = "Test evidence" as NSString
            text.draw(at: CGPoint(x: 60, y: 260),
                      withAttributes: [.font: UIFont.boldSystemFont(ofSize: 64), .foregroundColor: UIColor.white])
        }
    }
}
#endif
