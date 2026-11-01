import GameCore
import XCTest
@testable import GamePresentation

/// Exact R100CK presentation binding only: no fleet ratios, timetable changes,
/// livery randomisation, new purchases or train-pack gates.
final class Map3DR100IntegrationTests: XCTestCase {
    private func payload(_ model: Map3DModelPack.Model) -> [UInt32] {
        model.vertices.flatMap { v in
            [v.x.bitPattern, v.y.bitPattern, v.z.bitPattern,
             v.nx.bitPattern, v.ny.bitPattern, v.nz.bitPattern,
             v.color, v.u.bitPattern, v.v.bitPattern, v.layer.bitPattern]
        }
    }

    private func model(_ name: String, in pack: Map3DModelPack) throws -> Map3DModelPack.Model {
        pack.models[try XCTUnwrap(pack.index(of: name), name)]
    }

    /// Connected, closed lamp solids, identified from the actual source
    /// triangles. A lens may be unlit in the recipe: the runtime recognises
    /// its lens colour and lights only the selected end of the whole train.
    private func realLenses(_ model: Map3DModelPack.Model, atFront: Bool) -> [[Map3DVertex]] {
        var triangles: [[Map3DVertex]] = []
        for start in stride(from: 0, to: model.vertices.count, by: 3) {
            let triangle = Array(model.vertices[start ..< start + 3])
            if triangle[0].color == Map3DPalette.tunnelLamp,
               triangle.allSatisfy({ atFront ? $0.x > model.maximum.x - model.length * 0.3
                                            : $0.x < model.minimum.x + model.length * 0.3 }) {
                triangles.append(triangle)
            }
        }
        func key(_ vertex: Map3DVertex) -> String {
            "\(Int((vertex.x * 100_000).rounded())),\(Int((vertex.y * 100_000).rounded())),\(Int((vertex.z * 100_000).rounded()))"
        }
        var parents = Array(triangles.indices)
        func root(_ index: Int) -> Int {
            var current = index
            while parents[current] != current { current = parents[current] }
            return current
        }
        var owners: [String: Int] = [:]
        for (index, triangle) in triangles.enumerated() {
            for vertex in triangle {
                if let previous = owners[key(vertex)] { parents[root(index)] = root(previous) }
                else { owners[key(vertex)] = index }
            }
        }
        var components: [Int: [Map3DVertex]] = [:]
        for (index, triangle) in triangles.enumerated() { components[root(index), default: []] += triangle }
        return Array(components.values)
    }

    func testOnlyTheExistingR100IdentitySelectsTheOrangeNativeLocomotive() throws {
        XCTAssertEqual(Map3DTrainSet.key(type: .r100ChuKuang, performance: .standard), "R100CK")
        XCTAssertEqual(Map3DTrainSet.key(type: nil, performance: .r100ChuKuang), "R100CK")
        XCTAssertEqual(Map3DTrainSet.key(type: .blueTrain, performance: .r100ChuKuang), "BLUE")
        XCTAssertFalse(TrainPack.sets.contains("R100CK"))
        XCTAssertFalse(TrainPack.sets.contains("BLUE"))
        for number in [0, 1, 2, 123, 135] {
            XCTAssertEqual(Map3DTrainSet.variant(of: "R100CK", number: number), "R100CK")
            XCTAssertEqual(Map3DTrainSet.variant(of: "BLUE", number: number), "BLUE")
        }
        for locked in [TrainPack.locked(unlocked: false), TrainPack.locked(unlocked: true)] {
            XCTAssertEqual(Map3DTrainSet.set(forKey: "R100CK", count: 6, locked: locked)?.key, "R100CK")
            XCTAssertEqual(Map3DTrainSet.set(forKey: "BLUE", count: 6, locked: locked)?.key, "BLUE")
        }
        for far in [false, true] {
            let set = try XCTUnwrap(Map3DTrainSet.named(far ? "R100CKFar" : "R100CK"))
            XCTAssertEqual(payload(set.build().head), payload(Map3DR100.model(livery: .orange, far: far)))
        }
    }

    func testLocomotiveAndUnchangedCoachesUseTheirNativeLengthsForEveryCount() throws {
        let pack = Map3DModelPack.standard
        for count in [1, 2, 3, 6, 12] {
            let layout = try XCTUnwrap(pack.layout(forType: "R100CK", count: count))
            XCTAssertEqual(layout.count, count)
            let names = layout.map { pack.models[$0.model].name }
            let expected = count == 1 ? ["set-R100CK-head"]
                : ["set-R100CK-head"] + Array(repeating: "set-R100CK-car", count: count - 2) + ["set-R100CK-tail"]
            XCTAssertEqual(names, expected)
            XCTAssertEqual(layout[0].length, Map3DR100.model(livery: .orange).length, accuracy: 0.0001)
            XCTAssertTrue(layout.dropFirst().allSatisfy { abs($0.length - 20) < 0.0001 })
            XCTAssertTrue(layout.allSatisfy { $0.gap == 0 })
            for (index, unit) in layout.enumerated() {
                XCTAssertFalse(pack.isTurned(forType: "R100CK", carIndex: index, count: count))
                let item = pack.models[unit.model]
                let instance = Map3DTrains.instance(of: item, index: unit.model,
                    from: Map3DPoint(-unit.length / 2, 0, 0), to: Map3DPoint(unit.length / 2, 0, 0), stripe: 0)
                XCTAssertEqual(instance.transform[0], 1, accuracy: 0.0001, "native metre scale, +X short end toward the front")
            }
        }
        XCTAssertNil(Map3DTrainSet.named("R100CK")?.fixedCars)
    }

    func testTheNativeFarLocomotiveUsesTheExisting500And900MetreTransitions() throws {
        let pack = Map3DModelPack.standard
        let head = try XCTUnwrap(pack.index(of: "set-R100CK-head"))
        let far = try XCTUnwrap(pack.index(of: "set-R100CKFar-head"))
        XCTAssertEqual(pack.model(head, forType: "R100CK", count: 6, at: 499), head)
        XCTAssertEqual(pack.model(head, forType: "R100CK", count: 6, at: 500), far)
        XCTAssertEqual(pack.model(head, forType: "R100CK", count: 6, at: 899), far)
        XCTAssertNil(pack.model(head, forType: "R100CK", count: 6, at: 900))
        XCTAssertLessThan(pack.models[far].triangleCount * 2, pack.models[head].triangleCount)
        XCTAssertEqual(pack.models[head].minimum, pack.models[far].minimum)
        XCTAssertEqual(pack.models[head].maximum, pack.models[far].maximum)
        let lower = Map3DLoadStep.nearerFarModels.reach(on: .standard)
        XCTAssertEqual(pack.model(head, forType: "R100CK", count: 6, at: 251, reach: lower), far)
    }

    func testTheLegacyCoachesArePreserved() throws {
        let pack = Map3DModelPack.unbaked
        for far in [false, true] {
            let prefix = far ? "set-R100CKFar" : "set-R100CK"
            XCTAssertEqual(payload(try model(prefix + "-car", in: pack)), payload(Map3DChuKuangPassenger.model(.standard, far: far)))
            XCTAssertEqual(payload(try model(prefix + "-tail", in: pack)), payload(Map3DTrainSet.chuKuangTail(far: far)))
        }
        // Decision 540: the Blue Train no longer runs the R135 stand-in; its
        // set is pinned by Map3DBreezyBlueIntegrationTests.
        XCTAssertNotNil(Map3DTrainSet.named("BLUEFar"))
    }

    func testBothRealLampEndsAreUsedAndTheModelIsNotReversedTwice() throws {
        let pack = Map3DModelPack.standard
        for far in [false, true] {
            let name = far ? "set-R100CKFar-head" : "set-R100CK-head"
            let at = try XCTUnwrap(pack.index(of: name))
            let lights = try XCTUnwrap(pack.lights[at])
            let recipe = Map3DR100.model(livery: .orange, far: far)
            for front in [false, true] {
                let lenses = realLenses(recipe, atFront: front)
                XCTAssertEqual(lenses.count, 2, "two actual stacked lamp solids at each end")
                for lens in lenses {
                    XCTAssertTrue(lens.allSatisfy { abs($0.y) < 0.09 && $0.z > (front ? 3.4 : 3.0) }, "real high central R100 lamps")
                }
                let lamps = lights.lamps(atFront: front)
                XCTAssertFalse(lamps.head.isEmpty)
                XCTAssertFalse(lamps.tail.isEmpty)
                XCTAssertTrue(lamps.head.allSatisfy { front ? $0.x > 0 : $0.x < 0 })
                let source = lenses.flatMap { $0 }
                XCTAssertEqual(lamps.head.count, source.count, "runtime uses every triangle of the two real lenses")
                for lit in lamps.head {
                    XCTAssertTrue(source.contains { vertex in
                        abs(lit.x - vertex.x - vertex.nx * Map3DTrainLights.proud) < 0.00001 &&
                        abs(lit.y - vertex.y - vertex.ny * Map3DTrainLights.proud) < 0.00001 &&
                        abs(lit.z - vertex.z - vertex.nz * Map3DTrainLights.proud) < 0.00001
                    }, "runtime lamp must come from a real connected lens, not a fallback rectangle")
                }
                let synthetic = Map3DTrainLights.madeLamps(of: recipe, atFront: front)
                XCTAssertNotEqual(lamps.head.map(\.position), synthetic.map(\.position), "real lenses, not synthesized fallback")
            }
            XCTAssertFalse(pack.isTurned(forType: "R100CK", carIndex: 0, count: 1))
            var frame = Map3DTrains.Frame()
            frame.instances = [Map3DInstance(model: at, transform: [], stripe: (0, 0, 0))]
            frame.addEnds(ofCar: 0, count: 1, turned: false)
            XCTAssertEqual(frame.ends, [.init(instance: 0, atFront: true, isTail: false), .init(instance: 0, atFront: false, isTail: true)])
        }
    }
}
