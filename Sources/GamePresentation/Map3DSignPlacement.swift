import Foundation
import GameCore

// ARCHITECTURE decision 352: where the signs hang. The station-front shops'
// boards (decision 322's "a colour-block sign" now says what the shop
// sells), the row houses' blade signs, the real signs of Kaohsiung's and
// Taichung's city tiles (where `Web/CityView`'s pipeline hung them, from
// OpenStreetMap's named places, ODbL), and billboards, LED screens and
// banners on tall commercial buildings by `tools/pipeline/signs.mjs`'s
// `placeAds` (MIT). Near only, like the street furniture.

extension Map3DScene.Builder {
    /// Decision 352: `sign` in its chunk, when the city is built in full.
    mutating func addSign(_ sign: Map3DSign) {
        guard !isFar else { return }
        signs[key(of: sign.centre), default: []].append(sign)
    }

    /// The shop words a station-front food shop's board may say, and a
    /// shop's (the town scene's `SHOP_NAMES` among them).
    static let foodWords = ["早餐店", "豆花", "麵店", "小吃", "便當", "水餃", "牛肉麵", "滷肉飯", "咖啡", "麵包", "冰店", "鹹酥雞", "手搖飲", "肉圓",
                            "燒臘", "粥"].compactMap(Map3DSignAtlas.word)
    static let retailWords = ["便利商店", "文具行", "雜貨店", "書店", "花店", "洗衣店", "水果行", "五金行", "照相館", "藥局", "眼鏡行", "服飾",
                              "鐘錶行", "電器行", "機車行", "彩券行", "鞋店", "電信"].compactMap(Map3DSignAtlas.word)
    /// What a row house's blade sign may say: any shop's word but a
    /// building's, a mall's or a night market's.
    static let streetWords = Map3DSignAtlas.shopWords.indices.filter { !["大樓", "商場", "夜市", "飯店"].contains(Map3DSignAtlas.shopWords[$0]) }

    /// The colour of letters on a board of `board` (0xRRGGBB): navy on a
    /// light board, warm yellow on navy, white on the rest.
    static func letters(on board: UInt32) -> UInt32 {
        if board == 0x262C57 { return 0xFFC86B }
        let r = Float((board >> 16) & 0xFF), g = Float((board >> 8) & 0xFF), b = Float(board & 0xFF)
        return (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255 > 0.62 ? 0x262C57 : 0xFFFFFF
    }

    /// A row house's blade sign's two faces: the box `addFrontDetail`
    /// stands 0.7 m out from `front` (0.25 m thick, `height` tall from
    /// `bottom`), its word on each side.
    static func bladeSigns(middle: Map3DPoint, facing: Map3DPoint, height: Float, board: UInt32, word: Int, closes: Float) -> [Map3DSign] {
        let across = Map3DPoint(-facing.z, 0, facing.x)
        return [Float(1), -1].map { side in
            Map3DSign(kind: .down, centre: middle + across * (side * (0.125 + 0.012)), facing: across * side, width: 0.7 * 0.86,
                      height: height * 0.9, picture: word, seed: 0, board: board, letters: letters(on: board), closes: closes)
        }
    }

    /// A billboard's dark casing and, on a roof, its legs down to `roof`
    /// (`ads.js`'s `frame`).
    mutating func addAdFrame(_ sign: Map3DSign, roof: Float?) {
        let facing = sign.facing, width = sign.right.length * 2, height = sign.up.length * 2
        let casing = Map3DColor.rgb(0x2A2C2F)
        let back = sign.centre - facing * 0.12 - Map3DPoint(0, height * 0.515, 0)
        mesh(at: sign.centre) { mesh in
            mesh.addBox(base: back, forward: facing, length: 0.16, width: width * 1.03, height: height * 1.03, top: casing, side: casing)
            if let roof {
                let bottom = sign.centre.y - height / 2
                for side: Float in [-0.8, 0, 0.8] {
                    let foot = sign.centre - facing * 0.22 + sign.right * side
                    mesh.addBox(base: Map3DPoint(foot.x, roof, foot.z), forward: facing, length: 0.12, width: 0.12, height: bottom - roof,
                                top: casing, side: casing)
                }
            }
        }
    }

    /// One wall of a building, for `placeAds`: where it starts, its
    /// direction and outward normal (level), its length, and whether it
    /// looks onto a street.
    struct AdWall {
        let start: Map3DPoint
        let direction: Map3DPoint
        let normal: Map3DPoint
        let length: Float
        let street: Bool
    }

    /// How likely each of `placeAds`' signs is on a building's wall.
    struct AdChances {
        var wall: Float
        var screen: Float
        var banner: Float
        var roof: Float

        /// `placeAds`' chances at `distance` metres from the area's
        /// middle (its station): thick round it, thinning out; a station
        /// front in Taiwan ``taiwan`` times as thick as the Scramble
        /// Crossing `placeAds` was made for (Kaohsiung's square hung 779
        /// at full chance, a billboard on nearly every tall wall).
        static func real(distance d: Float) -> AdChances {
            AdChances(wall: (d < 220 ? 0.9 : d < 500 ? 0.5 : d < 900 ? 0.2 : 0.07) * taiwan,
                      screen: d < 260 ? 0.45 : d < 600 ? 0.12 : 0.03,
                      banner: (d < 260 ? 0.7 : d < 600 ? 0.4 : d < 1_100 ? 0.2 : 0.08) * taiwan,
                      roof: (d < 450 ? 0.38 : d < 900 ? 0.12 : 0.03) * taiwan)
        }

        static let taiwan: Float = 0.45
    }

    /// `placeAds` (`signs.mjs`) on one building standing on `foot`,
    /// `height` tall: on its two longest walls onto a street, a billboard
    /// or a screen, a banner down one end, and on the roof a board on a
    /// frame. Returns the signs and, for each, the roof under its legs.
    static func ads(walls: [AdWall], foot: Float, height: Float, chances: AdChances, r: (Int32) -> Float) -> [(sign: Map3DSign, roof: Float?)] {
        guard height >= 12 else { return [] }
        var placed: [(sign: Map3DSign, roof: Float?)] = []
        let chosen = walls.filter { $0.street && $0.length >= 4.5 }.sorted { $0.length > $1.length }.prefix(2)
        for (index, wall) in chosen.enumerated() {
            let salt = Int32(200 + index * 10)
            let h1 = r(salt), h2 = r(salt + 1), h3 = r(salt + 2), h4 = r(salt + 3), h5 = r(salt + 4), h6 = r(salt + 5)
            let middle = wall.start + wall.direction * (wall.length / 2)
            if h1 < chances.wall {
                // On the wall: wide on a long wall, tall on a narrow one.
                let tall = wall.length < 8, width = tall ? wall.length * 0.8 : min(wall.length * 0.72, 15)
                let h = tall ? min(height * 0.5, width * 2.2, 14) : min(height * 0.34, width * 0.62, 9)
                let y = foot + max(6.5 + h / 2, height * 0.62)
                if h > 2.5, y + h / 2 < foot + height - 0.8 {
                    let screen = h2 < chances.screen
                    let kind: Map3DSign.Kind = screen ? .screen : .poster
                    placed.append((Map3DSign(kind: kind, centre: Map3DPoint(middle.x, y, middle.z) + wall.normal * 0.3, facing: wall.normal,
                                             width: width, height: h, picture: Int(h5 * 997) % Map3DSignAtlas.posters, seed: h6,
                                             closes: Map3DSignAtlas.adCloses(kind, rooftop: false, share: h3)), nil))
                }
            }
            // Down the side of the building: a banner near one end.
            if wall.length >= 6, height >= 15, h4 < chances.banner {
                let width = 1.6 + 1.2 * h5, h = min(height * 0.55, width * 6.5, 18)
                let end = h6 < 0.5 ? 0.9 + width / 2 : wall.length - 0.9 - width / 2
                let at = wall.start + wall.direction * end
                placed.append((Map3DSign(kind: .banner, centre: Map3DPoint(at.x, foot + max(4.5 + h / 2, height * 0.5), at.z) + wall.normal * 0.3,
                                         facing: wall.normal, width: width, height: h, picture: Int(h4 * 9_973) % Map3DSignAtlas.banners,
                                         seed: h6, closes: Map3DSignAtlas.adCloses(.banner, rooftop: false, share: h2)), nil))
            }
            // On the roof, on a frame.
            if index == 0, height < 60, r(salt + 6) < chances.roof {
                let width = min(wall.length * 0.8, 12), h = min(width * 0.45, 5)
                if width > 4 {
                    let centre = Map3DPoint(middle.x, foot + height + 1.6 + h / 2, middle.z) - wall.normal * 0.6
                    placed.append((Map3DSign(kind: .poster, centre: centre, facing: wall.normal, width: width, height: h,
                                             picture: Int(r(salt + 7) * 991) % Map3DSignAtlas.posters, seed: h6,
                                             closes: Map3DSignAtlas.adCloses(.poster, rooftop: true, share: h1)), foot + height))
                }
            }
        }
        return placed
    }

    /// The walls of `outline` (scene points, level), every edge at least
    /// 2.2 m long, each facing out of it, `street` telling whether it
    /// looks onto one (`placeSigns`' walls).
    static func adWalls(_ outline: [Map3DPoint], street: (Map3DPoint, Map3DPoint) -> Bool) -> [AdWall] {
        let polygon = [outline]
        var walls: [AdWall] = []
        for (index, a) in outline.enumerated() {
            let b = outline[(index + 1) % outline.count]
            let edge = Map3DPoint(b.x - a.x, 0, b.z - a.z)
            guard edge.length >= 2.2, let direction = edge.normalized else { continue }
            var normal = Map3DPoint(-direction.z, 0, direction.x)
            let middle = Map3DPoint((a.x + b.x) / 2, 0, (a.z + b.z) / 2)
            if inside(middle + normal * 0.5, polygon) { normal = -normal }
            walls.append(AdWall(start: Map3DPoint(a.x, 0, a.z), direction: direction, normal: normal, length: edge.length,
                                street: street(middle, normal)))
        }
        return walls
    }

    /// The side of ``streetCells(within:)``'s cells, metres.
    static let streetCell: Float = 4

    /// Decision 352: the 4 m cells within reach of a road's carriageway or
    /// pavement round `areas` (scene points), for a wall to tell whether
    /// it looks onto a street (`placeSigns`' `facesStreet`).
    func streetCells(within boxes: [(min: Map3DPoint, max: Map3DPoint)]) -> Set<Map3DScene.ChunkKey> {
        var cells = Set<Map3DScene.ChunkKey>()
        guard !boxes.isEmpty else { return cells }
        func near(_ p: Map3DPoint) -> Bool {
            boxes.contains { p.x >= $0.min.x - 40 && p.x <= $0.max.x + 40 && p.z >= $0.min.z - 40 && p.z <= $0.max.z + 40 }
        }
        for road in roadLines {
            for (a, b) in zip(road.points, road.points.dropFirst()) where near(a) || near(b) {
                let span = Map3DPoint(b.x - a.x, 0, b.z - a.z), steps = max(1, Int((span.length / 2).rounded(.up)))
                let cell = Self.streetCell, reach = Int((road.half / cell).rounded(.down))
                for step in 0...steps {
                    let p = a + span * (Float(step) / Float(steps))
                    let column = Int((p.x / cell).rounded(.down)), row = Int((p.z / cell).rounded(.down))
                    for dr in -reach...reach {
                        for dc in -reach...reach where Float(dr * dr + dc * dc) * cell * cell <= road.half * road.half {
                            cells.insert(Map3DScene.ChunkKey(column: column + dc, row: row + dr))
                        }
                    }
                }
            }
        }
        return cells
    }

    /// Whether a wall whose middle is `middle` looks onto a street in
    /// `cells`: a road within 2, 4.5 or 8 m out of it (`placeSigns`).
    static func facesStreet(_ cells: Set<Map3DScene.ChunkKey>, middle: Map3DPoint, normal: Map3DPoint) -> Bool {
        [Float(2), 4.5, 8].contains { distance in
            let p = middle + normal * distance
            return cells.contains(Map3DScene.ChunkKey(column: Int((p.x / streetCell).rounded(.down)), row: Int((p.z / streetCell).rounded(.down))))
        }
    }

    /// Decision 352: the signs `area`'s pipeline hung, laid on the world by
    /// `world` (the tiles' projection): each says the word its place's
    /// name tells (never the name), in the pipeline's colours.
    mutating func addTileSigns(_ area: CityTileArea, world: (CityTileArea.Point) -> (x: Double, y: Double)) {
        guard !isFar else { return }
        for tile in area.signs where tile.style <= 2 && tile.height >= 0.5 && tile.width > 0 {
            let spot = world(CityTileArea.Point(x: tile.x, z: tile.z))
            guard contains(x: spot.x, y: spot.y) else { continue }
            let out = world(CityTileArea.Point(x: tile.x + tile.nx, z: tile.z + tile.nz))
            let foot = point(x: spot.x, y: spot.y, height: 0), ahead = point(x: out.x, y: out.y, height: 0)
            guard let normal = Map3DPoint(ahead.x - foot.x, 0, ahead.z - foot.z).normalized else { continue }
            let ground = self.ground(x: spot.x, y: spot.y)
            let centre = Map3DPoint(foot.x, ground + tile.y, foot.z)
            let colours = Map3DSignAtlas.tileColours[Map3DSignAtlas.plainColour(tile.colour)]
            let word = Map3DSignAtlas.word(forName: tile.text, title: tile.style == 2)
            let hash = Map3DSignAtlas.stableHash(tile.text + "\(Int(tile.x)),\(Int(tile.z))")
            let closes = Map3DSignAtlas.closes(word, share: Float(hash % 1_000) / 1_000)
            if tile.style == 1 {
                // A blade: out from the wall, read from both ways along
                // the street (`signs.js`).
                let along = Map3DPoint.up.cross(normal)
                for side: Float in [1, -1] {
                    addSign(Map3DSign(kind: .down, centre: centre + normal * (0.15 + tile.width / 2) + along * (side * 0.04), facing: along * side,
                                      width: tile.width, height: tile.height, picture: word, seed: 0, board: colours.board,
                                      letters: colours.letters, closes: closes))
                }
            } else {
                addSign(Map3DSign(kind: .across, centre: centre + normal * 0.03, facing: normal, width: tile.width, height: tile.height,
                                  picture: word, seed: 0, board: colours.board, letters: colours.letters, closes: closes))
            }
        }
    }
}

extension Map3DScene.Builder {
    /// Decision 352: `placeAds` on a city block of `addBlock` (density 3
    /// a slab, 4 a podium under a tower), commercial or offices: on a
    /// tower its lowest 30 m above the podium, where the street sees them;
    /// on a slab its roof too. The game's city has no street names to
    /// thin them out by, so the chance goes by what the block is.
    mutating func addBlockAds(base: Map3DPoint, side: Float, density: Int, office: Bool, commercial: Bool, r: (Int32) -> Float) {
        guard density >= 3, office || commercial else { return }
        let chances = density >= 4
            ? (commercial ? AdChances(wall: 0.7, screen: 0.35, banner: 0.5, roof: 0) : AdChances(wall: 0.3, screen: 0.15, banner: 0.2, roof: 0))
            : (commercial ? AdChances(wall: 0.4, screen: 0.12, banner: 0.3, roof: 0.25) : AdChances(wall: 0.3, screen: 0.15, banner: 0.2, roof: 0.15))
        let footprint = max(side - 4, 8)
        let along: Map3DPoint, length: Float, width: Float, foot: Float, height: Float
        if density >= 4 {
            (along, length, width) = (Map3DPoint(0, 0, -1), footprint * 0.55, footprint * 0.55)
            foot = base.y + 9
            height = min(3.3 * Float(18 + Int(r(1) * 23)), 30)
        } else {
            along = r(2) < 0.5 ? Map3DPoint(1, 0, 0) : Map3DPoint(0, 0, -1)
            (length, width) = (footprint * 0.9, footprint * 0.45)
            foot = base.y
            height = 4.6 + 3.2 * Float(7 + Int(r(1) * 10) - 1)
        }
        let across = Map3DPoint(-along.z, 0, along.x)
        let outline = [(Float(1), Float(1)), (1, -1), (-1, -1), (-1, 1)].map { base + along * ($0.0 * length / 2) + across * ($0.1 * width / 2) }
        // Lots stand between streets on every side.
        let walls = Self.adWalls(outline) { _, _ in true }
        for ad in Self.ads(walls: walls, foot: foot, height: height, chances: chances, r: r) {
            addSign(ad.sign)
            addAdFrame(ad.sign, roof: ad.roof)
        }
    }
}
