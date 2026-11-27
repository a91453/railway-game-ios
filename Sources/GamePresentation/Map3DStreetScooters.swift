import GameCore

// Decision 1037 (STREET-PEOPLE-POOL and SCOOTER-SHARE, the rules of
// railway-assets-private-2 docs/handoff/STREET-TEMPLE-VIADUCT-TRAM-RULES.md
// §2): how many of a street's vehicles are scooters. Until then one
// Taiwanese vehicle slot in two was a lone scooter and one in eight two
// riding together, so with the ones riding beside a lone one some seven
// drawn vehicles in ten were scooters, all over Taiwan. The rules' table
// (§2.1) takes the real traffic's: Taipei's streets 46% scooters and
// Kaohsiung's 57% (traffic counts, some twenty years old), so 57% for the
// rest of Taiwan; Japan's 3% (Kumamoto's trips 2.6% by motorcycle, 2023;
// the country's registered vehicles 4.9%), Hong Kong's 3% (decision 743)
// and Finland's none (decision 802). A lane's county is its middle's;
// only Taipei City's outline is needed, anywhere else being the rest of
// Taiwan. Only what is drawn changes, from the map's place: no
// rule, save or golden reads it.

enum Map3DStreetScooters {
    /// The share of a street's drawn vehicles that are scooters, those
    /// riding beside another counted too: Taipei City's (`taipei`) 46%,
    /// the rest of Taiwan's 57%, Japan's 3% and Hong Kong's 3% (decision
    /// 743's, unchanged); Finland none.
    static func drawnShare(_ region: Map3DStreetRegion, taipei: Bool) -> Float {
        switch region {
        case .taiwan: taipei ? 0.46 : 0.57
        case .hongKong: 0.03
        case .japan: 0.03
        case .finland: 0
        }
    }

    /// Of Taiwan's scooter slots, the share with two riding (decision 446's
    /// one in eight of the slots to the lone ones' one in two), kept.
    static let pairShare: Float = 0.12 / 0.62

    /// The share of Taiwan's vehicle slots to give scooters so that, with
    /// a lone one's ``Map3DStreetLife/beside`` scooter (where a street
    /// allows one beside, as most do), `drawn` of the drawn vehicles are
    /// scooters: a slot draws 1 + `beside` (1 − pair share) vehicles if a
    /// scooter, 1 if not.
    static func slotShare(drawn: Float) -> Float {
        let extra = Map3DStreetLife.beside.share * (1 - pairShare)
        return drawn / (1 + extra * (1 - drawn))
    }

    /// Taipei City's (臺北市) outline, latitude and longitude: its twelve
    /// districts of the app's township outlines (OpenStreetMap, ODbL 1.0,
    /// decision 159) joined and simplified to 150 m by
    /// `tools/street-scooters/taipei_outline.py`.
    static let taipeiOutline: [(latitude: Double, longitude: Double)] = [
        (25.02095, 121.51628), (25.02113, 121.50839), (25.00938, 121.49565), (25.01208, 121.48985), (25.02318, 121.48891), (25.03695, 121.48366),
        (25.04184, 121.48786), (25.04280, 121.49571), (25.04970, 121.50490), (25.07447, 121.50615), (25.08721, 121.49978), (25.09699, 121.48901),
        (25.10085, 121.48135), (25.10169, 121.46620), (25.10657, 121.45778), (25.11617, 121.46093), (25.12294, 121.45880), (25.12425, 121.46483),
        (25.13154, 121.46559), (25.15022, 121.48287), (25.15141, 121.48744), (25.16041, 121.49240), (25.16928, 121.50175), (25.17325, 121.50257),
        (25.16943, 121.51042), (25.17100, 121.51357), (25.16927, 121.51995), (25.17468, 121.52256), (25.17916, 121.52181), (25.18306, 121.52619),
        (25.18719, 121.54067), (25.19573, 121.54494), (25.19786, 121.55206), (25.20367, 121.55163), (25.20850, 121.55493), (25.20946, 121.56267),
        (25.19972, 121.56608), (25.19540, 121.57174), (25.19457, 121.58377), (25.18356, 121.58288), (25.18201, 121.58091), (25.17721, 121.58333),
        (25.16715, 121.57698), (25.16374, 121.58991), (25.15589, 121.59185), (25.15238, 121.58939), (25.15006, 121.59375), (25.14026, 121.59838),
        (25.13675, 121.60568), (25.13077, 121.60462), (25.13017, 121.60784), (25.12592, 121.60443), (25.12602, 121.60172), (25.11423, 121.59599),
        (25.11515, 121.59352), (25.10891, 121.59838), (25.10387, 121.61541), (25.09732, 121.62216), (25.09700, 121.62554), (25.08647, 121.62861),
        (25.07811, 121.62424), (25.07325, 121.62062), (25.06957, 121.62151), (25.06760, 121.61763), (25.06394, 121.61614), (25.06460, 121.61392),
        (25.06202, 121.62005), (25.05585, 121.62423), (25.05665, 121.62053), (25.05350, 121.62093), (25.05080, 121.61647), (25.04037, 121.62158),
        (25.02799, 121.64672), (25.02744, 121.65515), (25.03045, 121.66080), (25.02988, 121.66594), (25.02275, 121.66284), (25.02442, 121.65382),
        (25.02172, 121.64625), (25.02456, 121.64298), (25.02321, 121.63569), (25.02563, 121.63236), (25.01993, 121.62894), (25.01727, 121.62328),
        (25.02096, 121.60925), (25.01911, 121.60416), (25.01500, 121.60231), (25.01456, 121.59348), (25.01463, 121.59706), (25.00444, 121.59592),
        (25.00075, 121.60055), (24.99454, 121.59814), (24.99037, 121.60195), (24.97816, 121.59947), (24.97436, 121.60518), (24.97351, 121.61437),
        (24.97030, 121.61959), (24.96739, 121.61978), (24.96052, 121.59722), (24.96423, 121.59338), (24.96320, 121.58575), (24.96664, 121.57867),
        (24.96689, 121.57456), (24.96400, 121.57266), (24.96467, 121.56127), (24.97726, 121.55395), (24.98688, 121.55231), (24.98374, 121.54903),
        (24.98359, 121.54537), (24.98805, 121.54413), (24.98847, 121.53704), (24.99514, 121.53517), (24.99050, 121.53170), (24.99791, 121.53056),
        (25.00314, 121.53422), (25.00859, 121.53198)
    ]

    /// Taipei City's outline in `frame`'s world units, or `nil` off a
    /// map of Taiwan.
    static func taipei(in frame: RealWorldFrame?, region: Map3DStreetRegion) -> [(x: Double, y: Double)]? {
        guard region == .taiwan, let frame else { return nil }
        return taipeiOutline.map { frame.worldPosition(latitude: $0.latitude, longitude: $0.longitude) }
    }

    /// Whether the world point (`x`, `y`) is inside `outline` (even-odd).
    static func contains(_ outline: [(x: Double, y: Double)], x: Double, y: Double) -> Bool {
        var inside = false
        var j = outline.count - 1
        for i in outline.indices {
            let a = outline[i], b = outline[j]
            if (a.y > y) != (b.y > y), x < (b.x - a.x) * (y - a.y) / (b.y - a.y) + a.x { inside.toggle() }
            j = i
        }
        return inside
    }
}
