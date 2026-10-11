import GameCore

// The first Taiwan railway history challenge (decision 90): take over the
// Pingxi Line, built for coal and kept for its sights, and fill it with
// visitors. It is played on the real-world demo's map as it was before
// decision 132 (``RealWorldDemo/makeFlat(in:railways:land:water:steep:)``):
// the Pingxi, Yilan and Shenao Lines on their real alignments, flat,
// running.
//
// The history in its story is from public sources (the English
// Wikipedia's "Pingxi line"; CommonWealth's Smile Taiwan, "回憶平溪支線的黑金
// 歲月"): the line was built for the Tai-Yang mining company's coal and
// opened in 1921, the Government-General bought it in 1929 and began
// passenger service, and after the mines declined it was nearly closed for
// its losses in the 1980s before local people kept it; it became a tourist
// line. Its targets, the festival's days and boost are this project's.

extension Challenge {
    /// The Taiwan railway history challenges, oldest era first.
    public static let history: [Challenge] = [liuMingchuan, pingxi]

    /// The Pingxi Line, home of the sky lanterns.
    static let pingxi = Challenge(
        id: "history.pingxi",
        titles: ("Pingxi Line: Sky Lanterns", "平溪線：天燈之鄉"),
        stories: (
            "Built in 1921 to carry the valley's coal and bought by the Government-General in 1929, the Pingxi Line almost closed for its losses when the mines ran down. Visitors saved it: Shifen's falls, Jingtong's old streets and the sky lanterns of Pingxi. Take over the line and fill its trains, above all at the Sky Lantern Festival, when the crowds pour into Shifen and Pingxi.",
            "平溪線在 1921 年為了運煤而建，1929 年由總督府收購並開始載客；煤礦沒落後，一度因為虧損差點停駛。後來救了它的是遊客：十分瀑布、菁桐老街，還有平溪的天燈。接手這條路線，讓列車載滿乘客，特別是天燈節人潮湧進十分與平溪的時候。"
        ),
        map: .pingxi,
        rules: { _, _ in
            Scenario(
                id: "history.pingxi",
                goals: [.dailyRiders(PingxiChallenge.ridersTarget), .annualNetProfit(PingxiChallenge.profitTarget)],
                goldDays: FinancePeriod.year.days, silverDays: 2 * FinancePeriod.year.days, deadlineDays: 3 * FinancePeriod.year.days,
                insolvencyDays: 60
            )
        }
    )
}

/// The Pingxi challenge's numbers and its festival (decision 90).
///
/// Measured headless (release build, the demo as it starts, nobody
/// playing): its stations' demand is 71,000 a day; it carries 55,000 to
/// 71,000 riders a day over its first week; fares bring some $310,000 a
/// day against $340,000 of running costs, a loss of about $25,000 a day,
/// $9 million a year, as the real line lost money before it was saved.
/// So the riders' target is reached only on the festival's days, with the
/// trains to carry them, and the profit only by turning the line round:
/// fares, costs, lines. Its ratings fall on the year-end closings: gold in
/// the first year, silver in the second, bronze in the third.
public enum PingxiChallenge {
    /// Riders a day to reach.
    static let ridersTarget: Int64 = 80_000
    /// A closed year's net profit to reach: $2,000,000.
    static let profitTarget = Money(200_000_000)

    /// The Sky Lantern Festival: from day 45 of each 360-day year for 3 days
    /// (the game's calendar has no lunar new year, so a fixed day stands in
    /// for the Lantern Festival), the demand at Shifen and Pingxi two and a
    /// half times their own, announced a week before.
    static let festivalDay: Int64 = 45
    static let festivalDays: Int64 = 3
    static let festivalBoost: Int64 = 1_500
    static let festivalNotice: Int64 = 7
    static let festivalStations = ["十分", "平溪"]

    /// The challenge's world: the real-world demo's lines, running, and the
    /// scenario with the festival at its stations.
    public static func make(
        in language: DisplayLanguage, railways: RealRailways, land: [LandCell]? = nil, water: [CellPosition] = [], steep: [CellPosition] = []
    ) -> GameWorld {
        var world = RealWorldDemo.makeFlat(in: language, railways: railways, land: land, water: water, steep: steep)
        let events = festivalStations.compactMap { name -> ScenarioEvent? in
            guard let real = railways.stations.first(where: { $0.id == "tra_sched|\(name)" }),
                  let station = world.stations.first(where: { $0.name == real.name(in: language) }) else { return nil }
            return ScenarioEvent(station: station.id, dayOfYear: festivalDay, days: festivalDays, boost: festivalBoost, notice: festivalNotice)
        }
        let rules = Challenge.pingxi.scenario(seed: 0, in: world.bounds)
        do {
            try world.startScenario(Scenario(
                id: rules.id, goals: rules.goals, goldDays: rules.goldDays, silverDays: rules.silverDays, deadlineDays: rules.deadlineDays,
                insolvencyDays: rules.insolvencyDays, trainTypes: rules.trainTypes, events: events
            ))
        } catch {
            preconditionFailure("Could not start the Pingxi challenge: \(error)")
        }
        return world
    }

    /// The festival's line on the challenge card: "Sky Lantern Festival:
    /// day 45 of each year, 3 days, crowds at Shifen and Pingxi".
    public static func festivalText(in language: DisplayLanguage) -> String {
        language.text(
            "Sky Lantern Festival: day \(festivalDay + 1) of each year, \(festivalDays) days, crowds at Shifen and Pingxi",
            "天燈節：每年第 \(festivalDay + 1) 天起 \(festivalDays) 天，十分與平溪湧入人潮"
        )
    }
}
