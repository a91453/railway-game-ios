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
        return made
    }

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
    }

    /// The airfields of a scene, laid for the aircraft drawn each frame.
    public struct Laid: Sendable {
        struct Stand: Sendable {
            let nose: Map3DPoint
            let forward: Map3DPoint
            /// The widest wings that fit beside its neighbours, metres.
            let room: Float
        }

        struct Runway: Sendable {
            let a: Map3DPoint
            let b: Map3DPoint
            let length: Float
        }

        struct Field: Sendable {
            let seed: Int32
            /// The world's airports that are this airfield, by their place
            /// in ``GameWorld/airports``.
            let airports: [Int]
            let stands: [Stand]
            /// The longest first.
            let runways: [Runway]
            /// The share of its aircraft that are wide-bodied, and
            /// propeller-driven; the rest narrow-bodied jets.
            let wide: Float
            let propeller: Float
        }

        let fields: [Field]
        public var isEmpty: Bool { fields.isEmpty }

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
                    stands.append(Stand(nose: nose, forward: forward, room: room - 3))
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
                made.append(Field(seed: Int32(truncatingIfNeeded: number &* 7_919 &+ 17), airports: airports, stands: stands, runways: runways,
                                  wide: wide, propeller: propeller))
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
        /// (game seconds), which runway, which way, its type and livery.
        struct Flight {
            let time: Double
            let landing: Bool
            let runway: Int
            let kind: Kind
            let livery: Int
        }

        /// The flights of `field` whose runway time falls in hour `hour`
        /// of day `day`, `traffic` saying how many: spread evenly over the
        /// hour, the take-offs between the landings and never within 75
        /// seconds of one on the same runway.
        static func flights(of field: Field, day: Int64, hour: Int, traffic: Traffic) -> [Flight] {
            var landings = 0, takeOffs = 0
            for airport in field.airports where traffic.landings.indices.contains(airport) && traffic.landings[airport].indices.contains(hour) {
                landings += traffic.landings[airport][hour]
                takeOffs += traffic.takeOffs[airport][hour]
            }
            guard landings + takeOffs > 0 else { return [] }
            let start = Double(day * GameTime.secondsPerDay) + Double(hour) * 3_600
            let salt = Int32(truncatingIfNeeded: day &* 24 &+ Int64(hour))
            // Two runways side by side share the flights.
            let pair = field.runways.count > 1 && field.runways[1].length > field.runways[0].length * 0.7 ? 2 : 1
            var flights: [Flight] = []
            for index in 0..<landings {
                let r = { (n: Int32) in map3DRandom(field.seed, salt, salt: Int32(index) &* 8 &+ n) }
                let runway = index % pair
                flights.append(Flight(time: start + (Double(index) + 0.5) * 3_600 / Double(landings), landing: true, runway: runway,
                                      kind: kind(field, share: r(0), runway: field.runways[runway].length),
                                      livery: Int(r(1) * Float(Map3DAircraft.liveries.count)) % Map3DAircraft.liveries.count))
            }
            let touchdowns = flights
            for index in 0..<takeOffs {
                let r = { (n: Int32) in map3DRandom(field.seed, salt, salt: Int32(index) &* 8 &+ 4 &+ n) }
                let runway = (index + 1) % pair
                var time = start + (Double(index) + 0.25) * 3_600 / Double(takeOffs)
                while touchdowns.contains(where: { $0.runway == runway && abs($0.time - time) < 75 }) { time += 80 }
                flights.append(Flight(time: time, landing: false, runway: runway,
                                      kind: kind(field, share: r(0), runway: field.runways[runway].length),
                                      livery: Int(r(1) * Float(Map3DAircraft.liveries.count)) % Map3DAircraft.liveries.count))
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
        /// is seen or after it has gone.
        static func pose(of flight: Flight, on field: Field, second: Double, northEast: Bool) -> Drawn? {
            let runway = field.runways[flight.runway]
            var from = runway.a, to = runway.b
            // x east, z south: north-east is +x, −z.
            let along = Map3DPoint(to.x - from.x, 0, to.z - from.z)
            if (along.x - along.z > 0) != northEast { swap(&from, &to) }
            guard let forward = Map3DPoint(to.x - from.x, 0, to.z - from.z).normalized else { return nil }
            let length = Double(runway.length), figures = Map3DAircraft.figures(flight.kind)
            let t = second - flight.time
            // `s`: metres along the runway from the end it starts at.
            var s: Double, height = 0.0, pitch = 0.0
            if flight.landing {
                let aim = min(400, length * 0.14), speed = figures.approach
                if t < 0 {
                    let out = -t * speed
                    guard out < Map3DAircraft.seenFrom else { return nil }
                    s = aim - out
                    // The flare: the last 200 m level out.
                    height = out > 200 ? out * Map3DAircraft.glide : out * out / 200 * Map3DAircraft.glide
                    pitch = out > 200 ? 0.05 : 0.05 + 0.04 * (1 - out / 200)
                } else {
                    let stop = (speed - Map3DAircraft.taxiSpeed) / Map3DAircraft.braking
                    if t < stop {
                        s = aim + speed * t - Map3DAircraft.braking * t * t / 2
                        pitch = max(0, 0.09 * (1 - t / 4))
                    } else {
                        s = aim + speed * stop - Map3DAircraft.braking * stop * stop / 2 + Map3DAircraft.taxiSpeed * (t - stop)
                    }
                    // Off the runway by its end.
                    guard s < length - 60 else { return nil }
                }
            } else {
                // It waits lined up for 25 seconds, then rolls.
                guard t > -25 else { return nil }
                let start = min(70, length * 0.04), roll = figures.liftOff / Map3DAircraft.thrust
                if t <= 0 {
                    s = start
                } else if t < roll {
                    s = start + Map3DAircraft.thrust * t * t / 2
                    pitch = t > roll - 3 ? 0.07 * (t - (roll - 3)) : 0
                } else {
                    let up = (t - roll) * (figures.liftOff + 8)
                    guard up < Map3DAircraft.seenFrom else { return nil }
                    s = start + Map3DAircraft.thrust * roll * roll / 2 + up
                    height = up * Map3DAircraft.climb
                    pitch = 0.21
                }
            }
            // On the runway's own ground, held level past its ends.
            let share = Float(min(1, max(0, s / length)))
            let ground = Map3DPoint(from.x + forward.x * Float(s), from.y + (to.y - from.y) * share, from.z + forward.z * Float(s))
            return Drawn(ground: ground, height: Float(height), forward: forward, pitch: Float(pitch), kind: flight.kind, livery: flight.livery,
                         flying: true)
        }

        /// The aircraft at game second `second` (since the game began):
        /// those parked at the stands, and with `traffic` and not `still`
        /// those landing and leaving.
        public func aircraft(second: Double, traffic: Traffic?, still: Bool = false) -> [Drawn] {
            let day = Int64((second / Double(GameTime.secondsPerDay)).rounded(.down))
            let hour = Int((second - Double(day * GameTime.secondsPerDay)) / 3_600)
            let northEast = Self.landsNorthEast(day: day)
            var drawn: [Drawn] = []
            for field in fields {
                // Parked: six stands in ten, the same ones all day.
                let salt = Int32(truncatingIfNeeded: day)
                for (index, stand) in field.stands.enumerated() {
                    let r = { (n: Int32) in map3DRandom(field.seed &+ 101, Int32(index), salt: salt &* 4 &+ n) }
                    guard r(0) < 0.6, stand.room > 18 else { continue }
                    let kind = Self.kind(field, share: r(1), runway: field.runways[0].length, room: stand.room)
                    let length = Map3DAircraftStudies.dimensions(kind).length
                    drawn.append(Drawn(ground: stand.nose - stand.forward * (length / 2), height: 0, forward: stand.forward, pitch: 0, kind: kind,
                                       livery: Int(r(2) * Float(Map3DAircraft.liveries.count)) % Map3DAircraft.liveries.count, flying: false))
                }
                guard let traffic, !still, !field.airports.isEmpty else { continue }
                for offset in -1...1 {
                    let at = hour + offset
                    // The hours next to midnight take today's numbers.
                    let flights = Self.flights(of: field, day: at < 0 ? day - 1 : (at > 23 ? day + 1 : day), hour: (at + 24) % 24, traffic: traffic)
                    for flight in flights where abs(flight.time - second) < 400 {
                        if let pose = Self.pose(of: flight, on: field, second: second, northEast: northEast) { drawn.append(pose) }
                    }
                }
            }
            return drawn
        }

        /// The aircraft added to `frame`, seen from `eye`, with `pack`'s
        /// models: whole close up, their far models from farther, and a
        /// soft shadow under each.
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
            var whole = 0
            for (distance, aircraft) in seen {
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
