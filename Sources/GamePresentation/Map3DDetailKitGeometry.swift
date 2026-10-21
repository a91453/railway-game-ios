import Foundation

extension StationKitBuilder {
    static let detailAccent=Map3DPalette.player
    static let detailRed=Map3DPalette.templeRidge
    static let detailGreen=Map3DPalette.crown
    // Closed polygonal cylinders along arbitrary axes, with solid end caps.
    mutating func detailTube(_ a: Map3DPoint,_ b: Map3DPoint,_ radius: Float,_ color: UInt32,sides: Int = 12) {
        guard let d=(b-a).normalized,let u=d.cross(abs(d.y)>0.95 ? Map3DPoint(1,0,0) : .up).normalized else { return }
        let v=d.cross(u)
        func ring(_ p: Map3DPoint) -> [Map3DPoint] { (0..<sides).map { i in let t=Float(i)*2*Float.pi/Float(sides);return p+u*(cosf(t)*radius)+v*(sinf(t)*radius) } }
        let p=ring(a),q=ring(b),inside=(a+b)*0.5
        face(p,inside:inside,color:color);face(q,inside:inside,color:color)
        for i in 0..<sides { let j=(i+1)%sides;face([p[i],p[j],q[j],q[i]],inside:inside,color:color) }
    }
    mutating func detailFrame(_ x: Float,_ y: Float,_ z: Float,_ width: Float,_ height: Float,_ depth: Float = 0.06,_ color: UInt32 = Self.steel) {
        for dz: Float in [-width/2,width/2] { box(x,y,z+dz,depth,0.06,height,color) }
        for dy: Float in [0,height-0.06] { box(x,y+dy,z,depth,width,0.06,color) }
    }
    mutating func detailPlate(_ y: Float = 0,_ z: Float = 0,width: Float = 0.28,height: Float = 0.3) {
        box(0.02,y,z,0.04,width,height,Self.steel)
        for dy in [height*0.2,height*0.8] { for dz in [-width*0.3,width*0.3] {
            detailTube(Map3DPoint(0.04,y+dy,z+dz),Map3DPoint(0.055,y+dy,z+dz),0.018,Self.ink,sides:6)
        } }
    }
    mutating func detailWheel(_ x: Float,_ y: Float,_ z: Float,_ radius: Float = 0.12,_ width: Float = 0.08) {
        detailTube(Map3DPoint(x,y,z-width/2),Map3DPoint(x,y,z+width/2),radius,Self.ink)
        detailTube(Map3DPoint(x,y,z-width/2-0.005),Map3DPoint(x,y,z+width/2+0.005),radius*0.5,Self.steel)
    }
    mutating func detailRack(_ x: Float = 0,_ y: Float = 0,_ z: Float = 0,width: Float = 1.2,height: Float = 1.7,depth: Float = 0.5,levels: Int = 4) {
        for dx in [-depth/2,depth/2] { for dz in [-width/2,width/2] { box(x+dx,y,z+dz,0.045,0.045,height,Self.steel) } }
        for i in 0..<levels { box(x,y+0.08+Float(i)*(height-0.14)/Float(levels-1),z,depth,width,0.045,Self.white) }
    }
    mutating func detailCrate(_ x: Float,_ y: Float,_ z: Float,width: Float = 0.6,color: UInt32 = Self.detailGreen) {
        box(x,y,z,0.45,width,0.045,color)
        for side: Float in [-1,1] {
            for level: Float in [0.07,0.18,0.29] {
                box(x+side*0.21,y+level,z,0.03,width,0.05,color)
                box(x,y+level,z+side*(width/2-0.015),0.45,0.03,0.05,color)
            }
            for t: Float in [-1,1] { box(x+side*0.21,y,z+t*(width/2-0.015),0.035,0.035,0.34,color) }
        }
    }
    mutating func detailPartStatic(_ part: Map3DDetailKit.Part) {
        switch part.category {
        case .rail: detailRail(part)
        case .building: detailBuilding(part)
        case .interior: detailInterior(part)
        case .street: detailStreet(part)
        case .life: detailLife(part)
        case .moving: break
        }
    }
    mutating func detail(_ part: Map3DDetailKit.Part,moving: inout StationKitBuilder) {
        if part.category == .moving { detailMoving(part,moving:&moving) } else { detailPartStatic(part) }
    }
}
