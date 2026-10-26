// Decision 417: what moves on the 3D map (the trains, the player's buses,
// the streets' people and vehicles) shares one budget of triangles a
// frame. The player's trains and buses come first, never fewer; the
// streets have what is left, their scooters and cars giving way before
// their people. And a device that cannot keep up draws less a step at a
// time (``Map3DLoadStep``): the streets, then the trains' far models
// nearer, then fewer pixels; once it keeps up again for a while, a step
// back.

/// How many of the streets' figures and vehicles a frame draws at most:
/// the people, the vehicles (the player's buses among them) and, of those,
/// the buses.
public struct Map3DStreetLimits: Equatable, Sendable {
    public var people: Int
    public var vehicles: Int
    public var buses: Int

    public init(people: Int, vehicles: Int, buses: Int) {
        self.people = people
        self.vehicles = vehicles
        self.buses = buses
    }

    /// All `detail` draws (decision 259), with ``Map3DStreetLife/mostBuses``.
    public init(_ detail: Map3DStreetDetail) {
        self.init(people: detail.people, vehicles: detail.vehicles, buses: detail == .off ? 0 : Map3DStreetLife.mostBuses)
    }
}

/// Decision 417: the triangles a frame's moving things may take, and how
/// many of the streets' it leaves room for.
public struct Map3DMotionBudget: Equatable, Sendable {
    /// What the device draws of the streets to begin with (its GPU's).
    public var detail: Map3DStreetDetail
    /// How far it has stepped down under load.
    public var step: Map3DLoadStep
    /// The trains' triangles this frame: their models' and their boxes'.
    public var trainTriangles: Int

    public init(detail: Map3DStreetDetail, step: Map3DLoadStep = .full, trainTriangles: Int = 0) {
        self.detail = detail
        self.step = step
        self.trainTriangles = trainTriangles
    }

    /// The triangles of everything that moves, by the device's detail: on
    /// the A15 and later what the streets draw in full and 400,000 for the
    /// trains and buses besides; on the A12–A14 under half of it.
    public static func triangles(for detail: Map3DStreetDetail) -> Int {
        switch detail {
        case .off: 0
        case .reduced: 250_000
        case .full: 600_000
        }
    }

    /// A figure's triangles (``Map3DStreetModel/walking``, `standing`).
    public static let personTriangles = 70
    /// A street vehicle's, on average: half scooters (160 and 210), the
    /// rest cars and vans (110).
    public static let vehicleTriangles = 150
    /// A bus's, on average: the low-floor bus's 2,212 to the coach's 2,884
    /// (the shuttle's 1,434 among them): as many as 15 cars.
    public static let busTriangles = 2_300
    /// The fewest of their own the streets keep, however busy the lines,
    /// so that a town never stands empty: a tenth.
    public static let leastShare: Float = 0.1

    /// The streets' limits with `routeBuses` of the player's buses to draw
    /// (decision 400, 10i-6): the trains and those buses first; the
    /// streets' vehicles (their buses, which share
    /// ``Map3DStreetLife/mostBuses`` with the player's, among them) from
    /// what is left, then their people; at least ``leastShare`` of each,
    /// and at most ``Map3DLoadStep/streetShare``.
    public func limits(routeBuses: Int = 0) -> Map3DStreetLimits {
        guard detail != .off else { return Map3DStreetLimits(.off) }
        let full = Map3DStreetLimits(detail)
        let streetBuses = max(full.buses - routeBuses, 0)
        let left = Float(Self.triangles(for: detail) - trainTriangles - routeBuses * Self.busTriangles)
        let vehicles = Float(full.vehicles * Self.vehicleTriangles + streetBuses * Self.busTriangles)
        let people = Float(full.people * Self.personTriangles)
        func share(_ room: Float, of cost: Float) -> Float { cost > 0 ? min(max(room / cost, Self.leastShare), 1) : 1 }
        let vehicleShare = min(share(left - people, of: vehicles), step.streetShare)
        let peopleShare = min(share(left - Self.leastShare * vehicles, of: people), step.streetShare)
        func part(_ count: Int, _ share: Float) -> Int { Int((Float(count) * share).rounded()) }
        return Map3DStreetLimits(people: part(full.people, peopleShare), vehicles: routeBuses + part(full.vehicles, vehicleShare),
                                 buses: routeBuses + part(streetBuses, vehicleShare))
    }
}

/// Decision 417: how far a device that cannot keep up has stepped down,
/// in order: fewer of the streets' people and vehicles, then fewest, then
/// the trains' far models nearer, then fewer pixels.
public enum Map3DLoadStep: Int, CaseIterable, Comparable, Sendable {
    case full, fewerOnStreets, fewestOnStreets, nearerFarModels, fewerPixels

    /// The most of the streets' people and vehicles drawn (``Map3DMotionBudget/limits(routeBuses:)``).
    public var streetShare: Float {
        switch self {
        case .full: 1
        case .fewerOnStreets: 0.5
        case .fewestOnStreets, .nearerFarModels, .fewerPixels: 0.2
        }
    }

    /// How much nearer than in full a train car turns to its far set's
    /// model (``Map3DModelPack/model(_:forType:count:at:step:)``), and to
    /// a box.
    public var farModelReach: Float { self >= .nearerFarModels ? 0.5 : 1 }
    public var boxReach: Float { self >= .nearerFarModels ? 0.8 : 1 }

    /// Whether the map draws fewer pixels (``Map3DDrawScale``).
    public var fewerPixels: Bool { self == .fewerPixels }

    public var lowered: Map3DLoadStep { Map3DLoadStep(rawValue: rawValue + 1) ?? self }
    public var raised: Map3DLoadStep { Map3DLoadStep(rawValue: rawValue - 1) ?? self }

    public static func < (a: Map3DLoadStep, b: Map3DLoadStep) -> Bool { a.rawValue < b.rawValue }
}

/// Decision 417: steps a device down while it cannot keep up and back up
/// once it has kept up for a while, measured every half second. A step
/// down after ``heavyWindows`` heavy half seconds in a row (decision 259's
/// 1.5 s); a step up after ``raiseWindows`` light ones in a row, at first
/// 10 s, twice as long each time a step up had to be taken back within
/// ``relapseWindows`` (up to 2 minutes), so it does not go up and down.
public struct Map3DLoadGovernor: Equatable, Sendable {
    /// A half second's measurement.
    public struct Sample: Equatable, Sendable {
        public var framesPerSecond: Double
        /// The frames a second aimed for.
        public var aim: Double
        public var gpuMilliseconds: Double
        /// Whether the streets' people or vehicles were drawn: stepping
        /// them down helps only then.
        public var drawingStreets: Bool

        public init(framesPerSecond: Double, aim: Double, gpuMilliseconds: Double, drawingStreets: Bool) {
            self.framesPerSecond = framesPerSecond
            self.aim = aim
            self.gpuMilliseconds = gpuMilliseconds
            self.drawingStreets = drawingStreets
        }

        /// Under three quarters of the frames aimed for, or the GPU over
        /// its budget (``Map3DDrawScale/isOver(gpuMilliseconds:aim:)``).
        public var isHeavy: Bool {
            aim > 0 && (framesPerSecond < aim * 0.75 || Map3DDrawScale.isOver(gpuMilliseconds: gpuMilliseconds, aim: aim))
        }

        /// All but a few of the frames aimed for, and the GPU well within
        /// its budget (three quarters of it), so a step up is not at once
        /// over it.
        public var isLight: Bool {
            aim > 0 && framesPerSecond >= aim * 0.92 && gpuMilliseconds < 1_000 / aim * Map3DDrawScale.budget * 0.75
        }
    }

    public static let heavyWindows = 3
    public static let firstRaiseWindows = 20
    public static let mostRaiseWindows = 240
    public static let relapseWindows = 30

    public private(set) var step: Map3DLoadStep = .full
    /// The lowest it may step down to: ``Map3DLoadStep/nearerFarModels``
    /// on a look that never draws fewer pixels for the GPU (``Map3DQuality/Plan/lowersWhenOver``).
    public var lowest: Map3DLoadStep = .fewerPixels {
        didSet { if step > lowest { step = lowest } }
    }
    public private(set) var raiseWindows = Self.firstRaiseWindows
    private var heavy = 0
    private var light = 0
    /// Half seconds since the last step up, while within ``relapseWindows``.
    private var sinceRaise: Int?

    public init(lowest: Map3DLoadStep = .fewerPixels) {
        self.lowest = lowest
    }

    /// Takes a half second's measurement; whether the step changed.
    @discardableResult
    public mutating func record(_ sample: Sample) -> Bool {
        if let since = sinceRaise { sinceRaise = since + 1 < Self.relapseWindows ? since + 1 : nil }
        heavy = sample.isHeavy ? heavy + 1 : 0
        light = sample.isLight ? light + 1 : 0
        if heavy >= Self.heavyWindows, step < lowest {
            // Fewer on the streets helps only while they are drawn.
            step = sample.drawingStreets ? step.lowered : max(step.lowered, min(.nearerFarModels, lowest))
            if sinceRaise != nil { raiseWindows = min(raiseWindows * 2, Self.mostRaiseWindows) }
            sinceRaise = nil
            heavy = 0
            light = 0
            return true
        }
        if light >= raiseWindows, step > .full {
            step = step.raised
            sinceRaise = 0
            heavy = 0
            light = 0
            return true
        }
        return false
    }
}

extension Map3DTrains.Frame {
    /// Decision 417: the triangles of this frame's trains: their models'
    /// (as many as `pack` has them), boxes and shadows.
    public func triangles(in pack: Map3DModelPack?) -> Int {
        let modelled = instances.reduce(0) { total, car in
            total + (pack.map { $0.models.indices.contains(car.model) ? $0.models[car.model].triangleCount : 0 } ?? 0)
        }
        return modelled + boxes.triangleCount + shadows.triangleCount
    }
}
