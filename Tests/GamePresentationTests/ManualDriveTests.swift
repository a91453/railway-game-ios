@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 686: a run the player drives by hand on the 3D map.
final class ManualDriveTests: XCTestCase {
    private let train = ManualDrive.Train(.standard)

    /// How long the timetable's train takes over `metres` from a stand to a
    /// stand: full power, top speed, its braking.
    private func timetableSeconds(_ metres: Double, train: ManualDrive.Train) -> Double {
        let up = train.topSpeed * train.topSpeed / (2 * train.acceleration), down = train.topSpeed * train.topSpeed / (2 * train.braking)
        precondition(metres > up + down)
        return train.topSpeed / train.acceleration + train.topSpeed / train.braking + (metres - up - down) / train.topSpeed
    }

    /// Full power, then the timetable's brake step from where it stops the
    /// train a little short, then a light brake to the mark.
    private func driveByTheBook(_ drive: inout ManualDrive) {
        drive.set(.fullPower)
        while !drive.isOver {
            // What the brake still to come on, and the one on now, need.
            let braking = drive.train.braking
            let needed = drive.speed * drive.speed / (2 * braking) + drive.speed * (braking / ManualDrive.jerk) / 2 + drive.speed * 0.05
            if drive.notch.step > 0, drive.remaining <= needed + 3 {
                drive.set(ManualDrive.Notch(step: -ManualDrive.timetableBrakeStep))
            } else if drive.notch.step < 0, drive.speed > 0.2 {
                // Eases or tightens the brake to stop on the mark.
                let wanted = drive.remaining > 0.2 ? drive.speed * drive.speed / (2 * drive.remaining) : braking * 1.4
                let step = Int((wanted / braking * Double(ManualDrive.timetableBrakeStep)).rounded(.up))
                drive.set(ManualDrive.Notch(step: -min(max(step, 1), ManualDrive.Notch.brakeSteps)))
            }
            drive.advance(seconds: 1.0 / 60)
        }
    }

    func testTheHandleHasFivePowerStepsSevenBrakeStepsAndTheEmergencyBrake() {
        XCTAssertEqual(ManualDrive.Notch.all.map(\.mark), ["EB", "B7", "B6", "B5", "B4", "B3", "B2", "B1", "N", "P1", "P2", "P3", "P4", "P5"])
        XCTAssertEqual(ManualDrive.Notch.fullPower.raised, .fullPower, "no further than full power")
        XCTAssertEqual(ManualDrive.Notch.emergency.lowered, .emergency)
        XCTAssertEqual(ManualDrive.Notch.neutral.lowered.mark, "B1")
        XCTAssertEqual(ManualDrive.Notch(step: 3).label(in: .traditionalChinese), "加速 3 段")
        XCTAssertEqual(ManualDrive.Notch(step: -4).label(in: .english), "Brake 4")
        XCTAssertEqual(ManualDrive.Notch.emergency.label(in: .traditionalChinese), "緊急煞車")
        XCTAssertEqual(ManualDrive.Notch.neutral.label(in: .traditionalChinese), "空檔")
    }

    func testTheTrainRunsByItsRunningCurvesFigures() {
        XCTAssertEqual(train.acceleration, 1.5 / 3.6, accuracy: 1e-9, "1.5 km/h a second")
        XCTAssertEqual(train.braking, 2.5 / 3.6, accuracy: 1e-9)
        XCTAssertEqual(train.topSpeed, 110 / 3.6, accuracy: 1e-9)
        XCTAssertEqual(ManualDrive.Train(.highSpeed).rolling, 0.45 / 3.6, accuracy: 1e-9, "a train that coasts rolls as its coast says")

        var drive = ManualDrive(train: train, course: .init(stop: 50_000, scheduled: 3_000))
        drive.set(.fullPower)
        drive.advance(seconds: 2)
        drive.advance(seconds: 2)
        XCTAssertEqual(drive.applied, train.acceleration, accuracy: 1e-9, "the pull has come on")
        let speed = drive.speed
        drive.advance(seconds: 4)
        XCTAssertEqual(drive.speed - speed, train.acceleration * 4, accuracy: 1e-6, "full power is its acceleration")
        for _ in 0..<60 { drive.advance(seconds: 2) }
        XCTAssertEqual(drive.speed, train.topSpeed, "never over its top speed")
        XCTAssertEqual(drive.drive, .holding)

        drive.set(.neutral)
        for _ in 0..<5 { drive.advance(seconds: 2) }
        XCTAssertEqual(drive.drive, .coasting)
        XCTAssertLessThan(drive.speed, train.topSpeed, "it rolls, losing a little speed")
        XCTAssertGreaterThan(drive.speedKMH, 108)

        drive.set(ManualDrive.Notch(step: -ManualDrive.timetableBrakeStep))
        for _ in 0..<3 { drive.advance(seconds: 1) }
        XCTAssertEqual(drive.applied, -train.braking, accuracy: 1e-9, "brake step 5 is the timetable's braking")
        XCTAssertEqual(drive.drive, .braking)
        drive.set(.fullBrake)
        for _ in 0..<3 { drive.advance(seconds: 1) }
        XCTAssertEqual(drive.applied, -train.braking * 1.4, accuracy: 1e-9)
        drive.set(.emergency)
        for _ in 0..<3 { drive.advance(seconds: 1) }
        XCTAssertEqual(drive.applied, -train.braking * ManualDrive.emergencyShare, accuracy: 1e-9)
        XCTAssertTrue(drive.usedEmergency)
    }

    func testARunDoesNotDependOnTheFrameRate() {
        func run(frame: Double) -> ManualDrive {
            var drive = ManualDrive(train: train, course: .init(stop: 5_000, scheduled: 300))
            drive.set(.fullPower)
            var time = 0.0
            while time < 30 - 1e-9 {
                drive.advance(seconds: frame)
                time += frame
            }
            return drive
        }
        let slow = run(frame: 0.1), fast = run(frame: 0.02)
        XCTAssertEqual(slow.distance, fast.distance, accuracy: 1e-6)
        XCTAssertEqual(slow.speed, fast.speed, accuracy: 1e-6)
    }

    func testDrivenByTheBookItStopsOnTheMarkOnTimeWithTopMarks() throws {
        for (performance, metres) in [(TrainPerformance.standard, 3_000.0), (.metro, 1_200), (.emu800, 8_000)] {
            let train = ManualDrive.Train(performance)
            // The timetable's whole seconds, as a run's are.
            let scheduled = timetableSeconds(metres, train: train).rounded(.up)
            var drive = ManualDrive(train: train, course: .init(stop: metres, scheduled: scheduled))
            driveByTheBook(&drive)
            let result = try XCTUnwrap(drive.result)
            XCTAssertEqual(result.outcome, .stopped)
            XCTAssertLessThan(abs(result.offset), 3, "\(performance)")
            XCTAssertLessThan(abs(result.lateness), 15, "the timetable can be kept: \(result.lateness)")
            XCTAssertEqual(result.handling, ManualDrive.handlingMarks)
            XCTAssertGreaterThanOrEqual(result.total, 85, "\(performance): \(result)")
            XCTAssertTrue([.s, .a].contains(result.grade))
            // Nothing moves once it is over.
            let distance = drive.distance
            drive.set(.fullPower)
            drive.advance(seconds: 5)
            XCTAssertEqual(drive.distance, distance)
            XCTAssertEqual(drive.reading.phase, .over)
        }
    }

    func testTheMarksFallWithTheDistanceFromTheMarkAndTheTimeOffTheTimetable() {
        // Decision 693: marked by the world's rules, from the run's figures
        // in whole world units and milliseconds.
        func marked(offset: Double = 0, lateness: Double = 0) -> ManualDrive.Result {
            ManualDrive.Result(outcome: .stopped, offset: offset, lateness: lateness, overspeedSeconds: 0, usedEmergency: false)
        }
        XCTAssertEqual(marked(offset: -0.5).position, 50)
        XCTAssertEqual(marked(offset: -12.75).position, 25)
        XCTAssertEqual(marked(offset: -25).position, 0)
        XCTAssertEqual(marked(lateness: 32.5).time, 15)
        XCTAssertEqual(marked(offset: -12.75, lateness: 32.5).run(of: TrainID(rawValue: 4)), DrivenRun(
            train: TrainID(rawValue: 4), outcome: .stopped, offset: -816, lateness: 32_500, overspeed: 0, usedEmergency: false
        ))

        // Stopped ten metres short, late: where a light brake from 150 m
        // brings it to a stand, then the same with the mark 10 m on.
        func braked(stop: Double) -> ManualDrive {
            var drive = ManualDrive(train: train, course: .init(stop: stop, scheduled: 20))
            drive.set(.fullPower)
            while drive.distance < 150 { drive.advance(seconds: 0.1) }
            drive.set(ManualDrive.Notch(step: -3))
            while !drive.isOver, drive.speed > 0 { drive.advance(seconds: 0.1) }
            return drive
        }
        let drive = braked(stop: braked(stop: 5_000).distance + 10)
        let result = drive.result!
        XCTAssertEqual(result.outcome, .stopped)
        XCTAssertEqual(result.offset, -10, accuracy: 1e-6)
        XCTAssertGreaterThan(result.offset, -ManualDrive.stopWindowMetres)
        XCTAssertLessThan(result.position, ManualDrive.positionMarks)
        XCTAssertGreaterThan(result.lateness, 0)
        let text = result.text(in: .traditionalChinese)
        XCTAssertEqual(text.title, "到站")
        XCTAssertTrue(text.lines[0].hasPrefix("差 "), text.lines[0])
        XCTAssertTrue(text.lines[0].hasSuffix(" m 沒到停車點"), text.lines[0])
        XCTAssertEqual(text.total, result.total)
        XCTAssertEqual(text.grade, result.grade.rawValue)
        XCTAssertTrue(result.text(in: .english).lines[0].hasSuffix(" short"))
    }

    func testAStandFarShortOfTheStopIsNotTheEnd() {
        var drive = ManualDrive(train: train, course: .init(stop: 2_000, scheduled: 400))
        drive.set(.fullPower)
        while drive.distance < 100 { drive.advance(seconds: 0.1) }
        drive.set(.fullBrake)
        for _ in 0..<300 { drive.advance(seconds: 0.1) }
        XCTAssertEqual(drive.speed, 0)
        XCTAssertFalse(drive.isOver, "the player pulls forward again")
        let stood = drive.distance
        drive.set(.fullPower)
        for _ in 0..<100 { drive.advance(seconds: 0.1) }
        XCTAssertGreaterThan(drive.distance, stood, "it never runs back, and pulls away once the brake is off")
    }

    func testRunningPastTheStopOrNeverReachingItEndsTheRunWithNoMarks() {
        var past = ManualDrive(train: train, course: .init(stop: 500, scheduled: 60))
        past.set(.fullPower)
        while !past.isOver { past.advance(seconds: 0.1) }
        XCTAssertEqual(past.result?.outcome, .passed)
        XCTAssertEqual(past.result?.total, 0)
        XCTAssertEqual(past.result?.grade, .d)
        XCTAssertEqual(past.result?.text(in: .traditionalChinese).title, "過站了")
        XCTAssertNil(past.result?.text(in: .english).total)

        var never = ManualDrive(train: train, course: .init(stop: 500, scheduled: 60))
        for _ in 0..<2_500 { never.advance(seconds: 0.1) }
        XCTAssertEqual(never.result?.outcome, .timedOut)
        XCTAssertEqual(never.elapsed, 60 + ManualDrive.lateSeconds, accuracy: 0.1)
        XCTAssertEqual(never.result?.text(in: .english).title, "Did not reach the stop in time")
    }

    func testSpeedingAndTheEmergencyBrakeCostHandlingMarks() throws {
        let limit = ManualDrive.Limit(start: 300, end: 600, speed: 40 / 3.6)
        var drive = ManualDrive(train: train, course: .init(stop: 1_500, limits: [limit], scheduled: 120))
        XCTAssertNil(drive.limitHere, "only the train's top speed at first")
        drive.set(.fullPower)
        var sawLimit = false, sawOverspeed = false
        while drive.distance < 1_500 - 60 {
            drive.advance(seconds: 0.05)
            if drive.limitHere != nil {
                XCTAssertEqual(drive.reading.limit, 40)
                sawLimit = true
            }
            if drive.isOverspeed {
                XCTAssertTrue(drive.reading.isOverspeed)
                sawOverspeed = true
            }
        }
        XCTAssertTrue(sawLimit)
        XCTAssertTrue(sawOverspeed)
        XCTAssertNil(drive.limitHere, "past the limit's end")
        drive.set(.emergency)
        while !drive.isOver { drive.advance(seconds: 0.05) }
        let result = try XCTUnwrap(drive.result)
        XCTAssertGreaterThan(result.overspeedSeconds, 5)
        XCTAssertTrue(result.usedEmergency)
        XCTAssertEqual(result.handling, 0)
        if result.outcome == .stopped {
            let lines = result.text(in: .traditionalChinese).lines
            XCTAssertTrue(lines.contains { $0.hasPrefix("超速 ") })
            XCTAssertTrue(lines.contains("用了緊急煞車"))
        }
    }

    func testThePanelsFiguresAreWholeUntilTheLastTenMetres() {
        var drive = ManualDrive(train: train, course: .init(stop: 1_234.4, scheduled: 100))
        XCTAssertEqual(drive.reading.phase, .driving)
        XCTAssertEqual(drive.reading.distanceText(in: .english), "1.2 km")
        XCTAssertEqual(drive.reading.label(in: .traditionalChinese), "0 km/h，空檔，停車點 1.2 km，準點")
        XCTAssertEqual(drive.reading.label(in: .english, stop: "Beta"), "0 km/h, Neutral, next stop Beta, stop in 1.2 km, On time")
        drive = ManualDrive(train: train, course: .init(stop: 8.44, scheduled: 100))
        XCTAssertEqual(drive.reading.distanceText(in: .traditionalChinese), "8.4 m")
        drive = ManualDrive(train: train, course: .init(stop: -3.21, scheduled: 100))
        XCTAssertEqual(drive.reading.distanceText(in: .traditionalChinese), "超過 3.2 m")
        XCTAssertEqual(drive.reading.distanceText(in: .english), "3.2 m past")
        XCTAssertNil(ManualDrive.Reading.waiting.distanceText(in: .english))
        XCTAssertEqual(ManualDrive.Reading.waiting.phase, .waiting)
    }

    /// Decision 690: the card's punctuality is the player's own run
    /// against the timetable: on time until its arrival has passed, then
    /// late by the whole seconds since.
    func testThePanelSaysOnTimeUntilTheTimetablesArrivalThenHowLate() {
        var drive = ManualDrive(train: train, course: .init(stop: 5_000, scheduled: 10))
        XCTAssertEqual(drive.reading.lateness, 0)
        XCTAssertEqual(drive.reading.latenessText(in: .traditionalChinese), "準點")
        for _ in 0..<21 { drive.advance(seconds: 0.5) }
        XCTAssertEqual(drive.reading.lateness, 0, "not a whole second yet")
        for _ in 0..<16 { drive.advance(seconds: 0.5) }
        XCTAssertEqual(drive.reading.lateness, 8)
        XCTAssertEqual(drive.reading.latenessText(in: .traditionalChinese), "晚 8 秒")
        XCTAssertEqual(drive.reading.latenessText(in: .english), "8 s late")
        XCTAssertEqual(ManualDrive.Reading.waiting.lateness, 0)
    }

    /// Decision 704: "stop ahead" shows only once the brake is due: within
    /// one and a half times the timetable's braking distance from this
    /// speed, or the last 200 m; never at a stand, past the point or once
    /// the run is over.
    func testStopAheadShowsOnlyOnceTheBrakeIsDue() {
        let speed = train.topSpeed, braking = speed * speed / (2 * train.braking)
        precondition(braking * ManualDrive.stopAheadShare > ManualDrive.stopAheadMetres)
        var drive = ManualDrive(train: train, course: .init(stop: braking * 1.5 + 50, scheduled: 100), speed: speed)
        XCTAssertFalse(drive.reading.stopAhead)
        XCTAssertNil(drive.reading.stopAheadText(in: .traditionalChinese), "nothing on the way there")
        drive = ManualDrive(train: train, course: .init(stop: braking * 1.5 - 1, scheduled: 100), speed: speed)
        XCTAssertTrue(drive.reading.stopAhead)
        drive = ManualDrive(train: train, course: .init(stop: 160, scheduled: 100), speed: 2)
        XCTAssertEqual(drive.reading.stopAheadText(in: .traditionalChinese), "前方停車 160 m")
        XCTAssertEqual(drive.reading.stopAheadText(in: .english), "Stop ahead 160 m")
        XCTAssertEqual(drive.reading.label(in: .traditionalChinese), "7 km/h，空檔，前方停車 160 m，準點")
        drive = ManualDrive(train: train, course: .init(stop: 201, scheduled: 100), speed: 2)
        XCTAssertFalse(drive.reading.stopAhead, "slow and still far")
        drive = ManualDrive(train: train, course: .init(stop: 161, scheduled: 100))
        XCTAssertFalse(drive.reading.stopAhead, "standing")
        drive = ManualDrive(train: train, course: .init(stop: -3, scheduled: 100), speed: 2)
        XCTAssertFalse(drive.reading.stopAhead, "past the point")
        XCTAssertFalse(ManualDrive.Reading.waiting.stopAhead)
    }

    /// Decision 704: the lever. A notch a step from full power at the top
    /// to the emergency brake at the bottom; a drag moves the handle from
    /// where it stood to the nearest notch and no further than the ends.
    func testTheLeverStandsOnANotchAndADragEndsOnTheNearestOne() {
        typealias Lever = ManualDrive.Lever
        typealias Notch = ManualDrive.Notch
        XCTAssertEqual(Lever.fraction(of: .fullPower), 0)
        XCTAssertEqual(Lever.fraction(of: .emergency), 1)
        XCTAssertEqual(Lever.fraction(of: .neutral), 5.0 / 13, accuracy: 1e-12)
        let step = 1.0 / 13
        XCTAssertEqual(Lever.notch(from: .neutral, dragged: 0), .neutral)
        XCTAssertEqual(Lever.notch(from: .neutral, dragged: step * 0.49), .neutral, "less than half a notch: it stays")
        XCTAssertEqual(Lever.notch(from: .neutral, dragged: step * 0.51), Notch(step: -1))
        XCTAssertEqual(Lever.notch(from: .neutral, dragged: -step * 3), Notch(step: 3), "up is power")
        XCTAssertEqual(Lever.notch(from: Notch(step: 2), dragged: step * 6.2), Notch(step: -4))
        XCTAssertEqual(Lever.notch(from: .neutral, dragged: step * 7), .fullBrake)
        XCTAssertEqual(Lever.notch(from: .neutral, dragged: step * 8), .emergency, "one notch past the last brake")
        XCTAssertEqual(Lever.notch(from: .neutral, dragged: 40), .emergency)
        XCTAssertEqual(Lever.notch(from: .neutral, dragged: -40), .fullPower)
        XCTAssertEqual(Lever.notch(from: Notch(step: -2), dragged: .nan), Notch(step: -2))
        for notch in Notch.all {
            XCTAssertEqual(Lever.notch(from: .fullPower, dragged: Lever.fraction(of: notch)), notch)
        }
    }

    /// Decision 704: each notch is felt; reaching or crossing neutral and
    /// the emergency brake are felt harder; no move, nothing.
    func testNeutralAndTheEmergencyBrakeAreFeltHarderThanAStep() {
        typealias Lever = ManualDrive.Lever
        typealias Notch = ManualDrive.Notch
        XCTAssertNil(Lever.detent(from: .neutral, to: .neutral))
        XCTAssertEqual(Lever.detent(from: Notch(step: 2), to: Notch(step: 3)), .step)
        XCTAssertEqual(Lever.detent(from: Notch(step: -3), to: Notch(step: -6)), .step)
        XCTAssertEqual(Lever.detent(from: .neutral, to: Notch(step: 1)), .step, "leaving neutral is a step")
        XCTAssertEqual(Lever.detent(from: .neutral, to: Notch(step: -1)), .step)
        XCTAssertEqual(Lever.detent(from: Notch(step: 1), to: .neutral), .heavy)
        XCTAssertEqual(Lever.detent(from: Notch(step: -1), to: .neutral), .heavy)
        XCTAssertEqual(Lever.detent(from: Notch(step: 2), to: Notch(step: -2)), .heavy, "a drag across neutral")
        XCTAssertEqual(Lever.detent(from: .fullBrake, to: .emergency), .heavy)
        XCTAssertEqual(Lever.detent(from: .emergency, to: .fullBrake), .step)
    }
}
