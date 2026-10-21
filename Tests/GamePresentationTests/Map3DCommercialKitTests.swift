import Foundation
@testable import GamePresentation
import XCTest

final class Map3DCommercialKitTests: XCTestCase {
    func testCatalogContainsDistinctModelsInThreeCategories() {
        let parts = Map3DCommercialKit.Part.allCases
        XCTAssertEqual(parts.count, 36)
        XCTAssertEqual(Set(parts.map(\.id)).count, 36)
        for c in Map3DCommercialKit.Category.allCases {
            XCTAssertEqual(parts.filter { $0.category == c }.count, 12)
        }
        let models = parts.map(Map3DCommercialKit.model(for:))
        for i in models.indices {
            for j in 0..<i {
                XCTAssertNotEqual(models[i].vertices, models[j].vertices, parts[i].id)
            }
        }
    }

    func testFiniteOpaqueClosedUndersidesWithinNativeBudget() {
        let models = Map3DCommercialKit.Part.allCases.map(Map3DCommercialKit.model(for:)) +
                     Map3DCommercialKit.Example.allCases.map(Map3DCommercialKit.model(for:))
        for m in models {
            XCTAssertGreaterThan(m.triangleCount, 0, m.name)
            XCTAssertLessThanOrEqual(m.triangleCount, 15000, m.name)
            XCTAssertTrue(m.vertices.contains { $0.nz < -0.5 }, m.name)
            for v in m.vertices {
                XCTAssertTrue([v.x, v.y, v.z, v.nx, v.ny, v.nz].allSatisfy(\.isFinite), m.name)
                XCTAssertEqual(v.color >> 24, 255, m.name)
                XCTAssertEqual(v.nx * v.nx + v.ny * v.ny + v.nz * v.nz, 1, accuracy: 0.0001, m.name)
            }
        }
    }

    func testInstallationPlanesAndConnectorNormals() {
        for p in Map3DCommercialKit.Part.allCases {
            let m = Map3DCommercialKit.model(for: p)
            switch p.mount {
            case .ground:
                XCTAssertEqual(m.minimum.z, 0, accuracy: 0.04, p.id + " ground offset")
            case .wall:
                XCTAssertEqual(m.minimum.x, 0, accuracy: 0.0001, p.id + " wall offset")
            case .ceiling:
                XCTAssertEqual(m.maximum.z, 0, accuracy: 0.0001, p.id + " ceiling offset")
            }
            for c in p.connectors {
                XCTAssertEqual(c.normal.dot(c.normal), 1, accuracy: 0.0001)
            }
        }
    }

    func testBuildingWindowsHaveBackingWithinFrameDepth() {
        for p in Map3DCommercialKit.Part.allCases where p.category == .building {
            let m = Map3DCommercialKit.model(for: p)
            var checked = 0
            for i in stride(from: 0, to: m.vertices.count, by: 3) {
                let t = Array(m.vertices[i..<i + 3])
                guard t.allSatisfy({ $0.color == Map3DPalette.glazing && $0.nx > 0.8 }) else { continue }
                let c = t.reduce(Map3DPoint.zero) { $0 + Map3DPoint($1.x, $1.y, $1.z) * (1.0 / 3.0) }
                XCTAssertLessThan(ray(from: c + Map3DPoint(0.001, 0, 0), vertices: m.vertices), 0.12, p.id)
                checked += 1
            }
            XCTAssertGreaterThan(checked, 0, p.id)
        }
    }

    func testTransitFeederBusDimensionsAndDoors() throws {
        let bus = Map3DCommercialKit.Part.transitFeederBus
        let m = Map3DCommercialKit.model(for: bus)
        // Length around 10.4m, width around 2.5m, height around 3.2m
        XCTAssertEqual(m.maximum.x - m.minimum.x, 10.4, accuracy: 0.6)
        XCTAssertEqual(m.maximum.y - m.minimum.y, 2.5, accuracy: 0.4)
        XCTAssertGreaterThan(m.maximum.z, 2.8)
        XCTAssertEqual(m.minimum.z, 0, accuracy: 0.04)

        let frontDoor = try XCTUnwrap(bus.connectors.first { $0.name == "frontDoor" })
        let rearDoor = try XCTUnwrap(bus.connectors.first { $0.name == "rearDoor" })
        XCTAssertGreaterThan(frontDoor.position.x, rearDoor.position.x)
        XCTAssertEqual(frontDoor.normal, Map3DPoint(0, -1, 0))
    }

    func testOnDemandPackDeterminism() {
        let a = Map3DCommercialKit.model(for: .departmentStore)
        _ = Map3DCommercialKit.model(for: .transitFeederBus)
        XCTAssertEqual(a.vertices, Map3DCommercialKit.model(for: .departmentStore).vertices)

        let pack = Map3DModelPack(commercialKit: [.departmentStore, .transitFeederBus])
        XCTAssertEqual(pack.models.count, 2)
        XCTAssertEqual(pack.index(of: "commercial-transitFeederBus"), 1)
    }

    private func ray(from origin: Map3DPoint, vertices: [Map3DVertex]) -> Float {
        let direction = Map3DPoint(-1, 0, 0)
        var result = Float.infinity
        for i in stride(from: 0, to: vertices.count, by: 3) {
            if vertices[i].color == Map3DPalette.glazing { continue }
            let p = vertices[i..<i + 3].map { Map3DPoint($0.x, $0.y, $0.z) }
            let e = p[1] - p[0], f = p[2] - p[0]
            let h = direction.cross(f)
            let det = e.dot(h)
            if abs(det) < 0.000001 { continue }
            let s = origin - p[0]
            let u = s.dot(h) / det
            let q = s.cross(e)
            let v = direction.dot(q) / det
            let d = f.dot(q) / det
            if u >= -0.00001 && v >= -0.00001 && u + v <= 1.00001 && d > 0.00001 {
                result = min(result, d)
            }
        }
        return result
    }
}
