import Foundation
import GameCore

// A one-shot executable, not a persistent game bridge or a renderer.
@main
struct RailwayWasmProbe {
    struct Failure: Error { let message: String }
    struct Report: Encodable {
        let protocolVersion: Int
        let intBits: Int
        let intMax: String
        let checks: [String]
        let goldenScenarios: [String]
        let largeBalance: String
    }

    static func require(_ condition: Bool, _ message: String) throws {
        guard condition else { throw Failure(message: message) }
    }

    static func main() throws {
        var checks: [String] = []
        var world = try GameWorld(
            width: 32, height: 32,
            economy: GameEconomy(balance: Money(9_007_199_254_740_993), costs: ConstructionCosts(track: 100, station: 1_000, train: 500)),
            clock: GameClock(speed: .normal)
        )
        let before = world
        do {
            _ = try world.purchaseTrain(named: " ")
            throw Failure(message: "invalid name accepted")
        } catch let error as GameError {
            try require(error == .invalidName && world == before, "rejected command mutated world")
        }
        checks.append("failure-atomicity")

        let start = try world.buildTrackNode(at: WorldCoordinate(x: 0, y: 0))
        let end = try world.buildTrackNode(at: WorldCoordinate(x: 16_384, y: 0, z: 512))
        let edge = try world.buildTrackEdge(
            from: start, to: end,
            profile: TrackProfile(startTransition: 2_048, endTransition: 2_048), structure: .elevated
        )
        guard let geometry = world.trackGeometry(of: edge) else { throw Failure(message: "missing geometry") }
        try require([0, 1_024, 2_048, 8_192, 15_360, 16_384].map(geometry.height(at:)) == [0, 9, 37, 256, 503, 512], "S4 vertical geometry changed")
        let train = try world.purchaseTrain(named: "Wasm probe")
        try world.placeTrain(train.id, at: .onEdge(TrackTraversal(edge: edge, direction: .forward), offset: 0))
        try world.setTrainMovementRate(train.id, to: 1_024)
        try world.advance(ticks: 8)
        let snapshot = world.railwaySnapshot()
        try require(world.clock.now.minutes == 8 && snapshot.edges.count == 1 && snapshot.trains.count == 1, "tick or snapshot changed")
        try require(snapshot.trains[0].head.position == WorldCoordinate(x: 8_192, y: 0, z: 256), "train position changed")
        checks.append("ticks-and-s4-snapshot")

        let product = UInt64.max.multipliedFullWidth(by: 2)
        let division = UInt64(2).dividingFullWidth(product)
        try require(division.quotient == UInt64.max && division.remainder == 0, "full-width arithmetic changed")
        try require(Int64.max.addingReportingOverflow(1).overflow, "overflow check changed")
        checks.append("full-width-and-overflow")

        let bytes = try JSONEncoder().encode(world)
        let restored = try JSONDecoder().decode(GameWorld.self, from: bytes)
        try require(restored == world, "Codable save round trip changed")
        // The browser receives this value as a string, never an imprecise JS Number.
        let largeBalance = String(restored.economy.balance.amount)
        try require(largeBalance == "9007199254735693", "large integer lost precision")
        checks.append("codable-large-integer")

        var clock = GameClock(now: GameTime(minutes: Int64.max), speed: .normal)
        let oldClock = clock
        do {
            try clock.advance(ticks: 1)
            throw Failure(message: "clock overflow accepted")
        } catch let error as GameError {
            try require(error == .clockOverflow && clock == oldClock, "clock overflow changed state")
        }
        checks.append("clock-overflow-atomicity")

        var passed: [String] = []
        for (name, json) in embeddedFixtures {
            let scenario = try GoldenScenario.decode(Data(json.utf8))
            let differences = scenario.differences()
            try require(differences.isEmpty, "\(name): \(differences.joined(separator: "; "))")
            passed.append(name)
        }
        // Prove the reused oracle can detect a wrong expected value.
        var mutation = try GoldenScenario.decode(Data(embeddedFixtures[0].1.utf8))
        mutation.expectedFinalState.balance += 1
        try require(!mutation.differences().isEmpty, "golden oracle cannot fail")
        checks.append("golden-oracle-mutation")

        let report = Report(protocolVersion: 1, intBits: Int.bitWidth, intMax: String(Int.max), checks: checks, goldenScenarios: passed, largeBalance: largeBalance)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        print(String(decoding: try encoder.encode(report), as: UTF8.self))
    }
}
