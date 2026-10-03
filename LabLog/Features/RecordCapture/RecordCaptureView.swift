import SwiftUI

/// The core capture screen: the ExperimentChecklist custom component + camera
/// evidence + observation + submit. Uses in-memory state here for the scaffold;
/// swap to the ViewModel + LocalStore once wired.
struct RecordCaptureView: View {
    let experiment: Experiment
    let steps: [Step]

    @State private var completions: [StepCompletion] = []
    @State private var photoStepIds: Set<UUID> = []
    @State private var observation: String = ""
    @State private var cameraStep: Step?
    @State private var toast: String?

    private let recordId = UUID()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ExperimentChecklist(
                    steps: steps,
                    completions: $completions,
                    photoStepIds: photoStepIds,
                    onStepCompleted: { _ in toast = nil },
                    onPhotoRequested: { step in cameraStep = step },
                    onLockedStepTapped: { _, reason in toast = reason },
                )

                VStack(alignment: .leading, spacing: 8) {
                    Text("Observation").font(.headline)
                    TextEditor(text: $observation)
                        .frame(minHeight: 100)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
                }

                Button {
                    // submit → write record (status submitted), stamp location, queue sync
                } label: {
                    Text("Submit Lab Record").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(completions.count < steps.count)
            }
            .padding()
        }
        .navigationTitle(experiment.title)
        .sheet(item: $cameraStep) { step in
            CameraPicker { _ in
                photoStepIds.insert(step.id)
                cameraStep = nil
            }
        }
        .overlay(alignment: .bottom) {
            if let toast {
                Text(toast)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 24)
            }
        }
    }
}
