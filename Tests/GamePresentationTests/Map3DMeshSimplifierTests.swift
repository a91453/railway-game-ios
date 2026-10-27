import Foundation
import XCTest
@testable import GamePresentation

/// Decision 420: the game's own quadric edge collapses.
final class Map3DMeshSimplifierTests: XCTestCase {
    private let white = Map3DColor.rgb(0xF2F3F1), red = Map3DColor.rgb(0xC8102E)

    /// A sphere of `rings` × `segments` quads, one colour, its triangles
    /// facing out.
    private func sphere(rings: Int = 24, segments: Int = 32) -> [Map3DVertex] {
        func point(_ ring: Int, _ segment: Int) -> Map3DPoint {
            let a = Float.pi * Float(ring) / Float(rings), b = 2 * Float.pi * Float(segment) / Float(segments)
            return Map3DPoint(sin(a) * cos(b), cos(a), sin(a) * sin(b))
        }
        var out: [Map3DVertex] = []
        func triangle(_ p: [Map3DPoint]) {
            guard let n = (p[1] - p[0]).cross(p[2] - p[0]).normalized else { return }
            out += p.map { Map3DVertex($0, normal: n, color: white) }
        }
        for r in 0..<rings {
            for s in 0..<segments {
                let a = point(r, s), b = point(r, s + 1), c = point(r + 1, s + 1), d = point(r + 1, s)
                triangle([a, b, c])
                triangle([a, c, d])
            }
        }
        return out
    }

    /// A flat 10 × 4 m side of `step`-metre squares, white with a red band
    /// from 1.5 to 2.5 m up: a car's side and its stripe.
    private func stripedSide(step: Float = 0.25) -> [Map3DVertex] {
        var out: [Map3DVertex] = []
        let normal = Map3DPoint(0, 0, 1)
        for i in 0..<Int(10 / step) {
            for j in 0..<Int(4 / step) {
                let x = Float(i) * step, y = Float(j) * step
                let colour = y >= 1.5 && y < 2.5 ? red : white
                let a = Map3DPoint(x, y, 0), b = Map3DPoint(x + step, y, 0), c = Map3DPoint(x + step, y + step, 0), d = Map3DPoint(x, y + step, 0)
                out += [a, b, c, a, c, d].map { Map3DVertex($0, normal: normal, color: colour) }
            }
        }
        return out
    }

    private func triangles(_ corners: [Map3DVertex]) -> [[Map3DVertex]] {
        stride(from: 0, to: corners.count, by: 3).map { Array(corners[$0..<$0 + 3]) }
    }

    private func area(_ t: [Map3DVertex]) -> Float {
        (t[1].position - t[0].position).cross(t[2].position - t[0].position).length / 2
    }

    /// No triangle left flat or with a normal other than its own.
    private func assertWhole(_ corners: [Map3DVertex], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(corners.count % 3, 0, file: file, line: line)
        for t in triangles(corners) {
            XCTAssertGreaterThan(area(t), 1e-7, "a flat triangle", file: file, line: line)
            let own = (t[1].position - t[0].position).cross(t[2].position - t[0].position).normalized!
            for c in t {
                XCTAssertEqual(Map3DPoint(c.nx, c.ny, c.nz).dot(own), 1, accuracy: 1e-3, "a normal not its triangle's own", file: file, line: line)
            }
        }
    }

    func testTrianglesFallToEachShare() {
        let full = sphere()
        let count = full.count / 3
        let levels = Map3DMeshSimplifier.simplify(full, targets: [count / 2, count / 4, count / 10])
        XCTAssertEqual(levels.count, 3)
        for (level, share) in zip(levels, [2, 4, 10]) {
            XCTAssertLessThanOrEqual(level.count / 3, count / share)
            XCTAssertGreaterThan(level.count / 3, count / share - 4)
            assertWhole(level)
        }
    }

    func testNothingTurnsOver() {
        // Every triangle of a sphere still faces out, and the sphere stays
        // round: no corner moves, so all stay on it.
        for level in Map3DMeshSimplifier.simplify(sphere(), targets: [384, 154]) {
            for t in triangles(level) {
                let middle = (t[0].position + t[1].position + t[2].position) * (1.0 / 3)
                XCTAssertGreaterThan(Map3DPoint(t[0].nx, t[0].ny, t[0].nz).dot(middle), 0)
                for c in t { XCTAssertEqual(c.position.length, 1, accuracy: 1e-5) }
            }
        }
    }

    func testAStripeKeepsItsEdges() {
        let full = stripedSide()
        let level = Map3DMeshSimplifier.simplify(full, targets: [full.count / 3 / 10])[0]
        XCTAssertLessThan(level.count, full.count / 5)
        var redArea: Float = 0, whiteArea: Float = 0
        for t in triangles(level) {
            let ys = t.map(\.y)
            if t[0].color == red {
                redArea += area(t)
                XCTAssertTrue(ys.allSatisfy { $0 >= 1.5 - 1e-4 && $0 <= 2.5 + 1e-4 }, "the stripe spills: \(ys)")
            } else {
                whiteArea += area(t)
                XCTAssertTrue(ys.allSatisfy { $0 <= 1.5 + 1e-4 || $0 >= 2.5 - 1e-4 } && !(ys.contains { $0 < 1.5 - 1e-4 } && ys.contains { $0 > 2.5 + 1e-4 }),
                              "white across the stripe: \(ys)")
            }
        }
        // The band and the side are as large as they were: no edge moved.
        XCTAssertEqual(redArea, 10, accuracy: 1e-3)
        XCTAssertEqual(whiteArea, 30, accuracy: 1e-3)
        assertWhole(level)
    }

    func testTheSameModelGivesTheSameTriangles() {
        let model = Map3DModelPack.standard.models[0]
        let first = model.simplified(to: [0.5, 0.25]), second = model.simplified(to: [0.5, 0.25])
        for (a, b) in zip(first, second) {
            XCTAssertEqual(a.vertices, b.vertices)
        }
        XCTAssertNotEqual(first[0].vertices.count, first[1].vertices.count)
    }

    func testAModelKeepsItsNameBoxAndColours() {
        let pack = Map3DModelPack.unbaked
        for name in ["commuter-cab", "express-car"] {
            let model = pack.models[pack.index(of: name)!]
            let half = model.simplified(to: 0.5)
            XCTAssertEqual(half.name, model.name)
            XCTAssertEqual(half.minimum, model.minimum)
            XCTAssertEqual(half.maximum, model.maximum)
            XCTAssertLessThanOrEqual(half.triangleCount, (model.triangleCount + 1) / 2)
            XCTAssertEqual(Set(half.vertices.map(\.color)), Set(model.vertices.map(\.color)), name)
            assertWhole(half.vertices)
        }
    }

    func testAMeshKeepsItsSceneAxes() {
        var mesh = Map3DMesh()
        for t in triangles(sphere()) { mesh.appendTriangle(t) }
        let half = mesh.simplified(to: 0.5)
        XCTAssertLessThanOrEqual(half.triangleCount, mesh.triangleCount / 2)
        XCTAssertEqual(half.indices.count, half.vertices.count)
        assertWhole(half.vertices)
    }

    func testATargetPastReachGetsTheFewest() {
        // Three triangles of three colours round one corner: where seams
        // meet nothing moves, so every target gets them as they were.
        let n = Map3DPoint(0, 0, 1), blue = Map3DColor.rgb(0x1D4A9C)
        let middle = Map3DPoint(0, 0, 0)
        let rim = [Map3DPoint(1, 0, 0), Map3DPoint(-0.5, 0.87, 0), Map3DPoint(-0.5, -0.87, 0)]
        var corners: [Map3DVertex] = []
        for (k, colour) in [white, red, blue].enumerated() {
            corners += [middle, rim[k], rim[(k + 1) % 3]].map { Map3DVertex($0, normal: n, color: colour) }
        }
        XCTAssertEqual(Map3DMeshSimplifier.simplify(corners, targets: [3, 1, 0]), [corners, corners, corners])
    }
}
