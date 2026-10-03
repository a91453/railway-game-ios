/// A saved game: the world and the version of the save format it was
/// written in (Stage C4).
///
/// The version is GameCore's, because only GameCore knows the world's
/// format. Version 1 is ``GameWorld``'s `Codable` form as of Stage C4, which
/// still reads every older world (keys added since Phase 1 are optional, see
/// ``GameWorld/init(from:)``). When a later change cannot be read that way,
/// it raises ``currentVersion`` and adds a step that turns a save of the
/// version before into the new one, each with a regression save that must
/// keep loading (the reference pack's `01_MIGRATION_MAP.md`: "Every schema
/// change should have an explicit migration function and regression
/// fixture").
///
/// A save of a later version than this build knows is refused rather than
/// guessed at, and so is any version below 1.
public struct SavedGame: Equatable, Sendable {
    /// The version this build writes.
    public static let currentVersion = 1

    public let world: GameWorld

    public init(world: GameWorld) {
        self.world = world
    }
}

extension SavedGame: Codable {
    private enum CodingKeys: String, CodingKey {
        case saveVersion, world
    }

    /// Decodes `{"saveVersion": n, "world": {...}}`, the world in the form
    /// version `n` wrote it, brought up to date. Rejects a missing or
    /// unknown version, and a world ``GameWorld/init(from:)`` rejects.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .saveVersion)
        guard version >= 1 else {
            throw DecodingError.dataCorruptedError(
                forKey: .saveVersion, in: container, debugDescription: "Save version \(version) does not exist."
            )
        }
        guard version <= Self.currentVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .saveVersion, in: container,
                debugDescription: "The save is version \(version); this build reads up to version \(Self.currentVersion)."
            )
        }
        // Version 1 is the current form; later versions add their steps here.
        world = try container.decode(GameWorld.self, forKey: .world)
    }

    /// Encodes the world in the current version.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.currentVersion, forKey: .saveVersion)
        try container.encode(world, forKey: .world)
    }
}
