import Foundation

// Decision 410: the scene kit's cab cars (decision 318's multiple units and
// the scene kit's train subjects) on the shared train shell
// (`Map3DTrainShell`), each variant's face as #900 gave it: the Puyuma's red
// face, the modern EMUs' tall windscreen, the metro's split front.
struct SceneKitCab {
    let style: Map3DTrainStyle
    let asset: Map3DSceneKit.Asset
    let tail: Bool
    let tint: UInt32
    /// Whether the livery's band stays the line's colour, as the game's
    /// metro does (decision 318), rather than `tint` baked in.
    var lineColoured = false
    /// Decision 410: decision 408's light car for the far set.
    var detail = Map3DTrainShell.Detail.near
    /// Decision 410: the body's colour over the nose, if the face has its own.
    var noseColour: UInt32? = nil

    /// The cab's face: a flat-fronted EMU's windscreen square on its front,
    /// a sloping nose's on its slope.
    var front: Map3DTrainShell.Front {
        let v = asset.variant
        let highSpeed = asset.family == .metro && v == 0
        let redFace = asset.family == .traModern && v == 1
        let modern = asset.family == .traModern && v < 3
        if highSpeed || (modern && style.noseShape.slopes) {
            // A sloping nose takes its windscreen on the slope: seen straight
            // on, only the tip faces forward.
            var front = Map3DTrainShell.front(of: style)
            front.tail = tail
            front.lampAcross = 0.67
            if redFace { front.face = (Map3DPalette.lantern, 0.18, 0.91) }
            return front
        }
        return Map3DTrainShell.Front(screen: modern ? 0.45...0.82 : 0.28...0.87, screenWidth: modern ? 0.80 : 0.77,
                                     face: redFace ? (Map3DPalette.lantern, 0.18, 0.91) : nil,
                                     lampShare: modern ? 0.37 : 0.26, tail: tail, pillar: !modern, onSlope: false, lowBand: !modern)
    }

    func model() -> Map3DModelPack.Model {
        var front = front
        front.noseColour = noseColour
        let cab = Map3DTrainShell(style: style, cab: true, detail: detail, front: front).model(named: asset.id)
        return Map3DTrainSet.baked(cab, tint: tint, keepsShares: lineColoured)
    }

    /// A middle car or coach of `style`.
    static func coach(style: Map3DTrainStyle, named name: String, detail: Map3DTrainShell.Detail = .near) -> Map3DModelPack.Model {
        Map3DTrainShell(style: style, cab: false, detail: detail).model(named: name)
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
