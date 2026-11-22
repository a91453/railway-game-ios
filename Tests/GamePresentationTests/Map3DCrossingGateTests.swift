@testable import GamePresentation
import GameCore
import XCTest

/// Decision 929: a level crossing's warning post and boom are the studio's
/// model.
final class Map3DCrossingGateTests: XCTestCase {
    /// The post and the boom decode at the studio's triangle counts and
    /// sizes, in the crossing's own colours.
    func testTheModelsDecode() throws {
        let post = try XCTUnwrap(Map3DCrossingGate.post), arm = try XCTUnwrap(Map3DCrossingGate.arm)
        XCTAssertEqual(post.triangleCount, 348)
        XCTAssertEqual(arm.triangleCount, 68)
        XCTAssertEqual(post.minimum.z, 0, accuracy: 0.01)
        XCTAssertEqual(post.maximum.z, 3, accuracy: 0.01)
        XCTAssertEqual(arm.maximum.x - arm.minimum.x, 4, accuracy: 0.01, "the boom's length")
        for model in [post, arm] {
            XCTAssertTrue(model.vertices.allSatisfy { Map3DCrossingGate.meshPalette.contains($0.color) })
        }
        // Its two red lamps face the traffic coming (+y).
        let lamps = post.vertices.filter { $0.color == Map3DScene.Builder.barrierRed }
        XCTAssertEqual(lamps.count, 60)
        XCTAssertTrue(lamps.allSatisfy { $0.y > 0.2 })
        // The look keeps its black and red.
        XCTAssertTrue(Map3DLook.functional.contains(Map3DScene.Builder.barrierRed))
        XCTAssertTrue(Map3DLook.functional.contains(Map3DScene.Builder.barrierBlack))
    }

    /// Raised, the boom stands up from its pivot on the post: its far end
    /// 4.94 m up, clear of the lamp box.
    func testTheBoomIsRaisedAboutItsPivot() throws {
        let raised = try XCTUnwrap(Map3DCrossingGate.raised)
        XCTAssertEqual(raised.count, (348 + 68) * 3)
        XCTAssertEqual(raised.map(\.z).max()!, 4.94, accuracy: 0.01)
        let boom = raised.dropFirst(348 * 3)
        XCTAssertEqual(boom.map(\.x).min()!, 0.14 - 0.06, accuracy: 0.01)
        XCTAssertEqual(boom.map(\.y).max()!, -0.27 + 0.06, accuracy: 0.01)
        XCTAssertEqual(boom.map(\.z).min()!, 1 - 0.06, accuracy: 0.01)
    }

    /// In the scene: upright at its foot, its lamps towards `facing`, each
    /// triangle turned as its normal.
    func testItStandsInTheScene() throws {
        var mesh = Map3DMesh()
        let foot = Map3DPoint(10, 2, -5), reach = Map3DPoint(0, 0, 1), facing = Map3DPoint(1, 0, 0)
        XCTAssertTrue(Map3DCrossingGate.add(to: &mesh, at: foot, reach: reach, facing: facing))
        XCTAssertEqual(mesh.triangleCount, 348 + 68)
        let bounds = try XCTUnwrap(mesh.bounds)
        XCTAssertEqual(bounds.min.y, 2, accuracy: 0.01)
        XCTAssertEqual(bounds.max.y, 2 + 4.94, accuracy: 0.01)
        let lamps = mesh.vertices.filter { $0.color == Map3DScene.Builder.barrierRed }
        XCTAssertTrue(lamps.allSatisfy { $0.x > 10.2 && $0.nx > 0.9 || $0.x > 10.2 })
        var facingOut: Float = 0
        for t in 0..<mesh.triangleCount {
            let p = (0..<3).map { mesh.vertices[Int(mesh.indices[t * 3 + $0])] }
            facingOut += (p[1].position - p[0].position).cross(p[2].position - p[0].position).dot(Map3DPoint(p[0].nx, p[0].ny, p[0].nz))
        }
        XCTAssertGreaterThan(facingOut, 0)
    }
}
