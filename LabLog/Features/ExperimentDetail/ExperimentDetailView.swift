import SwiftUI

/// Briefing before starting: what the experiment is, the procedure with its
/// constraints spelled out, and a sticky call to action.
struct ExperimentDetailView: View {
    let experiment: Experiment
    let lab: Lab

    @Environment(AppModel.self) private var app
    @State private var steps: [Step] = []
    @State private var records: [LabRecord] = []
    @State private var draftDone = 0
    @State private var openRecordId: UUID?

    private var discipline: Discipline { .of(labCode: lab.code) }
    private var draft: LabRecord? { records.first { $0.status == .draft } }
    private var submitted: [LabRecord] { records.filter { $0.status == .submitted } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                hero

                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    SectionHeader(title: "Procedure")
                    VStack(spacing: 0) {
                        ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                            ProcedureRow(step: step, steps: steps, tint: discipline.tint, isLast: index == steps.count - 1)
                        }
                    }
                    .card()
                    Text("Steps unlock in order. Some need a photo or a waiting time before they can be marked done.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if !submitted.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.Space.m) {
                        SectionHeader(title: "Your submissions", trailing: "\(submitted.count)")
                        VStack(spacing: 0) {
                            ForEach(submitted) { record in
                                Button { openRecordId = record.id } label: {
                                    HStack {
                                        Image(systemName: "checkmark.seal.fill")
                                            .foregroundStyle(Theme.success)
                                        Text(record.submittedAt ?? record.createdAt, format: .dateTime.day().month().hour().minute())
                                            .foregroundStyle(.primary)
                                        Spacer()
                                        SyncStateBadge(state: record.syncState)
                                        Image(systemName: "chevron.right")
                                            .font(.footnote.weight(.semibold))
                                            .foregroundStyle(.tertiary)
                                    }
                                    .font(.subheadline)
                                    .padding(.vertical, Theme.Space.s)
                                }
                                if record.id != submitted.last?.id { Divider() }
                            }
                        }
                        .card(padding: Theme.Space.m)
                    }
                }
            }
            .padding(.horizontal, Theme.Space.l)
            .padding(.bottom, Theme.Space.l)
        }
        .background(Theme.canvas)
        .navigationTitle(experiment.title)
        .navigationBarTitleDisplayMode(.inline)
        .bottomActionBar {
            Button(action: startOrContinue) {
                PrimaryButtonLabel(title: draft == nil ? "Start lab record" : "Continue draft · \(draftDone) of \(steps.count)",
                                   symbol: draft == nil ? "plus" : "arrow.right")
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .tint(discipline.tint)
            .accessibilityIdentifier("start-record")
        }
        .navigationDestination(item: $openRecordId) { recordId in
            RecordCaptureView(recordId: recordId)
        }
        .toolbar { ConnectivityToolbarItem() }
        .task(id: app.store.version) {
            steps = app.store.steps(experimentId: experiment.id)
            records = app.store.records(experimentId: experiment.id)
            draftDone = draft.map { app.store.completions(recordId: $0.id).count } ?? 0
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack(spacing: Theme.Space.m) {
                DisciplineIcon(discipline: discipline, size: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(lab.code) · \(lab.name)").eyebrow()
                    Text(experiment.title)
                        .font(.title2.weight(.bold))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let description = experiment.description {
                Text(description)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ExperimentMetaChips(steps: steps)
        }
        .padding(.top, Theme.Space.s)
    }

    private func startOrContinue() {
        if let draft {
            openRecordId = draft.id
        } else {
            let record = app.store.createRecord(experimentId: experiment.id)
            app.didChangeLocally()
            openRecordId = record.id
        }
    }
}

/// One step of the procedure on a numbered rail, with its guards as chips.
private struct ProcedureRow: View {
    let step: Step
    let steps: [Step]
    let tint: Color
    let isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.m) {
            VStack(spacing: 0) {
                Text("\(step.order)")
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(tint)
                    .frame(width: 28, height: 28)
                    .background(tint.opacity(0.14), in: Circle())
                if !isLast {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.2))
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(step.title)
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    if !step.prerequisiteStepIds.isEmpty {
                        MetaChip(symbol: "arrow.turn.down.right", text: "After \(prerequisiteNames)")
                    }
                    if step.requiresPhoto {
                        MetaChip(symbol: "camera.fill", text: "Photo", tint: Theme.caution)
                    }
                    if let seconds = step.minDurationSeconds {
                        MetaChip(symbol: "timer",
                                 text: Duration.seconds(seconds).formatted(.units(allowed: [.minutes, .seconds], width: .abbreviated)),
                                 tint: Theme.caution)
                    }
                }
            }
            .padding(.top, 4)
            .padding(.bottom, isLast ? 0 : Theme.Space.l)
            Spacer(minLength: 0)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }

    private var prerequisiteNames: String {
        step.prerequisiteStepIds
            .compactMap { id in steps.first { $0.id == id }?.order }
            .sorted()
            .map { "Step \($0)" }
            .joined(separator: " & ")
    }
}
