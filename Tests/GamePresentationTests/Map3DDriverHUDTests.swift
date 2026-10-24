@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 403: the 3D map's driving display while it follows a train.
final class Map3DDriverHUDTests: XCTestCase {
    func testDistancesAreMetresUnderAKilometreAndTenthsOfAKilometreAbove() {
        XCTAssertEqual(Map3DDriverHUD.distanceText(643), "640 m")
        XCTAssertEqual(Map3DDriverHUD.distanceText(0), "0 m")
        XCTAssertEqual(Map3DDriverHUD.distanceText(3_849), "3.8 km")
        XCTAssertEqual(Map3DDriverHUD.distanceText(1_000), "1.0 km")
    }

    func testLatenessIsInSecondsUnderAMinuteAndMinutesAbove() {
        XCTAssertEqual(Map3DDriverHUD.latenessText(0, in: .traditionalChinese), "準點")
        XCTAssertEqual(Map3DDriverHUD.latenessText(8, in: .traditionalChinese), "晚 8 秒")
        XCTAssertEqual(Map3DDriverHUD.latenessText(185, in: .traditionalChinese), "晚 3 分")
        XCTAssertEqual(Map3DDriverHUD.latenessText(-12, in: .traditionalChinese), "早 12 秒")
        XCTAssertEqual(Map3DDriverHUD.latenessText(8, in: .english), "8 s late")
        XCTAssertEqual(Map3DDriverHUD.latenessText(-120, in: .english), "2 min early")
    }

    func testThePromptsSayTheStopAndThenThePunctuality() {
        func hud(_ prompt: Map3DDriverHUD.Prompt?) -> Map3DDriverHUD {
            Map3DDriverHUD(line: nil, lineName: "Main", service: "Main", origin: "A", terminus: "B", place: .next("B"),
                           metresToNext: 640, lateness: 8, speed: 60, limitHere: 75, limitAhead: .init(speed: 60, metres: 1_500), prompt: prompt)
        }
        XCTAssertEqual(hud(.approaching(station: "B", metres: 640)).promptText(in: .traditionalChinese), "下一站 B，剩 640 m")
        XCTAssertEqual(hud(.arrived(lateness: 40)).promptText(in: .traditionalChinese), "準點", "under a minute is on time")
        XCTAssertEqual(hud(.arrived(lateness: 200)).promptText(in: .english), "3 min late")
        XCTAssertNil(hud(nil).promptText(in: .english))
        XCTAssertEqual(hud(nil).routeText, "A → B", "the service is the line's own name")
        XCTAssertEqual(hud(nil).speedLabel(in: .traditionalChinese), "60 km/h，限速 75 km/h，1.5 km 後限 60 km/h")
        XCTAssertEqual(hud(nil).placeLabel(in: .traditionalChinese), "下一站")
    }

    /// Station A, 1 km east, a 300 m quarter circle (75 km/h), 1 km north,
    /// station B; one standard train on the line A–B (as
    /// `CurveSpeedTextTests`).
    private func world(limits: Bool) throws -> (GameWorld, TrainID) {
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
        _ = try world.buildTrackEdge(from: nodes[2], to: nodes[3], curve: .cubic(
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
        return (world, train)
    }

    /// From A to B: the curve named ahead with its distance, then kept to,
    /// the stop's distance counting down, the approach prompt inside the
    /// last kilometre, and the arrival's punctuality once it stands at B.
    func testAFollowedTrainShowsTheLimitsTheStopAndItsArrival() throws {
        var (world, train) = try world(limits: true)
        // Six seconds a tick, so the half minute after it arrives is seen.
        world.setSpeed(.x60)
        var sawAhead = false, sawHere = false, sawApproach = false, sawArrival = false
        var lastDistance: Int64?
        for _ in 0..<1_000 {
            try world.advance(ticks: 1)
            let hud = try XCTUnwrap(world.map3DDriverHUD(of: train, in: .traditionalChinese))
            XCTAssertEqual(hud.lineName, "Main")
            if let ahead = hud.limitAhead {
                XCTAssertEqual(ahead.speed, 75)
                XCTAssertLessThanOrEqual(ahead.metres, Map3DDriverHUD.limitLookaheadMetres)
                sawAhead = true
            }
            if hud.limitHere == 75 { sawHere = true }
            if hud.place == .next("B"), let distance = hud.metresToNext {
                if let lastDistance { XCTAssertLessThanOrEqual(distance, lastDistance) }
                lastDistance = distance
                XCTAssertEqual(hud.lateness.map { $0 >= 0 }, true)
            }
            if case .approaching(let station, let metres)? = hud.prompt {
                XCTAssertEqual(station, "B")
                XCTAssertLessThanOrEqual(metres, Map3DDriverHUD.approachMetres)
                sawApproach = true
            }
            if case .arrived? = hud.prompt {
                XCTAssertEqual(hud.place, .at("B"))
                XCTAssertNotNil(hud.promptText(in: .traditionalChinese))
                sawArrival = true
                break
            }
        }
        XCTAssertTrue(sawAhead, "the curve is named ahead")
        XCTAssertTrue(sawHere, "and then kept to")
        XCTAssertTrue(sawApproach, "the approach prompt shows inside the last kilometre")
        XCTAssertTrue(sawArrival, "the arrival's punctuality shows at B")
    }

    func testWithTheLimitsOffNoLimitIsShown() throws {
        var (world, train) = try world(limits: false)
        for _ in 0..<600 {
            try world.advance(ticks: 1)
            let hud = try XCTUnwrap(world.map3DDriverHUD(of: train, in: .english))
            XCTAssertNil(hud.limitHere)
            XCTAssertNil(hud.limitAhead)
        }
    }

    func testAnUnknownTrainHasNoDisplay() throws {
        let (world, _) = try world(limits: true)
        XCTAssertNil(world.map3DDriverHUD(of: TrainID(rawValue: 99), in: .english))
    }
}
