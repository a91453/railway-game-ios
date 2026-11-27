import Foundation

/// Decision 895: a landmark that keeps everything of its own in its own
/// files, as decision 782's trains do, so two pull requests that each add
/// a landmark touch no file in common but ``Map3DLandmarkRegistry/landmarks``'s
/// list (one line a landmark, merged line by line, `.gitattributes`). Its
/// source file holds this registration (where it stands, its palette, the
/// size it is checked against); its mesh file (`<Type>Mesh.swift`) the
/// encoded models, which `tools/landmarks/glb_to_swift.py` writes;
/// `tools/landmarks/locks/<id>.json` its models' hashes.
/// `Map3DLandmarkRegistryTests` reads the registry, so no test is edited
/// for a new landmark.
///
/// The landmarks made before the registry (Hong Kong's towers in
/// ``Map3DHongKongLandmark``, Sun Moon Lake's, Taipei's) stay where they
/// are until they are made again or changed (the owner, 2026-11-20: the
/// old ones are not moved for the sake of it); a new or remade one comes
/// in here.
public struct Map3DLandmarkRegistration: Sendable {
    /// Its name: its near model's (its far one's is `<id>-far`) and its
    /// lock file's stem.
    public let id: String
    /// The map it stands on (an ``OverseasMap``'s pack folder, or
    /// `taiwan`): each map's landmarks share one budget.
    public let map: String
    /// Where the middle of its footprint stands.
    public let latitude: Double
    public let longitude: Double
    /// How high its foot stands above the map's datum (metres), where that
    /// is above the ground the map draws; 0 to stand on that ground.
    public let baseHeight: Float
    /// How far its model's foot stands below the ground it is set on
    /// (metres): a building whose ground floor is above its foot, as the
    /// Peak Tower's plaza stands over its plinth down the hillside
    /// (decision 913); its floor is set on the ground at its middle. 0 to
    /// stand on the lowest ground under it.
    public let sink: Float
    /// BRIDGE-LANDMARK-DECK: a road bridge's road surface over its model's
    /// foot (metres), or `nil` for a landmark no road crosses: its deck
    /// is set level with the drawn ground at its two ends (their mean),
    /// and the real map's own bridge under it is left out
    /// (``Map3DBaseMap/leavingOut(_:)``).
    public let deck: Float?
    /// The colour of each of its mesh's materials, in the order
    /// `glb_to_swift.py --materials` gave them: ``Map3DPalette``'s.
    let palette: [UInt32]
    /// The palette's glass, drawn as curtain glass (mullions and floors by
    /// day, one bay in three lit after dark; decision 817).
    let glass: Set<Int>
    /// The palette's glass drawn by its floors rather than its mullions
    /// (``Map3DVertex/floorLines``), as Fukuoka Tower's bands of mirror
    /// panes; lit at night as the rest.
    let bandedGlass: Set<Int>
    /// Its near and far models, encoded (`glb_to_swift.py`'s `encoded`).
    let encoded: [String: String]
    /// Its size, metres east, north and up, that
    /// `Map3DLandmarkRegistryTests` checks its models against (half a
    /// metre either way): the real building's.
    let size: (x: Float, y: Float, z: Float)
    /// Decision 1020: what makes it a station's building (Hakata,
    /// Kumamoto, Duoliang), `nil` for any other landmark.
    public let station: Map3DStationLandmark?
    /// Decision 1033: the corners of the rectangle round its body,
    /// metres east and north of its middle, in turn, that the track is
    /// kept clear of: for a long building turned across the map, whose
    /// box east and north would reach over the line beside it (Ōmura's
    /// sheds). `nil` for that box.
    let body: [(x: Float, y: Float)]?
    /// Decision 1018 (continued 4): the middles (the mean of their
    /// outlines' corners, as ``Map3DFootprints`` takes them) of the real
    /// buildings it stands in the place of though it covers neither their
    /// middles nor a third of their corners, metres east and north of its
    /// own middle: Dazaifu's main hall, whose OpenStreetMap outline is the
    /// whole precinct, cloister and gate with it. The footprint whose
    /// middle is within ``replacedReach`` of one is not drawn again but
    /// counts as built (decision 879's ``Map3DScene/Builder/LandmarkState/replacedPlots``).
    let replaces: [(east: Float, north: Float)]
    /// How far from a ``replaces`` point (metres, either way) the
    /// footprint's middle may be: an outline's corners as the map pack
    /// keeps them move its mean a little from OpenStreetMap's.
    static let replacedReach: Float = 6

    init(id: String, map: String, latitude: Double, longitude: Double, baseHeight: Float = 0, sink: Float = 0, deck: Float? = nil,
         palette: [UInt32],
         glass: Set<Int> = [], bandedGlass: Set<Int> = [], encoded: [String: String], station: Map3DStationLandmark? = nil,
         replaces: [(east: Float, north: Float)] = [],
         body: [(x: Float, y: Float)]? = nil, size: (x: Float, y: Float, z: Float)) {
        self.replaces = replaces
        self.id = id
        self.map = map
        self.latitude = latitude
        self.longitude = longitude
        self.baseHeight = baseHeight
        self.sink = sink
        self.deck = deck
        self.palette = palette
        self.glass = glass
        self.bandedGlass = bandedGlass
        self.encoded = encoded
        self.station = station
        self.body = body
        self.size = size
    }

    /// The model in full close by, or the far model; empty if it does not
    /// decode (`Map3DLandmarkRegistryTests` keeps that from happening).
    func model(full: Bool) -> LandmarkMesh {
        guard let text = encoded[full ? id : id + "-far"], let data = Data(base64Encoded: text, options: .ignoreUnknownCharacters),
              let mesh = LandmarkMesh.decodedLandmark(Array(data), full: full, palette: palette, glass: glass, bandedGlass: bandedGlass)
        else { return LandmarkMesh(full: full) }
        return mesh
    }
}

/// Decision 1020 (the owner, 2026-11-27: one rule for every station): a
/// landmark that is a station's building. Unlike any other landmark it
/// does not give way to the track: the player's track and platforms and
/// the real lines' track may run through it, in the room it leaves for
/// them (``Map3DScene/Builder/stationLandmarkStands(_:snapshot:frame:)``),
/// so it stands before and after its line is bought, and the game's own
/// building, entrances and canopies of a station whose platforms it
/// stands over are left out (its platforms stay, laid by the game).
public struct Map3DStationLandmark: Sendable {
    /// How high over the model's foot the rails it was built round are
    /// (Hakata's Shinkansen platforms' roofs clear a train on rails
    /// 12.3 m up, Kumamoto's shed 10 m, Duoliang's platforms on their
    /// retaining walls 2.5 m): those rails are then put on the drawn
    /// rails under it, all of it under them stretched down to the
    /// ground and all over them raised as much. `nil` to stand on the
    /// ground as it was built.
    public let railHeight: Float?

    public init(railHeight: Float? = nil) {
        self.railHeight = railHeight
    }
}

enum Map3DLandmarkRegistry {
    /// The registered landmark `id`, if it is one.
    static func registration(_ id: String) -> Map3DLandmarkRegistration? {
        landmarks.first { $0.id == id }
    }
}

extension LandmarkMesh {
    /// Reads `tools/landmarks/glb_to_swift.py`'s encoding: the vertex
    /// count (UInt16), each vertex x and y in centimetres (Int16) and z in
    /// centimetres (UInt16), the triangle count (UInt16), each triangle's
    /// three vertex indices (UInt16) and `palette` index (UInt8),
    /// little-endian; whole or not at all. Its `glass` walls are curtain
    /// glass (decision 817), u metres along the wall and v metres up; its
    /// `bandedGlass` walls floor-lined glass.
    static func decodedLandmark(_ bytes: [UInt8], full: Bool, palette: [UInt32], glass: Set<Int>, bandedGlass: Set<Int> = [])
        -> LandmarkMesh? {
        var at = 0
        func u16() -> Int? {
            guard at + 2 <= bytes.count else { return nil }
            defer { at += 2 }
            return Int(UInt16(bytes[at]) | UInt16(bytes[at + 1]) << 8)
        }
        guard let vertexCount = u16() else { return nil }
        var points: [LandmarkMesh.P3] = []
        points.reserveCapacity(vertexCount)
        for _ in 0..<vertexCount {
            guard let x = u16(), let y = u16(), let z = u16() else { return nil }
            func signed(_ n: Int) -> Float { Float(Int16(truncatingIfNeeded: n)) / 100 }
            points.append((signed(x), signed(y), Float(z) / 100))
        }
        guard let triangleCount = u16() else { return nil }
        var mesh = LandmarkMesh(full: full)
        for _ in 0..<triangleCount {
            guard let a = u16(), let b = u16(), let c = u16(), at < bytes.count else { return nil }
            let paint = Int(bytes[at])
            at += 1
            guard [a, b, c].allSatisfy(points.indices.contains), palette.indices.contains(paint) else { return nil }
            let (p, q, s) = (points[a], points[b], points[c])
            let n = Map3DPoint(q.x - p.x, q.y - p.y, q.z - p.z).cross(Map3DPoint(s.x - p.x, s.y - p.y, s.z - p.z)).normalized
            if glass.contains(paint) || bandedGlass.contains(paint), let n, abs(n.z) < 0.7, let along = Map3DPoint(-n.y, n.x, 0).normalized {
                let uv = [p, q, s].map { (x: $0.x * along.x + $0.y * along.y, y: $0.z) }
                mesh.tri(p, q, s, palette[paint], bandedGlass.contains(paint) ? LandmarkMesh.floors : LandmarkMesh.curtain, uv)
            } else {
                mesh.tri(p, q, s, palette[paint], LandmarkMesh.plain)
            }
        }
        guard at == bytes.count else { return nil }
        return mesh
    }
}
