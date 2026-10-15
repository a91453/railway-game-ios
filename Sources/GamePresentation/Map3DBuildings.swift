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
    /// Plant on the roofs: air conditioners, stair houses' doors.
    static let plant = rgbColor(0xA7A39A)
    static let signs: [UInt32] = [rgbColor(0xD9534A), rgbColor(0x3E7CC0), rgbColor(0xF0B847), rgbColor(0x4FA36B)]

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
                Self.addDoors(&mesh, on: hall, forward: forward, length: hallLength, width: hallWidth, count: 1 + Int(r(10) * 2), height: 4.4)
            case 1:
                // A sawtooth hall, its glazing to the north light.
                let height = 6 + r(8) * 1.5
                mesh.addBox(base: hall, forward: forward, length: hallLength, width: hallWidth, height: height, top: roof, side: wall,
                            frontPaint: Self.metal, flankPaint: Self.metal, capped: false)
                mesh.addSawtoothRoof(base: hall + Map3DPoint(0, height, 0), forward: forward, length: hallLength, width: hallWidth,
                                     teeth: max(3, Int(hallLength / 7)), rise: 2.4, color: roof, glazing: Map3DPalette.glazing, paint: Self.metal)
                Self.addDoors(&mesh, on: hall, forward: forward, length: hallLength, width: hallWidth, count: 2, height: 4.2)
            case 2:
                // An arched warehouse (its walls 5.5 m, the crown a fifth of
                // the span higher) with containers in the yard.
                let height: Float = 5.5
                mesh.addBox(base: hall, forward: forward, length: hallLength, width: hallWidth, height: height, top: roof, side: wall,
                            frontPaint: Self.metal, flankPaint: Self.metal, capped: false)
                mesh.addBarrelRoof(base: hall + Map3DPoint(0, height, 0), forward: forward, length: hallLength + 0.6, width: hallWidth + 0.4,
                                   rise: hallWidth * 0.2, color: roof, end: wall, paint: Self.metal)
                Self.addDoors(&mesh, on: hall, forward: forward, length: hallLength, width: hallWidth, count: 1, height: 5.2)
                for index in 0..<(1 + Int(r(11) * 3)) {
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
                mesh.addBox(base: office + Map3DPoint(0, 6.4, 0), forward: forward, length: 8.1, width: 11.1, height: 0.5,
                            top: Map3DPalette.roof, side: Map3DPalette.trimBlue)
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
        let windows = Map3DPaint.bays(.flatWindows, bay: 3.6, floors: floors)
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
        let upperPaint = Map3DPaint.bays(Self.pick(Map3DSurface.flats, r(7)), bay: 3.2, floors: floors - 1)
        mesh(at: base) { mesh in
            mesh.addBox(base: base, forward: forward, length: length, width: width, height: ground, top: Map3DPalette.roof, side: Map3DPalette.stone,
                        frontPaint: .bays(.shopfront, bay: 5.4, floors: 1), flankPaint: Self.plaster, capped: false)
            mesh.addBox(base: base + Map3DPoint(0, ground, 0), forward: forward, length: length, width: width, height: height - ground,
                        top: Map3DPalette.roof, side: Map3DPalette.tileWhite, topPaint: Self.roofing, frontPaint: upperPaint, flankPaint: upperPaint)
            // The band over the ground storey, the canopy over the door.
            mesh.addBox(base: base + Map3DPoint(0, ground - 0.4, 0), forward: forward, length: length + 0.3, width: width + 0.3, height: 0.4,
                        top: Map3DPalette.stone, side: Map3DPalette.stone)
            let across = Map3DPoint(-forward.z, 0, forward.x)
            mesh.addBox(base: base + forward * (width / 2 + 0.7) + Map3DPoint(0, 3.2, 0), forward: across, length: length * 0.4, width: 1.4,
                        height: 0.35, top: Map3DPalette.plant, side: Map3DPalette.trimBlue)
            Self.addRoofPlant(&mesh, on: base + Map3DPoint(0, height, 0), forward: forward, length: length, width: width, r: r, salt: 40)
        }
        addShadow(centre: base, forward: forward, length: width, width: length, spread: 3, darkness: 0.33)
    }

    mutating func addFireStation(base: Map3DPoint, lot: Float, r: (Int32) -> Float) {
        let forward = Map3DPoint(0, 0, -1)
        let length: Float = 14, width = min(lot * 0.7, 24)
        mesh(at: base) { mesh in
            let windows = Map3DPaint.bays(.flatWindows, bay: 3.2, floors: 2)
            mesh.addBox(base: base, forward: forward, length: length, width: width, height: 4.4, top: Map3DPalette.roof,
                        side: Map3DColor.rgb(0xC9746A), frontPaint: .bays(.shutter, bay: 4.6, floors: 1), flankPaint: Self.plaster, capped: false)
            mesh.addBox(base: base + Map3DPoint(0, 4.4, 0), forward: forward, length: length, width: width, height: 6.6, top: Map3DPalette.roof,
                        side: Map3DPalette.tileWhite, topPaint: Self.roofing, frontPaint: windows, flankPaint: windows)
            // The hose tower.
            mesh.addBox(base: base + Map3DPoint(width / 2 - 2, 0, length / 2 - 2), length: 3.4, width: 3.4, height: 18, top: Map3DPalette.roof,
                        side: Map3DColor.rgb(0xC9746A))
            Self.addRoofPlant(&mesh, on: base + Map3DPoint(0, 11, 0), forward: forward, length: length, width: width, r: r, salt: 50)
        }
        addShadow(centre: base, forward: forward, length: length, width: width, spread: 3, darkness: 0.32)
    }

    // MARK: Sights and amusements

    /// A temple on a granite terrace (a front hall and a main hall with
    /// two-tiered, swept, orange-glazed roofs) or a shopping hall with its
    /// sign band.
    mutating func addLeisure(base: Map3DPoint, side: Float, seed: (Int32, Int32)) {
        let r = Self.numbers(seed)
        let lot = max(side - 2, 14)
        if r(1) < 0.55 {
            addTemple(base: base, lot: lot)
        } else {
            addMall(base: base, lot: lot, r: r)
        }
    }

    mutating func addTemple(base: Map3DPoint, lot: Float) {
        let forward = Map3DPoint(0, 0, 1) // facing south, as temples do
        let terrace = min(lot * 0.85, 34)
        let hallLength: Float = 12, hallWidth = min(terrace * 0.6, 18)
        // A front hall only where the terrace has room for a courtyard.
        let hasFrontHall = terrace >= 24
        let mainHall = hasFrontHall ? base - forward * (terrace / 2 - hallLength / 2 - 1) : base
        let frontHall = base + forward * (terrace / 2 - 4.5)
        mesh(at: base) { mesh in
            mesh.addBox(base: base, forward: forward, length: terrace, width: terrace, height: 0.6, top: Map3DPalette.granite,
                        side: Map3DColor.shaded(Map3DPalette.granite, 0.9), topPaint: Self.paving)
            let floor = Map3DPoint(0, 0.6, 0)
            // The main hall: two roofs, the upper one over a clerestory.
            mesh.addBox(base: mainHall + floor, forward: forward, length: hallLength, width: hallWidth, height: 5.2, top: Map3DPalette.templeWall,
                        side: Map3DPalette.templeWall, capped: false)
            mesh.addHipRoof(base: mainHall + floor + Map3DPoint(0, 5.2, 0), forward: Map3DPoint(1, 0, 0), length: hallWidth, width: hallLength,
                            rise: 2.6, overhang: 1.8, sweep: 1.0, color: Map3DPalette.templeRoof, paint: Self.roofing)
            mesh.addBox(base: mainHall + floor + Map3DPoint(0, 6.4, 0), forward: forward, length: hallLength * 0.6, width: hallWidth * 0.7,
                        height: 1.6, top: Map3DPalette.templeWall, side: Map3DPalette.templeWall, capped: false)
            mesh.addHipRoof(base: mainHall + floor + Map3DPoint(0, 8, 0), forward: Map3DPoint(1, 0, 0), length: hallWidth * 0.7,
                            width: hallLength * 0.6, rise: 2.8, overhang: 1.4, sweep: 1.1, color: Map3DPalette.templeRoof, paint: Self.roofing)
            // The ridge, red, its ends swept up like a swallow's tail (燕尾).
            let ridgeLength = max(2, hallWidth * 0.7 + 2.8 - hallLength * 0.6 - 2.8)
            Self.addSwallowtailRidge(&mesh, middle: mainHall + floor + Map3DPoint(0, 10.8, 0), along: Map3DPoint(1, 0, 0), length: ridgeLength + 2)
            // The front hall, lower, one roof.
            guard hasFrontHall else { return }
            mesh.addBox(base: frontHall + floor, forward: forward, length: 6, width: hallWidth * 0.9, height: 4.4, top: Map3DPalette.templeWall,
                        side: Map3DPalette.templeWall, capped: false)
            mesh.addHipRoof(base: frontHall + floor + Map3DPoint(0, 4.4, 0), forward: Map3DPoint(1, 0, 0), length: hallWidth * 0.9, width: 6,
                            rise: 2.4, overhang: 1.5, sweep: 0.9, color: Map3DPalette.templeRoof, paint: Self.roofing)
            Self.addSwallowtailRidge(&mesh, middle: frontHall + floor + Map3DPoint(0, 6.8, 0), along: Map3DPoint(1, 0, 0),
                                     length: max(2, hallWidth * 0.9 - 6) + 2)
            // The incense burner in the courtyard between them.
            let burner = (mainHall + frontHall) * 0.5 + floor
            mesh.addCylinder(base: burner, radius: 0.8, height: 1.2, sides: 8, top: Map3DColor.rgb(0x6B5A3E), side: Map3DColor.rgb(0x8C7449))
        }
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
            Self.addRoofPlant(&mesh, on: base + Map3DPoint(0, height, 0), forward: forward, length: size, width: size, r: r, salt: 60)
        }
        addShadow(centre: base, forward: forward, length: size, width: size, spread: 4, darkness: 0.34)
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
