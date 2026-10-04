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
///
/// The versions:
///
/// 1. Stage C4: the world's form, with every tile of the map written out.
/// 2. Stage E1 (ARCHITECTURE decision 48): the map's occupied tiles only,
///    each with its position. A new game's map is 1024 tiles a side, and
///    writing them all made a save of an empty map 13 MB; a build that
///    reads only version 1 says the save is newer than it rather than
///    calling it damaged.
/// 3. Ring lines (ARCHITECTURE decision 49): a line can be a ring
///    (`"ring": true`, with `"outerLastDispatch"`). A build that reads only
///    version 2 would take a ring for a line that turns round at its ends,
///    so it says the save is newer than it instead.
/// 4. Real-world maps (Stage E2, ARCHITECTURE decision 50): the world can
///    have a `"geoAnchor"`. A build that reads only version 3 would drop
///    it, and its next save would turn a real-world game into a blank one,
///    so it says the save is newer than it instead.
/// 5. The track spacing (Stage F2, ARCHITECTURE decision 52): edges at one
///    level keep 4 m apart, and the network lists the pairs built closer
///    before that rule (`"spacingExemptions"`). A version 4 world may hold
///    such pairs and does not list them; it is read with every pair it has
///    too close exempt, so old saves load as they were. A version 5 world
///    must list exactly its pairs too close, and a build that reads only
///    version 4 would drop the list and refuse those pairs on its next load,
///    so it says the save is newer than it instead.
public struct SavedGame: Equatable, Sendable {
    /// The version this build writes.
    public static let currentVersion = 5

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
        // Version 1 to 2: the world reads the map with every tile written
        // out as well as with only its occupied tiles, so a version 1 world
        // needs no step of its own. Version 2 to 3: a version 2 world has no
        // rings, and a line without `"ring"` is not one, so it needs none
        // either. Version 3 to 4: a version 3 world is a blank map, and a
        // world without `"geoAnchor"` is one. Version 4 to 5: the pairs of
        // edges a version 4 world has closer than the track spacing become
        // its spacing exemptions. Later versions add their steps here.
        world = try GameWorld(from: container.superDecoder(forKey: .world), madeBeforeSpacing: version < 5)
    }

    /// Encodes the world in the current version.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.currentVersion, forKey: .saveVersion)
        try container.encode(world, forKey: .world)
    }
}
