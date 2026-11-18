import GameCore

// Decision 866: the station panel's sounds, the arrival chime and the
// departure melody the player picks for a station (decision 219, stage 2).
// GameCore keeps the choice (`Station.chime`, `Station.departureMelody`);
// what it is called, what "automatic" plays and the panel's commands are
// here so a Linux test can hold them.

extension StationChime {
    /// Its name on the panel.
    public func title(in language: DisplayLanguage) -> String {
        switch self {
        case .local: language.text("Small station bell", "小站鈴")
        case .metro: language.text("Interchange bell", "轉乘站鈴")
        case .tourist: language.text("Sightseeing chime", "觀光站鈴")
        }
    }
}

extension DepartureMelody {
    /// Its name on the panel.
    public func title(in language: DisplayLanguage) -> String {
        switch self {
        case .a: language.text("Melody 1", "旋律一")
        case .b: language.text("Melody 2", "旋律二")
        case .c: language.text("Melody 3", "旋律三")
        }
    }
}

/// Decision 866: the station panel's sounds row, for one station: what the
/// player set it to play, and what it plays when set to neither.
public struct StationSoundsChoice: Hashable, Sendable {
    /// The chime the player set, `nil` for automatic.
    public var chime: StationChime?
    /// The melody the player set, `nil` for each line's own.
    public var departureMelody: DepartureMelody?
    /// The chime the station rings when set to automatic.
    public var automaticChime: StationChime

    /// The row of station `id` in `world`, or `nil` for a depot (no train
    /// calls there in service) or a station that does not exist.
    public init?(of id: StationID, in world: GameWorld) {
        guard let station = world.station(id: id), !station.isDepot else { return nil }
        chime = station.chime
        departureMelody = station.departureMelody
        automaticChime = StationChime.automatic(id, in: world)
    }

    /// The chime picker's choice for `chime`: automatic says what it rings.
    public func chimeTitle(_ chime: StationChime?, in language: DisplayLanguage) -> String {
        guard let chime else {
            return language.text("Automatic (\(automaticChime.title(in: language)))", "自動（\(automaticChime.title(in: language))）")
        }
        return chime.title(in: language)
    }

    /// The melody picker's choice for `melody`.
    public static func melodyTitle(_ melody: DepartureMelody?, in language: DisplayLanguage) -> String {
        melody?.title(in: language) ?? language.text("Each line's own", "依路線")
    }

    /// What the row does for the player.
    public static func note(in language: DisplayLanguage) -> String {
        language.text(
            "The bell rings as trains arrive; the melody plays as the doors close on a train you are watching, at 60× or slower. Picking one plays it once.",
            "到站鈴在列車進站時響；發車旋律在你看著的列車關門時響（60 倍速以下）。選好會先播一次給你聽。"
        )
    }
}

extension GameSession {
    /// Decision 866: the selected station's sounds row, or `nil` when no
    /// station or a depot is selected.
    public var selectedStationSounds: StationSoundsChoice? {
        selectedStationID.flatMap { StationSoundsChoice(of: $0, in: world) }
    }

    /// Decision 866: sets the selected station's arrival chime, `nil` for
    /// automatic, through `GameWorld.setStationChime(_:to:)`, and plays the
    /// chime it rings now once.
    public func setSelectedStationChime(_ chime: StationChime?) {
        guard let station = selectedStation else { return }
        let done = perform(.setStationChime(station.id, chime)) { _, _, after in
            let rung = StationChime.of(station.id, in: after)
            return chime == nil
                ? language.text("\(station.name) rings its own bell again: \(rung.title(in: .english)).",
                                "\(station.name) 的到站鈴改回自動：\(rung.title(in: .traditionalChinese))。")
                : language.text("\(station.name) now rings the \(rung.title(in: .english)).",
                                "\(station.name) 的到站鈴改為\(rung.title(in: .traditionalChinese))。")
        }
        if done != nil { playSound?(.arrival(watched: true, chime: StationChime.of(station.id, in: world))) }
    }

    /// Decision 866: sets the selected station's departure melody, `nil`
    /// for each line's own, through
    /// `GameWorld.setStationDepartureMelody(_:to:)`, and plays the melody
    /// once (for each line's own, the first line calling there's).
    public func setSelectedStationDepartureMelody(_ melody: DepartureMelody?) {
        guard let station = selectedStation else { return }
        let done = perform(.setStationDepartureMelody(station.id, melody)) { _, _, _ in
            guard let melody else {
                return language.text("\(station.name) plays each line's own melody again.", "\(station.name) 的發車旋律改回依路線。")
            }
            return language.text("\(station.name) now plays \(melody.title(in: .english)) as doors close.",
                                 "\(station.name) 的發車旋律改為\(melody.title(in: .traditionalChinese))。")
        }
        guard done != nil else { return }
        let heard = melody ?? world.lines.first { !$0.isFreight && $0.stops.contains(station.id) }.map { DepartureMelody.of(lineNamed: $0.name) }
        if let heard { playSound?(.departure(heard)) }
    }
}
