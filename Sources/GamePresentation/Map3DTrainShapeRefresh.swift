import Foundation

/// Independent photo-led static studies. Decision 408: the E200 draws the
/// Chu-Kuang sets' locomotive. The 700T's four recipe cars drew the
/// high-speed set beside it until decision 988 (``Map3DTHSR700T``, the
/// owner's old cars, has their place); they were deleted with their tests
/// and tools on 2026-11-27 (the owner: a model a newer one replaces goes),
/// and only the 700T's colours, which the new cars wear too, stay here.
public enum Map3DTrainShapeRefresh {
    public static let highSpeedBodyColor=Map3DPalette.shopAwnings[3]
    /// Decision 983: the 700T's band, the real train's orange; the teal it
    /// was built in until then (the game's own colour, decision 243's
    /// time) is the paint a player can choose instead.
    public static let highSpeedBandColor=Map3DPalette.highSpeedOrange
    public static let highSpeedGameBandColor=Map3DPalette.shopAwnings[0]
    /// Decision 983: the paints a line's 700T sets can wear.
    static let highSpeedPaints=TrainPaintFamily(
        id:"highSpeed",sets:[Map3DTHSR700T.key],english:"700T",chinese:"700T",
        ownEnglish:"Orange band",ownChinese:"橘色帶",ownSwatch:highSpeedBandColor,
        paints:[TrainPaint(id:"teal",english:"Teal band",chinese:"青綠帶",swatch:highSpeedGameBandColor,
                           swaps:[TrainPaint.Swap(from:highSpeedBandColor,to:highSpeedGameBandColor)])])
    /// The E200's model's name (decision 408).
    public static let ids = ["refresh-e200"]
    public static func model(_ id: String) -> Map3DModelPack.Model { model(id, far: false) }
    /// Decision 825: the E200's livery, the parts of it a repaint changes.
    public struct E200Paint: Sendable {
        public let lower: UInt32, upper: UInt32, line: UInt32, chevron: UInt32, roof: UInt32
        /// TRA orange (photographs) below, ivory above and on the roof.
        public static let standard = E200Paint(lower: e200Orange, upper: e200Ivory, line: e200Orange, chevron: e200Ivory,
                                               roof: e200Roof)
    }
    public static let e200Orange = Map3DColor.rgb(0xE8692F)
    public static let e200Ivory = Map3DColor.rgb(0xE9DCBC)
    /// The flat of the roof as photographs show it, weathered grey (the
    /// rounded edges keep the sides' ivory), so from the game's camera the
    /// orange still reads.
    public static let e200Roof = Map3DColor.rgb(0xBDB8AA)
    /// Decision 825: the E200 in `paint`, near or `far`, its front lamps
    /// not yet lit (``Map3DTrainSet/lit(_:front:)`` lights them).
    public static func e200(_ paint: E200Paint, far: Bool, named name: String) -> Map3DModelPack.Model {
        var b = StationKitBuilder()
        b.refreshElectric(paint: paint, far: far)
        return .flat(named: name, from: b.mesh)
    }
    /// Decision 825: the E200, near or `far` (decision 420's light
    /// version, as ``StationKitBuilder/refreshElectric(paint:far:)`` makes
    /// it), named `id` (``ids``).
    public static func model(_ id: String, far: Bool) -> Map3DModelPack.Model {
        var b = StationKitBuilder()
        b.refreshElectric(far: far)
        return .flat(named: far ? id + "-far" : id, from: b.mesh)
    }
}

extension StationKitBuilder {
    private var refreshWhite: UInt32 { Map3DPalette.shopAwnings[3] }
    private var refreshGlass: UInt32 { Map3DColor.shaded(Map3DPalette.glazing,0.5) }
    private mutating func refreshRunning(_ centres: [Float], axles: [Float], radius: Float, gauge: Float) {
        // Twelve-sided cross sections include the true bottom contact point.
        let contactHeight=radius
        for x in centres {
            box(x,0.49,0,axles.last! - axles.first! + 0.8,gauge+0.22,0.25,Self.ink)
            for dx in axles {
                civicTube(Map3DPoint(x+dx,contactHeight,-gauge/2),Map3DPoint(x+dx,contactHeight,gauge/2),radius:0.075,color:Self.steel,sides:6)
                for s: Float in [-1,1] {
                    civicTube(Map3DPoint(x+dx,contactHeight,s*(gauge/2-0.04)),Map3DPoint(x+dx,contactHeight,s*(gauge/2+0.15)),radius:radius,color:Map3DStreetModel.tyre,sides:12)
                }
            }
            box(x,0.72,0,1.2,gauge,0.35,Self.steel)
            for side: Float in [-1,1] {
                let outer=side*(gauge/2+0.22)
                box(x,0.48,outer,axles.last!-axles.first!+0.74,0.16,0.23,Self.steel)
                for dx in axles {
                    box(x+dx,0.36,outer,0.37,0.19,0.28,Self.ink)
                    civicTube(Map3DPoint(x+dx,contactHeight,outer),Map3DPoint(x+dx,contactHeight,outer+side*0.035),radius:radius*0.43,color:Self.steel,sides:12)
                    for coil: Float in [-0.3,0.3] { cylinder(x+dx+coil,0.58,outer,radius:0.10,height:0.23,color:Self.ink,sides:8) }
                }
            }
        }
    }
    private mutating func refreshPanto(_ x: Float, roof: Float, singleArm: Bool = false) {
        box(x,roof,0,1.8,1.15,0.12,Self.steel)
        for z: Float in [-0.43,0.43] {
            cylinder(x,roof+0.12,z,radius:0.12,height:0.18,color:refreshWhite,sides:8)
            if singleArm {
                let hand: Float = x>=0 ? 1:-1
                beam(Map3DPoint(x-hand*0.45,roof+0.28,z),Map3DPoint(x+hand*0.65,roof+0.58,z),0.055,Self.ink)
                beam(Map3DPoint(x+hand*0.65,roof+0.58,z),Map3DPoint(x,roof+0.90,z),0.045,Self.ink)
            } else {
                for sign: Float in [-1,1] {
                    beam(Map3DPoint(x,roof+0.28,z),Map3DPoint(x+sign*0.65,roof+0.57,z),0.045,Self.ink)
                    beam(Map3DPoint(x+sign*0.65,roof+0.57,z),Map3DPoint(x,roof+0.9,z),0.045,Self.ink)
                }
            }
        }
        box(x,roof+0.88,0,0.16,1.5,0.07,Self.steel)
    }
    /// Decision 825: the E200 as the real locomotive (Commons photographs of
    /// E217, E227 and the reference's garage E200): TRA orange below, ivory
    /// above and on the roof with an orange line in the ivory along each
    /// side, an ivory V on each orange face, the two windscreens in black
    /// rubber frames, the twin headlamps over them, black number plates and
    /// a black and yellow striped pilot. `paint` is the livery (the Ming-Ri
    /// repaints it, decision 483); `far`: the light version drawn from 500 m
    /// out (decision 420's rules: the same shell, paint, lamps and length,
    /// plain running gear, no small fittings).
    mutating func refreshElectric(paint: Map3DTrainShapeRefresh.E200Paint = .standard,far: Bool = false) {
        // E200 dimensions from the project's sourced engineering catalog.
        // Black parts black (``Map3DPalette/dark``), not the kit's navy ink.
        let black = Map3DPalette.dark
        let half: Float = 8.5245, w: Float = 1.486, floor: Float = 1.13, eave: Float = 3.35, top: Float = 3.92
        // The side's bands (photographs): orange to 2.50 m, a thin ivory and
        // a thin orange line, the ivory up to the roof's grey flat.
        let lowerTop: Float = 2.50, lineBottom: Float = 2.57, lineTop: Float = 2.64
        let profile: [(Float,Float)] = [(floor,-w),(lowerTop,-w),(lineBottom,-w),(lineTop,-w),(eave,-w),(top,-1.14),
                                        (top,1.14),(eave,w),(lineTop,w),(lineBottom,w),(lowerTop,w),(floor,w)]
        let bands = [paint.lower,paint.upper,paint.line,paint.upper,paint.upper,paint.roof,
                     paint.upper,paint.upper,paint.line,paint.upper,paint.lower,black]
        // The cab roof raked back 0.18 m over the windscreens.
        let rings = [-half,-half+0.42,half-0.42,half].map { x in
            profile.map { h,z in Map3DPoint(x.sign == .minus ? x + (h>eave ? 0.18:0) : x - (h>eave ? 0.18:0),h,z) }
        }
        let inside = Map3DPoint(0,2.5,0)
        for k in 0..<3 { for i in profile.indices {
            let j=(i+1)%profile.count
            face([rings[k][i],rings[k][j],rings[k+1][j],rings[k+1][i]],inside:inside,color:bands[i])
        } }
        for s: Float in [-1,1] {
            let x=s*half
            // The face: orange, the ivory V from the side's line down to a
            // point at the middle, ivory from under the windscreens up.
            let vTopCorner: Float = 2.50, vBottomCorner: Float = 2.30, vTopMiddle: Float = 1.92, vBottomMiddle: Float = 1.70
            for side: Float in [-1,1] {
                func p(_ z: Float,_ h: Float) -> Map3DPoint { Map3DPoint(x,h,side*z) }
                face([p(0,floor),p(w,floor),p(w,vBottomCorner),p(0,vBottomMiddle)],inside:inside,color:paint.lower)
                face([p(0,vBottomMiddle),p(w,vBottomCorner),p(w,vTopCorner),p(0,vTopMiddle)],inside:inside,color:paint.chevron)
                face([p(0,vTopMiddle),p(w,vTopCorner),p(w,lineTop),p(0,lineTop)],inside:inside,color:paint.lower)
                face([p(0,lineTop),p(w,lineTop),p(w,eave),p(0,eave)],inside:inside,color:paint.upper)
            }
            let r=s<0 ? 0:3
            face([rings[r][4],rings[r][5],rings[r][6],rings[r][7]],inside:inside,color:paint.upper)
            // Two windscreens, each in a black rubber frame, raked with the
            // roof above the eave.
            func raked(_ outline: [(Float,Float)],proud: Float,thickness: Float,color: UInt32) {
                for upper in [false,true] {
                    var clipped: [(Float,Float)]=[]
                    for i in outline.indices {
                        let a=outline[i],b=outline[(i+1)%outline.count]
                        let ia=upper ? a.1>=eave:a.1<=eave,ib=upper ? b.1>=eave:b.1<=eave
                        if ia { clipped.append(a) }
                        if ia != ib { let t=(eave-a.1)/(b.1-a.1);clipped.append((a.0+(b.0-a.0)*t,eave)) }
                    }
                    guard clipped.count>=3 else { continue }
                    let q=clipped.map { lateral,h in Map3DPoint(x-s*max(0,h-eave)*0.18/0.57+s*proud,h,lateral) }
                    refreshPanel(q,thickness:thickness,color:color)
                }
            }
            for z: Float in [-0.68,0.68] {
                if far {
                    raked([(z-0.62,2.93),(z+0.62,2.93),(z+0.62,3.64),(z-0.62,3.64)],proud:0.012,thickness:0.012,color:black)
                    raked([(z-0.58,2.96),(z+0.58,2.96),(z+0.58,3.61),(z-0.58,3.61)],proud:0.026,thickness:0.025,color:refreshGlass)
                } else {
                    raked(refreshRoundedOutline(x:z,y:3.285,width:1.26,height:0.75,radius:0.11),proud:0.012,thickness:0.012,color:black)
                    raked(refreshRoundedOutline(x:z,y:3.285,width:1.16,height:0.65,radius:0.075),proud:0.026,thickness:0.025,color:refreshGlass)
                }
            }
            // The headlamps' housing on the cab roof and its twin lamps.
            box(x-s*0.12,3.70,0,0.24,0.62,0.18,paint.upper)
            for z: Float in [-0.15,0.15] {
                civicTube(Map3DPoint(x-s*0.01,3.79,z),Map3DPoint(x+s*0.035,3.79,z),radius:0.095,color:Map3DPalette.tunnelLamp,sides:far ? 8:12)
            }
            // The number plates under the windscreens.
            for z: Float in [-0.68,0.68] { box(x+s*0.015,2.30,z,0.03,0.46,0.17,black) }
            // The pilot: black, its face striped yellow in a V like the
            // body's, the coupler in the middle.
            let pilotBottom: Float = 0.45, pilotTop: Float = 1.11, pilotHalf: Float = 1.30
            box(x+s*0.0,pilotBottom,0,0.11,2*pilotHalf,pilotTop-pilotBottom,black)
            let front=x+s*0.067, period: Float = 0.28, slope: Float = 1.0
            for side: Float in [-1,1] {
                let rectangle: [(Float,Float)]=[(0,pilotBottom),(pilotHalf,pilotBottom),(pilotHalf,pilotTop),(0,pilotTop)]
                func clip(_ input: [(Float,Float)],_ edge: Float,_ keepAbove: Bool) -> [(Float,Float)] {
                    var output: [(Float,Float)]=[]
                    func score(_ p: (Float,Float)) -> Float { (p.1-slope*p.0)/period-edge }
                    for i in input.indices {
                        let a=input[i],b=input[(i+1)%input.count],fa=score(a),fb=score(b)
                        let insideA=keepAbove ? fa>=0:fa<=0,insideB=keepAbove ? fb>=0:fb<=0
                        if insideA { output.append(a) }
                        if insideA != insideB { let t=fa/(fa-fb);output.append((a.0+(b.0-a.0)*t,a.1+(b.1-a.1)*t)) }
                    }
                    return output
                }
                let low=Int(((pilotBottom-slope*pilotHalf)/period).rounded(.down)),high=Int((pilotTop/period).rounded(.up))
                for band in low...high where band.isMultiple(of:2) {
                    let q=clip(clip(rectangle,Float(band),true),Float(band)+0.5,false)
                    guard q.count>=3 else { continue }
                    face(q.map { Map3DPoint(front,$0.1,side*$0.0) },inside:Map3DPoint(x,0.8,0),color:Map3DG12.hazard)
                }
            }
            box(x+s*0.15,0.83,0,0.44,0.34,0.22,black)
            if !far {
                // Marker lamps at the face's top corners, and the round
                // lamp housings low at its corners.
                for z: Float in [-1.22,1.22] {
                    civicTube(Map3DPoint(x,3.62,z),Map3DPoint(x+s*0.03,3.62,z),radius:0.06,color:Self.steel,sides:8)
                    civicTube(Map3DPoint(x,1.42,z*0.95),Map3DPoint(x+s*0.04,1.42,z*0.95),radius:0.10,color:black,sides:8)
                }
            }
            // The cab doors' seams and windows, the cab's side windows.
            for side: Float in [-1,1] {
                let dx=x-s*1.32, out=side*(w+0.006)
                if !far {
                    for edge: Float in [-0.315,0.315] { box(dx+edge,1.30,out,0.03,0.012,2.0,black) }
                    box(dx,3.27,out,0.66,0.012,0.03,black)
                }
                box(dx,2.65,side*(w+0.017),0.44,0.012,0.57,refreshGlass)
                box(dx+s*0.65,2.73,side*(w+0.018),0.84,0.012,0.59,refreshGlass)
            }
        }
        box(0,0.99,0,16.8,2.65,0.14,black)
        if far {
            // Two bogies, three axles each, plain.
            for x: Float in [-5.1,5.1] {
                box(x,0.40,0,3.9,2.0,0.58,black)
                for dx: Float in [-1.5,0,1.5] { for side: Float in [-1,1] {
                    civicTube(Map3DPoint(x+dx,0.51,side*0.98),Map3DPoint(x+dx,0.51,side*1.10),radius:0.51,color:Map3DStreetModel.tyre,sides:8)
                } }
            }
            box(0,0.38,0,4.9,1.95,0.59,Self.steel)
            // Each pantograph as one arm, its head as high as the near
            // one's, so the far car keeps the near car's box.
            for x: Float in [-4.8,4.8] {
                box(x,top,0,1.8,1.15,0.12,Self.steel)
                beam(Map3DPoint(x-0.6,top+0.12,0),Map3DPoint(x+0.05,top+0.88,0),0.07,black)
                box(x,top+0.88,0,0.16,1.5,0.07,Self.steel)
            }
            box(1.72,top,0,3.85,1.88,0.14,Self.steel)
            box(1.72,top+0.14,0,3.58,1.55,0.23,paint.roof)
            return
        }
        refreshRunning([-5.1,5.1],axles:[-1.5,0,1.5],radius:0.51,gauge:1.067)
        for s: Float in [-1,1] {
            // Panel seams down each side, the orange body otherwise smooth.
            for x: Float in [-5.9,0,5.9] { box(x,1.35,s*(w+0.006),0.025,0.012,2.0,Map3DColor.shaded(paint.lower,0.7)) }
        }
        for x: Float in [-4.8,4.8] { refreshPanto(x,roof:top,singleArm:true) }
        // E201 source study: asymmetric roof equipment, rebuilt in simple solids.
        // Its source mesh/texture is not copied and its dimensions are not used.
        box(1.72,top,0,3.85,1.88,0.14,Self.steel)
        box(1.72,top+0.14,0,3.58,1.55,0.23,paint.roof)
        for side: Float in [-1,1] { for i in 0..<3 {
            box(0.55+Float(i)*1.14,4.11,side*0.786,1.00,0.025,0.14,black)
            for j in 0..<4 { box(0.55+Float(i)*1.14,4.12+Float(j)*0.033,side*0.804,0.94,0.012,0.009,Self.steel) }
        } }
        for x: Float in [-7.45,7.45] {
            box(x,top,0,0.9,1.3,0.18,paint.roof)
            cylinder(x,4.10,0,radius:0.43,height:0.035,color:black,sides:16)
            for j in -2...2 { box(x+Float(j)*0.14,4.14,0,0.025,0.70,0.018,Self.steel) }
        }
        for lateral: Float in [-0.47,0.47] {
            box(-2.15,top,lateral,2.75,0.28,0.10,Self.steel)
            for i in 0..<9 { cylinder(-3.2+Float(i)*0.26,4.02,lateral,radius:0.10,height:0.19,color:refreshWhite,sides:8) }
        }
        for sign: Float in [-1,1] { for x: Float in [-7.15,7.15] {
            for j in 0..<3 { box(x,0.56+Float(j)*0.22,sign*1.39,0.64,0.24,0.07,Self.steel) }
            for dx: Float in [-0.30,0.30] { beam(Map3DPoint(x+dx,0.55,sign*1.4),Map3DPoint(x+dx,1.3,sign*1.4),0.045,black) }
        } }
        box(0,0.38,0,4.9,1.95,0.59,Self.steel)
        for side: Float in [-1,1] { for j in 0..<9 { box(-2.1+Float(j)*0.52,0.52,side*0.987,0.33,0.025,0.27,black) } }
        for x: Float in [-3.45,3.45] {
            cylinder(x,top,0,radius:0.16,height:0.43,color:refreshWhite,sides:10)
            for j in 0..<4 { cylinder(x,4.00+Float(j)*0.085,0,radius:0.20,height:0.035,color:Self.steel,sides:10) }
        }
        beam(Map3DPoint(-4.8,4.17,0.43),Map3DPoint(4.8,4.17,0.43),0.04,black)
    }
    /// Twelve-vertex rounded rectangle, shared only by this Codex recipe.
    private func refreshRoundedOutline(x: Float,y: Float,width: Float,height: Float,radius: Float)->[(Float,Float)] {
        let r=min(radius,min(width,height)/2)
        let corners: [(Float,Float,Float)]=[(x+width/2-r,y+height/2-r,0),(x-width/2+r,y+height/2-r,90),(x-width/2+r,y-height/2+r,180),(x+width/2-r,y-height/2+r,270)]
        var result: [(Float,Float)]=[]
        for (cx,cy,start) in corners {
            for i in 0...2 { let a=(start+Float(i)*45)*Float.pi/180;result.append((cx+cosf(a)*r,cy+sinf(a)*r)) }
        }
        return result
    }
    private mutating func refreshPanel(_ p: [Map3DPoint],thickness: Float,color: UInt32) {
        var raw=Map3DPoint.zero
        for i in 2..<p.count { if let n=(p[1]-p[0]).cross(p[i]-p[0]).normalized { raw=n;break } }
        let centre=p.reduce(Map3DPoint.zero) { $0+$1*(1/Float(p.count)) }
        let normal=raw.dot(centre-Map3DPoint(0,2,0))>=0 ? raw:raw*(-1)
        let back=p.map { $0-normal*thickness }
        let c=(p+back).reduce(Map3DPoint.zero) { $0+$1*(1/Float(p.count*2)) }
        face(p,inside:c,color:color);face(back,inside:c,color:color)
        for i in p.indices { let j=(i+1)%p.count;face([p[i],back[i],back[j],p[j]],inside:c,color:color) }
    }
}

extension Map3DPalette {
    /// Decision 983: the 700T's band, Taiwan High Speed Rail's orange: the
    /// shade the 2D map has drawn its nose in since decision 243
    /// (``TrainLivery/highSpeed``, the owner's city view's `hsr` livery).
    public static let highSpeedOrange = Map3DColor.rgb(0xEA6A1E)
}
