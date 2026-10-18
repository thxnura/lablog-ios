import SwiftUI

/// Lecturer tab: the labs, with what's in each and who can do it (ADR-029).
/// Lecturers don't do practicals, so this replaces the student's Labs tab.
struct ManageLabsView: View {
    @Environment(AppModel.self) private var app
    @State private var labs: [ManagedLabDTO] = []
    @State private var state: LoadState = .loading
    @State private var showNewLab = false

    enum LoadState: Equatable { case loading, loaded, failed(String) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                switch state {
                case .loading where labs.isEmpty:
                    ProgressView().frame(maxWidth: .infinity).padding(.top, Theme.Space.xxl)
                case .failed(let message) where labs.isEmpty:
                    ContentUnavailableView("Couldn't load labs", systemImage: "exclamationmark.icloud",
                                           description: Text(message))
                default:
                    ForEach(labs) { lab in
                        NavigationLink(value: lab) { LabRow(lab: lab) }
                            .buttonStyle(.pressableCard)
                            .accessibilityIdentifier("manage-\(lab.code)")
                    }
                }
            }
            .padding(.horizontal, Theme.Space.l)
            .padding(.vertical, Theme.Space.s)
        }
        .background(Theme.canvas)
        .navigationTitle("Labs")
        .navigationDestination(for: ManagedLabDTO.self) { lab in
            ManageLabView(lab: lab, onChange: { await load(refreshCatalog: false) })
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showNewLab = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("New lab")
                    .accessibilityIdentifier("new-lab")
            }
        }
        .sheet(isPresented: $showNewLab) {
            NewLabSheet { created in
                // Shown at once from the server's answer; nothing else to fetch.
                labs.append(ManagedLabDTO(id: created.id, name: created.name, code: created.code,
                                          isOpenToAll: false, experimentCount: 0, studentIds: []))
                labs.sort { $0.name.localizedCompare($1.name) == .orderedAscending }
            }
        }
        .refreshable { await load() }
        .task { await load() }
    }

    private func load(refreshCatalog: Bool = true) async {
        guard let manage = app.manage else { return state = .failed("No server in this build.") }
        do {
            labs = try await manage.managedLabs()
            state = .loaded
            // Brings in other lecturers' changes; never holds up the list.
            if refreshCatalog { Task { await app.sync.refreshCatalog() } }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

private struct LabRow: View {
    let lab: ManagedLabDTO

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            DisciplineIcon(discipline: .of(labCode: lab.code), size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(lab.code).eyebrow().foregroundStyle(.secondary)
                Text(lab.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(details)
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

    private var details: String {
        let experiments = "\(lab.experimentCount) experiment\(lab.experimentCount == 1 ? "" : "s")"
        let who = lab.isOpenToAll ? "all students"
            : "\(lab.studentIds.count) student\(lab.studentIds.count == 1 ? "" : "s")"
        return "\(experiments) · \(who)"
    }
}

/// One lab: its experiments, and the students who can do it.
struct ManageLabView: View {
    let lab: ManagedLabDTO
    let onChange: () async -> Void

    @Environment(AppModel.self) private var app
    @State private var experiments: [Experiment] = []
    @State private var students: [StudentDTO] = []
    @State private var enrolled: Set<UUID>
    @State private var showNewExperiment = false
    @State private var editingExperiment: Experiment?
    @State private var showStudents = false
    @State private var error: String?

    init(lab: ManagedLabDTO, onChange: @escaping () async -> Void) {
        self.lab = lab
        self.onChange = onChange
        _enrolled = State(initialValue: Set(lab.studentIds))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    SectionHeader(title: "Experiments", trailing: "\(experiments.count)")
                    VStack(spacing: Theme.Space.m) {
                        ForEach(experiments) { experiment in
                            Button {
                                editingExperiment = experiment
                            } label: {
                                ExperimentRow(experiment: experiment, steps: app.store.steps(experimentId: experiment.id))
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("edit-\(experiment.title)")
                            Divider().padding(.leading, 52)
                        }
                        Button {
                            showNewExperiment = true
                        } label: {
                            Label("Add Experiment", systemImage: "plus.circle.fill")
                                .fontWeight(.medium)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .accessibilityIdentifier("add-experiment")
                    }
                    .card()
                }

                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    SectionHeader(title: "Students", trailing: lab.isOpenToAll ? nil : "\(enrolled.count)")
                    VStack(alignment: .leading, spacing: Theme.Space.m) {
                        if lab.isOpenToAll {
                            Text("A course lab: every student can do it.")
                                .foregroundStyle(.secondary)
                        } else {
                            if enrolled.isEmpty {
                                Text("No students yet. Only the students you choose see this lab.")
                                    .foregroundStyle(.secondary)
                            }
                            ForEach(students.filter { enrolled.contains($0.id) }) { student in
                                InfoRow(symbol: "person.fill", title: student.email, tint: .secondary) { EmptyView() }
                            }
                            Button {
                                showStudents = true
                            } label: {
                                Label("Choose students", systemImage: "person.badge.plus")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .accessibilityIdentifier("choose-students")
                        }
                    }
                    .font(.subheadline)
                    .card()
                    if let error {
                        Text(error).font(.footnote).foregroundStyle(Theme.danger)
                    }
                }
            }
            .padding(.horizontal, Theme.Space.l)
            .padding(.bottom, Theme.Space.xl)
        }
        .background(Theme.canvas)
        .navigationTitle(lab.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showNewExperiment) {
            ExperimentEditorSheet(lab: lab) { Task { await onChange() } }
        }
        .sheet(item: $editingExperiment) { experiment in
            ExperimentEditorSheet(lab: lab, existing: experiment,
                                  steps: app.store.steps(experimentId: experiment.id)) { Task { await onChange() } }
        }
        .sheet(isPresented: $showStudents) {
            StudentPickerSheet(students: students, selected: enrolled) { chosen in
                // Optimistic: show the choice now, send it, and undo it if the server refuses.
                let previous = enrolled
                enrolled = chosen
                error = nil
                Task {
                    do {
                        try await app.manage?.setStudents(labId: lab.id, studentIds: Array(chosen))
                        await onChange()
                    } catch {
                        enrolled = previous
                        self.error = "Couldn't save the students: \(error.localizedDescription)"
                    }
                }
            }
        }
        .task(id: app.store.version) {
            experiments = app.store.experiments(labId: lab.id)
        }
        .task {
            guard !lab.isOpenToAll else { return }
            do { students = try await app.manage?.students() ?? [] } catch { self.error = error.localizedDescription }
        }
    }
}

/// An experiment in a lab: its title, and what its steps ask for at a glance.
/// Tap to edit.
private struct ExperimentRow: View {
    let experiment: Experiment
    let steps: [Step]

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            Image(systemName: "flask.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 40, height: 40)
                .background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(experiment.title)
                    .font(.headline)
                HStack(spacing: Theme.Space.m) {
                    Label("\(steps.count) step\(steps.count == 1 ? "" : "s")", systemImage: "list.number")
                    let photos = steps.filter(\.requiresPhoto).count
                    if photos > 0 { Label("\(photos)", systemImage: "camera.fill") }
                    let timers = steps.filter { $0.minDurationSeconds != nil }.count
                    if timers > 0 { Label("\(timers)", systemImage: "timer") }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
            }
            Spacer()
            Text("Edit")
                .font(.subheadline)
                .foregroundStyle(Color.accentColor)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Edit the experiment and its steps")
    }
}
