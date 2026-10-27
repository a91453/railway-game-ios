import Foundation
import GameCore

// Decision 441: a depot is seen as one in 3D. Beside each depot station
// (`Station.isDepot`) stands a three-track maintenance shed in place of a
// passenger building, and at the Changhua Roundhouse (attraction t071) a
// turntable, the only one: a modern depot has none.
//
// Both are the private reference's Railway Facilities Pack 01
// (`Railway/railway-asset-pipeline-2026-10-22/tools/railway-asset-pipeline/railway_facilities_pack01.py`,
// `build_shed` and `build_turntable`), its boxes and sizes laid again here
// as native recipes in the station kit's builder; no mesh, texture or file
// of the pack is read. The pack's axes are x front, y left, z up from the
// box's middle; the kit's x front, y up from the box's foot, z right.

/// The depot's maintenance shed and the roundhouse's turntable.
public enum Map3DDepotFacilities {
    /// The pack's colours not in ``Map3DPalette``: its steel, dark and
    /// glass, and its wall (one of the concrete walls).
    static let steel = Map3DColor.rgb(0x8A9099)
    static let dark = Map3DColor.rgb(0x2B2F36)
    static let glass = Map3DColor.rgb(0x26313D)
    static let wall = Map3DColor.rgb(0xC9CCD5)

    /// The shed's size: 36 m long (its open bays at +x), 16 m wide, its
    /// walls 6.4 m and its ridge 9 m high (`build_shed`).
    public static let shedLength: Float = 36
    public static let shedWidth: Float = 16
    static let shedWall: Float = 6.4
    static let shedRidge: Float = 9
    /// Track to track inside it, as the pack lays them.
    static let shedTracks: [Float] = [-5.1, 0, 5.1]

    /// `depot-maintenance-shed-a`: the floor, the back and side walls, the
    /// piers and lintel of the three open bays at the front (+x), a gabled
    /// roof with a vent along its ridge, five windows a side, and a track
    /// in each bay with its inspection pit between the rails. Its middle
    /// on the ground at the origin.
    public static let shed: Map3DMesh = {
        var kit = StationKitBuilder()
        let half = shedWidth / 2
        kit.box(0, 0, 0, shedLength, shedWidth, 0.2, Map3DPalette.concrete)
        kit.box(-shedLength / 2 + 0.18, 0, 0, 0.36, shedWidth, shedWall, wall)
        for z in [-half + 0.18, half - 0.18] { kit.box(0, 0, z, shedLength, 0.36, shedWall, wall) }
        for z in [-half + 0.22, -shedWidth / 6, shedWidth / 6, half - 0.22] {
            kit.box(shedLength / 2 - 0.18, 0, z, 0.36, 0.42, shedWall, steel)
        }
        kit.box(shedLength / 2 - 0.18, shedWall - 0.625, 0, 0.36, shedWidth, 0.55, Map3DPalette.canopy)
        // The roof's two sides, each a slab 0.22 m thick from the eaves to
        // the ridge.
        let rise = shedRidge - shedWall, slope = (half * half + rise * rise).squareRoot()
        for side: Float in [-1, 1] {
            kit.slab(centre: Map3DPoint(0, (shedWall + shedRidge) / 2, side * half / 2),
                     up: Map3DPoint(0, rise / slope, -side * half / slope), length: shedLength + 0.7, wide: slope, thickness: 0.22,
                     color: Map3DPalette.roof)
        }
        for z in shedTracks {
            kit.box(0, 0.2, z, shedLength - 1, 1.9, 0.14, dark)
            for rail: Float in [-0.5335, 0.5335] { kit.box(0, 0.35, z + rail, shedLength - 1, 0.075, 0.1, Map3DPalette.railTop) }
            // The pack's pit marker lies inside the bed, where it does not
            // show: here on its top between the rails.
            kit.box(-2, 0.34, z, 22, 0.72, 0.02, steel)
        }
        for x: Float in [-13, -7, -1, 5, 11] {
            for z in [-half + 0.02, half - 0.02] { kit.box(x, 3.425, z, 2.2, 0.05, 1.25, glass) }
        }
        kit.box(-2, shedRidge + 0.04, 0, 18, 0.28, 0.24, steel)
        return kit.mesh
    }()

    /// The shed far off: a box as long and wide, between its eaves and
    /// ridge high, its roof's colour on top.
    public static let shedFar: Map3DMesh = {
        var mesh = Map3DMesh()
        mesh.addBox(base: .zero, forward: Map3DPoint(1, 0, 0), length: shedLength, width: shedWidth, height: (shedWall + shedRidge) / 2,
                    top: Map3DPalette.roof, side: wall)
        return mesh
    }()

    /// The turntable's pit, to the outside of its rim, and its bridge.
    public static let pitRadius: Float = 13
    public static let bridgeLength: Float = 24

    /// `depot-turntable-a`: a pit with a concrete rim, a pivot, a 24 m
    /// bridge (+x along it) with sleepers, rails, a railing each side and
    /// a yellow plate at each end, and a small operator's cabin on it. Its
    /// middle on the ground at the origin.
    public static let turntable: Map3DMesh = {
        var kit = StationKitBuilder()
        kit.disk(y: 0.03, radius: 12.35, color: dark, sides: 32)
        kit.ring(from: 0, to: 0.38, inner: 12.35, outer: pitRadius, color: Map3DPalette.concrete, sides: 32)
        kit.cylinder(0, 0.08, 0, radius: 0.62, height: 0.64, color: steel, sides: 16)
        kit.box(0, 0.43, 0, bridgeLength, 2.8, 0.38, steel)
        kit.box(0, 0.79, 0, 23.6, 2.45, 0.08, dark)
        for index in -10...10 { kit.box(Float(index) * 1.08, 0.865, 0, 0.16, 2.35, 0.11, Map3DPalette.ballast) }
        for z: Float in [-0.5335, 0.5335] { kit.box(0, 0.97, z, 23.6, 0.075, 0.1, Map3DPalette.railTop) }
        for z: Float in [-1.27, 1.27] {
            kit.box(0, 1.6925, z, 23, 0.055, 0.055, steel)
            kit.box(0, 1.2275, z, 23, 0.045, 0.045, steel)
            for x: Float in [-11.2, -8, -4, 0, 4, 8, 11.2] { kit.box(x, 0.725, z, 0.055, 0.055, 1.25, steel) }
        }
        for x: Float in [-11.9, 11.9] { kit.box(x, 0.975, 0, 0.12, 2.7, 0.55, Map3DPalette.platformEdge) }
        kit.box(3.8, 0.625, 1.72, 2.2, 1.35, 1.75, wall)
        kit.box(3.8, 2.36, 1.72, 2.45, 1.55, 0.12, Map3DPalette.roof)
        kit.box(4.91, 1.21, 1.72, 0.06, 0.78, 0.82, glass)
        return kit.mesh
    }()

    /// The turntable far off: its pit and its bridge as a box.
    public static let turntableFar: Map3DMesh = {
        var kit = StationKitBuilder()
        kit.disk(y: 0.03, radius: pitRadius, color: dark, sides: 12)
        kit.mesh.addBox(base: .zero, forward: Map3DPoint(1, 0, 0), length: bridgeLength, width: 2.8, height: 1.2,
                        top: steel, side: steel)
        return kit.mesh
    }()

    /// Where the Changhua Roundhouse's turntable stands, and the middle of
    /// the roundhouse it serves. The private reference's tw3d pack
    /// (`Railway/tw3d-reference-clean/source/js/cities/changhua/landmarks/catalog.json`,
    /// `changhua-roundhouse`) found its pit as the largest clear disc
    /// inside the hull of OpenStreetMap's outline of the roundhouse (way
    /// 220285047, ODbL) and outside it: 5.3 m east and 22.3 m south of the
    /// roundhouse's middle. Its bridge lies towards that middle, along the
    /// middle stall.
    public static let roundhouse = (latitude: 24.0858858, longitude: 120.5400988)
    public static let turntablePlace = (latitude: 24.0858858 - 22.3 / 110_759, longitude: 120.5400988 + 5.3 / 101_684)

    /// Which way the bays of a depot's shed open, along its platforms'
    /// line (`along`), from the counts of track points beyond each end
    /// of them: towards the end more track runs on from (the yard's
    /// throat, where its sidings meet), the end the line starts at when
    /// neither has more.
    public static func baysFacing(beyondStart: Int, beyondEnd: Int) -> Float {
        beyondEnd > beyondStart ? 1 : -1
    }
}

extension StationKitBuilder {
    /// A slab `length` along x, `wide` along `up` (a direction across x),
    /// `thickness` thick, its middle at `centre`: a roof's side.
    mutating func slab(centre: Map3DPoint, up: Map3DPoint, length: Float, wide: Float, thickness: Float, color: UInt32) {
        let x = Map3DPoint(length / 2, 0, 0), v = up * (wide / 2)
        let w = (Map3DPoint(1, 0, 0).cross(up).normalized ?? Map3DPoint(0, 1, 0)) * (thickness / 2)
        let p = [centre - x - v - w, centre + x - v - w, centre + x + v - w, centre - x + v - w,
                 centre - x - v + w, centre + x - v + w, centre + x + v + w, centre - x + v + w]
        for f in [[0, 3, 2, 1], [4, 5, 6, 7], [0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7]] {
            face(f.map { p[$0] }, inside: centre, color: color)
        }
    }

    /// A flat disc facing up, `y` over the origin.
    mutating func disk(y: Float, radius: Float, color: UInt32, sides: Int) {
        let centre = Map3DPoint(0, y, 0)
        for i in 0..<sides {
            let a0 = Float(i) * 2 * Float.pi / Float(sides), a1 = Float(i + 1) * 2 * Float.pi / Float(sides)
            face([centre, Map3DPoint(cosf(a0) * radius, y, sinf(a0) * radius), Map3DPoint(cosf(a1) * radius, y, sinf(a1) * radius)],
                 inside: centre - Map3DPoint(0, 1, 0), color: color)
        }
    }

    /// A ring round the origin from height `from` to `to`, `inner` to
    /// `outer` metres out: its top and its two sides.
    mutating func ring(from: Float, to: Float, inner: Float, outer: Float, color: UInt32, sides: Int) {
        let middle = (inner + outer) / 2
        for i in 0..<sides {
            let a0 = Float(i) * 2 * Float.pi / Float(sides), a1 = Float(i + 1) * 2 * Float.pi / Float(sides)
            func at(_ r: Float, _ a: Float, _ y: Float) -> Map3DPoint { Map3DPoint(cosf(a) * r, y, sinf(a) * r) }
            let mid = (a0 + a1) / 2
            face([at(inner, a0, to), at(inner, a1, to), at(outer, a1, to), at(outer, a0, to)],
                 inside: at(middle, mid, from), color: color)
            face([at(outer, a0, from), at(outer, a1, from), at(outer, a1, to), at(outer, a0, to)],
                 inside: at(middle, mid, (from + to) / 2), color: color)
            face([at(inner, a1, from), at(inner, a0, from), at(inner, a0, to), at(inner, a1, to)],
                 inside: at(middle, mid, (from + to) / 2), color: color)
        }
    }
}

// MARK: - Building

extension Map3DScene.Builder {
    /// Decision 441: a depot's maintenance shed beside its platforms (as
    /// a station's building stands, ``besidePlatforms(depth:wide:platforms:middle:)``),
    /// its length along them and its bays open towards the yard's throat.
    /// Close up the pack's shed with its shadow, far off a box. The cells
    /// it stands on.
    mutating func addDepotShed(platforms: [LaidPlatform], path: Map3DStreetLife.Path,
                               middle: (point: Map3DPoint, along: Map3DPoint, right: Map3DPoint)) -> Set<Map3DScene.ChunkKey> {
        let depth = Map3DDepotFacilities.shedWidth, wide = Map3DDepotFacilities.shedLength
        let (out, back) = besidePlatforms(depth: depth, wide: wide, platforms: platforms, middle: middle)
        // Track points within 60 m beyond each end of the platforms,
        // within 15 m of their line.
        let half = path.length / 2
        func beyond(_ sign: Float) -> Int {
            trackLines.reduce(0) { count, line in
                count + line.points.filter { p in
                    let d = p - middle.point, along = d.dot(middle.along) * sign
                    return along > half && along < half + 60 && abs(d.dot(middle.right)) < 15
                }.count
            }
        }
        let bays = middle.along * Map3DDepotFacilities.baysFacing(beyondStart: beyond(-1), beyondEnd: beyond(1))
        let centre0 = back + out * (depth / 2)
        let foot = Map3DPoint(centre0.x, drawnGround(x: centre0.x, z: centre0.z), centre0.z)
        let saved = target
        defer { target = saved }
        target = .near
        mesh(at: foot) { $0.append(Map3DDepotFacilities.shed, at: foot, forward: bays) }
        addShadow(centre: foot, forward: bays, length: wide, width: depth, spread: 3, darkness: 0.3)
        target = .far
        mesh(at: foot) { $0.append(Map3DDepotFacilities.shedFar, at: foot, forward: bays) }
        // The cells under its footprint.
        let corners = Map3DMesh.footprint(centre: foot, forward: bays, length: wide, width: depth)
        houseFootprints.append(corners)
        return cells(under: corners)
    }

    /// Decision 441: on a real-world map, the Changhua Roundhouse's
    /// turntable where it stands, its bridge towards the roundhouse; none
    /// where the player's track or platforms come. Close up the pack's
    /// turntable, far off its pit and a box for its bridge. The cells it
    /// stands on, none when it is not in the scene.
    mutating func addRoundhouseTurntable(frame: RealWorldFrame) -> Set<Map3DScene.ChunkKey> {
        let place = Map3DDepotFacilities.turntablePlace, house = Map3DDepotFacilities.roundhouse
        let at = frame.worldPosition(latitude: place.latitude, longitude: place.longitude)
        guard contains(x: at.x, y: at.y) else { return [] }
        let toward = frame.worldPosition(latitude: house.latitude, longitude: house.longitude)
        let centre = point(x: at.x, y: at.y, height: 0), middle = point(x: toward.x, y: toward.y, height: 0)
        let forward = Map3DPoint(middle.x - centre.x, 0, middle.z - centre.z).normalized ?? Map3DPoint(1, 0, 0)
        let size = 2 * Map3DDepotFacilities.pitRadius
        let outline = Map3DMesh.footprint(centre: centre, forward: forward, length: size, width: size)
        guard isClearOfTrack(outline) else { return [] }
        let foot = Map3DPoint(centre.x, outline.map { drawnGround(x: $0.x, z: $0.z) }.min() ?? 0, centre.z)
        let saved = target
        defer { target = saved }
        target = .near
        mesh(at: foot) { $0.append(Map3DDepotFacilities.turntable, at: foot, forward: forward) }
        target = .far
        mesh(at: foot) { $0.append(Map3DDepotFacilities.turntableFar, at: foot, forward: forward) }
        return cells(under: outline)
    }
}
