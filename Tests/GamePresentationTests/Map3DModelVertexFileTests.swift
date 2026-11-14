@testable import GamePresentation
import Foundation
import XCTest

/// Decision 750: the pack's vertices written to a mapped file read back
/// as they were, model by model, so a model put on the GPU from it the
/// first time it is drawn looks the same as one put there from the pack.
final class Map3DModelVertexFileTests: XCTestCase {
    func testEveryModelReadsBackAsItWas() throws {
        let pack = Map3DModelPack.standard
        let directory = FileManager.default.temporaryDirectory
        let file = try XCTUnwrap(Map3DModelVertexFile.write(pack, in: directory))
        XCTAssertEqual(file.count, pack.models.count)
        XCTAssertEqual(file.byteCount, pack.models.reduce(0) { $0 + $1.vertices.count * MemoryLayout<Map3DVertex>.stride })
        for index in pack.models.indices {
            let model = pack.models[index]
            file.withBytes(of: index) { bytes in
                XCTAssertEqual(bytes.count, model.vertexCount * MemoryLayout<Map3DVertex>.stride, model.name)
            }
            XCTAssertEqual(file.vertices(of: index), model.vertices, model.name)
        }
    }

    func testTheFileIsGoneOnceMapped() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("map3d-vertex-file-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let pack = Map3DModelPack(models: Array(Map3DModelPack.standard.models.prefix(3)))
        let file = try XCTUnwrap(Map3DModelVertexFile.write(pack, in: directory))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), [])
        // The mapping still holds the bytes.
        XCTAssertEqual(file.vertices(of: 2), pack.models[2].vertices)
    }

    func testNoFileWhereItCannotBeWritten() {
        let nowhere = URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)")
        XCTAssertNil(Map3DModelVertexFile.write(Map3DModelPack(models: Array(Map3DModelPack.standard.models.prefix(1))), in: nowhere))
    }
}
