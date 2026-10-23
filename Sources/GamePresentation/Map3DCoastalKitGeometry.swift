import Foundation

// Builder coordinates are x front / y up / z right. Box y is its bottom.
extension StationKitBuilder {
    static let coastalWood=Map3DPalette.counters[1]
    static let coastalBlue=Map3DPalette.tinRoofs[0]
    static let coastalGreen=Map3DPalette.gymGreen
    static let coastalSand=Map3DPalette.forecourt
    mutating func coastal(_ part: Map3DCoastalKit.Part) {
        switch part.category {
        case .coast: coastalStructure(part)
        case .harbor: coastalHarbor(part)
        case .camp: coastalCamp(part)
        }
    }
    /// Closed prism between two equal convex profiles. No paper thin sheets.
    mutating func coastalPrism(_ p: [Map3DPoint],_ q: [Map3DPoint],_ color: UInt32) {
        let inside=(p+q).reduce(Map3DPoint.zero) { $0+$1*(1/Float(p.count+q.count)) }
        face(p,inside:inside,color:color);face(q,inside:inside,color:color)
        for i in p.indices { let j=(i+1)%p.count;face([p[i],p[j],q[j],q[i]],inside:inside,color:color) }
    }
    mutating func coastalFrustum(_ x: Float,_ y: Float,_ z: Float,_ bottom: Float,_ top: Float,_ height: Float,_ color: UInt32,sides: Int = 12) {
        let p=(0..<sides).map { i in let a=Float(i)*2*Float.pi/Float(sides);return Map3DPoint(x+cosf(a)*bottom,y,z+sinf(a)*bottom) }
        let q=(0..<sides).map { i in let a=Float(i)*2*Float.pi/Float(sides);return Map3DPoint(x+cosf(a)*top,y+height,z+sinf(a)*top) }
        coastalPrism(p,q,color)
    }
    /// Polygonal torus in XY (upright) or XZ (horizontal).
    mutating func coastalRing(_ centre: Map3DPoint,radius: Float,tube: Float,color: UInt32,upright: Bool = false,segments: Int = 16) {
        for i in 0..<segments {
            func p(_ j: Int) -> Map3DPoint { let a=Float(j)*2*Float.pi/Float(segments);return centre+(upright ? Map3DPoint(cosf(a)*radius,sinf(a)*radius,0) : Map3DPoint(cosf(a)*radius,0,sinf(a)*radius)) }
            civicTube(p(i),p(i+1),radius:tube,color:color,sides:6)
        }
    }
    /// Hollow, thick hull with sealed rims and transoms. Five new sections;
    /// the source's mast/sail and texture-driven shell are not retained.
    mutating func coastalHull(length: Float,width: Float,height: Float,color: UInt32) {
        let xs: [Float]=[-0.5,-0.30,0.10,0.37,0.5],ws: [Float]=[0.72,1,0.96,0.60,0.10]
        for i in 0..<4 {
            let a=xs[i]*length,b=xs[i+1]*length,wa=ws[i]*width/2,wb=ws[i+1]*width/2
            let levels: [Float]=[0.06,0,0,0.08,0.16],ya=levels[i],yb=levels[i+1]
            let lowA=Map3DPoint(a,ya,0),lowB=Map3DPoint(b,yb,0)
            coastalPrism([lowA+Map3DPoint(0,0,-wa*0.5),lowA+Map3DPoint(0,0,wa*0.5),Map3DPoint(a,max(0.14,ya+0.06),wa*0.5),Map3DPoint(a,max(0.14,ya+0.06),-wa*0.5)],
                         [lowB+Map3DPoint(0,0,-wb*0.5),lowB+Map3DPoint(0,0,wb*0.5),Map3DPoint(b,max(0.14,yb+0.06),wb*0.5),Map3DPoint(b,max(0.14,yb+0.06),-wb*0.5)],color)
            for sign: Float in [-1,1] {
                let p=[Map3DPoint(a,ya,sign*wa*0.5),Map3DPoint(a,height,sign*wa),Map3DPoint(a,height,sign*max(0.02,wa-0.065)),Map3DPoint(a,max(0.14,ya+0.06),sign*wa*0.5)]
                let q=[Map3DPoint(b,yb,sign*wb*0.5),Map3DPoint(b,height+0.08*Float(i==3 ? 1:0),sign*wb),Map3DPoint(b,height+0.08*Float(i==3 ? 1:0),sign*max(0.02,wb-0.065)),Map3DPoint(b,max(0.14,yb+0.06),sign*wb*0.5)]
                coastalPrism(p,q,color)
                beam(p[1],q[1],0.07,Self.white)
            }
        }
        // Both end bulkheads join the floor, both gunwales and the inner shell.
        for i in [0,4] { box(xs[i]*length,0.14,0,0.07,ws[i]*width,height-0.14,color) }
        for x: Float in [-length*0.24,length*0.13] { box(x,height-0.12,0,0.22,width*0.75,0.08,Self.coastalWood) }
    }
    mutating func coastalPanel(_ a: Map3DPoint,_ b: Map3DPoint,width: Float,thickness: Float,color: UInt32) {
        let u=Map3DPoint(0,0,width/2),d=Map3DPoint(0,-thickness,0)
        coastalPrism([a-u,b-u,b-u+d,a-u+d],[a+u,b+u,b+u+d,a+u+d],color)
    }
}
