// A terminus's throat (ARCHITECTURE decision 278). Decision 57 lets a
// service borrow track for another berth of its station only where no
// other train is planned to run the other way. At a terminus every track
// is run both ways: each train comes in along it and leaves along it
// turned round. So the direction protection that keeps single track and
// double track to their ways forbade every berth but the one a route
// names: in the high-speed demo under traffic control a set at Tainan
// waited for the one set standing on its berth at Zuoying with seven of
// its eight tracks free, and with it the sets behind it.
//
// A way into a terminus is exempt: a traversal from which every way on,
// without turning round, ends at a dead end, with no other station's
// platform on any of it. A train that goes in must come out turned round
// on the same track, so the trains planned the other way there are trains
// coming out, which reservation keeps apart; nothing in there is a stretch
// of single or double track where two ways meet. A depot's sidings are
// dead ends of the same kind (decision 280): the high-speed demo's Nangang
// depot lies beyond the station's tracks, and counting its sidings as
// another station's kept every set bound for Nangang to the one berth its
// route names.

extension GameWorld {
    /// The traversals of `path` that lead into station `id`'s terminus (see
    /// the file's header): those the direction protection of decision 57
    /// does not forbid on a way to `id`.
    func terminusTraversals(along path: TrainPath, to id: StationID) -> Set<TrackTraversal> {
        // Without block sections a train following others stops a
        // following gap short of what they hold, which can be inside the
        // terminus's throat, on the way out of it: more trains let in then
        // filled every berth of the high-speed demo's Zuoying, and the
        // sets there could not leave for the depot past the one stopped
        // in the throat (decision 278). With them it stops only at a
        // block's boundary, never among the points.
        guard blockSections else { return [] }
        var known: [TrackTraversal: Bool] = [:]
        return Set(path.traversals.filter { leadsOnlyInto($0, of: id, known: &known) })
    }

    /// Whether every way on from `traversal`, without turning round, ends
    /// at a dead end with no platform of a station other than `id` on it,
    /// but a depot's (decision 280).
    /// `known` keeps the answers of one question; a traversal being asked
    /// is taken as no, so a way that comes round to it again (a loop) is
    /// none.
    private func leadsOnlyInto(_ traversal: TrackTraversal, of id: StationID, known: inout [TrackTraversal: Bool]) -> Bool {
        if let answer = known[traversal] { return answer }
        known[traversal] = false
        guard let edge = network.edge(traversal.edge),
              !network.platforms(on: traversal.edge).contains(where: { $0.station != id && station(id: $0.station)?.isDepot != true })
        else { return false }
        let node = traversal.direction == .forward ? edge.to : edge.from
        guard let end = network.node(node)?.end(of: traversal.edge) else { return false }
        for exit in end.exits {
            guard let next = network.edge(exit), next.from != next.to,
                  leadsOnlyInto(TrackTraversal(edge: exit, direction: next.from == node ? .forward : .backward), of: id, known: &known)
            else { return false }
        }
        known[traversal] = true
        return true
    }
}
