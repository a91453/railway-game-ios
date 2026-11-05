import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 585 PR-4 (FERRYFOLLOW): the 3D map following a ferry boat: the
/// boats numbered in turn, the pose moving on without a jump (sailing,
/// lying at a pier, moving to and from its place beside the first pier),
/// the double-ended ferry's bridge facing the way it sails, the followed
/// boat always drawn whole, the four views, and the session's follow bar.
final class FerryFollowTests: XCTestCase {
    static var pack: Map3DModelPack { Map3DModelPack.standard }

    /// A day's departures go to the boats in turn; the stages are the
    /// ones ``Map3DFerries/sailings(of:atSecond:open:)`` gives.
    func testTheBoatsSailInTurn() throws {
        let (world, id) = try makeFerryWorld(from: CellPosition(row: 3, column: 10), to: CellPosition(row: 6, column: 30), boats: 2)
        let route = try XCTUnwrap(world.ferryRoute(id: id))
        let at = Double(7 * 3_600 + 16 * 60)
        let numbered = Map3DFerries.numberedSailings(of: route, atSecond: at) { _ in true }
        XCTAssertEqual(numbered.map(\.stage), Map3DFerries.sailings(of: route, atSecond: at) { _ in true })
        // 07:00 went to boat 0, 07:15 to boat 1.
        XCTAssertEqual(numbered.map(\.number), [0, 1])
        XCTAssertEqual(numbered.map(\.start), [7 * 3_600, 7 * 3_600 + 15 * 60])
        // Boat 0 is back by 07:30 (two crossings and two stops, under 17
        // minutes) and lies until its next sailing, 07:30.
        let lying = Map3DFerries.lying(0, of: route, atSecond: Double(7 * 3_600 + 29 * 60)) { _ in true }
        XCTAssertNotNil(lying.since)
        XCTAssertEqual(lying.until, Double(7 * 3_600 + 30 * 60))
        XCTAssertEqual(Map3DFerries.lying(1, of: route, atSecond: 0) { _ in true }.until, Double(7 * 3_600 + 15 * 60))
        XCTAssertNil(Map3DFerries.lying(1, of: route, atSecond: 0) { _ in false }.until)
    }

    /// Step by step through a morning, the followed boat moves on with no
    /// jump: off the berth, across, round at the far pier, back, to its
    /// place beside the first pier and back to the berth for its next
    /// sailing. The passenger boat turns smoothly too.
    func testTheFollowedBoatMovesOnWithoutAJump() throws {
        for (to, kind) in [(CellPosition(row: 6, column: 30), Map3DFerry.Boat.tamsui), (CellPosition(row: 6, column: 12), .cijin)] {
            let (world, _) = try makeFerryWorld(from: CellPosition(row: 3, column: 10), to: to, boats: 3)
            let laid = Map3DFerries(world: world, scene: Map3DScene(world: world))
            let line = try XCTUnwrap(laid.lines.first)
            XCTAssertEqual(line.boat, kind)
            for number in 0..<3 {
                let id = FerryBoatID(route: line.id, number: number)
                var last: Map3DFollow.Pose?
                var second = Double(6 * 3_600 + 55 * 60)
                var moved = false
                while second < Double(8 * 3_600 + 30 * 60) {
                    let pose = try XCTUnwrap(laid.pose(of: id, second: second), "boat \(number) at \(second)")
                    if let last {
                        let step = (pose.rail - last.rail).length
                        XCTAssertLessThan(step, 12, "\(kind) boat \(number) jumped \(step) m at \(second)")
                        if step > 0.01 { moved = true }
                        if kind == .tamsui {
                            XCTAssertGreaterThan(pose.forward.dot(last.forward), cosf(0.25), "\(kind) boat \(number) turned at once at \(second)")
                        }
                    }
                    last = pose
                    second += 2
                }
                XCTAssertTrue(moved)
            }
        }
    }

    /// The double-ended ferry sails back stern first, and the bridge view
    /// faces the way it sails: back the other way, turning round half way
    /// through its time at the far pier.
    func testTheDoubleEndedFerrysBridgeFacesTheWayItSails() throws {
        let (world, _) = try makeFerryWorld(from: CellPosition(row: 3, column: 10), to: CellPosition(row: 6, column: 12), boats: 1)
        let laid = Map3DFerries(world: world, scene: Map3DScene(world: world))
        let line = try XCTUnwrap(laid.lines.first)
        XCTAssertEqual(line.boat, .cijin)
        let way = Map3DFerries.way(line, leg: 0)
        func travel(_ stage: Map3DFerries.Stage) -> Map3DPoint {
            let at = Map3DFerries.place(stage, on: line)
            let laid = Map3DFerries.Laid(number: 0, point: at.point, forward: at.forward,
                                         sailing: Map3DFerries.Sailing(number: 0, start: 0, stage: stage))
            return Map3DFerries.travel(laid, on: line)
        }
        func near(_ a: Map3DPoint, _ b: Map3DPoint) -> Bool { (a - b).length < 1e-3 }
        XCTAssertTrue(near(travel(.sailing(leg: 0, share: 0.5, outbound: true)), way))
        XCTAssertTrue(near(travel(.docked(pier: 1, share: 0.2, outbound: true)), way))
        XCTAssertTrue(near(travel(.docked(pier: 1, share: 0.8, outbound: true)), -way))
        XCTAssertTrue(near(travel(.sailing(leg: 0, share: 0.5, outbound: false)), -way))
        XCTAssertTrue(near(travel(.docked(pier: 0, share: 0.8, outbound: false)), way))
    }

    /// The followed boat is drawn whole from any distance, once, and the
    /// boats drawn are as many as without following it.
    func testTheFollowedBoatIsAlwaysDrawnWhole() throws {
        let (world, _) = try makeFerryWorld(from: CellPosition(row: 3, column: 10), to: CellPosition(row: 6, column: 30), boats: 3)
        let laid = Map3DFerries(world: world, scene: Map3DScene(world: world))
        let line = try XCTUnwrap(laid.lines.first)
        let models = try XCTUnwrap(Map3DFerries.Models(Self.pack))
        let pier = line.piers[0].origin
        let eye = pier + Map3DPoint(0, 600, -1_000)
        for second in [Double(6 * 3_600), Double(7 * 3_600 + 5 * 60)] {
            let plain = laid.frame(second: second, eye: eye, target: pier, pack: Self.pack)
            XCTAssertEqual(plain.nearBoats, 0)
            let followed = laid.frame(second: second, eye: eye, target: pier, pack: Self.pack,
                                      following: FerryBoatID(route: line.id, number: 1))
            XCTAssertEqual(followed.nearBoats, 1)
            XCTAssertEqual(followed.nearBoats + followed.farBoats, plain.nearBoats + plain.farBoats)
            XCTAssertEqual(followed.instances.filter { $0.model == models.boat[.tamsui]!.near }.count, 1)
        }
        // Lying, the followed boat takes the first place beside the pier.
        let pose = try XCTUnwrap(laid.pose(of: FerryBoatID(route: line.id, number: 2), second: 6 * 3_600))
        XCTAssertLessThan((pose.rail - Map3DFerries.idle(1, on: line).point).length, 0.01)
        XCTAssertNil(laid.pose(of: FerryBoatID(route: line.id, number: 3), second: 6 * 3_600))
    }

    /// A boat is followed from its bridge, its cabin's window, above and
    /// beside it; the bridge's eye stands at the wheelhouse's front window,
    /// the window's out to the left of the way it sails.
    func testABoatIsFollowedFromItsFourViews() throws {
        let id = FerryBoatID(route: FerryRouteID(rawValue: 1), number: 0)
        XCTAssertEqual(Map3DFollow.ferryViews, [.cab, .window, .aboveBack, .side])
        XCTAssertEqual(Map3DFollow(ferry: id, view: .back).view, .aboveBack)
        XCTAssertEqual(Map3DFollow(ferry: id, view: .station).view, .aboveBack)
        XCTAssertEqual(Map3DFollow(ferry: id, view: .cab).view, .cab)
        XCTAssertEqual(Map3DFollow(ferry: id).ferry, id)
        XCTAssertNil(Map3DFollow(ferry: id).cabin)
        XCTAssertEqual(Map3DFollow.View.cab.ferryText(in: .traditionalChinese), "駕駛台")
        XCTAssertEqual(Map3DFollow.View.window.ferryText(in: .traditionalChinese), "船艙窗")
        XCTAssertEqual(Map3DFollow.View.cab.ferryText(in: .english), "Bridge")
        XCTAssertEqual(Map3DFollow.View.aboveBack.ferryText(in: .traditionalChinese), "上後方")

        let (world, _) = try makeFerryWorld(from: CellPosition(row: 3, column: 10), to: CellPosition(row: 6, column: 30), boats: 1)
        let laid = Map3DFerries(world: world, scene: Map3DScene(world: world))
        let line = try XCTUnwrap(laid.lines.first)
        let boat = FerryBoatID(route: line.id, number: 0)
        let pose = try XCTUnwrap(laid.pose(of: boat, second: Double(7 * 3_600 + 3 * 60)))
        let start = Map3DCamera(target: pose.rail, distance: 200, viewport: (844, 390))
        let cab = Map3DFollow(ferry: boat, view: .cab).camera(following: pose, from: start, elapsed: 0, turnsAtOnce: true)
        let bridge = cab.eye - pose.rail
        XCTAssertEqual(bridge.y, Map3DFerry.Boat.tamsui.bridgeEye, accuracy: 0.05)
        XCTAssertEqual(bridge.dot(pose.forward), Map3DFerry.Boat.tamsui.bridgeFront + Map3DFollow.cabLead, accuracy: 0.05)
        XCTAssertEqual(cab.pitch ?? 0, .pi / 2 - Map3DFerries.bridgeLookDown, accuracy: 0.001)
        let window = Map3DFollow(ferry: boat, view: .window).camera(following: pose, from: start, elapsed: 0, turnsAtOnce: true)
        let seat = window.eye - pose.rail
        let left = Map3DPoint(pose.forward.z, 0, -pose.forward.x)
        XCTAssertEqual(seat.dot(left), Map3DFerry.Boat.tamsui.seatAcross, accuracy: 0.05)
        XCTAssertEqual(seat.y, Map3DFerry.Boat.tamsui.seatHeight, accuracy: 0.05)
        XCTAssertGreaterThan(window.forward.dot(left), 0.9)
    }

    /// Before the first sailing the bar says where the boat lies and when
    /// it leaves; boat 1 takes the second departure.
    func testTheBarSaysWhenALyingBoatLeaves() throws {
        let (world, id) = try makeFerryWorld(from: CellPosition(row: 3, column: 10), to: CellPosition(row: 6, column: 30), boats: 2)
        let first = try XCTUnwrap(world.ferryFollowFacts(of: FerryBoatID(route: id, number: 0), in: .traditionalChinese))
        XCTAssertEqual(first.name, "渡輪 \(id.rawValue)")
        XCTAssertEqual(first.directionText, "往第 2 碼頭")
        XCTAssertEqual(first.stopText, "停在第 1 碼頭 · 下一班 07:00 開")
        let second = try XCTUnwrap(world.ferryFollowFacts(of: FerryBoatID(route: id, number: 1), in: .english))
        XCTAssertEqual(second.stopText, "At Pier 1 · Next sailing 07:15")
        XCTAssertNil(world.ferryFollowFacts(of: FerryBoatID(route: id, number: 2), in: .english))
        XCTAssertEqual(world.ferryBoatToFollow(on: id), FerryBoatID(route: id, number: 0))
    }

    /// The card's follow button follows a boat of the Tamsui–Bali ferry
    /// scene (10:00 of its second day); the bar names the real piers;
    /// following a train lets it go, and so does closing the 3D map.
    @MainActor
    func testTheSessionFollowsABoatAndShowsItsBar() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let water = try WaterGrid(data: Data(contentsOf: root.appendingPathComponent("RailwayGameApp/Resources/RealWorld/taiwan_water.json")))
        let session = GameSession(world: ScreenshotScene.tamsuiFerry.make(in: .traditionalChinese, water: water), language: .traditionalChinese)
        let route = try XCTUnwrap(session.world.ferryRoutes.first)
        XCTAssertNotNil(RealFerry.matching(route, in: session.world))
        XCTAssertTrue(session.hasFerryBoatToFollow(on: route.id))
        session.setMap3DOpen(true)
        session.followFerry(on: route.id)
        let id = try XCTUnwrap(session.followedFerryBoatID)
        XCTAssertTrue(session.isFollowingVehicle)
        XCTAssertTrue(session.isFollowingFerry)
        let bar = try XCTUnwrap(session.ferryFollowBar)
        XCTAssertEqual(bar.name, "渡輪 \(route.id.rawValue)")
        XCTAssertTrue(["往淡水碼頭", "往八里碼頭"].contains(bar.directionText), bar.directionText)
        XCTAssertTrue(bar.stopText.contains("碼頭"), bar.stopText)
        // The screenshots' boat is out on the crossing when one is.
        let middle = try XCTUnwrap(session.world.ferryBoatMidCrossing(on: route.id))
        if let sailing = session.world.ferrySailings(of: route).first(where: { $0.number == middle.number }) {
            guard case .sailing = sailing.stage else { return XCTFail("\(sailing.stage)") }
        }
        session.setMap3DOpen(false)
        XCTAssertNil(session.followedFerryBoatID)
        XCTAssertNil(session.ferryFollowBar)
        session.setMap3DOpen(true)
        session.followFerryBoat(id)
        XCTAssertNotNil(session.followedFerryBoatID)
        session.stopFollowingTrain()
        XCTAssertNil(session.followedFerryBoatID)
        // Closing the route lets its boat go.
        session.followFerryBoat(id)
        session.removeFerryRoute(route.id)
        XCTAssertNil(session.followedFerryBoatID)
    }

    // MARK: - Helpers

    /// 64 × 16 cells with water across rows 4 and 5, and one ferry route
    /// between two piers, a boat every 15 minutes (as Map3DFerriesTests).
    private func makeFerryWorld(from a: CellPosition, to b: CellPosition, boats: Int) throws -> (world: GameWorld, id: FerryRouteID) {
        var world = try makeWorld(width: 64 * Land.cellLength, height: 16 * Land.cellLength, balance: Money(10_000_000_000))
        try world.setWater((4...5).flatMap { row in (0..<64).map { CellPosition(row: row, column: $0) } })
        let route = try world.createFerryRoute(piers: [a, b], service: .every(minutes: 15), boats: boats)
        return (world, route.id)
    }
}
