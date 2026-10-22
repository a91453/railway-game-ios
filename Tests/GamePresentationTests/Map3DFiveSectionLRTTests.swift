import XCTest
@testable import GamePresentation

final class Map3DFiveSectionLRTTests: XCTestCase {
    func testIndependentSectionsReconstructTheActualFormationWithoutRotation() {
        let train = Map3DFiveSectionLRT.formation()
        var index = 0
        for unit in Map3DFiveSectionLRT.Unit.allCases {
            for p in Map3DFiveSectionLRT.model(unit).vertices {
                let q = train.vertices[index]
                XCTAssertEqual(q.x,p.x+unit.centre,accuracy:0.0001)
                XCTAssertEqual(q.y,p.y,accuracy:0.0001)
                XCTAssertEqual(q.z,p.z,accuracy:0.0001)
                XCTAssertEqual(q.color,p.color)
                index += 1
            }
        }
        XCTAssertEqual(index,train.vertices.count)
        XCTAssertEqual(train.length,34,accuracy:0.01)
        XCTAssertEqual(train.maximum.y-train.minimum.y,2.818,accuracy:0.10)
    }
    func testActualWheelGeometryHasSixAxlesAndSuspendedSectionsHaveNone() {
        let wheels=Map3DFiveSectionLRT.formation().vertices.filter { $0.color == Map3DStreetModel.tyre }
        let xs=wheels.map(\.x).sorted()
        var clusters: [[Float]]=[]
        for x in xs {
            if let last=clusters.last?.last,x-last<0.17 { clusters[clusters.count-1].append(x) }
            else { clusters.append([x]) }
        }
        // Wheel surfaces span .58m, with an actual .92m gap between axles.
        XCTAssertEqual(clusters.count,6)
        XCTAssertEqual(wheels.map(\.z).min()!,0,accuracy:0.001)
        for unit in [Map3DFiveSectionLRT.Unit.suspendedFront,.suspendedRear] {
            XCTAssertFalse(Map3DFiveSectionLRT.model(unit).vertices.contains { $0.color == Map3DStreetModel.tyre })
        }
    }
    func testDoorLeavesAndOnlyOnePantographArePresentInTheMesh() {
        var pantos=0
        for unit in Map3DFiveSectionLRT.Unit.allCases {
            let model=Map3DFiveSectionLRT.model(unit)
            if model.maximum.z>4 { pantos += 1;XCTAssertEqual(unit,.trailing) }
            let suspended=unit == .suspendedFront || unit == .suspendedRear
            for sign: Float in [-1,1] {
                // Narrow door leaves are the only glass at this outer plane.
                let leaves=model.vertices.filter { $0.color == Map3DFiveSectionLRT.glass && $0.y*sign>1.357 }
                let centres=Set(leaves.map { Int(($0.x*1000).rounded()) })
                XCTAssertEqual(centres.count,suspended ? 0 : 8) // 4 leaves, 2 edges each
            }
        }
        XCTAssertEqual(pantos,1)
    }
    func testEveryNewModelHasFiniteNondegenerateTrianglesAndReadsBackAlongsideExistingModels() {
        for unit in Map3DFiveSectionLRT.Unit.allCases {
            let model=Map3DFiveSectionLRT.model(unit)
            XCTAssertLessThan(model.triangleCount,3000)
            for i in stride(from:0,to:model.vertices.count,by:3) {
                let a=model.vertices[i],b=model.vertices[i+1],c=model.vertices[i+2]
                XCTAssertGreaterThan((b.position-a.position).cross(c.position-a.position).length,0.0000001)
                XCTAssertTrue([a.x,a.y,a.z,a.nx,a.ny,a.nz].allSatisfy(\.isFinite))
            }
            XCTAssertNotNil(Map3DModelPack.standard.index(of:model.name))
        }
        XCTAssertLessThan(Map3DFiveSectionLRT.formation().triangleCount,15000)
        for name in ["commuter-cab","green-tram-head","green-commuter-leading"] {
            XCTAssertNotNil(Map3DModelPack.standard.index(of:name),name)
        }
    }
}
