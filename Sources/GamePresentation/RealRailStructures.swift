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
// geometry; `tools/real-railways/extract_structures.py` keeps the running
// lines' of the TRA, the High Speed Rail and the Alishan Forest Railway
// (`rail_structures.json`).

/// The stretches of Taiwan's real railways that are on bridges and viaducts
/// or in tunnels (decision 279), as `rail_structures.json` lists them.
public struct RealRailStructures: Sendable, Equatable {
    public enum Kind: String, Sendable, Hashable, Decodable {
        /// On a bridge or a viaduct.
        case bridge
        case tunnel
    }

    public struct Structure: Sendable, Equatable {
        /// The system it is a line of, as ``RealRailways/System/id`` names
        /// it (`tra_sched`).
        public let system: String
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
                let system: String
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
            return Structure(system: structure.system, kind: structure.kind, points: points)
        }
    }

    /// How far from `path` a structure may lie and still be its: the other
    /// track of a double line, and the few metres a centre line strays.
    static let reach = 20.0 * RealWorldDemo.metre

    /// The systems it has structures of.
    public var systems: Set<String> { Set(structures.map(\.system)) }

    /// How far apart a structure is followed along its length: its ways'
    /// points can be far apart on a straight viaduct.
    static let sampleSpacing = 16.0 * RealWorldDemo.metre
    /// How much of its own length a run along the path covers of the path:
    /// less, and it crosses the path rather than runs along it.
    static let alongShare = 0.8
    /// How long a run that is only part of its structure must be: the end
    /// of another line's structure where it leaves the path is shorter.
    static let shortestPart = 64.0 * RealWorldDemo.metre

    /// The stretches of `path` (in world units of `frame`) that `system`'s
    /// real line carries on a bridge or in a tunnel: each run of a
    /// structure, every ``sampleSpacing`` along it, within ``reach`` of the
    /// path and along it (``alongShare``), from the nearest point of the
    /// path to its first sample to the nearest to its last (a part of a
    /// structure at least ``shortestPart`` long); one stretch where those
    /// of a kind overlap or touch. In order along the path.
    func stretches(along path: WorldPath, frame: RealWorldFrame, system: String) -> [TrackRise.Carried] {
        let xs = path.points.map(\.x), ys = path.points.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return [] }
        let box = (x: (minX - Self.reach)...(maxX + Self.reach), y: (minY - Self.reach)...(maxY + Self.reach))
        var found: [TrackRise.Carried] = []
        for structure in structures where structure.system == system {
            let points = structure.points.map { WorldVector(frame.worldPosition(latitude: $0.latitude, longitude: $0.longitude)) }
            // A piece's box, not only its points: a straight viaduct's two
            // points can lie kilometres beyond a short path along it.
            guard zip(points, points.dropFirst()).contains(where: { a, b in
                min(a.x, b.x) <= box.x.upperBound && box.x.lowerBound <= max(a.x, b.x)
                    && min(a.y, b.y) <= box.y.upperBound && box.y.lowerBound <= max(a.y, b.y)
            }) || points.contains(where: { box.x.contains($0.x) && box.y.contains($0.y) }) else { continue }
            var samples = [points[0]]
            for (a, b) in zip(points, points.dropFirst()) {
                let steps = max(1, Int(((b - a).length / Self.sampleSpacing).rounded(.up)))
                samples += (1...steps).map { a + (b - a) * (Double($0) / Double(steps)) }
            }
            var run: [Double] = [], length = 0.0, first = 0
            func close(at last: Int) {
                defer { run = []; length = 0 }
                guard run.count >= 2, let start = run.min(), let end = run.max(), end - start >= Self.alongShare * length else { return }
                guard (first == 0 && last == samples.count - 1) || end - start >= Self.shortestPart else { return }
                found.append(TrackRise.Carried(range: start...end, kind: structure.kind))
            }
            for (index, sample) in samples.enumerated() {
                let inBox = box.x.contains(sample.x) && box.y.contains(sample.y)
                guard inBox, case let nearest = path.nearest(sample), nearest.away <= Self.reach else {
                    close(at: index - 1)
                    continue
                }
                if run.isEmpty { first = index } else { length += (sample - samples[index - 1]).length }
                run.append(nearest.along)
            }
            close(at: samples.count - 1)
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
