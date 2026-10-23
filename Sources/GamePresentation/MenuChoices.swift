import GameCore

/// One entry of a native menu that lists the world's trains or stations:
/// only what the entry shows, so a menu built from them is the same from
/// tick to tick while the game runs.
///
/// The game loop replaces the session's world every tick (every 100 ms), and
/// a SwiftUI view that reads the world is drawn again each time. A native
/// menu open on screen whose contents are drawn again is rebuilt: it jumps
/// back to its top, cross-fades its rows (two layers of text) and can drop
/// a tap. The app's menus are equatable views that compare these entries,
/// so a tick that changes none of them leaves the open menu alone.
public struct MenuChoice<ID: Hashable & Sendable>: Equatable, Identifiable, Sendable {
    public let id: ID
    public let title: String
    /// A second line under the title, when the entry has one.
    public let detail: String?

    public init(id: ID, title: String, detail: String? = nil) {
        self.id = id
        self.title = title
        self.detail = detail
    }
}

extension GameSession {
    /// The trains, in the world's order, to choose the one to control.
    public var trainMenuChoices: [MenuChoice<TrainID>] {
        world.trains.map { MenuChoice(id: $0.id, title: $0.name) }
    }

    /// The stations, in the world's order, to add to a line or insert in it.
    public var stationMenuChoices: [MenuChoice<StationID>] {
        world.stations.map { MenuChoice(id: $0.id, title: $0.name) }
    }

    /// The stations station `id` could be linked with for transfers
    /// (`GameWorld.transferCandidates(for:)`), each with how far away it is.
    public func transferMenuChoices(for id: StationID) -> [MenuChoice<StationID>] {
        world.transferCandidates(for: id).map { candidate in
            let distance = NetworkBuilding.lengthText(world.distanceUnits(between: id, and: candidate.id) ?? 0, in: language)
            return MenuChoice(id: candidate.id, title: "\(candidate.name) · \(distance)")
        }
    }

    /// The types train `id`'s cars can be (item 2, the reference's
    /// `TRAIN_TYPES`): the standard car (`nil`) where the game offers it,
    /// then the offered types (in a lesson, those it has opened, decision
    /// 374), each with its card and what changing the train to it costs
    /// (decision 180).
    public func trainTypeMenuChoices(for id: TrainID) -> [MenuChoice<TrainType?>] {
        trainTypes.map { type in
            MenuChoice(id: type, title: Train.typeText(type, in: language), detail: world.trainTypeMenuText(type, for: id, in: language))
        }
    }

    /// The offered types with their cards alone, for the trains a line buys
    /// (decision 180; its menu offers the line's default besides); in a
    /// lesson, those it has opened (decision 374).
    public var trainTypeCardChoices: [MenuChoice<TrainType>] {
        world.openTrainTypes.map { type in
            MenuChoice(id: type, title: Train.typeText(type, in: language), detail: world.trainTypeCard(type).text(in: language))
        }
    }

    private var trainTypes: [TrainType?] {
        (world.offersStandardCar ? [nil] : []) + world.openTrainTypes.map { $0 }
    }

    /// The platform tracks that can go beside `platform`, island or side,
    /// on either side of its track
    /// (``addPlatformTrack(beside:layout:side:)``), each named by its layout
    /// and the way it lies, with what it would cost or why it cannot be
    /// built (``platformTrackPreview(beside:layout:side:)``, TestFlight
    /// 59.1). The dry runs are kept until the next command: a tick leaves
    /// the track alone, though a cost the balance could not meet may then
    /// read as built until the player taps it.
    public func platformTrackMenuChoices(beside platform: TrackPlatform) -> [MenuChoice<PlatformTrackPlacement>] {
        if let memo = platformTrackMenuMemo[platform], memo.revision == commandRevision { return memo.choices }
        let choices = PlatformTrackLayout.allCases.flatMap { layout in
            PlatformTrackSide.allCases.map { side in
                let preview = platformTrackPreview(beside: platform, layout: layout, side: side)
                return MenuChoice(
                    id: PlatformTrackPlacement(layout: layout, side: side),
                    title: "\(layout.title(in: language)) · \(platformTrackSideText(side, of: platform))",
                    detail: preview.problem ?? preview.cost.map { language.text("Costs \($0.moneyText)", "費用 \($0.moneyText)") }
                )
            }
        }
        platformTrackMenuMemo = platformTrackMenuMemo.filter { $0.value.revision == commandRevision }
        platformTrackMenuMemo[platform] = (commandRevision, choices)
        return choices
    }
}

/// Where a new platform track goes beside a platform: its layout and side.
public struct PlatformTrackPlacement: Hashable, Sendable {
    public let layout: PlatformTrackLayout
    public let side: PlatformTrackSide
}
