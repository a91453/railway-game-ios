import GameCore
import XCTest

/// Costs used across tests so expected balances are easy to read.
let testCosts = ConstructionCosts(track: 100, station: 1_000, train: 5_000)

/// A world `width` × `height` world units (320 m a side by default).
func makeWorld(
    width: Int64 = 20_480,
    height: Int64 = 20_480,
    balance: Money = 10_000
) throws -> GameWorld {
    GameWorld(bounds: try WorldBounds(width: width, height: height), economy: GameEconomy(balance: balance, costs: testCosts))
}

/// Asserts that `expression` throws exactly `expected`.
func XCTAssertThrowsGameError<T>(
    _ expression: @autoclosure () throws -> T,
    _ expected: GameError,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertThrowsError(try expression(), file: file, line: line) { error in
        XCTAssertEqual(error as? GameError, expected, file: file, line: line)
    }
}

/// Stage W2c: how far along a service's run a train is `elapsed` seconds
/// after it set off: the running curve its performance builds for
/// `length` units in `seconds` (W1's `RunningCurve`, checked against the
/// reference's JavaScript in `RunningCurveTests`), all of it from the end
/// of the run. Tests work arrival times out by hand; where a train is in
/// between follows the curve, and this reads it off.
func runDistance(_ length: Int64, in seconds: Int64, after elapsed: Int64, performance: TrainPerformance = .standard) -> Int64 {
    guard elapsed > 0 else { return 0 }
    guard elapsed < seconds else { return length }
    return RunningCurve(length: length, duration: seconds * 1000, performance: performance)!.distance(at: elapsed * 1000)
}

/// Decision 499: what a save written before version 76 reads as, in the
/// form ``SavedGame`` writes (pretty-printed, sorted keys): each amount of
/// money times 3, and the real high-speed fares (kept at NT$10 to the
/// dollar) times 10. The keys are every amount the saves in `SaveFixtures/`
/// hold, by the object they are in (an array's objects by the array's name
/// and `[]`), found by reading each fixture at both scales, with the other
/// amounts of the same objects' coding keys; any other number is left as it
/// is, so a test comparing bytes still checks it.
func newTaiwanDollars(ofSaveText text: String) -> String {
    let times: [String: Int64] = [
        "accounts/dayPass": 3, "accounts/fareBaseline": 3, "accounts/loan": 3, "acquisitions[]/value": 3,
        "active[]/reward": 3, "offers[]/reward": 3, "assets[]/cost": 3, "assets[]/depreciation": 3,
        "books/totalCost": 3, "books/totalSales": 3, "breakdown[]/amount": 3,
        "capitalDays[]/capitalSpending": 3, "capitalDays[]/depreciation": 3, "capitalDays[]/saleBookValue": 3,
        "capitalDays[]/saleProceeds": 3, "capitalDays[]/writeOff": 3, "capitalDays[]/borrowed": 3, "capitalDays[]/repaid": 3,
        "cityRequests/owed": 3, "cityRequests/paid": 3, "closed[]/cost": 3, "closed[]/sales": 3,
        "costs/car": 3, "costs/station": 3, "costs/track": 3, "costs/train": 3,
        "days[]/cost": 3, "days[]/energyCost": 3, "days[]/fareRevenue": 3, "days[]/fares": 3, "days[]/freightRevenue": 3,
        "days[]/maintenanceCost": 3, "days[]/operatingCost": 3, "days[]/propertyCost": 3, "days[]/propertyRevenue": 3,
        "days[]/staffCost": 3, "days[]/interestCost": 3, "days[]/taxCost": 3, "economy/balance": 3,
        "income/fareRevenue": 3, "income/operatingCost": 3, "income/maintenanceCost": 3, "income/energyCost": 3,
        "income/staffCost": 3, "income/interestCost": 3, "income/depreciationCost": 3, "income/writeOffCost": 3,
        "income/capitalSpending": 3, "income/loanBorrowed": 3, "income/loanRepaid": 3, "income/propertyRevenue": 3,
        "income/propertyCost": 3, "income/saleProceeds": 3, "income/saleBookValue": 3, "income/taxCost": 3,
        "income/freightRevenue": 3, "closing/cash": 3, "closing/loan": 3,
        "track/cost": 3, "track/depreciation": 3, "stations/cost": 3, "stations/depreciation": 3,
        "rollingStock/cost": 3, "rollingStock/depreciation": 3, "buildings/cost": 3, "buildings/depreciation": 3,
        "land/cost": 3, "land/depreciation": 3, "entries[]/amount": 3, "highSpeedFares[]/fare": 10,
        "pending/fareRevenue": 3, "placedBuildings[]/buildingCost": 3, "placedBuildings[]/landCost": 3,
        "request/reward": 3, "tally/energyCost": 3, "tally/fareRevenue": 3, "tally/maintenanceCost": 3,
        "tally/operatingCost": 3, "tally/staffCost": 3, "thisMonth/cost": 3, "thisMonth/sales": 3, "tripLog[]/fare": 3,
    ]
    var parents: [String] = []
    var lines: [String] = []
    for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
        var line = String(line)
        let trimmed = line.drop { $0 == " " }
        var key: String?
        if trimmed.hasPrefix("\""), let end = trimmed.dropFirst().firstIndex(of: "\"") {
            key = String(trimmed[trimmed.index(after: trimmed.startIndex)..<end])
        }
        let rest = key.map { _ in trimmed[trimmed.index(after: trimmed.dropFirst().firstIndex(of: "\"")!)...].drop { $0 == " " || $0 == ":" } } ?? trimmed[...]
        if rest.hasPrefix("{") && !rest.hasPrefix("{}") {
            parents.append(key ?? "")
        } else if rest.hasPrefix("[") && !rest.hasPrefix("[]") {
            parents.append((key ?? "") + "[]")
        } else if rest.hasPrefix("}") || rest.hasPrefix("]") {
            parents.removeLast()
        } else if let key, let parent = parents.last(where: { !$0.isEmpty }), let factor = times[parent + "/" + key] {
            let digits = rest.prefix { $0 == "-" || $0.isNumber }
            if let value = Int64(digits) {
                let indent = line.prefix { $0 == " " }
                line = "\(indent)\"\(key)\" : \(value * factor)" + rest.dropFirst(digits.count)
            }
        }
        lines.append(line)
    }
    return lines.joined(separator: "\n")
}

extension ConstructionCosts {
    /// These prices times `scale`: 3 is what a save written before version
    /// 76 reads them as (decision 499).
    func times(_ scale: Int64) -> ConstructionCosts {
        ConstructionCosts(track: Money(track.amount * scale), station: Money(station.amount * scale), train: Money(train.amount * scale), car: Money(car.amount * scale))
    }
}
