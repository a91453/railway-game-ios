import GameCore

// Closing track by hand from the select tool's track card (decision 716,
// continued). The card closes the picked track from the switch or track
// end before it to the one after, all of it together, and opens it again:
// one command that the command log keeps and undo takes back. With a
// train on it or on its way along it the track is being closed until the
// trains have left, and the card can call that off. The map marks closed
// track, and track being closed, at every zoom.

extension GameSession {
    /// Whether the select tool picked track the card can close or open.
    public var canCloseSelectedTrack: Bool {
        // In a lesson, once double track has been taught: nothing a lesson
        // has not come to yet.
        guard allows(UnlockableTool.doubleTrack) else { return false }
        guard tool == .select, let id = selectedTrackEdge else { return false }
        return world.network.edge(id) != nil
    }

    /// Whether the picked track is closed to trains.
    public var isSelectedTrackClosed: Bool {
        selectedTrackClosure == .closed
    }

    /// What the picked track is to trains: open, being closed (any piece
    /// of it from switch to switch still waits for its trains) or closed.
    public var selectedTrackClosure: TrackClosureState {
        guard let id = selectedTrackEdge else { return .open }
        return closure(of: trackRun(through: id))
    }

    func closure(of run: [TrackEdgeID]) -> TrackClosureState {
        if run.contains(where: world.isTrackClosing) { return .closing }
        return run.contains(where: world.isTrackClosed) ? .closed : .open
    }

    /// The pieces of track from the switch or track end before `id` to the
    /// one after, in ascending order: what the card closes together.
    func trackRun(through id: TrackEdgeID) -> [TrackEdgeID] {
        let section = world.networkSections().first { $0.traversals.contains { $0.edge == id } }
        return section.map { $0.traversals.map(\.edge).sorted() } ?? [id]
    }

    /// Closes the picked track to trains, from switch to switch, or opens
    /// it again when it is closed or being closed. With a train on it or
    /// on its way along it, it is closed once the trains have left.
    public func toggleSelectedTrackClosure() {
        guard canCloseSelectedTrack, let id = selectedTrackEdge else { return }
        let run = trackRun(through: id)
        let numbers = run.map(\.number)
        switch closure(of: run) {
        case .closed:
            perform(.openTrack(edges: numbers)) { [language] _, _, _ in
                language.text("Track open again.", "已重新開放這段軌道。")
            }
        case .closing:
            perform(.openTrack(edges: numbers)) { [language] _, _, _ in
                language.text("Closing called off. The track stays open.", "已取消封閉，這段軌道照常開放。")
            }
        case .open:
            perform(.closeTrack(edges: numbers)) { [language] _, _, world in
                run.contains(where: world.isTrackClosing)
                    ? language.text("Closing once trains have passed. No new trains are sent this way.", "列車通過後封閉，不再讓新的列車開進來。")
                    : language.text("Track closed. Trains go another way or wait.", "已封閉這段軌道，列車會改走別條路或等候。")
            }
        }
    }
}

/// What a piece of track is to trains (decision 716).
public enum TrackClosureState: Sendable {
    case open
    /// Closed once the trains using it have left.
    case closing
    case closed
}
