import GameCore

// Decision 1024 (the owner, 2026-11-27: 「你鋪設完 照理說 路線設定 在跳出去」):
// laying track and making a line were two places, Build and Lines, and a
// player in a hurry had to remember to leave one for the other. Once the
// track tools have built two stations that track joins, the build card
// offers the line between them: one button leaves Build, opens Lines and
// starts the new line with its ends picked, the stations between found
// along the track as a line picked by hand finds them (decision 100).
//
// The reference has nothing to port: `Ci/` and MapBuilder make a line
// from its own menu, after the track.

/// A line the build card offers between stations just built (decision
/// 1024): its two ends, in the order they were built, and how many
/// stations the track between them passes, the two counted.
public struct LineFromBuiltTrack: Equatable, Sendable {
    public let from: StationID
    public let to: StationID
    public let stops: Int

    /// The card's line: the stations it joins.
    public func title(from: String, to: String, in language: DisplayLanguage) -> String {
        language.text("Make a line: \(from) → \(to)", "建立路線：\(from) → \(to)")
    }

    /// Under it: how many stations, and what the button does.
    public func detail(in language: DisplayLanguage) -> String {
        language.text(
            "Your new stations are joined by track. Open Lines with this line ready, \(stops) stations.",
            "新蓋的車站已有軌道相連。打開「路線」，這條路線已排好，共 \(stops) 站。"
        )
    }

    /// The button.
    public static func buttonTitle(in language: DisplayLanguage) -> String {
        language.text("Make this line", "用這段軌道建路線")
    }
}

extension GameSession {
    /// How many of the stations the track tools built last are looked at
    /// for a line between two of them: four, six pairs, each a line's
    /// journey worked out on a copy of the world, only when something is
    /// built.
    static let builtStationsKept = 4

    /// Decision 1024: the line the build card offers, or `nil`: none
    /// found, the tutorial leads (its own steps make the first line), or
    /// the newest station built is already on a line (the line was made,
    /// or the station added to one).
    public var lineFromBuiltTrack: LineFromBuiltTrack? {
        guard tutorial == nil, let offer = builtTrackLine,
              world.station(id: offer.from) != nil, world.station(id: offer.to) != nil,
              let newest = stationsBuiltWithTrackTools.last,
              !world.lines.contains(where: { $0.stops.contains(newest) })
        else { return nil }
        return offer
    }

    /// Records station `id`, just built by the track tools, and looks for
    /// the line to offer again.
    func noteStationBuiltWithTrackTools(_ id: StationID) {
        stationsBuiltWithTrackTools.removeAll { $0 == id }
        stationsBuiltWithTrackTools.append(id)
        if stationsBuiltWithTrackTools.count > Self.builtStationsKept {
            stationsBuiltWithTrackTools.removeFirst(stationsBuiltWithTrackTools.count - Self.builtStationsKept)
        }
        refreshLineFromBuiltTrack()
    }

    /// Works out ``builtTrackLine`` again: of every two stations built
    /// last that a line can be driven between, the two whose line passes
    /// the most stations; the later built on a tie. Track built since can
    /// join two that were apart.
    func refreshLineFromBuiltTrack() {
        let built = stationsBuiltWithTrackTools.filter { world.station(id: $0) != nil }
        guard built.count >= 2 else {
            if builtTrackLine != nil { builtTrackLine = nil }
            return
        }
        var best: LineFromBuiltTrack?
        for (i, from) in built.enumerated() {
            for to in built[(i + 1)...] {
                guard let route = world.stationsAlongTrack(through: [from, to]) else { continue }
                if route.count >= (best?.stops ?? 0) {
                    best = LineFromBuiltTrack(from: from, to: to, stops: route.count)
                }
            }
        }
        if best != builtTrackLine { builtTrackLine = best }
    }

    /// Decision 1024: starts the offered line: a new draft from one end
    /// to the other, picking on the map on, so a station tapped next adds
    /// to it as a line picked by hand. A draft already begun is dropped.
    /// Never changes the world. The app then leaves Build and opens Lines.
    public func startLineFromBuiltTrack() {
        guard let offer = lineFromBuiltTrack else { return }
        clearLineDraft()
        lineDraft = [offer.from, offer.to]
        refreshLineDraftRoute()
        isPickingLineStops = true
        let from = world.station(id: offer.from)?.name ?? ""
        let to = world.station(id: offer.to)?.name ?? ""
        message = StatusMessage(
            kind: .success,
            text: language.text(
                "The line from \(from) to \(to) is ready. Check its stops and create it.",
                "已排好\(from)到\(to)的路線。看過停靠站後按「建立路線」。"
            )
        )
    }
}
