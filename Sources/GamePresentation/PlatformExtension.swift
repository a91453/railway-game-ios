import GameCore

// Lengthening a platform where it stands (ARCHITECTURE decision 687): a
// player whose trains grew from 10 cars to 12 had to remove the platform
// and build it again. The station's panel now offers each platform's
// longer lengths, by cars as the platform tool counts them
// (``GameSession/platformCars``); GameCore lengthens it
// (`GameWorld.extendTrackPlatform(_:on:from:toStart:end:)`). The owner's
// reference projects have nothing to port.

/// A platform lengthened to a whole number of cars: the stretch of its
/// edge it would then take.
public struct PlatformExtension: Hashable, Sendable {
    public let platform: TrackPlatform
    public let cars: Int
    /// The stretch along its edge as the edge lies now. Past the edge's
    /// ends when ``station`` is set and a turnout must move (decision 691).
    public let start: Int64
    public let end: Int64
    /// Decision 691: set when the platform stands between a station's two
    /// turnouts, where lengthening it is the station's
    /// (`GameWorld.extendPlatformLoop(_:on:from:toStart:end:)`): what it
    /// would do.
    public let station: PlatformLoopExtensionPreview?

    public var length: Int64 { end - start }
}

extension GameWorld {
    /// How many whole cars stand at `platform`, as the platform tool
    /// counts them (``platformCarLength``).
    func platformCars(of platform: TrackPlatform) -> Int {
        Int(platform.length / platformCarLength)
    }

    /// Decision 687: `platform` lengthened to `cars` cars, or `nil` when it
    /// is that long already or has no room for it
    /// (`GameWorld.trackPlatformRoom(of:)`). Half the new length goes to
    /// each end; what one end has no room for goes to the other, so the
    /// platform stays where it is and grows towards the room there is.
    ///
    /// Decision 691: between a station's two turnouts the room is also
    /// what the turnouts can move out (`GameWorld.platformLoopRoom(of:)`),
    /// used only when the platform's own edge has not enough, and the
    /// station's platform on the track beside grows with it.
    func platformExtension(of platform: TrackPlatform, toCars cars: Int, heights: HeightGrid? = nil) -> PlatformExtension? {
        guard let room = trackPlatformRoom(of: platform) else { return nil }
        let extra = Int64(cars) * platformCarLength - platform.length
        let loop = platformLoopRoom(of: platform)
        guard let growth = Self.platformGrowth(extra, before: room.before, after: room.after)
            ?? loop.flatMap({ Self.platformGrowth(extra, before: room.before + $0.before, after: room.after + $0.after) })
        else { return nil }
        let start = platform.start - growth.before, end = platform.end + growth.after
        guard loop != nil else { return PlatformExtension(platform: platform, cars: cars, start: start, end: end, station: nil) }
        // Decision 124: the ground beside the line may not be read yet.
        var surveyed = self
        let ground = platformLoopExtensionGround(platform.station, on: platform.edge, from: platform.start, toStart: start, end: end)
        guard (try? surveyed.readGround(under: ground, from: heights)) != nil,
              let preview = try? surveyed.platformLoopExtensionPreview(platform.station, on: platform.edge, from: platform.start, toStart: start, end: end)
        else { return nil }
        return PlatformExtension(platform: platform, cars: cars, start: start, end: end, station: preview)
    }

    /// The lengths `platform` could be lengthened to, shortest first: each
    /// whole number of cars past its own, up to the longest train
    /// (``Train/maximumCars``) and the room it has.
    func platformExtensions(of platform: TrackPlatform, heights: HeightGrid? = nil) -> [PlatformExtension] {
        let own = platformCars(of: platform)
        guard own < Train.maximumCars else { return [] }
        return ((own + 1)...Train.maximumCars).compactMap { platformExtension(of: platform, toCars: $0, heights: heights) }
    }
}

extension GameSession {
    /// "10 cars · 200 m": how long `platform` is now.
    public func platformLengthText(of platform: TrackPlatform) -> String {
        "\(Train.carsText(world.platformCars(of: platform), in: language)) · \(NetworkBuilding.lengthText(platform.length, in: language))"
    }

    /// The lengths `platform` could be lengthened to
    /// (``extendPlatform(_:)``), each "12 cars · 240 m" with how much is
    /// added; a platform costs nothing, so neither does more of it.
    /// Decision 691: between a station's turnouts it also says when the
    /// platform beside grows with it, and what moving the turnouts out
    /// costs. Kept until the next command (each is a dry run on the
    /// track; a tick leaves the track alone).
    public func platformExtensionMenuChoices(for platform: TrackPlatform) -> [MenuChoice<PlatformExtension>] {
        if let memo = platformExtensionMenuMemo[platform], memo.revision == commandRevision, memo.language == language { return memo.choices }
        let choices = world.platformExtensions(of: platform, heights: heights).map { longer in
            let added = NetworkBuilding.lengthText(longer.length - platform.length, in: language)
            var parts = [language.text("Adds \(added)", "加長 \(added)")]
            if let station = longer.station {
                if station.platforms == 2 {
                    parts.append(language.text("both platforms", "兩座月台一起"))
                } else if station.platforms > 2 {
                    parts.append(language.text("\(station.platforms) platforms", "\(station.platforms) 座月台一起"))
                }
                if station.movesTurnouts { parts.append(language.text("moves the turnouts out", "轉轍器往外移")) }
            }
            let cost = longer.station?.cost ?? .zero
            parts.append(cost > .zero ? cost.moneyText : language.text("free", "免費"))
            return MenuChoice(
                id: longer,
                title: "\(Train.carsText(longer.cars, in: language)) · \(NetworkBuilding.lengthText(longer.length, in: language))",
                detail: parts.joined(separator: " · ")
            )
        }
        platformExtensionMenuMemo = platformExtensionMenuMemo.filter { $0.value.revision == commandRevision && $0.value.language == language }
        platformExtensionMenuMemo[platform] = (commandRevision, language, choices)
        return choices
    }

    /// Why ``platformExtensionMenuChoices(for:)`` offers nothing.
    public var platformExtensionNoRoomText: String {
        language.text(
            "No room to lengthen: the track ends, slopes or meets another platform here, or the turnouts cannot move farther out.",
            "沒有空間加長：這裡是軌道的盡頭、坡道、已經有別的月台，或轉轍器無法再往外移。"
        )
    }

    /// Lengthens a platform as `longer` says, where it stands.
    public func extendPlatform(_ longer: PlatformExtension) {
        let name = world.station(id: longer.platform.station)?.name ?? "#\(longer.platform.station.rawValue)"
        let cars = Train.carsText(longer.cars, in: language)
        let length = NetworkBuilding.lengthText(longer.length, in: language)
        guard let station = longer.station else {
            perform(.extendPlatform(longer.platform, start: longer.start, end: longer.end)) { _, _, _ in
                language.text(
                    "\(name)’s platform now takes \(cars) (\(length)).",
                    "\(name) 的月台已加長到 \(cars)（\(length)）。"
                )
            }
            return
        }
        let balance = world.economy.balance
        perform(.extendPlatformLoop(longer.platform, start: longer.start, end: longer.end)) { _, _, world in
            let cost = Money(balance.amount - world.economy.balance.amount)
            let paid = cost > .zero ? language.text(", for \(cost.moneyText)", "，花費 \(cost.moneyText)") : ""
            return station.platforms > 1
                ? language.text(
                    "\(name)’s platforms now take \(cars) (\(length))\(paid).",
                    "\(name) 的月台已一起加長到 \(cars)（\(length)）\(paid)。"
                )
                : language.text(
                    "\(name)’s platform now takes \(cars) (\(length))\(paid).",
                    "\(name) 的月台已加長到 \(cars)（\(length)）\(paid)。"
                )
        }
    }
}
