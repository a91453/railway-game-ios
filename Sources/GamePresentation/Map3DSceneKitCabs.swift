import Foundation

// Scene-kit cabs only: standard game train models remain unchanged. The body
// and equipment reuse the native builder; a uniformly painted nose replaces
// its per-vertex end-cap colours, which made a radial white star in front view.
struct SceneKitCab {
    let style: Map3DTrainStyle
    let asset: Map3DSceneKit.Asset
    let tail: Bool
    let tint: UInt32
    /// Whether the livery's band stays the line's colour, as the game's
    /// metro does (decision 318), rather than `tint` baked in.
    var lineColoured = false

    func model() -> Map3DModelPack.Model {
        let builder=Map3DTrainBuilder(style:style,cab:true)
        let start=style.length/2-style.nose
        var result=SceneKitBuilder()
        result.addModel(Self.clipped(builder.model(named:asset.id),maximumX:start),tint:tint,keepsShares:lineColoured)
        var nose=Map3DMesh()
        let steps=max(8,Int(style.nose/0.35))
        let rings=(0...steps).map { i in builder.ring(at:start+style.nose*Float(i)/Float(steps),t:Float(i)/Float(steps)) }
        for i in 0..<steps {
            for k in 0..<Map3DTrainBuilder.ringPoints {
                let j=(k+1)%Map3DTrainBuilder.ringPoints
                let corners=[rings[i][k].point,rings[i][j].point,rings[i+1][j].point,rings[i+1][k].point]
                let height=corners.reduce(Float(0)) { $0+$1.y }/4
                let color=height<style.floor+0.13*(style.roof-style.floor) ? style.skirt : style.body
                Self.face(&nose,corners,color:color,inside:Map3DPoint((corners[0].x+corners[2].x)/2,height,0))
            }
        }
        let end=rings[steps].map(\.point)
        // All cap vertices share one paint; no interpolated white centre.
        Self.face(&nose,end,color:style.body,inside:Map3DPoint(style.length/2-0.1,(style.floor+style.roof)/2,0))
        let surface=CabSurface(mesh:nose)
        var cab=nose
        let v=asset.variant,h=style.roof-style.floor
        let highSpeed=asset.family == .metro && v==0
        let redFace=asset.family == .traModern && v==1
        let modern=asset.family == .traModern && v<3
        if !redFace { surface.band(&cab,style:style,tint:lineColoured ? tint & 0x00FF_FFFF : tint) }
        let low=style.floor+(highSpeed ? 0.57 : redFace ? 0.18 : modern ? 0.32 : 0.24)*h
        let high=style.floor+0.91*h
        let width=style.halfWidth*(highSpeed ? 0.66 : 0.84)
        // A continuous mask projected onto the real nose, not painted by the
        // coarse ring vertices' heights. Corners taper into the body.
        surface.panel(&cab,low:low,high:high,halfWidth:width,color:redFace ? Map3DPalette.lantern : Map3DColor.shaded(Map3DTrainStyle.glass,0.70))
        if modern {
            surface.panel(&cab,low:style.floor+0.48*h,high:style.floor+0.79*h,halfWidth:width*0.85,color:Map3DTrainStyle.glass,proud:0.024)
        } else {
            surface.panel(&cab,low:low+0.10,high:high-0.10,halfWidth:width*0.92,color:Map3DTrainStyle.glass,proud:0.024)
        }
        if !modern && !highSpeed {
            // Metro/commuter front panes and central door are visibly split.
            surface.panel(&cab,low:low+0.10,high:high-0.12,halfWidth:0.035,color:Map3DTrainStyle.doorColour,proud:0.026)
        }
        let lightY=style.floor+(highSpeed ? 0.48 : modern ? 0.37 : 0.26)*h
        let lamp=tail ? Map3DPalette.lantern : Map3DTrainStyle.headlamp
        for sign: Float in [-1,1] {
            let z=sign*style.halfWidth*(highSpeed ? 0.67 : 0.66)
            surface.disc(&cab,y:lightY,z:z,ry:0.16,rz:0.20,color:Map3DTrainStyle.lampHousing)
            let glowStart=cab.vertices.count
            surface.disc(&cab,y:lightY,z:z,ry:0.085,rz:0.12,color:lamp,proud:0.034)
            cab.makeGlowing(from:glowStart)
        }
        if modern && v==0 {
            surface.disc(&cab,y:style.floor+0.82*h,z:0,ry:0.06,rz:0.15,color:lamp,proud:0.032)
        }
        if !highSpeed {
            if !modern {
                surface.panel(&cab,low:style.floor+0.12*h,high:style.floor+0.18*h,halfWidth:style.halfWidth*0.72,
                              color:Map3DTrainBuilder.lineColour)
            }
            // Coupler originates inside the lower front, with a short neck.
            result.box(style.length/2-0.03,style.floor+0.02,0,0.38,0.32,0.25,Map3DTrainStyle.under)
        }
        result.mesh.append(cab)
        return Map3DModelPack.Model.flat(named:asset.id,from:result.mesh)
    }

    static func face(_ mesh: inout Map3DMesh,_ corners: [Map3DPoint],color: UInt32,inside: Map3DPoint) {
        guard corners.count>=3 else { return }
        let normal=(corners[1]-corners[0]).cross(corners[2]-corners[0])
        let centre=corners.reduce(Map3DPoint.zero) { $0+$1*(1/Float(corners.count)) }
        mesh.addFacet(normal.dot(centre-inside)>=0 ? corners : Array(corners.reversed()),color:color)
    }

    static func coach(style: Map3DTrainStyle,named name: String) -> Map3DModelPack.Model {
        let original=Map3DTrainBuilder(style:style,cab:false).model(named:name)
        var mesh=Map3DMesh()
        for i in stride(from:0,to:original.vertices.count,by:3) {
            let triangle=original.vertices[i..<i+3]
            let end=triangle.allSatisfy { $0.x < -style.length/2+0.001 }
            mesh.appendTriangle(triangle.map { v in
                Map3DVertex(Map3DPoint(v.x,v.z,-v.y),normal:.zero,color:end ? style.body : v.color,layer:v.layer)
            })
        }
        return Map3DModelPack.Model.flat(named:name,from:mesh)
    }

    // Clip triangles, including ones spanning the cut. Filtering whole
    // triangles leaves holes in the long body panels and the roof equipment.
    static func clipped(_ model: Map3DModelPack.Model,maximumX: Float,keepFront: Bool = false) -> Map3DModelPack.Model {
        var mesh=Map3DMesh()
        for i in stride(from:0,to:model.vertices.count,by:3) {
            let original=Array(model.vertices[i..<i+3])
            var polygon: [Map3DVertex]=[]
            for j in 0..<3 {
                let a=original[j],b=original[(j+1)%3]
                let insideA=keepFront ? a.x>=maximumX : a.x<=maximumX
                let insideB=keepFront ? b.x>=maximumX : b.x<=maximumX
                if insideA { polygon.append(a) }
                if insideA != insideB {
                    let t=(maximumX-a.x)/(b.x-a.x)
                    var vertex=a;vertex.x=maximumX;vertex.y=a.y+(b.y-a.y)*t;vertex.z=a.z+(b.z-a.z)*t
                    polygon.append(vertex)
                }
            }
            if polygon.count>=3 {
                for j in 1..<polygon.count-1 { mesh.appendTriangle([polygon[0],polygon[j],polygon[j+1]].map { v in
                    Map3DVertex(Map3DPoint(v.x,v.z,-v.y),normal:.zero,color:v.color,layer:v.layer)
                }) }
            }
        }
        return Map3DModelPack.Model.flat(named:model.name,from:mesh)
    }
}

// Ray-project front details onto the nose's actual triangles. Thus the
// windscreen and lamps share the silhouette at every view, including below.
private struct CabSurface {
    let triangles: [[Map3DPoint]]
    init(mesh: Map3DMesh) {
        triangles=stride(from:0,to:mesh.indices.count,by:3).map { i in
            (0..<3).map { j in let v=mesh.vertices[Int(mesh.indices[i+j])];return Map3DPoint(v.x,v.y,v.z) }
        }
    }

    func band(_ mesh: inout Map3DMesh,style: Map3DTrainStyle,tint: UInt32) {
        let start=style.length/2-style.nose,h=style.roof-style.floor
        for triangle in triangles {
            let normal=(triangle[1]-triangle[0]).cross(triangle[2]-triangle[0])
            guard abs(normal.z)>0.01 else { continue }
            var cut=triangle
            for (boundary,sign) in [(style.band.lowerBound,Float(1)),(style.band.upperBound,Float(-1))] {
                func side(_ p: Map3DPoint) -> Float {
                    let t=max(0,min(1,(p.x-start)/style.nose))
                    return ((p.y-style.floor)/h+style.dive*t-boundary)*sign
                }
                var next: [Map3DPoint]=[]
                for i in cut.indices {
                    let p=cut[i],q=cut[(i+1)%cut.count],a=side(p),b=side(q)
                    if a>=0 { next.append(p) }
                    if (a>=0) != (b>=0) { next.append(p+(q-p)*(a/(a-b))) }
                }
                cut=next
                if cut.isEmpty { break }
            }
            if cut.count>=3 {
                let offset=(normal.normalized ?? .zero)*0.016
                mesh.addFacet(cut.map { $0+offset },color:tint)
            }
        }
    }

    func panel(_ mesh: inout Map3DMesh,low: Float,high: Float,halfWidth: Float,color: UInt32,proud: Float = 0.018) {
        let bevel=(high-low)*0.12,w=halfWidth
        let polygon=[(low,-w*0.74),(low,w*0.74),(low+bevel,w),(high-bevel,w),
                     (high,w*0.78),(high,-w*0.78),(high-bevel,-w),(low+bevel,-w)]
        project(&mesh,polygon:polygon,color:color,proud:proud)
    }

    func disc(_ mesh: inout Map3DMesh,y: Float,z: Float,ry: Float,rz: Float,color: UInt32,proud: Float = 0.026) {
        let polygon=(0..<12).map { i -> (Float,Float) in
            let a=Float(i)*2*Float.pi/12
            return (y+ry*cosf(a),z+rz*sinf(a))
        }
        project(&mesh,polygon:polygon,color:color,proud:proud)
    }

    // Cut the decal along EVERY shell facet. Sampling a separate rectangular
    // grid bridges the curved nose and sinks through it between sample points.
    // These clipped polygons stay exactly on the original facet, offset 2 cm.
    private func project(_ mesh: inout Map3DMesh,polygon: [(Float,Float)],color: UInt32,proud: Float) {
        let area=polygon.indices.reduce(Float(0)) { sum,i in
            let a=polygon[i],b=polygon[(i+1)%polygon.count]
            return sum+a.0*b.1-b.0*a.1
        }
        let orientation: Float=area>0 ? 1 : -1
        for triangle in triangles {
            guard (triangle[1]-triangle[0]).cross(triangle[2]-triangle[0]).x>0.000001 else { continue }
            var cut=triangle
            for edge in polygon.indices {
                let a=polygon[edge],b=polygon[(edge+1)%polygon.count]
                func side(_ p: Map3DPoint) -> Float { ((b.0-a.0)*(p.z-a.1)-(b.1-a.1)*(p.y-a.0))*orientation }
                var next: [Map3DPoint]=[]
                for i in cut.indices {
                    let p=cut[i],q=cut[(i+1)%cut.count],sp=side(p),sq=side(q)
                    if sp>=0 { next.append(p) }
                    if (sp>=0) != (sq>=0) { next.append(p+(q-p)*(sp/(sp-sq))) }
                }
                cut=next
                if cut.isEmpty { break }
            }
            if cut.count>=3 {
                mesh.addFacet(cut.map { $0+Map3DPoint(proud,0,0) },color:color)
            }
        }
    }
}
