import XCTest
@testable import GamePresentation

/// Decision 450's later note: the studio's meshes mark their glass face by
/// face, and only those faces are glass. The Hong Kong trains' dark greys
/// (the doors' and window bays' charcoal #464B51, the front's mask, the
/// hardware and the under-frame's dark) are close to the glass in colour;
/// guessed by colour they were lit at night as windows.
final class Map3DTrainOwnGlassTests: XCTestCase {
    /// Every studio Hong Kong car, near and far, by name.
    var studioCars: [Map3DModelPack.Model] {
        get throws {
            var cars: [Map3DModelPack.Model] = []
            for far in [false, true] {
                for unit in Map3DMTRUrbanLine.Unit.allCases { cars.append(try XCTUnwrap(Map3DMTRUrbanLine.model(unit, far: far))) }
                for unit in Map3DMTRTuenMaLine.Unit.allCases { cars.append(try XCTUnwrap(Map3DMTRTuenMaLine.model(unit, far: far))) }
                for unit in Map3DMTRAirportLine.Unit.allCases { cars.append(try XCTUnwrap(Map3DMTRAirportLine.model(unit, far: far))) }
                for unit in Map3DMTREastRailLine.Unit.allCases { cars.append(try XCTUnwrap(Map3DMTREastRailLine.model(unit, far: far))) }
                for unit in Map3DMTRSouthIslandLine.Unit.allCases { cars.append(try XCTUnwrap(Map3DMTRSouthIslandLine.model(unit, far: far))) }
                for unit in Map3DMTRDisneylandLine.Unit.allCases { cars.append(try XCTUnwrap(Map3DMTRDisneylandLine.model(unit, far: far))) }
                // Decision 864: and the Finnish double-deck coach.
                cars.append(try XCTUnwrap(Map3DFinlandDoubleDeck.model(far: far)))
            }
            return cars
        }
    }

    /// The dark greys that the colour test takes for glass.
    let darkGreys: Set<UInt32> = [Map3DPalette.mtrCharcoal, Map3DColor.rgb(0x1D2125), Map3DColor.rgb(0x4B535C), Map3DColor.rgb(0x30363D)]

    func testTheDarkGreysLookLikeGlassByColour() {
        // Why the colour cannot be trusted for these trains.
        for colour in darkGreys { XCTAssertTrue(Map3DTrainLights.isGlass(colour), String(colour, radix: 16)) }
    }

    /// The glass faces are the glass material's, every one of them that
    /// does not look down, and nothing else.
    func testOnlyTheGlassMaterialIsGlass() throws {
        for model in try studioCars {
            XCTAssertTrue(Map3DTrainMaterial.marksOwnGlass(model), model.name)
            for start in stride(from: 0, to: model.vertices.count, by: 3) {
                let face = model.vertices[start]
                // A face looking down is not glass, as the pack marks it.
                let glass = face.color == Map3DTrainStyle.glass && face.nz >= Map3DTrainMaterial.lowestNormal
                XCTAssertEqual(face.layer == Map3DVertex.trainGlass, glass, model.name)
            }
        }
    }

    /// Marking the pack keeps them so: no dark grey face becomes glass.
    func testMarkingLeavesTheDarkGreysPlain() throws {
        for model in try studioCars {
            let marked = Map3DTrainMaterial.marked(model)
            for start in stride(from: 0, to: marked.vertices.count, by: 3) where darkGreys.contains(marked.vertices[start].color) {
                XCTAssertFalse(marked.vertices[start].isTrainMaterial, model.name)
            }
            XCTAssertEqual(marked.vertices.filter { $0.layer == Map3DVertex.trainGlass }.count,
                           model.vertices.filter { $0.layer == Map3DVertex.trainGlass }.count, model.name)
        }
    }

    /// At night only the windows are lit: each lit pane stands over a
    /// glass face, none over a door or a window's frame; guessed by colour
    /// the same car lit more.
    func testOnlyTheWindowsLightAtNight() throws {
        var checked = 0
        for model in try studioCars {
            guard let panes = Map3DTrainLights.windowModel(of: model) else { continue }
            checked += 1
            func key(_ v: Map3DVertex) -> [Int] { [v.x, v.y, v.z].map { Int(($0 * 1000).rounded()) } }
            var glass = Set<[[Int]]>()
            for start in stride(from: 0, to: model.vertices.count, by: 3) where model.vertices[start].layer == Map3DVertex.trainGlass {
                glass.insert(model.vertices[start ..< start + 3].map(key))
            }
            for start in stride(from: 0, to: panes.vertices.count, by: 3) {
                let under = panes.vertices[start ..< start + 3].map { pane -> [Int] in
                    var v = pane
                    v.x -= v.nx * Map3DTrainLights.paneProud
                    v.y -= v.ny * Map3DTrainLights.paneProud
                    v.z -= v.nz * Map3DTrainLights.paneProud
                    return key(v)
                }
                XCTAssertTrue(glass.contains(under), "\(model.name): a lit pane not over glass")
            }
            // The same car with its marks taken off, its glass guessed by colour.
            let guessed = Map3DModelPack.Model(name: model.name, vertices: model.vertices.map { var v = $0; v.layer = Map3DVertex.plain; return v },
                                               minimum: model.minimum, maximum: model.maximum)
            let byColour = try XCTUnwrap(Map3DTrainLights.windowModel(of: guessed), model.name)
            XCTAssertLessThanOrEqual(panes.triangleCount, byColour.triangleCount, model.name)
            // The urban line's and the airport lines' doors and window bays
            // are charcoal and their window bands dark (the Tuen Ma line's
            // are navy, never taken for glass): those lit no longer.
            if !model.name.hasPrefix("mtr-tuen-ma") {
                XCTAssertLessThan(panes.triangleCount, byColour.triangleCount, "\(model.name): the dark greys no longer lit")
            }
        }
        XCTAssertGreaterThan(checked, 10, "the cars with windows")
    }

    /// A recipe that does not mark its glass is guessed by colour as before.
    func testOtherTrainsAreGuessedByColourAsBefore() throws {
        let cab = try XCTUnwrap(Map3DRedCommuter.cab())
        XCTAssertFalse(Map3DTrainMaterial.marksOwnGlass(cab))
        XCTAssertTrue(Map3DTrainMaterial.marked(cab).vertices.contains { $0.layer == Map3DVertex.trainGlass })
    }
}
