@testable import GamePresentation
import XCTest

/// OLD-PORT-AUDIT: no landmark model in the game carries a ground plate.
/// The earlier version's buildings often bring their own lot (Fukuoka
/// Tower's file begins with a 40 m square of plaza); the map draws its
/// own ground, so a model leaves it out. The same rule as
/// `tools/landmarks/ground_plate.py`, which stops a conversion.
final class Map3DLandmarkGroundPlateTests: XCTestCase {
    /// Square metres of level faces looking up on the model's lowest
    /// level that reach beyond its body (the box round everything more
    /// than a metre, or an eighth of its height, above its foot).
    static func plateArea(_ mesh: LandmarkMesh) -> Float {
        let points = mesh.vertices
        guard let low = points.map(\.z).min(), let high = points.map(\.z).max() else { return 0 }
        let body = points.filter { $0.z > low + max(1, 0.12 * (high - low)) }
        guard let minX = body.map(\.x).min(), let maxX = body.map(\.x).max(),
              let minY = body.map(\.y).min(), let maxY = body.map(\.y).max() else { return 0 }
        var area: Float = 0
        for at in stride(from: 0, to: mesh.indices.count - 2, by: 3) {
            let a = points[Int(mesh.indices[at])], b = points[Int(mesh.indices[at + 1])], c = points[Int(mesh.indices[at + 2])]
            guard max(a.z, b.z, c.z) <= low + 0.05 else { continue }
            let u = Map3DPoint(b.x - a.x, b.y - a.y, b.z - a.z), v = Map3DPoint(c.x - a.x, c.y - a.y, c.z - a.z)
            let n = u.cross(v)
            let nx: Float = n.x, ny: Float = n.y, nz: Float = n.z
            let squared: Float = nx * nx + ny * ny + nz * nz
            let length: Float = squared.squareRoot()
            guard length > 0, nz / length >= 0.98 else { continue }
            let beyond = [a, b, c].contains { (p: Map3DVertex) -> Bool in
                let x: Float = p.x, y: Float = p.y
                if x < minX - 0.5 || x > maxX + 0.5 { return true }
                return y < minY - 0.5 || y > maxY + 0.5
            }
            if beyond { area += length / 2 }
        }
        return area
    }

    /// The tool's limit: the Bank of China Tower's corner garden is 8.7 m².
    private static let limit: Float = 25

    func testNoModelBringsItsOwnGround() {
        for landmark in Map3DHongKongLandmark.allCases {
            for full in [true, false] {
                XCTAssertLessThanOrEqual(Self.plateArea(landmark.model(full: full)), Self.limit, "\(landmark) full \(full)")
            }
        }
        // Decision 895: the registered ones too.
        for landmark in Map3DLandmarkRegistry.landmarks {
            for full in [true, false] {
                XCTAssertLessThanOrEqual(Self.plateArea(landmark.model(full: full)), Self.limit, "\(landmark.id) full \(full)")
            }
        }
        // The pier's deck is the model itself, and stands on the water.
        for model in Map3DSunMoonLandmark.Model.allCases where model != .pier {
            for full in [true, false] {
                XCTAssertLessThanOrEqual(Self.plateArea(model.mesh(full: full)), Self.limit, "\(model) full \(full)")
            }
        }
    }

    /// The rule finds a plate: a 4 m tower on a 40 m square.
    func testAPlateIsFound() {
        var mesh = LandmarkMesh(full: true)
        let colour = Map3DPalette.granite
        for (half, z) in [(Float(20), Float(0)), (2, 30)] {
            mesh.tri((-half, -half, z), (half, -half, z), (half, half, z), colour, LandmarkMesh.plain)
            mesh.tri((-half, -half, z), (half, half, z), (-half, half, z), colour, LandmarkMesh.plain)
        }
        XCTAssertEqual(Self.plateArea(mesh), 1_600, accuracy: 1)
    }
}
