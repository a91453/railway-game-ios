import Foundation

extension StationKitBuilder {
    static let civicWood=Map3DPalette.counters[1]
    static let civicRed=Map3DPalette.templeRidge
    static let civicGreen=Map3DProp.greens[1]
    mutating func cylinder(_ x: Float,_ y: Float,_ z: Float,_ radius: Float,_ height: Float,_ color: UInt32,sides: Int = 12) {
        cylinder(x,y,z,radius:radius,height:height,color:color,sides:sides)
    }
    mutating func civic(_ part: Map3DCivicKit.Part) {
        switch part.category {
        case .building: civicBuilding(part)
        case .furniture: civicFurniture(part)
        case .culture: civicCulture(part)
        }
    }
    mutating func civicTube(_ a: Map3DPoint,_ b: Map3DPoint,radius: Float,color: UInt32,sides: Int = 12) {
        guard let axis=(b-a).normalized,let u=axis.cross(abs(axis.y)>0.95 ? Map3DPoint(1,0,0) : .up).normalized else { return }
        let v=axis.cross(u),inside=(a+b)*0.5
        func ring(_ p: Map3DPoint) -> [Map3DPoint] { (0..<sides).map { i in let t=Float(i)*2*Float.pi/Float(sides);return p+u*(cosf(t)*radius)+v*(sinf(t)*radius) } }
        let p=ring(a),q=ring(b);face(p,inside:inside,color:color);face(q,inside:inside,color:color)
        for i in 0..<sides { let j=(i+1)%sides;face([p[i],p[j],q[j],q[i]],inside:inside,color:color) }
    }
    mutating func civicCushion(_ x: Float,_ y: Float,_ z: Float,_ length: Float,_ width: Float,_ height: Float,_ color: UInt32) {
        let r=min(height*0.25,0.06),a=x-length/2,b=x+length/2
        let outline=[(a+r,y),(b-r,y),(b,y+r),(b,y+height-r),(b-r,y+height),(a+r,y+height),(a,y+height-r),(a,y+r)]
        let p=outline.map { Map3DPoint($0.0,$0.1,z-width/2) },q=outline.map { Map3DPoint($0.0,$0.1,z+width/2) },inside=Map3DPoint(x,y+height/2,z)
        face(p,inside:inside,color:color);face(q,inside:inside,color:color)
        for i in 0..<8 { let j=(i+1)%8;face([p[i],p[j],q[j],q[i]],inside:inside,color:color) }
    }
    mutating func civicLegs(_ x: Float,_ y: Float,_ z: Float,length: Float,width: Float,height: Float,color: UInt32 = Self.civicWood) {
        for dx in [-length/2,length/2] { for dz in [-width/2,width/2] { box(x+dx,y,z+dz,0.07,0.07,height,color) } }
    }
    mutating func civicBoard(_ x: Float,_ y: Float,_ z: Float,width: Float,height: Float,color: UInt32) {
        box(x,y,z,0.08,width,height,Self.steel);box(x+0.048,y+0.06,z,0.02,width-0.12,height-0.12,color)
    }
    mutating func civicWindowBands(_ x: Float,_ y: Float,_ z: Float,length: Float,width: Float,floors: Int,bays: Int = 4) {
        for floor in 0..<floors {
            for i in 0..<bays {
                let offset=(Float(i)+0.5)*width/Float(bays)-width/2
                pane(x+length/2,y+0.85+Float(floor)*3.0,z+offset,width/Float(bays)*0.65,1.35)
                box(x-length/2-0.012,y+0.85+Float(floor)*3,z+offset,0.025,width/Float(bays)*0.65,1.35,Self.glass)
            }
            for sign: Float in [-1,1] { for i in 0..<3 { let offset=(Float(i)+0.5)*length/3-length/2
                box(x+offset,y+0.85+Float(floor)*3,z+sign*(width/2+0.012),length*0.21,0.025,1.35,Self.glass)
            } }
        }
    }
    mutating func civicBlock(_ x: Float = 0,_ y: Float = 0,_ z: Float = 0,length: Float,width: Float,floors: Int,color: UInt32,roof: UInt32 = Map3DPalette.roof) {
        box(x,y,z,length,width,Float(floors)*3,color)
        civicWindowBands(x,y,z,length:length,width:width,floors:floors)
        box(x,y+Float(floors)*3,z,length+0.2,width+0.2,0.18,roof)
    }
    mutating func civicEntrance(_ x: Float,_ y: Float,_ z: Float,width: Float = 2) {
        pane(x,y,z,width,2.3)
        box(x+0.7,y+2.6,z,1.6,width+1.0,0.15,Map3DPalette.canopy)
        for side: Float in [-1,1] { box(x+1.2,y,z+side*(width/2+0.35),0.12,0.12,2.6,Self.steel) }
    }
    mutating func civicTempleRoof(_ x: Float,_ y: Float,_ z: Float,length: Float,width: Float,rise: Float) {
        // Put the ridge along the longer dimension; its straight section must
        // coincide with the actual hip roof, not float above its sloping faces.
        let along=width>length ? Map3DPoint(0,0,1) : Self.forward
        let long=max(length,width),short=min(length,width),base=Map3DPoint(x,y,z)
        mesh.addHipRoof(base:base,forward:along,length:long,width:short,rise:rise,overhang:0.5,sweep:0.40,color:Map3DPalette.templeRoof)
        box(x,y-0.12,z,length+1,width+1,0.52,Map3DPalette.templeRoof)
        let ridge=base+Map3DPoint(0,rise,0),end=max(0,(long-short)/2)
        if end>0 { beam(ridge-along*end,ridge+along*end,0.12,Self.civicRed) }
        for sign: Float in [-1,1] {
            beam(ridge+along*(sign*end),ridge+along*(sign*(end+0.45))+Map3DPoint(0,0.18,0),0.10,Self.civicRed)
            beam(ridge+along*(sign*(end+0.45))+Map3DPoint(0,0.18,0),ridge+along*(sign*(end+0.85))+Map3DPoint(0,0.55,0),0.08,Self.civicRed)
        }
    }
}
