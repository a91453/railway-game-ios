import Foundation
import GameCore

// Buying a real station (decision 400 A.8): on a real-world map the platform
// tool's faint pins (decision 295) put the next platform on the player's
// track within 400 m. Where there is none, the pin offers the station
// instead: a short stretch of track along the real line's centre, the
// platform as long as decision 295 makes it and 150 m on past each end (the
// room decision 351 leaves for a crossover), with the station named as the
// real one. All of it on the ground, as the game's stations are (decision
// 132). Decision 760: a station whose real platforms are an island gets two
// tracks 11 m apart, the island between; one with a side platform on each
// of two tracks gets two tracks 5 m apart, a platform on each; the others
// (one side platform, or no data) one track.
//
// The price is what building it costs, worked out by building it on a copy
// of the world: no value for a line's running, as there is no line, no
// train and no timetable to buy. What is built is the company's own track
// and station, as if laid by hand; nothing records that it was bought, and
// one Undo takes it back.

/// A real station bought, as the command builds it
/// (``PlayerCommand/buyRealStation(_:)``): the stretches one after another,
/// the station's platform the whole of the edge of stretch `platform`, and
/// the new station's name, place and ridership. Decision 760: a second
/// track beside the first, its own stretches one after another, with a
/// platform the whole of the edge of its stretch `secondPlatform`; none
/// where the station has one track.
public struct RealStationPurchase: Hashable, Sendable {
    public let stretches: [PlayerCommand.TrackStretch]
    public let platform: Int
    public let secondStretches: [PlayerCommand.TrackStretch]
    public let secondPlatform: Int?
    public let name: String
    public let at: PlanPoint
    public let demand: StationDemand

    public init(
        stretches: [PlayerCommand.TrackStretch], platform: Int,
        secondStretches: [PlayerCommand.TrackStretch] = [], secondPlatform: Int? = nil,
        name: String, at: PlanPoint, demand: StationDemand
    ) {
        self.stretches = stretches
        self.platform = platform
        self.secondStretches = secondStretches
        self.secondPlatform = secondPlatform
        self.name = name
        self.at = at
        self.demand = demand
    }
}

/// How the platforms of a real station a purchase lays stand (decision
/// 760), from ``RealStationPlatformTypes``.
public enum RealStationPlatformKind: Sendable, Equatable {
    /// One track and its platform.
    case single
    /// Two tracks 11 m apart, an island platform between.
    case island
    /// Two tracks 5 m apart, a side platform outside each.
    case sides

    /// How `station`'s real platforms stand: one track where the data has
    /// one side platform, none, or not the station.
    public static func of(_ station: RealRailways.Station) -> RealStationPlatformKind {
        if RealStationPlatformTypes.island.contains(station.id) { return .island }
        if RealStationPlatformTypes.side.contains(station.id) { return .sides }
        return .single
    }

    /// How far the second track stands from the first: decision 741's
    /// island, or the demo lines' track spacing.
    var spacing: Double {
        switch self {
        case .single: 0
        case .island: RealLineAcquisition.islandSpacing
        case .sides: HighSpeedDemo.trackOffset
        }
    }
}

/// What the card offering a real station says (decision 400 A.8): the
/// station, the real line the track follows, how long the track is, the
/// price, and what is in the way, if anything.
public struct RealStationOffer: Sendable {
    public let suggestion: RealStationSuggestion
    /// The system whose line the track follows.
    public let system: RealRailways.System
    public let purchase: RealStationPurchase?
    /// The track's length in whole metres; 0 where nothing can be built.
    public let metres: Int
    /// How the platforms stand (decision 760): what the purchase lays.
    public var platforms: RealStationPlatformKind = .single
    public let price: Money?
    /// Why it cannot be bought, as the player reads it.
    public let problem: String?

    /// What the purchase brings, in a line.
    public func summaryText(in language: DisplayLanguage) -> String {
        let name = suggestion.name(in: language)
        guard purchase != nil else {
            return language.text("\(name) station and a short stretch of track.", "\(name)站和一小段軌道。")
        }
        switch platforms {
        case .single:
            return language.text(
                "\(metres) m of track and a platform, the station named \(name) as the real one, to extend both ways from here.",
                "一段 \(metres) 公尺的軌道和月台，站名照真實的\(name)，從這一站往兩頭延伸。"
            )
        case .island:
            return language.text(
                "Two tracks of \(metres) m with an island platform between, as the real \(name), to extend both ways from here.",
                "兩股各 \(metres) 公尺的軌道，中間一座島式月台，照真實的\(name)站，從這一站往兩頭延伸。"
            )
        case .sides:
            return language.text(
                "Two tracks of \(metres) m with a platform on each side, as the real \(name), to extend both ways from here.",
                "兩股各 \(metres) 公尺的軌道，兩側各一座月台，照真實的\(name)站，從這一站往兩頭延伸。"
            )
        }
    }

    /// What the company still lacks to buy it with `balance`, or `nil`
    /// when it has enough (or there is nothing to buy).
    public func shortfallText(balance: Money, in language: DisplayLanguage) -> String? {
        guard let price, balance < price else { return nil }
        let short = (price - balance).moneyText
        return language.text("\(short) short of the price.", "還差 \(short)。")
    }
}

extension GameSession {
    /// How far past each end of the platform the track runs: 150 m, the
    /// room decision 351 leaves at an end for a crossover, enough for the
    /// player to join a turnout or trace on from either end.
    static let realStationRunOn = DemoRealLines.runOn

    /// The real line's systems at `suggestion` the track may follow, in
    /// the order the card lists them: the TRA's first, as the default.
    public func realStationSystems(of suggestion: RealStationSuggestion) -> [RealRailways.System] {
        let systems = suggestion.systems
        return systems.filter { $0.id == Self.traSystem } + systems.filter { $0.id != Self.traSystem }
    }

    /// Lays a real station out on a copy of the world and prices it
    /// (decision 400 A.8): along the line of `system` (by default the
    /// first of ``realStationSystems(of:)``), or why it cannot be bought
    /// here (another track in the way, land not bought, a grade too
    /// steep). Want of cash is not a problem here: the card weighs the
    /// price against the balance.
    public func realStationOffer(for suggestion: RealStationSuggestion, system wanted: String? = nil) -> RealStationOffer {
        let systems = realStationSystems(of: suggestion)
        let system = systems.first { $0.id == wanted } ?? systems[0]
        func refused(_ english: String, _ chinese: String) -> RealStationOffer {
            RealStationOffer(suggestion: suggestion, system: system, purchase: nil, metres: 0, price: nil, problem: language.text(english, chinese))
        }
        guard let traces = realRailwayTraces, let frame = RealWorldFrame(world: world),
              let real = suggestion.stations.first(where: { $0.system.id == system.id }) else {
            return refused("This map has no real railway here.", "這張地圖這裡沒有真實鐵路。")
        }
        let point = WorldVector(frame.worldPosition(latitude: real.coordinate.latitude, longitude: real.coordinate.longitude))
        guard let snap = traces.snap(point, within: DemoRealLines.stationReach, system: system.id) else {
            return refused("The real line's track could not be followed here.", "這裡沒辦法沿著真實鐵路鋪軌。")
        }

        // The platform as decision 295 makes it: a TRA station's real
        // length, the other systems' as long as their trains.
        let name = suggestion.name(in: language)
        let cars = system.id == Self.traSystem
            ? realPlatformCars(forStationNamed: name, at: point.plan) ?? Self.defaultPlatformCars
            : DemoRealLines.cars(ofSystem: system.id)
        let length = Double(Int64(cars) * world.platformCarLength)
        // Centred on the real station, the track on past both ends, across
        // the joins of the real line's pieces (a big station's line is
        // drawn in two, split at it); at the end of the real line, as much
        // as there is.
        let reach = length / 2 + Self.realStationRunOn
        let back = Array(traces.walk(from: snap.place, distance: reach, forward: false).reversed())
        let path = WorldPath(back + traces.walk(from: snap.place, distance: reach, forward: true).dropFirst())
        let at = WorldPath(back).length
        let lower = max(0, at - length / 2 - Self.realStationRunOn)
        let upper = min(path.length, at + length / 2 + Self.realStationRunOn)
        let low = min(max(lower, at - length / 2), upper - length)
        guard low >= lower else {
            return refused("The real line's track could not be followed here.", "這裡沒辦法沿著真實鐵路鋪軌。")
        }
        let ends = [path.point(at: lower).plan, path.point(at: upper).plan]
        guard ends.allSatisfy(world.bounds.contains) else {
            return refused("The track would run off this map.", "軌道會超出這張地圖。")
        }
        guard let plan = tracePlan(
            from: .point(ends[0]), to: .point(ends[1]), along: path.points(from: lower, to: upper),
            platforms: [(path.point(at: low), path.point(at: low + length))], onGround: true
        ) else {
            return refused("The real line's track could not be followed here.", "這裡沒辦法沿著真實鐵路鋪軌。")
        }
        guard !plan.stopped, !plan.stretches.isEmpty else {
            return refused(plan.problem ?? "The track cannot be laid here.", plan.problem ?? "這裡鋪不了軌道。")
        }
        guard let index = plan.platformStretches.first ?? nil else {
            return refused("The platform does not fit on the real line here.", "這裡的真實鐵路放不下月台。")
        }
        let middle = path.point(at: low + length / 2).plan
        let single = RealStationPurchase(
            stretches: plan.stretches, platform: index, name: name, at: middle, demand: newStationDemand(at: middle)
        )
        let metres = Int((upper - lower) / RealRailwayTraces.metre)

        // GameCore's answer and the price, on a funded copy.
        func priced(_ purchase: RealStationPurchase) throws(GameError) -> Money {
            var probe = world.pricingCopy()
            let opening = probe.economy.balance
            _ = try build(purchase, in: &probe)
            return opening - probe.economy.balance
        }
        // Decision 760: the second track as the real station has it, the
        // one track where it does not fit.
        let kind = RealStationPlatformKind.of(real)
        if kind != .single, let pair = secondTrack(
            beside: path, from: lower, to: upper, platform: low...(low + length), spacing: kind.spacing, single: single
        ), let price = try? priced(pair) {
            var offer = RealStationOffer(suggestion: suggestion, system: system, purchase: pair, metres: metres, price: price, problem: nil)
            offer.platforms = kind
            return offer
        }
        do throws(GameError) {
            let price = try priced(single)
            return RealStationOffer(suggestion: suggestion, system: system, purchase: single, metres: metres, price: price, problem: nil)
        } catch {
            return refused(error.playerMessage(in: .english), error.playerMessage(in: .traditionalChinese))
        }
    }

    /// `single` with a second track beside its own (decision 760): along
    /// `path` from `lower` to `upper`, 5 m to its side at the ends, as the
    /// demo lines' tracks stand, eased out to `spacing` by the platform's
    /// ends, its own platform beside the first's; `nil` where it cannot be
    /// laid.
    func secondTrack(
        beside path: WorldPath, from lower: Double, to upper: Double, platform: ClosedRange<Double>, spacing: Double,
        single: RealStationPurchase
    ) -> RealStationPurchase? {
        let base = HighSpeedDemo.trackOffset
        let ramp = max(RealRailwayTraces.metre, min(platform.lowerBound - lower, upper - platform.upperBound))
        let beside = path.offset(from: lower, to: upper, by: spacing - base, ramp: ramp, from: base)
        let start = beside.project(path.point(at: platform.lowerBound))
        let end = beside.project(path.point(at: platform.upperBound))
        let ends = [beside.point(at: 0).plan, beside.point(at: beside.length).plan]
        guard ends.allSatisfy(world.bounds.contains), let plan = tracePlan(
            from: .point(ends[0]), to: .point(ends[1]), along: beside.points,
            platforms: [(beside.point(at: start), beside.point(at: end))], onGround: true
        ), !plan.stopped, !plan.stretches.isEmpty, let index = plan.platformStretches.first ?? nil else { return nil }
        return RealStationPurchase(
            stretches: single.stretches, platform: single.platform, secondStretches: plan.stretches, secondPlatform: index,
            name: single.name, at: single.at, demand: single.demand
        )
    }

    /// Opens the card for `suggestion`, laid out and priced now.
    public func offerRealStation(_ suggestion: RealStationSuggestion) {
        shownRealStationOffer = realStationOffer(for: suggestion)
    }

    /// Lays the offer out again along the line of `system`.
    public func chooseRealStationSystem(_ system: String) {
        guard let shown = shownRealStationOffer, shown.system.id != system else { return }
        shownRealStationOffer = realStationOffer(for: shown.suggestion, system: system)
    }

    /// Buys `offer` as one command (``PlayerCommand/buyRealStation(_:)``),
    /// closing the card, with the feedback a station built by hand gets.
    /// Whether it was bought; a refusal says why.
    @discardableResult
    public func buyRealStation(_ offer: RealStationOffer) -> Bool {
        guard let purchase = offer.purchase else {
            message = StatusMessage(kind: .failure, text: offer.problem ?? "")
            return false
        }
        let name = purchase.name, metres = offer.metres
        let made = perform(.buyRealStation(purchase)) { _, _, _ in
            language.text(
                "Bought \(name) station with \(metres) m of track. Lay track on from either end.",
                "已收購\(name)站和 \(metres) 公尺的軌道。可以從兩頭接著鋪軌。"
            )
        }
        guard made?.station != nil else { return false }
        shownRealStationOffer = nil
        networkEdgePoint = nil
        notePutUp(at: purchase.at)
        return true
    }

    /// Builds `purchase` in `world`: the track, then the station and its
    /// platform; all of it or, throwing, none, the caller's copy dropped.
    func build(_ purchase: RealStationPurchase, in world: inout GameWorld) throws(GameError) -> Station {
        guard purchase.stretches.indices.contains(purchase.platform),
              purchase.secondPlatform.map(purchase.secondStretches.indices.contains) ?? purchase.secondStretches.isEmpty
        else { throw .invalidTrackGeometry }
        func lay(_ stretches: [PlayerCommand.TrackStretch]) throws(GameError) -> [TrackEdgeID] {
            var previous: TrackNodeID?
            var edges: [TrackEdgeID] = []
            for stretch in stretches {
                let built = try stretch.starting(at: previous).build(in: &world, heights: heights)
                edges.append(built.edge)
                previous = built.to
            }
            return edges
        }
        var platforms = [try lay(purchase.stretches)[purchase.platform]]
        if let second = purchase.secondPlatform {
            platforms.append(try lay(purchase.secondStretches)[second])
        }
        let station = try world.buildStation(named: purchase.name, at: purchase.at)
        if world.accounts.mode == .management, !world.landDemand {
            try world.setStationDemand(station.id, to: purchase.demand)
        }
        for edge in platforms {
            guard let length = world.network.edge(edge)?.length else { throw .unknownTrackEdge(edge) }
            try world.addTrackPlatform(station.id, on: edge, from: 0, to: length)
        }
        Self.readLand(roundStationsOf: &world, population: population, places: places, water: water, coverage: coverage)
        return world.station(id: station.id) ?? station
    }
}

extension RealRailwayTraces {
    /// The points along the real lines from `place` on for `distance`
    /// world units, the way `forward` goes along its line (or back), and
    /// on across the join at the line's end to the next piece of it, as
    /// far as the lines go; `place`'s point first.
    func walk(from place: Place, distance: Double, forward: Bool) -> [WorldVector] {
        var line = place.line, along = place.along, forward = forward, left = distance
        var points = [lines[line].path.point(at: along)]
        var visited: Set<Int> = [line]
        while left > 0 {
            let path = lines[line].path
            let end = forward ? path.length : 0
            let step = min(left, abs(end - along))
            let stop = forward ? along + step : along - step
            let piece = path.points(from: min(along, stop), to: max(along, stop))
            points += (forward ? piece : piece.reversed()).dropFirst()
            left -= step
            // The next piece: a join from this line's end, or one from
            // another line's end to here.
            let next = links.first { $0.a == Place(line: line, along: end) }.map(\.b)
                ?? links.first { $0.b.line == line && abs($0.b.along - end) <= Self.joinReach }.map(\.a)
            guard left > 0, let next, visited.insert(next.line).inserted else { break }
            line = next.line
            along = next.along
            forward = along < lines[line].path.length / 2
        }
        return points
    }
}
