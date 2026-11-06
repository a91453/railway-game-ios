/// Decision 611 art study. Local coordinates are metres: +x is into the
/// tunnel, +y is up, +z is the road's right. The road surface is y = 0.
/// ROADTUNNEL will choose placements; this file does not alter map drawing.
public enum Map3DRoadTunnelPortals {
    public enum Style: String, CaseIterable, Sendable {
        case dividedExpressway, mountainArch, nameplate, narrowLane
    }

    public enum Width: String, CaseIterable, Sendable {
        case oneWay, twoWay
    }

    public struct Connector: Sendable {
        /// Road centre on the surface, in the mesh's local metres.
        public let roadCenter: Map3DPoint
        public let roadElevation: Float
        public let intoTunnel: Map3DPoint
    }

    public struct Part: Sendable {
        public let mesh: Map3DMesh
        public let connector: Connector
        /// Clear span of each opening, in metres.
        public let clearWidth: Float
        public let clearHeight: Float
    }

    public static let wallThickness: Float = 1.2
    public static let overRoof: Float = 1.3
    public static let embed: Float = 0.8
    public static let wingLength: Float = 8
    public static let wingSplay: Float = 2

    /// Build one portal with its pair of 8 m wing walls. A divided portal
    /// has two openings and a solid centre pier in both width variants.
    public static func make(_ style: Style, width: Width) -> Part {
        let divided = style == .dividedExpressway
        let half: Float
        switch (style, width) {
        case (.dividedExpressway, .oneWay): half = 3.75
        case (.dividedExpressway, .twoWay): half = 5.25
        case (.mountainArch, .oneWay): half = 3.1
        case (.mountainArch, .twoWay): half = 4.6
        case (.nameplate, .oneWay): half = 4
        case (.nameplate, .twoWay): half = 5.5
        case (.narrowLane, .oneWay): half = 2.5
        case (.narrowLane, .twoWay): half = 3.5
        }
        let clear: Float = style == .narrowLane ? 4.7 : 5.2
        let spring: Float = style == .mountainArch ? 3.7 : clear
        let pier: Float = 1.4
        let centres: [Float] = divided ? [-(half + pier / 2), half + pier / 2] : [0]
        let outer = (centres.last ?? 0) + half + (style == .narrowLane ? 1.2 : 2)
        let top = clear + overRoof + (style == .nameplate ? 1.1 : 0)
        let concrete = Map3DPalette.concrete
        let trim = Map3DPalette.portal
        let lining = Map3DPalette.tunnelWall
        var mesh = Map3DMesh()
        func point(_ z: Float, _ y: Float, _ x: Float = 0) -> Map3DPoint { Map3DPoint(x, y, z) }
        func face(_ corners: [Map3DPoint], toward: Map3DPoint, color: UInt32) {
            guard corners.count > 2, let normal = (corners[1] - corners[0]).cross(corners[2] - corners[0]).normalized else { return }
            let ordered = normal.dot(toward) < 0 ? Array(corners.reversed()) : corners
            if ordered.count == 4 { mesh.addQuad(ordered[0], ordered[1], ordered[2], ordered[3], color: color) }
            else { mesh.addFacet(ordered, color: color) }
        }
        func panel(_ left: Float, _ right: Float, _ bottom: Float, _ roof: Float, _ x: Float, _ color: UInt32) {
            face([point(left, bottom, x), point(right, bottom, x), point(right, roof, x), point(left, roof, x)],
                 toward: Map3DPoint(x == 0 ? -1 : 1, 0, 0), color: color)
        }
        // Aperture roof is a sequence of straight facets, never a smooth arch.
        func roof(_ centre: Float) -> [(Float, Float)] {
            if style == .mountainArch {
                return [(-half, spring), (-half * 0.76, 4.5), (-half * 0.4, clear),
                        (half * 0.4, clear), (half * 0.76, 4.5), (half, spring)]
                    .map { (centre + $0.0, $0.1) }
            }
            if style == .narrowLane {
                return [(centre - half, 4.35), (centre - half * 0.74, clear),
                        (centre + half * 0.74, clear), (centre + half, 4.35)]
            }
            return [(centre - half, clear), (centre + half, clear)]
        }
        for x: Float in [0, wallThickness] {
            for (index, centre) in centres.enumerated() {
                let left = centre - half, right = centre + half
                let leftEnd = index == 0 ? -outer : centres[index - 1] + half
                let rightEnd = index == centres.count - 1 ? outer : right
                panel(leftEnd, left, -embed, top, x, concrete)
                if index == centres.count - 1 { panel(right, rightEnd, -embed, top, x, concrete) }
                let profile = roof(centre)
                for segment in 1..<profile.count {
                    let a = profile[segment - 1], b = profile[segment]
                    face([point(a.0, a.1, x), point(b.0, b.1, x), point(b.0, top, x), point(a.0, top, x)],
                         toward: Map3DPoint(x == 0 ? -1 : 1, 0, 0), color: concrete)
                }
            }
        }
        // Opening reveals and dark inner lining make the road visibly enter.
        for centre in centres {
            let profile = roof(centre)
            for side: Float in [-1, 1] {
                let z = centre + side * half
                face([point(z, -embed), point(z, spring), point(z, spring, wallThickness), point(z, -embed, wallThickness)],
                     toward: Map3DPoint(0, 0, -side), color: lining)
            }
            for segment in 1..<profile.count {
                let a = profile[segment - 1], b = profile[segment]
                face([point(a.0, a.1), point(b.0, b.1), point(b.0, b.1, wallThickness), point(a.0, a.1, wallThickness)],
                     toward: Map3DPoint(0, -1, 0), color: lining)
                // Proud, planar concrete band around the opening.
                let rise: Float = 0.45
                face([point(a.0, a.1, -0.2), point(b.0, b.1, -0.2),
                      point(b.0, b.1 + rise, -0.2), point(a.0, a.1 + rise, -0.2)],
                     toward: Map3DPoint(-1, 0, 0), color: trim)
            }
        }
        for side: Float in [-1, 1] {
            let z = outer * side, tip = (outer + wingSplay) * side
            face([point(z, -embed), point(z, top - 0.2), point(tip, 0.6, -wingLength), point(tip, -embed, -wingLength)],
                 toward: Map3DPoint(0, 0, -side), color: concrete)
            let offset: Float = 0.45 * side
            face([point(z + offset, -embed), point(z + offset, top - 0.2),
                  point(tip + offset, 0.6, -wingLength), point(tip + offset, -embed, -wingLength)],
                 toward: Map3DPoint(0, 0, side), color: concrete)
            face([point(z, top - 0.2), point(z + offset, top - 0.2),
                  point(tip + offset, 0.6, -wingLength), point(tip, 0.6, -wingLength)],
                 toward: .up, color: trim)
        }
        // The large portal has a blank, flat fascia for a later name plate.
        if style == .nameplate {
            face([point(-half * 0.8, clear + 0.65, -0.24), point(half * 0.8, clear + 0.65, -0.24),
                  point(half * 0.8, top - 0.28, -0.24), point(-half * 0.8, top - 0.28, -0.24)],
                 toward: Map3DPoint(-1, 0, 0), color: trim)
        }
        let connector = Connector(roadCenter: point(0, 0), roadElevation: 0, intoTunnel: Map3DPoint(1, 0, 0))
        return Part(mesh: mesh, connector: connector, clearWidth: 2 * half, clearHeight: clear)
    }
}
