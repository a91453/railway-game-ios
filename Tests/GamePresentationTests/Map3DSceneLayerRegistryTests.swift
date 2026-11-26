import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 976: what each layer of the 3D scene keeps while the scene is
/// built is its own struct in its own file, listed one line a layer in
/// `Map3DSceneLayerList.swift` (``Map3DScene/Builder/LayerStates``); the
/// builder itself keeps only what every layer shares.
final class Map3DSceneLayerRegistryTests: XCTestCase {
    static let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources/GamePresentation")

    /// What every layer shares: where the scene is, the meshes by chunk
    /// and kind, what is being built, the ground, the shared work and the
    /// tallies of each step. A layer's own state does not join them.
    static let shared: Set<String> = [
        "originX", "originY", "region", "world", "meshes", "shadows", "sizing", "sizesFar", "farSizing", "baseParts", "farParts", "shadowParts",
        "layers", "marked", "steps", "stepEnded", "target", "state", "facadeMeshes", "props", "signs", "streetLife", "studyRegion",
        "nearMeshes", "keptColours", "farMeshes", "instancingBoxes", "closeMeshes", "standInMeshes", "ownColourNear", "ownColourFar",
        "corners", "levelling", "trackCover", "shared", "detail", "detailAhead", "fileGround", "placedGround", "look",
    ]

    private func builder() -> Map3DScene.Builder {
        let world = GameWorld.newGame()
        let (region, originX, originY) = Map3DScene.frame(world: world, focus: nil)
        return Map3DScene.Builder(originX: originX, originY: originY, region: region, world: world, heights: nil)
    }

    /// The builder keeps what every layer shares and no more: a layer's
    /// own state goes in its own file.
    func testTheBuilderKeepsOnlyWhatTheLayersShare() {
        let stored = Set(Mirror(reflecting: builder()).children.compactMap(\.label))
        XCTAssertEqual(stored.subtracting(Self.shared), [],
                       "a layer's own state is a struct in the layer's file, with its line in Map3DSceneLayerList.swift (decision 976)")
        XCTAssertEqual(Self.shared.subtracting(stored), [], "no longer the builder's: take it out of `shared` here")
    }

    /// Each line of the list is one layer's, under a name of its own, of
    /// a type declared outside the list and outside the builder's file.
    func testEachLineIsOneLayersState() throws {
        let list = try String(contentsOf: Self.sources.appendingPathComponent("Map3DSceneLayerList.swift"), encoding: .utf8)
        let line = try NSRegularExpression(pattern: #"^        var (\w+) = (\w+)\(\)$"#, options: .anchorsMatchLines)
        let lines = line.matches(in: list, range: NSRange(list.startIndex..., in: list)).map { match in
            (String(list[Range(match.range(at: 1), in: list)!]), String(list[Range(match.range(at: 2), in: list)!]))
        }
        let declared = list.components(separatedBy: "\n").filter { $0.hasPrefix("        var ") }
        XCTAssertEqual(lines.count, declared.count, "one `var <layer> = <Type>()` a line: \(declared)")
        XCTAssertEqual(Set(lines.map(\.0)).count, lines.count, "a layer listed twice (two branches each added it?)")
        XCTAssertEqual(Set(lines.map(\.1)).count, lines.count, "a state listed twice")
        let children = Mirror(reflecting: Map3DScene.Builder.LayerStates()).children.compactMap(\.label)
        XCTAssertEqual(children, lines.map(\.0))

        var homes: [String: [String]] = [:]
        for name in try FileManager.default.contentsOfDirectory(atPath: Self.sources.path) where name.hasSuffix(".swift") {
            let text = try String(contentsOf: Self.sources.appendingPathComponent(name), encoding: .utf8)
            for (_, type) in lines where text.contains("struct \(type) ") || text.contains("struct \(type):") {
                homes[type, default: []].append(name)
            }
        }
        for (layer, type) in lines {
            let files = homes[type] ?? []
            XCTAssertEqual(files.count, 1, "\(layer): \(type) declared once, in its layer's file: \(files)")
            XCTAssertFalse(files.contains("Map3DSceneLayerList.swift") || files.contains("Map3DSceneBuilder.swift"),
                           "\(layer): its state goes in the layer's own file")
        }
    }
}
