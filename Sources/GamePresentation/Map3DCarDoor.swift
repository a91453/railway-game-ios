/// One door of a car ported from the owner's old version: where its leaf,
/// frame and window are on a side wall, the outline its car's mesh is cut
/// along, so that every triangle is wholly a door's or wholly the wall's
/// and the doors can be moved apart from the wall, to open at a station,
/// without the mesh being cut again.
///
/// SPLIT-HOTSPOTS-2 (CAR-DOOR-SHARED): the N700 (``Map3DKyushuN700``), the
/// N700S (``Map3DN700S``), the 800 series (``Map3DKyushu800``), the 700
/// series (``Map3DSeries700``), the 700T (``Map3DTHSR700T``) and the Keikyu
/// New 1000 (``Map3DKeikyuNew1000``) each had a copy of this type, and the
/// copies had drifted apart: the 800 series' slanted top and one door per
/// wall, the N700S's triangles, half a millimetre of slack on three and
/// 2 mm on the others. Each car's `Door` is now this; the most complete
/// copy, the 800 series', is the model. At half a millimetre every door of
/// every car takes in the same triangles as it did at 2 mm, so the slack
/// is the same for all (the 800 series' second review: at 2 mm a door can
/// take in faces of the wall's; `tools/texture-palette/port_check.py`).
public struct Map3DCarDoor: Sendable, Equatable {
    /// Along the car, metres from its middle, the cab's end positive.
    public let x: ClosedRange<Float>
    /// Over the rail, metres.
    public let z: ClosedRange<Float>
    /// The driver's own door, by the cab.
    public let crew: Bool
    /// The wall it is on: 1 the left (+y), -1 the right; 0 for a door whose
    /// outline is the same on both walls, on whichever wall a point is.
    public let side: Float
    /// A slanted top, from the door's back to its front: (along the car,
    /// over the rail). Empty for a square top at `z`'s upper bound.
    public let top: [SIMD2<Float>]
    /// How far from the car's middle, metres, a point is on a side wall:
    /// 1.5 m on the Shinkansen's 3.36–3.38 m bodies, 1.2 m on the Keikyu's
    /// 2.80 m.
    public let wall: Float
    /// Its triangles on the left wall (+y) and on the right, where its car
    /// keeps them (the N700S: the vertices `3 * n` to `3 * n + 2` of
    /// triangle `n`, the GLB's nodes `…-door-left-…` and `…-door-right-…`);
    /// empty elsewhere.
    public let left: Range<Int>, right: Range<Int>

    public init(x: ClosedRange<Float>, z: ClosedRange<Float>, crew: Bool = false, side: Float = 0,
                top: [SIMD2<Float>] = [], wall: Float = 1.5, left: Range<Int> = 0..<0, right: Range<Int> = 0..<0) {
        self.x = x
        self.z = z
        self.crew = crew
        self.side = side
        self.top = top
        self.wall = wall
        self.left = left
        self.right = right
    }

    /// Its triangles on the wall `side` is on (+y the left).
    public func triangles(side: Float) -> Range<Int> { side > 0 ? left : right }

    /// How high the door reaches at `along` the car.
    public func height(at along: Float) -> Float {
        guard let first = top.first, let last = top.last else { return z.upperBound }
        if along <= first.x { return first.y }
        for (a, b) in zip(top, top.dropFirst()) where along <= b.x {
            return a.y + (b.y - a.y) * (along - a.x) / (b.x - a.x)
        }
        return last.y
    }

    /// Whether `point` is on this door. Half a millimetre of slack, no
    /// more: some of the wall's faces next to a door's outline are a
    /// millimetre wide.
    public func contains(_ point: Map3DPoint, margin: Float = 0.0005) -> Bool {
        (side == 0 ? abs(point.y) : point.y * side) > wall
            && point.x >= x.lowerBound - margin && point.x <= x.upperBound + margin
            && point.z >= z.lowerBound - margin && point.z <= height(at: point.x) + margin
    }
}
