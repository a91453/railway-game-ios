import GameCore

// Decision 649: the list of real lines for sale (the lines panel's "Real
// lines for sale"), nearest first, with those the company's land does not
// reach greyed out and a line saying how far. The check is the purchase's
// own (``RealLineLaying/landCheckOnly``: the tiles under the line must
// touch the land owned, ``RealLineAcquisition/buyingOrder(of:owned:)``),
// stopped there, so it needs no price and no layout of the line.

/// Why a real line for sale cannot be bought from the land owned.
public struct RealLineLandNote: Hashable, Sendable {
    /// How far the line is from the company's land, in metres.
    public let metres: Int64

    public func text(in language: DisplayLanguage) -> String {
        let km = max(1, (metres + 500) / 1_000)
        return language.text(
            "Your land does not reach it, about \(km) km away. Expand the map toward it first.",
            "和你的地不相連，約 \(km) 公里外。先擴建地圖。"
        )
    }
}

/// A row of the list.
public struct RealLineListing: Hashable, Sendable {
    public let line: RealBranchLine
    /// From the middle of the company's land (``GameSession/realLineFocus``)
    /// to its nearest station, in metres.
    public let metres: Int64
    /// Set when the line cannot be bought from the land owned.
    public let note: RealLineLandNote?

    public var isBuyable: Bool { note == nil }
}

extension GameSession {
    /// Where the list measures from: the middle of the land owned on a map
    /// bought tile by tile, else of the map.
    public var realLineFocus: PlanPoint {
        if let owned = world.mapExpansion?.owned, !owned.isEmpty {
            let length = Double(MapExpansion.tileLength)
            let x = owned.reduce(0.0) { $0 + (Double($1.column) + 0.5) * length } / Double(owned.count)
            let y = owned.reduce(0.0) { $0 + (Double($1.row) + 0.5) * length } / Double(owned.count)
            return PlanPoint(x: Int64(x), y: Int64(y))
        }
        return PlanPoint(x: world.bounds.width / 2, y: world.bounds.height / 2)
    }

    /// ``buyableRealLines`` nearest ``realLineFocus`` first (ties by id),
    /// each with why it cannot be bought yet, if so.
    public var realLineListings: [RealLineListing] {
        guard let railways, let frame = RealWorldFrame(world: world) else {
            return buyableRealLines.map { RealLineListing(line: $0, metres: 0, note: nil) }
        }
        let focus = WorldVector(realLineFocus)
        return buyableRealLines.map { line -> RealLineListing in
            let nearest = line.stops.compactMap {
                RealLineLaying.realPoint(of: $0, system: line.system, railways: railways, frame: frame)
            }.map { ($0 - focus).length }.min() ?? 0
            let metres = Int64((nearest / RealLineAcquisition.metre).rounded())
            return RealLineListing(line: line, metres: metres, note: realLineOutOfReach.contains(line.id) ? RealLineLandNote(metres: metres) : nil)
        }.sorted { ($0.metres, $0.line.id) < ($1.metres, $1.line.id) }
    }

    /// Review L14-5: the panel shows the list (`true`, as it appears) or
    /// no longer does. While it shows, the list is checked again whenever
    /// the land owned changes (the map expanded with the panel open), not
    /// only as it opens.
    public func showRealLineList(_ shown: Bool) {
        realLineListShown = shown
        if shown { refreshRealLineAvailability() }
    }

    /// Works out, off the main actor, which of the lines for sale the land
    /// owned does not reach, nearest first; the panel calls it as it opens
    /// and the notes arrive in ``realLineOutOfReach``. Worked out again only
    /// when the commands or the railways have changed since.
    ///
    /// Review L14-5: each line's answer arrives as it is found, nearest
    /// first, so a line the land has come to reach is not left greyed out
    /// by the check before until the whole list is done.
    public func refreshRealLineAvailability() {
        let key = [commandRevision, railwaysRevision]
        realLineCheckedLand = world.mapExpansion?.owned
        guard realLineAvailabilityKey != key else { return }
        realLineAvailabilityKey = key
        realLineAvailabilityTask?.cancel()
        guard world.mapExpansion != nil else {
            realLineOutOfReach = []
            return
        }
        var laying = realLineLaying
        laying.landCheckOnly = true
        let lines = realLineListings.map(\.line)
        let checking = laying
        realLineAvailabilityTask = Task {
            var failed: Set<String> = []
            for line in lines {
                let out = await Task.detached(priority: .utility) { () -> Bool in
                    let offer = checking.offer(for: line)
                    return offer.acquisition == nil && offer.problem == Self.landProblem(in: checking.language)
                }.value
                guard !Task.isCancelled, realLineAvailabilityKey == key else { return }
                if out {
                    failed.insert(line.id)
                    realLineOutOfReach.insert(line.id)
                } else {
                    realLineOutOfReach.remove(line.id)
                }
            }
            realLineOutOfReach = failed
            realLineAvailabilityTask = nil
        }
    }

    /// Waits for ``refreshRealLineAvailability()`` (for the tests).
    func realLineAvailabilityChecked() async {
        await realLineAvailabilityTask?.value
    }

    /// The refusal for land not touching the company's.
    nonisolated static func landProblem(in language: DisplayLanguage) -> String {
        language.text(
            "The land this line crosses does not touch yours. Use Expand Map to buy up to the line first, then buy it.",
            "這條線經過的地和你的地不相連。先用「擴建地圖」買到這條線旁邊，再收購。"
        )
    }
}
