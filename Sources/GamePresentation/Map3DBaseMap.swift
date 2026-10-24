import Foundation
import GameCore

/// The app's base map of Taiwan (`taiwan.pmtiles`, decision 151) for the 3D
/// map (decision 234): the 2D map's MapLibre draws the same file.
public struct BaseMapTiles: Sendable {
    let archive: PMTilesArchive

    /// The base map in `data`, the file's bytes (best mapped, not read).
    public init(data: Data) throws {
        archive = try PMTilesArchive(data: data)
    }

    /// The zoom the 3D map reads: the base map's most detailed, the only
    /// one with every road (`tools/basemap/build_basemap.py`'s `ROADS`).
    static let zoom = 14
}

/// What the base map holds round a 3D scene, in the scene's metres (x east,
/// z south of its origin): roads, rivers and streams, and the land's cover.
///
/// Read as the reference's location modeler reads OpenFreeMap's tiles for
/// its far zone (`RKFAR.build` in
/// `Railway/location_modeler_reference_clean/source/js/app.js`): the
/// OpenMapTiles classes, tunnels left out, each tile's features kept to the
/// tile itself so the tiles' overlap is not drawn twice.
struct Map3DBaseMap: Sendable {
    /// The land's cover, in the order it is laid: each over the ones
    /// before it where they overlap. Decision 393: farmland first, under
    /// every other.
    enum Cover: Int, CaseIterable, Sendable {
        case farmland, grass, sand, wetland, wood, park, water
    }

    /// A road's class (the tiles' `class`), from the least.
    enum RoadKind: Int, CaseIterable, Sendable {
        case service, minor, tertiary, secondary, primary, trunk, motorway
    }

    enum WaterwayKind: Int, Sendable {
        case stream, canal, river
    }

    /// The rectangle a tile's features are kept to, in scene metres.
    struct Bounds: Hashable, Sendable {
        let minX: Double, minZ: Double, maxX: Double, maxZ: Double
    }

    struct Point: Hashable, Sendable {
        let x: Double, z: Double
    }

    struct Area: Sendable {
        let cover: Cover
        /// The outer ring, then its holes.
        let rings: [[Point]]
        let bounds: Bounds
    }

    struct Road: Sendable {
        let kind: RoadKind
        /// A link road (the tiles' `ramp`).
        let isRamp: Bool
        let points: [Point]
        let bounds: Bounds
    }

    struct Waterway: Sendable {
        let kind: WaterwayKind
        let points: [Point]
        let bounds: Bounds
    }

    var areas: [Area] = []
    var roads: [Road] = []
    var waterways: [Waterway] = []

    /// A base map of the features given (a scene laid by hand).
    init(areas: [Area] = [], roads: [Road] = [], waterways: [Waterway] = []) {
        self.areas = areas
        self.roads = roads
        self.waterways = waterways
    }

    /// The base map's features over `region` (world units) of the world laid
    /// on the Earth by `frame`, in the metres of a scene whose origin is
    /// the world point (`originX`, `originY`). Tiles that fail to read are
    /// left out.
    init(tiles: BaseMapTiles, frame: RealWorldFrame, region: WorldRegion, originX: Double, originY: Double) {
        let metre = Double(WorldCoordinate.unitsPerMetre)
        let anchorLatitude = frame.anchor.latitudeDegrees
        let pointsPerMetre = RealWorldFrame.worldPoints / (2 * Double.pi * RealWorldFrame.earthRadius * cos(anchorLatitude * .pi / 180))
        let anchorX = RealWorldFrame.mercatorX(frame.anchor.longitudeDegrees), anchorY = RealWorldFrame.mercatorY(anchorLatitude)
        // A scene metre east of the scene's origin is a metre east of the
        // anchor, shifted by where the origin lies from the anchor.
        let shiftX = (frame.middleX - originX) / metre, shiftZ = (frame.middleY - originY) / metre
        let zoom = BaseMapTiles.zoom
        let tilePoints = RealWorldFrame.worldPoints / Double(1 << zoom)
        func tile(_ scene: Double, shift: Double, anchor: Double) -> Int {
            Int((((scene - shift) * pointsPerMetre + anchor) / tilePoints).rounded(.down))
        }
        let low = (x: (region.minX - originX) / metre, z: (region.minY - originY) / metre)
        let high = (x: (region.maxX - originX) / metre, z: (region.maxY - originY) / metre)
        let columns = tile(low.x, shift: shiftX, anchor: anchorX)...tile(high.x, shift: shiftX, anchor: anchorX)
        let rows = tile(low.z, shift: shiftZ, anchor: anchorY)...tile(high.z, shift: shiftZ, anchor: anchorY)
        for row in rows {
            for column in columns {
                guard let bytes = try? tiles.archive.tile(zoom: zoom, x: column, y: row),
                      let decoded = try? VectorTile(bytes, layers: ["water", "landcover", "park", "waterway", "transportation"])
                else { continue }
                for layer in decoded.layers.values {
                    // A tile unit to a scene metre.
                    let scale = tilePoints / Double(layer.extent) / pointsPerMetre
                    let westX = (Double(column) * tilePoints - anchorX) / pointsPerMetre + shiftX
                    let northZ = (Double(row) * tilePoints - anchorY) / pointsPerMetre + shiftZ
                    let span = Double(layer.extent) * scale
                    let bounds = Bounds(minX: max(westX, low.x), minZ: max(northZ, low.z), maxX: min(westX + span, high.x), maxZ: min(northZ + span, high.z))
                    guard bounds.minX < bounds.maxX, bounds.minZ < bounds.maxZ else { continue }
                    func scene(_ point: VectorTile.Point) -> Point {
                        Point(x: westX + Double(point.x) * scale, z: northZ + Double(point.y) * scale)
                    }
                    add(layer, bounds: bounds, scene: scene)
                }
            }
        }
    }

    private mutating func add(_ layer: VectorTile.Layer, bounds: Bounds, scene: (VectorTile.Point) -> Point) {
        for feature in layer.features {
            switch (layer.name, feature.kind) {
            case ("water", .polygon), ("landcover", .polygon), ("park", .polygon):
                guard let cover = Self.cover(layer: layer.name, class: feature.string("class")) else { continue }
                for polygon in feature.polygons {
                    areas.append(Area(cover: cover, rings: polygon.map { $0.map(scene) }, bounds: bounds))
                }
            case ("transportation", .line):
                guard feature.string("brunnel") != "tunnel", let kind = Self.roadKind(feature.string("class")) else { continue }
                let isRamp: Bool
                if case .number(let ramp) = feature.properties["ramp"] { isRamp = ramp != 0 } else { isRamp = false }
                for part in feature.parts where part.count >= 2 {
                    roads.append(Road(kind: kind, isRamp: isRamp, points: part.map(scene), bounds: bounds))
                }
            case ("waterway", .line):
                guard feature.string("brunnel") != "tunnel", let kind = Self.waterwayKind(feature.string("class")) else { continue }
                for part in feature.parts where part.count >= 2 {
                    waterways.append(Waterway(kind: kind, points: part.map(scene), bounds: bounds))
                }
            default:
                continue
            }
        }
    }

    static func cover(layer: String, class name: String?) -> Cover? {
        switch layer {
        case "water": return name == "swimming_pool" ? nil : .water
        case "park": return .park
        default:
            switch name {
            case "wood": return .wood
            case "grass": return .grass
            case "wetland": return .wetland
            case "sand": return .sand
            case "farmland": return .farmland
            default: return nil
            }
        }
    }

    static func roadKind(_ name: String?) -> RoadKind? {
        switch name {
        case "motorway": .motorway
        case "trunk": .trunk
        case "primary": .primary
        case "secondary": .secondary
        case "tertiary": .tertiary
        case "minor": .minor
        case "service": .service
        default: nil
        }
    }

    static func waterwayKind(_ name: String?) -> WaterwayKind? {
        switch name {
        case "river": .river
        case "canal": .canal
        case "stream": .stream
        default: nil
        }
    }
}

extension Map3DBaseMap.RoadKind {
    /// The road's width in metres, kerb to kerb: the location modeler's
    /// far roads (`WID` in `RKFAR`), a link road at most 7 m (its near
    /// roads' `motorway_link`).
    func width(ramp: Bool) -> Float {
        let width: Float
        switch self {
        case .motorway: width = 13
        case .trunk: width = 11
        case .primary: width = 9
        case .secondary: width = 8
        case .tertiary: width = 7
        case .minor: width = 5
        case .service: width = 3.5
        }
        return ramp ? min(width, 7) : width
    }
}

extension Map3DBaseMap.WaterwayKind {
    /// The water's width in metres: the location modeler's near zone
    /// (`WATERWAY`).
    var width: Float {
        switch self {
        case .river: 14
        case .canal: 9
        case .stream: 2.5
        }
    }
}
