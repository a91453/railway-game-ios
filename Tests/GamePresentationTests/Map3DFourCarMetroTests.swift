import XCTest
@testable import GamePresentation

final class Map3DFourCarMetroTests: XCTestCase {
    func testFourCarsReconstructTheFormationWithConsistentRailDatum() {
        let formation=Map3DFourCarMetro.formation();var index=0
        for unit in Map3DFourCarMetro.Unit.allCases {
            let part=Map3DFourCarMetro.model(unit)
            for v in part.vertices {
                let q=formation.vertices[index];index += 1
                XCTAssertEqual(q.x,v.x+unit.centre,accuracy:0.0001)
                XCTAssertEqual(q.y,v.y,accuracy:0.0001);XCTAssertEqual(q.z,v.z,accuracy:0.0001)
                XCTAssertEqual(q.color,v.color);XCTAssertEqual(q.nx,v.nx,accuracy:0.0001)
            }
            XCTAssertEqual(part.minimum.z,0,accuracy:0.0001)
            XCTAssertEqual(part.maximum.z,3.694,accuracy:0.001)
            XCTAssertNotNil(Map3DModelPack.standard.index(of:part.name))
        }
        XCTAssertEqual(index,formation.vertices.count)
        XCTAssertLessThan(formation.triangleCount,Map3DModelFile.maximumTriangles)
    }
    func testActualWheelDiscsShowFourAxlesPerCarAndSixteenPerFormation() {
        for model in Map3DFourCarMetro.Unit.allCases.map({ Map3DFourCarMetro.model($0) })+[Map3DFourCarMetro.formation()] {
            let wheels=model.vertices.filter { $0.color == Map3DStreetModel.tyre }
            var clusters=0,last: Float = -.infinity
            for x in wheels.map(\.x).sorted() { if x-last>0.17 { clusters += 1 };last=x }
            XCTAssertEqual(clusters,model.name.hasSuffix("formation") ? 16:4)
            XCTAssertEqual(wheels.map(\.z).min()!,0,accuracy:0.0001)
            XCTAssertEqual(wheels.map(\.z).max()!,0.76,accuracy:0.0001)
        }
    }
    func testActualGlazingHasFourDoorLeavesAndThreeWindowBaysOnEachSide() {
        let shades: [Float]=[0.86,0.80]
        let colors=shades.map { Map3DColor.shaded(Map3DFourCarMetro.glass,$0) }
        for unit in Map3DFourCarMetro.Unit.allCases {
            let model=Map3DFourCarMetro.model(unit)
            for sign: Float in [-1,1] {
                let panes=model.vertices.filter { colors.contains($0.color) && $0.y*sign>1.36 && $0.ny*sign>0.9 }
                let doors=panes.filter { abs($0.x)>2 && abs($0.x)<4 }
                XCTAssertEqual(Set(doors.map { Int(($0.x*1000).rounded()) }).count,8)
                let windows=panes.filter { abs($0.x)<2 || abs($0.x)>4 }
                XCTAssertEqual(Set(windows.map { Int(($0.x*1000).rounded()) }).count,6)
            }
            let frontGlass=model.vertices.filter { ($0.color == Map3DFourCarMetro.glass) && abs($0.nx)>0.9 && abs($0.y)<1.1 && $0.z>1.9 }
            if unit == .middleFront || unit == .middleRear { XCTAssertTrue(frontGlass.isEmpty) }
            else { XCTAssertFalse(frontGlass.isEmpty) }
        }
    }
    func testTrianglesAreFiniteNondegenerateWithUnitOutwardNormals() {
        for unit in Map3DFourCarMetro.Unit.allCases {
            let m=Map3DFourCarMetro.model(unit)
            for i in stride(from:0,to:m.vertices.count,by:3) {
                let a=m.vertices[i],b=m.vertices[i+1],c=m.vertices[i+2]
                let cross=(b.position-a.position).cross(c.position-a.position)
                XCTAssertGreaterThan(cross.length,0.0000001)
                XCTAssertTrue([a.x,a.y,a.z,a.nx,a.ny,a.nz].allSatisfy(\.isFinite))
                XCTAssertEqual(Map3DPoint(a.nx,a.ny,a.nz).length,1,accuracy:0.0001)
                XCTAssertGreaterThan(cross.dot(Map3DPoint(a.nx,a.ny,a.nz)),0)
            }
        }
        for id in ["urban-three-leading","lrt-seven-formation","lrt-five-formation","metro-four-formation"] {
            XCTAssertNotNil(Map3DModelPack.standard.index(of:id))
        }
    }
}
