import GameCore

/// Decision 686: a run the player drives by hand, as a session keeps it:
/// waiting for the followed train to leave its stop, or driving along the
/// track read when it was taken over.
struct ManualDriveRun: Sendable {
    let train: TrainID
    /// The track and the run, once the train has been taken over.
    var driving: (track: ManualDriveTrack, drive: ManualDrive, length: Double)?
    /// When the run was last stepped, on the map's clock.
    var stepped: Double?
    /// Decision 693: whether the run, ended, has been told to the world.
    var settled = false
}

extension ManualDrive {
    /// Decision 690: what the driving card says of the run above its
    /// figures: the line and the way the train runs, and the stop it is
    /// driven to. Read when the run is taken over and kept for it, since
    /// the world's train runs on to its timetable and would name the stop
    /// after.
    public struct Heading: Hashable, Sendable {
        public let line: LineID?
        /// "Local · Alpha → Gamma", or the line's name.
        public let route: String?
        /// The stop driven to; `nil` while the train waits at one.
        public let stop: String?

        /// `waiting` is what was read when the handle was taken, kept for
        /// the way where the train says less of it once it runs.
        init(_ hud: Map3DDriverHUD?, after waiting: Heading? = nil) {
            line = hud?.line ?? waiting?.line
            route = hud?.routeText ?? waiting?.route ?? hud?.lineName
            if waiting != nil, case .next(let name)? = hud?.place { stop = name } else { stop = nil }
        }
    }
}

extension GameWorld {
    /// Decision 686: how far train `id` is into its run to its next stop:
    /// the run, the world units it has covered and the whole seconds since
    /// it set off; `nil` unless it runs to a stop of its timetable.
    func manualDriveTakeOver(of id: TrainID) -> (run: ServiceRun, covered: Int64, elapsed: Int64)? {
        guard let train = train(id: id), case .travellingToStop? = train.execution, train.position != nil,
              let run = train.times?.run, let curve = runCurve(of: run, for: train.performance) else { return nil }
        let elapsed = max(0, clock.now.seconds - run.start.seconds)
        guard elapsed < run.seconds else { return nil }
        return (run, min(run.length, curve.distance(at: elapsed * 1000)), elapsed)
    }

    /// Decision 686: whether train `id` can be driven by hand: it runs to
    /// a timetable (a stop to drive to, and an arrival to keep).
    public func canManualDrive(_ id: TrainID) -> Bool {
        guard let train = train(id: id), train.position != nil else { return false }
        return train.execution != nil || assignedLine(of: id) != nil
    }
}

extension ManualDriveRun {
    /// A run is taken over only with this much of it left, in metres: less,
    /// and the next one is waited for.
    static let shortestMetres: Int64 = 300

    /// The track and the run for `train` taken over now in `world`, or
    /// `nil` while it stands at a stop or is too near its next one.
    static func takeOver(_ id: TrainID, in world: GameWorld) -> (track: ManualDriveTrack, drive: ManualDrive, length: Double)? {
        guard let train = world.train(id: id), let found = world.manualDriveTakeOver(of: id) else { return nil }
        let units = WorldCoordinate.unitsPerMetre
        let remaining = found.run.length - found.covered
        guard remaining >= shortestMetres * units, let track = ManualDriveTrack(train: train, in: world, remaining: remaining) else { return nil }
        let limits = found.run.limits.compactMap { limit -> ManualDrive.Limit? in
            guard limit.end > found.covered else { return nil }
            return ManualDrive.Limit(start: Double(limit.start - found.covered) / Double(units), end: Double(limit.end - found.covered) / Double(units),
                                     speed: Double(limit.speed) / 3.6)
        }
        let course = ManualDrive.Course(stop: track.stopMetres, limits: limits, scheduled: Double(found.run.seconds - found.elapsed))
        let drive = ManualDrive(train: ManualDrive.Train(train.performance), course: course, speed: world.trainSpeedKMH(of: id) / 3.6)
        return (track, drive, Double(train.length))
    }
}

extension GameSession {
    /// Decision 686: whether the followed train can be driven by hand.
    public var canManualDrive: Bool {
        followedTrainID.map { world.canManualDrive($0) } ?? false
    }

    /// Decision 686: the player takes the followed train's handle: from
    /// now (or from when it leaves its stop) to its next stop, the 3D map
    /// draws it where the player drives it. The game runs at 1× for it:
    /// a faster game comes down to 1×, and one paused resumes at 1×
    /// (review L17-5: asked of the paused clock's speed, which is none, a
    /// game paused at 10× was left to resume at 10×). Until the handle is
    /// given back the speed goes no higher (``speedCap``).
    /// Nothing for a train without a timetable.
    public func startManualDrive() {
        guard let id = followedTrainID, world.canManualDrive(id) else { return }
        if world.clock.runningSpeed.tenthsPerTick > Map3DFollowSpeed.driving.tenthsPerTick {
            setRunningSpeed(Map3DFollowSpeed.driving)
        }
        manualDriveRun = ManualDriveRun(train: id)
        manualDriveReading = .waiting
        manualDrivePhase = .waiting
        manualDriveHeading = ManualDrive.Heading(world.map3DDriverHUD(of: id, in: language))
        manualDriveSettlement = nil
        stepManualDrive(at: nil)
    }

    /// Decision 686: gives the handle back: the map draws the world's
    /// train again.
    public func endManualDrive() {
        guard manualDriveRun != nil || manualDriveReading != nil else { return }
        manualDriveRun = nil
        manualDriveReading = nil
        manualDrivePhase = nil
        manualDriveHeading = nil
        manualDriveSettlement = nil
        updateFollowSounds()
    }

    /// Decision 686: moves the handle a step towards power (`up`) or
    /// towards the brake.
    public func moveManualDriveNotch(up: Bool) {
        guard let notch = manualDriveRun?.driving?.drive.notch else { return }
        setManualDriveNotch(up ? notch.raised : notch.lowered)
    }

    public func setManualDriveNotch(_ notch: ManualDrive.Notch) {
        guard manualDriveRun?.driving != nil else { return }
        manualDriveRun?.driving?.drive.set(notch)
        publishManualDrive()
    }

    /// Decision 686: steps the hand-driven run to `time` (seconds on the
    /// map's clock, `nil` for no time passing) and says where the 3D map
    /// draws its train: on which track, how many metres into the run, and
    /// how long the train is in world units; `nil` when none is driven, or
    /// while it waits at its stop.
    @discardableResult
    public func stepManualDrive(at time: Double?) -> (track: ManualDriveTrack, metres: Double, length: Double)? {
        guard var run = manualDriveRun else { return nil }
        guard followedTrainID == run.train, world.train(id: run.train)?.position != nil else {
            endManualDrive()
            return nil
        }
        let passed = time.flatMap { now in run.stepped.map { min(max(now - $0, 0), 0.25) } } ?? 0
        if let time { run.stepped = time }
        if run.driving == nil {
            run.driving = ManualDriveRun.takeOver(run.train, in: world)
            if run.driving != nil {
                manualDriveHeading = ManualDrive.Heading(world.map3DDriverHUD(of: run.train, in: language), after: manualDriveHeading)
            }
        } else if !world.clock.isPaused {
            // A second of the game for each of the clock's at 1×, and no
            // more whatever the clock runs at (a night being skipped).
            let rate = min(world.clock.speed.tenthsPerTick, Map3DFollowSpeed.driving.tenthsPerTick)
            run.driving?.drive.advance(seconds: passed * Double(rate) / Double(GameSpeed.x1.tenthsPerTick))
        }
        manualDriveRun = run
        settleManualDrive()
        publishManualDrive()
        return run.driving.map { ($0.track, $0.drive.distance, $0.length) }
    }

    /// Decision 693: tells the world of the run once it has ended, as the
    /// one command that makes it count
    /// (``PlayerCommand/Edit/settleDrivenRun(_:)``, logged and replayed as
    /// any edit), and keeps what the world made of it for the result
    /// card. A run the world refuses is left as decision 686 had it: its
    /// marks shown and nothing counted.
    private func settleManualDrive() {
        guard let run = manualDriveRun, !run.settled, let result = run.driving?.drive.result else { return }
        manualDriveRun?.settled = true
        manualDriveSettlement = (try? performCommand(.edit(.settleDrivenRun(result.run(of: run.train)))))?.drivenRun
    }

    /// Decision 686: for the screenshot review only: the run being driven
    /// ends as one stopped just short of the mark, a few seconds late, so
    /// its result can be looked at without driving a whole run.
    public func finishManualDriveForScreenshot() {
        guard var run = manualDriveRun, let driving = run.driving else { return }
        var drive = ManualDrive(train: driving.drive.train, course: .init(stop: 0.8, scheduled: -4), speed: 0.3)
        drive.set(ManualDrive.Notch(step: -ManualDrive.timetableBrakeStep))
        drive.advance(seconds: 5)
        run.driving = (driving.track, drive, driving.length)
        manualDriveRun = run
        settleManualDrive()
        publishManualDrive()
    }

    /// The speed and the drive the followed train is heard with while it is
    /// driven by hand.
    var manualDriveSound: (kmh: Double, drive: GameWorld.TrainDrive?)? {
        guard let drive = manualDriveRun?.driving?.drive else { return nil }
        // Review L17-14: a run that ended past the mark or out of time
        // keeps the speed it ended at, and the train is drawn standing:
        // it is heard standing too, not running until the card is closed.
        if drive.isOver { return (0, nil) }
        return (drive.speedKMH, drive.drive)
    }

    private func publishManualDrive() {
        let reading = manualDriveRun?.driving?.drive.reading ?? (manualDriveRun == nil ? nil : .waiting)
        guard reading != manualDriveReading else { return }
        manualDriveReading = reading
        if manualDrivePhase != reading?.phase { manualDrivePhase = reading?.phase }
        updateFollowSounds()
    }
}
