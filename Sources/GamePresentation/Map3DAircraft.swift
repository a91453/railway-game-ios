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
    public static let farReach: Float = 3_600
    /// Within this of the eye an aircraft casts its shadow, metres.
    public static let shadowReach: Float = 1_200
    public static let mostNear = 10
    /// The most drawn as far models: an airport's 190 would be a quarter
    /// of a million triangles.
    public static let mostFar = 90

    /// A flight's figures by type: its speed over the threshold and at
    /// lift-off (m/s), and the least runway it uses (m).
    static func figures(_ kind: Kind) -> (approach: Double, liftOff: Double, runway: Float) {
        switch kind {
        case .commuter19: (48, 46, 0)
        // Decision 702: 1,200 m, not 1,000: Lanyu's 1,132 m (1,179 m as
        // OpenStreetMap draws it) takes nineteen-seaters only.
        case .regional70: (58, 56, 1_200)
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
        /// Decision 702: a flight's aircraft: which flight, and what it
        /// is doing; `nil` for one parked all day.
        public var flight: FlightID?
        public var phase: Phase?
    }

    /// Decision 702: a flight, for the camera that follows its aircraft:
    /// its airfield (``Laid/Field/seed``), the hour its runway time falls
    /// in (hours since the game began), whether it lands, and its number
    /// among that hour's landings or take-offs. Nothing is kept of it:
    /// the same numbers give the same flight again.
    public struct FlightID: Hashable, Sendable {
        public let field: Int32
        public let hours: Int64
        public let landing: Bool
        public let index: Int

        public init(field: Int32, hours: Int64, landing: Bool, index: Int) {
            self.field = field
            self.hours = hours
            self.landing = landing
            self.index = index
        }
    }

    /// Decision 702: what a flight's aircraft is doing.
    public enum Phase: Hashable, Sendable {
        case approach, landingRoll, taxiIn, parked, pushBack, taxiOut, lineUp, takeOffRoll, climb

        /// Whether it has its landing lights on: in the air and on the
        /// runway.
        var landingLights: Bool {
            switch self {
            case .approach, .landingRoll, .lineUp, .takeOffRoll, .climb: true
            case .taxiIn, .parked, .pushBack, .taxiOut: false
            }
        }
    }

    /// The airfields of a scene, laid for the aircraft drawn each frame.
    public struct Laid: Sendable {
        struct Stand: Sendable {
            let nose: Map3DPoint
            let forward: Map3DPoint
            /// The widest wings it takes beside its neighbours, metres; 0
            /// for a stand left empty (``giveRoom(to:seed:wide:propeller:runway:)``).
            var room: Float
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
            /// Decision 702: the drawn ground along it from `a` to `b`, a
            /// height every ``heightStep`` metres and at `b`: a runway on
            /// an island's hill (Qimei, Green Island) rises between its
            /// ends, and an aircraft set on the straight line between
            /// them rolled under it. Empty: the straight line.
            var heights: [Float] = []
            static let heightStep: Float = 20

            /// The ground `s` metres from `a`, held level past the ends.
            func height(at s: Float) -> Float {
                guard heights.count > 1, length > 0 else { return a.y + (b.y - a.y) * min(1, max(0, s / max(length, 1))) }
                let along = min(1, max(0, s / length)) * Float(heights.count - 1)
                let index = min(Int(along), heights.count - 2)
                return heights[index] + (heights[index + 1] - heights[index]) * (along - Float(index))
            }
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
        /// Decision 702: the map's edges in the scene (x from, x to, z
        /// from, z to): past them there is no ground to follow an aircraft
        /// over. `nil`: no edges.
        var edges: (x: ClosedRange<Float>, z: ClosedRange<Float>)?
        private let kept = Kept()
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
            let corner = scene.point(worldX: 0, worldY: 0, height: 0)
            let far = scene.point(worldX: Double(world.bounds.width), worldY: Double(world.bounds.height), height: 0)
            edges = (min(corner.x, far.x)...max(corner.x, far.x), min(corner.z, far.z)...max(corner.z, far.z))
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
                    guard length > 300 else { continue }
                    let steps = max(1, Int((length / Runway.heightStep).rounded(.up)))
                    let heights = (0...steps).map { step -> Float in
                        let at = a + (b - a) * (Float(step) / Float(steps))
                        return scene.drawnGround.height(x: at.x, z: at.z, world: world)
                    }
                    runways.append(Runway(a: a, b: b, length: length, heights: heights))
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
                    let bridged = field.bridges.contains { bridge in
                        place(bridge.to).map { Map3DPoint($0.x - nose.x, 0, $0.z - nose.z).length < 35 } ?? false
                    }
                    stands.append(Stand(nose: nose, forward: forward, room: 0, bridged: bridged))
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
                let seed = Int32(truncatingIfNeeded: number &* 7_919 &+ 17)
                Self.giveRoom(to: &stands, seed: seed, wide: wide, propeller: propeller, runway: runways[0].length)
                var laid = Field(seed: seed, airports: airports, stands: stands, runways: runways, wide: wide, propeller: propeller)
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

        /// Gives each of `stands` its room: the widest wings it takes with
        /// every other stand taking its own. OpenStreetMap maps a wide
        /// stand and the two narrow ones that share its ground as three,
        /// 20 m apart; so the stands are taken in a fixed shuffled order,
        /// each given the type the airport's mix picks for it, or the
        /// largest smaller one that clears the wings already given (4 m
        /// between wing tips), or none.
        static func giveRoom(to stands: inout [Stand], seed: Int32, wide: Float, propeller: Float, runway: Float) {
            let order = stands.indices.sorted { map3DRandom(seed &+ 31, Int32($0)) < map3DRandom(seed &+ 31, Int32($1)) }
            var given: [(nose: Map3DPoint, span: Float)] = []
            for index in order {
                let nose = stands[index].nose
                var room: Float = 80
                for other in given { room = min(room, 2 * (Map3DPoint(other.nose.x - nose.x, 0, other.nose.z - nose.z).length - other.span / 2 - 4)) }
                let kind = kind(wide: wide, propeller: propeller, share: map3DRandom(seed &+ 32, Int32(index)), runway: runway, room: room)
                let span = Map3DAircraftStudies.dimensions(kind).wingspan
                guard span <= room else { continue }
                stands[index].room = span + 0.5
                given.append((nose, span))
            }
        }

        /// The type of an aircraft of `field`, picked by `share` (0–1)
        /// among those `runway` metres of runway and `room` metres of
        /// wingspan take.
        static func kind(_ field: Field, share: Float, runway: Float, room: Float = .infinity) -> Kind {
            kind(wide: field.wide, propeller: field.propeller, share: share, runway: runway, room: room)
        }

        /// The type `share` (0–1) picks at an airport `wide` of whose
        /// aircraft are wide-bodied and `propeller` propeller-driven.
        static func kind(wide: Float, propeller: Float, share: Float, runway: Float, room: Float = .infinity) -> Kind {
            var kind: Kind
            if share < wide {
                kind = .wideJet
            } else if share > 1 - propeller {
                kind = share > 1 - propeller * 0.25 && wide == 0 ? .commuter19 : .regional70
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
            var id = FlightID(field: 0, hours: 0, landing: false, index: 0)
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
            // Decision 702: a field of a few stands (an island's) gives
            // out two an hour, one to its landing and one to its take-off.
            let slots = min(128, max(field.rotation.count / 3, min(field.rotation.count, 2)))
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
                              livery: Int(r(1) * Float(Map3DAircraft.liveries.count)) % Map3DAircraft.liveries.count, stand: stand,
                              id: FlightID(field: field.seed, hours: hours, landing: landing, index: index))
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

        /// A flight laid on its field: what does not change while it is
        /// seen (its runway the way it is used, its speeds, its way along
        /// the taxiways), worked out once (``plan(_:on:northEast:)``) so
        /// each frame only reads where it is (``pose(_:second:)``).
        struct Planned: Sendable {
            let flight: Flight
            /// The runway's ends the way it is used, the level way along
            /// it, and its length, metres.
            let from: Map3DPoint
            let to: Map3DPoint
            let forward: Map3DPoint
            let length: Double
            /// Decision 702: the runway, and whether it is used from its
            /// `b` to its `a`, for the ground along it.
            var runway: Runway?
            var turned = false
            /// A landing: where it aims, its speed over the threshold, how
            /// long it brakes and how far along it has slowed.
            var aim = 0.0
            var speed = 0.0
            var stop = 0.0
            var slowed = 0.0
            /// A take-off: where its roll starts and how long it lasts.
            var start = 0.0
            var roll = 0.0
            /// With a stand the taxiways reach: how long it rolls on the
            /// runway to its taxiway (a landing), its way between the
            /// runway and the stand's point (and, for a landing, on to the
            /// stand), that way's length, and for a take-off how long its
            /// taxi and its push back last.
            var rolled: Double?
            var path: [Map3DPoint] = []
            var total = 0.0
            var taxi = 0.0
            var push = 0.0
            /// Its stand: its number, where the aircraft's middle stands,
            /// the way it points, whether a bridge reaches it, and the
            /// taxiways' point it is pushed back to.
            var stand: Int?
            var parked = Map3DPoint.zero
            var facing = Map3DPoint(1, 0, 0)
            var bridged = false
            var node = Map3DPoint.zero

            /// On the runway `s` metres from the end it starts at, on the
            /// runway's own ground, held level past its ends.
            func onRunway(_ s: Double, height: Double = 0, pitch: Double = 0) -> Drawn {
                let share = Float(min(1, max(0, s / length)))
                let level = runway.map { $0.height(at: (turned ? 1 - share : share) * $0.length) } ?? from.y + (to.y - from.y) * share
                let ground = Map3DPoint(from.x + forward.x * Float(s), level, from.z + forward.z * Float(s))
                return Drawn(ground: ground, height: Float(height), forward: forward, pitch: Float(pitch), kind: flight.kind, livery: flight.livery,
                             flying: true, flight: flight.id)
            }

            func drawn(at ground: Map3DPoint, forward: Map3DPoint) -> Drawn {
                Drawn(ground: ground, height: 0, forward: forward, pitch: 0, kind: flight.kind, livery: flight.livery, flying: true, flight: flight.id)
            }

            /// Decision 702: the way round on the runway at `s` metres
            /// along it: on along the middle line, across to one side and
            /// back (`ahead`: for a landing that goes back the way it
            /// came); or coming back along one side and across on to the
            /// middle line at `s`, facing the way the runway is used (a
            /// take-off lining up). Some 10 m to the side: a runway is 23 m
            /// wide or more.
            func turnRound(from s: Double, ahead: Bool) -> [Map3DPoint] {
                let side = Map3DPoint(forward.z, 0, -forward.x) * 9
                if ahead {
                    return [onRunway(s).ground, onRunway(s + 28).ground, onRunway(s + 34).ground + side, onRunway(s + 10).ground + side]
                }
                return [onRunway(s + 45).ground + side, onRunway(s - 14).ground + side, onRunway(s - 18).ground]
            }

            var atStand: Drawn {
                Drawn(ground: parked, height: 0, forward: facing, pitch: 0, kind: flight.kind, livery: flight.livery, flying: false, stand: stand,
                      bridged: bridged, flight: flight.id, phase: .parked)
            }
        }

        /// `flight` laid on `field`, landing towards the north-east or not.
        static func plan(_ flight: Flight, on field: Field, northEast: Bool) -> Planned? {
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
            var plan = Planned(flight: flight, from: from, to: to, forward: forward, length: length)
            plan.runway = runway
            plan.turned = turned
            // The taxiways' meetings with this runway, measured the way it
            // is used, that have a way to the stand's point.
            let stand = flight.stand.flatMap { index in field.stands[index].node.map { (index: index, stand: field.stands[index], node: $0) } }
            func links() -> [(link: Link, s: Double)] {
                guard let stand else { return [] }
                return field.links.filter { $0.runway == flight.runway && ($0.next[stand.node] >= 0 || $0.node == stand.node) }
                    .map { ($0, turned ? length - Double($0.along) : Double($0.along)) }
            }
            if let stand {
                plan.stand = stand.index
                plan.parked = stand.stand.nose - stand.stand.forward * (Map3DAircraftStudies.dimensions(flight.kind).length / 2)
                plan.facing = stand.stand.forward
                plan.bridged = stand.stand.bridged
                plan.node = field.nodes[stand.node]
            }
            if flight.landing {
                plan.aim = min(400, length * 0.14)
                plan.speed = figures.approach
                plan.stop = (plan.speed - Map3DAircraft.taxiSpeed) / Map3DAircraft.braking
                plan.slowed = plan.aim + plan.speed * plan.stop - Map3DAircraft.braking * plan.stop * plan.stop / 2
                // Off by the first taxiway past where it has slowed, turning
                // from 20 m before it; along the taxiways to the stand's
                // point, and in to the stand.
                if let stand, let exit = links().filter({ $0.s > plan.slowed + 20 }).min(by: { $0.s < $1.s }) {
                    plan.rolled = (exit.s - 20 - plan.slowed) / Map3DAircraft.taxiSpeed
                    plan.path = [plan.onRunway(exit.s - 20).ground, plan.onRunway(exit.s).ground]
                        + field.way(from: stand.node, to: exit.link).reversed() + [plan.parked]
                    plan.total = Self.length(of: plan.path)
                } else if let stand, let exit = links().max(by: { $0.s < $1.s }) {
                    // Decision 702: its taxiway is behind it (a short
                    // runway with its apron by the middle): it turns round
                    // on the runway and rolls back to it.
                    plan.rolled = 0
                    plan.path = plan.turnRound(from: plan.slowed, ahead: true) + [plan.onRunway(exit.s).ground]
                        + field.way(from: stand.node, to: exit.link).reversed() + [plan.parked]
                    plan.total = Self.length(of: plan.path)
                }
            } else {
                // It rolls from where it lined up: with a stand, 25 m past
                // the taxiway nearest the runway's start.
                plan.start = min(70, length * 0.04)
                plan.roll = figures.liftOff / Map3DAircraft.thrust
                // Decision 702: the runway its roll takes, and a third
                // more: with less of it left past a taxiway, it does not
                // start there.
                let needed = Map3DAircraft.thrust * plan.roll * plan.roll / 2 * 1.3
                let entries = links().filter { $0.s < length * 0.5 && length - ($0.s + 25) >= min(needed, length * 0.5) }
                if let stand, entries.isEmpty, let entry = links().min(by: { $0.s < $1.s }) {
                    // Decision 702: no taxiway near the runway's start (a
                    // short runway with its apron by the middle): it
                    // rolls back along the runway to its start and turns
                    // round there.
                    let turn = plan.turnRound(from: plan.start, ahead: false)
                    plan.path = field.way(from: stand.node, to: entry.link) + [plan.onRunway(entry.s).ground] + turn + [plan.onRunway(plan.start).ground]
                    plan.total = Self.length(of: plan.path)
                    plan.taxi = plan.total / Map3DAircraft.taxiSpeed
                    plan.push = Double((plan.node - plan.parked).length) / Map3DAircraft.pushSpeed
                    plan.rolled = 0
                } else if let stand, let entry = entries.min(by: { $0.s < $1.s }) {
                    plan.start = max(plan.start, min(entry.s, length - Double(figures.runway) * 0.6)) + 25
                    plan.path = field.way(from: stand.node, to: entry.link) + [plan.onRunway(entry.s).ground, plan.onRunway(plan.start).ground]
                    plan.total = Self.length(of: plan.path)
                    plan.taxi = plan.total / Map3DAircraft.taxiSpeed
                    plan.push = Double((plan.node - plan.parked).length) / Map3DAircraft.pushSpeed
                    plan.rolled = 0
                }
            }
            return plan
        }

        /// `flight` on `field` at game second `second`, or `nil` before it
        /// is seen or after it has gone (``pose(_:second:)``).
        static func pose(of flight: Flight, on field: Field, second: Double, northEast: Bool) -> Drawn? {
            plan(flight, on: field, northEast: northEast).flatMap { pose($0, second: second) }
        }

        /// Where `plan`'s flight is at game second `second`, or `nil`
        /// before it is seen or after it has gone: in the air, on the
        /// runway, and with a stand the taxiways reach, taxiing to it and
        /// standing at it for ``Map3DAircraft/turnaround`` after landing,
        /// or standing at it for as long, pushed back and taxiing out
        /// before leaving.
        static func pose(_ plan: Planned, second: Double) -> Drawn? {
            let flight = plan.flight, t = second - flight.time
            func doing(_ phase: Phase, _ drawn: Drawn) -> Drawn {
                var drawn = drawn
                drawn.phase = phase
                return drawn
            }
            if flight.landing {
                if t < 0 {
                    let out = -t * plan.speed
                    guard out < Map3DAircraft.seenFrom else { return nil }
                    // The flare: the last 200 m level out.
                    return doing(.approach, plan.onRunway(plan.aim - out, height: out > 200 ? out * Map3DAircraft.glide : out * out / 200 * Map3DAircraft.glide,
                                                          pitch: out > 200 ? 0.05 : 0.05 + 0.04 * (1 - out / 200)))
                }
                if t < plan.stop {
                    return doing(.landingRoll, plan.onRunway(plan.aim + plan.speed * t - Map3DAircraft.braking * t * t / 2, pitch: max(0, 0.09 * (1 - t / 4))))
                }
                guard let rolled = plan.rolled else {
                    // No way to a stand: gone by the runway's end.
                    let s = plan.slowed + Map3DAircraft.taxiSpeed * (t - plan.stop)
                    return s < plan.length - 60 ? doing(.landingRoll, plan.onRunway(s)) : nil
                }
                // Slowed: along the runway to its taxiway, already on its way to its stand.
                if t < plan.stop + rolled { return doing(.taxiIn, plan.onRunway(plan.slowed + Map3DAircraft.taxiSpeed * (t - plan.stop))) }
                let travelled = Map3DAircraft.taxiSpeed * (t - plan.stop - rolled)
                if travelled < plan.total {
                    let at = Self.point(on: plan.path, at: travelled)
                    return doing(.taxiIn, plan.drawn(at: at.point, forward: at.forward))
                }
                return travelled < plan.total + Map3DAircraft.turnaround * Map3DAircraft.taxiSpeed ? plan.atStand : nil
            }
            if t > 0 {
                let liftOff = plan.roll * Map3DAircraft.thrust
                if t < plan.roll {
                    return doing(.takeOffRoll, plan.onRunway(plan.start + Map3DAircraft.thrust * t * t / 2, pitch: t > plan.roll - 3 ? 0.07 * (t - (plan.roll - 3)) : 0))
                }
                let up = (t - plan.roll) * (liftOff + 8)
                guard up < Map3DAircraft.seenFrom else { return nil }
                return doing(.climb, plan.onRunway(plan.start + Map3DAircraft.thrust * plan.roll * plan.roll / 2 + up, height: up * Map3DAircraft.climb, pitch: 0.21))
            }
            // It waits lined up for 25 seconds.
            if t > -25 { return doing(.lineUp, plan.onRunway(plan.start)) }
            guard plan.rolled != nil else { return nil }
            // Backwards in time from the line-up: its taxi from the
            // stand's point, a pause there, and the push back.
            var before = -25 - t
            if before < plan.taxi {
                let at = Self.point(on: plan.path, at: (plan.taxi - before) * Map3DAircraft.taxiSpeed)
                return doing(.taxiOut, plan.drawn(at: at.point, forward: at.forward))
            }
            before -= plan.taxi
            // Pushed back tail first, then turned the way it will go.
            let out = Map3DPoint(plan.node.x - plan.parked.x, 0, plan.node.z - plan.parked.z).normalized ?? plan.facing * -1
            if before < Map3DAircraft.pushPause {
                let onward = Self.point(on: plan.path, at: 0).forward
                let turn = Float(before / Map3DAircraft.pushPause)
                return doing(.pushBack, plan.drawn(at: plan.node, forward: (onward * (1 - turn) + out * -turn).normalized ?? onward))
            }
            before -= Map3DAircraft.pushPause
            if before < plan.push {
                let share = Float(before / plan.push)
                return doing(.pushBack, plan.drawn(at: plan.node + (plan.parked - plan.node) * share,
                                                   forward: (out * -1 * (1 - share) + plan.facing * share).normalized ?? plan.facing))
            }
            return before - plan.push < Map3DAircraft.turnaround ? plan.atStand : nil
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

        /// What a frame reads again and again, kept: each hour's flights
        /// laid (``Planned``), and each day's aircraft parked all day.
        final class Kept: @unchecked Sendable {
            /// Review L19, P3-4: an hour's flights are laid once, with
            /// the numbers of the day that first asked for them, and stay
            /// as laid while they are seen: the hours either side of
            /// midnight are not laid again with the new day's numbers
            /// (their aircraft would jump).
            struct Hour: Hashable {
                let field: Int
                let hours: Int64
            }

            struct Day: Hashable {
                let field: Int
                let day: Int64
                let turning: Bool
            }

            private let lock = NSLock()
            private var hours: [Hour: [Planned]] = [:]
            private var days: [Day: [Drawn]] = [:]
            /// The last moment's aircraft: a paused game asks for the same
            /// moment every frame.
            private var last: (second: Double, traffic: Int64?, still: Bool, drawn: [Drawn])?

            func moment(second: Double, traffic: Int64?, still: Bool, _ make: () -> [Drawn]) -> [Drawn] {
                lock.lock()
                if let last, last.second == second, last.traffic == traffic, last.still == still {
                    lock.unlock()
                    return last.drawn
                }
                lock.unlock()
                let made = make()
                lock.lock()
                last = (second, traffic, still, made)
                lock.unlock()
                return made
            }

            func plans(_ key: Hour, _ make: () -> [Planned]) -> [Planned] {
                lock.lock()
                defer { lock.unlock() }
                if let known = hours[key] { return known }
                // Review L19, P3-7: only the hours no longer seen go, not
                // those drawn now (laying them all again in one frame).
                if hours.count > Self.mostHours {
                    hours = hours.filter { abs($0.key.hours - key.hours) <= Self.hoursKept }
                }
                let made = make()
                hours[key] = made
                return made
            }

            /// How many hours' flights are kept before the old ones go,
            /// and how far from the hour asked for one is kept: the hours
            /// drawn are within two of now, so within four of each other.
            static let mostHours = 200
            static let hoursKept: Int64 = 4

            /// How many hours' flights are kept now.
            var hoursCount: Int {
                lock.lock()
                defer { lock.unlock() }
                return hours.count
            }

            func parked(_ key: Day, _ make: () -> [Drawn]) -> [Drawn] {
                lock.lock()
                defer { lock.unlock() }
                if let known = days[key] { return known }
                if days.count > 60 { days = days.filter { $0.key.day == key.day } }
                let made = make()
                days[key] = made
                return made
            }
        }

        /// The aircraft at game second `second` (since the game began):
        /// those parked at the stands, and with `traffic` and not `still`
        /// those landing, leaving and taxiing. With `still` (Reduce
        /// Motion) none moves: the flights' aircraft stand at their stands
        /// for their time there, and that is all.
        public func aircraft(second: Double, traffic: Traffic?, still: Bool = false) -> [Drawn] {
            kept.moment(second: second, traffic: traffic?.day, still: still) { worked(second: second, traffic: traffic, still: still) }
        }

        private func worked(second: Double, traffic: Traffic?, still: Bool) -> [Drawn] {
            let day = Int64((second / Double(GameTime.secondsPerDay)).rounded(.down))
            let hour = Int((second - Double(day * GameTime.secondsPerDay)) / 3_600)
            var drawn: [Drawn] = []
            for (number, field) in fields.enumerated() {
                let flies = traffic != nil && !field.airports.isEmpty
                // Parked all day: most of the stands no flight turns round
                // at.
                drawn += kept.parked(.init(field: number, day: day, turning: flies)) {
                    let salt = Int32(truncatingIfNeeded: day), turning = flies ? Set(field.rotation) : []
                    var parked: [Drawn] = []
                    for (index, stand) in field.stands.enumerated() where !turning.contains(index) {
                        let r = { (n: Int32) in map3DRandom(field.seed &+ 101, Int32(index), salt: salt &* 4 &+ n) }
                        guard r(0) < 0.9, stand.room > 16 else { continue }
                        let kind = Self.kind(field, share: r(1), runway: field.runways[0].length, room: stand.room)
                        let length = Map3DAircraftStudies.dimensions(kind).length
                        parked.append(Drawn(ground: stand.nose - stand.forward * (length / 2), height: 0, forward: stand.forward, pitch: 0, kind: kind,
                                            livery: Int(r(2) * Float(Map3DAircraft.liveries.count)) % Map3DAircraft.liveries.count, flying: false,
                                            stand: index, bridged: stand.bridged))
                    }
                    return parked
                }
                guard let traffic, flies else { continue }
                // The flights whose runway time is within an hour and a
                // half: the hours next to midnight take the numbers of the
                // day that first drew them, and keep them.
                for offset in -2...2 {
                    let at = hour + offset
                    let flightDay = at < 0 ? day - 1 : (at > 23 ? day + 1 : day), flightHour = (at + 24) % 24
                    let plans = plans(of: number, day: flightDay, hour: flightHour, traffic: traffic)
                    for plan in plans where abs(plan.flight.time - second) < 5_400 {
                        if let pose = Self.pose(plan, second: second), !still || !pose.flying { drawn.append(pose) }
                    }
                }
            }
            return drawn
        }

        /// The flights of field `number` whose runway time falls in hour
        /// `hour` of day `day`, laid; kept. They land the way their own
        /// day's season has it, and an hour laid before is not laid again
        /// with another day's `traffic` (review L19, P3-4).
        private func plans(of number: Int, day: Int64, hour: Int, traffic: Traffic) -> [Planned] {
            let field = fields[number]
            return kept.plans(.init(field: number, hours: day &* 24 &+ Int64(hour))) {
                let northEast = Self.landsNorthEast(day: day)
                return Self.flights(of: field, day: day, hour: hour, traffic: traffic).compactMap { Self.plan($0, on: field, northEast: northEast) }
            }
        }

        /// How many hours' flights are kept now (a test's reading).
        var keptHours: Int { kept.hoursCount }

        /// Decision 702: flight `id`'s aircraft at game second `second`,
        /// as ``aircraft(second:traffic:still:)`` draws it; `nil` before
        /// it is seen, after it has gone, with no traffic and with
        /// `still`.
        public func aircraft(of id: FlightID, second: Double, traffic: Traffic?, still: Bool = false) -> Drawn? {
            guard !still, let traffic, let number = fields.firstIndex(where: { $0.seed == id.field }) else { return nil }
            let flightDay = GameDate.floorDivide(id.hours, 24)
            let plans = plans(of: number, day: flightDay, hour: Int(id.hours - flightDay * 24), traffic: traffic)
            guard let plan = plans.first(where: { $0.flight.id == id }), abs(plan.flight.time - second) < 5_400 else { return nil }
            return Self.pose(plan, second: second)
        }

        /// Decision 702: the game's airport (its place in
        /// ``GameWorld/airports``) flight `id` lands at or leaves.
        public func airport(of id: FlightID) -> Int? {
            fields.first { $0.seed == id.field }?.airports.first
        }

        /// The aircraft added to `frame`, seen from `eye`, with `pack`'s
        /// models: whole close up, their far models from farther, a soft
        /// shadow under each, and close up the vehicles by a parked one.
        ///
        /// Decision 702: the aircraft of flight `following` (the camera's)
        /// is drawn whole whatever the others; and each moving aircraft
        /// within the glows' reach has its lamps (``Map3DAircraft/lamps(of:blink:)``,
        /// ``Map3DTrains/Frame/lamps``), flashing by `blink` (seconds of a
        /// clock that runs with the player's, not the game's); none with
        /// `lit` false (by day, when no glow is drawn).
        public func add(to frame: inout Map3DTrains.Frame, pack: Map3DModelPack, second: Double, traffic: Traffic?, eye: Map3DPoint,
                        reach: Float = 1, still: Bool = false, following: FlightID? = nil, blink: Double? = nil, lit: Bool = true) {
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
            var whole = 0, far = 0
            for (distance, aircraft) in seen {
                if distance < Map3DAircraft.vehicleReach * reach, let stand = aircraft.stand {
                    for (vehicle, at, forward) in Map3DAircraft.vehicles(by: aircraft, stand: stand) {
                        guard let model = vehicles[vehicle] else { continue }
                        let foot = at + Map3DPoint(0, Map3DScene.Builder.Airfield.apronLift, 0)
                        frame.instances.append(.prop(model, at: foot, forward: forward, scale: 1, tint: 0xFFFFFF))
                    }
                }
                guard let pair = models[aircraft.kind] else { continue }
                let followed = following != nil && aircraft.flight == following
                let near = followed || distance < Map3DAircraft.nearReach * reach && whole < Map3DAircraft.mostNear
                if lit, aircraft.flying, distance < Map3DGlow.reach { frame.lamps += Map3DAircraft.lamps(of: aircraft, blink: blink) }
                if near {
                    whole += 1
                } else {
                    // The nearest first; one in the air is always drawn.
                    guard far < Map3DAircraft.mostFar || aircraft.height > 0 else { continue }
                    far += 1
                }
                frame.instances.append(Map3DAircraft.instance(near ? pair.near : pair.far, aircraft))
                // Its shadow: the fuselage's and the wings'.
                let size = Map3DAircraftStudies.dimensions(aircraft.kind)
                let darkness = 0.3 * max(0, 1 - aircraft.height / 120)
                guard darkness > 0.02, distance < Map3DAircraft.shadowReach else { continue }
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

    /// Where `aircraft`'s model stands in the scene: its origin (on the
    /// ground under its middle, when its wheels are down) and its axes, x
    /// forward (its nose pitched up), y left, z up.
    static func axes(of aircraft: Drawn) -> (origin: Map3DPoint, x: Map3DPoint, y: Map3DPoint, z: Map3DPoint) {
        let level = aircraft.forward, cosine = cosf(aircraft.pitch), sine = sinf(aircraft.pitch)
        let x = Map3DPoint(level.x * cosine, sine, level.z * cosine)
        let y = Map3DPoint(level.z, 0, -level.x)
        return (aircraft.ground + Map3DPoint(0, aircraft.height + Map3DScene.Builder.Airfield.apronLift, 0), x, y, x.cross(y))
    }

    /// The instance of model `index` for `aircraft`: its wheels on the
    /// ground at its middle, its nose pitched up.
    static func instance(_ index: Int, _ aircraft: Drawn) -> Map3DInstance {
        let (foot, x, y, z) = axes(of: aircraft)
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
    ///
    /// Decision 702: a small field whose taxiways OpenStreetMap does not
    /// map (Lanyu, Green Island: an apron beside the runway) has its
    /// stands joined straight to the runway, each by the shortest way to
    /// the runway's middle line, and every stand takes flights: without
    /// them a landing was gone at the runway's end and a take-off came
    /// from nowhere.
    mutating func layTaxiways(_ lines: [[Map3DPoint]]) {
        lay(lines, joins: nil)
        guard links.isEmpty, stands.contains(where: { $0.room > 16 }), let runway = runways.first else { return }
        let along = Map3DPoint(runway.b.x - runway.a.x, 0, runway.b.z - runway.a.z) * (1 / runway.length)
        func foot(of point: Map3DPoint) -> (foot: Map3DPoint, off: Float) {
            let s = min(runway.length, max(0, Map3DPoint(point.x - runway.a.x, 0, point.z - runway.a.z).dot(along)))
            let foot = Map3DPoint(runway.a.x + along.x * s, runway.height(at: s), runway.a.z + along.z * s)
            return (foot, Map3DPoint(point.x - foot.x, 0, point.z - foot.z).length)
        }
        // Each stand's point: 30 m behind its nose (where it is pushed
        // back to), or its nose where that is on the runway; then the
        // way from the runway's middle line to it, its first 14 m square
        // to the runway.
        var joins: [Int: Map3DPoint] = [:], direct: [[Map3DPoint]] = []
        for (index, stand) in stands.enumerated() where stand.room > 16 {
            let behind = stand.nose - stand.forward * 30
            let point = foot(of: behind).off > 20 ? behind : stand.nose
            let (foot, off) = foot(of: point)
            // Off the runway, within a taxiway's length of it.
            guard off > 20, off < 400 else { continue }
            joins[index] = point
            direct.append([foot, foot + (point - foot) * (14 / off), point])
        }
        guard !direct.isEmpty else { return }
        lay(lines + direct, joins: joins)
    }

    /// `joins`: decision 702's points of the stands joined straight to the
    /// runway, by the stand's number (then every stand with a way takes
    /// flights); `nil` for a field with its own taxiways.
    private mutating func lay(_ lines: [[Map3DPoint]], joins: [Int: Map3DPoint]?) {
        let everyStandTurns = joins != nil
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
        for (number, stand) in stands.enumerated() {
            let tail = joins?[number] ?? stand.nose - stand.forward * 55
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
            // A third of the stands take the flights; the others keep an
            // aircraft all day, most of them.
            if best != nil, stands[index].room > 16, everyStandTurns || map3DRandom(seed &+ 55, Int32(index)) < 0.35 { turning.append(index) }
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
