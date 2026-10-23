import Foundation
import GameCore

/// The 3D map's train models (ARCHITECTURE decision 230), made in code.
///
/// The owner, 2026-10-15, after seeing the reference repository's white
/// models in the game: they looked the same as the originals, so they are
/// not used (art-style §7). What was learned from them is the method and the
/// proportions: a car is about 2.9–3.1 m wide and 3.6–3.7 m tall, its windows
/// between some 1.6 and 3.0 m above the rail, the Wenhu Line's cars smaller
/// (2.6 m by 3.3 m). The shape is swept the way this project's own city view
/// sweeps its trains (`Web/CityView/src/world/trains.js` `shellRing` and
/// `shellGeometry`, MIT): rings of a rounded section along the car, a cab
/// car's front rings narrowing and dropping into its nose. The livery is
/// painted by height, as there: the skirt, a band in the line's colour,
/// windows and doors standing a little proud of the body, the windscreen.
///
/// A model's space: +x the front, +y the left, +z up, the rail at z 0,
/// metres, the car's middle at x 0. A vertex whose alpha is below 1 takes
/// the line's colour in that share.
public struct Map3DModelPack: Sendable {
    public struct Model: Sendable {
        public let name: String
        /// Three to a triangle, each with the triangle's own normal (flat,
        /// the miniature look).
        public let vertices: [Map3DVertex]
        public let minimum: Map3DPoint
        public let maximum: Map3DPoint

        public var length: Float { maximum.x - minimum.x }
        public var triangleCount: Int { vertices.count / 3 }
    }

    public let models: [Model]
    /// Decision 338: the sets drawn as they were before them (``TrainPack``).
    public var locked: Set<String> = []

    /// Every style's cab car and middle car, made once.
    public static let standard = Map3DModelPack(styles: Map3DTrainStyle.all)

    public init(styles: [Map3DTrainStyle]) {
        var models: [Model] = []
        for style in styles {
            models.append(Map3DTrainBuilder(style: style, cab: true).model(named: style.name + "-cab"))
            models.append(Map3DTrainBuilder(style: style, cab: false).model(named: style.name + "-car"))
            if !style.pantographCars.isEmpty {
                models.append(Map3DTrainBuilder(style: style, cab: false, pantograph: true).model(named: style.name + "-panto"))
            }
        }
        // Decision 244: and the street furniture.
        // Decision 370: in the model look, as the city round them.
        models += Map3DProp.allCases.map { Map3DLook.restyle($0.model()) }
        // Decision 259: and the people, scooters and cars.
        models += Map3DStreetModel.allCases.map { $0.model() }
        // Decision 318: and the sets that had none.
        models += Map3DTrainSet.all.flatMap { $0.models() }
        // Static low-floor tram parts and a full formation for scene authors.
        models += Map3DGreenTram.Section.allCases.map { Map3DGreenTram.model($0) }
        models.append(Map3DGreenTram.formation())
        // Separate high-floor two-car commuter set from the low-floor tram.
        models += Map3DGreenCommuter.Unit.allCases.map { Map3DGreenCommuter.model($0) }
        models.append(Map3DGreenCommuter.formation())
        models += Map3DThreeCarUrban.Unit.allCases.map { Map3DThreeCarUrban.model($0) }
        models.append(Map3DThreeCarUrban.formation())
        // Independent static five-section articulated LRT; no operating type binding.
        models += Map3DFiveSectionLRT.Unit.allCases.map { Map3DFiveSectionLRT.model($0) }
        models.append(Map3DFiveSectionLRT.formation())
        models += Map3DSevenSectionLRT.Unit.allCases.map { Map3DSevenSectionLRT.model($0) }
        models.append(Map3DSevenSectionLRT.formation())
        models += Map3DFourCarMetro.Unit.allCases.map { Map3DFourCarMetro.model($0) }
        models.append(Map3DFourCarMetro.formation())
        self.models = models
    }

    init(models: [Model]) {
        self.models = models
    }

    /// The model called `name`'s index.
    public func index(of name: String) -> Int? {
        models.firstIndex { $0.name == name }
    }

    /// The style of each train type, by its code (`""` for a train with no
    /// type: a commuter EMU). Types with neither a style nor a set
    /// (``Map3DTrainSet``: maglev, skyrail, monorail, steam) are drawn as
    /// boxes.
    public static let styleByType: [String: String] = [
        "": "commuter", "EMU3000": "express", "HSR": "highSpeed",
        // Decision 252: the flat-fronted EMUs as commuters (decision 286:
        // and the Shan-Lan); the Chu-Kuang sets have no locomotive model
        // yet, so are boxes.
        "EMU100": "commuter", "HAIFENG": "commuter", "SHANLAN": "commuter",
        "A": "metro", "B": "metro", "C": "metro", "L": "metro", "D": "metro", "APM": "peopleMover",
    ]

    /// The cab and middle car models' indices for a train of type `code`
    /// (or a set's key, ``Map3DTrainSet/key(type:performance:)``), or `nil`
    /// when it has none.
    public func models(forType code: String) -> (head: Int, middle: Int)? {
        if let set = Map3DTrainSet.named(code) {
            guard let head = index(of: set.headName), let middle = index(of: set.middleName) else { return nil }
            return (head, middle)
        }
        guard let style = Self.styleByType[code], let head = index(of: style + "-cab"), let middle = index(of: style + "-car") else { return nil }
        return (head, middle)
    }

    /// The model index for car `carIndex` (0-indexed) in a `count`-car train
    /// of type `code`, using the pantograph car model on cars listed in the
    /// style's `pantographCars`.
    public func modelIndex(forType code: String, carIndex: Int, count: Int) -> Int? {
        if let set = Map3DTrainSet.set(forKey: code, count: count, locked: locked) {
            if count == 1, let single = index(of: set.singleName) { return single }
            if carIndex == 0 { return index(of: set.headName) }
            if carIndex == count - 1 { return index(of: set.tailName) ?? index(of: set.headName) }
            if set.pantographCars.contains(carIndex), let panto = index(of: set.pantographName) { return panto }
            return index(of: set.middleName)
        }
        guard let styleName = Self.styleByType[code] else { return nil }
        if carIndex == 0 || carIndex == count - 1 {
            return index(of: styleName + "-cab")
        }
        if let style = Map3DTrainStyle.all.first(where: { $0.name == styleName }),
           style.pantographCars.contains(carIndex),
           let panto = index(of: styleName + "-panto") {
            return panto
        }
        return index(of: styleName + "-car")
    }

    /// Whether car `carIndex` of a `count`-car train of type `code` is the
    /// head car's model turned round: the last car, unless the set has a
    /// tail of its own or the train is one car.
    public func isTurned(forType code: String, carIndex: Int, count: Int) -> Bool {
        guard count > 1, carIndex == count - 1 else { return false }
        if let set = Map3DTrainSet.set(forKey: code, count: count, locked: locked) { return index(of: set.tailName) == nil }
        return true
    }
}

/// How one kind of train looks (decision 230): its section, its nose and
/// its livery. Heights are shares of the section (0 the skirt's hem, 1 the
/// roof), as `trains.js`'s liveries are.
public struct Map3DTrainStyle: Sendable {
    public enum DoorLayout: Sendable {
        case even
        case carEnds
    }

    public enum RoofKind: Sendable {
        case airConditioners
        case cableShrouds
    }

    public let name: String
    /// The car's length as drawn, metres (``TrainCars/drawnCarLength`` less
    /// the gap between cars).
    public var length: Float = 19.4
    public var halfWidth: Float
    /// The section's bottom and top above the rail.
    public var floor: Float
    public var roof: Float
    /// The cab car's nose: its length, how far its top drops and its bottom
    /// lifts, how much it narrows, how much its tip rounds over.
    public var nose: Float
    public var drop: Float
    public var lift: Float = 0.05
    public var tuck: Float
    public var cap: Float
    /// The nose's shoulder wing bulge and cockpit canopy ridge (the N700ST
    /// "Dual Supreme Wing" and raised canopy fairing), and how far the side
    /// stripes dive toward the nose tip.
    public var wing: Float = 0
    public var shoulder: Float = 0.66
    public var canopy: Float = 0
    public var dive: Float = 0
    /// The body's colour, the skirt's and how high the skirt reaches.
    public var body: UInt32 = Map3DColor.rgb(0xF2F3F1)
    public var skirt: UInt32 = Map3DColor.rgb(0x9AA0A4)
    public var skirtTop: Float = 0.14
    /// The band in the line's colour, and a thin dark line, if any.
    public var band: ClosedRange<Float>
    public var line: ClosedRange<Float>?
    public var lineColour: UInt32 = Map3DTrainStyle.darkLine
    /// The windows: their heights, the distance between their middles and
    /// their width, in metres.
    public var windows: ClosedRange<Float>
    public var windowPitch: Float
    public var windowWidth: Float
    /// Doors on each side, how they are arranged along the car, whether each
    /// door carries a window pane, and their width.
    public var doors: Int
    public var doorWidth: Float = 1.3
    public var doorLayout: DoorLayout = .even
    public var doorWindows: Bool = false
    /// Roof equipment layout and which 0-indexed cars in a formation carry a
    /// pantograph fairing (Car 4 and Car 9 -> `[3, 8]` on a 12-car high-speed set).
    public var roofKind: RoofKind = .airConditioners
    public var pantographCars: Set<Int> = []
    /// The windscreen: where it starts and stops along the nose (0 at the
    /// body, 1 at the tip), how high it reaches down, and what share of the
    /// width it spans.
    public var screenFrom: Float
    public var screenTo: Float = 0.92
    public var screenDown: Float
    public var screenAcross: Float = 1.0

    static let glass = Map3DColor.rgb(0x26313D)
    static let doorColour = Map3DColor.rgb(0x5D6670)
    static let darkLine = Map3DColor.rgb(0x2A3340)
    static let navyLine = Map3DColor.rgb(0x2B3356)
    static let roofColour = Map3DColor.rgb(0xC5C9CD)
    static let under = Map3DColor.rgb(0x474B51)
    static let lampHousing = Map3DColor.rgb(0x49505A)
    static let headlamp = Map3DColor.rgb(0xFFF4D6)

    /// The styles, from what the reference's trains measure and this
    /// project's own city view (`trains.js` `EMU3000_STOCK`, `HSR_STOCK`).
    public static let all: [Map3DTrainStyle] = [
        // A TRA commuter EMU: a short, upright cab; three doors a side.
        Map3DTrainStyle(name: "commuter", halfWidth: 1.45, floor: 0.6, roof: 3.7, nose: 1.4, drop: 0.35, tuck: 0.06, cap: 0.22,
                        band: 0.33...0.40, line: nil, windows: 0.46...0.80, windowPitch: 1.9, windowWidth: 1.4, doors: 3,
                        screenFrom: 0.0, screenDown: 0.47),
        // The EMU3000 (trains.js EMU3000_STOCK): a long sloping nose, white,
        // a thin dark line under the windows; one door a side at the end.
        Map3DTrainStyle(name: "express", halfWidth: 1.455, floor: 0.53, roof: 3.49, nose: 5.4, drop: 1.15, lift: 0.18, tuck: 0.3, cap: 0.46,
                        band: 0.40...0.44, line: 0.70...0.726, windows: 0.47...0.70, windowPitch: 1.35, windowWidth: 0.7, doors: 1,
                        doorWidth: 1.0, screenFrom: 0.15, screenDown: 0.62),
        // High speed (trains.js HSR_STOCK, THSR N700ST / 700T): a 9 m
        // Dual Supreme Wing duck-bill nose, raised cockpit canopy, tall
        // warm-grey skirt, orange and navy bands sweeping down the nose,
        // shoulder headlamps, plug doors at the car ends, and pantograph
        // fairings on Car 4 and Car 9 (0-indexed 3 and 8).
        Map3DTrainStyle(name: "highSpeed", halfWidth: 1.45, floor: 0.62, roof: 3.75, nose: 9, drop: 1.78, lift: 0.1, tuck: 0.34, cap: 0.56,
                        wing: 0.06, shoulder: 0.64, canopy: 0.24, dive: 0.24,
                        body: Map3DColor.rgb(0xF6F6F4), skirt: Map3DColor.rgb(0x8F959B), skirtTop: 0.28,
                        band: 0.38...0.50, line: 0.50...0.566, lineColour: navyLine,
                        windows: 0.58...0.76, windowPitch: 1.0, windowWidth: 0.5, doors: 2,
                        doorWidth: 0.85, doorLayout: .carEnds, doorWindows: true,
                        roofKind: .cableShrouds, pantographCars: [3, 8],
                        screenFrom: 0.12, screenTo: 0.42, screenDown: 0.68, screenAcross: 0.64),
        // A metro car: wider, a flat front, four doors a side.
        Map3DTrainStyle(name: "metro", halfWidth: 1.55, floor: 0.55, roof: 3.6, nose: 1.0, drop: 0.22, tuck: 0.04, cap: 0.2,
                        band: 0.34...0.41, line: nil, windows: 0.45...0.82, windowPitch: 1.9, windowWidth: 1.3, doors: 4,
                        screenFrom: 0.0, screenDown: 0.45),
        // A people mover (the Wenhu Line's size): small and rounded.
        Map3DTrainStyle(name: "peopleMover", length: 13, halfWidth: 1.3, floor: 0.7, roof: 3.3, nose: 1.8, drop: 0.55, tuck: 0.1, cap: 0.35,
                        band: 0.28...0.35, line: nil, windows: 0.40...0.80, windowPitch: 2.0, windowWidth: 1.6, doors: 2,
                        screenFrom: 0.0, screenDown: 0.40),
    ]
}

/// Builds one car of a style (decision 230). Works in a frame with y up
/// (x the front, z the right), so ``Map3DMesh``'s boxes stand the right way,
/// and turns the result into the model's frame (z up, y the left) at the end.
struct Map3DTrainBuilder {
    let style: Map3DTrainStyle
    let cab: Bool
    let pantograph: Bool
    static let ringPoints = 20

    private var mesh = Map3DMesh()

    init(style: Map3DTrainStyle, cab: Bool, pantograph: Bool = false) {
        self.style = style
        self.cab = cab
        self.pantograph = pantograph
    }

    // MARK: The shell

    static func ease(_ x: Float) -> Float {
        let v = min(1, max(0, x))
        return v * v * (3 - 2 * v)
    }

    /// `trains.js` `shellRing`: the section at `along` metres, `t` along the
    /// nose (0 at the body, 1 at the tip). Each point with its height's
    /// share of the section, for the livery. On a high-speed cab nose, the
    /// centre crown rises into the cockpit canopy dome before dropping across
    /// the windscreen, while the outer shoulders carry the N700 Dual Supreme
    /// Wing ridges.
    func ring(at along: Float, t: Float) -> [(point: Map3DPoint, share: Float)] {
        let halfWidth = style.halfWidth * (1 - style.tuck * Self.ease((t - 0.45) / 0.55))
        let top = style.roof - style.drop * Self.ease(t), bottom = style.floor + style.lift * Self.ease((t - 0.6) / 0.4)
        let cap = 1 - style.cap * Self.ease((t - 0.88) / 0.12)
        let middle = (top + bottom) / 2, half = (top - bottom) / 2 * cap
        let low = 2 / (8.5 - 5.6 * Self.ease(t)), up = 2 / (4.6 - 2.3 * Self.ease(t))
        return (0..<Self.ringPoints).map { k in
            let a = -Float.pi / 2 + 2 * Float.pi * Float(k) / Float(Self.ringPoints)
            let c = cosf(a), s = sinf(a)
            var y = middle + (s < 0 ? -1 : 1) * powf(abs(s), s < 0 ? low : up) * half
            let sectionShare = (y - bottom) / max(0.01, top - bottom)
            if t > 0, s > 0, style.canopy > 0 || style.wing > 0 {
                let dome = style.canopy * sinf(Float.pi * min(1, t / 0.50)) * expf(-powf(c / 0.48, 2)) * s
                let cheek = style.wing * 1.4 * 4 * t * (1 - t) * expf(-powf((abs(c) - 0.76) / 0.20, 2)) * s
                y = min(style.roof, y + (dome + cheek) * cap)
            }
            let d = (sectionShare - style.shoulder) / 0.14
            let wingBulge = t > 0 && style.wing > 0 ? style.wing * 4 * t * (1 - t) * expf(-d * d) : 0
            let across = (c < 0 ? -1 : 1) * min(style.halfWidth, (powf(abs(c), low) * halfWidth + wingBulge) * cap)
            let share = min(1, max(0, (y - style.floor) / (style.roof - style.floor)))
            return (Map3DPoint(along, y, across), share)
        }
    }

    /// The paint of the shell at `share` of the height, `t` along the nose,
    /// and `across` metres from the centre line.
    func paint(share: Float, t: Float, across: Float = 0, front: Bool) -> UInt32 {
        if share < style.skirtTop { return style.skirt }
        // The windscreen: the cockpit canopy's upper-central window between
        // screenFrom and screenTo, or on a flat front, its face above screenDown.
        let inScreenSpan = t > style.screenFrom && t < style.screenTo && share > style.screenDown
            && abs(across) <= style.halfWidth * style.screenAcross
        let inFlatFront = front && style.nose < 2 && share > style.screenDown && share < 0.92
        if cab, inScreenSpan || inFlatFront {
            return Map3DTrainStyle.glass
        }
        // The roof's colour over the top: on a diving high-speed nose only
        // back of the nose (t == 0), so its body colour sweeps to the tip;
        // on every other cab along the nose too, as before #752.
        if share > 0.9, t == 0 || style.dive == 0 { return Map3DTrainStyle.roofColour }
        return style.body
    }

    /// The line's colour stands in for this: alpha 0 (``Map3DModelPack``).
    static let lineColour: UInt32 = Map3DColor.rgb(0x2F6DB5) & 0x00FF_FFFF

    mutating func addShell() {
        let half = style.length / 2
        let nose = cab ? style.nose : 0
        var rings: [(along: Float, t: Float)] = [(-half, 0)]
        if nose > 0 {
            let steps = max(3, Int((nose / 0.6).rounded()))
            rings.append((half - nose, 0))
            for i in 1...steps { rings.append((half - nose + nose * Float(i) / Float(steps), Float(i) / Float(steps))) }
        } else {
            rings.append((half, 0))
        }
        let sections = rings.map { ring(at: $0.along, t: $0.t) }
        let topIndex = Self.ringPoints / 2
        for i in 0..<(sections.count - 1) {
            let midY = (sections[i][0].point.y + sections[i][topIndex].point.y
                + sections[i + 1][0].point.y + sections[i + 1][topIndex].point.y) / 4
            let centre = Map3DPoint((rings[i].along + rings[i + 1].along) / 2, midY, 0)
            for k in 0..<Self.ringPoints {
                let j = (k + 1) % Self.ringPoints
                let a = sections[i][k], b = sections[i][j], c = sections[i + 1][j], d = sections[i + 1][k]
                let t0 = rings[i].t, t1 = rings[i + 1].t
                let corners = [(a, t0), (b, t0), (c, t1), (d, t1)].map {
                    ($0.0.point, paint(share: $0.0.share, t: $0.1, across: $0.0.point.z, front: false))
                }
                addTriangle(corners[0], corners[1], corners[2], outFrom: centre)
                addTriangle(corners[0], corners[2], corners[3], outFrom: centre)
            }
        }
        // The two ends: the back flat, the front its nose's tip or flat face.
        for (index, front) in [(0, false), (sections.count - 1, true)] {
            let section = sections[index]
            let middle = section.reduce(Map3DPoint.zero) { $0 + $1.point * (1 / Float(Self.ringPoints)) }
            let share: Float = front && cab && style.nose > 2 ? 0.5 : section.reduce(Float(0)) { $0 + $1.share } / Float(Self.ringPoints)
            let t = rings[index].t
            let centreColour = paint(share: share, t: t, across: 0, front: front && cab)
            let outside = middle + Map3DPoint(front ? -1 : 1, 0, 0)
            for k in 0..<Self.ringPoints {
                let j = (k + 1) % Self.ringPoints
                addTriangle((middle, centreColour),
                            (section[k].point, paint(share: section[k].share, t: t, across: section[k].point.z, front: front && cab)),
                            (section[j].point, paint(share: section[j].share, t: t, across: section[j].point.z, front: front && cab)),
                            outFrom: outside)
            }
        }
    }

    /// A triangle facing away from `inside`.
    mutating func addTriangle(_ a: (Map3DPoint, UInt32), _ b: (Map3DPoint, UInt32), _ c: (Map3DPoint, UInt32), outFrom inside: Map3DPoint) {
        guard let normal = (b.0 - a.0).cross(c.0 - a.0).normalized else { return }
        let middle = (a.0 + b.0 + c.0) * (1 / 3)
        let corners = normal.dot(middle - inside) >= 0 ? [a, b, c] : [a, c, b]
        let facing = normal.dot(middle - inside) >= 0 ? normal : -normal
        mesh.appendTriangle(corners.map { Map3DVertex($0.0, normal: facing, color: $0.1) })
    }

    // MARK: Windows, doors, bands

    /// Interpolates both vertical height `y` and lateral flank position `z` on
    /// the ring polygon at `share` (`0...1`), so panels and nose stripes follow
    /// the exact cross-section facet without cutting through it.
    func flank(at share: Float, along: Float = 0, t: Float = 0) -> (y: Float, z: Float) {
        let section = ring(at: along, t: t).filter { $0.point.z > 0 }.sorted { $0.share < $1.share }
        guard let above = section.firstIndex(where: { $0.share >= share }), above > 0 else {
            if let first = section.first, share <= first.share { return (first.point.y, first.point.z) }
            if let last = section.last { return (last.point.y, last.point.z) }
            return (height(at: share), style.halfWidth)
        }
        let a = section[above - 1], b = section[above]
        let s = b.share > a.share ? (share - a.share) / (b.share - a.share) : 0
        return (a.point.y + (b.point.y - a.point.y) * s, a.point.z + (b.point.z - a.point.z) * s)
    }

    func side(at share: Float, along: Float = 0, t: Float = 0) -> Float {
        flank(at: share, along: along, t: t).z
    }

    func height(at share: Float) -> Float { style.floor + share * (style.roof - style.floor) }

    /// A panel on both sides from `along0` to `along1`, between two
    /// heights' shares, standing `proud` metres off the body; in three
    /// pieces up the side, so it follows where the side curves in.
    mutating func addPanels(along along0: Float, to along1: Float, shares: ClosedRange<Float>, proud: Float, colour: UInt32) {
        guard along1 > along0 else { return }
        let steps = 3
        let cuts = (0...steps).map { shares.lowerBound + (shares.upperBound - shares.lowerBound) * Float($0) / Float(steps) }
        for sign: Float in [-1, 1] {
            for piece in 0..<steps {
                let low = height(at: cuts[piece]), high = height(at: cuts[piece + 1])
                let outLow = side(at: cuts[piece]) + proud, outHigh = side(at: cuts[piece + 1]) + proud
                let a = Map3DPoint(along0, low, sign * outLow), b = Map3DPoint(along1, low, sign * outLow)
                let c = Map3DPoint(along1, high, sign * outHigh), d = Map3DPoint(along0, high, sign * outHigh)
                let inside = Map3DPoint((along0 + along1) / 2, (low + high) / 2, 0)
                addTriangle((a, colour), (b, colour), (c, colour), outFrom: inside)
                addTriangle((a, colour), (c, colour), (d, colour), outFrom: inside)
            }
        }
    }

    /// Sweeps a side stripe forward from `along0` onto the cab nose up to
    /// `along1`, following the nose rings and dropping by `dive * ease(t)`.
    mutating func addNoseStripe(from along0: Float, to along1: Float, shares: ClosedRange<Float>, dive: Float, proud: Float, colour: UInt32) {
        guard along1 > along0, style.nose > 0 else { return }
        let noseStart = style.length / 2 - style.nose
        let steps = 8
        for step in 0..<steps {
            let u0 = Float(step) / Float(steps), u1 = Float(step + 1) / Float(steps)
            let x0 = along0 + (along1 - along0) * u0, x1 = along0 + (along1 - along0) * u1
            let t0 = min(1, max(0, (x0 - noseStart) / style.nose)), t1 = min(1, max(0, (x1 - noseStart) / style.nose))
            let drop0 = dive * Self.ease(t0), drop1 = dive * Self.ease(t1)
            let low0 = shares.lowerBound - drop0, high0 = shares.upperBound - drop0
            let low1 = shares.lowerBound - drop1, high1 = shares.upperBound - drop1
            let pLow0 = flank(at: low0, along: x0, t: t0), pHigh0 = flank(at: high0, along: x0, t: t0)
            let pLow1 = flank(at: low1, along: x1, t: t1), pHigh1 = flank(at: high1, along: x1, t: t1)
            for sign: Float in [-1, 1] {
                let a = Map3DPoint(x0, pLow0.y + proud * 0.25, sign * (pLow0.z + proud))
                let b = Map3DPoint(x1, pLow1.y + proud * 0.25, sign * (pLow1.z + proud))
                let c = Map3DPoint(x1, pHigh1.y + proud * 0.25, sign * (pHigh1.z + proud))
                let d = Map3DPoint(x0, pHigh0.y + proud * 0.25, sign * (pHigh0.z + proud))
                let inside = Map3DPoint((x0 + x1) / 2, (pLow0.y + pHigh1.y) / 2, 0)
                addTriangle((a, colour), (b, colour), (c, colour), outFrom: inside)
                addTriangle((a, colour), (c, colour), (d, colour), outFrom: inside)
            }
        }
    }

    /// Adds the N700ST shoulder headlamp housings and glowing LED lenses along
    /// the lower outer Dual Supreme Wing ridges, just above the diving navy band.
    mutating func addNoseHeadlamps() {
        guard cab, style.dive > 0 else { return }
        let noseStart = style.length / 2 - style.nose
        let x0 = noseStart + style.nose * 0.50, x1 = noseStart + style.nose * 0.64
        addNoseStripe(from: x0, to: x1, shares: 0.46...0.54, dive: 0.08, proud: 0.022, colour: Map3DTrainStyle.lampHousing)
        let glowStart = mesh.vertices.count
        addNoseStripe(from: x0 + 0.14, to: x1 - 0.10, shares: 0.475...0.525, dive: 0.08, proud: 0.028, colour: Map3DTrainStyle.headlamp)
        mesh.makeGlowing(from: glowStart)
    }

    mutating func addLivery() {
        let half = style.length / 2
        let back = -half + 0.5, front = half - (cab ? style.nose : 0) - 0.3
        guard front > back else { return }
        // The band in the line's colour, and the dark line, the whole body
        // long; on a high-speed cab nose they sweep and dive along the nose too.
        addPanels(along: back, to: front, shares: style.band, proud: 0.01, colour: Self.lineColour)
        if let line = style.line { addPanels(along: back, to: front, shares: line, proud: 0.012, colour: style.lineColour) }
        if cab, style.dive > 0 {
            let noseEnd = half - style.nose * 0.14
            addNoseStripe(from: front, to: noseEnd, shares: style.band, dive: style.dive, proud: 0.011, colour: Self.lineColour)
            if let line = style.line {
                addNoseStripe(from: front, to: noseEnd, shares: line, dive: style.dive, proud: 0.013, colour: style.lineColour)
            }
            addNoseHeadlamps()
        }
        // Doors: on a long-nosed cab car, one less door stands behind the nose;
        // on a car-end plug-door layout, the two doors sit near the ends.
        let count = cab && style.nose > 4 ? max(1, style.doors - 1) : max(1, style.doors)
        let span = front - back
        let doorCentres: [Float]
        if count == 1 {
            doorCentres = [cab ? back + style.doorWidth : front - style.doorWidth]
        } else if style.doorLayout == .carEnds && count == 2 {
            doorCentres = [back + style.doorWidth * 1.1, front - style.doorWidth * 1.1]
        } else {
            doorCentres = (0..<count).map { back + span * (Float($0) + 0.5) / Float(count) }
        }
        for centre in doorCentres {
            addPanels(along: centre - style.doorWidth / 2, to: centre + style.doorWidth / 2,
                      shares: style.skirtTop...style.windows.upperBound, proud: 0.025, colour: Map3DTrainStyle.doorColour)
            if style.doorWindows {
                addPanels(along: centre - style.doorWidth * 0.24, to: centre + style.doorWidth * 0.24,
                          shares: style.windows, proud: 0.028, colour: Map3DTrainStyle.glass)
            }
        }
        // Windows at their pitch, clear of the doors.
        var at = back + style.windowPitch / 2
        while at + style.windowWidth / 2 < front {
            let from = at - style.windowWidth / 2, to = at + style.windowWidth / 2
            if !doorCentres.contains(where: { abs($0 - at) < (style.doorWidth + style.windowWidth) / 2 + 0.15 }) {
                addPanels(along: from, to: to, shares: style.windows, proud: 0.02, colour: Map3DTrainStyle.glass)
            }
            at += style.windowPitch
        }
    }

    // MARK: Under and on top

    mutating func addKit() {
        let half = style.length / 2
        let back = -half + 1.2, front = half - (cab ? style.nose : 0) + (cab && style.nose > 2 ? 1.4 : -1.2)
        let length = front - back, middle = (back + front) / 2
        let forward = Map3DPoint(1, 0, 0)
        // The underframe and two bogies.
        mesh.addBox(base: Map3DPoint(middle, 0.2, 0), forward: forward, length: length, width: style.halfWidth * 1.5, height: max(0.2, style.floor - 0.2),
                    top: Map3DTrainStyle.under, side: Map3DTrainStyle.under)
        for z in [back + 2.4, front - 2.4] where length > 6 {
            mesh.addBox(base: Map3DPoint(z, 0, 0), forward: forward, length: 2.8, width: style.halfWidth * 1.45, height: 0.75,
                        top: Map3DTrainStyle.under, side: Map3DTrainStyle.under)
        }
        if style.roofKind == .cableShrouds {
            // Shinkansen roof: smooth continuous cable shrouds along the crown
            // stopping clear of the cab nose, and a low-profile aerodynamic
            // pantograph fairing only on the cars that carry one.
            let runTo = cab ? half - style.nose - 0.6 : front - 0.6
            let runFrom = back + 0.6
            let runLength = max(2.4, runTo - runFrom), runMid = (runFrom + runTo) / 2
            let shroudSide = Map3DColor.shaded(style.body, 0.94)
            for lateral: Float in [-0.72, 0.72] {
                mesh.addBox(base: Map3DPoint(runMid, style.roof - 0.02, lateral), forward: forward,
                            length: runLength, width: 0.26, height: 0.26, top: style.body, side: shroudSide)
            }
            if pantograph {
                mesh.addBox(base: Map3DPoint(runMid, style.roof - 0.02, 0), forward: forward,
                            length: min(2.8, runLength * 0.6), width: style.halfWidth * 1.12, height: 0.3,
                            top: Map3DTrainStyle.roofColour, side: Map3DColor.shaded(Map3DTrainStyle.roofColour, 0.92))
            }
            return
        }
        // The air-conditioning boxes along the roof.
        let units = max(1, Int((length - 1.2) / 4.5))
        for i in 0..<units {
            let z = back + 0.6 + (length - 1.2) * (Float(i) + 0.5) / Float(units)
            mesh.addBox(base: Map3DPoint(z, style.roof - 0.02, 0), forward: forward, length: 2.2, width: style.halfWidth * 1.25, height: 0.3,
                        top: Map3DTrainStyle.roofColour, side: Map3DColor.shaded(Map3DTrainStyle.roofColour, 0.92))
        }
    }

    // MARK: The model

    func model(named name: String) -> Map3DModelPack.Model {
        var builder = self
        builder.addShell()
        builder.addLivery()
        builder.addKit()
        // Into the model's frame: x stays the front, the left is −z, up is y;
        // three vertices to a triangle, each with the triangle's normal.
        return Map3DModelPack.Model.flat(named: name, from: builder.mesh)
    }
}

/// One car drawn with a model (decision 230): which model, where it stands
/// and the line's colour for its stripes. Laid out as Metal reads it: a
/// 4 × 4 matrix (model space to the scene), then the stripe colour as four
/// floats: 80 bytes.
public struct Map3DInstance: Sendable {
    public let model: Int
    /// Column by column.
    public let transform: [Float]
    public let stripe: (Float, Float, Float)

    /// The 20 floats the shader reads.
    public var floats: [Float] {
        transform + [stripe.0, stripe.1, stripe.2, 1]
    }

    /// The box in scene space round its model of `pack` as placed, or
    /// `nil` for a model `pack` does not have.
    func bounds(in pack: Map3DModelPack) -> (min: Map3DPoint, max: Map3DPoint)? {
        guard pack.models.indices.contains(model), transform.count == 16 else { return nil }
        let shape = pack.models[model], t = transform
        var low = Map3DPoint(.infinity, .infinity, .infinity), high = Map3DPoint(-.infinity, -.infinity, -.infinity)
        for x in [shape.minimum.x, shape.maximum.x] {
            for y in [shape.minimum.y, shape.maximum.y] {
                for z in [shape.minimum.z, shape.maximum.z] {
                    let p = Map3DPoint(t[0] * x + t[4] * y + t[8] * z + t[12], t[1] * x + t[5] * y + t[9] * z + t[13], t[2] * x + t[6] * y + t[10] * z + t[14])
                    low = Map3DPoint(min(low.x, p.x), min(low.y, p.y), min(low.z, p.z))
                    high = Map3DPoint(max(high.x, p.x), max(high.y, p.y), max(high.z, p.z))
                }
            }
        }
        return (low, high)
    }
}
