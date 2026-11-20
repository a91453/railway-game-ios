import Foundation
import GameCore

// Decision 896: the company's houses (``PlacedBuildingKind/house``, a
// 16 m square) drawn from the residential kit (decision 669) instead of
// the yellow box of decision 205: Taiwanese 透天厝 side by side, an
// arcade house, a roof-terrace house, a duplex and a corner house, with
// their roof water tanks and tin rooftop sheds (頂樓加蓋). A house has one
// look in the game; which of these it is drawn as is the building's
// number, as decision 398 picks a roof colour, so a street of the
// player's houses is not one house over and over; the sheds' tin takes
// one of four colours the same way. Close up the models, from farther the
// boxes round them, as the other kits' buildings
// (``Map3DScene/Builder/addPlacedKitBuilding``).

extension Map3DScene.Builder {
    /// The colour a rooftop shed's tin is drawn in, before it takes the
    /// house's own (``placedShedRoofs``).
    static let shedTin = Map3DPalette.tinRoofs[0]
    /// The tin of a rooftop shed by the house's number: the usual blue,
    /// a green, a paler blue and a rusted brown.
    static let placedShedRoofs: [UInt32] = [Map3DPalette.tinRoofs[0], Map3DPalette.crown, Map3DPalette.tinRoofs[1], Map3DPalette.tinRoofs[4]]

    /// A rooftop shed `length` deep and `width` across, its front +x: a
    /// steel-sheet room with a door and a window under a tin roof that
    /// overhangs it, its foot at 0.
    static func rooftopShed(length: Float, width: Float) -> Map3DModelPack.Model {
        var builder = StationKitBuilder()
        let height: Float = 2.3
        builder.box(0, 0, 0, length, width, height, Map3DPalette.shedWalls[1])
        builder.residentialDoor(length / 2, 0, width / 4, width: 0.9)
        builder.residentialWindow(length / 2, 1.0, -width / 4, width: 1.0, height: 0.8)
        builder.box(0.15, height, 0, length + 0.5, width + 0.3, 0.14, shedTin)
        return .flat(named: "rooftop-shed", from: builder.mesh)
    }

    /// A tin awning over a ground-floor front, `width` across, sloping
    /// 0.9 m out and 0.25 m down from its back edge at 0, its tin the
    /// rooftop sheds' (``shedTin``), so the two take the house's colour
    /// together.
    static func streetAwning(width: Float) -> Map3DModelPack.Model {
        var builder = StationKitBuilder()
        let depth: Float = 0.9, drop: Float = 0.25, thickness: Float = 0.06
        Map3DScene.Builder.addSlope(&builder.mesh, from: .zero, facing: StationKitBuilder.forward,
                                    width: width, depth: depth, drop: drop, color: shedTin)
        let top = [Map3DPoint(0, 0, -width / 2), Map3DPoint(0, 0, width / 2),
                   Map3DPoint(depth, -drop, width / 2), Map3DPoint(depth, -drop, -width / 2)]
        let bottom = top.map { $0 - Map3DPoint(0, thickness, 0) }
        let inside = Map3DPoint(depth / 2, -drop / 2 - thickness, 0)
        builder.face(bottom, inside: inside, color: shedTin)
        for i in 0..<4 { let j = (i + 1) % 4; builder.face([top[i], bottom[i], bottom[j], top[j]], inside: inside, color: shedTin) }
        return .flat(named: "street-awning", from: builder.mesh)
    }

    /// The houses' layouts, each inside the 14 m the house is drawn in
    /// (its 16 m less a metre each side), its front +x.
    static let placedHouseLayouts: [PlacedKitLayout] = {
        typealias Part = (model: Map3DModelPack.Model, x: Float, right: Float, lift: Float, angle: Float)
        typealias Home = Map3DResidentialKit.Part
        func home(_ part: Home, _ x: Float, _ right: Float, lift: Float = 0, angle: Float = 0) -> Part {
            (Map3DResidentialKit.model(for: part), x, right, lift, angle)
        }
        func awning(_ width: Float, _ x: Float, _ right: Float) -> Part {
            (streetAwning(width: width), x, right, 2.95, 0)
        }
        func shed(_ length: Float, _ width: Float, _ x: Float, _ right: Float, lift: Float) -> Part {
            (rooftopShed(length: length, width: width), x, right, lift, 0)
        }
        // The kit's roofs (its recipes): the narrow townhouse's slab top
        // 9.33 m up, 6.2 m deep and 0.4 m behind its middle; the arcade
        // house's 9.28 m, 8.2 m and 0.7 m; the roof-terrace house's 6.56 m
        // and the corner house's 6.60 m, 0.8 m behind; the duplex's 6.42 m.
        let narrowRoof: Float = 9.33, arcadeRoof: Float = 9.28, terraceRoof: Float = 6.56, cornerRoof: Float = 6.60, duplexRoof: Float = 6.42
        return [
            // Two narrow townhouses side by side, tin awnings over their
            // ground floors, a shed on the back of one roof, a tank on each.
            PlacedKitLayout([home(.narrowTownhouse, 2.5, -3.0), home(.narrowTownhouse, 2.5, 3.0),
                             shed(3.0, 4.6, 0.3, -3.0, lift: narrowRoof),
                             home(.waterTank, 3.2, -3.0, lift: narrowRoof), home(.waterTank, 1.0, 3.0, lift: narrowRoof),
                             awning(5.0, 4.98, -3.0), awning(5.0, 4.98, 3.0),
                             home(.planter, -5.0, 0)], pad: nil, recolours: false),
            // An arcade townhouse with a shed beside an old brick one.
            PlacedKitLayout([home(.arcadeTownhouse, 2.4, -2.95), home(.oldNarrowTownhouse, 2.4, 4.0),
                             shed(4.0, 6.0, 0.0, -2.95, lift: arcadeRoof),
                             home(.waterTank, 4.0, -4.2, lift: arcadeRoof), home(.waterTank, 0.9, 4.0, lift: narrowRoof)],
                            pad: nil, recolours: false),
            // The roof-terrace house, its tank and solar panel up top, a
            // planter by the street.
            PlacedKitLayout([home(.roofTerraceHouse, 2.0, -2.0), home(.waterTank, 0.3, -0.3, lift: terraceRoof),
                             home(.roofSolar, 2.9, -0.8, lift: terraceRoof), home(.planter, 5.8, 4.5)],
                            pad: nil, recolours: false),
            // A pair of semi-detached houses, one with a shed.
            PlacedKitLayout([home(.duplexHouse, 1.5, 0), shed(3.6, 5.0, -0.6, -3.3, lift: duplexRoof),
                             home(.waterTank, -1.5, 3.3, lift: duplexRoof)],
                            pad: nil, recolours: false),
            // The corner house with a shed and a tank, a planter along its side.
            PlacedKitLayout([home(.cornerHouse, 1.5, -1.5), shed(3.4, 4.4, -0.3, -2.4, lift: cornerRoof),
                             home(.waterTank, 2.6, 0.6, lift: cornerRoof), home(.planter, 1.5, 5.3, angle: .pi / 2)],
                            pad: nil, recolours: false),
        ]
    }()
}

/// Decision 896: the company's houses as single models, for the model-look
/// tools (`tools/model-look/export-houses.sh`).
public enum Map3DPlacedHouses {
    /// How many ways a house is drawn.
    public static var count: Int { Map3DScene.Builder.placedHouseLayouts.count }

    /// The `index`th way, x front, y left, z up, metres; its rooftop shed
    /// in the `tin`th of ``Map3DScene/Builder/placedShedRoofs``.
    public static func model(_ index: Int, tin: Int = 0) -> Map3DModelPack.Model {
        var mesh = Map3DScene.Builder.placedHouseLayouts[index].mesh
        let colour = Map3DScene.Builder.placedShedRoofs[tin]
        mesh.restyleVertices { $0.color = Map3DScene.Builder.placedRoof($0.color, from: Map3DScene.Builder.shedTin, as: colour) }
        return .flat(named: "placed-house-\(index)", from: mesh)
    }
}
