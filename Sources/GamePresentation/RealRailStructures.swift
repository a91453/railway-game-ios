import Foundation

// Where the real railway is on bridges and viaducts or in tunnels
// (ARCHITECTURE decision 279), so that track built along it can stand where
// the real one does: up on the viaduct south of Yilan, down in the tunnels
// round Sandiaoling, and on the ground where the real line is.
//
// The owner's `Railway/` site settles each OpenStreetMap way's structure
// (`rail-3d/physical/level-profiles.json`, after its `classifyRailStructure`
// in `structure-kind.js`): OpenStreetMap's own bridge and tunnel tags, filled
// in from the National Land Surveying and Mapping Center's railway
// geometry; `tools/real-railways/extract_structures.py` keeps the TRA's
// running lines' (`tra_structures.json`).

/// The stretches of the real TRA lines that are on bridges and viaducts or
/// in tunnels (decision 279), as `tra_structures.json` lists them.
public struct RealRailStructures: Sendable, Equatable {
    public enum Kind: String, Sendable, Hashable, Decodable {
        /// On a bridge or a viaduct.
        case bridge
        case tunnel
    }

    public struct Structure: Sendable, Equatable {
        public let kind: Kind
        /// Along the track, at least two.
        public let points: [RealRailways.Coordinate]
    }

    public let structures: [Structure]

    /// Reads the file. Throws for one out of shape: a structure of fewer
    /// than two points, or a point off the Earth.
    public init(data: Data) throws {
        struct File: Decodable {
            struct Structure: Decodable {
                let kind: Kind
                let points: [[Double]]
            }

            let structures: [Structure]
        }
        structures = try JSONDecoder().decode(File.self, from: data).structures.map { structure in
            let points = try structure.points.map { point -> RealRailways.Coordinate in
                guard point.count == 2, (-180...180).contains(point[0]), (-90...90).contains(point[1]) else {
                    throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "A structure's point is not [longitude, latitude]"))
                }
                return RealRailways.Coordinate(latitude: point[1], longitude: point[0])
            }
            guard points.count >= 2 else {
                throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "A structure has fewer than two points"))
            }
            return Structure(kind: structure.kind, points: points)
        }
    }

    /// How far from `path` a structure may lie and still be its: the other
    /// track of a double line, and the few metres a centre line strays.
    static let reach = 20.0 * RealWorldDemo.metre

    /// The stretches of `path` (in world units of `frame`) that the real
    /// line carries on a bridge or in a tunnel: each structure whose every
    /// point lies within ``reach`` of it, from the nearest point of the path
    /// to its first to the nearest to its last, one stretch where those of
    /// a kind overlap or touch. In order along the path.
    func stretches(along path: WorldPath, frame: RealWorldFrame) -> [TrackRise.Carried] {
        let xs = path.points.map(\.x), ys = path.points.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return [] }
        let box = (x: (minX - Self.reach)...(maxX + Self.reach), y: (minY - Self.reach)...(maxY + Self.reach))
        var found: [TrackRise.Carried] = []
        for structure in structures {
            let points = structure.points.map { WorldVector(frame.worldPosition(latitude: $0.latitude, longitude: $0.longitude)) }
            guard points.allSatisfy({ box.x.contains($0.x) && box.y.contains($0.y) }) else { continue }
            let nearest = points.map(path.nearest)
            guard nearest.allSatisfy({ $0.away <= Self.reach }), let start = nearest.map(\.along).min(), let end = nearest.map(\.along).max(),
                  end > start else { continue }
            found.append(TrackRise.Carried(range: start...end, kind: structure.kind))
        }
        var merged: [TrackRise.Carried] = []
        for kind in [Kind.bridge, .tunnel] {
            for stretch in found.filter({ $0.kind == kind }).sorted(by: { $0.range.lowerBound < $1.range.lowerBound }) {
                if let last = merged.last, last.kind == kind, stretch.range.lowerBound <= last.range.upperBound {
                    merged[merged.count - 1] = TrackRise.Carried(range: last.range.lowerBound...max(last.range.upperBound, stretch.range.upperBound), kind: kind)
                } else {
                    merged.append(stretch)
                }
            }
        }
        return merged.sorted { $0.range.lowerBound < $1.range.lowerBound }
    }
}
