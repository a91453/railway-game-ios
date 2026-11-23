import Foundation
import GameCore

/// Decision 944: 關渡大橋 over the Tamsui River: its three red half-through
/// steel arches (143, 165 and 143 m, the middle one highest) with their
/// hangers, the deck between them and the V-shaped piers under it, the
/// 539 m of steel between the concrete approaches. Modelled by the local
/// studio from photographs (`a91453/railway-assets-private-2`
/// `game-art-previews/docs/art/tw-landmark-guandu-bridge-2026-11/revision-2`,
/// #299; lessons in `docs/studio/lessons/tw-guandu-bridge.md`) and written
/// here by `tools/landmarks/glb_to_swift.py --turn 32.2 --raise 1`
/// (``encoded``): turned onto OpenStreetMap's way, and raised by the metre
/// its pier footings reach under the water, which ``registration``'s
/// `sink` lowers again, so the water at its middle is the river's.
///
/// The road the base map draws over the river is lifted onto its deck
/// (``deck``, the way decision 873 lifts 淡江大橋's), so the cars cross on
/// the arches, and no pier of the road's own stands under it
/// (``Map3DScene/Builder/standsOnArchBridge(x:z:)``).
enum Map3DGuanduBridge {
    static let registration = Map3DLandmarkRegistration(
        id: "tw-guandu-bridge", map: "taiwan",
        // The middle of OpenStreetMap's way 250500239 (534 m, straight,
        // 57.8° east of north).
        latitude: 25.1255488, longitude: 121.4572397,
        sink: 1,
        // archRed, hanger, deck, pier.
        palette: [Map3DPalette.mtrRed, Map3DPalette.tankSteel, Map3DPalette.portal, Map3DPalette.concrete],
        encoded: encoded,
        // 539 m by 20.6 m turned 32.2°: its footprint's box east and
        // north; the arches' crown 36.1 m over the water, with the footing
        // a metre under it.
        size: (466.22, 303.30, 37.1))

    /// The deck the model carries the road on.
    static let deck = Map3DArchBridgeDeck(
        latitude: registration.latitude, longitude: registration.longitude, bearing: 57.8,
        // The model's steel: 269.5 m either side of its middle, 10.3 m
        // either side of its line.
        half: 269.5, width: 10.3,
        // Its deck's top over the water at its middle.
        top: 16.0)
}

/// Decision 944: a registered landmark bridge that carries the base map's
/// road over a river on its own deck: the road is held up to ``top``
/// along it (as decision 873 holds 淡江大橋's), a little over the model's
/// deck, and its piers are the model's.
struct Map3DArchBridgeDeck: Sendable {
    /// The middle of its deck, on the water.
    let latitude: Double
    let longitude: Double
    /// Its line, degrees clockwise from north.
    let bearing: Double
    /// How far its deck reaches each way along its line, and each side of
    /// it, metres.
    let half: Float
    let width: Float
    /// Its deck's top over the water at its middle, metres.
    let top: Float

    static let all = [Map3DGuanduBridge.deck]

    /// How far the road's top stands over the model's deck, metres: as
    /// decision 873's deck between 淡江大橋's carriageways keeps under it.
    static let roadOver: Float = 0.15

    /// Placed in the scene whose origin is the world (`originX`, `originY`).
    struct Placed: Sendable {
        let middle: Map3DPoint
        let along: Map3DPoint
        let across: Map3DPoint
        let deck: Map3DArchBridgeDeck

        /// The scene point `along` metres from its middle along its line.
        func point(along distance: Float) -> Map3DPoint { middle + along * distance }

        /// Whether scene point (`x`, `z`) is under its deck.
        func covers(x: Float, z: Float) -> Bool {
            let d = Map3DPoint(x - middle.x, 0, z - middle.z)
            return abs(d.dot(along)) <= deck.half && abs(d.dot(across)) <= deck.width + 5
        }
    }

    func placed(frame: RealWorldFrame, origin: (x: Double, y: Double)) -> Placed? {
        let metre = Double(WorldCoordinate.unitsPerMetre)
        let turn = bearing * .pi / 180, reach = 100.0
        let ahead = (latitude: latitude + cos(turn) * reach / 111_320,
                     longitude: longitude + sin(turn) * reach / (111_320 * cos(latitude * .pi / 180)))
        let points = [(latitude, longitude), ahead].map { place -> Map3DPoint in
            let world = frame.worldPosition(latitude: place.0, longitude: place.1)
            return Map3DPoint(Float((world.x - origin.x) / metre), 0, Float((world.y - origin.y) / metre))
        }
        guard let along = (points[1] - points[0]).normalized else { return nil }
        return Placed(middle: points[0], along: along, across: Map3DPoint(-along.z, 0, along.x), deck: self)
    }
}

extension Map3DScene.Builder {
    /// Decision 944: the landmark bridges whose deck reaches within 2 km of
    /// what the scene covers.
    mutating func archBridges() -> [Map3DArchBridgeDeck.Placed] {
        if let placedArchBridges { return placedArchBridges }
        var found: [Map3DArchBridgeDeck.Placed] = []
        if let frame = RealWorldFrame(world: world) {
            let reach = 2_000 * Self.metre
            for deck in Map3DArchBridgeDeck.all {
                guard let placed = deck.placed(frame: frame, origin: (originX, originY)) else { continue }
                let ends = [placed.point(along: -deck.half), placed.point(along: deck.half)]
                    .map { (x: originX + Double($0.x) * Self.metre, y: originY + Double($0.z) * Self.metre) }
                let (xs, ys) = (ends.map(\.x), ends.map(\.y))
                guard xs.max()! >= region.minX - reach, xs.min()! <= region.maxX + reach,
                      ys.max()! >= region.minY - reach, ys.min()! <= region.maxY + reach else { continue }
                found.append(placed)
            }
        }
        placedArchBridges = found
        return found
    }

    /// Decision 944: whether a road's deck at scene point (`x`, `z`) lies
    /// on a landmark bridge's, so no pier of its own stands under it.
    mutating func standsOnArchBridge(x: Float, z: Float) -> Bool {
        archBridges().contains { $0.covers(x: x, z: z) }
    }
}
