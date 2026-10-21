import Foundation

// Independent native geometry: the reference supplies proportions and ideas,
// not vertices, UVs, textures or complete silhouettes. The same primitives
// feed the app's model type and all six exported views.
struct SceneKitBuilder {
    var mesh = Map3DMesh()
    static let forward = Map3DPoint(1, 0, 0)
    static let ink = Map3DPalette.playerRim
    static let glass = Map3DPalette.glazing
    static let steel = Map3DPalette.tankSteel

    mutating func box(_ x: Float, _ y: Float, _ z: Float, _ length: Float, _ width: Float, _ height: Float, _ color: UInt32) {
        guard length > 0, width > 0, height > 0 else { return }
        mesh.addBox(base: Map3DPoint(x, y, z), forward: Self.forward, length: length, width: width, height: height, top: color, side: color)
        // Native map boxes omit their unseen undersides. This kit explicitly
        // closes them because the user also asks to look up from below.
        mesh.addQuad(Map3DPoint(x-length/2, y, z-width/2), Map3DPoint(x+length/2, y, z-width/2),
                     Map3DPoint(x+length/2, y, z+width/2), Map3DPoint(x-length/2, y, z+width/2), color: Map3DColor.shaded(color, 0.7))
    }

    mutating func cylinder(_ x: Float, _ y: Float, _ z: Float, radius: Float, height: Float, color: UInt32, sides: Int = 10) {
        mesh.addCylinder(base: Map3DPoint(x,y,z), radius: radius, height: height, sides: sides, top: color, side: color)
        let ring = (0..<sides).map { i -> Map3DPoint in
            let a = Float(i) * 2 * .pi / Float(sides)
            return Map3DPoint(x+cosf(a)*radius, y, z+sinf(a)*radius)
        }
        mesh.addFacet(ring, color: Map3DColor.shaded(color, 0.7))
    }

    mutating func beam(_ a: Map3DPoint, _ b: Map3DPoint, thickness: Float, color: UInt32) {
        guard let direction = (b-a).normalized else { return }
        let reference = abs(direction.y) > 0.95 ? Map3DPoint(1,0,0) : Map3DPoint(0,1,0)
        guard let side = direction.cross(reference).normalized else { return }
        let u = side * (thickness/2), v = direction.cross(side) * (thickness/2)
        let p = [a-u-v, a+u-v, a+u+v, a-u+v, b-u-v, b+u-v, b+u+v, b-u+v]
        for face in [[0,3,2,1],[4,5,6,7],[0,1,5,4],[1,2,6,5],[2,3,7,6],[3,0,4,7]] {
            mesh.addFacet(face.map { p[$0] }, color: color)
        }
    }

    mutating func wheel(_ x: Float, _ y: Float, _ z: Float, radius: Float, width: Float) {
        let n=10
        let rings = [-width/2,width/2].map { dz in (0..<n).map { i -> Map3DPoint in
            let a=Float(i)*2*Float.pi/Float(n)
            return Map3DPoint(x+cosf(a)*radius,y+sinf(a)*radius,z+dz)
        }}
        for i in 0..<n {
            let j=(i+1)%n
            mesh.addFacet([rings[0][i],rings[0][j],rings[1][j],rings[1][i]], color: Map3DTrainStyle.under)
        }
        mesh.addFacet(Array(rings[0].reversed()), color: Self.steel)
        mesh.addFacet(rings[1], color: Self.steel)
    }

    mutating func gable(_ x: Float, _ y: Float, _ z: Float, length: Float, width: Float, rise: Float, color: UInt32) {
        mesh.addGableRoof(base: Map3DPoint(x,y,z), forward: Self.forward, length: length, width: width, rise: rise,
                          overhang: 0.35, color: color, gable: Map3DPalette.tileWhite)
        // Close the roof's underside, visible on the exported bottom view.
        box(x,y-0.12,z,length+0.7,width+0.7,0.12,color)
    }

    mutating func hip(_ x: Float, _ y: Float, _ z: Float, length: Float, width: Float, rise: Float, color: UInt32) {
        mesh.addHipRoof(base: Map3DPoint(x,y,z), forward: Self.forward, length: length, width: width, rise: rise,
                        overhang: 0.4, color: color)
        box(x,y-0.12,z,length+0.8,width+0.8,0.12,color)
    }

    mutating func windows(x: Float = 0, z: Float = 0, length: Float, width: Float, floors: Int,
                          start: Float = 0, floorHeight: Float = 3.1, office: Bool = false) {
        let nx=max(1,Int(length/2.8)), nz=max(1,Int(width/2.8))
        let paneHeight: Float = office ? 2 : 1.35
        for floor in 0..<floors {
            let y=start+Float(floor)*floorHeight+0.95
            for sign: Float in [-1,1] {
                for bay in 0..<nz {
                    let middle=z-width/2+(Float(bay)+0.5)*width/Float(nz)
                    let d=min(office ? 2.5 : 1.5,width/Float(nz)*0.7)/2
                    let a=Map3DPoint(x+sign*(length/2+0.025),y,middle-d)
                    let b=Map3DPoint(a.x,y,middle+d), c=b+Map3DPoint(0,paneHeight,0), dpoint=a+Map3DPoint(0,paneHeight,0)
                    mesh.addFacet(sign>0 ? [a,dpoint,c,b] : [a,b,c,dpoint], color: Self.glass)
                }
                for bay in 0..<nx {
                    let middle=x-length/2+(Float(bay)+0.5)*length/Float(nx)
                    let d=min(office ? 2.5 : 1.5,length/Float(nx)*0.7)/2
                    let a=Map3DPoint(middle-d,y,z+sign*(width/2+0.025))
                    let b=Map3DPoint(middle+d,y,a.z), c=b+Map3DPoint(0,paneHeight,0), dpoint=a+Map3DPoint(0,paneHeight,0)
                    mesh.addFacet(sign>0 ? [a,b,c,dpoint] : [a,dpoint,c,b], color: Self.glass)
                }
            }
        }
    }

    mutating func tree(_ x: Float, _ y: Float, _ z: Float, size: Float = 1) {
        cylinder(x,y,z,radius:0.14*size,height:2.3*size,color:Map3DPalette.trunk,sides:6)
        // Three differently sized crowns, remade in the native palette.
        for (dx,dy,dz,r) in [(Float(0),Float(3.5),Float(0),Float(1.5)),(0.8,2.9,0.3,1.1),(-0.7,3.0,-0.4,1.0)] {
            let start=mesh.vertices.count
            Map3DProp.addLump(&mesh,centre:Map3DPoint(x+dx*size,y+dy*size,z+dz*size),radius:r*size)
            mesh.tintVertices(from:start,with:Map3DPalette.crown)
        }
    }

    mutating func tank(_ x: Float, _ y: Float, _ z: Float, blue: Bool = false) {
        for dx: Float in [-0.55,0.55] { for dz: Float in [-0.55,0.55] {
            box(x+dx,y,z+dz,0.09,0.09,0.6,Map3DPalette.tankStand)
        }}
        cylinder(x,y+0.5,z,radius:0.85,height:1.5,color:blue ? Map3DPalette.tankBlue : Self.steel,sides:12)
        cylinder(x,y+2,z,radius:0.32,height:0.12,color:Self.steel,sides:8)
        for h: Float in [0.9,1.5] { cylinder(x,y+h,z,radius:0.87,height:0.05,color:Self.steel,sides:12) }
    }

    mutating func bench(_ x: Float, _ y: Float, _ z: Float, length: Float = 2) {
        for dx: Float in [-length*0.35,length*0.35] { box(x+dx,y,z,0.12,0.55,0.48,Self.ink) }
        box(x,y+0.48,z,length,0.6,0.1,Map3DPalette.counters[1])
        box(x,y+0.65,z+0.27,length,0.09,0.55,Map3DPalette.counters[1])
    }

    mutating func planter(_ x: Float, _ y: Float, _ z: Float, size: Float = 1.7) {
        box(x,y,z,size,size,0.55,Map3DPalette.concrete)
        box(x,y+0.55,z,size*0.85,size*0.85,0.08,Map3DPalette.park)
        tree(x,y+0.6,z,size:0.55)
    }

    mutating func addModel(_ model: Map3DModelPack.Model, at offset: Map3DPoint = .zero, angle: Float = 0,
                           scale: Float = 1, tint: UInt32 = Map3DPalette.canopy) {
        let c=cosf(angle),s=sinf(angle)
        for i in stride(from:0,to:model.vertices.count,by:3) {
            let triangle=model.vertices[i..<i+3].map { vertex -> Map3DVertex in
                // Model z-up -> scene y-up, then a yaw in the scene's xz plane.
                let x=vertex.x*scale,z = -vertex.y*scale
                let p=Map3DPoint(c*x-s*z,vertex.z*scale,s*x+c*z)+offset
                return Map3DVertex(p,normal:.zero,color:Self.baked(vertex.color,tint:tint),layer:vertex.layer)
            }
            mesh.appendTriangle(triangle)
        }
    }

    static func baked(_ color: UInt32, tint: UInt32) -> UInt32 {
        let alpha=Float(color>>24)/255
        var result: UInt32=0xFF00_0000
        for shift: UInt32 in [0,8,16] {
            let original=Float((color>>shift)&255),replacement=Float((tint>>shift)&255)
            result |= UInt32((original*alpha+replacement*(1-alpha)).rounded())<<shift
        }
        return result
    }
}

private extension Map3DMesh {
    mutating func tintVertices(from start: Int, with tint: UInt32) {
        // Public mesh buffers intentionally cannot be mutated in place.
        // Rebuild these few newly added crown faces with baked vertex colours.
        var replacement=Map3DMesh()
        for i in stride(from:0,to:indices.count,by:3) {
            let corners=(0..<3).map { j -> Map3DVertex in
                let index=Int(indices[i+j]);var v=vertices[index]
                if index>=start { v.color=SceneKitBuilder.baked(v.color,tint:tint) }
                return v
            }
            replacement.appendTriangle(corners)
        }
        self=replacement
    }
}
