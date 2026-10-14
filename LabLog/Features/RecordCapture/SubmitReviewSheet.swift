import SwiftUI

/// "Review & submit": a summary of exactly what will be handed in, one clear
/// primary action, and a success state. Replaces the system confirmation
/// dialog, which rendered as a popover pointing at an unrelated step card.
struct SubmitReviewSheet: View {
    @Bindable var model: RecordCaptureModel

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: Phase = .review

    enum Phase { case review, submitting, done }

    var body: some View {
        VStack(spacing: Theme.Space.xl) {
            if phase == .done {
                success
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
            } else {
                review
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, Theme.Space.xl)
        .padding(.top, Theme.Space.xxl)
        .padding(.bottom, Theme.Space.l)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.canvas)
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .bouncy(duration: 0.45), value: phase)
        .sensoryFeedback(.success, trigger: phase == .done)
        .presentationDetents([.large])
        .presentationDragIndicator(phase == .review ? .visible : .hidden)
        .interactiveDismissDisabled(phase == .submitting)
    }

    // MARK: Review

    private var review: some View {
        VStack(spacing: Theme.Space.xl) {
            VStack(spacing: Theme.Space.m) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 68, height: 68)
                    .background(LinearGradient(colors: [Theme.success, Theme.success.opacity(0.75)],
                                               startPoint: .topLeading, endPoint: .bottomTrailing),
                                in: Circle())
                    .shadow(color: Theme.success.opacity(0.35), radius: 14, y: 6)
                Text("Ready to submit")
                    .font(.title2.weight(.bold))
                Text(model.experiment?.title ?? "")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: Theme.Space.m) {
                InfoRow(symbol: "checklist", title: "Steps", tint: Theme.success) {
                    Text("\(model.completedCount) of \(model.steps.count) complete")
                }
                Divider()
                InfoRow(symbol: "camera.fill", title: "Evidence", tint: .accentColor) {
                    Text(model.attachments.isEmpty ? "No photos" : "\(model.attachments.count) photo\(model.attachments.count == 1 ? "" : "s")")
                }
                Divider()
                InfoRow(symbol: "text.alignleft", title: "Observation",
                        tint: model.observationText.isEmpty ? Theme.caution : .accentColor) {
                    Text(model.observationText.isEmpty ? "None added" : "\(model.observationText.count) characters")
                }
                Divider()
                InfoRow(symbol: "location.fill", title: "Location", tint: .accentColor) {
                    Text("Stamped now")
                }
            }
            .card()

            if model.observationText.isEmpty {
                Label("You haven't written an observation. Lecturers usually expect one.", systemImage: "exclamationmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(Theme.caution)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer(minLength: 0)

            VStack(spacing: Theme.Space.m) {
                Label("Submitted records are final and can't be edited.", systemImage: "lock.fill")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button {
                    Task { await submit() }
                } label: {
                    PrimaryButtonLabel(title: phase == .submitting ? "Stamping location…" : "Submit lab record",
                                       symbol: "paperplane.fill",
                                       isLoading: phase == .submitting)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .tint(Theme.success)
                .disabled(phase != .review)
                .accessibilityIdentifier("confirm-submit")

                Button("Keep editing") { dismiss() }
                    .font(.subheadline.weight(.semibold))
                    .disabled(phase != .review)
                    .accessibilityIdentifier("cancel-submit")
            }
        }
    }

    // MARK: Success

    private var success: some View {
        VStack(spacing: Theme.Space.l) {
            Spacer(minLength: Theme.Space.xxl)
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 76))
                .foregroundStyle(Theme.success)
                .symbolEffect(.bounce, value: phase == .done)
            Text("Submitted")
                .font(.largeTitle.weight(.bold))
            Text(model.record?.syncState == .synced
                 ? "Your lecturer can see it now."
                 : "Saved on this iPhone. It will upload automatically when you're online.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let lat = model.record?.latitude, let lon = model.record?.longitude {
                Label(String(format: "%.4f, %.4f", lat, lon), systemImage: "location.fill")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("submit-success")
    }

    private func submit() async {
        phase = .submitting
        await model.submit()
        phase = .done
        try? await Task.sleep(for: .seconds(1.6))
        dismiss()
    }
}
