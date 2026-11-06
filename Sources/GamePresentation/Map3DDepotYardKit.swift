import Foundation

/// Optional depot furniture. Recipes are independent of map placement and saves.
/// Geometry uses the existing station builder's x forward, y up, z right.
/// Public connectors use native x forward, y left, z up, in metres.
public enum Map3DDepotYardKit {
    public enum System: String, CaseIterable, Sendable {
        case wenhu, metro, lightRail, taiwanRail

        /// Rail head to the underside of a portal or canopy. Estimates; see README.
        public var clearHeight: Float {
            switch self {
            case .wenhu: 4.8
            case .metro: 6.0
            case .lightRail: 6.3
            case .taiwanRail: 7.2
            }
        }
        public var hasOverheadWire: Bool { self != .wenhu }
    }

    public enum Kind: String, CaseIterable, Sendable {
        case shedHead, shedMiddle, shedTail, parkingCanopy, washFrame
        case office, fence, gate, guardHouse
    }

    public struct Part: Sendable {
        public let kind: Kind
        public let system: System
        public let tracks: Int
        public let length: Float
        public var id: String { "depot-yard-\(system.rawValue)-\(kind.rawValue)-\(tracks)" }
        public var width: Float {
            switch kind {
            case .fence: 0.35
            case .gate, .office: 8
            case .guardHouse: 3
            case .washFrame: 6.45
            default: max(8, Float(tracks) * 5.1 + 0.7)
            }
        }
        /// Rail heads top out at y=0.45 internally and z=0.45 outside.
        public var connectors: [Map3DStationKit.Connector] {
            let centres = trackCentres
            var result = centres.flatMap { c in [
                connector("track-\(c)-front", length / 2, c, 0.45, 1),
                connector("track-\(c)-back", -length / 2, c, 0.45, -1)
            ] }
            if [.shedHead, .shedMiddle, .shedTail, .parkingCanopy, .fence].contains(kind) {
                result += [connector("seam-front", length / 2, 0, 0, 1), connector("seam-back", -length / 2, 0, 0, -1)]
            }
            if result.isEmpty { result = [connector("ground-anchor", 0, 0, 0, 1)] }
            return result
        }
        public var trackCentres: [Float] {
            guard [.shedHead, .shedMiddle, .shedTail, .parkingCanopy, .washFrame].contains(kind) else { return [] }
            return (0..<tracks).map { (Float($0) - Float(tracks - 1) / 2) * 5.1 }
        }
        private func connector(_ name: String, _ x: Float, _ internalZ: Float, _ height: Float, _ direction: Float) -> Map3DStationKit.Connector {
            .init(name: name, position: Map3DPoint(x, -internalZ, height), normal: Map3DPoint(direction, 0, 0))
        }
    }

    /// Each middle bay is 12 m; repeating it gives a shed longer than the
    /// longest built-in full train while keeping every asset small.
    public static func part(_ kind: Kind, system: System, tracks: Int = 2) -> Part {
        let valid = kind == .parkingCanopy ? 2...6 : 2...4
        let count = kind == .washFrame ? 1 : valid.contains(tracks) ? tracks : valid.lowerBound
        let length: Float = switch kind {
        case .shedHead, .shedMiddle, .shedTail, .parkingCanopy: 12
        case .fence: 4
        case .office: 12
        case .gate: 8
        case .guardHouse: 3.5
        case .washFrame: 2.4
        }
        return Part(kind: kind, system: system, tracks: count, length: length)
    }

    public static func model(for part: Part, far: Bool = false) -> Map3DModelPack.Model {
        var b = StationKitBuilder()
        let w = part.width
        let isShed = [.shedHead, .shedMiddle, .shedTail].contains(part.kind)
        // The head's lintel hangs 0.625 m below the eaves. Its underside
        // (rather than the eaves) is the specified rail-to-opening clearance.
        let h = part.system.clearHeight + 0.45 + (isShed ? 0.625 : 0)
        if far {
            let height: Float = switch part.kind {
            case .shedHead, .shedMiddle, .shedTail: h + 1.5
            case .parkingCanopy: h + 0.3
            case .washFrame: h + 0.5
            case .office: 9.8
            case .fence, .gate: 2.5
            case .guardHouse: 3.4
            }
            b.box(0, 0, 0, part.length, w, height, part.kind == .shedHead || part.kind == .shedMiddle || part.kind == .shedTail ? Map3DDepotFacilities.wall : Map3DPalette.concrete)
            return .flat(named: part.id + "-far", from: b.mesh)
        }
        switch part.kind {
        case .shedHead, .shedMiddle, .shedTail:
            b.box(0, 0, 0, part.length, w, 0.2, Map3DPalette.concrete)
            for side: Float in [-1, 1] {
                b.box(0, 0, side * (w / 2 - 0.18), part.length, 0.36, h, Map3DDepotFacilities.wall)
                let rise: Float = 2.6, slope = hypotf(w / 2, rise)
                b.slab(centre: Map3DPoint(0, h + rise / 2, side * w / 4),
                       up: Map3DPoint(0, rise / slope, -side * w / 2 / slope),
                       length: part.length + 0.7, wide: slope, thickness: 0.22, color: Map3DPalette.roof)
                for x: Float in [-3.5, 3.5] { b.box(x, 3.425, side * (w / 2 - 0.02), 2.2, 0.05, 1.25, Map3DDepotFacilities.glass) }
            }
            if part.kind == .shedTail { b.box(-part.length / 2 + 0.18, 0, 0, 0.36, w, h, Map3DDepotFacilities.wall) }
            if part.kind == .shedHead {
                for i in 0...part.tracks { b.box(part.length / 2 - 0.18, 0, -w / 2 + Float(i) * w / Float(part.tracks), 0.36, 0.42, h, Map3DDepotFacilities.steel) }
                b.box(part.length / 2 - 0.18, h - 0.625, 0, 0.36, w, 0.55, Map3DPalette.canopy)
            }
            for c in part.trackCentres {
                guideway(&b, system: part.system, x: 0, z: c, length: part.length - 0.2)
                if part.system != .wenhu { b.box(0, 0.34, c, part.length - 1, 0.72, 0.02, Map3DDepotFacilities.steel) }
            }
            b.box(0, h + 2.64, 0, part.length - 1, 0.28, 0.24, Map3DDepotFacilities.steel)
        case .parkingCanopy:
            for x: Float in [-5.7, 5.7] { for z: Float in [-w / 2 + 0.2, w / 2 - 0.2] { b.box(x, 0, z, 0.25, 0.25, h, Map3DDepotFacilities.steel) } }
            b.box(0, h, 0, 12.4, w + 0.7, 0.24, Map3DPalette.roof)
            for c in part.trackCentres { guideway(&b, system: part.system, x: 0, z: c, length: 11.8) }
        case .washFrame:
            for z: Float in [-3, 3] { b.box(0, 0, z, 1.4, 0.45, h, Map3DDepotFacilities.steel) }
            b.box(0, h, 0, 2.4, 6.45, 0.4, Map3DPalette.canopy)
            for z: Float in [-2.6, 2.6] { b.box(0, 1.1, z, 0.15, 0.1, h - 1.5, Map3DDepotFacilities.glass) }
            guideway(&b, system: part.system, x: 0, z: 0, length: 2.4)
        case .office:
            b.box(0, 0, 0, 12, 8, 9.4, Map3DDepotFacilities.wall)
            for level: Float in [1.6, 4.7, 7.8] { for x: Float in [-3.5, 0, 3.5] { b.box(x, level, 4.03, 1.5, 0.06, 1.2, Map3DDepotFacilities.glass) } }
            b.box(0, 9.4, 0, 12.6, 8.6, 0.24, Map3DPalette.roof)
            b.box(3, 0, 4.04, 1.5, 0.08, 2.5, Map3DDepotFacilities.dark)
        case .fence:
            for x: Float in [-1.9, 1.9] { b.box(x, 0, 0, 0.22, 0.4, 2.5, Map3DDepotFacilities.steel) }
            b.box(0, 0, 0, 4, 0.28, 1.8, Map3DDepotFacilities.wall)
            b.box(0, 1.8, 0, 4, 0.35, 0.12, Map3DPalette.roof)
        case .gate:
            for x: Float in [-3.8, 3.8] { b.box(x, 0, 0, 0.35, 0.5, 2.7, Map3DDepotFacilities.wall) }
            b.box(0, 2.45, 0, 8, 0.28, 0.22, Map3DDepotFacilities.steel)
            for x: Float in stride(from: -3.4, through: 3.4, by: 0.85) { b.box(x, 0, 0, 0.08, 0.1, 2.4, Map3DDepotFacilities.steel) }
        case .guardHouse:
            b.box(0, 0, 0, 3.5, 3, 3, Map3DDepotFacilities.wall)
            b.box(0, 3, 0, 3.9, 3.4, 0.2, Map3DPalette.roof)
            b.box(1.76, 1.1, 0, 0.06, 1.4, 1.2, Map3DDepotFacilities.glass)
        }
        return .flat(named: part.id, from: b.mesh)
    }

    public static func shed(system: System, tracks: Int, middleBays: Int, far: Bool = false) -> [Map3DModelPack.Model] {
        [model(for: part(.shedHead, system: system, tracks: tracks), far: far)] +
        (0..<max(0, middleBays)).map { _ in model(for: part(.shedMiddle, system: system, tracks: tracks), far: far) } +
        [model(for: part(.shedTail, system: system, tracks: tracks), far: far)]
    }

    // Wenhu's existing APM256 model puts load wheels at ±0.99 m and guide
    // bearings at ±1.02 m. Use its dimensions, never the steel rail recipe.
    private static func guideway(_ b: inout StationKitBuilder, system: System, x: Float, z: Float, length: Float) {
        if system == .wenhu {
            b.box(x, 0.2, z, length, 2.7, 0.16, Map3DPalette.concrete)
            for side: Float in [-1, 1] {
                b.box(x, 0.36, z + side * 0.99, length, 0.36, 0.09, Map3DDepotFacilities.dark)
                b.box(x, 0.33, z + side * 1.27, length, 0.10, 0.32, Map3DDepotFacilities.steel)
            }
        } else {
            b.box(x, 0.2, z, length, 1.9, 0.14, Map3DDepotFacilities.dark)
            for side: Float in [-0.5335, 0.5335] { b.box(x, 0.35, z + side, length, 0.075, 0.1, Map3DPalette.railTop) }
        }
    }

    private static func parkedTrain(_ b: inout StationKitBuilder, system: System, z: Float) {
        switch system {
        case .wenhu:
            let centres: [Float] = [20.67, 6.89, -6.89, -20.67]
            for (index, x) in centres.enumerated() {
                b.add(Map3DWenhuAPM256.model(index.isMultiple(of: 2) ? .a : .b, far: true), at: Map3DPoint(x, 0.45, z))
            }
        case .metro:
            let centres: [Float] = [58.855, 35.25, 11.75, -11.75, -35.25, -58.855]
            for (index, x) in centres.enumerated() { b.add(Map3DC381.model(Map3DC381.arrangement[index], far: true), at: Map3DPoint(x, 0.45, z)) }
        case .lightRail:
            var x: Float = -15.2
            for unit in Map3DKaohsiungCitadis.Unit.allCases {
                let length = Map3DKaohsiungCitadis.length(unit)
                b.add(Map3DKaohsiungCitadis.model(unit, far: true), at: Map3DPoint(x + length / 2, 0.45, z))
                x += length + Map3DKaohsiungCitadis.joint
            }
        case .taiwanRail:
            for placement in Map3DEMU3000.placements { b.add(Map3DEMU3000.model(placement.unit, far: true), at: Map3DPoint(placement.x, 0.45, z)) }
        }
    }

    /// Four review scenes with a full existing set on an exposed siding.
    public static func reviewScene(system: System) -> Map3DModelPack.Model {
        var b = StationKitBuilder()
        let bays: Int = switch system { case .wenhu: 5; case .metro: 12; case .lightRail: 3; case .taiwanRail: 21 }
        let length = Float(bays) * 12
        let tracks = system == .wenhu || system == .lightRail ? 2 : 4
        b.box(0, -0.22, 0, length + 28, 78, 0.2, Map3DPalette.concrete)
        for index in 0..<bays {
            let kind: Kind = index == 0 ? .shedTail : index == bays - 1 ? .shedHead : .shedMiddle
            b.add(model(for: part(kind, system: system, tracks: tracks)), at: Map3DPoint(Float(index) * 12 - length / 2 + 6, 0, -20))
            b.add(model(for: part(.parkingCanopy, system: system, tracks: tracks)), at: Map3DPoint(Float(index) * 12 - length / 2 + 6, 0, 3))
        }
        b.add(model(for: part(.washFrame, system: system)), at: Map3DPoint(length / 2 + 3, 0, -20))
        b.add(model(for: part(.office, system: system)), at: Map3DPoint(-length / 2 + 9, 0, 32))
        b.add(model(for: part(.gate, system: system)), at: Map3DPoint(length / 2 - 14, 0, 36))
        b.add(model(for: part(.guardHouse, system: system)), at: Map3DPoint(length / 2 - 7, 0, 34))
        for index in 0..<min(16, bays * 2) {
            b.add(model(for: part(.fence, system: system)), at: Map3DPoint(Float(index) * 4 - length / 2 - 8, 0, 36))
        }
        guideway(&b, system: system, x: 0, z: 22, length: length - 4)
        parkedTrain(&b, system: system, z: 22)
        if system == .taiwanRail {
            // Yard-only 55 m gantry pitch; these preview props are not live track.
            for x in stride(from: -length / 2 + 20, through: length / 2 - 12, by: Float(55)) {
                for z: Float in [17, 27] { b.box(x, 0, z, 0.26, 0.26, 7.1, Map3DPalette.mastSteel) }
                b.box(x, 7.1, 22, 0.20, 10.2, 0.20, Map3DPalette.mastSteel)
                b.box(x, 5.65, 22, 0.12, 0.12, 1.45, Map3DPalette.mastSteel)
            }
            b.box(0, 5.65, 22, length - 4, 0.06, 0.06, Map3DPalette.overheadWire)
        }
        return .flat(named: "depot-yard-scene-\(system.rawValue)", from: b.mesh)
    }
}
