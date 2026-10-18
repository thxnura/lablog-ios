import SwiftUI

/// Create a lab: a code and a name. Plain system form, like Settings.
/// One request; the sheet closes as soon as it answers and the list updates
/// from the answer, without reloading anything.
struct NewLabSheet: View {
    let onCreated: (CreatedLabDTO) -> Void

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var name = ""
    @State private var isSaving = false
    @State private var error: String?

    private var canSave: Bool { code.trimmingCharacters(in: .whitespaces).count >= 2 && name.trimmingCharacters(in: .whitespaces).count >= 2 }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Code, e.g. CHEM301", text: $code)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("lab-code")
                    TextField("Name, e.g. Analytical Chemistry Lab", text: $name)
                        .accessibilityIdentifier("lab-name")
                } footer: {
                    Text(error ?? "After creating it, add experiments and choose the students who can do it.")
                        .foregroundStyle(error == nil ? Color.secondary : Theme.danger)
                }
            }
            .navigationTitle("New Lab")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Create") { Task { await save() } }
                            .disabled(!canSave)
                            .accessibilityIdentifier("create-lab")
                    }
                }
            }
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            guard let lab = try await app.manage?.createLab(code: code.trimmingCharacters(in: .whitespaces),
                                                             name: name.trimmingCharacters(in: .whitespaces)) else { return }
            app.store.replaceCatalog(labs: [Lab(id: lab.id, name: lab.name, code: lab.code)], experiments: [], steps: [])
            onCreated(lab)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Create or edit an experiment with its steps and their rules: a photo, a
/// wait, and which earlier steps must be done first (ADR-029). The server
/// answers with the experiment as the catalog has it, which goes straight into
/// the local store: no catalog refetch before the sheet closes. Editing keeps
/// each step's id, so students' work on it stays attached.
struct ExperimentEditorSheet: View {
    let lab: ManagedLabDTO
    /// nil: a new experiment.
    let existing: Experiment?
    let onSaved: () -> Void

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var draft: ExperimentDraft
    @State private var editing: EditTarget?
    @State private var isSaving = false
    @State private var error: String?

    struct EditTarget: Identifiable { let id: Int } // index into draft.steps

    init(lab: ManagedLabDTO, existing: Experiment? = nil, steps: [Step] = [], onSaved: @escaping () -> Void) {
        self.lab = lab
        self.existing = existing
        self.onSaved = onSaved
        _draft = State(initialValue: existing.map { ExperimentDraft(experiment: $0, steps: steps) } ?? ExperimentDraft())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Experiment") {
                    TextField("Title", text: $draft.title)
                        .accessibilityIdentifier("experiment-title")
                    TextField("What students will do (optional)", text: $draft.description, axis: .vertical)
                        .lineLimit(2...4)
                }

                Section {
                    ForEach(Array(draft.steps.enumerated()), id: \.element.id) { index, step in
                        Button {
                            editing = EditTarget(id: index)
                        } label: {
                            StepDraftRow(number: index + 1, step: step)
                        }
                        .tint(.primary) // a row to open, not a link
                        .accessibilityIdentifier("draft-step-\(index + 1)")
                    }
                    .onDelete { offsets in
                        for index in offsets.sorted(by: >) { draft.removeStep(at: index) }
                    }
                    Button {
                        draft.steps.append(.init())
                        editing = EditTarget(id: draft.steps.count - 1)
                    } label: {
                        Label("Add Step", systemImage: "plus.circle.fill")
                            .fontWeight(.medium)
                    }
                    .accessibilityIdentifier("add-step")
                } header: {
                    Text("Steps")
                } footer: {
                    Text(existing == nil
                         ? "Tap a step to set its rules. Swipe left to remove it."
                         : "Steps keep students' work when you edit them. A step a student has completed can't be removed.")
                }

                if let message = error ?? draft.problems.first, !draft.steps.isEmpty || error != nil {
                    Section {
                        Label(message, systemImage: error == nil ? "info.circle" : "exclamationmark.triangle.fill")
                            .foregroundStyle(error == nil ? Color.secondary : Theme.danger)
                            .font(.footnote)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(existing == nil ? "New Experiment" : "Edit Experiment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save") { Task { await save() } }
                            .fontWeight(.semibold)
                            .disabled(!draft.problems.isEmpty)
                            .accessibilityIdentifier("save-experiment")
                    }
                }
            }
            .sheet(item: $editing) { target in
                StepEditorSheet(number: target.id + 1, step: $draft.steps[target.id])
            }
        }
        .interactiveDismissDisabled(isSaving)
    }

    private func save() async {
        guard let manage = app.manage else { return }
        isSaving = true
        error = nil
        defer { isSaving = false }
        do {
            let detail = if let existing {
                try await manage.updateExperiment(id: existing.id, draft.request)
            } else {
                try await manage.createExperiment(labId: lab.id, draft.request)
            }
            app.store.replaceCatalog(labs: [Lab(id: lab.id, name: lab.name, code: lab.code)],
                                     experiments: [detail.experiment], steps: detail.steps)
            onSaved()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// A step in the editor: its number in a circle, its title, and its rules as
/// small symbols, so the whole procedure reads at a glance.
private struct StepDraftRow: View {
    let number: Int
    let step: ExperimentDraft.StepDraft

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.m) {
            Text("\(number)")
                .font(.footnote.weight(.semibold).monospacedDigit())
                .foregroundStyle(Color.accentColor)
                .frame(width: 26, height: 26)
                .background(Color.accentColor.opacity(0.14), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(step.title.isEmpty ? "Untitled step" : step.title)
                    .foregroundStyle(step.title.isEmpty ? .secondary : .primary)
                StepRules(step: step)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
                .padding(.top, 4)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

/// A step's rules as symbols: camera, timer, and the steps it unlocks after.
private struct StepRules: View {
    let step: ExperimentDraft.StepDraft

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            if step.requiresPhoto {
                Label("Photo", systemImage: "camera.fill")
            }
            if let wait = step.waitSeconds {
                Label(ExperimentDraft.formatWait(wait), systemImage: "timer")
            }
            if !step.after.isEmpty {
                Label("After \(step.after.sorted().map(String.init).joined(separator: ", "))",
                      systemImage: "arrow.turn.down.right")
            }
            if !step.requiresPhoto && step.waitSeconds == nil && step.after.isEmpty {
                Text("No rules")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .labelStyle(CompactLabelStyle())
        .accessibilityLabel(ExperimentDraft.summary(of: step))
    }
}

private struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon
            configuration.title
        }
    }
}

/// One step: what to do, and its rules. "Unlocks after" offers only earlier
/// steps, so the order can never loop.
private struct StepEditorSheet: View {
    let number: Int
    @Binding var step: ExperimentDraft.StepDraft

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $step.title)
                        .accessibilityIdentifier("step-title")
                    TextField("Instruction for students (optional)", text: $step.instruction, axis: .vertical)
                        .lineLimit(2...5)
                }
                Section {
                    Toggle(isOn: $step.requiresPhoto) {
                        Label("Needs a photo", systemImage: "camera")
                    }
                    .accessibilityIdentifier("step-photo")
                    Picker(selection: $step.waitSeconds) {
                        Text("None").tag(Int?.none)
                        ForEach(ExperimentDraft.waitChoices(including: step.waitSeconds), id: \.self) { seconds in
                            Text(ExperimentDraft.formatWait(seconds)).tag(Int?.some(seconds))
                        }
                    } label: {
                        Label("Wait before done", systemImage: "timer")
                    }
                } header: {
                    Text("Rules")
                } footer: {
                    Text("A photo step completes when the photo is taken. A wait starts when the step unlocks.")
                }
                Section {
                    if number == 1 {
                        Text("The first step has nothing before it.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(1..<max(number, 1), id: \.self) { earlier in
                        Button {
                            if step.after.contains(earlier) { step.after.remove(earlier) } else { step.after.insert(earlier) }
                        } label: {
                            HStack {
                                Text("Step \(earlier)")
                                Spacer()
                                Image(systemName: step.after.contains(earlier) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(step.after.contains(earlier) ? Color.accentColor : Color(uiColor: .tertiaryLabel))
                            }
                        }
                        .tint(.primary)
                        .accessibilityIdentifier("after-\(earlier)")
                    }
                } header: {
                    Text("Unlocks after")
                } footer: {
                    if number > 1 {
                        Text("Students can't start this step until the chosen steps are done.")
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Step \(number)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                        .accessibilityIdentifier("step-done")
                }
            }
        }
    }
}

/// Choose which students can do a lab: one tap per student, a clear
/// selected state, search, and select all. Saving is instant: the choice
/// shows at once and is sent in the background (the caller reverts it if the
/// server refuses).
struct StudentPickerSheet: View {
    let students: [StudentDTO]
    let onSave: (Set<UUID>) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<UUID>
    @State private var search = ""
    private let initial: Set<UUID>

    init(students: [StudentDTO], selected: Set<UUID>, onSave: @escaping (Set<UUID>) -> Void) {
        self.students = students
        self.onSave = onSave
        initial = selected
        _selected = State(initialValue: selected)
    }

    private var shown: [StudentDTO] {
        search.isEmpty ? students : students.filter { $0.email.localizedCaseInsensitiveContains(search) }
    }

    private var allShownSelected: Bool { !shown.isEmpty && shown.allSatisfy { selected.contains($0.id) } }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(shown) { student in
                        StudentRow(student: student, isSelected: selected.contains(student.id)) {
                            if selected.contains(student.id) { selected.remove(student.id) } else { selected.insert(student.id) }
                        }
                    }
                } header: {
                    if !shown.isEmpty {
                        HStack {
                            Text("\(selected.count) of \(students.count) selected")
                            Spacer()
                            Button(allShownSelected ? "Deselect All" : "Select All") {
                                if allShownSelected {
                                    selected.subtract(shown.map(\.id))
                                } else {
                                    selected.formUnion(shown.map(\.id))
                                }
                            }
                            .font(.footnote.weight(.semibold))
                            .textCase(nil)
                            .accessibilityIdentifier("select-all-students")
                        }
                    }
                } footer: {
                    if !shown.isEmpty {
                        Text("Only the students you choose see this lab and its experiments.")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .overlay {
                if students.isEmpty {
                    ContentUnavailableView("No students yet", systemImage: "person.2",
                                           description: Text("Student accounts appear here once they exist."))
                } else if shown.isEmpty {
                    ContentUnavailableView.search(text: search)
                }
            }
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search by email")
            .navigationTitle("Choose Students")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(selected)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(selected == initial)
                    .accessibilityIdentifier("save-students")
                }
            }
            .sensoryFeedback(.selection, trigger: selected)
        }
    }
}

/// One student: a monogram, their name from the email, the email, and a
/// checkmark circle that fills when chosen (as in Mail and Photos).
private struct StudentRow: View {
    let student: StudentDTO
    let isSelected: Bool
    let toggle: () -> Void

    private var handle: String { student.email.split(separator: "@").first.map(String.init) ?? student.email }
    private var initial: String { handle.first.map { String($0).uppercased() } ?? "?" }

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: Theme.Space.m) {
                Text(initial)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Color(uiColor: .systemGray2), in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text(handle.capitalized)
                        .foregroundStyle(.primary)
                    Text(student.email)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : Color(uiColor: .tertiaryLabel))
                    .contentTransition(.symbolEffect(.replace))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
        .accessibilityIdentifier("student-\(student.email)")
    }
}
