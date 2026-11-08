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

    func testTheStaticMeshoptConverterFixtureReadsWithFixedColorsAndSource() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let url = root.appendingPathComponent("tools/glb-to-m3dmodel/fixtures/static.m3dmodel")
        let decoded = try Map3DModelFile(decoding: Data(contentsOf: url), named: "static-fixture")
        XCTAssertEqual(decoded.model.triangleCount, 2)
        XCTAssertEqual(decoded.model.minimum, Map3DPoint(-0.5, -2, 0))
        XCTAssertEqual(decoded.model.maximum, Map3DPoint(0.5, 2, 6))
        XCTAssertEqual(decoded.model.vertices[0].color, 0xFFCC_CCCC, "light building surfaces keep their own color")
        XCTAssertTrue(decoded.model.vertices.allSatisfy { $0.color >> 24 == 255 })
        XCTAssertTrue(decoded.model.vertices[3].glows, "named lamps keep the existing glow flag")
        XCTAssertTrue(decoded.provenance.contains("non-ai"))
        XCTAssertTrue(decoded.provenance.contains("fixture-v1"))
        XCTAssertTrue(decoded.provenance.contains("sha256"))
        XCTAssertFalse(decoded.provenance.contains("aiGenerated"))
        XCTAssertFalse(decoded.provenance.contains("tasks"))
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
        XCTAssertEqual(refusal(Self.file(Self.sample, version: 3)), .unsupportedVersion(3))
        XCTAssertEqual(refusal(Self.file(Self.sample, version: 0)), .unsupportedVersion(0))
        XCTAssertEqual(refusal(Array(good.dropLast())), .wrongSize(expected: good.count, actual: good.count - 1))
        XCTAssertEqual(refusal(good + [0]), .wrongSize(expected: good.count, actual: good.count + 1))
        XCTAssertEqual(refusal(Self.file([], count: Map3DModelFile.maximumTriangles + 1)),
                       .tooManyTriangles(Map3DModelFile.maximumTriangles + 1))
        XCTAssertEqual(refusal(Self.file(Self.sample, provenance: "")), .noProvenance, "a generated model keeps its record")
        XCTAssertEqual(refusal(Self.file(Self.sample, provenance: "   ")), .noProvenance)
        var flagged = Self.sample
        flagged[0].flags = 8
        XCTAssertEqual(refusal(Self.file(flagged)), .unknownFlags(8))
        flagged[0].flags = 6
        XCTAssertEqual(refusal(Self.file(flagged)), .unknownFlags(6), "glass and stainless at once")
        flagged[0].flags = 9
        XCTAssertEqual(refusal(Self.file(flagged)), .unknownFlags(9), "version 1 has no texture to paint with")
        // Decision 450: a train's glass, lit glass and stainless read back.
        for (bits, layer) in [(UInt32(2), Map3DVertex.trainGlass), (3, Map3DVertex.trainGlassLit), (4, Map3DVertex.trainSteel)] {
            flagged[0].flags = bits
            XCTAssertEqual(try Map3DModelFile(decoding: Self.file(flagged), named: "bus").model.vertices.first?.layer, layer)
        }
        var broken = Self.sample
        broken[1].corners[2] = (.nan, 0, 0)
        XCTAssertEqual(refusal(Self.file(broken)), .notFinite)
    }

    /// A file of no triangles, or of only ones with no area, has nothing
    /// to draw and no size: refused, as the converter refuses it, rather
    /// than read with endless bounds.
    func testAModelWithNothingToDrawIsRefused() {
        let flat = Triangle(corners: [(0, 0, 0), (1, 0, 0), (2, 0, 0)], colour: 0xFF00_0000)
        for triangles in [[], [flat]] {
            XCTAssertThrowsError(try Map3DModelFile(decoding: Self.file(triangles), named: "empty")) { error in
                XCTAssertEqual(error as? Map3DModelFile.Error, .nothingToDraw)
            }
        }
    }
}

/// Decision 653: a model painted by a texture of its own (`.m3dmodel`
/// version 2), written here byte by byte as `tools/glb-to-m3dmodel`'s
/// `--textured` writes it. The texture is a few bytes that start as a PNG
/// does: the file only keeps them; Metal's loader reads them in the app.
final class Map3DTexturedModelFileTests: XCTestCase {
    struct Corner {
        var position: (Float, Float, Float)
        var normal: (Float, Float, Float)
        var uv: (Float, Float)
    }

    struct Triangle {
        var corners: [Corner]
        var colour: UInt32 = 0xFFFF_FFFF
        var flags: UInt32 = 8
    }

    static let provenance = #"{"asset":{"generator":"test"},"source":"made in the test"}"#
    static let png: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3]

    static func file(_ triangles: [Triangle], provenance: String = provenance, kind: UInt32 = 1,
                     texture: [UInt8] = png, count: Int? = nil) -> [UInt8] {
        var bytes = Array("M3DM".utf8)
        func put16(_ value: UInt16) { bytes += [UInt8(value & 0xFF), UInt8(value >> 8)] }
        func put32(_ value: UInt32) { bytes += (0..<4).map { UInt8((value >> ($0 * 8)) & 0xFF) } }
        func pad() { bytes += [UInt8](repeating: 0, count: (4 - bytes.count % 4) % 4) }
        let text = Array(provenance.utf8)
        put16(2)
        put16(0)
        put32(UInt32(count ?? triangles.count))
        put32(UInt32(text.count))
        put32(kind)
        put32(UInt32(texture.count))
        bytes += text
        pad()
        bytes += texture
        pad()
        for triangle in triangles {
            put32(triangle.flags)
            for corner in triangle.corners {
                for value in [corner.position.0, corner.position.1, corner.position.2,
                              corner.normal.0, corner.normal.1, corner.normal.2, corner.uv.0, corner.uv.1] {
                    put32(value.bitPattern)
                }
                put32(triangle.colour)
            }
        }
        return bytes
    }

    /// A rounded roof's two halves, each corner with its own normal (one
    /// left zero, to take the flat one), a lit sign, and an untextured
    /// stainless panel.
    static let sample: [Triangle] = [
        Triangle(corners: [Corner(position: (0, -1, 3), normal: (0, -0.6, 0.8), uv: (0, 0)),
                           Corner(position: (4, -1, 3), normal: (0, -0.6, 0.8), uv: (1, 0)),
                           Corner(position: (4, 0, 3.4), normal: (0, 0, 0), uv: (1, 0.5))]),
        Triangle(corners: [Corner(position: (0, 0, 0), normal: (1, 0, 0), uv: (0.25, 0.75)),
                           Corner(position: (0, 1, 0), normal: (1, 0, 0), uv: (0.5, 0.75)),
                           Corner(position: (0, 1, 1), normal: (1, 0, 0), uv: (0.5, 1))], colour: 0xFF80_8080, flags: 9),
        Triangle(corners: [Corner(position: (4, 1, 0), normal: (0, 1, 0), uv: (0.9, 0.9)),
                           Corner(position: (0, 1, 0), normal: (0, 1, 0), uv: (0.9, 0.9)),
                           Corner(position: (4, 1, 2), normal: (0, 1, 0), uv: (0.9, 0.9))], flags: 4),
    ]

    func testATexturedModelReadsBackWithItsUVsNormalsAndTexture() throws {
        let file = try Map3DModelFile(decoding: Self.file(Self.sample), named: "car")
        let model = file.model
        XCTAssertEqual(file.provenance, Self.provenance)
        XCTAssertEqual(model.triangleCount, 3)
        XCTAssertEqual(model.texture, Map3DModelTexture(kind: .png, bytes: Self.png))
        XCTAssertEqual(model.minimum, Map3DPoint(0, -1, 0))
        XCTAssertEqual(model.maximum, Map3DPoint(4, 1, 3.4))

        let roof = Array(model.vertices[0..<3]), sign = Array(model.vertices[3..<6]), panel = Array(model.vertices[6..<9])
        XCTAssertEqual(roof.map(\.layer), [Map3DVertex.modelTexture, Map3DVertex.modelTexture, Map3DVertex.modelTexture])
        XCTAssertEqual(roof.map(\.u), [0, 1, 1])
        XCTAssertEqual(roof.map(\.v), [0, 0, 0.5])
        XCTAssertEqual(roof[0].ny, -0.6, accuracy: 1e-6)
        XCTAssertEqual(roof[0].nz, 0.8, accuracy: 1e-6)
        // The zero normal takes the triangle's flat one.
        let flat = (Map3DPoint(4, -1, 3) - Map3DPoint(0, -1, 3)).cross(Map3DPoint(4, 0, 3.4) - Map3DPoint(0, -1, 3)).normalized!
        XCTAssertEqual(roof[2].nx, flat.x, accuracy: 1e-6)
        XCTAssertEqual(roof[2].ny, flat.y, accuracy: 1e-6)
        XCTAssertEqual(roof[2].nz, flat.z, accuracy: 1e-6)
        XCTAssertTrue(roof.allSatisfy { $0.isModelTextured && !$0.glows })

        XCTAssertTrue(sign.allSatisfy { $0.layer == Map3DVertex.modelTextureLit && $0.isModelTextured && $0.glows })
        XCTAssertEqual(sign.map(\.color), [0xFF80_8080, 0xFF80_8080, 0xFF80_8080])

        XCTAssertTrue(panel.allSatisfy { $0.layer == Map3DVertex.trainSteel && !$0.isModelTextured })
        XCTAssertTrue(panel.allSatisfy { $0.u == 0 && $0.v == 0 }, "an untextured triangle keeps no u, v")
    }

    func testAFileOfNoTextureReadsWhenNothingIsPaintedByIt() throws {
        let unpainted = Self.sample.map { triangle -> Triangle in
            var triangle = triangle
            triangle.flags &= ~8
            return triangle
        }
        let model = try Map3DModelFile(decoding: Self.file(unpainted, kind: 0, texture: []), named: "car").model
        XCTAssertNil(model.texture)
        XCTAssertEqual(model.vertices[0].layer, Map3DVertex.plain)
        XCTAssertEqual(model.vertices[3].layer, Map3DVertex.glowing)
    }

    func testEveryKindOfTextureIsKeptAsItsFileIs() throws {
        let jpeg: [UInt8] = [0xFF, 0xD8, 0xFF, 0xE0, 0]
        let ktx: [UInt8] = [0xAB, 0x4B, 0x54, 0x58, 0x20, 0x31, 0x31, 0xBB, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3, 4]
        for (kind, bytes) in [(Map3DModelTexture.Kind.jpeg, jpeg), (.ktx, ktx)] {
            let model = try Map3DModelFile(decoding: Self.file(Self.sample, kind: kind.rawValue, texture: bytes), named: "car").model
            XCTAssertEqual(model.texture?.kind, kind)
            XCTAssertEqual(model.texture?.bytes, bytes)
        }
    }

    func testAnythingElseIsRefused() {
        func refusal(_ bytes: [UInt8]) -> Map3DModelFile.Error? {
            do {
                _ = try Map3DModelFile(decoding: bytes, named: "car")
                return nil
            } catch {
                return error
            }
        }
        let good = Self.file(Self.sample)
        XCTAssertEqual(refusal(Array(good.dropLast())), .wrongSize(expected: good.count, actual: good.count - 1))
        XCTAssertEqual(refusal(Array(good.prefix(20))), .wrongSize(expected: 24, actual: 20))
        XCTAssertEqual(refusal(Self.file([], count: Map3DModelFile.maximumTriangles + 1)), .tooManyTriangles(Map3DModelFile.maximumTriangles + 1))
        XCTAssertEqual(refusal(Self.file(Self.sample, provenance: " ")), .noProvenance)
        XCTAssertEqual(refusal(Self.file(Self.sample, kind: 4)), .badTexture, "an unknown kind")
        XCTAssertEqual(refusal(Self.file(Self.sample, kind: 3)), .badTexture, "PNG bytes called KTX")
        XCTAssertEqual(refusal(Self.file(Self.sample, kind: 1, texture: [0x89, 0x50])), .badTexture, "too short to be a PNG")
        XCTAssertEqual(refusal(Self.file(Self.sample, kind: 0, texture: [])), .noTexture)
        var flagged = Self.sample
        for flags: UInt32 in [10, 12, 16] {
            flagged[0].flags = flags
            XCTAssertEqual(refusal(Self.file(flagged)), .unknownFlags(flags))
        }
        var broken = Self.sample
        broken[0].corners[1].uv = (.infinity, 0)
        XCTAssertEqual(refusal(Self.file(broken)), .notFinite)
        broken = Self.sample
        broken[0].corners[1].normal = (.nan, 0, 0)
        XCTAssertEqual(refusal(Self.file(broken)), .notFinite)
        let flat = Triangle(corners: [Corner(position: (0, 0, 0), normal: (0, 0, 1), uv: (0, 0)),
                                      Corner(position: (1, 0, 0), normal: (0, 0, 1), uv: (0, 0)),
                                      Corner(position: (2, 0, 0), normal: (0, 0, 1), uv: (0, 0))])
        XCTAssertEqual(refusal(Self.file([flat])), .nothingToDraw)
    }

    /// `tools/glb-to-m3dmodel/textured.mjs` on its own tiny GLB: what the
    /// node writer writes, the app reads.
    func testTheNodeWritersTexturedFixtureReads() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let url = root.appendingPathComponent("tools/glb-to-m3dmodel/fixtures/tiny-textured.m3dmodel")
        let decoded = try Map3DModelFile(decoding: Data(contentsOf: url), named: "fixture")
        let model = decoded.model
        XCTAssertEqual(model.triangleCount, 2)
        XCTAssertEqual(model.length, 12)
        XCTAssertEqual(model.texture?.kind, .png)
        XCTAssertEqual(model.vertices[0].layer, Map3DVertex.modelTexture)
        XCTAssertEqual(model.vertices[0].color, 0xFFFF_FFFF, "the texture shows untinted")
        XCTAssertEqual(model.vertices[0].x, 6, "-x GLB front becomes +x")
        XCTAssertEqual(model.vertices.map(\.u)[0..<3], [0, 1, 1])
        XCTAssertEqual(model.vertices[3].layer, Map3DVertex.glowing, "the headlight, untextured, keeps its night flag")
        XCTAssertTrue(decoded.provenance.contains("Meshy fixture"))
    }

    func testATextureTooLargeIsRefused() {
        XCTAssertNil(Map3DModelTexture(kind: .png, bytes: Self.png + [UInt8](repeating: 0, count: Map3DModelTexture.maximumBytes)))
        XCTAssertNotNil(Map3DModelTexture(kind: .png, bytes: Self.png))
    }
}

/// The train-model tool's `--night-lights` exporter reads every lit car back
/// through ``Map3DModelFile`` and stops when a normal is off by 5e-3 or more;
/// a lamp is a small triangle, so its normal, recomputed from the file's
/// corners, drifts more than a car panel's. It once drifted by 1e-3 and the
/// tool died on its own check (the crash report then took minutes to print).
final class TrainNightLightsReadBackTests: XCTestCase {
    // The file keeps no normals (the reader recomputes them from the corners), so a lamp's are only a direction.
    func testEveryLampNormalSurvivesTheNativeFileWithinTheExportersLimit() {
        let pack = Map3DModelPack.standard
        var checked = 0
        for car in pack.lights.values {
            for lamps in [car.front.head, car.front.tail, car.back.head, car.back.tail] {
                for start in stride(from: 0, to: lamps.count - 2, by: 3) {
                    let t = Array(lamps[start..<start + 3])
                    guard let normal = (t[1].position - t[0].position).cross(t[2].position - t[0].position).normalized else { continue }
                    for v in t {
                        XCTAssertEqual(v.nx, normal.x, accuracy: 0.005)
                        XCTAssertEqual(v.ny, normal.y, accuracy: 0.005)
                        XCTAssertEqual(v.nz, normal.z, accuracy: 0.005)
                    }
                    checked += 1
                }
            }
        }
        XCTAssertGreaterThan(checked, 0)
    }
}
