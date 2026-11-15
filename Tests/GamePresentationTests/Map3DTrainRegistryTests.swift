import Foundation
@testable import GamePresentation
import XCTest

/// Decision 782: the registered trains (``Map3DTrainRegistry``), each in
/// its own files.
final class Map3DTrainRegistryTests: XCTestCase {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// Every `Map3DTrainRegistration(id: …)` in the sources is in the list
    /// once, and every one in the list has its lock file and no lock file
    /// is left without its train (a train whose line was forgotten, or a
    /// line two branches both added).
    func testTheListIsEveryRegistrationInTheSources() throws {
        let sources = Self.root.appendingPathComponent("Sources/GamePresentation")
        var declared: [String] = []
        let pattern = try NSRegularExpression(pattern: #"Map3DTrainRegistration\(\s*id:\s*"([^"]+)""#)
        for name in try FileManager.default.contentsOfDirectory(atPath: sources.path) where name.hasSuffix(".swift") {
            let text = try String(contentsOf: sources.appendingPathComponent(name), encoding: .utf8)
            for match in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                declared.append(String(text[Range(match.range(at: 1), in: text)!]))
            }
        }
        let listed = Map3DTrainRegistry.trains.map(\.id)
        XCTAssertEqual(listed.count, Set(listed).count, "a train listed twice: \(listed)")
        XCTAssertEqual(Set(declared), Set(listed),
                       "add `<Type>.registration,` to Map3DTrainRegistryList.swift for each of \(Set(declared).subtracting(listed).sorted())")
        let locks = Self.root.appendingPathComponent("tools/train-models/locks")
        let files = try FileManager.default.contentsOfDirectory(atPath: locks.path).filter { $0.hasSuffix(".json") }
        XCTAssertEqual(Set(files), Set(listed.map { $0 + ".json" }), "one lock file a registered train")
    }

    /// The registered sets are the last of ``Map3DTrainSet/all``, their
    /// keys their own, every near set's far set is the train's own, the far
    /// sets are drawn near only, and each showcase row is a near set of
    /// its train.
    func testTheRegisteredSetsJoinTheGame() {
        let all = Map3DTrainSet.all.map(\.key)
        let registered = Map3DTrainRegistry.sets.map(\.key)
        XCTAssertEqual(Array(all.suffix(registered.count)), registered)
        XCTAssertEqual(Set(all).count, all.count, "a set key twice")
        for train in Map3DTrainRegistry.trains {
            let keys = Set(train.sets.map(\.key))
            for set in train.sets {
                XCTAssertTrue(train.owns(set.headName), "\(train.id): \(set.key)'s head is its own")
                if let far = set.far {
                    XCTAssertTrue(keys.contains(far), "\(train.id): \(set.key)'s far set \(far)")
                    XCTAssertTrue(Map3DTrainSet.nearOnly.contains(set.key), set.key)
                }
            }
            for entry in train.showcase {
                XCTAssertTrue(keys.contains(entry.key), "\(train.id): showcase \(entry.key)")
                XCTAssertEqual(Map3DShowcase.entry(entry.key), entry)
            }
            XCTAssertNotNil(Map3DTrainRegistry.registration(ofSet: train.sets[0].key))
        }
        // No hand-written model is taken for a registered train's.
        XCTAssertFalse(Map3DTrainRegistry.trains.contains { $0.owns("set-metroGeneric-head") })
        XCTAssertTrue(Map3DTrainRegistry.trains.contains { $0.owns("light-set-mtrTungChungFar-car") })
        XCTAssertFalse(Map3DTrainRegistry.trains.contains { $0.owns("set-mtrTungChungFarther-car") })
    }
}
