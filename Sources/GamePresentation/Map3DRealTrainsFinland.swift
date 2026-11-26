// SPLIT-HOTSPOTS-2 (REAL-TRAINS-PER-REGION): which of the game's train
// sets Finland's real lines run (VR's Rovaniemi lines), split from
// Map3DRealTrains.swift's ``Map3DRealTrains/formation(system:id:name:)``
// so that a pull request adding one place's trains changes only its file.

extension Map3DRealTrains {
    /// The part of ``formation(system:id:name:)`` for Finland's systems;
    /// `nil` for a system of another place.
    static func finlandFormation(system: String, id: String, name: String) -> Formation? {
        switch system {
        case "vr":
            // Decision 864: Rovaniemi's two lines (the Kemijärvi line and
            // Rovaniemi–Muurola), whose intercity and night trains are
            // hauled: the Sr2 and six double-deck coaches, the coach every
            // train of the week counted had and the locomotive most of them.
            // FINLAND-TRAINS-2: each timetable train by its name
            // (``finland(train:)``); this, a bought line's, the intercity.
            return Formation(key: Map3DFinlandSr2.key, cars: Map3DFinlandSr2.cars)
        default:
            return nil
        }
    }

    /// FINLAND-TRAINS-2: a Rovaniemi train by its name in the timetable
    /// (`PYO 265`, `IC 24`): a night train (`PYO`) its locomotive and
    /// double-deck sleepers, any other (`IC`, `S`, December's `MUS`) its
    /// locomotive, double-deck coaches and the control car at the back.
    /// The locomotive an Sr3 for three train numbers in eight (the
    /// remainders ``sr3Remainders``) and an Sr2 for the others, about as a
    /// week of Digitraffic's compositions had them (38 trains in 99);
    /// which train has which is not fixed, but the Kemijärvi line's night
    /// trains (265, 274), which the Sr2 hauled that week, keep it.
    static func finland(train: String) -> Formation {
        let sr3 = sr3Remainders.contains(Map3DTrainSet.number(ofRealTrain: train) % 8)
        let night = train.hasPrefix("PYO")
        let key = night ? (sr3 ? Map3DFinlandSleeper.sr3Key : Map3DFinlandSleeper.key) : (sr3 ? Map3DFinlandSr3.key : Map3DFinlandSr2.key)
        return Formation(key: key, cars: Map3DFinlandSr2.cars)
    }

    /// FINLAND-TRAINS-2: the remainders of a train number divided by
    /// eight drawn behind the Sr3.
    static let sr3Remainders: Set<Int> = [3, 5, 6]
}
