@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 710: stopping a train driven by hand: the bar over the last
/// 200 m, the mark at the stopping point, and the look from beside.
final class ManualDriveStopTests: XCTestCase {
    private typealias Bar = ManualDrive.StopBar
    private let train = ManualDrive.Train(.standard)

    private func bar(_ metres: Double, phase: ManualDrive.Reading.Phase = .driving) -> Bar? {
        Bar(phase: phase, remainingTenths: Int((metres * 10).rounded()))
    }

    func testTheBarShowsOverTheLastTwoHundredMetresOfARunBeingDriven() {
        XCTAssertNil(bar(200.1), "not yet")
        XCTAssertNotNil(bar(200))
        XCTAssertNotNil(bar(0))
        XCTAssertNotNil(bar(-30), "past the point, until the run is given up")
        XCTAssertNil(bar(50, phase: .waiting), "not before the train has left")
        XCTAssertNil(bar(0.2, phase: .over), "gone once the train stands or has run past")
        XCTAssertNil(Bar(phase: .driving, remainingTenths: nil))
        XCTAssertNil(ManualDrive.Reading.waiting.stopBar)
    }

    func testTheRunsReadingCarriesTheBarAndLosesItWhenTheTrainStands() {
        var drive = ManualDrive(train: train, course: .init(stop: 1_000, scheduled: 120), speed: 5, distance: 700)
        XCTAssertNil(drive.reading.stopBar, "300 m to go")
        drive = ManualDrive(train: train, course: .init(stop: 1_000, scheduled: 120), speed: 0.3, distance: 999.2)
        XCTAssertEqual(drive.reading.stopBar?.state, .short)
        XCTAssertEqual(drive.reading.stopBar?.remainingTenths, 8)
        drive.set(ManualDrive.Notch(step: -ManualDrive.timetableBrakeStep))
        drive.advance(seconds: 5)
        XCTAssertEqual(drive.result?.outcome, .stopped)
        XCTAssertNil(drive.reading.stopBar, "the result card takes over")
    }

    func testShortOnTargetAndPastMeetAtHalfAMetreEitherSide() {
        XCTAssertEqual(bar(0.6)?.state, .short)
        XCTAssertEqual(bar(0.5)?.state, .onTarget, "half a metre short still earns the position's full marks")
        XCTAssertEqual(bar(0)?.state, .onTarget)
        XCTAssertEqual(bar(-0.5)?.state, .onTarget)
        XCTAssertEqual(bar(-0.6)?.state, .past)
        // The same half metre the marks are given by.
        XCTAssertEqual(DrivenRun.marks(outcome: .stopped, offset: -DrivenRun.exactOffset, lateness: 0, overspeed: 0, usedEmergency: false).position,
                       DrivenRun.positionMarks)
        XCTAssertEqual(ManualDrive.exactMetres * Double(WorldCoordinate.unitsPerMetre), Double(DrivenRun.exactOffset))
    }

    func testTheMarkerRunsAlongTheBarAndIsOverTheTargetOnlyWhenOnIt() throws {
        XCTAssertEqual(Bar.share(short: 200), 0)
        XCTAssertEqual(Bar.share(short: 500), 0, "held on the bar")
        XCTAssertEqual(Bar.share(short: -12.5), 1)
        XCTAssertEqual(Bar.share(short: -40), 1)
        XCTAssertEqual(Bar.share(short: .nan), 0)
        XCTAssertEqual(Bar.share(short: 125), 0.09, accuracy: 1e-9, "straight between 200 m and 50 m")
        XCTAssertEqual(Bar.share(short: 0), 0.67, accuracy: 1e-9, "the point is the target's middle")
        XCTAssertEqual(Bar.target.lowerBound, 0.62, accuracy: 1e-9)
        XCTAssertEqual(Bar.target.upperBound, 0.72, accuracy: 1e-9)
        // Never backwards as the train goes on, and inside the target
        // exactly when the state says so.
        var last = -1.0
        for tenths in stride(from: 2_000, through: -300, by: -1) {
            let bar = try XCTUnwrap(Bar(phase: .driving, remainingTenths: tenths))
            XCTAssertGreaterThanOrEqual(bar.marker, last)
            XCTAssertTrue((0...1).contains(bar.marker))
            XCTAssertEqual(Bar.target.contains(bar.marker), bar.state == .onTarget, "\(tenths)")
            last = bar.marker
        }
        // The last ten metres take more of the bar than the first 150.
        XCTAssertGreaterThan(Bar.share(short: 0) - Bar.share(short: 10), Bar.share(short: 50) - Bar.share(short: 200))
    }

    func testTheBarsWordsSayOnlyWhereTheTrainIs() throws {
        let zh = DisplayLanguage.traditionalChinese, en = DisplayLanguage.english
        XCTAssertEqual(try XCTUnwrap(bar(38)).text(in: zh), "40 m", "the same figure as the strip above: tens of metres until the last ten")
        XCTAssertEqual(try XCTUnwrap(bar(4.2)).text(in: en), "4.2 m")
        XCTAssertEqual(try XCTUnwrap(bar(0.2)).text(in: zh), "在目標上")
        XCTAssertEqual(try XCTUnwrap(bar(0.2)).text(in: en), "On the mark")
        XCTAssertEqual(try XCTUnwrap(bar(-1.3)).text(in: zh), "超過 1.3 m")
        XCTAssertEqual(try XCTUnwrap(bar(-1.3)).text(in: en), "1.3 m past")
        XCTAssertEqual([Bar.State.short, .onTarget, .past].map { Bar.text(of: $0, in: zh) }, ["未到位", "停車目標", "越位"])
        XCTAssertEqual([Bar.State.short, .onTarget, .past].map { Bar.text(of: $0, in: en) }, ["Short", "Stop here", "Past"])
        // VoiceOver.
        XCTAssertEqual(Bar.title(in: zh), "停車位置")
        XCTAssertEqual(try XCTUnwrap(bar(38)).value(in: zh), "未到位，還差 40 m")
        XCTAssertEqual(try XCTUnwrap(bar(38)).value(in: en), "Short, 40 m to go")
        XCTAssertEqual(try XCTUnwrap(bar(0)).value(in: zh), "在停車目標上")
        XCTAssertEqual(try XCTUnwrap(bar(-1.3)).value(in: zh), "越位，超過停車目標 1.3 m")
        XCTAssertEqual(try XCTUnwrap(bar(-1.3)).value(in: en), "Past, 1.3 m past the stopping point")
    }

    func testComingOntoTheTargetAndRunningPastItAreFelt() {
        XCTAssertEqual(Bar.feel(from: .short, to: .onTarget), .onTarget)
        XCTAssertEqual(Bar.feel(from: .onTarget, to: .past), .past)
        XCTAssertEqual(Bar.feel(from: .short, to: .past), .past, "a frame may skip the half metre")
        XCTAssertNil(Bar.feel(from: nil, to: .short), "the bar showing is not felt")
        XCTAssertNil(Bar.feel(from: nil, to: .onTarget), "nor a bar that first shows on the target")
        XCTAssertNil(Bar.feel(from: .short, to: .short))
        XCTAssertNil(Bar.feel(from: .onTarget, to: nil), "the stop itself is the result's to say")
    }

    func testAStoppedRunIsLookedAtFromBesideUnlessMotionIsReduced() {
        func result(_ outcome: ManualDrive.Outcome) -> ManualDrive.Result {
            ManualDrive.Result(outcome: outcome, offset: -0.4, lateness: 3, overspeedSeconds: 0, usedEmergency: false)
        }
        typealias Look = ManualDrive.StopLook
        XCTAssertEqual(Look.view(chosen: .cab, result: result(.stopped), looking: true, reduceMotion: false), .side)
        XCTAssertEqual(Look.view(chosen: .cab, result: result(.stopped), looking: false, reduceMotion: false), .cab, "and back after a while")
        XCTAssertEqual(Look.view(chosen: .cab, result: result(.stopped), looking: true, reduceMotion: true), .cab, "the camera stays put")
        XCTAssertEqual(Look.view(chosen: .back, result: result(.passed), looking: true, reduceMotion: false), .back, "nothing at a platform to look at")
        XCTAssertEqual(Look.view(chosen: .back, result: result(.timedOut), looking: true, reduceMotion: false), .back)
        XCTAssertEqual(Look.view(chosen: .aboveBack, result: nil, looking: true, reduceMotion: false), .aboveBack, "not while driving")
        XCTAssertTrue((5...12).contains(Look.seconds), "long enough to read the card, not a wait")
        XCTAssertEqual(Look.backText(chosen: .cab, looking: true, in: .traditionalChinese), "回駕駛室")
        XCTAssertEqual(Look.backText(chosen: .cab, looking: true, in: .english), "Back to the cab")
        XCTAssertEqual(Look.backText(chosen: .cab, looking: false, in: .traditionalChinese), "好", "already back in the cab")
        XCTAssertEqual(Look.backText(chosen: .cab, looking: false, in: .english), "OK")
        for looking in [true, false] {
            XCTAssertEqual(Look.backText(chosen: .back, looking: looking, in: .traditionalChinese), ManualDrive.doneText(in: .traditionalChinese))
        }
    }

    func testTheMarkIsAPostLeftOfTheTrackAndABarBetweenTheRails() {
        typealias Mark = ManualDrive.StopMark
        var mesh = Map3DMesh()
        // The train comes along +x: its left is −z (north on the map).
        let rail = Map3DPoint(100, 7, 50)
        Mark.add(to: &mesh, at: rail, forward: Map3DPoint(3, 0, 0))
        XCTAssertFalse(mesh.vertices.isEmpty)
        let xs = mesh.vertices.map(\.position.x), ys = mesh.vertices.map(\.position.y), zs = mesh.vertices.map(\.position.z)
        XCTAssertEqual(try XCTUnwrap(ys.max()), rail.y + Mark.postHeight, accuracy: 1e-3)
        XCTAssertEqual(try XCTUnwrap(ys.min()), rail.y - Mark.barUnderRail - Mark.barHeight, accuracy: 1e-3)
        XCTAssertEqual(try XCTUnwrap(zs.min()), rail.z - Mark.postAcross - Mark.boardSide / 2, accuracy: 1e-3, "the board, left of the track")
        XCTAssertEqual(try XCTUnwrap(zs.max()), rail.z + Mark.barWidth / 2, accuracy: 1e-3, "nothing right of the rails")
        XCTAssertLessThan(Mark.barWidth / 2, 0.5335, "the bar lies inside the 1,067 mm gauge")
        XCTAssertGreaterThan(Mark.postAcross - Mark.boardSide / 2, Map3DTrains.carWidth / 2, "the board is clear of the car's side")
        XCTAssertEqual(try XCTUnwrap(xs.max()) - (try XCTUnwrap(xs.min())), Mark.barLength, accuracy: 1e-3)
        // Nothing above the rails between them: the train runs over the bar.
        for vertex in mesh.vertices where abs(vertex.position.z - rail.z) < Map3DTrains.carWidth / 2 {
            XCTAssertLessThan(vertex.position.y, rail.y)
        }
        // The board and the bar are lit at night; the post is not.
        XCTAssertTrue(mesh.vertices.contains { $0.layer == Map3DVertex.glowing })
        XCTAssertTrue(mesh.vertices.contains { $0.layer != Map3DVertex.glowing })
        var none = Map3DMesh()
        Mark.add(to: &none, at: rail, forward: Map3DPoint(0, 1, 0))
        XCTAssertTrue(none.vertices.isEmpty, "no way on the plan, no mark")
    }
}
