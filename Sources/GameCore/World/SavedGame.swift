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
/// The versions, one file each (decision 910): `SaveFixtures/versions/<N>.md`,
/// what version N added and what a build that reads only the version
/// before does with it. A change that raises ``currentVersion`` adds the
/// next one.
public struct SavedGame: Equatable, Sendable {
    /// The version this build writes.
    public static let currentVersion = 112

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
        // Version 38 to 39: freight without `"buildingMaterials"` has none,
        // and its yards send goods, as every yard did.
        // Version 39 to 40: a world without `"mapExpansion"` owns the
        // whole of its map, and builds anywhere in it as it did.
        // Version 40 to 41: disruptions without `"seed"` have holidays
        // alone, as before.
        // Version 41 to 42: a map bought without `"ridersStep"` asks
        // 100,000 riders and $5 million a tile, as it did.
        // Version 42 to 43: a demand without `"hinterland"` has none, as
        // every one did.
        // Version 43 to 44: a world without `"doorCrowding"` has it off, and
        // every exchange takes as long as it did.
        // Version 44 to 45: a train without `"deadhead"` runs a passenger
        // service, and a line without `"deadheadDistance"` has driven
        // nothing empty, as every one had.
        // Version 45 to 46: a building has no `"books"` and the ledger no
        // subsidiary rows, as none traded.
        // Version 46 to 47: a world without `"tourism"` has no sights, and
        // its passengers are as they were.
        // Version 47 to 48: a world without `"lineAccounts"` has them off,
        // and keeps no line records or station flow, as none did.
        // Version 48 to 49: a world without `"rollingStockEconomics"` has it
        // off, and every train costs and weighs what it did.
        // Version 49 to 50: a world without `"cityRequests"` has none, and
        // its ledger no subsidy rows.
        // Version 50 to 51: an economy without `"unlimitedFunds"` pays for
        // what it builds, as every one did.
        // Version 51 to 52: a world without `"keepLeft"` finds its routes
        // as before, the first of equally short ways by edge number.
        // Version 52 to 53: a world without `"realisticOperation"` plans
        // its legs at their least times; a line without `"dwellSeconds"`
        // dwells a minute; a tally without `"trips"` counted none.
        // Version 53 to 54: a world without `"depot"` flags has no depot,
        // and its lines keep their trains where their trips end.
        // Version 54 to 55: a line without `"code"` has the app's own.
        // Version 55 to 56: a world without `"blockSections"` takes and
        // follows on whole legs, as before.
        // Version 56 to 57: a station without `"commerce"` has no shops, and
        // a station day without `"transferred"` counted no changes.
        // Version 57 to 58: a world without `"curveSpeedLimits"` runs and
        // plans as before, and a run without `"limits"` meets none.
        // Version 58 to 59: a line's single `"depot"` reads as its only
        // depot, and a line with runs had none.
        // Version 59 to 60: a world without `"tripLog"` has kept no trips.
        // Version 60 to 61: nothing to convert; a world from this version
        // may carry a line's `"depots"`.
        // Version 61 to 62: a world without `"realCarLengths"` buys trains
        // of 16 m cars, and a train without `"carPitch"` has them.
        // Version 62 to 63: a world without `"spacingAllowances"` gives its
        // trains theirs as it goes on (at a whole minute it has none).
        // Version 63 to 64: a world without `"realTransfers"` has them off,
        // and a station without `"transferPoints"` has none.
        // Version 64 to 65: a line without `"dispatchPattern"` spaces its
        // trains evenly, as before.
        // Version 65 to 66: a world without `"acquisitions"` bought no
        // real line.
        // Version 66 to 67: a world without `"tidalDemand"` has it off,
        // and a demand without `"homeShare"` follows its kind.
        // Version 67 to 68: accounts without `"dayPass"` sell none.
        // Version 68 to 69: accounts without `"highSpeedFares"` have no
        // fare table, and every high-speed trip pays by the kilometre.
        // Version 69 to 70: a world without `"modeShift"` has it off: no
        // rider takes a scooter or a car instead.
        // Version 70 to 71: a world before version 71 has no park or
        // temple of the company's, and a building without `"look"` has its
        // kind's first, as every one did.
        // Version 71 to 72: a world without `"roads"` has none: no road
        // grows and no station road can be built.
        // Version 72 itself: a tile a blank map's company bought before
        // decision 400's sequel has no roads for its towns; they get them
        // now (``GameWorld/seedBoughtTilesRoads()``, which a save that has
        // them leaves as it is).
        // Version 72 to 73: a world without `"busRoutes"` runs no buses,
        // and a purchase without `"kind"` is a railway's.
        // Version 73 to 74: a world before version 74 has no school,
        // hospital or night market of the company's.
        // Version 74 to 75: every route of a world before version 75 feeds
        // its station, carrying no trips of its own, and roads without
        // `"built"` are all the city's: nothing to turn.
        // Version 75 to 76: every amount was a dollar and is three New
        // Taiwan dollars (decision 499), so each Money the world holds is
        // read times 3; the real high-speed fares, kept at NT$10 to the
        // dollar, become the real table's own New Taiwan dollars
        // (``GameWorld/convertHighSpeedFaresToNewTaiwanDollars()``).
        // Version 76 to 77: every edge of a world before version 77 is
        // ordinary track, as an edge without `"mountain"` reads, and no
        // train is the Alishan Forest Railway's.
        // Version 77 to 78: a station without `"expansion"` is not expanded
        // (decision 506): nothing to turn.
        // Version 78 to 79: a purchase without `"track"` laid none it
        // knows of and a world without `"leftTrack"` has none left
        // (decision 528): nothing to turn.
        // Version 79 to 80: no ring of a world before version 80 has runs,
        // and no run a way (decision 535): nothing to turn.
        // Version 80 or 81 to 82 or 83: a line without `"keepsRight"` keeps
        // left, as every line did (decision 564): nothing to turn.
        // Version 80, 81 or 82 to 83: a world without `"cableways"` has none
        // (decision 574): nothing to turn.
        // Version 83 or earlier to 84: a world without festival `"sites"`, an
        // event's `"festival"` or a scenario event's `"follows"` has none
        // (decision 576): nothing to turn.
        // Version 84 or earlier to 85: a world without `"ferryRoutes"` has
        // none (decision 585): nothing to turn.
        // Version 85 or earlier to 86: a run without `"passes"` calls at
        // every stop (decision 605): nothing to turn.
        // Version 86 or earlier to 87: a world before version 87 has no
        // railway museum (decision 684): nothing to turn.
        // Version 88 or earlier to 89: a world before version 89 has
        // settled no run driven by hand (decision 693): nothing to turn.
        // Version 89 or earlier to 90: a world without `"airports"` has
        // none (decision 695): nothing to turn.
        // Version 90 or earlier to 91: a world without `"coachStops"` has
        // none (decision 706): nothing to turn.
        // Version 91 or earlier to 92: a record of the runs driven by hand
        // without `"assisted"` has none the stopping assist helped with
        // (decision 710): nothing to turn.
        // Version 93 or earlier to 94: a network without `"closedEdges"`
        // has no track closed (decision 716): nothing to turn.
        // Version 94 to 95: a network without `"closingEdges"` has no
        // track being closed (decision 716, continued): nothing to turn.
        // Version 95 or earlier to 97: a world without
        // `"passengerPatience"` has its passengers wait as long as it
        // takes, and a station without `"gaveUp"` had nobody give up
        // (decision 731): nothing to turn.
        // Version 97 or earlier to 98: a demand event without `"opens"` and
        // `"closes"` runs all day (decision 730): nothing to turn.
        // Version 98 or earlier to 99: a world without `"annualTaxes"`
        // pays each day's tax, and accounts without `"incomeTaxPayable"`
        // owe nothing (decision 734): nothing to turn.
        // Version 99 or earlier to 100: accounts without
        // `"houseTaxPayable"` and `"landTaxPayable"` owe no house or land
        // tax (decision 736): nothing to turn.
        // Version 100 or earlier to 101: a route preference without
        // `"alternates"` names one platform (decision 740): nothing to turn.
        // Version 101 or earlier to 102: a world without
        // `"switchInterlocking"` has switches that take no time to throw
        // (decision 756): nothing to turn.
        // Version 102 or earlier to 103: a world without `"airRoutes"` has
        // bought no air route (decision 758): nothing to turn.
        // Version 103 or earlier to 104: demand events without `"venues"`
        // have none, and an event without `"venue"` is held at no venue
        // (decision 768): nothing to turn.
        // Version 104 or earlier to 105: a sight held as a town whose
        // English name ends in "Night Market" is a night market (decision
        // 769, ``GameWorld/reclassifyNightMarkets()`` below).
        // Version 107 or earlier to 108: a world without `"farDemand"`
        // draws its trips as before, and a line bought without
        // `"stateTrack"` keeps its track (decision 828): nothing to turn.
        // Version 108 or earlier to 109: a station without `"chime"` or
        // `"departureMelody"` plays what its place calls for (decision
        // 866): nothing to turn.
        // Version 109 or earlier to 110: a station's melody is one of the
        // first three, which read as before (decision 868): nothing to turn.
        // Later versions add their steps here.
        let worldDecoder = try container.superDecoder(forKey: .world)
        var world = try Money.$decodingScale.withValue(version < 76 ? 3 : 1) {
            try GameWorld(from: worldDecoder, madeBeforeSpacing: version < 5)
        }
        if version == 72 { world.seedBoughtTilesRoads() }
        if version < 76 { world.convertHighSpeedFaresToNewTaiwanDollars() }
        if version < 105 { world.reclassifyNightMarkets() }
        // Version 105 or earlier to 106: the towns that are landmarks,
        // museums or temples take their kind (decision 772).
        if version < 106 { world.reclassifySightKinds() }
        // Version 106 or earlier to 107: the coasts that are harbours take
        // their kind (decision 773).
        if version < 107 { world.reclassifyHarbours() }
        // Version 111 or earlier to 112: the track only guideway trains
        // run on becomes their guideway (decision 951).
        if version < 112 { world.layGuideways() }
        self.world = world
    }

    /// Encodes the world in the current version.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.currentVersion, forKey: .saveVersion)
        try container.encode(world, forKey: .world)
    }
}
