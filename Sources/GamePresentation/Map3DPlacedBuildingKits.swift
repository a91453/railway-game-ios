import Foundation
import GameCore

// Decision 361: the company's parks and temples, drawn from the Codex model
// kits as they are (#946's park and civic kits, the temples of decision
// 331): each look its own model, facing south. Close up only; from
// farther, a park is its lawn and a temple the box of its hall.

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
        default:
            return false
        }
    }
}
