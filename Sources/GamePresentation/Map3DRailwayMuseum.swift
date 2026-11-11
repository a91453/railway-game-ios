import Foundation
import GameCore

// Decision 696: the company's railway museum (decision 684) with a look of
// its own. The hall is drawn after the old Taipei Workshop of the Railway
// Department (1909, the red-brick workshop that now stands by Beimen):
// a tall gabled nave between two lower aisles, red brick banded in white,
// a round-headed crown over the front gable and a white arch at the door.
// Before it a yard of display tracks, one for each type of train the
// museum shows (``PlacedBuilding/exhibits``), up to the twelve that count
// for its stars (``Tourism/exhibitsCounted``): the first six stand before
// the hall, the next three bring a car shed on the left, the last three
// one on the right, so the museum grows as the company's collection does.
//
// The hall, the sheds, the tracks and the yard are one mesh, built with
// +x the front, +y up and +z the right, the plot's middle at 0. The
// exhibits are not in it: they are the train pack's own models (decision
// 608 keeps their vertices only on the GPU), stood on the tracks as
// instances each frame (``Exhibit``, ``add(to:exhibits:at:facing:pack:eye:reach:)``).

public enum Map3DRailwayMuseum {
    /// The most exhibits that stand in the yard: those that count.
    static let mostShown = Tourism.exhibitsCounted

    /// Each display track's place across the yard, metres right of the
    /// middle, in the order the exhibits take them: six before the hall
    /// from the middle outward, three under the left shed, three under
    /// the right one.
    static let trackOffsets: [Float] = [-3, 3, -7.5, 7.5, -12, 12, -18.5, -23, -27.5, 18.5, 23, 27.5]

    /// The tracks before the hall, and each shed's.
    static let hallTracks = 6, shedTracks = 3

    /// The rails' top over the plot's ground: the pad, the bed and the rail
    /// as ``StationKitBuilder/track(_:_:_:at:)`` lays them.
    static let railTop: Float = 0.46

    /// The hall, front to back and across: 25 m long, a 13 m nave and two
    /// 8 m aisles (a third larger than the real one, so it holds its own
    /// beside twelve tracks). The real workshop's front is about 24 m, its ridge
    /// about 13 m and its length half as much again (estimated from the
    /// door and a scooter in the photographs; docs/art/railway-museum-2026-11-12).
    static let hallFront: Float = -5, hallBack: Float = -29.6
    static let naveHalf: Float = 6.5, naveEave: Float = 9, ridge: Float = 12.6
    static let aisleOuter: Float = 14.5, aisleEave: Float = 5.6, aisleTop: Float = 7.4

    /// A car shed: its middle across the yard and its walls.
    static let shedCentre: Float = 23, shedHalf: Float = 7, shedFront: Float = -10, shedBack: Float = -30
    static let shedEave: Float = 5.4, shedRise: Float = 2.6

    static let brick = Map3DPalette.brick
    static let white = Map3DPalette.tileWhite
    /// The roofs: the grey of the workshop's tiles, and the darker grey of
    /// its ridges and posts.
    static let slate = Map3DPalette.tinRoofs[2]
    static let iron = Map3DPalette.tankStand
    static let glass = Map3DPalette.playerRim
    /// The yard between the tracks: red brick paving, as round the real
    /// workshop, so the museum is red from straight above too.
    static let paving = Map3DPalette.track

    /// How many sheds a museum of `exhibits` exhibits has: the left one
    /// from the seventh exhibit, the right one from the tenth.
    static func sheds(exhibits: Int) -> Int {
        exhibits > hallTracks + shedTracks ? 2 : exhibits > hallTracks ? 1 : 0
    }

    /// Where track `index` starts, at its buffer stop: before the hall's
    /// front, or at the back of its shed.
    static func start(ofTrack index: Int) -> Float {
        index < hallTracks ? hallFront + 1.3 : shedBack + 1.5
    }

    /// Where track `index` ends, by the street.
    static func end(ofTrack index: Int) -> Float {
        index < hallTracks ? 29 : 18
    }

    /// Where the front of an exhibit `length` metres long stands on track
    /// `index`, metres ahead of the plot's middle: before the hall near the
    /// street, a shed's a little back with its tail under the roof; a long
    /// one further forward, so its tail is clear of the buffer stop.
    static func frontOfExhibit(onTrack index: Int, length: Float) -> Float {
        max(index < hallTracks ? 25 : 15, start(ofTrack: index) + 0.7 + length)
    }

    /// The boxes that stand in for the museum from farther: the nave, the
    /// aisles and each shed there is.
    static func boxes(exhibits: Int) -> [(centre: Map3DPoint, length: Float, width: Float, height: Float)] {
        let middle = (hallFront + hallBack) / 2, length = hallFront - hallBack
        var boxes: [(centre: Map3DPoint, length: Float, width: Float, height: Float)] = [
            (Map3DPoint(middle, 0, 0), length, naveHalf * 2, (naveEave + ridge) / 2),
            (Map3DPoint(middle, 0, -(naveHalf + aisleOuter) / 2), length, aisleOuter - naveHalf, (aisleEave + aisleTop) / 2),
            (Map3DPoint(middle, 0, (naveHalf + aisleOuter) / 2), length, aisleOuter - naveHalf, (aisleEave + aisleTop) / 2),
        ]
        for side in shedSides(exhibits: exhibits) {
            boxes.append((Map3DPoint((shedFront + shedBack) / 2, 0, side * shedCentre), shedFront - shedBack, shedHalf * 2, shedEave + shedRise / 2))
        }
        return boxes
    }

    /// −1 for the left shed and 1 for the right one, those there are.
    static func shedSides(exhibits: Int) -> [Float] {
        Array([Float(-1), 1].prefix(sheds(exhibits: exhibits)))
    }

    // MARK: - The mesh

    /// The museum of `exhibits` exhibits on a plot `side` metres across:
    /// the yard, the hall, the six tracks before it (empty until an
    /// exhibit comes) and the sheds with theirs.
    static func mesh(exhibits: Int, side: Float = 62) -> Map3DMesh {
        var b = StationKitBuilder()
        let shown = max(0, min(mostShown, exhibits)), half = side / 2
        yard(&b, shown: shown, half: half)
        hall(&b)
        for index in 0..<max(hallTracks, shown) { track(&b, index) }
        for side in shedSides(exhibits: shown) { shed(&b, side: side) }
        gate(&b, half: half)
        waterTower(&b, x: half - 6, z: -(half - 3.5))
        return b.mesh
    }

    /// The meshes already built, by exhibits shown.
    static let meshes: [Map3DMesh] = (0...mostShown).map { mesh(exhibits: $0) }

    /// A slab between `back` and `front` along x whose outline, seen from
    /// the front, is `outline` (z right, y up; convex, counter-clockwise
    /// seen from the front).
    static func slab(_ b: inout StationKitBuilder, _ outline: [(z: Float, y: Float)], back: Float, front: Float, _ color: UInt32) {
        let middle = outline.reduce((z: Float(0), y: Float(0))) { ($0.z + $1.z / Float(outline.count), $0.y + $1.y / Float(outline.count)) }
        let inside = Map3DPoint((back + front) / 2, middle.y, middle.z)
        b.face(outline.map { Map3DPoint(front, $0.y, $0.z) }, inside: inside, color: color)
        b.face(outline.map { Map3DPoint(back, $0.y, $0.z) }, inside: inside, color: Map3DColor.shaded(color, 0.75))
        for index in outline.indices {
            let p = outline[index], q = outline[(index + 1) % outline.count]
            b.face([Map3DPoint(back, p.y, p.z), Map3DPoint(front, p.y, p.z), Map3DPoint(front, q.y, q.z), Map3DPoint(back, q.y, q.z)],
                   inside: inside, color: Map3DColor.shaded(color, q.y > p.y || q.y == p.y && p.y > middle.y ? 0.95 : 0.85))
        }
    }

    /// An upright rectangle with a round head: `width` across, `height` to
    /// the spring of its arch, standing on `y` with its middle at `z`.
    static func arched(z: Float, y: Float, width: Float, height: Float, steps: Int = 6) -> [(z: Float, y: Float)] {
        let r = width / 2
        return [(z - r, y), (z + r, y)] + (0...steps).map { step in
            let a = Float(step) / Float(steps) * .pi
            return (z + cosf(a) * r, y + height + sinf(a) * r)
        }
    }

    /// A window in the wall whose outer face is at `x` facing the front: a
    /// white surround standing out of the wall and dark glass set in it.
    static func frontWindow(_ b: inout StationKitBuilder, x: Float, z: Float, y: Float, width: Float, height: Float) {
        slab(&b, arched(z: z, y: y - 0.18, width: width + 0.5, height: height + 0.18), back: x - 0.05, front: x + 0.16, white)
        slab(&b, arched(z: z, y: y, width: width, height: height), back: x, front: x + 0.2, glass)
    }

    /// A window in a side wall whose outer face is at `z`, facing `way`
    /// (−1 left, 1 right): a white sill and head, and dark glass.
    static func sideWindow(_ b: inout StationKitBuilder, x: Float, z: Float, way: Float, y: Float, width: Float, height: Float) {
        b.box(x, y - 0.25, z + way * 0.1, width + 0.5, 0.3, 0.25, white)
        b.box(x, y + height, z + way * 0.1, width + 0.5, 0.3, 0.3, white)
        b.box(x, y, z + way * 0.06, width, 0.2, height, glass)
    }

    static func hall(_ b: inout StationKitBuilder) {
        let middle = (hallFront + hallBack) / 2, length = hallFront - hallBack
        let dark = Map3DColor.shaded(brick, 0.82)
        // A stone base all round, the brick standing on it.
        b.box(middle, 0, 0, length + 0.5, aisleOuter * 2 + 0.5, 0.6, Map3DPalette.granite)
        // The nave and its roof, the ridge front to back.
        b.box(middle, 0, 0, length, naveHalf * 2, naveEave, brick)
        b.mesh.addGableRoof(base: Map3DPoint(middle, naveEave, 0), forward: StationKitBuilder.forward, length: length, width: naveHalf * 2,
                            rise: ridge - naveEave, overhang: 0.45, color: slate, gable: brick)
        // The ridge's cap, so the two slopes part, and a band of glazing
        // down each slope.
        b.box(middle, ridge - 0.1, 0, length + 0.6, 0.6, 0.3, iron)
        let pitch = (ridge - naveEave) / naveHalf
        for way: Float in [-1, 1] {
            let near = way * 2.2, far = way * 4.0, lift: Float = 0.12
            b.face([Map3DPoint(hallBack + 3, ridge - 2.2 * pitch + lift, near), Map3DPoint(hallFront - 3, ridge - 2.2 * pitch + lift, near),
                    Map3DPoint(hallFront - 3, ridge - 4.0 * pitch + lift, far), Map3DPoint(hallBack + 3, ridge - 4.0 * pitch + lift, far)],
                   inside: Map3DPoint(middle, 0, 0), color: Map3DPalette.glazing)
        }
        for way: Float in [-1, 1] {
            let centre = way * (naveHalf + aisleOuter) / 2, width = aisleOuter - naveHalf
            b.box(middle, 0, centre, length, width, aisleEave, brick)
            // The lean-to roof, from under the nave's windows down to the
            // aisle's eaves, and the wall under its two ends.
            let inner = way * naveHalf, outer = way * (aisleOuter + 0.45), low = aisleEave - 0.15
            let roof = [Map3DPoint(hallBack - 0.3, aisleTop, inner), Map3DPoint(hallFront, aisleTop, inner),
                        Map3DPoint(hallFront, low, outer), Map3DPoint(hallBack - 0.3, low, outer)]
            b.face(roof, inside: Map3DPoint(middle, 0, centre), color: Map3DColor.shaded(slate, way < 0 ? 0.82 : 0.95))
            b.face(roof.map { $0 - Map3DPoint(0, 0.2, 0) }, inside: Map3DPoint(middle, 20, centre), color: Map3DColor.shaded(slate, 0.6))
            b.face([Map3DPoint(hallBack, aisleEave, inner), Map3DPoint(hallBack, aisleTop, inner), Map3DPoint(hallBack, aisleEave, way * aisleOuter)],
                   inside: Map3DPoint(middle, aisleEave, centre), color: dark)
            // The eaves' board.
            b.box(middle, low - 0.25, outer - way * 0.1, length + 0.3, 0.2, 0.3, white)
            // The nave's windows over the aisle: one dark band under a white
            // head.
            b.box(middle, aisleTop + 0.25, inner + way * 0.05, length - 3, 0.16, 0.95, glass)
            b.box(middle, aisleTop + 1.2, inner + way * 0.08, length - 2, 0.22, 0.25, white)
            // The side wall: brick piers, a white band over the windows and a
            // tall window in each bay.
            let bays = 6, bay = length / Float(bays)
            b.box(middle, 3.9, way * (aisleOuter + 0.06), length + 0.2, 0.2, 0.3, white)
            for index in 0...bays {
                b.box(hallBack + Float(index) * bay, 0, way * (aisleOuter + 0.12), 0.7, 0.45, aisleEave - 0.3, dark)
            }
            for index in 0..<bays {
                sideWindow(&b, x: hallBack + (Float(index) + 0.5) * bay, z: way * aisleOuter, way: way, y: 1.3, width: 1.5, height: 2.3)
            }
        }
        front(&b)
        back(&b)
    }

    /// The front: the gable standing above the roof behind it, banded in
    /// white, its crown, its three windows and the white arch of its door;
    /// and the curved heads of the two aisles.
    static func front(_ b: inout StationKitBuilder) {
        let x = hallFront, face = hallFront + 0.6
        let half = naveHalf + 0.3, shoulder = naveEave + 0.9, apex = ridge + 1.3
        slab(&b, [(-half, 0), (half, 0), (half, shoulder), (0, apex), (-half, shoulder)], back: x - 0.7, front: face, brick)
        // The white coping up the two rakes.
        for way: Float in [-1, 1] {
            b.beam(Map3DPoint(face - 0.65, shoulder + 0.05, way * (half + 0.2)), Map3DPoint(face - 0.65, apex + 0.1, 0), 0.9, white)
        }
        // The crown: a white round-headed block, a brick field and two
        // narrow windows in it.
        slab(&b, arched(z: 0, y: apex - 2.4, width: 4.4, height: 2.5), back: x - 0.3, front: face + 0.1, white)
        slab(&b, arched(z: 0, y: apex - 2.0, width: 3.3, height: 2.3), back: face, front: face + 0.2, brick)
        for way: Float in [-1, 1] {
            slab(&b, arched(z: way * 0.75, y: apex - 1.4, width: 0.75, height: 1.3, steps: 4), back: face, front: face + 0.3, glass)
        }
        // Two white bands, and the white pediment between them over the door.
        for y: Float in [4.3, 8.3] { b.box(face + 0.05, y, 0, 0.25, half * 2 + 0.3, 0.35, white) }
        for way: Float in [-1, 1] {
            b.beam(Map3DPoint(face + 0.12, 8.5, way * 5.2), Map3DPoint(face + 0.12, 10.3, 0), 0.36, white)
        }
        // Three windows over the door, one each side of it below.
        for z: Float in [-2.1, 0, 2.1] { frontWindow(&b, x: face, z: z, y: 5.3, width: 1.2, height: 1.6) }
        for z: Float in [-4.6, 4.6] { frontWindow(&b, x: face, z: z, y: 1.3, width: 1.5, height: 1.9) }
        // The door: a white arch standing out of the wall, dark within.
        slab(&b, arched(z: 0, y: 0, width: 5.2, height: 2.2), back: face, front: face + 0.9, white)
        slab(&b, arched(z: 0, y: 0, width: 3.8, height: 2.0), back: face + 0.85, front: face + 0.95, glass)
        // Each aisle's front: brick under a white segment of a circle.
        for way: Float in [-1, 1] {
            let inner = naveHalf + 0.3, outer = aisleOuter + 0.3, mid = (inner + outer) / 2, top = aisleEave + 0.9
            func head(_ low: Float, _ rise: Float, _ inset: Float) -> [(z: Float, y: Float)] {
                let a = inner + inset, c = outer - inset
                let arc = (0...6).map { step -> (z: Float, y: Float) in
                    let t = Float(step) / 6 * 2 - 1
                    return (way * (mid - t * (c - a) / 2), low + rise * (1 - t * t))
                }
                let outline = [(way * a, Float(0)), (way * c, Float(0))] + arc
                return way > 0 ? outline : Array(outline.reversed())
            }
            slab(&b, head(top, 1.7, 0), back: x - 0.3, front: face - 0.1, white)
            slab(&b, head(top - 0.5, 1.4, 0.45), back: x + 0.1, front: face, brick)
            b.box(face - 0.05, 4.3, way * mid, 0.25, outer - inner, 0.35, white)
            frontWindow(&b, x: face, z: way * mid, y: 1.2, width: 2.0, height: 1.9)
            for off: Float in [-2.5, 2.5] { frontWindow(&b, x: face, z: way * mid + off, y: 1.2, width: 1.0, height: 1.7) }
        }
    }

    /// The back: the gable standing above the roof as the front's does,
    /// coped in white, with a round window and a white band.
    static func back(_ b: inout StationKitBuilder) {
        let x = hallBack, half = naveHalf + 0.3, shoulder = naveEave + 0.9, apex = ridge + 1.0
        slab(&b, [(-half, 0), (half, 0), (half, shoulder), (0, apex), (-half, shoulder)], back: x - 0.5, front: x + 0.6, brick)
        for way: Float in [-1, 1] {
            b.beam(Map3DPoint(x + 0.05, shoulder + 0.05, way * (half + 0.2)), Map3DPoint(x + 0.05, apex + 0.1, 0), 0.9, white)
        }
        b.box(x - 0.55, 4.3, 0, 0.2, aisleOuter * 2 + 0.3, 0.35, white)
        b.box(x - 0.55, 8.3, 0, 0.2, half * 2, 0.35, white)
        slab(&b, (0..<10).map { step in (cosf(Float(step) / 10 * 2 * .pi), 9.9 + sinf(Float(step) / 10 * 2 * .pi)) }, back: x - 0.6, front: x - 0.5, glass)
        for z: Float in [-3.2, 0, 3.2] { b.box(x - 0.58, 5.2, z, 0.16, 1.3, 2.2, glass) }
        for way: Float in [-1, 1] {
            for off: Float in [-1.8, 1.8] { b.box(x - 0.08, 1.3, way * (naveHalf + aisleOuter) / 2 + off, 0.16, 1.3, 2.2, glass) }
        }
    }

    /// The ground: the paved yard, the ballast under the tracks there are,
    /// lawns and trees where a shed has not been built yet, and the path
    /// from the gate to the door.
    static func yard(_ b: inout StationKitBuilder, shown: Int, half: Float) {
        b.box(0, 0, 0, half * 2, half * 2, 0.1, Map3DPalette.forecourt)
        let reach = abs(trackOffsets[hallTracks - 1]) + 2.2
        b.box(12.5, 0.1, 0, 31, reach * 2, 0.04, paving)
        b.box(13, 0.1, 0, 32, 2.6, 0.08, Map3DPalette.granite)
        let sides = shedSides(exhibits: shown)
        for way: Float in [-1, 1] {
            if sides.contains(way) {
                b.box(4, 0.1, way * shedCentre, 30, shedHalf * 2 - 0.6, 0.04, paving)
            } else {
                b.box(-2, 0.1, way * 23, 50, 13, 0.08, Map3DPalette.park)
                for (x, z, size) in [(-24, 20, 1.6), (-14, 26, 1.9), (-3, 20.5, 1.5), (8, 26, 1.8), (18, 21, 1.5)] as [(Float, Float, Float)] {
                    b.tree(x, 0.18, way * z, size: size)
                }
            }
        }
    }

    /// Display track `index` from its buffer stop to its end by the street.
    static func track(_ b: inout StationKitBuilder, _ index: Int) {
        let z = trackOffsets[index], start = start(ofTrack: index), end = end(ofTrack: index)
        b.track(start, end, z, at: 0.1)
        // The buffer stop: two posts and a red beam.
        for side: Float in [-0.6, 0.6] { b.box(start + 0.3, 0.3, z + side, 0.25, 0.2, 0.95, iron) }
        b.box(start + 0.3, 1.0, z, 0.3, 1.9, 0.3, Map3DPalette.lantern)
    }

    /// A car shed on the left (`side` −1) or the right: brick walls at the
    /// back and the sides, brick piers and a white beam across its open
    /// front, a pitched roof.
    static func shed(_ b: inout StationKitBuilder, side: Float) {
        let z = side * shedCentre, middle = (shedFront + shedBack) / 2, length = shedFront - shedBack
        b.box(shedBack + 0.25, 0, z, 0.5, shedHalf * 2, shedEave, brick)
        for way: Float in [-1, 1] {
            b.box(middle, 0, z + way * (shedHalf - 0.25), length, 0.5, shedEave, brick)
            b.box(middle, 3.6, z + way * (shedHalf + 0.03), length - 2, 0.12, 0.9, glass)
            b.box(middle, 4.5, z + way * (shedHalf + 0.05), length, 0.16, 0.25, white)
        }
        for index in 0...shedTracks {
            b.box(shedFront - 0.4, 0, z - shedHalf + 0.4 + Float(index) * (shedHalf * 2 - 0.8) / Float(shedTracks), 0.8, 0.8, shedEave, brick)
        }
        b.box(shedFront - 0.4, shedEave - 0.9, z, 0.9, shedHalf * 2, 0.9, white)
        b.mesh.addGableRoof(base: Map3DPoint(middle, shedEave, z), forward: StationKitBuilder.forward, length: length, width: shedHalf * 2,
                            rise: shedRise, overhang: 0.5, color: slate, gable: brick)
        b.box(middle, shedEave + shedRise - 0.1, z, length + 0.8, 0.45, 0.25, iron)
    }

    /// The gate by the street: two brick posts with white caps, and a low
    /// brick wall along the plot's front each side of them.
    static func gate(_ b: inout StationKitBuilder, half: Float) {
        let x = half - 1
        for way: Float in [-1, 1] {
            b.box(x, 0.1, way * 2.4, 1, 1, 3, brick)
            b.box(x, 3.1, way * 2.4, 1.3, 1.3, 0.3, white)
            let from: Float = 2.9, to = half - 0.5
            b.box(x, 0.1, way * (from + to) / 2, 0.4, to - from, 0.9, brick)
            b.box(x, 1.0, way * (from + to) / 2, 0.55, to - from, 0.14, white)
        }
    }

    /// A steam engine's water tower in the yard's front corner: a white
    /// tank with a dark roof on a brick drum, its spout towards the tracks.
    static func waterTower(_ b: inout StationKitBuilder, x: Float, z: Float) {
        b.cylinder(x, 0.1, z, radius: 1.5, height: 5, color: brick, sides: 10)
        b.cylinder(x, 5.1, z, radius: 2.3, height: 2.4, color: white, sides: 12)
        b.cylinder(x, 7.5, z, radius: 2.5, height: 0.3, color: iron, sides: 12)
        b.cylinder(x, 7.8, z, radius: 1.2, height: 0.5, color: iron, sides: 8)
        b.beam(Map3DPoint(x, 5.6, z + 2.2), Map3DPoint(x, 4.6, z + 4.4), 0.3, iron)
    }

    // MARK: - The exhibits

    /// One exhibit standing on its track: the train set it is drawn as
    /// (``Map3DTrainSet/key(type:performance:)``) and where it stands in
    /// the museum's own space.
    struct Exhibit: Equatable, Sendable {
        let type: TrainType
        let key: String
        let track: Int
        /// The rail under the front of its car, `length` metres long, +x
        /// the museum's front.
        func front(length: Float) -> Map3DPoint {
            Map3DPoint(frontOfExhibit(onTrack: track, length: length), railTop, trackOffsets[track])
        }
    }

    /// The exhibits of `types` that stand in the yard, in their order: the
    /// first ``mostShown``.
    static func exhibits(of types: [TrainType]) -> [Exhibit] {
        types.prefix(mostShown).enumerated().map { index, type in
            Exhibit(type: type, key: Map3DTrainSet.key(type: type, performance: type.spec.performance ?? .standard), track: index)
        }
    }

    /// How many cars an exhibit's train is taken to have, when its head car
    /// is picked: the showcase's for its set, six for any other.
    static func cars(of key: String) -> Int {
        Map3DShowcase.entry(key)?.defaultCars ?? 6
    }

    /// The exhibits of `types` added to `frame` for a museum whose middle
    /// is on `base` facing `facing`: each one's head car, the pack's model
    /// within reach of `eye` and a box beyond it or when the type has no
    /// model; parked, so with no lamps lit and no label.
    static func add(to frame: inout Map3DTrains.Frame, exhibits types: [TrainType], at base: Map3DPoint, facing: Map3DPoint,
                    pack: Map3DModelPack?, eye: Map3DPoint?, reach: Map3DModelReach = .standard) {
        let along = Map3DPoint(facing.x, 0, facing.z).normalized ?? Map3DPoint(0, 0, 1)
        let right = along.cross(.up)
        for exhibit in exhibits(of: types) {
            let count = cars(of: exhibit.key)
            let near = pack?.modelIndex(forType: exhibit.key, carIndex: 0, count: count)
            // It stands by its own model's length, near or far.
            let boxLength = Float(exhibit.type.spec.carLength) / Float(WorldCoordinate.unitsPerMetre) - Map3DTrains.carGap
            let length = near.flatMap { pack?.models[$0].length } ?? boxLength
            let local = exhibit.front(length: length)
            let front = base + along * local.x + right * local.z + Map3DPoint(0, local.y, 0)
            var model: Int?
            if let pack, let near {
                let distance = eye.map { ($0 - front).length } ?? 0
                model = pack.model(near, forType: exhibit.key, count: count, at: distance, reach: reach)
            }
            if let pack, let model {
                let stripe = Map3DColor.rgb(Map3DShowcase.entry(exhibit.key)?.stripe ?? 0x2F6DB5)
                frame.instances.append(Map3DTrains.instance(of: pack.models[model], index: model, from: front - along * length, to: front,
                                                            stripe: stripe))
                // Its soft shadow on the track, as a running train's.
                let centre = front - along * (length / 2) + Map3DPoint(0, 0.05 - railTop + 0.36, 0)
                frame.shadows.addShadow(
                    inner: Map3DMesh.footprint(centre: centre, forward: along, length: length, width: Map3DTrains.carWidth),
                    outer: Map3DMesh.footprint(centre: centre, forward: along, length: length + 1, width: Map3DTrains.carWidth + 1),
                    darkness: 0.38)
            } else {
                frame.boxes.addBox(base: front - along * (length / 2), forward: along, length: length, width: Map3DTrains.carWidth,
                                   height: 3.4, top: Map3DPalette.roof, side: Map3DPalette.tileWhite)
            }
        }
    }

    /// A world's museum laid in a scene: where it stands there and what it
    /// shows, for the exhibits drawn each frame.
    public struct Laid: Equatable, Sendable {
        public let exhibits: [TrainType]
        public let base: Map3DPoint
        public let facing: Map3DPoint

        /// `world`'s museum in `scene`, as the scene's builder stood its
        /// hall (``Map3DScene/Builder/addPlacedKitBuilding(_:base:side:)``);
        /// `nil` with no museum or none of its exhibits to show.
        public init?(world: GameWorld, scene: Map3DScene) {
            guard let museum = world.railwayMuseum, !museum.exhibits.isEmpty else { return nil }
            let flat = scene.point(worldX: Double(museum.centre.x), worldY: Double(museum.centre.y), height: 0)
            exhibits = museum.exhibits
            base = Map3DPoint(flat.x, scene.drawnGround.height(x: flat.x, z: flat.z, world: world), flat.z)
            facing = Map3DScene.Builder.templeFacings[0]
        }

        /// The exhibits added to `frame`, seen from `eye`.
        public func add(to frame: inout Map3DTrains.Frame, pack: Map3DModelPack?, eye: Map3DPoint?, reach: Map3DModelReach = .standard) {
            Map3DRailwayMuseum.add(to: &frame, exhibits: exhibits, at: base, facing: facing, pack: pack, eye: eye, reach: reach)
        }
    }

    /// How many exhibits `world`'s museum shows in its yard, 0 with no
    /// museum: when it changes the 3D map builds the museum again, a new
    /// exhibit bringing its track or its shed.
    public static func shown(in world: GameWorld) -> Int {
        min(world.railwayMuseum?.exhibits.count ?? 0, mostShown)
    }

    /// The hall alone as one model, for a look sheet beside the photographs.
    public static func hallModel() -> Map3DModelPack.Model {
        var b = StationKitBuilder()
        hall(&b)
        return .flat(named: "railway-museum-hall", from: b.mesh)
    }

    /// The museum showing `types` as one model, the exhibits' head cars
    /// standing on their tracks in it: what the look sheets and the tests
    /// read (`tools/model-look/export-museum.sh`). The 3D map draws the
    /// exhibits as instances instead. With `far`, the exhibits' far models
    /// where their sets have them, as the map draws them from a distance.
    public static func lookModel(exhibits types: [TrainType], far: Bool = false, pack: Map3DModelPack = .standard) -> Map3DModelPack.Model {
        var b = StationKitBuilder()
        b.mesh = mesh(exhibits: types.count)
        for exhibit in exhibits(of: types) {
            let count = cars(of: exhibit.key)
            guard let near = pack.modelIndex(forType: exhibit.key, carIndex: 0, count: count) else { continue }
            let index = far ? pack.farModel(of: near, forType: exhibit.key, count: count) ?? near : near
            let model = pack.models[index], front = exhibit.front(length: pack.models[near].length)
            b.add(model, at: Map3DPoint(front.x - model.maximum.x, front.y, front.z))
        }
        return .flat(named: "railway-museum-\(types.count)", from: b.mesh)
    }
}
