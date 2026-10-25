import Foundation
import GameCore

// Decision 361: the company's parks and temples, drawn from the Codex model
// kits as they are (#946's park and civic kits, the temples of decision
// 331): each look its own model, facing south. Close up only; from
// farther, a park is its lawn and a temple the box of its hall.
// Decision 398: its hotels, department stores and amusement park from the
// estate kit, its wharves and marinas from the coastal kit, the same way:
// close up the kit's models, from farther a box round each tall one.
// Decision 361's sequel: its schools and hospitals from the civic kit
// (with the park kit's pitch and play things), its night markets from the
// commercial kit's stalls and the civic kit's market, the same way.

extension Map3DScene.Builder {
    /// Each park look's model (``PlacedBuildingKind/looks``): a community
    /// garden, a playground, a pond garden.
    static let placedParkModels: [Map3DMesh] = [Map3DParkKit.Example.pocketPark, .playground, .gardenWalk].map { example in
        var builder = StationKitBuilder()
        builder.add(Map3DParkKit.model(for: example), at: .zero)
        return builder.mesh
    }

    /// Each temple look's model: the hall, burner and gate on a square,
    /// and the kit's large temple square.
    static let placedTempleModels: [TempleModel] = [templeModels[.temple]!, templeModels[.large]!]

    /// Draws `building` if it is a park or a temple on `base`, its foot
    /// on the ground, `side` metres across. Returns whether it drew it.
    mutating func addPlacedKitBuilding(_ building: PlacedBuilding, base: Map3DPoint, side: Float) -> Bool {
        let facing = Self.templeFacings[0]
        switch building.kind {
        case .park:
            mesh(at: base) { mesh in
                mesh.addBox(base: base, length: side, width: side, height: 0.1, top: Map3DPalette.park, side: Map3DPalette.park)
            }
            target = .close
            mesh(at: base) { $0.append(Self.placedParkModels[building.look], at: base, forward: facing) }
            target = .base
            return true
        case .temple:
            let model = Self.placedTempleModels[building.look]
            target = .close
            mesh(at: base) { $0.append(model.mesh, at: base, forward: facing) }
            let hall = base + facing * model.hall.x + Map3DPoint(0, Self.templeHallFloor, 0)
            for level in [Target.near, .far] {
                target = level
                mesh(at: base) { mesh in
                    mesh.addBox(base: hall, forward: facing, length: model.hall.length, width: model.hall.width, height: model.hall.height,
                                top: Map3DPalette.templeRoof, side: Map3DPalette.templeWall)
                }
            }
            target = .base
            return true
        case .hotel, .departmentStore, .amusementPark, .wharf, .marina, .school, .hospital, .nightMarket:
            let layout = Self.placedKitLayouts[building.kind]![building.look]
            let facing = building.kind.standsOnShore ? seaward(of: building) : facing
            let right = facing.cross(.up)
            var model = layout.mesh
            let roof = layout.recolours ? Self.placedRoofs[building.id.rawValue % Self.placedRoofs.count] : Map3DPalette.playerRoof
            if roof != Map3DPalette.playerRoof {
                model.restyleVertices { $0.color = Self.placedRoof($0.color, as: roof) }
            }
            if let pad = layout.pad {
                mesh(at: base) { $0.addBox(base: base, length: side, width: side, height: 0.1, top: pad, side: pad) }
            }
            target = .close
            mesh(at: base) { $0.append(model, at: base, forward: facing) }
            // The boxes round the models hide them: not drawn close up.
            for level in [Target.standIn, .far] {
                target = level
                mesh(at: base) { mesh in
                    for box in layout.boxes {
                        mesh.addBox(base: base + facing * box.centre.x + right * box.centre.z, forward: facing,
                                    length: box.length, width: box.width, height: box.height, top: roof, side: Map3DPalette.player)
                    }
                }
            }
            target = .base
            return true
        default:
            return false
        }
    }

    /// The level way out to sea from `building` on the shore: of the
    /// four ways a temple faces, the one with the most water cells under
    /// the middle and the corners of that side, south when none has any.
    func seaward(of building: PlacedBuilding) -> Map3DPoint {
        let half = building.kind.side / 2 - 1
        func wet(_ dx: Int64, _ dy: Int64) -> Int {
            func cell(_ value: Int64) -> Int { Int(value >= 0 ? value / Land.cellLength : -((-value + Land.cellLength - 1) / Land.cellLength)) }
            return world.isWater(row: cell(building.centre.y + dy), column: cell(building.centre.x + dx)) ? 1 : 0
        }
        let counts = Self.templeFacings.map { way -> Int in
            let ahead = (Int64(way.x) * half, Int64(way.z) * half), across = (Int64(-way.z) * half, Int64(way.x) * half)
            return wet(ahead.0, ahead.1) + wet(ahead.0 + across.0, ahead.1 + across.1) + wet(ahead.0 - across.0, ahead.1 - across.1)
        }
        let most = counts.max() ?? 0
        return most == 0 ? Self.templeFacings[0] : Self.templeFacings[counts.firstIndex(of: most)!]
    }

    /// A kit layout for one look: its models together, built with +x its
    /// front, +y up and +z its right, its foot at 0; the box round each
    /// model taller than 2.5 m (what is drawn from farther); the ground
    /// under the whole lot, if any; and whether its roofs take the
    /// building's own colour.
    struct PlacedKitLayout {
        var mesh: Map3DMesh
        var boxes: [(centre: Map3DPoint, length: Float, width: Float, height: Float)]
        var pad: UInt32?
        var recolours: Bool

        /// `parts`' models, each at `x` ahead and `right` of the middle,
        /// `lift` up, turned `angle` (StationKitBuilder's: clockwise seen
        /// from above), after `ground`.
        init(_ parts: [(model: Map3DModelPack.Model, x: Float, right: Float, lift: Float, angle: Float)], pad: UInt32?, recolours: Bool,
             ground: (inout StationKitBuilder) -> Void = { _ in }) {
            var builder = StationKitBuilder()
            ground(&builder)
            boxes = []
            for part in parts {
                builder.add(part.model, at: Map3DPoint(part.x, part.lift, part.right), angle: part.angle)
                guard part.model.maximum.z > 2.5 else { continue }
                // The model's footprint turned as `add` turns it.
                let c = cosf(part.angle), s = sinf(part.angle)
                let corners = [(part.model.minimum.x, part.model.minimum.y), (part.model.maximum.x, part.model.minimum.y),
                               (part.model.maximum.x, part.model.maximum.y), (part.model.minimum.x, part.model.maximum.y)]
                    .map { (x: c * $0.0 + s * $0.1, z: s * $0.0 - c * $0.1) }
                let low = (x: corners.map(\.x).min()!, z: corners.map(\.z).min()!), high = (x: corners.map(\.x).max()!, z: corners.map(\.z).max()!)
                boxes.append((centre: Map3DPoint(part.x + (low.x + high.x) / 2, part.lift, part.right + (low.z + high.z) / 2),
                               length: high.x - low.x, width: high.z - low.z, height: part.model.maximum.z))
            }
            mesh = builder.mesh
            self.pad = pad
            self.recolours = recolours
        }
    }

    /// Decision 398: the colours the estate kit's roofs (all
    /// ``Map3DPalette/playerRoof``, a pale cream) take, by the building's
    /// number, so the company's buildings side by side differ: the map's
    /// blue tin, a temple's orange tiles, a tree's green and brown tin.
    static let placedRoofs: [UInt32] = [Map3DPalette.tinRoofs[0], Map3DPalette.templeRoof, Map3DPalette.crown, Map3DPalette.tinRoofs[4]]

    /// `colour` in `roof` if it is ``Map3DPalette/playerRoof`` or a shade
    /// of it (a slope the roof builders darken), in the same shade; any
    /// other colour as it is.
    static func placedRoof(_ colour: UInt32, as roof: UInt32) -> UInt32 {
        let cream = Map3DPalette.playerRoof
        func channel(_ value: UInt32, _ shift: UInt32) -> Float { Float((value >> shift) & 0xFF) }
        let shade = channel(colour, 0) / channel(cream, 0)
        guard colour & 0xFF00_0000 == cream & 0xFF00_0000, shade > 0,
              [8, 16].allSatisfy({ abs(channel(colour, $0) - channel(cream, $0) * shade) <= 1.5 }) else { return colour }
        return Map3DColor.shaded(roof, shade)
    }

    /// Each look's layout (``PlacedBuildingKind/looks``) of the kinds the
    /// estate and coastal kits draw (decision 398).
    static let placedKitLayouts: [PlacedBuildingKind: [PlacedKitLayout]] = {
        typealias Estate = Map3DEstateKit.Part
        func estate(_ part: Estate, _ x: Float = 0, _ right: Float = 0, _ angle: Float = 0) -> (model: Map3DModelPack.Model, x: Float, right: Float, lift: Float, angle: Float) {
            (Map3DEstateKit.model(for: part), x, right, 0, angle)
        }
        func coastal(_ part: Map3DCoastalKit.Part, _ x: Float, _ right: Float, lift: Float, _ angle: Float = 0) -> (model: Map3DModelPack.Model, x: Float, right: Float, lift: Float, angle: Float) {
            (Map3DCoastalKit.model(for: part), x, right, lift, angle)
        }
        // The coastal kit's harbour (Map3DCoastalKit.Example.fishingHarbor):
        // its quay top and water 0.3 m up, a floating thing's origin the
        // water less its waterline (the coastal-kit skill).
        let water: Float = 0.3
        func afloat(_ part: Map3DCoastalKit.Part) -> Float {
            water - part.connectors.first { $0.name == "waterline" }!.position.z
        }
        let forecourt = Map3DPalette.forecourt
        typealias Part = (model: Map3DModelPack.Model, x: Float, right: Float, lift: Float, angle: Float)
        func civic(_ part: Map3DCivicKit.Part, _ x: Float, _ right: Float, _ angle: Float = 0) -> Part {
            (Map3DCivicKit.model(for: part), x, right, 0, angle)
        }
        func play(_ part: Map3DParkKit.Part, _ x: Float, _ right: Float, _ angle: Float = 0) -> Part {
            (Map3DParkKit.model(for: part), x, right, 0, angle)
        }
        func stall(_ part: Map3DCommercialKit.Part, _ x: Float, _ right: Float, _ angle: Float = 0) -> Part {
            (Map3DCommercialKit.model(for: part), x, right, 0, angle)
        }
        // A hotel (30 m) one of the kit's three largest: the tower for its
        // fourteen storeys, the resort round its pool, the hot-spring inn.
        let hotels = [Estate.towerHotel, .resortHotel, .hotSpringInn].map { PlacedKitLayout([estate($0)], pad: forecourt, recolours: true) }
        // A department store (46 m) four commercial halls round a cross of
        // walks, the front two facing the street and the back two away.
        let stores = [[Estate.coworkingAtrium, .outletArcade, .foodCourtHall, .gardenCenter],
                      [Estate.exhibitionHall, .weddingBanquetHall, .foodCourtHall, .coworkingAtrium]].map { halls in
            PlacedKitLayout([estate(halls[0], 12, -12), estate(halls[1], 12, 12), estate(halls[2], -12, -12, .pi), estate(halls[3], -12, 12, .pi)],
                            pad: forecourt, recolours: true)
        }
        // The amusement park (110 m): the gate at the front, the wheel and
        // the carousel past it, the castle at the back facing the gate,
        // the water hall and the planetarium at its sides, on a plaza.
        let park = PlacedKitLayout([estate(.themeParkGate, 40), estate(.ferrisWheel, 14, -24), estate(.carouselPavilion, 14, 24),
                                    estate(.fantasyCastle, -26), estate(.waterPlayHall, -18, -34, .pi / 2), estate(.planetarium, -18, 34)],
                                   pad: Map3DPalette.plaza, recolours: true)
        // The wharf (22 m): the kit's own small fishing harbour, its quay
        // and water as the kit lays them (``Map3DCoastalKit/model(for:)``),
        // its water to the sea.
        let wharf = PlacedKitLayout(Map3DCoastalKit.placements(for: .fishingHarbor).map {
            (Map3DCoastalKit.model(for: $0.part), $0.position.x, -$0.position.y, $0.position.z, $0.angle)
        }, pad: nil, recolours: false) { builder in
            builder.box(-4, 0, -1, 10, 16, water, Map3DPalette.concrete)
            builder.box(5, -0.15, -1, 8, 16, water + 0.15, Map3DPalette.water)
        }
        // The marina (30 m): a quay on the land half, two floating piers
        // out into the water half with boats moored along them.
        let marina = PlacedKitLayout([
            coastal(.floatingPontoon, 2.1, -6, lift: afloat(.floatingPontoon)), coastal(.floatingPontoon, 6.3, -6, lift: afloat(.floatingPontoon)),
            coastal(.floatingPontoon, 10.5, -6, lift: afloat(.floatingPontoon)),
            coastal(.floatingPontoon, 2.1, 6, lift: afloat(.floatingPontoon)), coastal(.floatingPontoon, 6.3, 6, lift: afloat(.floatingPontoon)),
            coastal(.floatingPontoon, 10.5, 6, lift: afloat(.floatingPontoon)),
            coastal(.motorDinghy, 5, -2.6, lift: afloat(.motorDinghy)), coastal(.motorDinghy, 10, -9.4, lift: afloat(.motorDinghy)),
            coastal(.rowingSkiff, 9, 2.6, lift: afloat(.rowingSkiff)), coastal(.motorDinghy, 4.5, 9.4, lift: afloat(.motorDinghy)),
            coastal(.mooringBollard, -0.6, -2.6, lift: water), coastal(.mooringBollard, -0.6, 2.6, lift: water),
            coastal(.lifeRingStand, -1, 0, lift: water), coastal(.beaconTower, -2, -13, lift: water),
            coastal(.coastShelter, -10, -6, lift: water), coastal(.kayakRack, -10, 7, lift: water, .pi / 2),
        ], pad: nil, recolours: false) { builder in
            builder.box(-7.5, 0, 0, 15, 30, water, Map3DPalette.concrete)
            builder.box(7.5, -0.15, 0, 15, 30, water + 0.15, Map3DPalette.water)
        }
        // Decision 361's sequel. A school (46 m): the primary school and its
        // gym facing the street, a pitch and play things behind; or a
        // kindergarten with a playground, a court behind.
        let schools = [
            PlacedKitLayout([civic(.primarySchool, 12, -11), civic(.schoolGym, 10, 13, .pi / 2),
                             play(.miniSoccerPitch, -13, -10, .pi / 2), play(.soccerGoal, -5, -10), play(.soccerGoal, -21, -10, .pi),
                             play(.bleachers, -13, 6), play(.slide, -8, 14), play(.swingSet, -14, 18), play(.climbingFrame, -19, 12), play(.sandpit, -19, 19)],
                            pad: forecourt, recolours: false),
            PlacedKitLayout([civic(.kindergarten, 12, -12), play(.playhouse, 12, 8), play(.slide, 16, 14), play(.swingSet, 8, 16), play(.sandpit, 6, 6),
                             play(.basketballCourt, -12, -8, .pi / 2), play(.gazebo, -14, 15)],
                            pad: forecourt, recolours: false),
        ]
        // A hospital (30 m): the clinic and the day-care wing side by
        // side, tables before them; or the care centre in front and the
        // clinic behind.
        let hospitals = [
            PlacedKitLayout([civic(.clinic, 8, -9), civic(.dayCareCenter, 6, 7), civic(.umbrellaTable, -10, -6), civic(.umbrellaTable, -10, 6)],
                            pad: forecourt, recolours: false),
            PlacedKitLayout([civic(.dayCareCenter, 6, -6), civic(.clinic, -8, 8, .pi), civic(.umbrellaTable, -10, -10), play(.gazebo, 10, 11)],
                            pad: forecourt, recolours: false),
        ]
        // A night market (30 m): the commercial kit's alley of stalls
        // (Map3DCommercialKit.Example.nightMarketAlley, as it lays them);
        // or the civic kit's market canopies and carts round tables under
        // lanterns.
        let markets = [
            PlacedKitLayout([stall(.ramenYatai, -5, -8), stall(.nightMarketFryer, -5, 0), stall(.nightMarketFruit, -5, 8),
                             stall(.nightMarketGame, 5, -6, .pi), stall(.mobileFoodCart, 5, 6, .pi), stall(.commercialRecycling, 0, 12),
                             stall(.aFrameSign, -1, -12), stall(.totemLightbox, 1, -12)],
                            pad: Map3DPalette.plaza, recolours: false),
            PlacedKitLayout([civic(.marketCanopy, 8, -7), civic(.marketStall, 8, -9), civic(.marketStall, 8, -5), civic(.produceCart, 6, 1),
                             civic(.snackCart, 10, 1), civic(.umbrellaTable, 7, 7), civic(.umbrellaTable, 11, 11), civic(.lanternString, 2, 7),
                             civic(.marketCanopy, -8, 7, .pi), civic(.marketStall, -8, 9, .pi), civic(.marketStall, -8, 5, .pi),
                             stall(.nightMarketFryer, -8, -6), civic(.umbrellaTable, -4, -11), civic(.umbrellaTable, -11, -11),
                             civic(.lanternString, -2, -7)],
                            pad: Map3DPalette.plaza, recolours: false),
        ]
        return [.hotel: hotels, .departmentStore: stores, .amusementPark: [park], .wharf: [wharf], .marina: [marina],
                .school: schools, .hospital: hospitals, .nightMarket: markets]
    }()
}
