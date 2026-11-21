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

    init(id: String, map: String, latitude: Double, longitude: Double, baseHeight: Float = 0, sink: Float = 0, palette: [UInt32],
         glass: Set<Int> = [], bandedGlass: Set<Int> = [], encoded: [String: String], size: (x: Float, y: Float, z: Float)) {
        self.id = id
        self.map = map
        self.latitude = latitude
        self.longitude = longitude
        self.baseHeight = baseHeight
        self.sink = sink
        self.palette = palette
        self.glass = glass
        self.bandedGlass = bandedGlass
        self.encoded = encoded
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
