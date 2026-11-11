import Foundation
import GameCore

/// Decision 343: the sound of the followed train running (decision 219's
/// next item, the research note `JAPAN_RAIL_DATA_2026-10-21.md` §7.3). A
/// loop the app plays while the player follows a train at 60× or slower,
/// louder and higher the faster it runs: a high-speed train's or an
/// ordinary train's with its rail joints, each made to the spectrum of
/// recordings of real trains (`tools/audio/README.md`); decision 567: a
/// diesel railcar's engine, idling, pulling away or coasting; decision 664:
/// over an electric train's wheels, its motors (``MotorSound``). Worked out
/// after each step; never part of the world, never saved.
public struct RunningSound: Hashable, Sendable {
    /// Which loop plays.
    public enum Loop: String, CaseIterable, Hashable, Sendable {
        case electric
        case highSpeed
        /// Decision 567: a diesel railcar's engine notched up, pulling
        /// away, with the wheels under it.
        case diesel
        /// Its engine idling, the train standing.
        case dieselIdle
        /// Its engine back at idle as the train coasts or brakes, with the
        /// wheels under it.
        case dieselCoast

        /// The loop's file in the app's `Resources/Audio/` (made by
        /// `tools/audio/make_game_audio.py`).
        public var resource: (name: String, extension: String) {
            switch self {
            case .electric: ("run-electric", "caf")
            case .highSpeed: ("run-highspeed", "caf")
            case .diesel: ("run-diesel", "caf")
            case .dieselIdle: ("run-diesel-idle", "caf")
            case .dieselCoast: ("run-diesel-coast", "caf")
            }
        }

        /// The speed at which the loop plays at full volume and its
        /// highest rate, in km/h: about the top speed of the trains it
        /// stands for.
        var fullSpeedKMH: Double {
            switch self {
            case .electric: 120
            case .highSpeed: 300
            // The DR1000's and DR3100's top speed (110 km/h).
            case .diesel, .dieselIdle, .dieselCoast: 110
            }
        }

        /// How far down the loop is just above ``quietBelowKMH``, in
        /// decibels: the wheels' 12 dB; decision 567: the diesel's engine
        /// 6 dB, as it is heard at once when it is notched up or idling
        /// under the wheels.
        var quietestDecibels: Double {
            switch self {
            case .electric, .highSpeed: RunningSound.quietestDecibels
            case .diesel, .dieselIdle, .dieselCoast: -6
            }
        }

        /// The rate's range: 0.8 to 1.2; decision 567: the diesel's engine
        /// 0.9 to 1.2 pulling away (its pitch rises with the speed), and
        /// 0.9 to 1.1 coasting, where only the wheels speed up, not the
        /// idling engine.
        var rates: ClosedRange<Double> {
            switch self {
            case .electric, .highSpeed: RunningSound.slowestRate...RunningSound.fastestRate
            case .diesel: 0.9...1.2
            case .dieselIdle: 1...1
            case .dieselCoast: 0.9...1.1
            }
        }
    }

    /// The loop that plays.
    public let loop: Loop
    /// The factor on the loop's own volume, `1` at full speed.
    public let volume: Double
    /// The rate the loop plays at, `1` as made: slower and lower at low
    /// speed, faster and higher at full speed.
    public let rate: Double
    /// Decision 664: the motors heard over the wheels, `nil` for none (a
    /// diesel, a train hauled by a locomotive, one coasting). Below 5 km/h
    /// the motors sound alone, ``volume`` 0.
    public internal(set) var motor: MotorSound? = nil

    /// Below this the train is about to stand: nothing plays.
    static let quietBelowKMH = 5.0
    /// How far down the loop is just above ``quietBelowKMH``, in decibels.
    static let quietestDecibels = -12.0
    /// The steps the volume moves in, in decibels: the app is told only
    /// when the sound moves a step, and fades between them.
    static let volumeStepDecibels = 1.0
    /// The rate's range, and the steps it moves in.
    static let slowestRate = 0.8
    static let fastestRate = 1.2
    static let rateStep = 0.02

    /// Decision 567: how far down the idling engine is, in decibels: under
    /// the engine pulling away at any speed.
    static let idleDecibels = -8.0

    /// The sound `loop` makes at `kmh`, or `nil` below 5 km/h. The share
    /// of the loop's full speed sets both: the volume rises evenly in
    /// decibels from 12 dB down (the diesel's 6 dB) to full, in 1 dB
    /// steps; the rate from 0.8 to 1.2 (the diesel's ``Loop/rates``), in
    /// steps of 0.02. The idling engine (decision 567) sounds the same at
    /// any speed, 8 dB down at its own rate.
    public static func of(_ loop: Loop, atKMH kmh: Double) -> RunningSound? {
        if loop == .dieselIdle {
            return RunningSound(loop: loop, volume: pow(10, idleDecibels / 20), rate: 1)
        }
        guard kmh >= quietBelowKMH else { return nil }
        let share = min(kmh / loop.fullSpeedKMH, 1)
        let decibels = ((1 - share) * loop.quietestDecibels / volumeStepDecibels).rounded() * volumeStepDecibels
        let rates = loop.rates
        let steps = (share * (rates.upperBound - rates.lowerBound) / rateStep).rounded()
        return RunningSound(
            loop: loop,
            volume: decibels == 0 ? 1 : pow(10, decibels / 20),
            rate: rates.lowerBound + steps * rateStep
        )
    }

    /// Decision 567: a diesel railcar's sound at `kmh`: its engine idling
    /// below 5 km/h, standing or about to; above, notched up and louder and
    /// higher the faster it goes while it is `powering` (speeding up or
    /// holding its speed), and back at idle under the wheels while it
    /// coasts or brakes. Never silent: a diesel's engine runs at a stand.
    public static func ofDiesel(atKMH kmh: Double, powering: Bool) -> RunningSound {
        let loop: Loop = kmh < quietBelowKMH ? .dieselIdle : powering ? .diesel : .dieselCoast
        // Every diesel loop sounds at 5 km/h and above, and the idle at any.
        return of(loop, atKMH: kmh) ?? of(.dieselIdle, atKMH: 0)!
    }

    /// Decision 567: whether `train` in `world` runs on a diesel engine,
    /// so it sounds as one (``ofDiesel(atKMH:powering:)``). As the 3D map
    /// draws it and its horn blows: a freight train (behind an R200), a
    /// Chu-Kuang or the Blue Train behind a diesel locomotive
    /// (``TrainHorn/diesel``), the Alishan Forest Railway's train behind
    /// its DL-38, a train on a real diesel branch the company bought (drawn
    /// as its DR1000 railcars, ``RealLineStock``), and a train of no type
    /// that runs as the diesel railcar or diesel express does. Never one
    /// that runs as a high-speed train.
    static func isDiesel(_ train: Train, in world: GameWorld) -> Bool {
        if train.performance.isHighSpeed { return false }
        if TrainHorn.of(train, in: world) == .diesel { return true }
        if let key = RealLineStock.setKeys(in: world)[train.id] { return key == "dieselRailcar" }
        if let type = train.type { return type == .alishan }
        guard let preset = PerformancePreset(matching: train.performance) else { return false }
        return [.dieselRailcar, .dieselExpress].contains(preset)
    }

    /// Decision 664: whether `train` in `world` is heard with its motors:
    /// an EMU, a metro or high-speed train, or a train of no type that is
    /// not a diesel. Not a diesel (``isDiesel(_:in:)``), a steam train, nor
    /// coaches behind an electric locomotive (the Chu-Kuang behind an E200
    /// or E500, the Ming-Ri, the Formosa Star), whose motors are in the
    /// locomotive, out of hearing.
    static func hasMotors(_ train: Train, in world: GameWorld) -> Bool {
        if isDiesel(train, in: world) || TrainHorn.of(train, in: world) == .steam { return false }
        guard let type = train.type else { return true }
        return !["E200CK", "E500CK", "MINGRI", "STAR"].contains(type.rawValue)
    }

    /// The sound while `train` is followed in `world`: `nil` unless the
    /// game runs (not paused) at 60× or slower, where the player can hear
    /// one train, and the train moves at 5 km/h or more. A train that
    /// runs as a high-speed train (``TrainPerformance/isHighSpeed``) plays
    /// the high-speed loop; decision 567: a diesel (``isDiesel(_:in:)``)
    /// its engine, idling at a stand too; any other the electric one.
    ///
    /// Decision 686: `driven` is the speed and the drive of a run the
    /// player drives by hand (``ManualDrive``), heard instead of the
    /// world's train's: the motors and the engine follow the handle.
    static func of(following train: Train?, in world: GameWorld, driven: (kmh: Double, drive: GameWorld.TrainDrive?)? = nil) -> RunningSound? {
        guard let train, !world.clock.isPaused,
              world.clock.speed.tenthsPerTick <= GameSpeed.x60.tenthsPerTick
        else { return nil }
        let kmh = driven?.kmh ?? world.trainSpeedKMH(of: train.id)
        if isDiesel(train, in: world) {
            let powering = driven.map { $0.drive == .powering || $0.drive == .holding } ?? !world.trainIsSlowing(train.id)
            return ofDiesel(atKMH: kmh, powering: powering)
        }
        let wheels: Loop = train.performance.isHighSpeed ? .highSpeed : .electric
        let drive = driven.map(\.drive) ?? world.trainDrive(train.id)
        let motor = hasMotors(train, in: world) ? MotorSound.of(drive, atKMH: kmh, under: wheels) : nil
        guard var sound = of(wheels, atKMH: kmh) else {
            // Below 5 km/h, the motors alone.
            return motor.map { RunningSound(loop: wheels, volume: 0, rate: 1, motor: $0) }
        }
        sound.motor = motor
        return sound
    }
}

/// Decision 664: the motors of the electric train the player follows, heard
/// over its wheels (``RunningSound``): an inverter's song, made to the
/// tones measured at each speed in recordings of a real train pulling away
/// and braking (`tools/audio/measure_motor_sound.py`). A loop for each of a
/// few speeds, played faster or slower between them, so the pitch follows
/// the speed; one set pulling away, one braking; nothing while the train
/// coasts.
public struct MotorSound: Hashable, Sendable {
    /// What the motors do.
    public enum Mode: String, CaseIterable, Hashable, Sendable {
        /// Pulling the train: speeding up or holding its speed.
        case power
        /// Braking it, the motors turned to generators.
        case brake

        /// The speeds a loop is made at, in km/h (`MOTOR_TONES` in
        /// `make_game_audio.py`): pulling away at 45 km/h no tone was
        /// heard over the wheels, so there is none.
        var loopKMH: [Int] {
            switch self {
            case .power: [4, 6, 9, 14, 20, 30, 68]
            case .brake: [4, 6, 9, 14, 20, 30, 45, 68]
            }
        }

        /// The loops whose tones hold still as the speed changes (`steady`
        /// in `MOTOR_TONES`): the inverter's carrier at low speed, before
        /// its pitch starts to follow the speed.
        var steadyKMH: Set<Int> {
            switch self {
            case .power: [4, 6, 9, 14]
            case .brake: [4, 6]
            }
        }
    }

    /// One of the loops.
    public struct Loop: Hashable, Sendable, CaseIterable {
        public let mode: Mode
        /// The speed it is made at, in km/h.
        public let kmh: Int

        public static let allCases: [Loop] = Mode.allCases.flatMap { mode in mode.loopKMH.map { Loop(mode: mode, kmh: $0) } }

        /// Whether its tones hold still: it plays at its own rate.
        public var isSteady: Bool { mode.steadyKMH.contains(kmh) }

        /// The loop's file in the app's `Resources/Audio/`.
        public var resource: (name: String, extension: String) {
            ("run-motor-\(mode.rawValue)-\(kmh < 10 ? "0" : "")\(kmh)", "caf")
        }
    }

    /// The loop that plays.
    public let loop: Loop
    /// The factor on the loop's own volume, `1` at full speed.
    public let volume: Double
    /// The rate the loop plays at, `1` at its own speed (and always, for a
    /// steady loop).
    public let rate: Double

    /// Below this the motors are not heard, in km/h.
    static let quietBelowKMH = 1.0
    /// How far under pulling away the motors are holding the speed, in
    /// decibels: a light notch.
    static let holdingDecibels = -10.0
    /// The rate's range: the app plays a loop from half to twice its speed.
    static let rates = 0.5...2.0
    /// A high-speed train's motors turn as an ordinary train's at this
    /// share of its speed (300 km/h as 120).
    static let highSpeedShare = 0.4

    /// The motors' sound in `drive` at `kmh`, over `wheels`, or `nil`: none
    /// while coasting or below 1 km/h, or of a train not moving under a
    /// drive. The volume rises with speed as the wheels' does, from 12 dB
    /// down at a stand to full at the wheels' full speed, in 1 dB steps (10
    /// dB less holding the speed); the loop is the one made nearest the
    /// speed (a high-speed train's at 0.4 of it), at the rate that speed
    /// over its own, in steps of 0.02, or its own rate if it is steady.
    static func of(_ drive: GameWorld.TrainDrive?, atKMH kmh: Double, under wheels: RunningSound.Loop) -> MotorSound? {
        guard let drive, kmh >= quietBelowKMH else { return nil }
        let mode: Mode
        var decibels = ((1 - min(kmh / wheels.fullSpeedKMH, 1)) * RunningSound.quietestDecibels / RunningSound.volumeStepDecibels).rounded()
            * RunningSound.volumeStepDecibels
        switch drive {
        case .powering: mode = .power
        case .holding:
            mode = .power
            decibels += holdingDecibels
        case .coasting: return nil
        case .braking: mode = .brake
        }
        let speed = wheels == .highSpeed ? kmh * highSpeedShare : kmh
        // The nearest loop by ratio, as pitch goes.
        let loopKMH = mode.loopKMH.min { abs(log(speed / Double($0))) < abs(log(speed / Double($1))) }!
        let loop = Loop(mode: mode, kmh: loopKMH)
        let rate = loop.isSteady ? 1 : min(max(speed / Double(loopKMH), rates.lowerBound), rates.upperBound)
        return MotorSound(
            loop: loop,
            volume: decibels == 0 ? 1 : pow(10, decibels / 20),
            rate: (rate / RunningSound.rateStep).rounded() * RunningSound.rateStep
        )
    }
}

extension GameWorld {
    /// Decision 567: whether train `id` is losing speed, coasting or
    /// braking between two stops of its timetable: its running curve
    /// covers less ground in the next second than in the last. A train
    /// that speeds up or holds its speed is not, nor one that moves at a
    /// set rate without a timetable, nor an unknown one.
    func trainIsSlowing(_ id: TrainID) -> Bool {
        guard let paces = trainPaces(id) else { return false }
        return paces.next < paces.last * 0.999
    }

    /// Decision 664: what drives a moving train.
    enum TrainDrive: Hashable, Sendable {
        /// Speeding up.
        case powering
        /// Holding its speed, or moving at a set rate without a timetable.
        case holding
        /// Rolling, slowing gently (a high-speed train's coast).
        case coasting
        /// Braking.
        case braking
    }

    /// Decision 664: what drives train `id` now, `nil` for a train that
    /// does not move or is unknown. Between two stops of its timetable, by
    /// its running curve as ``trainIsSlowing(_:)`` reads it: speeding up,
    /// holding its speed, or slowing, which is coasting when the train
    /// coasts (``TrainPerformance/coast``) and slows by less than halfway
    /// from its coast to its braking, braking otherwise. A train moving at
    /// a set rate holds it.
    func trainDrive(_ id: TrainID) -> TrainDrive? {
        guard let train = train(id: id), trainSpeedKMH(of: id) > 0 else { return nil }
        guard let paces = trainPaces(id) else { return .holding }
        if paces.next > paces.last * 1.001 { return .powering }
        if paces.next >= paces.last * 0.999 { return .holding }
        guard let coast = train.performance.coast, paces.last > 0 else { return .braking }
        // km/h lost in the second, against thousandths of a km/h a second.
        let slowing = trainSpeedKMH(of: id) * (1 - paces.next / paces.last) * 1000
        return slowing < Double(coast.deceleration + train.performance.braking) / 2 ? .coasting : .braking
    }

    /// The ground train `id`'s running curve covers per millisecond in the
    /// last second and in the next, between two stops of its timetable;
    /// `nil` for a train not running to a stop on its timetable.
    private func trainPaces(_ id: TrainID) -> (last: Double, next: Double)? {
        guard let train = train(id: id), case .travellingToStop? = train.execution,
              let run = train.times?.run, clock.now > run.start, clock.now < run.end,
              let curve = runCurve(of: run, for: train.performance) else { return nil }
        let now = (clock.now.seconds - run.start.seconds) * 1000
        // Ground covered per millisecond between two times, kept within
        // the run.
        func pace(from start: Int64, to end: Int64) -> Double {
            let first = max(0, start), last = min(curve.duration, end)
            guard last > first else { return 0 }
            return Double(curve.distance(at: last) - curve.distance(at: first)) / Double(last - first)
        }
        return (pace(from: now - 1000, to: now), pace(from: now, to: now + 1000))
    }
}
