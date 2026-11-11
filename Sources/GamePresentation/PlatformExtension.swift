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
    public let start: Int64
    public let end: Int64

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
    func platformExtension(of platform: TrackPlatform, toCars cars: Int) -> PlatformExtension? {
        guard let room = trackPlatformRoom(of: platform) else { return nil }
        let extra = Int64(cars) * platformCarLength - platform.length
        guard extra > 0, extra <= room.before + room.after else { return nil }
        var before = min(room.before, extra / 2)
        var after = extra - before
        if after > room.after {
            after = room.after
            before = extra - after
        }
        return PlatformExtension(platform: platform, cars: cars, start: platform.start - before, end: platform.end + after)
    }

    /// The lengths `platform` could be lengthened to, shortest first: each
    /// whole number of cars past its own, up to the longest train
    /// (``Train/maximumCars``) and the room it has.
    func platformExtensions(of platform: TrackPlatform) -> [PlatformExtension] {
        let own = platformCars(of: platform)
        guard own < Train.maximumCars else { return [] }
        return ((own + 1)...Train.maximumCars).compactMap { platformExtension(of: platform, toCars: $0) }
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
    public func platformExtensionMenuChoices(for platform: TrackPlatform) -> [MenuChoice<PlatformExtension>] {
        world.platformExtensions(of: platform).map { longer in
            let added = NetworkBuilding.lengthText(longer.length - platform.length, in: language)
            return MenuChoice(
                id: longer,
                title: "\(Train.carsText(longer.cars, in: language)) · \(NetworkBuilding.lengthText(longer.length, in: language))",
                detail: language.text("Adds \(added) · free", "加長 \(added) · 免費")
            )
        }
    }

    /// Why ``platformExtensionMenuChoices(for:)`` offers nothing.
    public var platformExtensionNoRoomText: String {
        language.text(
            "No room to lengthen: the track ends, slopes or meets another platform here.",
            "沒有空間加長：這裡是軌道的盡頭、坡道，或已經有別的月台。"
        )
    }

    /// Lengthens a platform as `longer` says, where it stands.
    public func extendPlatform(_ longer: PlatformExtension) {
        let name = world.station(id: longer.platform.station)?.name ?? "#\(longer.platform.station.rawValue)"
        let cars = Train.carsText(longer.cars, in: language)
        let length = NetworkBuilding.lengthText(longer.length, in: language)
        perform(.extendPlatform(longer.platform, start: longer.start, end: longer.end)) { _, _, _ in
            language.text(
                "\(name)’s platform now takes \(cars) (\(length)).",
                "\(name) 的月台已加長到 \(cars)（\(length)）。"
            )
        }
    }
}
