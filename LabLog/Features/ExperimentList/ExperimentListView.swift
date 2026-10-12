import SwiftUI

/// Experiments in one lab, each with what it demands and your progress on it.
struct ExperimentListView: View {
    let lab: Lab

    @Environment(AppModel.self) private var app
    @State private var rows: [Row] = []

    private var discipline: Discipline { .of(labCode: lab.code) }

    struct Row: Identifiable {
        let experiment: Experiment
        let steps: [Step]
        let progress: Progress
        var id: UUID { experiment.id }
    }

    enum Progress {
        case notStarted
        case inProgress(done: Int)
        case submitted
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                header

                SectionHeader(title: "Experiments", trailing: "\(rows.count)")
                ForEach(rows) { row in
                    NavigationLink(value: row.experiment) {
                        ExperimentCard(row: row, tint: discipline.tint)
                    }
                    .buttonStyle(.pressableCard)
                    .accessibilityIdentifier("experiment-\(row.experiment.title)")
                }
                if rows.isEmpty {
                    ContentUnavailableView("No experiments", systemImage: "testtube.2")
                }
            }
            .padding(.horizontal, Theme.Space.l)
            .padding(.bottom, Theme.Space.xl)
        }
        .background(Theme.canvas)
        .navigationTitle(lab.code)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: Experiment.self) { experiment in
            ExperimentDetailView(experiment: experiment, lab: lab)
        }
        .toolbar { ConnectivityToolbarItem() }
        .task(id: app.store.version) { load() }
    }

    private var header: some View {
        HStack(spacing: Theme.Space.l) {
            DisciplineIcon(discipline: discipline, size: 64)
            VStack(alignment: .leading, spacing: 4) {
                Text(lab.code).eyebrow()
                Text(lab.name)
                    .font(.title2.weight(.bold))
            }
        }
        .padding(.top, Theme.Space.s)
    }

    private func load() {
        rows = app.store.experiments(labId: lab.id).map { experiment in
            let records = app.store.records(experimentId: experiment.id)
            let progress: Progress
            if let draft = records.first(where: { $0.status == .draft }) {
                progress = .inProgress(done: app.store.completions(recordId: draft.id).count)
            } else if records.contains(where: { $0.status == .submitted }) {
                progress = .submitted
            } else {
                progress = .notStarted
            }
            return Row(experiment: experiment, steps: app.store.steps(experimentId: experiment.id), progress: progress)
        }
    }
}

private struct ExperimentCard: View {
    let row: ExperimentListView.Row
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.m) {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Text(row.experiment.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                if let description = row.experiment.description {
                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                ExperimentMetaChips(steps: row.steps)
                    .padding(.top, 2)
            }
            Spacer(minLength: 0)
            progressBadge
        }
        .card()
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var progressBadge: some View {
        switch row.progress {
        case .notStarted:
            Text("New")
                .font(.caption.weight(.bold))
                .foregroundStyle(tint)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(tint.opacity(0.14), in: Capsule())
        case .inProgress(let done):
            ZStack {
                ProgressRing(progress: Double(done) / Double(max(row.steps.count, 1)), lineWidth: 4, tint: Theme.caution)
                Text("\(done)/\(row.steps.count)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }
            .frame(width: 42, height: 42)
        case .submitted:
            Image(systemName: "checkmark.seal.fill")
                .font(.title2)
                .foregroundStyle(Theme.success)
        }
    }
}

/// "5 steps · 1 photo · 5 min wait" — what an experiment will ask of you.
struct ExperimentMetaChips: View {
    let steps: [Step]

    var body: some View {
        let photos = steps.filter(\.requiresPhoto).count
        let wait = steps.compactMap(\.minDurationSeconds).reduce(0, +)
        HStack(spacing: 6) {
            MetaChip(symbol: "list.number", text: "\(steps.count) steps")
            if photos > 0 {
                MetaChip(symbol: "camera.fill", text: "\(photos) photo\(photos == 1 ? "" : "s")")
            }
            if wait > 0 {
                MetaChip(symbol: "timer", text: Duration.seconds(wait).formatted(.units(allowed: [.minutes, .seconds], width: .abbreviated)))
            }
        }
    }
}
