import GameCore

// Closing track by hand from the select tool's track card (decision 716,
// continued). The card closes the picked track from the switch or track
// end before it to the one after, all of it or none, and opens it again:
// one command that the command log keeps and undo takes back. The map
// marks closed track at every zoom.

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
        selectedTrackEdge.map(world.isTrackClosed) ?? false
    }

    /// The pieces of track from the switch or track end before `id` to the
    /// one after, in ascending order: what the card closes together.
    func trackRun(through id: TrackEdgeID) -> [TrackEdgeID] {
        let section = world.networkSections().first { $0.traversals.contains { $0.edge == id } }
        return section.map { $0.traversals.map(\.edge).sorted() } ?? [id]
    }

    /// Closes the picked track to trains, from switch to switch, or opens
    /// it again when it is closed. A train on it or on its way along it
    /// refuses the closing, and nothing changes.
    public func toggleSelectedTrackClosure() {
        guard canCloseSelectedTrack, let id = selectedTrackEdge else { return }
        let run = trackRun(through: id).map(\.number)
        if world.isTrackClosed(id) {
            perform(.openTrack(edges: run)) { [language] _, _, _ in
                language.text("Track open again.", "已重新開放這段軌道。")
            }
        } else {
            perform(.closeTrack(edges: run)) { [language] _, _, _ in
                language.text("Track closed. Trains go another way or wait.", "已封閉這段軌道，列車會改走別條路或等候。")
            }
        }
    }
}
