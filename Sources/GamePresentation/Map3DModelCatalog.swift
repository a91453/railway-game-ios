import Foundation
import GameCore

/// Decision 820 (PERF-3D-FIRST): the name and bounds of every model of
/// ``Map3DModelPack/standard``, in its order, with no vertices: what a
/// scene needs of the models it places (their places, by name, and their
/// boxes), without waiting for the pack.
///
/// The pack is made once, at a low priority (decision 546's
/// `Map3DTrainModels`), with its shade baked on every core: on a phone
/// some tens of seconds. A scene that asked the pack for a street lamp's
/// place while it was being made waited for all of it (the owner's build
/// 136: 44.9 s to build the first scene). The catalog is made from the
/// recipes alone, in the order the pack puts them, and the windows' models
/// it puts after them (``Map3DTrainLights/split(_:recipes:)``): baking the
/// shade, marking the glass and unlighting a car keep each model's name
/// and bounds, so these are the pack's own, to the bit
/// (`Map3DModelCatalogTests`). Made from the pack itself when it is
/// already made.
struct Map3DModelCatalog: Sendable {
    /// Each model's name, in the pack's order.
    let names: [String]
    let minimum: [Map3DPoint]
    let maximum: [Map3DPoint]
    private let first: [String: Int]

    init(models: [Map3DModelPack.Model]) {
        names = models.map(\.name)
        minimum = models.map(\.minimum)
        maximum = models.map(\.maximum)
        var first: [String: Int] = [:]
        for (index, name) in names.enumerated() where first[name] == nil { first[name] = index }
        self.first = first
    }

    /// The model called `name`'s index, as ``Map3DModelPack/index(of:)``.
    func index(of name: String) -> Int? {
        first[name]
    }

    /// ``Map3DModelPack/standard``'s catalog, made once.
    static let standard: Map3DModelCatalog = {
        if let pack = Map3DModelPack.standardIfMade { return Map3DModelCatalog(models: pack.models) }
        return Map3DModelCatalog(models: Map3DModelPack.recipesWithWindows(styles: Map3DTrainStyle.all))
    }()
}
