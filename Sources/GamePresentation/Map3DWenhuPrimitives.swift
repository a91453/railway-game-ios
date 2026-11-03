import Foundation

// Vehicle-local primitives only. No other train shell, wheelbase or palette is changed.
struct WenhuMesh {
    var kit = StationKitBuilder()
    mutating func prism(_ ring: [Map3DPoint], offset: Map3DPoint, color: UInt32) {
        let centre = ring.reduce(Map3DPoint.zero) { $0 + $1 * (1 / Float(ring.count)) } + offset * 0.5
        kit.face(ring, inside: centre, color: color)
        kit.face(ring.map { $0 + offset }, inside: centre, color: color)
        for i in ring.indices {
            let j = (i + 1) % ring.count
            kit.face([ring[i],ring[j],ring[j]+offset,ring[i]+offset], inside: centre, color: color)
        }
    }
    func clip(_ poly: [Map3DPoint], axis: Int, level: Float, above: Bool) -> [Map3DPoint] {
        guard !poly.isEmpty else { return [] }
        func value(_ p: Map3DPoint) -> Float { (axis == 0 ? p.y : p.z) - level }
        var result: [Map3DPoint] = []
        for i in poly.indices {
            let a=poly[i],b=poly[(i+1)%poly.count],da=value(a),db=value(b)
            let ia=above ? da>=0:da<=0,ib=above ? db>=0:db<=0
            if ia { result.append(a) }
            if ia != ib { result.append(a+(b-a)*(da/(da-db))) }
        }
        var clean: [Map3DPoint] = []
        for p in result {
            if let last=clean.last, (p-last).length<0.000001 { continue }
            clean.append(p)
        }
        if clean.count>1, let a=clean.first, let b=clean.last, (a-b).length<0.000001 { clean.removeLast() }
        return clean
    }
    mutating func sidePane(_ x: Float,_ h: Float,_ side: Float,_ lateral: Float,_ length: Float,_ height: Float,_ color: UInt32, segments: Int = 4) {
        let radius: Float = min(0.10,min(length,height)/4)
        var ring: [Map3DPoint] = []
        for (cx,cy,start) in [(x+length/2-radius,h+height-radius,Float(0)),(x-length/2+radius,h+height-radius,Float.pi/2),(x-length/2+radius,h+radius,Float.pi),(x+length/2-radius,h+radius,Float.pi*1.5)] {
            for i in 0...segments {
                let a=start+Float(i)*Float.pi/(2*Float(segments))
                ring.append(Map3DPoint(cx+cosf(a)*radius,cy+sinf(a)*radius,side*lateral))
            }
        }
        prism(ring,offset:Map3DPoint(0,0,side*0.018),color:color)
    }
    mutating func wheel(_ x: Float, _ h: Float, _ lateral: Float, radius: Float, width: Float, horizontal: Bool, color: UInt32, sides: Int) {
        let ring = (0..<sides).map { i -> Map3DPoint in
            let a = Float(i) * 2 * Float.pi / Float(sides)
            return horizontal ? Map3DPoint(x+cosf(a)*radius,h,lateral+sinf(a)*radius)
                : Map3DPoint(x+cosf(a)*radius,h+sinf(a)*radius,lateral-width/2)
        }
        prism(ring, offset: horizontal ? Map3DPoint(0,width,0) : Map3DPoint(0,0,width), color: color)
    }
}
