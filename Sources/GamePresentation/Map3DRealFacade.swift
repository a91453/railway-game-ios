import GameCore

// Decision 610 (FACADE-REAL, NEXT_PRIORITIES §24.6 7a): the real
// buildings' outlines (decisions 239 and 389, some 1.96 million) close up
// on the side that looks onto a street: arcade pillars (騎樓), window
// grilles (鐵窗), air conditioners, blade signs (直式招牌) and rooftop rooms
// (頂樓加蓋). Decision 267's parts and colours, on the walls decision 352
// finds facing a street (`adWalls`, `facesStreet`), in sizes and shares from
// the Taipei streetscape spec (`Railway/slop-taipei-reference-clean`,
// `TAIWAN_STREETSCAPE.md` §c.1, §c.8, §c.12). No models made by hand; the
// same every time for the same building (seeded where it stands on the map).

/// Decision 610: when the 3D map draws the real buildings' street fronts.
public enum Map3DRealFacade {
    /// Whether the map draws them: not when it draws fewer pixels (Battery
    /// Saver, Low Power Mode or a hot phone, ``Map3DQuality/plan(lowPower:heat:)``)
    /// nor on the lowest tier's rungs, where an older device starts and
    /// memory running short steps down to (decision 417's ``Map3DLoadGovernor/relieve()``).
    public static func draws(quality: Map3DQuality, lowPower: Bool, heat: Map3DQuality.Heat, tier: Map3DDeviceTier?) -> Bool {
        guard let tier, tier > .lower else { return false }
        return !quality.plan(lowPower: lowPower, heat: heat).fewerPixels
    }

    /// Decision 610 續 (review L12-1): whether the map may ever draw them
    /// on this device with this 3D look: only above the lowest tier, the
    /// highest rung it climbs to (``Map3DQuality/tier(device:)``). The scene
    /// is built without them when not, so their memory is not kept; Low
    /// Power Mode and heat change while the map is open, so they only stop
    /// the drawing (``draws(quality:lowPower:heat:tier:)``).
    public static func mayDraw(quality: Map3DQuality, device: Map3DDeviceTier?) -> Bool {
        guard let tier = quality.tier(device: device) else { return false }
        return tier > .lower
    }

    /// Decision 610 續 (review L12-2): the most chunks' street fronts the
    /// 3D map puts on the GPU in one frame (each at most some 0.9 MB).
    public static let uploadsAFrame = 2

    /// A shopfront's bay along a street wall (§c.1: columns 4–6 m apart).
    static let bay: Float = 5
    /// The most bays a wall is given, and walls a building.
    static let mostBays = 24
    static let mostWalls = 4
    /// The lowest floors above the ground floor that get grilles and air
    /// conditioners: a walk-up's (§c.12's 1970s–90s four- and five-storey
    /// homes); a tower's upper floors are seen from far below.
    static let floorsDrawn = 3
    /// §c.12: a grille on 50–70% of a home's windows.
    static let grilleShare: Float = 0.6
    /// An air conditioner under most windows without one.
    static let conditionerShare: Float = 0.2
    /// §c.8: 0–2 blade signs a shopfront.
    static let signShare: Float = 0.55
    /// §c.12: a rooftop room on 30–50% of older walk-ups.
    static let roomShare: Float = 0.4
    /// The most triangles of street fronts a chunk holds: two thirds of
    /// decision 267's closest detail's busiest chunk round Banqiao
    /// (15,534), so the two together stay under twice it. Over it, a
    /// chunk keeps its buildings' fronts in the order of a number seeded
    /// where each stands (``Map3DScene/Builder/facadeRank``), whatever
    /// order they were built in, so a chunk built alone (decision 358)
    /// keeps the same ones.
    public static let chunkBudget = 10_000
    /// §c.12: grilles' dark grey-green metal.
    static let grille = Map3DColor.rgb(0x4A544E)
    /// §c.12: a rooftop room's corrugated walls, pale green, grey or white.
    static let roomWalls: [UInt32] = [Map3DColor.rgb(0xC6D6C3), Map3DColor.rgb(0xCDD0CC), Map3DColor.rgb(0xE6E5DE)]
}

extension Map3DScene.Builder {
    /// Decision 610: the street cells (``streetCells(within:)``) round the
    /// part of the region built in full: within ``Map3DScene/detailRadius``
    /// of ``detail`` and a chunk more, or all of it.
    func facadeStreetCells() -> Set<Map3DScene.ChunkKey> {
        let a = point(x: region.minX, y: region.minY, height: 0), b = point(x: region.maxX, y: region.maxY, height: 0)
        var low = Map3DPoint(min(a.x, b.x), 0, min(a.z, b.z)), high = Map3DPoint(max(a.x, b.x), 0, max(a.z, b.z))
        if let detail {
            let reach = Map3DScene.detailRadius + Map3DScene.chunkSize
            low = Map3DPoint(max(low.x, detail.x - reach), 0, max(low.z, detail.z - reach))
            high = Map3DPoint(min(high.x, detail.x + reach), 0, min(high.z, detail.z + reach))
        }
        guard low.x < high.x, low.z < high.z else { return [] }
        return streetCells(within: [(low, high)])
    }

    /// What a real building's ground floor has on its streets.
    struct FrontStreetLevel {
        /// Arcade pillars at its bays (a shophouse's, or flats' over shops).
        var arcade = false
        /// Shops, with blade signs.
        var shops = false
        /// Its height, metres (0: homes to the ground).
        var height: Float = 0
    }

    /// Decision 610: the street fronts of the real building of `outline`
    /// (scene points, level) standing `height` metres on `ground` at
    /// `centre`, of `storeys` and `kind`, its walls `wall`, `street` its
    /// ground floor, `rooms` whether a rooftop room may stand on it (none
    /// stands there yet). Into ``Map3DScene/Chunk/facade``, only while
    /// ``facadeStreets`` is set and its chunk is built in full.
    mutating func addRealFacade(_ outline: [Map3DPoint], centre: Map3DPoint, ground: Float, height: Float, storeys: Int, kind: RealKind,
                                wall: UInt32, street: FrontStreetLevel, rooms: Bool, r: (Int32) -> Float) {
        guard buildsFacades, let streets = facadeStreets, outline.count >= 3, !isCoarse(key(of: centre)) else { return }
        let homes: Bool
        switch kind {
        case .shophouse, .house: homes = true
        case .flats: homes = storeys <= 7
        case .office: homes = false
        default: return
        }
        let walls = Self.adWalls(outline) { Self.facesStreet(streets, middle: $0, normal: $1) }.filter { $0.street && $0.length >= 3 }
        guard !walls.isEmpty else { return }
        let above = street.height > 0 ? max(0, storeys - 1) : storeys
        let storey = above > 0 ? (height - street.height) / Float(above) : 0
        let polygon = [outline]
        var front = Map3DMesh()
        for (index, side) in walls.sorted(by: { $0.length > $1.length }).prefix(Map3DRealFacade.mostWalls).enumerated() {
            let count = min(Map3DRealFacade.mostBays, max(1, Int((side.length / Map3DRealFacade.bay).rounded())))
            let bay = side.length / Float(count)
            let along = side.direction, out = side.normal
            for at in 0..<count {
                let salt = Int32(1_000 + index * 2_000 + at * 64)
                let foot = side.start + along * (bay * (Float(at) + 0.5)) + Map3DPoint(0, ground, 0)
                // The ground floor: a pillar at each bay's edge, the wall's
                // ends kept inside its corners (§c.1: 0.4–0.6 m square).
                if street.arcade, street.height > 0 {
                    for edge in at == count - 1 ? [Float(0), 1] : [0] {
                        let inset: Float = at == 0 && edge == 0 ? 0.3 : at == count - 1 && edge == 1 ? -0.3 : 0
                        let spot = side.start + along * (bay * (Float(at) + edge) + inset) + out * 0.25 + Map3DPoint(0, ground, 0)
                        Self.addStub(&front, base: spot, out: out, depth: 0.5, width: 0.5, height: street.height,
                                     top: Map3DColor.shaded(wall, 0.92), side: Map3DColor.shaded(wall, 0.88))
                    }
                }
                // §c.8: a blade sign at the bay's edge, 0.9–1.4 m out,
                // 2–4.5 m tall from just over the ground floor.
                if street.shops, street.height > 0, above > 0, r(salt) < Map3DRealFacade.signShare {
                    let reach = 0.9 + 0.5 * r(salt + 1)
                    let tall = min(2 + 2.5 * r(salt + 2), height - street.height - 0.6)
                    if tall >= 1.5 {
                        let spot = foot + along * (bay / 2 - 0.6) + out * (reach / 2) + Map3DPoint(0, street.height + 0.3, 0)
                        let board = Self.pick(Map3DPalette.signs, r(salt + 3))
                        Self.addStub(&front, base: spot, out: out, depth: reach, width: 0.25, height: tall, top: Map3DPalette.tileWhite, side: board)
                    }
                }
                // The floors above: a grille over a home's window (and a
                // tin awning over some), or an air conditioner.
                guard storey >= 2.4 else { continue }
                for floor in 0..<min(above, Map3DRealFacade.floorsDrawn) {
                    let level = foot + Map3DPoint(0, street.height + storey * Float(floor), 0)
                    let roll = r(salt + 4 + Int32(floor) * 4)
                    if homes, roll < Map3DRealFacade.grilleShare {
                        let width = min(2.6, bay - 1.4), tall = min(1.5, storey - 1.3)
                        guard width >= 0.8, tall >= 0.8 else { continue }
                        Self.addStub(&front, base: level + out * 0.15 + Map3DPoint(0, 0.9, 0), out: out, depth: 0.3, width: width, height: tall,
                                     top: Map3DColor.shaded(Map3DRealFacade.grille, 1.15), side: Map3DRealFacade.grille, frontPaint: Self.metal)
                        if r(salt + 5 + Int32(floor) * 4) < 0.35 {
                            Self.addSlope(&front, from: level + out * 0.02 + Map3DPoint(0, min(2.55, storey - 0.2), 0), facing: out, width: width + 0.4,
                                          depth: 0.55, drop: 0.18, color: Self.pick(Map3DPalette.tinAwnings, r(salt + 6 + Int32(floor) * 4)))
                        }
                    } else if homes, roll < Map3DRealFacade.grilleShare + Map3DRealFacade.conditionerShare {
                        let shift: Float = r(salt + 7 + Int32(floor) * 4) < 0.5 ? -1 : 1
                        Self.addStub(&front, base: level + along * (shift * bay / 4) + out * 0.2 + Map3DPoint(0, 0.5, 0), out: out,
                                     depth: 0.35, width: 0.8, height: 0.55, top: Map3DPalette.acUnit, side: Map3DPalette.acUnit)
                    }
                }
                // §c.12: a sheet-steel room on the roof, set back from the
                // parapet, under a pent roof falling to the street.
                guard homes, rooms, storeys <= 6, r(salt + 60) < Map3DRealFacade.roomShare else { continue }
                let deep = 3 + 1.5 * r(salt + 61), wide = bay - 0.6
                let middle = foot - out * (0.6 + deep / 2) + Map3DPoint(0, height, 0)
                let corners = [middle + out * (deep / 2) + along * (wide / 2), middle + out * (deep / 2) - along * (wide / 2),
                               middle - out * (deep / 2) + along * (wide / 2), middle - out * (deep / 2) - along * (wide / 2)]
                guard corners.allSatisfy({ Self.inside($0, polygon) }) else { continue }
                let tin = Self.pick(Map3DPalette.tinRoofs, r(salt + 62))
                front.addBox(base: middle, forward: out, length: deep, width: wide, height: 2.4, top: tin,
                             side: Self.pick(Map3DRealFacade.roomWalls, r(salt + 63)), frontPaint: Self.metal, flankPaint: Self.metal, capped: false)
                Self.addSlope(&front, from: middle - out * (deep / 2 + 0.15) + Map3DPoint(0, 2.9, 0), facing: out, width: wide + 0.3,
                              depth: deep + 0.3, drop: 0.5, color: tin)
            }
        }
        guard !front.isEmpty else { return }
        facadeParts[key(of: centre), default: []].append((r(999), front))
    }

    /// Decision 610: the street fronts of each chunk into its ``Map3DScene/Chunk/facade``,
    /// those of the lowest ranks first, up to ``Map3DRealFacade/chunkBudget``
    /// triangles.
    mutating func addFacadeParts() {
        for (key, parts) in facadeParts {
            var kept = Map3DMesh()
            for part in parts.sorted(by: { ($0.rank, $0.mesh.triangleCount) < ($1.rank, $1.mesh.triangleCount) }) {
                guard kept.triangleCount + part.mesh.triangleCount <= Map3DRealFacade.chunkBudget else { continue }
                kept.append(part.mesh)
            }
            facadeMeshes[key, default: Map3DMesh()].append(kept)
        }
        facadeParts = [:]
    }

    /// Decision 610: a box `depth` out from a wall along `out`, `width`
    /// along it and `height` up, standing on `base` (its middle): its top,
    /// its face (painted `frontPaint`) and its two flanks, shaded as
    /// ``Map3DMesh/addBox(base:forward:length:width:height:top:side:topPaint:frontPaint:flankPaint:capped:shaded:)``'s,
    /// but no back against the wall, which nothing sees: 8 triangles.
    static func addStub(_ mesh: inout Map3DMesh, base: Map3DPoint, out: Map3DPoint, depth: Float, width: Float, height: Float,
                        top: UInt32, side: UInt32, frontPaint: Map3DPaint? = nil) {
        guard depth > 0, width > 0, height > 0, let along = Map3DPoint(out.x, 0, out.z).normalized else { return }
        let across = Map3DPoint(-along.z, 0, along.x)
        let f = along * (depth / 2), r = across * (width / 2), h = Map3DPoint(0, height, 0)
        let corners = [base + f - r, base + f + r, base - f + r, base - f - r]
        let up = corners.map { $0 + h }
        mesh.addQuad(up[0], up[3], up[2], up[1], color: top)
        mesh.addQuad(corners[1], corners[0], up[0], up[1], color: Map3DColor.shaded(side, 0.92), paint: frontPaint)
        mesh.addQuad(corners[2], corners[1], up[1], up[2], color: Map3DColor.shaded(side, 0.80))
        mesh.addQuad(corners[0], corners[3], up[3], up[0], color: Map3DColor.shaded(side, 0.86))
    }
}
