@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 517 續 PR 2: a tap on the 3D map selects the station under the
/// finger as a tap on the 2D map does, and its tag stands at the station.
@MainActor
final class Map3DTapTests: XCTestCase {
    private static let towns = Land.townCentres(seed: 1, in: GameWorld.newGameBounds)
    private static let world = try! newGameLine(through: [towns[0], towns[1]])

    private func view(of station: Station) -> (camera: Map3DCamera, space: Map3DPick.Space, ground: Map3DPick.Ground) {
        let space = Map3DPick.Space(originX: Double(station.location.x) - 2_000, originY: Double(station.location.y) + 900)
        let ground = Map3DPick.ground(of: Self.world, in: space)
        let anchor = Map3DTap.anchor(of: station.id, in: Self.world, space: space, ground: ground)!
        return (Map3DCamera(target: anchor, distance: 200, heading: 0.6, viewport: (844, 390)), space, ground)
    }

    private func tap(_ session: GameSession, atX x: Float, y: Float, camera: Map3DCamera, space: Map3DPick.Space, ground: Map3DPick.Ground) -> StationID? {
        let world = session.world
        guard let hit = Map3DPick.pick(atX: x, y: y, camera: camera, space: space, bounds: world.bounds, nodes: [], ground: ground) else {
            XCTFail("no ground under (\(x), \(y))")
            return nil
        }
        return session.tapMap3D(at: hit, reach: Map3DTap.reach(at: hit.point, camera: camera))
    }

    func testTheReachIsTheTouchRadiusAtTheDepthTapped() {
        let camera = Map3DCamera(target: .zero, distance: 1_000, heading: 0, viewport: (844, 390))
        // Straight down from 1 km: 24 points of a 390-point view 35° tall.
        let expected = 2 * 1_000 * tan(35.0 / 2 * .pi / 180) / 390 * 24 * 64
        XCTAssertEqual(Double(Map3DTap.reach(at: .zero, camera: camera)), expected, accuracy: 2)
        // Farther along the view, farther reached.
        let near = Map3DCamera(target: .zero, distance: 150, heading: 0, viewport: (844, 390))
        let ahead = near.ray(throughX: 422, y: 40), behind = near.ray(throughX: 422, y: 350)
        let far = Map3DPick.ground(along: ahead, ground: { _, _ in 0 }, within: 5_000)!
        let close = Map3DPick.ground(along: behind, ground: { _, _ in 0 }, within: 5_000)!
        XCTAssertGreaterThan(Map3DTap.reach(at: far, camera: near), Map3DTap.reach(at: close, camera: near))
    }

    func testATapOnAStationSelectsItAndOneOffItLetsGo() throws {
        let session = GameSession(world: Self.world)
        let station = try XCTUnwrap(Self.world.stations.first)
        let (camera, space, ground) = view(of: station)
        let anchor = try XCTUnwrap(Map3DTap.anchor(of: station.id, in: Self.world, space: space, ground: ground))
        let seen = try XCTUnwrap(camera.screenPoint(of: anchor))
        XCTAssertEqual(seen.x, 422, accuracy: 0.5, "the camera looks at the station")
        XCTAssertEqual(tap(session, atX: seen.x + 10, y: seen.y + 6, camera: camera, space: space, ground: ground), station.id)
        XCTAssertEqual(session.selectedStationID, station.id)
        // 150 points away, on the open ground.
        XCTAssertNil(tap(session, atX: seen.x + 150, y: seen.y - 120, camera: camera, space: space, ground: ground))
        XCTAssertNil(session.selectedStationID, "the tag goes")
    }

    func testOnlyWhileLookingAtTheMap() throws {
        let session = GameSession(world: Self.world)
        let station = try XCTUnwrap(Self.world.stations.first)
        let (camera, space, ground) = view(of: station)
        let seen = try XCTUnwrap(camera.screenPoint(of: Map3DTap.anchor(of: station.id, in: Self.world, space: space, ground: ground)!))
        session.selectTool(.network)
        XCTAssertNil(tap(session, atX: seen.x, y: seen.y, camera: camera, space: space, ground: ground))
        XCTAssertNil(session.selectedStationID)
    }

    func testTheTagStandsWhereTheTrackIsDrawnAtTheStation() throws {
        let station = try XCTUnwrap(Self.world.stations.first)
        let space = Map3DPick.Space(originX: 0, originY: 0)
        let ground: Map3DPick.Ground = { _, _ in 12 }
        let anchor = try XCTUnwrap(Map3DTap.anchor(of: station.id, in: Self.world, space: space, ground: ground))
        XCTAssertEqual(anchor.y, 12 + Map3DScene.railLift)
        let back = space.worldPosition(of: anchor)
        XCTAssertEqual(back.x, Double(station.location.x), accuracy: 0.01)
        XCTAssertEqual(back.y, Double(station.location.y), accuracy: 0.01)
        XCTAssertNil(Map3DTap.anchor(of: StationID(rawValue: 9_999), in: Self.world, space: space, ground: ground))
    }
}

extension Map3DTapTests {
    func testTheTagStandsUnderTheStationAndStaysInTheView() throws {
        let viewport: (width: Float, height: Float) = (844, 390)
        // In the middle: centred, under.
        let middle = try XCTUnwrap(Map3DTap.tagOrigin(under: 422, 195, width: 160, height: 44, viewport: viewport))
        XCTAssertEqual(middle.x, 342)
        XCTAssertEqual(middle.y, 195 + Map3DTap.tagGap)
        // By the bottom: over it.
        let low = try XCTUnwrap(Map3DTap.tagOrigin(under: 422, 360, width: 160, height: 44, viewport: viewport))
        XCTAssertEqual(low.y, 360 - Map3DTap.tagGap - 44)
        // By the left, past the controls: moved in.
        let left = try XCTUnwrap(Map3DTap.tagOrigin(under: 130, 195, width: 160, height: 44, viewport: viewport,
                                                    clear: (top: 0, leading: 100, bottom: 0, trailing: 0)))
        XCTAssertEqual(left.x, 100 + Map3DTap.tagMargin)
        // Under the controls or off the view: none.
        XCTAssertNil(Map3DTap.tagOrigin(under: 60, 195, width: 160, height: 44, viewport: viewport,
                                        clear: (top: 0, leading: 100, bottom: 0, trailing: 0)))
        XCTAssertNil(Map3DTap.tagOrigin(under: 422, -30, width: 160, height: 44, viewport: viewport))
    }
}
