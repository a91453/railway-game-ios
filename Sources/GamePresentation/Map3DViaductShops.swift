import Foundation
import GameCore

// Decision 1035 (STREET-TEMPLE-VIADUCT-TRAM-RULES §4): shops in the spans
// under the player's own viaducts near an elevated station, as Taiwan's
// railway and metro viaducts have them (Songshan to Nangang, the Kaohsiung
// line's, the Taichung line's): within 300 m of the station's platforms,
// never under the station itself, never where a road passes under, one
// span left empty after every three, and as many spans as the station's
// commerce: a convenience store 1, a shop street 3, a station mall 6. For
// the look only: they earn nothing (the station's commerce does).

/// Decision 1035: the bay of shops the local studio built for a viaduct's
/// span, and the wall that closes the space above it up to the girder.
///
/// The owner's Meshy model rebuilt by the studio and passed by its review
/// (`a91453/railway-assets-private-2`
/// `game-art-previews/docs/art/viaduct-shops-2026-11/revision-2`; lessons
/// in `docs/studio/lessons/viaduct-shops.md`). Written here by
/// `tools/train-models/glb_to_swift.py` (``encoded``): 30 m along x (the
/// line), 9 m across y, 5 m tall, its foot's middle at the origin; the
/// infill 1 m tall from 5 m, stretched to the girder.
enum Map3DViaductShops: String, CaseIterable, Sendable {
    case bay = "viaduct-shops-bay"
    case bayFar = "viaduct-shops-bay-far"
    case infill = "viaduct-shops-infill"

    /// The colours, in the order `glb_to_swift.py --materials` gave them
    /// (viaductConcrete, glass, shutter, dark, signBlue, signRed,
    /// signYellow), each the game's own.
    static let palette: [UInt32] = [
        Map3DPalette.concrete, Map3DPalette.glazing, Map3DPalette.steel, Map3DPalette.dark, Map3DPalette.canopy,
        Map3DPalette.templeRidge, Map3DPalette.platformEdge,
    ]

    /// The bay's length, width and height as built.
    static let length: Float = 30
    static let width: Float = 9
    static let height: Float = 5

    var model: Map3DModelPack.Model? { Self.models[self] ?? nil }

    private static let models: [Map3DViaductShops: Map3DModelPack.Model?] = Dictionary(uniqueKeysWithValues: allCases.map { part in
        guard let text = encoded[part.rawValue], let data = Data(base64Encoded: text, options: .ignoreUnknownCharacters) else { return (part, nil) }
        return (part, Map3DRedCommuter.decodedMesh([UInt8](data), named: part.rawValue, palette: palette))
    })
}

extension Map3DViaducts {
    /// Decision 1035: a pier as it stood (``Map3DScene/Builder/addPiers(_:)``):
    /// under the middle of its pair, `spread` the tracks apart.
    struct StoodPier: Sendable {
        let top: Map3DPoint
        let foot: Float
        let forward: Map3DPoint
        let spread: Float
        let kind: TrackSectionKind
        let viaduct: Map3DViaduct
    }
}

extension Map3DScene.Builder {
    /// Decision 1035: a span between two piers of the player's own
    /// viaduct, where a bay of shops could stand.
    struct ViaductSpan: Sendable {
        /// The middle of the span on the line, at the girder's bottom.
        let middle: Map3DPoint
        /// Along the line, level.
        let forward: Map3DPoint
        /// Between the piers' faces, metres.
        let clear: Float
        /// The deck's width, the tracks' spacing with it.
        let wide: Float
    }

    /// The shops' rules (decision 1035).
    static let viaductShopReach: Float = 300
    static let viaductShopRun = 3
    static let viaductShopMinimumHeight: Float = 5.3
    static let viaductShopMaximumHeight: Float = 12
    /// At most this many bays in a scene (decision 935's budget: about
    /// 1,000 triangles each, drawn near only).
    static let viaductShopCap = 48

    /// The bays a station of commerce `level` has.
    static func viaductShopBays(_ level: StationCommerceLevel?) -> Int {
        switch level {
        case .convenienceStore: 1
        case .arcade: 3
        case .mall: 6
        case nil: 0
        }
    }

    /// Decision 1035: the spans between `stood`'s piers (by the piece
    /// each stands under), each pier and the next a span ahead of it in
    /// line, of whichever piece (a track is laid in pieces), under a
    /// railway's or a metro's viaduct over dry land with two tracks on it.
    mutating func addShopSpans(_ stood: [Int: [Map3DViaducts.StoodPier]]) {
        func kept(_ pier: Map3DViaducts.StoodPier) -> Bool {
            guard pier.kind == .viaduct, pier.spread > 0 else { return false }
            return pier.viaduct == .railway || pier.viaduct == .metro
        }
        let piers: [Map3DViaducts.StoodPier] = stood.keys.sorted().flatMap { stood[$0] ?? [] }.filter(kept)
        var cells: [Map3DScene.ChunkKey: [Int]] = [:]
        for (index, pier) in piers.enumerated() { cells[Map3DViaducts.cell(pier.top), default: []].append(index) }
        var seen = Set<Map3DScene.ChunkKey>()
        for a in piers {
            let look = a.viaduct.look(over: a.kind)
            for way in [a.forward, a.forward * -1] {
                let ahead = a.top + way * look.span, home = Map3DViaducts.cell(ahead)
                var next: Map3DViaducts.StoodPier?
                for dc in -1...1 {
                    for dr in -1...1 {
                        for other in cells[Map3DScene.ChunkKey(column: home.column + dc, row: home.row + dr)] ?? [] {
                            let b = piers[other]
                            let offset = Map3DPoint(b.top.x - ahead.x, 0, b.top.z - ahead.z)
                            guard b.viaduct == a.viaduct, abs(offset.dot(way)) < 2, abs(offset.dot(way.cross(.up))) < 1,
                                  abs(b.forward.dot(a.forward)) > 0.998 else { continue }
                            next = b
                        }
                    }
                }
                guard let b = next else { continue }
                let middle = Map3DPoint((a.top.x + b.top.x) / 2, min(a.top.y, b.top.y), (a.top.z + b.top.z) / 2)
                // Each span once, from whichever end.
                guard seen.insert(Map3DScene.ChunkKey(column: Int((middle.x * 2).rounded()), row: Int((middle.z * 2).rounded()))).inserted,
                      let forward = Map3DPoint(b.top.x - a.top.x, 0, b.top.z - a.top.z).normalized else { continue }
                let pier: Float = switch look.pier {
                case let .wall(along, _, _): along
                case let .column(along, _, _): along
                case let .round(radius, _): radius * 2
                }
                let length = Map3DPoint(b.top.x - a.top.x, 0, b.top.z - a.top.z).length
                state.elevated.shopSpans.append(ViaductSpan(middle: middle, forward: forward, clear: length - pier - 0.3,
                                                            wide: look.deckWidth + min(a.spread, b.spread)))
            }
        }
    }

    /// Decision 1035: the bays of shops under the spans kept
    /// (``ViaductSpan``) near each elevated station with commerce, as
    /// many as its commerce has, nearest first along each way out, one
    /// span left empty after three; near only, the simpler bay from afar.
    /// `commerce` stands in for the world's stations' (the tests').
    mutating func addViaductShops(commerce: ((StationID) -> StationCommerceLevel?)? = nil) {
        let world = world
        let level = commerce ?? { world.station(id: $0)?.commerce }
        let spans = state.elevated.shopSpans
        state.elevated.shopSpans = []
        guard !spans.isEmpty, let bay = Map3DViaductShops.bay.model, let far = Map3DViaductShops.bayFar.model,
              let infill = Map3DViaductShops.infill.model else { return }
        // The elevated stations with commerce: their raised platforms'
        // points, and the way they run.
        var platforms: [StationID: [Map3DPoint]] = [:]
        var ways: [StationID: Map3DPoint] = [:]
        for platform in state.platforms.laidPlatforms where platform.structure == .elevated || platform.structure == .bridge {
            guard Self.viaductShopBays(level(platform.station)) > 0, platform.line.count > 1 else { continue }
            platforms[platform.station, default: []] += platform.line
            if ways[platform.station] == nil, let way = Map3DPoint(platform.line[platform.line.count - 1].x - platform.line[0].x, 0,
                                                                    platform.line[platform.line.count - 1].z - platform.line[0].z).normalized {
                ways[platform.station] = way
            }
        }
        guard !platforms.isEmpty else { return }
        // Each span to the nearest such station within reach, by its way
        // out (the end of the station it lies beyond) and how far beyond.
        var ends: [StationID: [[(distance: Float, span: Int)]]] = [:]
        for (index, span) in spans.enumerated() {
            var best: (station: StationID, distance: Float)?
            for (station, points) in platforms {
                let distance = points.lazy.map { Map3DPoint($0.x - span.middle.x, 0, $0.z - span.middle.z).length }.min() ?? .infinity
                if distance <= Self.viaductShopReach, distance < (best?.distance ?? .infinity) { best = (station, distance) }
            }
            guard let best, let way = ways[best.station], let points = platforms[best.station] else { continue }
            // How far along the station's way each platform point lies
            // from the span: all ahead of it, or all behind, by half the
            // span and 10 m, so none stands under the station.
            let ahead = points.map { Map3DPoint($0.x - span.middle.x, 0, $0.z - span.middle.z).dot(way) }
            guard let first = ahead.min(), let last = ahead.max() else { continue }
            let half = span.clear / 2 + 10
            let end: Int, beyond: Float
            if first > half { (end, beyond) = (0, first) } else if last < -half { (end, beyond) = (1, -last) } else { continue }
            ends[best.station, default: [[], []]][end].append((beyond, index))
        }
        var grounds: [Int: Float] = [:]
        var placed = 0
        for station in ends.keys.sorted() {
            let wanted = Self.viaductShopBays(level(station))
            // Each way out: the spans nearest first, a bay where one may
            // stand, one left empty after each three in a row; a span
            // that may not take one ends the row too.
            var chosen: [[Int]] = [[], []]
            for end in 0..<2 {
                var row = 0
                for (_, index) in (ends[station]?[end] ?? []).sorted(by: { $0.distance < $1.distance }) {
                    guard chosen[end].count < wanted else { break }
                    guard let ground = shopGround(spans[index]) else { row = 0; continue }
                    if row == Self.viaductShopRun { row = 0; continue }
                    row += 1
                    chosen[end].append(index)
                    grounds[index] = ground
                }
            }
            // Both ways in turn, nearest first.
            var order: [Int] = []
            for step in 0..<wanted {
                for end in 0..<2 where step < chosen[end].count && order.count < wanted { order.append(chosen[end][step]) }
            }
            for index in order where placed < Self.viaductShopCap {
                guard let ground = grounds[index] else { continue }
                addShopBay(spans[index], ground: ground, bay: bay, far: far, infill: infill)
                placed += 1
            }
        }
    }

    /// Decision 1035: the ground a bay under `span` stands on, `nil` where
    /// none may: too low or too high under the girder, on a slope, over
    /// water, where a road passes under, or by track or a platform on the
    /// ground.
    mutating func shopGround(_ span: ViaductSpan) -> Float? {
        guard span.wide >= 7.5 else { return nil }
        let side = span.forward.cross(.up)
        let length = span.clear / 2, width = min(span.wide, Map3DViaductShops.width) / 2
        let corners = [(-1, -1), (1, -1), (1, 1), (-1, 1), (0, 0)].map { (along: Float, across: Float) in
            span.middle + span.forward * (along * length) + side * (across * width)
        }
        let grounds = corners.map { drawnGround(x: $0.x, z: $0.z) }
        guard let low = grounds.min(), let high = grounds.max(), high - low <= 1 else { return nil }
        let clearance = span.middle.y - low
        // Its outline and 3 m round it (the fire lane, §4.2) on dry land.
        let reach = [(-1, -1), (1, -1), (1, 1), (-1, 1), (0, -1), (0, 1)].map { (along: Float, across: Float) in
            span.middle + span.forward * (along * (length + 3)) + side * (across * (width + 3))
        }
        guard clearance >= Self.viaductShopMinimumHeight, clearance <= Self.viaductShopMaximumHeight,
              !reach.contains(where: isOverWater) else { return nil }
        let middle = Map3DPoint(span.middle.x, 0, span.middle.z)
        func near(_ p: Map3DPoint, _ margin: Float) -> Bool {
            let d = Map3DPoint(p.x - middle.x, 0, p.z - middle.z)
            return abs(d.dot(span.forward)) < length + margin && abs(d.dot(side)) < width + margin
        }
        // A road under the span or along under it, its middle within 3 m
        // of the outline (the base map's, or the seeded streets).
        for road in state.baseMap.roadLines {
            for (a, b) in zip(road.points, road.points.dropFirst()) {
                let step = Map3DPoint(b.x - a.x, 0, b.z - a.z), steps = max(1, Int((step.length / 2).rounded(.up)))
                guard Map3DPoint(a.x - middle.x, 0, a.z - middle.z).length < step.length + length + width + road.half + 4 else { continue }
                for index in 0...steps where near(a + step * (Float(index) / Float(steps)), max(3, road.half + 1)) { return nil }
            }
        }
        // Track on the ground beside or under it, and platforms.
        for line in state.track.trackLines where line.kind != .viaduct && line.kind != .bridge && line.kind != .tunnel {
            if line.points.contains(where: { near($0, 3) }) { return nil }
        }
        if state.platforms.laidPlatforms.contains(where: { platform in
            platform.line.contains { near($0, abs(platform.offset) + platform.width / 2 + 2) }
        }) { return nil }
        return low
    }

    /// One bay under `span` on `ground`: the shops near, the simpler bay
    /// from afar, each with its wall up to the girder.
    mutating func addShopBay(_ span: ViaductSpan, ground: Float, bay: Map3DModelPack.Model, far: Map3DModelPack.Model, infill: Map3DModelPack.Model) {
        let foot = Map3DPoint(span.middle.x, ground - 0.05, span.middle.z)
        let along = span.clear / Map3DViaductShops.length, across = min(span.wide, Map3DViaductShops.width) / Map3DViaductShops.width
        let top = span.middle.y - foot.y
        let saved = target
        defer { target = saved }
        for (tier, model) in [(Target.near, bay), (.far, far)] {
            target = tier
            mesh(at: foot) { mesh in
                Self.appendStretched(model, to: &mesh, at: foot, forward: span.forward, along: along, across: across) { $0 }
                // The infill's 5–6 m stretched to the girder.
                Self.appendStretched(infill, to: &mesh, at: foot, forward: span.forward, along: along, across: across) { z in
                    Map3DViaductShops.height + (z - Map3DViaductShops.height) * (top - Map3DViaductShops.height)
                }
            }
        }
    }

    /// `model` (x forward, y left, z up) at `p` facing `forward`, `along`
    /// and `across` times its length and width, each height `rise`'s;
    /// its normals turned and stretched with it.
    static func appendStretched(_ model: Map3DModelPack.Model, to mesh: inout Map3DMesh, at p: Map3DPoint, forward: Map3DPoint,
                                along: Float, across: Float, rise: (Float) -> Float) {
        let right = forward.cross(.up)
        // How much taller each triangle's heights became, for its normal.
        for i in stride(from: 0, to: model.vertices.count, by: 3) {
            let corners = model.vertices[i..<i + 3]
            let heights = corners.map(\.z), risen = heights.map(rise)
            let low = heights.min() ?? 0, high = heights.max() ?? 0
            let stretch = high - low > 0.001 ? ((risen.max() ?? 0) - (risen.min() ?? 0)) / (high - low) : 1
            mesh.appendTriangle(zip(corners, risen).map { v, z in
                let normal = forward * (v.nx / along) - right * (v.ny / across) + Map3DPoint(0, v.nz / max(stretch, 0.001), 0)
                return Map3DVertex(p + forward * (v.x * along) - right * (v.y * across) + Map3DPoint(0, z, 0),
                                   normal: normal.normalized ?? normal, color: v.color, layer: v.layer)
            })
        }
    }
}
