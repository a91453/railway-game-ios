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

    /// The scene's world, its clock paused at the moment to show.
    public func make(in language: DisplayLanguage) -> GameWorld {
        switch self {
        case .freight: Self.freightWorld(in: language)
        }
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
