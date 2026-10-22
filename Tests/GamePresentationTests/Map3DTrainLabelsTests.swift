import GameCore
@testable import GamePresentation
import XCTest

/// Decision 314: close up, a label over the front of the few trains
/// nearest the middle of the 3D map: the line's badge and riders over
/// capacity.
final class Map3DTrainLabelsTests: XCTestCase {
    private func info(_ code: String) -> Map3DTrainLabels.Info {
        Map3DTrainLabels.Info(line: LineID(rawValue: 1), code: code, riders: 120, capacity: 640)
    }

    private func head(_ train: Int, _ x: Float, _ z: Float) -> Map3DTrains.Head {
        Map3DTrains.Head(train: TrainID(rawValue: train), point: Map3DPoint(x, 0, z))
    }

    private let camera = Map3DCamera(target: .zero, distance: 300, viewport: (400, 800))

    /// A front at the camera's target is labelled at the view's middle,
    /// the label's foot there.
    func testATrainAtTheMiddleIsLabelledThere() throws {
        let labels = Map3DTrainLabels(infos: [TrainID(rawValue: 1): info("BL")]).labels(heads: [head(1, 0, 0)], camera: camera)
        let label = try XCTUnwrap(labels.first)
        XCTAssertEqual(labels.count, 1)
        XCTAssertEqual(label.info.code, "BL")
        XCTAssertEqual(label.x, 200, accuracy: 0.5)
        XCTAssertEqual(label.y, 400, accuracy: 0.5)
    }

    /// At most three, nearest the middle first; none at the view's edges,
    /// none for a train with no label, none from farther than the reach.
    func testOnlyAFewTrainsNearTheMiddleAreLabelled() {
        var infos: [TrainID: Map3DTrainLabels.Info] = [:]
        for train in 1...6 { infos[TrainID(rawValue: train)] = info("L\(train)") }
        let labels = Map3DTrainLabels(infos: infos)
        let heads = [head(1, 20, 0), head(2, 4, 0), head(3, -8, 0), head(4, 14, 0), head(5, 2_000, 0), head(7, 1, 0)]
        XCTAssertEqual(labels.labels(heads: heads, camera: camera).map(\.train.rawValue), [2, 3, 4], "7 has none; 1 is the fourth; 5 is off the middle")

        var far = camera
        far.distance = Map3DTrainLabels.reach + 1
        XCTAssertEqual(labels.labels(heads: heads, camera: far), [])
        XCTAssertEqual(Map3DTrainLabels(infos: [:]).labels(heads: heads, camera: camera), [])
    }

    /// The trains of a world's lines have labels with their line's code
    /// and their load; each train's front is over its first car's roof.
    func testAWorldsTrainsHaveTheirLinesLabels() throws {
        let towns = Land.townCentres(seed: 1, in: GameWorld.newGameBounds)
        var world = try newGameLine(through: [towns[0], towns[1]])
        try world.advance(ticks: 30)
        let line = try XCTUnwrap(world.lines.first)
        let labels = Map3DTrainLabels(world: world)
        XCTAssertEqual(Set(labels.infos.keys), Set(line.trains))
        let code = LineBadge.codes(for: world.lines)[line.id]
        for train in line.trains {
            let info = try XCTUnwrap(labels.infos[train])
            let load = try XCTUnwrap(world.trainLoadInfo(of: train))
            XCTAssertEqual(info.code, code)
            XCTAssertEqual(info.riders, load.passengerCount)
            XCTAssertEqual(info.capacity, load.capacity)
        }

        let motion = TrainMotion(world: world, time: 0)
        let frame = Map3DTrains.frame(motion, progress: 1, heights: Map3DTrains.Heights(world.railwaySnapshot()), in: Map3DScene(world: world),
                                      models: nil, eye: nil)
        XCTAssertEqual(frame.heads.map(\.train), motion.runs.map(\.train))
        let roof = Map3DScene.railLift + Map3DTrains.carHeight
        XCTAssertTrue(frame.heads.allSatisfy { abs($0.point.y - roof - Map3DTrains.headClearance) < 0.01 })
        // Decision 337: the nose, where the cab view looks out, is ahead of the label.
        XCTAssertTrue(frame.heads.allSatisfy { ($0.nose - $0.rail).dot($0.forward) > 1 })
    }
}
