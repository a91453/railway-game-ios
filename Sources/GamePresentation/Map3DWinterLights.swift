import Foundation

// Decision 794 (WINTER-LIGHTS): the winter event's trees and lights
// (decision 790's ``Map3DWinterDecor``) laid on the 3D map: a string of
// lights under the front eaves of every station building, a 6 m tree on
// the plaza of a big one, and an 18 m tree on the plazas where the real
// cities put theirs (Banqiao's civic square, Tsim Sha Tsui's waterfront,
// later the Santa Claus village). Where they go is worked out once, as the
// scene is built (``Map3DScene/Builder/addWinterDecor(frame:)``); whether
// they are drawn is asked each frame (``WinterEvent/showsDecorations(at:switchedOn:)``),
// so switching them on or off builds nothing again. The bulbs are the
// models' lit vertices (``Map3DVertex/glowing``): by day they show their
// colours, at night the shader lights them and ``Map3DGlow`` gives each
// its glow. No snow: real Taipei and Hong Kong have none.

/// Decision 794: the winter event's trees and lights laid in a scene.
public struct Map3DWinterLights: Equatable, Sendable {
    /// One tree or one length of lights: the model it is drawn with near
    /// (``Map3DWinterDecor/treeMedium``, ``Map3DWinterDecor/treeLarge`` or
    /// ``Map3DWinterDecor/lightString``), where its foot (or, for a string,
    /// the line it hangs from) is, and the way its +x faces.
    public struct Placement: Equatable, Sendable {
        public let decor: Map3DWinterDecor
        public let point: Map3DPoint
        public let forward: Map3DPoint
    }

    public let placements: [Placement]

    public init(placements: [Placement]) {
        self.placements = placements
    }

    public var isEmpty: Bool { placements.isEmpty }

    /// The pack's winter models (decision 790's, in the game's own
    /// colours, not restyled), after the commuter and before the route bus.
    static var drawn: [Map3DModelPack.Model] { Map3DWinterDecor.allCases.compactMap(\.model) }

    // MARK: Where

    /// A station with this many platforms or more is a big one and gets a
    /// tree, as the real big stations (``Map3DScene/Builder/isBig(_:)``) do.
    static let bigPlatforms = 3
    /// The most lengths of lights along one building's front: 32 m, the
    /// middle of a big station's.
    static let mostStringsAFront = 8
    /// One length of lights, metres (``Map3DWinterDecor/lightString``).
    static let stringLength: Float = 4
    /// The heights the lights hang between: over a door, and no higher
    /// than a two-floor front's eaves.
    static let lowestString: Float = 2.4
    static let highestString: Float = 9
    /// How far before the face they hang on the lights are, so the bulbs
    /// clear it.
    static let stringOut: Float = 0.15
    /// How far apart the front is looked at, along it and up it, and how
    /// far two neighbours may differ and still be one straight stretch.
    static let frontStep: Float = 0.5
    static let heightStep: Float = 0.1
    static let sameFace: Float = 0.3
    /// How far behind the farthest forward of them the lights may hang:
    /// a porch and the wall beside it, not a wing well behind.
    static let frontDepth: Float = 3

    /// WINTER-LIGHTS-2: where the lights hang on a station building
    /// (`house`, the kit's: +x its front, y up, z along it): on what
    /// stands out farthest between ``lowestString`` and ``highestString``
    /// (the edge of a porch's canopy, the eaves, else the wall), at the
    /// top of that face, ``stringLength`` lengths along each straight
    /// stretch of it, the ``mostStringsAFront`` nearest the middle. Each
    /// is the middle of a length, which runs along z. Looked for on the
    /// building itself, not its bounds: those take in the forecourt
    /// before it, over which the lights hung in the air.
    static func strings(on house: Map3DMesh) -> [Map3DPoint] {
        guard let bounds = house.bounds else { return [] }
        let count = Int(((bounds.max.z - bounds.min.z) / frontStep).rounded(.down))
        guard count > 0 else { return [] }
        let first = (bounds.min.z + bounds.max.z) / 2 - Float(count - 1) / 2 * frontStep
        // The triangles over each place along the front.
        var over = [[Int]](repeating: [], count: count)
        for start in stride(from: 0, to: house.indices.count - 2, by: 3) {
            let z = (0..<3).map { house.vertices[Int(house.indices[start + $0])].z }
            let y = (0..<3).map { house.vertices[Int(house.indices[start + $0])].y }
            guard y.max()! >= lowestString, y.min()! <= highestString else { continue }
            let from = max(0, Int(((z.min()! - first) / frontStep).rounded(.up)))
            let to = min(count - 1, Int(((z.max()! - first) / frontStep).rounded(.down)))
            guard from <= to else { continue }
            for place in from...to { over[place].append(start) }
        }
        // The face at (z, y): the farthest forward of what is there.
        func face(_ place: Int, _ height: Float) -> Float? {
            let z = first + Float(place) * frontStep
            var found: Float?
            for start in over[place] {
                let a = house.vertices[Int(house.indices[start])].position
                let b = house.vertices[Int(house.indices[start + 1])].position
                let c = house.vertices[Int(house.indices[start + 2])].position
                let whole = (b.z - a.z) * (c.y - a.y) - (c.z - a.z) * (b.y - a.y)
                guard abs(whole) > 1e-6 else { continue }
                let u = ((z - a.z) * (c.y - a.y) - (c.z - a.z) * (height - a.y)) / whole
                let v = ((b.z - a.z) * (height - a.y) - (z - a.z) * (b.y - a.y)) / whole
                guard u >= -1e-4, v >= -1e-4, u + v <= 1 + 1e-4 else { continue }
                let x = a.x + (b.x - a.x) * u + (c.x - a.x) * v
                if x > (found ?? -.infinity) { found = x }
            }
            return found
        }
        // Each place's farthest face and the top of it.
        let heights = Int(((highestString - lowestString) / heightStep).rounded())
        var profile: [(x: Float, y: Float)?] = (0..<count).map { place in
            var faces: [(x: Float, y: Float)] = []
            for step in 0...heights {
                let y = lowestString + Float(step) * heightStep
                if let x = face(place, y) { faces.append((x, y)) }
            }
            guard let out = faces.map(\.x).max() else { return nil }
            return faces.last { $0.x >= out - sameFace }.map { (out, $0.y) }
        }
        func same(_ a: (x: Float, y: Float)?, _ b: (x: Float, y: Float)?) -> Bool {
            guard let a, let b else { return a == nil && b == nil }
            return abs(a.x - b.x) <= sameFace && abs(a.y - b.y) <= sameFace
        }
        // A post or a mullion one place wide is not a stretch of its own.
        if count >= 3 {
            for place in 1..<count - 1 where !same(profile[place], profile[place - 1]) && same(profile[place - 1], profile[place + 1]) {
                profile[place] = profile[place - 1]
            }
        }
        // The straight stretches, from the middle outwards so a building
        // alike on both sides is hung alike: each all within ``sameFace``
        // of where it starts, so an arched canopy's edge is followed in
        // steps.
        var hung: [Map3DPoint] = []
        func hang(_ from: Int, _ to: Int) {
            let run = profile[from...to].compactMap { $0 }
            guard run.count == to - from + 1 else { return }
            let lengths = min(mostStringsAFront, Int((Float(run.count) * frontStep / stringLength).rounded(.down)))
            let x = run.map(\.x).max()! + stringOut, y = run.map(\.y).min()!
            let middle = first + Float(from + to) / 2 * frontStep
            for number in 0..<lengths {
                hung.append(Map3DPoint(x, y, middle + (Float(number) - Float(lengths - 1) / 2) * stringLength))
            }
        }
        func reach(from start: Int, by step: Int) -> Int {
            var end = start
            while end + step >= 0, end + step < count, same(profile[end + step], profile[end]), same(profile[end + step], profile[start]) { end += step }
            return end
        }
        // The middle stretch: both ways from the two middle places.
        let left = (count - 1) / 2, right = count / 2
        var low = left, high = right
        if same(profile[left], profile[right]) {
            low = reach(from: left, by: -1)
            high = reach(from: right, by: 1)
            hang(low, high)
            low -= 1
            high += 1
        } else {
            high = left + 1
        }
        while low >= 0 {
            let end = reach(from: low, by: -1)
            hang(end, low)
            low = end - 1
        }
        while high < count {
            let end = reach(from: high, by: 1)
            hang(high, end)
            high = end + 1
        }
        // Only the front: not a wall well behind the porch.
        guard let front = hung.map(\.x).max() else { return [] }
        let centre = (bounds.min.z + bounds.max.z) / 2
        let nearest = hung.filter { $0.x >= front - frontDepth }.enumerated().sorted {
            abs($0.element.z - centre) != abs($1.element.z - centre) ? abs($0.element.z - centre) < abs($1.element.z - centre) : $0.offset < $1.offset
        }
        var kept = Array(nearest.prefix(mostStringsAFront))
        // A pair as far out on both sides is kept or dropped together, so a
        // building alike on both sides stays hung alike.
        if nearest.count > kept.count, let last = kept.last,
           abs(abs(nearest[kept.count].element.z - centre) - abs(last.element.z - centre)) < 0.01 {
            let cut = abs(last.element.z - centre)
            kept.removeAll { abs(abs($0.element.z - centre) - cut) < 0.01 }
        }
        return kept.map(\.element).sorted { $0.z < $1.z }
    }

    /// WINTER-LIGHTS-2: where the lights hang on an underground station's
    /// exit or a viaduct's stair entrance (the kit's `undergroundExit` and
    /// `stairHead`: +x the way in, y up): a length along each long edge of
    /// its canopy, running along x.
    static let exitStrings = [Map3DPoint(0, 2.8, -1.9), Map3DPoint(0, 2.8, 1.9)]

    /// How far before a big station's front its tree stands: the middle of
    /// the plaza, clear of the bushes (4 m) and of the shops across it
    /// (their awnings from about 12 m).
    static let treeOut: Float = 8

    /// A plaza that puts up a big tree each December.
    public struct Plaza: Equatable, Sendable {
        public let name: String
        public let latitude: Double
        public let longitude: Double
    }

    /// New Taipei's Christmasland on the civic square between Banqiao
    /// Station and the city hall; Tsim Sha Tsui's waterfront by the Clock
    /// Tower; the Santa Claus village on the Arctic Circle north of
    /// Rovaniemi (drawn once Rovaniemi's map is). Places from OpenStreetMap
    /// (ODbL); each tree is moved off a road, the track or a landmark
    /// (``plazaSearch``).
    public static let plazas: [Plaza] = [
        Plaza(name: "banqiao", latitude: 25.01330, longitude: 121.46450),
        Plaza(name: "tsim-sha-tsui", latitude: 22.29380, longitude: 114.16930),
        Plaza(name: "santa-claus-village", latitude: 66.54355, longitude: 25.84730),
    ]
    /// How far a plaza's tree may be moved to stand clear, metres, and the
    /// step.
    static let plazaSearch: Float = 40
    static let plazaStep: Float = 8

    // MARK: Drawing

    /// A tree whole within this of the eye, its far model within
    /// ``treeFarReach``, nothing beyond: the coach stop's (decision 708).
    public static let treeNearReach: Float = Map3DCoaches.stopNearReach
    public static let treeFarReach: Float = Map3DCoaches.stopFarReach
    /// The lights within this of the eye; beyond they are too small to see
    /// and have no far model (decision 790).
    public static let stringReach: Float = Map3DCoaches.stopNearReach
    /// The most of a frame drawn: the nearest first.
    public static let mostTrees = 24
    public static let mostStrings = 96

    /// The most triangles a frame's trees and lights take: every one the
    /// largest it can be.
    public static var mostTriangles: Int {
        let tree = Map3DWinterDecor.treeLarge.model?.triangleCount ?? 0
        let string = Map3DWinterDecor.lightString.model?.triangleCount ?? 0
        return mostTrees * tree + mostStrings * string
    }

    /// Adds the trees and lights seen from `eye` to `frame` (``Map3DCoaches``'s
    /// reach for the far models: `reach`), the nearest ``mostTrees`` and
    /// ``mostStrings``, when the event shows its decorations on `date`
    /// with the settings' switch `switchedOn`
    /// (``WinterEvent/showsDecorations(at:switchedOn:calendar:)``);
    /// nothing otherwise, nor when the pack lacks the models.
    public func add(to frame: inout Map3DTrains.Frame, pack: Map3DModelPack, eye: Map3DPoint, reach: Float = 1,
                    at date: Date, switchedOn: Bool, calendar: Calendar = WinterEvent.calendar()) {
        guard !isEmpty, WinterEvent.showsDecorations(at: date, switchedOn: switchedOn, calendar: calendar) else { return }
        var index: [Map3DWinterDecor: Int] = [:]
        for decor in Map3DWinterDecor.allCases {
            guard let found = pack.index(of: decor.modelName) else { return }
            index[decor] = found
        }
        var trees: [(away: Float, placement: Placement)] = [], strings: [(away: Float, placement: Placement)] = []
        for placement in placements {
            let away = (placement.point - eye).length
            if placement.decor == .lightString {
                if away < Self.stringReach * reach { strings.append((away, placement)) }
            } else if away < Self.treeFarReach {
                trees.append((away, placement))
            }
        }
        func nearest(_ list: [(away: Float, placement: Placement)], _ most: Int) -> ArraySlice<(away: Float, placement: Placement)> {
            list.sorted { $0.away < $1.away }.prefix(most)
        }
        for (away, placement) in nearest(trees, Self.mostTrees) {
            let far = away >= Self.treeNearReach * reach
            let decor = far ? (placement.decor == .treeLarge ? .treeLargeFar : .treeMediumFar) : placement.decor
            frame.instances.append(.prop(index[decor]!, at: placement.point, forward: placement.forward, scale: 1, tint: 0xFFFFFF))
        }
        for (_, placement) in nearest(strings, Self.mostStrings) {
            frame.instances.append(.prop(index[.lightString]!, at: placement.point, forward: placement.forward, scale: 1, tint: 0xFFFFFF))
        }
    }
}

extension Map3DScene.Builder {
    /// Decision 794: where the winter event's trees and lights go
    /// (``winterDecor``): the lights along each station building's front
    /// under its eaves, a tree on a big station's plaza where nothing is
    /// near, and on a real-world map a big tree on each of
    /// ``Map3DWinterLights/plazas`` in the scene. After the shops, so the
    /// trees keep to what they leave.
    mutating func addWinterDecor(frame: RealWorldFrame?) {
        typealias Lights = Map3DWinterLights
        for front in stationFronts {
            let right = front.forward.cross(.up)
            for at in front.strings {
                winterDecor.append(.init(decor: .lightString, point: at, forward: right))
            }
            guard front.big else { continue }
            let spot = front.centre + front.forward * (front.depth / 2 + Lights.treeOut)
            let corners: [(Float, Float)] = [(-1.8, -1.8), (1.8, -1.8), (1.8, 1.8), (-1.8, 1.8)]
            let footprint = corners.map { spot + front.forward * $0.0 + right * $0.1 }
            guard isClear(footprint, facing: front.forward) else { continue }
            winterDecor.append(.init(decor: .treeMedium, point: Map3DPoint(spot.x, drawnGround(x: spot.x, z: spot.z), spot.z), forward: front.forward))
        }
        for exit in exitLights {
            winterDecor.append(.init(decor: .lightString, point: exit.at, forward: exit.forward))
        }
        guard let frame else { return }
        for plaza in Lights.plazas {
            let place = frame.worldPosition(latitude: plaza.latitude, longitude: plaza.longitude)
            guard contains(x: place.x, y: place.y) else { continue }
            let middle = point(x: place.x, y: place.y, height: 0)
            if let spot = Self.plazaSpot(round: middle, isClear: { spot in
                let corners: [(Float, Float)] = [(-3, -3), (3, -3), (3, 3), (-3, 3)]
                let footprint = corners.map { spot + Map3DPoint($0.0, 0, $0.1) }
                return !underLandmark(spot) && isClear(footprint, facing: Map3DPoint(1, 0, 0))
            }) {
                winterDecor.append(.init(decor: .treeLarge, point: Map3DPoint(spot.x, drawnGround(x: spot.x, z: spot.z), spot.z),
                                         forward: Map3DPoint(1, 0, 0)))
            }
        }
    }

    /// Decision 794: the spot nearest `middle` that `isClear` says is
    /// clear, by rings ``Map3DWinterLights/plazaStep`` apart out to
    /// ``Map3DWinterLights/plazaSearch``, eight ways round each; `nil`
    /// when none is.
    static func plazaSpot(round middle: Map3DPoint, isClear: (Map3DPoint) -> Bool) -> Map3DPoint? {
        if isClear(middle) { return middle }
        let rings = Int(Map3DWinterLights.plazaSearch / Map3DWinterLights.plazaStep)
        for ring in 1...rings {
            let radius = Float(ring) * Map3DWinterLights.plazaStep
            for way in 0..<8 {
                let angle = Float(way) * Float.pi / 4
                let spot = middle + Map3DPoint(cosf(angle) * radius, 0, sinf(angle) * radius)
                if isClear(spot) { return spot }
            }
        }
        return nil
    }
}
