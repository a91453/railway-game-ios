import GameCore

// Decision 605 (third part): a line bought before its real layout came,
// rebuilt as real. The Taoyuan Airport MRT has been bought with a passing
// loop outside each track at Chang Gung Memorial Hospital (A8), where its
// expresses overtake the stopping trains, and with the timetable whose
// expresses pass the stations between since decision 605; a game saved
// with the line bought before then has two tracks there and every train
// stopping everywhere. A save is never changed when it is read (decision
// 315); the line's panel offers the rebuild, priced, and the player
// decides, as it offers a missing depot (decision 557).
//
// The loops are laid with the platform track tool (``PlatformTrackPlan``):
// beside each of the station's two platforms, on the side away from the
// other, a double track's spacing out with the tool's 50 m S-curve to each
// turnout (``PlatformTrackLayout/side``), as near as it comes to the
// purchase's loops (6 m out, 50 m ramps, ``RealLineLayout``). The island
// layout's 88 m S-curves reach past the junctions beyond A8's platforms.
// A8 stands on the climb to Linkou, so the turnouts may stand on a grade
// (``GameSession/platformTrackTurnout(from:at:forward:reach:onGrade:in:)``):
// GameCore's split takes one on a steady grade no steeper than a turnout
// may be (decision 233) and says why where not.

/// A line rebuilt as real (decision 605): a platform track beside each
/// platform of its overtaking station, and the timetable whose expresses
/// overtake there, built with ``GameWorld``'s commands.
public struct RealLineRebuild: Hashable, Sendable, Codable {
    /// The line rebuilt.
    public let line: LineID
    /// The real line's name in the app's data (`tymc:A`).
    public let realLine: String
    /// A platform track beside each of the station's platforms.
    let tracks: [PlatformTrackPlan]
    /// The line's runs from then on, in its stops' order.
    let runs: [LineRun]
}

/// What the line panel's "rebuild as real" card shows (decision 605).
public struct RealLineRebuildOffer: Sendable {
    public let line: LineID
    /// The station the loops are added at.
    public let station: String
    /// What the rebuild takes, or `nil` with ``problem`` saying why it
    /// cannot be done.
    public let rebuild: RealLineRebuild?
    /// The whole price.
    public let price: Money?
    /// The company's buildings in its way, which come down with it.
    public let demolished: [String]
    public let problem: String?
    /// Whether a run of the line is due or under way: its timetable
    /// changes, so it is rebuilt only once the day's last train is in.
    public let waitsForTheLastTrain: Bool

    /// Whether the card's button rebuilds it now, with `balance` in hand.
    public func canRebuild(balance: Money) -> Bool {
        rebuild != nil && !waitsForTheLastTrain && shortfallText(balance: balance, in: .english) == nil
    }

    /// The button on the line's panel.
    public static func buttonTitle(in language: DisplayLanguage) -> String {
        language.text("Rebuild as real", "照真實改建")
    }

    /// The card's text: what changes, what it costs and what comes down;
    /// or why it cannot be done.
    public func summaryText(in language: DisplayLanguage) -> String {
        if let problem { return problem }
        let cost = price?.moneyText ?? ""
        var text = language.text(
            "\(station) gets a passing track beside each platform, and the express trains run again, passing the stations they pass in real life and overtaking at \(station). For \(cost).",
            "\(station)兩側各加一股待避線，直達車照真實只停幾站、在\(station)越過普通車。\(cost)。"
        )
        if waitsForTheLastTrain {
            text += language.text(
                " The line's timetable changes with it: rebuild after the day's last train is in.",
                "班次會跟著換成有直達車的時刻表：請在今天末班車收班後改建。"
            )
        }
        if !demolished.isEmpty {
            let names = demolished.joined(separator: language.text(", ", "、"))
            text += language.text(" Comes down: \(names).", "要拆：\(names)。")
        }
        return text
    }

    /// Why the company cannot pay for it now, or `nil`.
    public func shortfallText(balance: Money, in language: DisplayLanguage) -> String? {
        guard let price, balance < price else { return nil }
        return language.text(
            "Not enough money: it costs \(price.moneyText).",
            "資金不足：需要 \(price.moneyText)。"
        )
    }
}

extension GameSession {
    /// The selected line's rebuild as real (decision 605), laid out and
    /// priced; `nil` when it has nothing to rebuild: a line not bought,
    /// bought as real already, or off a real-world map.
    public var selectedLineRealRebuildOffer: RealLineRebuildOffer? {
        guard let line = selectedLine else { return nil }
        return realRebuildOffer(for: line.id)
    }

    /// Whether line `id` has a rebuild as real to offer: the panel's
    /// button shows for it. Cheap: nothing is laid or priced.
    public func rebuildsAsReal(_ id: LineID) -> Bool {
        realRebuildTarget(for: id) != nil
    }

    /// What a rebuild of line `id` starts from: the line, the real line's
    /// name, its overtaking station and the real timetable's runs; `nil`
    /// for nothing to rebuild.
    private func realRebuildTarget(for id: LineID) -> (line: ServiceLine, realLine: String, station: Station, runs: [LineRun])? {
        guard let railways, RealWorldFrame(world: world) != nil, let line = world.line(id: id),
              let bought = world.acquisitions.first(where: { $0.line == id }),
              let urban = RealBranchLine.urbanLines.first(where: { "\(RealBranchLine.dataSystem(of: $0.system)):\($0.network)" == bought.realLine }),
              let name = RealBranchLine.overtakeStations(system: urban.system, network: urban.network).first,
              let station = realOvertakeStation(name, of: line, system: urban.system, railways: railways),
              world.trackPlatforms(of: station.id).count == 2
        else { return nil }
        // The real timetable, as a line bought now runs it.
        let candidates = [urban.shares.flatMap { RealBranchLine.metroRuns(of: bought.realLine, after: $0, in: railways) }, railways.metroRuns[bought.realLine]]
        guard let real = candidates.compactMap(\.self).first(where: { $0.stops.count == line.stops.count }),
              real.runs.contains(where: { !$0.passes.isEmpty }) else { return nil }
        return (line, bought.realLine, station, real.runs.map { $0.lineRun(stops: real.stops, reversed: true) })
    }

    /// Line `id`'s rebuild as real, laid out on a copy of the world and
    /// priced, or `nil` for nothing to rebuild.
    public func realRebuildOffer(for id: LineID) -> RealLineRebuildOffer? {
        guard let (line, realLine, station, runs) = realRebuildTarget(for: id) else { return nil }
        let waits = !RealLineDepotAddition.isAtRest(line, runs: runs, in: world)
        func refused(_ problem: String) -> RealLineRebuildOffer {
            RealLineRebuildOffer(
                line: id, station: station.name, rebuild: nil, price: nil, demolished: [], problem: problem, waitsForTheLastTrain: waits
            )
        }

        // A platform track beside each platform, on the side away from
        // the other.
        let platforms = world.trackPlatforms(of: station.id)
        var tracks: [PlatformTrackPlan] = []
        for (index, platform) in platforms.enumerated() {
            let other = platforms[1 - index]
            guard let geometry = world.trackGeometry(of: platform.edge), let across = world.trackGeometry(of: other.edge) else {
                return refused(language.text("\(station.name) cannot be rebuilt here.", "\(station.name)在這裡不能改建。"))
            }
            let here = geometry.location(at: (platform.start + platform.end) / 2)
            let there = across.location(at: (other.start + other.end) / 2).position.plan
            let way = here.direction
            // y grows south on the map: the left of a track running along
            // `way` is (dy, -dx), as ``sideText(_:of:)`` reads it.
            let toOther = PlanVector(dx: there.x - here.position.plan.x, dy: there.y - here.position.plan.y)
            let otherOnLeft = toOther.dx * way.dy - toOther.dy * way.dx > 0
            switch platformTrackPlan(beside: platform, layout: .side, side: otherOnLeft ? .right : .left, onGrade: true) {
            case .success(let plan): tracks.append(plan)
            case .failure(let problem):
                return refused(language.text("\(station.name) cannot be rebuilt: ", "\(station.name)改建不了：") + problem.text(in: language))
            }
        }
        let rebuild = RealLineRebuild(line: id, realLine: realLine, tracks: tracks, runs: runs)

        // GameCore's answer and the price, on a funded copy, with the
        // line's trains at rest: the runs are set only while none is out.
        var probe = world.pricingCopy()
        if waits { probe = RealLineDepotAddition.atRest(probe, line: id) }
        let opening = probe.economy.balance
        let standing = probe.placedBuildings
        do throws(GameError) {
            try build(rebuild, in: &probe)
            let gone = standing.filter { building in !probe.placedBuildings.contains { $0.id == building.id } }
            return RealLineRebuildOffer(
                line: id, station: station.name, rebuild: rebuild, price: opening - probe.economy.balance,
                demolished: gone.map { $0.kind.title(in: language) }, problem: nil, waitsForTheLastTrain: waits
            )
        } catch {
            return refused(language.text("\(station.name) cannot be rebuilt: ", "\(station.name)改建不了：") + error.playerMessage(in: language))
        }
    }

    /// The line's stop nearest the real station `name`, within reach of it.
    private func realOvertakeStation(_ name: String, of line: ServiceLine, system: String, railways: RealRailways) -> Station? {
        guard let frame = RealWorldFrame(world: world),
              let real = RealLineLaying.realPoint(of: name, system: system, railways: railways, frame: frame) else { return nil }
        let stops = line.stops.compactMap(world.station(id:))
        guard let nearest = stops.min(by: { (WorldVector($0.location) - real).length < (WorldVector($1.location) - real).length }),
              (WorldVector(nearest.location) - real).length < RealLineAcquisition.stationReach else { return nil }
        return nearest
    }

    /// Rebuilds the line of `offer` as real (decision 605), paying for it.
    /// `false`, with the message saying why, where it cannot be.
    ///
    /// The offer is taken again from the world as it is now, as a depot's
    /// is (``addRealDepot(_:)``): once the first train is due it waits for
    /// the last one, and where the rebuild no longer lays or prices as the
    /// card said, the player is asked to look again.
    @discardableResult
    public func rebuildRealLine(_ offer: RealLineRebuildOffer) -> Bool {
        let current = realRebuildOffer(for: offer.line)
        guard let current, let rebuild = current.rebuild, !current.waitsForTheLastTrain, rebuild == offer.rebuild else {
            let changed = current?.problem == nil && current?.waitsForTheLastTrain == false && offer.rebuild != nil
            message = StatusMessage(
                kind: .failure,
                text: changed
                    ? language.text(
                        "The line has changed since the card opened: open it again for its price now.",
                        "這條線在打開後變了，請重新打開看現在的價格。"
                    )
                    : current.map { $0.problem ?? $0.summaryText(in: language) }
                    ?? language.text("This line has nothing to rebuild.", "這條線沒有要改建的。")
            )
            return false
        }
        let station = offer.station
        return perform(.rebuildRealLine(rebuild)) { _, _, _ in
            language.text(
                "Rebuilt: \(station) has its passing tracks and the express trains run.",
                "已改建：\(station)有待避線，直達車開始行駛。"
            )
        } != nil
    }

    /// Builds `rebuild` in `world`: the platform tracks, then the line's
    /// new runs, its trains still out taken off their runs and put back;
    /// all of it or, throwing, none.
    func build(_ rebuild: RealLineRebuild, in world: inout GameWorld) throws(GameError) {
        try world.editTrackAsOne { (world: inout GameWorld) throws(GameError) in
            guard let line = world.line(id: rebuild.line) else { throw .unknownLine(rebuild.line) }
            for plan in rebuild.tracks {
                _ = try build(plan, in: &world)
            }
            var lifted: [(TrainID, Int?)] = []
            for id in line.trains where world.train(id: id)?.execution != nil {
                lifted.append((id, world.assignedPattern(of: id)))
                try world.unassignTrain(id)
                try world.stopTrainService(id)
            }
            try world.setLineRuns(line.id, to: rebuild.runs)
            for (id, pattern) in lifted {
                try world.assignTrain(id, to: line.id, pattern: pattern)
            }
        }
    }
}
