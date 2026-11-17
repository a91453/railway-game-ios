import GameCore

// Decision 817 (FACADE-VARIETY, NEXT_PRIORITIES §29.14 item 1): the city's
// towers in more than one kind of window. Until now every tower of flats
// had the one grid of windows (`flatWindows`, `flatBlinds`) and every
// office the one curtain wall (`officeGlass`), each 3.2 m or 3 m a bay
// and a floor of the data's every 3.2 m: towers read as graph paper. Now
// a tower of flats has balconies with full-height glass doors and air
// conditioners, or the grid; an office ribbon windows, a curtain wall
// with its spandrel bands, vertical sun fins, or the plain curtain wall;
// a Hong Kong tower its dense windows with bay windows. Each tower's bay,
// floor height and the bays on its narrow sides are its own, seeded where
// it stands. The five new kinds are five layers more of the atlas
// (`tools/map3d-facades/layers.py`): every building takes them, near or
// far, at no triangle. Near (where decision 610's street fronts are
// built), the balconies' parapets, the fins and the stacked bay windows
// stand out of the wall as boxes, within a budget of their own a chunk.
// Proportions after the owner's Taipei city packs: `Railway/tw3d-reference-clean`
// `js/taipei-facades.js` (a home's floor 3.15 m, an office's 3.85 m; a
// bay 3.1 m on a tower, 2.4 m on an office, 1.55 m on a glass tower;
// balconies on a third of a tower's bays) and `Railway/slop-taipei-reference-clean`
// Taipei_Basin_3D_Clean `js/buildings.js` (curtain walls 2.5–2.9 m a bay
// and 3.8–4.1 m a floor; walk-up slabs 2.05 m and 3.1 m; ribbon windows
// 3.6 m), MIT (slop-newyork).

/// Decision 817: the kinds of windows a tower may have.
public enum Map3DFacadeStyle: CaseIterable, Sendable {
    /// Flats' windows in a grid (``Map3DSurface/flats``), as before.
    case grid
    /// A tower of flats (大樓住宅): balconies, full-height glass doors,
    /// air conditioners.
    case balconies
    /// An office's ribbon windows (帶狀窗).
    case ribbon
    /// A curtain wall with its spandrel bands (窗間橫帶).
    case curtain
    /// An office behind vertical sun fins (直條遮陽鰭).
    case fins
    /// A curtain wall of glass alone (``Map3DSurface/officeGlass``), as before.
    case glass
    /// Hong Kong's dense windows with bay windows (密窗加凸窗).
    case hongKong

    /// The layer its walls are painted with; a grid picks one of the
    /// flats'.
    func surface(_ share: Float) -> Map3DSurface {
        switch self {
        case .grid: Map3DScene.Builder.pick(Map3DSurface.flats, share)
        case .balconies: .flatBalconies
        case .ribbon: .officeRibbon
        case .curtain: .curtainSpandrel
        case .fins: .officeFins
        case .glass: .officeGlass
        case .hongKong: .hkWindows
        }
    }

    /// The narrowest and widest of its bays, metres, and the lowest and
    /// highest of its floors as its windows are drawn.
    var bays: ClosedRange<Float> {
        switch self {
        case .grid: 2.8...3.6
        case .balconies: 3.0...4.0
        case .ribbon: 3.6...4.8
        case .curtain: 2.5...3.2
        case .fins: 2.4...3.2
        case .glass: 2.6...3.4
        case .hongKong: 2.4...3.0
        }
    }

    var storeys: ClosedRange<Float> {
        switch self {
        case .grid: 2.9...3.3
        case .balconies: 3.0...3.4
        case .ribbon, .fins: 3.6...4.0
        case .curtain, .glass: 3.8...4.2
        case .hongKong: 2.8...3.1
        }
    }

    /// Whether it is an office's.
    var isOffice: Bool { [.ribbon, .curtain, .fins, .glass].contains(self) }
}

/// Decision 817: how one tower's walls are painted.
public struct Map3DFacadeLook: Equatable, Sendable {
    public var style: Map3DFacadeStyle
    public var surface: Map3DSurface
    /// A bay on its broad walls, metres.
    public var bay: Float
    /// A bay on its narrow walls (fewer windows there, or as many).
    public var sideBay: Float
    /// A floor's height as its windows are drawn, metres.
    public var storey: Float

    /// The paint of a wall `high` metres high over `detail` (decision
    /// 242's material): whole bays across and floors up.
    func paint(high: Float, detail: Map3DSurface?, side: Bool = false) -> Map3DPaint {
        Map3DPaint.bays(surface, bay: side ? sideBay : bay, floors: floors(high)).on(detail)
    }

    /// The floors of windows a wall `high` metres high holds.
    func floors(_ high: Float) -> Int { max(1, Int((high / storey).rounded())) }
}

public enum Map3DFacadeVariety {
    /// The fewest storeys a block of flats has to take a tower's windows
    /// (lower ones keep decision 610's walk-up fronts), and an office.
    static let flatsStoreys = 8
    static let officeStoreys = 5

    /// How much wider a narrow wall's bays may be than its broad walls':
    /// as many windows, a third fewer, or half as many.
    static let sideBays: [Float] = [1, 1.5, 2]

    /// A wall under this share of its building's longest wall is a narrow
    /// one (``Map3DFacadeLook/sideBay``).
    static let narrowShare: Float = 0.6

    /// Decision 817: how a building of `kind` and `storeys` is painted, or
    /// `nil` for one not a tower (and on a northern map, decision 802's
    /// own). `solid` is whether an office is faced in concrete or stone
    /// rather than glass; `r` its seeded numbers.
    static func look(_ kind: Map3DScene.Builder.RealKind, storeys: Int, hongKong: Bool, nordic: Bool, solid: Bool,
                     r: (Int32) -> Float) -> Map3DFacadeLook? {
        guard !nordic else { return nil }
        let roll = r(817)
        let style: Map3DFacadeStyle
        switch kind {
        case .flats, .shophouse:
            guard storeys >= (hongKong ? Map3DHongKong.towerStoreys : flatsStoreys) else { return nil }
            if hongKong {
                style = roll < 0.65 ? .hongKong : roll < 0.85 ? .balconies : .grid
            } else {
                style = roll < 0.5 ? .balconies : .grid
            }
        case .office:
            guard storeys >= officeStoreys else { return nil }
            if solid {
                style = roll < 0.6 ? .ribbon : .fins
            } else {
                style = roll < 0.4 ? .curtain : roll < 0.7 ? .glass : .fins
            }
        default:
            return nil
        }
        return look(style, r: r)
    }

    /// `style`'s look for one building, its bays and floors seeded by `r`.
    static func look(_ style: Map3DFacadeStyle, r: (Int32) -> Float) -> Map3DFacadeLook {
        func within(_ range: ClosedRange<Float>, _ share: Float) -> Float { range.lowerBound + (range.upperBound - range.lowerBound) * share }
        let bay = within(style.bays, r(818))
        // Hong Kong's towers have windows round every side.
        let side = style == .hongKong ? 1 : Map3DScene.Builder.pick(sideBays, r(820))
        return Map3DFacadeLook(style: style, surface: style.surface(r(3)), bay: bay, sideBay: bay * side,
                               storey: within(style.storeys, r(819)))
    }

    /// Decision 817: the most triangles of towers' reliefs a chunk holds,
    /// beside decision 610's street fronts (``Map3DRealFacade/chunkBudget``).
    public static let chunkBudget = 8_000
    /// The most bays of a wall that take a relief, and walls a tower.
    static let mostBays = 24
    static let mostWalls = 8
    /// The shortest wall that takes a relief, metres.
    static let shortestWall: Float = 6
    /// A balcony's depth and its parapet's height, metres; a fin's depth
    /// and width; a bay window's depth and its share of the bay.
    static let balconyDepth: Float = 1.2
    static let parapetHeight: Float = 1.1
    static let finDepth: Float = 0.7
    static let finWidth: Float = 0.3
    static let bayWindowDepth: Float = 0.55
    static let bayWindowShare: Float = 0.55
}

extension Map3DScene.Builder {
    /// Decision 817: what stands out of a tower's walls, near: the
    /// parapets of its balconies on each floor (on runs of bays, the same
    /// up the tower), its fins at each bay's edge, its stacked bay
    /// windows (Hong Kong's), or a sill under each ribbon of windows.
    /// `outline` is its outer ring (scene points, level), its windows
    /// `look` from `bottom` (its ground floor's top) to `top`.
    mutating func addTowerRelief(_ outline: [Map3DPoint], centre: Map3DPoint, bottom: Float, top: Float, look: Map3DFacadeLook, wall: UInt32,
                                 r: (Int32) -> Float) {
        guard buildsFacades, facadeStreets != nil, outline.count >= 3, top - bottom >= 6, !isCoarse(key(of: centre)) else { return }
        guard [.balconies, .fins, .hongKong, .ribbon].contains(look.style) else { return }
        var walls: [(start: Map3DPoint, end: Map3DPoint, out: Map3DPoint, length: Float)] = []
        for (at, a) in outline.enumerated() {
            let b = outline[(at + 1) % outline.count]
            let flat = Map3DPoint(b.x - a.x, 0, b.z - a.z)
            guard flat.length >= Map3DFacadeVariety.shortestWall, let direction = flat.normalized else { continue }
            var out = Map3DPoint(direction.z, 0, -direction.x)
            let middle = a + flat * 0.5
            if Self.inside(Map3DPoint(middle.x + out.x * 0.3, 0, middle.z + out.z * 0.3), [outline]) { out = out * -1 }
            walls.append((Map3DPoint(a.x, 0, a.z), Map3DPoint(b.x, 0, b.z), out, flat.length))
        }
        guard let longest = walls.map(\.length).max() else { return }
        let floors = look.floors(top - bottom)
        let storey = (top - bottom) / Float(floors)
        // A bay window's sides darker still (model-look round 2: without
        // it, a stack read as a stripe painted on the wall).
        let light = Map3DColor.shaded(wall, 1.04), flank = Map3DColor.shaded(wall, 0.97), shade = Map3DColor.shaded(wall, 0.84)
        var relief = Map3DMesh()
        for (index, face) in walls.sorted(by: { $0.length > $1.length }).prefix(Map3DFacadeVariety.mostWalls).enumerated() {
            let narrow = face.length < longest * Map3DFacadeVariety.narrowShare
            let count = min(Map3DFacadeVariety.mostBays, max(1, Int((face.length / (narrow ? look.sideBay : look.bay)).rounded())))
            let bay = face.length / Float(count)
            // Measured from where the texture's first bay starts: its u
            // grows to the right seen from outside.
            let right = Map3DPoint.up.cross(face.out)
            let (first, direction) = (face.end - face.start).dot(right) >= 0
                ? (face.start, (face.end - face.start) * (1 / face.length)) : (face.end, (face.start - face.end) * (1 / face.length))
            func spot(_ along: Float, _ y: Float, _ depth: Float) -> Map3DPoint {
                first + direction * along + face.out * (depth / 2) + Map3DPoint(0, y, 0)
            }
            let out = face.out
            let salt = Int32(2_000 + index * 97)
            switch look.style {
            case .balconies:
                // Runs of two bays, a balcony on most; none on a narrow wall.
                guard !narrow else { continue }
                var runs: [(from: Int, to: Int)] = []
                for pair in stride(from: 0, to: count, by: 2) where r(salt + Int32(pair)) < 0.7 {
                    let end = min(count, pair + 2)
                    if let last = runs.last, last.to == pair { runs[runs.count - 1].to = end } else { runs.append((pair, end)) }
                }
                for run in runs {
                    let from = Float(run.from) * bay + 0.3, to = Float(run.to) * bay - 0.3
                    guard to - from >= 1.5 else { continue }
                    for floor in 0..<floors {
                        Self.addLedge(&relief, base: spot((from + to) / 2, bottom + storey * Float(floor), Map3DFacadeVariety.balconyDepth),
                                      out: out, depth: Map3DFacadeVariety.balconyDepth, width: to - from,
                                      height: min(Map3DFacadeVariety.parapetHeight, storey * 0.4), top: light, front: flank)
                    }
                }
            case .fins:
                for edge in 0...count {
                    let along = min(max(Float(edge) * bay, 0.2), face.length - 0.2)
                    Self.addStub(&relief, base: spot(along, bottom, Map3DFacadeVariety.finDepth), out: out, depth: Map3DFacadeVariety.finDepth,
                                 width: Map3DFacadeVariety.finWidth, height: top - bottom - 0.4, top: light, side: light)
                }
            case .hongKong:
                // The bay windows stacked up each bay, from the second floor.
                let wide = bay * Map3DFacadeVariety.bayWindowShare
                guard floors >= 3, wide >= 1 else { continue }
                for at in 0..<count {
                    let low = bottom + storey
                    Self.addStub(&relief, base: spot((Float(at) + 0.37) * bay, low, Map3DFacadeVariety.bayWindowDepth), out: out,
                                 depth: Map3DFacadeVariety.bayWindowDepth, width: wide, height: top - low - storey * 0.3, top: light, side: shade,
                                 frontPaint: .bays(.flatWindows, bay: wide, floors: max(1, floors - 1)))
                }
            case .ribbon:
                // A sill under each floor's ribbon, the broad walls only.
                guard !narrow else { continue }
                for floor in 0..<floors {
                    Self.addLedge(&relief, base: spot(face.length / 2, bottom + storey * (Float(floor) + 0.26), 0.35), out: out, depth: 0.35,
                                  width: face.length, height: 0.18, top: light, front: light)
                }
            default:
                break
            }
        }
        guard !relief.isEmpty else { return }
        // The cheapest first (model-look round 2: a few towers' balconies
        // left many towers' bay windows out), then by its seeded number.
        reliefParts[key(of: centre), default: []].append((Float(relief.triangleCount) + r(998), relief))
    }

    /// A ledge `width` wide out of a wall facing `out`, `depth` deep and
    /// `height` high from `base` (its middle, at its foot): its front and
    /// top alone, which the map's camera, always above, sees; four
    /// triangles to ``addStub(_:base:out:depth:width:height:top:side:frontPaint:)``'s eight.
    static func addLedge(_ mesh: inout Map3DMesh, base: Map3DPoint, out: Map3DPoint, depth: Float, width: Float, height: Float,
                         top: UInt32, front: UInt32) {
        guard depth > 0, width > 0, height > 0, let along = Map3DPoint(out.x, 0, out.z).normalized else { return }
        let across = Map3DPoint(-along.z, 0, along.x)
        let f = along * (depth / 2), r = across * (width / 2), h = Map3DPoint(0, height, 0)
        let corners = [base + f - r, base + f + r, base - f + r, base - f - r]
        let up = corners.map { $0 + h }
        mesh.addQuad(up[0], up[3], up[2], up[1], color: top)
        mesh.addQuad(corners[1], corners[0], up[0], up[1], color: Map3DColor.shaded(front, 0.92))
    }
}
