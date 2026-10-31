import GameCore

/// Worlds set up for the game website's screenshots (decision 165), opened
/// only by the Debug app's `-screenshot-scene` launch argument from the
/// screenshot UI test. Each is built from GameCore's own commands, as the
/// demos are, and run on to a moment worth showing; nothing in them is
/// drawn or staged outside the game's rules.
public enum ScreenshotScene: String, CaseIterable, Sendable {
    /// The demo map (``DemoWorld``) with freight: a freight track inside
    /// the ring, a yard at West and at East, industry beyond each, and a
    /// freight line whose train carries goods between them. Run on to the
    /// second morning just after the hour's goods came in, when both yards
    /// hold goods, the train carries a load and the first midnight has left
    /// stations short of building materials.
    case freight

    /// The demo map with two depots, one beyond West and one beyond East,
    /// and Line 1 keeping its trains at the west one (decision 221): the
    /// line panel's depot checklist, for its UI test. The high-speed demo
    /// has depots too, but takes minutes to build on a test runner.
    case depots

    /// Decision 514: the demo map on its second morning with zones in each
    /// outlook the zoning layer marks: by the demo's stations, which grew
    /// last night, schools (which the city builds) and the use the city
    /// wants least (not needed now); round a new station no train serves
    /// yet (waits for its station); and further out than any station
    /// reaches (too far). For the screenshot review of the pull request
    /// that marked them.
    case zoning

    /// Decision 524: the demo map with realistic operation, run on to its
    /// second morning, so each line's card shows its last seven days'
    /// punctuality beside Taiwan Railway's. For the screenshot review of
    /// the pull request that added it.
    case punctuality

    /// The scene's world, its clock paused at the moment to show.
    public func make(in language: DisplayLanguage) -> GameWorld {
        switch self {
        case .freight: Self.freightWorld(in: language)
        case .depots: Self.depotsWorld(in: language)
        case .zoning: Self.zoningWorld(in: language)
        case .punctuality: Self.punctualityWorld(in: language)
        }
    }

    // MARK: - Punctuality

    /// A day and nine hours: the first day settled, trains running.
    static let punctualityRunSeconds: Int64 = 33 * 3_600

    private static func punctualityWorld(in language: DisplayLanguage) -> GameWorld {
        var world = DemoWorld.make(in: language)
        world.setRealisticOperation(true)
        do throws(GameError) {
            // .fast is ten minutes a tick.
            world.setSpeed(.fast)
            try world.advance(ticks: Int(punctualityRunSeconds / 600))
        } catch {
            preconditionFailure("The punctuality screenshot scene no longer builds: \(error)")
        }
        world.setSpeed(.normal)
        world.setSpeed(.paused)
        return world
    }

    // MARK: - Depots

    /// How far beyond West and East, and to the south, each depot stands.
    private static let depotOffset: Int64 = 4 * 1_024

    private static func depotsWorld(in language: DisplayLanguage) -> GameWorld {
        var world = DemoWorld.make(in: language)
        do throws(GameError) {
            guard let line1 = world.lines.first, let westID = line1.stops.first, let eastID = line1.stops.last,
                  let west = world.station(id: westID)?.point, let east = world.station(id: eastID)?.point
            else { throw .unknownLine(LineID(rawValue: 1)) }
            let westDepot = try world.buildStation(
                named: language.text("West Depot", "西機廠"), at: PlanPoint(x: west.x - depotOffset, y: west.y + depotOffset)
            ).id
            let eastDepot = try world.buildStation(
                named: language.text("East Depot", "東機廠"), at: PlanPoint(x: east.x + depotOffset, y: east.y + depotOffset)
            ).id
            try world.setStationDepot(westDepot, to: true)
            try world.setStationDepot(eastDepot, to: true)
            try world.setLineDepots(line1.id, to: [westDepot])
        } catch {
            preconditionFailure("The depots screenshot scene no longer builds: \(error)")
        }
        world.setSpeed(.normal)
        world.setSpeed(.paused)
        return world
    }

    // MARK: - Zoning

    private static func zoningWorld(in language: DisplayLanguage) -> GameWorld {
        var world = DemoWorld.make(in: language)
        do throws(GameError) {
            // Past the first midnight, when the served stations grew.
            world.setSpeed(.fast)
            try world.advance(ticks: Int(freightRunSeconds / 600))
            let row = Int((world.bounds.height / 2) / Land.cellLength)
            let column = Int((world.bounds.width / 2) / Land.cellLength)
            // The use the city wants least, if it has more than it wants.
            let levels = world.cityDemandLevels
            let unwanted = [(Zone.residential, levels.homes), (.commercial, levels.shops), (.office, levels.work)]
                .min { $0.1 < $1.1 }.map(\.0) ?? .residential
            // The town fills the demo's stations' 800 m (some 13 cells), so
            // only its edge is in reach: north of it, out past the reach,
            // the unwanted use; west, schools.
            try world.setZone(unwanted, rows: (row - 20)...(row - 10), columns: (column - 6)...(column + 6))
            try world.setZone(.civic, rows: (row - 6)...(row + 6), columns: (column - 20)...(column - 10))
            // A station 1.5 km east, no train serves yet, zoned round.
            let east = Int64(column + 24) * Land.cellLength + Land.cellLength / 2
            _ = try world.buildStation(
                named: language.text("New Town", "新市鎮"), at: PlanPoint(x: east, y: Int64(row) * Land.cellLength + Land.cellLength / 2)
            )
            try world.setZone(.residential, rows: (row - 4)...(row + 4), columns: (column + 20)...(column + 28))
        } catch {
            preconditionFailure("The zoning screenshot scene no longer builds: \(error)")
        }
        world.setSpeed(.normal)
        world.setSpeed(.paused)
        return world
    }

    /// Decision 522: the zoning drag the zoning scene's screenshot holds
    /// down: a box some 2 km a side round the new station 1.5 km east,
    /// reaching back to the town's edge, so the drag shows cells in reach
    /// and the grey ones past it.
    public static func zoningDrag(in world: GameWorld) -> (from: PlanPoint, to: PlanPoint) {
        let row = Int((world.bounds.height / 2) / Land.cellLength)
        let column = Int((world.bounds.width / 2) / Land.cellLength)
        func middle(_ row: Int, _ column: Int) -> PlanPoint {
            PlanPoint(x: Int64(column) * Land.cellLength + Land.cellLength / 2, y: Int64(row) * Land.cellLength + Land.cellLength / 2)
        }
        return (middle(row - 15, column + 9), middle(row + 15, column + 39))
    }

    // MARK: - Freight

    /// How long the freight scene runs before it is shown: to 08:00:30 on
    /// the second day, past the first midnight's growth and half a minute
    /// after the hour's goods came in. The train clears a yard in minutes
    /// on this short track, so only just after the hour do both yards hold
    /// goods while it carries a load.
    static let freightRunSeconds: Int64 = 32 * 3_600 + 30
    /// The freight track's distance south of Line 1: inside the demo's
    /// inner ring (192 m), under Line 2's viaduct (8 m up), 40 m from Line 1.
    private static let freightOffset: Int64 = 2_560
    /// The industry beyond each yard: a block of cells this many cells
    /// from the middle of the map (1 km), each with ``industryJobs`` jobs,
    /// so each yard takes in some 240 tons at each hour, more than the
    /// train's 160.
    private static let industryDistance = 16
    private static let industryJobs: Int64 = 750

    private static func freightWorld(in language: DisplayLanguage) -> GameWorld {
        var world = DemoWorld.make(in: language)
        do throws(GameError) {
            try addFreight(to: &world, language: language)
            // .fast is ten minutes a tick, .x10 one second.
            world.setSpeed(.fast)
            try world.advance(ticks: Int(freightRunSeconds / 600))
            world.setSpeed(.x10)
            try world.advance(ticks: Int(freightRunSeconds % 600))
        } catch {
            preconditionFailure("The freight screenshot scene no longer builds: \(error)")
        }
        // Paused, to go on at the usual speed (the HUD shows the speed a
        // paused game resumes at).
        world.setSpeed(.normal)
        world.setSpeed(.paused)
        return world
    }

    private static func addFreight(to world: inout GameWorld, language: DisplayLanguage) throws(GameError) {
        let middleRow = Int((world.bounds.height / 2) / Land.cellLength)
        let middleColumn = Int((world.bounds.width / 2) / Land.cellLength)
        // Industry west of West and east of East, on cells the city has not
        // taken, so each yard is the nearest to its own.
        var cells = world.land.cells
        var taken = Set(cells.map { [$0.row, $0.column] })
        for side in [-1, 1] {
            for dr in -2...2 {
                for step in 0..<3 {
                    let row = middleRow + dr, column = middleColumn + side * (industryDistance + step)
                    guard taken.insert([row, column]).inserted else { continue }
                    cells.append(LandCell(row: row, column: column, use: .industrial, residents: 0, jobs: industryJobs))
                }
            }
        }
        try world.setLand(cells)

        // West and East are the demo's first and last stations on Line 1.
        guard let line1 = world.lines.first, let west = line1.stops.first, let east = line1.stops.last else {
            throw .unknownLine(LineID(rawValue: 1))
        }
        let cx = world.bounds.width / 2, cy = world.bounds.height / 2
        let reach: Int64 = 9 * 1_024
        let platform = 4 * Train.carLength
        let from = try world.buildTrackNode(at: WorldCoordinate(x: cx - reach, y: cy + freightOffset))
        let to = try world.buildTrackNode(at: WorldCoordinate(x: cx + reach, y: cy + freightOffset))
        let track = try world.buildTrackEdge(from: from, to: to)
        try world.addTrackPlatform(west, on: track, from: 1_024, to: 1_024 + platform)
        try world.addTrackPlatform(east, on: track, from: 2 * reach - 1_024 - platform, to: 2 * reach - 1_024)
        try world.buildFreightFacility(at: west)
        try world.buildFreightFacility(at: east)

        let line = try world.createLine(named: language.text("Freight Line", "貨運線"), stops: [west, east]).id
        try world.setLineFreight(line, to: true)
        try world.setLineServiceWindow(line, to: .allDay)
        try world.setLineTrainsInService(line, to: TrainsInService(peak: 1, offPeak: 1, low: 1))
        let train = try world.purchaseTrain(named: language.text("Freight Train 1", "貨運列車 1")).id
        try world.setTrainCars(train, to: 4)
        let berth = 1_024 + platform
        try world.placeTrain(train, at: .onEdge(TrackTraversal(edge: track, direction: .forward), offset: berth))
        try world.setTrainContinuation(train, along: [], stoppingAt: berth)
        try world.setTrainMovementRate(train, to: 512)
        try world.assignTrain(train, to: line)
    }
}
