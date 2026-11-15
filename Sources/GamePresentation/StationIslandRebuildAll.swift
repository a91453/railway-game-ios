import GameCore

// Decision 770: decision 761's next step. A game saved before stations
// could be islands has its real island stations (猴硐, 八堵, 宜蘭 ...) on
// two side platforms 5 m apart, as every double-track station was laid.
// Rebuilding each from its panel means finding them one by one; the
// author asked (2026-11-14) for one tap when there are many. So the
// stations of the world that are a real island station (its name within
// 450 m of one, as the station card already tells, decision 295) and
// still have two side platforms are listed on one card, each with its
// price and ticked, with the total; one button rebuilds the ticked ones
// in turn, each as decision 761's own command. Nothing changes when a game
// is loaded: the card only offers, and the player taps (decision 315).
//
// Which real stations are islands is decision 760's table
// (``RealStationPlatformTypes``, from OSM and the official station plans).

/// A station the island list offers (decision 770): its name, and the
/// price of rebuilding it as an island, or why it cannot be done.
public struct IslandRebuildCandidate: Identifiable, Equatable, Sendable {
    public let id: StationID
    public let name: String
    public let cost: Money?
    public let problem: String?
}

extension GameSession {
    /// The world's stations that are a real island station and still stand
    /// on two side platforms, in the world's order; none on a map that is
    /// not real or before double track is taught. Worked out once for each
    /// command, without pricing anything.
    func realIslandsToRebuild(isRealIsland: ((Station) -> Bool)? = nil) -> [StationID] {
        if isRealIsland == nil, let memo = realIslandsToRebuildMemo, memo.revision == commandRevision { return memo.ids }
        var ids: [StationID] = []
        if allows(UnlockableTool.doubleTrack) {
            let real = isRealIsland ?? { [self] station in
                realStations(named: station.name, at: station.location).contains { RealStationPlatformTypes.island.contains($0.id) }
            }
            ids = world.stations.filter { station in
                real(station) && !sidePlatformPairs(of: station.id, in: world).isEmpty
            }.map(\.id)
        }
        if isRealIsland == nil { realIslandsToRebuildMemo = (commandRevision, ids) }
        return ids
    }

    /// Whether the island list has a station to offer: the station panel's
    /// way back to the card shows (decision 770).
    public var hasRealIslandsToRebuild: Bool { !realIslandsToRebuild().isEmpty }

    /// Whether the card opens by itself (decision 770, REVIEW-L22): only
    /// when a station on it can be rebuilt now. A list whose stations all
    /// say why they cannot (the real-world demo's 瑞芳, 猴硐 and 十分, laid
    /// with no room for turnouts) gave the player nothing to tick and
    /// covered the map as the game opened. The station panel still opens it.
    public var opensIslandRebuildListByItself: Bool { opensIslandRebuildListByItself(isRealIsland: nil) }

    func opensIslandRebuildListByItself(isRealIsland: ((Station) -> Bool)?) -> Bool {
        islandRebuildList(isRealIsland: isRealIsland).contains { $0.cost != nil }
    }

    /// The device's record that the card has opened by itself once
    /// (`@AppStorage`); UI tests start with it set (`RailwayGameApp`).
    public static let islandRebuildListSeenKey = "islandRebuildList.seen"

    /// The island list: each real island station on two side platforms,
    /// priced on its own as its panel prices it (decision 761).
    public var islandRebuildList: [IslandRebuildCandidate] { islandRebuildList(isRealIsland: nil) }

    func islandRebuildList(isRealIsland: ((Station) -> Bool)?) -> [IslandRebuildCandidate] {
        if isRealIsland == nil, let memo = islandRebuildListMemo, memo.revision == commandRevision { return memo.list }
        let list = realIslandsToRebuild(isRealIsland: isRealIsland).compactMap { id -> IslandRebuildCandidate? in
            guard let station = world.station(id: id) else { return nil }
            let draft = stationIslandDraft(for: id)
            guard draft.cost != nil || draft.problem != nil else { return nil }
            return IslandRebuildCandidate(id: id, name: station.name, cost: draft.cost, problem: draft.problem)
        }
        if isRealIsland == nil { islandRebuildListMemo = (commandRevision, list) }
        return list
    }

    /// What the ticked stations `ids` cost together: each priced on the
    /// world as it is now (each rebuild touches only its own station).
    public func islandRebuildTotal(of ids: Set<StationID>, in list: [IslandRebuildCandidate]) -> Money {
        Money(list.filter { ids.contains($0.id) }.compactMap(\.cost).reduce(0) { $0 + $1.amount })
    }

    /// Opens the island list's card.
    public func openIslandRebuildList() { showsIslandRebuildList = true }

    /// Rebuilds stations `ids` as islands, in the list's order, each as
    /// decision 761's command (undo takes them back one at a time). Each is
    /// planned again on the world the one before it left; one that cannot
    /// be done, or no longer has the cash, is skipped and named.
    public func rebuildStationsAsIsland(_ ids: [StationID]) {
        let before = world.economy.balance
        var done: [String] = [], skipped: [String] = []
        var lifted = 0
        var parked: [String] = []
        for id in ids {
            guard let station = world.station(id: id) else { continue }
            guard let rebuild = stationIslandDraft(for: id).rebuild else {
                skipped.append(station.name)
                continue
            }
            do throws(GameError) {
                let outcome = try performCommand(.rebuildStationAsIsland(rebuild))
                done.append(station.name)
                lifted += outcome.left.count
                parked += outcome.parked
            } catch {
                skipped.append(station.name)
            }
        }
        let separator = language.text(", ", "、")
        guard !done.isEmpty else {
            message = StatusMessage(kind: .failure, text: language.text(
                "No station could be rebuilt as an island: \(skipped.joined(separator: separator)).",
                "沒有車站能改成島式月台：\(skipped.joined(separator: separator))。"
            ))
            return
        }
        let cost = Money(before.amount - world.economy.balance.amount)
        var outcome = PlayerCommand.Outcome()
        outcome.left = Array(repeating: "", count: lifted)
        outcome.parked = parked
        var text = language.text(
            "\(done.count) \(done.count == 1 ? "station has" : "stations have") an island platform now (\(done.joined(separator: separator))), for \(cost.moneyText).",
            "\(done.count) 站已改成島式月台（\(done.joined(separator: separator))），花費 \(cost.moneyText)。"
        ) + Self.liftedText(outcome, in: language)
        if !skipped.isEmpty {
            text += language.text(
                " Not rebuilt: \(skipped.joined(separator: separator)); open the station to see why.",
                "沒有改的：\(skipped.joined(separator: separator))，打開車站可以看原因。"
            )
        }
        message = StatusMessage(kind: .success, text: text)
        endFollowIfGone()
        showsIslandRebuildList = false
        playSound?(.track)
    }

    /// The card's title, what it says, and its button.
    public var islandRebuildListTitle: String {
        language.text("Real island stations", "真實是島式月台的車站")
    }

    public var islandRebuildListHelp: String {
        language.text(
            "These stations have an island platform between their two tracks in real life, but yours has a platform on each side. Tick the ones to rebuild: one track swings out round each, lines keep their platforms, and a train in the way goes back to the start of its line.",
            "這些車站真實是兩股軌道中間一座島式月台，你的站現在是兩側各一座。勾選要改建的站：每站其中一股在站內往外移，路線指定的月台會跟著換，擋在軌道上的列車會回到路線起點。"
        )
    }

    public func islandRebuildAllButtonText(count: Int, total: Money) -> String {
        language.text(
            "Rebuild \(count) \(count == 1 ? "station" : "stations") (\(total.moneyText))",
            "改建 \(count) 站（\(total.moneyText)）"
        )
    }

    /// The station panel's way back to the card.
    public var islandRebuildListButtonText: String {
        language.text("All real island stations…", "所有真實島式站…")
    }
}
