import Foundation

// Decision 235: the city's factories, schools, clinics, temples and malls,
// and the clutter on its roofs, put together from the rules of the
// owner's asset library (`Railway/procedural_assets_reference_clean/`):
// the industrial pack's sheds (gable, sawtooth, arched), offices, brick
// halls, chimneys and tanks; the city pack's clinic, police and fire
// stations (a stone ground storey, a band, upper storeys of about 3 m,
// a parapet, a stair house and plant on the roof); the japan pack's
// temple hall and school gym. Recombined, never copied: each building is
// a few boxes and roofs, a few hundred triangles, in the 3D map's own
// palette (F 台灣版＋), and the same every time for the same lot.

extension Map3DPalette {
    /// Factory roofs: Taiwan's blue sheet steel most of all, and the
    /// industrial pack's neutral, faded and rusted sheets, lightened.
    static let tinRoofs: [UInt32] = [rgbColor(0x5F8BC0), rgbColor(0x6F9AC9), rgbColor(0xA6A8A3), rgbColor(0xBDBBB1), rgbColor(0x9C8270)]
    /// Sheds' walls: the industrial pack's warehouse and workshop greys.
    static let shedWalls: [UInt32] = [rgbColor(0xD0D2CF), rgbColor(0xBFC3BE), rgbColor(0xC9CDC9), rgbColor(0xB7BDB3)]
    /// Brick for the old plant halls and chimneys (its `#aa5c3d`, lighter).
    static let brick = rgbColor(0xB8735A)
    static let rollerDoor = rgbColor(0x8A96A0)
    static let glazing = rgbColor(0x9DB3C2)
    /// Office trim blue (the compact factory office's `#244e86`, lighter).
    static let trimBlue = rgbColor(0x4A72A8)
    static let containers: [UInt32] = [rgbColor(0xB65C4E), rgbColor(0x4F80A8), rgbColor(0x6F9B6C), rgbColor(0xCFA24C)]
    static let tankWhite = rgbColor(0xE4E2DC)
    /// A school's cream walls and red track.
    static let schoolWalls = rgbColor(0xEFE5CF)
    static let track = rgbColor(0xC9806A)
    static let sportsField = rgbColor(0x9CC983)
    /// The school gym's metal roof (its `#274d49`, lighter).
    static let gymGreen = rgbColor(0x5E8F86)
    /// A clinic's or public office's white tile and grey stone.
    static let tileWhite = rgbColor(0xEDEFF0)
    static let stone = rgbColor(0xBFBBB2)
    /// A temple's vermilion walls, orange-glazed roofs and granite.
    static let templeWall = rgbColor(0xC8573F)
    static let templeRoof = rgbColor(0xE39A48)
    static let templeRidge = rgbColor(0xC64C36)
    static let granite = rgbColor(0xD3CDC1)
    /// Decision 268: a temple forecourt's stone, and its lanterns' red
    /// (HANDOFF §4.3).
    static let forecourt = rgbColor(0xD8D0C2)
    static let lantern = rgbColor(0xE0392C)
    /// Plant on the roofs: air conditioners, stair houses' doors.
    static let plant = rgbColor(0xA7A39A)
    /// The japan pack's outdoor air conditioner (`#e9e7df`).
    static let acUnit = rgbColor(0xE9E7DF)
    static let signs: [UInt32] = [rgbColor(0xD9534A), rgbColor(0x3E7CC0), rgbColor(0xF0B847), rgbColor(0x4FA36B)]
    /// Decision 267: a street's life on a row house's front, in the colours
    /// of F 台灣版＋ (`docs/art/3d-style-2026-10-13/`, HANDOFF §4.3) and the
    /// owner's target picture: shop counters, the crates on them, the low
    /// shop awnings, the tin awnings over the windows (blue, green, red,
    /// grey) and the washing on the balconies.
    static let counters: [UInt32] = [rgbColor(0xD8D0C2), rgbColor(0x8E6E52), rgbColor(0xC9CCCF)]
    static let crates: [UInt32] = [rgbColor(0xE86A7A), rgbColor(0xF2D24B), rgbColor(0x5E9A78), rgbColor(0x4E78A8), rgbColor(0xF2F0EA), rgbColor(0xD98A4A)]
    static let shopAwnings: [UInt32] = [rgbColor(0x3E8C8C), rgbColor(0xC65A4E), rgbColor(0x4E78A8), rgbColor(0xF2F0EA)]
    static let tinAwnings: [UInt32] = [rgbColor(0x4E78A8), rgbColor(0x5E9A78), rgbColor(0xC65A4E), rgbColor(0x7A93A6)]
    static let washing: [UInt32] = [rgbColor(0xF2F0EA), rgbColor(0x4E78A8), rgbColor(0xE86A7A), rgbColor(0x8A9BB0), rgbColor(0xD9B48A)]
    /// The water tank's stand.
    static let tankStand = rgbColor(0x6E747B)

    fileprivate static func rgbColor(_ hex: UInt32) -> UInt32 { Map3DColor.rgb(hex) }
}

extension Map3DScene.Builder {
    /// A lot's random numbers, 0 up to 1, one for each `salt`.
    static func numbers(_ seed: (Int32, Int32)) -> (Int32) -> Float {
        { salt in map3DRandom(seed.0, seed.1, salt: salt) }
    }

    // MARK: Factories

    /// A factory on its yard: a gable shed with an office, a sawtooth
    /// hall, an arched warehouse with containers, or an old brick plant
    /// with a chimney and tanks.
    mutating func addFactory(base: Map3DPoint, side: Float, seed: (Int32, Int32)) {
        let r = Self.numbers(seed)
        let lot = max(side - 4, 12)
        let forward = r(2) < 0.5 ? Map3DPoint(1, 0, 0) : Map3DPoint(0, 0, -1)
        let across = Map3DPoint(-forward.z, 0, forward.x)
        let roof = Self.pick(Map3DPalette.tinRoofs, r(3))
        let wall = Self.pick(Map3DPalette.shedWalls, r(4))
        let hallLength = lot * (0.62 + r(5) * 0.18), hallWidth = lot * (0.42 + r(6) * 0.14)
        let hall = base - forward * (lot / 2 - hallLength / 2 - 1) + across * ((lot - hallWidth) / 2 - 1) * (r(7) < 0.5 ? -1 : 1)
        var shadows: [(Map3DPoint, Float, Float)] = []
        mesh(at: base) { mesh in
            // The yard.
            let half = lot / 2 + 1
            mesh.addQuad(base + Map3DPoint(-half, 0.03, -half), base + Map3DPoint(-half, 0.03, half),
                         base + Map3DPoint(half, 0.03, half), base + Map3DPoint(half, 0.03, -half), color: Map3DPalette.concrete, paint: Self.concrete)
        }
        let kind = Int(r(1) * 4)
        let far = isFar
        mesh(at: base) { mesh in
            switch kind {
            case 0:
                // A gable shed (the workshops: 12–19°) with roller doors.
                let height = 6.5 + r(8) * 2
                mesh.addBox(base: hall, forward: forward, length: hallLength, width: hallWidth, height: height, top: roof, side: wall,
                            frontPaint: Self.metal, flankPaint: Self.metal, capped: false)
                let pitch = (12 + r(9) * 7) * Float.pi / 180
                mesh.addGableRoof(base: hall + Map3DPoint(0, height, 0), forward: forward, length: hallLength, width: hallWidth,
                                  rise: hallWidth / 2 * tanf(pitch), overhang: 0.5, color: roof, gable: wall, paint: Self.metal)
                if !far { Self.addDoors(&mesh, on: hall, forward: forward, length: hallLength, width: hallWidth, count: 1 + Int(r(10) * 2), height: 4.4) }
            case 1:
                // A sawtooth hall, its glazing to the north light.
                let height = 6 + r(8) * 1.5
                mesh.addBox(base: hall, forward: forward, length: hallLength, width: hallWidth, height: height, top: roof, side: wall,
                            frontPaint: Self.metal, flankPaint: Self.metal, capped: false)
                mesh.addSawtoothRoof(base: hall + Map3DPoint(0, height, 0), forward: forward, length: hallLength, width: hallWidth,
                                     teeth: max(3, Int(hallLength / 7)), rise: 2.4, color: roof, glazing: Map3DPalette.glazing, paint: Self.metal)
                if !far { Self.addDoors(&mesh, on: hall, forward: forward, length: hallLength, width: hallWidth, count: 2, height: 4.2) }
            case 2:
                // An arched warehouse (its walls 5.5 m, the crown a fifth of
                // the span higher) with containers in the yard.
                let height: Float = 5.5
                mesh.addBox(base: hall, forward: forward, length: hallLength, width: hallWidth, height: height, top: roof, side: wall,
                            frontPaint: Self.metal, flankPaint: Self.metal, capped: false)
                mesh.addBarrelRoof(base: hall + Map3DPoint(0, height, 0), forward: forward, length: hallLength + 0.6, width: hallWidth + 0.4,
                                   rise: hallWidth * 0.2, color: roof, end: wall, paint: Self.metal)
                if !far { Self.addDoors(&mesh, on: hall, forward: forward, length: hallLength, width: hallWidth, count: 1, height: 5.2) }
                for index in 0..<(far ? 0 : 1 + Int(r(11) * 3)) {
                    let spot = base + forward * (lot / 2 - 4) + across * (Float(index) * 3 - 3) * (r(7) < 0.5 ? 1 : -1)
                    let color = Self.pick(Map3DPalette.containers, r(Int32(12 + index)))
                    mesh.addBox(base: spot, forward: forward, length: 6.06, width: 2.44, height: 2.59, top: Map3DColor.shaded(color, 1.05), side: color)
                }
            default:
                // An old brick plant: a steep hall (30°), a chimney and two
                // tanks.
                let height = 8 + r(8) * 2
                mesh.addBox(base: hall, forward: forward, length: hallLength, width: hallWidth, height: height, top: roof,
                            side: Map3DPalette.brick, capped: false)
                mesh.addGableRoof(base: hall + Map3DPoint(0, height, 0), forward: forward, length: hallLength, width: hallWidth,
                                  rise: hallWidth / 2 * 0.58, overhang: 0.4, color: Map3DPalette.roof, gable: Map3DPalette.brick, paint: Self.roofing)
                let chimney = hall + forward * (hallLength / 2 + 3) - across * (hallWidth / 2 - 2)
                let stack = 16 + r(10) * 8
                mesh.addBox(base: chimney, forward: forward, length: 2, width: 2, height: stack, top: Map3DColor.rgb(0x5A4E48), side: Map3DPalette.brick)
                mesh.addBox(base: chimney + Map3DPoint(0, stack, 0), forward: forward, length: 2.4, width: 2.4, height: 0.6,
                            top: Map3DColor.rgb(0x5A4E48), side: Map3DColor.shaded(Map3DPalette.brick, 0.8))
                for index in 0..<2 {
                    let spot = hall + forward * (hallLength / 2 + 4) + across * (hallWidth / 2 - 3 - Float(index) * 5)
                    mesh.addCylinder(base: spot, radius: 2, height: 7 + Float(index), sides: 10, top: Map3DPalette.tankSteel, side: Map3DPalette.tankWhite)
                }
            }
            // An office at the front: two storeys, flat, the blue trim of
            // the compact factory office under its parapet.
            let office = base + forward * (lot / 2 - 5) - across * (lot / 2 - 7) * (r(7) < 0.5 ? -1 : 1)
            if kind != 2 {
                let windows = Map3DPaint.bays(.flatWindows, bay: 3.2, floors: 2)
                mesh.addBox(base: office, forward: forward, length: 8, width: 11, height: 6.4, top: Map3DPalette.roof, side: Map3DPalette.tileWhite,
                            topPaint: Self.roofing, frontPaint: windows, flankPaint: windows)
                if !far {
                    mesh.addBox(base: office + Map3DPoint(0, 6.4, 0), forward: forward, length: 8.1, width: 11.1, height: 0.5,
                                top: Map3DPalette.roof, side: Map3DPalette.trimBlue)
                }
            }
        }
        shadows.append((hall, hallLength, hallWidth))
        for (centre, length, width) in shadows {
            addShadow(centre: centre, forward: forward, length: length, width: width, spread: 3, darkness: 0.3)
        }
    }

    /// Roller doors across the front end of a shed `length` along
    /// `forward`, `count` of them side by side.
    static func addDoors(_ mesh: inout Map3DMesh, on hall: Map3DPoint, forward: Map3DPoint, length: Float, width: Float, count: Int, height: Float) {
        let across = Map3DPoint(-forward.z, 0, forward.x)
        let doorWidth = min(5, width / Float(count + 1))
        for index in 0..<count {
            let offset = (Float(index) - Float(count - 1) / 2) * (doorWidth + 1.5)
            mesh.addBox(base: hall + forward * (length / 2 + 0.06) + across * offset, forward: forward, length: 0.12, width: doorWidth,
                        height: height, top: Map3DPalette.rollerDoor, side: Map3DPalette.rollerDoor,
                        frontPaint: .bays(.shutter, bay: doorWidth, floors: 1))
        }
    }

    // MARK: Schools, clinics, public offices

    /// A school (classroom blocks on two sides of a field, a gym), a
    /// clinic or public office (a stone ground storey under tiled
    /// floors, a canopy over the door), or a fire station.
    mutating func addCivic(base: Map3DPoint, side: Float, density: Int, seed: (Int32, Int32)) {
        let r = Self.numbers(seed)
        let lot = max(side - 2, 14)
        let pick = r(1)
        if pick < 0.45 {
            addSchool(base: base, lot: lot, r: r)
        } else if pick < 0.85 {
            addClinic(base: base, lot: lot, floors: 3 + Int(r(2) * Float(min(density, 3) * 2)), r: r)
        } else {
            addFireStation(base: base, lot: lot, r: r)
        }
    }

    mutating func addSchool(base: Map3DPoint, lot: Float, r: (Int32) -> Float) {
        let floors = 3 + Int(r(3) * 2)
        let height = 3.6 * Float(floors)
        let wing: Float = 10
        // Decision 242: classrooms faced with 二丁掛, as Taiwan's schools are.
        let windows = Map3DPaint.bays(.flatWindows, bay: 3.6, floors: floors).on(.brickTile)
        let north = Map3DPoint(0, 0, -1), east = Map3DPoint(1, 0, 0)
        let backBlock = base - north * (wing / 2 - lot / 2), sideBlock = base - east * (lot / 2 - wing / 2) + north * (wing / 2)
        // The rest of the lot: the gym along its south side, the field.
        let open = lot - wing
        let gymWidth: Float = 13, gymLength = open - 2
        let gym = base + east * (wing / 2) + Map3DPoint(0, 0, lot / 2 - gymWidth / 2 - 1)
        let fieldDepth = open - gymWidth - 2
        let field = base + Map3DPoint(wing / 2, 0.035, -lot / 2 + wing + fieldDepth / 2)
        mesh(at: base) { mesh in
            // The field and its track.
            if fieldDepth > 6 {
                let halfX = open / 2 - 1, halfZ = fieldDepth / 2
                mesh.addQuad(field + Map3DPoint(-halfX, 0, -halfZ), field + Map3DPoint(-halfX, 0, halfZ), field + Map3DPoint(halfX, 0, halfZ),
                             field + Map3DPoint(halfX, 0, -halfZ), color: Map3DPalette.track)
                mesh.addQuad(field + Map3DPoint(-halfX + 2.5, 0.01, -halfZ + 2.5), field + Map3DPoint(-halfX + 2.5, 0.01, halfZ - 2.5),
                             field + Map3DPoint(halfX - 2.5, 0.01, halfZ - 2.5), field + Map3DPoint(halfX - 2.5, 0.01, -halfZ + 2.5),
                             color: Map3DPalette.sportsField, paint: Self.grass)
            }
            // Two classroom blocks, cream with a red rim, their corridors
            // toward the field.
            mesh.addBox(base: backBlock, forward: east, length: lot, width: wing, height: height, top: Map3DPalette.roof,
                        side: Map3DPalette.schoolWalls, topPaint: Self.roofing, frontPaint: Self.plaster, flankPaint: windows)
            mesh.addBox(base: sideBlock, forward: north, length: lot - wing, width: wing, height: height, top: Map3DPalette.roof,
                        side: Map3DPalette.schoolWalls, topPaint: Self.roofing, frontPaint: Self.plaster, flankPaint: windows)
            for (block, along, length) in [(backBlock, east, lot), (sideBlock, north, lot - wing)] {
                mesh.addBox(base: block + Map3DPoint(0, height, 0), forward: along, length: length + 0.4, width: wing + 0.4, height: 0.6,
                            top: Map3DPalette.roof, side: Map3DPalette.templeRidge)
            }
            // The gym (the japan pack's: walls to 8 m between brick-red
            // pilasters, an arched metal roof), its roof green or blue.
            if gymLength > 10 {
                let roof = r(8) < 0.5 ? Map3DPalette.gymGreen : Map3DPalette.tinRoofs[0]
                mesh.addBox(base: gym, forward: east, length: gymLength, width: gymWidth, height: 8, top: roof, side: Map3DPalette.schoolWalls,
                            frontPaint: Self.plaster, flankPaint: .bays(.flatWindows, bay: 4, floors: 2), capped: false)
                mesh.addBarrelRoof(base: gym + Map3DPoint(0, 8, 0), forward: east, length: gymLength + 0.8, width: gymWidth + 0.4,
                                   rise: 2.6, color: roof, end: Map3DPalette.schoolWalls, paint: Self.metal)
            }
        }
        addShadow(centre: backBlock, forward: east, length: lot, width: wing, spread: 3, darkness: 0.32)
        addShadow(centre: sideBlock, forward: north, length: lot - wing, width: wing, spread: 3, darkness: 0.32)
        if gymLength > 10 {
            addShadow(centre: gym, forward: east, length: gymLength, width: gymWidth, spread: 3, darkness: 0.3)
        }
    }

    mutating func addClinic(base: Map3DPoint, lot: Float, floors: Int, r: (Int32) -> Float) {
        let length = lot * (0.6 + r(4) * 0.2), width = lot * (0.4 + r(5) * 0.15)
        let forward = r(6) < 0.5 ? Map3DPoint(0, 0, -1) : Map3DPoint(1, 0, 0)
        let ground: Float = 4.4, upper: Float = 3.2
        let height = ground + upper * Float(floors - 1)
        // Decision 242: the floors above in small tiles or fair-faced concrete.
        let upperPaint = Map3DPaint.bays(Self.pick(Map3DSurface.flats, r(7)), bay: 3.2, floors: floors - 1)
            .on(r(8) < 0.5 ? .mosaicTile : .formConcrete)
        let far = isFar
        mesh(at: base) { mesh in
            mesh.addBox(base: base, forward: forward, length: length, width: width, height: ground, top: Map3DPalette.roof, side: Map3DPalette.stone,
                        frontPaint: .bays(.shopfront, bay: 5.4, floors: 1), flankPaint: Self.plaster, capped: false)
            mesh.addBox(base: base + Map3DPoint(0, ground, 0), forward: forward, length: length, width: width, height: height - ground,
                        top: Map3DPalette.roof, side: Map3DPalette.tileWhite, topPaint: Self.roofing, frontPaint: upperPaint, flankPaint: upperPaint)
            // The band over the ground storey, the canopy over the door.
            guard !far else { return }
            mesh.addBox(base: base + Map3DPoint(0, ground - 0.4, 0), forward: forward, length: length + 0.3, width: width + 0.3, height: 0.4,
                        top: Map3DPalette.stone, side: Map3DPalette.stone)
            let across = Map3DPoint(-forward.z, 0, forward.x)
            mesh.addBox(base: base + forward * (length / 2 + 0.7) + Map3DPoint(0, 3.2, 0), forward: across, length: length * 0.4, width: 1.4,
                        height: 0.35, top: Map3DPalette.plant, side: Map3DPalette.trimBlue)
            Self.addRoofPlant(&mesh, on: base + Map3DPoint(0, height, 0), forward: forward, length: length, width: width, r: r, salt: 40)
        }
        addShadow(centre: base, forward: forward, length: length, width: width, spread: 3, darkness: 0.33)
    }

    mutating func addFireStation(base: Map3DPoint, lot: Float, r: (Int32) -> Float) {
        let forward = Map3DPoint(0, 0, -1)
        let length: Float = 14, width = min(lot * 0.7, 24)
        let far = isFar
        mesh(at: base) { mesh in
            let windows = Map3DPaint.bays(.flatWindows, bay: 3.2, floors: 2).on(.brickTile)
            mesh.addBox(base: base, forward: forward, length: length, width: width, height: 4.4, top: Map3DPalette.roof,
                        side: Map3DColor.rgb(0xC9746A), frontPaint: .bays(.shutter, bay: 4.6, floors: 1), flankPaint: Self.plaster, capped: false)
            mesh.addBox(base: base + Map3DPoint(0, 4.4, 0), forward: forward, length: length, width: width, height: 6.6, top: Map3DPalette.roof,
                        side: Map3DPalette.tileWhite, topPaint: Self.roofing, frontPaint: windows, flankPaint: windows)
            // The hose tower.
            mesh.addBox(base: base + Map3DPoint(width / 2 - 2, 0, length / 2 - 2), length: 3.4, width: 3.4, height: 18, top: Map3DPalette.roof,
                        side: Map3DColor.rgb(0xC9746A))
            if !far {
                Self.addRoofPlant(&mesh, on: base + Map3DPoint(0, 11, 0), forward: forward, length: length, width: width, r: r, salt: 50)
            }
        }
        addShadow(centre: base, forward: forward, length: length, width: width, spread: 3, darkness: 0.32)
    }

    // MARK: Sights and amusements

    /// A temple on a granite terrace (a front hall and a main hall with
    /// two-tiered, swept, orange-glazed roofs) or a shopping hall with its
    /// sign band. Decision 268: `front` is the way a temple faces and how
    /// far from the lot's middle the pavement before it begins.
    mutating func addLeisure(base: Map3DPoint, side: Float, seed: (Int32, Int32), front: (forward: Map3DPoint, distance: Float)? = nil) {
        let r = Self.numbers(seed)
        let lot = max(side - 2, 14)
        if r(1) < 0.55 {
            addTemple(base: base, lot: lot, forward: front?.forward ?? Map3DPoint(0, 0, 1), front: front?.distance ?? lot / 2)
        } else {
            addMall(base: base, lot: lot, r: r)
        }
    }

    /// Decision 268: the temple faces `forward` (south, as temples do,
    /// unless a busier street is on another side) with a stone forecourt
    /// (廟埕) between its terrace and the street, a gateway (牌樓) at the
    /// pavement, banyans at the forecourt's corners and red lanterns
    /// under the front eaves that glow at night (HANDOFF §4.3: the
    /// forecourt 34 × 16, the gateway's posts 0.9 × 6 at ±6 m under a
    /// 14 m beam at 5.4 m, the lanterns E0392C).
    mutating func addTemple(base: Map3DPoint, lot: Float, forward: Map3DPoint = Map3DPoint(0, 0, 1), front: Float? = nil) {
        let across = Map3DPoint(-forward.z, 0, forward.x)
        let front = front ?? lot / 2
        // From the street's pavement to the lot's back: the terrace, and
        // the forecourt before it.
        let room = front + lot / 2
        let terrace = max(14, min(lot * 0.85, 34, room - 8))
        let court = max(0, min(16, room - terrace))
        let centre = base + forward * (front - court - terrace / 2)
        let hallLength: Float = 12, hallWidth = min(terrace * 0.6, 18)
        // A front hall only where the terrace has room for a courtyard.
        let hasFrontHall = terrace >= 24
        let mainHall = hasFrontHall ? centre - forward * (terrace / 2 - hallLength / 2 - 1) : centre
        let frontHall = centre + forward * (terrace / 2 - 4.5)
        let gateway = base + forward * (front - 1.2)
        let far = isFar
        mesh(at: base) { mesh in
            mesh.addBox(base: centre, forward: forward, length: terrace, width: terrace, height: 0.6, top: Map3DPalette.granite,
                        side: Map3DColor.shaded(Map3DPalette.granite, 0.9), topPaint: Self.paving)
            // The forecourt, paved in stone from the terrace to the street.
            if court > 1 {
                let near = centre + forward * (terrace / 2), street = base + forward * front
                let half = across * (terrace / 2)
                mesh.addQuad(near + half + Map3DPoint(0, 0.03, 0), street + half + Map3DPoint(0, 0.03, 0),
                             street - half + Map3DPoint(0, 0.03, 0), near - half + Map3DPoint(0, 0.03, 0),
                             color: Map3DPalette.forecourt, paint: Self.paving)
            }
            let floor = Map3DPoint(0, 0.6, 0)
            // The main hall: two roofs, the upper one over a clerestory.
            mesh.addBox(base: mainHall + floor, forward: forward, length: hallLength, width: hallWidth, height: 5.2, top: Map3DPalette.templeWall,
                        side: Map3DPalette.templeWall, capped: false)
            mesh.addHipRoof(base: mainHall + floor + Map3DPoint(0, 5.2, 0), forward: across, length: hallWidth, width: hallLength,
                            rise: 2.6, overhang: 1.8, sweep: 1.0, color: Map3DPalette.templeRoof, paint: Self.roofing)
            mesh.addBox(base: mainHall + floor + Map3DPoint(0, 6.4, 0), forward: forward, length: hallLength * 0.6, width: hallWidth * 0.7,
                        height: 1.6, top: Map3DPalette.templeWall, side: Map3DPalette.templeWall, capped: false)
            mesh.addHipRoof(base: mainHall + floor + Map3DPoint(0, 8, 0), forward: across, length: hallWidth * 0.7,
                            width: hallLength * 0.6, rise: 2.8, overhang: 1.4, sweep: 1.1, color: Map3DPalette.templeRoof, paint: Self.roofing)
            // The ridge, red, its ends swept up like a swallow's tail (燕尾).
            let ridgeLength = max(2, hallWidth * 0.7 + 2.8 - hallLength * 0.6 - 2.8)
            if !far { Self.addSwallowtailRidge(&mesh, middle: mainHall + floor + Map3DPoint(0, 10.8, 0), along: across, length: ridgeLength + 2) }
            guard !far else {
                // Afar, only the front hall's box and roof.
                guard hasFrontHall else { return }
                mesh.addBox(base: frontHall + floor, forward: forward, length: 6, width: hallWidth * 0.9, height: 4.4, top: Map3DPalette.templeWall,
                            side: Map3DPalette.templeWall, capped: false)
                mesh.addHipRoof(base: frontHall + floor + Map3DPoint(0, 4.4, 0), forward: across, length: hallWidth * 0.9, width: 6,
                                rise: 2.4, overhang: 1.5, sweep: 0.9, color: Map3DPalette.templeRoof, paint: Self.roofing)
                return
            }
            // The gateway at the pavement: two red posts, a beam and a
            // little roof.
            if court >= 6 {
                for end: Float in [-1, 1] {
                    mesh.addBox(base: gateway + across * (end * 6), forward: forward, length: 0.9, width: 0.9, height: 6, top: Map3DPalette.templeRidge,
                                side: Map3DPalette.templeRidge)
                }
                mesh.addBox(base: gateway + Map3DPoint(0, 5.4, 0), forward: forward, length: 0.9, width: 14, height: 0.9, top: Map3DPalette.templeWall,
                            side: Map3DPalette.templeWall)
                mesh.addHipRoof(base: gateway + Map3DPoint(0, 6.3, 0), forward: across, length: 14.6, width: 1.8, rise: 0.9, overhang: 0.4,
                                sweep: 0.5, color: Map3DPalette.templeRoof, paint: Self.roofing)
            }
            // The hall the lanterns hang from: the front hall where there is
            // one, else the main hall.
            let eaves = hasFrontHall ? (hall: frontHall, depth: Float(6), width: hallWidth * 0.9, height: Float(3.6))
                : (hall: mainHall, depth: hallLength, width: hallWidth, height: Float(4.2))
            let glow = mesh.vertices.count
            for lantern in 0..<4 {
                let spot = eaves.hall + floor + forward * (eaves.depth / 2 + 0.9) + across * ((Float(lantern) - 1.5) * eaves.width / 4.5)
                mesh.addCylinder(base: spot + Map3DPoint(0, eaves.height, 0), radius: 0.32, height: 0.6, sides: 6, top: Map3DPalette.lantern,
                                 side: Map3DPalette.lantern)
            }
            mesh.makeGlowing(from: glow)
            // The front hall, lower, one roof.
            guard hasFrontHall else { return }
            mesh.addBox(base: frontHall + floor, forward: forward, length: 6, width: hallWidth * 0.9, height: 4.4, top: Map3DPalette.templeWall,
                        side: Map3DPalette.templeWall, capped: false)
            mesh.addHipRoof(base: frontHall + floor + Map3DPoint(0, 4.4, 0), forward: across, length: hallWidth * 0.9, width: 6,
                            rise: 2.4, overhang: 1.5, sweep: 0.9, color: Map3DPalette.templeRoof, paint: Self.roofing)
            Self.addSwallowtailRidge(&mesh, middle: frontHall + floor + Map3DPoint(0, 6.8, 0), along: across,
                                     length: max(2, hallWidth * 0.9 - 6) + 2)
            // The incense burner in the courtyard between them.
            let burner = (mainHall + frontHall) * 0.5 + floor
            mesh.addCylinder(base: burner, radius: 0.8, height: 1.2, sides: 8, top: Map3DColor.rgb(0x6B5A3E), side: Map3DColor.rgb(0x8C7449))
        }
        // Decision 268: a banyan at each of the forecourt's front corners.
        let court0 = base + forward * (front - min(court, 10) / 2)
        if court >= 8, target == .near, let tree = Self.propModels[.tree] {
            for end: Float in [-1, 1] {
                let foot = court0 + across * (end * (terrace / 2 - 2.5))
                props[key(of: foot), default: []].append(.prop(tree, at: foot, forward: forward, scale: 1.7, tint: Map3DProp.greens[1]))
            }
        }
        // Decision 259: worshippers and visitors (decision 268: on the
        // forecourt, more of them where it is wide).
        let middle = base + forward * (front - max(court, 6) / 2) + Map3DPoint(0, 0.05, 0)
        addTempleLife(from: middle - across * (terrace / 2 - 1), to: middle + across * (terrace / 2 - 1),
                      width: max(3, court - 4), people: court >= 10 ? 36 : 12)
        addShadow(centre: mainHall, forward: forward, length: hallLength + 2, width: hallWidth + 2, spread: 3, darkness: 0.3)
    }

    /// A temple ridge `length` long along `along`, red, standing on
    /// `middle`, each end rising into an upturned tail.
    static func addSwallowtailRidge(_ mesh: inout Map3DMesh, middle: Map3DPoint, along: Map3DPoint, length: Float) {
        let across = Map3DPoint(-along.z, 0, along.x)
        mesh.addBox(base: middle, forward: along, length: length, width: 0.5, height: 0.7, top: Map3DPalette.templeRidge, side: Map3DPalette.templeRidge)
        for end: Float in [-1, 1] {
            let foot = middle + along * (end * length / 2)
            let tip = foot + along * (end * 1.4) + Map3DPoint(0, 2.0, 0)
            let a = foot + Map3DPoint(0, 0.7, 0) - across * 0.25, b = foot + Map3DPoint(0, 0.7, 0) + across * 0.25
            let low = foot - across * 0.25, high = foot + across * 0.25
            let ridgeColor = Map3DPalette.templeRidge
            // Two flat fins, back to back, from the ridge's end up to the tip.
            if end > 0 {
                mesh.addFacet([low, tip - across * 0.25, a], color: Map3DColor.shaded(ridgeColor, 0.85))
                mesh.addFacet([high, b, tip + across * 0.25], color: Map3DColor.shaded(ridgeColor, 0.95))
                mesh.addFacet([a, tip - across * 0.25, tip + across * 0.25, b], color: ridgeColor)
            } else {
                mesh.addFacet([low, a, tip - across * 0.25], color: Map3DColor.shaded(ridgeColor, 0.85))
                mesh.addFacet([high, tip + across * 0.25, b], color: Map3DColor.shaded(ridgeColor, 0.95))
                mesh.addFacet([a, b, tip + across * 0.25, tip - across * 0.25], color: ridgeColor)
            }
        }
    }

    mutating func addMall(base: Map3DPoint, lot: Float, r: (Int32) -> Float) {
        let forward = r(2) < 0.5 ? Map3DPoint(0, 0, -1) : Map3DPoint(1, 0, 0)
        let size = lot * 0.85
        let floors = 3 + Int(r(3) * 3)
        let height = 4.6 * Float(floors)
        let sign = Self.pick(Map3DPalette.signs, r(4))
        let far = isFar
        mesh(at: base) { mesh in
            let shops = Map3DPaint.bays(Self.pick(Map3DSurface.shops, r(5)), bay: 5.4, floors: 1)
            mesh.addBox(base: base, forward: forward, length: size, width: size, height: 4.6, top: Map3DPalette.roof, side: Map3DPalette.tileWhite,
                        frontPaint: shops, flankPaint: shops, capped: false)
            mesh.addBox(base: base + Map3DPoint(0, 4.6, 0), forward: forward, length: size, width: size, height: height - 4.6,
                        top: Map3DPalette.roof, side: Map3DPalette.tileWhite, topPaint: Self.roofing, frontPaint: Self.plaster, flankPaint: Self.plaster)
            // A band of colour round the top, and a glass atrium on the front.
            mesh.addBox(base: base + Map3DPoint(0, height - 2.2, 0), forward: forward, length: size + 0.3, width: size + 0.3, height: 1.6,
                        top: sign, side: sign)
            mesh.addBox(base: base + forward * (size / 2), forward: forward, length: 3, width: size * 0.3, height: height - 3,
                        top: Map3DPalette.glazing, side: Map3DPalette.glazing, frontPaint: .bays(.officeGlass, bay: 3, floors: floors))
            if !far {
                Self.addRoofPlant(&mesh, on: base + Map3DPoint(0, height, 0), forward: forward, length: size, width: size, r: r, salt: 60)
            }
        }
        addShadow(centre: base, forward: forward, length: size, width: size, spread: 4, darkness: 0.34)
        // Decision 352: the band's word over the atrium.
        let board = Map3DColor.hex(sign)
        addSign(Map3DSign(kind: .across, centre: base + forward * ((size + 0.3) / 2 + 0.02) + Map3DPoint(0, height - 2.2 + 0.8, 0), facing: forward,
                          width: size * 0.4, height: 1.6 * 0.85, picture: Map3DSignAtlas.word("商場") ?? 0, seed: 0, board: board,
                          letters: Self.letters(on: board), closes: Map3DSignAtlas.closes(Map3DSignAtlas.word("商場") ?? 0, share: r(6))))
    }

    // MARK: Fronts (decision 238)

    /// What stands out of a row house's front, near only: a balcony on
    /// each upper floor of a 透天厝 with balconies, an air conditioner
    /// under some windows of the rest, and a blade sign on a shop (the
    /// japan pack's balconies 0.95–1.05 m deep, its air conditioners
    /// 0.8 m, its blade signs). Decision 352: returns the blade sign's
    /// words.
    @discardableResult
    static func addFrontDetail(_ mesh: inout Map3DMesh, close: inout Map3DMesh, front: Map3DPoint, facing: Map3DPoint, width: Float, groundFloor: Float,
                               upper: Float, floors: Int, wall: UInt32, balconies: Bool, sign: Bool, arcade: Bool = false,
                               r: (Int32) -> Float) -> [Map3DSign] {
        let across = Map3DPoint(-facing.z, 0, facing.x)
        // Decision 267: the arcade's pillars, and a shop's counter, crates
        // and low awning, in `close` (drawn only close up), as are the
        // awnings and washing above.
        addStreetLevel(&close, front: front, facing: facing, width: width, groundFloor: groundFloor, wall: wall, shop: sign, arcade: arcade, r: r)
        for floor in 1..<max(1, floors) {
            let level = Map3DPoint(0, groundFloor + upper * Float(floor - 1), 0)
            // Decision 267: a tin awning over the windows on half the
            // floors, out past a balcony.
            if r(Int32(50 + floor)) < 0.5 {
                addSlope(&close, from: front + level + Map3DPoint(0, 2.45, 0), facing: facing, width: width - 0.8, depth: balconies ? 1.4 : 0.9,
                         drop: 0.33, color: pick(Map3DPalette.tinAwnings, r(Int32(60 + floor))))
            }
            if balconies {
                mesh.addBox(base: front + facing * 0.5 + level, forward: facing, length: 1, width: width - 0.8, height: 1.05,
                            top: Map3DColor.shaded(wall, 0.97), side: Map3DColor.shaded(wall, 0.93))
                // Decision 267: washing on 45% of the balconies: four
                // pieces hung out over the rail.
                if r(Int32(70 + floor)) < 0.45 {
                    for piece in 0..<4 {
                        let spot = front + facing * 1.08 + level + across * ((Float(piece) - 1.5) * min(0.55, (width - 1.2) / 4)) + Map3DPoint(0, 0.45, 0)
                        addPanel(&close, at: spot, facing: facing, width: 0.45, height: 0.6,
                                 color: pick(Map3DPalette.washing, r(Int32(80 + floor * 4 + piece))))
                    }
                }
            } else if r(Int32(20 + floor)) < 0.5 {
                let side: Float = r(Int32(30 + floor)) < 0.5 ? -1 : 1
                mesh.addBox(base: front + facing * 0.2 + across * (side * width / 4) + level + Map3DPoint(0, 0.5, 0), forward: facing,
                            length: 0.35, width: 0.8, height: 0.55, top: Map3DPalette.acUnit, side: Map3DPalette.acUnit)
            }
        }
        guard sign, r(12) < 0.7 else { return [] }
        let height: Float = floors >= 3 ? 3.2 : 2.4
        let foot = front + facing * 0.45 + across * (width / 2 - 0.5) + Map3DPoint(0, groundFloor + 0.3, 0), board = pick(Map3DPalette.signs, r(13))
        mesh.addBox(base: foot, forward: facing, length: 0.7, width: 0.25, height: height, top: Map3DPalette.tileWhite, side: board)
        let word = pick(streetWords, r(14))
        return bladeSigns(middle: foot + Map3DPoint(0, height / 2, 0), facing: facing, height: height, board: Map3DColor.hex(board), word: word,
                          closes: Map3DSignAtlas.closes(word, share: r(15)))
    }

    /// Decision 267: what stands at a row house's foot. Under an arcade
    /// (騎樓), its two pillars at the front corners; at a shop, a counter
    /// with three crates out before the shop front (in the arcade, or on
    /// the pavement) under a low awning sloping out (HANDOFF §4.3: the
    /// counter 0.55 of the width, 0.9 m tall, 0.6 m deep; crates 0.5 ×
    /// 0.35 × 0.35; the awning 2.95 m up, 1.1 m out, falling 0.25 rad).
    static func addStreetLevel(_ mesh: inout Map3DMesh, front: Map3DPoint, facing: Map3DPoint, width: Float, groundFloor: Float, wall: UInt32,
                               shop: Bool, arcade: Bool, r: (Int32) -> Float) {
        let across = Map3DPoint(-facing.z, 0, facing.x)
        if arcade {
            for side: Float in [-1, 1] {
                mesh.addBox(base: front - facing * 0.2 + across * (side * (width / 2 - 0.25)), forward: facing, length: 0.4, width: 0.4,
                            height: groundFloor, top: Map3DColor.shaded(wall, 0.92), side: Map3DColor.shaded(wall, 0.88))
            }
            // Decision 446: a row of scooters parked along its edge.
            Map3DScooter.addParkedRow(&mesh, front: front, facing: facing, width: width, r: r)
        }
        guard shop else { return }
        // The shop front: the arcade's back wall, or the house's face.
        let shopFront = arcade ? front - facing * Self.arcadeDepth : front
        let counterWidth = width * 0.55
        let counter = shopFront + facing * 0.6
        mesh.addBox(base: counter, forward: facing, length: 0.6, width: counterWidth, height: 0.9, top: pick(Map3DPalette.counters, r(40)),
                    side: pick(Map3DPalette.counters, r(40)))
        for crate in 0..<3 {
            let colour = pick(Map3DPalette.crates, r(Int32(41 + crate)))
            mesh.addBox(base: counter + across * ((Float(crate) - 1) * counterWidth / 3) + Map3DPoint(0, 0.9, 0), forward: facing, length: 0.35,
                        width: min(0.5, counterWidth / 3 - 0.05), height: 0.35, top: colour, side: colour)
        }
        // The awning: at the arcade's edge, or over the shop front.
        let height = min(2.95, groundFloor - 0.35)
        addSlope(&mesh, from: (arcade ? front : shopFront) + Map3DPoint(0, height, 0), facing: facing, width: width - 0.3, depth: 1.1, drop: 0.28,
                 color: pick(Map3DPalette.shopAwnings, r(45)))
    }

    /// How far an arcade's ground floor stands back from the house's face
    /// (``addRowHouses``).
    static let arcadeDepth: Float = 3.4

    /// A sloping sheet `width` wide from a wall at `from` (its top edge's
    /// middle), `depth` out along `facing` and `drop` lower there: an
    /// awning, its face up.
    static func addSlope(_ mesh: inout Map3DMesh, from top: Map3DPoint, facing: Map3DPoint, width: Float, depth: Float, drop: Float, color: UInt32) {
        let across = Map3DPoint(-facing.z, 0, facing.x) * (width / 2)
        let out = facing * depth - Map3DPoint(0, drop, 0)
        let corners = [top - across, top + across, top + across + out, top - across + out]
        let up = (corners[1] - corners[0]).cross(corners[3] - corners[0]).y > 0
        mesh.addFacet(up ? corners : corners.reversed(), color: color)
    }

    /// An upright sheet `width` × `height` hanging from `at` (its top
    /// edge's middle), its face toward `facing`: a piece of washing.
    static func addPanel(_ mesh: inout Map3DMesh, at top: Map3DPoint, facing: Map3DPoint, width: Float, height: Float, color: UInt32) {
        let across = Map3DPoint(-facing.z, 0, facing.x) * (width / 2)
        let down = Map3DPoint(0, height, 0)
        let corners = [top - across - down, top + across - down, top + across, top - across]
        let out = (corners[1] - corners[0]).cross(corners[3] - corners[0]).dot(facing) > 0
        mesh.addFacet(out ? corners : corners.reversed(), color: color)
    }

    // MARK: Roofs

    /// What stands on a flat roof `length` along `forward` and `width`
    /// across: a stair house (樓梯間) and one to three air conditioners
    /// (the city pack's clinic and rooftop units).
    static func addRoofPlant(_ mesh: inout Map3DMesh, on roof: Map3DPoint, forward: Map3DPoint, length: Float, width: Float,
                             r: (Int32) -> Float, salt: Int32) {
        guard length > 6, width > 6 else { return }
        let across = Map3DPoint(-forward.z, 0, forward.x)
        let stair = roof + forward * ((r(salt) - 0.5) * (length - 5)) + across * ((r(salt + 1) - 0.5) * (width - 5))
        mesh.addBox(base: stair, forward: forward, length: 3.2, width: 2.6, height: 2.6, top: Map3DPalette.roof, side: Map3DPalette.tileWhite,
                    topPaint: roofing)
        for index in 0..<(1 + Int(r(salt + 2) * 3)) {
            let spot = roof + forward * ((r(salt + 3 + Int32(index)) - 0.5) * (length - 4))
                + across * ((r(salt + 6 + Int32(index)) - 0.5) * (width - 4))
            mesh.addBox(base: spot, forward: forward, length: 1.6, width: 1.2, height: 1.1, top: Map3DColor.shaded(Map3DPalette.plant, 1.05),
                        side: Map3DPalette.plant)
        }
    }
}
