@testable import GamePresentation
import XCTest

/// The trial model file (`docs/research/MESHY_TRIAL_MODEL_SPEC_2026-10-17.md`):
/// a few triangles written here byte by byte, as the `tools/` converter
/// will write them, and read back.
final class Map3DModelFileTests: XCTestCase {
    struct Triangle {
        var corners: [(Float, Float, Float)]
        var colour: UInt32
        var flags: UInt32 = 0
    }

    static let provenance = #"{"asset":{"generator":"Meshy","version":"2.0"},"extras":{"aiGenerated":true}}"#

    static func file(_ triangles: [Triangle], provenance: String = provenance, version: UInt16 = 1, count: Int? = nil) -> [UInt8] {
        var bytes = Array("M3DM".utf8)
        func put16(_ value: UInt16) { bytes += [UInt8(value & 0xFF), UInt8(value >> 8)] }
        func put32(_ value: UInt32) { bytes += (0..<4).map { UInt8((value >> ($0 * 8)) & 0xFF) } }
        let text = Array(provenance.utf8)
        put16(version)
        put16(0)
        put32(UInt32(count ?? triangles.count))
        put32(UInt32(text.count))
        bytes += text
        bytes += [UInt8](repeating: 0, count: (4 - text.count % 4) % 4)
        for triangle in triangles {
            put32(triangle.flags)
            for (x, y, z) in triangle.corners {
                put32(x.bitPattern)
                put32(y.bitPattern)
                put32(z.bitPattern)
                put32(triangle.colour)
            }
        }
        return bytes
    }

    /// A bus-like box's roof (white, up), its body side (alpha 0: the
    /// instance's colour, facing left), a headlight lit at night (facing
    /// front), and a triangle with no area, left out.
    static let sample: [Triangle] = [
        Triangle(corners: [(-6, -1.25, 3.2), (6, -1.25, 3.2), (6, 1.25, 3.2)], colour: 0xFFF2_F3F1),
        Triangle(corners: [(-6, 1.25, 0.3), (6, 1.25, 3.2), (6, 1.25, 0.3)], colour: 0x0000_0000),
        Triangle(corners: [(6, -1, 0.6), (6, -0.6, 0.6), (6, -0.6, 0.9)], colour: 0xFF99_EEFF, flags: 1),
        Triangle(corners: [(0, 0, 0), (1, 0, 0), (2, 0, 0)], colour: 0xFF00_0000),
    ]

    func testAModelReadsBackFlatWithItsColoursAndProvenance() throws {
        let file = try Map3DModelFile(decoding: Self.file(Self.sample), named: "bus")
        let model = file.model
        XCTAssertEqual(model.name, "bus")
        XCTAssertEqual(model.triangleCount, 3, "the triangle with no area is left out")
        XCTAssertEqual(file.provenance, Self.provenance)
        XCTAssertEqual(model.minimum, Map3DPoint(-6, -1.25, 0.3))
        XCTAssertEqual(model.maximum, Map3DPoint(6, 1.25, 3.2))
        XCTAssertEqual(model.length, 12)

        let roof = model.vertices[0..<3], side = model.vertices[3..<6], light = model.vertices[6..<9]
        for vertex in roof {
            XCTAssertEqual(vertex.nz, 1, accuracy: 1e-6, "the roof faces up")
            XCTAssertEqual(vertex.color, 0xFFF2_F3F1)
            XCTAssertEqual(vertex.layer, Map3DVertex.plain)
        }
        for vertex in side {
            XCTAssertEqual(vertex.ny, 1, accuracy: 1e-6, "the side faces left, out of the bus")
            XCTAssertEqual(vertex.color >> 24, 0, "alpha 0: the instance's colour shows")
        }
        for vertex in light {
            XCTAssertEqual(vertex.nx, 1, accuracy: 1e-6, "the headlight faces the front")
            XCTAssertTrue(vertex.glows)
        }
    }

    func testTheSameFileReadsTheSameEveryTime() throws {
        let bytes = Self.file(Self.sample)
        XCTAssertEqual(try Map3DModelFile(decoding: bytes, named: "bus").model.vertices,
                       try Map3DModelFile(decoding: Data(bytes), named: "bus").model.vertices)
    }

    func testTheNodeConverterFixtureReadsWithItsTextureAndFront() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let url = root.appendingPathComponent("tools/glb-to-m3dmodel/fixtures/tiny.m3dmodel")
        let decoded = try Map3DModelFile(decoding: Data(contentsOf: url), named: "fixture")
        XCTAssertEqual(decoded.model.triangleCount, 2)
        XCTAssertEqual(decoded.model.length, 12)
        XCTAssertEqual(decoded.model.vertices[0].color, 0xFFC8_5A14, "blue PNG becomes a flat color")
        XCTAssertEqual(decoded.model.vertices[0].x, 6, "-x GLB front becomes +x")
        XCTAssertEqual(decoded.model.vertices[0].z, 0, "the model rests on the ground")
        XCTAssertTrue(decoded.model.vertices[3].glows, "the headlight keeps its night flag")
        XCTAssertTrue(decoded.provenance.contains("Meshy fixture"))
    }

    func testTheConvertedCityBusReadsWithEightColorsAndItsTaskRecord() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let url = root.appendingPathComponent("docs/art/meshy-city-bus-2026-10-18/city-bus.m3dmodel")
        let decoded = try Map3DModelFile(decoding: Data(contentsOf: url), named: "city-bus")
        XCTAssertEqual(decoded.model.triangleCount, 1543)
        XCTAssertEqual(decoded.model.length, 12, accuracy: 0.001)
        XCTAssertEqual(Set(decoded.model.vertices.map(\.color)).count, 8)
        XCTAssertTrue(decoded.model.vertices.contains { $0.color >> 24 == 0 }, "body paint can use each instance's stripe")
        XCTAssertTrue(decoded.provenance.contains("01a14cae-0304-73a5-acee-8a7abb7122e3"))
        XCTAssertTrue(decoded.provenance.contains("43b59d1958bb2beb5ae07db491018fadd2545355f787664db7d9b4986a70126d"))
    }

    func testAnythingElseIsRefused() {
        func refusal(_ bytes: [UInt8]) -> Map3DModelFile.Error? {
            do {
                _ = try Map3DModelFile(decoding: bytes, named: "bus")
                return nil
            } catch {
                return error
            }
        }
        let good = Self.file(Self.sample)
        XCTAssertEqual(refusal([]), .notAModel)
        XCTAssertEqual(refusal(Array("GLTF".utf8) + good.dropFirst(4)), .notAModel)
        XCTAssertEqual(refusal(Self.file(Self.sample, version: 2)), .unsupportedVersion(2))
        XCTAssertEqual(refusal(Array(good.dropLast())), .wrongSize(expected: good.count, actual: good.count - 1))
        XCTAssertEqual(refusal(good + [0]), .wrongSize(expected: good.count, actual: good.count + 1))
        XCTAssertEqual(refusal(Self.file([], count: Map3DModelFile.maximumTriangles + 1)),
                       .tooManyTriangles(Map3DModelFile.maximumTriangles + 1))
        XCTAssertEqual(refusal(Self.file(Self.sample, provenance: "")), .noProvenance, "a generated model keeps its record")
        XCTAssertEqual(refusal(Self.file(Self.sample, provenance: "   ")), .noProvenance)
        var flagged = Self.sample
        flagged[0].flags = 2
        XCTAssertEqual(refusal(Self.file(flagged)), .unknownFlags(2))
        var broken = Self.sample
        broken[1].corners[2] = (.nan, 0, 0)
        XCTAssertEqual(refusal(Self.file(broken)), .notFinite)
    }
}
