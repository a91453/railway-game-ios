@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 217: the loupe's speed beside the radius, and the train's
/// curve limit in the follow bar and the train card.
final class CurveSpeedTextTests: XCTestCase {
    func testTheLoupeSaysHowFastARadiusMayBeRun() {
        let metre = Double(WorldCoordinate.unitsPerMetre)
        XCTAssertEqual(TrackCurvature.speedText(300 * metre, in: .traditionalChinese), "可跑 75 km/h")
        XCTAssertEqual(TrackCurvature.speedText(1_000 * metre, in: .english), "up to 135 km/h")
        XCTAssertNil(TrackCurvature.speedText(nil, in: .english), "straight")
        XCTAssertNil(TrackCurvature.speedText(9_000 * metre, in: .english), "no train runs faster")
    }

    func testTheReadingSaysWhetherTheCurveIsHereOrAhead() {
        XCTAssertEqual(CurveLimitReading(speed: 60, ahead: false).text(in: .traditionalChinese), "彎道限速 60 km/h")
        XCTAssertEqual(CurveLimitReading(speed: 60, ahead: true).text(in: .traditionalChinese), "前方彎道 60 km/h")
        XCTAssertEqual(CurveLimitReading(speed: 60, ahead: false).text(in: .english), "Curve limit 60 km/h")
    }

    /// Station A, 1 km east, a 300 m quarter circle (75 km/h), 1 km north,
    /// station B; one standard train on the line A–B.
    private func world(limits: Bool) throws -> (GameWorld, TrainID, TrackEdgeID) {
        var world = try GameWorld(
            bounds: WorldBounds(width: 262_144, height: 262_144),
            economy: GameEconomy(balance: 1_000_000_000, costs: ConstructionCosts(track: 100, station: 1_000, train: 500))
        )
        let r: Int64 = 300 * 64, k = r * 5523 / 10_000, x: Int64 = 8_192, y: Int64 = 8_192
        let points = [
            WorldCoordinate(x: x, y: y), WorldCoordinate(x: x + 4_096, y: y), WorldCoordinate(x: x + 68_096, y: y),
            WorldCoordinate(x: x + 68_096 + r, y: y + r), WorldCoordinate(x: x + 68_096 + r, y: y + r + 64_000),
            WorldCoordinate(x: x + 68_096 + r, y: y + r + 68_096),
        ]
        let nodes = try points.map { try world.buildTrackNode(at: $0) }
        let first = try world.buildTrackEdge(from: nodes[0], to: nodes[1])
        _ = try world.buildTrackEdge(from: nodes[1], to: nodes[2])
        let bend = try world.buildTrackEdge(from: nodes[2], to: nodes[3], curve: .cubic(
            PlanPoint(x: points[2].x + k, y: points[2].y), PlanPoint(x: points[3].x, y: points[3].y - k)))
        _ = try world.buildTrackEdge(from: nodes[3], to: nodes[4])
        let last = try world.buildTrackEdge(from: nodes[4], to: nodes[5])
        let a = try world.buildStation(named: "A", at: PlanPoint(x: x + 2_048, y: y + 512)).id
        try world.addTrackPlatform(a, on: first, from: 0, to: 4_096)
        let b = try world.buildStation(named: "B", at: PlanPoint(x: points[4].x + 512, y: points[4].y + 2_048)).id
        try world.addTrackPlatform(b, on: last, from: 0, to: 4_096)
        try world.createLine(named: "Main", stops: [a, b])
        let line = LineID(rawValue: 1)
        try world.setLineServiceWindow(line, to: .allDay)
        try world.setLineTrainsInService(line, to: TrainsInService(peak: 1, offPeak: 1, low: 1))
        world.setRealisticOperation(true)
        world.setCurveSpeedLimits(limits)
        let train = try world.purchaseTrain(named: "Blue").id
        try world.placeTrain(train, at: .onEdge(TrackTraversal(edge: first, direction: .forward), offset: 4_096))
        try world.setTrainMovementRate(train, to: 1024)
        try world.assignTrain(train, to: line)
        world.setSpeed(.normal)
        return (world, train, bend)
    }

    func testAFollowedTrainNamesTheCurveAheadAndThenTheLimitItKeepsTo() throws {
        var (world, train, bend) = try world(limits: true)
        var readings: [CurveLimitReading] = []
        for _ in 0..<600 {
            try world.advance(ticks: 1)
            if let reading = world.curveLimit(of: train), reading != readings.last { readings.append(reading) }
            if case .onEdge(let traversal, _)? = world.train(id: train)?.position, traversal.edge == bend {
                XCTAssertEqual(world.curveLimit(of: train), CurveLimitReading(speed: 75, ahead: false))
            }
        }
        XCTAssertTrue(readings.contains(CurveLimitReading(speed: 75, ahead: true)))
        XCTAssertTrue(readings.contains(CurveLimitReading(speed: 75, ahead: false)))
    }

    func testWithTheLimitsOffThereIsNoReading() throws {
        var (world, train, _) = try world(limits: false)
        for _ in 0..<300 {
            try world.advance(ticks: 1)
            XCTAssertNil(world.curveLimit(of: train))
        }
    }
}
