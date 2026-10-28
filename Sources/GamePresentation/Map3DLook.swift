import GameCore

/// Decision 370: the 3D map's model look ((e), the owner's pick of
/// 2026-10-23, `docs/art/map3d-mapbox-look-2026-10-23/README.md`). The
/// ground, land cover, roads and their kerbs, the centre line and the track's
/// bed take ``Map3DPalette``'s own colours; every other colour the city is
/// built in is drawn as a pale, calm version of itself (its hue kept), so
/// neighbours still differ. What the player built and runs keeps its colour:
/// the player's buildings, the track, the platforms and their yellow edge,
/// the canopies, viaducts and the rooftop water tanks (``kept``). The trains,
/// people and vehicles are never passed through it.
///
/// Ported from the preview's `compose_play.py` (`REMAP`, `KEEP`, `pale()`,
/// `mid=62 navy=6 ground=ECEEF6 icon`) in the reference repository's
/// `Railway/game-art-previews/docs/art/map3d-mapbox-look-2026-10-23/`.
///
/// Decision 451: softer (``city``, ``close``), and the colours that tell
/// the player something kept (``functional``). Made once as a scene is
/// built: no vertex, texture or draw is added, so the frame costs the same.
public enum Map3DLook {
    /// The colours left as they are: the palette's (e) colours, and what
    /// the player built and runs.
    static let kept: Set<UInt32> = {
        let palette: [UInt32] = [
            Map3DPalette.ground, Map3DPalette.plaza, Map3DPalette.park, Map3DPalette.farm, Map3DPalette.water,
            Map3DPalette.cover(.grass), Map3DPalette.cover(.sand), Map3DPalette.cover(.wetland), Map3DPalette.cover(.wood),
            Map3DPalette.road(.motorway), Map3DPalette.road(.primary), Map3DPalette.road(.tertiary), Map3DPalette.road(.minor),
            Map3DPalette.sidewalk, Map3DPalette.centreLine, Map3DPalette.ballast, Map3DPalette.crown,
            // The player's tunnels (decision 359), which the preview had
            // none of: their bore keeps its shade.
            Map3DPalette.portal, Map3DPalette.tunnelWall, Map3DPalette.tunnelLining, Map3DPalette.tunnelLamp,
        ]
        let played: [UInt32] = [
            0xFFC86B, 0xFFE2A6, 0x26385C, // the player's buildings (decision 205)
            0x6E7379, 0xC9CED4, // rail, rail top
            0xDCD6C8, 0xF2C94C, 0x2F6DB5, // platform, its edge, canopy blue
            0xCFCBC2, 0x8E9CA8, 0x9DB07E, // viaduct concrete, bridge, embankment
            0x3B7DD8, 0x285491, 0x2C5DA1, 0x326BB8, 0x3774C8, // rooftop water tanks
        ].map(Map3DColor.rgb)
        // Decision 446: the scooters parked in the arcades, vehicles too.
        return Set(palette + played).union(Map3DScooter.parked).union(functional)
    }()

    /// Decision 451: the colours that tell the player something, which a
    /// pale version would hide: the traffic signals' housings and lights,
    /// lit and unlit (the cars' and the walkers', decisions 355, 429 and
    /// 445); the level crossings' red and black (decision 263), and the
    /// red kerb line, which is the same red (decision 447).
    static let functional: Set<UInt32> = Set(Map3DProp.signalLights.flatMap { [$0.lit, $0.unlit] } + [
        Map3DProp.signalHousing, Map3DPedestrianSignal.housing,
        Map3DScene.Builder.barrierRed, Map3DScene.Builder.barrierBlack,
    ])

    /// Colours the look gives a colour of its own rather than a pale one.
    static let remapped: [UInt32: UInt32] = [
        0xFFE3B0: 0xFFC86B, // a street light's head: the icon's yellow (its pool on the ground stays warm white)
        0x5FAD48: 0x8DC27A, // the street trees' first green, as the parks' crowns
        0xC64C36: 0xC4826C, // the red roof ridges, softer
        0x8B3526: 0x9E5F4C, // their eaves
        0xC65A4E: 0xC98A78,
    ].reduce(into: [:]) { $0[Map3DColor.rgb($1.key)] = Map3DColor.rgb($1.value) }

    /// Decision 451: how pale a colour is drawn: in HLS, its lightness
    /// `floor` + `share` × its own and its saturation `saturation` × its
    /// own, its hue kept.
    struct Strength: Equatable, Sendable {
        var floor: Double
        var share: Double
        var saturation: Double

        /// Decision 370's (e): 0.80 + 0.17 × and × 0.45.
        static let e = Strength(floor: 0.80, share: 0.17, saturation: 0.45)
    }

    /// Decision 451: the city's buildings and everything else the look
    /// makes pale, softer than (e) so the buildings keep most of their
    /// hue and their lightness spread (the owner: 「建築感覺變得有點死」).
    static let city = Strength(floor: 0.45, share: 0.52, saturation: 0.80)
    /// Decision 451: the closest detail (decision 267's shopfronts,
    /// awnings, washing), nearly its own colour.
    static let close = Strength(floor: 0.25, share: 0.73, saturation: 0.95)

    /// `color` (``Map3DVertex/color``, its alpha kept) as the look draws it.
    public static func colour(_ color: UInt32) -> UInt32 { colour(color, strength: city) }

    static func colour(_ color: UInt32, strength: Strength) -> UInt32 {
        let opaque = color | 0xFF00_0000
        if kept.contains(opaque) { return color }
        if let mapped = remapped[opaque] { return (mapped & 0x00FF_FFFF) | (color & 0xFF00_0000) }
        return pale(color, strength: strength)
    }

    /// The colour lighter and calmer, its hue kept (`pale()`), as
    /// `strength` says.
    static func pale(_ color: UInt32, strength: Strength = city) -> UInt32 {
        let r = Double(color & 0xFF) / 255, g = Double((color >> 8) & 0xFF) / 255, b = Double((color >> 16) & 0xFF) / 255
        let high = max(r, g, b), low = min(r, g, b), l = (high + low) / 2
        var h = 0.0, s = 0.0
        if high != low {
            let range = high - low
            s = l <= 0.5 ? range / (high + low) : range / (2 - high - low)
            let rc = (high - r) / range, gc = (high - g) / range, bc = (high - b) / range
            h = r == high ? bc - gc : g == high ? 2 + rc - bc : 4 + gc - rc
            h = (h / 6).truncatingRemainder(dividingBy: 1)
            if h < 0 { h += 1 }
        }
        let lightness = strength.floor + strength.share * l, saturation = min(s, 1) * strength.saturation
        func channel(_ m1: Double, _ m2: Double, _ hue: Double) -> Double {
            var hue = hue.truncatingRemainder(dividingBy: 1)
            if hue < 0 { hue += 1 }
            if hue < 1.0 / 6 { return m1 + (m2 - m1) * hue * 6 }
            if hue < 0.5 { return m2 }
            if hue < 2.0 / 3 { return m1 + (m2 - m1) * (2.0 / 3 - hue) * 6 }
            return m1
        }
        let m2 = lightness <= 0.5 ? lightness * (1 + saturation) : lightness + saturation - lightness * saturation
        let m1 = 2 * lightness - m2
        let rgb = saturation == 0 ? [lightness, lightness, lightness]
            : [channel(m1, m2, h + 1.0 / 3), channel(m1, m2, h), channel(m1, m2, h - 1.0 / 3)]
        let bytes = rgb.map { UInt32((min(max($0, 0), 1) * 255).rounded()) }
        return bytes[0] | bytes[1] << 8 | bytes[2] << 16 | (color & 0xFF00_0000)
    }

    /// The roads' own carriageway colours (``Map3DPalette/road(_:)``).
    static let roads: Set<UInt32> = [
        Map3DPalette.road(.motorway), Map3DPalette.road(.primary), Map3DPalette.road(.tertiary), Map3DPalette.road(.minor),
    ]

    /// Every vertex of `mesh` in the look: its colour, and a plain road's
    /// layer ``Map3DVertex/road`` so the shader lights it after dark; the
    /// colours `keeping` as they are.
    static func restyle(_ mesh: inout Map3DMesh, keeping: Set<UInt32> = [], strength: Strength = city) {
        var last: (from: UInt32, to: UInt32)?
        mesh.restyleVertices { vertex in
            let from = vertex.color
            if let last, last.from == from {
                vertex.color = last.to
            } else {
                vertex.color = keeping.contains(from) ? from : colour(from, strength: strength)
                last = (from, vertex.color)
            }
            if vertex.layer == Map3DVertex.plain, roads.contains(from | 0xFF00_0000) { vertex.layer = Map3DVertex.road }
        }
    }

    /// Decision 455: the boxes' faces in the look as ``restyle(_:keeping:strength:)``
    /// changes their vertices.
    static func restyle(_ boxes: inout [Map3DBoxInstance], keeping: Set<UInt32> = [], strength: Strength = city) {
        var known: [UInt32: UInt32] = [:]
        let plain = Int16(Map3DVertex.plain), road = Int16(Map3DVertex.road)
        for index in boxes.indices {
            boxes[index].restyle { from, layer in
                let to = known[from] ?? (keeping.contains(from) ? from : colour(from, strength: strength))
                known[from] = to
                return (to, layer == plain && roads.contains(from | 0xFF00_0000) ? road : layer)
            }
        }
    }

    /// `model` in the look (the street furniture's models).
    static func restyle(_ model: Map3DModelPack.Model) -> Map3DModelPack.Model {
        Map3DModelPack.Model(name: model.name, vertices: model.vertices.map { vertex in
            var vertex = vertex
            vertex.color = colour(vertex.color)
            return vertex
        }, minimum: model.minimum, maximum: model.maximum)
    }
}
