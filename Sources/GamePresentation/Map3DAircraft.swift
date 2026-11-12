import Foundation
import GameCore

// Decision 699: the aircraft on the 3D map of a real-world game. Decision
// 698's four types stand at the airfields' parking positions
// (``RealAirfields``) and land and take off on their runways, as many an
// hour as the game's airports count that day (``AirportDay/landings`` and
// ``AirportDay/takeOffs``, decision 695). They are a picture only: nothing
// of the game's rules reads them, no random number decides them (each is
// worked out from the airport, the day, the hour and its number in it),
// and with Reduce Motion none flies: the parked ones stay.
//
// Each flight stays on the ground as long as the owner's web game's do
// (`Ci/reference_snapshot/lib/flight_planner_panel`: 45 minutes between
// legs); how it flies its approach and its climb is this project's own,
// from the published figures of the types (a 3° glide path, some 70 m/s
// over the threshold).

public enum Map3DAircraft {
    public typealias Kind = Map3DAircraftStudies.Kind

    /// A type's model name. "single": a whole vehicle, for the pack's
    /// baked shade (``Map3DTrainOcclusion``).
    public static func name(_ kind: Kind, far: Bool = false) -> String {
        "aircraft-" + kind.rawValue + "-single" + (far ? "-far" : "")
    }

    /// Every model the 3D map draws (``Map3DModelPack/standard``): each
    /// type near, then far. Its livery colour (the tail, the engines, the
    /// wing tips) is left clear, so each aircraft is tinted its own
    /// (``liveries``).
    public static var drawn: [Map3DModelPack.Model] {
        var made: [Map3DModelPack.Model] = []
        for far in [false, true] {
            for kind in Kind.allCases {
                let study = Map3DAircraftStudies.model(kind, far: far, palette: 0)
                let paint = Map3DAircraftStudies.paints[0]
                let vertices = study.vertices.map { vertex -> Map3DVertex in
                    guard vertex.color == paint else { return vertex }
                    var clear = vertex
                    clear.color &= 0x00FF_FFFF
                    return clear
                }
                made.append(Map3DModelPack.Model(name: name(kind, far: far), vertices: vertices, minimum: study.minimum, maximum: study.maximum))
            }
        }
        // The ground vehicles by a parked aircraft, their lighter models.
        for vehicle in Vehicle.allCases {
            let study = Map3DAirportStudies.model(vehicle.study, far: true)
            made.append(Map3DModelPack.Model(name: name(vehicle), vertices: study.vertices, minimum: study.minimum, maximum: study.maximum))
        }
        return made
    }

    /// The ground vehicles drawn by a parked aircraft, close up.
    public enum Vehicle: String, CaseIterable, Sendable {
        case tug, baggageCart, boardingStairs, fuelTruck

        var study: Map3DAirportStudies.Kind {
            switch self {
            case .tug: .tug
            case .baggageCart: .baggageCart
            case .boardingStairs: .boardingStairs
            case .fuelTruck: .fuelTruck
            }
        }
    }

    public static func name(_ vehicle: Vehicle) -> String {
        "airfield-" + vehicle.rawValue + "-single"
    }

    /// Within this of the eye a parked aircraft has its vehicles, metres.
    public static let vehicleReach: Float = 650

    /// The liveries' colours: plain ones of no airline.
    public static let liveries: [UInt32] = [0x5F8BC0, 0x5E8F86, 0xC65A4E, 0x2F4470, 0xE28A3A, 0x8A6FA8, 0x3F9DB5].map(Map3DColor.rgb)

    /// Within this of the eye an aircraft is drawn whole, metres; within
    /// ``farReach``, its far model; and the most drawn whole.
    public static let nearReach: Float = 900
    public static let farReach: Float = 14_000
    public static let mostNear = 14

    /// A flight's figures by type: its speed over the threshold and at
    /// lift-off (m/s), and the least runway it uses (m).
    static func figures(_ kind: Kind) -> (approach: Double, liftOff: Double, runway: Float) {
        switch kind {
        case .commuter19: (48, 46, 0)
        case .regional70: (58, 56, 1_000)
        case .narrowJet: (70, 75, 1_800)
        case .wideJet: (74, 82, 2_500)
        }
    }

    /// The glide path, 3°, and the climb, 9°.
    static let glide = tan(3.0 * Double.pi / 180)
    static let climb = tan(9.0 * Double.pi / 180)
    /// How far out a landing aircraft is first drawn and a leaving one
    /// last, metres from the runway.
    static let seenFrom = 7_000.0
    /// Braking after touchdown and gathering speed on the roll, m/s².
    static let braking = 1.9
    static let thrust = 2.3
    /// The speed it rolls off the runway at, m/s, and how long it is on
    /// the ground between landing and leaving (the reference's 45 minutes).
    static let taxiSpeed = 9.0
    public static let turnaround = 2_700.0
    /// Pushed back from its stand at this speed, m/s, and how long it
    /// stands after, turning the way it will go.
    static let pushSpeed = 2.0
    static let pushPause = 40.0

    /// The landings and take-offs of each of a world's airports in each
    /// hour of a day, worked out once a day (``Map3DAircraft/Laid/frame``
    /// reads it every frame).
    public struct Traffic: Sendable {
        public let day: Int64
        /// By airport (``GameWorld/airports``' order), hour 0 first.
        public let landings: [[Int]]
        public let takeOffs: [[Int]]

        public init(world: GameWorld) {
            day = GameDate.floorDivide(world.clock.now.seconds, GameTime.secondsPerDay)
            let days = world.airportDays()
            landings = days.map { $0.landings.map(Int.init) }
            takeOffs = days.map { $0.takeOffs.map(Int.init) }
        }

        public init(day: Int64, landings: [[Int]], takeOffs: [[Int]]) {
            self.day = day
            self.landings = landings
            self.takeOffs = takeOffs
        }
    }

    /// An aircraft to draw: where its middle is on the ground under it,
    /// how high it is over that, the level way it points, its nose's pitch
    /// up (radians), its type and its livery.
    public struct Drawn: Sendable {
        public let ground: Map3DPoint
        public let height: Float
        public let forward: Map3DPoint
        public let pitch: Float
        public let kind: Kind
        public let livery: Int
        /// Whether it is one landing or leaving, not a parked one.
        public let flying: Bool
        /// A parked one's stand: its number in its airfield (which picks
        /// the vehicles by it), and whether a jet bridge reaches it.
        public var stand: Int?
        public var bridged = false
    }

    /// The airfields of a scene, laid for the aircraft drawn each frame.
    public struct Laid: Sendable {
        struct Stand: Sendable {
            let nose: Map3DPoint
            let forward: Map3DPoint
            /// The widest wings that fit beside its neighbours, metres.
            let room: Float
            /// Whether a jet bridge ends by it.
            var bridged = false
            /// The taxiways' point it is reached from (``Field/nodes``),
            /// `nil` when none is near.
            var node: Int?
        }

        struct Runway: Sendable {
            let a: Map3DPoint
            let b: Map3DPoint
            let length: Float
        }

        /// Where a taxiway meets a runway: the taxiways' point, and how
        /// far along the runway from its `a` it is, metres.
        struct Link: Sendable {
            let runway: Int
            let node: Int
            let along: Float
            /// From each of the taxiways' points, the next on the shortest
            /// way to this one; −1 from a point with no way to it.
            let next: [Int32]
        }

        struct Field: Sendable {
            let seed: Int32
            /// The world's airports that are this airfield, by their place
            /// in ``GameWorld/airports``.
            let airports: [Int]
            var stands: [Stand]
            /// The longest first.
            let runways: [Runway]
            /// The share of its aircraft that are wide-bodied, and
            /// propeller-driven; the rest narrow-bodied jets.
            let wide: Float
            let propeller: Float
            /// The taxiways' points, and where they meet the runways.
            var nodes: [Map3DPoint] = []
            var links: [Link] = []
            /// The stands the flights turn round at, in the order they are
            /// given out; the others keep an aircraft all day.
            var rotation: [Int] = []
        }

        let fields: [Field]
        public var isEmpty: Bool { fields.isEmpty }

        init(fields: [Field]) {
            self.fields = fields
        }

        /// `airfields` in `scene` of `world`: every airfield with a runway
        /// within the map.
        public init(world: GameWorld, scene: Map3DScene, airfields: RealAirfields) {
            guard let frame = RealWorldFrame(world: world) else {
                fields = []
                return
            }
            func place(_ point: RealAirfields.Point) -> Map3DPoint? {
                let at = frame.worldPosition(latitude: point.latitude, longitude: point.longitude)
                guard at.x >= 0, at.y >= 0, at.x < Double(world.bounds.width), at.y < Double(world.bounds.height) else { return nil }
                let flat = scene.point(worldX: at.x, worldY: at.y, height: 0)
                return Map3DPoint(flat.x, scene.drawnGround.height(x: flat.x, z: flat.z, world: world), flat.z)
            }
            var made: [Field] = []
            for (number, field) in airfields.fields.enumerated() {
                var runways: [Runway] = []
                for runway in field.runways {
                    guard let first = runway.line.first, let last = runway.line.last, let a = place(first), let b = place(last) else { continue }
                    let length = Map3DPoint(b.x - a.x, 0, b.z - a.z).length
                    if length > 300 { runways.append(Runway(a: a, b: b, length: length)) }
                }
                guard !runways.isEmpty else { continue }
                runways.sort { $0.length > $1.length }
                let noses = field.stands.map { place($0.nose) }
                var stands: [Stand] = []
                for (index, stand) in field.stands.enumerated() {
                    guard let nose = noses[index] else { continue }
                    var forward: Map3DPoint
                    if let heading = stand.heading {
                        let way = Map3DScene.Builder.direction(degrees: heading)
                        forward = Map3DPoint(Float(way.x), 0, Float(way.z))
                    } else {
                        // Nose in, away from the nearest runway.
                        forward = Self.away(from: runways, at: nose)
                    }
                    var room: Float = 80
                    for (other, place) in noses.enumerated() where other != index {
                        if let place { room = min(room, Map3DPoint(place.x - nose.x, 0, place.z - nose.z).length) }
                    }
                    let bridged = field.bridges.contains { bridge in
                        place(bridge.to).map { Map3DPoint($0.x - nose.x, 0, $0.z - nose.z).length < 35 } ?? false
                    }
                    stands.append(Stand(nose: nose, forward: forward, room: room - 3, bridged: bridged))
                }
                // The game's airports within 4 km of the airfield's middle.
                var airports: [Int] = []
                var passengers: Int64 = 0, flights: Int64 = 0
                if let middle = place(field.at) {
                    for (index, airport) in world.airports.enumerated() {
                        let at = scene.point(worldX: Double(airport.point.x), worldY: Double(airport.point.y), height: 0)
                        if Map3DPoint(at.x - middle.x, 0, at.z - middle.z).length < 4_000 {
                            airports.append(index)
                            passengers += airport.dailyPassengers
                            flights += airport.dailyFlights
                        }
                    }
                }
                var wide: Float = 0, propeller: Float = runways[0].length < 1_700 ? 1 : 0.6
                if flights > 0 {
                    let each = Float(passengers) / Float(flights)
                    wide = min(0.5, max(0, (each - 100) / 200))
                    propeller = each > 150 ? 0 : 0.35
                }
                var laid = Field(seed: Int32(truncatingIfNeeded: number &* 7_919 &+ 17), airports: airports, stands: stands, runways: runways,
                                 wide: wide, propeller: propeller)
                laid.layTaxiways(field.taxiways.map { $0.line.compactMap(place) })
                made.append(laid)
            }
            fields = made
        }

        /// The level way from the nearest of `runways` to `point`.
        static func away(from runways: [Runway], at point: Map3DPoint) -> Map3DPoint {
            var best: (distance: Float, way: Map3DPoint)?
            for runway in runways {
                let along = Map3DPoint(runway.b.x - runway.a.x, 0, runway.b.z - runway.a.z)
                let t = min(1, max(0, Map3DPoint(point.x - runway.a.x, 0, point.z - runway.a.z).dot(along) / (runway.length * runway.length)))
                let foot = Map3DPoint(runway.a.x, 0, runway.a.z) + along * t
                let off = Map3DPoint(point.x - foot.x, 0, point.z - foot.z)
                if best.map({ off.length < $0.distance }) ?? true, let way = off.normalized { best = (off.length, way) }
            }
            return best?.way ?? Map3DPoint(1, 0, 0)
        }

        /// The type of an aircraft of `field`, picked by `share` (0–1)
        /// among those `runway` metres of runway and `room` metres of
        /// wingspan take.
        static func kind(_ field: Field, share: Float, runway: Float, room: Float = .infinity) -> Kind {
            var kind: Kind
            if share < field.wide {
                kind = .wideJet
            } else if share > 1 - field.propeller {
                kind = share > 1 - field.propeller * 0.25 && field.wide == 0 ? .commuter19 : .regional70
            } else {
                kind = .narrowJet
            }
            // The next smaller, until it fits.
            let smaller: [Kind: Kind] = [.wideJet: .narrowJet, .narrowJet: .regional70, .regional70: .commuter19]
            while let next = smaller[kind],
                  Map3DAircraft.figures(kind).runway > runway || Map3DAircraftStudies.dimensions(kind).wingspan > room {
                kind = next
            }
            return kind
        }

        /// A flight of a field: when it touches down or starts its roll
        /// (game seconds), which runway, its type and livery, and the
        /// stand it turns round at (`nil` at a field whose stands the
        /// taxiways do not reach: it is seen on the runway and in the air
        /// only).
        struct Flight {
            let time: Double
            let landing: Bool
            let runway: Int
            let kind: Kind
            let livery: Int
            var stand: Int?
        }

        /// The flights of `field` whose runway time falls in hour `hour`
        /// of day `day`, `traffic` saying how many: spread evenly over the
        /// hour, the take-offs between the landings and never within 75
        /// seconds of one on the same runway. Each takes the next stand of
        /// the field's rotation, so none is given twice within an hour or
        /// two, and is of a type that fits it.
        static func flights(of field: Field, day: Int64, hour: Int, traffic: Traffic) -> [Flight] {
            var landings = 0, takeOffs = 0
            for airport in field.airports where traffic.landings.indices.contains(airport) && traffic.landings[airport].indices.contains(hour) {
                landings += traffic.landings[airport][hour]
                takeOffs += traffic.takeOffs[airport][hour]
            }
            guard landings + takeOffs > 0 else { return [] }
            let start = Double(day * GameTime.secondsPerDay) + Double(hour) * 3_600
            let hours = day &* 24 &+ Int64(hour)
            let salt = Int32(truncatingIfNeeded: hours)
            // Two runways side by side share the flights.
            let pair = field.runways.count > 1 && field.runways[1].length > field.runways[0].length * 0.7 ? 2 : 1
            // The rotation: each hour has `slots` places in it.
            // A third of the stands an hour, so none is given again while
            // its aircraft is still there; a flight past them has none.
            let slots = min(128, field.rotation.count / 3)
            func stand(_ slot: Int) -> Int? {
                guard !field.rotation.isEmpty, slot < slots else { return nil }
                let place = (hours &* Int64(slots) &+ Int64(slot)) % Int64(field.rotation.count)
                return field.rotation[Int((place + Int64(field.rotation.count)) % Int64(field.rotation.count))]
            }
            func flight(_ index: Int, landing: Bool, time: Double, runway: Int) -> Flight {
                let r = { (n: Int32) in map3DRandom(field.seed, salt, salt: Int32(index) &* 8 &+ (landing ? 0 : 4) &+ n) }
                let stand = stand(index * 2 + (landing ? 0 : 1))
                return Flight(time: time, landing: landing, runway: runway,
                              kind: kind(field, share: r(0), runway: field.runways[runway].length, room: stand.map { field.stands[$0].room } ?? .infinity),
                              livery: Int(r(1) * Float(Map3DAircraft.liveries.count)) % Map3DAircraft.liveries.count, stand: stand)
            }
            var flights: [Flight] = []
            for index in 0..<landings {
                flights.append(flight(index, landing: true, time: start + (Double(index) + 0.5) * 3_600 / Double(landings), runway: index % pair))
            }
            let touchdowns = flights
            for index in 0..<takeOffs {
                let runway = (index + 1) % pair
                var time = start + (Double(index) + 0.25) * 3_600 / Double(takeOffs)
                while touchdowns.contains(where: { $0.runway == runway && abs($0.time - time) < 75 }) { time += 80 }
                flights.append(flight(index, landing: false, time: time, runway: runway))
            }
            return flights
        }

        /// Whether the airfields land towards the north-east on game day
        /// `day`: October to March, into the winter monsoon; towards the
        /// south-west the rest of the year.
        static func landsNorthEast(day: Int64) -> Bool {
            let month = GameDate(day: day).month
            return month >= 10 || month <= 3
        }

        /// `flight` on `field` at game second `second`, or `nil` before it
        /// is seen or after it has gone: in the air, on the runway, and
        /// with a stand the taxiways reach, taxiing to it and standing at
        /// it for ``Map3DAircraft/turnaround`` after landing, or standing
        /// at it for as long, pushed back and taxiing out before leaving.
        static func pose(of flight: Flight, on field: Field, second: Double, northEast: Bool) -> Drawn? {
            let runway = field.runways[flight.runway]
            var from = runway.a, to = runway.b, turned = false
            // x east, z south: north-east is +x, −z.
            let along = Map3DPoint(to.x - from.x, 0, to.z - from.z)
            if (along.x - along.z > 0) != northEast {
                swap(&from, &to)
                turned = true
            }
            guard let forward = Map3DPoint(to.x - from.x, 0, to.z - from.z).normalized else { return nil }
            let length = Double(runway.length), figures = Map3DAircraft.figures(flight.kind)
            let t = second - flight.time
            // On the runway `s` metres from the end it starts at, on the
            // runway's own ground, held level past its ends.
            func onRunway(_ s: Double, height: Double = 0, pitch: Double = 0, backwards: Bool = false) -> Drawn {
                let share = Float(min(1, max(0, s / length)))
                let ground = Map3DPoint(from.x + forward.x * Float(s), from.y + (to.y - from.y) * share, from.z + forward.z * Float(s))
                return Drawn(ground: ground, height: Float(height), forward: backwards ? forward * -1 : forward, pitch: Float(pitch),
                             kind: flight.kind, livery: flight.livery, flying: true)
            }
            // The taxiways' meetings with this runway, measured the way it
            // is used.
            func links() -> [(link: Link, s: Double)] {
                field.links.filter { $0.runway == flight.runway }.map { ($0, turned ? length - Double($0.along) : Double($0.along)) }
            }
            let stand = flight.stand.flatMap { index in field.stands[index].node == nil ? nil : (index, field.stands[index]) }
            if flight.landing {
                let aim = min(400, length * 0.14), speed = figures.approach
                if t < 0 {
                    let out = -t * speed
                    guard out < Map3DAircraft.seenFrom else { return nil }
                    // The flare: the last 200 m level out.
                    return onRunway(aim - out, height: out > 200 ? out * Map3DAircraft.glide : out * out / 200 * Map3DAircraft.glide,
                                    pitch: out > 200 ? 0.05 : 0.05 + 0.04 * (1 - out / 200))
                }
                let stop = (speed - Map3DAircraft.taxiSpeed) / Map3DAircraft.braking
                if t < stop { return onRunway(aim + speed * t - Map3DAircraft.braking * t * t / 2, pitch: max(0, 0.09 * (1 - t / 4))) }
                let slowed = aim + speed * stop - Map3DAircraft.braking * stop * stop / 2
                // Off by the first taxiway past where it has slowed, and
                // along the taxiways to its stand.
                let exits = links().filter { $0.s > slowed + 20 && $0.link.next.indices.contains(stand?.1.node ?? -1) }.sorted { $0.s < $1.s }
                guard let (index, stand) = stand, let node = stand.node,
                      let exit = exits.first(where: { $0.link.next[node] >= 0 || $0.link.node == node }) else {
                    // No way to a stand: gone by the runway's end.
                    let s = slowed + Map3DAircraft.taxiSpeed * (t - stop)
                    return s < length - 60 ? onRunway(s) : nil
                }
                // It turns off from 20 m before the taxiway.
                let rolled = (exit.s - 20 - slowed) / Map3DAircraft.taxiSpeed
                if t < stop + rolled { return onRunway(slowed + Map3DAircraft.taxiSpeed * (t - stop)) }
                // From the runway's middle line to the exit's point, along
                // the taxiways to the stand's point, and in to the stand.
                var path = [onRunway(exit.s - 20).ground, onRunway(exit.s).ground] + field.way(from: node, to: exit.link).reversed()
                let size = Map3DAircraftStudies.dimensions(flight.kind)
                let parked = stand.nose - stand.forward * (size.length / 2)
                path.append(parked)
                let travelled = Map3DAircraft.taxiSpeed * (t - stop - rolled)
                let total = Self.length(of: path)
                if travelled < total {
                    let at = Self.point(on: path, at: travelled)
                    return Drawn(ground: at.point, height: 0, forward: at.forward, pitch: 0, kind: flight.kind, livery: flight.livery, flying: true)
                }
                guard travelled < total + Map3DAircraft.turnaround * Map3DAircraft.taxiSpeed else { return nil }
                return Drawn(ground: parked, height: 0, forward: stand.forward, pitch: 0, kind: flight.kind, livery: flight.livery, flying: false,
                             stand: index, bridged: stand.bridged)
            }
            // A take-off: it rolls from where it lined up, `start` metres
            // along; with a stand, from the taxiway nearest the runway's
            // start.
            var start = min(70, length * 0.04)
            let roll = figures.liftOff / Map3DAircraft.thrust
            var entry: (link: Link, s: Double)?
            if let (_, stand) = stand, let node = stand.node {
                entry = links().filter { $0.s < length * 0.5 && $0.link.next.indices.contains(node) && ($0.link.next[node] >= 0 || $0.link.node == node) }
                    .min { $0.s < $1.s }
                // It lines up 25 m past the taxiway.
                if let entry { start = max(start, min(entry.s, length - Double(figures.runway) * 0.6)) + 25 }
            }
            if t > 0 {
                if t < roll { return onRunway(start + Map3DAircraft.thrust * t * t / 2, pitch: t > roll - 3 ? 0.07 * (t - (roll - 3)) : 0) }
                let up = (t - roll) * (figures.liftOff + 8)
                guard up < Map3DAircraft.seenFrom else { return nil }
                return onRunway(start + Map3DAircraft.thrust * roll * roll / 2 + up, height: up * Map3DAircraft.climb, pitch: 0.21)
            }
            // It waits lined up for 25 seconds.
            if t > -25 { return onRunway(start) }
            guard let (index, stand) = stand, let node = stand.node, let entry else { return nil }
            let size = Map3DAircraftStudies.dimensions(flight.kind)
            let parked = stand.nose - stand.forward * (size.length / 2)
            // Backwards in time from the line-up: along the runway from the
            // taxiway, along the taxiways from the stand's point, a pause,
            // and the push back from the stand.
            let path = field.way(from: node, to: entry.link) + [onRunway(entry.s).ground, onRunway(start).ground]
            let taxi = Self.length(of: path) / Map3DAircraft.taxiSpeed
            let push = Double((field.nodes[node] - parked).length) / Map3DAircraft.pushSpeed
            var before = -25 - t
            if before < taxi {
                let at = Self.point(on: path, at: (taxi - before) * Map3DAircraft.taxiSpeed)
                return Drawn(ground: at.point, height: 0, forward: at.forward, pitch: 0, kind: flight.kind, livery: flight.livery, flying: true)
            }
            before -= taxi
            // Pushed back tail first, then turned the way it will go.
            let out = Map3DPoint(field.nodes[node].x - parked.x, 0, field.nodes[node].z - parked.z).normalized ?? stand.forward * -1
            if before < Map3DAircraft.pushPause {
                let onward = path.count > 1 ? Self.point(on: path, at: 0).forward : out
                let turn = Float(before / Map3DAircraft.pushPause)
                let facing = (onward * (1 - turn) + out * -turn).normalized ?? onward
                return Drawn(ground: field.nodes[node], height: 0, forward: facing, pitch: 0, kind: flight.kind, livery: flight.livery, flying: true)
            }
            before -= Map3DAircraft.pushPause
            if before < push {
                let share = Float(before / push)
                let facing = (out * -1 * (1 - share) + stand.forward * share).normalized ?? stand.forward
                return Drawn(ground: field.nodes[node] + (parked - field.nodes[node]) * share, height: 0, forward: facing, pitch: 0, kind: flight.kind,
                             livery: flight.livery, flying: true)
            }
            guard before - push < Map3DAircraft.turnaround else { return nil }
            return Drawn(ground: parked, height: 0, forward: stand.forward, pitch: 0, kind: flight.kind, livery: flight.livery, flying: false,
                         stand: index, bridged: stand.bridged)
        }

        /// How long the level line `path` is, metres.
        static func length(of path: [Map3DPoint]) -> Double {
            zip(path, path.dropFirst()).reduce(0) { $0 + Double(Map3DPoint($1.1.x - $1.0.x, 0, $1.1.z - $1.0.z).length) }
        }

        /// The point `distance` metres along `path` and the way it runs
        /// there, turning over the 16 m round a corner.
        static func point(on path: [Map3DPoint], at distance: Double) -> (point: Map3DPoint, forward: Map3DPoint) {
            func plain(_ distance: Double) -> Map3DPoint {
                var left = Float(max(0, distance))
                for (a, b) in zip(path, path.dropFirst()) {
                    let step = Map3DPoint(b.x - a.x, 0, b.z - a.z).length
                    if left <= step, step > 0 { return a + (b - a) * (left / step) }
                    left -= step
                }
                return path[path.count - 1]
            }
            let total = length(of: path), at = plain(distance)
            let behind = plain(max(0, distance - 8)), ahead = plain(min(total, distance + 8))
            return (at, Map3DPoint(ahead.x - behind.x, 0, ahead.z - behind.z).normalized ?? Map3DPoint(1, 0, 0))
        }

        /// The flights seen about game second `second`: those whose runway
        /// time is within an hour and a half of it.
        func flights(of field: Field, second: Double, traffic: Traffic) -> [Flight] {
            let day = Int64((second / Double(GameTime.secondsPerDay)).rounded(.down))
            let hour = Int((second - Double(day * GameTime.secondsPerDay)) / 3_600)
            var flights: [Flight] = []
            for offset in -2...2 {
                let at = hour + offset
                // The hours next to midnight take today's numbers.
                flights += Self.flights(of: field, day: at < 0 ? day - 1 : (at > 23 ? day + 1 : day), hour: (at + 24) % 24, traffic: traffic)
                    .filter { abs($0.time - second) < 5_400 }
            }
            return flights
        }

        /// The aircraft at game second `second` (since the game began):
        /// those parked at the stands, and with `traffic` and not `still`
        /// those landing, leaving and taxiing. With `still` (Reduce
        /// Motion) none moves: the flights' aircraft stand at their stands
        /// for their time there, and that is all.
        public func aircraft(second: Double, traffic: Traffic?, still: Bool = false) -> [Drawn] {
            let day = Int64((second / Double(GameTime.secondsPerDay)).rounded(.down))
            let northEast = Self.landsNorthEast(day: day)
            var drawn: [Drawn] = []
            for field in fields {
                // Parked all day: most of the stands no flight turns round
                // at.
                let salt = Int32(truncatingIfNeeded: day)
                let turning = traffic == nil || field.airports.isEmpty ? [] : Set(field.rotation)
                for (index, stand) in field.stands.enumerated() where !turning.contains(index) {
                    let r = { (n: Int32) in map3DRandom(field.seed &+ 101, Int32(index), salt: salt &* 4 &+ n) }
                    guard r(0) < 0.85, stand.room > 18 else { continue }
                    let kind = Self.kind(field, share: r(1), runway: field.runways[0].length, room: stand.room)
                    let length = Map3DAircraftStudies.dimensions(kind).length
                    drawn.append(Drawn(ground: stand.nose - stand.forward * (length / 2), height: 0, forward: stand.forward, pitch: 0, kind: kind,
                                       livery: Int(r(2) * Float(Map3DAircraft.liveries.count)) % Map3DAircraft.liveries.count, flying: false,
                                       stand: index, bridged: stand.bridged))
                }
                guard let traffic, !field.airports.isEmpty else { continue }
                for flight in flights(of: field, second: second, traffic: traffic) {
                    guard let pose = Self.pose(of: flight, on: field, second: second, northEast: northEast), !still || !pose.flying else { continue }
                    drawn.append(pose)
                }
            }
            return drawn
        }

        /// The aircraft added to `frame`, seen from `eye`, with `pack`'s
        /// models: whole close up, their far models from farther, a soft
        /// shadow under each, and close up the vehicles by a parked one.
        public func add(to frame: inout Map3DTrains.Frame, pack: Map3DModelPack, second: Double, traffic: Traffic?, eye: Map3DPoint,
                        reach: Float = 1, still: Bool = false) {
            guard !fields.isEmpty else { return }
            var models: [Kind: (near: Int, far: Int)] = [:]
            for kind in Kind.allCases {
                guard let near = pack.index(of: Map3DAircraft.name(kind)), let far = pack.index(of: Map3DAircraft.name(kind, far: true)) else { return }
                models[kind] = (near, far)
            }
            var seen: [(distance: Float, aircraft: Drawn)] = []
            for aircraft in aircraft(second: second, traffic: traffic, still: still) {
                let distance = (aircraft.ground + Map3DPoint(0, aircraft.height, 0) - eye).length
                if distance < Map3DAircraft.farReach { seen.append((distance, aircraft)) }
            }
            seen.sort { $0.distance < $1.distance }
            let vehicles = Dictionary(uniqueKeysWithValues: Vehicle.allCases.compactMap { vehicle in
                pack.index(of: Map3DAircraft.name(vehicle)).map { (vehicle, $0) }
            })
            var whole = 0
            for (distance, aircraft) in seen {
                if distance < Map3DAircraft.vehicleReach * reach, let stand = aircraft.stand {
                    for (vehicle, at, forward) in Map3DAircraft.vehicles(by: aircraft, stand: stand) {
                        guard let model = vehicles[vehicle] else { continue }
                        let foot = at + Map3DPoint(0, Map3DScene.Builder.Airfield.apronLift, 0)
                        frame.instances.append(.prop(model, at: foot, forward: forward, scale: 1, tint: 0xFFFFFF))
                    }
                }
                guard let pair = models[aircraft.kind] else { continue }
                let near = distance < Map3DAircraft.nearReach * reach && whole < Map3DAircraft.mostNear
                if near { whole += 1 }
                frame.instances.append(Map3DAircraft.instance(near ? pair.near : pair.far, aircraft))
                // Its shadow: the fuselage's and the wings'.
                let size = Map3DAircraftStudies.dimensions(aircraft.kind)
                let darkness = 0.3 * max(0, 1 - aircraft.height / 120)
                guard darkness > 0.02 else { continue }
                let lift = Map3DPoint(0, Map3DScene.Builder.Airfield.paintLift + 0.03, 0)
                for (length, width, ahead) in [(size.length, size.height * 0.35, Float(0)), (size.length * 0.16, size.wingspan, size.length * 0.03)] {
                    let centre = aircraft.ground + lift + aircraft.forward * ahead
                    frame.shadows.addShadow(inner: Map3DMesh.footprint(centre: centre, forward: aircraft.forward, length: length, width: width),
                                            outer: Map3DMesh.footprint(centre: centre, forward: aircraft.forward, length: length + 3, width: width + 3),
                                            darkness: darkness)
                }
            }
        }
    }

    /// The vehicles by parked `aircraft` at stand number `stand`, each
    /// where it stands and the way it points: a baggage train by the hold
    /// on the right, a fuel truck under a jet's left wing, stairs at the
    /// door of a jet no bridge reaches, a tug at the nose; which of them,
    /// by the stand's number.
    static func vehicles(by aircraft: Drawn, stand: Int) -> [(Vehicle, at: Map3DPoint, forward: Map3DPoint)] {
        let size = Map3DAircraftStudies.dimensions(aircraft.kind), forward = aircraft.forward
        let left = Map3DPoint(forward.z, 0, -forward.x), centre = aircraft.ground
        let jet = aircraft.kind == .narrowJet || aircraft.kind == .wideJet
        let body = size.height * 0.2
        let r = { (n: Int32) in map3DRandom(Int32(stand), 77, salt: n) }
        var made: [(Vehicle, at: Map3DPoint, forward: Map3DPoint)] = []
        if r(0) < 0.7 { made.append((.baggageCart, centre + forward * (size.length * 0.2) - left * (body + 5), forward)) }
        if jet, r(1) < 0.45 { made.append((.fuelTruck, centre - forward * (size.length * 0.08) + left * (size.wingspan * 0.3), forward)) }
        if jet, !aircraft.bridged { made.append((.boardingStairs, centre + forward * (size.length * 0.33) + left * (body + 5.5), left * -1)) }
        if r(2) < 0.3 { made.append((.tug, centre + forward * (size.length / 2 + 4.5), forward * -1)) }
        return made
    }

    /// The instance of model `index` for `aircraft`: its wheels on the
    /// ground at its middle, its nose pitched up.
    static func instance(_ index: Int, _ aircraft: Drawn) -> Map3DInstance {
        let level = aircraft.forward, cosine = cosf(aircraft.pitch), sine = sinf(aircraft.pitch)
        // The model's x forward, y left, z up.
        let x = Map3DPoint(level.x * cosine, sine, level.z * cosine)
        let y = Map3DPoint(level.z, 0, -level.x)
        let z = x.cross(y)
        let foot = aircraft.ground + Map3DPoint(0, aircraft.height + Map3DScene.Builder.Airfield.apronLift, 0)
        let tint = liveries[aircraft.livery % liveries.count]
        func channel(_ shift: UInt32) -> Float { Float((tint >> shift) & 0xFF) / 255 }
        return Map3DInstance(model: index, transform: [x.x, x.y, x.z, 0, y.x, y.y, y.z, 0, z.x, z.y, z.z, 0, foot.x, foot.y, foot.z, 1],
                             stripe: (channel(0), channel(8), channel(16)))
    }
}

extension Map3DAircraft.Laid.Field {
    /// Lays the taxiways (`lines`, scene points): their points, joined
    /// where they come within 2 m; where they meet the runways, with the
    /// shortest way to each meeting from every point; each stand's point;
    /// and the stands the flights turn round at.
    mutating func layTaxiways(_ lines: [[Map3DPoint]]) {
        var nodes: [Map3DPoint] = [], cells: [SIMD2<Int32>: [Int]] = [:]
        var edges: [[(to: Int, length: Float)]] = []
        func cell(_ p: Map3DPoint) -> SIMD2<Int32> { SIMD2(Int32((p.x / 4).rounded(.down)), Int32((p.z / 4).rounded(.down))) }
        func node(_ p: Map3DPoint) -> Int {
            let home = cell(p)
            for dx in Int32(-1)...1 {
                for dz in Int32(-1)...1 {
                    for index in cells[home &+ SIMD2(dx, dz)] ?? [] where Map3DPoint(nodes[index].x - p.x, 0, nodes[index].z - p.z).length < 2 {
                        return index
                    }
                }
            }
            nodes.append(p)
            edges.append([])
            cells[home, default: []].append(nodes.count - 1)
            return nodes.count - 1
        }
        for line in lines {
            var last: Int?
            for point in line {
                let index = node(point)
                if let last, last != index {
                    let length = Map3DPoint(nodes[index].x - nodes[last].x, 0, nodes[index].z - nodes[last].z).length
                    edges[last].append((index, length))
                    edges[index].append((last, length))
                }
                last = index
            }
        }
        guard !nodes.isEmpty else { return }
        // Each stand's point: on the taxiway nearest behind its tail,
        // within 150 m; a new point where that is along a stretch.
        var standNodes: [Int?] = []
        for stand in stands {
            let tail = stand.nose - stand.forward * 55
            var best: (distance: Float, a: Int, b: Int, share: Float)?
            for a in edges.indices {
                for edge in edges[a] where a < edge.to && edge.length > 0 {
                    let p = nodes[a], q = nodes[edge.to]
                    let share = min(1, max(0, ((tail.x - p.x) * (q.x - p.x) + (tail.z - p.z) * (q.z - p.z)) / (edge.length * edge.length)))
                    let foot = p + (q - p) * share
                    let distance = Map3DPoint(foot.x - tail.x, 0, foot.z - tail.z).length
                    if distance < 150, best.map({ distance < $0.distance }) ?? true { best = (distance, a, edge.to, share) }
                }
            }
            guard let best else {
                standNodes.append(nil)
                continue
            }
            let length = Map3DPoint(nodes[best.b].x - nodes[best.a].x, 0, nodes[best.b].z - nodes[best.a].z).length
            if best.share * length < 3 {
                standNodes.append(best.a)
            } else if (1 - best.share) * length < 3 {
                standNodes.append(best.b)
            } else {
                // Cut the stretch in two at the point.
                let new = nodes.count
                nodes.append(nodes[best.a] + (nodes[best.b] - nodes[best.a]) * best.share)
                edges[best.a].removeAll { $0.to == best.b }
                edges[best.b].removeAll { $0.to == best.a }
                edges[best.a].append((new, best.share * length))
                edges[best.b].append((new, (1 - best.share) * length))
                edges.append([(best.a, best.share * length), (best.b, (1 - best.share) * length)])
                standNodes.append(new)
            }
        }
        self.nodes = nodes
        // A taxiway's point within 4 m of a runway's middle line meets it.
        var links: [Map3DAircraft.Laid.Link] = []
        for (number, runway) in runways.enumerated() {
            let along = Map3DPoint(runway.b.x - runway.a.x, 0, runway.b.z - runway.a.z) * (1 / runway.length)
            for (index, point) in nodes.enumerated() where edges[index].count > 0 {
                let off = Map3DPoint(point.x - runway.a.x, 0, point.z - runway.a.z)
                let s = off.dot(along)
                guard s > -30, s < runway.length + 30, (off - along * s).length < 4 else { continue }
                // Not a point of a taxiway that only runs along the runway.
                guard edges[index].contains(where: { edge in
                    let other = Map3DPoint(nodes[edge.to].x - runway.a.x, 0, nodes[edge.to].z - runway.a.z)
                    return (other - along * other.dot(along)).length > 12
                }) else { continue }
                links.append(.init(runway: number, node: index, along: s, next: Self.ways(to: index, edges: edges, off: runways, nodes: nodes)))
            }
        }
        self.links = links
        guard !links.isEmpty else { return }
        // A stand whose point has a way to a runway takes flights.
        var turning: [Int] = []
        for index in stands.indices {
            let reached = standNodes[index].flatMap { node in links.contains { $0.next[node] >= 0 || $0.node == node } ? node : nil }
            stands[index].node = reached
            let best = reached
            // Half the stands take the flights; the others keep an
            // aircraft all day, most of them.
            if best != nil, stands[index].room > 18, map3DRandom(seed &+ 55, Int32(index)) < 0.5 { turning.append(index) }
        }
        // Given out by strides, so neighbours are not taken one after
        // another.
        let stride = turning.count > 2 ? (1...turning.count).first { $0 >= turning.count * 3 / 8 && Self.coprime($0, turning.count) } ?? 1 : 1
        rotation = turning.indices.map { turning[($0 * stride) % turning.count] }
    }

    static func coprime(_ a: Int, _ b: Int) -> Bool {
        var (a, b) = (a, b)
        while b != 0 { (a, b) = (b, a % b) }
        return a == 1
    }

    /// From every point, the next on the shortest way to point `target`
    /// (Dijkstra's); −1 where there is none. A way does not run along a
    /// runway: a step between two points on a runway's middle line counts
    /// ten times its length.
    static func ways(to target: Int, edges: [[(to: Int, length: Float)]], off runways: [Map3DAircraft.Laid.Runway], nodes: [Map3DPoint]) -> [Int32] {
        func onRunway(_ p: Map3DPoint) -> Bool {
            runways.contains { runway in
                let along = Map3DPoint(runway.b.x - runway.a.x, 0, runway.b.z - runway.a.z) * (1 / runway.length)
                let off = Map3DPoint(p.x - runway.a.x, 0, p.z - runway.a.z), s = off.dot(along)
                return s > -30 && s < runway.length + 30 && (off - along * s).length < 4
            }
        }
        let runwayPoint = nodes.map(onRunway)
        var distance = [Float](repeating: .infinity, count: edges.count), next = [Int32](repeating: -1, count: edges.count)
        var done = [Bool](repeating: false, count: edges.count)
        distance[target] = 0
        // A plain search for the nearest: an airfield has a thousand
        // points or so.
        var open: Set<Int> = [target]
        while let at = open.min(by: { distance[$0] < distance[$1] }) {
            open.remove(at)
            done[at] = true
            for edge in edges[at] where !done[edge.to] {
                let cost = edge.length * (runwayPoint[at] && runwayPoint[edge.to] ? 10 : 1)
                if distance[at] + cost < distance[edge.to] {
                    distance[edge.to] = distance[at] + cost
                    next[edge.to] = Int32(at)
                    open.insert(edge.to)
                }
            }
        }
        return next
    }

    /// The taxiways' points from point `node` to `link`'s, both ends in.
    func way(from node: Int, to link: Map3DAircraft.Laid.Link) -> [Map3DPoint] {
        var path = [nodes[node]], at = node, steps = 0
        while at != link.node, link.next.indices.contains(at), link.next[at] >= 0, steps < nodes.count {
            at = Int(link.next[at])
            path.append(nodes[at])
            steps += 1
        }
        return path
    }
}
