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
/// 19. Festivals (decision 90): a scenario can hold `"events"`, festivals on
///     the same day every year, and the demand events can be of kind
///     `"festival"`. A build that reads only version 18 would drop the
///     festivals, or refuse the kind.
/// 20. Eight land uses (decision 91): land and buildings can be factories,
///     schools and public offices, sights, farms and parks (a park with no
///     one in it), and a station's demand can be a school's or public
///     office's. A build that reads only an earlier version would call such
///     land or demand damaged, so it says the save is newer than it instead.
/// 21. Buildings the player places (decision 92): the world can have
///     `"placedBuildings"` and `"nextPlacedBuildingID"`. A build that reads
///     only an earlier version would drop them, and its next save would
///     lose the player's buildings, so it says the save is newer than it
///     instead.
/// 22. The company's buildings (decision 94): a placed building can have
///     `"residents"`, `"jobs"`, `"buildingCost"` and `"landCost"`; the
///     accounts can have building asset records, days and closed years
///     with `"propertyRevenue"` and `"propertyCost"`, and ledger rows of
///     the day's property. A build that reads only an earlier version
///     would drop who lives in them and what they cost, so it says the save
///     is newer than it instead.
/// 23. Zoning (decision 98): the world can have `"zones"`. A build that
///     reads only an earlier version would drop them, and its next save
///     would lose the player's zones, so it says the save is newer than it
///     instead.
/// 24. Water (decision 105): the world can have `"terrain"`, which of its
///     cells are water. A build that reads only an earlier version would
///     drop it, and its city would spread onto the sea again, so it says the
///     save is newer than it instead.
/// 25. Shore buildings (decision 111): a placed building can be a
///     `"wharf"` or a `"marina"`. A build that reads only an earlier version
///     would call such a building damaged, so it says the save is newer
///     than it instead.
/// 26. Steep slopes (decision 115): the world's `"terrain"` can have
///     `"steep"`. A build that reads only an earlier version would drop
///     them, and its city would spread up the mountains again, so it says
///     the save is newer than it instead.
/// 27. The ground's height (decision 124): the world can have `"ground"`,
///     the heights of the blocks read. A build that reads only an earlier
///     version would drop it, and its next save would lose the ground the
///     track is measured from, so it says the save is newer than it
///     instead.
/// 28. Track over the ground (decision 124): an edge can be
///     `"automatic"`, with the `"sections"` the ground made of it, and a
///     world can have `"ground"` with no block read yet. A build that reads
///     only an earlier version would call such an edge damaged and such a
///     world flat, so it says the save is newer than it instead.
/// 29. Selling the company's buildings (decision 130): the accounts' capital
///     days and closed years can have `"saleProceeds"` and
///     `"saleBookValue"`. A build that reads only an earlier version would
///     drop them, and its statements would lose the cash a sale brought in
///     and the gain or loss it realized, so it says the save is newer than
///     it instead.
/// 30. A line's runs (decision 133): a line can have `"runs"`, the trains of
///     a real timetable it sends out at their times, and `"runDays"`, the
///     day each last ran. A build that reads only an earlier version would
///     drop them and run the line at a headway, so it says the save is
///     newer than it instead. The income tax (decision 131) added
///     `"dailyTax"`, `"incomeTax"` and `"taxCost"` without raising the
///     version; from this version on, a build that reads only an earlier
///     one says a save with them is newer too (decision 134).
/// 31. Demand by distance and the outside connections (decision 137): a
///     world can have `"distanceDemand"` and `"outsideConnections"`. A build
///     that reads only an earlier version would drop them, and the game's
///     short trips would ride and its edge stations bring no one again, so
///     it says the save is newer than it instead.
/// 32. The city's demand (decision 139): a world can have `"cityDemand"`,
///     with the mix its city keeps (`"baseline"`). A build that reads only
///     an earlier version would drop it, and the city would grow without
///     its valves again, so it says the save is newer than it instead.
/// 33. The city's footprints (decision 142): a world can have
///     `"cityFootprints": true`, a city building's square its density's. A
///     build that reads only an earlier version would drop it, and the
///     company's buildings would buy out 40 m squares again, so it says the
///     save is newer than it instead.
/// 34. Buying out by area (decision 146): a world can have
///     `"areaBuyOut": true`, the company's buildings buying out the city's
///     by the ground they cover. A build that reads only an earlier version
///     would drop it, and a real-world map's buildings would buy out the
///     game's squares again, so it says the save is newer than it instead.
/// 35. Real coverage (decision 147): a run of land can have `"coverage"`,
///     how much of each of its cells real buildings cover. A build that
///     reads only an earlier version would drop it, and a real-world map's
///     buy-outs would be reckoned from the cells' densities again, so it
///     says the save is newer than it instead.
/// 36. The steam train (decision 153): a train can have the type
///     `"STEAM"`. A build that reads only an earlier version would call
///     such a save damaged, so it says the save is newer than it instead.
/// 37. Public holidays (decision 154): a world can have `"disruptions"`,
///     the country whose holidays it keeps and how strongly they bite. A
///     build that reads only an earlier version would drop them, and its
///     holidays would raise no demand, so it says the save is newer than it
///     instead.
/// 38. Freight (decision 155): a world can have `"freight"`, its facilities
///     and the cargo on its trains, a line `"freight": true`, and the ledger
///     the `hourlyFreight` rows and `"freightRevenue"` totals. A build that
///     reads only an earlier version would drop them and the cargo would
///     vanish, so it says the save is newer than it instead.
public struct SavedGame: Equatable, Sendable {
    /// The version this build writes.
    public static let currentVersion = 38

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
        // Version 18 to 19: a scenario without `"events"` holds no
        // festivals, and no demand event is a festival.
        // Version 19 to 20: a world before version 20 has only homes, shops
        // and offices, and demands of the four reference kinds, which
        // version 20 reads as before.
        // Version 20 to 21: a world without `"placedBuildings"` has none,
        // and hands out placed building IDs from 1.
        // Version 21 to 22: a placed building without `"residents"`,
        // `"jobs"`, `"buildingCost"` or `"landCost"` is empty and was paid
        // nothing for, and has no asset record: on the books at nothing,
        // as decision 85 keeps what was built before it.
        // Version 22 to 23: a world without `"zones"` has none, and grows
        // as it did.
        // Version 23 to 24: a world without `"terrain"` has no water, and
        // grows and builds as it did.
        // Version 24 to 25: a version 24 world has no wharf or marina,
        // which version 25 reads as before.
        // Version 25 to 26: terrain without `"steep"` has no steep slopes,
        // and grows and builds as it did.
        // Version 26 to 27: a world without `"ground"` has read no ground,
        // and is flat at 0 m as before.
        // Version 27 to 28: a world with `"ground"` has ground, and its
        // track is measured from it; no build before 28 wrote ground with
        // track (the app read none), and no edge was automatic.
        // Version 28 to 29: capital days and closed years without
        // `"saleProceeds"` or `"saleBookValue"` sold no building, and their
        // net profit and investing cash flow read as before.
        // Version 29 to 30: a line without `"runs"` runs at a headway, as
        // every line did.
        // Version 30 to 31: a world without `"distanceDemand"` or
        // `"outsideConnections"` has them off, and its demand is as it was.
        // Version 31 to 32: a world without `"cityDemand"` grows as it did.
        // Version 32 to 33: a world without `"cityFootprints"` keeps its
        // city buildings' 40 m squares.
        // Version 33 to 34: a world without `"areaBuyOut"` buys out by
        // squares, as it did.
        // Version 34 to 35: land without `"coverage"` has none known, and
        // its buy-outs are reckoned from its densities as before.
        // Version 35 to 36: a version 35 world has no steam train, which
        // version 36 reads as before.
        // Version 36 to 37: a world without `"disruptions"` has no
        // holidays, and its demand is as it was.
        // Version 37 to 38: a world without `"freight"` has no freight, and a
        // line without `"freight"` carries passengers, as every line did.
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
