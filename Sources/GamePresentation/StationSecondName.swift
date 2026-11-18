import GameCore

// Decision 845: the station card's nameboard gives a real station both of
// its names, as the railways' own signs do: the name the station has in
// the game, large, and under it, small, its other name from the real data
// (`station_names.json`): the official English name of a station in
// Taiwan or Hong Kong, the Finnish one of a station in Lapland, and the
// Chinese one of a Taiwanese or Hong Kong station named in English.

extension GameSession {
    /// The second name the nameboard shows under station `id`'s name, or
    /// `nil` when there is none: a station the player named themselves, one
    /// on a map that is not the real world, or one whose real names are the
    /// same.
    public func stationSecondName(of id: StationID) -> String? {
        guard let station = world.station(id: id), RealWorldFrame(world: world) != nil else { return nil }
        let real = realStations(named: station.name, at: station.location)
        return Self.secondName(of: station.name, real: real, language: language)
    }

    /// The second name of a station named `name` that is the real stations
    /// `real` (in the site's order): the first one's English name under a
    /// Chinese name, its Chinese name under an English one. A place whose
    /// own names are written in Latin letters (``RealRailways/System/namesInLatin``)
    /// shows no Chinese under its name in English, where that name is
    /// already the one on its signs.
    static func secondName(of name: String, real: [RealRailways.Station], language: DisplayLanguage) -> String? {
        guard let station = real.first(where: { $0.english != nil }) ?? real.first else { return nil }
        let key = RealRailways.stationKey(name)
        let english = station.english.map(RealRailways.Station.shown)
        let isEnglish = english.map { RealRailways.stationKey($0) == key } ?? false
        let second: String?
        if isEnglish {
            second = language == .english && station.system.namesInLatin ? nil : station.chinese
        } else {
            second = english
        }
        guard let second, RealRailways.stationKey(second) != key else { return nil }
        return second
    }
}
