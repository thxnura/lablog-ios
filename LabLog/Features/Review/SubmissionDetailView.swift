import MapKit
import SwiftUI

/// Everything a lecturer needs to judge one submission: who and when, how long
/// it took, each step with its completion time and photo, the observation, and
/// where it was submitted.
struct SubmissionDetailView: View {
    let submission: SubmissionDTO
    let experiment: Experiment
    let lab: Lab?
    let steps: [Step]

    @State private var fullScreenPhoto: SubmissionDTO.Photo?

    private var discipline: Discipline { .of(labCode: lab?.code ?? "") }

    private var completionByStep: [UUID: SubmissionDTO.Completion] {
        Dictionary(submission.stepCompletions.map { ($0.stepId, $0) }, uniquingKeysWith: { a, _ in a })
    }

    private var photoByStep: [UUID: SubmissionDTO.Photo] {
        Dictionary(submission.attachments.compactMap { photo in photo.stepId.map { ($0, photo) } },
                   uniquingKeysWith: { a, _ in a })
    }

    /// First step completed → submitted.
    private var duration: String? {
        guard let first = submission.stepCompletions.map(\.completedAt).min(),
              let end = submission.submittedAt else { return nil }
        let seconds = Int(end.timeIntervalSince(first))
        return Duration.seconds(max(seconds, 0)).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .abbreviated, maximumUnitCount: 2))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                header
                stats
                procedure
                if !submission.observations.isEmpty { observation }
                if let coordinate { location(coordinate) }
            }
            .padding(.horizontal, Theme.Space.l)
            .padding(.bottom, Theme.Space.xl)
        }
        .background(Theme.canvas)
        .navigationTitle("Submission")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $fullScreenPhoto) { photo in
            PhotoViewer(photo: photo, stepTitle: steps.first { $0.id == photo.stepId }?.title)
        }
    }

    // MARK: Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text("\(lab?.code ?? "") · \(experiment.title)").eyebrow()
            Text(submission.studentEmail ?? "Student")
                .font(.title2.weight(.bold))
            Label((submission.submittedAt ?? submission.createdAt).formatted(date: .complete, time: .shortened),
                  systemImage: "checkmark.seal.fill")
                .font(.subheadline)
                .foregroundStyle(Theme.success)
        }
        .padding(.top, Theme.Space.s)
    }

    private var stats: some View {
        HStack(spacing: Theme.Space.m) {
            StatTile(value: submission.stepCompletions.count, label: "of \(steps.count) steps",
                     symbol: "checklist", tint: Theme.success)
            StatTile(value: submission.attachments.count, label: "Photos", symbol: "camera.fill", tint: .accentColor)
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Image(systemName: "clock.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.caution)
                    .frame(width: 30, height: 30)
                    .background(Theme.caution.opacity(0.14), in: Circle())
                Text(duration ?? "—")
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("Duration")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .card(padding: Theme.Space.m)
        }
    }

    private var procedure: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            SectionHeader(title: "Procedure")
            VStack(spacing: 0) {
                ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                    let completion = completionByStep[step.id]
                    HStack(alignment: .top, spacing: Theme.Space.m) {
                        VStack(spacing: 0) {
                            Image(systemName: completion == nil ? "circle.dashed" : "checkmark.circle.fill")
                                .font(.title3)
                                .foregroundStyle(completion == nil ? Color.secondary : Theme.success)
                            if index < steps.count - 1 {
                                Rectangle()
                                    .fill(completion == nil ? Color.secondary.opacity(0.2) : Theme.success.opacity(0.5))
                                    .frame(width: 2)
                                    .frame(maxHeight: .infinity)
                            }
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Step \(step.order)").eyebrow()
                            Text(step.title).font(.subheadline.weight(.semibold))
                            Text(completion.map { "Done at \($0.completedAt.formatted(date: .omitted, time: .shortened))" } ?? "Not completed")
                                .font(.caption)
                                .foregroundStyle(completion == nil ? Theme.danger : .secondary)
                        }
                        .padding(.bottom, index < steps.count - 1 ? Theme.Space.l : 0)
                        Spacer(minLength: 0)
                        if let photo = photoByStep[step.id] {
                            Button { fullScreenPhoto = photo } label: {
                                RemotePhoto(url: photo.url)
                                    .frame(width: 64, height: 64)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            .buttonStyle(.pressableCard)
                            .accessibilityLabel("Evidence photo for step \(step.order)")
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .card()
        }
    }

    private var observation: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            SectionHeader(title: "Observation")
            Text(submission.observations.map(\.text).joined(separator: "\n\n"))
                .font(.body)
                .card()
        }
    }

    private var coordinate: CLLocationCoordinate2D? {
        guard let lat = submission.latitude, let lon = submission.longitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    private func location(_ coordinate: CLLocationCoordinate2D) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            SectionHeader(title: "Submitted from", trailing: String(format: "%.4f, %.4f", coordinate.latitude, coordinate.longitude))
            Map(initialPosition: .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 700, longitudinalMeters: 700)),
                interactionModes: []) {
                Marker(submission.studentEmail ?? "Student", systemImage: discipline.symbol, coordinate: coordinate)
                    .tint(discipline.tint)
            }
            .frame(height: 180)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .allowsHitTesting(false)
        }
    }
}

/// Photo from a signed URL, with a placeholder while it loads.
private struct RemotePhoto: View {
    let url: URL?

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            case .failure:
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.inset)
            default:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.inset)
            }
        }
    }
}

private struct PhotoViewer: View {
    let photo: SubmissionDTO.Photo
    let stepTitle: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            RemotePhoto(url: photo.url)
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.black)
                .navigationTitle(stepTitle ?? "Evidence")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}
