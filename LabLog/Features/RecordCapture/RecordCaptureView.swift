import MapKit
import SwiftUI

/// The core capture screen: the ExperimentChecklist custom component + camera
/// evidence + observation + submit. Also the read-only view of a submitted record.
struct RecordCaptureView: View {
    let recordId: UUID

    @Environment(AppModel.self) private var app
    @State private var model: RecordCaptureModel?

    var body: some View {
        Group {
            if let model {
                RecordCaptureContent(model: model)
            } else {
                ProgressView()
            }
        }
        // One task creates and loads the model. With two, the reload could run
        // before the model existed and the screen stayed empty (failure 019).
        .task(id: app.store.version) {
            if model == nil { model = RecordCaptureModel(recordId: recordId, app: app) }
            model?.load()
        }
    }
}

private struct RecordCaptureContent: View {
    @Bindable var model: RecordCaptureModel

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var cameraStep: Step?
    @State private var confirmDiscard = false
    @State private var isLeaving = false
    @State private var toast: String?
    @State private var toastTask: Task<Void, Never>?
    @State private var confirmSubmit = false
    @State private var thumbnails: [UUID: UIImage] = [:]
    @State private var guide: GuideTarget?
    @FocusState private var observationFocused: Bool

    private static let observationLimit = 5000 // backend zod max

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                header

                ExperimentChecklist(
                    steps: model.steps,
                    completions: $model.completions,
                    recordId: model.recordId,
                    startedAt: model.record?.createdAt,
                    photoStepIds: model.photoStepIds,
                    photoThumbnails: thumbnails,
                    isEditable: model.isEditable,
                    onStepCompleted: { _, completion in model.persist(completion) },
                    onPhotoRequested: { step in requestPhoto(for: step) },
                    onLockedStepTapped: { _, reason in show(reason) },
                    onStepSelected: { step in guide = GuideTarget(id: step.id) },
                )

                if !model.attachments.isEmpty {
                    evidence
                }

                observation

                if !model.isEditable, let record = model.record {
                    SubmissionReceipt(record: record)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(.horizontal, Theme.Space.l)
            .padding(.bottom, Theme.Space.l)
        }
        .background(Theme.canvas)
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(model.isEditable ? "Lab record" : "Submitted record")
        .navigationBarTitleDisplayMode(.inline)
        // Focus mode: the tab bar steps aside while you're mid-experiment.
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ConnectivityToolbarItem()
            if model.isEditable {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Discard draft", systemImage: "trash", role: .destructive) {
                            confirmDiscard = true
                        }
                        .accessibilityIdentifier("discard-draft")
                    } label: {
                        Label("More", systemImage: "ellipsis")
                    }
                    .accessibilityIdentifier("record-menu")
                }
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { observationFocused = false }
            }
        }
        .bottomActionBar {
            if model.isEditable {
                submitBar
            }
        }
        .sheet(item: $cameraStep) { step in
            CameraPicker(
                onCaptured: { image in
                    cameraStep = nil
                    model.attachPhoto(image, to: step)
                },
                onCancel: { cameraStep = nil },
            )
            .ignoresSafeArea()
        }
        .overlay(alignment: .top) {
            if let toast {
                Label(toast, systemImage: "lock.fill")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, Theme.Space.l)
                    .padding(.vertical, Theme.Space.m)
                    .background(.regularMaterial, in: Capsule())
                    .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
                    .padding(.top, Theme.Space.s)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .accessibilityIdentifier("toast")
            }
        }
        .animation(Theme.spring, value: toast)
        .animation(Theme.spring, value: model.isEditable)
        .alert("Couldn't save photo", isPresented: .constant(model.errorMessage != nil)) {
            Button("OK") { model.clearError() }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .sheet(isPresented: $confirmSubmit) {
            SubmitReviewSheet(model: model)
        }
        // Signed out from the Sync tab while this record was open: it's gone.
        .onChange(of: model.isGone) { _, gone in
            guard gone, !isLeaving else { return }
            isLeaving = true
            dismiss()
        }
        .alert("Discard this draft?", isPresented: $confirmDiscard) {
            Button("Discard", role: .destructive) {
                isLeaving = true
                model.discard()
                dismiss()
            }
            .accessibilityIdentifier("confirm-discard")
            Button("Keep working", role: .cancel) {}
        } message: {
            Text("Its completed steps, photos, notes and observation will be deleted from this iPhone\(app.config.isBackendConfigured ? " and the server" : ""). This can't be undone.")
        }
        .sensoryFeedback(.success, trigger: model.isEditable) { wasEditable, isEditable in
            wasEditable && !isEditable
        }
        .sheet(item: $guide) { target in
            StepGuideSheet(model: model, stepId: target.id)
        }
        .onChange(of: model.attachments) { loadThumbnails() }
        .onAppear {
            app.visibleRecordId = model.recordId
            loadThumbnails()
            openPendingDeepLink()
        }
        .onChange(of: app.pendingDeepLink) { openPendingDeepLink() }
        .onDisappear {
            if app.visibleRecordId == model.recordId { app.visibleRecordId = nil }
            model.saveObservationNow()
        }
    }

    // MARK: Header

    private var discipline: Discipline {
        .of(labCode: app.store.labs().first { $0.id == model.experiment?.labId }?.code ?? "")
    }

    private var progress: Double {
        Double(model.completedCount) / Double(max(model.steps.count, 1))
    }

    private var isComplete: Bool { model.completedCount == model.steps.count && !model.steps.isEmpty }

    private var nextStepText: String {
        if isComplete { return model.isEditable ? "All steps done — ready to submit" : "All steps completed" }
        let done = Set(model.completions.map(\.stepId))
        let context = StepConstraintEngine.Context(completedStepIds: done, attachedPhotoStepIds: model.photoStepIds,
                                                   completionTimes: [:], now: Date())
        guard let next = StepConstraintEngine().reachableSteps(model.steps, context: context).first else { return "" }
        return "Next: Step \(next.order) · \(next.title)"
    }

    private var header: some View {
        HStack(alignment: .center, spacing: Theme.Space.l) {
            ZStack {
                ProgressRing(progress: progress, lineWidth: 7, tint: isComplete ? Theme.success : discipline.tint)
                VStack(spacing: -2) {
                    Text("\(model.completedCount)")
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .contentTransition(.numericText(value: Double(model.completedCount)))
                    Text("of \(model.steps.count)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .monospacedDigit()
            }
            .frame(width: 72, height: 72)

            VStack(alignment: .leading, spacing: 6) {
                Text(model.experiment?.title ?? "")
                    .font(.title3.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(nextStepText)
                    .font(.subheadline)
                    .foregroundStyle(isComplete ? Theme.success : .secondary)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    if let record = model.record {
                        RecordStatusBadge(status: record.status)
                        SyncStateBadge(state: record.syncState)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .card()
        // Combine the card into one VoiceOver element *before* adding the timer
        // pill, so the pill stays its own button (failure 005).
        .accessibilityElement(children: .combine)
        .overlay(alignment: .bottom) {
            if let timed = model.timedStep {
                LiveTimerPill(timed: timed) { guide = GuideTarget(id: timed.step.id) }
                    // Hang below the card, overlapping only its bottom padding.
                    .offset(y: 30)
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
        }
        .padding(.bottom, model.timedStep == nil ? 0 : 34)
        .animation(Theme.spring, value: model.timedStep?.step.id)
        .padding(.top, Theme.Space.s)
        .animation(Theme.spring, value: model.completedCount)
    }

    // MARK: Evidence

    private var evidence: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            SectionHeader(title: "Evidence", trailing: "\(model.attachments.count) photo\(model.attachments.count == 1 ? "" : "s")")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Space.m) {
                    ForEach(model.attachments) { attachment in
                        // Tap a photo to open its step (retake or remove it there).
                        Button {
                            if let stepId = attachment.stepId { guide = GuideTarget(id: stepId) }
                        } label: {
                            EvidenceTile(attachment: attachment,
                                         image: thumbnails[attachment.stepId ?? attachment.id],
                                         stepOrder: model.steps.first { $0.id == attachment.stepId }?.order)
                        }
                        .buttonStyle(.pressableCard)
                    }
                }
            }
            .scrollClipDisabled()
        }
    }

    // MARK: Observation

    private var observation: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            SectionHeader(title: "Observations")
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                if model.isEditable {
                    TextField("Masses, readings, colour changes, anything unexpected…",
                              text: $model.observationText, axis: .vertical)
                        .lineLimit(4...12)
                        .focused($observationFocused)
                        .onChange(of: model.observationText) {
                            if model.observationText.count > Self.observationLimit {
                                model.observationText = String(model.observationText.prefix(Self.observationLimit))
                            }
                            model.observationChanged()
                        }
                        .accessibilityIdentifier("observation")
                    HStack {
                        Label("Saved on this device", systemImage: "internaldrive")
                        Spacer()
                        Text("\(model.observationText.count)/\(Self.observationLimit)")
                            .monospacedDigit()
                    }
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                } else {
                    Text(model.observationText.isEmpty ? "No observation recorded." : model.observationText)
                        .foregroundStyle(model.observationText.isEmpty ? .secondary : .primary)
                }
            }
            .card()
        }
    }

    // MARK: Submit

    private var submitBar: some View {
        VStack(spacing: Theme.Space.s) {
            if !model.canSubmit && !model.isSubmitting {
                let left = model.steps.count - model.completedCount
                Text("\(left) step\(left == 1 ? "" : "s") left · progress is saved on this device")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            Button {
                confirmSubmit = true
            } label: {
                PrimaryButtonLabel(title: model.isSubmitting ? "Stamping location…" : "Submit lab record",
                                   symbol: "paperplane.fill",
                                   isLoading: model.isSubmitting)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .tint(Theme.success)
            .disabled(!model.canSubmit)
            .accessibilityIdentifier("submit-record")
        }
        .animation(Theme.spring, value: model.canSubmit)
    }

    // MARK: Actions

    private func requestPhoto(for step: Step) {
        #if DEBUG
        if CameraStub.isEnabled {
            model.attachPhoto(CameraStub.image(), to: step)
            return
        }
        #endif
        cameraStep = step
    }

    /// A Live Activity / notification asked to open a step of this record.
    private func openPendingDeepLink() {
        guard let link = app.pendingDeepLink, link.recordId == model.recordId else { return }
        app.pendingDeepLink = nil
        if let stepId = link.stepId {
            guide = GuideTarget(id: stepId)
        }
    }

    private func show(_ message: String) {
        toast = message
        toastTask?.cancel()
        toastTask = Task {
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            toast = nil
        }
    }

    /// Thumbnails keyed by step (falls back to attachment id for step-less photos).
    private func loadThumbnails() {
        var result: [UUID: UIImage] = [:]
        for attachment in model.attachments {
            guard let name = attachment.localPath,
                  let image = EvidenceStore.image(for: name)?.preparingThumbnail(of: CGSize(width: 240, height: 240))
            else { continue }
            result[attachment.stepId ?? attachment.id] = image
        }
        thumbnails = result
    }
}

private struct EvidenceTile: View {
    let attachment: Attachment
    let image: UIImage?
    let stepOrder: Int?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Image(systemName: "photo")
                        .font(.title)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Theme.inset)
                }
            }
            .frame(width: 132, height: 132)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous))

            if let stepOrder {
                Text("Step \(stepOrder)")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(8)
            }
        }
        .overlay(alignment: .topTrailing) {
            Image(systemName: attachment.syncState == .synced ? "checkmark.icloud.fill" : "icloud.and.arrow.up.fill")
                .font(.caption)
                .foregroundStyle(attachment.syncState == .synced ? Theme.success : .primary)
                .padding(6)
                .background(.ultraThinMaterial, in: Circle())
                .padding(8)
        }
        .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Evidence photo\(stepOrder.map { " for step \($0)" } ?? "")")
    }
}

/// The "receipt" for a submitted record: when, where (map), and sync state.
private struct SubmissionReceipt: View {
    let record: LabRecord

    private var coordinate: CLLocationCoordinate2D? {
        guard let lat = record.latitude, let lon = record.longitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            SectionHeader(title: "Submission")
            VStack(alignment: .leading, spacing: 0) {
                if let coordinate {
                    Map(initialPosition: .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 600, longitudinalMeters: 600)),
                        interactionModes: []) {
                        Marker("Lab record", systemImage: "flask.fill", coordinate: coordinate)
                            .tint(Theme.success)
                    }
                    .frame(height: 150)
                    .allowsHitTesting(false)
                }
                VStack(spacing: Theme.Space.m) {
                    InfoRow(symbol: "checkmark.seal.fill", title: "Submitted", tint: Theme.success) {
                        Text((record.submittedAt ?? record.createdAt).formatted(date: .abbreviated, time: .shortened))
                    }
                    InfoRow(symbol: "location.fill", title: "Location", tint: .accentColor) {
                        if let lat = record.latitude, let lon = record.longitude {
                            Text(String(format: "%.4f, %.4f", lat, lon)).monospacedDigit()
                        } else {
                            Text("Not available")
                        }
                    }
                    InfoRow(symbol: "icloud.fill", title: "Server", tint: record.syncState == .failed ? Theme.danger : .accentColor) {
                        SyncStateBadge(state: record.syncState)
                    }
                    if let error = record.lastSyncError, record.syncState == .failed {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(Theme.danger)
                    }
                }
                .padding(Theme.Space.l)
            }
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        }
    }
}

/// Floating pill under the header while a timed step is waiting: live
/// countdown + ring; tap to open that step's guide (the full timer dial).
private struct LiveTimerPill: View {
    let timed: StepTimerCoordinator.TimedStep
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let remaining = max(0, Int(ceil(timed.end.timeIntervalSince(context.date))))
                let total = max(timed.end.timeIntervalSince(timed.start), 1)
                let ready = remaining == 0
                HStack(spacing: 8) {
                    ZStack {
                        ProgressRing(progress: ready ? 1 : 1 - Double(remaining) / total, lineWidth: 3,
                                     tint: ready ? Theme.success : Theme.caution)
                        Image(systemName: ready ? "checkmark" : "hourglass")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(ready ? Theme.success : Theme.caution)
                    }
                    .frame(width: 22, height: 22)
                    Text("Step \(timed.step.order)")
                        .foregroundStyle(.secondary)
                    Text(ready ? "Ready" : StepGuideSheet.format(remaining))
                        .monospacedDigit()
                        .contentTransition(.numericText(countsDown: true))
                        .foregroundStyle(ready ? Theme.success : .primary)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.tertiary)
                }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder((ready ? Theme.success : Theme.caution).opacity(0.5), lineWidth: 1))
                .shadow(color: .black.opacity(0.1), radius: 10, y: 4)
                .animation(.snappy, value: remaining)
            }
        }
        .buttonStyle(.pressableCard)
        .accessibilityLabel("Step \(timed.step.order) timer")
        .accessibilityHint("Opens the step guide")
        .accessibilityIdentifier("timer-pill")
    }
}
