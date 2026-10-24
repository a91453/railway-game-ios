import Foundation
import GameCore

// ARCHITECTURE decision 321: the 3D map's stations from the station kit
// (`Map3DStationKit`, #913). A station of the game near a real station of
// the kit's catalogue (on a real-world map) is built as that station's
// recipe, a landmark with its own outline; any other as the kit's general
// type for its platforms: on the ground a regional station or a halt by
// how many platforms it has, on a viaduct stair entrances, underground
// exits at street level. The kit's own track and platforms are left out:
// the game's track and `TrackPlatform`s are drawn as they are, the kit's
// canopy along each of them at the platform's own height, and the
// building beside them on the side clear of other track, its back to the
// platforms. Close up the kit's models; far off a box for each building
// and the flat canopy that was. Only drawing: which station stands where
// is GameCore's.

extension Map3DStationKit {
    /// How a station's platforms lie, for its general type.
    enum Layout: Equatable {
        /// On the ground: how many platforms, and the longest in metres.
        case surface(platforms: Int, longest: Float)
        /// On a viaduct or a bridge.
        case elevated
        /// Every platform in a tunnel.
        case underground
    }

    /// How near, in metres, a real station of the catalogue must be to a
    /// station of the game for the game's to be built as it.
    static let realReach: Double = 300

    /// The recipe station `id` is built as: the real station of the
    /// catalogue within ``realReach`` of `middle` (world units) on a
    /// real-world map, when its kind suits `layout` (an underground
    /// station's exits only over a tunnel, a viaduct's stairs only under a
    /// viaduct), the nearest first; otherwise the general type for
    /// `layout`.
    static func recipe(for id: StationID, at middle: (x: Double, y: Double), layout: Layout, frame: RealWorldFrame?) -> Station {
        if let frame {
            let reach = realReach * Double(WorldCoordinate.unitsPerMetre)
            let near = stations.compactMap { station -> (Station, Double)? in
                let p = frame.worldPosition(latitude: station.latitude, longitude: station.longitude)
                let distance = ((p.x - middle.x) * (p.x - middle.x) + (p.y - middle.y) * (p.y - middle.y)).squareRoot()
                return distance <= reach && suits(station.profile, layout) ? (station, distance) : nil
            }
            if let nearest = near.min(by: { $0.1 < $1.1 || $0.1 == $1.1 && $0.0.id < $1.0.id }) { return nearest.0 }
        }
        let seed = UInt32(truncatingIfNeeded: id.rawValue &* 2_654_435_761)
        let profile: Profile, tier: Int
        switch layout {
        case .underground: (profile, tier) = (.underground, 1)
        case .elevated: (profile, tier) = (.elevated, 1)
        case let .surface(platforms, longest):
            // The kit's classes: 特等 0 to 三等 3, the rest a halt.
            tier = max(0, 4 - platforms)
            profile = platforms <= 1 && longest < 100 ? .halt : .regional
        }
        return Station(id: "game-\(id.rawValue)", name: "", system: "game", latitude: 0, longitude: 0, lines: [], profile: profile,
                       tier: tier, seed: seed, planned: false, isLandmark: false)
    }

    /// Whether a station of `profile` can stand where the platforms lie
    /// as `layout`.
    static func suits(_ profile: Profile, _ layout: Layout) -> Bool {
        switch profile {
        case .underground, .formosa, .centralPark: layout == .underground
        case .elevated: layout == .elevated
        case .lightRail: layout != .underground
        default: true
        }
    }

    /// Whether `profile` is a building (beside the platforms, or over them
    /// when they are underground), not entrances alone.
    static func hasHouse(_ profile: Profile) -> Bool {
        switch profile {
        case .underground, .formosa, .centralPark, .elevated, .lightRail: false
        default: true
        }
    }

    /// The far box's walls and roof for a building of `profile`.
    static func farColours(_ profile: Profile) -> (wall: UInt32, roof: UInt32) {
        switch profile {
        case .taipei: (Map3DPalette.stone, Map3DPalette.templeRidge)
        case .kaohsiung: (Map3DPalette.tileWhite, Map3DPalette.gymGreen)
        case .timber: (Map3DPalette.counters[1], Map3DPalette.gymGreen)
        case .hsinchu, .tainan, .chiayi, .heritage, .taichung: (Map3DPalette.brick, Map3DPalette.templeRidge)
        case .regional, .halt, .taitung: (Map3DPalette.schoolWalls, Map3DPalette.gymGreen)
        default: (Map3DPalette.tileWhite, Map3DPalette.tileWhite)
        }
    }
}

extension StationKitBuilder {
    /// Decision 321: the station's building alone, without the kit's track
    /// and platforms, its back (−x) to the platforms, its long side along
    /// them (z), a forecourt to its front; nothing for a profile that has
    /// only entrances (``Map3DStationKit/hasHouse(_:)``). The kit's own
    /// recipes (`station(_:)`), each rail court left out.
    mutating func house(_ station: Map3DStationKit.Station) {
        let p = station.profile, v = Int(station.seed % 7)
        switch p {
        case .taipei: taipei()
        case .taichung:
            // The old brick station on the forecourt; the elevated hall is
            // the game's own viaduct.
            historic(0, 0.3, 0, length: 13, width: 35, wood: false, clock: true)
        case .kaohsiung: kaohsiung()
        case .hsinchu, .tainan, .chiayi, .heritage, .timber:
            let grand = p == .hsinchu || p == .tainan
            historic(0, 0.25, 0, length: 13, width: grand ? 43 : 21 + Float(v) * 2, wood: p == .timber, clock: grand || p == .chiayi)
        case .banqiao, .nangang:
            let w: Float = p == .nangang ? 74 : 64
            facade(0, 0.3, 0, 38, w, 10, Self.white, bays: 12)
            for sign: Float in [-1, 1] {
                let h: Float = p == .nangang ? 55 : 39
                facade(-7, 10.3, sign * w * 0.30, 23, w * 0.28, h, Map3DPalette.concrete, bays: 5)
                for floor in 1..<Int(h / 4) { box(-7, 10.3 + Float(floor) * 4, sign * w * 0.30, 23.15, w * 0.28 + 0.15, 0.22, Self.white) }
                box(-7, h + 10.3, sign * w * 0.30, 23.5, w * 0.28 + 0.5, 0.45, Self.steel)
            }
            canopy(24, 7, 0, length: 10, width: w * 0.8, rise: 2, color: Self.glass)
            for z: Float in [-w * 0.35, w * 0.35] { box(27, 0.3, z, 0.4, 0.4, 7.55, Self.steel) }
        case .hualien:
            facade(8, 0.25, 0, 28, 62, 6.5, Self.white, bays: 10)
            for z: Float in [-22, 0, 22] {
                for x: Float in [-5, 21] { box(x, 0.25, z, 0.5, 0.5, 8, Self.steel) }
                hip(8, 8.25, z, 30, 23, 4, Self.white)
            }
        case .taitung:
            facade(10, 0.25, 0, 22, 62, 5.8, Map3DPalette.schoolWalls, bays: 10)
            for z: Float in [-22, 0, 22] {
                canopy(9, 7, z, length: 27, width: 22, rise: 4, color: Self.white)
                for x: Float in [-3, 21] { for dz: Float in [-9, 9] { box(x, 0.25, z + dz, 0.35, 0.35, 7.55, Map3DPalette.brick) } }
            }
        case .keelung:
            facade(4, 0.25, 0, 30, 52, 7, Self.white, bays: 8)
            canopy(4, 7.25, 0, length: 32, width: 54, rise: 9, color: Self.white)
            for z: Float in [-24, 0, 24] {
                beam(Map3DPoint(20, 0.25, z), Map3DPoint(20, 7.25 + 9 * sinf((z + 27) / 54 * Float.pi), z), 0.45, Self.steel)
            }
        case .zuoying, .hsrTaichung, .hsrTaoyuan, .hsrHsinchu, .hsrTainan, .highSpeed:
            highSpeed(profile: p, variant: v)
        case .regional, .halt:
            let small = p == .halt
            let width: Float = small ? 10 + Float(v) : 22 + Float(4 - station.tier) * 5 + Float(v)
            facade(13, 0.25, 0, 12, width, small ? 4.2 : 6.2, Map3DPalette.schoolWalls, bays: small ? 3 : 7)
            if v % 2 == 0 {
                gable(13, small ? 4.45 : 6.45, 0, 13, width + 1, small ? 1.6 : 2.4, Map3DPalette.gymGreen)
            } else {
                box(13, small ? 4.45 : 6.45, 0, 13, width + 1, 0.25, Map3DPalette.tinRoofs[v % 5])
            }
            box(20, 2.8, 0, 3, width + 2, 0.20, Map3DPalette.canopy)
            for z: Float in [-width * 0.43, width * 0.43] { box(21.2, 0.25, z, 0.24, 0.24, 2.55, Self.steel) }
        case .formosa, .centralPark, .underground, .elevated, .lightRail:
            return
        }
        // A forecourt from its back to six metres before it.
        guard let bounds = mesh.bounds, bounds.min.x < bounds.max.x else { return }
        let length = bounds.max.x - bounds.min.x + 6, width = bounds.max.z - bounds.min.z + 8
        box(bounds.min.x + length / 2, 0, (bounds.min.z + bounds.max.z) / 2, length, width, 0.2, Map3DPalette.plaza)
    }

    /// The kit's canopy over `length` metres of a platform `width` wide
    /// whose top is at y 0: the closed curved roof 3.2 m up, a column at
    /// its start (and at its end when `last`), as the kit's
    /// `platformCanopy`.
    mutating func platformCanopy(length: Float, width: Float, last: Bool) {
        canopy(0, 3.2, 0, length: length, width: width, rise: 0.6, color: Map3DPalette.canopy)
        for x in last ? [-length / 2, length / 2] : [-length / 2] { box(x, 0, 0, 0.22, 0.22, 3.58, Self.steel) }
    }

    /// Decision 321: 美麗島's two glass entrances, as the kit's
    /// underground station has them, their front along x.
    mutating func formosaEntrances() {
        box(0, 0, 0, 12.5, 26, 0.15, Map3DPalette.plaza)
        for sign: Float in [-1, 1] {
            hip(0, 4.6, sign * 6, 9, 9, 4, Self.glass)
            for dx: Float in [-3.2, 3.2] { for dz: Float in [-3.2, 3.2] { box(dx, 0, sign * 6 + dz, 0.15, 0.15, 4.6, Self.steel) } }
        }
    }
}

extension Map3DScene.Builder {
    /// A platform as ``addPlatforms(_:)`` laid it: its line at the rails'
    /// height, how far its middle lies to the line's right and how wide
    /// it is, and what carries its track.
    struct LaidPlatform {
        let station: StationID
        let line: [Map3DPoint]
        let offset: Float
        let width: Float
        let structure: TrackStructure
    }

    /// Every station in the scene from the station kit: the canopies over
    /// its platforms, its building or its entrances; the cells (64 m) its
    /// building stands on, for a plaza there and no city lot. On a
    /// real-world map (`frame`), the real stations' recipes.
    /// With `shops` false, the shop streets wait for
    /// ``addShopStreets()``, after the streets they keep clear of. No
    /// building of the profiles in `drawnElsewhere` (decision 370: Taipei
    /// Main Station's, where its landmark stands).
    mutating func addStations(_ snapshot: RailwaySnapshot, frame: RealWorldFrame?, shops: Bool = true,
                              drawnElsewhere: Set<Map3DStationKit.Profile> = []) -> Set<Map3DScene.ChunkKey> {
        let saved = target
        defer { target = saved }
        addCanopies()
        let tunnels = snapshot.platforms.filter { platform in
            platform.structure == .tunnel && platform.points.count > 1
                && platform.points.contains { contains(x: Double($0.x), y: Double($0.y)) }
        }
        var laid: [StationID: [LaidPlatform]] = [:], under: [StationID: [[Map3DPoint]]] = [:]
        for platform in laidPlatforms { laid[platform.station, default: []].append(platform) }
        for platform in tunnels { under[platform.platform.station, default: []].append(platform.points.map { point($0) + Self.lifted }) }
        var cells = Set<Map3DScene.ChunkKey>()
        for id in Set(laid.keys).union(under.keys).sorted() {
            // A station with platforms both on the ground and on a viaduct
            // (two lines crossing) stands by those on the ground.
            let all = laid[id] ?? [], onGround = all.filter { $0.structure != .elevated && $0.structure != .bridge }
            let open = onGround.isEmpty ? all : onGround, lines = open.isEmpty ? under[id] ?? [] : open.map(\.line)
            guard let longest = lines.compactMap(Map3DStreetLife.Path.init).max(by: { $0.length < $1.length }) else { continue }
            let middle = longest.at(longest.length / 2)
            let layout: Map3DStationKit.Layout = open.isEmpty ? .underground
                : onGround.isEmpty ? .elevated
                : .surface(platforms: open.count, longest: longest.length)
            let world = (x: originX + Double(middle.point.x) * Self.metre, y: originY + Double(middle.point.z) * Self.metre)
            let station = Map3DStationKit.recipe(for: id, at: world, layout: layout, frame: frame)
            if drawnElsewhere.contains(station.profile) {
                continue
            } else if Map3DStationKit.hasHouse(station.profile) {
                cells.formUnion(addHouse(station, platforms: open, middle: middle))
            } else {
                addEntrances(station, platforms: open, path: longest, middle: middle)
            }
        }
        if shops { addShopStreets() }
        return cells
    }

    /// Decision 322: the shop streets of the stations' buildings laid so
    /// far, on the plazas they leave.
    mutating func addShopStreets() {
        let saved = target
        defer { target = saved }
        for street in shopStreets {
            addShopStreet(street.station, centre: street.centre, forward: street.forward, depth: street.depth, wide: street.wide, cells: street.cells)
        }
        shopStreets = []
    }

    /// The kit's canopy over the middle three fifths of each platform (as
    /// most of TRA's are, decision 259), in pieces of at most 8 m along
    /// its line; far off the flat canopy.
    private mutating func addCanopies() {
        for platform in laidPlatforms {
            let middle = Self.middle(of: platform.line, share: 0.6)
            guard let path = Map3DStreetLife.Path(middle) else { continue }
            let count = max(1, Int((path.length / 8).rounded(.up))), step = path.length / Float(count)
            let width = min(platform.width + 0.3, 7)
            let centre = path.at(path.length / 2).point
            target = .near
            mesh(at: centre) { mesh in
                for index in 0..<count {
                    let a = path.at(step * Float(index)), b = path.at(step * Float(index + 1))
                    let along = Map3DPoint(b.point.x - a.point.x, 0, b.point.z - a.point.z)
                    var kit = StationKitBuilder()
                    // A little longer, so the pieces meet on a curve.
                    kit.platformCanopy(length: along.length + 0.3, width: width, last: index == count - 1)
                    let foot = (a.point + b.point) * 0.5 + (a.right + b.right) * (platform.offset / 2) + Map3DPoint(0, Self.platformHeight, 0)
                    mesh.append(kit.mesh, at: foot, forward: along)
                }
            }
            target = .far
            mesh(at: centre) { mesh in
                mesh.addRibbon(along: middle, width: min(platform.width, 3.6), offset: platform.offset, lift: Self.canopyHeight, depth: 0.3,
                               top: Map3DPalette.canopy, side: Map3DPalette.canopy, topPaint: Self.metal)
            }
        }
    }

    /// `station`'s building: beside its platforms on the side with less
    /// other track, its back a metre past the farthest of them, or over
    /// the middle of its underground platforms. Close up the kit's model
    /// with its shadow, far off a box. The cells it stands on.
    private mutating func addHouse(_ station: Map3DStationKit.Station, platforms: [LaidPlatform],
                                   middle: (point: Map3DPoint, along: Map3DPoint, right: Map3DPoint)) -> Set<Map3DScene.ChunkKey> {
        var kit = StationKitBuilder()
        kit.house(station)
        guard let bounds = kit.mesh.bounds else { return [] }
        let depth = bounds.max.x - bounds.min.x, wide = bounds.max.z - bounds.min.z
        let forward: Map3DPoint, back: Map3DPoint
        if platforms.isEmpty {
            forward = middle.right
            back = middle.point - forward * (depth / 2)
        } else {
            // How far each side the platforms and their track reach from
            // the middle, and how much other track lies where the
            // building would stand.
            func reach(_ side: Float, of across: (LaidPlatform) -> [Float]) -> Float {
                platforms.map { platform -> Float in
                    guard let path = Map3DStreetLife.Path(platform.line) else { return 0 }
                    let at = path.at(path.length / 2)
                    return across(platform).map { (at.point + at.right * $0 - middle.point).dot(middle.right) * side }.max() ?? 0
                }.max() ?? 0
            }
            func reach(_ side: Float) -> Float {
                reach(side) { [$0.offset - $0.width / 2, $0.offset + $0.width / 2, -2.5, 2.5] }
            }
            // Whether a platform, not its track, is outermost that way: the
            // building then opens onto it, as most stations' do.
            func opensOnto(_ side: Float) -> Bool {
                reach(side) { [$0.offset - $0.width / 2, $0.offset + $0.width / 2] } >= reach(side) { _ in [-2.5, 2.5] }
            }
            // How far the track points within `from` to `to` metres of
            // `anchor` that way lie, beside the building's length.
            func farthest(_ side: Float, from: Float, to: Float, at anchor: Map3DPoint) -> [Float] {
                trackLines.flatMap { line in
                    line.points.compactMap { p -> Float? in
                        let d = p - anchor, across = d.dot(middle.right) * side, along = abs(d.dot(middle.along))
                        return across > from && across < to && along < wide / 2 + 4 ? across : nil
                    }
                }
            }
            // Past the platforms, and past any track just beyond them
            // (a through track with no platform of its own).
            func clear(_ side: Float, at anchor: Map3DPoint) -> Float {
                var edge = reach(side)
                for _ in 0..<6 {
                    guard let next = farthest(side, from: edge - 0.1, to: edge + 5, at: anchor).max() else { break }
                    edge = next + 2.5
                }
                return edge + 1
            }
            // Each side, at the middle or slid along the platform (where
            // another line crosses at the middle): the least other track
            // where it would stand, then opening onto a platform, then
            // the least slid, then the left.
            let half = platforms.compactMap { Map3DStreetLife.Path($0.line)?.length }.max().map { $0 / 2 } ?? 0
            let slides = [Float(0), 1, -1, 2, -2].map { $0 * (wide / 2 + 4) }.filter { abs($0) <= max(half, 1) }
            let choices = slides.flatMap { slide in
                [Float(-1), 1].map { side in
                    let anchor = middle.point + middle.along * slide, edge = clear(side, at: anchor)
                    return (side: side, slide: slide, edge: edge, blocked: farthest(side, from: edge, to: edge + depth, at: anchor).count,
                            shut: opensOnto(side) ? 0 : 1)
                }
            }
            let best = choices.min { ($0.blocked, $0.shut, abs($0.slide), $0.side) < ($1.blocked, $1.shut, abs($1.slide), $1.side) }!
            forward = middle.right * best.side
            back = middle.point + middle.along * best.slide + forward * best.edge
        }
        // The building's back on `back`, its middle across it there.
        let shift = Map3DPoint(-bounds.min.x, 0, -(bounds.min.z + bounds.max.z) / 2)
        var moved = Map3DMesh()
        moved.append(kit.mesh, at: shift, forward: Map3DPoint(1, 0, 0))
        let foot = Map3DPoint(back.x, drawnGround(x: back.x, z: back.z), back.z)
        let centre = foot + forward * (depth / 2)
        target = .near
        mesh(at: centre) { $0.append(moved, at: foot, forward: forward) }
        addShadow(centre: centre, forward: forward, length: depth, width: wide, spread: 3, darkness: 0.3)
        target = .far
        let colours = Map3DStationKit.farColours(station.profile)
        mesh(at: centre) { mesh in
            mesh.addBox(base: centre, forward: forward, length: depth, width: wide, height: max(bounds.max.y * 0.8, 1),
                        top: colours.roof, side: colours.wall)
        }
        // The cells under its footprint.
        let right = forward.cross(.up)
        let corners = [(-0.5, -0.5), (0.5, -0.5), (0.5, 0.5), (-0.5, 0.5)].map { centre + forward * (Float($0.0) * depth) + right * (Float($0.1) * wide) }
        let cell = Double(Land.cellLength)
        func index(_ value: Float, _ origin: Double) -> Int { Int(((origin + Double(value) * Self.metre) / cell).rounded(.down)) }
        let columns = corners.map { index($0.x, originX) }, rows = corners.map { index($0.z, originY) }
        var cells = Set<Map3DScene.ChunkKey>()
        for row in rows.min()!...rows.max()! { for column in columns.min()!...columns.max()! { cells.insert(Map3DScene.ChunkKey(column: column, row: row)) } }
        houseFootprints.append(corners)
        // Decision 322: the shop street on the plaza they leave.
        shopStreets.append((station, centre, forward, depth, wide, cells))
        // Decision 331: a big station's commercial kit, later.
        if Self.isBig(station) { bigStations.append((centre, forward, depth)) }
        return cells
    }

    /// An underground station's exits at street level, a viaduct's stair
    /// entrances beside it, 美麗島's glass entrances, 中央公園's wave
    /// roof; a light-rail stop has its canopies alone.
    private mutating func addEntrances(_ station: Map3DStationKit.Station, platforms: [LaidPlatform], path: Map3DStreetLife.Path,
                                       middle: (point: Map3DPoint, along: Map3DPoint, right: Map3DPoint)) {
        guard station.profile != .lightRail else { return }
        var pieces: [(mesh: Map3DMesh, at: Map3DPoint, forward: Map3DPoint)] = []
        func part(_ part: Map3DStationKit.Part) -> Map3DMesh {
            var kit = StationKitBuilder()
            kit.part(part)
            return kit.mesh
        }
        switch station.profile {
        case .elevated:
            // At the middle, a stair entrance each way beside the viaduct.
            let out = (platforms.map { abs($0.offset) + $0.width / 2 }.max() ?? Self.platformEdge) + 3
            for sign: Float in [-1, 1] {
                pieces.append((part(.stairHead), middle.point + middle.along * (sign * 12) + middle.right * (sign * out), middle.along * sign))
            }
        default:
            // An exit a sixth of the way in from each end, on either side,
            // its stairs going down towards the platforms.
            for (share, sign) in [(Float(1) / 6, Float(-1)), (5 / 6, 1)] {
                let at = path.at(path.length * share)
                pieces.append((part(.undergroundExit), at.point + at.right * (sign * 8), at.along * sign))
            }
            if station.profile == .formosa {
                var kit = StationKitBuilder()
                kit.formosaEntrances()
                pieces.append((kit.mesh, middle.point + middle.right * 16, middle.right))
            } else if station.profile == .centralPark {
                var kit = StationKitBuilder()
                kit.supportedRoof(x: 0, y: 6.8, z: 0, length: 39 + Float(station.seed % 7) * 2, width: 26, rise: 2.2, wave: true,
                                  color: Map3DPalette.gymGreen, base: 0)
                pieces.append((kit.mesh, middle.point, middle.along))
            }
        }
        for piece in pieces {
            let foot = Map3DPoint(piece.at.x, drawnGround(x: piece.at.x, z: piece.at.z), piece.at.z)
            target = .near
            mesh(at: foot) { $0.append(piece.mesh, at: foot, forward: piece.forward) }
        }
    }
}
