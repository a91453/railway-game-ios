import Foundation

// Decision 705: a station's name on its boards as strokes, where a
// station's own recipe hangs the boards it is known by (Jiji's four on
// its gable, Bao'an's row on the platform side's eaves). Each character is
// a handful of straight strokes on a grid 1 across (to the reader's right)
// and 1 up; flat quads a little before the board, read from one side.
extension StationKitBuilder {
    static let nameStrokes: [Character: [(Float,Float,Float,Float)]] = [
        "車": [(0.15,0.88,0.85,0.88),(0.25,0.72,0.75,0.72),(0.25,0.54,0.75,0.54),(0.25,0.36,0.75,0.36),(0.25,0.72,0.25,0.36),(0.75,0.72,0.75,0.36),
              (0.06,0.2,0.94,0.2),(0.5,1,0.5,0)],
        "站": [(0.22,0.98,0.22,0.86),(0.04,0.82,0.42,0.82),(0.13,0.72,0.17,0.42),(0.34,0.72,0.3,0.42),(0.02,0.3,0.44,0.38),
              (0.7,1,0.7,0.5),(0.7,0.76,0.96,0.76),(0.54,0.5,0.96,0.5),(0.54,0.06,0.96,0.06),(0.54,0.5,0.54,0.06),(0.96,0.5,0.96,0.06)],
        "集": [(0.3,1,0.12,0.8),(0.24,0.88,0.24,0.44),(0.5,1,0.56,0.9),(0.24,0.86,0.86,0.86),(0.24,0.72,0.8,0.72),(0.24,0.58,0.8,0.58),
              (0.24,0.44,0.92,0.44),(0.54,0.86,0.54,0.44),(0.04,0.3,0.96,0.3),(0.5,0.44,0.5,0),(0.5,0.3,0.12,0.04),(0.5,0.3,0.88,0.04)],
        "保": [(0.26,1,0.04,0.62),(0.17,0.78,0.17,0),(0.42,0.94,0.9,0.94),(0.42,0.66,0.9,0.66),(0.42,0.94,0.42,0.66),(0.9,0.94,0.9,0.66),
              (0.32,0.46,1,0.46),(0.66,0.66,0.66,0),(0.66,0.46,0.36,0.1),(0.66,0.46,0.96,0.1)],
        "安": [(0.5,1,0.5,0.88),(0.08,0.84,0.92,0.84),(0.08,0.84,0.08,0.68),(0.92,0.84,0.92,0.7),(0.44,0.74,0.28,0.4),(0.28,0.4,0.78,0.02),
              (0.68,0.62,0.5,0.24),(0.5,0.24,0.16,0.02),(0.04,0.5,0.96,0.5)],
        // The railway's round mark, as a ring with its bar.
        "〇": [(0.3,0.9,0.7,0.9),(0.7,0.9,0.92,0.68),(0.92,0.68,0.92,0.32),(0.92,0.32,0.7,0.1),(0.7,0.1,0.3,0.1),(0.3,0.1,0.08,0.32),
              (0.08,0.32,0.08,0.68),(0.08,0.68,0.3,0.9),(0.5,0.72,0.5,0.28),(0.32,0.5,0.68,0.5)],
    ]

    /// `text` on boards `size` square standing across the building's front
    /// (their faces at `x`, facing +x when `facing` is 1, −x when −1),
    /// their middles `pitch` apart about `z`, each one's foot at `y` plus
    /// its `lift`; read left to right from the side they face.
    mutating func nameBoards(_ text: String,x: Float,y: Float,z: Float,facing: Float,size: Float,pitch: Float,lifts: [Float] = [],board: UInt32,ink: UInt32) {
        let characters=Array(text),stroke=size*0.085
        for (n,character) in characters.enumerated() {
            // The reader's right is −z before a board that faces +x.
            let across=(Float(n)-Float(characters.count-1)/2)*pitch,cz=z-facing*across,foot=y+(n<lifts.count ? lifts[n] : 0)
            box(x-facing*0.05,foot,cz,0.1,size,size,board)
            let paint=x+facing*0.012,inset=size*0.12,cell=size-2*inset
            for s in Self.nameStrokes[character] ?? [] {
                func point(_ u: Float,_ v: Float) -> Map3DPoint { Map3DPoint(paint,foot+inset+v*cell,cz-facing*(u-0.5)*cell) }
                let a=point(s.0,s.1),b=point(s.2,s.3)
                guard let along=(b-a).normalized else { continue }
                let half=Map3DPoint(0,along.z,-along.y)*(stroke/2),end=along*(stroke/2)
                face([a-end-half,a-end+half,b+end+half,b+end-half],inside:Map3DPoint(x-facing,a.y,a.z),color:ink)
            }
        }
    }

    /// Tile courses on a roof's slope: `count` thin bands between `low`
    /// and `high` (two points on the slope's fall line, eaves and ridge),
    /// each along z to `reach(t)` either side of the fall line's z, t
    /// being how far up the slope it lies; a shade darker than the tiles,
    /// so a tiled roof and a sheet roof differ from above.
    mutating func tileCourses(low: Map3DPoint,high: Map3DPoint,count: Int,color: UInt32,reach: (Float) -> Float) {
        for i in 1...count {
            let t=Float(i)/Float(count+1),p=low+(high-low)*t,half=reach(t)
            beam(Map3DPoint(p.x,p.y+0.02,p.z-half),Map3DPoint(p.x,p.y+0.02,p.z+half),0.09,color)
        }
    }
}
