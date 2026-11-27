// SPLIT-HOTSPOTS-2 (REAL-TRAINS-PER-REGION): which of the game's train
// sets Japan's real lines run (the Fukuoka City Subway, the Kyushu and
// Nishi-Kyushu Shinkansen, the Relay Kamome and the Sanyo Shinkansen), split from Map3DRealTrains.swift's ``Map3DRealTrains/formation(system:id:name:)``
// so that a pull request adding one place's trains changes only its file.

extension Map3DRealTrains {
    /// The part of ``formation(system:id:name:)`` for Japan's systems;
    /// `nil` for a system of another place.
    static func japanFormation(system: String, id: String, name: String) -> Formation? {
        switch system {
        case "fksubway":
            // Decision 893: the Airport line's newest six-car train on
            // the Airport and Hakozaki lines, which run the same trains,
            // and the Nanakuma line's own four cars.
            switch id {
            case "K", "H": return Formation(key: Map3DFukuokaAirportLine.key, cars: Map3DFukuokaAirportLine.cars)
            case "N": return Formation(key: Map3DFukuokaNanakumaLine.key, cars: Map3DFukuokaNanakumaLine.cars)
            default: return Formation(key: "", cars: 3)
            }
        case "kyushushinkansen":
            // Decision 977: the Kyushu Shinkansen's N700 series 7000 and
            // 8000, eight cars (the "Mizuho" and "Sakura" through trains).
            // Decision 978: and its odd-numbered trains the 800 series'
            // six (the "Tsubame"), the line's two fleets.
            // Decision 998: the Nishi-Kyushu Shinkansen's N700S series
            // 8000, six cars (the "Kamome"); decision 998 (continued): in
            // its own livery.
            if id == "NK" { return Formation(key: Map3DN700SKamome.key, cars: Map3DN700SKamome.cars) }
            return Formation(key: Map3DKyushuN700.key, cars: Map3DKyushuN700.cars, alternate: Map3DKyushu800.key)
        case "jrkyushu":
            // Decision 1028 (continued): the Relay Kamome's 885 series,
            // six cars, and its odd-numbered trains the 787 series' six,
            // the line's two fleets (until they had their own models, the
            // Taroko).
            return Formation(key: Map3DKyushu885.key, cars: Map3DKyushu885.cars, alternate: Map3DKyushu787.key)
        case "sanyoshinkansen":
            // Decision 1029: the Sanyo Shinkansen's N700S, sixteen cars,
            // its odd-numbered trains the 700 series' sixteen (the
            // garage's, first drawn on a line here), the line's two
            // fleets as the game has them.
            return Formation(key: Map3DN700S.key, cars: 16, alternate: Map3DSeries700.key)
        default:
            return nil
        }
    }
}
