import XCTest
@testable import GamePresentation

/// Decision 1041 (continued): the Kumamoto City Tram's low-floor tram, the
/// local studio's model in place of Kaohsiung's Citadis.
final class Map3DKumamotoTramTests: XCTestCase {
    /// The real tram's size, near and far: 18.40 m long, 2.40 m wide, its
    /// pantograph raised to 5.10 m.
    func testItDecodesAtTheRealSize() throws {
        for far in [false, true] {
            let model = try XCTUnwrap(Map3DKumamotoTram.model(far: far), "far \(far)")
            XCTAssertEqual(model.length, 18.4, accuracy: 0.01, "far \(far)")
            XCTAssertEqual(model.maximum.y - model.minimum.y, 2.4, accuracy: 0.01, "far \(far)")
            XCTAssertEqual(model.minimum.z, 0, accuracy: 0.03, "far \(far)")
            XCTAssertEqual(model.maximum.z, 5.1, accuracy: 0.01, "far \(far): the raised pantograph")
            XCTAssertTrue(Map3DKumamotoTram.registration.triangles.contains(model.triangleCount), "far \(far)")
            XCTAssertTrue(Map3DKumamotoTram.registration.length.contains(model.length), "far \(far)")
        }
        let near = try XCTUnwrap(Map3DKumamotoTram.model()), far = try XCTUnwrap(Map3DKumamotoTram.model(far: true))
        XCTAssertLessThan(far.triangleCount * 2, near.triangleCount, "the far one less than half the near one")
    }

    /// The wheels stand on the 1,435 mm gauge, and only they reach the rail.
    func testTheWheelsStandOnTheStandardGauge() throws {
        let low = try XCTUnwrap(Map3DKumamotoTram.model()).vertices.filter { $0.z < 0.05 }
        XCTAssertFalse(low.isEmpty)
        XCTAssertTrue(low.allSatisfy { $0.color == Map3DPalette.dark }, "only the wheels reach the rail")
        let widest = low.map { abs($0.y) }.max() ?? 0
        XCTAssertGreaterThan(widest, 1.435 / 2 - 0.05)
        XCTAssertLessThan(widest, 1.435 / 2 + 0.15)
    }

    /// Its own colours: the white body, the wine band, the navy lamp band,
    /// and nothing that is not the mesh's palette.
    func testTheColoursAreItsPalettes() throws {
        for far in [false, true] {
            let used = Set(try XCTUnwrap(Map3DKumamotoTram.model(far: far)).vertices.map(\.color))
            XCTAssertTrue(used.isSubset(of: Set(Map3DKumamotoTram.meshPalette)), "far \(far)")
            for colour in [Map3DPalette.tileWhite, Map3DPalette.kumamotoWine, Map3DEMU800.navy, Map3DTrainStyle.headlamp, Map3DPalette.lantern] {
                XCTAssertTrue(used.contains(colour), "far \(far): \(String(colour, radix: 16))")
            }
        }
        XCTAssertEqual(Map3DPalette.kumamotoWine, Map3DColor.rgb(0x943040))
    }

    /// At night the saloon's windows light, the cabs' at both ends do not
    /// (the studio's brief: a cab lit in its first previews).
    func testOnlyTheSaloonsWindowsLightAtNight() throws {
        let pack = Map3DModelPack.unbaked
        for name in ["set-kumamotoTram-single", "set-kumamotoTramFar-single"] {
            let model = pack.models[try XCTUnwrap(pack.index(of: name), name)]
            let panes = try XCTUnwrap(Map3DTrainLights.windowModel(of: model), name)
            XCTAssertGreaterThan(panes.triangleCount, 20, name)
            for vertex in panes.vertices {
                XCTAssertGreaterThan(vertex.x, model.minimum.x + Map3DTrainLights.cabReach - 0.01, "\(name): a back cab's pane lit")
                XCTAssertLessThan(vertex.x, model.maximum.x - Map3DTrainLights.cabReach + 0.01, "\(name): a front cab's pane lit")
            }
        }
    }

    /// Both of the City Tram's lines are drawn as it, one model a train,
    /// where they were Kaohsiung's Citadis.
    func testTheCityTramRunsIt() {
        for id in ["A", "B"] {
            XCTAssertEqual(Map3DRealTrains.japanFormation(system: "kumamotocity", id: id, name: ""),
                           .init(key: Map3DKumamotoTram.key, cars: 1), id)
        }
        XCTAssertEqual(RealLineStock.name(ofSet: Map3DKumamotoTram.key, in: .english), "Kumamoto low-floor tram")
        XCTAssertEqual(RealLineStock.name(ofSet: Map3DKumamotoTram.key, in: .traditionalChinese), "熊本市電低地板電車")
        XCTAssertEqual(RealLineStock.name(ofSet: Map3DKumamotoTram.key, in: .japanese), "熊本市電 超低床電車")
    }
}
