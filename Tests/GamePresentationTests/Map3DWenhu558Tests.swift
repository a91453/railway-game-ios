import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 558: the Wenhu line's two fleets, #1742's VAL256 and 370
/// (INNOVIA APM256), as running sets: two pairs A-B-A-B, split by train
/// number about 1 in 3 VAL256, never mixed; the old generic car kept as
/// the fallback.
final class Map3DWenhu558Tests: XCTestCase {
    private var pack: Map3DModelPack { .standard }

    /// The real line and the player's people mover are the 370 set, a
    /// third of their trains the VAL256.
    func testTheWenhuLineRunsBothFleets() throws {
        let line = Map3DRealTrains.formation(system: "trtc", id: "BR", name: "文湖線")
        XCTAssertEqual(line, .init(key: Map3DTrainSet.wenhu370Key, cars: 4))
        var counts: [String: Int] = [:]
        for number in 0..<300 {
            let key = Map3DRealTrains.formation(of: line, system: "trtc", number: number).key
            counts[key, default: 0] += 1
            XCTAssertEqual(Map3DTrainSet.variant(of: "APM", number: number), key, "the player's people mover the same, \(number)")
        }
        XCTAssertEqual(counts, [Map3DTrainSet.wenhuVAL256Key: 100, Map3DTrainSet.wenhu370Key: 200])
        // 51 pairs to 101: a third is within a percent of the VAL256's share.
        XCTAssertEqual(Double(counts[Map3DTrainSet.wenhuVAL256Key]!) / 300, 51.0 / 152, accuracy: 0.01)
        XCTAssertEqual(Map3DTrainSet.wenhuLine(number: -3), Map3DTrainSet.wenhuVAL256Key)
        XCTAssertEqual(Map3DTrainSet.wenhuLine(number: -1), Map3DTrainSet.wenhu370Key)
        // The old generic car's key stays its own.
        XCTAssertEqual(Map3DTrainSet.variant(of: "wenhu", number: 3), "wenhu")
    }

    /// Four cars are A B A B, each unit as #1742's assembly places it (no
    /// car turned round), at its own length, touching the next; a pair is
    /// A B, six cars three pairs. Near within 500 m, the far set's same
    /// car beyond.
    func testTheCarsAreTwoPairs() throws {
        for (key, far) in [(Map3DTrainSet.wenhuVAL256Key, "wenhuVAL256Far"), (Map3DTrainSet.wenhu370Key, "wenhu370Far")] {
            func names(_ count: Int) throws -> [String] {
                try XCTUnwrap(pack.layout(forType: key, count: count)).map { pack.models[$0.model].name }
            }
            XCTAssertEqual(try names(4), ["set-\(key)-head", "set-\(key)-car", "set-\(key)-centre", "set-\(key)-tail"])
            XCTAssertEqual(try names(2), ["set-\(key)-head", "set-\(key)-tail"])
            XCTAssertEqual(try names(6), ["set-\(key)-head", "set-\(key)-car", "set-\(key)-centre", "set-\(key)-car",
                                          "set-\(key)-centre", "set-\(key)-tail"])
            for index in 0..<4 { XCTAssertFalse(pack.isTurned(forType: key, carIndex: index, count: 4), "\(key) \(index)") }
            let laid = try XCTUnwrap(pack.layout(forType: key, count: 4))
            for car in laid {
                XCTAssertEqual(car.length, 13.78, accuracy: 0.45, "\(key): \(pack.models[car.model].name)")
                XCTAssertEqual(car.gap, 0)
            }
            // The unrecoloured head is #1742's A and the tail its B.
            let recipes = try XCTUnwrap(Map3DTrainSet.byKey[key]).build()
            let a = key == Map3DTrainSet.wenhuVAL256Key ? Map3DWenhuVAL256.model(.a) : Map3DWenhuAPM256.model(.a)
            let b = key == Map3DTrainSet.wenhuVAL256Key ? Map3DWenhuVAL256.model(.b) : Map3DWenhuAPM256.model(.b)
            XCTAssertEqual(recipes.middle?.vertices, b.vertices, "\(key): the middle car is the B unit as it is")
            XCTAssertEqual(recipes.centre?.vertices, a.vertices, "\(key): the centre car is the A unit as it is")
            XCTAssertEqual(recipes.head.vertices.map(\.x), a.vertices.map(\.x), "\(key): the head is the A unit, not turned")
            XCTAssertEqual(recipes.tail?.vertices.map(\.x), b.vertices.map(\.x), "\(key): the tail is the B unit, not turned")
            // The head's lamps glow at its front, the tail's at its back.
            let head = recipes.head, tail = try XCTUnwrap(recipes.tail)
            XCTAssertTrue(head.vertices.contains { $0.layer == Map3DVertex.glowing && $0.x > head.maximum.x - 1 }, "\(key) head lamps")
            XCTAssertTrue(tail.vertices.contains { $0.layer == Map3DVertex.glowing && $0.x < tail.minimum.x + 1 }, "\(key) tail lamps")
            // Near within 500 m, then the far set's car, then a box.
            XCTAssertEqual(Map3DTrainSet.reach(of: key), 500)
            let near = try XCTUnwrap(pack.modelIndex(forType: key, carIndex: 1, count: 4))
            XCTAssertEqual(pack.model(near, forType: key, count: 4, at: 300), near)
            XCTAssertEqual(pack.model(near, forType: key, count: 4, at: 700), pack.index(of: "set-\(far)-car"))
            XCTAssertNil(pack.model(near, forType: key, count: 4, at: 1_000))
        }
    }

    /// A pack without the new sets' models (one built before them) draws
    /// the Wenhu line as the old generic car rather than boxes.
    func testThePackWithoutThemDrawsTheOldCar() throws {
        var models = pack.models.filter { !$0.name.contains("-wenhuVAL256") && !$0.name.contains("-wenhu370") }
        models = models.filter { !$0.name.hasPrefix("light-set-wenhu3") && !$0.name.hasPrefix("light-set-wenhuV") }
        let old = Map3DModelPack(models: models)
        for key in ["APM", Map3DTrainSet.wenhu370Key, Map3DTrainSet.wenhuVAL256Key] {
            let head = try XCTUnwrap(old.modelIndex(forType: key, carIndex: 0, count: 4), key)
            XCTAssertEqual(old.models[head].name, "set-wenhu-head", key)
            XCTAssertNotNil(old.models(forType: key), key)
            XCTAssertNil(old.layout(forType: key, count: 4), "\(key): 20 m a car, as the old car was")
        }
    }

    /// The cars are what #1742 counted: within the near car budget, the far
    /// car under half of it.
    func testTheTriangles() throws {
        for key in [Map3DTrainSet.wenhuVAL256Key, Map3DTrainSet.wenhu370Key] {
            for unit in ["head", "car", "centre", "tail"] {
                let near = pack.models[try XCTUnwrap(pack.index(of: "set-\(key)-\(unit)"))]
                let far = pack.models[try XCTUnwrap(pack.index(of: "set-\(key)Far-\(unit)"))]
                XCTAssertLessThanOrEqual(near.triangleCount, 20_000, "\(key) \(unit)")
                XCTAssertLessThan(far.triangleCount * 2, near.triangleCount, "\(key) \(unit) far")
                if ProcessInfo.processInfo.environment["MAP3D_FRAME_REPORT"] != nil {
                    print("\(key) \(unit): \(near.triangleCount) near, \(far.triangleCount) far, \(near.length) m")
                }
            }
        }
    }

    /// The names players read: the line's two fleets, in both languages.
    func testTheNames() {
        XCTAssertEqual(RealLineStock.name(ofSet: Map3DTrainSet.wenhuVAL256Key, in: .traditionalChinese), "文湖線 VAL256")
        XCTAssertEqual(RealLineStock.name(ofSet: Map3DTrainSet.wenhu370Key, in: .traditionalChinese), "文湖線 370 型")
        XCTAssertEqual(RealLineStock.name(ofSet: Map3DTrainSet.wenhuVAL256Key, in: .english), "Wenhu Line VAL256")
        XCTAssertEqual(RealLineStock.name(ofSet: Map3DTrainSet.wenhu370Key, in: .english), "Wenhu Line Type 370")
        XCTAssertEqual(RealLineStock.lineName(ofSet: Map3DTrainSet.wenhu370Key, in: .traditionalChinese), "文湖線 VAL256／370 型")
        XCTAssertEqual(RealLineStock.setKey(ofRealLine: "trtc:BR"), Map3DTrainSet.wenhu370Key)
        let showcase = Map3DShowcase.catalog.map(\.key)
        XCTAssertTrue(showcase.contains(Map3DTrainSet.wenhuVAL256Key))
        XCTAssertTrue(showcase.contains(Map3DTrainSet.wenhu370Key))
    }
}
