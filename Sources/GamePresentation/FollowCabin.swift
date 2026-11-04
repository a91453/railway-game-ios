import GameCore

// Decision 583 (CABLEFOLLOW, 2026-11-04): the 3D map's camera following a
// cabin of a player's cable car, after following a bus (decision 400's
// FOLLOWBUS, `FollowBus.swift`). Cabins are not GameCore things: where each
// one is follows from the cable car and the clock (``CablewayCabins``), so
// the session keeps only the cabin's ID (``CabinID``) and reads the rest.
// Presentation only: nothing here changes the world, the save or a golden
// value.

/// What the follow bar shows of the cabin followed, read through
/// ``GameSession/cabinFollowBar``.
public struct CabinFollowFacts: Equatable, Sendable {
    public var cabin: CabinID
    /// "Cable car 1".
    public var name: String
    /// "Crystal cabin" for one with a glass floor, else `nil`.
    public var kind: String?
    /// "At Station 1 · Next: Station 2", or "Next: Station 2".
    public var stopText: String
    /// "To Station 4" or "Back to Station 1".
    public var directionText: String
    public var runningSpeed: GameSpeed?
}

extension GameWorld {
    /// Whether cabin `id` runs now: its cable car is there, runs at this
    /// hour, and has a cabin of that number.
    public func cabinRuns(_ id: CabinID) -> Bool {
        guard let cableway = cableway(id: id.cableway), id.number >= 0, id.number < CablewayCabins.count(of: cableway) else { return false }
        return CablewayCabins.runs(id.cableway, in: self, at: clock.now)
    }

    /// The cabin of cable car `id` to follow: the one that left its first
    /// stop last (the card's follow button); `nil` while it stands still.
    public func cabinToFollow(on id: CablewayID) -> CabinID? {
        guard let cableway = cableway(id: id), CablewayCabins.runs(id, in: self, at: clock.now) else { return nil }
        let loop = CablewayCabins.loopSeconds(of: cableway)
        let second = clock.now.seconds
        let number = (0..<CablewayCabins.count(of: cableway)).min { a, b in
            func at(_ n: Int) -> Int64 { ((second - Int64(n) * Cableway.cabinIntervalSeconds) % loop + loop) % loop }
            return at(a) < at(b)
        }
        return number.map { CabinID(cableway: id, number: $0) }
    }

    /// A cabin of cable car `id` out over its longest span, a crystal one
    /// when one is there, the nearest the span's middle first (the
    /// screenshots' window view, decision 583); `nil` while it stands
    /// still or none is out on that span.
    public func cabinOverLongestSpan(on id: CablewayID) -> CabinID? {
        guard let cableway = cableway(id: id), CablewayCabins.runs(id, in: self, at: clock.now),
              let longest = cableway.legMetres.indices.max(by: { cableway.legMetres[$0] < cableway.legMetres[$1] }) else { return nil }
        let second = Double(clock.now.seconds)
        let out = (0..<CablewayCabins.count(of: cableway)).compactMap { number -> (number: Int, offMiddle: Double)? in
            guard case .span(let leg, let share, _) = CablewayCabins.glide(of: number, on: cableway, atSecond: second), leg == longest else { return nil }
            return (number, abs(share - 0.5))
        }
        let best = out.min { a, b in
            let crystalA = CablewayCabins.isCrystal(a.number), crystalB = CablewayCabins.isCrystal(b.number)
            return crystalA != crystalB ? crystalA : a.offMiddle < b.offMiddle
        }
        return best.map { CabinID(cableway: id, number: $0.number) }
    }

    /// The text for the bar: where a followed cabin is and goes. A real
    /// cable car's stops take their real names (Taipei Zoo, Zhinan
    /// Temple…); others are counted among those that board (the angle
    /// stations are passed through), the one that meets a railway station
    /// taking its name.
    func cabinFollowFacts(of id: CabinID, in language: DisplayLanguage) -> CabinFollowFacts? {
        guard cabinRuns(id), let cableway = cableway(id: id.cableway) else { return nil }
        let boarding = cableway.stops.indices.filter { cableway.stops[$0].boards }
        let real = RealCableway.matching(cableway, in: self)
        func name(_ stop: Int) -> String {
            if let real, real.stops.indices.contains(stop) {
                let named = real.stops[stop]
                return language.text("\(named.englishName) station", "\(named.name)站")
            }
            if let transfer = cableway.transfer, transfer.stop == stop, let station = station(id: transfer.station) {
                return language.text("\(station.name) station", "\(station.name)站")
            }
            let number = (boarding.firstIndex(of: stop) ?? 0) + 1
            return language.text("Station \(number)", "第 \(number) 站")
        }
        let glide = CablewayCabins.glide(of: id.number, on: cableway, atSecond: Double(clock.now.seconds))
        let stops = CablewayCabins.stops(of: glide, on: cableway)
        let outbound: Bool
        switch glide {
        case .span(_, _, let way): outbound = way
        case .station(_, _, _, let leaves): outbound = leaves
        }
        // The next stop that boards, the way it goes.
        var next = stops.next
        while !cableway.stops[next].boards, next > 0, next < cableway.stops.count - 1 { next += outbound ? 1 : -1 }
        let nextText = language.text("Next: \(name(next))", "下一站：\(name(next))")
        let stopText: String
        if let at = stops.at, cableway.stops[at].boards {
            stopText = language.text("At \(name(at))", "停在\(name(at))") + " · " + nextText
        } else {
            stopText = nextText
        }
        let end = outbound ? cableway.stops.count - 1 : 0
        let direction = outbound ? language.text("To \(name(end))", "往\(name(end))") : language.text("Back to \(name(end))", "回\(name(end))")
        return CabinFollowFacts(
            cabin: id, name: CablewayText.name(id.cableway, in: language),
            kind: CablewayCabins.isCrystal(id.number) ? language.text("Crystal cabin", "水晶吊廂") : nil,
            stopText: stopText, directionText: direction, runningSpeed: clock.isPaused ? nil : clock.speed)
    }
}

extension GameSession {
    public var isFollowingCabin: Bool { followedCabinID != nil }

    /// Starts following cabin `id` if it runs; never changes the world.
    public func followCabin(_ id: CabinID) {
        guard world.cabinRuns(id) else { return }
        followedTrainID = nil
        followedBusID = nil
        followedCabinID = id
        updateFollowSounds()
    }

    /// Follows the cabin of cable car `id` that left its first stop last
    /// (the card's follow button). While it stands still, nothing changes.
    public func followCabin(on id: CablewayID) {
        guard let cabin = world.cabinToFollow(on: id) else { return }
        followCabin(cabin)
    }

    /// Whether cable car `id` has a cabin running to follow.
    public func hasCabinToFollow(on id: CablewayID) -> Bool { world.cabinToFollow(on: id) != nil }

    /// Works ``cabinFollowBar`` out again; set only when it differs.
    func refreshCabinFollow() {
        let facts = followedCabinID.flatMap { world.cabinFollowFacts(of: $0, in: language) }
        if facts != cabinFollowBar { cabinFollowBar = facts }
    }

    /// After a step or an edit: a cabin whose cable car is gone or stops
    /// for the day is let go, and the camera goes back to the map's own
    /// view; one running has its bar brought up to date.
    func keepFollowingCabin() {
        guard let id = followedCabinID else { return }
        guard world.cabinRuns(id) else {
            followedCabinID = nil
            return
        }
        refreshCabinFollow()
    }
}
