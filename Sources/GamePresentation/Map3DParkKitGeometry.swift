import Foundation

extension StationKitBuilder {
    static let parkWood=Map3DPalette.counters[1]
    static let parkBlue=Map3DPalette.canopy
    static let parkRed=Map3DPalette.templeRidge
    static let parkGreen=Map3DProp.greens[1]
    mutating func park(_ p: Map3DParkKit.Part) {
        switch p.category { case .playground: parkPlayground(p);case .sport: parkSport(p);case .garden: parkGarden(p) }
    }
    mutating func parkRail(_ a: Map3DPoint,_ b: Map3DPoint,_ radius: Float,_ color: UInt32) {
        civicTube(a,b,radius:radius,color:color,sides:8)
    }
    mutating func parkPost(_ x: Float,_ z: Float,_ height: Float,_ color: UInt32 = Self.steel) {
        cylinder(x,0,z,radius:0.055,height:height,color:color,sides:8)
    }
    mutating func parkLine(_ ax: Float,_ az: Float,_ bx: Float,_ bz: Float,_ y: Float = 0.085) {
        let a=Map3DPoint(ax,y,az),b=Map3DPoint(bx,y,bz)
        beam(a,b,0.045,Self.white)
    }
    mutating func parkCircle(_ x: Float,_ y: Float,_ z: Float,radius: Float,color: UInt32,segments: Int = 32) {
        for i in 0..<segments { let a=Float(i)*2*Float.pi/Float(segments),b=Float(i+1)*2*Float.pi/Float(segments)
            parkRail(Map3DPoint(x+cosf(a)*radius,y,z+sinf(a)*radius),Map3DPoint(x+cosf(b)*radius,y,z+sinf(b)*radius),0.018,color)
        }
    }
    mutating func parkNet(_ x: Float,_ y: Float,_ z: Float,width: Float,height: Float) {
        for i in 0...12 { let dz=Float(i)*width/12-width/2;box(x,y,z+dz,0.018,0.018,height,Self.white) }
        for i in 0...6 { box(x,y+Float(i)*height/6,z,0.018,width,0.018,Self.white) }
    }
    mutating func parkSlide(height: Float,length: Float,width: Float) {
        let start=Map3DPoint(-length/2,height,0),end=Map3DPoint(length/2,0.12,0)
        // Closed ramp mesh, side lips and connected landing feet.
        let points=[start+Map3DPoint(0,0,-width/2),start+Map3DPoint(0,0,width/2),end+Map3DPoint(0,0,width/2),end+Map3DPoint(0,0,-width/2)]
        let lower=points.map { $0-Map3DPoint(0,0.06,0) },inside=(start+end)*0.5-Map3DPoint(0,0.03,0)
        face(points,inside:inside,color:Self.parkBlue);face(lower,inside:inside,color:Self.parkBlue)
        for i in 0..<4 { let j=(i+1)%4;face([points[i],points[j],lower[j],lower[i]],inside:inside,color:Self.parkBlue) }
        for z: Float in [-width/2,width/2] { beam(start+Map3DPoint(0,0.09,z),end+Map3DPoint(0,0.09,z),0.18,Self.parkRed) }
        for x in [-length/2,length/2] { for z: Float in [-width/2,width/2] { box(x,0,z,0.10,0.10,x<0 ? height : 0.14,Self.steel) } }
        box(-length/2-0.28,height-0.08,0,0.65,width+0.2,0.08,Self.parkWood)
        for z: Float in [-width/2,width/2] {
            beam(Map3DPoint(-length/2-1,0.04,z),Map3DPoint(-length/2-0.4,height,z),0.08,Self.steel)
        }
        for i in 1...5 { let f=Float(i)/5;box(-length/2-1+0.6*f,height*f-0.04,0,0.16,width,0.06,Self.parkWood) }
    }
    mutating func parkRectCourt(length: Float,width: Float,color: UInt32) {
        box(0,0,0,length+2,width+2,0.08,color)
        for z in [-width/2,width/2] { parkLine(-length/2,z,length/2,z) }
        for x in [-length/2,0,length/2] { parkLine(x,-width/2,x,width/2) }
    }
}
