import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 342: the ground's thin layers (``Map3DRealGround``'s covers,
/// sidewalks, roads and centre lines, the shadows, the track) are told
/// apart by the depth buffer alone, a few centimetres apart. These tests
/// take a ray through each of a grid of the view's pixels down to two
/// layers `gap` apart and work out, in `Float` as the GPU does, the depth
/// each would write: where the two come out equal or the wrong way round,
/// the farther layer shows through the nearer one, and as the camera
/// moves, flickers.
final class Map3DDepthTests: XCTestCase {
    /// The gaps between the ground's layers (``Map3DRealGround``): the
    /// smallest, a sidewalk (0.26 m) under a lane (0.28 m), a centre line
    /// (0.38 m) under a shadow (0.40 m); the covers' and the roads' steps.
    static let gaps: [Float] = [0.02, 0.04]
    /// The camera's distances: the closest, the follow view's, where the
    /// map tilts most and starts to, the 3D button's whole city, the
    /// farthest.
    static let distances: [Float] = [Map3DCamera.nearest, 120, 280, 800, 3_000, 10_800, Map3DCamera.farthest]

    /// The map's own cameras at ``distances``, and the follow views
    /// (decisions 333, 337) of a train at the middle facing north.
    static var cameras: [(name: String, camera: Map3DCamera)] {
        var cameras = distances.flatMap { distance in
            [Map3DPoint.zero, Map3DPoint(5_500, 0, -5_500)].map { target in
                ("map, \(Int(distance)) m, tilted \(Int(Map3DCamera.tilt(atDistance: distance) * 180 / .pi))°\(target == .zero ? "" : ", 7.8 km off the middle")",
                 Map3DCamera(target: target, distance: distance, viewport: (402, 874)))
            }
        }
        let head = Map3DTrains.Head(train: TrainID(rawValue: 1), point: Map3DPoint(0, Map3DScene.railLift + Map3DTrains.carHeight + Map3DTrains.headClearance, 0))
        for view in [Map3DFollow.View.back, .aboveBack, .cab] {
            let follow = Map3DFollow(train: head.train, view: view)
            cameras.append(("follow, \(view)", follow.camera(following: head, from: Map3DCamera(viewport: (402, 874)), elapsed: 0, turnsAtOnce: true)))
        }
        return cameras
    }

    /// How many of the view's pixels see two layers `gap` apart the same
    /// or the wrong way round, and how many no more than `margin` steps
    /// of the depth buffer apart, out of how many see the ground before
    /// the fog hides it; with `matrix`, or the camera's own.
    static func fights(camera: Map3DCamera, gap: Float, at height: Float = 0.26, margin: Float = 8,
                       matrix: Map3DMatrix? = nil) -> (wrong: Int, close: Int, seen: Int, fewest: Float) {
        let m = (matrix ?? camera.viewProjection).columns
        let view = camera.view.columns
        let side = Map3DPoint(view[0], view[4], view[8]), up = Map3DPoint(view[1], view[5], view[9])
        let look = -Map3DPoint(view[2], view[6], view[10])
        let tall = tanf(camera.fieldOfViewTall / 2), wide = tall * camera.viewport.width / camera.viewport.height
        let eye = camera.eye
        let fogEnd = camera.depthRange.far * 0.9
        func depth(_ p: Map3DPoint) -> Float {
            let z = m[2] * p.x + m[6] * p.y + m[10] * p.z + m[14]
            let w = m[3] * p.x + m[7] * p.y + m[11] * p.z + m[15]
            return z / w
        }
        let reversed = depth(eye + look * (camera.depthRange.near * 2)) > depth(eye + look * (camera.depthRange.far / 2))
        var wrong = 0, close = 0, seen = 0, fewest = Float.infinity
        let columns = 60, rows = 120
        for row in 0..<rows {
            for column in 0..<columns {
                let sx = (Float(column) + 0.5) / Float(columns) * 2 - 1, sy = (Float(row) + 0.5) / Float(rows) * 2 - 1
                let ray = look + side * (sx * wide) + up * (sy * tall)
                guard ray.y < 0 else { continue }
                let low = eye + ray * ((height - eye.y) / ray.y), high = eye + ray * ((height + gap - eye.y) / ray.y)
                guard (low - eye).length < fogEnd else { continue }
                seen += 1
                let far = depth(low), near = depth(high)
                let apart = reversed ? near - far : far - near
                fewest = min(fewest, apart / max(far, near).ulp)
                if apart <= 0 {
                    wrong += 1
                } else if apart <= margin * max(far, near).ulp {
                    close += 1
                }
            }
        }
        return (wrong, close, seen, fewest)
    }

    /// The projection before decision 342: depth 0 at the near plane, 1
    /// at the far one.
    static func standardProjection(_ camera: Map3DCamera) -> Map3DMatrix {
        let aspect = camera.viewport.width / camera.viewport.height
        let f = 1 / tanf(camera.fieldOfViewTall / 2)
        let (near, far) = camera.depthRange
        return Map3DMatrix(columns: [
            f / aspect, 0, 0, 0,
            0, f, 0, 0,
            0, 0, far / (near - far), -1,
            0, 0, near * far / (near - far), 0,
        ]) * camera.view
    }

    /// The measurement in the decision, only on request
    /// (`MAP3D_FRAME_REPORT=1`): each camera, each gap, the old and the new
    /// projection.
    func testTheDepthReport() throws {
        guard ProcessInfo.processInfo.environment["MAP3D_FRAME_REPORT"] != nil else { throw XCTSkip("Set MAP3D_FRAME_REPORT=1.") }
        for (name, camera) in Self.cameras {
            var line = "\(name):"
            for gap in Self.gaps {
                let old = Self.fights(camera: camera, gap: gap, matrix: Self.standardProjection(camera))
                let new = Self.fights(camera: camera, gap: gap)
                func share(_ n: Int, _ of: Int) -> String { of == 0 ? "-" : String(format: "%.1f%%", Double(n) * 100 / Double(of)) }
                line += " | \(Int(gap * 100)) cm: before wrong \(share(old.wrong, old.seen)) close \(share(old.close, old.seen))"
                line += ", now wrong \(share(new.wrong, new.seen)) close \(share(new.close, new.seen)) (fewest steps \(Int(old.fewest)) → \(Int(new.fewest)))"
            }
            print(line)
        }
    }
}
