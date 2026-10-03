import SwiftUI

@main
struct LabLogApp: App {
    @State private var reachability = Reachability()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(reachability)
                .onAppear { reachability.start() }
        }
    }
}

/// Placeholder root. Replace with the real navigation (Lab list → Experiment →
/// Record capture) once the Xcode project and SwiftDataStore are wired up.
struct RootView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "LabLog",
                systemImage: "flask",
                description: Text("Scaffold ready. Wire LabListView → ExperimentDetailView → RecordCaptureView."),
            )
            .navigationTitle("LabLog")
        }
    }
}
