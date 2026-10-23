import Foundation

// Builder uses +x front / +y up / +z right; box y is the bottom.
extension StationKitBuilder {
    static let estateGold=Map3DPalette.player
    static let estateRoof=Map3DPalette.playerRoof
    mutating func estate(_ p: Map3DEstateKit.Part) {
        switch p.category {
        case .leisure: estateLeisure(p)
        case .hotel: estateHotel(p)
        case .residential: estateResidential(p)
        case .commercial: estateCommercial(p)
        }
    }
    mutating func estateBase(_ length: Float,_ width: Float) { box(0,0,0,length,width,0.16,Map3DPalette.forecourt) }
    mutating func estateBlock(_ x: Float,_ y: Float,_ z: Float,_ length: Float,_ width: Float,_ floors: Int) {
        civicBlock(x,y,z,length:length,width:width,floors:floors,color:Self.white,roof:Self.estateRoof)
        // Broad yellow sill stays inside the wall thickness, backed by the block.
        for f in 0..<floors { box(x+length/2,y+Float(f)*3+0.20,z,0.06,width,0.22,Self.estateGold) }
    }
    mutating func estatePorch(_ x: Float,_ y: Float,_ z: Float,_ depth: Float,_ width: Float,_ height: Float) {
        box(x,y+height,z,depth,width,0.18,Self.estateRoof)
        for dz: Float in [-width/2+0.14,width/2-0.14] { box(x+depth/2-0.14,y,z+dz,0.22,0.22,height,Self.estateGold) }
    }
    mutating func estatePrism(_ p: [Map3DPoint],_ q: [Map3DPoint],_ color: UInt32) {
        let inside=(p+q).reduce(Map3DPoint.zero) { $0+$1*(1/Float(p.count+q.count)) }
        face(p,inside:inside,color:color);face(q,inside:inside,color:color)
        for i in p.indices { let j=(i+1)%p.count;face([p[i],p[j],q[j],q[i]],inside:inside,color:color) }
    }
    mutating func estateFrustum(_ x: Float,_ y: Float,_ z: Float,_ bottom: Float,_ top: Float,_ height: Float,_ color: UInt32,sides: Int = 12) {
        let p=(0..<sides).map { i in let a=Float(i)*2*Float.pi/Float(sides);return Map3DPoint(x+cosf(a)*bottom,y,z+sinf(a)*bottom) }
        let q=(0..<sides).map { i in let a=Float(i)*2*Float.pi/Float(sides);return Map3DPoint(x+cosf(a)*top,y+height,z+sinf(a)*top) }
        estatePrism(p,q,color)
    }
    mutating func estatePlanter(_ x: Float,_ y: Float,_ z: Float) {
        box(x,y,z,1.1,0.8,0.35,Map3DPalette.concrete)
        box(x,y+0.30,z,0.9,0.6,0.35,Map3DPalette.gymGreen)
    }
    /// Closed polygonal barrel roof. End caps are solid, with no open underside.
    mutating func estateBarrel(_ x: Float,_ y: Float,_ z: Float,_ length: Float,_ width: Float,_ rise: Float) {
        var p=[Map3DPoint(x-length/2,y,z-width/2),Map3DPoint(x-length/2,y,z+width/2)]
        for i in 0...8 { let t=Float(i)*Float.pi/8;p.append(Map3DPoint(x-length/2,y+0.15+sinf(t)*rise,z+cosf(t)*width/2)) }
        estatePrism(p,p.map { $0+Map3DPoint(length,0,0) },Self.estateRoof)
    }
}
