import GameCore

// Decision 429: the 3D map's traffic signals (decision 355) change with
// the game clock, green, amber and red, a junction's main road and its
// crossing road in turn. The timing is the TW3D pack's (the private
// reference's `Railway/tw3d-reference-clean/source/js/city-config.js`,
// `SIGNAL_TIMING` and `signalPhase`; slop-newyork, MIT, copyright (c) 2026
// Mr.doob): a 70 s cycle, the main road green until 32 s and amber until
// 35 s, the crossing road green from 36 s, amber from 64 s and red from
// 67 s, a short all-red at each change. There every junction changes at
// once; here each takes one of four offsets, from where it is.

/// When the 3D map's signals show green, amber and red.
public enum Map3DSignalTiming {
    /// Which of a junction's roads a signal faces: the main road (its
    /// widest, and the arms nearly in line with it) or the crossing road.
    public enum Road: Sendable, Equatable {
        case main
        case cross
    }

    /// The light a signal shows, as an index of ``Map3DProp/signalLights``.
    public enum Light: Int, Sendable, CaseIterable {
        case red = 0
        case amber = 1
        case green = 2
    }

    /// A cycle's length in game seconds, and where in it the lights change
    /// (`SIGNAL_TIMING`).
    public static let cycle: Int64 = 70
    static let mainAmber: Int64 = 32
    static let mainRed: Int64 = 35
    static let crossAmber: Int64 = 64
    static let crossRed: Int64 = 67

    /// How many offsets the junctions are spread over: few, so a chunk
    /// draws its signals in few runs (``Map3DPropRuns``).
    public static let groups = 4

    /// The shortest a cycle may last on the screen, in real seconds, for
    /// the lights to change: shorter, they would blink.
    static let shortestCycle = 4.0

    /// What `road`'s signals show `second` game seconds into the clock
    /// (`signalPhase`).
    public static func light(_ road: Road, at second: Int64) -> Light {
        let t = (second % cycle + cycle) % cycle
        switch road {
        case .main: return t < mainAmber ? .green : t < mainRed ? .amber : .red
        case .cross: return t < mainRed + 1 ? .red : t < crossAmber ? .green : t < crossRed ? .amber : .red
        }
    }

    /// The same at a junction of offset `group`.
    public static func light(_ road: Road, group: Int, at second: Int64) -> Light {
        light(road, at: second + offset(group))
    }

    /// How far into its cycle a junction of `group` is, in game seconds:
    /// a quarter cycle a group.
    static func offset(_ group: Int) -> Int64 {
        Int64(group) * cycle / Int64(groups)
    }

    /// The offset of the junction at `point` (metres east and south of the
    /// world's origin), the same every time.
    static func group(at point: Map3DBaseMap.Point) -> Int {
        let r = map3DRandom(Int32(truncatingIfNeeded: Int(point.x.rounded())), Int32(truncatingIfNeeded: Int(point.z.rounded())), salt: 429)
        return min(groups - 1, Int(r * Float(groups)))
    }

    /// Whether the lights change at `speed`: not when a cycle would last
    /// under ``shortestCycle`` on the screen (faster than about 17×; a
    /// speed runs as many game seconds a real second as it has tenths a
    /// tick, decision 12).
    public static func changes(at speed: GameSpeed) -> Bool {
        Double(cycle) >= shortestCycle * Double(speed.tenthsPerTick)
    }

    /// What `road`'s signals show while they do not change: the main road
    /// green, the crossing road red (decision 355's look).
    public static func steady(_ road: Road) -> Light {
        road == .main ? .green : .red
    }

    /// The game clock as the signals read it.
    public struct Clock: Sendable, Equatable {
        /// The game second.
        public let second: Int64
        /// Whether the lights change: by the speed the clock runs at, or
        /// paused, the speed it resumes at (so pausing at 600× keeps the
        /// steady look).
        public let changes: Bool

        public init(_ clock: GameClock) {
            second = clock.now.seconds
            changes = Map3DSignalTiming.changes(at: clock.runningSpeed)
        }

        /// What `road`'s signals at a junction of `group` show.
        public func light(_ road: Road, group: Int) -> Light {
            changes ? Map3DSignalTiming.light(road, group: group, at: second) : Map3DSignalTiming.steady(road)
        }
    }

    /// A pack's three signal models, one a lit light, for a renderer to
    /// draw the light the clock shows. The signals stand in a chunk as
    /// ``Map3DProp/signalGo`` (the main road's) and
    /// ``Map3DProp/signalStop`` (the crossing road's); their instances'
    /// ``Map3DInstance/group`` is their junction's.
    public struct Models: Sendable, Equatable {
        let red: Int
        let amber: Int
        let green: Int

        public init?(pack: Map3DModelPack) {
            guard let red = pack.index(of: Map3DProp.signalStop.modelName), let amber = pack.index(of: Map3DProp.signalAmber.modelName),
                  let green = pack.index(of: Map3DProp.signalGo.modelName) else { return nil }
            (self.red, self.amber, self.green) = (red, amber, green)
        }

        /// The model to draw the instances of `model` of `group` with at
        /// `clock`: a signal's lit as the clock says (as they stand without
        /// one), any other model itself.
        public func model(_ model: Int, group: Int, clock: Clock?) -> Int {
            let road: Road
            switch model {
            case green: road = .main
            case red: road = .cross
            default: return model
            }
            switch clock?.light(road, group: group) ?? Map3DSignalTiming.steady(road) {
            case .red: return red
            case .amber: return amber
            case .green: return green
            }
        }
    }
}

/// Decision 429: a chunk's street furniture as a renderer draws it, sorted
/// by model and, among one model's, by group: one run a model and group for
/// the frame (a signal's lights by its junction's group), one a model for
/// the sun's shadow map (the lights cast no shadow of their own).
public struct Map3DPropRuns: Sendable {
    public struct Run: Sendable, Equatable {
        public let model: Int
        public let group: Int
        public let first: Int
        public var count: Int
    }

    public let instances: [Map3DInstance]
    public let runs: [Run]
    public let shapes: [Run]

    public init(_ props: [Map3DInstance]) {
        instances = props.enumerated().sorted { a, b in
            (a.element.model, a.element.group, a.offset) < (b.element.model, b.element.group, b.offset)
        }.map(\.element)
        runs = Self.runs(of: instances, byGroup: true)
        shapes = Self.runs(of: instances, byGroup: false)
    }

    /// `instances`' runs, one a model (and a group, `byGroup`).
    private static func runs(of instances: [Map3DInstance], byGroup: Bool) -> [Run] {
        var runs: [Run] = []
        for (index, instance) in instances.enumerated() {
            if let last = runs.last, last.model == instance.model, !byGroup || last.group == instance.group {
                runs[runs.count - 1].count += 1
            } else {
                runs.append(Run(model: instance.model, group: byGroup ? instance.group : 0, first: index, count: 1))
            }
        }
        return runs
    }
}
