import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// STATION-ALIGN-APPLY (decision 1022): the real platforms' ends the app
/// carries (`real_platforms.json`), and how a line's stations are moved
/// along its way onto them (``RealLineAcquisition/alignedStations(_:realEnds:half:length:endReach:gap:)``).
final class RealPlatformEndsTests: XCTestCase {
    private let metre = RealLineAcquisition.metre

    func testTheBundledFileIsRead() throws {
        let ends = try XCTUnwrap(BundledRealData.railways().platformEnds)
        XCTAssertGreaterThan(ends.ends.count, 150)
        // Tainan's TRA platforms (the underground ones, decision 1021) and
        // the High Speed Rail's.
        let tainan = try XCTUnwrap(ends.ends(system: "tra_sched", station: "臺南"))
        XCTAssertLessThan(tainan.first.distance(to: tainan.last), 600)
        XCTAssertGreaterThan(tainan.first.distance(to: tainan.last), 100)
        for value in ends.ends.values {
            XCTAssertLessThan(value.first.distance(to: value.last), 2_000)
        }
    }

    func testKeys() {
        XCTAssertEqual(RealPlatformEnds.key(line: "tra:NEIWAN", station: "合興"), "tra:NEIWAN|合興")
        XCTAssertEqual(RealPlatformEnds.key(system: "tra_sched", station: "臺南"), "tra_sched|臺南")
    }

    /// A station moves to its real platforms' middle; one with none, or
    /// whose real platforms lie too far off, stays.
    func testStationsMoveToTheRealPlatformsMiddle() {
        let at: [(along: Double, away: Double)] = [(300, 0), (2_000, 1), (4_000, 2), (6_000, 0)].map { ($0.0 * metre, $0.1 * metre) }
        let ends: [(Double, Double)?] = [nil, (2_050, 2_150), (4_000 + 400, 4_000 + 500), (5_900, 6_000)].map { pair in
            pair.map { ($0.0 * metre, $0.1 * metre) }
        }
        let placed = RealLineAcquisition.alignedStations(
            at, realEnds: ends, half: 60 * metre, length: 6_300 * metre, endReach: 250 * metre, gap: 500 * metre
        )
        XCTAssertEqual(placed.map { $0.along / metre }, [300, 2_100, 4_000, 5_950])
        XCTAssertEqual(placed.map(\.away), at.map(\.away))
    }

    /// Not past where an end's loops still lie on the way, nor nearer a
    /// neighbour than two platforms and their loops (where it was farther).
    func testEndsAndNeighboursKeepTheirRoom() {
        let at: [(along: Double, away: Double)] = [(260, 0), (900, 0), (1_500, 0)].map { ($0.0 * metre, $0.1 * metre) }
        let ends: [(Double, Double)?] = [(100.0, 200.0), (1_150.0, 1_250.0), (1_600.0, 1_700.0)].map { ($0.0 * metre, $0.1 * metre) }
        let placed = RealLineAcquisition.alignedStations(
            at, realEnds: ends, half: 60 * metre, length: 1_760 * metre, endReach: 250 * metre, gap: 400 * metre
        )
        // The first only to 250 m (its loops' reach); the second not to
        // 1,200 m, 300 m short of the third; the third only to 1,510 m.
        XCTAssertEqual(placed.map { $0.along / metre }, [250, 900, 1_510])
    }

    /// The old version's measures Chien handed over on 2026-11-25
    /// (assets-2 `docs/planning/OLD-3D-COMPAT.md` §3–4), so its station
    /// and depot modules still fit once imported: the platforms moved
    /// along their line onto the real ones keep their height over the rail
    /// (1.08–1.15 m) and their edge from the track's middle (1.55–1.76 m,
    /// never under 1.50 m, where a car would touch it), and a building over
    /// the track leaves 6.50 m (``Map3DTrainRoom/trackAbove``). Aligning moves a station along its line
    /// only, never across (``testStationsMoveToTheRealPlatformsMiddle``).
    func testTheOldVersionsPlatformMeasuresHold() {
        XCTAssertTrue((1.08...1.15).contains(Map3DScene.Builder.platformHeight))
        for edge in [Map3DScene.Builder.platformEdge, Map3DScene.Builder.highSpeedPlatformEdge] {
            XCTAssertTrue((1.55...1.76).contains(edge), "\(edge)")
        }
        XCTAssertGreaterThanOrEqual(Map3DTrainRoom.trackAbove, 6.5)
    }
}
