import Foundation

extension StationKitBuilder {
    static let worksYellow=Map3DPalette.player
    static let worksGreen=Map3DProp.greens[1]
    static let worksWood=Map3DPalette.trunk
    // Closed axial solid; all low-poly primitives include their undersides.
    mutating func worksTube(_ a: Map3DPoint,_ b: Map3DPoint,_ radius: Float,_ color: UInt32,sides: Int = 12) {
        guard let axis=(b-a).normalized,let u=axis.cross(abs(axis.y)>0.95 ? Map3DPoint(1,0,0) : .up).normalized else { return }
        let v=axis.cross(u),inside=(a+b)*0.5
        func ring(_ p: Map3DPoint) -> [Map3DPoint] { (0..<sides).map { i in let t=Float(i)*2*Float.pi/Float(sides);return p+u*(cosf(t)*radius)+v*(sinf(t)*radius) } }
        let p=ring(a),q=ring(b);face(p,inside:inside,color:color);face(q,inside:inside,color:color)
        for i in 0..<sides { let j=(i+1)%sides;face([p[i],p[j],q[j],q[i]],inside:inside,color:color) }
    }
    mutating func worksBlob(_ p: Map3DPoint,_ size: Map3DPoint,_ color: UInt32,sides: Int = 10,rings: Int = 6,patches: Bool = false) {
        func point(_ row: Int,_ col: Int) -> Map3DPoint {
            let a=Float(row)*Float.pi/Float(rings),b=Float(col)*2*Float.pi/Float(sides)
            if row==0 { return p+Map3DPoint(0,size.y,0) }
            if row==rings { return p-Map3DPoint(0,size.y,0) }
            return p+Map3DPoint(sinf(a)*cosf(b)*size.x,cosf(a)*size.y,sinf(a)*sinf(b)*size.z)
        }
        for row in 0..<rings { for col in 0..<sides {
            let a=point(row,col),b=point(row,col+1),c=point(row+1,col+1),d=point(row+1,col)
            let paint=patches && ((row==2 && col%4<2)||(row==3 && col%5<2)) ? Self.ink : color
            if row==0 { face([a,c,d],inside:p,color:paint) }
            else if row==rings-1 { face([a,b,c],inside:p,color:paint) }
            else { face([a,b,c,d],inside:p,color:paint) }
        } }
    }
    mutating func worksPrism(_ outline: [(Float,Float)],z: Float,width: Float,color: UInt32) {
        let p=outline.map { Map3DPoint($0.0,$0.1,z-width/2) },q=outline.map { Map3DPoint($0.0,$0.1,z+width/2) }
        let inside=(p+q).reduce(Map3DPoint.zero) { $0+$1*(1/Float(p.count*2)) }
        face(p,inside:inside,color:color);face(q,inside:inside,color:color)
        for i in p.indices { let j=(i+1)%p.count;face([p[i],p[j],q[j],q[i]],inside:inside,color:color) }
    }
    mutating func worksWheel(_ x: Float,_ y: Float,_ z: Float,radius: Float = 0.48,width: Float = 0.30,rail: Bool = false) {
        worksTube(Map3DPoint(x,y,z-width/2),Map3DPoint(x,y,z+width/2),radius,rail ? Map3DPalette.railTop : Self.ink,sides:16)
        worksTube(Map3DPoint(x,y,z-width/2-0.008),Map3DPoint(x,y,z+width/2+0.008),radius*0.52,Self.steel,sides:12)
        if rail { worksTube(Map3DPoint(x,y,z-width/2),Map3DPoint(x,y,z-width/2+0.025),radius*1.08,Self.steel,sides:16) }
        for k in 0..<6 { let t=Float(k)*Float.pi/3
            worksTube(Map3DPoint(x+cosf(t)*radius*0.32,y+sinf(t)*radius*0.32,z-width/2-0.02),Map3DPoint(x+cosf(t)*radius*0.32,y+sinf(t)*radius*0.32,z+width/2+0.02),radius*0.055,Self.ink,sides:6)
        }
    }
    mutating func worksCab(_ x: Float,_ y: Float,_ z: Float,length: Float = 1.9,width: Float = 1.8,height: Float = 1.8,color: UInt32 = Self.worksYellow) {
        let back=x-length/2,front=x+length/2,roofFront=x+length*0.26
        worksPrism([(back,y),(front,y),(front,y+height*0.40),(roofFront,y+height),(back,y+height)],z:z,width:width,color:color)
        // A single solid shell backs the sloped windshield, no hovering card.
        func screen(_ t: Float,_ side: Float) -> Map3DPoint {
            Map3DPoint(front+(roofFront-front)*t+0.004,y+height*0.4+height*0.6*t,z+side*width*0.40)
        }
        face([screen(0.15,-1),screen(0.82,-1),screen(0.82,1),screen(0.15,1)],inside:Map3DPoint(x,y+height/2,z),color:Self.glass)
        for side: Float in [-1,1] {
            face([Map3DPoint(back+0.12,y+height*0.48,z+side*(width/2+0.004)),Map3DPoint(x+length*0.22,y+height*0.48,z+side*(width/2+0.004)),Map3DPoint(x+length*0.10,y+height*0.88,z+side*(width/2+0.004)),Map3DPoint(back+0.12,y+height*0.88,z+side*(width/2+0.004))],inside:Map3DPoint(x,y+height/2,z),color:Self.glass)
            box(back+0.25,y+height*0.35,z+side*(width/2+0.015),0.18,0.025,0.04,Self.steel)
        }
        box(x,y+height,z,length+0.12,width+0.10,0.08,color)
        for side: Float in [-1,1] { box(front+0.01,y+0.17,z+side*width*0.35,0.04,width*0.18,0.13,Map3DProp.lampLight) }
        box(front+0.025,y,z,0.12,width+0.08,0.10,Self.ink)
    }
    mutating func worksTracks(length: Float = 3.8,width: Float = 2.5) {
        for side: Float in [-1,1] {
            let z=side*(width/2-0.28)
            worksPrism([(-length/2+0.25,0), (length/2-0.25,0),(length/2,0.28),(length/2-0.2,0.65),(-length/2+0.2,0.65),(-length/2,0.28)],z:z,width:0.54,color:Self.ink)
            for x in stride(from:-length/2+0.3,through:length/2-0.3,by:Float(0.46)) { worksWheel(x,0.31,z,radius:0.25,width:0.56) }
            for x in stride(from:-length/2+0.15,to:length/2,by:Float(0.23)) { box(x,0.64,z,0.055,0.60,0.035,Self.steel);box(x,0,z,0.055,0.60,0.03,Self.steel) }
        }
        box(0,0.30,0,length-0.5,width-0.5,0.24,Self.steel)
    }
    mutating func worksHydraulic(_ a: Map3DPoint,_ b: Map3DPoint,_ radius: Float = 0.065) {
        let mid=a+(b-a)*0.62
        worksTube(a,mid,radius,Self.worksYellow,sides:8);worksTube(mid,b,radius*0.58,Map3DPalette.railTop,sides:8)
        for p in [a,b] { worksTube(p-Map3DPoint(0,0,0.09),p+Map3DPoint(0,0,0.09),radius*1.1,Self.steel,sides:8) }
    }
    mutating func worksLeaf(_ a: Map3DPoint,_ b: Map3DPoint,width: Float,color: UInt32 = Self.worksGreen) {
        let d=b-a,u=Map3DPoint(-d.z,0,d.x).normalized ?? Map3DPoint(1,0,0),mid=a+d*0.48
        let p=[a,mid+u*width,b,mid-u*width],thick=Map3DPoint(0,0.015,0)
        face(p.map { $0+thick },inside:mid,color:color);face(p.map { $0-thick },inside:mid,color:Map3DColor.shaded(color,0.8))
        for i in 0..<4 { let j=(i+1)%4;face([p[i]-thick,p[j]-thick,p[j]+thick,p[i]+thick],inside:mid,color:color) }
    }
    mutating func works(_ part: Map3DWorksKit.Part) {
        switch part.category {
        case .engineering: worksVehicle(part)
        case .freight: worksFreight(part)
        case .animal: worksAnimal(part)
        case .nature: worksNature(part)
        }
    }
}

extension StationKitBuilder {
    mutating func worksCone(_ p: Map3DPoint,radius: Float,height: Float,color: UInt32) {
        let n=16,inside=p+Map3DPoint(0,height*0.4,0)
        let ring=(0..<n).map { i in let a=Float(i)*2*Float.pi/Float(n);return p+Map3DPoint(cosf(a)*radius,0,sinf(a)*radius) }
        face(ring,inside:inside,color:color)
        for i in 0..<n { face([ring[i],ring[(i+1)%n],p+Map3DPoint(0,height,0)],inside:inside,color:color) }
    }
}
