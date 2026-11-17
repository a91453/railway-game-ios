import Foundation
import GameCore

/// Decision 827: the Tamsui-Xinyi line's elevated stations, the local
/// studio's four shells (`tools/tpe-mrt-stations/glb_to_swift.py`): the
/// palace-style standard station (Yuanshan to Qiyan), Jiantan's
/// suspension station, Beitou's four-track station and Xinbeitou's
/// terminus. A shell is drawn over a station of the game whose platforms
/// lie at the real station, along the game's own track there (not where
/// OpenStreetMap has the building, which lies 5–8 m off the line the game
/// draws), its rails at the game's rails; the track, platforms and trains
/// are the game's, through the shell's open middle. The shapes began from
/// Slop New York (Copyright (c) 2026 Mr.doob, MIT,
/// https://github.com/mrdoob/slop-newyork) and were remade in the game's
/// style by the studio. Only drawing: which station stands where is
/// GameCore's.
enum Map3DTaipeiMRTStation: String, CaseIterable, Sendable {
    case yuanshan, jiantan, shilin, zhishan, mingde, shipai, qilian, qiyan, beitou, xinbeitou

    enum Kind: String, Sendable {
        case standard, jiantan, beitou, xinbeitou
    }

    var kind: Kind {
        switch self {
        case .jiantan: .jiantan
        case .beitou: .beitou
        case .xinbeitou: .xinbeitou
        default: .standard
        }
    }

    /// The station's point (the game's real-station catalogue).
    var place: (latitude: Double, longitude: Double) {
        switch self {
        case .yuanshan: (25.071391, 121.520215)
        case .jiantan: (25.08418, 121.525053)
        case .shilin: (25.09351, 121.526292)
        case .zhishan: (25.102731, 121.522636)
        case .mingde: (25.109851, 121.518848)
        case .shipai: (25.114503, 121.515657)
        case .qilian: (25.120916, 121.506248)
        case .qiyan: (25.125481, 121.501208)
        case .beitou: (25.131884, 121.498669)
        case .xinbeitou: (25.137015, 121.502535)
        }
    }

    /// The materials' colours, in `glb_to_swift.py`'s `MATERIALS` order,
    /// each one the game already has.
    static let materialColours: [UInt32] = [
        0xF2C94C, // roofGold: Map3DPalette.platformEdge (round 4, deeper than hallWalls[4])
        0xDADCDD, // trimWhite: cityConcreteWalls[4]
        0xE3DCCB, // stoneBeige: Map3DPalette.terrazzo
        0xE3002C, // lineRed: the line's colour (RealRailways mrt|R)
        0x8A9099, // eaveTrim: Map3DPalette.steel
        0x2B2F36, // windowGlass: Map3DPalette.dark
        0xCFCBC2, // pier: Map3DPalette.concrete
        0xC9CCD5, // graniteGrey: concreteWalls[0]
        0xC8CDD2, // frameSilver: Map3DPalette.tankSteel
        0xC4C8D6, // roofPale: Map3DPalette.roof
        0xBFC8B4, // roofSeam: houseWalls[7]
        0x2B2F36, // cable: Map3DPalette.dark
        0xF2C94C, // clampGold: Map3DPalette.platformEdge
        0xA9B0B8, // graniteDark: cityConcreteWalls[5] (Beitou's end towers)
        0xDAE2E6, // glassBright: cityOfficeWalls[4] (Beitou's truss glass)
    ].map(Map3DColor.rgb)

    /// The rails' height in the model, and how far under and over them,
    /// and either side of the middle, the model leaves room for the
    /// game's track, platforms and trains (the brief's §4).
    static let modelRails: Float = 9.0
    static let roomBelow: Float = 1.2
    static let roomAbove: Float = 3.9
    static func roomHalf(_ kind: Kind) -> Float {
        switch kind {
        case .standard: 8.5
        case .jiantan: 9.5
        case .beitou: 18
        case .xinbeitou: 8.0
        }
    }
    /// Where along the model the room ends: Xinbeitou's end wall (from
    /// x 53) closes the track; the other three are open both ways.
    static func roomEnd(_ kind: Kind) -> Float { kind == .xinbeitou ? 53 : .infinity }

    /// How near (metres) a station's platforms' middle must be to the real
    /// station's point; how far its longest platform may bend off its
    /// chord and still carry a straight shell.
    static let reach: Float = 80
    static let straightness: Float = 1.0
    /// The least height of the rails over the ground for a shell (an
    /// elevated station).
    static let leastRise: Float = 5

    /// The model of `kind` in its own metres (+x along, +y up, +z across),
    /// close by or from afar.
    static func model(_ kind: Kind, near: Bool) -> [(Map3DPoint, Map3DPoint, Map3DPoint, UInt32)] {
        guard let text = encodedMeshes[kind.rawValue + (near ? "" : "-far")], let data = Data(base64Encoded: text),
              let triangles = decoded(Array(data)) else { return [] }
        return triangles
    }

    /// Reads `glb_to_swift.py`'s encoding.
    static func decoded(_ bytes: [UInt8]) -> [(Map3DPoint, Map3DPoint, Map3DPoint, UInt32)]? {
        var at = 0
        func u16() -> Int? {
            guard at + 2 <= bytes.count else { return nil }
            defer { at += 2 }
            return Int(UInt16(bytes[at]) | UInt16(bytes[at + 1]) << 8)
        }
        func metres(_ n: Int) -> Float { Float(Int16(truncatingIfNeeded: n)) / 100 }
        guard let count = u16() else { return nil }
        var points: [Map3DPoint] = []
        points.reserveCapacity(count)
        for _ in 0..<count {
            guard let x = u16(), let y = u16(), let z = u16() else { return nil }
            points.append(Map3DPoint(metres(x), metres(y), metres(z)))
        }
        guard let triangleCount = u16() else { return nil }
        var triangles: [(Map3DPoint, Map3DPoint, Map3DPoint, UInt32)] = []
        triangles.reserveCapacity(triangleCount)
        for _ in 0..<triangleCount {
            guard let a = u16(), let b = u16(), let c = u16(), at < bytes.count else { return nil }
            let paint = Int(bytes[at])
            at += 1
            guard [a, b, c].allSatisfy(points.indices.contains), materialColours.indices.contains(paint) else { return nil }
            triangles.append((points[a], points[b], points[c], materialColours[paint]))
        }
        return at == bytes.count ? triangles : nil
    }

    /// Where a shell stands over a station's platforms, each a track's
    /// line at the rails' height in the scene: its middle (at the rails),
    /// the way along the track (east-going), and how far along that way
    /// the model's middle lies from the platforms' middle. `nil` when the
    /// longest platform bends more than ``straightness``.
    struct Placement: Equatable {
        let rails: Map3DPoint
        let along: Map3DPoint
        let shift: Float
    }

    static func placement(of kind: Kind, platforms: [[Map3DPoint]]) -> Placement? {
        let lines = platforms.filter { $0.count > 1 }
        guard let longest = lines.max(by: { length($0) < length($1) }), let first = longest.first, let last = longest.last,
              var along = Map3DPoint(last.x - first.x, 0, last.z - first.z).normalized else { return nil }
        let chord = last - first
        for p in longest {
            let ap = p - first, share = min(max(chord.dot(ap) / max(chord.dot(chord), 1e-6), 0), 1)
            let off = ap - chord * share
            if Map3DPoint(off.x, 0, off.z).length > straightness { return nil }
        }
        if along.x < 0 || (along.x == 0 && along.z > 0) { along = along * -1 }
        // The middle between the platforms' middles, across the track.
        let middles = lines.map { line in line.reduce(Map3DPoint(0, 0, 0)) { $0 + $1 } * (1 / Float(line.count)) }
        let rails = middles.reduce(Map3DPoint(0, 0, 0)) { $0 + $1 } * (1 / Float(middles.count))
        var shift: Float = 0
        if kind == .xinbeitou {
            // The terminus: the model's end wall (from ``roomEnd``) a metre
            // past where the platforms end, not round their middle.
            let end = lines.flatMap { $0 }.map { ($0 - rails).dot(along) }.max() ?? 0
            shift = end + 1 - roomEnd(kind)
        }
        return Placement(rails: rails, along: along, shift: shift)
    }

    private static func length(_ line: [Map3DPoint]) -> Float {
        zip(line, line.dropFirst()).reduce(0) { $0 + ($1.1 - $1.0).length }
    }

    /// The model's point `p` in the scene, the shell at `placement` over
    /// ground `ground`: the rails at the game's rails, the parts under the
    /// platforms (concourse, piers) stretched down to the ground.
    static func scenePoint(_ p: Map3DPoint, _ placement: Placement, ground: Float) -> Map3DPoint {
        let along = placement.along, right = along.cross(.up)
        let floor = modelRails - roomBelow
        let y: Float = p.y >= floor
            ? placement.rails.y + (p.y - modelRails)
            : ground + p.y / floor * (placement.rails.y - roomBelow - ground)
        let flat = placement.rails + along * (p.x + placement.shift) + right * p.z
        return Map3DPoint(flat.x, y, flat.z)
    }

    /// The model of `kind` in the scene, as ``scenePoint(_:_:ground:)``
    /// puts it, flat-shaded.
    static func sceneMesh(_ kind: Kind, near: Bool, at placement: Placement, ground: Float) -> Map3DMesh {
        var vertices: [Map3DVertex] = [], indices: [UInt32] = []
        for (a, b, c, colour) in model(kind, near: near) {
            let (p, q, r) = (scenePoint(a, placement, ground: ground), scenePoint(b, placement, ground: ground),
                             scenePoint(c, placement, ground: ground))
            guard let n = (q - p).cross(r - p).normalized else { continue }
            for v in [p, q, r] {
                indices.append(UInt32(vertices.count))
                vertices.append(Map3DVertex(v, normal: n, color: colour, u: 0, v: 0, layer: Map3DVertex.plain))
            }
        }
        return Map3DMesh(vertices: vertices, indices: indices)
    }
}

extension Map3DScene.Builder {
    /// Decision 827: the shell for station `id`, if its platforms
    /// (`lines`, at the rails) lie within ``Map3DTaipeiMRTStation/reach``
    /// of one of the Tamsui-Xinyi line's elevated stations, run straight
    /// there and stand at least ``Map3DTaipeiMRTStation/leastRise`` over
    /// the ground. Asked of the platforms alone, so a block of chunks
    /// without the shell's middle agrees that the kit draws no building.
    mutating func taipeiMRTShell(platforms lines: [[Map3DPoint]], frame: RealWorldFrame?)
        -> (station: Map3DTaipeiMRTStation, placement: Map3DTaipeiMRTStation.Placement)? {
        guard let frame, !lines.isEmpty else { return nil }
        let all = lines.flatMap { $0 }
        let middle = all.reduce(Map3DPoint(0, 0, 0)) { $0 + $1 } * (1 / Float(all.count))
        for station in Map3DTaipeiMRTStation.allCases {
            let place = frame.worldPosition(latitude: station.place.latitude, longitude: station.place.longitude)
            let at = point(x: place.x, y: place.y, height: 0)
            guard Map3DPoint(at.x - middle.x, 0, at.z - middle.z).length <= Map3DTaipeiMRTStation.reach else { continue }
            guard let placement = Map3DTaipeiMRTStation.placement(of: station.kind, platforms: lines),
                  placement.rails.y - drawnGround(x: placement.rails.x, z: placement.rails.z) >= Map3DTaipeiMRTStation.leastRise
            else { return nil }
            return (station, placement)
        }
        return nil
    }

    /// Decision 827: the shell drawn, in its own colours (as the exterior
    /// studies, decision 625), in the chunk of its middle; the cells under
    /// it, for no city lot there.
    mutating func addTaipeiMRTShell(_ station: Map3DTaipeiMRTStation, at placement: Map3DTaipeiMRTStation.Placement)
        -> Set<Map3DScene.ChunkKey> {
        let kind = station.kind
        let half = Map3DTaipeiMRTStation.roomHalf(kind) + 9
        let right = placement.along.cross(.up)
        let models = Map3DTaipeiMRTStation.model(kind, near: false).flatMap { [$0.0, $0.1, $0.2] }
        let xs = models.map(\.x), zs = models.map(\.z)
        let (x0, x1) = ((xs.min() ?? -75) + placement.shift, (xs.max() ?? 75) + placement.shift)
        let (z0, z1) = (zs.min() ?? -half, zs.max() ?? half)
        let corners = [(x0, z0), (x1, z0), (x1, z1), (x0, z1)].map { placement.rails + placement.along * $0.0 + right * $0.1 }
        let ground = min(corners.map { drawnGround(x: $0.x, z: $0.z) }.min() ?? 0, placement.rails.y - Map3DTaipeiMRTStation.leastRise)
        let key = key(of: placement.rails)
        if !isCoarse(key) {
            ownColourNear[key, default: Map3DMesh()].append(Map3DTaipeiMRTStation.sceneMesh(kind, near: true, at: placement, ground: ground))
        }
        ownColourFar[key, default: Map3DMesh()].append(Map3DTaipeiMRTStation.sceneMesh(kind, near: false, at: placement, ground: ground))
        let footprint = corners.map { Map3DPoint($0.x, ground, $0.z) }
        houseFootprints.append(footprint)
        return cells(under: footprint)
    }
}
