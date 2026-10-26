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

/// Decision 417: how much a device draws of what moves at most, by its
/// GPU: the A12–A14 (and the M1) less, the A15–A16 (and the M2) what
/// decision 259 drew in full, the A17 Pro and the M3 on more, and its far
/// train models farther. Under load it steps down from there
/// (``Map3DLoadStep``), never up past it.
public enum Map3DDeviceTier: Int, CaseIterable, Comparable, Sendable {
    case lower, standard, higher

    /// The tier of a GPU of Apple family `family` (Metal's
    /// `MTLGPUFamily.apple1`… as a number): `nil` before the A12 (family
    /// 5), whose 3D map draws nothing that moves on the streets.
    public static func forGPUFamily(_ family: Int) -> Map3DDeviceTier? {
        family >= 9 ? .higher : family >= 8 ? .standard : family >= 5 ? .lower : nil
    }

    /// Decision 259's street detail of the tier (the rain's too).
    public var streetDetail: Map3DStreetDetail { self == .lower ? .reduced : .full }

    /// The triangles of everything that moves: on the A15–A16 what the
    /// streets draw in full and 400,000 for the trains and buses besides;
    /// on the A12–A14 under half of it; on the A17 Pro and the M3 on, more
    /// of both.
    public var triangles: Int {
        switch self {
        case .lower: 250_000
        case .standard: 600_000
        case .higher: 1_000_000
        }
    }

    /// The most of the streets' people, vehicles and buses: on the
    /// A12–A14 a third of the buses, each the triangles of 15 cars.
    public var streetLimits: Map3DStreetLimits {
        switch self {
        case .lower: Map3DStreetLimits(people: Map3DStreetDetail.reduced.people, vehicles: Map3DStreetDetail.reduced.vehicles, buses: 10)
        case .standard: Map3DStreetLimits(streetDetail)
        case .higher: Map3DStreetLimits(people: 2_000, vehicles: 600, buses: 45)
        }
    }

    /// How much farther than decision 408's a car turns to its far set's
    /// model, and to a box.
    public var farModelReach: Float { self == .higher ? 1.5 : 1 }
    public var boxReach: Float { self == .higher ? 1.25 : 1 }

    /// The share of the streets' people and vehicles a step draws at most
    /// (``Map3DLoadStep/streetShare``): on the A12–A14 none from
    /// ``Map3DLoadStep/fewestOnStreets`` on, leaving the GPU to the
    /// player's trains and buses.
    public func streetShare(at step: Map3DLoadStep) -> Float {
        self == .lower && step >= .fewestOnStreets ? 0 : step.streetShare
    }

    public static func < (a: Map3DDeviceTier, b: Map3DDeviceTier) -> Bool { a.rawValue < b.rawValue }
}

/// Decision 417: the triangles a frame's moving things may take, and how
/// many of the streets' it leaves room for.
public struct Map3DMotionBudget: Equatable, Sendable {
    /// The device's tier; `nil` for one that draws nothing on the streets.
    public var tier: Map3DDeviceTier?
    /// How far it has stepped down under load.
    public var step: Map3DLoadStep
    /// The trains' triangles this frame: their models' and their boxes'.
    public var trainTriangles: Int

    public init(tier: Map3DDeviceTier?, step: Map3DLoadStep = .full, trainTriangles: Int = 0) {
        self.tier = tier
        self.step = step
        self.trainTriangles = trainTriangles
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
    /// streets' vehicles (their buses, which share the tier's buses with
    /// the player's, among them) from what is left, then their people; at
    /// least ``leastShare`` of each, and at most
    /// ``Map3DDeviceTier/streetShare(at:)``.
    public func limits(routeBuses: Int = 0) -> Map3DStreetLimits {
        guard let tier else { return Map3DStreetLimits(people: 0, vehicles: routeBuses, buses: routeBuses) }
        let full = tier.streetLimits
        let streetBuses = max(full.buses - routeBuses, 0)
        let left = Float(tier.triangles - trainTriangles - routeBuses * Self.busTriangles)
        let vehicles = Float(full.vehicles * Self.vehicleTriangles + streetBuses * Self.busTriangles)
        let people = Float(full.people * Self.personTriangles)
        func share(_ room: Float, of cost: Float) -> Float { cost > 0 ? min(max(room / cost, Self.leastShare), 1) : 1 }
        let most = tier.streetShare(at: step)
        let vehicleShare = min(share(left - people, of: vehicles), most)
        let peopleShare = min(share(left - Self.leastShare * vehicles, of: people), most)
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
    /// model (``Map3DModelPack/model(_:forType:count:at:reach:)``), and to
    /// a box.
    public var farModelReach: Float { self >= .nearerFarModels ? 0.5 : 1 }
    public var boxReach: Float { self >= .nearerFarModels ? 0.8 : 1 }

    /// The reaches on a device of `tier` (``Map3DDeviceTier/farModelReach``):
    /// a higher tier's farther ones, but stepped down never farther than
    /// another's in full.
    public func reach(on tier: Map3DDeviceTier?) -> Map3DModelReach {
        let far = tier?.farModelReach ?? 1, box = tier?.boxReach ?? 1
        return self >= .nearerFarModels ? Map3DModelReach(farModel: farModelReach, box: boxReach) : Map3DModelReach(farModel: far, box: box)
    }

    /// Whether the map draws fewer pixels (``Map3DDrawScale``).
    public var fewerPixels: Bool { self == .fewerPixels }

    public var lowered: Map3DLoadStep { Map3DLoadStep(rawValue: rawValue + 1) ?? self }
    public var raised: Map3DLoadStep { Map3DLoadStep(rawValue: rawValue - 1) ?? self }

    public static func < (a: Map3DLoadStep, b: Map3DLoadStep) -> Bool { a.rawValue < b.rawValue }
}

/// Decision 417: where the map is between all a device can draw and the
/// least: a rung of the ladder of what moves (``all``: a tier and how much
/// of the streets), and how the GPU is spared (`drawing`: the trains' far
/// models nearer, then fewer pixels).
public struct Map3DLoadLevel: Equatable, Sendable {
    public let tier: Map3DDeviceTier
    /// ``Map3DLoadStep/full``, ``Map3DLoadStep/fewerOnStreets`` or ``Map3DLoadStep/fewestOnStreets``.
    public let streets: Map3DLoadStep
    /// ``Map3DLoadStep/full``, ``Map3DLoadStep/nearerFarModels`` or ``Map3DLoadStep/fewerPixels``.
    public var drawing: Map3DLoadStep

    public init(tier: Map3DDeviceTier, streets: Map3DLoadStep, drawing: Map3DLoadStep = .full) {
        self.tier = tier
        self.streets = streets
        self.drawing = drawing
    }

    /// The rungs of what moves, from the bottom: the lower tier's fewest
    /// on the streets to its full, then the standard tier's full, then
    /// the higher tier's. A device climbs no higher than its own tier's
    /// full (``Map3DLoadGovernor/top``).
    public static let all: [Map3DLoadLevel] = [Map3DLoadStep.fewestOnStreets, .fewerOnStreets, .full].map { Map3DLoadLevel(tier: .lower, streets: $0) }
        + [Map3DLoadLevel(tier: .standard, streets: .full), Map3DLoadLevel(tier: .higher, streets: .full)]

    /// The ways of sparing the GPU, the least first.
    public static let drawingSteps: [Map3DLoadStep] = [.full, .nearerFarModels, .fewerPixels]

    /// The rung of `tier` in full.
    public static func top(of tier: Map3DDeviceTier) -> Int {
        all.firstIndex(of: Map3DLoadLevel(tier: tier, streets: .full)) ?? 0
    }

    /// The train models' reach on it (``Map3DLoadStep/reach(on:)``).
    public var reach: Map3DModelReach { drawing.reach(on: tier) }

    /// "standard full · 600000 triangles" (and how the GPU is spared, if
    /// it is), for the debug numbers and a problem report.
    public var summary: String {
        "\(tier) \(streets)\(drawing == .full ? "" : " \(drawing)") · \(tier.triangles) triangles"
    }
}

/// Decision 417: climbs a device up the ladder (``Map3DLoadLevel``) while
/// it keeps up and steps it down while it cannot, measured every half
/// second. Whether to step is the frames' (what the player feels); what
/// to step down is the CPU's and the GPU's times: the CPU behind (each
/// frame's street life, buses and trains) takes fewer on the streets
/// first, the GPU alone behind spares the GPU first (far models nearer,
/// then fewer pixels), both or neither known keeps the order (the streets,
/// then the GPU). A step down after ``heavyWindows`` heavy half seconds
/// in a row (decision 259's 1.5 s); a step up, the last way down first,
/// after ``raiseWindows`` light ones in a row, at first 10 s, twice as
/// long each time a step up had to be taken back within
/// ``relapseWindows`` (up to 2 minutes), so it does not go up and down.
/// On Automatic it starts below its own tier
/// (``start(for:device:remembered:)``), so the oldest device of a tier
/// stays where it keeps up and the newest climbs to the top. On High
/// Quality it does not step down for the load (``stepsDownForLoad``),
/// but for memory running short (``relieve()``) and the phone running hot
/// (``highest``) on any look: the system closing the app for its memory
/// is, for the player, a crash.
public struct Map3DLoadGovernor: Equatable, Sendable {
    /// A half second's measurement.
    public struct Sample: Equatable, Sendable {
        public var framesPerSecond: Double
        /// The frames a second aimed for.
        public var aim: Double
        /// A frame's CPU work and GPU time, in milliseconds; 0 when not
        /// known (the GPU's times not back yet).
        public var cpuMilliseconds: Double
        public var gpuMilliseconds: Double
        /// Whether the streets' people or vehicles were drawn: stepping
        /// them down helps only then.
        public var drawingStreets: Bool

        public init(framesPerSecond: Double, aim: Double, cpuMilliseconds: Double = 0, gpuMilliseconds: Double, drawingStreets: Bool) {
            self.framesPerSecond = framesPerSecond
            self.aim = aim
            self.cpuMilliseconds = cpuMilliseconds
            self.gpuMilliseconds = gpuMilliseconds
            self.drawingStreets = drawingStreets
        }

        /// Under three quarters of the frames aimed for, or the GPU over
        /// its budget (``Map3DDrawScale/isOver(gpuMilliseconds:aim:)``).
        public var isHeavy: Bool {
            aim > 0 && (framesPerSecond < aim * 0.75 || isGPUOver)
        }

        /// All but a few of the frames aimed for, and the GPU well within
        /// its budget (three quarters of it), so a step up is not at once
        /// over it.
        public var isLight: Bool {
            aim > 0 && framesPerSecond >= aim * 0.92 && gpuMilliseconds < 1_000 / aim * Map3DDrawScale.budget * 0.75
        }

        /// The GPU over its share of the frame (``Map3DDrawScale/budget``).
        public var isGPUOver: Bool { gpuMilliseconds > 0 && Map3DDrawScale.isOver(gpuMilliseconds: gpuMilliseconds, aim: aim) }
        /// The CPU's work over the same share.
        public var isCPUOver: Bool { aim > 0 && cpuMilliseconds > 1_000 / aim * Map3DDrawScale.budget }
        /// Whether sparing the GPU helps first: the GPU behind and the CPU
        /// not, or nothing on the streets to take away.
        public var sparesTheGPUFirst: Bool { (isGPUOver && !isCPUOver) || !drawingStreets }
    }

    public static let heavyWindows = 3
    public static let firstRaiseWindows = 20
    public static let mostRaiseWindows = 240
    public static let relapseWindows = 30

    /// The rung it is on (``Map3DLoadLevel/all``).
    public private(set) var rung: Int
    /// How the GPU is spared now (``Map3DLoadLevel/drawingSteps``).
    public private(set) var drawing = Map3DLoadStep.full
    /// The highest rung it climbs to: its tier's full.
    public private(set) var top: Int
    /// How far it may spare the GPU: not to fewer pixels on a look that
    /// never draws fewer for the GPU (``Map3DQuality/Plan/lowersWhenOver``,
    /// ``deepest(lowersWhenOver:)``).
    public var deepest = Map3DLoadStep.fewerPixels {
        didSet { drawing = min(drawing, deepest) }
    }
    /// The highest rung it may climb to whatever its tier: the lower
    /// tier's fewest on the streets while the phone is too hot
    /// (``Map3DQuality/Heat/critical``, ``highest(heat:)``).
    public var highest = Map3DLoadLevel.all.count - 1 {
        didSet { rung = min(rung, allowedTop) }
    }
    /// Whether it steps down when the frames or the GPU cannot keep up
    /// (not on High Quality).
    public var stepsDownForLoad = true
    public private(set) var raiseWindows = Self.firstRaiseWindows
    private var heavy = 0
    private var light = 0
    /// Half seconds since the last step up, while within ``relapseWindows``.
    private var sinceRaise: Int?

    /// On `top`'s rung (``Map3DLoadLevel/top(of:)``), starting at `start`.
    public init(top: Int = Map3DLoadLevel.all.count - 1, start: Int? = nil) {
        self.top = top
        rung = min(max(start ?? top, 0), top)
    }

    public var level: Map3DLoadLevel {
        var level = Map3DLoadLevel.all[rung]
        level.drawing = drawing
        return level
    }

    private var allowedTop: Int { min(top, highest) }

    /// The rung a device of `device`'s tier starts on with `quality`: on
    /// Automatic one below its own tier's full (the lower tier at its
    /// least: its fewest on the streets, the player's trains and buses in
    /// full), or where it got to last time (`remembered`,
    /// ``remembered(_:quality:system:)``); on Battery Saver and High
    /// Quality its tier's full.
    public static func start(for quality: Map3DQuality, device: Map3DDeviceTier?, remembered: Int? = nil) -> Int {
        guard let tier = quality.tier(device: device) else { return 0 }
        let top = Map3DLoadLevel.top(of: tier)
        guard quality == .automatic else { return top }
        if let remembered { return min(max(remembered, 0), top) }
        return tier == .lower ? 0 : top - 1
    }

    /// The rung kept on the device in `stored` (``remembering(_:quality:system:)``),
    /// when it was kept with `quality` on `system`; `nil` after a change of
    /// look or of the system, so it climbs again.
    public static func remembered(_ stored: String?, quality: Map3DQuality, system: String) -> Int? {
        guard let parts = stored?.split(separator: "|", omittingEmptySubsequences: false), parts.count == 3,
              parts[0] == quality.rawValue, parts[1] == system, let rung = Int(parts[2]),
              Map3DLoadLevel.all.indices.contains(rung) else { return nil }
        return rung
    }

    /// `rung`, to keep on the device with `quality` on `system`.
    public static func remembering(_ rung: Int, quality: Map3DQuality, system: String) -> String {
        "\(quality.rawValue)|\(system)|\(rung)"
    }

    /// What is kept on the device (``remembering(_:quality:system:)``) for
    /// a problem report: the look and the rung it got to ("automatic,
    /// standard full · 600000 triangles"), or `nil` for nothing kept.
    public static func report(_ stored: String?) -> String? {
        guard let parts = stored?.split(separator: "|", omittingEmptySubsequences: false), parts.count == 3,
              let rung = Int(parts[2]), Map3DLoadLevel.all.indices.contains(rung) else { return nil }
        return "\(parts[0]), \(Map3DLoadLevel.all[rung].summary)"
    }

    /// Takes a half second's measurement; whether the level changed.
    @discardableResult
    public mutating func record(_ sample: Sample) -> Bool {
        if let since = sinceRaise { sinceRaise = since + 1 < Self.relapseWindows ? since + 1 : nil }
        heavy = sample.isHeavy ? heavy + 1 : 0
        light = sample.isLight ? light + 1 : 0
        if stepsDownForLoad, heavy >= Self.heavyWindows, stepDown(sparingTheGPUFirst: sample.sparesTheGPUFirst) {
            if sinceRaise != nil { raiseWindows = min(raiseWindows * 2, Self.mostRaiseWindows) }
            sinceRaise = nil
            heavy = 0
            light = 0
            return true
        }
        if light >= raiseWindows, drawing > .full || rung < allowedTop {
            // The last way down first: the GPU spared less, then more on
            // the streets.
            if drawing > .full { drawing = Self.drawing(drawing, by: -1) } else { rung += 1 }
            sinceRaise = 0
            heavy = 0
            light = 0
            return true
        }
        return false
    }

    /// One step down: the GPU spared more first, or fewer on the streets
    /// first, then the other; whether there was one.
    private mutating func stepDown(sparingTheGPUFirst: Bool) -> Bool {
        let canSpare = drawing < deepest, canThin = rung > 0
        if sparingTheGPUFirst ? canSpare : !canThin && canSpare {
            drawing = Self.drawing(drawing, by: 1)
        } else if canThin {
            rung -= 1
        } else {
            return false
        }
        return true
    }

    private static func drawing(_ step: Map3DLoadStep, by steps: Int) -> Map3DLoadStep {
        let index = Map3DLoadLevel.drawingSteps.firstIndex(of: step) ?? 0
        return Map3DLoadLevel.drawingSteps[min(max(index + steps, 0), Map3DLoadLevel.drawingSteps.count - 1)]
    }

    /// Memory runs short (the system's warning): two steps down at once,
    /// in the order (the streets, then the GPU spared), and the next step
    /// up twice as long in coming.
    public mutating func relieve() {
        for _ in 0..<2 { _ = stepDown(sparingTheGPUFirst: false) }
        raiseWindows = min(raiseWindows * 2, Self.mostRaiseWindows)
        sinceRaise = nil
        heavy = 0
        light = 0
    }

    /// The heat's highest rung: the lower tier's fewest on the streets at
    /// ``Map3DQuality/Heat/critical``, else the top of the ladder.
    public static func highest(heat: Map3DQuality.Heat) -> Int {
        heat >= .critical ? 0 : Map3DLoadLevel.all.count - 1
    }

    /// How far a look that draws fewer pixels for the GPU
    /// (`lowersWhenOver`) or not spares it.
    public static func deepest(lowersWhenOver: Bool) -> Map3DLoadStep { lowersWhenOver ? .fewerPixels : .nearerFarModels }
}

/// Decision 417: how far, against decision 408's, a train car keeps its
/// own model before its far set's, and any model before a box.
public struct Map3DModelReach: Equatable, Sendable {
    public var farModel: Float
    public var box: Float

    public init(farModel: Float = 1, box: Float = 1) {
        self.farModel = farModel
        self.box = box
    }

    public static let standard = Map3DModelReach()
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
