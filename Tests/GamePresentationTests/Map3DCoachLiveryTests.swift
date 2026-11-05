import XCTest
@testable import GamePresentation

final class Map3DCoachLiveryTests: XCTestCase {
    private func hash(_ model: Map3DModelPack.Model) -> String {
        var h: UInt64=0xcbf29ce484222325
        for v in model.vertices {
            for word in [v.x.bitPattern,v.y.bitPattern,v.z.bitPattern,v.nx.bitPattern,v.ny.bitPattern,v.nz.bitPattern,
                         v.color,v.u.bitPattern,v.v.bitPattern,v.layer.bitPattern] {
                for shift in stride(from:0,to:32,by:8) { h=(h ^ UInt64((word >> UInt32(shift)) & 0xFF)) &* 0x100000001b3 }
            }
        }
        return String(h,radix:16)
    }
    func testDefaultModelRetainsLockedHashAndStreetInstance() {
        let original=Map3DCoachBus.model()
        XCTAssertEqual(hash(original),"ed823eef367fbf12")
        let index=Map3DStreetLife.models[.coachBus]!
        XCTAssertEqual(Map3DModelPack.standard.models[index].vertices,original.vertices)
    }
    func testIdentifiersPaletteAndGeometry() {
        let liveries=Map3DCoachLivery.allCases
        XCTAssertEqual(liveries.count,8)
        XCTAssertEqual(Set(liveries.map(\.rawValue)).count,liveries.count)
        XCTAssertEqual(liveries.filter(\.isTourism),[.tourismOrange])
        for livery in liveries { XCTAssertFalse(livery.nameZH.isEmpty);XCTAssertFalse(livery.nameEN.isEmpty) }
        let original=Map3DCoachBus.model()
        let baseColours=Set(original.vertices.map(\.color))
        var nearCount: Int?,farCount: Int?
        var signatures=Set<String>()
        for livery in liveries {
            let palette=[livery.paint.body,livery.paint.belt,livery.paint.nose,livery.paint.roof]
            let allowed=baseColours.union(palette.flatMap { color in [Float(1),0.7,0.8,0.87].map { Map3DColor.shaded(color,$0) } })
            let near=Map3DCoachBus.model(livery:livery),far=Map3DCoachBus.model(livery:livery,far:true)
            nearCount = nearCount ?? near.triangleCount;farCount = farCount ?? far.triangleCount
            XCTAssertEqual(near.triangleCount,nearCount)
            XCTAssertEqual(far.triangleCount,farCount)
            XCTAssertEqual(near.triangleCount,original.triangleCount)
            XCTAssertLessThan(far.triangleCount,near.triangleCount)
            XCTAssertTrue(near.vertices.allSatisfy { allowed.contains($0.color) })
            XCTAssertEqual(near.vertices.count,original.vertices.count)
            for (old,new) in zip(original.vertices,near.vertices) {
                XCTAssertEqual(old.position,new.position)
                if old.color == Map3DPalette.glazing { XCTAssertTrue(new.glows) }
                else { XCTAssertEqual(old.layer,new.layer) }
                XCTAssertEqual(old.nx,new.nx);XCTAssertEqual(old.ny,new.ny);XCTAssertEqual(old.nz,new.nz)
                if old.glows { XCTAssertEqual(old.color,new.color) }
            }
            XCTAssertEqual(near.vertices,Map3DCoachBus.model(livery:livery).vertices)
            XCTAssertEqual(far.vertices,Map3DCoachBus.model(livery:livery,far:true).vertices)
            signatures.insert(hash(near))
        }
        XCTAssertEqual(signatures.count,liveries.count)
    }
}
