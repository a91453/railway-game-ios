// SPLIT-HOTSPOTS-2 (REAL-TRAINS-PER-REGION): which of the game's train
// sets Hong Kong's real lines run (the MTR), split from
// Map3DRealTrains.swift's ``Map3DRealTrains/formation(system:id:name:)``
// so that a pull request adding one place's trains changes only its file.

extension Map3DRealTrains {
    /// The part of ``formation(system:id:name:)`` for Hong Kong's systems;
    /// `nil` for a system of another place.
    static func hongKongFormation(system: String, id: String, name: String) -> Formation? {
        switch system {
        case "hkmtr":
            // Decision 781: the MTR's lines, which have no set of their own
            // yet, borrow the generic metro car with the line's colour
            // band, as many cars as the line's real trains have
            // (``hongKongCars``), not three boxes; decision 780: but the
            // Airport Express and the Tung Chung Line their own trains;
            // decision 786: and the four urban lines (the Tseung Kwan O
            // Line's LOHAS Park branch too) theirs; decision 839: and the
            // Tuen Ma line its own; decision 843: and the East Rail line
            // (its Lok Ma Chau branch too) its own; decision 851: and the
            // South Island line its own; decision 852: and the Disneyland
            // Resort line its own.
            switch id {
            case "AEL": return Formation(key: Map3DMTRAirportLine.expressKey, cars: 8)
            case "TCL": return Formation(key: Map3DMTRAirportLine.tungChungKey, cars: 8)
            case "TWL", "ISL", "KTL", "TKL", "TKL_LHP": return Formation(key: Map3DMTRUrbanLine.key, cars: 8)
            case "TML": return Formation(key: Map3DMTRTuenMaLine.key, cars: 8)
            case "EAL", "EAL_LMC": return Formation(key: Map3DMTREastRailLine.key, cars: 9)
            case "SIL": return Formation(key: Map3DMTRSouthIslandLine.key, cars: 3)
            case "DRL": return Formation(key: Map3DMTRDisneylandLine.key, cars: 4)
            default: return Formation(key: "metroGeneric", cars: hongKongCars[id] ?? 8)
            }
        default:
            return nil
        }
    }

    /// Decision 781: how many cars a train of each MTR line has, by
    /// `hkmtr.json`'s line id: the East Rail Line's (and its Lok Ma Chau
    /// branch's) nine-car R-train, the South Island Line's three-car
    /// S-train, the Disneyland Resort Line's four cars, the other lines'
    /// eight (the Airport Express's, the Tung Chung Line's, the Tuen Ma
    /// Line's SP1900 and the urban lines' M- and Q-trains).
    static let hongKongCars: [String: Int] = [
        "AEL": 8, "TCL": 8, "TML": 8, "EAL": 9, "EAL_LMC": 9, "TWL": 8,
        "ISL": 8, "KTL": 8, "TKL": 8, "TKL_LHP": 8, "SIL": 3, "DRL": 4,
    ]
}
