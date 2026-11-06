import XCTest
@testable import GamePresentation

final class Map3DTransparentGlassTests: XCTestCase {
    private let identity: [Float] = [1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1]
    private func pane(z: Float, layer: Float = Map3DVertex.trainGlass, normal: Map3DPoint = Map3DPoint(0,1,0), color: UInt32 = 0xff885522) -> Map3DModelPack.Model {
        let p = [Map3DPoint(-1,0,z), Map3DPoint(1,0,z), Map3DPoint(0,1,z)]
        return Map3DModelPack.Model(name: "pane", vertices: p.map { Map3DVertex($0, normal: normal, color: color, u: 0.3, layer: layer) }, minimum: p[0], maximum: p[2])
    }
    private func moved(_ model: Int, x: Float = 0, z: Float = 0) -> Map3DInstance {
        var t = identity; t[12] = x; t[14] = z
        return Map3DInstance(model: model, transform: t, stripe: (1,0,0))
    }
    func testExplicitConversionChangesOnlyGlassAndPreservesLayoutAndPaint() {
        let glass = pane(z: 0), steel = pane(z: 1, layer: Map3DVertex.trainSteel)
        let combined = Map3DModelPack.Model(name: "both", vertices: glass.vertices + steel.vertices, minimum: glass.minimum, maximum: steel.maximum)
        let new = Map3DTransparentGlass.applying(to: combined)
        XCTAssertEqual(Array(new.vertices.suffix(3)), steel.vertices)
        for (a,b) in zip(glass.vertices, new.vertices.prefix(3)) {
            XCTAssertEqual(a.position,b.position); XCTAssertEqual(a.color,b.color)
            XCTAssertEqual(b.layer,Map3DVertex.transparentGlass); XCTAssertEqual(b.u,0.14); XCTAssertEqual(b.v,0.3)
        }
        XCTAssertEqual(new.minimum, combined.minimum); XCTAssertEqual(new.maximum, combined.maximum)
        XCTAssertEqual(MemoryLayout<Map3DVertex>.stride, 40)
        XCTAssertTrue(Map3DTransparentGlass.Cache(models: [combined]).isEmpty)
    }
    func testFloorIsClearerAndNightFlagSurvives() {
        let floor = pane(z: 0, layer: Map3DVertex.trainGlassLit, normal: Map3DPoint(0,0,1))
        let new = Map3DTransparentGlass.applying(to: floor)
        XCTAssertTrue(new.vertices.allSatisfy { $0.u == 0.06 && $0.glows && $0.layer == Map3DVertex.transparentGlassLit })
        XCTAssertFalse(Map3DVertex(Map3DPoint(0,0,0), normal: Map3DPoint(0,1,0), color: 0xffffffff).isTransparentGlass)
    }
    func testNonfiniteOpacityIsSafeAndRangeIsClamped() {
        XCTAssertEqual(Map3DTransparentGlass.Style(window: .nan, floor: .infinity), .init())
        XCTAssertEqual(Map3DTransparentGlass.Style(window: -3, floor: 5), .init(window: 0, floor: 1))
    }
    func testTrianglesAreSortedAcrossInstancesByViewDepthNotEuclideanDistance() {
        let m = Map3DTransparentGlass.applying(to: pane(z: 0))
        let cache = Map3DTransparentGlass.Cache(models: [m])
        let vertices = cache.vertices(instances: [moved(0,x:100,z:2),moved(0,z:8)], eye: Map3DPoint(0,0,0), toward: Map3DPoint(0,0,1))
        XCTAssertEqual(vertices.count,6); XCTAssertEqual(vertices[0].z,8); XCTAssertEqual(vertices[3].z,2)
        let reverse = cache.vertices(instances: [moved(0,z:8),moved(0,z:2)], eye: Map3DPoint(0,0,10), toward: Map3DPoint(0,0,0))
        XCTAssertEqual(reverse[0].z,2)
    }
    func testStableTiesAndIndividualTrianglesWithinOneModel() {
        let a = pane(z:2), b = pane(z:8)
        let both = Map3DModelPack.Model(name:"two",vertices:a.vertices+b.vertices,minimum:a.minimum,maximum:b.maximum)
        let cache = Map3DTransparentGlass.Cache(models:[Map3DTransparentGlass.applying(to:both)])
        let result = cache.vertices(instances:[moved(0,x:1),moved(0,x:3)],eye:Map3DPoint(0,0,0),toward:Map3DPoint(0,0,1))
        XCTAssertEqual(result.map(\.z),[8,8,8,8,8,8,2,2,2,2,2,2])
        XCTAssertEqual(result[0].x,0); XCTAssertEqual(result[3].x,2)
    }
    func testNonuniformTransformRecomputesNormalsAndStripeAlphaIsNotOpacity() {
        let m = Map3DTransparentGlass.applying(to:pane(z:0,color:0x00885522))
        var t = identity;t[0] = 2;t[5] = 3;t[10] = 0.5
        let v = Map3DTransparentGlass.Cache(models:[m]).vertices(instances:[Map3DInstance(model:0,transform:t,stripe:(1,0,0))],eye:Map3DPoint(0,0,-2),toward:Map3DPoint(0,0,0))
        XCTAssertEqual(v.count,3);XCTAssertEqual(v[0].color,0xff0000ff);XCTAssertEqual(v[0].u,0.14)
        XCTAssertEqual(v[0].nz,1,accuracy:0.00001);XCTAssertEqual(v[0].nx,0)
    }
    func testInvalidInputsAndZeroOpacityDoNotReachGPU() {
        let model=Map3DTransparentGlass.applying(to:pane(z:0)),cache=Map3DTransparentGlass.Cache(models:[model])
        let zero=Map3DTransparentGlass.applying(to:pane(z:0),style:.init(window:0,floor:0))
        XCTAssertTrue(Map3DTransparentGlass.Cache(models:[zero]).isEmpty)
        let bad=Map3DInstance(model:0,transform:[.nan],stripe:(1,1,1))
        XCTAssertTrue(cache.vertices(instances:[bad,moved(9)],eye:Map3DPoint(0,0,0),toward:Map3DPoint(0,0,1)).isEmpty)
        XCTAssertTrue(cache.vertices(instances:[moved(0)],eye:Map3DPoint(.nan,0,0),toward:Map3DPoint(0,0,1)).isEmpty)
    }
    func testEveryLegacyMaterialKeepsItsOldMeaningAndNoStandardModelOptsIn() {
        for layer: Float in [-1,-2,-3,-5,-8,-9,-10,-11,-12,-13,-14,-15] {
            let v=Map3DVertex(Map3DPoint(0,0,0),normal:Map3DPoint(0,1,0),color:0xffffffff,layer:layer)
            XCTAssertEqual(v.glows, layer == -2 || layer == -15)
            XCTAssertFalse(v.isTransparentGlass)
        }
        // Decision 615: the cable car cabins, and only they, opt in.
        let glassy = Map3DModelPack.standard.models.filter { $0.vertices.contains(where: \.isTransparentGlass) }.map(\.name)
        XCTAssertEqual(Set(glassy), Set(Map3DCableCar.drawn.map(\.name).filter { $0.hasPrefix("cablecar-cabin-") && !$0.hasSuffix("-far") }))
    }
    func testAdapterIsIdempotentAndRejectsInvalidReflectionShade() {
        let a=Map3DTransparentGlass.applying(to:pane(z:0))
        XCTAssertEqual(Map3DTransparentGlass.applying(to:a).vertices,a.vertices)
        var v=a.vertices;v[0].v = .nan
        let bad=Map3DModelPack.Model(name:"bad",vertices:v,minimum:a.minimum,maximum:a.maximum)
        XCTAssertTrue(Map3DTransparentGlass.Cache(models:[bad]).isEmpty)
    }

}
