import GameCore

// Decision 812: Hong Kong's buildings (``Map3DRegionLook/Buildings/hongKong``),
// from the parts and the atlas the city already has: no texture is new.
// From the game's camera, what tells Hong Kong from Taipei is its towers
// and its roofs: slender towers of flats thirty to sixty floors high in
// off-white, cream, pale pink and pale green, each crowned with its lift
// machine room and water tank; walk-up tenements (唐樓) of four to nine
// floors in faded mosaic, shops on the pavement and huts on their roofs;
// offices walled in blue-green glass; and grey concrete roofs, not the
// blue, green and red waterproofing of Taiwan's. The colours are the
// owner's Causeway Bay street scene's
// (`Railway/street_scene_reference_clean/source/models/causeway-bay-buildings.gltf`,
// its materials) and Mong Kok's and Central's in the commuter game
// (`Railway/commuter_journey_reference_clean/source/js/scene/MongKokStreet.js`,
// `CentralStreet.js`), each written as the map draws it.

/// Decision 812: the colours of Hong Kong's buildings, each written as the
/// map draws it (``Map3DLook/source(drawing:)``).
enum Map3DHongKong {
    /// A tower of flats: off-white the commonest, then cream, pale pink,
    /// pale green, sand, pale blue-grey, salmon and pale teal.
    static let towerWalls: [UInt32] = drawn([
        0xF2EFE8, 0xF2EFE8, 0xF2EFE8, 0xEDE3CF, 0xEBD5C8, 0xDCE6D8, 0xE6DCC6, 0xDCE2E6, 0xE9C8BA, 0xD3E2DE,
    ])
    /// A tenement: the faded sand, sage, mauve and taupe of Mong Kok's,
    /// the pink concrete, the repaired plaster and the grey-green mosaic
    /// of Causeway Bay's, each a step lighter than the reference's, which
    /// its lit scene darkens less than the map's flat light does.
    static let tenementWalls: [UInt32] = drawn([
        0xD9C9AE, 0xBFCFC5, 0xD5C3C6, 0xCDBFB3, 0xE6CDB9, 0xDDD7C7, 0xA9BDBB, 0xE3D6BE, 0xC9CDBE,
    ])
    /// A village house (丁屋) or a low block: white, cream and pale tile.
    static let lowWalls: [UInt32] = drawn([0xEEECE5, 0xEEECE5, 0xE8DDB8, 0xE6D3C9, 0xD8E0D2, 0xE7DAC5])
    /// An office's glass: blue, blue-green and grey-green, a dark ribbon
    /// now and then.
    static let glass: [UInt32] = drawn([0x4E7E97, 0x5F7E88, 0x608E9D, 0x6D9DAB, 0x87A1A5, 0x455960, 0x3E4D56])
    /// An office faced in stone or panels between its window bands.
    static let officeStone: [UInt32] = drawn([0xD2D5D0, 0xDBD6C5, 0xE5DECE, 0xBCC7C6])
    /// A school's, a hospital's or a government building's walls.
    static let civicWalls: [UInt32] = drawn([0xE0E3E0, 0xDCCFB7, 0xE7DAC5, 0xD2D5D0])
    /// A flat roof's concrete: pale greys, a warm or a cool one now and
    /// then.
    static let roofs: [UInt32] = drawn([0xCFD0CC, 0xCFD0CC, 0xC7C9C6, 0xBEC1C0, 0xD3CFC6, 0xC2C6C8, 0xB9BCBA])
    /// A rooftop hut's walls (天台僭建) and its sheet-steel roof.
    static let hutWall = Map3DLook.source(drawing: Map3DColor.rgb(0xC9C8BF))
    static let hutRoofs: [UInt32] = drawn([0x9EA3A3, 0xB0ABA0, 0x8F9A9C])

    private static func drawn(_ colours: [UInt32]) -> [UInt32] { colours.map { Map3DLook.source(drawing: Map3DColor.rgb($0)) } }

    /// The fewest storeys a tower of flats has; lower ones are tenements
    /// or village houses.
    static let towerStoreys = 10
    /// The most storeys a village house or low block has.
    static let lowStoreys = 3
    /// A tower's window bay, metres: a flat's rooms are narrow.
    static let towerBay: Float = 2.6
    /// A tenement's window bay and its shops', metres.
    static let tenementBay: Float = 3
    static let shopBay: Float = 4.5
    /// A glass office's mullions, metres.
    static let mullion: Float = 1.6
    /// The crown on a tower's roof (its lift machine room and water
    /// tank): how high, metres, and the most of the roof it covers.
    static let crownHeight: Float = 5
    static let crownShare: Float = 0.55
    /// The largest roof a crown stands on, m²: a tower's (some 20 × 30 m
    /// at most); a wider roof is a podium's or an estate block's, whose
    /// lift rooms are many and small (its plant, near).
    static let crownedRoof: Float = 900
}

extension Map3DScene.Builder {
    /// Decision 812: how one of Hong Kong's real buildings is faced.
    struct HongKongFaces {
        var wall: UInt32
        var roof: UInt32
        var groundFloor: Float = 0
        var groundPaint: Map3DPaint?
        var upperPaint: Map3DPaint?
        /// Whether its roof is sheet steel.
        var metalRoof = false
    }

    /// Decision 812: the faces of a real building of `kind` and `storeys`,
    /// `height` metres high, on Hong Kong's map, or `nil` for a kind drawn
    /// as Taiwan's (a temple, a station, a terminal, a hall).
    /// `floors(high, storeys)` is how many floors of windows a wall of
    /// `high` metres takes.
    static func hongKongFaces(_ kind: RealKind, storeys: Int, height: Float, r: (Int32) -> Float,
                              floors: (Float, Int) -> Int) -> HongKongFaces? {
        let roof = pick(Map3DHongKong.roofs, r(1040))
        let shops = pick(Map3DSurface.shops, r(2))
        switch kind {
        case .house, .flats, .shophouse:
            let tower = storeys >= Map3DHongKong.towerStoreys
            var faces = HongKongFaces(wall: 0, roof: roof)
            // Shops on the pavement: a tenement's and a shophouse tower's
            // always, most other tenements'.
            if kind == .shophouse || (!tower && storeys > Map3DHongKong.lowStoreys && r(1) < 0.7) {
                faces.groundFloor = min(3.8, height / 3)
                faces.groundPaint = .bays(shops, bay: Map3DHongKong.shopBay, floors: 1)
            }
            let upper = floors(height - faces.groundFloor, faces.groundFloor > 0 ? max(1, storeys - 1) : storeys)
            if tower {
                faces.wall = pick(Map3DHongKong.towerWalls, r(1043))
                faces.upperPaint = .bays(pick(Map3DSurface.flats, r(3)), bay: Map3DHongKong.towerBay, floors: upper)
            } else if storeys > Map3DHongKong.lowStoreys || kind == .shophouse {
                faces.wall = pick(Map3DHongKong.tenementWalls, r(1043))
                faces.upperPaint = Map3DPaint.bays(pick(Map3DSurface.flats, r(3)), bay: Map3DHongKong.tenementBay, floors: upper)
                    .on(r(5) < 0.5 ? .mosaicTile : nil)
            } else {
                faces.wall = pick(Map3DHongKong.lowWalls, r(1043))
                faces.upperPaint = Map3DPaint.bays(.homeWindows, bay: Map3DHongKong.shopBay, floors: upper).on(r(5) < 0.5 ? .mosaicTile : nil)
            }
            return faces
        case .office:
            var faces = HongKongFaces(wall: 0, roof: roof, groundFloor: min(4.6, height / 3))
            let upper = floors(height - faces.groundFloor, max(1, storeys - 1))
            if r(6) < 0.65 {
                faces.wall = pick(Map3DHongKong.glass, r(1043))
                faces.groundPaint = .bays(.officeGlass, bay: 3, floors: 1)
                faces.upperPaint = .bays(.officeGlass, bay: Map3DHongKong.mullion, floors: upper)
            } else {
                faces.wall = pick(Map3DHongKong.officeStone, r(1043))
                faces.groundPaint = .bays(r(1) < 0.5 ? .officeGlass : shops, bay: r(1) < 0.5 ? 3 : Map3DHongKong.shopBay, floors: 1)
                faces.upperPaint = .bays(.officeGlass, bay: 2.4, floors: upper)
            }
            return faces
        case .industry:
            // A works: a shed under grey sheet steel, or a factory block
            // (工廠大廈) of four floors and more under concrete.
            guard storeys >= 4 else {
                return HongKongFaces(wall: pick(Map3DPalette.shedWalls, r(1043)), roof: pick(Map3DHongKong.hutRoofs, r(4)),
                                     upperPaint: metal, metalRoof: true)
            }
            return HongKongFaces(wall: pick(Map3DHongKong.civicWalls, r(1043)), roof: roof,
                                 upperPaint: .bays(.flatWindows, bay: 3.4, floors: floors(height, storeys)))
        case .civic:
            return HongKongFaces(wall: pick(Map3DHongKong.civicWalls, r(1043)), roof: roof,
                                 upperPaint: Map3DPaint.bays(.flatWindows, bay: 3.4, floors: floors(height, storeys)).on(.mosaicTile))
        default:
            return nil
        }
    }

    /// Decision 812: what stands on a Hong Kong roof, `top` the roof's
    /// middle over the oriented box: on a tower of flats its crown (the
    /// lift machine room, the water tank over it), which every tower has
    /// and which shows from afar; on a tenement or a village house a hut
    /// of sheet steel or a stair house; on an office or a public building,
    /// near, its plant. 10 triangles a box.
    static func addHongKongRoof(_ mesh: inout Map3DMesh, kind: RealKind, storeys: Int, wall: UInt32, top: Map3DPoint,
                                box: (centre: Map3DPoint, along: Map3DPoint, length: Float, width: Float), far: Bool, r: (Int32) -> Float) {
        let across = Map3DPoint(-box.along.z, 0, box.along.x)
        switch kind {
        case .house, .flats, .shophouse:
            guard storeys < Map3DHongKong.towerStoreys else {
                addHongKongCrown(&mesh, wall: wall, top: top, box: box, far: far, r: r)
                return
            }
            // Only on a house's or a tenement's roof, not a long terrace's.
            guard box.length > 4, box.width > 3.2, box.length < 40, box.width < 25 else { return }
            if r(6) < 0.6 {
                let length = box.length * 0.45, width = box.width - 0.8
                let spot = top - box.along * (box.length / 2 - length / 2 - 0.4)
                mesh.addBox(base: spot, forward: box.along, length: length, width: width, height: 2.4, top: pick(Map3DHongKong.hutRoofs, r(11)),
                            side: Map3DHongKong.hutWall, topPaint: metal, frontPaint: metal, flankPaint: metal, capped: false)
            } else if r(6) < 0.85 {
                let spot = top + box.along * ((r(7) - 0.5) * (box.length - 3.2)) + across * ((r(8) - 0.5) * (box.width - 2.6))
                mesh.addBox(base: spot, forward: box.along, length: 3.2, width: 2.6, height: 2.6, top: pick(Map3DHongKong.roofs, r(1044)),
                            side: Map3DColor.shaded(wall, 0.94), capped: false)
            }
        case .office, .civic:
            if !far { addRoofPlant(&mesh, on: top, forward: box.along, length: box.length * 0.8, width: box.width * 0.8, r: r, salt: 30) }
        default:
            break
        }
    }

    /// Decision 812: a tower's crown: its lift machine room over the
    /// middle of its roof, the water tank over one end of it; on a roof
    /// wider than ``Map3DHongKong/crownedRoof`` a stair house and plant.
    static func addHongKongCrown(_ mesh: inout Map3DMesh, wall: UInt32, top: Map3DPoint,
                                 box: (centre: Map3DPoint, along: Map3DPoint, length: Float, width: Float), far: Bool, r: (Int32) -> Float) {
        guard box.length >= 8, box.width >= 8, box.length * box.width <= Map3DHongKong.crownedRoof else {
            guard !far else { return }
            addRoofPlant(&mesh, on: top, forward: box.along, length: box.length * 0.8, width: box.width * 0.8, r: r, salt: 30)
            return
        }
        let length = min(box.length * Map3DHongKong.crownShare, 14), width = min(box.width * Map3DHongKong.crownShare, 12)
        let room = Map3DColor.shaded(wall, 0.94)
        let roof = pick(Map3DHongKong.roofs, r(1044))
        mesh.addBox(base: top, forward: box.along, length: length, width: width, height: Map3DHongKong.crownHeight, top: roof, side: room,
                    capped: false)
        // The tank to one end of it, a storey higher.
        let tank = top + box.along * (length * 0.2) + Map3DPoint(0, Map3DHongKong.crownHeight, 0)
        mesh.addBox(base: tank, forward: box.along, length: length * 0.5, width: width * 0.8, height: 2.4, top: roof, side: room,
                    capped: false)
    }

    /// Decision 812: one of the houses the game lays along a road
    /// (``addTownHouse``) on Hong Kong's map: a tenement of four to eight
    /// floors, shops on the pavement with `shops`, under a grey roof with
    /// its hut; or with `flats` a tower of up to twenty, crowned. No
    /// arcade, no Taiwanese tank or rooftop room; the same afar.
    static func addHongKongHouse(_ mesh: inout Map3DMesh, middle: Map3DPoint, front: Map3DPoint, width: Float, depth: Float, flats: Bool,
                                 shops: Bool, far: Bool, tallest: Int?, r: (Int32) -> Float) {
        let wide = width - 0.1
        guard wide >= 3 else { return }
        let storeys = flats ? min(10 + Int(r(2) * 11), max(tallest ?? 20, 4)) : min(4 + Int(r(2) * 5), max(tallest ?? 8, 2))
        let kind: RealKind = shops ? .shophouse : .flats
        let height = Float(storeys) * Map3DScene.Builder.storeyHeight
        guard let faces = hongKongFaces(kind, storeys: storeys, height: height, r: r, floors: { max($1, Int($0 / tallestStorey)) }) else { return }
        let wall = varied(faces.wall, r(1041))
        var base = middle
        if faces.groundFloor > 0 {
            mesh.addBox(base: base, forward: front, length: depth, width: wide, height: faces.groundFloor, top: faces.roof, side: wall,
                        frontPaint: faces.groundPaint, flankPaint: plaster, capped: false)
            base.y += faces.groundFloor
        }
        mesh.addBox(base: base, forward: front, length: depth, width: wide, height: height - faces.groundFloor, top: faces.roof, side: wall,
                    topPaint: roofing, frontPaint: faces.upperPaint, flankPaint: storeys >= Map3DHongKong.towerStoreys ? faces.upperPaint : plaster)
        let box = (centre: middle, along: front, length: depth, width: wide)
        addHongKongRoof(&mesh, kind: kind, storeys: storeys, wall: wall, top: middle + Map3DPoint(0, height, 0), box: box, far: far, r: r)
    }
}
