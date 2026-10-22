import Foundation

// Geometry uses x front / y up / z right. Model.flat performs the native
// x front / y left / z up conversion once at the API boundary.
struct StationKitBuilder {
    var mesh=Map3DMesh()
    static let forward=Map3DPoint(1,0,0)
    static let glass=Map3DPalette.glazing
    static let steel=Map3DPalette.tankStand
    static let white=Map3DPalette.tileWhite
    static let ink=Map3DPalette.playerRim

    mutating func box(_ x: Float,_ y: Float,_ z: Float,_ length: Float,_ width: Float,_ height: Float,_ color: UInt32) {
        mesh.addBox(base:Map3DPoint(x,y,z),forward:Self.forward,length:length,width:width,height:height,top:color,side:color)
        mesh.addQuad(Map3DPoint(x-length/2,y,z-width/2),Map3DPoint(x+length/2,y,z-width/2),
                     Map3DPoint(x+length/2,y,z+width/2),Map3DPoint(x-length/2,y,z+width/2),color:Map3DColor.shaded(color,0.7))
    }
    mutating func cylinder(_ x: Float,_ y: Float,_ z: Float,radius: Float,height: Float,color: UInt32,sides: Int = 12) {
        mesh.addCylinder(base:Map3DPoint(x,y,z),radius:radius,height:height,sides:sides,top:color,side:color)
        mesh.addFacet((0..<sides).map { i in let a=Float(i)*2*Float.pi/Float(sides);return Map3DPoint(x+cosf(a)*radius,y,z+sinf(a)*radius) },color:Map3DColor.shaded(color,0.7))
    }
    mutating func beam(_ a: Map3DPoint,_ b: Map3DPoint,_ thickness: Float,_ color: UInt32) {
        guard let d=(b-a).normalized,let u=d.cross(abs(d.y)>0.95 ? Map3DPoint(1,0,0) : .up).normalized else { return }
        let v=d.cross(u)*(thickness/2),w=u*(thickness/2)
        let p=[a-w-v,a+w-v,a+w+v,a-w+v,b-w-v,b+w-v,b+w+v,b-w+v]
        for f in [[0,3,2,1],[4,5,6,7],[0,1,5,4],[1,2,6,5],[2,3,7,6],[3,0,4,7]] { mesh.addFacet(f.map { p[$0] },color:color) }
    }
    mutating func gable(_ x: Float,_ y: Float,_ z: Float,_ length: Float,_ width: Float,_ rise: Float,_ color: UInt32) {
        mesh.addGableRoof(base:Map3DPoint(x,y,z),forward:Self.forward,length:length,width:width,rise:rise,overhang:0.35,color:color,gable:Self.white)
        box(x,y-0.12,z,length+0.7,width+0.7,0.12,color)
    }
    mutating func hip(_ x: Float,_ y: Float,_ z: Float,_ length: Float,_ width: Float,_ rise: Float,_ color: UInt32) {
        mesh.addHipRoof(base:Map3DPoint(x,y,z),forward:Self.forward,length:length,width:width,rise:rise,overhang:0.4,color:color)
        box(x,y-0.12,z,length+0.8,width+0.8,0.12,color)
    }
    mutating func pane(_ x: Float,_ y: Float,_ z: Float,_ width: Float,_ height: Float) {
        box(x,y,z,0.10,width+0.16,height+0.16,Self.white)
        mesh.addQuad(Map3DPoint(x+0.057,y+0.08,z-width/2),Map3DPoint(x+0.057,y+height+0.08,z-width/2),
                     Map3DPoint(x+0.057,y+height+0.08,z+width/2),Map3DPoint(x+0.057,y+0.08,z+width/2),color:Self.glass)
    }
    mutating func facade(_ x: Float,_ y: Float,_ z: Float,_ length: Float,_ width: Float,_ height: Float,_ color: UInt32,bays: Int = 5) {
        box(x,y,z,length,width,height,color)
        for sign: Float in [-1,1] {
            for i in 0..<bays {
                let dz=z-width/2+(Float(i)+0.5)*width/Float(bays)
                if sign>0 { pane(x+length/2,y+height*0.24,dz,width/Float(bays)*0.60,height*0.50) }
                else { box(x-length/2-0.018,y+height*0.24,dz,0.035,width/Float(bays)*0.60,height*0.50,Self.glass) }
            }
        }
    }
    mutating func bench(_ x: Float,_ y: Float,_ z: Float,back: Bool = true) {
        for dz: Float in [-0.7,0.7] { box(x,y,z+dz,0.4,0.12,0.48,Self.steel) }
        box(x,y+0.48,z,0.5,1.9,0.12,Map3DPalette.counters[1])
        if back { box(x-0.22,y+0.60,z,0.10,1.9,0.48,Map3DPalette.counters[1]) }
    }
    mutating func tree(_ x: Float,_ y: Float,_ z: Float,size: Float = 1) {
        cylinder(x,y,z,radius:0.12*size,height:2.3*size,color:Map3DPalette.trunk,sides:6)
        let c=Map3DPoint(x,y+3*size,z),r=1.3*size
        let p=[c+Map3DPoint(0,r,0),c-Map3DPoint(0,r*0.8,0),c+Map3DPoint(r,0,0),c+Map3DPoint(0,0,r),c-Map3DPoint(r,0,0),c-Map3DPoint(0,0,r)]
        for i in 0..<4 {
            let a=2+i,b=2+(i+1)%4
            face([p[0],p[b],p[a]],inside:c,color:Map3DProp.greens[i])
            face([p[1],p[a],p[b]],inside:c,color:Map3DProp.greens[i])
        }
    }
    mutating func face(_ points: [Map3DPoint],inside: Map3DPoint,color: UInt32) {
        guard points.count>=3 else { return }
        let n=(points[1]-points[0]).cross(points[2]-points[0]),c=points.reduce(Map3DPoint.zero) { $0+$1*(1/Float(points.count)) }
        mesh.addFacet(n.dot(c-inside)>=0 ? points : Array(points.reversed()),color:color)
    }
    mutating func add(_ model: Map3DModelPack.Model,at p: Map3DPoint,angle: Float = 0) {
        let c=cosf(angle),s=sinf(angle)
        for i in stride(from:0,to:model.vertices.count,by:3) {
            mesh.appendTriangle(model.vertices[i..<i+3].map { v in
                // The model's normal turned the same way: a scene that draws
                // this mesh as it is (temples, parks, station shops) lights
                // it by these, and a zero normal shades black.
                Map3DVertex(Map3DPoint(c*v.x+s*v.y,v.z,s*v.x-c*v.y)+p,normal:Map3DPoint(c*v.nx+s*v.ny,v.nz,s*v.nx-c*v.ny),
                            color:v.color,layer:v.layer)
            })
        }
    }
    mutating func track(_ start: Float,_ end: Float,_ z: Float,at y: Float = 0) {
        box((start+end)/2,y,z,end-start,3,0.20,Map3DPalette.ballast)
        for side: Float in [-0.5335,0.5335] { box((start+end)/2,y+0.23,z+side,end-start,0.09,0.13,Map3DPalette.railTop) }
        for x in stride(from:start+0.3,to:end,by:Float(1.1)) { box(x,y+0.2,z,0.18,2.0,0.08,Map3DPalette.concrete) }
    }
    mutating func stairs(_ x: Float,_ y: Float,_ z: Float,run: Float = 4,width: Float = 2.4,rise: Float = 2.4) {
        let count=12
        for i in 0..<count { box(x-run/2+(Float(i)+0.5)*run/Float(count),y,z,run/Float(count),width,rise*Float(i+1)/Float(count),Map3DPalette.concrete) }
        for sign: Float in [-1,1] {
            beam(Map3DPoint(x-run/2,y+0.9,z+sign*width/2),Map3DPoint(x+run/2,y+rise+0.9,z+sign*width/2),0.08,Self.steel)
            for t: Float in [0,0.5,1] { box(x-run/2+t*run,y+t*rise,z+sign*width/2,0.08,0.08,0.9,Self.steel) }
        }
    }
    // A CLOSED double-surface roof. No double-sided material or paper-thin
    // patch: every edge and underside remains visible when looking up.
    mutating func canopy(_ x: Float,_ y: Float,_ z: Float,length: Float,width: Float,rise: Float,color: UInt32,wave: Bool = false) {
        let n=12,thickness: Float=0.22
        func p(_ side: Float,_ i: Int,_ down: Float) -> Map3DPoint {
            let t=Float(i)/Float(n),h=wave ? cosf(t*2*Float.pi)*rise : sinf(t*Float.pi)*rise
            return Map3DPoint(x+side*length/2,y+h-down,z-width/2+t*width)
        }
        for i in 0..<n {
            mesh.addQuad(p(-1,i,0),p(-1,i+1,0),p(1,i+1,0),p(1,i,0),color:color)
            mesh.addQuad(p(1,i,thickness),p(1,i+1,thickness),p(-1,i+1,thickness),p(-1,i,thickness),color:Map3DColor.shaded(color,0.7))
            for side: Float in [-1,1] {
                let a=p(side,i,0),b=p(side,i+1,0)
                face([a,b,b-Map3DPoint(0,thickness,0),a-Map3DPoint(0,thickness,0)],inside:Map3DPoint(x,y,z),color:color)
            }
        }
        for i in [0,n] {
            let a=p(-1,i,0),b=p(1,i,0)
            face([a,b,b-Map3DPoint(0,thickness,0),a-Map3DPoint(0,thickness,0)],inside:Map3DPoint(x,y,z),color:color)
        }
    }
}
