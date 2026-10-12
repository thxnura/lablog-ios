import Foundation

/// The catalog bundled with the app so it is usable offline from the very
/// first launch. Ids match `lablog-backend/db/seed.sql`, so records created
/// against this catalog sync to the same experiments and steps on the server.
/// A server catalog refresh replaces it once the device is online and signed in.
enum CatalogSeed {
    private static func id(_ string: String) -> UUID { UUID(uuidString: string)! }

    static let chemistryLab = Lab(id: id("11111111-1111-1111-1111-111111111111"), name: "Organic Chemistry Lab", code: "CHEM201")
    static let physicsLab = Lab(id: id("11111111-1111-1111-1111-111111111112"), name: "Physics Lab", code: "PHYS101")

    static let recrystallisation = Experiment(
        id: id("22222222-2222-2222-2222-222222222222"), labId: chemistryLab.id,
        title: "Recrystallisation of Benzoic Acid",
        description: "Purify an impure benzoic acid sample by recrystallisation.",
    )
    static let titration = Experiment(
        id: id("22222222-2222-2222-2222-222222222223"), labId: chemistryLab.id,
        title: "Acid–Base Titration",
        description: "Find the concentration of an HCl solution by titrating against 0.10 M NaOH.",
    )
    static let pendulum = Experiment(
        id: id("22222222-2222-2222-2222-222222222224"), labId: physicsLab.id,
        title: "Simple Pendulum",
        description: "Measure the period of a simple pendulum and estimate g.",
    )

    static let labs = [chemistryLab, physicsLab]
    static let experiments = [recrystallisation, titration, pendulum]

    static let steps: [Step] = {
        let r1 = id("33333333-0000-0000-0000-000000000001")
        let r2 = id("33333333-0000-0000-0000-000000000002")
        let r3 = id("33333333-0000-0000-0000-000000000003")
        let r4 = id("33333333-0000-0000-0000-000000000004")

        let t1 = id("33333333-0000-0000-0001-000000000001")
        let t2 = id("33333333-0000-0000-0001-000000000002")
        let t3 = id("33333333-0000-0000-0001-000000000003")
        let t4 = id("33333333-0000-0000-0001-000000000004")
        let t5 = id("33333333-0000-0000-0001-000000000005")

        let p1 = id("33333333-0000-0000-0002-000000000001")
        let p2 = id("33333333-0000-0000-0002-000000000002")
        let p3 = id("33333333-0000-0000-0002-000000000003")
        let p4 = id("33333333-0000-0000-0002-000000000004")

        let r = recrystallisation.id, t = titration.id, p = pendulum.id
        return [
            // Linear chain with a 5-minute timer and a photo guard.
            Step(id: r1, experimentId: r, order: 1, title: "Weigh the impure sample",
                 instruction: "Record the starting mass of impure benzoic acid.",
                 requiresPhoto: false, minDurationSeconds: nil, prerequisiteStepIds: []),
            Step(id: r2, experimentId: r, order: 2, title: "Add hot solvent",
                 instruction: "Add minimum boiling water to dissolve the sample.",
                 requiresPhoto: false, minDurationSeconds: nil, prerequisiteStepIds: [r1]),
            Step(id: r3, experimentId: r, order: 3, title: "Allow to dissolve (5 min)",
                 instruction: "Keep near boiling until fully dissolved.",
                 requiresPhoto: false, minDurationSeconds: 300, prerequisiteStepIds: [r2]),
            Step(id: r4, experimentId: r, order: 4, title: "Cool and photograph crystals",
                 instruction: "Cool slowly, then photograph the crystals formed.",
                 requiresPhoto: true, minDurationSeconds: nil, prerequisiteStepIds: [r3]),

            // Branching DAG: 1 and 2 in any order; 4 needs both 1 and 3.
            Step(id: t1, experimentId: t, order: 1, title: "Rinse and fill the burette",
                 instruction: "Rinse with NaOH, fill, and record the initial reading.",
                 requiresPhoto: false, minDurationSeconds: nil, prerequisiteStepIds: []),
            Step(id: t2, experimentId: t, order: 2, title: "Pipette the acid",
                 instruction: "Transfer 25.0 mL of HCl into a clean conical flask.",
                 requiresPhoto: false, minDurationSeconds: nil, prerequisiteStepIds: []),
            Step(id: t3, experimentId: t, order: 3, title: "Add indicator",
                 instruction: "Add 3 drops of phenolphthalein to the flask.",
                 requiresPhoto: false, minDurationSeconds: nil, prerequisiteStepIds: [t2]),
            Step(id: t4, experimentId: t, order: 4, title: "Titrate to the endpoint",
                 instruction: "Add NaOH dropwise until a faint permanent pink. Photograph the endpoint.",
                 requiresPhoto: true, minDurationSeconds: nil, prerequisiteStepIds: [t1, t3]),
            Step(id: t5, experimentId: t, order: 5, title: "Repeat for concordant titres",
                 instruction: "Repeat until two titres agree within 0.10 mL.",
                 requiresPhoto: false, minDurationSeconds: nil, prerequisiteStepIds: [t4]),

            // Short timer, handy for live demos.
            Step(id: p1, experimentId: p, order: 1, title: "Measure the string length",
                 instruction: "Measure from the clamp to the centre of the bob.",
                 requiresPhoto: false, minDurationSeconds: nil, prerequisiteStepIds: []),
            Step(id: p2, experimentId: p, order: 2, title: "Set up and photograph the rig",
                 instruction: "Clamp the pendulum and photograph the setup with the ruler visible.",
                 requiresPhoto: true, minDurationSeconds: nil, prerequisiteStepIds: [p1]),
            Step(id: p3, experimentId: p, order: 3, title: "Time 20 oscillations",
                 instruction: "Release from a small angle and time 20 full swings.",
                 requiresPhoto: false, minDurationSeconds: 30, prerequisiteStepIds: [p2]),
            Step(id: p4, experimentId: p, order: 4, title: "Repeat at two more lengths",
                 instruction: "Shorten the string twice and repeat the timing.",
                 requiresPhoto: false, minDurationSeconds: nil, prerequisiteStepIds: [p3]),
        ]
    }()

    /// Loads the bundled catalog if the device has never cached one.
    @MainActor
    static func installIfNeeded(into store: LocalStore) {
        guard !store.hasCatalog() else { return }
        store.replaceCatalog(labs: labs, experiments: experiments, steps: steps)
    }
}
