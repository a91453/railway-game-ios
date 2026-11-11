import GameCore

/// Decision 360: following a train on the 3D map runs at 10× at most. The
/// ground ahead of the camera is built as it goes (decision 358), which
/// keeps up at 10× (833 m/s at 300 km/h) but not at 60× and up; 600×, a new
/// game's speed, crosses 50 km of map a second. The 2D map's speeds stay
/// as they are, and leaving the 3D map, or following, gives back the speed
/// it ran at (``GameSession/setMap3DOpen(_:)``).
public enum Map3DFollowSpeed {
    /// The fastest speed while following on the 3D map.
    public static let fastest: GameSpeed = .x10

    /// The speeds the speed menu offers: all of them on the 2D map, up to
    /// ``fastest`` while `capped`.
    public static func choices(capped: Bool) -> [GameSpeed] {
        GameSpeed.allCases.filter { $0 != .paused && (!capped || $0.tenthsPerTick <= fastest.tenthsPerTick) }
    }

    /// The fastest speed while a train is driven by hand (decision 686,
    /// review L17-5): the handle and the braking distance are a real
    /// train's, which nobody can drive at ten times the clock.
    public static let driving: GameSpeed = .x1

    /// The speeds the speed menu offers up to `cap`, all of them for `nil`.
    public static func choices(upTo cap: GameSpeed?) -> [GameSpeed] {
        GameSpeed.allCases.filter { speed in speed != .paused && capped(speed, to: cap) == speed }
    }

    /// `speed`, or `cap` when it is faster.
    public static func capped(_ speed: GameSpeed, to cap: GameSpeed?) -> GameSpeed {
        guard let cap, speed.tenthsPerTick > cap.tenthsPerTick else { return speed }
        return cap
    }

    /// What the speed menu says under its speeds while they stop at `cap`.
    public static func limitText(upTo cap: GameSpeed, in language: DisplayLanguage) -> String {
        cap == driving
            ? language.text("\(cap.label(in: language)) while you drive the train", "自己駕駛時是 \(cap.label(in: language))")
            : limitText(in: language)
    }

    /// `speed`, or ``fastest`` when it is faster.
    public static func capped(_ speed: GameSpeed) -> GameSpeed {
        speed.tenthsPerTick > fastest.tenthsPerTick ? fastest : speed
    }

    /// What the speed menu says under its speeds while capped.
    public static func limitText(in language: DisplayLanguage) -> String {
        language.text("Up to \(fastest.label(in: language)) while following in 3D", "3D 跟車時最高 \(fastest.label(in: language))")
    }
}
