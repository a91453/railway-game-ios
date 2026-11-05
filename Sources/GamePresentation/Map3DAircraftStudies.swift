import Foundation

/// On-demand geometry for studies. Native x forward, y left, z up; metres.
/// These models are not registered in the game scene or used for operations.
public enum Map3DAircraftStudies {
    public enum Kind: String, CaseIterable, Sendable {
        case commuter19, regional70, narrowJet, wideJet
    }
    public struct Dimensions: Sendable {
        public let length: Float
        public let wingspan: Float
        public let height: Float
    }
    public struct Joint: Sendable {
        public let part: String
        public let pivot: Map3DPoint
        public let axis: Map3DPoint
        public let lower: Float
        public let upper: Float
    }
    public struct Metadata: Sendable {
        public let dimensions: Dimensions
        public let door: Map3DPoint
        public let joints: [Joint]
        public let glowParts: [String]
    }
    public static func metadata(_ kind: Kind) -> Metadata {
        let d=dimensions(kind)
        let radius:Float = switch kind { case .commuter19: 1.20; case .regional70: 1.45; case .narrowJet: 1.98; case .wideJet: 2.98 }
        let wingHeight:Float = switch kind { case .commuter19: 2.944; case .regional70: 3.544; case .narrowJet: 2.5474; case .wideJet: 3.5274 }
        let wingX:Float = switch kind { case .commuter19:4.2;case .regional70:5;case .narrowJet:7.4;case .wideJet:10 }
        let doorHeight: Float = switch kind { case .commuter19: 1.8; case .regional70: 3.2; case .narrowJet: 4.3; case .wideJet: 5.9 }
        let props: [Joint] = (kind == .commuter19 || kind == .regional70) ? [-1,1].map { side in
            Joint(part:"propeller-\(side)",pivot:Map3DPoint(wingX+0.03,Float(side) * (radius+d.wingspan*0.12),wingHeight-0.05),axis:Map3DPoint(1,0,0),lower:0,upper:2 * .pi)
        } : []
        return Metadata(dimensions:d,door:Map3DPoint(d.length * 0.35,radius,doorHeight),
            joints:props + [Joint(part:"landing-gear",pivot:Map3DPoint(0,0,1),axis:Map3DPoint(0,1,0),lower:0,upper:kind == .commuter19 ? 0 : 1.2),
                            Joint(part:"door",pivot:Map3DPoint(d.length * 0.35,radius,doorHeight),axis:Map3DPoint(0,0,1),lower:0,upper:1.57)],
            glowParts:["left-red","right-green","tail-white","anti-collision-red","strobe-white","cabin-windows"])
    }
    public static func dimensions(_ kind: Kind) -> Dimensions {
        switch kind {
        case .commuter19: Dimensions(length:16.56,wingspan:16.97,height:4.86)
        case .regional70: Dimensions(length:27.17,wingspan:27.05,height:7.65)
        case .narrowJet: Dimensions(length:44.51,wingspan:35.80,height:11.76)
        case .wideJet: Dimensions(length:66.80,wingspan:64.75,height:17.05)
        }
    }
    public static func model(_ kind: Kind, far: Bool = false, palette: Int = 0) -> Map3DModelPack.Model {
        let d=dimensions(kind), dark=Map3DPalette.playerRim
        let paint=[Map3DPalette.counters[1],Map3DPalette.gymGreen,Map3DPalette.shopAwnings[1]][max(0,min(2,palette))]
        let white=Map3DPalette.tileWhite, steel=Map3DPalette.tankStand, glass=Map3DPalette.glazing
        let r:Float = switch kind { case .commuter19: 1.20; case .regional70: 1.45; case .narrowJet: 1.98; case .wideJet: 2.98 }
        let floor:Float = switch kind { case .commuter19: 0.88; case .regional70: 1.05; case .narrowJet: 1.30; case .wideJet: 1.65 }
        let belly=floor+r, high=(kind == .commuter19 || kind == .regional70)
        let wingHeight=belly+(high ? r*0.72 : -r*0.37)
        var b=StationKitBuilder()
        b.aircraftHull(d.length,r,belly,far,white)
        for side:Float in [-1,1] {
            b.box(d.length*0.405,belly+r*0.18,side*r*0.61,d.length*0.075,r*0.48,0.055,dark)
        }
        if !far {
            for side:Float in [-1,1] { b.box(d.length*0.02,belly-r*0.12,side*r*1.008,d.length*0.55,0.16,0.045,paint) }
            let windows=max(4,Int(d.length/2.2))
            for i in 0..<windows {
                let x = -d.length*0.27+(Float(i)+0.5)*d.length*0.66/Float(windows)
                for side:Float in [-1,1] { b.box(x,belly+r*0.23,side*r*0.995,0.35,0.30,0.035,glass) }
            }
            b.box(d.length*0.35,metadata(kind).door.z-0.65,r+0.02,0.8,1.3,0.04,steel)
        }
        for side:Float in [-1,1] {
            let root:Float = high ? d.length*0.14 : d.length*0.105
            let wingX:Float = switch kind { case .commuter19:4.2;case .regional70:5;case .narrowJet:7.4;case .wideJet:10 }
            let span=d.wingspan*0.5,dihedral:Float=high ? 0.35 : (kind == .wideJet ? 0.8 : 0.55)
            b.aircraftWing([(wingX-root*0.60,side*r*0.82),(wingX+root,side*r*0.82),
                            (wingX-root*0.62,side*span),(wingX-root*1.22,side*span)],
                           wingHeight,dihedral,span,white)
            b.aircraftWing([(wingX-root*1.17,side*(span-1.15)),(wingX-root*0.54,side*(span-1.15)),
                            (wingX-root*0.62,side*span),(wingX-root*1.22,side*span)],
                           wingHeight+0.105,dihedral,span,paint)
            let tailZ:Float=kind == .regional70 ? d.height-0.28 : belly+r*0.56
            b.aircraftWing([(-d.length*0.46,0),(-d.length*0.31,0),
                            (-d.length*0.39,side*d.wingspan*0.17),(-d.length*0.48,side*d.wingspan*0.17)],
                           tailZ,0.07,d.wingspan*0.17,paint)
            let ex=wingX-1.2,ey=side*(r+d.wingspan*0.12)
            if high {
                b.aircraftNacelle(ex-0.95,ex+1.15,ey,wingHeight-0.05,r*0.28,far,steel)
                b.box(ex+1.18,wingHeight-0.05,ey,0.16,0.20,0.20,dark)
                b.box(ex+1.23,wingHeight-1.0,ey,0.06,2.0,0.13,dark)
                if !far { b.box(ex+1.24,wingHeight-0.05,ey,0.06,0.13,1.64,dark) }
            } else {
                let er=max(0.75,r*0.5),length:Float=kind == .narrowJet ? 3.4 : 4.5
                b.aircraftNacelle(ex-length*0.5,ex+length*0.5,ey,max(wingHeight-er*0.70,0.42+er),er,far,steel)
            }
            if !far { b.box(0,wingHeight,side*(d.wingspan*0.5-0.12),0.22,0.15,0.22,side>0 ? Map3DPalette.shopAwnings[1] : Map3DPalette.gymGreen) }
        }
        b.aircraftFin([(-d.length*0.49,belly+r*0.26),(-d.length*0.25,belly+r*0.26),
                       (-d.length*0.37,d.height),(-d.length*0.43,d.height)],paint)
        for (x,side) in [(d.length*0.18,Float(0)),(-d.length*0.10,d.wingspan*0.11),(-d.length*0.10,-d.wingspan*0.11)] {
            b.box(x,0,side,0.38,0.30,floor,dark)
        }
        return .flat(named:"aircraft-\(kind.rawValue)-\(far ? "far" : "near")",from:b.mesh)
    }
}

private extension StationKitBuilder {
    mutating func aircraftPrism(_ a:[Map3DPoint],_ b:[Map3DPoint],_ color:UInt32) {
        let inside=(a+b).reduce(Map3DPoint.zero,+)*(1/Float(a.count+b.count))
        face(a,inside:inside,color:color);face(b,inside:inside,color:color)
        for i in a.indices { let j=(i+1)%a.count;face([a[i],a[j],b[j],b[i]],inside:inside,color:color) }
    }
    mutating func aircraftHull(_ length:Float,_ radius:Float,_ belly:Float,_ far:Bool,_ color:UInt32) {
        let stations:[(Float,Float)]=[(-0.50,0.10),(-0.45,0.52),(-0.34,0.91),(-0.19,1),
                                    (0.20,1),(0.36,0.88),(0.46,0.52),(0.50,0.08)]
        let sides=far ? 12 : 20
        let rings=stations.map { station in (0..<sides).map { i in
            let angle=Float(i)*2*Float.pi/Float(sides)
            return Map3DPoint(length*station.0,belly+radius*station.1*sinf(angle),radius*station.1*cosf(angle))
        } }
        let inside=Map3DPoint(0,belly,0)
        face(rings[0],inside:inside,color:color);face(rings[rings.count-1],inside:inside,color:color)
        for k in 0..<(rings.count-1) { for i in 0..<sides {
            let j=(i+1)%sides
            face([rings[k][i],rings[k][j],rings[k+1][j],rings[k+1][i]],inside:inside,color:color)
        } }
    }
    mutating func aircraftWing(_ outline:[(Float,Float)],_ height:Float,_ rise:Float,_ halfSpan:Float,_ color:UInt32) {
        let lower=outline.map { Map3DPoint($0.0,height+rise*abs($0.1)/halfSpan-0.10,$0.1) }
        let upper=outline.map { Map3DPoint($0.0,height+rise*abs($0.1)/halfSpan+0.10,$0.1) }
        aircraftPrism(lower,upper,color)
    }
    mutating func aircraftFin(_ profile:[(Float,Float)],_ color:UInt32) {
        let a=profile.map { Map3DPoint($0.0,$0.1,-0.135) }
        let b=profile.map { Map3DPoint($0.0,$0.1,0.135) }
        aircraftPrism(a,b,color)
    }
    mutating func aircraftNacelle(_ x0:Float,_ x1:Float,_ lateral:Float,_ height:Float,_ radius:Float,_ far:Bool,_ color:UInt32) {
        let stations:[(Float,Float)]=[(x0,radius*0.58),(x0+(x1-x0)*0.14,radius),
                                      (x1-(x1-x0)*0.10,radius),(x1,radius*0.43)]
        let sides=far ? 8 : 12
        let rings=stations.map { station in (0..<sides).map { i in
            let angle=Float(i)*2*Float.pi/Float(sides)
            return Map3DPoint(station.0,height+station.1*sinf(angle),lateral+station.1*cosf(angle))
        } }
        let inside=Map3DPoint((x0+x1)*0.5,height,lateral)
        face(rings[0],inside:inside,color:color);face(rings[rings.count-1],inside:inside,color:color)
        for k in 0..<(rings.count-1) { for i in 0..<sides {
            let j=(i+1)%sides
            face([rings[k][i],rings[k][j],rings[k+1][j],rings[k+1][i]],inside:inside,color:color)
        } }
    }
}
