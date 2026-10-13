import GameCore

// The distance fare's first step, set by the player (TestFlight 59.1: "can
// I set where the distance fares start?"): the five standard steps scaled
// so the first is the chosen fare, each to the nearest 0.05, through the
// existing `setFareRules`. The editor's own steps
// (`lineInfoFareDefaultDistanceBands`) are fixed; no reference scales them.

extension FareRules {
    /// The steps' starting fares the player can choose, 0.05 apart.
    public static let bandStartRange: ClosedRange<Int64> = 5...10_000
    public static let bandStartStep: Int64 = 5

    /// The standard distance steps for a city whose fare baseline is
    /// `baseline`, scaled so the first costs `start`: each standard step's
    /// fare times `start` ÷ the first standard fare (0.55), to the nearest
    /// 0.05. When `start` is where the city's own steps start
    /// (``standardBands(for:)``), those steps exactly.
    ///
    /// - Precondition: `start` is in ``bandStartRange``; `baseline` is from
    ///   1 to ``maximumFare``.
    public static func distanceBands(startingAt start: Money, baseline: Money) -> [FareBand] {
        precondition(bandStartRange.contains(start.amount), "distanceBands(startingAt:baseline:) requires a start in bandStartRange")
        let city = standardBands(for: baseline)
        if city.first?.fare == start { return city }
        let first = standardBands[0].fare.amount
        return standardBands.map { band in
            let fare = (2 * band.fare.amount * start.amount + first * 5) / (first * 10) * 5
            return FareBand(fromMeters: band.fromMeters, toMeters: band.toMeters, fare: Money(fare))
        }
    }

    /// Where the distance steps start for the stepper: the first step's fare
    /// when these rules are by distance, else the city's standard first
    /// step; within ``bandStartRange``, on its 0.05 steps.
    public func bandStart(baseline: Money) -> Int64 {
        let fare: Int64
        switch self {
        case .distance(let bands): fare = bands.first?.fare.amount ?? Self.standardBands(for: baseline)[0].fare.amount
        case .flat: fare = Self.standardBands(for: baseline)[0].fare.amount
        }
        let stepped = (fare + Self.bandStartStep / 2) / Self.bandStartStep * Self.bandStartStep
        return min(max(stepped, Self.bandStartRange.lowerBound), Self.bandStartRange.upperBound)
    }

    /// The steps, one per line: "0–6 km · $ 0.55", …, "32 km and more ·
    /// $ 1.20".
    public static func bandsText(_ bands: [FareBand], in language: DisplayLanguage) -> [String] {
        bands.map { band in
            let from = kilometres(band.fromMeters)
            let range = band.toMeters.map { "\(from)–\(kilometres($0)) km" }
                ?? language.text("\(from) km and more", "\(from) km 以上")
            return "\(range) · \(band.fare.centsText)"
        }
    }

    private static func kilometres(_ meters: Int64) -> String {
        meters % 1_000 == 0 ? "\(meters / 1_000)" : "\(meters / 1_000).\(meters % 1_000 / 100)"
    }
}
