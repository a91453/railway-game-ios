import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 517: Build on the 3D map builds on the 2D map at the same
/// place and goes back to the 3D camera it left as building ends; Build on
/// the 2D map stays there.
final class Map3DBuildReturnTests: XCTestCase {
    private final class Game {}

    private static let scene: Map3DScene = {
        let towns = Land.townCentres(seed: 1, in: GameWorld.newGameBounds)
        return Map3DScene(world: try! newGameLine(through: [towns[0], towns[1]]))
    }()

    private func turnedView() -> Map3DBuildReturn.Viewpoint {
        var camera = Map3DCamera(target: Map3DPoint(120, 4, -340), distance: 420, heading: 1.1, viewport: (844, 390))
        camera.pitch = 0.6
        return Map3DBuildReturn.Viewpoint(camera: camera, in: Self.scene)
    }

    func testBuildingEndsBackOnTheThreeDCameraItLeft() {
        let game = Game(), id = ObjectIdentifier(game)
        var trip = Map3DBuildReturn()
        let view = turnedView()
        trip.leftForBuilding(from: view, in: id)
        XCTAssertTrue(trip.waits)
        // Build opens the track tools; other tools still build.
        for tool in [ConstructionTool.network, .train, .building, .bus, .network] {
            XCTAssertNil(trip.toolChanged(to: tool, in: id, shows3D: true, tutorialRuns: false), "\(tool) still builds")
            XCTAssertTrue(trip.waits)
        }
        // Done: the same camera, heading and lean too.
        let back = trip.toolChanged(to: .select, in: id, shows3D: true, tutorialRuns: false)
        XCTAssertEqual(back, view)
        XCTAssertEqual(back?.camera.heading, 1.1)
        XCTAssertEqual(back?.camera.pitch, 0.6)
        XCTAssertFalse(trip.waits, "once")
        XCTAssertNil(trip.toolChanged(to: .network, in: id, shows3D: true, tutorialRuns: false))
        XCTAssertNil(trip.toolChanged(to: .select, in: id, shows3D: true, tutorialRuns: false))
    }

    /// Review L3-2: Expand Map from building that began on the 3D map puts
    /// the tools away to choose a tile on the 2D map: that is not building
    /// ended, so the 3D map does not open over the tiles for sale, nor
    /// later.
    func testExpandingTheMapIsNotBuildingEnded() {
        let game = Game(), id = ObjectIdentifier(game)
        var trip = Map3DBuildReturn()
        trip.leftForBuilding(from: turnedView(), in: id)
        XCTAssertNil(trip.toolChanged(to: .network, in: id, shows3D: true, tutorialRuns: false))
        XCTAssertNil(trip.toolChanged(to: .select, in: id, shows3D: true, tutorialRuns: false, choosingMapTile: true))
        XCTAssertFalse(trip.waits)
        XCTAssertNil(trip.toolChanged(to: .network, in: id, shows3D: true, tutorialRuns: false))
        XCTAssertNil(trip.toolChanged(to: .select, in: id, shows3D: true, tutorialRuns: false))
    }

    /// What the app's watch sees as Expand Map is pressed in a game that
    /// buys its map: the select tool, and choosing a tile already set.
    @MainActor
    func testExpandMapIsSeenAsChoosingATile() {
        let session = GameSession(world: GameWorld.newGame(balance: 3_000_000_000, eventSeed: 9, buysMap: true),
                                  language: .english)
        var trip = Map3DBuildReturn()
        trip.leftForBuilding(from: turnedView(), in: ObjectIdentifier(session))
        func seen() -> Map3DBuildReturn.Viewpoint? {
            trip.toolChanged(to: session.tool, in: ObjectIdentifier(session), shows3D: true,
                             tutorialRuns: session.tutorial != nil, choosingMapTile: session.isChoosingMapTile)
        }
        session.selectTool(.network)
        let building = seen()
        XCTAssertNil(building)
        session.startChoosingMapTile()
        let (tool, choosing) = (session.tool, session.isChoosingMapTile)
        XCTAssertEqual(tool, .select)
        XCTAssertTrue(choosing)
        let expanding = seen()
        XCTAssertNil(expanding, "the 3D map does not open over the tiles for sale")
        XCTAssertFalse(trip.waits)
    }

    /// Building started on the 2D map ends there.
    func testBuildingFromTheTwoDMapStaysTwoD() {
        let game = Game(), id = ObjectIdentifier(game)
        var trip = Map3DBuildReturn()
        XCTAssertNil(trip.toolChanged(to: .network, in: id, shows3D: true, tutorialRuns: false))
        XCTAssertNil(trip.toolChanged(to: .select, in: id, shows3D: true, tutorialRuns: false))
        XCTAssertFalse(trip.waits)
    }

    /// The 3D map off (decision 365), the tutorial, another game, or the 3D
    /// map opened some other way meanwhile: no return, and none later.
    func testNoReturnWhenItWouldNotFit() {
        let game = Game(), other = Game()
        let id = ObjectIdentifier(game)
        let cases: [(String, (inout Map3DBuildReturn) -> Map3DBuildReturn.Viewpoint?)] = [
            ("3D off", { $0.toolChanged(to: .select, in: id, shows3D: false, tutorialRuns: false) }),
            ("tutorial", { $0.toolChanged(to: .select, in: id, shows3D: true, tutorialRuns: true) }),
            ("another game", { $0.toolChanged(to: .select, in: ObjectIdentifier(other), shows3D: true, tutorialRuns: false) }),
            ("3D opened meanwhile", { trip in
                trip.forget()
                return trip.toolChanged(to: .select, in: id, shows3D: true, tutorialRuns: false)
            }),
        ]
        for (name, end) in cases {
            var trip = Map3DBuildReturn()
            trip.leftForBuilding(from: turnedView(), in: id)
            XCTAssertNil(end(&trip), name)
            XCTAssertFalse(trip.waits, name)
            XCTAssertNil(trip.toolChanged(to: .select, in: id, shows3D: true, tutorialRuns: false), name)
        }
        // The 3D map turned off mid-build forgets, even if it is back on.
        var trip = Map3DBuildReturn()
        trip.leftForBuilding(from: turnedView(), in: id)
        XCTAssertNil(trip.toolChanged(to: .train, in: id, shows3D: false, tutorialRuns: false))
        XCTAssertNil(trip.toolChanged(to: .select, in: id, shows3D: true, tutorialRuns: false))
        withExtendedLifetime((game, other)) {}
    }

    /// The 3D map opens again round the same world point, however the new
    /// scene's origin falls, with the same distance, heading and lean.
    func testTheViewComesBackInANewSceneAtTheSamePlace() throws {
        let view = turnedView()
        let towns = Land.townCentres(seed: 1, in: GameWorld.newGameBounds)
        let wider = Map3DScene(world: try newGameLine(through: [towns[0], towns[1], towns[2]]))
        for scene in [Self.scene, wider] {
            let camera = view.camera(in: scene, viewport: (1_024, 768))
            let middle = scene.worldPosition(of: camera.target)
            XCTAssertEqual(middle.x, view.x, accuracy: 1)
            XCTAssertEqual(middle.y, view.y, accuracy: 1)
            XCTAssertEqual(camera.target.y, 4, accuracy: 1e-4, "the same height")
            XCTAssertEqual(camera.distance, 420)
            XCTAssertEqual(camera.heading, 1.1)
            XCTAssertEqual(camera.pitch, 0.6)
            XCTAssertEqual(camera.viewport.width, 1_024)
            XCTAssertEqual(camera.viewport.height, 768)
        }
        // Its scene is built round where it looked, as close.
        XCTAssertEqual(view.plan.x, view.x)
        XCTAssertEqual(view.plan.referenceSize, Map3DHandoff.referenceSize(distance: 420, viewportHeight: 390), accuracy: 1e-9)
    }

    /// The 2D map Build opens is centred where the 3D camera looked, a
    /// turned and leaning one too, and as close as it was.
    func testTheTwoDMapOpensWhereTheThreeDMapLooked() throws {
        let towns = Land.townCentres(seed: 1, in: GameWorld.newGameBounds)
        let world = try newGameLine(through: [towns[0], towns[1]])
        let scene = Map3DScene(world: world)
        let x = Double(towns[1].x), y = Double(towns[1].y)
        for distance in [Float(300), 900, 2_400] {
            var camera = Map3DCamera(target: scene.point(worldX: x, worldY: y, height: 0), distance: distance, heading: 2.3, viewport: (844, 390))
            camera.pitch = 0.7
            let plan = Map3DHandoff.plan(from: camera, in: scene)
            XCTAssertEqual(plan.x, x, accuracy: 64)
            XCTAssertEqual(plan.y, y, accuracy: 64)
            XCTAssertEqual(plan.referenceSize, Map3DHandoff.referenceSize(distance: distance, viewportHeight: 390), accuracy: 1e-9)
            // Closer in 3D, closer on the 2D map.
            XCTAssertGreaterThan(plan.referenceSize, Map3DHandoff.plan(from: camera.zoomed(by: 0.5), in: scene).referenceSize)
        }
    }
}
