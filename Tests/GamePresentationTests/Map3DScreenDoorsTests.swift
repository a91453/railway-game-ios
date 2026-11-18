import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 847: the real lines' platform screen doors and gates.
final class Map3DScreenDoorsTests: XCTestCase {
    private typealias Doors = Map3DScreenDoors
    private typealias Builder = Map3DScene.Builder

    private func doors(_ line: String, _ station: String, underground: Bool = false) -> Doors.Doors? {
        Doors.doors(realLine: line, station: station, underground: underground)
    }

    // MARK: Which line has which

    func testTaipeiMetrosNewStationsHaveScreenDoorsAndItsOldOnesTheGatesAddedLater() {
        // The Wenhu and Circular lines: full-height everywhere.
        XCTAssertEqual(doors("trtc:BR", "動物園"), .full)
        XCTAssertEqual(doors("trtc:BR", "大安"), .full)
        XCTAssertEqual(doors("trtc:Y", "景安"), .full)
        // The Xinyi section built with them; the Tamsui line's old stations
        // the 1.45 m gates, underground or not.
        XCTAssertEqual(doors("trtc:R", "象山", underground: true), .full)
        XCTAssertEqual(doors("trtc:R", "東門", underground: true), .full)
        XCTAssertEqual(doors("trtc:R", "台北車站", underground: true), .gate(1.45))
        XCTAssertEqual(doors("trtc:R", "淡水"), .gate(1.45))
        XCTAssertEqual(doors("trtc:R_XBT", "新北投"), .gate(1.45))
        // The Songshan section, not the Xindian line.
        XCTAssertEqual(doors("trtc:G", "松山", underground: true), .full)
        XCTAssertEqual(doors("trtc:G", "中山", underground: true), .full)
        XCTAssertEqual(doors("trtc:G", "新店"), .gate(1.45))
        XCTAssertEqual(doors("trtc:G_XBT", "小碧潭"), .gate(1.45))
        // The Luzhou and Xinzhuang sections, not the old Zhonghe line.
        XCTAssertEqual(doors("trtc:O_LUZHOU", "蘆洲", underground: true), .full)
        XCTAssertEqual(doors("trtc:O_XINZHUANG", "迴龍", underground: true), .full)
        XCTAssertEqual(doors("trtc:O_XINZHUANG", "頂溪", underground: true), .gate(1.45))
        // The Bannan line: only its two newest ends.
        XCTAssertEqual(doors("trtc:BL", "頂埔", underground: true), .full)
        XCTAssertEqual(doors("trtc:BL", "南港展覽館", underground: true), .full)
        XCTAssertEqual(doors("trtc:BL", "板橋", underground: true), .gate(1.45))
        // A station the player renamed: the line's gates.
        XCTAssertEqual(doors("trtc:BL", "我的車站", underground: true), .gate(1.45))
    }

    func testTheMTRsUndergroundStationsHaveScreenDoorsAndItsOthersByLine() {
        XCTAssertEqual(doors("hkmtr:TWL", "中環", underground: true), .full)
        XCTAssertEqual(doors("hkmtr:TWL", "荃灣"), .gate(1.55))
        XCTAssertEqual(doors("hkmtr:KTL", "觀塘"), .gate(1.55))
        XCTAssertEqual(doors("hkmtr:ISL", "柴灣"), .gate(1.55))
        // The Airport Express and Tung Chung Line had them from the start,
        // but Sunny Bay.
        XCTAssertEqual(doors("hkmtr:AEL", "機場"), .full)
        XCTAssertEqual(doors("hkmtr:TCL", "青衣"), .full)
        XCTAssertEqual(doors("hkmtr:TCL", "欣澳"), .gate(1.55))
        XCTAssertEqual(doors("hkmtr:TKL_LHP", "康城"), .full)
        // The old West Rail's, not the old Ma On Shan Line's.
        XCTAssertEqual(doors("hkmtr:TML", "元朗"), .full)
        XCTAssertEqual(doors("hkmtr:TML", "大圍"), .gate(1.7))
        XCTAssertEqual(doors("hkmtr:EAL", "紅磡"), .full)
        XCTAssertEqual(doors("hkmtr:EAL", "沙田"), .gate(1.8))
        XCTAssertEqual(doors("hkmtr:EAL", "會展", underground: true), .full)
        XCTAssertEqual(doors("hkmtr:EAL_LMC", "落馬洲"), .gate(1.8))
        XCTAssertEqual(doors("hkmtr:SIL", "海洋公園"), .gate(1.7))
        XCTAssertEqual(doors("hkmtr:DRL", "迪士尼"), .gate(1.2))
    }

    func testTheOtherMetrosAsTheyAreAndNoneOnARailwayOrALightRail() {
        XCTAssertEqual(doors("krtc:KR", "美麗島", underground: true), .full)
        XCTAssertNil(doors("krtc:KR", "岡山車站"), "Kaohsiung's raised stations have none")
        XCTAssertEqual(doors("krtc:KO", "大寮"), Doors.otherGate)
        XCTAssertNil(doors("krtc:C", "夢時代"), "nor its light rail")
        XCTAssertEqual(doors("tymc:A", "機場第一航廈站", underground: true), .full)
        XCTAssertEqual(doors("tymc:A", "林口站"), Doors.otherGate)
        XCTAssertEqual(doors("tmrt:TG", "市政府"), Doors.otherGate)
        for line in ["tra:PINGXI", "thsr:HSR", "vr:KEMIJARVI", "ntdlrt:V", "ntalrt:K", "afr:AFR_MAIN", "trtc"] {
            XCTAssertNil(doors(line, "台北車站"), line)
            XCTAssertNil(doors(line, "台北車站", underground: true), line)
        }
    }

    // MARK: Along the platform

    func testThereIsAnOpeningAtEachOfTheTrainsDoorsBetweenFixedPanels() {
        let six = Map3DPlatformProps.Formation(cars: 6, carLength: 22, doors: 4)
        let pieces = Doors.pieces(length: 150, formations: [six])
        let openings = pieces.filter(\.door)
        let centres = Map3DPlatformProps.doorCentres(length: 150, formations: [six], kind: .metro)
        XCTAssertEqual(openings.count, 24)
        for (opening, centre) in zip(openings, centres) {
            XCTAssertEqual((opening.from + opening.to) / 2, centre, accuracy: 0.001)
            XCTAssertEqual(opening.to - opening.from, Doors.opening, accuracy: 0.001)
        }
        // One run, piece after piece, a panel between each two openings,
        // the train's length and half a metre each end.
        for (a, b) in zip(pieces, pieces.dropFirst()) {
            XCTAssertEqual(a.to, b.from, accuracy: 0.001)
            XCTAssertFalse(a.door && b.door)
        }
        XCTAssertEqual(pieces.first?.from ?? 0, 9 - 0.5, accuracy: 0.001)
        XCTAssertEqual(pieces.last?.to ?? 0, 141 + 0.5, accuracy: 0.001)
        // No train fits: none.
        XCTAssertTrue(Doors.pieces(length: 60, formations: [six]).isEmpty)
    }

    // MARK: Laid in the scene

    /// A builder of `world` with one platform 150 m along x beside the
    /// track at z 0, on `edge` at `station`.
    private func builder(world: GameWorld, station: StationID, edge: TrackEdgeID?) -> Builder {
        var builder = Builder(originX: 0, originY: 0, region: WorldRegion(minX: -64_000, minY: -64_000, maxX: 64_000, maxY: 64_000),
                              world: world)
        let line = stride(from: Float(-75), through: 75, by: 15).map { Map3DPoint($0, Map3DScene.railLift, 0) }
        builder.laidPlatforms = [Builder.LaidPlatform(station: station, line: line, offset: 1.6 + 2, width: 4, structure: .elevated,
                                                      edge: edge)]
        return builder
    }

    @MainActor
    func testTheWenhuLinesPlatformHasScreenDoorsOnlyTheirGlassLitAfterDark() throws {
        let world = try DepotReturnReportTests.bought("trtc:BR")
        let plan = Doors.Plan(world: world)
        let platform = try XCTUnwrap(world.railwaySnapshot().platforms.first { !world.station(id: $0.platform.station)!.isDepot })
        XCTAssertEqual(plan.doors(edge: platform.platform.edge, station: platform.platform.station, underground: false), .full)
        XCTAssertFalse(plan.trains(edge: platform.platform.edge, station: platform.platform.station).isEmpty, "the line's own trains")

        var with = builder(world: world, station: platform.platform.station, edge: platform.platform.edge)
        with.addPlatformProps()
        let all = with.closeMeshes.values.flatMap(\.vertices)
        let top = Map3DScene.railLift + Builder.platformHeight
        let glass = all.filter { $0.color == StationKitBuilder.glass }
        XCTAssertFalse(glass.isEmpty)
        XCTAssertTrue(glass.allSatisfy { $0.layer == Map3DVertex.nightLit }, "the glass shows the lit platform after dark")
        XCTAssertTrue(glass.allSatisfy { $0.y >= top - 0.001 && $0.y <= top + 2.25 + 0.001 })
        // Between the edge (1.6 m) and the queue lines.
        XCTAssertTrue(glass.allSatisfy { abs($0.z - (1.6 + Doors.setBack)) < 0.01 })
        // The frames and the header are not lit.
        let frames = all.filter { $0.color == Map3DColor.shaded(StationKitBuilder.steel, 0.92) || $0.color == Map3DPalette.canopy }
        XCTAssertFalse(frames.isEmpty)
        XCTAssertTrue(frames.allSatisfy { $0.layer != Map3DVertex.nightLit && !$0.glows })
        // Close up only.
        for meshes in [with.meshes, with.nearMeshes, with.farMeshes, with.standInMeshes] {
            XCTAssertFalse(meshes.values.flatMap(\.vertices).contains { $0.color == StationKitBuilder.glass })
        }
        // What they cost: about 36 triangles a door, close up only.
        let pieces = Doors.pieces(length: 150, formations: plan.trains(edge: platform.platform.edge, station: platform.platform.station))
        let openings = pieces.filter(\.door).count
        XCTAssertGreaterThan(openings, 0)
        var alone = Map3DMesh()
        let path = try XCTUnwrap(Map3DStreetLife.Path(with.laidPlatforms[0].line))
        Builder.addScreenDoors(&alone, path: path, across: 1.6 + Doors.setBack, top: top, pieces: pieces, doors: .full)
        XCTAssertLessThanOrEqual(alone.triangleCount, openings * 36 + 8, "\(alone.triangleCount) triangles for \(openings) doors")
        print("SCREEN-DOORS: Wenhu line platform, \(openings) doors, \(alone.triangleCount) triangles")
        // A player's own line: none.
        var own = builder(world: GameWorld.newGame(), station: platform.platform.station, edge: platform.platform.edge)
        own.addPlatformProps()
        XCTAssertFalse(own.closeMeshes.values.flatMap(\.vertices).contains { $0.color == StationKitBuilder.glass })
    }

    func testAnUndergroundPlatformSeenThroughTheGroundShowsItsDoors() {
        let line = stride(from: Float(0), through: 100, by: 20).map { Map3DPoint($0, -12, 0) }
        var plain = Map3DMesh(), doored = Map3DMesh()
        Map3DXRay.addPlatform(Map3DXRay.Platform(station: StationID(rawValue: 1), line: line, offset: -3.6, width: 4), to: &plain)
        Map3DXRay.addPlatform(Map3DXRay.Platform(station: StationID(rawValue: 1), line: line, offset: -3.6, width: 4, doors: .full), to: &doored)
        XCTAssertFalse(plain.vertices.contains { $0.color == Map3DXRay.seen(StationKitBuilder.glass, Map3DXRay.doorOpacity) })
        let glass = doored.vertices.filter { $0.color == Map3DXRay.seen(StationKitBuilder.glass, Map3DXRay.doorOpacity) }
        XCTAssertFalse(glass.isEmpty)
        // On the edge by the track (to the line's left, 1.6 m out), the
        // whole platform long.
        XCTAssertTrue(glass.allSatisfy { abs(abs($0.z) - (1.6 + Doors.setBack)) < 0.01 })
        XCTAssertEqual(glass.map(\.x).max() ?? 0, 100, accuracy: 0.01)
        XCTAssertEqual(doored.triangleCount - plain.triangleCount, 5 * 4)
    }

    // MARK: Preview

    /// `SCREEN_DOORS_PREVIEW=<file.json>`: the meshes of the decision's
    /// preview (`tools/screen-doors/preview.py` draws them): three
    /// platforms side by side, each with a train standing at it.
    func testWriteThePreviewsMeshes() throws {
        guard let out = ProcessInfo.processInfo.environment["SCREEN_DOORS_PREVIEW"] else {
            throw XCTSkip("SCREEN_DOORS_PREVIEW=<file.json> writes the preview's meshes")
        }
        typealias Formation = Map3DPlatformProps.Formation
        let taipei = Formation(cars: 6, carLength: 23.5, doors: 4), mtr = Formation(cars: 8, carLength: 22.5, doors: 5)
        let cases: [(name: String, doors: Doors.Doors, train: Formation, colour: UInt32)] = [
            ("full", .full, taipei, Map3DColor.rgb(0xD8262E)),
            ("taipei-gate", Doors.taipeiGate, taipei, Map3DColor.rgb(0x1E64B4)),
            ("mtr-gate", .gate(1.55), mtr, Map3DColor.rgb(0x00AB4E)),
        ]
        var scenes: [[String: Any]] = []
        for item in cases {
            var mesh = Map3DMesh()
            let length = item.train.length + 10
            let line = stride(from: Float(0), through: length, by: 5).map { Map3DPoint($0, 0, 0) }
            let path = try XCTUnwrap(Map3DStreetLife.Path(line))
            let top = Builder.platformHeight, width: Float = 4, edge: Float = 1.6
            // The ballast and the platform, its yellow line.
            mesh.addRibbon(along: line, width: 3.4, top: Map3DPalette.ballast)
            for rail: Float in [-0.75, 0.75] { mesh.addRibbon(along: line, width: 0.12, offset: rail, lift: 0.17, top: Map3DPalette.rail) }
            mesh.addRibbon(along: line, width: width, offset: edge + width / 2, lift: top, depth: top, top: Map3DPalette.platform,
                           side: Map3DPalette.platform)
            mesh.addRibbon(along: line, width: 0.3, offset: edge + 0.35, lift: top + 0.01, top: Map3DPalette.platformEdge)
            let pieces = Doors.pieces(length: length, formations: [item.train])
            Builder.addScreenDoors(&mesh, path: path, across: edge + Doors.setBack, top: top, pieces: pieces, doors: item.doors)
            for centre in Map3DPlatformProps.doorCentres(length: length, formations: [item.train], kind: .metro) {
                let at = path.at(centre)
                Builder.addQueueLines(&mesh, edge: at.point + at.right * edge + Map3DPoint(0, top + 0.012, 0), along: at.along,
                                      inward: at.right, depth: width)
            }
            // The train: a box a car, its doors dark on the platform side.
            let start = (length - item.train.length) / 2
            for car in 0..<item.train.cars {
                let middle = start + item.train.carLength * (Float(car) + 0.5)
                mesh.addBox(base: Map3DPoint(middle, 0.4, 0), forward: Map3DPoint(1, 0, 0), length: item.train.carLength - 0.8, width: 2.9,
                            height: 3.3, top: Map3DPalette.sidewalk, side: item.colour)
            }
            for centre in Map3DPlatformProps.doorCentres(length: length, formations: [item.train], kind: .metro) {
                mesh.addQuad(Map3DPoint(centre - 0.65, 0.9, 1.46), Map3DPoint(centre + 0.65, 0.9, 1.46), Map3DPoint(centre + 0.65, 2.8, 1.46),
                             Map3DPoint(centre - 0.65, 2.8, 1.46), color: Map3DPalette.playerRim)
            }
            scenes.append([
                "name": item.name, "length": length, "height": item.doors.height, "full": item.doors.full,
                "positions": mesh.vertices.flatMap { [$0.x, $0.y, $0.z] },
                "colours": mesh.vertices.map { Int($0.color & 0xFF_FFFF) },
                "lit": mesh.vertices.map { $0.layer == Map3DVertex.nightLit || $0.glows },
                "indices": mesh.indices.map { Int($0) },
            ])
        }
        let data = try JSONSerialization.data(withJSONObject: ["scenes": scenes])
        try data.write(to: URL(fileURLWithPath: out))
    }
}
