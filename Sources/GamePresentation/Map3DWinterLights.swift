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
    /// How high the lights hang: three fifths of the building, as its eaves
    /// (the kit's houses have theirs at 0.56–0.65 of their tops), at most
    /// this many metres.
    static let highestString: Float = 6
    static let eaveShare: Float = 0.6
    /// How far in from the building's outermost front the lights hang, so
    /// they are under its overhang.
    static let stringSetIn: Float = 0.4
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
            let ground = drawnGround(x: front.centre.x, z: front.centre.z)
            // The lights: 4 m lengths along the front, as many as fit.
            let length: Float = 4
            let count = min(Lights.mostStringsAFront, Int(((front.wide - 1) / length).rounded(.down)))
            if count > 0 {
                let height = min(front.top * Lights.eaveShare, Lights.highestString)
                let line = front.centre + front.forward * (front.depth / 2 - Lights.stringSetIn)
                for number in 0..<count {
                    let at = line + right * ((Float(number) - Float(count - 1) / 2) * length)
                    winterDecor.append(.init(decor: .lightString, point: Map3DPoint(at.x, ground + height, at.z), forward: right))
                }
            }
            guard front.big else { continue }
            let spot = front.centre + front.forward * (front.depth / 2 + Lights.treeOut)
            let corners: [(Float, Float)] = [(-1.8, -1.8), (1.8, -1.8), (1.8, 1.8), (-1.8, 1.8)]
            let footprint = corners.map { spot + front.forward * $0.0 + right * $0.1 }
            guard isClear(footprint, facing: front.forward) else { continue }
            winterDecor.append(.init(decor: .treeMedium, point: Map3DPoint(spot.x, drawnGround(x: spot.x, z: spot.z), spot.z), forward: front.forward))
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
