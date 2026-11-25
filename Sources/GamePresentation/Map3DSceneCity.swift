import GameCore

/// The game's own city in a 3D scene (row houses, blocks, open lots) and
/// the player's buildings, with how their colours are chosen. Moved as
/// it was out of `Map3DScene.swift` (MAP3D-SCENE-SPLIT).
extension Map3DScene.Builder {
    // MARK: City

    /// Every lot of the city in the scene, but those on cells the track
    /// runs through: row houses on low homes and shops, blocks for the
    /// rest, trees in the parks.
    /// Decisions 385 and 516: on a real-world map, the uses whose low
    /// lots (density 2 and under) lay houses along the roads
    /// (``addFrontage``); a factory keeps its hall and yard.
    static let frontedUses: Set<LandUse> = [.residential, .commercial, .office, .civic, .leisure]

    mutating func addCity(_ skyline: CitySkyline, clearOf cleared: Set<ChunkKey>, takenBy taken: Set<ChunkKey> = [],
                          besideRoads: Set<ChunkKey> = [], thinlyBuilt: Set<ChunkKey> = []) {
        let cell = Double(Land.cellLength)
        let pieces = roadPieces(near: besideRoads)
        // Decision 385: on a real-world map, the houses along its roads,
        // laid in the first pass and drawn again in the second.
        if state.roadside.streetFrontage, state.roadside.frontage.pieces.isEmpty { prepareFrontage() }
        // Decision 723: but on the cells of `thinlyBuilt`, whose
        // footprints each house keeps off by itself.
        let blocked = state.roadside.streetFrontage ? cleared.union(taken.subtracting(thinlyBuilt)) : []
        for lot in skyline.lots(in: region) {
            var x = (Double(lot.column) + 0.5) * cell, y = (Double(lot.row) + 0.5) * cell
            // Decision 234: no lot where the real map has water or a
            // park.
            let key = ChunkKey(column: lot.column, row: lot.row)
            let thin = state.roadside.streetFrontage && thinlyBuilt.contains(key)
            // Decision 767: among the real buildings, no factory of the
            // game's, but now and then a coal bunker in the yard.
            if state.roadside.streetFrontage, taken.contains(key), lot.use == .industrial, !lot.isOpenGround, !cleared.contains(key), contains(x: x, y: y) {
                addRealYardCoalBunker(key, blocked: cleared)
                continue
            }
            guard contains(x: x, y: y), !taken.contains(key) || thin else { continue }
            // Decision 385: low homes and shops along the real roads,
            // house by house clear of the no-build land; no other lot
            // whose middle is on it. Decision 516: the low offices,
            // civic and leisure lots too, not one building in the
            // cell's middle (the real schools and temples stand where
            // they are, from the footprints and the temples).
            if state.roadside.streetFrontage, !lot.isOpenGround, !cleared.contains(key), Self.frontedUses.contains(lot.use), lot.density <= 2 {
                addFrontage(column: lot.column, row: lot.row, density: lot.density, shops: lot.use == .commercial || lot.use == .office,
                            blocked: blocked)
                continue
            }
            // Decision 723: nothing else of the game's among footprints.
            if thin { continue }
            if onNoBuildLand(point(x: x, y: y, height: 0)) { continue }
            var side = Float(Double(lot.side) / Self.metre)
            // Decision 345: where its roads reach, a building in the
            // room they leave, if a big enough one fits.
            if besideRoads.contains(key), !lot.isOpenGround, !cleared.contains(key) {
                guard let room = roomBesideRoads(column: lot.column, row: lot.row, side: Int(side.rounded(.down)), in: pieces[key] ?? [])
                else { continue }
                (x, y, side) = (room.x, room.y, Float(room.side))
            } else if besideRoads.contains(key) {
                continue
            }
            let centre = point(x: x, y: y, height: 0)
            let base = Map3DPoint(centre.x, ground(x: x, y: y), centre.z)
            let seed = (Int32(truncatingIfNeeded: lot.column), Int32(truncatingIfNeeded: lot.row))
            if lot.isOpenGround {
                addOpenGround(lot, base: base, seed: seed)
                continue
            }
            if cleared.contains(ChunkKey(column: lot.column, row: lot.row)) {
                // On a real-world map, nothing: the base map's ground,
                // roads and cover are there, and a 62 m square of
                // paving over them read as a bare khaki patch (four
                // round Hong Kong's Kowloon Station), over a cutting
                // with the platforms' canopies poking through it.
                if state.roadside.streetFrontage { continue }
                // A plaza where the track passes, none of it over a
                // trench (decision 375).
                let square = groundSquare(round: base, half: Float(cell / Self.metre / 2) - 1, lift: 0.03)
                let (points, triangles) = outsideTrenches(square, triangles: Self.squareTriangles, lift: 0.03)
                guard !triangles.isEmpty else { continue }
                mesh(at: base) { $0.addFlat(points, triangles: triangles, color: Map3DPalette.plaza, paint: Self.paving) }
                continue
            }
            switch lot.use {
            case .residential, .commercial:
                if lot.density <= 2 {
                    addRowHouses(base: base, side: side, density: lot.density, shops: lot.use == .commercial, seed: seed,
                                 fronts: streetFronts(column: lot.column, row: lot.row))
                } else {
                    addBlock(base: base, side: side, density: lot.density, walls: Self.pickWall(seed), facade: .flatWindows, seed: seed,
                             commercial: lot.use == .commercial)
                }
            case .office:
                addBlock(base: base, side: side, density: lot.density, walls: Self.pick(Map3DPalette.cityOfficeWalls, seed), facade: .officeGlass, seed: seed)
            // Decision 235: factories, schools, clinics, temples and
            // malls from the asset library's rules.
            case .industrial:
                addFactory(base: base, side: side, seed: seed)
            case .civic:
                addCivic(base: base, side: side, density: lot.density, seed: seed)
            default:
                addLeisure(base: base, side: side, seed: seed, front: templeFront(column: lot.column, row: lot.row))
            }
        }
    }

    /// 103.1: the corners of a lot's square `half` metres each way
    /// round `base` (its 64 m cell's middle), `lift` over the drawn
    /// ground (``drawnGround(x:z:)``). Laid flat at the middle's
    /// height, a square on a slope stuck out of the hill as long
    /// triangles where the ground dipped under it.
    mutating func groundSquare(round base: Map3DPoint, half: Float, lift: Float) -> [Map3DPoint] {
        [(-half, -half), (-half, half), (half, half), (half, -half)].map { dx, dz in
            Map3DPoint(base.x + dx, drawnGround(x: base.x + dx, z: base.z + dz) + lift, base.z + dz)
        }
    }

    /// ``groundSquare(round:half:lift:)``'s two triangles, split from
    /// its north-west corner to its south-east one as the cell's
    /// ground is, so each lies on one of the ground's.
    static let squareTriangles = [0, 1, 2, 0, 2, 3]

    mutating func addOpenGround(_ lot: CitySkyline.Lot, base: Map3DPoint, seed: (Int32, Int32)) {
        let half = Float(Double(Land.cellLength) / Self.metre / 2) - 0.5
        let park = lot.use == .park
        let far = isFar
        // Up to nine trees on a hashed 20 m grid (rail-3d's trees
        // stand on a hashed 26 m grid): where each stands and its size.
        var trees: [(spot: Map3DPoint, size: Float)] = []
        if park {
            for i in -1...1 {
                for j in -1...1 {
                    let salt = Int32(10 + (i + 1) * 3 + (j + 1))
                    guard map3DRandom(seed.0, seed.1, salt: salt) < 0.7 else { continue }
                    let jitterX = (map3DRandom(seed.0, seed.1, salt: salt + 20) - 0.5) * 8
                    let jitterZ = (map3DRandom(seed.0, seed.1, salt: salt + 40) - 0.5) * 8
                    var spot = base + Map3DPoint(Float(i) * 20 + jitterX, 0, Float(j) * 20 + jitterZ)
                    spot.y = drawnGround(x: spot.x, z: spot.z)
                    trees.append((spot, 4 + map3DRandom(seed.0, seed.1, salt: salt + 60) * 3))
                }
            }
        }
        let square = groundSquare(round: base, half: half, lift: 0.02)
        // Decision 965: lit as the ground under it.
        let squareNormals = square.map { groundNormal(x: $0.x, z: $0.z) }
        mesh(at: base) { mesh in
            mesh.addFlat(square, triangles: Self.squareTriangles, color: park ? Map3DPalette.park : Map3DPalette.farm, paint: Self.grass,
                         normals: squareNormals)
            for (spot, size) in trees {
                if !far {
                    mesh.addBox(base: spot, length: 0.6, width: 0.6, height: size * 0.45, top: Map3DPalette.trunk, side: Map3DPalette.trunk)
                }
                mesh.addBox(base: spot + Map3DPoint(0, size * 0.4, 0), length: size, width: size, height: size * 0.75,
                            top: Map3DPalette.crown, side: Map3DPalette.crown)
            }
        }
        // Decision 232: a round-ish shadow under each crown.
        for (spot, size) in trees {
            addShadow(centre: spot, length: size * 0.3, width: size * 0.3, spread: size * 0.55, darkness: 0.3)
        }
    }

    /// Decision 263: where a lot's rows of houses stand, from its middle,
    /// metres: each row's front (north, south: `nil` with no street on
    /// that side), and the rows' west and east ends.
    struct RowFronts {
        let north: Float?
        let south: Float?
        let west: Float
        let east: Float
        /// Decision 267: the kind of street each row faces.
        var northKind: Map3DBaseMap.RoadKind?
        var southKind: Map3DBaseMap.RoadKind?

        /// Decision 267: the share of a row's houses with a shop on the
        /// ground floor: on a main road most, on a street some, on a
        /// lane or the back none (a Taiwanese 透天厝 on a busy street
        /// keeps a shop below its home).
        func shopShare(facing: Float) -> Float {
            switch facing > 0 ? southKind : northKind {
            case .primary, .secondary, .trunk: 0.7
            case .tertiary: 0.4
            default: 0
            }
        }
    }

    /// The fronts on the seeded streets round cell (`column`, `row`), or
    /// `nil` on a map without them.
    func streetFronts(column: Int, row: Int) -> RowFronts? {
        guard !state.streets.streetEdges.isEmpty else { return nil }
        let half = Float(Double(Land.cellLength) / Self.metre / 2)
        func clear(_ horizontal: Bool, _ line: Int, _ along: Int) -> Float? {
            state.streets.streetEdges[Map3DSeededStreets.Edge(horizontal: horizontal, line: line, along: along)].map { Map3DSeededStreets.clearance($0) + 0.3 }
        }
        return RowFronts(north: clear(true, row, column).map { half - $0 }, south: clear(true, row + 1, column).map { half - $0 },
                         west: -half + (clear(false, column, row) ?? 2), east: half - (clear(false, column + 1, row) ?? 2),
                         northKind: state.streets.streetEdges[Map3DSeededStreets.Edge(horizontal: true, line: row, along: column)],
                         southKind: state.streets.streetEdges[Map3DSeededStreets.Edge(horizontal: true, line: row + 1, along: column)])
    }

    /// Decision 268: the way a temple on cell (`column`, `row`) faces,
    /// toward the busiest seeded street beside it (south first, as
    /// temples face, when two are alike), and how far from the lot's
    /// middle that street's pavement begins; `nil` with no street
    /// beside it.
    func templeFront(column: Int, row: Int) -> (forward: Map3DPoint, distance: Float)? {
        let half = Float(Double(Land.cellLength) / Self.metre / 2)
        let sides: [(Map3DPoint, Map3DSeededStreets.Edge)] = [
            (Map3DPoint(0, 0, 1), Map3DSeededStreets.Edge(horizontal: true, line: row + 1, along: column)),
            (Map3DPoint(1, 0, 0), Map3DSeededStreets.Edge(horizontal: false, line: column + 1, along: row)),
            (Map3DPoint(-1, 0, 0), Map3DSeededStreets.Edge(horizontal: false, line: column, along: row)),
            (Map3DPoint(0, 0, -1), Map3DSeededStreets.Edge(horizontal: true, line: row, along: column)),
        ]
        var best: (forward: Map3DPoint, distance: Float, kind: Map3DBaseMap.RoadKind)?
        for (forward, edge) in sides {
            guard let kind = state.streets.streetEdges[edge], kind.rawValue > (best?.kind.rawValue ?? -1) else { continue }
            best = (forward, half - Map3DSeededStreets.clearance(kind) - 0.3, kind)
        }
        return best.map { ($0.forward, $0.distance) }
    }

    /// Two rows of 透天厝 back to back on the lot, facing north and
    /// south, each house 4.4–6.6 m wide (a block of flats 6.5–12.5 m at
    /// density 2) with an arcade (騎樓) on most shops, a parapet and a
    /// water tank on many roofs (`city_world_reference` `pickType`,
    /// `floorsFor`, `widthFor`, `waterTank`).
    mutating func addRowHouses(base: Map3DPoint, side: Float, density: Int, shops lotShops: Bool, seed: (Int32, Int32), fronts: RowFronts? = nil) {
        var depth = min(16, side / 2 - 1)
        // Decision 263: on seeded streets, each row's front at its
        // street's pavement (back to back where it has none), from the
        // side street's pavement to the other's.
        let span = fronts.map { ($0.west, $0.east) } ?? (-side / 2 + 0.5, side / 2)
        func frontAt(_ facing: Float) -> Float {
            (facing > 0 ? fronts?.south : fronts?.north) ?? depth + 0.5
        }
        if let fronts { depth = min(depth, [fronts.north, fronts.south].compactMap { $0 }.map { $0 - 0.5 }.min() ?? depth) }
        guard depth > 4 else { return }
        let look = look
        // Decision 267: the street's smallest things, drawn only close.
        var closeDetail = Map3DMesh()
        // Decision 352: the blade signs' words.
        var blades: [Map3DSign] = []
        let flats = density >= 2
        let far = isFar
        mesh(at: base) { mesh in
            for facing: Float in [-1, 1] {
                // From the west end along the row.
                var x = span.0
                var number: Int32 = 0
                while x < span.1 - 3.2 {
                    let salt = Int32(facing > 0 ? 100 : 300) + number * 7
                    let r = { (extra: Int32) in map3DRandom(seed.0, seed.1, salt: salt + extra) }
                    var width = flats ? 6.5 + r(1) * 6 : 4.4 + r(1) * 2.2
                    width = min(width, span.1 - x)
                    guard width >= 3.2 else { break }
                    let wall = Self.pickWall((seed.0 &+ salt, seed.1))
                    let middleX = x + width / 2
                    let front = Map3DPoint(0, 0, facing) // the way the house faces
                    let rowMiddle = base + Map3DPoint(middleX, 0, facing * (frontAt(facing) - depth / 2))
                    // Decision 267: a shop below on a commercial lot, and
                    // on a busy street's houses now and then.
                    let shops = lotShops || r(13) < (fronts?.shopShare(facing: facing) ?? 0)
                    Self.addTownHouse(&mesh, close: &closeDetail, blades: &blades, middle: rowMiddle, front: front, width: width,
                                      depth: depth, flats: flats, shops: shops, wall: wall, far: far, look: look, r: r)
                    x += width
                    number += 1
                }
            }
        }
        for blade in blades { addSign(blade) }
        if !closeDetail.isEmpty {
            let saved = target
            target = .close
            mesh(at: base) { $0.append(closeDetail) }
            target = saved
        }
        // Decision 268: between two rows facing streets on both sides,
        // the back yards; on most lots a lawn down their middle with a
        // few trees (the rest stay paved, for parking).
        if let north = fronts?.north, let south = fronts?.south {
            let yard = (from: -(north - depth) + 1.5, to: south - depth - 1.5)
            let r = { (salt: Int32) in map3DRandom(seed.0, seed.1, salt: salt) }
            if yard.to - yard.from >= 5, span.1 - span.0 > 16, r(90) < 0.7 {
                let length = (span.1 - span.0) * (0.5 + 0.3 * r(91))
                let middleX = (span.0 + span.1) / 2 + (r(92) - 0.5) * (span.1 - span.0 - length)
                let west = middleX - length / 2, east = middleX + length / 2
                mesh(at: base) { mesh in
                    mesh.addQuad(base + Map3DPoint(west, 0.02, yard.from), base + Map3DPoint(west, 0.02, yard.to),
                                 base + Map3DPoint(east, 0.02, yard.to), base + Map3DPoint(east, 0.02, yard.from),
                                 color: Map3DPalette.park, paint: Self.grass)
                }
                if target == .near, let tree = Self.propModels[.tree] {
                    let count = 1 + Int(r(93) * 3)
                    for index in 0..<count {
                        let x = west + length * (Float(index) + 0.5 + (r(Int32(94 + index)) - 0.5) * 0.5) / Float(count)
                        let foot = base + Map3DPoint(x, 0, (yard.from + yard.to) / 2 + (r(Int32(98 + index)) - 0.5) * (yard.to - yard.from - 3))
                        props[key(of: foot), default: []].append(.prop(tree, at: foot, forward: Map3DPoint(1, 0, 0), scale: 0.9 + 0.4 * r(Int32(102 + index)),
                                                                       tint: Self.pick(Map3DProp.greens, r(Int32(106 + index)))))
                    }
                }
            }
        }
        // Decision 232: a shadow round each row.
        for facing: Float in [-1, 1] {
            addShadow(centre: base + Map3DPoint((span.0 + span.1) / 2, 0, facing * (frontAt(facing) - depth / 2)), forward: Map3DPoint(1, 0, 0),
                      length: span.1 - span.0, width: depth + 0.5, spread: 3, darkness: 0.3)
        }
        // Decision 259: shoppers along the shops' fronts (decision 267:
        // and along a busy street's).
        for facing: Float in [-1, 1] where lotShops || (fronts?.shopShare(facing: facing) ?? 0) > 0 {
            let out = facing * (frontAt(facing) + 1.2)
            addShopLife(from: base + Map3DPoint(span.0 + 0.5, 0.05, out), to: base + Map3DPoint(span.1 - 0.5, 0.05, out), density: density)
        }
    }

    /// A block of flats, offices or a tower: density 3 a slab of 7–16
    /// floors, density 4 a two-floor podium under a tower of 18–40.
    /// Decision 231: every side windows of `facade`, a bay to each
    /// 3.2 m (an office's curtain wall 3 m) and floor; a tower's podium
    /// shops, or glass under offices.
    mutating func addBlock(base: Map3DPoint, side: Float, density: Int, walls: UInt32, facade: Map3DSurface, seed: (Int32, Int32),
                           commercial: Bool = false) {
        let r = { (salt: Int32) in map3DRandom(seed.0, seed.1, salt: salt) }
        // Decision 764: its roof, and its walls a little lighter or darker.
        // Decision 812: on Hong Kong's map its walls and roof Hong Kong's.
        let hongKong = look.buildings == .hongKong
        let own = !hongKong ? walls : facade == .officeGlass ? Self.pick(Map3DHongKong.glass, r(1043))
            : Self.pick(density >= 4 ? Map3DHongKong.towerWalls : Map3DHongKong.tenementWalls, r(1043))
        let walls = Self.varied(own, r(1041))
        let roof = hongKong ? Self.pick(Map3DHongKong.roofs, r(1040)) : Self.pickRoof(r(1040), low: false)
        let bay: Float = facade == .officeGlass ? 3 : 3.2
        // Flats' windows with or without blinds, and the podium's shop,
        // picked by where the block stands.
        let windowSurface = facade == .flatWindows ? Self.pick(Map3DSurface.flats, r(3)) : facade
        // Decision 242: flats faced with tiles or grit, offices now and
        // then fair-faced concrete.
        let facing = facade == .officeGlass ? (r(5) < 0.4 ? Map3DSurface.formConcrete : nil) : Self.homeMaterial(r(5))
        // Decision 817: a tower's windows of their own kind, bays and
        // floors; the rest as before (a slab keeps decision 238's
        // balconies, floor for floor). A tower has 18 floors or more
        // (below), enough for Hong Kong's too.
        let towerLook = density >= 4 && look.buildings != .nordic
            ? Map3DFacadeVariety.look(facade == .officeGlass ? .office : .flats, storeys: 18,
                                      hongKong: hongKong, nordic: false, solid: facade == .officeGlass && facing != nil, r: r)
            : nil
        func windows(_ floors: Float, high: Float? = nil, side: Bool = false) -> Map3DPaint {
            if let towerLook, let high { return towerLook.paint(high: high, detail: facing, side: side) }
            return Map3DPaint.bays(windowSurface, bay: bay, floors: Int(floors)).on(facing)
        }
        let far = isFar
        mesh(at: base) { mesh in
            let footprint = max(side - 4, 8)
            switch density {
            case ...2:
                let floors = Float(3 + Int(r(1) * 4))
                mesh.addBox(base: base, length: footprint * 0.8, width: footprint * 0.8, height: 3.8 + 3.2 * (floors - 1),
                            top: roof, side: walls, topPaint: Self.roofing, frontPaint: windows(floors), flankPaint: windows(floors))
            case 3:
                let floors = Float(7 + Int(r(1) * 10))
                let turned = r(2) < 0.5
                mesh.addBox(base: base, forward: turned ? Map3DPoint(1, 0, 0) : Map3DPoint(0, 0, -1),
                            length: footprint * 0.9, width: footprint * 0.45, height: 4.6 + 3.2 * (floors - 1), top: roof, side: walls,
                            topPaint: Self.roofing, frontPaint: windows(floors), flankPaint: windows(floors))
                // Decision 235: a stair house and air conditioners on top;
                // decision 238: near, a balcony along each long side
                // on every floor.
                if !far {
                    let along = turned ? Map3DPoint(1, 0, 0) : Map3DPoint(0, 0, -1)
                    Self.addRoofPlant(&mesh, on: base + Map3DPoint(0, 4.6 + 3.2 * (floors - 1), 0), forward: along,
                                      length: footprint * 0.9, width: footprint * 0.45, r: r, salt: 30)
                    let across = Map3DPoint(-along.z, 0, along.x)
                    for floor in 1..<Int(floors) {
                        for side: Float in [-1, 1] {
                            mesh.addBox(base: base + across * (side * (footprint * 0.225 + 0.5)) + Map3DPoint(0, 4.6 + 3.2 * Float(floor - 1), 0),
                                        forward: along, length: footprint * 0.9 - 2, width: 1, height: 1.05,
                                        top: Map3DColor.shaded(walls, 0.97), side: Map3DColor.shaded(walls, 0.93))
                        }
                    }
                }
            default:
                let floors = Float(18 + Int(r(1) * 23))
                let podium = facade == .officeGlass ? Map3DPaint.bays(.officeGlass, bay: 3, floors: 2) : Map3DPaint.bays(Self.pick(Map3DSurface.shops, r(4)), bay: 5.4, floors: 2)
                mesh.addBox(base: base, length: footprint, width: footprint, height: 9, top: roof, side: Map3DColor.shaded(walls, 0.9),
                            topPaint: Self.roofing, frontPaint: podium, flankPaint: podium)
                mesh.addBox(base: base + Map3DPoint(0, 9, 0), length: footprint * 0.55, width: footprint * 0.55, height: 3.3 * floors,
                            top: roof, side: walls, topPaint: Self.roofing, frontPaint: windows(floors, high: 3.3 * floors),
                            flankPaint: windows(floors, high: 3.3 * floors))
                if hongKong, facade != .officeGlass {
                    let side = footprint * 0.55
                    Self.addHongKongCrown(&mesh, wall: walls, top: base + Map3DPoint(0, 9 + 3.3 * floors, 0),
                                          box: (centre: base, along: Map3DPoint(0, 0, -1), length: side, width: side), far: far, r: r)
                } else if !far {
                    Self.addRoofPlant(&mesh, on: base + Map3DPoint(0, 9 + 3.3 * floors, 0), forward: Map3DPoint(0, 0, -1),
                                      length: footprint * 0.55, width: footprint * 0.55, r: r, salt: 30)
                }
            }
        }
        if !far { addBlockAds(base: base, side: side, density: density, office: facade == .officeGlass, commercial: commercial, r: r) }
        // Decision 817: near, what stands out of a tower's walls.
        if let towerLook, !far, density >= 4 {
            let half = max(side - 4, 8) * 0.55 / 2, floors = Float(18 + Int(r(1) * 23))
            let outline = [Map3DPoint(base.x - half, 0, base.z - half), Map3DPoint(base.x + half, 0, base.z - half),
                           Map3DPoint(base.x + half, 0, base.z + half), Map3DPoint(base.x - half, 0, base.z + half)]
            addTowerRelief(outline, centre: base, bottom: base.y + 9, top: base.y + 9 + 3.3 * floors, look: towerLook, wall: walls, r: r)
        }
        // Decision 259: shoppers round a tower's shops.
        if density >= 4, facade != .officeGlass {
            let half = max(side - 4, 8) / 2 + 1.7
            for (a, b) in [((-1, -1), (1, -1)), ((1, -1), (1, 1)), ((1, 1), (-1, 1)), ((-1, 1), (-1, -1))] as [((Float, Float), (Float, Float))] {
                addShopLife(from: base + Map3DPoint(a.0 * half, 0.05, a.1 * half), to: base + Map3DPoint(b.0 * half, 0.05, b.1 * half),
                            density: density)
            }
        }
        // Decision 232: the shadow round its foot, wider under a taller
        // block.
        let footprint = max(side - 4, 8)
        switch density {
        case ...2:
            addShadow(centre: base, length: footprint * 0.8, width: footprint * 0.8, spread: 2.5, darkness: 0.32)
        case 3:
            let turned = r(2) < 0.5
            addShadow(centre: base, forward: turned ? Map3DPoint(1, 0, 0) : Map3DPoint(0, 0, -1), length: footprint * 0.9,
                      width: footprint * 0.45, spread: 3.5, darkness: 0.34)
        default:
            addShadow(centre: base, length: footprint, width: footprint, spread: 4.5, darkness: 0.36)
        }
    }

    // MARK: The player's buildings

    /// The player's and the company's buildings, warm yellow with a navy
    /// rim on the roof.
    mutating func addPlacedBuildings() {
        for building in world.placedBuildings {
            let x = Double(building.centre.x), y = Double(building.centre.y)
            guard contains(x: x, y: y) else { continue }
            let centre = point(x: x, y: y, height: 0)
            let base = Map3DPoint(centre.x, ground(x: x, y: y), centre.z)
            let side = Float(Double(building.kind.side) / Self.metre) - 2
            if addPlacedKitBuilding(building, base: base, side: side) { continue }
            let height = 1.5 + 3.5 * Float(building.kind.floors)
            let windows = Map3DPaint.bays(.flatWindows, bay: 3.2, floors: Int(building.kind.floors))
            mesh(at: base) { mesh in
                mesh.addBox(base: base, length: side, width: side, height: height, top: Map3DPalette.playerRoof, side: Map3DPalette.player,
                            frontPaint: windows, flankPaint: windows)
                mesh.addBox(base: base + Map3DPoint(0, height, 0), length: side, width: side, height: 0.6,
                            top: Map3DPalette.playerRim, side: Map3DPalette.playerRim)
                mesh.addBox(base: base + Map3DPoint(0, height, 0), length: side - 2, width: side - 2, height: 0.4,
                            top: Map3DPalette.playerRoof, side: Map3DPalette.playerRoof, topPaint: Self.roofing)
            }
            addShadow(centre: base, length: side, width: side, spread: 2.5, darkness: 0.32)
        }
    }

    // MARK: Choosing

    /// Decision 242: what a home's walls are faced with, by a share
    /// from 0 to 1: 二丁掛 tiles on half, 馬賽克 on a quarter, 洗石子 on
    /// some, plain paint on the rest.
    static func homeMaterial(_ share: Float) -> Map3DSurface? {
        share < 0.5 ? .brickTile : share < 0.75 ? .mosaicTile : share < 0.9 ? .terrazzo : nil
    }

    static func pickWall(_ seed: (Int32, Int32)) -> UInt32 {
        let walls = Map3DPalette.houseWalls
        let total = walls.reduce(0) { $0 + $1.weight }
        var roll = map3DRandom(seed.0, seed.1, salt: 7) * total
        for wall in walls {
            if roll < wall.weight { return wall.color }
            roll -= wall.weight
        }
        return walls[0].color
    }

    /// Decision 764: a city building's flat roof by a share from 0 to
    /// 1 (``Map3DPalette/cityRoofs``); red tiles only on a `low` one.
    static func pickRoof(_ share: Float, low: Bool) -> UInt32 {
        let roofs = Map3DPalette.cityRoofs
        var roll = min(max(share, 0), 0.999_9) * roofs.reduce(0) { $0 + $1.weight }
        for roof in roofs {
            if roll < roof.weight { return roof.low && !low ? Map3DPalette.roof : roof.color }
            roll -= roof.weight
        }
        return Map3DPalette.roof
    }

    /// Decision 764: `wall` a little darker by a share from 0 to 1 (at
    /// most 8 %), so two neighbours of one colour still differ.
    static func varied(_ wall: UInt32, _ share: Float) -> UInt32 {
        Map3DColor.shaded(wall, 1 - 0.08 * min(max(share, 0), 1))
    }

    static func pick(_ colors: [UInt32], _ seed: (Int32, Int32)) -> UInt32 {
        colors[min(colors.count - 1, Int(map3DRandom(seed.0, seed.1, salt: 9) * Float(colors.count)))]
    }

    /// One of `choices` by a share from 0 up to 1.
    static func pick<Choice>(_ choices: [Choice], _ share: Float) -> Choice {
        choices[min(choices.count - 1, max(0, Int(share * Float(choices.count))))]
    }
}
