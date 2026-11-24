import Foundation

/// Decision 949: where bicycles are parked on the 3D map, in the kits' own
/// rack and shed. The station kit's bicycle rack (three steel hoops,
/// `Map3DStationKit.Part.bikeRack`) stands by the bus stops whose
/// pavement is wide enough and beside the exits of underground stations
/// and the stair entrances of elevated ones; the residential kit's shed
/// (`Map3DResidentialKit.Part.bikeShed`) at the company's primary schools.
/// Decision 918's bicycles stand in them, no longer loose by the stops.
/// How many places have one is the region's
/// (``Map3DStreetRegion/stopRackShare``, ``Map3DStreetRegion/exitRackShare``):
/// Taiwan's and Japan's streets many, Hong Kong's few.
public enum Map3DBikeParking {
    /// The two models, by their names in ``Map3DModelPack``.
    public enum Unit: String, CaseIterable, Sendable {
        case rack = "bike-rack"
        case shed = "bike-shed"
    }

    /// The two models, for ``Map3DModelPack``: after the level crossings'
    /// boom and before the route bus, which stays last.
    static var drawn: [Map3DModelPack.Model] {
        Unit.allCases.map(model).map(Map3DLook.restyle)
    }

    /// `unit`'s model: the kit's part as it is, named for the pack.
    public static func model(_ unit: Unit) -> Map3DModelPack.Model {
        var builder = StationKitBuilder()
        switch unit {
        case .rack: builder.part(.bikeRack)
        case .shed: builder.residential(.bikeShed, far: false, traditional: true)
        }
        return .flat(named: unit.rawValue, from: builder.mesh)
    }

    /// The rack's hoops stand this far along it from its middle, metres
    /// (the kit's), and a bicycle beside each, this far on from its hoop:
    /// its 0.62 m handlebars clear the next hoop.
    static let hoops: [Double] = [-1, 0, 1]
    static let besideHoop = 0.3

    /// Where the first `count` bicycles in a rack stand along it from its
    /// middle, metres: one beside each hoop, three at most.
    static func inRack(_ count: Int) -> [Double] {
        hoops.prefix(max(0, min(count, hoops.count))).map { $0 + besideHoop }
    }

    /// The shed's three wheel stops (the kit's, 1.5 m apart across it at
    /// x −1.5): a bicycle's middle stands this far ahead of the shed's
    /// middle, its front wheel in the stop, facing back (−x).
    static let shedSlots: [Float] = [-1.5, 0, 1.5]
    static let shedAhead: Float = -0.5

    /// What stands in a rack, for two random numbers in 0..<1 (which kind,
    /// how many): a dock's three public bicycles where the map has them
    /// (`publicBikes`), this share of the time; else two or three
    /// ordinary ones.
    static func rackLoad(publicBikes: Bool, publicShare: Float, kind: Float, count: Float) -> [Map3DBicycle.Unit] {
        if publicBikes && kind < publicShare { return Array(repeating: .publicBike, count: 3) }
        return Array(repeating: .bicycle, count: count < 0.5 ? 2 : 3)
    }

    /// One rack by a station's way in: its middle `ahead` metres along the
    /// exit from the exit's middle (toward the way in) and `aside` metres
    /// out from it, away from the track; its hoops in a row along the
    /// exit, the bicycles across it.
    struct ExitRack: Equatable, Sendable {
        var ahead: Float
        var aside: Float
        var bicycles: [Map3DBicycle.Unit]
    }

    /// Of the racks by the exits, this share hold public bicycles where the
    /// map has them: the docks at Taipei's and Kaohsiung's metro exits.
    static let exitPublicShare: Float = 0.5

    /// The rack beside an exit `width` metres across (its half each side)
    /// and `length` long, for three random numbers in 0..<1 (whether any,
    /// which kind, how many), on `region`'s map: none past the region's
    /// share. It stands by the half of the exit nearer the way in, a
    /// bicycle's half length and 0.4 m out from its side.
    static func exitRack(width: Float, length: Float, region: Map3DStreetRegion, random: (any: Float, kind: Float, count: Float)) -> ExitRack? {
        guard random.any < region.exitRackShare else { return nil }
        let load = rackLoad(publicBikes: region.hasPublicBicycles, publicShare: exitPublicShare, kind: random.kind, count: random.count)
        return ExitRack(ahead: length / 4, aside: width / 2 + 0.4 + 0.9, bicycles: load)
    }
}

extension Map3DBikeParking {
    /// A part of a kit layout (``Map3DScene/Builder/PlacedKitLayout``):
    /// its model, `x` ahead and `right` of the layout's middle, `lift` up,
    /// turned `angle`.
    typealias LayoutPart = (model: Map3DModelPack.Model, x: Float, right: Float, lift: Float, angle: Float)

    /// An ordinary bicycle in a layout: its middle `x` ahead and `right`
    /// of the layout's middle, its front wheel toward the layout's front
    /// (+x) or, `backward`, its back. Drawn as the streets' bicycles are,
    /// close up only (``Map3DScene/Builder/addLayoutBicycles(_:base:facing:)``),
    /// so a layout's own triangles stay as they were.
    struct LayoutBicycle: Equatable, Sendable {
        var x: Float
        var right: Float
        var backward: Bool
    }

    /// Decision 949: a rack, its middle at `x`, `right` in a layout, its
    /// hoops in a row to the right, and `count` bicycles in it, their
    /// front wheels toward the layout's front (+x).
    static func rack(x: Float, right: Float, bicycles count: Int) -> (parts: [LayoutPart], bicycles: [LayoutBicycle]) {
        ([(model(.rack), x, right, 0, 0)], inRack(count).map { LayoutBicycle(x: x, right: right + Float($0), backward: false) })
    }

    /// Decision 949: the shed, its middle at `x`, `right` in a layout, and
    /// a bicycle in each of its wheel stops.
    static func shed(x: Float, right: Float) -> (parts: [LayoutPart], bicycles: [LayoutBicycle]) {
        ([(model(.shed), x, right, 0, 0)], shedSlots.map { LayoutBicycle(x: x + shedAhead, right: right + $0, backward: true) })
    }
}

extension Map3DStreetRegion {
    /// Decision 949: the share of the bus stops with a wide enough
    /// pavement that have a bicycle rack (decision 918 had loose bicycles
    /// by 35% of them everywhere). Taiwan's and Japan's as before; Hong
    /// Kong's few (its urban streets have little cycle parking; the racks
    /// are in the New Towns); Finland's few, under snow.
    var stopRackShare: Float {
        switch self {
        case .taiwan, .japan: 0.35
        case .finland: 0.2
        case .hongKong: 0.1
        }
    }

    /// Decision 949: the share of an underground station's exits and an
    /// elevated one's stair entrances with a bicycle rack beside them:
    /// most of Taiwan's metro exits have one, or a public bicycle dock;
    /// Fukuoka's stations their bicycle parks; Hong Kong's MTR exits
    /// seldom.
    var exitRackShare: Float {
        switch self {
        case .taiwan: 0.7
        case .japan: 0.6
        case .finland: 0.3
        case .hongKong: 0.15
        }
    }
}

extension Map3DScene.Builder {
    /// Decision 949: the bicycle racks' and sheds' models in
    /// ``Map3DModelPack/standard``.
    static let bikeParkingModels: [Map3DBikeParking.Unit: Int] = Dictionary(uniqueKeysWithValues: Map3DBikeParking.Unit.allCases.compactMap { unit in
        Map3DModelCatalog.standard.index(of: unit.rawValue).map { (unit, $0) }
    })

    /// Decision 949: a rack beside the station exit (or stair entrance)
    /// standing at `foot`, its way in `forward` and the track behind its
    /// left, for the exit's own random numbers: the rack and its bicycles,
    /// close up only, as the streets' furniture.
    mutating func addExitBikeRack(exit foot: Map3DPoint, forward: Map3DPoint, width: Float, length: Float) {
        let seed = (Int32(truncatingIfNeeded: Int((foot.x * 2).rounded())), Int32(truncatingIfNeeded: Int((foot.z * 2).rounded())))
        guard let rack = Map3DBikeParking.exitRack(width: width, length: length, region: streetLife.region,
                                                   random: (map3DRandom(seed.0, seed.1, salt: 949), map3DRandom(seed.0, seed.1, salt: 950),
                                                            map3DRandom(seed.0, seed.1, salt: 951))),
              let rackModel = Self.bikeParkingModels[.rack] else { return }
        let along = Map3DPoint(forward.x, 0, forward.z).normalized ?? Map3DPoint(1, 0, 0), away = along.cross(.up)
        let middle = foot + along * rack.ahead + away * rack.aside
        func stand(_ model: Int, at point: Map3DPoint, facing: Map3DPoint) {
            let at = Map3DPoint(point.x, drawnGround(x: point.x, z: point.z), point.z)
            props[key(of: at), default: []].append(.prop(model, at: at, forward: facing, scale: 1, tint: Map3DColor.rgb(0xFFFFFF)))
        }
        // The rack's +x across the exit, so its hoops run along it.
        stand(rackModel, at: middle, facing: away)
        // A bicycle beside each hoop, its front wheel toward the exit
        // (the hoops stand evenly either side, so either way along fits).
        for (offset, unit) in zip(Map3DBikeParking.inRack(rack.bicycles.count), rack.bicycles) {
            guard let model = Self.bicycleModels[unit] else { continue }
            stand(model, at: middle - along * Float(offset), facing: away * -1)
        }
    }
}

extension Map3DScene.Builder {
    /// Decision 949: a kit layout's bicycles standing on its ground at
    /// `base` (its pad's 0.1 m up), the layout facing `facing`.
    mutating func addLayoutBicycles(_ bicycles: [Map3DBikeParking.LayoutBicycle], base: Map3DPoint, facing: Map3DPoint) {
        guard let model = Self.bicycleModels[.bicycle] else { return }
        let right = facing.cross(.up)
        for bicycle in bicycles {
            let at = base + facing * bicycle.x + right * bicycle.right + Map3DPoint(0, 0.1, 0)
            props[key(of: at), default: []].append(.prop(model, at: at, forward: bicycle.backward ? facing * -1 : facing, scale: 1,
                                                         tint: Map3DColor.rgb(0xFFFFFF)))
        }
    }
}
