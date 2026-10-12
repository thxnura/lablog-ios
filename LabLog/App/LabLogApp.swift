import SwiftUI

@main
struct LabLogApp: App {
    @State private var app = AppModel(inMemory: ProcessInfo.processInfo.arguments.contains("-UITestInMemoryStore"))

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .task { app.start() }
        }
    }
}
