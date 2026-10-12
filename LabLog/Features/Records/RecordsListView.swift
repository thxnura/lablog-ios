import SwiftUI

/// Every record on this device, filterable, with progress and sync state.
struct RecordsListView: View {
    @Environment(AppModel.self) private var app
    @State private var rows: [Row] = []
    @State private var filter: Filter = .all

    enum Filter: String, CaseIterable, Identifiable {
        case all = "All", drafts = "In progress", submitted = "Submitted"
        var id: Self { self }
    }

    struct Row: Identifiable {
        let record: LabRecord
        let title: String
        let labCode: String
        let done: Int
        let total: Int
        let photos: Int
        var id: UUID { record.id }
    }

    private var visible: [Row] {
        switch filter {
        case .all: rows
        case .drafts: rows.filter { $0.record.status == .draft }
        case .submitted: rows.filter { $0.record.status == .submitted }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                Picker("Filter", selection: $filter) {
                    ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.bottom, Theme.Space.s)

                ForEach(visible) { row in
                    NavigationLink(value: RecordRoute(id: row.record.id)) {
                        RecordCard(row: row)
                    }
                    .buttonStyle(.pressableCard)
                }

                if visible.isEmpty {
                    ContentUnavailableView(
                        filter == .all ? "No lab records" : "Nothing here",
                        systemImage: "list.bullet.clipboard",
                        description: Text("Start an experiment from the Labs tab. Records are saved on this device first."),
                    )
                    .padding(.top, Theme.Space.xxl)
                }
            }
            .padding(.horizontal, Theme.Space.l)
            .padding(.bottom, Theme.Space.xl)
            .animation(Theme.spring, value: filter)
        }
        .background(Theme.canvas)
        .navigationTitle("Records")
        .navigationDestination(for: RecordRoute.self) { route in
            RecordCaptureView(recordId: route.id)
        }
        .toolbar { ConnectivityToolbarItem() }
        .refreshable { await app.sync.sync() }
        .task(id: app.store.version) { load() }
    }

    private func load() {
        let store = app.store
        let labs = store.labs()
        rows = store.records().map { record in
            let experiment = store.experiment(id: record.experimentId)
            return Row(record: record,
                       title: experiment?.title ?? "Unknown experiment",
                       labCode: labs.first { $0.id == experiment?.labId }?.code ?? "",
                       done: store.completions(recordId: record.id).count,
                       total: store.steps(experimentId: record.experimentId).count,
                       photos: store.attachments(recordId: record.id).count)
        }
    }
}

private struct RecordCard: View {
    let row: RecordsListView.Row

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            DisciplineIcon(discipline: .of(labCode: row.labCode), size: 44)
            VStack(alignment: .leading, spacing: 5) {
                Text(row.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(row.record.submittedAt ?? row.record.createdAt, format: .dateTime.weekday(.abbreviated).day().month().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    RecordStatusBadge(status: row.record.status)
                    SyncStateBadge(state: row.record.syncState)
                    if row.photos > 0 {
                        Label("\(row.photos)", systemImage: "photo")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer(minLength: 0)
            ZStack {
                ProgressRing(progress: Double(row.done) / Double(max(row.total, 1)), lineWidth: 4,
                             tint: row.done == row.total ? Theme.success : Theme.caution)
                Text("\(row.done)/\(row.total)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }
            .frame(width: 42, height: 42)
        }
        .card(padding: Theme.Space.m + 2)
        .accessibilityElement(children: .combine)
    }
}
