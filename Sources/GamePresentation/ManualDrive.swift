import GameCore

/// Decision 686: one run the player drives by hand on the 3D map, from
/// where they took the train over to its next stop.
///
/// It is a demonstration run kept by the presentation: the world's train
/// goes on running to its timetable and stays the only authority for where
/// the train is; nothing here is written to the world or saved. While it
/// lasts the 3D map draws the followed train where the player has driven
/// it (``ManualDriveTrack``), and at the stop the run is marked against the
/// stopping point and the timetable's arrival.
///
/// The train runs by the same figures as its running curve
/// (``TrainPerformance``): full power is its acceleration, the fifth brake
/// step its braking, so the timetable can be kept. The owner's references
/// have no driving model (decision 686's table); the steps, the marks and
/// the tolerances are this project's.
///
/// Metres, seconds, metres a second; `Double`, as the rest of the 3D map's
/// drawing (not GameCore's fixed point: it is never authoritative).
public struct ManualDrive: Equatable, Sendable {
    /// Where the one handle stands: power 1 to 5, neutral, brake 1 to 7,
    /// emergency.
    public struct Notch: Hashable, Comparable, Sendable {
        /// 5 (full power) down to 1, 0 neutral, −1 to −7 brake, −8
        /// emergency.
        public let step: Int

        public static let powerSteps = 5
        public static let brakeSteps = 7
        public static let neutral = Notch(step: 0)
        public static let fullPower = Notch(step: powerSteps)
        public static let fullBrake = Notch(step: -brakeSteps)
        public static let emergency = Notch(step: -brakeSteps - 1)
        /// Every position, emergency first.
        public static let all: [Notch] = (emergency.step...fullPower.step).map(Notch.init)

        public init(step: Int) {
            self.step = min(max(step, -Self.brakeSteps - 1), Self.powerSteps)
        }

        public static func < (a: Notch, b: Notch) -> Bool { a.step < b.step }

        public var isEmergency: Bool { self == .emergency }
        /// One step towards full power.
        public var raised: Notch { Notch(step: step + 1) }
        /// One step towards the emergency brake.
        public var lowered: Notch { Notch(step: step - 1) }

        /// "P3", "N", "B4", "EB": what a cab's handle is marked with, the
        /// same in both languages.
        public var mark: String {
            if isEmergency { return "EB" }
            if step > 0 { return "P\(step)" }
            return step < 0 ? "B\(-step)" : "N"
        }

        /// What VoiceOver reads for it.
        public func label(in language: DisplayLanguage) -> String {
            if isEmergency { return language.text("Emergency brake", "緊急煞車") }
            if step > 0 { return language.text("Power \(step)", "加速 \(step) 段") }
            if step < 0 { return language.text("Brake \(-step)", "煞車 \(-step) 段") }
            return language.text("Neutral", "空檔")
        }
    }

    /// How the train answers the handle.
    public struct Train: Equatable, Sendable {
        /// Full power, m/s².
        public let acceleration: Double
        /// The braking its timetable runs by, m/s²: brake step
        /// ``ManualDrive/timetableBrakeStep``.
        public let braking: Double
        /// m/s.
        public let topSpeed: Double
        /// How it slows rolling in neutral, m/s².
        public let rolling: Double

        public init(acceleration: Double, braking: Double, topSpeed: Double, rolling: Double) {
            self.acceleration = acceleration
            self.braking = braking
            self.topSpeed = topSpeed
            self.rolling = rolling
        }

        /// From the figures the train's running curve is made with:
        /// thousandths of a km/h a second, and km/h. It rolls as its coast
        /// says, or by ``ManualDrive/rollingKMHPerSecond``.
        public init(_ performance: TrainPerformance) {
            self.init(
                acceleration: Double(performance.acceleration) / 3_600,
                braking: Double(performance.braking) / 3_600,
                topSpeed: Double(performance.topSpeed) / 3.6,
                rolling: performance.coast.map { Double($0.deceleration) / 3_600 } ?? ManualDrive.rollingKMHPerSecond / 3.6
            )
        }
    }

    /// A speed limit on the way, from where the run was taken over.
    public struct Limit: Equatable, Sendable {
        public let start: Double
        public let end: Double
        /// m/s.
        public let speed: Double

        public init(start: Double, end: Double, speed: Double) {
            self.start = start
            self.end = end
            self.speed = speed
        }
    }

    /// The way to drive: how far the stopping point is, the limits before
    /// it, and when the timetable's train stands there.
    public struct Course: Equatable, Sendable {
        /// Metres from where the run was taken over to where the head
        /// stops.
        public let stop: Double
        public let limits: [Limit]
        /// Seconds from the take-over to the timetable's arrival.
        public let scheduled: Double

        public init(stop: Double, limits: [Limit] = [], scheduled: Double) {
            self.stop = stop
            self.limits = limits
            self.scheduled = scheduled
        }
    }

    /// How a run ended.
    public enum Outcome: Hashable, Sendable {
        /// Stood near the stopping point.
        case stopped
        /// Ran more than ``overrunMetres`` past it.
        case passed
        /// Not there ``lateSeconds`` after the timetable's arrival.
        case timedOut
    }

    /// The marks of a run that ended.
    public struct Result: Hashable, Sendable {
        /// Decision 693: the world's grades, as it marks a run settled.
        public typealias Grade = DrivenRun.Grade

        public let outcome: Outcome
        /// Metres past the stopping point (negative: short of it).
        public let offset: Double
        /// Seconds after the timetable's arrival (negative: early).
        public let lateness: Double
        public let overspeedSeconds: Double
        public let usedEmergency: Bool
        /// Out of ``ManualDrive/positionMarks``, ``ManualDrive/timeMarks``
        /// and ``ManualDrive/handlingMarks``; all 0 unless it stopped.
        public let position: Int
        public let time: Int
        public let handling: Int

        public var total: Int { position + time + handling }

        public var grade: Grade {
            DrivenRun.Marks(position: position, time: time, handling: handling).grade
        }

        /// Decision 693: the run as the world settles it, for `train`: its
        /// figures in whole world units and milliseconds, which the marks
        /// here are worked out from too, so the world gives it the same.
        public func run(of train: TrainID) -> DrivenRun {
            Self.run(of: train, outcome: outcome, offset: offset, lateness: lateness, overspeedSeconds: overspeedSeconds, usedEmergency: usedEmergency)
        }

        private static func run(
            of train: TrainID, outcome: Outcome, offset: Double, lateness: Double, overspeedSeconds: Double, usedEmergency: Bool
        ) -> DrivenRun {
            func whole(_ value: Double) -> Int64 {
                Int64(min(max(value.rounded(), -Double(DrivenRun.longest)), Double(DrivenRun.longest)))
            }
            let kind: DrivenRun.Outcome = switch outcome {
            case .stopped: .stopped
            case .passed: .passed
            case .timedOut: .timedOut
            }
            return DrivenRun(
                train: train, outcome: kind, offset: whole(offset * Double(WorldCoordinate.unitsPerMetre)), lateness: whole(lateness * 1_000),
                overspeed: max(0, whole(overspeedSeconds * 1_000)), usedEmergency: usedEmergency
            )
        }

        /// A run that ended so, marked by the world's rules
        /// (``DrivenRun/marks``).
        init(outcome: Outcome, offset: Double, lateness: Double, overspeedSeconds: Double, usedEmergency: Bool) {
            let marks = Self.run(
                of: TrainID(rawValue: 1), outcome: outcome, offset: offset, lateness: lateness, overspeedSeconds: overspeedSeconds,
                usedEmergency: usedEmergency
            ).marks
            self.outcome = outcome
            self.offset = offset
            self.lateness = lateness
            self.overspeedSeconds = overspeedSeconds
            self.usedEmergency = usedEmergency
            position = marks.position
            time = marks.time
            handling = marks.handling
        }
    }

    // MARK: The rules' figures

    /// Brake step 5 is the braking the timetable runs by; 6 and 7 brake
    /// harder, in the same steps.
    public static let timetableBrakeStep = 5
    /// The emergency brake, against the timetable's braking.
    public static let emergencyShare = 1.6
    /// A train with no coast of its own loses 0.1 km/h a second rolling.
    public static let rollingKMHPerSecond = 0.1
    /// How fast the pull or the braking follows the handle, m/s³; the
    /// emergency brake ``emergencyJerk``.
    public static let jerk = 1.0
    public static let emergencyJerk = 3.0
    /// The longest step worked out at once, seconds: a frame is cut into
    /// steps this long, so the run does not depend on the frame rate.
    public static let stepSeconds = 0.02
    /// Over a limit by more than this counts, m/s (3 km/h).
    public static let overspeedTolerance = 3 / 3.6
    /// A stand this near short of the stopping point ends the run, metres;
    /// shorter of it, the player may pull forward again.
    public static let stopWindowMetres = 50.0
    /// Past the stopping point by more than this, the stop was missed.
    public static let overrunMetres = 50.0
    /// The run is given up this long after the timetable's arrival.
    public static let lateSeconds = 180.0

    public static let positionMarks = 50
    public static let timeMarks = 30
    public static let handlingMarks = 20
    /// Full marks within half a metre; none 25 m short or 12.5 m past (a
    /// train past its platform's end is worse than one short of it).
    public static let exactMetres = 0.5
    public static let shortMetres = 25.0
    public static let pastMetres = 12.5
    /// Full marks within 5 seconds of the timetable; none a minute off.
    public static let exactSeconds = 5.0
    public static let offSeconds = 60.0
    /// Each second over a limit, and the emergency brake.
    public static let overspeedMarksPerSecond = 2.0
    public static let emergencyMarks = 10

    /// Decision 704: "stop ahead" shows from this many times the
    /// timetable's braking distance, and always within these metres.
    public static let stopAheadShare = 1.5
    public static let stopAheadMetres = 200.0

    // MARK: The run

    public let train: Train
    public let course: Course
    public private(set) var notch: Notch = .neutral
    /// Metres from where the run was taken over.
    public private(set) var distance = 0.0
    /// m/s.
    public private(set) var speed: Double
    /// What the handle has brought on by now, m/s² (negative braking).
    public private(set) var applied = 0.0
    /// Seconds since the take-over.
    public private(set) var elapsed = 0.0
    public private(set) var overspeedSeconds = 0.0
    public private(set) var usedEmergency = false
    public private(set) var result: Result?

    public init(train: Train, course: Course, speed: Double = 0) {
        self.init(train: train, course: course, speed: speed, distance: 0)
    }

    /// A run already `distance` metres on its way: for the screenshot
    /// review's looks at a run near its stop.
    init(train: Train, course: Course, speed: Double, distance: Double) {
        self.train = train
        self.course = course
        self.speed = min(max(speed, 0), train.topSpeed)
        self.distance = distance
    }

    public var isOver: Bool { result != nil }
    public var speedKMH: Double { speed * 3.6 }
    /// Metres still to the stopping point (negative past it).
    public var remaining: Double { course.stop - distance }

    /// Moves the handle; nothing once the run is over.
    public mutating func set(_ notch: Notch) {
        guard !isOver else { return }
        self.notch = notch
    }

    /// The limit over the head at `distance`, m/s: the lowest that covers
    /// it, or the train's top speed.
    public func limit(at distance: Double) -> Double {
        course.limits.reduce(train.topSpeed) { $1.start <= distance && distance < $1.end ? min($0, $1.speed) : $0 }
    }

    /// The limit kept to now, when it is one of the way's (not just the
    /// train's top speed), m/s.
    public var limitHere: Double? {
        let limit = limit(at: distance)
        return limit < train.topSpeed ? limit : nil
    }

    public var isOverspeed: Bool { speed > limit(at: distance) + Self.overspeedTolerance }

    /// Decision 704: whether the brake is due: the run is on, the train
    /// moves, and the stopping point is no farther than the timetable's
    /// braking from this speed with ``stopAheadShare`` to spare, or than
    /// ``stopAheadMetres``.
    public var isStopAhead: Bool {
        guard !isOver, speed > 0, remaining > 0 else { return false }
        let braking = train.braking > 0 ? speed * speed / (2 * train.braking) : 0
        return remaining <= max(braking * Self.stopAheadShare, Self.stopAheadMetres)
    }

    /// What the handle asks for at `speed`, m/s².
    func asked(at speed: Double) -> Double {
        if notch.isEmergency { return -train.braking * Self.emergencyShare }
        if notch.step > 0 {
            return speed < train.topSpeed ? train.acceleration * Double(notch.step) / Double(Notch.powerSteps) : 0
        }
        if notch.step < 0 { return -train.braking * Double(-notch.step) / Double(Self.timetableBrakeStep) }
        return speed > 0 ? -train.rolling : 0
    }

    /// What drives the train now, for its sound (``RunningSound``).
    var drive: GameWorld.TrainDrive? {
        guard speed > 0 else { return nil }
        if notch.step > 0 { return applied > 0 ? .powering : .holding }
        return notch.step < 0 ? .braking : .coasting
    }

    /// Runs on for `seconds`.
    public mutating func advance(seconds: Double) {
        var left = min(max(seconds, 0), 5)
        while left > 0, !isOver {
            let dt = min(left, Self.stepSeconds)
            left -= dt
            step(dt)
        }
    }

    private mutating func step(_ dt: Double) {
        let asked = asked(at: speed)
        let reach = (notch.isEmergency ? Self.emergencyJerk : Self.jerk) * dt
        applied += min(max(asked - applied, -reach), reach)
        // Brakes hold a train at a stand: it never runs back.
        let next = min(max(speed + applied * dt, 0), train.topSpeed)
        distance += (speed + next) / 2 * dt
        speed = next
        elapsed += dt
        if isOverspeed { overspeedSeconds += dt }
        if notch.isEmergency, speed > 0 { usedEmergency = true }
        if distance > course.stop + Self.overrunMetres {
            finish(.passed)
        } else if speed == 0, notch.step < 0, distance > 0, distance >= course.stop - Self.stopWindowMetres {
            finish(.stopped)
        } else if elapsed > course.scheduled + Self.lateSeconds {
            finish(.timedOut)
        }
    }

    private mutating func finish(_ outcome: Outcome) {
        result = Result(outcome: outcome, offset: distance - course.stop, lateness: elapsed - course.scheduled,
                        overspeedSeconds: overspeedSeconds, usedEmergency: usedEmergency)
    }
}

// MARK: - What the panel shows

extension ManualDrive {
    /// What the driving panel shows of a run, in whole figures, so it is
    /// told to the interface only when one of them changes.
    public struct Reading: Hashable, Sendable {
        public enum Phase: Hashable, Sendable {
            /// The train stands at a stop: the run starts when it leaves.
            case waiting
            case driving
            case over
        }

        public let phase: Phase
        public let notch: Notch
        /// Whole km/h.
        public let speed: Int
        /// The way's limit kept to now, km/h.
        public let limit: Int?
        public let isOverspeed: Bool
        /// Metres to the stopping point: whole metres, tenths within 10 m
        /// (``distanceText``); `nil` while waiting.
        public let remainingTenths: Int?
        /// Decision 690: whole seconds past the timetable's arrival, 0
        /// until then: the player's own run against the timetable, not
        /// the world's train, which keeps to it meanwhile.
        public let lateness: Int
        /// Decision 704: the stopping point is near enough that the brake
        /// is due (``ManualDrive/isStopAhead``): the panel's one line.
        public let stopAhead: Bool
        public let result: Result?

        /// Before the train has left its stop.
        public static let waiting = Reading(phase: .waiting, notch: .neutral, speed: 0, limit: nil, isOverspeed: false,
                                            remainingTenths: nil, lateness: 0, stopAhead: false, result: nil)

        /// Decision 704: "Stop ahead 161 m", only while ``stopAhead``.
        public func stopAheadText(in language: DisplayLanguage) -> String? {
            guard stopAhead, let distance = distanceText(in: language) else { return nil }
            return language.text("Stop ahead \(distance)", "前方停車 \(distance)")
        }

        /// "640 m", "8.4 m" within 10 m, "3.2 m past" beyond the point.
        public func distanceText(in language: DisplayLanguage) -> String? {
            guard let tenths = remainingTenths else { return nil }
            if tenths < 0 {
                let past = ManualDrive.metresText(tenths: -tenths)
                return language.text("\(past) past", "超過 \(past)")
            }
            return tenths < 100 ? ManualDrive.metresText(tenths: tenths) : Map3DDriverHUD.distanceText(Int64(tenths / 10))
        }

        /// "On time", or "8 s late" once the timetable's arrival has
        /// passed (decision 690).
        public func latenessText(in language: DisplayLanguage) -> String {
            Map3DDriverHUD.latenessText(Int64(lateness), in: language)
        }

        /// What VoiceOver reads for the panel's figures; with the stop the
        /// run is driven to, when it is known (decision 690).
        public func label(in language: DisplayLanguage, stop: String? = nil) -> String {
            var text = "\(speed) km/h" + language.text(", ", "，") + notch.label(in: language)
            if let limit { text += language.text(", limit \(limit) km/h", "，限速 \(limit) km/h") }
            if let stop { text += language.text(", next stop \(stop)", "，下一站 \(stop)") }
            if let distance = distanceText(in: language) {
                text += stopAhead ? language.text(", stop ahead in \(distance)", "，前方停車 \(distance)")
                    : language.text(", stop in \(distance)", "，停車點 \(distance)")
            }
            if phase == .driving { text += language.text(", ", "，") + latenessText(in: language) }
            return text
        }
    }

    /// A run's result in words.
    public struct ResultText: Hashable, Sendable {
        public let title: String
        /// Where it stopped and how late; empty when it did not stop.
        public let lines: [String]
        public let total: Int?
        public let grade: String?
    }

    static func metresText(tenths: Int) -> String {
        "\(tenths / 10).\(tenths % 10) m"
    }

    public var reading: Reading {
        // Whole metres until the last ten, so the panel is not redrawn
        // every frame on the way.
        let tenths = Int((remaining * 10).rounded())
        return Reading(
            phase: isOver ? .over : .driving, notch: notch, speed: Int(speedKMH.rounded()),
            limit: limitHere.map { Int(($0 * 3.6).rounded()) }, isOverspeed: isOverspeed,
            remainingTenths: abs(tenths) < 100 ? tenths : Int(remaining.rounded()) * 10,
            lateness: max(0, Int((elapsed - course.scheduled).rounded(.down))),
            stopAhead: isStopAhead,
            result: result
        )
    }
}

extension ManualDrive.Result {
    /// What the result card says; with `settled`, what the world made of
    /// the run (decision 693), a last line says what it brought the
    /// company.
    public func text(in language: DisplayLanguage, settled: DrivenRunSettlement?) -> ManualDrive.ResultText {
        let text = text(in: language)
        guard let line = settled.flatMap({ ManualDrive.settlementText($0, stopped: outcome == .stopped, in: language) }) else { return text }
        return .init(title: text.title, lines: text.lines + [line], total: text.total, grade: text.grade)
    }

    public func text(in language: DisplayLanguage) -> ManualDrive.ResultText {
        switch outcome {
        case .passed:
            return .init(title: language.text("Ran past the stop", "過站了"), lines: [], total: nil, grade: nil)
        case .timedOut:
            return .init(title: language.text("Did not reach the stop in time", "沒有及時到站"), lines: [], total: nil, grade: nil)
        case .stopped:
            let tenths = Int((abs(offset) * 10).rounded())
            let metres = ManualDrive.metresText(tenths: tenths)
            let place = abs(offset) <= ManualDrive.exactMetres ? language.text("Stopped on the mark", "停在停車點上")
                : offset < 0 ? language.text("Stopped \(metres) short", "差 \(metres) 沒到停車點")
                : language.text("Stopped \(metres) past the mark", "超過停車點 \(metres)")
            var lines = [place, Map3DDriverHUD.latenessText(Int64(lateness.rounded()), in: language)]
            if overspeedSeconds >= 0.5 {
                let seconds = Int(overspeedSeconds.rounded())
                lines.append(language.text("Over the limit for \(max(seconds, 1)) s", "超速 \(max(seconds, 1)) 秒"))
            }
            if usedEmergency { lines.append(language.text("Used the emergency brake", "用了緊急煞車")) }
            return .init(title: language.text("Arrived", "到站"), lines: lines, total: total, grade: grade.rawValue)
        }
    }
}

// MARK: - The lever

extension ManualDrive {
    /// Decision 704: the handle drawn as one lever with a notch a step,
    /// full power at the top and the emergency brake at the bottom: where
    /// a notch stands along it, which notch a drag ends on, and how hard
    /// a step is felt.
    public enum Lever {
        /// How far down the lever `notch` stands: 0 at full power, 1 at
        /// the emergency brake.
        public static func fraction(of notch: Notch) -> Double {
            Double(Notch.fullPower.step - notch.step) / Double(Notch.all.count - 1)
        }

        /// The notch a drag that began at `start` stands on after the
        /// finger went `fraction` of the lever's length down (negative
        /// up): the nearest one, so letting go leaves it on a notch.
        public static func notch(from start: Notch, dragged fraction: Double) -> Notch {
            guard fraction.isFinite else { return start }
            let steps = (fraction * Double(Notch.all.count - 1)).rounded()
            return Notch(step: start.step - Int(max(-100, min(100, steps))))
        }

        /// Review L19, P3-15: the drag on the handle now: where the finger
        /// came down and the notch the handle stood on then. A drag the
        /// system cancels never says it ended, so the next one is told
        /// apart by where it began, and starts from the notch the handle
        /// stands on then, not from the one kept.
        public struct Drag: Equatable, Sendable {
            public let x: Double
            public let y: Double
            public let notch: Notch

            /// The drag that began at (`x`, `y`): `held` when that is the
            /// one it kept, otherwise a new one from `notch`, where the
            /// handle stands now.
            public static func began(atX x: Double, y: Double, on notch: Notch, held: Drag?) -> Drag {
                if let held, held.x == x, held.y == y { return held }
                return Drag(x: x, y: y, notch: notch)
            }
        }

        /// How a move of the handle is felt.
        public enum Detent: Hashable, Sendable {
            /// One notch among the power or the brake ones.
            case step
            /// Reaching or crossing neutral, and the emergency brake.
            case heavy
        }

        /// What moving from `old` to `new` is felt as; `nil` for no move.
        public static func detent(from old: Notch, to new: Notch) -> Detent? {
            guard old != new else { return nil }
            return new.isEmergency || new == .neutral || old.step * new.step < 0 ? .heavy : .step
        }
    }

    public static func leverText(in language: DisplayLanguage) -> String {
        language.text("Handle", "把手")
    }

    /// What VoiceOver adds to the lever.
    public static func leverHint(in language: DisplayLanguage) -> String {
        language.text("Drag up for power and down for the brake, or tap above or below the handle for one step.",
                      "往上拉加速，往下拉煞車；點把手的上方或下方一次動一格。")
    }

    public static func emergencyText(in language: DisplayLanguage) -> String {
        Notch.emergency.label(in: language)
    }
}

// MARK: - The panel's words

extension ManualDrive {
    public static func startText(in language: DisplayLanguage) -> String {
        language.text("Drive", "駕駛")
    }

    /// Under the start button, and what VoiceOver adds to it.
    public static func startHint(in language: DisplayLanguage) -> String {
        language.text("Drive this train to its next stop yourself.", "自己把這班車開到下一站。")
    }

    public static func waitingText(in language: DisplayLanguage) -> String {
        language.text("You drive when it leaves the stop.", "離站後由你駕駛。")
    }

    public static func powerText(in language: DisplayLanguage) -> String {
        language.text("Power", "加速")
    }

    public static func brakeText(in language: DisplayLanguage) -> String {
        language.text("Brake", "煞車")
    }

    public static func endText(in language: DisplayLanguage) -> String {
        language.text("Stop driving", "結束駕駛")
    }

    public static func doneText(in language: DisplayLanguage) -> String {
        language.text("Back to the train", "回到列車")
    }

    /// Decision 690: before the name of the stop driven to.
    public static func nextLabel(in language: DisplayLanguage) -> String {
        language.text("Next", "下一站")
    }

    public static func stopLabel(in language: DisplayLanguage) -> String {
        language.text("Stop in", "停車點")
    }

    /// Decision 693: what a run settled brought the company: what it
    /// earned, with the passengers it carried, and "a new best" for the
    /// most marks so far after the first; without accounts, which run it
    /// was and the best so far. Nothing for a run that did not stop.
    static func settlementText(_ settled: DrivenRunSettlement, stopped: Bool, in language: DisplayLanguage) -> String? {
        guard stopped else { return nil }
        let best = settled.isBest && settled.record.arrivals > 1 ? language.text(" · new best", " · 新紀錄") : ""
        if settled.bonus > .zero {
            let riders = settled.riders.groupedText
            return language.text(
                "Earned the company \(settled.bonus.moneyText) · \(riders) aboard", "替公司多賺 \(settled.bonus.moneyText) · 車上 \(riders) 人"
            ) + best
        }
        if settled.keepsAccounts {
            return language.text(
                "Earned the company nothing: score over \(DrivenRun.bonusFloor) to earn", "沒有替公司多賺：超過 \(DrivenRun.bonusFloor) 分才有"
            )
        }
        let runs = settled.record.runs.groupedText
        return language.text("Run \(runs) by hand · best \(settled.record.best) points", "手動駕駛第 \(runs) 趟 · 最佳 \(settled.record.best) 分")
    }

    public static func marksText(_ total: Int, in language: DisplayLanguage) -> String {
        language.text("\(total) points", "\(total) 分")
    }
}
