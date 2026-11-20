import Foundation
import GameCore

// Decision 791: Hong Kong's landmark towers on its 3D map. Their shapes
// are the Lands Department's surveyed models (3D Visualisation Map,
// non-textured individualised models), cut down and painted by the local
// studio in Blender (`a91453/railway-assets-private`,
// `game-art-previews/docs/art/hk-landmarks-2026-11/revision-11/`);
// `tools/landmarks/glb_to_swift.py --legacy hongkong` writes them into
// `Map3DHongKongLandmarkMeshes.swift`. Decision 793 adds the bank
// headquarters at 1 Queen's Road Central, which the studio made again;
// decision 798 the Convention and Exhibition Centre in Wan Chai, its
// curved roofs rebuilt piece by piece from the surveyed one. Decision
// 895: the registered landmarks (``Map3DLandmarkRegistration``, Fukuoka's
// since then) are placed here the same way, after these; Hong Kong's stay
// in this enum until they are made again.

/// Decision 791: the landmarks, each in its own metres (x east, y north,
/// z up, the middle of its footprint at the origin), stood where it is.
enum Map3DHongKongLandmark: String, CaseIterable, Sendable {
    case internationalCommerceCentre = "international-commerce-centre"
    case twoIFC = "two-ifc"
    case centralPlaza = "central-plaza"
    case bankOfChinaTower = "bank-of-china-tower"
    case cheungKongCenter = "cheung-kong-center"
    case hsbcMainBuilding = "hsbc-main-building"
    case theCenter = "the-center"
    case tsimShaTsuiClockTower = "tsim-sha-tsui-clock-tower"
    case culturalCentre = "cultural-centre"
    case conventionCentre = "convention-centre"

    /// Where the middle of its footprint stands: the surveyed model's, from
    /// the Hong Kong 1980 Grid (`base/landmarks.json`).
    var latitude: Double {
        switch self {
        case .internationalCommerceCentre: 22.303338
        case .twoIFC: 22.2853515
        case .centralPlaza: 22.2801147
        case .bankOfChinaTower: 22.2792662
        case .cheungKongCenter: 22.279541
        case .hsbcMainBuilding: 22.2802842
        case .theCenter: 22.2846127
        case .tsimShaTsuiClockTower: 22.2935845
        case .culturalCentre: 22.2937068
        case .conventionCentre: 22.2830975
        }
    }
    var longitude: Double {
        switch self {
        case .internationalCommerceCentre: 114.1602056
        case .twoIFC: 114.1592872
        case .centralPlaza: 114.1735806
        case .bankOfChinaTower: 114.16157
        case .cheungKongCenter: 114.1605384
        case .hsbcMainBuilding: 114.1595382
        case .theCenter: 114.1547296
        case .tsimShaTsuiClockTower: 114.1695373
        case .culturalCentre: 114.1702111
        case .conventionCentre: 114.1730512
        }
    }

    /// How high its foot stands above Principal Datum (metres), the
    /// surveyed model's: the International Commerce Centre stands on its
    /// podium, 29 m up.
    var baseHeight: Float {
        switch self {
        case .internationalCommerceCentre: 28.98
        case .twoIFC: 7.28
        case .centralPlaza: 4.03
        case .bankOfChinaTower: 7.11
        case .cheungKongCenter: 7.32
        case .hsbcMainBuilding: 3.96
        case .theCenter: 3.35
        case .tsimShaTsuiClockTower: 4.32
        case .culturalCentre: 3.97
        case .conventionCentre: 3.99
        }
    }

    /// The colour of each of the brief's materials, in
    /// `tools/landmarks/glb_to_swift.py`'s `HONG_KONG` order: the city's
    /// building colours (`Map3DPalette`, and the old textures' colours in
    /// `tools/texture-palette/t003/`); only the gold is the landmarks' own.
    static let materialColours: [UInt32] = [
        0x8A949E, // glassBlueGrey: cityOfficeWalls[5]
        0xA9B0B8, // glassSilver: cityConcreteWalls[5]
        0x2B2F36, // glassDark: Map3DPalette.dark
        0xDAE2E6, // mullionWhite: cityOfficeWalls[4]
        0x8A9099, // steelGrey: Map3DPalette.steel
        0xC8A24E, // goldBand: Map3DPalette.gold (Central Plaza's gold)
        0xD9D4C8, // podiumStone: cityOfficeWalls[3]
        0x6C7279, // roofGrey: cityRoofs[1]
        0xB0624A, // brickRed: hallWalls[3]
        0xCFCBC2, // graniteLight: Map3DPalette.concrete
        0xD9B9A2, // tilePink: the houses' pink
        0xC8CDD2, // mast: Map3DPalette.tankSteel
    ].map(Map3DColor.rgb)

    /// Decision 817: the materials that are glass (blue-grey, silver and
    /// dark), lit at night.
    static let glassMaterials: Set<Int> = [0, 1, 2]

    /// The model in full close by, or the studio's far model.
    func model(full: Bool) -> LandmarkMesh {
        let name = rawValue + (full ? "" : "-far")
        guard let text = Self.encodedMeshes[name], let data = Data(base64Encoded: text),
              let mesh = Self.decoded(Array(data), full: full) else { return LandmarkMesh(full: full) }
        return mesh
    }

    /// Reads `tools/landmarks/glb_to_swift.py`'s encoding
    /// (``LandmarkMesh/decodedLandmark(_:full:palette:glass:bandedGlass:)``)
    /// in ``materialColours``.
    static func decoded(_ bytes: [UInt8], full: Bool) -> LandmarkMesh? {
        LandmarkMesh.decodedLandmark(bytes, full: full, palette: materialColours, glass: glassMaterials)
    }

    /// Half its footprint's length (east) and width (north) in `model`.
    static func body(of model: LandmarkMesh) -> (x: Float, y: Float) {
        let xs = model.vertices.map(\.x), ys = model.vertices.map(\.y)
        return (((xs.max() ?? 0) - (xs.min() ?? 0)) / 2, ((ys.max() ?? 0) - (ys.min() ?? 0)) / 2)
    }
}

extension Map3DScene.Builder {
    /// Decision 791: Hong Kong's landmarks where they stand, and after
    /// them the registered ones (decision 895, ``Map3DLandmarkRegistry``),
    /// when the scene holds their middle and no track or platform but a
    /// tunnel's runs within their body: in full close by, the far model
    /// from afar. Unlike Taipei's they clear no 64 m cell (the towers of
    /// Central stand closer than that); the footprint their body covers is
    /// left undrawn (``landmarkPlots``). Returns the names of those built
    /// (the enum's raw values, the registrations' ids).
    @discardableResult
    mutating func addHongKongLandmarks(frame: RealWorldFrame) -> Set<String> {
        typealias Placed = (id: String, latitude: Double, longitude: Double, baseHeight: Float, model: (Bool) -> LandmarkMesh)
        let landmarks: [Placed] = Map3DHongKongLandmark.allCases.map { landmark in
            (landmark.rawValue, landmark.latitude, landmark.longitude, landmark.baseHeight, landmark.model(full:))
        } + Map3DLandmarkRegistry.landmarks.map { landmark in
            (landmark.id, landmark.latitude, landmark.longitude, landmark.baseHeight, landmark.model(full:))
        }
        var built = Set<String>()
        for landmark in landmarks {
            let place = frame.worldPosition(latitude: landmark.latitude, longitude: landmark.longitude)
            guard contains(x: place.x, y: place.y) else { continue }
            let centre = point(x: place.x, y: place.y, height: 0)
            let models = [true: landmark.model(true), false: landmark.model(false)]
            let body = LandmarkMesh.corners(Map3DHongKongLandmark.body(of: models[true]!), origin: centre, rotation: 0)
            guard isClearOfTrack(body) else { continue }
            // On its podium where the ground is lower than its foot.
            let ground = max(body.map { drawnGround(x: $0.x, z: $0.z) }.min() ?? 0, landmark.baseHeight)
            let saved = target
            for (level, full) in [(Target.near, true), (.far, false)] {
                target = level
                let mesh = models[full]!.placed(origin: centre, ground: ground, rotation: 0)
                keptColours.formUnion(mesh.vertices.map(\.color))
                self.mesh(at: centre) { $0.append(mesh) }
            }
            target = saved
            landmarkPlots.append(PlacedSquare(minX: body.map(\.x).min()!, minZ: body.map(\.z).min()!,
                                              maxX: body.map(\.x).max()!, maxZ: body.map(\.z).max()!))
            built.insert(landmark.id)
        }
        return built
    }

    /// Whether the scene point `middle` stands within a landmark's body,
    /// so the footprint round it (the surveyed building the landmark
    /// draws) is not drawn again.
    func underLandmark(_ middle: Map3DPoint) -> Bool {
        landmarkPlots.contains { $0.minX <= middle.x && middle.x <= $0.maxX && $0.minZ <= middle.z && middle.z <= $0.maxZ }
    }
}
