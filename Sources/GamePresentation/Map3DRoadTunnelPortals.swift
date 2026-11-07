/// Decision 611: the road tunnels' portals (and the rail studies, which
/// the map does not draw: decision 359's portal stays). Metres: +x into
/// the tunnel, +y up, +z right. The scene places them
/// (`Map3DRoadTunnels.swift`) and covers their tops with the hillside.
public enum Map3DRoadTunnelPortals {
    public enum Style: String, CaseIterable, Sendable {
        case dividedExpressway, mountainArch, nameplate, narrowLane, daylightGallery
    }
    public enum Width: String, CaseIterable, Sendable { case oneWay, twoWay }
    public enum RailTracks: String, CaseIterable, Sendable { case single, double }

    public struct Connector: Sendable {
        /// Surface centre at the outer entrance. Rail studies use the same origin.
        public let roadCenter: Map3DPoint
        public let roadElevation: Float
        public let intoTunnel: Map3DPoint
    }
    public struct Part: Sendable {
        public let mesh: Map3DMesh
        public let connector: Connector
        public let clearWidth: Float
        public let clearHeight: Float
        /// The cap at the deep end prevents a see-through preview.
        public let liningDepth: Float
        /// Decision 611: how far the facade reaches each side of the
        /// middle, the head wall's top, the outer entrance (0, or the
        /// gallery's 12 m out) and the foot, all metres; the cap's depth.
        public let outerHalfWidth: Float
        public let top: Float
        public let front: Float
        public let floor: Float
        public let innerEnd: Float
        /// The bores' middles across.
        public let centres: [Float]
    }

    public static let wallThickness: Float = 1.2
    public static let overRoof: Float = 1.3
    public static let embed: Float = 0.8
    public static let wingLength: Float = 8
    public static let wingSplay: Float = 2
    public static let liningDepth: Float = 8
    public static let galleryLength: Float = 12

    /// Decision 611: the lining's colours, which face down (``make``).
    static let liningShades: [UInt32] = [Map3DPalette.tunnelWall, Map3DPalette.tunnelLining,
                                         Map3DColor.rgb(0x4B5162), Map3DColor.rgb(0x353948)]
    static let capColor = Map3DColor.rgb(0x222630)

    /// `depth`: how far in the lining reaches before its cap (decision
    /// 611: less where the drawn ground rises inside it).
    public static func make(_ style: Style, width: Width, depth: Float = liningDepth) -> Part {
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
        case (.daylightGallery, .oneWay): half = 3.75
        case (.daylightGallery, .twoWay): half = 5.25
        }
        let clear: Float = style == .narrowLane ? 4.7 : 5.2
        let spring: Float = style == .mountainArch ? 3.7 : (style == .narrowLane ? 4.35 : clear)
        let divided = style == .dividedExpressway
        let centres: [Float] = divided ? [-(half + 0.7), half + 0.7] : [0]
        return build(half: half, clear: clear, spring: spring, centres: centres,
                     shoulder: style == .narrowLane ? 1.2 : 2,
                     nameplate: style == .nameplate, gallery: style == .daylightGallery,
                     shape: style == .mountainArch ? .roadArch : (style == .narrowLane ? .narrow : .box),
                     floor: -embed, depth: depth)
    }

    /// Decision 359's 3.2 m half bore, 2.8 m spring and 6 m crown. The
    /// double-track study is a widened shared bore; both have a daylight form.
    public static func makeRail(_ tracks: RailTracks, daylight: Bool) -> Part {
        let half: Float = tracks == .single ? 3.2 : 6.3
        return build(half: half, clear: 6, spring: 2.8, centres: [0],
                     shoulder: 2, nameplate: false, gallery: daylight,
                     shape: .railArch, floor: -1.2, depth: liningDepth)
    }

    private enum Shape { case box, roadArch, narrow, railArch }

    private static func build(half: Float, clear: Float, spring: Float, centres: [Float],
                              shoulder: Float, nameplate: Bool, gallery: Bool,
                              shape: Shape, floor: Float, depth: Float) -> Part {
        let outer = (centres.last ?? 0) + half + shoulder
        let top = clear + overRoof + (nameplate ? 1.1 : 0)
        let front: Float = gallery ? -galleryLength : 0
        let innerStart: Float = gallery ? wallThickness : front + wallThickness
        let depth = min(max(depth, 1), liningDepth)
        let innerEnd = innerStart + depth
        let bandLength = depth / Float(liningShades.count)
        let wall = Map3DPalette.concrete, trim = Map3DPalette.portal
        let shades = liningShades, cap = capColor
        var mesh = Map3DMesh()
        func p(_ z: Float, _ y: Float, _ x: Float) -> Map3DPoint { Map3DPoint(x, y, z) }
        func face(_ corners: [Map3DPoint], toward: Map3DPoint, color: UInt32) {
            guard corners.count >= 3,
                  let n = (corners[1] - corners[0]).cross(corners[2] - corners[0]).normalized else { return }
            let c = n.dot(toward) < 0 ? Array(corners.reversed()) : corners
            if c.count == 4 { mesh.addQuad(c[0], c[1], c[2], c[3], color: color) }
            else { mesh.addFacet(c, color: color) }
        }
        func panel(_ a: Float, _ b: Float, _ low: Float, _ high: Float, _ x: Float, _ color: UInt32) {
            guard b > a else { return }
            face([p(a, low, x), p(b, low, x), p(b, high, x), p(a, high, x)],
                 toward: Map3DPoint(x == front ? -1 : 1, 0, 0), color: color)
        }
        func roof(_ c: Float) -> [(Float, Float)] {
            switch shape {
            case .box: return [(c - half, clear), (c + half, clear)]
            case .narrow: return [(c - half, spring), (c - half * 0.74, clear),
                                  (c + half * 0.74, clear), (c + half, spring)]
            case .roadArch: return [(c - half, spring), (c - half * 0.76, 4.5),
                                    (c - half * 0.4, clear), (c + half * 0.4, clear),
                                    (c + half * 0.76, 4.5), (c + half, spring)]
            case .railArch: return [(c - half, spring), (c - half + 1.4, clear),
                                    (c + half - 1.4, clear), (c + half, spring)]
            }
        }
        // The facade's two faces, with solid jambs and faceted spandrels.
        for x: Float in [front, gallery ? 0 : wallThickness] {
            for (index, c) in centres.enumerated() {
                let left = c - half, right = c + half
                let leftEnd = index == 0 ? -outer : centres[index - 1] + half
                panel(leftEnd, left, floor, top, x, wall)
                if index == centres.count - 1 { panel(right, outer, floor, top, x, wall) }
                let profile = roof(c)
                for i in 1..<profile.count {
                    let a = profile[i - 1], b = profile[i]
                    face([p(a.0, a.1, x), p(b.0, b.1, x), p(b.0, top, x), p(a.0, top, x)],
                         toward: Map3DPoint(x == front ? -1 : 1, 0, 0), color: wall)
                }
            }
        }
        for c in centres {
            let profile = roof(c)
            // Gallery is an open-air retaining shell: 12 m concrete cover and
            // sidewalls between the outer entrance and the mountain face.
            if gallery {
                for side: Float in [-1, 1] {
                    let z = c + half * side
                    face([p(z, floor, front), p(z, spring, front), p(z, spring, 0), p(z, floor, 0)],
                         toward: Map3DPoint(0, 0, -side), color: Map3DPalette.tunnelWall)
                    face([p(z + side * shoulder, floor, front), p(z + side * shoulder, top, front),
                          p(z + side * shoulder, top, 0), p(z + side * shoulder, floor, 0)],
                         toward: Map3DPoint(0, 0, side), color: wall)
                }
                for i in 1..<profile.count {
                    let a = profile[i - 1], b = profile[i]
                    face([p(a.0, a.1, front), p(b.0, b.1, front), p(b.0, b.1, 0), p(a.0, a.1, 0)],
                         toward: Map3DPoint(0, -1, 0), color: Map3DPalette.tunnelWall)
                }
                face([p(-outer, top, front), p(outer, top, front), p(outer, top, 0), p(-outer, top, 0)],
                     toward: .up, color: trim)
            }
            // Four bands, a quarter of the depth each: the deep wall darker.
            for band in 0..<shades.count {
                let x0 = innerStart + Float(band) * bandLength
                let x1 = x0 + bandLength
                for side: Float in [-1, 1] {
                    let z = c + half * side
                    face([p(z, floor, x0), p(z, spring, x0), p(z, spring, x1), p(z, floor, x1)],
                         toward: Map3DPoint(0, 0, -side), color: shades[band])
                }
                for i in 1..<profile.count {
                    let a = profile[i - 1], b = profile[i]
                    face([p(a.0, a.1, x0), p(b.0, b.1, x0), p(b.0, b.1, x1), p(a.0, a.1, x1)],
                         toward: Map3DPoint(0, -1, 0), color: shades[band])
                }
                face([p(c - half, floor, x0), p(c + half, floor, x0),
                      p(c + half, floor, x1), p(c - half, floor, x1)], toward: .up, color: shades[band])
            }
            // A solid polygon at 8 m makes every oblique preview opaque.
            var end = [p(c - half, floor, innerEnd)]
            end += profile.map { p($0.0, $0.1, innerEnd) }
            end.append(p(c + half, floor, innerEnd))
            face(end, toward: Map3DPoint(-1, 0, 0), color: cap)
            face(Array(end.reversed()), toward: Map3DPoint(1, 0, 0), color: cap)
            for i in 1..<profile.count {
                let a = profile[i - 1], b = profile[i]
                face([p(a.0, a.1, front - 0.2), p(b.0, b.1, front - 0.2),
                      p(b.0, b.1 + 0.45, front - 0.2), p(a.0, a.1 + 0.45, front - 0.2)],
                     toward: Map3DPoint(-1, 0, 0), color: trim)
            }
        }
        // An outside shell closes the lining when seen from above or beside.
        for side: Float in [-1, 1] {
            let z = outer * side
            face([p(z, floor, 0), p(z, top, 0), p(z, top, innerEnd), p(z, floor, innerEnd)],
                 toward: Map3DPoint(0, 0, side), color: wall)
        }
        // Decision 611 (#1885's review, 1): no flat roof over it; the
        // scene lays the hillside over the head wall's top instead.
        // The same 8 m / 2 m splay as decision 359, attached at the entrance.
        for side: Float in [-1, 1] {
            let z = outer * side, tip = (outer + wingSplay) * side
            let edge = 0.45 * side
            face([p(z, floor, front), p(z, top - 0.2, front),
                  p(tip, 0.6, front - wingLength), p(tip, floor, front - wingLength)],
                 toward: Map3DPoint(0, 0, -side), color: wall)
            face([p(z + edge, floor, front), p(z + edge, top - 0.2, front),
                  p(tip + edge, 0.6, front - wingLength), p(tip + edge, floor, front - wingLength)],
                 toward: Map3DPoint(0, 0, side), color: wall)
            face([p(z, top - 0.2, front), p(z + edge, top - 0.2, front),
                  p(tip + edge, 0.6, front - wingLength), p(tip, 0.6, front - wingLength)],
                 toward: .up, color: trim)
        }
        if nameplate {
            face([p(-half * 0.8, clear + 0.65, front - 0.24),
                  p(half * 0.8, clear + 0.65, front - 0.24),
                  p(half * 0.8, top - 0.28, front - 0.24),
                  p(-half * 0.8, top - 0.28, front - 0.24)],
                 toward: Map3DPoint(-1, 0, 0), color: trim)
        }
        // Decision 611 (#1885's review, 2): the lining and its cap face
        // down, so neither the sun nor the sky lights them; only the
        // ground's dim light reaches in, as into a real bore.
        let lining = Set(shades + [cap])
        mesh.restyleVertices { vertex in
            guard lining.contains(vertex.color) else { return }
            (vertex.nx, vertex.ny, vertex.nz) = (0, -1, 0)
        }
        return Part(mesh: mesh,
                    connector: Connector(roadCenter: p(0, 0, front), roadElevation: 0,
                                         intoTunnel: Map3DPoint(1, 0, 0)),
                    clearWidth: 2 * half, clearHeight: clear, liningDepth: depth,
                    outerHalfWidth: outer, top: top, front: front, floor: floor, innerEnd: innerEnd, centres: centres)
    }
}
