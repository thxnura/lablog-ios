import SwiftUI

/// Lecturer home: pick an experiment to review its submissions. Shown only to
/// lecturers (role from the JWT); the API enforces the same rule (403).
struct ReviewView: View {
    @Environment(AppModel.self) private var app
    @State private var groups: [(lab: Lab, experiments: [Experiment])] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                HStack(spacing: Theme.Space.m) {
                    Image(systemName: "checkmark.rectangle.stack.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .frame(width: 52, height: 52)
                        .background(Color.accentColor.gradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Lecturer").eyebrow()
                        Text(app.auth.session?.email ?? "")
                            .font(.headline)
                        Text("Submitted records sync here from students' phones.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .card()
                .padding(.top, Theme.Space.s)

                ForEach(groups, id: \.lab.id) { group in
                    VStack(alignment: .leading, spacing: Theme.Space.m) {
                        SectionHeader(title: group.lab.name, trailing: group.lab.code)
                        ForEach(group.experiments) { experiment in
                            NavigationLink(value: experiment) {
                                HStack(spacing: Theme.Space.m) {
                                    DisciplineIcon(discipline: .of(labCode: group.lab.code), size: 40)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(experiment.title)
                                            .font(.headline)
                                            .foregroundStyle(.primary)
                                        Text("View submissions")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.footnote.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                }
                                .card()
                            }
                            .buttonStyle(.pressableCard)
                            .accessibilityIdentifier("review-\(experiment.title)")
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.Space.l)
            .padding(.bottom, Theme.Space.xl)
        }
        .background(Theme.canvas)
        .navigationTitle("Review")
        .navigationDestination(for: Experiment.self) { experiment in
            SubmissionsView(experiment: experiment,
                            lab: groups.first { $0.lab.id == experiment.labId }?.lab)
        }
        .toolbar { ConnectivityToolbarItem() }
        .task(id: app.store.version) {
            groups = app.store.labs().map { lab in (lab, app.store.experiments(labId: lab.id)) }
        }
    }
}

/// One experiment's submissions, newest first, fetched live from the API.
struct SubmissionsView: View {
    let experiment: Experiment
    let lab: Lab?

    @Environment(AppModel.self) private var app
    @State private var state: LoadState = .loading

    enum LoadState {
        case loading
        case loaded([SubmissionDTO])
        case failed(String)
    }

    private var steps: [Step] { app.store.steps(experimentId: experiment.id) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                switch state {
                case .loading:
                    ProgressView("Loading submissions…")
                        .frame(maxWidth: .infinity)
                        .padding(.top, Theme.Space.xxl)
                case .failed(let message):
                    ContentUnavailableView("Couldn't load submissions", systemImage: "wifi.exclamationmark",
                                           description: Text(message))
                        .padding(.top, Theme.Space.xxl)
                case .loaded(let submissions) where submissions.isEmpty:
                    ContentUnavailableView("No submissions yet", systemImage: "tray",
                                           description: Text("Records appear here once students submit and their phones sync."))
                        .padding(.top, Theme.Space.xxl)
                case .loaded(let submissions):
                    SectionHeader(title: "Submissions", trailing: "\(submissions.count)")
                    ForEach(submissions) { submission in
                        NavigationLink(value: submission) {
                            SubmissionCard(submission: submission, totalSteps: steps.count)
                        }
                        .buttonStyle(.pressableCard)
                        .accessibilityIdentifier("submission-\(submission.studentEmail ?? submission.id.uuidString)")
                    }
                }
            }
            .padding(.horizontal, Theme.Space.l)
            .padding(.bottom, Theme.Space.xl)
        }
        .background(Theme.canvas)
        .navigationTitle(experiment.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: SubmissionDTO.self) { submission in
            SubmissionDetailView(submission: submission, experiment: experiment, lab: lab, steps: steps)
        }
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        guard let api = app.api else {
            state = .failed("This build has no server configured.")
            return
        }
        guard app.reachability.isOnline else {
            state = .failed("Reviewing needs a connection. Submissions live on the server.")
            return
        }
        do {
            state = .loaded(try await api.submissions(experimentId: experiment.id))
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

private struct SubmissionCard: View {
    let submission: SubmissionDTO
    let totalSteps: Int

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            Text(initials)
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(Color.accentColor.gradient, in: Circle())
            VStack(alignment: .leading, spacing: 5) {
                Text(submission.studentEmail ?? "Student")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text((submission.submittedAt ?? submission.createdAt)
                        .formatted(.dateTime.day().month().hour().minute()))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    MetaChip(symbol: "checklist", text: "\(submission.stepCompletions.count)/\(totalSteps) steps",
                             tint: submission.stepCompletions.count >= totalSteps ? Theme.success : Theme.caution)
                    MetaChip(symbol: "camera.fill", text: "\(submission.attachments.count)")
                    if submission.latitude != nil {
                        MetaChip(symbol: "location.fill", text: "Located", tint: .accentColor)
                    }
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .card()
        .accessibilityElement(children: .combine)
    }

    private var initials: String {
        let name = (submission.studentEmail ?? "S").split(separator: "@").first.map(String.init) ?? "S"
        return String(name.prefix(2)).uppercased()
    }
}
