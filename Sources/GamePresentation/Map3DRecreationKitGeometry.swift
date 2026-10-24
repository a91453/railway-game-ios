import Foundation

extension StationKitBuilder {
    static let recreationGold=Map3DPalette.player
    static let recreationRoof=Map3DPalette.playerRoof
    static let recreationGreen=Map3DPalette.gymGreen
    mutating func recreation(_ p: Map3DRecreationKit.Part) {
        switch p.category {
        case .venue: recreationVenue(p)
        case .fitness: recreationFitness(p)
        case .sport: recreationSport(p)
        case .aquatic: recreationAquatic(p)
        }
    }
    mutating func recreationPrism(_ p: [Map3DPoint],_ q: [Map3DPoint],_ color: UInt32) {
        let inside=(p+q).reduce(Map3DPoint.zero) { $0+$1*(1/Float(p.count+q.count)) }
        face(p,inside:inside,color:color);face(q,inside:inside,color:color)
        for i in p.indices { let j=(i+1)%p.count;face([p[i],p[j],q[j],q[i]],inside:inside,color:color) }
    }
    mutating func recreationFrustum(_ x: Float,_ y: Float,_ z: Float,_ r: Float,_ top: Float,_ h: Float,_ color: UInt32,sides: Int = 12) {
        let a=(0..<sides).map { i in let t=Float(i)*2*Float.pi/Float(sides);return Map3DPoint(x+cosf(t)*r,y,z+sinf(t)*r) }
        let b=(0..<sides).map { i in let t=Float(i)*2*Float.pi/Float(sides);return Map3DPoint(x+cosf(t)*top,y+h,z+sinf(t)*top) }
        recreationPrism(a,b,color)
    }
    mutating func recreationPanel(_ a: Map3DPoint,_ b: Map3DPoint,_ width: Float,_ thickness: Float,_ color: UInt32) {
        let u=Map3DPoint(0,0,width/2),d=Map3DPoint(0,-thickness,0)
        recreationPrism([a-u,b-u,b-u+d,a-u+d],[a+u,b+u,b+u+d,a+u+d],color)
    }
    mutating func recreationWheel(_ x: Float,_ y: Float,_ z: Float,_ radius: Float,_ width: Float,_ color: UInt32) {
        civicTube(Map3DPoint(x,y,z-width/2),Map3DPoint(x,y,z+width/2),radius:radius,color:color,sides:12)
    }
    mutating func recreationLadder(_ a: Map3DPoint,_ b: Map3DPoint,_ width: Float,_ rungs: Int) {
        for z: Float in [-width/2,width/2] { civicTube(a+Map3DPoint(0,0,z),b+Map3DPoint(0,0,z),radius:0.045,color:Self.steel,sides:8) }
        for i in 1...rungs {
            let p=a+(b-a)*(Float(i)/Float(rungs+1))
            civicTube(p-Map3DPoint(0,0,width/2),p+Map3DPoint(0,0,width/2),radius:0.035,color:Self.steel,sides:8)
        }
    }
    mutating func recreationBall(_ x: Float,_ y: Float,_ z: Float,_ radius: Float) {
        // Closed clipped sphere with nonzero cap radii; no degenerate apex fans.
        for i in 0..<6 {
            let a = -Float.pi/2+Float(i)*Float.pi/6,b = -Float.pi/2+Float(i+1)*Float.pi/6
            recreationFrustum(x,y+sinf(a)*radius,z,max(0.006,cosf(a)*radius),max(0.006,cosf(b)*radius),(sinf(b)-sinf(a))*radius,Self.recreationGold,sides:10)
        }
    }
}
