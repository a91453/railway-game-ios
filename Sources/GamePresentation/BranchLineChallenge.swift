import Foundation
import GameCore

// The branch-line challenges (decision 289, NEXT_PRIORITIES §15.2 third,
// §16 step 5.2): Taiwan's branch lines, one challenge each, in the Taiwan
// railway history section. Each is played as the Liu Mingchuan challenge is
// (decision 153): a real-world map round the line, its ground and towns
// today's, with nothing built; the player lays the line again (tracing the
// real railway, decision 213, follows its alignment), reaches its towns one
// milestone at a time, and fills its trains with the riders and tourists
// of its sights. A line is data here (``BranchLineChallenge``); its
// targets are measured (`JijiReportTests` for the Jiji Line).

/// A branch line's challenge: its words, its map, its places and
/// milestones, its sights and its targets (decision 289).
public struct BranchLineChallenge: Sendable {
    /// What follows "branch." in its challenge's id: "jiji".
    public let id: String
    let titles: (english: String, chinese: String)
    let stories: (english: String, chinese: String)
    /// The map's box, in degrees: a few kilometres round the line's towns.
    let west: Double
    let east: Double
    let north: Double
    let south: Double
    /// The line's towns, first the one it leaves the main line at.
    let places: [Place]
    /// The milestones, in the order the line reaches them: each links its
    /// places' indices in ``places``.
    let milestones: [Milestone]
    /// The sights tourists come to (``AttractionCatalog`` ids).
    let sights: Set<String>
    let ridersTarget: Int64
    /// A closed year's net profit to reach, if the line asks for one.
    let profitTarget: Money?
    let startingBalance: Money
    let goldDays: Int64
    let silverDays: Int64
    let deadlineDays: Int64
    /// What the station master says first.
    let welcome: (english: String, chinese: String)
    /// The line on the challenge card under its story.
    let card: (english: String, chinese: String)

    /// A town of the line, where on the Earth it is.
    struct Place: Sendable {
        let english: String
        let chinese: String
        let latitude: Double
        let longitude: Double
    }

    /// A milestone: the places it links, what it is called, and what the
    /// station master says when it is reached.
    struct Milestone: Sendable {
        let places: [Int]
        let english: String
        let chinese: String
        let cheer: (english: String, chinese: String)
    }

    /// Its challenge's id: "branch.jiji".
    public var challengeID: String { "branch.\(id)" }

    /// The middle of the box, as ``LiuMingchuanChallenge/anchor`` works its
    /// own out.
    public var anchor: GeoAnchor {
        let y = (RealWorldFrame.mercatorY(north) + RealWorldFrame.mercatorY(south)) / 2
        let latitude = asin(tanh((0.5 - y / RealWorldFrame.worldPoints) * 2 * Double.pi)) * 180 / .pi
        guard let anchor = GeoAnchor(latitudeDegrees: latitude, longitudeDegrees: (west + east) / 2) else {
            preconditionFailure("The middle of the \(id) map is not on the Earth.")
        }
        return anchor
    }

    /// The world round ``anchor`` that holds the box.
    public var bounds: WorldBounds {
        let frame = RealWorldFrame(anchor: anchor, bounds: .standard)
        let corners = [(north, west), (south, east)].map { frame.worldPosition(latitude: $0.0, longitude: $0.1) }
        let halfWidth = corners.map { abs($0.x - frame.middleX) }.max() ?? 0
        let halfHeight = corners.map { abs($0.y - frame.middleY) }.max() ?? 0
        do {
            return try WorldBounds(width: Int64((2 * halfWidth).rounded(.up)), height: Int64((2 * halfHeight).rounded(.up)))
        } catch {
            preconditionFailure("The \(id) map does not fit in a world: \(error)")
        }
    }

    /// Where `place` is on the challenge's map.
    func point(of place: Place) -> PlanPoint {
        let position = RealWorldFrame(anchor: anchor, bounds: bounds).worldPosition(latitude: place.latitude, longitude: place.longitude)
        return PlanPoint(x: Int64(position.x.rounded()), y: Int64(position.y.rounded()))
    }

    /// The towns' points, where the app reads the land in first.
    public var townPoints: [PlanPoint] { places.map(point(of:)) }

    /// The scenario: the milestones, the riders and the profit.
    var scenario: Scenario {
        Scenario(
            id: challengeID,
            goals: milestones.map { .connect(points: $0.places.map { point(of: places[$0]) }, radius: Land.catchmentRadius) } + [.dailyRiders(ridersTarget)]
                + (profitTarget.map { [.annualNetProfit($0)] } ?? []),
            goldDays: goldDays, silverDays: silverDays, deadlineDays: deadlineDays, insolvencyDays: 60
        )
    }

    /// The challenge the start screen offers.
    var challenge: Challenge {
        let scenario = scenario
        return Challenge(id: challengeID, titles: titles, stories: stories, map: .branchLine(id), rules: { _, _ in scenario })
    }

    /// The challenge's world: a new real-world game on the line's map with
    /// its money, its land read in round each station as it is built, its
    /// sights, and nothing built; its ends are its story, so its edges bring
    /// no one from beyond the map (decision 137). The app reads in the towns
    /// round ``townPoints`` and maps the ground (``GameLauncher``).
    public func make(eventSeed: UInt32 = 1) -> GameWorld {
        var world = GameWorld.newGame(anchor: anchor, bounds: bounds, balance: startingBalance, eventSeed: eventSeed, land: [])
        world.setLandOnDemand()
        world.setOutsideConnections(false)
        // As the Liu Mingchuan challenge's (decision 153): its targets were
        // measured without holidays, building materials, dwells that
        // lengthen in a crowd, the rolling stock's own economics, flexible
        // dispatch, keeping left, realistic timetables, block sections, curve
        // speed limits, real car lengths or the city's requests.
        world.setDisruptions(nil)
        world.setBuildingMaterials(false)
        world.setDoorCrowding(false)
        world.setRollingStockEconomics(false)
        world.setFlexDispatch(false)
        world.setKeepLeft(false)
        world.setRealisticOperation(false)
        world.setBlockSections(false)
        world.setCurveSpeedLimits(false)
        world.setRealCarLengths(false)
        // Decision 319: its demand keeps the hours it was measured by.
        world.setTidalDemand(false)
        world.setCityRequests(seed: nil)
        // Its sights (decision 174): the line's own, which a sightseeing
        // train calling near raises (decision 286).
        world.setTourism(RealWorldFrame(world: world).map { AttractionCatalog.attractions(in: $0, bounds: world.bounds, only: sights) })
        do {
            try world.startScenario(scenario)
        } catch {
            preconditionFailure("Could not start the \(id) challenge: \(error)")
        }
        return world
    }

    func welcomeText(in language: DisplayLanguage) -> String { language.text(welcome.english, welcome.chinese) }

    func milestoneCheer(_ index: Int, in language: DisplayLanguage) -> String? {
        milestones.indices.contains(index) ? language.text(milestones[index].cheer.english, milestones[index].cheer.chinese) : nil
    }

    func milestoneTitle(_ index: Int, in language: DisplayLanguage) -> String? {
        milestones.indices.contains(index) ? language.text(milestones[index].english, milestones[index].chinese) : nil
    }

    /// The line on the challenge card.
    public func cardText(in language: DisplayLanguage) -> String { language.text(card.english, card.chinese) }

    /// Every branch line's challenge, in the order the menu lists them.
    public static let all: [BranchLineChallenge] = [jiji]

    /// The branch line whose challenge is `id` ("branch.jiji"), if any.
    public static func named(_ id: String) -> BranchLineChallenge? {
        all.first { $0.challengeID == id }
    }

    /// The branch line `id` ("jiji") names, if any.
    public static func line(_ id: String) -> BranchLineChallenge? {
        all.first { $0.id == id }
    }
}

// MARK: - The Jiji Line

// The history in its story is from public sources (the owner's
// `Railway/taiwan-rail-reference-clean/source/data/tra_special_trains.json`
// `branchLines` `jiji`; the English and Chinese Wikipedia's "Jiji line" /
// 「集集線」; Kurogane Rail's "Taiwan 45→C33"): the Taiwan Electric Power Company
// (臺灣電力株式會社, not today's Taipower; decision 387) laid the line in
// the early 1920s (sources give 1921 or 1922) to carry materials for the
// Sun Moon Lake hydroelectric works, and the Government-General bought it
// in 1927 and named it the Jiji Line; at 29.7 km it is the Taiwan Railway's
// longest branch; Jiji's wooden station of 1930 was wrecked by the 921
// earthquake of 1999 and rebuilt; Checheng, at its end, keeps its timber
// village. Its targets, money and days are this project's.

extension BranchLineChallenge {
    /// The stations are the TRA stations of the app's real railways
    /// (`track_stations.geojson`, `tra_sched|JIJI`).
    static let jiji = BranchLineChallenge(
        id: "jiji",
        titles: ("Jiji Line: Timber and Water", "集集線：木業與水力"),
        stories: (
            "In the early 1920s the Taiwan Electric Power Company laid a line from Ershui into the hills to carry materials for the Sun Moon Lake hydroelectric works; the Government-General bought it in 1927 and named it the Jiji Line. Lay it again, Ershui to Checheng, the longest branch of the Taiwan Railway: past Jiji's wooden station, wrecked by the 921 earthquake and rebuilt, to Checheng's timber village at its end, and fill its trains with visitors.",
            "1920 年代初，臺灣電力株式會社從二水往山裡鋪了一條鐵路，運送興建日月潭水力發電廠的器材；1927 年由總督府收購，改名集集線。把它重新鋪回來：從二水到車埕，台鐵最長的支線。經過 921 地震毀損又重建的木造集集車站，一路到終點保留木業聚落的車埕，讓列車載滿遊客。"
        ),
        west: 120.58, east: 120.90, north: 23.87, south: 23.78,
        places: [
            Place(english: "Ershui", chinese: "二水", latitude: 23.813244, longitude: 120.618362),
            Place(english: "Jiji", chinese: "集集", latitude: 23.826317, longitude: 120.78496),
            Place(english: "Shuili", chinese: "水里", latitude: 23.818602, longitude: 120.853204),
            Place(english: "Checheng", chinese: "車埕", latitude: 23.83263, longitude: 120.86572),
        ],
        milestones: [
            Milestone(
                places: [0, 1], english: "Ershui to Jiji", chinese: "二水—集集",
                cheer: ("Trains from Ershui reach Jiji and its wooden station!", "二水的列車開到集集了，木造車站迎接遊客！")
            ),
            Milestone(
                places: [0, 2], english: "On to Shuili", chinese: "延伸到水里",
                cheer: ("On to Shuili, the gateway to the hills!", "延伸到水里了，山城的門戶打開了！")
            ),
            Milestone(
                places: [0, 3], english: "Checheng, the end of the line", chinese: "終點車埕",
                cheer: ("Checheng! The whole Jiji Line runs again, Ershui to the timber village.", "到車埕了！整條集集線又通了，從二水一路到木業聚落。")
            ),
        ],
        sights: ["t074", "t078"],
        ridersTarget: JijiTargets.riders,
        profitTarget: JijiTargets.profit,
        startingBalance: JijiTargets.startingBalance,
        goldDays: JijiTargets.goldDays,
        silverDays: JijiTargets.silverDays,
        deadlineDays: JijiTargets.deadlineDays,
        welcome: (
            "The Jiji Line is ours to lay again: from Ershui up the valley to Checheng. Reach Jiji, then Shuili, then Checheng, carry \(Money(JijiTargets.riders).displayText) riders a day and make a year's net profit of \(JijiTargets.profit.moneyText). Turn on Trace real in Network to follow the old line. The first months are lean: a long line is dear to run until the towns along it grow, so start with one short train.",
            "集集線交給我們重新鋪：從二水沿著山谷到車埕。先到集集、再到水里、最後到車埕，每日運量達到 \(Money(JijiTargets.riders).displayText) 人次、一年淨利 \(JijiTargets.profit.moneyText)。在「路網」打開「沿真實鐵路」就能沿著舊線鋪。頭幾個月最辛苦：沿線城鎮長大之前，長路線的營運很花錢，先用一列短短的列車撐過去。"
        ),
        card: (
            "Milestones: Jiji, Shuili, Checheng · sights: Jiji Station, Checheng",
            "里程碑：集集、水里、車埕 · 景點：集集車站、車埕"
        )
    )
}

/// The Jiji challenge's targets (decision 289), measured by
/// `JijiReportTests` (debug build, flat ground, the whole line laid on the
/// first day for some $5.3 million, one train on a new line's hours,
/// these targets): the line carries 10,600 riders a day in its first
/// week, but fares bring some $55,000 a day against $90,000 of running
/// costs (mostly by the train-kilometre, so a shorter train hardly saves),
/// until the towns along it grow: 19,900 riders on day 60, 38,300 on day
/// 120, 50,300 on day 180. One train of two cars at the flat $5 fare gets
/// through with its cash near nothing from day 30 to 60, then earns $30.9
/// million net in its first year: gold on day 360. A flat $8 fare slows the
/// towns (15,200 riders on day 360, 22,600 on day 720): $4.35 million net
/// in the first year, the riders in the second, silver. Two trains of two
/// spend too much too soon and go bankrupt on day 76; with $1 million less
/// to start the flat fare's one train does too, on day 80. The Blue Train,
/// 50 a car, carries only 6,000 a day and goes bankrupt on day 72. So the
/// line is laid easily; the challenge is to get through its first months.
enum JijiTargets {
    static let riders: Int64 = 20_000
    /// A closed year's net profit: $3,000,000.
    static let profit = Money(300_000_000)
    /// $7 million: the line on flat ground and $1.7 million to spare, for
    /// the app's embankments, cuttings and tunnels and the first months.
    static let startingBalance = Money(700_000_000)
    static let goldDays = FinancePeriod.year.days
    static let silverDays = 2 * FinancePeriod.year.days
    static let deadlineDays = 3 * FinancePeriod.year.days
}
