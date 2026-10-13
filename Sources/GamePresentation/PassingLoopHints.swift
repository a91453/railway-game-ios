import GameCore

// Two follow-ups of the passing-loop tool (decision 204, later).
//
// 1. Its signal station into the lines. The probe (decision 204 point 3)
//    found that a line counts only its stops as places to pass: a loop it
//    runs through without stopping still leaves one single-track section,
//    one train. So when a loop is built on the way of lines that do not
//    stop there, the tool asks once whether to add it to their stops,
//    each between the two stops it lies between. Not on its own: a stop
//    there costs each train a dwell, and the probe found that counting a
//    loop a line does not stop at would change the reference model and
//    the headways of lines already running. A line with patterns or route
//    choices names its legs by stop number, which an inserted stop would
//    shift, so it is left for the player to add by hand.
//
// 2. A one-time card the first time a line's train waits on single track
//    for another (the owner chose a card over a tutorial step, NEXT_PRIORITIES
//    Q21; as the route card of #510, ``RouteHint``): the passing-loop tool
//    is the cure. Seen once, it never comes again: the device keeps that,
//    not the save.

/// The lines a new passing loop lies on the way of, offered its signal
/// station as a stop.
public struct PassingLoopOffer: Hashable, Sendable {
    /// Where a line would stop at it: before stop `index`.
    public struct Stop: Hashable, Sendable {
        public let line: LineID
        public let index: Int
    }

    public let station: StationID
    /// The lines it can be added to, in ascending line order.
    public let stops: [Stop]
    /// Lines that run through it but whose stops are left to the player
    /// (patterns or route choices).
    public let byHand: [LineID]

    public static func title(in language: DisplayLanguage) -> String {
        language.text("Add the loop to the lines?", "把號誌站加進路線？")
    }

    public func message(in world: GameWorld, language: DisplayLanguage) -> String {
        let name = world.station(id: station)?.name ?? ""
        func names(_ lines: [LineID]) -> String {
            lines.map { world.line(id: $0)?.name ?? "#\($0.rawValue)" }.joined(separator: language.text(", ", "、"))
        }
        var text = language.text(
            "\(names(stops.map(\.line))) run through \(name). Its trains pass each other there only if it is one of the line's stops; each train then stops there briefly.",
            "\(names(stops.map(\.line))) 經過\(name)。要把它列為停靠站，列車才會在這裡交會；每班車會在這裡短暫停車。"
        )
        if !byHand.isEmpty {
            text += language.text(
                " \(names(byHand)) have patterns or route choices: add it to their stops by hand.",
                "\(names(byHand)) 有停車模式或進路設定，請手動加。"
            )
        }
        return text
    }

    public static func addButton(in language: DisplayLanguage) -> String {
        language.text("Add to Lines", "加進路線")
    }

    public static func skipButton(in language: DisplayLanguage) -> String {
        language.text("Not Now", "先不用")
    }
}

extension GameWorld {
    /// The lines whose base service runs over a platform of `station`
    /// without stopping there, and before which stop each would stop at it:
    /// the leg (out, or round a ring) whose path takes one of its
    /// platforms' edges. A line with patterns or route choices goes in
    /// `byHand` instead.
    public func passingLoopOffer(for station: StationID) -> PassingLoopOffer {
        let edges = Set(trackPlatforms(of: station).map(\.edge))
        var stops: [PassingLoopOffer.Stop] = []
        var byHand: [LineID] = []
        for line in lines.sorted(by: { $0.id < $1.id }) where !line.stops.contains(station) {
            guard let journey = lineJourney(line.id) else { continue }
            // The legs out: from each stop to the next (a ring's whole lap).
            let out = line.isRing ? journey.legs : journey.legs.filter { $0.to > $0.from }
            guard let leg = out.first(where: { $0.path.traversals.contains { edges.contains($0.edge) } }) else { continue }
            if !line.patterns.isEmpty || !line.routePreferences.isEmpty {
                byHand.append(line.id)
            } else {
                stops.append(.init(line: line.id, index: leg.to == 0 ? line.stops.count : leg.to))
            }
        }
        return PassingLoopOffer(station: station, stops: stops, byHand: byHand)
    }
}

extension GameSession {
    /// After a passing loop is built: the offer of its signal station to
    /// the lines it lies on, if any do.
    func offerPassingLoop(_ station: StationID) {
        let offer = world.passingLoopOffer(for: station)
        passingLoopOffer = offer.stops.isEmpty ? nil : offer
    }

    /// Adds the offered signal station to each line's stops, where it lies
    /// between them, through `GameWorld.setLineStops(_:to:)`; a line that
    /// refuses keeps its stops and is named.
    public func acceptPassingLoopOffer() {
        guard let offer = passingLoopOffer else { return }
        passingLoopOffer = nil
        let name = world.station(id: offer.station)?.name ?? ""
        var added: [String] = []
        var refused: [String] = []
        for stop in offer.stops {
            guard let line = world.line(id: stop.line), stop.index <= line.stops.count, !line.stops.contains(offer.station) else { continue }
            do throws(GameError) {
                try performCommand(.edit(.setLineStops(line.id, LineStopEditing.inserting(offer.station, at: stop.index, into: line.stops))))
                added.append(line.name)
            } catch {
                refused.append(line.name + language.text(" (\(error.playerMessage(in: language)))", "（\(error.playerMessage(in: language))）"))
            }
        }
        let separator = language.text(", ", "、")
        var text = added.isEmpty ? "" : language.text(
            "\(name) is now a stop of \(added.joined(separator: separator)).",
            "\(name) 已加進 \(added.joined(separator: separator)) 的停靠站。"
        )
        if !refused.isEmpty {
            text += language.text(" Not added: ", "沒有加進：") + refused.joined(separator: separator) + language.text(".", "。")
        }
        message = StatusMessage(kind: refused.isEmpty ? .success : .failure, text: text)
        endFollowIfGone()
    }

    /// The offer was declined.
    public func dismissPassingLoopOffer() {
        passingLoopOffer = nil
    }
}

/// The one-time card about passing loops: the first time a line's train
/// waits on single track for another.
public enum PassingLoopHint {
    /// The device's setting that says the card has been seen
    /// (`@AppStorage`).
    public static let seenKey = "hints.passingLoop.seen"

    public static func title(in language: DisplayLanguage) -> String {
        language.text("Trains waiting on single track", "列車在單線上等車")
    }

    /// What the card says of line `line`'s waiting train.
    public static func message(line: LineID, in world: GameWorld, language: DisplayLanguage) -> String {
        let name = world.line(id: line)?.name ?? ""
        return [
            language.text(
                "A train of \(name) is waiting for another on single track: only one can use it at a time.",
                "\(name) 的列車在單線上等另一列車：一段單線一次只能走一列。"
            ),
            language.text(
                "A passing loop lets them pass halfway. In Network, choose Loop and tap the single track: it adds a second track there with a signal station.",
                "加一條待避線，兩列車就能在中途交會。在「路網」選「待避」，點一段單線，就會在旁邊加第二條軌道和號誌站。"
            ),
            language.text(
                "Then add the signal station to the line's stops so its trains pass there.",
                "再把號誌站加進路線的停靠站，列車才會在那裡交會。"
            ),
        ].joined(separator: "\n\n")
    }

    public static func showButton(in language: DisplayLanguage) -> String {
        language.text("Add a Passing Loop", "加待避線")
    }

    public static func dismissButton(in language: DisplayLanguage) -> String {
        language.text("Got It", "知道了")
    }

    /// The line of the first train in `waits` (trains waiting for others,
    /// ascending) that waits for another train, not in a deadlock, on a
    /// line with a leg on single track (``GameWorld/lineTrackCounts(_:)``
    /// of 1): where a passing loop would help. `nil` for none.
    public static func waitingLine(_ waits: [TrafficOverlay.Wait], in world: GameWorld) -> LineID? {
        var single: [LineID: Bool] = [:]
        for wait in waits where !wait.isDeadlocked {
            guard let line = world.lines.first(where: { $0.trains.contains(wait.train) }) else { continue }
            let isSingle = single[line.id] ?? (world.lineTrackCounts(line.id) ?? []).contains(1)
            single[line.id] = isSingle
            if isSingle { return line.id }
        }
        return nil
    }
}

extension GameSession {
    /// Looks at the trains waiting now for the first line waiting on single
    /// track (``PassingLoopHint/waitingLine(_:in:)``): the card, unless the
    /// tutorial is on or another card is waiting.
    public func watchPassingLoopHint() {
        guard tutorial == nil, passingLoopHint == nil, routeHint == nil, passingLoopOffer == nil else { return }
        let waits = trafficOverlay.waits
        guard !waits.isEmpty else { return }
        passingLoopHint = PassingLoopHint.waitingLine(waits, in: world)
    }

    /// The card's button: the network tool's passing-loop mode.
    public func showPassingLoopTool() {
        passingLoopHint = nil
        selectTool(.network)
        setNetworkMode(.passingLoop)
    }

    /// The card was answered.
    public func dismissPassingLoopHint() {
        passingLoopHint = nil
    }
}
