import Foundation
@testable import GamePresentation
import XCTest

/// Decision 895: the registered landmarks (``Map3DLandmarkRegistry``), each
/// in its own files, checked here so no test is edited for a new one.
final class Map3DLandmarkRegistryTests: XCTestCase {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    static let locks = root.appendingPathComponent("tools/landmarks/locks")

    /// Every `Map3DLandmarkRegistration(id: …)` in the sources is in the
    /// list once, every one in the list has its lock file and no lock file
    /// is left without its landmark (a landmark whose line was forgotten,
    /// or a line two branches both added); no id is a pre-registry
    /// landmark's.
    func testTheListIsEveryRegistrationInTheSources() throws {
        let sources = Self.root.appendingPathComponent("Sources/GamePresentation")
        var declared: [String] = []
        let pattern = try NSRegularExpression(pattern: #"Map3DLandmarkRegistration\(\s*id:\s*"([^"]+)""#)
        for name in try FileManager.default.contentsOfDirectory(atPath: sources.path) where name.hasSuffix(".swift") {
            let text = try String(contentsOf: sources.appendingPathComponent(name), encoding: .utf8)
            for match in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                declared.append(String(text[Range(match.range(at: 1), in: text)!]))
            }
        }
        let listed = Map3DLandmarkRegistry.landmarks.map(\.id)
        XCTAssertEqual(listed.count, Set(listed).count, "a landmark listed twice: \(listed)")
        XCTAssertEqual(Set(declared), Set(listed),
                       "add `<Type>.registration,` to Map3DLandmarkRegistryList.swift for each of \(Set(declared).subtracting(listed).sorted())")
        let files = try FileManager.default.contentsOfDirectory(atPath: Self.locks.path).filter { $0.hasSuffix(".json") }
        XCTAssertEqual(Set(files), Set(listed.map { $0 + ".json" }), "one lock file a registered landmark")
        XCTAssertTrue(Set(listed).isDisjoint(with: Map3DHongKongLandmark.allCases.map(\.rawValue)))
        for landmark in Map3DLandmarkRegistry.landmarks {
            XCTAssertEqual(Map3DLandmarkRegistry.registration(landmark.id)?.id, landmark.id)
            XCTAssertEqual(Set(landmark.encoded.keys), [landmark.id, landmark.id + "-far"], "\(landmark.id): its near and far models only")
        }
    }

    /// Every model decodes, near and far, as tall and wide as its
    /// registration says (half a metre either way), standing on its foot
    /// with its footprint's middle at the origin; the far model has at most
    /// half the near one's triangles and no colour it lacks; each stays
    /// within one model's budget, and each map's landmarks within one.
    func testTheModels() {
        var maps: [String: Int] = [:]
        for landmark in Map3DLandmarkRegistry.landmarks {
            let id = landmark.id
            let near = landmark.model(full: true), far = landmark.model(full: false)
            for model in [near, far] {
                XCTAssertFalse(model.vertices.isEmpty, "\(id)")
                guard !model.vertices.isEmpty else { continue }
                let xs = model.vertices.map(\.x), ys = model.vertices.map(\.y), zs = model.vertices.map(\.z)
                XCTAssertEqual(xs.max()! - xs.min()!, landmark.size.x, accuracy: 0.5, "\(id) east")
                XCTAssertEqual(ys.max()! - ys.min()!, landmark.size.y, accuracy: 0.5, "\(id) north")
                XCTAssertEqual(zs.max()!, landmark.size.z, accuracy: 0.5, "\(id) height")
                XCTAssertEqual(zs.min()!, 0, accuracy: 0.01, "\(id) foot")
                XCTAssertEqual(abs(xs.max()! + xs.min()!) / 2, 0, accuracy: 0.5, "\(id) centred east")
                XCTAssertEqual(abs(ys.max()! + ys.min()!) / 2, 0, accuracy: 0.5, "\(id) centred north")
            }
            XCTAssertLessThanOrEqual(near.indices.count / 3, 15_000, "\(id)")
            XCTAssertLessThanOrEqual(far.indices.count * 2, near.indices.count + 3, "\(id) far")
            XCTAssertTrue(Set(far.vertices.map(\.color)).isSubset(of: Set(near.vertices.map(\.color))), "\(id) far colours")
            XCTAssertEqual(Set(near.vertices.map(\.color)), Set(landmark.palette), "\(id): every palette colour used, no other")
            XCTAssertTrue(landmark.glass.union(landmark.bandedGlass).allSatisfy(landmark.palette.indices.contains), "\(id) glass")
            maps[landmark.map, default: 0] += near.indices.count / 3
        }
        for (map, triangles) in maps {
            XCTAssertLessThanOrEqual(triangles, 60_000, map)
        }
    }

    /// The encoding is read whole or not at all.
    func testABrokenMeshIsRefused() throws {
        let landmark = try XCTUnwrap(Map3DLandmarkRegistry.landmarks.first)
        let text = try XCTUnwrap(landmark.encoded[landmark.id])
        let bytes = try Array(XCTUnwrap(Data(base64Encoded: text, options: .ignoreUnknownCharacters)))
        func decoded(_ bytes: [UInt8], palette: [UInt32] = landmark.palette) -> LandmarkMesh? {
            LandmarkMesh.decodedLandmark(bytes, full: true, palette: palette, glass: landmark.glass)
        }
        XCTAssertNotNil(decoded(bytes))
        XCTAssertNil(decoded(Array(bytes.dropLast())))
        XCTAssertNil(decoded(bytes + [0]))
        XCTAssertNil(decoded(bytes, palette: Array(landmark.palette.dropLast())), "a material past the palette")
    }

    /// Each landmark's models are as its lock file holds: FNV-1a of every
    /// vertex field and index, and the triangle count. A changed value is
    /// a deliberate model change the pull request must justify; run with
    /// `LANDMARK_LOCKS_WRITE=1` to write the files anew.
    func testEveryRegisteredLandmarkIsAsLocked() throws {
        let write = ProcessInfo.processInfo.environment["LANDMARK_LOCKS_WRITE"] == "1"
        for landmark in Map3DLandmarkRegistry.landmarks {
            var models: [String: [String: Any]] = [:]
            for full in [true, false] {
                let mesh = landmark.model(full: full)
                models[full ? landmark.id : landmark.id + "-far"] = ["hash": Self.hash(mesh), "triangles": mesh.indices.count / 3]
            }
            let url = Self.locks.appendingPathComponent(landmark.id + ".json")
            let lock: [String: Any] = [
                "comment": "Decision 895: the models of the registered landmark \(landmark.id): FNV-1a of every vertex field and index "
                    + "(Map3DLandmarkRegistryTests). A changed value is a deliberate model change the PR must justify.",
                "models": models,
            ]
            let text = String(decoding: try JSONSerialization.data(withJSONObject: lock, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self) + "\n"
            if write {
                try text.write(to: url, atomically: true, encoding: .utf8)
                continue
            }
            let held = try String(contentsOf: url, encoding: .utf8)
            XCTAssertEqual(held, text, "\(landmark.id): its models are not as locked")
        }
    }

    static func hash(_ mesh: LandmarkMesh) -> String {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        func add(_ value: UInt32) {
            for shift in stride(from: 0, to: 32, by: 8) {
                hash ^= UInt64((value >> UInt32(shift)) & 0xFF)
                hash = hash &* 0x0000_0100_0000_01B3
            }
        }
        for v in mesh.vertices {
            for field in [v.x, v.y, v.z, v.nx, v.ny, v.nz, v.u, v.v, v.layer] { add(field.bitPattern) }
            add(v.color)
        }
        mesh.indices.forEach(add)
        let text = String(hash, radix: 16)
        return String(repeating: "0", count: 16 - text.count) + text
    }
}
