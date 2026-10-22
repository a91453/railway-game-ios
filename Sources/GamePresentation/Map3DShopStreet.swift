import Foundation
import GameCore

// ARCHITECTURE decision 322: the station-front shop street. On the plaza
// a station's building leaves (decision 321's cells), a row of shops each
// side of the building facing the way it does, and a row across its
// forecourt facing it: #900's shop bodies (`commercialBlock`), the
// town-scene reference's striped awning (`main.js` `addAwning`), one main
// colour each, a colour-block sign lit at night, goods out front from the
// detail kit (#921), and on the nearest a rooftop sign and warm downlights
// under its awning (`decorateHotel`). Only on the plaza, clear of track
// and roads, so no city lot moves; close up only, a box each far off.

extension Map3DPalette {
    /// Decision 322: each station-front shop's main colour, the signs'
    /// four and three more of the game's.
    static let shopColours: [UInt32] = signs + [shopAwnings[0], counters[1], Map3DColor.rgb(0x9A3E52)]
    /// The awnings' second stripe (`main.js` `addAwning`, `0xf1ebe0`).
    static let awningCream = Map3DColor.rgb(0xF1EBE0)
}

extension Map3DScene.Builder {
    /// Decision 322: a shop's frontage and the pitch of a row of them (the
    /// slabs touching), metres.
    static let shopFrontage: Float = 7.5
    static let shopPitch: Float = shopFrontage + 0.6
    /// How far from a station's building its shops may stand, metres.
    static let shopReach: Float = 150
    /// Close up, the most triangles a station's shops may have.
    static let shopTriangles = 4_000

    /// How many shops a station of `station`'s type has at most: a halt
    /// four, a regional station more the bigger its class.
    static func shopCount(_ station: Map3DStationKit.Station) -> Int {
        switch station.profile {
        case .halt: 4
        default: 12 - 2 * min(max(station.tier, 0), 3)
        }
    }

    /// One shop's place: the middle of its front on the ground, the way it
    /// faces, how far it is from the station's front.
    struct ShopSlot {
        let front: Map3DPoint
        let facing: Map3DPoint
        let distance: Float
        let order: Int
        /// Its place in its row, counting from the station's side.
        let lane: Int
    }

    /// The places a station's shops may stand, nearest first: beside the
    /// building `wide` across and `depth` deep on `centre` facing
    /// `forward`, their fronts 4 m behind its forecourt's edge; and across
    /// its forecourt, 14 m past it, facing it.
    static func shopSlots(centre: Map3DPoint, forward: Map3DPoint, depth: Float, wide: Float) -> [ShopSlot] {
        let right = forward.cross(.up), entrance = centre + forward * (depth / 2)
        var slots: [ShopSlot] = []
        func add(_ front: Map3DPoint, _ facing: Map3DPoint, _ lane: Int) {
            let distance = Map3DPoint(front.x - entrance.x, 0, front.z - entrance.z).length
            guard distance <= shopReach else { return }
            slots.append(ShopSlot(front: front, facing: facing, distance: distance, order: slots.count, lane: lane))
        }
        let beside = centre + forward * (depth / 2 - 4), across = centre + forward * (depth / 2 + 14)
        for index in 0..<Int(shopReach / shopPitch) {
            for side: Float in [1, -1] {
                add(beside + right * (side * (wide / 2 + 2 + shopPitch * (Float(index) + 0.5))), forward, Int(side) * (index + 1))
                if index > 0 || side > 0 { add(across + right * (side * shopPitch * Float(index)), forward * -1, Int(side) * index) }
            }
        }
        return slots.sorted { ($0.distance, $0.order) < ($1.distance, $1.order) }
    }

    /// Decision 322: `station`'s shops on `cells`, the plaza its building
    /// on `centre` (`depth` along `forward`, `wide` across) leaves.
    mutating func addShopStreet(_ station: Map3DStationKit.Station, centre: Map3DPoint, forward: Map3DPoint, depth: Float, wide: Float,
                                cells: Set<Map3DScene.ChunkKey>) {
        guard !station.isLandmark else { return }
        let seed = Int32(truncatingIfNeeded: Int64(station.seed) & 0x7FFF_FFFF)
        var placed = 0, triangles = 0
        for slot in Self.shopSlots(centre: centre, forward: forward, depth: depth, wide: wide) {
            guard placed < Self.shopCount(station), triangles < Self.shopTriangles else { break }
            let tall = placed == 0
            let shop = Self.shop(seed: seed, index: Int32(slot.order), lane: slot.lane, tall: tall)
            let footprint = Self.shopFootprint(slot, depth: shop.depth)
            guard footprint.allSatisfy({ cells.contains(chunk(of: $0)) }), isClear(footprint, facing: slot.facing) else { continue }
            let foot = Map3DPoint(slot.front.x, footprint.map { drawnGround(x: $0.x, z: $0.z) }.min() ?? 0, slot.front.z)
            let middle = foot - slot.facing * (shop.depth / 2)
            target = .near
            mesh(at: middle) { $0.append(shop.mesh, at: middle, forward: slot.facing) }
            // Decision 352: what its board says.
            for sign in shop.signs { addSign(sign.placed(at: middle, forward: slot.facing)) }
            addShadow(centre: middle, forward: slot.facing, length: shop.depth, width: Self.shopFrontage, spread: 2, darkness: 0.3)
            let side = slot.facing.cross(.up), walk = foot + slot.facing * 2.4 + Map3DPoint(0, 0.05, 0)
            addShopLife(from: walk - side * (Self.shopFrontage / 2), to: walk + side * (Self.shopFrontage / 2), density: 2)
            target = .far
            mesh(at: middle) { mesh in
                mesh.addBox(base: middle, forward: slot.facing, length: shop.depth, width: Self.shopFrontage, height: shop.height,
                            top: shop.roof, side: shop.wall)
            }
            placed += 1
            triangles += shop.mesh.indices.count / 3
        }
    }

    /// The 64 m cell scene point `p` lies on.
    func chunk(of p: Map3DPoint) -> Map3DScene.ChunkKey {
        let cell = Double(Land.cellLength)
        return Map3DScene.ChunkKey(column: Int(((originX + Double(p.x) * Self.metre) / cell).rounded(.down)),
                                   row: Int(((originY + Double(p.z) * Self.metre) / cell).rounded(.down)))
    }

    /// The corners of the ground a shop `depth` deep in `slot` takes, its
    /// slab and its awning.
    static func shopFootprint(_ slot: ShopSlot, depth: Float) -> [Map3DPoint] {
        let side = slot.facing.cross(.up), half = shopFrontage / 2 + 0.3
        let back = slot.front - slot.facing * (depth + 0.3), out = slot.front + slot.facing * 1.9
        return [back - side * half, back + side * half, out + side * half, out - side * half]
    }

    /// Whether no track or platform comes within 4 m of `footprint`, nor
    /// any road or its pavement within a metre.
    func isClear(_ footprint: [Map3DPoint], facing: Map3DPoint) -> Bool {
        let side = facing.cross(.up)
        let middle = footprint.reduce(Map3DPoint(0, 0, 0)) { $0 + $1 } * 0.25
        let length = abs((footprint[2] - footprint[1]).dot(facing)) / 2, width = abs((footprint[1] - footprint[0]).dot(side)) / 2
        func near(_ p: Map3DPoint, _ margin: Float) -> Bool {
            let d = p - middle
            return abs(d.dot(facing)) < length + margin && abs(d.dot(side)) < width + margin
        }
        let reach = length + width
        if trackLines.contains(where: { $0.points.contains { near($0, 4) } }) { return false }
        if laidPlatforms.contains(where: { platform in platform.line.contains { near($0, abs(platform.offset) + platform.width / 2 + 1) } }) {
            return false
        }
        for road in roadLines {
            for (a, b) in zip(road.points, road.points.dropFirst()) {
                let span = Map3DPoint(b.x - a.x, 0, b.z - a.z), steps = max(1, Int((span.length / 2).rounded(.up)))
                guard (a - middle).length < span.length + reach + road.half + 4 else { continue }
                for step in 0...steps where near(a + span * (Float(step) / Float(steps)), road.half + 1) { return false }
            }
        }
        return true
    }

    /// One shop, built facing +x on its middle: #900's shop body, the
    /// striped awning, the sign, the goods; `tall` the station front's
    /// tallest, with a rooftop sign and downlights.
    struct Shop {
        let mesh: Map3DMesh
        let depth: Float
        let height: Float
        let wall: UInt32
        let roof: UInt32
        /// Decision 352: its board's word (and the tallest's rooftop
        /// sign's), built facing +x as the mesh is.
        let signs: [Map3DSign]
    }

    /// The main colour of the shop in place `lane` of its row: neighbours
    /// never alike, three colours on each time.
    static func shopColour(seed: Int32, lane: Int) -> UInt32 {
        let colours = Map3DPalette.shopColours
        return colours[((Int(seed) % colours.count + lane * 3) % colours.count + colours.count) % colours.count]
    }

    static func shop(seed: Int32, index: Int32, lane: Int, tall: Bool) -> Shop {
        func random(_ salt: Int32) -> Float { map3DRandom(seed, index, salt: salt) }
        // #900's shops of a 7.5 m frontage (`shop`): retail 0 and 2–8,
        // food 0–4 and 7; the tallest its three-storey food shop.
        let food = tall || random(1) < 0.45
        let kinds: [Int] = food ? [0, 1, 2, 3, 4, 7] : [0, 2, 3, 4, 5, 6, 7, 8]
        let v = tall ? 7 : kinds[min(Int(random(2) * Float(kinds.count)), kinds.count - 1)]
        let floors = v == 1 || v == 2 || v == 8 || food && v == 3 ? 2 : food && v == 7 ? 3 : 1
        let length: Float = v == 0 ? 7 : 8.5, width = shopFrontage
        let colour = shopColour(seed: seed, lane: lane)
        var b = SceneKitBuilder()
        b.commercialBlock(x: 0, z: 0, length: length, width: width, floors: floors, variant: v)
        let face = length / 2
        // The awning (`addAwning`): seven stripes, the shop's colour and
        // cream, sloping down 0.42 rad from over the door, and a hanging
        // edge.
        let top = Map3DPoint(face + 0.18, 3.0, 0), slope: Float = 0.42, reach: Float = 1.7
        let edge = top + Map3DPoint(cosf(slope) * reach, -sinf(slope) * reach, 0)
        let cloth = width * 0.82, stripe = cloth / 7
        for i in 0..<7 {
            let a = -cloth / 2 + Float(i) * stripe, c = a + stripe, color = i % 2 == 0 ? colour : Map3DPalette.awningCream
            let panel = [Map3DPoint(top.x, top.y, a), Map3DPoint(top.x, top.y, c), Map3DPoint(edge.x, edge.y, c), Map3DPoint(edge.x, edge.y, a)]
            // Its underside a little below, so the two faces never fight.
            let under = Map3DPoint(0, -0.03, 0), inside = Map3DPoint(-0.03, 0, 0)
            b.mesh.addFacet(panel, color: color)
            b.mesh.addFacet(panel.reversed().map { $0 + under }, color: Map3DColor.shaded(color, 0.8))
            let hang = [Map3DPoint(edge.x, edge.y, a), Map3DPoint(edge.x, edge.y, c), Map3DPoint(edge.x, edge.y - 0.25, c), Map3DPoint(edge.x, edge.y - 0.25, a)]
            b.mesh.addFacet(hang, color: color)
            b.mesh.addFacet(hang.reversed().map { $0 + inside }, color: color)
        }
        // The sign over it, a block of the shop's colour, lit at night.
        var glow = b.mesh.vertices.count
        b.box(face + 0.25, 3.1, 0, 0.12, width * 0.72, 0.85, colour)
        b.mesh.makeGlowing(from: glow)
        // Decision 352: on it, in the town scene's way, what the shop
        // sells, and when it closes.
        let words = food ? foodWords : retailWords
        let word = words[min(Int(random(20) * Float(words.count)), words.count - 1)]
        let board = Map3DColor.hex(colour), closes = Map3DSignAtlas.closes(word, share: random(21))
        var signs = [Map3DSign(kind: .across, centre: Map3DPoint(face + 0.25 + 0.06 + 0.02, 3.1 + 0.425, 0), facing: Map3DPoint(1, 0, 0),
                               width: width * 0.72 * 0.96, height: 0.85 * 0.86, picture: word, seed: 0, board: board,
                               letters: letters(on: board), closes: closes)]
        // Out front: a food shop's counters (#900's) and stools, a shop's
        // boxes (the detail kit's).
        func part(_ part: Map3DDetailKit.Part, _ x: Float, _ z: Float, facing: Map3DPoint = Map3DPoint(1, 0, 0)) {
            var fixed = StationKitBuilder(), moving = StationKitBuilder()
            fixed.detail(part, moving: &moving)
            b.mesh.append(fixed.mesh, at: Map3DPoint(x, 0, z), forward: facing)
        }
        if food {
            for z: Float in [-2.3, 2.3] {
                b.box(face + 0.8, 0, z, 1.2, 1.5, 0.9, Map3DPalette.counters[v % 3])
                b.cylinder(face + 0.8, 0.9, z, radius: 0.4, height: 0.2, color: Map3DPalette.crates[(v + Int(index)) % 6], sides: 8)
            }
            part(.plasticStool, face + 2.2, -1.1)
            part(.plasticStool, face + 2.3, 1.0)
        } else {
            part(.cartonClosed, face + 0.6, width / 2 - 0.8)
            part(.cartonOpen, face + 0.6, width / 2 - 1.5)
        }
        if index % 3 == 1 { part(.meterBox, face + 0.01, -width / 2 + 0.5) }
        if tall {
            // `decorateHotel`: warm lights under the awning and a sign on
            // two posts on the roof.
            glow = b.mesh.vertices.count
            for z: Float in [-2.2, 0, 2.2] { b.box(top.x + 0.7, 2.56, z, 0.3, 0.3, 0.06, Map3DProp.lampLight) }
            b.mesh.makeGlowing(from: glow)
            let roof = Float(floors) * 3.2 + 0.38
            for z: Float in [-1.8, 1.8] { b.box(face - 1.2, roof, z, 0.15, 0.15, 1.0, SceneKitBuilder.ink) }
            glow = b.mesh.vertices.count
            b.box(face - 1.2, roof + 0.9, 0, 0.2, 4.6, 1.5, colour)
            b.mesh.makeGlowing(from: glow)
            signs.append(Map3DSign(kind: .across, centre: Map3DPoint(face - 1.2 + 0.1 + 0.02, roof + 0.9 + 0.75, 0), facing: Map3DPoint(1, 0, 0),
                                   width: 4.6 * 0.96, height: 1.5 * 0.88, picture: word, seed: 0, board: board, letters: letters(on: board),
                                   closes: closes))
        }
        return Shop(mesh: b.mesh, depth: length, height: Float(floors) * 3.2 + 0.4,
                    wall: Map3DPalette.officeWalls[v % Map3DPalette.officeWalls.count], roof: Map3DPalette.concreteWalls[v % 3], signs: signs)
    }
}
