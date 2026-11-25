import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// `tools/layout-overview/`: writes the meshes the game draws for the
/// player's school and hospital on their plots and for the small station
/// kinds, for `render.py` to draw with a depth buffer. Does nothing unless
/// `LAYOUT_OVERVIEW_DIR` names a directory (it is a tool, not a check).
final class LayoutOverviewDumpTests: XCTestCase {
    /// The mesh as `render.py` reads it: little-endian counts, each vertex
    /// x, y (up), z, normal, colour (`Map3DVertex.color`), layer, then the
    /// indices; then the ground pad's colour (0 for none) and the plot's
    /// side in metres.
    private func write(_ mesh: Map3DMesh, pad: UInt32?, side: Float, to url: URL) throws {
        var data = Data()
        func put<T>(_ value: T) { withUnsafeBytes(of: value) { data.append(contentsOf: $0) } }
        put(UInt32(mesh.vertices.count))
        put(UInt32(mesh.indices.count))
        for v in mesh.vertices {
            for value in [v.x, v.y, v.z, v.nx, v.ny, v.nz] { put(value) }
            put(v.color)
            put(v.layer)
        }
        for index in mesh.indices { put(index) }
        put(pad ?? 0)
        put(side)
        try data.write(to: url)
    }

    private func station(_ profile: Map3DStationKit.Profile, tier: Int) -> Map3DStationKit.Station {
        Map3DStationKit.Station(id: "s", name: "s", system: "player", latitude: 0, longitude: 0, lines: [],
                                profile: profile, tier: tier, seed: 0, planned: false, isLandmark: false)
    }

    func testWriteTheMeshes() throws {
        guard let path = ProcessInfo.processInfo.environment["LAYOUT_OVERVIEW_DIR"] else { throw XCTSkip("LAYOUT_OVERVIEW_DIR not set") }
        let directory = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for kind in [PlacedBuildingKind.school, .hospital] {
            // 3,072 world units are a school's 46 m (Map3DPlayerSchoolHospitalTests).
            let side = Float(kind.side) * 46 / 3_072
            for (look, layout) in try XCTUnwrap(Map3DScene.Builder.placedKitLayouts[kind]).enumerated() {
                try write(layout.mesh, pad: layout.pad, side: side, to: directory.appendingPathComponent("\(kind)-\(look).bin"))
            }
        }
        let stations: [(String, Map3DStationKit.Profile, Int, StationExpansion?, Bool)] = [
            ("hk-2f", .regional, 1, nil, true), ("hk-2f-concourse", .regional, 1, .concourse, true),
            ("hk-2f-hall", .regional, 1, .hall, true), ("hk-1f-hall", .regional, 3, .hall, true),
            ("hk-halt-concourse", .halt, 3, .concourse, true), ("tw-2f-hall", .regional, 1, .hall, false),
        ]
        for (name, profile, tier, expansion, hongKong) in stations {
            var kit = StationKitBuilder()
            kit.hongKong = hongKong
            kit.genericHouse(station(profile, tier: tier), expansion: expansion)
            try write(kit.mesh, pad: nil, side: 0, to: directory.appendingPathComponent("station-\(name).bin"))
        }
    }
}
