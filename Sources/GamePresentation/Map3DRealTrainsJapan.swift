// SPLIT-HOTSPOTS-2 (REAL-TRAINS-PER-REGION): which of the game's train
// sets Japan's real lines run (the Fukuoka City Subway and the Kyushu and
// Nishi-Kyushu Shinkansen), split from Map3DRealTrains.swift's ``Map3DRealTrains/formation(system:id:name:)``
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
            // 8000, six cars (the "Kamome"), the game's N700S.
            if id == "NK" { return Formation(key: Map3DN700S.key, cars: 6) }
            return Formation(key: Map3DKyushuN700.key, cars: Map3DKyushuN700.cars, alternate: Map3DKyushu800.key)
        default:
            return nil
        }
    }
}
