import XCTest
@testable import GamePresentation

final class Map3DEMU900Tests: XCTestCase {
    func testPublishedTenCarPitchAndAsymmetricEquipmentOrder() {
        let ps=Map3DEMU900.placements
        XCTAssertEqual(ps.count,10)
        XCTAssertEqual(ps.filter { $0.role == .epCompressor || $0.role == .epAccessible }.count,3)
        XCTAssertEqual(ps[5].role,.epAccessible)
        XCTAssertEqual(ps[4].role,.emCrew)
        XCTAssertEqual(ps.first!.x-ps.last!.x+21.58,205.56,accuracy:0.001)
        XCTAssertFalse(ps[2].reversed)
        XCTAssertTrue(ps[5].reversed)
        XCTAssertTrue(ps[7].reversed)
        for i in 1..<ps.count {
            let a:Float=ps[i-1].role == .ed ? 21.58:20.30
            let b:Float=ps[i].role == .ed ? 21.58:20.30
            XCTAssertEqual(ps[i-1].x-ps[i].x,(a+b)/2,accuracy:0.0001)
        }
    }
    func testEveryDeliveredRoleHasLegalNearFarAndExactReverse() {
        for role in Map3DEMU900.Role.allCases {for (far,light) in [(false,false),(true,false),(false,true)] {
            let m=Map3DEMU900.model(role,far:far,light:light),r=Map3DEMU900.model(role,reversed:true,far:far,light:light)
            XCTAssertLessThanOrEqual(m.triangleCount,Map3DModelFile.maximumTriangles)
            XCTAssertGreaterThan(m.triangleCount,100)
            if light {XCTAssertLessThanOrEqual(m.triangleCount,role == .ed ? 2467:1592)}
            if !far && !light {XCTAssertLessThanOrEqual(m.triangleCount,role == .ed ? 11506:5400)}
            XCTAssertEqual(role.hasPantograph,role == .epCompressor || role == .epAccessible)
            XCTAssertEqual(m.minimum.z,0,accuracy:0.00001)
            XCTAssertEqual(m.vertices.count,r.vertices.count)
            for (a,b) in zip(m.vertices,r.vertices) {
                XCTAssertEqual(a.x,-b.x);XCTAssertEqual(a.y,-b.y);XCTAssertEqual(a.z,b.z)
                XCTAssertEqual(a.nx,-b.nx);XCTAssertEqual(a.ny,-b.ny);XCTAssertEqual(a.nz,b.nz)
                XCTAssertEqual(a.color,b.color);XCTAssertEqual(a.layer,b.layer)
            }
            XCTAssertFalse(m.vertices.contains {$0.color == Map3DColor.rgb(0xFFC86B)})
        }}
    }
    func testFormationUsesTheFinalUnitsWithoutScaleOrSecondRotation() {
        for (far,light) in [(false,false),(true,false),(false,true)] {
            let full=Map3DEMU900.formation(far:far,light:light)
            XCTAssertEqual(full.triangleCount,Map3DEMU900.placements.reduce(0){$0+Map3DEMU900.model($1.role,far:far,light:light).triangleCount})
            var cursor=0
            for p in Map3DEMU900.placements {
                let unit=Map3DEMU900.model(p.role,reversed:p.reversed,far:far,light:light)
                for v in unit.vertices {
                    let actual=full.vertices[cursor];cursor+=1
                    XCTAssertEqual(actual.x,v.x+p.x,accuracy:0.0001)
                    XCTAssertEqual(actual.y,v.y,accuracy:0.00001)
                    XCTAssertEqual(actual.z,v.z,accuracy:0.00001)
                    XCTAssertEqual(actual.color,v.color)
                }
            }
        }
    }

    /// Full-vertex pins protect the delivered near/far/light payload during later integration.
    func testDeliveredNearFarAndLightPayloadPins() {
        let expected: [String: String] = [
            "emu900-ed": "1c1b03af655d024a",
            "emu900-ed-light": "490003b967e88746",
            "emu900-emToilet": "77beb47b4062c431",
            "emu900-emToilet-light": "864067e5141ee7",
            "emu900-emSIV": "e14b040e50d14de5",
            "emu900-emSIV-light": "2d62dc15b0994ded",
            "emu900-emCrew": "fa95f9430ea49585",
            "emu900-emCrew-light": "ee2e4bec215ae3a1",
            "emu900-epCompressor": "bf2256208d78dbc6",
            "emu900-epCompressor-light": "576cbb355e826acd",
            "emu900-epAccessible": "2f57b4c48c8c920e",
            "emu900-epAccessible-light": "29ad776ec37250eb",
            "emu900-ed-far": "71d014c5bc910713",
            "emu900-emToilet-far": "4333c46cdd021e1d",
            "emu900-emSIV-far": "3ddecc12918c2c53",
            "emu900-emCrew-far": "d4d3787ab0f5235f",
            "emu900-epCompressor-far": "38f605c04537b046",
            "emu900-epAccessible-far": "2c4e2af7530f97d6",
        ]
        for (far, light) in [(false,false),(true,false),(false,true)] {
            for role in Map3DEMU900.Role.allCases {
                let model=Map3DEMU900.model(role,far:far,light:light)
                var pin: UInt64 = 0xcbf29ce484222325
                for v in model.vertices {
                    for bits in [v.x.bitPattern,v.y.bitPattern,v.z.bitPattern,v.nx.bitPattern,v.ny.bitPattern,v.nz.bitPattern,v.color,v.u.bitPattern,v.v.bitPattern,v.layer.bitPattern] {
                        for shift:UInt32 in [0,8,16,24] {pin=(pin ^ UInt64((bits>>shift)&255)) &* 0x100000001b3}
                    }
                }
                XCTAssertEqual(String(pin,radix:16),expected[model.name],model.name)
            }
        }
    }
}
