// Decision 460: two more measures of what a device bears besides its GPU
// (decision 417's ``Map3DDeviceTier``): its memory and its CPU. The
// memory, read once when the app opens (how much the device has, and the
// most the system lets the app use: what it uses and what is left to it),
// sets how much of the 3D map is kept built and where Automatic starts;
// what is left to the app, read every half second, steps the map down
// before the system's warning comes. The CPU, by chip and cores and how
// hot the phone is, sets how much of the time the game loop may spend
// working out ticks. Neither changes what GameCore works out: the same
// ticks make the same world, only fewer of them a real second.

/// Decision 460: how much memory a device gives the app.
public enum DeviceMemoryTier: Int, CaseIterable, Comparable, Sendable {
    /// 3–4 GB (iPhone XS–13, 12 mini, 13 mini; the iPads of 3–4 GB): the
    /// system lets the app use some 2 GB.
    case tight
    /// 6 GB (iPhone 12 Pro–15, the iPads of 6 GB): some 3 GB.
    case roomy
    /// 8 GB and more (iPhone 15 Pro on, the M-series iPads).
    case ample

    static let gibibyte: UInt64 = 1 << 30

    /// The tier of a device with `bytes` of memory
    /// (`ProcessInfo.physicalMemory`, a little under what is on the box:
    /// a 4 GB iPhone tells some 3.7 GiB).
    public static func forPhysicalMemory(_ bytes: UInt64) -> DeviceMemoryTier {
        bytes < 5 * gibibyte ? .tight : bytes < 7 * gibibyte ? .roomy : .ample
    }

    /// The tier of the most the system lets the app use, `bytes`: what it
    /// uses (`phys_footprint`) and what is left to it
    /// (`os_proc_available_memory`) together.
    public static func forLimit(_ bytes: UInt64) -> DeviceMemoryTier {
        bytes < 5 * gibibyte / 2 ? .tight : bytes < 33 * gibibyte / 10 ? .roomy : .ample
    }

    /// The most the system lets the app use, from what it uses
    /// (`footprint`) and what is left to it (`available`): `nil` when either
    /// is not known (the Simulator tells nothing left).
    public static func limit(footprint: UInt64?, available: UInt64?) -> UInt64? {
        guard let footprint, let available, available > 0 else { return nil }
        return footprint + available
    }

    /// The tier of a device with `physical` bytes of memory that lets the
    /// app use `limit`: the lower of the two.
    public static func of(physical: UInt64, limit: UInt64?) -> DeviceMemoryTier {
        let device = forPhysicalMemory(physical)
        return limit.map { min(device, forLimit($0)) } ?? device
    }

    /// Whether the 3D scene is built ahead while the flat map is pinched
    /// close (decision 269) and kept once the 3D map closes, so it opens at
    /// once: not on ``tight``, where the scene of a real city (some
    /// 370–520 MB, decision 455) is a quarter of all the app may use.
    public var keepsSceneBuilt: Bool { self != .tight }

    /// Whether Automatic starts a rung lower on the 3D map
    /// (``Map3DLoadGovernor/start(for:device:remembered:memory:)``): on
    /// ``tight``, which climbs from there as its frames allow.
    public var startsLower: Bool { self == .tight }

    public static func < (a: DeviceMemoryTier, b: DeviceMemoryTier) -> Bool { a.rawValue < b.rawValue }
}

/// Decision 460: steps the 3D map down (``Map3DLoadGovernor/relieve()``)
/// when what is left to the app runs low, before the system's warning:
/// below ``least`` at a half second's look, and again only after
/// ``waitWindows`` half seconds, so one low stretch is one step down, not
/// a fall to the bottom.
public struct Map3DMemoryWatch: Equatable, Sendable {
    /// What is left to the app below which the map steps down: a block of
    /// chunks built as the camera moves and the frame's buffers, with room.
    public static let least: UInt64 = 300 << 20
    /// Ten seconds between steps down.
    public static let waitWindows = 20

    private var since: Int?

    public init() {}

    /// Takes a half second's look at what is left to the app, `available`
    /// bytes (`nil` or 0: not known); whether to step down now.
    public mutating func record(available: UInt64?) -> Bool {
        if let wait = since { since = wait + 1 < Self.waitWindows ? wait + 1 : nil }
        guard since == nil, let available, available > 0, available < Self.least else { return false }
        since = 0
        return true
    }
}

/// Decision 460: how much work a device's CPU bears, by its chip (its Apple
/// GPU family, ``Map3DDeviceTier/forGPUFamily(_:)``'s number) and its
/// cores.
public enum DeviceCPUTier: Int, CaseIterable, Comparable, Sendable {
    /// The A14 and before.
    case lower
    /// The A15–A16, and any chip of 8 cores or more (the M1 on).
    case standard
    /// The A17 Pro, the M3 and on.
    case higher

    public static func of(gpuFamily family: Int, cores: Int) -> DeviceCPUTier {
        let chip: DeviceCPUTier = family >= 9 ? .higher : family >= 8 ? .standard : .lower
        return cores >= 8 ? max(chip, .standard) : chip
    }

    /// The most of real time the game loop spends working out ticks when
    /// they cannot keep up with the speed (``TickPace``).
    public var busiestShare: Double {
        switch self {
        case .lower: 0.6
        case .standard: 0.8
        case .higher: 1
        }
    }

    public static func < (a: DeviceCPUTier, b: DeviceCPUTier) -> Bool { a.rawValue < b.rawValue }
}

/// Decision 460: how the game loop paces itself on a device: after the
/// ticks of a step, how long it rests before the next. A step whose ticks
/// take less than a tick's interval rests the interval, as always; one
/// whose ticks take longer (a big map at 6000×) rests so the loop works no
/// more than ``busiestShare`` of the time, leaving the rest to the map's
/// frames and the phone cool. The game then runs slower than its speed, as
/// it already did when its ticks could not keep up (decision 143); the
/// ticks are the same.
public struct TickPace: Equatable, Sendable {
    public var cpu: DeviceCPUTier
    public var heat: Map3DQuality.Heat

    /// The longest rest after one step, so a long tick (the day's first
    /// passenger plan) does not hold the game still for long after it.
    public static let longestRest: Duration = .seconds(2)

    public init(cpu: DeviceCPUTier = .higher, heat: Map3DQuality.Heat = .nominal) {
        self.cpu = cpu
        self.heat = heat
    }

    /// The CPU's share, less when the phone runs hot: three fifths at
    /// ``Map3DQuality/Heat/serious``, two fifths at
    /// ``Map3DQuality/Heat/critical``.
    public var busiestShare: Double {
        min(cpu.busiestShare, heat >= .critical ? 0.4 : heat >= .serious ? 0.6 : 1)
    }

    /// The rest after a step whose ticks took `work`, with ticks every
    /// `interval`.
    public func rest(afterWorking work: Duration, interval: Duration) -> Duration {
        let share = busiestShare
        guard work > .zero, share < 1 else { return interval }
        // To the millisecond, which is all a sleep needs.
        let milliseconds = (Double(work.components.seconds) * 1_000 + Double(work.components.attoseconds) / 1e15) * (1 - share) / share
        return min(max(interval, .milliseconds(Int64(milliseconds.rounded()))), max(interval, Self.longestRest))
    }

    /// "CPU lower, ticks at most 60% of the time", for a problem report.
    public var summary: String {
        "CPU \(cpu), ticks at most \(Int((busiestShare * 100).rounded()))% of the time"
    }
}

/// Decision 460: what a problem report says of a device's memory and CPU:
/// "memory tight (3.7 GB, the app's limit 2.0 GB) · CPU lower, ticks at
/// most 60% of the time".
public func deviceLoadSummary(memory: DeviceMemoryTier, physical: UInt64, limit: UInt64?, pace: TickPace) -> String {
    func gb(_ bytes: UInt64) -> String {
        let tenths = (Double(bytes) / Double(DeviceMemoryTier.gibibyte) * 10).rounded()
        return "\(Int(tenths) / 10).\(Int(tenths) % 10) GB"
    }
    let memoryText = "memory \(memory) (\(gb(physical))" + (limit.map { ", the app's limit \(gb($0))" } ?? "") + ")"
    return memoryText + " · " + pace.summary
}
