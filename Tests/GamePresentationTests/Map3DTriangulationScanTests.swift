import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

final class Map3DTriangulationScanTests: XCTestCase {
    func testScanFootprints() throws {
        guard ProcessInfo.processInfo.environment["TRI_SCAN"] != nil else { throw XCTSkip("TRI_SCAN") }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let tiles = try FootprintTiles(data: Data(contentsOf: root.appendingPathComponent("RailwayGameApp/Resources/BaseMap/taiwan_buildings.pmtiles"), options: .alwaysMapped))
        func tx(_ lon: Double) -> Int { Int((lon + 180) / 360 * 65536) }
        func ty(_ lat: Double) -> Int { let r = lat * .pi / 180; return Int((1 - log(tan(r) + 1 / cos(r)) / .pi) / 2 * 65536) }
        var buildings = 0, bad = 0, transportBad = 0
        var worst: [(ratio: Double, x: Int, y: Int, use: Int, rings: Int, pts: Int, net: Double)] = []
        for y in ty(26.5)...ty(21.8) {
            for x in tx(118.1)...tx(122.1) {
                guard let bytes = try? tiles.archive.tile(zoom: 16, x: x, y: y), let decoded = try? Map3DFootprints.decode(bytes) else { continue }
                for b in decoded {
                    buildings += 1
                    let rings = b.rings.map { $0.map { (x: Double($0.x), y: Double($0.y)) } }
                    let pts = rings.flatMap { $0 }
                    func area(_ r: [(x: Double, y: Double)]) -> Double {
                        var s = 0.0; var p = r.last!
                        for q in r { s += p.x * q.y - q.x * p.y; p = q }
                        return s / 2
                    }
                    guard let outer = rings.first, outer.count >= 3 else { continue }
                    let net = abs(area(outer)) - rings.dropFirst().reduce(0) { $0 + abs(area($1)) }
                    let t = Earcut.triangulate(rings)
                    var sum = 0.0
                    for i in stride(from: 0, to: t.count, by: 3) {
                        let a = pts[t[i]], bb = pts[t[i + 1]], c = pts[t[i + 2]]
                        sum += abs((bb.x - a.x) * (c.y - a.y) - (c.x - a.x) * (bb.y - a.y)) / 2
                    }
                    if sum > net * 1.02 + 4 {
                        bad += 1
                        if b.use == 13 { transportBad += 1 }
                        worst.append((sum / max(net, 1), x, y, b.use, rings.count, pts.count, net))
                    }
                }
            }
        }
        worst.sort { $0.ratio > $1.ratio }
        print("SCAN buildings \(buildings) bad \(bad) transport \(transportBad)")
        for w in worst.prefix(40) { print("SCAN", w) }
    }
}
