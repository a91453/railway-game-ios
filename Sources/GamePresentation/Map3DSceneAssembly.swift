import GameCore

/// The order a 3D scene is built in: each layer the builder lays, one
/// after the other, from the ground to the player's buildings. Moved as
/// it was out of `Map3DScene.swift` (MAP3D-SCENE-SPLIT).
extension Map3DScene {
    /// Decision 339: the real lines' track laid in the scene `builder`
    /// builds, clear of `snapshot`'s, and their trains on it; `nil` on a
    /// map not of the real world or without `railways`' timetables.
    /// Decision 517 續 (PR 3b): apart, so a scene built again only where
    /// the track changed works them out again as the whole scene does.
    static func realTrains(world: GameWorld, railways: RealRailways?, snapshot: RailwaySnapshot,
                           builder: inout Builder) -> Map3DRealTrains? {
        if let railways, let operations = railways.operations, let frame = RealWorldFrame(world: world) {
            let region = builder.region, margin = Map3DRealTrains.margin * Builder.metre
            // Decision 876: a line's box on the map and its trains are the
            // same whatever the region, so the scene's builds keep them: a
            // line whose box is clear of the region is not read point by
            // point, and its timetable is made into runs once.
            let shared = builder.shared, key = Map3DSharedBuild.RealKey(railways, frame: frame)
            let traffic = RealTrainTraffic(operations: operations, bought: Set(world.acquisitions.map(\.realLine)), mayBeNear: { line, system in
                shared.box(of: line, system: system, key: key, frame: frame)
                    .meets(minX: region.minX - margin, minY: region.minY - margin, maxX: region.maxX + margin, maxY: region.maxY + margin)
            }, made: { line, system in
                shared.trafficLine(line, system: system, key: key, operations: operations)
            }, isNear: { coordinate in
                let at = frame.worldPosition(latitude: coordinate.latitude, longitude: coordinate.longitude)
                return at.x >= region.minX - margin && at.x <= region.maxX + margin && at.y >= region.minY - margin && at.y <= region.maxY + margin
            })
            // Decision 402: the real tracks, clear of the lines the
            // player bought.
            let bought = world.acquisitions.compactMap { acquisition -> (system: String, shape: [RealRailways.Coordinate])? in
                let parts = acquisition.realLine.split(separator: ":", maxSplits: 1).map(String.init)
                guard acquisition.kind == .railway, parts.count == 2, let line = operations.system(id: parts[0])?.lines.first(where: { $0.id == parts[1] }) else { return nil }
                return (parts[0], line.shape)
            }
            return Map3DRealTrains(traffic: traffic, structures: railways.structures, railTracks: railways.tracks,
                                   operations: operations, bought: bought,
                                   frame: frame, snapshot: snapshot, builder: &builder, key: key)
        }
        return nil
    }

    /// Decision 358: the scene of `frame`'s region round its origin (world
    /// units), built as the public initializer builds it. Decision 359:
    /// with `trackCover`, or the network's own when `nil`. Decision 368:
    /// with `detail`, the city in full only within ``detailRadius`` of it.
    /// Decision 455: the city's lots' simplified boxes as instances, or
    /// as vertices without `instancingBoxes` (as before it, for the tests).
    /// Decision 610 續: the real buildings' street fronts only with `facades`.
    /// Review L14-7: `studies`, where a station study can be drawn
    /// (``Builder/studyRegion``).
    init(world: GameWorld, snapshot: RailwaySnapshot?, skyline: CitySkyline?, frame: (region: WorldRegion, originX: Double, originY: Double),
         baseMap: BaseMapTiles?, cityTiles: [CityTileArea], footprints footprintTiles: FootprintTiles? = nil, heights: HeightGrid?,
         landCover: LandCoverGrid? = nil, lineBands: Map3DLineBands?, railways: RealRailways?, temples: RealTemples?, noBuild: RealNoBuildLand? = nil,
         trackCover: Map3DTrackCover? = nil, detail: Map3DPoint? = nil, detailAhead: Map3DPoint? = nil, instancingBoxes: Bool = true, facades: Bool = true,
         studies: WorldRegion? = nil) {
        (region, originX, originY) = frame
        // Where the world lies on the Earth, worked out once for every
        // layer below (MAP3D-ASSEMBLY-TIDY); `nil` on a map not of the
        // real world.
        let worldFrame = RealWorldFrame(world: world)

        var builder = Builder(originX: originX, originY: originY, region: region, world: world, heights: heights)
        builder.detail = detail
        builder.detailAhead = detailAhead
        builder.studyRegion = studies
        builder.state.facades.buildsFacades = facades
        // Decision 876: a part of a scene, built with the scene's track
        // cover, with what the scene's builds worked out before it.
        if let trackCover { builder.shared = trackCover.shared }
        // Decision 811: the land cover round the region, for the ground
        // and the forests' trees.
        if let landCover, let worldFrame { builder.readLandCover(landCover, frame: worldFrame) }
        builder.time("read the land cover")
        // Decision 732: Hong Kong's streets on its map.
        builder.streetLife.region = builder.look.streets
        let snapshot = snapshot ?? world.railwaySnapshot()
        // Decision 737: the ground levelled before anything is laid on it.
        builder.levelGround(under: snapshot)
        builder.time("level the ground under the track")
        // Decision 234: on a real-world map, the base map's water, cover
        // and roads; the ground's own water then gives way to its finer
        // shores.
        var real: Map3DBaseMap?
        if let baseMap, let frame = worldFrame {
            real = Map3DBaseMap(tiles: baseMap, frame: frame, region: region, originX: originX, originY: originY,
                                names: builder.look.streets.hasStreetNameSigns)
            // BRIDGE-LANDMARK-DECK: a landmark bridge's road on its own
            // deck, not the map's bridge too.
            real = real?.leavingOut(builder.landmarkDecks(frame: frame))
            // Decision 834: the motorways held to their grade, their
            // cuttings cut out of the ground laid next.
            builder.state.roadGrade = builder.gradeMotorways(of: real!)
            // Decision 385: the city's low homes and shops along the real
            // roads, and none on the land OpenStreetMap keeps clear.
            builder.state.roadside.streetFrontage = true
            if let noBuild { builder.prepareNoBuild(noBuild, frame: frame) }
        }
        builder.time("read the base map")
        let airfields = real == nil ? nil : noBuild?.airfields
        // Decision 359 (續): the whole network's, so a chunk built apart
        // lays a bore beside another as the whole scene does; decision 375:
        // first, as its trenches are cut out of the ground and what lies
        // on it.
        builder.trackCover = trackCover ?? Map3DTrackCover(snapshot, builder: &builder)
        // Decision 876 (later): once for the scene and the blocks built with its
        // track cover, not again for each block.
        builder.state.underground.undergroundStations = builder.shared.undergroundStations(of: snapshot, originX: originX, originY: originY) {
            Map3DUndergroundStations(snapshot, point: builder.point, cover: builder.trackCover)
        }
        builder.time("track cover")
        // Decision 238: the city twice, in full and simplified for afar.
        let city = skyline ?? CitySkyline(world: world)
        // Decision 720: the ground under the city's lots in their colours,
        // plain where the player's track runs.
        builder.addGround(water: real == nil, lots: city, clearOf: builder.trackCells(snapshot))
        builder.mark("ground")
        drawnGround = builder.groundGrid()
        builder.time("ground grid")
        let taken = real.map { builder.addBaseMap($0) } ?? Builder.TakenGround()
        builder.time("base map")
        // Decision 438: the player's own roads, which the base map has not.
        if real != nil { builder.addOwnRoads(baseMap: baseMap, frame: worldFrame) }
        builder.mark("own roads")
        // Decision 699: the airports' runways, taxiways and aprons, over
        // the base map's ground and roads.
        var runways = Set<ChunkKey>()
        if let airfields, let worldFrame { runways = builder.addAirfields(airfields, frame: worldFrame) }
        builder.mark("airfields")
        let cleared = builder.addTrack(snapshot)
        builder.addTrenches()
        if let lineBands { builder.addLineBands(lineBands, snapshot: snapshot) }
        builder.addPlatforms(snapshot)
        builder.addPortals(snapshot)
        self.trackCover = builder.trackCover
        builder.mark("the player's track and platforms")
        // Decision 339: the real lines' track, clear of the player's, and
        // their trains on it.
        realTrains = Self.realTrains(world: world, railways: railways, snapshot: snapshot, builder: &builder)
        builder.mark("real railways")
        builder.state.realTrains.realTrackLines = realTrains?.shownLanes ?? []
        // Decision 941 (later): the real map's roads crossing the track on
        // the level, the player's and the real lines', at level crossings.
        if real != nil { builder.addRealLevelCrossings() }
        // Decision 407: the viaducts, each pair of tracks on its piers.
        builder.addViaducts()
        builder.mark("viaducts")
        // Decision 370: Taipei 101 and Taipei Main Station, clear of the
        // track; on ground no real building, temple, scene or city lot
        // takes.
        let landmarks = worldFrame.map { builder.addTaipeiLandmarks(frame: $0) } ?? [:]
        // Decision 791: Hong Kong's landmark towers, clear of the track.
        // Decision 1020: the station landmarks over the track that runs
        // through them.
        if let worldFrame { builder.addHongKongLandmarks(frame: worldFrame, snapshot: snapshot) }
        // Decision 879: the earlier Sun Moon Lake's pier, boats, temple
        // and pavilion, where the real ones stand.
        if let worldFrame { builder.addSunMoonLandmarks(frame: worldFrame) }
        // Decision 1033: 西螺大橋 and 大樹舊鐵橋, span by span.
        if let worldFrame { builder.addTrussBridges(frame: worldFrame) }
        // Decision 869: the suspension bridges' towers and cables.
        builder.addSuspensionBridges()
        // Decision 625: the real stations' exterior studies, as landmarks,
        // cut clear of the track.
        let exteriors = worldFrame.map { builder.addStationExteriors(snapshot, frame: $0) } ?? [:]
        // Decision 725: Taipei's temples in their own shape, as landmarks.
        let taipeiTemples = temples.flatMap { temples in worldFrame.map { builder.addTaipeiTemples(temples, frame: $0) } } ?? []
        let landmarkCells = landmarks.values.reduce(into: Set<ChunkKey>()) { $0.formUnion($1) }
            .union(exteriors.values.reduce(into: Set<ChunkKey>()) { $0.formUnion($1) })
            .union(taipeiTemples)
        // Decision 441: the Changhua Roundhouse's turntable; no street
        // furniture or city lot on it, but the real buildings round it stay.
        let turntable = worldFrame.map { builder.addRoundhouseTurntable(frame: $0) } ?? []
        // Decision 321: the stations' canopies and buildings from the
        // station kit, a plaza where a building stands; Taipei's the
        // landmark, where it stands (decision 370).
        // Decision 699: nor does a building stand on a runway.
        let stationCells = builder.addStations(snapshot, frame: worldFrame, shops: false,
                                               drawnElsewhere: landmarks[.taipeiMainStation] == nil ? [] : [.taipei])
        let stations = cleared.union(stationCells).union(runways)
        // MRT-SHELL-CLEAR-OUTLINE: the real buildings are cleared by the
        // runways and what has no outline of its own; the track and the
        // stations' buildings leave out only those they overlap
        // (``onTrack(_:)``, ``underRailway(_:)``). Their cells still
        // keep no city lot.
        let realClear = stationCells.subtracting(builder.state.stations.outlineOnlyCells).union(runways)
        // What the track, the stations, the runways, the landmarks and
        // the turntable take: no prop, bush or forest tree on it.
        let builtOn = stations.union(landmarkCells).union(turntable)
        builder.indexTrackOutline()
        // Decision 263: on a map not of the real world, seeded streets
        // between the lots, clear of the track and the platforms but where
        // they cross it, and of the stations' buildings.
        if real == nil, world.geoAnchor == nil { builder.addSeededStreets(city, clearOf: cleared) }
        builder.mark("landmarks and stations")
        seededStreets = SeededStreetPlan(edges: builder.state.streets.streetEdges)
        stationExteriors = builder.state.exteriors.stationExteriors
        // Decision 322: the shops, clear of the streets.
        builder.addShopStreets()
        // Decision 794: where the winter event's trees and lights go.
        builder.addWinterDecor(frame: worldFrame)
        winterLights = Map3DWinterLights(placements: builder.state.winter.winterDecor)
        // Decision 840: the Santa Claus village's reindeer, clear of its tree.
        builder.addReindeerHerd(frame: worldFrame)
        reindeerHerd = Map3DReindeerHerd(placements: builder.state.reindeer.reindeerHerd)
        freightYards = builder.state.freight.freightYardPlaces
        screenDoors = builder.shared.screenDoors(of: world)
        // Decision 326: the overhead line, its masts clear of the platforms;
        // on a real-world map, none along the real lines without one.
        if let railways, let worldFrame { builder.addRealLines(railways, frame: worldFrame) }
        builder.addOverheadLine()
        builder.mark("overhead line")
        // Decision 436: the platforms' small things, close up.
        // Decision 882: the second names on the platforms' name boards.
        if let railways, let worldFrame {
            builder.state.nameBoards.boardSecondNames = Builder.boardSecondNames(world, railways, worldFrame)
            builder.state.nameBoards.boardSigns = Builder.boardSigns(world, railways, worldFrame)
        }
        // Decision 936: the footbridges and underpass stairs, before the
        // platforms' small things, which stand clear of them.
        builder.addStationCrossings(snapshot)
        builder.addPlatformProps()
        // Decision 244: no street furniture where the track runs (nor
        // where a station's building or a landmark stands).
        // Decision 458: the conifers of the high woods, before the props
        // where the track, a station or a landmark is are taken away.
        builder.addConifers(clearOf: builder.state.realTrains.realTrackCells)
        builder.removeProps(on: builtOn)
        // Decision 458: the bushes on the stations' plazas and the grass
        // beside the line.
        builder.addStationBushes()
        builder.addBushesBesideTrack(cleared.union(builder.state.realTrains.realTrackCells), clearOf: builtOn)
        builder.mark("trees, bushes and platform things")
        // Decision 229 續: the street lights' pools, seen at night.
        builder.addLampPools()
        builder.mark("street lights' pools")
        // Decision 239: on a real-world map, the real buildings round
        // Kaohsiung and Taichung Stations, and no city lot where they
        // stand.
        let frame = real == nil ? nil : worldFrame
        // The cells no real building is laid on, of the tiles' or the
        // footprints', and those no lot of the game's own city is.
        let clearOfReal = realClear.union(landmarkCells)
        let clearOfCity = stations.union(builder.state.realTrains.realTrackCells)
        // Decision 385: the airports' own buildings; decision 389: only
        // with no footprints, which have them.
        func addAirportBuildings() {
            if footprintTiles == nil, let noBuild, let frame { builder.addAirportBuildings(noBuild, frame: frame, clearOf: stations.union(landmarkCells)) }
        }
        var standing = landmarkCells
        // Decision 723: the cells of what is no building of the tiles' or
        // the footprints': the landmarks', then the temples', the kits'.
        var scenes = landmarkCells
        var footprints: Map3DFootprints?
        var beforeFootprints = Set<ChunkKey>(), cityTaken = Set<ChunkKey>(), thinlyBuilt = Set<ChunkKey>()
        // Decision 238: the city twice, in full and then simplified for
        // afar. MAP3D-NEAR-FAR-ONE-LOOP: both by the same calls with the
        // same arguments, each written once, so one is not changed
        // without the other. What stands in the full city alone (the
        // temples, the kits' scenes, the forests' trees) is laid in the
        // first pass, which also works out the cells both keep clear.
        for target in [Builder.Target.near, .far] {
            let full = target == .near
            builder.target = target
            if !full {
                // Decision 455: the city's boxes as instances: the lots',
                // the real buildings' on rectangles and their roofs'; the
                // other real outlines stay vertices.
                builder.instancingBoxes = instancingBoxes
                // Decision 709: each building left out from afar by its
                // own size.
                builder.sizesFar = true
            }
            let tileCells = frame.map { builder.addRealBuildings(cityTiles, frame: $0, clearOf: clearOfReal) } ?? []
            builder.mark("real buildings (city tiles)")
            if full {
                standing.formUnion(tileCells)
                addAirportBuildings()
                // Decision 331: the real temples, on no station or real
                // building.
                if let temples, let worldFrame {
                    let cells = builder.addTemples(temples, frame: worldFrame, clearOf: stations.union(standing))
                    standing.formUnion(cells)
                    scenes.formUnion(cells)
                    builder.target = .near
                }
                builder.mark("temples")
                // Decision 331: the commercial kit's scenes before the big
                // stations, on no real building or temple.
                let commerce = builder.addStationCommerce(clearOf: standing)
                standing.formUnion(commerce)
                scenes.formUnion(commerce)
                builder.mark("station commerce")
                builder.target = .near
                // Decision 331: the park kit's scenes in the real parks, on
                // no station, real building, temple or commercial scene; no
                // city lot on them.
                if let real {
                    let parks = builder.addParks(real, clearOf: stations.union(standing))
                    standing.formUnion(parks)
                    scenes.formUnion(parks)
                    builder.target = .near
                }
                builder.mark("parks")
                // Decision 389: the footprints' buildings, on no station,
                // landmark, real building, temple or kit's scene; no city
                // lot on them.
                if let frame, let tiles = footprintTiles {
                    footprints = Map3DFootprints(tiles: tiles, frame: frame, region: builder.region)
                    // Decision 707: the game's own houses no taller than these.
                    builder.state.lowRise.lowRise = Map3DLowRise(tiles: tiles, frame: frame)
                }
                beforeFootprints = standing
                builder.time("read the footprints")
            }
            if let footprints {
                let cells = builder.addFootprints(footprints, clearOf: clearOfReal, takenBy: beforeFootprints)
                if full { standing.formUnion(cells) }
            }
            builder.mark("real buildings (footprints)")
            if full {
                // Decision 723: the cells the real buildings cover little
                // of, which the houses along the roads are laid on, between
                // them.
                thinlyBuilt = builder.thinlyBuilt(but: scenes.union(taken.whole).union(turntable))
                cityTaken = taken.whole.union(standing).union(turntable)
            } else {
                // After the footprints here, as before: no scene has both,
                // and what each layer added (decision 709) stays as it was.
                addAirportBuildings()
            }
            builder.addCity(city, clearOf: clearOfCity, takenBy: cityTaken, besideRoads: taken.byRoads, thinlyBuilt: thinlyBuilt)
            builder.mark("the game's own city")
            if full {
                // Decision 811: the land cover's forests' trees, on nothing
                // built.
                builder.addWildTrees(clearOf: builtOn.union(standing).union(taken.whole).union(builder.state.realTrains.realTrackCells))
                builder.mark("forest trees")
            }
        }
        builder.sizesFar = false
        builder.instancingBoxes = false
        builder.target = .base
        builder.addPlacedBuildings()
        builder.mark("the player's buildings")
        layers = builder.layers

        chunks = builder.chunks()
        builder.time("chunks")
        steps = builder.steps
        streetLife = builder.streetLife
        levelCrossings = builder.state.streets.crossings
    }
}
