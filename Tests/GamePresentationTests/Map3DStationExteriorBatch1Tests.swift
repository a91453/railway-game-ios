import XCTest
@testable import GamePresentation

final class Map3DStationExteriorBatch1Tests: XCTestCase {
    func testHsinchuHSRStudyUsesTwoOSMWaysAndSeparateRoofs() {
        let near = Map3DStationExteriorBatch1.model(for: .hsinchuHSR, detail: .near)
        let far = Map3DStationExteriorBatch1.model(for: .hsinchuHSR, detail: .far)
        XCTAssertGreaterThan(near.triangleCount, far.triangleCount)
        XCTAssertLessThanOrEqual(near.triangleCount, 6_000)
        XCTAssertLessThanOrEqual(far.triangleCount, 2_500)
        XCTAssertNil(Map3DStationKit.model(id: near.name))
        XCTAssertNil(Map3DStationKit.model(id: far.name))
        XCTAssertEqual(near.maximum.z, 28.08, accuracy: 0.01) // estimated roof plus seam
        XCTAssertTrue(near.vertices.contains { abs($0.z - 13) < 0.001 }) // Liujia flat roof
        let outlines = [Map3DStationExteriorBatch1.hsinchuHSRFootprint,
                        Map3DStationExteriorBatch1.liujiaFootprint]
        XCTAssertEqual(outlines.map(\.count), [23, 11])
        for outline in outlines {
            for (east, north) in outline {
                XCTAssertTrue(near.vertices.contains {
                    abs($0.x - east) < 0.002 && abs($0.y + north) < 0.002
                        && abs($0.z - 0.32) < 0.002
                })
            }
        }
        let colours = Set(near.vertices.map(\.color))
        let ordered = [UInt32(0xE9ECE8), 0xD9E1DF, 0xCDD2CE,
                       0xAABAB9, 0x8EAEB2, 0x66878B, 0x657577].map(Map3DColor.rgb)
        func luminance(_ colour: UInt32) -> Float {
            Float(colour & 255) * 0.2126 + Float((colour >> 8) & 255) * 0.7152
                + Float((colour >> 16) & 255) * 0.0722
        }
        for (lighter, darker) in zip(ordered, ordered.dropFirst()) {
            XCTAssertTrue(colours.contains(lighter))
            XCTAssertGreaterThan(luminance(lighter), luminance(darker))
        }
        XCTAssertTrue(colours.contains(ordered.last!))
    }

    func testTaoyuanHSRStudyKeepsHSRAndA18FootprintsSeparate() {
        let near = Map3DStationExteriorBatch1.model(for: .taoyuanHSR, detail: .near)
        let far = Map3DStationExteriorBatch1.model(for: .taoyuanHSR, detail: .far)
        XCTAssertGreaterThan(near.triangleCount, far.triangleCount)
        XCTAssertLessThanOrEqual(near.triangleCount, 6_000)
        XCTAssertLessThanOrEqual(far.triangleCount, 2_500)
        XCTAssertNil(Map3DStationKit.model(id: near.name))
        XCTAssertNil(Map3DStationKit.model(id: far.name))
        let outlines: [([(Float, Float)], Float)] = [
            (Map3DStationExteriorBatch1.taoyuanHSRFootprint, 0.32),
            (Map3DStationExteriorBatch1.taoyuanA18Footprint, 8.32)
        ]
        XCTAssertEqual(outlines[0].0.count, 26)
        XCTAssertEqual(outlines[1].0.count, 18)
        for (outline, top) in outlines {
            for (east, north) in outline {
                XCTAssertTrue(near.vertices.contains {
                    abs($0.x - east) < 0.002 && abs($0.y + north) < 0.002
                        && abs($0.z - top) < 0.002
                })
            }
        }
        XCTAssertEqual(near.maximum.z, 30, accuracy: 0.01)
        let colours = Set(near.vertices.map(\.color))
        let ordered = [UInt32(0xE6E9E6), 0xCBD6D3, 0xB6CACB,
                       0x8EABB0, 0xB98E8E, 0x607F86].map(Map3DColor.rgb)
        func luminance(_ colour: UInt32) -> Float {
            Float(colour & 255) * 0.2126 + Float((colour >> 8) & 255) * 0.7152
                + Float((colour >> 16) & 255) * 0.0722
        }
        for (lighter, darker) in zip(ordered, ordered.dropFirst()) {
            XCTAssertTrue(colours.contains(lighter))
            XCTAssertGreaterThan(luminance(lighter), luminance(darker))
        }
        XCTAssertTrue(colours.contains(ordered.last!))
    }

    func testNangangStudyUsesFiveOSMWaysAndTaggedTowerHeights() {
        let near = Map3DStationExteriorBatch1.model(for: .nangangTRA, detail: .near)
        let far = Map3DStationExteriorBatch1.model(for: .nangangTRA, detail: .far)
        XCTAssertGreaterThan(near.triangleCount, far.triangleCount)
        XCTAssertLessThanOrEqual(near.triangleCount, 6_000)
        XCTAssertLessThanOrEqual(far.triangleCount, 2_500)
        XCTAssertNil(Map3DStationKit.model(id: near.name))
        XCTAssertNil(Map3DStationKit.model(id: far.name))
        XCTAssertEqual(near.maximum.z, 139, accuracy: 0.01)
        XCTAssertTrue(near.vertices.contains { abs($0.z - 70) < 0.01 })
        let outlines: [([(Float, Float)], Float)] = [
            (Map3DStationExteriorBatch1.nangangMainFootprint, 0.32),
            (Map3DStationExteriorBatch1.nangangBlockAFootprint, 28.32),
            (Map3DStationExteriorBatch1.nangangBlockBFootprint, 28.32),
            (Map3DStationExteriorBatch1.nangangBlockCFootprint, 0.32),
            (Map3DStationExteriorBatch1.nangangEastFootprint, 0.32)
        ]
        for (outline, top) in outlines {
            for (east, north) in outline {
                XCTAssertTrue(near.vertices.contains {
                    abs($0.x - east) < 0.002 && abs($0.y + north) < 0.002
                        && abs($0.z - top) < 0.002
                })
            }
        }
        let colours = Set(near.vertices.map(\.color))
        let ordered = [UInt32(0xE8E9E2), 0xD8E1DE, 0xB7C6C4,
                       0xBE9F91, 0x607D84].map(Map3DColor.rgb)
        func luminance(_ colour: UInt32) -> Float {
            Float(colour & 255) * 0.2126 + Float((colour >> 8) & 255) * 0.7152
                + Float((colour >> 16) & 255) * 0.0722
        }
        for (lighter, darker) in zip(ordered, ordered.dropFirst()) {
            XCTAssertTrue(colours.contains(lighter))
            XCTAssertGreaterThan(luminance(lighter), luminance(darker))
        }
        XCTAssertTrue(colours.contains(ordered.last!))
    }

    func testBanqiaoStudyPreservesFourOSMWaysAndTaggedTowerHeight() {
        let near = Map3DStationExteriorBatch1.model(for: .banqiaoTRA, detail: .near)
        let far = Map3DStationExteriorBatch1.model(for: .banqiaoTRA, detail: .far)
        XCTAssertGreaterThan(near.triangleCount, far.triangleCount)
        XCTAssertLessThanOrEqual(near.triangleCount, 6_000)
        XCTAssertLessThanOrEqual(far.triangleCount, 2_500)
        XCTAssertNil(Map3DStationKit.model(id: near.name))
        XCTAssertNil(Map3DStationKit.model(id: far.name))
        XCTAssertEqual(near.maximum.z, 116.8, accuracy: 0.01)
        let outlines: [([(Float, Float)], Float)] = [
            (Map3DStationExteriorBatch1.banqiaoMainFootprint, 0.32),
            (Map3DStationExteriorBatch1.banqiaoTowerSouthFootprint, 20.32),
            (Map3DStationExteriorBatch1.banqiaoTowerNorthFootprint, 20.32),
            (Map3DStationExteriorBatch1.banqiaoCircularLineFootprint, 7.32)
        ]
        for (outline, top) in outlines {
            for (east, north) in outline {
                XCTAssertTrue(near.vertices.contains {
                    abs($0.x - east) < 0.002 && abs($0.y + north) < 0.002
                        && abs($0.z - top) < 0.002
                })
            }
        }
        let colours = Set(near.vertices.map(\.color))
        let ordered = [UInt32(0xEEE5DA), 0xDDCEC2, 0xBEC7C6, 0xCDBEB5,
                       0x728C94, 0x688189, 0x5B6970].map(Map3DColor.rgb)
        func luminance(_ colour: UInt32) -> Float {
            Float(colour & 255) * 0.2126 + Float((colour >> 8) & 255) * 0.7152
                + Float((colour >> 16) & 255) * 0.0722
        }
        for (lighter, darker) in zip(ordered, ordered.dropFirst()) {
            XCTAssertTrue(colours.contains(lighter))
            XCTAssertGreaterThan(luminance(lighter), luminance(darker))
        }
        XCTAssertTrue(colours.contains(ordered.last!))
    }

    func testTaitungStudyPreservesFiveOSMWaysAndTwoDetailBudgets() {
        let near = Map3DStationExteriorBatch1.model(for: .taitungTRA, detail: .near)
        let far = Map3DStationExteriorBatch1.model(for: .taitungTRA, detail: .far)
        XCTAssertGreaterThan(near.triangleCount, far.triangleCount)
        XCTAssertLessThanOrEqual(near.triangleCount, 6_000)
        XCTAssertLessThanOrEqual(far.triangleCount, 2_500)
        XCTAssertNil(Map3DStationKit.model(id: near.name))
        XCTAssertNil(Map3DStationKit.model(id: far.name))
        let outlines: [([(Float, Float)], Float)] = [
            (Map3DStationExteriorBatch1.taitungHallFootprint, 0.32),
            (Map3DStationExteriorBatch1.taitungPorticoFootprint, 5.92),
            (Map3DStationExteriorBatch1.taitungPlatformAFootprint, 5.62),
            (Map3DStationExteriorBatch1.taitungPlatformBFootprint, 5.62),
            (Map3DStationExteriorBatch1.taitungPlatformCFootprint, 5.62)
        ]
        for (outline, top) in outlines {
            for (east, north) in outline {
                XCTAssertTrue(near.vertices.contains {
                    abs($0.x - east) < 0.002 && abs($0.y + north) < 0.002
                        && abs($0.z - top) < 0.002
                })
            }
        }
        let colours = Set(near.vertices.map(\.color))
        for colour in [UInt32(0xDCE8E6), 0xD9D0CC, 0xC6D2CF, 0xADBDBD,
                       0x8CACB1, 0x768E90, 0xBA9F92] {
            XCTAssertTrue(colours.contains(Map3DColor.rgb(colour)))
        }
        func luminance(_ colour: UInt32) -> Float {
            Float(colour & 255) * 0.2126 + Float((colour >> 8) & 255) * 0.7152
                + Float((colour >> 16) & 255) * 0.0722
        }
        let order = [0xDCE8E6, 0xD9D0CC, 0xC6D2CF, 0xADBDBD, 0x8CACB1, 0xBA9F92, 0x768E90]
            .map(Map3DColor.rgb)
        for (lighter, darker) in zip(order, order.dropFirst()) {
            XCTAssertGreaterThan(luminance(lighter), luminance(darker))
        }
    }

    func testHualienStudyUsesEightOSMWaysAndKeepsThemOutOfOperationalCatalog() {
        let near = Map3DStationExteriorBatch1.model(for: .hualienTRA, detail: .near)
        let far = Map3DStationExteriorBatch1.model(for: .hualienTRA, detail: .far)
        XCTAssertGreaterThan(near.triangleCount, far.triangleCount)
        XCTAssertLessThanOrEqual(near.triangleCount, 6_000)
        XCTAssertLessThanOrEqual(far.triangleCount, 2_500)
        XCTAssertNil(Map3DStationKit.model(id: near.name))
        XCTAssertNil(Map3DStationKit.model(id: far.name))
        let ground: [[(Float, Float)]] = [
            Map3DStationExteriorBatch1.crossHallFootprint,
            Map3DStationExteriorBatch1.ticketHallFootprint,
            Map3DStationExteriorBatch1.welcomeUmbrellaFootprint,
            Map3DStationExteriorBatch1.frontHallFootprint,
            Map3DStationExteriorBatch1.rearHallFootprint
        ]
        let canopies: [[(Float, Float)]] = [
            Map3DStationExteriorBatch1.platformNorthFootprint,
            Map3DStationExteriorBatch1.platformMiddleFootprint,
            Map3DStationExteriorBatch1.platformSouthFootprint
        ]
        for (outlines, height) in [(ground, Float(0.32)), (canopies, Float(5.96))] {
            for outline in outlines {
                for (east, north) in outline {
                    XCTAssertTrue(near.vertices.contains {
                        abs($0.x - east) < 0.002 && abs($0.y + north) < 0.002 && abs($0.z - height) < 0.002
                    })
                }
            }
        }
        let colours = Set(near.vertices.map(\.color))
        for colour in [UInt32(0xE8E6DE), 0xDDD8CB, 0xC1B19A, 0xB9B9B3, 0x9BB7B9, 0x858B89] {
            XCTAssertTrue(colours.contains(Map3DColor.rgb(colour)))
        }
        func brightness(_ colour: UInt32) -> Float {
            Float(colour & 255) * 0.2126 + Float((colour >> 8) & 255) * 0.7152
                + Float((colour >> 16) & 255) * 0.0722
        }
        let ordered = [0xE8E6DE, 0xDDD8CB, 0xB9B9B3, 0xC1B19A, 0x9BB7B9, 0x858B89]
            .map(Map3DColor.rgb)
        for (lighter, darker) in zip(ordered, ordered.dropFirst()) {
            XCTAssertGreaterThan(brightness(lighter), brightness(darker))
        }
    }

    func testHsinchuStudyKeepsOSMWayAndHistoricRoofSeparateFromChineseRoofs() {
        let near = Map3DStationExteriorBatch1.model(for: .hsinchuTRA, detail: .near)
        let far = Map3DStationExteriorBatch1.model(for: .hsinchuTRA, detail: .far)
        XCTAssertGreaterThan(near.triangleCount, far.triangleCount)
        XCTAssertLessThanOrEqual(near.triangleCount, 6_000)
        XCTAssertLessThanOrEqual(far.triangleCount, 2_500)
        XCTAssertNil(Map3DStationKit.model(id: near.name))
        for (east, north) in Map3DStationExteriorBatch1.hsinchuFootprint {
            XCTAssertTrue(near.vertices.contains {
                abs($0.x - east) < 0.002 && abs($0.y + north) < 0.002 && abs($0.z - 0.32) < 0.002
            })
        }
        let angle: Float = 32.2 * .pi / 180
        let along = Map3DStationExteriorBatch1.hsinchuFootprint.map { $0.0 * cos(angle) + $0.1 * sin(angle) }
        let across = Map3DStationExteriorBatch1.hsinchuFootprint.map { -$0.0 * sin(angle) + $0.1 * cos(angle) }
        XCTAssertEqual((along.max() ?? 0) - (along.min() ?? 0), 143.68, accuracy: 0.1)
        XCTAssertEqual((across.max() ?? 0) - (across.min() ?? 0), 16.87, accuracy: 0.1)
        let colours = Set(near.vertices.map(\.color))
        XCTAssertTrue(colours.contains(Map3DColor.rgb(0x899780)))
        XCTAssertTrue(colours.contains(Map3DColor.rgb(0xC79C89)))
        XCTAssertTrue(colours.contains(Map3DColor.rgb(0xE5D8C3)))
        let ordered = [0xF1EADD, 0xE5D8C3, 0xC79C89, 0x899780].map(Map3DColor.rgb)
        func brightness(_ color: UInt32) -> Float {
            Float(color & 255) * 0.2126 + Float((color >> 8) & 255) * 0.7152
                + Float((color >> 16) & 255) * 0.0722
        }
        for (lighter, darker) in zip(ordered, ordered.dropFirst()) {
            XCTAssertTrue(colours.contains(lighter))
            XCTAssertGreaterThan(brightness(lighter), brightness(darker))
        }
    }

    func testTaichungStudyUsesSurveyedFootprintsAndStaysOutsideOperationalCatalog() {
        let near = Map3DStationExteriorBatch1.model(for: .taichungTRA, detail: .near)
        let far = Map3DStationExteriorBatch1.model(for: .taichungTRA, detail: .far)
        XCTAssertGreaterThan(near.triangleCount, far.triangleCount)
        XCTAssertLessThanOrEqual(near.triangleCount, 6_000)
        XCTAssertLessThanOrEqual(far.triangleCount, 2_500)
        XCTAssertNil(Map3DStationKit.model(id: near.name))
        XCTAssertNil(Map3DStationKit.model(id: far.name))

        // Every OSM way vertex appears on the exported plinth boundary.
        for (x, north) in Map3DStationExteriorBatch1.mainFootprint + Map3DStationExteriorBatch1.oldFootprint {
            XCTAssertTrue(near.vertices.contains { abs($0.x - x) < 0.002 && abs($0.y + north) < 0.002 && abs($0.z - 0.32) < 0.002 })
        }
        let colours = Set(near.vertices.map(\.color))
        XCTAssertTrue(colours.contains(Map3DColor.rgb(0xE5E7E2)))
        XCTAssertTrue(colours.contains(Map3DColor.rgb(0xC79C89)))
        XCTAssertTrue(colours.contains(Map3DColor.rgb(0x90979E)))
        func brightness(_ color: UInt32) -> Float {
            Float(color & 255) * 0.2126 + Float((color >> 8) & 255) * 0.7152
                + Float((color >> 16) & 255) * 0.0722
        }
        let ordered = [StationKitBuilder.white, Map3DColor.rgb(0xEEE7DA),
                       Map3DColor.rgb(0xE5E7E2), Map3DColor.rgb(0xC79C89),
                       Map3DColor.rgb(0x90979E)]
        for (lighter, darker) in zip(ordered, ordered.dropFirst()) {
            XCTAssertTrue(colours.contains(lighter))
            XCTAssertGreaterThan(brightness(lighter), brightness(darker))
        }
    }
}
