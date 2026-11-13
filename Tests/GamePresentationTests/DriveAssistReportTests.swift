import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// HEALTH-129 (`docs/research/HEALTH_129_2026-11-13.md`): whether switching
/// the stopping assist of decision 710 on and off gets a run its help
/// without the half pay. A run of 600 m entered at 60 km/h is driven by a
/// few scripted hands, and each is printed: how it ended, its marks for the
/// position and the handling, whether it is told as assisted, and what it
/// is paid of a full run's bonus (the marks for the time taken as full, so
/// only the stop is compared). It runs only on request:
///
///     DRIVE_ASSIST_REPORT=1 swift test --skip-build --filter DriveAssistReportTests
final class DriveAssistReportTests: XCTestCase {
    func testSwitchingTheAssistOnAndOff() throws {
        guard ProcessInfo.processInfo.environment["DRIVE_ASSIST_REPORT"] != nil else {
            throw XCTSkip("set DRIVE_ASSIST_REPORT=1 to print the stopping assist report")
        }
        let train = ManualDrive.Train(.standard)
        /// Each frame, a hand sees the run and may move the handle or the
        /// assist's switch.
        typealias Hand = (inout ManualDrive, Int) -> Void
        /// The brake step `step` put on where it stops the train on the
        /// point, by the handle alone (with `early` metres to spare).
        func brakes(step: Int, early: Double = 0) -> Hand {
            { drive, _ in
                let rate = train.braking * Double(step) / Double(ManualDrive.timetableBrakeStep)
                let lag = rate / ManualDrive.jerk / 2
                if drive.remaining <= drive.speed * drive.speed / (2 * rate) + drive.speed * lag + early { drive.set(ManualDrive.Notch(step: -step)) }
            }
        }
        let hands: [(name: String, assists: Bool, hand: Hand)] = [
            ("Assist off, the handle left in neutral", false, { _, _ in }),
            ("Assist off, brake step 5 where it stops on the point", false, brakes(step: 5)),
            ("Assist off, brake step 3 where it stops on the point", false, brakes(step: 3)),
            ("Assist on, the handle left in neutral", true, { _, _ in }),
            ("Assist on, brake step 5 where it stops on the point", true, brakes(step: 5)),
            ("Assist on, brake step 2 where it stops on the point (lighter than the assist takes)", true, brakes(step: 2)),
            ("Assist on, switched off the frame after it takes the brake, then brake step 5", true, { drive, _ in
                if drive.isAssisting {
                    drive.setAssist(false)
                    drive.set(ManualDrive.Notch(step: -5))
                }
            }),
            ("Assist on, switched off under 1 m/s, then brake step 1", true, { drive, _ in
                if drive.assisted, drive.speed < 1 {
                    drive.setAssist(false)
                    drive.set(ManualDrive.Notch(step: -1))
                }
            }),
            ("Assist off until 30 m from the point at brake step 3, then on", false, { drive, frame in
                brakes(step: 3)(&drive, frame)
                if drive.remaining <= 30 { drive.setAssist(true) }
            }),
            ("Assist switched on and off every other frame, neutral", true, { drive, frame in drive.setAssist(frame % 2 == 0) }),
        ]
        var rows = ["| Hand | Ended | Off the point (m) | Position / handling marks | Told as assisted | Paid, of a full run's bonus |", "| --- | --- | --: | --: | --- | --: |"]
        let full = DrivenRun.bonus(marks: 100, riders: 500).amount
        for (name, assists, hand) in hands {
            var drive = ManualDrive(train: train, course: .init(stop: 600, scheduled: 600), speed: 60 / 3.6, assists: assists)
            var frame = 0
            while !drive.isOver, frame < 60 * 600 {
                hand(&drive, frame)
                drive.advance(seconds: 1.0 / 60)
                frame += 1
            }
            let result = try XCTUnwrap(drive.result, name)
            let marks = result.run(of: TrainID(rawValue: 1)).marks
            let total = result.outcome == .stopped ? marks.position + DrivenRun.timeMarks + marks.handling : 0
            let paid = DrivenRun.bonus(marks: total, riders: 500, assisted: result.assisted).amount
            rows.append("| \(name) | \(result.outcome) | \(String(format: "%+.2f", result.offset)) | \(marks.position) / \(marks.handling) | "
                + "\(result.assisted ? "yes" : "no") | \(paid * 100 / full)% |")
        }
        print("### Switching the stopping assist on and off (600 m entered at 60 km/h; the assist is \(ManualDrive.StopAssist.isOnByDefault ? "on" : "off") by default)\n\n"
            + rows.joined(separator: "\n"))
    }
}
