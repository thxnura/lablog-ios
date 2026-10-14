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

    /// Bump when the bundled catalog changes so devices that already cached an
    /// older copy pick up the new content (v2 added step guides).
    static let version = 2

    /// Step guides (how-to, safety, expected result). Mirrors the guide columns in seed.sql.
    static let guides: [String: StepGuide] = [
        "33333333-0000-0000-0000-000000000001": StepGuide(
            steps: ["Tare the balance with a clean, dry weighing boat.", "Add about 2 g of the impure benzoic acid.", "Record the mass to 0.01 g in your observations."],
            safety: "Benzoic acid irritates the eyes, so keep your goggles on.",
            expected: "A steady reading of roughly 2.00 g.",
        ),
        "33333333-0000-0000-0000-000000000002": StepGuide(
            steps: ["Heat distilled water to boiling on the hot plate.", "Add hot water a few mL at a time to the sample in a conical flask, swirling between additions.", "Stop as soon as the solid dissolves. Extra solvent lowers your yield."],
            safety: "Hot glassware: handle it with tongs or a heat-proof glove.",
            expected: "A clear, colourless solution with no solid left.",
        ),
        "33333333-0000-0000-0000-000000000003": StepGuide(
            steps: ["Keep the flask just below boiling on the hot plate.", "Swirl gently about once a minute.", "If insoluble specks remain, filter the solution while it is still hot."],
            safety: "Never stopper or seal a heated flask.",
            expected: "The sample is fully dissolved after five minutes.",
        ),
        "33333333-0000-0000-0000-000000000004": StepGuide(
            steps: ["Let the flask cool to room temperature without disturbing it.", "Then cool it in an ice bath for 10 minutes.", "Photograph the crystals against a dark background."],
            safety: nil,
            expected: "Shiny white crystals, needle- or plate-shaped.",
        ),
        "33333333-0000-0000-0001-000000000001": StepGuide(
            steps: ["Rinse the burette twice with a little NaOH, draining it through the tap.", "Fill it with 0.10 M NaOH using a funnel, then take the funnel out.", "Run a little solution out to clear the air bubble from the tip.", "Read the bottom of the meniscus at eye level."],
            safety: "NaOH is corrosive. Wear goggles and rinse any spill with plenty of water.",
            expected: "No air in the tip, and an initial reading recorded to 0.05 mL.",
        ),
        "33333333-0000-0000-0001-000000000002": StepGuide(
            steps: ["Rinse the pipette with a little of the HCl.", "Fill it to the line with a pipette filler.", "Let it drain into the flask, then touch the tip against the glass."],
            safety: "Always use a pipette filler. Never pipette by mouth.",
            expected: "Exactly 25.0 mL of acid in the flask.",
        ),
        "33333333-0000-0000-0001-000000000003": StepGuide(
            steps: ["Add 3 drops of phenolphthalein.", "Swirl to mix.", "Stand the flask on a white tile under the burette."],
            safety: nil,
            expected: "The solution stays colourless, because it is still acidic.",
        ),
        "33333333-0000-0000-0001-000000000004": StepGuide(
            steps: ["Run in NaOH quickly while swirling, until the pink takes longer to fade.", "Slow down to drop by drop.", "Stop at the first faint pink that lasts 30 seconds.", "Photograph the endpoint, then record the final burette reading."],
            safety: "Close the tap before you move the flask.",
            expected: "A pale pink colour that persists for 30 seconds.",
        ),
        "33333333-0000-0000-0001-000000000005": StepGuide(
            steps: ["Refill the burette and rinse the flask with distilled water.", "Repeat Steps 2 to 4.", "Stop when two titres agree within 0.10 mL."],
            safety: nil,
            expected: "Two concordant titres, for example 24.60 and 24.55 mL.",
        ),
        "33333333-0000-0000-0002-000000000001": StepGuide(
            steps: ["Clamp the string so the bob hangs freely.", "Measure from the pivot to the centre of the bob with a metre rule.", "Record the length in metres, to the nearest millimetre."],
            safety: nil,
            expected: "A length between about 0.50 and 1.00 m.",
        ),
        "33333333-0000-0000-0002-000000000002": StepGuide(
            steps: ["Fix the clamp stand to the bench with a G-clamp.", "Stand the ruler behind the pendulum.", "Photograph the whole rig with the ruler markings readable."],
            safety: "Clamp the stand firmly so it can't tip over.",
            expected: "A clear photo showing the clamp, string, bob and ruler.",
        ),
        "33333333-0000-0000-0002-000000000003": StepGuide(
            steps: ["Pull the bob aside to an angle under 10°.", "Release it without pushing, and start timing as it passes the centre.", "Count 20 full swings (there and back), then stop the timer."],
            safety: "Keep your face clear of the swinging bob.",
            expected: "About 28 s for a 0.50 m string (a period of about 1.4 s).",
        ),
        "33333333-0000-0000-0002-000000000004": StepGuide(
            steps: ["Shorten the string by about 20 cm.", "Re-measure the length and time 20 swings again.", "Repeat for a third length."],
            safety: nil,
            expected: "Shorter strings give shorter periods (T is proportional to √L).",
        ),
    ]

    static var steps: [Step] {
        baseSteps.map { step in
            var step = step
            step.guide = guides[step.id.uuidString.lowercased()]
            return step
        }
    }

    private static let baseSteps: [Step] = {
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

    /// Loads the bundled catalog if the device has never cached one, or if the
    /// cached copy came from an older bundled version.
    @MainActor
    static func installIfNeeded(into store: LocalStore, defaults: UserDefaults = .standard) {
        let key = "bundledCatalogVersion"
        guard !store.hasCatalog() || defaults.integer(forKey: key) < version else { return }
        store.replaceCatalog(labs: labs, experiments: experiments, steps: steps)
        defaults.set(version, forKey: key)
    }
}
