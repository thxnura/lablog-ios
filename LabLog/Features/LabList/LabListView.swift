import SwiftUI

/// Navigation value for opening a lab record from any stack.
struct RecordRoute: Hashable {
    let id: UUID
}

/// Home: what to continue, how you're doing, and the cached lab catalog.
/// Works fully offline from the first launch.
struct LabListView: View {
    @Environment(AppModel.self) private var app
    @State private var labs: [LabSummary] = []
    @State private var resume: ResumeItem?
    @State private var stats = Stats()

    struct LabSummary: Identifiable {
        let lab: Lab
        let experimentCount: Int
        let submittedCount: Int
        var id: UUID { lab.id }
    }

    struct ResumeItem {
        let record: LabRecord
        let experiment: Experiment
        let lab: Lab?
        let done: Int
        let total: Int
        let nextStep: Step?
    }

    struct Stats {
        var drafts = 0
        var submitted = 0
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                Text(Date.now, format: .dateTime.weekday(.wide).day().month(.wide))
                    .eyebrow()
                    .padding(.top, -Theme.Space.m)

                if let resume {
                    NavigationLink(value: RecordRoute(id: resume.record.id)) {
                        ResumeCard(item: resume)
                    }
                    .buttonStyle(.pressableCard)
                    .accessibilityIdentifier("resume-card")
                }

                HStack(spacing: Theme.Space.m) {
                    StatTile(value: stats.drafts, label: "In progress", symbol: "square.and.pencil", tint: Theme.caution)
                    StatTile(value: stats.submitted, label: "Submitted", symbol: "checkmark.seal.fill", tint: Theme.success)
                    StatTile(value: app.sync.pendingCount, label: "To sync", symbol: "arrow.clockwise.icloud.fill", tint: .accentColor)
                }

                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    SectionHeader(title: "Your labs", trailing: "\(labs.count)")
                    ForEach(labs) { summary in
                        NavigationLink(value: summary.lab) {
                            LabCard(summary: summary)
                        }
                        .buttonStyle(.pressableCard)
                        .accessibilityIdentifier("lab-\(summary.lab.code)")
                    }
                    if labs.isEmpty {
                        ContentUnavailableView("No labs yet", systemImage: "flask",
                                               description: Text("Pull to refresh once you're online."))
                    }
                }

                Label(catalogFootnote, systemImage: "internaldrive")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, Theme.Space.l)
            .padding(.bottom, Theme.Space.xl)
        }
        .background(Theme.canvas)
        .navigationTitle("Labs")
        .navigationDestination(for: Lab.self) { lab in
            ExperimentListView(lab: lab)
        }
        .navigationDestination(for: RecordRoute.self) { route in
            RecordCaptureView(recordId: route.id)
        }
        .toolbar { ConnectivityToolbarItem() }
        .refreshable { await app.refreshAndSync() }
        .task(id: app.store.version) { load() }
        .animation(Theme.spring, value: resume?.record.id)
    }

    private var catalogFootnote: String {
        if let refreshed = app.sync.catalogRefreshedAt {
            return "Catalog updated \(refreshed.formatted(.relative(presentation: .named)))."
        }
        return "Labs are stored on this device and open without a connection."
    }

    private func load() {
        let store = app.store
        let allLabs = store.labs()
        let records = store.records()
        labs = allLabs.map { lab in
            let experiments = store.experiments(labId: lab.id)
            let ids = Set(experiments.map(\.id))
            return LabSummary(lab: lab,
                              experimentCount: experiments.count,
                              submittedCount: records.filter { ids.contains($0.experimentId) && $0.status == .submitted }.count)
        }
        stats = Stats(drafts: records.filter { $0.status == .draft }.count,
                      submitted: records.filter { $0.status == .submitted }.count)

        // Most recent draft → "Continue" card.
        if let draft = records.first(where: { $0.status == .draft }),
           let experiment = store.experiment(id: draft.experimentId) {
            let steps = store.steps(experimentId: experiment.id)
            let completions = store.completions(recordId: draft.id)
            let done = Set(completions.map(\.stepId))
            let context = StepConstraintEngine.Context(completedStepIds: done, attachedPhotoStepIds: [],
                                                       completionTimes: [:], now: Date())
            resume = ResumeItem(record: draft, experiment: experiment,
                                lab: allLabs.first { $0.id == experiment.labId },
                                done: done.count, total: steps.count,
                                nextStep: StepConstraintEngine().reachableSteps(steps, context: context).first)
        } else {
            resume = nil
        }
    }
}

// MARK: - Cards

private struct ResumeCard: View {
    let item: LabListView.ResumeItem

    private var discipline: Discipline { .of(labCode: item.lab?.code ?? "") }
    private var progress: Double { item.total == 0 ? 0 : Double(item.done) / Double(item.total) }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack {
                Label("Continue", systemImage: "play.fill")
                    .font(.caption.weight(.bold))
                    .textCase(.uppercase)
                    .tracking(0.6)
                Spacer()
                Text("\(item.done) of \(item.total) steps")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
            }
            .foregroundStyle(.white.opacity(0.85))

            Text(item.experiment.title)
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.leading)

            if let next = item.nextStep {
                Text("Next: Step \(next.order) · \(next.title)")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
            } else {
                Text("All steps done — ready to submit")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.9))
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.25))
                    Capsule().fill(.white).frame(width: max(8, geo.size.width * progress))
                }
            }
            .frame(height: 6)
        }
        .padding(Theme.Space.l + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack(alignment: .topTrailing) {
                discipline.gradient
                Image(systemName: discipline.symbol)
                    .font(.system(size: 120, weight: .bold))
                    .foregroundStyle(.white.opacity(0.12))
                    .rotationEffect(.degrees(-12))
                    .offset(x: 24, y: -18)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .shadow(color: discipline.tint.opacity(0.35), radius: 16, y: 8)
        .accessibilityElement(children: .combine)
    }
}

private struct LabCard: View {
    let summary: LabListView.LabSummary

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            DisciplineIcon(discipline: .of(labCode: summary.lab.code), size: 52)
            VStack(alignment: .leading, spacing: 3) {
                Text(summary.lab.code)
                    .eyebrow()
                Text(summary.lab.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .card()
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        let experiments = "\(summary.experimentCount) experiment\(summary.experimentCount == 1 ? "" : "s")"
        return summary.submittedCount > 0 ? "\(experiments) · \(summary.submittedCount) submitted" : experiments
    }
}
