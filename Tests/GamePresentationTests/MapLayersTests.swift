import GameCore
import GamePresentation
import XCTest

final class MapLayersTests: XCTestCase {
    func testDefaultPreferencesHaveAllLayersEnabled() {
        let prefs = MapLayerPreferences.default
        XCTAssertTrue(prefs.showsStationNames)
        XCTAssertTrue(prefs.showsWaitingCounts)
        XCTAssertTrue(prefs.showsCatchmentRings)
    }

    func testPreferencesEqualityAndMutation() {
        var a = MapLayerPreferences()
        var b = MapLayerPreferences()
        XCTAssertEqual(a, b)

        a.showsCatchmentRings = false
        XCTAssertNotEqual(a, b)

        b.showsCatchmentRings = false
        XCTAssertEqual(a, b)

        a.showsStationNames = false
        XCTAssertNotEqual(a, b)

        a.showsWaitingCounts = false
        XCTAssertFalse(a.showsWaitingCounts)
    }

    func testCatchmentRadiusWorldUnitsConversion() {
        XCTAssertEqual(StationDemand.catchmentRadius, 800.0, "Station catchment radius must be exactly 800 metres (ten minutes walk)")
        XCTAssertEqual(WorldCoordinate.unitsPerMetre, 64, "1 metre must be exactly 64 world units")

        let expectedWorldUnits: Double = 800.0 * 64.0 // 51,200.0
        XCTAssertEqual(MapLayers.catchmentRadiusMetres, 800.0)
        XCTAssertEqual(MapLayers.catchmentRadiusWorldUnits, expectedWorldUnits)
        XCTAssertEqual(MapLayers.catchmentRadiusWorldUnits, 51_200.0)

        // Screen radius projection calculation: screenRadius = worldRadius * pointsPerUnit
        let pointsPerUnit: Double = 0.05
        let expectedScreenRadius = 51_200.0 * pointsPerUnit // 2560.0
        XCTAssertEqual(MapLayers.catchmentScreenRadius(pointsPerUnit: pointsPerUnit), expectedScreenRadius)
    }

    func testWaitingPassengerCountsDerivationAndSnapshotChanges() throws {
        var world = try makeWorld(width: 8_192, height: 4_096, balance: 1_000_000, speed: .normal)
        let line = TestLine(tiles: 7, row: 1)
        try line.build(in: &world)
        let alpha = try line.buildStation(named: "Alpha", beside: 1, at: 0, in: &world)
        let beta = try line.buildStation(named: "Beta", beside: 3, at: 0, in: &world)
        let gamma = try line.buildStation(named: "Gamma", beside: 5, at: 0, in: &world)

        let initialCounts = MapLayers.waitingPassengerCounts(in: world)
        XCTAssertEqual(initialCounts[alpha], 0)
        XCTAssertEqual(initialCounts[beta], 0)
        XCTAssertEqual(initialCounts[gamma], 0)

        let main = try world.createLine(named: "Main", stops: [alpha, beta, gamma]).id
        try world.setLineServiceWindow(main, to: .allDay)
        try world.setLineTrainsInService(main, to: TrainsInService(peak: 1, offPeak: 1, low: 1))
        let train = try world.purchaseTrain(named: "T1")
        try world.placeTrain(train.id, at: line.at(1, facingEast: true))
        try world.setTrainMovementRate(train.id, to: 1_024)
        try world.assignTrain(train.id, to: main)

        try world.setStationDemand(alpha, to: StationDemand(kind: .residential, dailyTrips: 200_000))
        try world.setStationDemand(gamma, to: StationDemand(kind: .office, dailyTrips: 1_000))
        try world.advance(ticks: 26)

        let updatedCounts = MapLayers.waitingPassengerCounts(in: world)
        let alphaWaiting = world.waitingPassengers(at: alpha).reduce(Int64(0)) { $0 + $1.count }
        XCTAssertGreaterThan(alphaWaiting, 0)
        XCTAssertEqual(updatedCounts[alpha], alphaWaiting)
        XCTAssertNotEqual(initialCounts, updatedCounts, "Waiting counts snapshot must change when passengers arrive")
    }
}
