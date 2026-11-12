// Decision 703: which line each train is assigned to, looked up rather
// than searched for. Derived from the lines alone; never world or save
// state.

extension GameWorld {
    /// Where in ``lines`` the line each train is assigned to is: what
    /// ``assignedLine(of:)`` and then ``line(id:)`` find by going through
    /// every line's trains, worked out once for all the trains. It keeps
    /// the lines it was worked out from and starts again when asked about
    /// others, so it answers as the search does whatever was done to the
    /// world since.
    struct TrainLineIndex {
        private var lines: [ServiceLine] = []
        private var indices: [TrainID: Int] = [:]
        private var ring: Set<TrainID> = []

        /// The index in `lines` of the line train `id` is assigned to (its
        /// own service or a pattern): the first line with the ID of the
        /// first line that has the train; `nil` if it is on none.
        mutating func index(of id: TrainID, in lines: [ServiceLine]) -> Int? {
            look(at: lines)
            return indices[id]
        }

        /// Whether train `id` is one of a ring's own trains (decision 49)
        /// in `lines`.
        mutating func isOnRing(_ id: TrainID, in lines: [ServiceLine]) -> Bool {
            look(at: lines)
            return ring.contains(id)
        }

        private mutating func look(at lines: [ServiceLine]) {
            // Arrays that share their storage compare at once: the usual
            // case, nothing having changed the lines since the last look.
            if self.lines != lines {
                indices.removeAll(keepingCapacity: true)
                ring.removeAll(keepingCapacity: true)
                var first: [LineID: Int] = [:]
                for (index, line) in lines.enumerated() {
                    let found = first[line.id] ?? index
                    first[line.id] = found
                    for service in 0..<line.serviceCount {
                        for train in line.trains(ofService: service) where indices[train] == nil { indices[train] = found }
                    }
                    if line.isRing { ring.formUnion(line.trains) }
                }
            }
            // Equal lines in other storage: compared at once from now on.
            self.lines = lines
        }
    }

    /// ``assignedLine(of:)`` as an index in ``lines``, from `known`.
    func assignedLineIndex(of id: TrainID, known: inout TrainLineIndex) -> Int? {
        known.index(of: id, in: lines)
    }

    /// The line train `id` is assigned to, from what `memo` knows.
    func assignedLine(of id: TrainID, memo: inout DirectionMemo) -> ServiceLine? {
        assignedLineIndex(of: id, known: &memo.trafficParts.trainLines).map { lines[$0] }
    }
}
