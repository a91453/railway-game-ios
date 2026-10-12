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

    public init(id: ID, title: String) {
        self.id = id
        self.title = title
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
}
