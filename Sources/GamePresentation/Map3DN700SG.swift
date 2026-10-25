import Foundation

/// Decision 408: the N700S-G, the author's own N700S model in the game's
/// dark green line (#1214, `docs/art/n700s-n700st/README.md`; the author's
/// mesh in the reference repository, `Railway/n700s-n700st-2026-10-24/
/// n700s-g/`), rebuilt in the game's look with the train builder every
/// other high-speed set uses (decision 230): matte, flat colours of the
/// palette, some 1,150 triangles a cab and 450 a middle car where the
/// author's are 8,000 to 13,000.
///
/// What is kept from the author's mesh, measured off it (×1.22 along and
/// across, so its 20.5-unit middle car is 25 m and its 2.8 units 3.36 m;
/// up, its skirt-to-roof 3.28 units onto the 3.03 m of the 700T's section):
/// the long nose (7.7 units, 9.4 m) and how its crown, sides and chin run
/// to the tip; the windscreen's place on it; the green line in two bands
/// under the windows; each of the five units' doors where they stand; the
/// pantograph cover on D and the fin on E. Its colours are already the
/// palette's (the body, skirt, roof, glass and doors are
/// ``Map3DTrainStyle``'s own, the line #1D4A44).
///
/// The units: A the cab, B to E the middle cars as the author's assembly
/// has them (A B C D E | E D C B A), each facing its own way.
public enum Map3DN700SG {
    public enum Unit: String, CaseIterable, Sendable {
        case a, b, c, d, e
    }

    /// The line's dark green (`docs/art/n700-game-style-2026-10-16/`).
    static let green = Map3DColor.rgb(0x1D4A44)
    static let grey = Map3DColor.rgb(0x8F959B)

    /// Unit `unit`, its front at +x.
    public static func model(_ unit: Unit) -> Map3DModelPack.Model {
        let name = "n700s-g-" + unit.rawValue
        var builder = StationKitBuilder()
        let body = Map3DTrainBuilder(style: style(unit), cab: unit == .a).model(named: name)
        builder.add(Map3DTrainSet.baked(body, tint: green), at: .zero)
        if unit == .a { windscreen(&builder) }
        let roof: Float = 3.62
        switch unit {
        case .d:
            // The pantograph cover over the car's back half (the author's
            // −7.8 to −3.1 units): a low wide step and a narrower top.
            builder.box(-6.65, roof, 0, 5.7, 2.6, 0.30, Map3DTrainStyle.roofColour)
            builder.box(-6.65, roof + 0.30, 0, 3.6, 2.1, 0.36, grey)
        case .e:
            // The fin at its back end (−10.2 to −9.6 units).
            builder.box(-12.0, roof, 0, 0.8, 0.22, 0.6, grey)
            builder.box(-11.4, roof, 0, 0.6, 0.22, 0.3, grey)
        default:
            break
        }
        return .flat(named: name, from: builder.mesh)
    }

    /// Unit `unit` turned round, for the train's back half.
    public static func reversed(_ unit: Unit) -> Map3DModelPack.Model {
        let model = model(unit).turned
        return Map3DModelPack.Model(name: "n700s-g-" + unit.rawValue + "-reversed", vertices: model.vertices,
                                    minimum: model.minimum, maximum: model.maximum)
    }

    /// Each car of a `count`-car train, front to back: A, then the front
    /// half's B, C, D, E and C again as far as it reaches, the back half the
    /// front half turned round. Twelve cars put the pantographs on the
    /// fourth and ninth, where the High Speed Rail's are.
    public static func formation(cars count: Int) -> [(unit: Unit, reversed: Bool)] {
        guard count > 1 else { return [(.a, false)] }
        let front: [Unit] = [.a, .b, .c, .d, .e]
        let half = (count + 1) / 2
        let head = (0..<half).map { $0 < front.count ? front[$0] : .c }
        let back = head.prefix(count - half).reversed().map { (unit: $0, reversed: true) }
        return head.map { (unit: $0, reversed: false) } + back
    }

    /// The windscreen as a panel of its own laid on the nose (the author's
    /// 4.9 to 6.5 units along, ±0.72 across), a hand's breadth proud, its
    /// edges sharp where the shell's painted vertices would blur them.
    static func windscreen(_ builder: inout StationKitBuilder) {
        let style = style(.a), shell = Map3DTrainBuilder(style: style, cab: true)
        let noseStart = style.length / 2 - style.nose, top = Map3DTrainBuilder.ringPoints / 2
        let steps: [Float] = [0.28, 0.33, 0.38, 0.43, 0.48, 0.52]
        let rings = steps.map { t in shell.ring(at: noseStart + style.nose * t, t: t).map { $0.point + Map3DPoint(0, 0.03, 0) } }
        for (a, b) in zip(rings, rings.dropFirst()) {
            for k in top - 2..<top + 2 {
                let inside = Map3DPoint((a[k].x + b[k].x) / 2, 1, 0)
                builder.face([a[k], a[k + 1], b[k + 1], b[k]], inside: inside, color: Map3DTrainStyle.glass)
            }
        }
    }

    /// The car's length: the cab 25.3 m (the author's 20.75 units), the
    /// middle cars 25 m (20.5).
    static func length(_ unit: Unit) -> Float { unit == .a ? 25.3 : 25.0 }

    /// Where each unit's doors stand, metres from its middle (the author's
    /// units ×1.22): A behind the nose and at its back, B and D one in from
    /// the back and at (or near) the front, C at both ends, E at its back.
    static func doors(_ unit: Unit) -> [Float] {
        switch unit {
        case .a: return [-9.87, 3.15]
        case .b: return [-9.0, 10.8]
        case .c: return [-12.1, 12.1]
        case .d: return [-9.0, 12.1]
        case .e: return [-12.1]
        }
    }

    static func style(_ unit: Unit) -> Map3DTrainStyle {
        var style = Map3DTrainStyle(
            name: "n700sG", length: length(unit), halfWidth: 1.68, floor: 0.62, roof: 3.65,
            nose: 9.36, drop: 1.8, lift: 0.4, tuck: 0.26, cap: 0.5,
            wing: 0.04, shoulder: 0.64, canopy: 0.06, dive: 0.08,
            body: Map3DColor.rgb(0xF6F6F4), skirt: grey, skirtTop: 0.24,
            band: 0.478...0.542, line: 0.434...0.463, lineColour: green,
            windows: 0.546...0.826, windowPitch: 1.06, windowWidth: 0.52, doors: 2,
            doorWidth: 0.8, doorLayout: .carEnds, doorWindows: true,
            roofKind: .cableShrouds,
            screenFrom: 0.28, screenTo: 0.52, screenDown: 2, screenAcross: 0.62)
        style.doorsAt = doors(unit)
        style.lampSpan = 0.78...0.86
        style.lampShare = 0.40
        return style
    }
}
