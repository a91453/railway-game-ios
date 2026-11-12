import Foundation

// Bao'an (保安, Tainan), a Japanese-era timber station: a low white boarded
// hall under a dark tiled hip-and-gable roof, a skirt roof below the eaves
// all round (deep over the platform side, on white posts, a row of white
// name signs standing on its edge), a gabled porch before the way in, and
// a tall palm on the forecourt. Shape and colours read from photographs;
// the sizes are estimates from doors and people in them, not a survey.
extension StationKitBuilder {
    /// The building, its middle at (`x`, `z`) on ground `y`: its front
    /// (+x) to the forecourt, its back to the platforms.
    mutating func baoan(_ x: Float,_ y: Float,_ z: Float) {
        let length: Float=17,depth: Float=6.8,eave: Float=4.75,rise: Float=2.3,overhang: Float=0.6
        let skirtHigh: Float=3.3,skirtLow: Float=2.75,front: Float=1.3,back: Float=3.0,end: Float=1.2
        let wall=Map3DPalette.houseWalls[0].color,frontWall=x+depth/2,backWall=x-depth/2,porchZ=z-length*0.12
        // Walls: a stone plinth, white boards, a grey rail under the high band.
        box(x,y,z,depth+0.1,length+0.1,0.45,Map3DPalette.stone)
        box(x,y+0.45,z,depth,length,eave-0.45,wall)
        box(x,y+skirtHigh,z,depth+0.08,length+0.08,0.14,Map3DPalette.stone)
        hipGable(x,y+eave,z,depth:depth,length:length,rise:rise,overhang:overhang)
        skirt(x,y,z,depth:depth,length:length,high:skirtHigh,low:skirtLow,front:front,back:back,end:end)
        // The high band's battens, front and back.
        for dz in stride(from:-length/2+0.85,through:length/2-0.8,by:Float(1.7)) {
            for (wx,s) in [(frontWall,Float(1)),(backWall,Float(-1))] { box(wx+s*0.03,y+skirtHigh+0.14,z+dz,0.06,0.1,eave-skirtHigh-0.6,Map3DPalette.stone) }
        }
        // The veranda's posts along the platform side, each with its braces, and the corner posts.
        let postX=backWall-back+0.25
        for dz in stride(from:-length/2-end+0.25,through:length/2+end-0.2,by:Float((length+2*end-0.5)/6)) {
            box(postX,y,z+dz,0.2,0.2,skirtLow-0.05,wall)
            for s: Float in [-1,1] { beam(Map3DPoint(postX,y+2.0,z+dz),Map3DPoint(postX,y+skirtLow-0.1,z+dz+s*0.75),0.1,wall) }
        }
        for s: Float in [-1,1] { box(frontWall+front-0.25,y,z+s*(length/2+end-0.25),0.2,0.2,skirtLow+0.02,wall) }
        // The name signs standing on the veranda's edge.
        nameBoards("〇"+Self.boardName(real:"保安",game:gameName),x:backWall-back+0.05,y:y+skirtLow,z:z,facing:-1,size:1.15,pitch:1.55,board:Self.white,ink:Map3DPalette.canopy)
        // Windows: the front's either side of the porch, the ends', the platform side's.
        for dz in [porchZ+3.4,porchZ+5.9,porchZ+8.4,porchZ-3.4,porchZ-5.4] where abs(dz-z)<length/2-1 {
            gridWindow(frontWall,y+1.0,dz,toward:Map3DPoint(1,0,0),width:2.0,height:1.7)
        }
        for s: Float in [-1,1] { gridWindow(z+s*length/2,y+1.0,x,toward:Map3DPoint(0,0,s),width:3.2,height:1.7) }
        for dz: Float in [-6.2,-3.4,5.6] { gridWindow(backWall,y+1.0,z+dz,toward:Map3DPoint(-1,0,0),width:2.0,height:1.7) }
        // The ways through, open and in shadow.
        box(frontWall+0.03,y,porchZ,0.1,2.4,2.5,Self.ink)
        box(backWall-0.03,y,z+1.0,0.1,4.4,2.5,Self.ink)
        porch(frontWall,y,porchZ,reach:2.8,width:3.8,eave:2.9,rise:1.35)
        // The fence between the building and the platform, flowers in pots along it.
        let fence=backWall-back-0.9
        for h: Float in [0.5,1.0] { box(fence,y+h,z,0.07,length+2*end,0.07,wall) }
        for dz in stride(from:-length/2-end,through:length/2+end,by:Float((length+2*end)/8)) { box(fence,y,z+dz,0.1,0.1,1.05,wall) }
        for (i,dz) in stride(from:-length/2+0.4,through:length/2-0.4,by:Float(2.05)).enumerated() {
            box(fence+0.5,y,z+dz,0.5,0.9,0.4,Map3DPalette.gymGreen)
            box(fence+0.5,y+0.4,z+dz,0.55,0.95,0.45,i%3==1 ? Map3DPalette.lantern : Map3DPalette.crown)
        }
        // The forecourt: the tall palm, shrubs in white pots, the notice board under its own little roof.
        palm(frontWall+3.4,y,z+length*0.16,height:10)
        for dz: Float in [1.6,3.6,5.6,7.4] {
            box(frontWall+2.6,y,porchZ+2.2+dz,0.6,0.6,0.6,wall)
            box(frontWall+2.6,y+0.6,porchZ+2.2+dz,0.95,0.95,0.7,Map3DPalette.crown)
            box(frontWall+2.6,y+1.3,porchZ+2.2+dz,0.65,0.65,0.5,Map3DPalette.crown)
            box(frontWall+2.6,y+1.8,porchZ+2.2+dz,0.35,0.35,0.35,Map3DPalette.crown)
        }
        let nx=frontWall+2.4,nz=porchZ-3.6
        for s: Float in [-1,1] { box(nx,y,nz+s*1.1,0.16,0.16,2.46,Self.timber) }
        box(nx,y+0.9,nz,0.1,2.2,1.2,Self.timber)
        leanTo(from:nx-0.5,to:nx+0.7,high:y+2.7,low:y+2.35,z:nz,width:2.9,color:Self.timber)
    }

    /// A hip-and-gable (入母屋) roof over walls that stop at `y`: hipped
    /// at the eaves all round, a small gable under each end of the ridge,
    /// which runs along z.
    mutating func hipGable(_ x: Float,_ y: Float,_ z: Float,depth: Float,length: Float,rise: Float,overhang: Float) {
        let a=depth/2+overhang,b=length/2+overhang,low=y-rise*overhang/(depth/2),top=y+rise,total=top-low
        let split: Float=0.52,d=a*split,mid=low+total*split,verge=b-d,tile=Self.tile,dark=Map3DPalette.plant
        let inside=Map3DPoint(x,low,z)
        func p(_ dx: Float,_ h: Float,_ dz: Float) -> Map3DPoint { Map3DPoint(x+dx,h,z+dz) }
        // The soffit, closing the roof from below.
        box(x,low-0.18,z,2*a+0.16,2*b+0.16,0.18,Self.white)
        for s: Float in [-1,1] {
            // The long slopes, front and back.
            face([p(s*a,low,-b),p(s*a,low,b),p(s*(a-d),mid,verge),p(0,top,verge),p(0,top,-verge),p(s*(a-d),mid,-verge)],inside:inside,
                 color:Map3DColor.shaded(tile,s>0 ? 0.96 : 0.80))
            // The hipped ends, and the gable above each, set back under its verge.
            face([p(a,low,s*b),p(a-d,mid,s*verge),p(-(a-d),mid,s*verge),p(-a,low,s*b)],inside:inside,color:Map3DColor.shaded(tile,s>0 ? 0.88 : 0.86))
            let set=s*(verge-0.4)
            face([p(a-d,mid,set),p(0,top,set),p(-(a-d),mid,set)],inside:inside,color:Self.white)
            face([p(a-d,mid,set),p(a-d,mid,s*verge),p(-(a-d),mid,s*verge),p(-(a-d),mid,set)],inside:inside,color:dark)
            // The gable's vent, its white verge boards and the ridge's end tile.
            box(x,mid+0.25,set+s*0.03,1.1,0.06,0.5,Self.timber)
            for t: Float in [-1,1] {
                beam(p(t*(a-d+0.1),mid-0.02,s*verge),p(0,top+0.03,s*verge),0.26,Self.white)
                // The hip ridges down to the corners.
                beam(p(t*(a-d),mid+0.05,s*verge),p(t*a,low+0.05,s*b),0.2,dark)
            }
            box(x,top-0.1,z+s*(verge+0.05),0.5,0.3,0.6,dark)
        }
        box(x,top-0.06,z,0.44,2*verge,0.3,dark)
        // Tile courses down the long slopes: under the gables' verges, then out to the hips.
        for s: Float in [-1,1] {
            let course=Map3DColor.shaded(tile,0.78)
            tileCourses(low:p(s*a,low,0),high:p(s*(a-d),mid,0),count:2,color:course) { b-d*$0 }
            tileCourses(low:p(s*(a-d),mid,0),high:p(0,top,0),count:2,color:course) { _ in verge }
        }
    }

    /// The skirt roof below the eaves, round all four sides, mitred at the
    /// corners: tiles to the front and the ends, sheet over the platform side.
    mutating func skirt(_ x: Float,_ y: Float,_ z: Float,depth: Float,length: Float,high: Float,low: Float,front: Float,back: Float,end: Float) {
        let t: Float=0.12,sheet=Map3DColor.shaded(Map3DPalette.mastSteel,0.74)
        let inner=[Map3DPoint(x+depth/2,y+high,z-length/2),Map3DPoint(x+depth/2,y+high,z+length/2),Map3DPoint(x-depth/2,y+high,z+length/2),Map3DPoint(x-depth/2,y+high,z-length/2)]
        let outer=[Map3DPoint(x+depth/2+front,y+low,z-length/2-end),Map3DPoint(x+depth/2+front,y+low,z+length/2+end),
                   Map3DPoint(x-depth/2-back,y+low,z+length/2+end),Map3DPoint(x-depth/2-back,y+low,z-length/2-end)]
        let down=Map3DPoint(0,t,0),shades: [Float]=[0.96,0.88,1,0.86]
        for i in 0..<4 {
            let j=(i+1)%4,color=i==2 ? sheet : Map3DColor.shaded(Self.tile,shades[i])
            let middle=(inner[i]+inner[j]+outer[i]+outer[j])*0.25-down*0.5
            face([inner[i],inner[j],outer[j],outer[i]],inside:middle,color:color)
            face([inner[i]-down,inner[j]-down,outer[j]-down,outer[i]-down],inside:middle,color:Map3DColor.shaded(color,0.7))
            face([outer[i],outer[j],outer[j]-down,outer[i]-down],inside:middle,color:Self.white)
        }
    }

    /// A window on the wall at `wall` (its x, or its z when it faces along
    /// z), `along` the wall: dark glass behind a white frame and bars.
    mutating func gridWindow(_ wall: Float,_ y: Float,_ along: Float,toward: Map3DPoint,width: Float,height: Float) {
        let glass=Map3DColor.shaded(Self.glass,0.62)
        func slab(_ out: Float,_ up: Float,_ off: Float,_ thick: Float,_ w: Float,_ h: Float,_ color: UInt32) {
            if toward.x != 0 { box(wall+toward.x*out,y+up,along+off,thick,w,h,color) }
            else { box(along+off,y+up,wall+toward.z*out,w,thick,h,color) }
        }
        slab(0.05,-0.1,0,0.12,width+0.24,height+0.2,Map3DPalette.stone)
        slab(0.09,0,0,0.08,width,height,glass)
        slab(0.11,height*0.62,0,0.06,width,0.07,Self.white)
        for i in 1..<3 { slab(0.11,0,(Float(i)/3-0.5)*width,0.06,0.07,height,Self.white) }
    }

    /// The gabled porch before the way in, on four white posts, the name board under its gable.
    mutating func porch(_ wall: Float,_ y: Float,_ z: Float,reach: Float,width: Float,eave: Float,rise: Float) {
        let middle=wall+reach/2-0.15,out=wall+reach
        mesh.addGableRoof(base:Map3DPoint(middle,y+eave,z),forward:Self.forward,length:reach+0.3,width:width,rise:rise,overhang:0.35,color:Self.tile,gable:Self.white)
        box(middle,y+eave-0.3,z,reach+1.0,width+0.7,0.14,Self.white)
        for s: Float in [-1,1] {
            for px in [out-0.2,wall+0.9] { box(px,y,z+s*(width/2-0.15),0.2,0.2,eave-0.3,Self.white) }
            // The white verge boards up the gable's front.
            beam(Map3DPoint(out+0.36,y+eave-0.24,z+s*(width/2+0.35)),Map3DPoint(out+0.36,y+eave+rise+0.02,z),0.3,Self.white)
        }
        box(out+0.02,y+eave-0.16,z,0.1,width,0.16,Self.white)
        box(out+0.08,y+eave-0.85,z,0.1,width-0.9,0.6,Self.timber)
        nameBoards(Self.boardName(real:"保安",game:gameName),x:out+0.19,y:y+eave-0.82,z:z,facing:1,size:0.54,pitch:0.64,board:Self.timber,ink:Map3DPalette.templeRoof)
        box(middle,y+eave+rise-0.08,z,reach+1.0,0.3,0.2,Map3DPalette.plant)
    }

    /// A tall palm, its trunk a little bent, its fronds drooping.
    mutating func palm(_ x: Float,_ y: Float,_ z: Float,height: Float) {
        let knots=[Map3DPoint(x,y,z),Map3DPoint(x+0.15,y+height*0.4,z+0.35),Map3DPoint(x+0.1,y+height*0.75,z+0.2),Map3DPoint(x,y+height,z)]
        for i in 0..<3 { beam(knots[i],knots[i+1]+Map3DPoint(0,0.1,0),0.42-Float(i)*0.05,Map3DPalette.trunk) }
        let top=knots[3],below=top-Map3DPoint(0,4,0)
        // Two rings of fronds: the upper ones short and raised, the lower long and drooping.
        for i in 0..<18 {
            let upper=i%2==0,a=Float(i)*Float.pi/9,out=Map3DPoint(cosf(a),0,sinf(a)),side=Map3DPoint(-sinf(a),0,cosf(a))*(upper ? 0.5 : 0.65),green=Map3DProp.greens[i%5]
            let mid=top+out*(upper ? 1.3 : 1.9)+Map3DPoint(0,upper ? 1.3 : 0.5,0),tip=top+out*(upper ? 2.5 : 3.5)+Map3DPoint(0,upper ? 0.9 : -1.5,0)
            for quad in [[top-side*0.4,top+side*0.4,mid+side,mid-side],[mid-side,mid+side,tip+side*0.25,tip-side*0.25]] {
                face(quad,inside:below,color:green)
                face(quad.map { $0-Map3DPoint(0,0.05,0) },inside:quad[0]+Map3DPoint(0,6,0),color:Map3DColor.shaded(green,0.7))
            }
        }
        box(top.x,top.y-0.5,top.z,0.7,0.7,0.9,Map3DProp.greens[1])
    }
}
