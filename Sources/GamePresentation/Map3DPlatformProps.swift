import GameCore

/// Decision 436: the small things on a platform close up, which a real one
/// has and the 3D map's had not: the stop-position boards (where the head of
/// a train of so many cars stops), the queue lines at a metro train's doors,
/// the lights along the edge, the recycling bins (the commercial kit's
/// `commercialRecycling`).
///
/// Where each stands is worked out here as plain values along the platform's
/// line (metres from its start), so it can be tested on Linux; the builder
/// (``Map3DScene/Builder/addPlatformProps()``) lays them in the closest
/// detail only (decision 267), so they cost nothing farther off.
public enum Map3DPlatformProps {
    /// How the platform's railway runs its trains, which says what marks
    /// it: a Taiwan Railway platform (and any other but a metro's) a board
    /// for each length of train, a metro's the doors too.
    public enum Kind: Equatable, Sendable {
        case railway, metro
    }

    /// A train that calls at the platform: how many cars, each how long
    /// (metres, centre to centre) and with how many doors a side.
    public struct Formation: Hashable, Sendable {
        public let cars: Int
        public let carLength: Float
        public let doors: Int

        public init(cars: Int, carLength: Float, doors: Int) {
            self.cars = cars
            self.carLength = carLength
            self.doors = doors
        }

        public var length: Float { Float(cars) * carLength }
    }

    /// Where the head of a `cars`-car train stops: `along` metres from the
    /// platform's start, for a train running towards its end (`heading` 1)
    /// or its start (-1).
    public struct StopMark: Equatable, Sendable {
        public let along: Float
        public let heading: Float
        public let cars: Int
    }

    /// Taiwan Railway's usual lengths of train when none of the player's
    /// calls (the EMU's 4 and 8, the EMU900's 10, the EMU3000's and the
    /// push-pull Tze-Chiang's 12), 20 m cars.
    static let railwayDefaults = [4, 8, 10, 12].map { Formation(cars: $0, carLength: 20, doors: 2) }
    /// A Taipei Metro high-capacity train when none calls: six of the
    /// catalogue's metro car (type A).
    static let metroDefault: Formation = {
        let spec = TrainTypeCatalog.builtIn.first { $0.code == "A" }
        return Formation(cars: 6, carLength: spec.map { Float($0.carLength) / Float(WorldCoordinate.unitsPerMetre) } ?? 22,
                         doors: spec.map { Int($0.doorsPerCar) } ?? 4)
    }()
    /// At most this many lengths are marked each way, the longest.
    public static let mostMarks = 4

    /// Decision 859: which way the trains calling at a platform stand
    /// there. GameCore stops every train with its head at the platform's
    /// far end the way it travels (``GameWorld/path(from:toStation:length:)``),
    /// so one coming in along the platform's track forward (from the
    /// platform's start to its end) stands at its end, one coming in
    /// backward at its start. Empty when not known: then each train is
    /// taken to stand in the middle, as before.
    public struct Stands: OptionSet, Hashable, Sendable {
        public let rawValue: UInt8
        public init(rawValue: UInt8) { self.rawValue = rawValue }
        public static let forward = Stands(rawValue: 1)
        public static let backward = Stands(rawValue: 2)
    }

    /// Decision 859: where along a platform `length` metres long a train
    /// `train` metres long stands from (its end nearer the platform's
    /// start), for each way in `stands`: at the platform's end coming in
    /// forward, at its start coming in backward; in the middle when
    /// `stands` is empty.
    public static func trainStarts(length: Float, train: Float, stands: Stands) -> [Float] {
        var starts: [Float] = []
        if stands.contains(.backward) { starts.append(0) }
        if stands.contains(.forward) { starts.append(max(0, length - train)) }
        return starts.isEmpty ? [(length - train) / 2] : starts
    }

    /// Where the heads stop: each train stands in the middle of the
    /// platform (a station's stairs and gates are in its middle, and a
    /// shorter train stops there), so a `cars`-car train's head stops half
    /// its length past the middle, each way. Only lengths that fit, the
    /// longest ``mostMarks``; on a metro platform the longest train only.
    /// `formations` empty: ``railwayDefaults`` or ``metroDefault``.
    /// Decision 859: where `stands` says which way the trains come in, the
    /// heads stop where GameCore stops them, at the far end, whatever
    /// their length: one board that way, the longest train's.
    public static func stopMarks(length: Float, formations: [Formation], kind: Kind, stands: Stands = []) -> [StopMark] {
        let calling = formations.filter { $0.cars > 0 && $0.carLength > 0 }
        let fitting = (calling.isEmpty ? (kind == .metro ? [metroDefault] : railwayDefaults) : calling).filter { $0.length <= length }
        // The longest of each count of cars.
        var byCars: [Int: Float] = [:]
        for formation in fitting { byCars[formation.cars] = max(byCars[formation.cars] ?? 0, formation.length) }
        let kept = byCars.sorted { $0.value > $1.value }.prefix(kind == .metro || !stands.isEmpty ? 1 : mostMarks)
        var marks: [StopMark] = []
        if !stands.isEmpty {
            for (cars, _) in kept {
                if stands.contains(.forward) { marks.append(StopMark(along: length, heading: 1, cars: cars)) }
                if stands.contains(.backward) { marks.append(StopMark(along: 0, heading: -1, cars: cars)) }
            }
            return marks.sorted { ($0.along, $0.heading) < ($1.along, $1.heading) }
        }
        for (cars, train) in kept {
            marks.append(StopMark(along: (length + train) / 2, heading: 1, cars: cars))
            marks.append(StopMark(along: (length - train) / 2, heading: -1, cars: cars))
        }
        return marks.sorted { ($0.along, $0.heading) < ($1.along, $1.heading) }
    }

    /// The metro train whose doors are marked: the longest that fits.
    static func markedTrain(length: Float, formations: [Formation]) -> Formation? {
        let calling = formations.filter { $0.cars > 0 && $0.carLength > 0 && $0.doors > 0 }
        return (calling.isEmpty ? [metroDefault] : calling).filter { $0.length <= length }.max { $0.length < $1.length }
    }

    /// The middles of the marked metro train's doors (``markedTrain``),
    /// standing in the platform's middle: each car's doors evenly along it.
    /// None on a railway platform, whose trains' doors differ.
    /// Decision 859: standing where `stands` says (``trainStarts(length:train:stands:)``),
    /// the doors of both ways when trains come in both ways, those of
    /// the two within half a door of each other once.
    public static func doorCentres(length: Float, formations: [Formation], kind: Kind, stands: Stands = []) -> [Float] {
        guard kind == .metro, let train = markedTrain(length: length, formations: formations) else { return [] }
        let doors = Float(train.doors)
        var all: [Float] = []
        for start in trainStarts(length: length, train: train.length, stands: stands) {
            for car in 0..<train.cars {
                for door in 0..<train.doors {
                    let share = (Float(door) + 0.5) / doors
                    all.append(start + train.carLength * (Float(car) + share))
                }
            }
        }
        var centres: [Float] = []
        for centre in all.sorted() {
            if let last = centres.last, centre - last < 0.7 { continue }
            centres.append(centre)
        }
        return centres
    }

    /// The Taipei Metro's lights at the platform edge that flash as a
    /// train comes in: one every ``edgeLightSpacing`` metres, none within
    /// half that of either end. Railway platforms have the canopy's lamps
    /// instead (``canopyLamps(length:)``).
    public static let edgeLightSpacing: Float = 5
    public static func edgeLights(length: Float, kind: Kind) -> [Float] {
        guard kind == .metro, length >= edgeLightSpacing else { return [] }
        let count = Int((length / edgeLightSpacing).rounded(.down))
        let first = (length - Float(count - 1) * edgeLightSpacing) / 2
        return (0..<count).map { first + Float($0) * edgeLightSpacing }
    }

    /// A lamp under the middle of each of the canopy's pieces: the middle
    /// three fifths of the platform in pieces of at most 8 m, as
    /// ``Map3DScene/Builder`` lays the canopy.
    public static func canopyLamps(length: Float) -> [Float] {
        guard length > 0 else { return [] }
        let from = length * 0.2, span = length * 0.6
        let count = max(1, Int((span / 8).rounded(.up))), step = span / Float(count)
        return (0..<count).map { from + step * (Float($0) + 0.5) }
    }

    /// How far apart the recycling bins stand; how far a bin's end keeps
    /// from a stop board, and from a metro door's middle (the door's 1.4 m
    /// and half a metre: it stands at the platform's back, behind the
    /// queue lines, but never across the way off the train).
    public static let binSpacing: Float = 40
    public static let binBoardClearance: Float = 2.5
    public static let binDoorClearance: Float = 1.2
    /// Half a bin's length along the platform (the kit's is 2.6 m long).
    static let binHalfLength: Float = 1.3

    /// The recycling bins' middles: under the canopy (its middle three
    /// fifths), every ``binSpacing`` metres, each moved up to 4 m to keep
    /// clear of the `doors`' middles and the `boards`; one that cannot is
    /// left out.
    public static func bins(length: Float, doors: [Float], boards: [Float]) -> [Float] {
        let from = length * 0.2 + binHalfLength, to = length * 0.8 - binHalfLength
        guard to >= from else { return [] }
        let count = max(1, Int(((to - from) / binSpacing).rounded(.down)) + 1)
        let first = from + (to - from - Float(count - 1) * binSpacing) / 2
        func clear(_ at: Float) -> Bool {
            at >= from && at <= to
                && doors.allSatisfy { abs($0 - at) >= binDoorClearance + binHalfLength }
                && boards.allSatisfy { abs($0 - at) >= binBoardClearance + binHalfLength }
        }
        return (0..<count).compactMap { index in
            let wanted = first + Float(index) * binSpacing
            return stride(from: Float(0), through: 4, by: 0.25).flatMap { [wanted + $0, wanted - $0] }.first(where: clear)
        }
    }

    // MARK: Furniture (decision 874)

    /// A piece of furniture's box on a platform: its middle `along` the
    /// platform and its `length` there, from `near` to `far` metres from
    /// the platform's back towards its track, from `bottom` to `top` over
    /// the platform.
    struct Furniture: Equatable, Sendable {
        let along: Float, length: Float
        let near: Float, far: Float
        let bottom: Float, top: Float
        let colour: UInt32
        /// A sign's face, lit.
        let lit: Bool
    }

    /// A platform at least so deep has furniture at its back (a bench
    /// 0.87 m deep leaves the walk inside the yellow line, as a bin does).
    static let furnishedPlatform: Float = 2.8
    /// How far a bench, machine or board keeps from a bin's end.
    static let furnitureBinClearance: Float = 0.5
    /// How far a hung sign keeps from a canopy's column, and from the
    /// platform's back and edge.
    static let signColumnClearance: Float = 0.6
    static let signInset: Float = 0.3
    /// A sign's top under a canopy (the kit's eaves are 3.2 m up).
    static let signTopUnderCanopy: Float = 3.15
    /// The walk kept between a piece on the floor and the platform's edge.
    static let furnitureWalk: Float = 1.2

    /// Where a canopy's columns stand along a platform `length` long,
    /// the canopy over its middle `share` in pieces of at most 8 m
    /// (``Map3DScene/Builder/addCanopies``).
    static func canopyColumns(length: Float, share: Float) -> [Float] {
        let from = length * (1 - share) / 2, span = length * share
        guard span > 0 else { return [] }
        let count = max(1, Int((span / 8).rounded(.up))), step = span / Float(count)
        return (0...count).map { from + step * Float($0) }
    }

    /// Decision 874: the old version's platform furniture
    /// (``Map3DOldIslandModule``, decision 860) on one platform `length`
    /// long and `depth` deep, half of an `island` or a side platform: the
    /// half of each module that faces its track (`rightHalf`: the
    /// module's right) at its back, every 40 m as under ground, `forward`
    /// when the platform's line runs as the module does. The benches,
    /// machines and boards keep clear of the `bins`; the signs hang only
    /// under a roof (`roof`: the stretch along the platform; `signTop`:
    /// its underside over the platform, `nil` the box's ceiling), clear
    /// of its `columns` and inside the platform's edge; no square column,
    /// which holds a ceiling up. Sizes as in an underground station's
    /// box (`Map3DOldIslandModule.drawnHeadroom`), never wider than the
    /// module's own.
    static func furniture(length: Float, depth: Float, island: Bool, rightHalf: Bool, forward: Bool, bins: [Float],
                          roof: ClosedRange<Float>?, signTop: Float? = nil, columns: [Float] = []) -> [Furniture] {
        typealias Module = Map3DOldIslandModule
        guard island ? 2 * depth >= Map3DUndergroundStations.furnishedIsland : depth >= furnishedPlatform else { return [] }
        let (count, start) = Module.modules(along: length)
        let across = min(1, 2 * depth / Module.width), up = Module.drawnHeadroom / Module.headroom
        var pieces: [Furniture] = []
        for number in 0..<count {
            let base = start + Float(number) * Module.length
            // A piece's parts stand or fall together: a bench's seat and
            // back, a board's post and panel, a sign and its face.
            var piece: (kind: Module.Kind, from: Float)?, kept = false, shift: Float = 0
            for part in Module.parts where part.kind != .column {
                let (left, right) = rightHalf ? (part.left, part.right) : (-part.right, -part.left)
                guard right > 0 else { continue }
                let middle = base + (part.from + part.to) / 2, half = (part.to - part.from) / 2
                let along = forward ? middle : length - middle
                // A new piece where the kind changes or the parts no
                // longer begin together along the module.
                if piece?.kind != part.kind || abs((piece?.from ?? 0) - part.from) > 1 {
                    piece = (part.kind, part.from)
                    shift = 0
                    if part.kind == .sign {
                        let clear = [0, 1, -1, 2, -2].first { move in
                            columns.allSatisfy { abs($0 - along - Float(move)) >= signColumnClearance + half }
                        }
                        kept = clear != nil && (roof.map { $0.contains(along - half - 2) && $0.contains(along + half + 2) } ?? false)
                        shift = Float(clear ?? 0)
                    } else {
                        kept = bins.allSatisfy { abs($0 - along) >= binHalfLength + furnitureBinClearance + half }
                    }
                }
                guard kept else { continue }
                var near = max(left, 0) * across, far = right * across
                var bottom = part.bottom * up, top = part.top * up
                if part.kind == .sign {
                    // Over the platform only, not out over the track; its
                    // face a little shorter than its case, as the module's.
                    let inset = part.glows ? Module.signFaceInset * across : 0
                    near = max(Module.signNear * across, signInset) + inset
                    far = min(Module.signFar * across, depth - signInset) - inset
                    guard far - near >= 1 else { continue }
                    if let signTop {
                        let drop = Module.signTop * up - signTop
                        bottom -= drop
                        top -= drop
                    }
                } else {
                    far = min(far, depth - furnitureWalk)
                    guard far > near else { continue }
                }
                pieces.append(Furniture(along: along + shift, length: part.to - part.from, near: near, far: far, bottom: bottom, top: top,
                                        colour: part.colour, lit: part.glows))
            }
        }
        return pieces
    }

    /// The kind of a station: a metro when its station kit recipe is a
    /// metro's (`system`), else a metro when every train calling there is
    /// one (`metroTrains` of `calling`), else a railway.
    public static func kind(system: String?, calling: Int, metroTrains: Int) -> Kind {
        if let system, metroSystems.contains(system) { return .metro }
        return calling > 0 && metroTrains == calling ? .metro : .railway
    }

    /// The station kit's metro systems (`Map3DStationKitCatalog`): Taipei,
    /// Kaohsiung, Taichung, Taoyuan's.
    static let metroSystems: Set<String> = ["mrt", "krtc", "tmrt", "tymc"]
}

// MARK: - Building

extension Map3DScene.Builder {
    /// Decision 436: the trains that call at each station, by their
    /// length, and how many of them are metro trains.
    func callingFormations() -> [StationID: (formations: [Map3DPlatformProps.Formation], metro: Int)] {
        var calling: [StationID: (formations: [Map3DPlatformProps.Formation], metro: Int)] = [:]
        let unit = Float(WorldCoordinate.unitsPerMetre)
        for train in world.trains {
            let formation = Map3DPlatformProps.Formation(cars: train.cars, carLength: Float(train.carPitch) / unit,
                                                         doors: Int(train.type?.doorsPerCar ?? ServiceDwell.doorsPerCar))
            let isMetro = train.type?.spec.family == .metro
            for station in Set(train.timetable.map(\.station)) {
                calling[station, default: ([], 0)].formations.append(formation)
                if isMetro { calling[station, default: ([], 0)].metro += 1 }
            }
        }
        return calling
    }

    /// Decision 436: on each platform laid (``laidPlatforms``), in the
    /// closest detail only: the stop-position boards at its edge, a metro
    /// platform's queue lines at the doors and the lights along its edge, a
    /// railway platform's lamps under its canopy, and the recycling bins at
    /// its back, clear of the doors and boards.
    mutating func addPlatformProps() {
        let saved = target
        defer { target = saved }
        target = .close
        // Decision 876: the world's trains by station and the screen
        // doors' plan are the same for every part of a scene.
        let calling = shared.calling(in: world) { callingFormations() }
        // Decision 441: none at a depot, where no one boards.
        let depots = Set(world.stations.filter(\.isDepot).map(\.id))
        // Decision 847: the real lines' screen doors.
        let screenDoors = shared.screenDoors(of: world)
        // Decision 860: the underground platforms' too.
        for platform in laidPlatforms + laidUnderground where !depots.contains(platform.station) {
            guard let path = Map3DStreetLife.Path(platform.line) else { continue }
            let trains = calling[platform.station]
            let doorsHere = platform.edge.flatMap {
                screenDoors.doors(edge: $0, station: platform.station, underground: platform.structure == .tunnel)
            }
            // Decision 847: behind screen doors, the line's own trains
            // mark its doors, so the queue lines meet the openings.
            let lineTrains = platform.edge.map { screenDoors.trains(edge: $0, station: platform.station) } ?? []
            let kind = doorsHere != nil ? .metro
                : Map3DPlatformProps.kind(system: stationSystems[platform.station], calling: trains?.formations.count ?? 0,
                                          metroTrains: trains?.metro ?? 0)
            let formations = (doorsHere != nil && !lineTrains.isEmpty ? lineTrains : trains?.formations ?? [])
                .filter { kind == .railway || $0.doors > 0 }
            // Decision 859: where the line's trains stand, at the end
            // they come in towards.
            let stands = platform.edge.map { screenDoors.stands(edge: $0) } ?? []
            let marks = Map3DPlatformProps.stopMarks(length: path.length, formations: formations, kind: kind, stands: stands)
            let doors = Map3DPlatformProps.doorCentres(length: path.length, formations: formations, kind: kind, stands: stands)
            let side: Float = platform.offset >= 0 ? 1 : -1
            // Across the line: the platform's edge by the track, and its back.
            let edge = platform.offset - side * platform.width / 2
            let top = Self.platformHeight
            let canopyShare = Map3DStationKit.canopyShare(world.station(id: platform.station)?.expansion)
            let shellRoofed = shellRoofed
            let name = world.station(id: platform.station)?.name, second = boardSecondNames[platform.station]
            mesh(at: path.at(path.length / 2).point) { mesh in
                func place(_ along: Float, _ across: Float, _ up: Float) -> (point: Map3DPoint, along: Map3DPoint, right: Map3DPoint) {
                    let at = path.at(min(max(along, 0), path.length))
                    return (at.point + at.right * across + Map3DPoint(0, up, 0), at.along, at.right)
                }
                for mark in marks {
                    let at = place(mark.along, edge + side * 0.8, top)
                    Self.addStopBoard(&mesh, foot: at.point, facing: at.along * -mark.heading, cars: mark.cars)
                }
                for door in doors {
                    let at = place(door, edge, top + 0.012)
                    Self.addQueueLines(&mesh, edge: at.point, along: at.along, inward: at.right * side, depth: platform.width)
                }
                for light in Map3DPlatformProps.edgeLights(length: path.length, kind: kind) {
                    let at = place(light, edge + side * 0.12, top + 0.01)
                    let first = mesh.vertices.count
                    Self.addFloorStrip(&mesh, middle: at.point, along: at.along, length: 0.3, width: 0.1, color: Map3DPalette.platformEdge)
                    mesh.makeGlowing(from: first)
                }
                if kind == .railway {
                    for lamp in Map3DPlatformProps.canopyLamps(length: path.length) {
                        // Under the canopy (3.2 m up), over the edge half.
                        let at = place(lamp, platform.offset - side * min(platform.width, 7) / 4, top + 3.0)
                        let first = mesh.vertices.count
                        mesh.addBox(base: at.point, forward: at.along, length: 1.2, width: 0.14, height: 0.08,
                                    top: Map3DPalette.tunnelLamp, side: Map3DPalette.tunnelLamp)
                        mesh.makeGlowing(from: first)
                    }
                }
                if let doorsHere {
                    Self.addScreenDoors(&mesh, path: path, across: edge + side * Map3DScreenDoors.setBack, top: top,
                                        pieces: Map3DScreenDoors.pieces(length: path.length, formations: formations, stands: stands),
                                        doors: doorsHere)
                }
                // The bins at the back, their long side along it; none on
                // a platform too narrow to walk past one.
                let bins = platform.width >= Self.binPlatform
                    ? Map3DPlatformProps.bins(length: path.length, doors: doors, boards: marks.map(\.along)) : []
                for bin in bins {
                    let at = place(bin, platform.offset + side * (platform.width / 2 - 0.55), top)
                    mesh.append(Self.binMesh, at: at.point, forward: at.right * -side)
                }
                // Decision 874: the old version's furniture at its back,
                // as on an underground island (decision 860, which lays
                // its own with its box).
                let under = platform.structure == .tunnel
                let back = platform.offset + side * platform.width / 2
                // Which way the module runs and which half faces this
                // track, by the compass, so an island's two halves agree;
                // under ground, an island's as its box lays it.
                let whole = path.at(path.length).point - path.at(0).point
                let forward = platform.modulesForward ?? (abs(whole.x) >= abs(whole.z) ? whole.x >= 0 : whole.z >= 0)
                // Decision 882: the name boards at its back, facing its track.
                if let name {
                    let columns = under || shellRoofed.contains(platform.station) ? []
                        : Map3DPlatformProps.canopyColumns(length: path.length, share: canopyShare)
                    for board in Map3DPlatformProps.nameBoards(length: path.length, depth: platform.width, island: platform.island,
                                                               forward: forward, bins: bins, columns: columns) {
                        let at = place(board, back, top)
                        Self.addNameBoard(&mesh, foot: at.point, out: at.right * -side, name: name, second: second, underground: under)
                    }
                }
                guard !(under && platform.island) else { return }
                let roof: ClosedRange<Float>? = under ? 0...path.length
                    : shellRoofed.contains(platform.station) ? nil
                    : (path.length * (1 - canopyShare) / 2)...(path.length * (1 + canopyShare) / 2)
                let furniture = Map3DPlatformProps.furniture(
                    length: path.length, depth: platform.width, island: platform.island,
                    rightHalf: (side < 0) == forward, forward: forward, bins: bins, roof: roof,
                    signTop: under ? nil : Map3DPlatformProps.signTopUnderCanopy,
                    columns: under ? [] : Map3DPlatformProps.canopyColumns(length: path.length, share: canopyShare)
                )
                for piece in furniture {
                    let at = place(piece.along, back - side * (piece.near + piece.far) / 2, top + piece.bottom)
                    let first = mesh.vertices.count
                    mesh.addBox(base: at.point, forward: at.along, length: piece.length, width: piece.far - piece.near,
                                height: piece.top - piece.bottom, top: piece.colour, side: piece.colour)
                    if piece.lit { if under { mesh.makeGlowing(from: first) } else { mesh.makeNightLit(from: first) } }
                }
            }
        }
    }

    /// The narrowest platform a bin stands on, metres: a bin 0.85 m deep
    /// at the back still leaves 1.5 m inside the yellow line.
    static let binPlatform: Float = 2.8

    /// The commercial kit's recycling bin (`commercialRecycling`), its
    /// front (+x) facing the track.
    static let binMesh: Map3DMesh = {
        var kit = StationKitBuilder()
        kit.commercial(.commercialRecycling)
        return kit.mesh
    }()

    /// A stop-position board: a white board 1.9 m up on a post, facing
    /// `facing` (towards the cab of the train it is for), the number of
    /// cars on it in navy figures; its back plain.
    static func addStopBoard(_ mesh: inout Map3DMesh, foot: Map3DPoint, facing: Map3DPoint, cars: Int) {
        let out = Map3DPoint(facing.x, 0, facing.z).normalized ?? Map3DPoint(1, 0, 0)
        mesh.addBox(base: foot, forward: out, length: 0.06, width: 0.06, height: 1.9, top: Map3DPalette.rail, side: Map3DPalette.rail)
        let board = foot + Map3DPoint(0, 1.9, 0)
        mesh.addBox(base: board, forward: out, length: 0.04, width: 0.5, height: 0.42, top: Map3DPalette.sidewalk, side: Map3DPalette.sidewalk)
        // The figures, a hand's breadth proud of the face.
        let face = board + out * 0.025 + Map3DPoint(0, 0.21, 0)
        let right = Map3DPoint(-out.z, 0, out.x) * -1 // to the right as seen facing the board
        let digits = String(cars).compactMap { $0.wholeNumberValue }
        let width: Float = 0.15, gap: Float = 0.05
        let total = Float(digits.count) * width + Float(digits.count - 1) * gap
        for (index, digit) in digits.enumerated() {
            let left = -total / 2 + Float(index) * (width + gap)
            for segment in Self.segments(of: digit) {
                let (x0, y0, x1, y1) = segment
                let a = face + right * (left + x0 * width) + Map3DPoint(0, (y0 - 0.5) * 0.3, 0)
                let b = face + right * (left + x1 * width) + Map3DPoint(0, (y0 - 0.5) * 0.3, 0)
                let c = face + right * (left + x1 * width) + Map3DPoint(0, (y1 - 0.5) * 0.3, 0)
                let d = face + right * (left + x0 * width) + Map3DPoint(0, (y1 - 0.5) * 0.3, 0)
                mesh.addQuad(a, b, c, d, color: Map3DPalette.playerRim)
            }
        }
    }

    /// A figure's strokes, as seven segments in a cell 1 wide and 1 tall
    /// (0 its bottom left): each `(x0, y0, x1, y1)`.
    static func segments(of digit: Int) -> [(Float, Float, Float, Float)] {
        let t: Float = 0.2 // stroke, as a share of the cell's width (its height counts double)
        let h = t / 2
        let strokes: [Character: (Float, Float, Float, Float)] = [
            "a": (0, 1 - h, 1, 1), "b": (1 - t, 0.5, 1, 1), "c": (1 - t, 0, 1, 0.5), "d": (0, 0, 1, h),
            "e": (0, 0, t, 0.5), "f": (0, 0.5, t, 1), "g": (0, 0.5 - h / 2, 1, 0.5 + h / 2),
        ]
        let lit = ["abcdef", "bc", "abged", "abgcd", "fgbc", "afgcd", "afgedc", "abc", "abcdefg", "abcdfg"][min(max(digit, 0), 9)]
        return lit.compactMap { strokes[$0] }
    }

    /// The queue lines at a metro door whose middle is at `edge` on the
    /// platform's edge: two lanes each side of the door, the door's own
    /// width kept clear for those getting off, in the edge's yellow, as
    /// the reference's `addPlatformMarkings` lays them (lines 0.69, 1.47
    /// and 2.25 m from the door's middle, 1.1 m long, a line across their
    /// ends).
    static func addQueueLines(_ mesh: inout Map3DMesh, edge: Map3DPoint, along: Map3DPoint, inward: Map3DPoint, depth: Float) {
        let from: Float = 0.7, to = min(1.8, depth - 0.3)
        guard to > from + 0.3 else { return }
        let length = to - from
        for sign: Float in [-1, 1] {
            for offset: Float in [0.69, 1.47, 2.25] {
                let middle = edge + along * (sign * offset) + inward * (from + length / 2)
                addFloorStrip(&mesh, middle: middle, along: inward, length: length, width: 0.05, color: Map3DPalette.platformEdge)
            }
            addFloorStrip(&mesh, middle: edge + along * (sign * 1.47) + inward * to, along: along, length: 1.61, width: 0.05,
                          color: Map3DPalette.platformEdge)
        }
    }

    /// A flat strip on the floor facing up, `length` along level `along`
    /// and `width` across, its middle at `middle`: two triangles.
    static func addFloorStrip(_ mesh: inout Map3DMesh, middle: Map3DPoint, along: Map3DPoint, length: Float, width: Float, color: UInt32) {
        guard let u = Map3DPoint(along.x, 0, along.z).normalized else { return }
        let l = u * (length / 2), w = Map3DPoint(-u.z, 0, u.x) * (width / 2)
        mesh.addQuad(middle - l - w, middle - l + w, middle + l + w, middle + l - w, color: color)
    }
}
