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
/// 6. The world's bounds (Stage F3d, ARCHITECTURE decision 54): the world
///    is `"bounds": {"width", "height"}` in world units, no longer a
///    `"map"` of tiles, and a train's movement no longer writes the grid's
///    empty `"continuation"`. A version 5 world's map of `w × h` tiles is
///    read as bounds `1024w × 1024h` units (every tile of it was empty
///    ground), and an empty `"continuation"` is still read. A build that
///    reads only version 5 would find no map in a version 6 world and call
///    it damaged, so it says the save is newer than it instead.
/// 7. Following (Stage U2, ARCHITECTURE decision 56): under traffic control
///    a service on its way to a call may hold its route only part of the
///    way, following the trains ahead. The format is the same; a build that
///    reads only version 6 would refuse such a reservation as not holding
///    the rest of its route, so it says the save is newer than it instead.
/// 8. Passing places (Stage V2, ARCHITECTURE decision 58): a service on its
///    way to a call may be on its way to, or stand at, a berth of another
///    station, where it stands aside out of a deadlock. The format is the
///    same; a build that reads only version 7 would refuse such a service
///    as travelling on a path that does not end at its next stop, or that
///    is spent, so it says the save is newer than it instead.
/// 9. Scheduled traffic (decision 59): actual station visits release meets
///    and overtakes, including after a delayed train enters its next run.
///    Version 8 would drop these events and release a wait too soon.
/// 10. Shared line/service physical route preferences (decision 61).
///     Older builds would silently drop an assigned path or platform.
/// 11. Network passenger journeys and transfer queues (Phase 5C/5F).
///     Older builds would drop their remaining legs or route balances.
/// 12. Land (Phase 6a, ARCHITECTURE decision 72): the world can have
///     `"land"`, who lives and works in each 64 m cell. A build that reads
///     only version 11 would drop it, and its next save would lose the
///     city, so it says the save is newer than it instead.
/// 13. City buildings (Phase 6c-1, ARCHITECTURE decision 74): the world can
///     have `"cityBuildings"` and `"buildings"`, the building on each cell
///     of land. A build that reads only version 12 would drop them.
/// 14. Town growth's last service and stations reached (Phase 6c-2,
///     ARCHITECTURE decision 75): a station's growth can have
///     `"lastService"` and `"lastReached"`, which raise buildings. A build
///     that reads only version 13 would drop them.
/// 15. Transfer groups (ARCHITECTURE decision 81): the world can have
///     `"transferGroups"` and `"nextTransferGroupID"`, stations passengers
///     walk between however far apart. A build that reads only version 14
///     would drop them, and its passengers' journeys across one with them.
/// 16. Fixed assets and closed years (Phase 7a, ARCHITECTURE decision 85):
///     the accounts can have `"assets"`, what each track edge, station,
///     train and car cost and how far it is written down, `"capitalDays"`
///     and `"years"`. A build that reads only version 15 would drop them,
///     and its next save would lose what everything cost.
/// 17. Goals and fast forward (decision 86): the world can have a
///     `"scenario"`, its goals and how far they are met, the accounts' days
///     their `"fareTrips"`, and the clock can run `"fast"`. A build that
///     reads only version 16 would drop the scenario, or refuse the speed.
/// 18. The whole of Taiwan (decision 88): a world's sides can be up to 2^25
///     units (524 km), no longer 2^20, and its land can be read in as it is
///     needed, with `"landBlocks"`, the blocks read so far. A build that
///     reads only version 17 would call a larger world damaged, or drop the
///     blocks and read none again, so it says the save is newer than it
///     instead.
/// 21. Buildings the player places (decision 92; 19 and 20 are reserved by
///     other work, issue #231): the world can have `"placedBuildings"` and
///     `"nextPlacedBuildingID"`. A build that reads only an earlier version
///     would drop them, and its next save would lose the player's
///     buildings, so it says the save is newer than it instead.
public struct SavedGame: Equatable, Sendable {
    /// The version this build writes.
    public static let currentVersion = 21

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
        // its spacing exemptions. Version 5 to 6: a world before version 6
        // has its map of tiles, which the world reads as the bounds it
        // covers, and its movements' empty continuations, which it reads
        // and drops. Version 6 to 7: a version 6 world has no train
        // following another, and every reservation holds its whole route,
        // which version 7 reads as before. Version 7 to 8: a version 7
        // world has no service at a passing place, and every travelling
        // service's path ends at its next stop, which version 8 reads as
        // before. Version 8 to 9: missing actual traffic visits decode as an
        // empty history; no plan is migrated or saved. Older running services
        // conservatively use their last actual arrival where history is absent.
        // Version 9 to 10: absent line/pattern routePreferences migrate
        // to empty automatic selections in their validated decoders.
        // Version 10 to 11: absent passenger routing mode means direct;
        // old waiting and riding groups have no journey or route balance.
        // Version 11 to 12: a world without `"land"` has none.
        // Version 12 to 13: a world without `"cityBuildings"` has the
        // city's buildings off and no `"buildings"`; its land keeps growing
        // to the fixed 400 residents and 1,200 jobs a cell (decision 73)
        // until they are turned on, which puts them up then.
        // Version 13 to 14: a station's growth without `"lastService"` or
        // `"lastReached"` has 0 of each until its next midnight measures
        // them, so it raises no building that night.
        // Version 14 to 15: a world without `"transferGroups"` has none,
        // and hands out transfer group IDs from 1.
        // Version 15 to 16: accounts without `"assets"` kept no record of
        // what anything cost: what was built before is on the books at
        // nothing (``GameWorld/unrecordedAssetCount()``), and is never
        // written down or off; there are no capital days or closed years.
        // Version 16 to 17: a world without `"scenario"` has no goals, and a
        // day without `"fareTrips"` had none counted.
        // Version 17 to 18: a world without `"landBlocks"` has its land
        // whole, as every world before had.
        // Version 20 to 21: a world without `"placedBuildings"` has none,
        // and hands out placed building IDs from 1.
        // Later versions add their steps here.
        world = try GameWorld(from: container.superDecoder(forKey: .world), madeBeforeSpacing: version < 5)
    }

    /// Encodes the world in the current version.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.currentVersion, forKey: .saveVersion)
        try container.encode(world, forKey: .world)
    }
}
