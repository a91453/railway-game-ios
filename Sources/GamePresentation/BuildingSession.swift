import GameCore

// City building P0-A (ARCHITECTURE decision 92): the building tool places
// the chosen building where the player taps, through GameCore; since P0-C1
// (decision 94) a managed company pays for it, and the tool can demolish the
// company's buildings too. Since P0-C2 (decision 95) a tap only chooses the
// site: the map shows the building there, what it costs and the city's
// buildings it would buy out, and the action button builds it. Since P0-B
// (decision 98) a mode zones cells (ZoningSession.swift), and since P0-D
// (decision 130) one sells the company's buildings to the city: a tap
// chooses the building, the card shows what it would bring in and the gain
// or loss, and the action button sells it.

/// What a tap with the building tool does (decision 94).
public enum BuildingToolMode: CaseIterable, Hashable, Sendable {
    case build
    case demolish
    /// Chooses the company's building to sell to the city (decision 130).
    case sell
    /// Zones the cell tapped, or the rectangle dragged (decision 98).
    case zone

    public func title(in language: DisplayLanguage) -> String {
        switch self {
        case .build: language.text("Put up", "建造")
        case .demolish: language.text("Demolish", "拆除")
        case .sell: language.text("Sell", "出售")
        case .zone: language.text("Zone", "分區")
        }
    }
}

extension PlacedBuildingKind {
    /// Its name in the building tool.
    public func title(in language: DisplayLanguage) -> String {
        switch self {
        case .house: language.text("House", "小住宅")
        case .shop: language.text("Shop", "商店")
        case .office: language.text("Office block", "辦公樓")
        case .wharf: language.text("Wharf", "漁人碼頭")
        case .marina: language.text("Marina", "遊艇港")
        }
    }
}

extension GameSession {
    /// A tap with the building tool at `point`: in ``BuildingToolMode/build``
    /// it makes `point` the ``buildingSite`` (decision 95), reading in the
    /// land there on a map whose land is read as it is needed, so the
    /// preview counts the city's buildings in the way; in
    /// ``BuildingToolMode/demolish`` it demolishes the company's building
    /// there or within `reach` of it, the one whose centre is nearest; in
    /// ``BuildingToolMode/sell`` it makes that building the
    /// ``saleCandidate`` (decision 130); in ``BuildingToolMode/zone`` it
    /// zones the cell tapped (decision 98).
    @discardableResult
    public func tapBuildingTool(at point: PlanPoint, reach: Int64) -> Bool {
        switch buildingMode {
        case .build:
            // Decision 103: a tap on the building shown, where it can
            // stand, builds it; with building on tap, every tap builds.
            if let preview = buildingPreview, preview.problem == nil, isOnBuildingSite(point) {
                return confirmBuilding()
            }
            // Not an edit: as for a game's stations, reading land in is not
            // something to undo.
            readLand(within: Self.buildingLandReach, of: point)
            buildingSite = snappedBuildingSite(point)
            message = nil
            if buildingBuildsOnTap {
                return confirmBuilding()
            }
            return true
        case .demolish:
            guard let building = placedBuilding(near: point, reach: reach) else {
                message = StatusMessage(kind: .failure, text: language.text("Tap one of your buildings to demolish it.", "請點選要拆除的建物。"))
                return false
            }
            return demolishBuilding(building.id)
        case .sell:
            guard let building = placedBuilding(near: point, reach: reach) else {
                saleCandidate = nil
                message = StatusMessage(kind: .failure, text: language.text("Tap one of your buildings to sell it.", "請點選要出售的建物。"))
                return false
            }
            saleCandidate = building.id
            message = nil
            return true
        case .zone:
            guard let cell = zoneRectangle(from: point, to: point) else { return false }
            return zone(cell)
        }
    }

    /// The company's building at `point` or within `reach` of it, the one
    /// whose centre is nearest, or `nil`.
    private func placedBuilding(near point: PlanPoint, reach: Int64) -> PlacedBuilding? {
        world.placedBuildings.filter { building in
            point.x >= building.minX - reach && point.x < building.maxX + reach
                && point.y >= building.minY - reach && point.y < building.maxY + reach
        }.min { distance($0, point) < distance($1, point) }
    }

    /// Whether `point` lies on the building shown at ``buildingSite``.
    func isOnBuildingSite(_ point: PlanPoint) -> Bool {
        guard let site = buildingSite else { return false }
        let half = buildingKind.side / 2
        return point.x >= site.x - half && point.x <= site.x + half && point.y >= site.y - half && point.y <= site.y + half
    }

    /// Whether a one-finger drag that starts at `point` moves the building
    /// shown (decision 103) rather than the map: it starts on it.
    public func buildingDragMoves(from point: PlanPoint) -> Bool {
        tool == .building && buildingMode == .build && isOnBuildingSite(point)
    }

    /// The finger that went down on the building shown at `start` is at
    /// `end`: the building moves with it, and the preview follows.
    /// Changes nothing in the world.
    public func dragBuildingSite(from start: PlanPoint, to end: PlanPoint) {
        guard buildingMode == .build else { return }
        if buildingDragSiteBefore == nil {
            guard let site = buildingSite else { return }
            buildingDragSiteBefore = site
        }
        guard let before = buildingDragSiteBefore else { return }
        let moved = PlanPoint(x: before.x + end.x - start.x, y: before.y + end.y - start.y)
        guard world.bounds.contains(moved) else { return }
        buildingSite = moved
    }

    /// The finger lifted: the building stays shown where it was left, to
    /// build with the action button or another tap on it.
    public func endBuildingDrag(from start: PlanPoint, to end: PlanPoint) {
        dragBuildingSite(from: start, to: end)
        if let site = buildingSite {
            readLand(within: Self.buildingLandReach, of: site)
            buildingSite = snappedBuildingSite(site)
        }
        buildingDragSiteBefore = nil
    }

    /// How far a site is moved to stand clear of the city's buildings
    /// (decision 144): 12 m, less than half a D1's square and the gap
    /// beside it, so a building put on top of a city building stays there
    /// and buys it out, and one put at its edge moves into the gap.
    public static let buildingSnapReach: Int64 = 768
    /// The points within ``buildingSnapReach`` of a site, half a metre
    /// apart, nearest first (then by row and column).
    private static let buildingSnapOffsets: [(x: Int64, y: Int64)] = {
        let step = 32, reach = buildingSnapReach
        var offsets: [(x: Int64, y: Int64)] = []
        for y in stride(from: -reach, through: reach, by: step) {
            for x in stride(from: -reach, through: reach, by: step) where x * x + y * y <= reach * reach && (x, y) != (0, 0) {
                offsets.append((x, y))
            }
        }
        return offsets.sorted { ($0.x * $0.x + $0.y * $0.y, $0.y, $0.x) < ($1.x * $1.x + $1.y * $1.y, $1.y, $1.x) }
    }()

    /// `point`, or when ``buildingKind`` there would buy out some of the
    /// city's buildings, the nearest point within ``buildingSnapReach``
    /// where it buys out none and GameCore would put it up (decision 144):
    /// the player taps near a gap between the city's buildings and the
    /// building lands in it. With none, `point`, whose preview shows what
    /// buying out costs. Buying out by area (decision 146), always `point`:
    /// there are no squares to fit between.
    func snappedBuildingSite(_ point: PlanPoint) -> PlanPoint {
        guard !world.areaBuyOut else { return point }
        let kind = buildingKind
        func clears(_ centre: PlanPoint) -> Bool {
            world.cityCells(claimedBy: PlacedBuilding(id: PlacedBuildingID(rawValue: 1), kind: kind, centre: centre)).isEmpty
        }
        guard world.bounds.contains(point), !clears(point) else { return point }
        // GameCore has the last word on each candidate (water, track, the
        // company's other buildings); a few tries are enough, as the
        // nearest clear points lie side by side.
        var tries = 0
        for offset in Self.buildingSnapOffsets {
            let candidate = PlanPoint(x: point.x + offset.x, y: point.y + offset.y)
            guard world.bounds.contains(candidate), clears(candidate) else { continue }
            var draft = world
            if (try? draft.placeBuilding(kind, at: candidate)) != nil { return candidate }
            tries += 1
            if tries == 8 { break }
        }
        return point
    }

    /// The drag was cancelled: the building goes back where it was.
    public func cancelBuildingDrag() {
        guard let before = buildingDragSiteBefore else { return }
        buildingSite = before
        buildingDragSiteBefore = nil
    }

    /// What building `kind` costs before its land (a managed company's
    /// building cost; its land depends on where it stands): `nil` in free
    /// play, where building is free.
    public func buildingStartingCost(_ kind: PlacedBuildingKind) -> Money? {
        guard world.accounts.mode == .management else { return nil }
        return Money(kind.floorArea * PlacedBuildingRules.floorCost.amount)
    }

    /// How far round a building's site the land is read in: 64 m, more
    /// than any building and its clearance reach.
    static let buildingLandReach: Int64 = Land.cellLength

    /// Builds ``buildingKind`` on the ``buildingSite`` (``placeBuilding(at:)``)
    /// and, once it stands, clears the site.
    @discardableResult
    public func confirmBuilding() -> Bool {
        guard let site = buildingSite else {
            message = StatusMessage(kind: .failure, text: language.text("Tap the map where it goes first.", "請先在地圖上點選位置。"))
            return false
        }
        guard placeBuilding(at: site) else { return false }
        buildingSite = nil
        return true
    }

    /// Drops the building shown, without building it: the map's cancel
    /// button beside it (ARCHITECTURE decision 107).
    public func clearBuildingSite() {
        buildingSite = nil
    }

    /// Places a building of ``buildingKind`` centred on `point` with
    /// ``GameWorld/placeBuilding(_:at:)``, as one edit that undo takes
    /// back, and reports the outcome, with what it cost a managed company
    /// and the city's buildings it bought out, in ``message``. Returns
    /// whether it was placed.
    @discardableResult
    public func placeBuilding(at point: PlanPoint) -> Bool {
        let kind = buildingKind
        let (population, places, water) = (population, places, water)
        var cleared = 0
        let placed = perform { world throws(GameError) in
            // The site's land, read when it was picked, may have gone with an
            // undo since: read it again, as part of the edit (decision 95).
            Self.readLand(within: Self.buildingLandReach, of: [point], in: &world, population: population, places: places, water: water, coverage: coverage)
            cleared = world.placedBuildingQuote(kind, at: point)?.cleared.count ?? 0
            let building = try world.placeBuilding(kind, at: point)
            let english = kind.title(in: .english).lowercased(), chinese = kind.title(in: .traditionalChinese), id = building.id.rawValue
            var bought = cleared == 0 ? ("", "") : (
                cleared == 1 ? ", pulling down 1 city building" : ", pulling down \(cleared) city buildings",
                "，拆除城市建物 \(cleared) 棟"
            )
            // Decision 146: buying out by area, who moved in.
            if world.areaBuyOut, let movingIn = Self.movingInText(residents: building.residents, jobs: building.jobs, moving: true) {
                bought = (bought.0 + ", " + movingIn.english, bought.1 + "，" + movingIn.chinese)
            }
            guard building.cost > .zero else {
                return language.text("Built \(english) #\(id)\(bought.0).", "蓋好\(chinese) #\(id)\(bought.1)。")
            }
            return language.text(
                "Built \(english) #\(id) for \(building.cost.moneyText)\(bought.0).",
                "蓋好\(chinese) #\(id)，花費 \(building.cost.moneyText)\(bought.1)。"
            )
        }
        if placed {
            notePutUp(at: point)
        }
        return placed
    }

    /// Demolishes the company's building `id` with
    /// ``GameWorld/removePlacedBuilding(_:)``, as one edit that undo takes
    /// back, and reports the outcome in ``message``.
    @discardableResult
    public func demolishBuilding(_ id: PlacedBuildingID) -> Bool {
        guard let building = world.placedBuilding(id: id) else {
            message = StatusMessage(kind: .failure, text: GameError.unknownPlacedBuilding(id).playerMessage(in: language))
            return false
        }
        let fee = world.demolitionCost(of: building)
        let name = { (language: DisplayLanguage) in building.kind.title(in: language) }
        return perform { world throws(GameError) in
            try world.removePlacedBuilding(id)
            guard fee > .zero else {
                return language.text(
                    "Demolished \(name(.english).lowercased()) #\(id.rawValue).", "拆除\(name(.traditionalChinese)) #\(id.rawValue)。"
                )
            }
            return language.text(
                "Demolished \(name(.english).lowercased()) #\(id.rawValue) for \(fee.moneyText).",
                "拆除\(name(.traditionalChinese)) #\(id.rawValue)，花費 \(fee.moneyText)。"
            )
        }
    }

    /// How many buildings the player has placed, and who lives and works in
    /// them once anyone does, for the building tool.
    public var placedBuildingsText: String {
        let count = world.placedBuildings.count
        let placed = language.text(count == 1 ? "1 building placed" : "\(count) buildings placed", "已蓋 \(count) 棟")
        let residents = world.placedBuildings.reduce(Int64(0)) { $0 + $1.residents }
        let jobs = world.placedBuildings.reduce(Int64(0)) { $0 + $1.jobs }
        guard residents + jobs > 0 else { return placed }
        return placed + language.text(" · \(residents) residents, \(jobs) jobs", " · 居民 \(residents) 人、就業 \(jobs) 個")
    }

    /// What a managed company's buildings earn and cost a day as things
    /// stand, to the cent (a day's upkeep is a few dollars), or `nil`
    /// without any (or in free play).
    public var buildingEconomyText: String? {
        guard world.accounts.mode == .management, !world.placedBuildings.isEmpty else { return nil }
        var rent = Money.zero, costs = Money.zero
        for building in world.placedBuildings {
            rent = rent + world.dailyRent(of: building)
            let upkeep = world.dailyUpkeep(of: building)
            costs = costs + upkeep.upkeep + upkeep.tax
        }
        return language.text(
            "Rent \(rent.centsText) a day · upkeep and land tax \(costs.centsText)",
            "每日租金 \(rent.centsText) · 維護與土地資產稅 \(costs.centsText)"
        )
    }

    /// What building on the ``buildingSite`` would do (decision 95): GameCore
    /// places ``buildingKind`` there on a copy of the world; `nil` without a
    /// site, or in another mode or tool.
    public var buildingPreview: BuildingPreview? {
        guard tool == .building, buildingMode == .build, let site = buildingSite else { return nil }
        let kind = buildingKind
        var draft = world
        let cost: Money?, problem: String?
        var movingIn: (residents: Int64, jobs: Int64) = (0, 0)
        do throws(GameError) {
            let placed = try draft.placeBuilding(kind, at: site)
            cost = placed.cost
            movingIn = (placed.residents, placed.jobs)
            problem = nil
        } catch {
            cost = nil
            problem = error.playerMessage(in: language)
        }
        return BuildingPreview(
            kind: kind, centre: site, cost: cost, problem: problem,
            quote: world.placedBuildingQuote(kind, at: site) ?? PlacedBuildingQuote(building: .zero, land: .zero),
            residentsMovingIn: movingIn.residents, jobsMovingIn: movingIn.jobs
        )
    }

    /// What the preview says under the building tool: why it cannot be
    /// built, or what a managed company pays for what, and the city's
    /// buildings it pulls down; buying out by area (decision 146), in
    /// free play too, who moves in.
    public var buildingPreviewText: String? {
        guard let preview = buildingPreview else { return nil }
        if let problem = preview.problem { return problem }
        let quote = preview.quote
        let count = quote.cleared.count
        var english: [String] = [], chinese: [String] = []
        let movingIn = world.areaBuyOut
            ? Self.movingInText(residents: preview.residentsMovingIn, jobs: preview.jobsMovingIn, moving: false)
            : nil
        if world.accounts.mode == .management {
            english.append("Building \(quote.building.moneyText) + land \(quote.land.moneyText)")
            chinese.append("建物 \(quote.building.moneyText) + 土地 \(quote.land.moneyText)")
            if count > 0 {
                english.append("buying out \(count == 1 ? "1 city building" : "\(count) city buildings") \(quote.buyOut.moneyText)")
                chinese.append("收購城市建物 \(count) 棟 \(quote.buyOut.moneyText)")
            } else if quote.buyOut > .zero {
                // Decision 146: the share of the city's floor under it.
                english.append("buying out the city's floor under it \(quote.buyOut.moneyText)")
                chinese.append("收購用地上的城市建物 \(quote.buyOut.moneyText)")
            }
        } else if count > 0 {
            english.append(count == 1 ? "Pulls down 1 city building" : "Pulls down \(count) city buildings")
            chinese.append("拆除城市建物 \(count) 棟")
        } else if movingIn == nil {
            return nil
        }
        if let movingIn {
            english.append(movingIn.english)
            chinese.append(movingIn.chinese)
        }
        return language.text(english.joined(separator: ", "), chinese.joined(separator: "，"))
    }

    /// Who moves into a building buying out by area (decision 146): the
    /// share of each covered cell's residents and jobs, as the preview
    /// (`moving` false: "move in") or the message once it stands (`moving`
    /// true: "moving in") says it; `nil` when no one does.
    static func movingInText(residents: Int64, jobs: Int64, moving: Bool) -> (english: String, chinese: String)? {
        guard residents > 0 || jobs > 0 else { return nil }
        var english: [String] = [], chinese: [String] = []
        if residents > 0 {
            english.append(residents == 1 ? "1 resident" : "\(residents) residents")
            chinese.append("居民 \(residents) 人")
        }
        if jobs > 0 {
            english.append(jobs == 1 ? "1 job" : "\(jobs) jobs")
            chinese.append("工作 \(jobs) 個")
        }
        return (english.joined(separator: " and ") + (moving ? " moving in" : " move in"), "搬進" + chinese.joined(separator: "、"))
    }

    /// What the map draws for the building tool; `nil` with another tool.
    public var buildingOverlay: BuildingOverlay? {
        guard tool == .building else { return nil }
        var overlay = BuildingOverlay()
        // Decision 146: buying out by area, the city's squares stand in no
        // one's way, so they are not drawn.
        overlay.showsCityBuildingSites = buildingMode == .build && !world.areaBuyOut
        if buildingMode == .zone, let drag = zoneDrag {
            overlay.zoneDrag = drag.planRect
            overlay.zoneDragColor = zoningZone.map(CityMap.zoneColor)
        }
        if buildingMode == .sell, let sale = salePreview {
            // Decision 130: the building to sell, marked as the one chosen.
            overlay.site = PlanRect(sale.building)
            overlay.siteIsBuildable = true
        }
        if let preview = buildingPreview {
            let half = preview.kind.side / 2
            overlay.site = PlanRect(minX: preview.centre.x - half, minY: preview.centre.y - half,
                                    maxX: preview.centre.x - half + preview.kind.side, maxY: preview.centre.y - half + preview.kind.side)
            overlay.siteIsBuildable = preview.problem == nil
            overlay.boughtOut = preview.quote.cleared.map { PlanRect.cityBuilding(row: $0.row, column: $0.column, in: world) }
        }
        // Decision 140: a real-world map has a city building on nearly every
        // cell, and their squares over the whole view hid its streets; there
        // only those round the chosen site are drawn, enough to see where a
        // building fits between them, and none before a site is chosen.
        if world.geoAnchor != nil, overlay.showsCityBuildingSites {
            if let site = overlay.site {
                let reach = Self.citySitesReach
                overlay.citySitesArea = PlanRect(minX: site.minX - reach, minY: site.minY - reach, maxX: site.maxX + reach, maxY: site.maxY + reach)
            } else {
                overlay.showsCityBuildingSites = false
            }
        }
        return overlay
    }

    /// How far round a real-world map's chosen site its city buildings are
    /// drawn (decision 140): two cells.
    public static let citySitesReach = 2 * Land.cellLength

    /// What ``buildingKind`` costs a managed company: its building, and the
    /// land under it at that land's value; `nil` in free play, where it is
    /// free.
    public var buildingQuoteText: String? {
        guard world.accounts.mode == .management else { return nil }
        let kind = buildingKind
        let building = Money(kind.floorArea * PlacedBuildingRules.floorCost.amount)
        return language.text(
            "\(kind.title(in: .english)): \(building.moneyText) to build, plus the land's value for \(kind.footprintArea) m²",
            "\(kind.title(in: .traditionalChinese))：建造費 \(building.moneyText)，另加 \(kind.footprintArea) m² 的土地使用權（依地價）"
        )
    }

    private func distance(_ building: PlacedBuilding, _ point: PlanPoint) -> Int64 {
        let dx = building.centre.x - point.x, dy = building.centre.y - point.y
        return dx * dx + dy * dy
    }
}

/// What building ``GameSession/buildingKind`` on the
/// ``GameSession/buildingSite`` would do (decision 95), as GameCore
/// worked it out on a copy of the world.
public struct BuildingPreview: Hashable, Sendable {
    public let kind: PlacedBuildingKind
    public let centre: PlanPoint
    /// What it would cost, or `nil` when GameCore refused it.
    public let cost: Money?
    /// Why GameCore refused it, as the player reads it; `nil` when it
    /// would stand.
    public let problem: String?
    /// The parts of what it costs, and the cells whose city buildings it
    /// would buy out.
    public let quote: PlacedBuildingQuote
    /// The residents and jobs that would move in from the cells it buys
    /// out (decision 146: a share of each, by area); 0 when it is refused.
    public var residentsMovingIn: Int64 = 0
    public var jobsMovingIn: Int64 = 0
}

/// A rectangle of the plan, in world units: `minX ..< maxX` by `minY ..< maxY`.
public struct PlanRect: Hashable, Sendable {
    public let minX: Int64
    public let minY: Int64
    public let maxX: Int64
    public let maxY: Int64

    public init(minX: Int64, minY: Int64, maxX: Int64, maxY: Int64) {
        self.minX = minX
        self.minY = minY
        self.maxX = maxX
        self.maxY = maxY
    }

    /// The square the city's building on the cell at `row`, `column`
    /// stands on in `world` (decision 95): ``GameWorld/cityBuildingSide(row:column:)``
    /// across (decision 142), in the middle of the cell.
    public static func cityBuilding(row: Int, column: Int, in world: GameWorld) -> PlanRect {
        let side = world.cityBuildingSide(row: row, column: column)
        let inset = (Land.cellLength - side) / 2
        let minX = Int64(column) * Land.cellLength + inset, minY = Int64(row) * Land.cellLength + inset
        return PlanRect(minX: minX, minY: minY, maxX: minX + side, maxY: minY + side)
    }

    /// The square `building` stands on.
    public init(_ building: PlacedBuilding) {
        self.init(minX: building.minX, minY: building.minY, maxX: building.maxX, maxY: building.maxY)
    }
}

/// What the map draws for the building tool (decision 95).
public struct BuildingOverlay: Hashable, Sendable {
    /// Whether to draw where the city's buildings stand, so the player sees
    /// where a building would buy one out, and where: everywhere in view
    /// when `citySitesArea` is `nil`, otherwise only those it reaches (a
    /// real-world map's, round the chosen site, decision 140).
    public var showsCityBuildingSites = false
    public var citySitesArea: PlanRect?
    /// The building on the site, and whether GameCore would build it.
    public var site: PlanRect?
    public var siteIsBuildable = false
    /// The squares of the city's buildings it would buy out.
    public var boughtOut: [PlanRect] = []
    /// The cells a zoning drag would zone (decision 98), and the zone's
    /// colour (`nil` when it clears them).
    public var zoneDrag: PlanRect?
    public var zoneDragColor: PopTravel.RGB?

    public init() {}
}

extension GameWorld {
    /// The company's buildings that stand here but not in `after`, this
    /// world once a command ran on it: those it pulled down.
    func placedBuildings(clearedIn after: GameWorld) -> [PlacedBuilding] {
        let standing = Set(after.placedBuildings.map(\.id))
        return placedBuildings.filter { !standing.contains($0.id) }
    }
}
