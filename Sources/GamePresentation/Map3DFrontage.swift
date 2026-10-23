import Foundation
import GameCore

// Decision 385: on a real-world map, the city's low homes and shops along
// its real streets, not two rows across each 64 m cell. Each house fronts
// the road nearest it, set back from its pavement by a little or not at
// all, its width, depth and kind (a 透天厝 or a block of flats) from a hash
// of where the road lies, so the same street is the same every time; a cell
// no road comes near keeps no house. And none on the land OpenStreetMap
// has for airports, military land, cemeteries, golf courses, railway land
// and ports (``RealNoBuildLand``), where the airports' own terminals and
// hangars stand instead.

extension Map3DScene.Builder {
    /// Decision 385: the no-build land round the scene, in scene metres, by
    /// the 64 m cells its outlines' boxes cover.
    struct NoBuild {
        var rings: [[(x: Float, z: Float)]] = []
        var byCell: [Map3DScene.ChunkKey: [Int]] = [:]

        var isEmpty: Bool { rings.isEmpty }

        /// Whether `point`, in 64 m cell `cell`, is on the land.
        func contains(_ point: Map3DPoint, cell: Map3DScene.ChunkKey) -> Bool {
            guard let indices = byCell[cell] else { return false }
            return indices.contains { Self.inside(point.x, point.z, rings[$0]) }
        }

        /// Even-odd.
        static func inside(_ x: Float, _ z: Float, _ ring: [(x: Float, z: Float)]) -> Bool {
            var inside = false
            var j = ring.count - 1
            for i in ring.indices {
                let a = ring[i], b = ring[j]
                if (a.z > z) != (b.z > z), x < (b.x - a.x) * (z - a.z) / (b.z - a.z) + a.x { inside.toggle() }
                j = i
            }
            return inside
        }
    }

    /// Decision 385: a house laid along a street: its middle on the ground,
    /// the way it faces (to the street), the way along the street, its
    /// width along and depth from the front.
    struct StreetHouse {
        let middle: Map3DPoint
        let front: Map3DPoint
        let along: Map3DPoint
        let width: Float
        let depth: Float

        /// Whether it and `other` overlap, by more than a hand's breadth
        /// (two houses of a row share a wall).
        func overlaps(_ other: StreetHouse) -> Bool {
            let shrink: Float = 0.1
            let d = other.middle - middle
            for axis in [along, front, other.along, other.front] {
                let mine = abs(along.dot(axis)) * (width / 2 - shrink) + abs(front.dot(axis)) * (depth / 2 - shrink)
                let theirs = abs(other.along.dot(axis)) * (other.width / 2 - shrink) + abs(other.front.dot(axis)) * (other.depth / 2 - shrink)
                if abs(d.dot(axis)) >= mine + theirs { return false }
            }
            return true
        }

        var corners: [Map3DPoint] {
            let u = along * (width / 2), v = front * (depth / 2)
            return [middle + u + v, middle - u + v, middle - u - v, middle + u - v]
        }

        /// How far the segment `a`–`b` passes from the house's footprint,
        /// metres (0 where it crosses it).
        func distance(from a: Map3DPoint, to b: Map3DPoint) -> Float {
            let hu = width / 2, hv = depth / 2
            func local(_ p: Map3DPoint) -> (u: Float, v: Float) {
                let d = p - middle
                return (d.dot(along), d.dot(front))
            }
            let p = local(a), q = local(b)
            // Does the segment cross the box (Liang–Barsky)?
            var low: Float = 0, high: Float = 1
            let du = q.u - p.u, dv = q.v - p.v
            var crosses = true
            for (step, gap) in [(-du, p.u + hu), (du, hu - p.u), (-dv, p.v + hv), (dv, hv - p.v)] {
                if step == 0 {
                    if gap < 0 { crosses = false; break }
                } else {
                    let t = gap / step
                    if step < 0 { low = max(low, t) } else { high = min(high, t) }
                    if low > high { crosses = false; break }
                }
            }
            if crosses { return 0 }
            func toBox(_ p: (u: Float, v: Float)) -> Float {
                let ou = max(abs(p.u) - hu, 0), ov = max(abs(p.v) - hv, 0)
                return (ou * ou + ov * ov).squareRoot()
            }
            func toSegment(_ c: (u: Float, v: Float)) -> Float {
                let length2 = du * du + dv * dv
                let t = length2 > 0 ? min(max(((c.u - p.u) * du + (c.v - p.v) * dv) / length2, 0), 1) : 0
                let ou = c.u - p.u - du * t, ov = c.v - p.v - dv * t
                return (ou * ou + ov * ov).squareRoot()
            }
            return [toBox(p), toBox(q), toSegment((hu, hv)), toSegment((-hu, hv)), toSegment((-hu, -hv)), toSegment((hu, -hv))].min() ?? 0
        }
    }

    /// Decision 385: a cell's houses as laid (``addFrontage``): each with
    /// its kind and the hash its look comes from; the span of them along
    /// each road's side, for their shadow, and the runs of shops side by
    /// side, for their shoppers.
    struct LaidFrontage {
        var houses: [(house: StreetHouse, flats: Bool, shops: Bool, seed: (Int32, Int32), salt: Int32, wall: UInt32)] = []
        var spans: [(from: Map3DPoint, to: Map3DPoint, front: Map3DPoint, depth: Float)] = []
        var runs: [(from: Map3DPoint, to: Map3DPoint, front: Map3DPoint)] = []
    }

    /// Decision 385: the real roads in pieces, and which come near each
    /// 64 m cell, for laying houses along them; the houses laid so far, by
    /// the cell of their middle, and each cell's as laid, which the
    /// simplified city's pass draws again.
    struct Frontage {
        var pieces: [(a: Map3DPoint, b: Map3DPoint, half: Float, kind: Map3DBaseMap.RoadKind?, fronted: Bool)] = []
        var byCell: [Map3DScene.ChunkKey: [Int]] = [:]
        var houses: [Map3DScene.ChunkKey: [StreetHouse]] = [:]
        var laid: [Map3DScene.ChunkKey: LaidFrontage] = [:]
    }

    /// How far beyond a road's pavement a house it fronts may reach,
    /// metres: the deepest setback and the deepest house.
    static let frontageReach: Float = 22

    /// Decision 385: the no-build land of `land` round the scene, laid on
    /// the world by `frame`.
    mutating func prepareNoBuild(_ land: RealNoBuildLand, frame: RealWorldFrame) {
        let low = frame.coordinate(worldX: region.minX, worldY: region.maxY), high = frame.coordinate(worldX: region.maxX, worldY: region.minY)
        let margin = 0.01
        var noBuild = NoBuild()
        for area in land.areas {
            guard area.ring.contains(where: { $0.latitude >= low.latitude - margin && $0.latitude <= high.latitude + margin }),
                  area.ring.contains(where: { $0.longitude >= low.longitude - margin && $0.longitude <= high.longitude + margin }),
                  !(area.ring.allSatisfy { $0.latitude < low.latitude - margin } || area.ring.allSatisfy { $0.latitude > high.latitude + margin }
                    || area.ring.allSatisfy { $0.longitude < low.longitude - margin } || area.ring.allSatisfy { $0.longitude > high.longitude + margin })
            else { continue }
            let ring = area.ring.map { place -> (x: Float, z: Float) in
                let at = frame.worldPosition(latitude: place.latitude, longitude: place.longitude)
                let scene = point(x: at.x, y: at.y, height: 0)
                return (scene.x, scene.z)
            }
            let index = noBuild.rings.count
            noBuild.rings.append(ring)
            let west = gridCell(Double(ring.map(\.x).min() ?? 0), origin: originX), east = gridCell(Double(ring.map(\.x).max() ?? 0), origin: originX)
            let north = gridCell(Double(ring.map(\.z).min() ?? 0), origin: originY), south = gridCell(Double(ring.map(\.z).max() ?? 0), origin: originY)
            let cell = Double(Land.cellLength)
            let columns = (max(west, Int((region.minX / cell).rounded(.down))), min(east, Int((region.maxX / cell).rounded(.down))))
            let rows = (max(north, Int((region.minY / cell).rounded(.down))), min(south, Int((region.maxY / cell).rounded(.down))))
            guard columns.0 <= columns.1, rows.0 <= rows.1 else { continue }
            for row in rows.0...rows.1 {
                for column in columns.0...columns.1 {
                    noBuild.byCell[Map3DScene.ChunkKey(column: column, row: row), default: []].append(index)
                }
            }
        }
        self.noBuild = noBuild
    }

    /// Decision 385: whether scene point `point` is on no-build land.
    func onNoBuildLand(_ point: Map3DPoint) -> Bool {
        !noBuild.isEmpty && noBuild.contains(point, cell: chunk(of: point))
    }

    /// Decision 385: the terminals, hangars and other buildings of `land`'s
    /// airports in the scene, laid on the world by `frame`.
    mutating func addAirportBuildings(_ land: RealNoBuildLand, frame: RealWorldFrame, clearOf cleared: Set<Map3DScene.ChunkKey>) {
        guard !noBuild.isEmpty else { return }
        for building in land.buildings {
            let places = building.ring.map { frame.worldPosition(latitude: $0.latitude, longitude: $0.longitude) }
            let middle = (x: places.reduce(0) { $0 + $1.x } / Double(places.count), y: places.reduce(0) { $0 + $1.y } / Double(places.count))
            guard contains(x: middle.x, y: middle.y) else { continue }
            let ring = places.map { point(x: $0.x, y: $0.y, height: 0) }
            guard cleared.isDisjoint(with: ring.map { chunk(of: $0) }) else { continue }
            let kind: RealKind
            switch building.use {
            case .hangar: kind = .industry
            case .terminal: kind = .transport
            case .other: kind = building.height >= 12 ? .civic : .industry
            }
            addRealBuilding([[ring]], ground: ground(x: middle.x, y: middle.y), height: building.height,
                            storeys: max(1, Int(building.height / 4)), kind: kind)
        }
    }

    /// Decision 385: whether a house fronts a road of `kind`: not a
    /// motorway, nor a service road (a drive, a car park's aisle).
    static func isFronted(_ kind: Map3DBaseMap.RoadKind) -> Bool {
        kind != .motorway && kind != .service
    }

    /// Decision 385: the share of a road's frontage left open (a yard, a
    /// car park, a vacant lot) on a lot of `density`: the low homes'
    /// streets more open than the town's.
    static func openShare(density: Int) -> Float {
        switch density {
        case ...0: 0.45
        case 1: 0.38
        default: 0.33
        }
    }

    /// Decision 385: the real roads' pieces (``roadLines``), and which come
    /// within ``frontageReach`` of each 64 m cell; a house fronts any but
    /// those ``isFronted(_:)`` rules out and link roads.
    mutating func prepareFrontage() {
        var frontage = Frontage()
        for (number, line) in roadLines.enumerated() {
            let kind = number < roadKinds.count ? roadKinds[number] : nil
            for (a, b) in zip(line.points, line.points.dropFirst()) {
                let index = frontage.pieces.count
                frontage.pieces.append((a, b, line.half, kind?.kind, kind.map { Self.isFronted($0.kind) && !$0.ramp } ?? false))
                let reach = Double(line.half + Self.frontageReach)
                let west = gridCell(Double(min(a.x, b.x)) - reach, origin: originX), east = gridCell(Double(max(a.x, b.x)) + reach, origin: originX)
                let north = gridCell(Double(min(a.z, b.z)) - reach, origin: originY), south = gridCell(Double(max(a.z, b.z)) + reach, origin: originY)
                for row in north...south {
                    for column in west...east {
                        frontage.byCell[Map3DScene.ChunkKey(column: column, row: row), default: []].append(index)
                    }
                }
            }
        }
        self.frontage = frontage
    }

    /// Decision 385: the houses of the low homes or shops (`density` 0–2,
    /// shops on every house with `lotShops`) on cell (`column`, `row`):
    /// those of the houses laid along the roads near it whose middle falls
    /// in it, on no cell of `blocked`, no road, no no-build land and no
    /// house laid before.
    mutating func addFrontage(column: Int, row: Int, density: Int, shops lotShops: Bool, blocked: Set<Map3DScene.ChunkKey>) {
        let key = Map3DScene.ChunkKey(column: column, row: row)
        let laid: LaidFrontage
        if let done = frontage.laid[key] {
            laid = done
        } else {
            laid = layFrontage(key, density: density, shops: lotShops, blocked: blocked)
            frontage.laid[key] = laid
        }
        drawFrontage(laid, column: column, row: row, density: density)
    }

    /// Decision 385: lays the houses of cell `key` (``addFrontage``).
    mutating func layFrontage(_ key: Map3DScene.ChunkKey, density: Int, shops lotShops: Bool, blocked: Set<Map3DScene.ChunkKey>) -> LaidFrontage {
        var laid = LaidFrontage()
        guard let near = frontage.byCell[key] else { return laid }
        for index in near {
            let piece = frontage.pieces[index]
            guard piece.fronted, let along = (piece.b - piece.a).normalized else { continue }
            let length = (piece.b - piece.a).length
            guard length >= 4 else { continue }
            // Seeded from where the road lies on the map, not in the
            // scene, whose origin moves as track is laid.
            let east = originX / Self.metre + Double(piece.a.x), south = originY / Self.metre + Double(piece.a.z)
            let seed = (Int32(truncatingIfNeeded: Int((east * 2).rounded())), Int32(truncatingIfNeeded: Int((south * 2).rounded())))
            let busy = (piece.kind?.rawValue ?? 0) >= Map3DBaseMap.RoadKind.secondary.rawValue
            let shopShare: Float = switch piece.kind {
            case .primary, .secondary, .trunk: 0.7
            case .tertiary: 0.4
            default: 0
            }
            let flatShare: Float = density >= 2 ? 0.55 : density == 1 ? (busy ? 0.25 : 0.08) : 0
            for side: Float in [-1, 1] {
                let out = Map3DPoint(-along.z, 0, along.x) * side
                let sideSalt: Int32 = side > 0 ? 0 : 50_000
                var t = map3DRandom(seed.0, seed.1, salt: sideSalt + 1) * 3
                var number: Int32 = 0
                var run: (from: Map3DPoint, to: Map3DPoint)?
                var span: (from: Map3DPoint, to: Map3DPoint, depth: Float)?
                func endRun() {
                    if let open = run { laid.runs.append((open.from, open.to, -out)) }
                    run = nil
                }
                while t < length - 3.2 {
                    let salt = sideSalt + 10 + number * 23
                    number += 1
                    let r = { (extra: Int32) in map3DRandom(seed.0, seed.1, salt: salt + extra) }
                    // A gap now and then: an alley, a yard, a vacant lot.
                    if r(14) < Self.openShare(density: density) {
                        t += 3 + r(15) * 7
                        endRun()
                        continue
                    }
                    let flats = r(16) < flatShare
                    let width = min(flats ? 8 + r(1) * 6 : 4.4 + r(1) * 2.2, length - t)
                    let depth: Float = flats ? 12 + r(17) * 6 : 9 + r(17) * 6
                    // On a busy road the fronts meet the pavement (arcades);
                    // on a lane, many stand back behind a yard or a car.
                    let setback = piece.half + 0.3 + (busy || r(18) < 0.45 ? 0 : 0.5 + r(19) * 3)
                    let start = t
                    t += width
                    let house = StreetHouse(middle: piece.a + along * (start + width / 2) + out * (setback + depth / 2),
                                            front: -out, along: along, width: width - 0.1, depth: depth)
                    guard chunk(of: house.middle) == key else {
                        endRun()
                        continue
                    }
                    guard fits(house, near: near, blocked: blocked) else {
                        endRun()
                        continue
                    }
                    frontage.houses[key, default: []].append(house)
                    let shops = lotShops || r(13) < shopShare
                    let wall = Self.pickWall((seed.0 &+ salt, seed.1))
                    laid.houses.append((house, flats, shops, seed, salt, wall))
                    let from = piece.a + along * start + out * (piece.half + 0.3), to = piece.a + along * t + out * (piece.half + 0.3)
                    span = (span?.from ?? from, to, max(span?.depth ?? 0, setback - piece.half - 0.3 + depth))
                    if !shops {
                        endRun()
                    } else if let open = run, (open.to - from).length < 0.5 {
                        run = (open.from, to)
                    } else {
                        endRun()
                        run = (from, to)
                    }
                }
                endRun()
                if let span { laid.spans.append((span.from, span.to, -out, span.depth)) }
            }
        }
        return laid
    }

    /// Decision 385: draws the houses `laid` on cell (`column`, `row`).
    mutating func drawFrontage(_ laid: LaidFrontage, column: Int, row: Int, density: Int) {
        guard !laid.houses.isEmpty else { return }
        let cell = Double(Land.cellLength)
        let centre = point(x: (Double(column) + 0.5) * cell, y: (Double(row) + 0.5) * cell, height: 0)
        var closeDetail = Map3DMesh()
        var blades: [Map3DSign] = []
        let far = isFar
        var grounded: [StreetHouse] = []
        for house in laid.houses.map(\.house) {
            grounded.append(StreetHouse(middle: Map3DPoint(house.middle.x, ground(at: house.middle), house.middle.z), front: house.front,
                                        along: house.along, width: house.width, depth: house.depth))
        }
        mesh(at: centre) { mesh in
            for (house, lot) in zip(grounded, laid.houses) {
                let r = { (extra: Int32) in map3DRandom(lot.seed.0, lot.seed.1, salt: lot.salt + extra) }
                if far {
                    Self.addFarTownHouse(&mesh, middle: house.middle, front: house.front, width: house.width, depth: house.depth,
                                         flats: lot.flats, wall: lot.wall, r: r)
                } else {
                    Self.addTownHouse(&mesh, close: &closeDetail, blades: &blades, middle: house.middle, front: house.front, width: house.width,
                                      depth: house.depth, flats: lot.flats, shops: lot.shops, wall: lot.wall, far: false, r: r)
                }
            }
        }
        for blade in blades { addSign(blade) }
        if !closeDetail.isEmpty {
            let saved = target
            target = .close
            mesh(at: centre) { $0.append(closeDetail) }
            target = saved
        }
        // Decision 232: a shadow along each road's side of houses (gaps
        // and all, as a row's did); decision 259: shoppers along each run
        // of shops.
        for span in laid.spans {
            let along = span.to - span.from
            guard let direction = along.normalized else { continue }
            let middle = span.from + along * 0.5 - span.front * (span.depth / 2)
            addShadow(centre: Map3DPoint(middle.x, ground(at: middle), middle.z), forward: direction, length: along.length, width: span.depth + 0.5,
                      spread: 3, darkness: 0.3)
        }
        for run in laid.runs {
            let out = run.front * 1.2 + Map3DPoint(0, 0.05, 0)
            addShopLife(from: run.from + out + Map3DPoint(0, ground(at: run.from), 0), to: run.to + out + Map3DPoint(0, ground(at: run.to), 0),
                        density: density)
        }
    }

    /// Decision 385: whether `house` stands in the scene, on no cell of
    /// `blocked`, clear of the roads (pieces `near`) and their pavements,
    /// off the no-build land and clear of the houses laid before.
    func fits(_ house: StreetHouse, near: [Int], blocked: Set<Map3DScene.ChunkKey>) -> Bool {
        let corners = house.corners
        for spot in corners + [house.middle] {
            guard contains(x: originX + Double(spot.x) * Self.metre, y: originY + Double(spot.z) * Self.metre),
                  !blocked.contains(chunk(of: spot)), !onNoBuildLand(spot) else { return false }
        }
        let radius = (house.width * house.width + house.depth * house.depth).squareRoot() / 2
        for index in near {
            let piece = frontage.pieces[index]
            // Far enough from the piece's line that no corner can reach it.
            let d = piece.b - piece.a, p = house.middle - piece.a
            let length2 = d.x * d.x + d.z * d.z
            let t = length2 > 0 ? min(max((p.x * d.x + p.z * d.z) / length2, 0), 1) : 0
            let ox = p.x - d.x * t, oz = p.z - d.z * t, clear = piece.half + 0.2 + radius
            if ox * ox + oz * oz >= clear * clear { continue }
            if house.distance(from: piece.a, to: piece.b) < piece.half + 0.2 { return false }
        }
        let cell = chunk(of: house.middle)
        for row in cell.row - 1...cell.row + 1 {
            for column in cell.column - 1...cell.column + 1 {
                if frontage.houses[Map3DScene.ChunkKey(column: column, row: row)]?.contains(where: { $0.overlaps(house) }) == true { return false }
            }
        }
        return true
    }
}

extension Map3DScene.Builder {
    /// Decision 385: a house of ``addTownHouse`` as seen from afar
    /// (decision 238): one box of its height, its front and back painted
    /// with its windows, no roof clutter.
    static func addFarTownHouse(_ mesh: inout Map3DMesh, middle: Map3DPoint, front: Map3DPoint, width: Float, depth: Float, flats: Bool,
                                wall: UInt32, r: (Int32) -> Float) {
        let floors: Float = flats ? Float(3 + Int(r(2) * 4)) : (r(2) < 0.375 ? 2 : r(2) < 0.875 ? 3 : 4)
        let groundFloor: Float = flats ? 3.5 + r(3) * 0.6 : 3.8 + r(3) * 0.5
        let upper: Float = flats ? 3.0 + r(4) * 0.25 : 3.4 + r(4) * 0.3
        let windows = flats ? Map3DPaint.bays(Self.pick(Map3DSurface.flats, r(10)), bay: 3.2, floors: Int(floors))
            : Map3DPaint.bays(r(8) >= 0.55 ? .homeBalcony : .homeWindows, bay: 6, floors: Int(floors))
        mesh.addBox(base: middle, forward: front, length: depth, width: width - 0.1, height: groundFloor + upper * (floors - 1) + 0.7,
                    top: Map3DPalette.roof, side: wall, topPaint: Self.roofing, frontPaint: windows.on(Self.homeMaterial(r(12))),
                    flankPaint: Self.plaster)
    }

    /// One house of a row (decision 263 on, `addRowHouses`; decision 385:
    /// `addFrontage`): a 透天厝, or a block of flats with `flats`, `width`
    /// wide and `depth` deep, its middle on the ground at `middle`, facing
    /// `front`, a shop below with `shops`; its look from `r`.
    static func addTownHouse(_ mesh: inout Map3DMesh, close closeDetail: inout Map3DMesh, blades: inout [Map3DSign], middle: Map3DPoint,
                             front: Map3DPoint, width: Float, depth: Float, flats: Bool, shops: Bool, wall: UInt32, far: Bool,
                             r: (Int32) -> Float) {
        let floors: Float = flats ? Float(3 + Int(r(2) * 4)) : (r(2) < 0.375 ? 2 : r(2) < 0.875 ? 3 : 4)
        let groundFloor: Float = flats ? 3.5 + r(3) * 0.6 : 3.8 + r(3) * 0.5
        let upper: Float = flats ? 3.0 + r(4) * 0.25 : 3.4 + r(4) * 0.3
        let height = groundFloor + upper * (floors - 1)
        let arcade = shops && r(5) < 0.8
        // Decision 231: the ground floor a shop or a
        // rolling shutter, the floors above windows (a
        // grille or a balcony on a 透天厝), the flanks
        // blank as row houses' walls are.
        let shop = Self.pick(Map3DSurface.shops, r(9))
        let groundPaint = Map3DPaint.bays(shops ? shop : .shutter, bay: 5.4, floors: 1)
        let balconies = !flats && r(8) >= 0.55
        // Decision 242: the house faced with tiles, grit or
        // paint, the floors above and the flanks alike.
        let facing = Self.homeMaterial(r(12))
        let upperPaint = (flats ? Map3DPaint.bays(Self.pick(Map3DSurface.flats, r(10)), bay: 3.2, floors: Int(floors) - 1)
            : Map3DPaint.bays(balconies ? .homeBalcony : .homeWindows, bay: 6, floors: Int(floors) - 1)).on(facing)
        if arcade {
            // The ground floor set back 3.4 m, dark; the
            // floors above over the arcade.
            mesh.addBox(base: middle - front * 1.7, forward: front, length: depth - 3.4, width: width - 0.1,
                        height: groundFloor, top: Map3DPalette.arcade, side: Map3DPalette.arcade,
                        frontPaint: groundPaint, flankPaint: Self.plaster, capped: false)
        } else {
            mesh.addBox(base: middle, forward: front, length: depth, width: width - 0.1, height: groundFloor,
                        top: Map3DPalette.roof, side: wall, frontPaint: groundPaint, flankPaint: Self.plaster, capped: false)
        }
        mesh.addBox(base: middle + Map3DPoint(0, groundFloor, 0), forward: front, length: depth, width: width - 0.1,
                    height: height - groundFloor, top: Map3DPalette.roof, side: wall,
                    topPaint: Self.roofing, frontPaint: upperPaint, flankPaint: Self.plaster.on(facing))
        // Decision 238: near, what stands out of the front
        // and the parapet's rim; afar, only the roof's tank
        // or room, which read from far off.
        if !far {
            blades += Self.addFrontDetail(&mesh, close: &closeDetail, front: middle + front * (depth / 2), facing: front, width: width,
                                groundFloor: groundFloor, upper: upper, floors: Int(floors), wall: wall,
                                balconies: balconies, sign: shops, arcade: arcade, r: r)
            mesh.addBox(base: middle + Map3DPoint(0, height, 0), forward: front, length: depth, width: width - 0.1,
                        height: 0.7, top: Map3DPalette.roof, side: Map3DColor.shaded(wall, 0.95),
                        topPaint: Self.roofing, frontPaint: Self.plaster, flankPaint: Self.plaster)
        }
        if r(6) < 0.75 {
            // Decision 267: on three in four roofs, a round water
            // tank (r 0.62 m, 1.1 m tall; HANDOFF §4.3) on its
            // stand, blue or stainless; afar one box in the
            // tank's colour, as few triangles as before.
            let tank = r(7) < 0.5 ? Map3DPalette.tankBlue : Map3DPalette.tankSteel
            let foot = middle + Map3DPoint(0, height + 0.7, 0) - front * (depth / 4)
            if far {
                mesh.addBox(base: foot, forward: front, length: 1.2, width: 1.2, height: 1.8, top: tank, side: tank)
            } else {
                mesh.addBox(base: foot, forward: front, length: 1.2, width: 1.2, height: 0.7, top: Map3DPalette.tankStand,
                            side: Map3DPalette.tankStand)
                mesh.addCylinder(base: foot + Map3DPoint(0, 0.7, 0), radius: 0.62, height: 1.1, sides: 8, top: tank, side: tank)
            }
        } else if r(6) < 0.92, width > 4 {
            // Decision 235: a sheet-steel room on the roof
            // (頂樓加蓋) over the back half, under a low gable
            // (the japan pack's shutter garage and shed
            // roofs: 2.4 m walls, a 20° pitch).
            let shack = middle + Map3DPoint(0, height + 0.7, 0) - front * (depth / 4)
            let roof = Self.pick(Map3DPalette.tinRoofs, r(11))
            mesh.addBox(base: shack, forward: front, length: depth / 2 - 0.4, width: width - 0.8, height: 2.4,
                        top: roof, side: Map3DColor.shaded(Map3DPalette.shedWalls[0], 0.95), frontPaint: Self.metal,
                        flankPaint: Self.metal, capped: false)
            mesh.addGableRoof(base: shack + Map3DPoint(0, 2.4, 0), forward: front, length: depth / 2 - 0.4, width: width - 0.8,
                              rise: (width - 0.8) / 2 * 0.36, overhang: 0.3, color: roof, gable: Map3DPalette.shedWalls[0],
                              paint: Self.metal)
        }
    }
}
