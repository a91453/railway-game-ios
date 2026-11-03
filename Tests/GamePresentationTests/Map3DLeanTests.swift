import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 555: two fingers lean the 3D map over to 60°, past the tilt
/// its distance gives (decisions 269 and 313, unchanged); the lean stays
/// when they lift and fades out with the distance's own tilt; the sun's
/// shadows' square moves ahead to the ground in view; and two fingers
/// moving up together are told from a pinch and a turn.
final class Map3DLeanTests: XCTestCase {
    private static let degree: Float = .pi / 180
    /// An iPhone 17 Pro upright and sideways, and an iPad's 11-inch screen.
    private static let viewports: [(width: Float, height: Float)] = [(402, 874), (874, 402), (834, 1_194)]

    private func camera(_ distance: Float, heading: Float = 0, lean: Float = 0, viewport: (width: Float, height: Float) = (402, 874)) -> Map3DCamera {
        var camera = Map3DCamera(target: Map3DPoint(130, 0, -250), distance: distance, heading: heading, viewport: viewport)
        camera.lean = lean
        return camera
    }

    /// With no lean, the tilt is the distance's own, as before: the owner's
    /// 34–40° at 150–200 m, 42° from 120 m in, flat from 800 m out.
    func testTheDistancesTiltIsAsItWas() {
        for distance in stride(from: Float(60), through: 1_200, by: 20) {
            XCTAssertEqual(camera(distance).tilt, Map3DCamera.tilt(atDistance: distance), "\(distance) m")
            XCTAssertEqual(Map3DCamera.tilt(atDistance: distance, lean: 0), Map3DCamera.tilt(atDistance: distance))
        }
        XCTAssertEqual(camera(150).tilt / Self.degree, 40.4, accuracy: 0.1)
        XCTAssertEqual(camera(200).tilt / Self.degree, 34.5, accuracy: 0.1)
        XCTAssertEqual(camera(120).tilt, Map3DCamera.mostTilt)
        XCTAssertEqual(camera(800).tilt, 0)
    }

    /// Two fingers up lean it over, half a degree a point, to 60° at
    /// most; down stand it up again, as far as the distance's own tilt.
    func testTwoFingersLeanItOverAndBack() {
        var leaned = camera(200).leaned(dy: -10)
        XCTAssertEqual(leaned.tilt / Self.degree, 34.5 + 5, accuracy: 0.1)
        leaned = leaned.leaned(dy: -1_000)
        XCTAssertEqual(leaned.tilt, Map3DCamera.mostLean, accuracy: 1e-5)
        XCTAssertEqual(leaned.leaned(dy: -50).tilt, Map3DCamera.mostLean, accuracy: 1e-5, "no further")
        XCTAssertEqual(leaned.leaned(dy: 20).tilt / Self.degree, 50, accuracy: 0.05, "no slack at the top")
        let back = leaned.leaned(dy: 1_000)
        XCTAssertEqual(back.lean, 0)
        XCTAssertEqual(back.tilt, Map3DCamera.tilt(atDistance: 200))
        // Close in, all the way.
        XCTAssertEqual(camera(60).leaned(dy: -1_000).tilt, Map3DCamera.mostLean, accuracy: 1e-5)
        XCTAssertEqual(camera(120).leaned(dy: -36).tilt / Self.degree, 60, accuracy: 0.01)
    }

    /// The lean stays as the map is pinched, moved and turned, and fades
    /// out with the distance's own tilt: from 800 m out straight down, as
    /// before; back in, leaning as it was.
    func testTheLeanStaysAndFadesWithTheDistance() {
        let leaned = camera(200).leaned(dy: -1_000)
        XCTAssertEqual(leaned.panned(dx: 30, dy: 40).tilt, leaned.tilt)
        XCTAssertEqual(leaned.turned(by: 1).tilt, leaned.tilt)
        let out = leaned.zoomed(by: 0.25)
        XCTAssertEqual(out.distance, 800)
        XCTAssertEqual(out.tilt, 0)
        XCTAssertEqual(out.zoomed(by: 4).tilt, leaned.tilt, accuracy: 1e-5)
        var last: Float = .infinity
        for distance in stride(from: Float(60), through: 900, by: 10) {
            var at = leaned
            at.distance = distance
            XCTAssertLessThanOrEqual(at.tilt, last + 1e-6, "less as it pulls out, \(distance) m")
            XCTAssertGreaterThanOrEqual(at.tilt, Map3DCamera.tilt(atDistance: distance))
            XCTAssertLessThanOrEqual(at.tilt, Map3DCamera.mostLean + 1e-6)
            last = at.tilt
        }
        // A camera handed over from the 2D map (decision 313), flat from
        // nearer in, flat there still.
        var handed = Map3DCamera(distance: 300, viewport: (874, 402))
        handed.tiltsFrom = 300
        XCTAssertEqual(handed.leaned(dy: -1_000).tilt, 0)
        handed.distance = 140
        XCTAssertEqual(handed.leaned(dy: -1_000).tilt, Map3DCamera.mostLean, accuracy: 1e-5)
    }

    /// A followed train's camera, and a flight's, have their tilt set
    /// outright (decisions 333 and 337): the fingers do not lean them.
    func testASetTiltDoesNotLean() {
        var cab = camera(40)
        cab.pitch = 88.9 * Self.degree
        cab.lens = 68 * Self.degree
        XCTAssertEqual(cab.leaned(dy: -100), cab)
        var flight = camera(200).leaned(dy: -1_000)
        flight.pitch = 20 * Self.degree
        XCTAssertEqual(flight.tilt, 20 * Self.degree)
        XCTAssertNotEqual(camera(200), camera(200).leaned(dy: -10), "the lean is part of the camera")
    }

    /// At 60° the top of the view, 17.5° above its middle, stays below
    /// the horizon: no sky and no edge of the scene. Every corner of the
    /// view meets the ground within what the scene draws in full
    /// (``Map3DCamera/wantsDetail``), keeps round its target
    /// (``Map3DStreaming/around``) and builds in full (decision 368).
    func testAt60TheGroundStaysWithinWhatIsDrawnInFull() {
        XCTAssertLessThan(Map3DCamera.mostLean + Map3DCamera.fieldOfView / 2, 80 * Self.degree)
        for viewport in Self.viewports {
            for distance in stride(from: Float(60), through: 800, by: 20) {
                for heading in [0, 0.7, 2, 4.5] as [Float] {
                    let leaned = camera(distance, heading: heading, viewport: viewport).leaned(dy: -1_000)
                    for corner in leaned.groundCorners {
                        XCTAssertEqual(corner.y, leaned.target.y, accuracy: 0.01, "\(viewport) \(distance) m: on the ground")
                        let reach = (corner - leaned.target).length
                        XCTAssertLessThanOrEqual(reach, max(Map3DCamera.detailReach, distance * 1.2) * 0.86, "\(viewport) \(distance) m")
                        XCTAssertLessThan(reach, Map3DStreaming.around)
                        XCTAssertLessThan(reach, Map3DScene.detailRadius)
                        XCTAssertTrue(leaned.wantsDetail(minimum: corner, maximum: corner), "\(viewport) \(distance) m")
                    }
                }
            }
        }
    }

    /// The numbers decision 555 gives: how far the ground in view reaches
    /// from the target, and how many of the scene's 512 m chunks are in
    /// view (``Map3DCamera/sees``, a chunk 60 m tall), at the distance's
    /// tilt and at 60°, the target in a chunk's corner (the most).
    func testTheChunksInViewAt42And60() {
        let size = Map3DScene.chunkSize
        func chunks(_ camera: Map3DCamera) -> Int {
            let matrix = camera.viewProjection
            var count = 0
            for column in -12..<12 {
                for row in -12..<12 {
                    let minimum = Map3DPoint(Float(column) * size, 0, Float(row) * size)
                    if Map3DCamera.sees(minimum: minimum, maximum: minimum + Map3DPoint(size, 60, size), through: matrix) { count += 1 }
                }
            }
            return count
        }
        func farthest(_ camera: Map3DCamera) -> Float { camera.groundCorners.map { ($0 - camera.target).length }.max() ?? 0 }
        var lines: [String] = []
        for viewport in Self.viewports.prefix(2) {
            for distance in [120, 200, 260, 400] as [Float] {
                let own = Map3DCamera(target: .zero, distance: distance, heading: 0.3, viewport: viewport)
                let leaned = own.leaned(dy: -1_000)
                lines.append("\(Int(viewport.width))×\(Int(viewport.height)) \(Int(distance)) m: "
                    + "\(String(format: "%.1f", own.tilt / Self.degree))° \(Int(farthest(own))) m \(chunks(own)) chunks, "
                    + "\(String(format: "%.1f", leaned.tilt / Self.degree))° \(Int(farthest(leaned))) m \(chunks(leaned)) chunks")
                XCTAssertLessThanOrEqual(chunks(leaned), 9, "\(viewport) \(distance) m")
            }
        }
        print(lines.joined(separator: "\n"))
    }

    // MARK: - The sun's shadows

    /// With no lean the square is round the target as before (decision
    /// 357), whichever screen.
    func testWithNoLeanTheSquareIsAsItWas() {
        let sun = Map3DLighting(minute: 15 * 60).sunDirection
        for viewport in Self.viewports {
            for distance in stride(from: Float(60), through: 4_100, by: 70) {
                let plain = camera(distance, heading: 1.1, viewport: viewport)
                XCTAssertEqual(Map3DSunShadow.region(camera: plain, sun: sun, size: 2_048),
                               Map3DSunShadow.region(target: plain.target, distance: distance, sun: sun, size: 2_048))
            }
        }
    }

    /// Leaned over, the square moves ahead and grows so that every corner
    /// of the ground in view falls inside it, short of where the shadows
    /// fade (but for the snapping to a quarter of its half side), at any
    /// hour, heading and screen; out past 4 km there are none, as before.
    func testLeanedTheSquareHoldsTheGroundInView() throws {
        for viewport in Self.viewports {
            for distance in stride(from: Float(60), through: 800, by: 20) {
                for heading in [0, 0.7, 2, 4.5] as [Float] {
                    for hour in [7, 10, 12, 15.5, 17.5] as [Double] {
                        let sun = Map3DLighting(minute: hour * 60).sunDirection
                        let leaned = camera(distance, heading: heading, viewport: viewport).leaned(dy: -1_000)
                        let region = try XCTUnwrap(Map3DSunShadow.region(camera: leaned, sun: sun, size: 2_048))
                        XCTAssertGreaterThanOrEqual(region.extent, Map3DSunShadow.extent(distance: distance))
                        XCTAssertLessThanOrEqual(region.extent, Map3DSunShadow.extent(distance: distance) * Map3DSunShadow.step * Map3DSunShadow.step + 0.1,
                                                 "\(viewport) \(distance) m: two steps larger at most")
                        let matrix = region.matrix
                        for corner in leaned.groundCorners {
                            let x = matrix[0, 0] * corner.x + matrix[0, 1] * corner.y + matrix[0, 2] * corner.z + matrix[0, 3]
                            let y = matrix[1, 0] * corner.x + matrix[1, 1] * corner.y + matrix[1, 2] * corner.z + matrix[1, 3]
                            let edge = max(abs(x), abs(y))
                            XCTAssertLessThanOrEqual(edge, Map3DSunShadow.fadeFrom + Map3DSunShadow.moveShare * 0.71 + 0.01,
                                                     "\(viewport) \(distance) m, heading \(heading), \(hour) h")
                        }
                    }
                }
            }
        }
        for viewport in Self.viewports.prefix(2) {
            print("\(Int(viewport.width))×\(Int(viewport.height)):", [120, 200, 260, 400, 600].map { (distance: Float) in
                let leaned = camera(distance, viewport: viewport).leaned(dy: -1_000)
                let region = Map3DSunShadow.region(camera: leaned, sun: .up, size: 2_048)
                let ahead = region.map { ($0.centre - leaned.target).dot(leaned.forward) } ?? 0
                return "\(Int(distance)) m: half side \(Int(region?.extent ?? 0)) m (\(Int(Map3DSunShadow.extent(distance: distance))) m before), ahead \(Int(ahead)) m"
            }.joined(separator: "; "))
        }
        var far = camera(4_100).leaned(dy: -1_000)
        far.lean = Map3DCamera.mostLean
        XCTAssertNil(Map3DSunShadow.region(camera: far, sun: .up, size: 2_048))
    }

    /// The example the study gave (IMMERSIVEMAP_STUDY §3.3): 200 m at 60°
    /// sideways reaches some 410 m from the target, out of the 220 m
    /// square round it; leaned, the square's middle goes ahead.
    func testTheStudysExample() throws {
        let leaned = camera(200, viewport: (874, 402)).leaned(dy: -1_000)
        let farthest = leaned.groundCorners.map { ($0 - leaned.target).length }.max() ?? 0
        XCTAssertEqual(farthest, 410, accuracy: 25)
        let region = try XCTUnwrap(Map3DSunShadow.region(camera: leaned, sun: .up, size: 2_048))
        XCTAssertGreaterThan((region.centre - leaned.target).dot(leaned.forward), 50, "ahead along the view")
        XCTAssertNotEqual(region, Map3DSunShadow.region(target: leaned.target, distance: 200, sun: .up, size: 2_048))
    }

    // MARK: - Telling a lean from a pinch and a turn

    func testTwoFingersUpTogetherLean() {
        var drag = Map3DTiltDrag((100, 500), (260, 520))
        XCTAssertEqual(drag.move((101, 495), (261, 516)), .undecided, "not far enough yet")
        XCTAssertEqual(drag.move((102, 486), (262, 508)), .leans)
        XCTAssertEqual(drag.drop((102, 486), (262, 508)), -13)
        XCTAssertEqual(drag.move((300, 100), (90, 100)), .leans, "decided once")
        var down = Map3DTiltDrag((100, 500), (260, 500))
        XCTAssertEqual(down.move((98, 520), (258, 518)), .leans)
    }

    func testAPinchATurnAndAStackedPairDoNotLean() {
        var pinch = Map3DTiltDrag((100, 500), (260, 500))
        XCTAssertEqual(pinch.move((80, 490), (280, 490)), .other, "drawing apart")
        var spread = Map3DTiltDrag((180, 300), (220, 300))
        XCTAssertEqual(spread.move((180, 300), (220, 330)), .other, "one finger, steady")
        var turn = Map3DTiltDrag((100, 500), (260, 500))
        XCTAssertEqual(turn.move((100, 512), (260, 488)), .other, "the fingers moving opposite ways")
        var stacked = Map3DTiltDrag((200, 300), (210, 500))
        XCTAssertEqual(stacked.move((200, 285), (210, 485)), .other, "one above the other: a pinch's start")
        var slanting = Map3DTiltDrag((100, 500), (260, 500))
        XCTAssertEqual(slanting.move((112, 492), (272, 492)), .other, "more across than up")
        XCTAssertEqual(slanting.move((100, 400), (260, 400)), .other, "decided once")
    }
}
