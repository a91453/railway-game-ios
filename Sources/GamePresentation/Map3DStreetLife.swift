import Foundation
import GameCore

// Decision 259: the people, scooters and cars of the 3D map's streets,
// seen only close up. Where they walk and drive is worked out with the
// still scene (``Map3DStreetLife/Lane``, ``Map3DStreetLife/Spot``); where
// each one is at a moment is worked out every frame from the clock alone,
// each from its own seed, so nothing is kept and GameCore never knows of
// them. How many there are follows the game: a station's crowd its
// passengers (waiting, and those who passed through), a street's its
// town's people and jobs.
//
// The models are this project's own block figures, sized after the
// reference's street scene (`Railway/street_scene_reference_clean`
// `street-agents.glb`: a figure 1.48–1.88 m tall, walking at 0.98–1.5 m/s;
// `scene.js`'s vehicles at 86–100% of the lane's limit) and after this
// repository's 3D city view (`Web/CityView/src/world/traffic.js`, MIT: the
// sedan's and the van's proportions, lanes 3 m wide kept to the right in
// Taiwan, a road's speed from its limit).

/// A street model and its shape.
public enum Map3DStreetModel: String, CaseIterable, Sendable {
    /// A walker mid-stride, its legs and arms swung (the walkers swap
    /// between this and ``standing`` a step at a time).
    case walking
    /// A figure standing, or the other half of a stride.
    case standing
    /// A scooter (機車) with its rider.
    case scooter
    /// A scooter carrying two.
    case scooterPair
    /// A small saloon car.
    case car
    /// A van or a tall hatchback.
    case van
    /// A 12 m city bus: drawn from the Meshy model the app bundles
    /// (``Map3DCityBus``); this box-built one stands in where that file
    /// cannot be read.
    case bus
    /// High-roof short-bonnet shuttle minibus, in teal and off-white.
    case shuttleBus
    /// Full-size front/middle-door low-floor bus, in warm white and blue.
    case lowFloorBus
    /// A three-axle high-deck touring coach, in off-white and warm red.
    case coachBus
    /// Rounded cab-over midibus, in warm white and teal.
    case midiBus

    /// The model's name in ``Map3DModelPack``.
    public var modelName: String { "life-" + rawValue }

    /// Any of the full-size buses or the high-roof shuttle.
    public var isBus: Bool { self == .bus || self == .shuttleBus || self == .lowFloorBus || self == .coachBus || self == .midiBus }

    /// Whether it is a figure on foot.
    public var isPerson: Bool { self == .walking || self == .standing }

    /// Its model, in the pack's space (+x the front, +y the left, +z up,
    /// its foot or wheels at the origin). Where the colour's alpha is 0
    /// (a figure's top, a vehicle's paint) the instance's colour shows.
    func model() -> Map3DModelPack.Model {
        var mesh = Map3DMesh()
        // Built in the scene's axes: x the front, y up, −z the left.
        func box(_ x: Float, _ y: Float, _ z: Float, _ length: Float, _ width: Float, _ height: Float, _ colour: UInt32) {
            mesh.addBox(base: Map3DPoint(x, y, z), forward: Map3DPoint(1, 0, 0), length: length, width: width, height: height, top: colour,
                        side: colour)
        }
        func glowing(_ build: () -> Void) {
            let first = mesh.vertices.count
            build()
            mesh.makeGlowing(from: first)
        }
        let tinted = Map3DColor.rgb(0xFFFFFF) & 0x00FF_FFFF
        switch self {
        case .shuttleBus: return Map3DShuttleBus.model()
        case .lowFloorBus: return Map3DLowFloorBus.model()
        case .coachBus: return Map3DCoachBus.model()
        case .midiBus: return Map3DMidiBus.model()
        case .walking, .standing:
            // A block figure 1.68 m tall: legs, a body and sleeves in the
            // instance's colour, a head and its hair.
            let swing: Float = self == .walking ? 0.13 : 0
            for side: Float in [-1, 1] {
                box(swing * side, 0, side * 0.09, 0.15, 0.14, 0.8, Self.trousers)
                box(-swing * side * 0.8, 0.86, side * 0.25, 0.12, 0.1, 0.52, tinted)
            }
            box(0, 0.8, 0, 0.24, 0.4, 0.58, tinted)
            box(0, 1.38, 0, 0.24, 0.24, 0.22, Self.skin)
            box(-0.01, 1.56, 0, 0.27, 0.27, 0.11, Self.hair)
        case .scooter, .scooterPair:
            // The scooter, 1.8 m long, painted in the instance's colour.
            for x: Float in [-0.6, 0.62] { box(x, 0, 0, 0.46, 0.13, 0.46, Self.tyre) }
            box(0.02, 0.2, 0, 1.0, 0.44, 0.22, tinted)
            box(-0.38, 0.38, 0, 0.72, 0.46, 0.36, tinted)
            box(0.46, 0.26, 0, 0.2, 0.5, 0.66, tinted)
            box(-0.36, 0.74, 0, 0.66, 0.38, 0.08, Self.seat)
            box(0.5, 0.96, 0, 0.08, 0.68, 0.06, Self.steel)
            glowing { box(0.57, 0.86, 0, 0.06, 0.2, 0.1, Self.headlamp) }
            glowing { box(-0.75, 0.5, 0, 0.04, 0.24, 0.08, Self.tailLamp) }
            // The rider, seated, hands on the bars, in a helmet.
            Self.addRider(to: &mesh, at: -0.2, shirt: Self.riderShirt, helmet: Self.helmets[1], reach: true)
            if self == .scooterPair {
                Self.addRider(to: &mesh, at: -0.62, shirt: Self.pillionShirt, helmet: Self.helmets[0], reach: false)
            }
        case .car, .van:
            // `traffic.js`'s sedan and van: length, width, the belt and the
            // roof, the glasshouse from z0 to z1 of the length.
            let spec: (length: Float, width: Float, belt: Float, roof: Float, z0: Float, z1: Float, rake: Float) =
                self == .car ? (4.4, 1.76, 0.92, 1.46, 0.2, 0.72, 0.7) : (4.6, 1.8, 1.04, 1.9, 0.08, 0.86, 0.45)
            let rear = -spec.length / 2, front = spec.length / 2
            for x in [rear + 0.85, front - 0.85] {
                for z: Float in [-1, 1] { box(x, 0, z * (spec.width / 2 - 0.12), 0.62, 0.22, 0.62, Self.tyre) }
            }
            box(0, 0.24, 0, spec.length, spec.width, spec.belt - 0.24, tinted)
            box(0, 0.22, 0, spec.length + 0.06, spec.width + 0.02, 0.16, Self.trim)
            // The glasshouse narrowing to the roof, its front leaning back.
            let c0 = rear + spec.z0 * spec.length, c1 = rear + spec.z1 * spec.length
            let low = spec.width * 0.45, high = spec.width * 0.38
            func corners(_ x0: Float, _ x1: Float, _ y: Float, _ half: Float) -> [Map3DPoint] {
                [Map3DPoint(x1, y, -half), Map3DPoint(x1, y, half), Map3DPoint(x0, y, half), Map3DPoint(x0, y, -half)]
            }
            let bottom = corners(c0, c1, spec.belt, low), top = corners(c0 + spec.rake * 0.4, c1 - spec.rake, spec.roof, high)
            for (from, to) in [(1, 0), (2, 1), (3, 2), (0, 3)] {
                mesh.addFacet([bottom[from], bottom[to], top[to], top[from]], color: Self.glass)
            }
            mesh.addFacet([top[0], top[3], top[2], top[1]], color: tinted)
            glowing {
                for z: Float in [-1, 1] { box(front - 0.02, spec.belt - 0.3, z * (spec.width / 2 - 0.26), 0.06, 0.36, 0.15, Self.headlamp) }
            }
            glowing {
                for z: Float in [-1, 1] { box(rear + 0.02, spec.belt - 0.28, z * (spec.width / 2 - 0.24), 0.06, 0.34, 0.14, Self.tailLamp) }
            }
        case .bus:
            // A Taiwanese low-floor city bus, 12 × 2.5 × 3.3 m: the body in
            // the instance's colour, the window band and windscreen, the
            // air conditioner on the roof, the lamps.
            for x: Float in [-3.4, 3.6] {
                for z: Float in [-1, 1] { box(x, 0, z * 1.1, 1.0, 0.3, 1.0, Self.tyre) }
            }
            box(0, 0.3, 0, 12, 2.5, 2.9, tinted)
            box(-0.2, 1.3, 0, 10.8, 2.54, 1.2, Self.glass)
            box(5.98, 0.85, 0, 0.06, 2.3, 1.95, Self.glass)
            box(-1.6, 3.2, 0, 3.4, 1.7, 0.22, Self.steel)
            Map3DCityBus.addLamps(to: &mesh)
        }
        return Map3DModelPack.Model.flat(named: modelName, from: mesh)
    }

    /// A seated rider whose seat is at `x`: legs on the floorboard, the
    /// body, arms to the bars when `reach`, the helmeted head.
    static func addRider(to mesh: inout Map3DMesh, at x: Float, shirt: UInt32, helmet: UInt32, reach: Bool) {
        func box(_ x: Float, _ y: Float, _ z: Float, _ length: Float, _ width: Float, _ height: Float, _ colour: UInt32) {
            mesh.addBox(base: Map3DPoint(x, y, z), forward: Map3DPoint(1, 0, 0), length: length, width: width, height: height, top: colour,
                        side: colour)
        }
        box(x + 0.22, 0.78, 0, 0.44, 0.34, 0.15, trousers)
        box(x + 0.42, 0.32, 0, 0.14, 0.3, 0.48, trousers)
        box(x - 0.04, 0.86, 0, 0.26, 0.38, 0.54, shirt)
        if reach {
            for z: Float in [-1, 1] { box(x + 0.32, 1.18, z * 0.21, 0.56, 0.1, 0.1, shirt) }
        }
        box(x - 0.02, 1.38, 0, 0.24, 0.24, 0.2, skin)
        box(x - 0.03, 1.5, 0, 0.32, 0.32, 0.18, helmet)
    }

    static let trousers = Map3DColor.rgb(0x3E4A66)
    static let skin = Map3DColor.rgb(0xEDC4A0)
    static let hair = Map3DColor.rgb(0x2C2A30)
    static let tyre = Map3DColor.rgb(0x2B2E34)
    static let seat = Map3DColor.rgb(0x33363D)
    static let steel = Map3DColor.rgb(0x9AA0A8)
    static let trim = Map3DColor.rgb(0x41464F)
    static let glass = Map3DColor.rgb(0x26313D)
    static let headlamp = Map3DColor.rgb(0xFFF4D6)
    static let tailLamp = Map3DColor.rgb(0xE0402F)
    static let riderShirt = Map3DColor.rgb(0x2F6DB5)
    static let pillionShirt = Map3DColor.rgb(0xE8574A)
    /// The helmets: the app's warm yellow and white.
    static let helmets = [Map3DColor.rgb(0xFFC86B), Map3DColor.rgb(0xF2F2EE)]
}

/// How much street life a device draws (decision 259): the most figures
/// and vehicles in a frame, the nearest first.
public enum Map3DStreetDetail: Int, CaseIterable, Comparable, Sendable {
    case off, reduced, full

    public var people: Int {
        switch self {
        case .off: 0
        case .reduced: 500
        case .full: 1_400
        }
    }

    public var vehicles: Int {
        switch self {
        case .off: 0
        case .reduced: 150
        case .full: 400
        }
    }

    /// One step less, when a device cannot hold its frame rate.
    public var lowered: Map3DStreetDetail { Map3DStreetDetail(rawValue: max(rawValue - 1, 0)) ?? .off }

    /// What a device whose GPU is of Apple family `family` (Metal's
    /// `MTLGPUFamily.apple1`… as a number) draws to begin with: everything
    /// from the A15 (family 8, iPhone 13) on, less on the A12–A14, nothing
    /// older.
    public static func forGPUFamily(_ family: Int) -> Map3DStreetDetail {
        family >= 8 ? .full : family >= 5 ? .reduced : .off
    }

    /// Whether `framesPerSecond`, measured `windows` half seconds in a row
    /// below what the device aims for, says to draw less.
    public static func shouldLower(framesPerSecond: Double, aim: Double, windows: Int) -> Bool {
        windows >= 3 && framesPerSecond < aim * 0.75
    }

    public static func < (a: Map3DStreetDetail, b: Map3DStreetDetail) -> Bool { a.rawValue < b.rawValue }
}

/// Where the 3D map's people walk and its vehicles drive (decision 259),
/// made with the still scene, and the figures and vehicles of a frame.
public struct Map3DStreetLife: Sendable {
    /// A line along the ground in scene metres, with the way to its right
    /// at each point and how far along each point is.
    public struct Path: Sendable {
        public let points: [Map3DPoint]
        let rights: [Map3DPoint]
        let distances: [Float]
        public var length: Float { distances.last ?? 0 }
        let minimum: (x: Float, z: Float)
        let maximum: (x: Float, z: Float)

        /// `points` (at least two, a metre or more long), or `nil`.
        public init?(_ points: [Map3DPoint]) {
            var kept: [Map3DPoint] = []
            for point in points where kept.last.map({ ($0 - point).length > 0.05 }) ?? true { kept.append(point) }
            guard kept.count >= 2 else { return nil }
            var distances: [Float] = [0]
            for index in 1..<kept.count {
                let a = kept[index - 1], b = kept[index]
                distances.append(distances[index - 1] + Map3DPoint(b.x - a.x, 0, b.z - a.z).length)
            }
            guard let total = distances.last, total >= 1 else { return nil }
            self.points = kept
            self.distances = distances
            rights = Map3DMesh.acrossDirections(kept)
            minimum = (kept.map(\.x).min() ?? 0, kept.map(\.z).min() ?? 0)
            maximum = (kept.map(\.x).max() ?? 0, kept.map(\.z).max() ?? 0)
        }

        /// The point `distance` along, the level way along there and the
        /// way to its right.
        public func at(_ distance: Float) -> (point: Map3DPoint, along: Map3DPoint, right: Map3DPoint) {
            let d = min(max(distance, 0), length)
            var low = 0, high = distances.count - 1
            while high - low > 1 {
                let middle = (low + high) / 2
                if distances[middle] <= d { low = middle } else { high = middle }
            }
            let a = points[low], b = points[high]
            let span = distances[high] - distances[low]
            let t = span > 0 ? (d - distances[low]) / span : 0
            let along = Map3DPoint(b.x - a.x, 0, b.z - a.z).normalized ?? Map3DPoint(1, 0, 0)
            let right = Map3DPoint(-along.z, 0, along.x)
            return (a + (b - a) * t, along, right)
        }

        /// This path moved `offset` metres to its right (left when less
        /// than 0), each point along its own way to the right.
        func shifted(_ offset: Float) -> Path? {
            Path(zip(points, rights).map { $0 + $1 * offset })
        }

        /// How far it is, on the level, from point `p`, at most: the
        /// distance to its bounding box.
        func boxDistance(to p: Map3DPoint) -> Float {
            let dx = max(minimum.x - p.x, 0, p.x - maximum.x), dz = max(minimum.z - p.z, 0, p.z - maximum.z)
            return (dx * dx + dz * dz).squareRoot()
        }
    }

    /// A road's vehicles: its middle line, both ways or one, how fast and
    /// how many.
    public struct Lane: Sendable {
        public let path: Path
        /// Half the carriageway's width, metres.
        public let half: Float
        public let twoWay: Bool
        /// Metres a second, every vehicle on it alike, so none run into
        /// one another.
        public let speed: Float
        /// Vehicles each way every 100 m.
        public let perHundred: Float
        /// Whether scooters may use it (not on a motorway).
        public let scooters: Bool
        let seed: (Int32, Int32)
        /// Whether city buses run on it (a main road's).
        public var buses = false
    }

    /// Where people gather or walk.
    public struct Spot: Sendable {
        public enum Kind: Sendable {
            /// On a platform, waiting for the train: as many as are waiting.
            case platform
            /// Outside a station: as many as its passengers in a day.
            case stationFront
            /// Along a row of shops (the arcade, 騎樓).
            case shops
            /// A temple's forecourt.
            case temple
            /// A street's pavement.
            case sidewalk

            /// Whether fewer are out at night (not at a station or a
            /// temple, which stay busy).
            var thinsAtNight: Bool {
                switch self {
                case .platform, .stationFront, .temple: false
                case .shops, .sidewalk: true
                }
            }

            /// The share of its people standing still, the rest walking up
            /// and down.
            var standing: Float {
                switch self {
                case .platform: 0.85
                case .temple: 0.45
                case .stationFront: 0.3
                case .shops: 0.35
                case .sidewalk: 0
                }
            }
        }

        public let kind: Kind
        public let path: Path
        /// How far either side of its line its people stand, metres.
        public let width: Float
        /// Its people, for a spot that is not a station's (those follow its
        /// passengers, ``Activity``).
        public let people: Int
        public let station: StationID?
        let seed: (Int32, Int32)
    }

    public internal(set) var lanes: [Lane] = []
    public internal(set) var spots: [Spot] = []

    public init() {}

    // MARK: How many

    /// `cap` times one less e to the minus `amount` over `per`: none for
    /// nothing, rising quickly at first and never past `cap`, so a busy
    /// station shows busier without filling the screen.
    static func shown(_ amount: Double, per: Double, cap: Int) -> Int {
        guard amount > 0, per > 0 else { return 0 }
        return Int((Double(cap) * (1 - exp(-amount / per))).rounded())
    }

    /// The figures waiting on one of a station's `platforms` platforms
    /// when `waiting` people wait there.
    public static func platformCrowd(waiting: Int64, platforms: Int) -> Int {
        shown(Double(waiting) / Double(max(platforms, 1)), per: 150, cap: 36)
    }

    /// The figures outside a station `trips` people passed through in a
    /// day: a few at any station, up to 60 at a busy one.
    public static func frontCrowd(trips: Int64) -> Int {
        2 + shown(Double(trips), per: 6_000, cap: 58)
    }

    /// How lively a street is, 0–1, with `residentsAndJobs` people living
    /// and working in the nine 64 m cells round it.
    public static func townLevel(_ residentsAndJobs: Int64) -> Float {
        Float(1 - exp(-Double(max(residentsAndJobs, 0)) / 2_400))
    }

    /// The crowds at the stations now: on each platform and outside each
    /// station, by station.
    public struct Activity: Sendable {
        public var platform: [StationID: Int] = [:]
        public var front: [StationID: Int] = [:]

        public init() {}

        /// From `world`'s stations with platforms: those waiting, and the
        /// most who passed through in a day of yesterday and today so far.
        public init(world: GameWorld) {
            var platforms: [StationID: Int] = [:]
            for platform in world.network.platforms { platforms[platform.station, default: 0] += 1 }
            let seconds = world.clock.now.seconds, day = GameTime.secondsPerDay
            let today = seconds >= 0 ? seconds / day : -((-seconds + day - 1) / day)
            for (station, count) in platforms {
                let waiting = world.waitingPassengers(at: station).reduce(Int64(0)) { $0 + $1.count }
                let yesterday = world.stationFlow(station, onDay: today - 1)?.people ?? 0
                let sofar = world.stationFlow(station, onDay: today)?.people ?? 0
                platform[station] = Map3DStreetLife.platformCrowd(waiting: waiting, platforms: count)
                front[station] = Map3DStreetLife.frontCrowd(trips: max(yesterday, sofar))
            }
        }
    }

    // MARK: A frame

    /// Within this camera distance, metres, people are drawn; within
    /// ``vehiclesFrom``, vehicles. Farther, none: a figure would be a dot.
    public static let peopleFrom: Float = 500
    public static let vehiclesFrom: Float = 1_300

    /// How far round the camera's target figures and vehicles are drawn
    /// at a camera distance, metres; they shrink away over the last
    /// ``fadeShare`` of it.
    static func peopleReach(_ distance: Float) -> Float { 120 + distance * 0.7 }
    static func vehiclesReach(_ distance: Float) -> Float { 200 + distance * 0.8 }
    static let fadeShare: Float = 0.15

    /// The models' places in ``Map3DModelPack/standard``.
    static let models: [Map3DStreetModel: Int] = Dictionary(uniqueKeysWithValues: Map3DStreetModel.allCases.compactMap { model in
        Map3DModelPack.standard.index(of: model.modelName).map { (model, $0) }
    })

    /// The figures' tops: bright and many, as a busy Taiwanese street's.
    public static let shirts: [UInt32] = [0xE8574A, 0x3B7DD8, 0x12A08F, 0xFFC86B, 0xF2F2EE, 0x8E6CC9, 0xF29BB0, 0x6FA85A, 0x2E3550, 0xF08A3C]
        .map(Map3DColor.rgb)
    /// The cars' paint: white and silver most, then red, dark, blue and the
    /// taxis' yellow.
    public static let carPaints: [UInt32] = [0xF2F3F1, 0xF2F3F1, 0xC3C8CF, 0xC3C8CF, 0xD9473F, 0x3A4150, 0x3B6FB6, 0xF2C230]
        .map(Map3DColor.rgb)
    /// The buses' paint: the reference's street scene's (HANDOFF §4.3:
    /// teal, blue, white, green), the colours of Taiwan's city buses.
    public static let busPaints: [UInt32] = [0x3E8C8C, 0x4E78A8, 0xF2F2F0, 0x5E9A78].map(Map3DColor.rgb)
    /// One vehicle in this many on a road buses run on is a bus; at most
    /// ``mostBuses`` are drawn (the model's budget,
    /// `docs/research/MESHY_TRIAL_MODEL_SPEC_2026-10-17.md`).
    public static let busShare: Float = 0.05
    public static let mostBuses = 30
    /// A bus takes a place only where the vehicles are this far apart, so
    /// that, with each one's start drawn up to 0.4 of it early, the car
    /// next to it never reaches it; and never right behind another bus
    /// (the place before it, round the lane), so that two buses are at
    /// least 1.6 of it apart, more than the longest bus
    /// (``Map3DCoachBus``).
    static let busSpacing: Float = 17

    /// The scooters' paint.
    public static let scooterPaints: [UInt32] = [0xF2F3F1, 0xC3C8CF, 0x3A4150, 0xD9473F, 0x3B7DD8, 0x8FD3C4, 0xF2C230].map(Map3DColor.rgb)

    /// A frame's figures and vehicles, and how many of each.
    public struct Frame: Sendable {
        public var instances: [Map3DInstance] = []
        public var people = 0
        public var vehicles = 0
        /// Of the vehicles, the buses.
        public var buses = 0
    }

    /// The figures and vehicles at `time` (seconds of any clock) round
    /// `target` seen from `distance` away, at most `detail`'s, the nearest
    /// spots and roads first. When `still` (Reduce Motion) nobody moves:
    /// everyone stands where they would be at the clock's start. With the
    /// city's `lights` on (``Map3DLighting/lights``, 0–1), the streets and
    /// shops have up to half their people.
    /// Decision 400, 10i-6: the player's route `buses` come first, counted
    /// with the vehicles and the buses, and the road's own vehicles give
    /// way where one stands.
    public func frame(target: Map3DPoint, distance: Float, time: Double, still: Bool = false, lights: Float = 0, detail: Map3DStreetDetail,
                      activity: Activity, buses: Map3DBuses.Frame = .init()) -> Frame {
        var frame = Frame()
        guard detail != .off, Self.models.count == Map3DStreetModel.allCases.count else { return frame }
        frame.instances = buses.instances
        frame.vehicles = buses.instances.count
        frame.buses = buses.instances.count
        let clock = still ? 0 : time
        if distance <= Self.peopleFrom {
            let reach = Self.peopleReach(distance)
            let near = spots.indices.compactMap { index -> (Int, Float)? in
                let away = spots[index].path.boxDistance(to: target)
                return away < reach ? (index, away) : nil
            }.sorted { $0.1 < $1.1 }
            for (index, _) in near where frame.people < detail.people {
                addPeople(of: spots[index], to: &frame, target: target, reach: reach, time: clock, still: still, lights: lights,
                          budget: detail.people, activity: activity)
            }
        }
        if distance <= Self.vehiclesFrom {
            let reach = Self.vehiclesReach(distance)
            let near = lanes.indices.compactMap { index -> (Int, Float)? in
                let away = lanes[index].path.boxDistance(to: target)
                return away < reach ? (index, away) : nil
            }.sorted { $0.1 < $1.1 }
            for (index, _) in near where frame.vehicles < detail.vehicles {
                addVehicles(of: lanes[index], to: &frame, target: target, reach: reach, time: clock, budget: detail.vehicles, clearOf: buses.clear)
            }
        }
        return frame
    }

    /// How big something `away` metres from the target is drawn when
    /// things are drawn within `reach`: whole, shrinking to nothing over
    /// the last ``fadeShare``.
    static func fade(_ away: Float, reach: Float) -> Float {
        min(max((reach - away) / (reach * fadeShare), 0), 1)
    }

    private func addPeople(of spot: Spot, to frame: inout Frame, target: Map3DPoint, reach: Float, time: Double, still: Bool, lights: Float,
                           budget: Int, activity: Activity) {
        var count: Int
        switch spot.kind {
        case .platform: count = spot.station.flatMap { activity.platform[$0] } ?? 0
        case .stationFront: count = spot.station.flatMap { activity.front[$0] } ?? 0
        default: count = spot.people
        }
        if spot.kind.thinsAtNight { count = Int((Float(count) * (1 - 0.5 * min(max(lights, 0), 1))).rounded()) }
        let length = spot.path.length
        for index in 0..<count where frame.people < budget {
            let r = { (salt: Int32) in map3DRandom(spot.seed.0 &+ Int32(index), spot.seed.1, salt: salt) }
            let scale = 0.88 + 0.24 * r(3)
            let tint = Self.shirts[min(Int(r(4) * Float(Self.shirts.count)), Self.shirts.count - 1)]
            let across = (r(2) * 2 - 1) * spot.width
            let at: Float, facing: Map3DPoint, model: Map3DStreetModel
            if r(1) < spot.kind.standing {
                at = r(5) * length
                let place = spot.path.at(at)
                // Turned some way, more often across the line (to a train,
                // a shop window, the temple) than along it.
                let turn = (r(6) - 0.5) * Float.pi * 1.2
                let base = r(7) < 0.5 ? place.right : -place.right
                facing = base * cosf(turn) + place.along * sinf(turn)
                model = .standing
            } else {
                // Up and down the line at its own pace.
                let pace = Double(0.98 + 0.52 * r(6))
                let travelled = Double(r(5)) * 2 * Double(length) + pace * time
                let lap = travelled.truncatingRemainder(dividingBy: 2 * Double(length))
                let outward = lap < Double(length)
                at = Float(outward ? lap : 2 * Double(length) - lap)
                let along = spot.path.at(at).along
                facing = outward ? along : -along
                let step = Int((travelled / (0.72 * Double(scale))).rounded(.down))
                model = still || step.isMultiple(of: 2) ? .standing : .walking
            }
            let place = spot.path.at(at)
            let foot = place.point + place.right * across
            let away = Map3DPoint(foot.x - target.x, 0, foot.z - target.z).length
            let size = Self.fade(away, reach: reach)
            guard size > 0, let index = Self.models[model] else { continue }
            frame.instances.append(.prop(index, at: foot, forward: facing, scale: scale * size, tint: tint))
            frame.people += 1
        }
    }

    private func addVehicles(of lane: Lane, to frame: inout Frame, target: Map3DPoint, reach: Float, time: Double, budget: Int,
                             clearOf buses: [(point: Map3DPoint, along: Map3DPoint)] = []) {
        // Decision 400, 10i-6: only the player's buses near this road.
        let buses = buses.filter { lane.path.boxDistance(to: $0.point) < Self.busClearance.along + lane.half }
        let length = lane.path.length
        // At least 9 m from one to the next: a car and its gap.
        let count = min(Int((length / 100 * lane.perHundred).rounded()), Int(length / 9))
        guard count > 0 else { return }
        let spacing = length / Float(count)
        // Kept to the right (Taiwan): a car in the middle of its half, a
        // scooter nearer the kerb where there is room.
        let carSide: Float = lane.twoWay ? max(lane.half * 0.5, 1.2) : 0
        let scooterSide = carSide + max(min(1.1, lane.half - carSide - 0.5), 0)
        for direction: Float in lane.twoWay ? [1, -1] : [1] {
            for index in 0..<count where frame.vehicles < budget {
                let draw = { (index: Int, salt: Int32) in map3DRandom(lane.seed.0 &+ Int32(index), lane.seed.1 &+ Int32(direction), salt: salt) }
                let r = { (salt: Int32) in draw(index, salt) }
                let start = (Float(index) + 0.4 * r(1)) * spacing
                let travelled = (Double(start) + Double(lane.speed) * time).truncatingRemainder(dividingBy: Double(length))
                let along = direction > 0 ? Float(travelled) : length - Float(travelled)
                let kind = r(2)
                let model: Map3DStreetModel
                if lane.buses, spacing >= Self.busSpacing, frame.buses < Self.mostBuses, r(5) < Self.busShare,
                   count == 1 || draw((index + count - 1) % count, 5) >= Self.busShare {
                    let variant = r(6)
                    model = variant < 0.30 ? .shuttleBus : variant < 0.65 ? .lowFloorBus : variant < 0.85 ? .coachBus : variant < 0.95 ? .midiBus : .bus
                } else if lane.scooters {
                    model = kind < 0.5 ? .scooter : kind < 0.62 ? .scooterPair : kind < 0.9 ? .car : .van
                } else {
                    model = kind < 0.75 ? .car : .van
                }
                let place = lane.path.at(along)
                let side = model.isScooter ? scooterSide : carSide
                let foot = place.point + place.right * (side * direction)
                let away = Map3DPoint(foot.x - target.x, 0, foot.z - target.z).length
                // Coming out of and going into the road's ends.
                // Use the chosen bus body length, rather than the car fade distance.
                let ends = min(max(min(along, length - along) / (model == .shuttleBus ? Map3DShuttleBus.length : model == .lowFloorBus ? Map3DLowFloorBus.length : model == .coachBus ? Map3DCoachBus.length : model == .midiBus ? Map3DMidiBus.length : model == .bus ? 12 : 4), 0), 1)
                let size = Self.fade(away, reach: reach) * ends * Self.giveWay(at: foot, to: buses)
                guard size > 0, let index = Self.models[model] else { continue }
                let paints = model.isBus ? Self.busPaints : model.isScooter ? Self.scooterPaints : Self.carPaints
                let tint = paints[min(Int(r(3) * Float(paints.count)), paints.count - 1)]
                frame.instances.append(.prop(index, at: foot, forward: place.along * direction, scale: size, tint: tint))
                frame.vehicles += 1
                if model.isBus { frame.buses += 1 }
            }
        }
    }
}

extension Map3DStreetLife {
    /// Decision 400, 10i-6: how near a player's bus a road's vehicle is
    /// not drawn, along the bus and across it (a 12 m bus and a car's
    /// half), metres; it shrinks away over ``busClearance`` `fade` more.
    static let busClearance: (along: Float, across: Float, fade: Float) = (8.5, 2.2, 5)

    /// How much of a road's vehicle at `foot` is drawn beside the player's
    /// `buses`: none over one, shrinking as one comes near along its way.
    static func giveWay(at foot: Map3DPoint, to buses: [(point: Map3DPoint, along: Map3DPoint)]) -> Float {
        var size: Float = 1
        for bus in buses {
            let offset = Map3DPoint(foot.x - bus.point.x, 0, foot.z - bus.point.z)
            let across = abs(offset.x * -bus.along.z + offset.z * bus.along.x)
            guard across < busClearance.across else { continue }
            let along = abs(offset.x * bus.along.x + offset.z * bus.along.z)
            size = min(size, min(max((along - busClearance.along) / busClearance.fade, 0), 1))
        }
        return size
    }
}

extension Map3DStreetModel {
    var isScooter: Bool { self == .scooter || self == .scooterPair }
}

// MARK: - Laying them out with the scene

extension Map3DScene.Builder {
    /// A seed from where a scene point is in the world, the same however
    /// the scene's origin moves as track is laid.
    func lifeSeed(_ point: Map3DPoint, salt: Int32) -> (Int32, Int32) {
        let x = Int((Double(point.x) + originX / Self.metre).rounded()), z = Int((Double(point.z) + originY / Self.metre).rounded())
        return (Int32(truncatingIfNeeded: x) &* 31 &+ salt, Int32(truncatingIfNeeded: z))
    }

    /// The people living and working in the nine 64 m cells round scene
    /// point `point`.
    func residentsAndJobs(near point: Map3DPoint) -> Int64 {
        let column = gridCell(Double(point.x), origin: originX), row = gridCell(Double(point.z), origin: originY)
        var total: Int64 = 0
        for dr in -1...1 {
            for dc in -1...1 {
                if let cell = world.land.cell(row: row + dr, column: column + dc) { total += cell.residents + cell.jobs }
            }
        }
        return total
    }

    /// Decision 259: a road of the base map as lanes and, where it has
    /// them, pavements: each kept to its tile, at the road's height.
    mutating func addStreetLife(_ road: Map3DBaseMap.Road) {
        let lift = Self.lift(of: road.kind) + 0.02
        // The road's runs inside its tile.
        var runs: [[Map3DBaseMap.Point]] = []
        for index in 1..<road.points.count {
            guard let (a, b) = Self.clipSegment(road.points[index - 1], road.points[index], to: road.bounds) else { continue }
            if let last = runs.last?.last, abs(last.x - a.x) < 0.01, abs(last.z - a.z) < 0.01 {
                runs[runs.count - 1].append(b)
            } else {
                runs.append([a, b])
            }
        }
        let kind = road.kind
        // Every 16 m at most, so the line keeps to the ground; decision
        // 375: in pieces, apart where the road gives way to a trench
        // (looked at every 2 m near one, and near a bridge, decision 391).
        var lines: [[Map3DPoint]] = []
        for run in runs {
            var points: [Map3DPoint] = []
            func add(_ x: Double, _ z: Double, along: (x: Double, z: Double)) {
                // Decision 391: at the road's height on a bridge or its
                // ramp, over any trench.
                let raised = roadRise(at: Map3DBaseMap.Point(x: x, z: z), along: along, onDeck: road.bridgeLevel > 0)
                if !raised.onBridge && givesWay(at: Map3DBaseMap.Point(x: x, z: z), along: along) {
                    if points.count > 1 { lines.append(points) }
                    points = []
                } else {
                    points.append(groundPoint(x: x, z: z, lift: lift) + Map3DPoint(0, raised.rise, 0))
                }
            }
            for (index, point) in run.enumerated() {
                guard index > 0 else {
                    let next = run.count > 1 ? run[1] : point, length = max(0.01, ((next.x - point.x) * (next.x - point.x) + (next.z - point.z) * (next.z - point.z)).squareRoot())
                    add(point.x, point.z, along: ((next.x - point.x) / length, (next.z - point.z) / length))
                    continue
                }
                let previous = run[index - 1]
                let length = ((point.x - previous.x) * (point.x - previous.x) + (point.z - previous.z) * (point.z - previous.z)).squareRoot()
                let near = !trackCover.trenches.pieces(minX: min(previous.x, point.x), minZ: min(previous.z, point.z),
                                                       maxX: max(previous.x, point.x), maxZ: max(previous.z, point.z)).isEmpty
                    || nearRaisedRoad(from: previous, to: point)
                let along = length > 0.01 ? ((point.x - previous.x) / length, (point.z - previous.z) / length) : (1.0, 0.0)
                let steps = max(1, Int((length / (near ? 2 : 16)).rounded(.up)))
                for step in 1...steps {
                    let t = Double(step) / Double(steps)
                    add(previous.x + (point.x - previous.x) * t, previous.z + (point.z - previous.z) * t, along: along)
                }
            }
            if points.count > 1 { lines.append(points) }
        }
        for points in lines {
            guard let path = Map3DStreetLife.Path(points) else { continue }
            let middle = path.at(path.length / 2).point
            let level = Map3DStreetLife.townLevel(residentsAndJobs(near: middle))
            let half = kind.width(ramp: road.isRamp) / 2
            if let traffic = Self.traffic(kind) {
                streetLife.lanes.append(Map3DStreetLife.Lane(
                    path: path, half: half, twoWay: !road.isRamp && kind != .motorway, speed: traffic.speed,
                    perHundred: traffic.perHundred * (0.25 + 0.75 * level), scooters: kind != .motorway && kind != .trunk || level > 0.5,
                    seed: lifeSeed(path.points[0], salt: 256), buses: !road.isRamp && Self.busRoutes.contains(kind)))
            }
            let sidewalk = Self.sidewalk(of: kind)
            guard sidewalk > 0, !road.isRamp else { continue }
            let people = Int((path.length / 100 * 4 * level).rounded())
            guard people > 0 else { continue }
            for side: Float in [1, -1] {
                guard let walk = path.shifted(side * (half + sidewalk / 2)) else { continue }
                // On the pavement, which lies lower than the road.
                let lowered = walk.points.map { Map3DPoint($0.x, $0.y - lift + Self.sidewalkLift + 0.02, $0.z) }
                guard let pavement = Map3DStreetLife.Path(lowered) else { continue }
                streetLife.spots.append(Map3DStreetLife.Spot(kind: .sidewalk, path: pavement, width: sidewalk * 0.3, people: people, station: nil,
                                                             seed: lifeSeed(pavement.points[0], salt: side > 0 ? 257 : 258)))
            }
        }
    }

    /// A point on the drawn ground `lift` over it, and (decision 263) over
    /// a level crossing's deck where one is.
    mutating func groundPoint(x: Double, z: Double, lift: Float) -> Map3DPoint {
        Map3DPoint(Float(x), drawnGround(x: Float(x), z: Float(z)) + lift + crossingLift(x: Float(x), z: Float(z)), Float(z))
    }

    /// The roads city buses run on: the main ones, through towns, not
    /// the motorways or the side streets.
    static let busRoutes: Set<Map3DBaseMap.RoadKind> = [.trunk, .primary, .secondary]

    /// How fast a road's vehicles go (`traffic.js`: its limit, 0.8 of it
    /// on a main road and 0.6 on a minor one, kept to 4.5–15 m/s; Taiwan's
    /// limits) and how many it has every 100 m each way in a busy town;
    /// `nil` for a road with none.
    static func traffic(_ kind: Map3DBaseMap.RoadKind) -> (speed: Float, perHundred: Float)? {
        func speed(_ limit: Float, minor: Bool) -> Float { min(15, max(4.5, limit * (minor ? 0.6 : 0.8) / 3.6)) }
        switch kind {
        case .motorway: return (speed(100, minor: false), 3)
        case .trunk: return (speed(70, minor: false), 4)
        case .primary: return (speed(50, minor: false), 4)
        case .secondary: return (speed(50, minor: false), 3.2)
        case .tertiary: return (speed(50, minor: false), 2.4)
        case .minor: return (speed(40, minor: true), 1.2)
        case .service: return nil
        }
    }

    /// Decision 259: a platform's waiting crowd on it, and outside it, on
    /// the side away from the track, the station's passengers coming and
    /// going.
    mutating func addStationLife(line: [Map3DPoint], offset: Float, width: Float, station: StationID) {
        let top = line.map { $0 + Map3DPoint(0, Self.platformHeight + 0.01, 0) }
        guard let middle = Map3DStreetLife.Path(top), let platform = middle.shifted(offset) else { return }
        streetLife.spots.append(Map3DStreetLife.Spot(kind: .platform, path: platform, width: max(width / 2 - 0.6, 0.2), people: 0, station: station,
                                                     seed: lifeSeed(platform.points[0], salt: 262)))
        let side: Float = offset >= 0 ? 1 : -1
        guard let outside = middle.shifted(offset + side * (width / 2 + 5)) else { return }
        // On the ground beside the station.
        var ground: [Map3DPoint] = []
        for point in outside.points { ground.append(groundPoint(x: Double(point.x), z: Double(point.z), lift: 0.05)) }
        guard let front = Map3DStreetLife.Path(ground) else { return }
        streetLife.spots.append(Map3DStreetLife.Spot(kind: .stationFront, path: front, width: 2.5, people: 0, station: station,
                                                     seed: lifeSeed(front.points[0], salt: 263)))
    }

    /// Decision 259: shoppers along a row of shops from `from` to `to`,
    /// more where the town is denser.
    mutating func addShopLife(from: Map3DPoint, to: Map3DPoint, density: Int) {
        guard target == .near, let path = Map3DStreetLife.Path([from, to]) else { return }
        let people = Int((path.length / 40 * Float(3 + 2 * density)).rounded())
        streetLife.spots.append(Map3DStreetLife.Spot(kind: .shops, path: path, width: 1.2, people: people, station: nil,
                                                     seed: lifeSeed(from, salt: 264)))
    }

    /// Decision 259: worshippers and visitors on a temple's forecourt.
    /// Decision 268: as wide and as many as the forecourt holds.
    mutating func addTempleLife(from: Map3DPoint, to: Map3DPoint, width: Float = 3, people: Int = 12) {
        guard target == .near, let path = Map3DStreetLife.Path([from, to]) else { return }
        streetLife.spots.append(Map3DStreetLife.Spot(kind: .temple, path: path, width: width, people: people, station: nil, seed: lifeSeed(from, salt: 265)))
    }
}
