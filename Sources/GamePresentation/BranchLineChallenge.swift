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

    /// The scenario: the milestones and the riders.
    var scenario: Scenario {
        Scenario(
            id: challengeID,
            goals: milestones.map { .connect(points: $0.places.map { point(of: places[$0]) }, radius: Land.catchmentRadius) } + [.dailyRiders(ridersTarget)],
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
// 「集集線」; Kurogane Rail's "Taiwan 45→C33"): Taiwan Power laid the line in
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
            "In the early 1920s Taiwan Power laid a line from Ershui into the hills to carry materials for the Sun Moon Lake hydroelectric works; the Government-General bought it in 1927 and named it the Jiji Line. Lay it again, Ershui to Checheng, the longest branch of the Taiwan Railway: past Jiji's wooden station, wrecked by the 921 earthquake and rebuilt, to Checheng's timber village at its end, and fill its trains with visitors.",
            "1920 年代初，台灣電力從二水往山裡鋪了一條鐵路，運送興建日月潭水力發電廠的器材；1927 年由總督府收購，改名集集線。把它重新鋪回來：從二水到車埕，台鐵最長的支線。經過 921 地震毀損又重建的木造集集車站，一路到終點保留木業聚落的車埕，讓列車載滿遊客。"
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
        startingBalance: JijiTargets.startingBalance,
        goldDays: JijiTargets.goldDays,
        silverDays: JijiTargets.silverDays,
        deadlineDays: JijiTargets.deadlineDays,
        welcome: (
            "The Jiji Line is ours to lay again: from Ershui up the valley to Checheng. Reach Jiji, then Shuili, then Checheng, and carry \(Money(JijiTargets.riders).displayText) riders a day. Turn on Trace real in Network to follow the old line; a sightseeing train calling at Jiji or Checheng brings more visitors.",
            "集集線交給我們重新鋪：從二水沿著山谷到車埕。先到集集、再到水里、最後到車埕，每日運量達到 \(Money(JijiTargets.riders).displayText) 人次。在「路網」打開「沿真實鐵路」就能沿著舊線鋪；觀光列車停靠集集或車埕，遊客會變多。"
        ),
        card: (
            "Milestones: Jiji, Shuili, Checheng · sights: Jiji Station, Checheng",
            "里程碑：集集、水里、車埕 · 景點：集集車站、車埕"
        )
    )
}

/// The Jiji challenge's targets (decision 289), measured by
/// `JijiReportTests`.
enum JijiTargets {
    static let riders: Int64 = 9_000_000
    static let startingBalance = Money(600_000_000)
    static let goldDays = FinancePeriod.year.days / 2
    static let silverDays = FinancePeriod.year.days
    static let deadlineDays = 3 * FinancePeriod.year.days
}
