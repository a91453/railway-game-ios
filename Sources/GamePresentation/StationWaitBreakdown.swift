import GameCore

// Why a full station can stand beside trains that leave half empty
// (TestFlight 59.1: "the station is full and the line goes where they want,
// so why is the peak load low?"). Those waiting each wait for one line, one
// way, and board only a train that calls where they are going; those
// changing trains wait too; and when a line has closed for the night they
// wait for its first train. The panel says so, line by line. Native: no
// reference explains its queues.

extension GameWorld {
    /// Who waits at station `id`, a line for each line and way: "Main to
    /// Gamma · 120", with how many of them change trains here ("(30
    /// changing)"), and "closed, waiting for the first train" while the line
    /// runs no service. Empty if nobody waits.
    public func waitingBreakdown(at id: StationID, in language: DisplayLanguage) -> [String] {
        struct Key: Hashable, Comparable {
            let line: LineID
            let direction: LineDirection
            static func < (lhs: Key, rhs: Key) -> Bool {
                lhs.line != rhs.line ? lhs.line < rhs.line : (lhs.direction == .outbound && rhs.direction != .outbound)
            }
        }
        var counts: [Key: (all: Int64, changing: Int64)] = [:]
        for group in waitingPassengers(at: id) {
            let key = Key(line: group.line, direction: group.direction)
            let changing = (group.journey?.origin).map { $0 != id } ?? false
            counts[key, default: (0, 0)].all += group.count
            if changing { counts[key, default: (0, 0)].changing += group.count }
        }
        return counts.keys.sorted().map { key in
            let count = counts[key] ?? (0, 0)
            let line = self.line(id: key.line)
            let end = key.direction == .outbound ? line?.stops.last : line?.stops.first
            let towards = end.flatMap { station(id: $0)?.name }.map { language.text(" to \($0)", " 往 \($0)") } ?? ""
            let name = line?.name ?? language.text("Line #\(key.line.rawValue)", "路線 #\(key.line.rawValue)")
            var text = "\(name)\(towards) · \(count.all)"
            if count.changing > 0 {
                text += language.text(" (\(count.changing) changing)", "（轉乘 \(count.changing)）")
            }
            if serviceLevel(of: key.line, at: clock.now) == nil {
                text += language.text(" · closed, waiting for the first train", " · 已收班，等首班車")
            }
            return text
        }
    }

    /// Why station `id` is crowded while trains may leave it part full,
    /// once at least half its room is taken (the map's "crowded" bubble);
    /// `nil` below that.
    public func crowdedStationNote(at id: StationID, in language: DisplayLanguage) -> String? {
        let groups = waitingPassengers(at: id)
        let waiting = groups.reduce(Int64(0)) { $0 + $1.count }
        guard waiting * 2 >= StationPassengers.capacity else { return nil }
        var note = language.text(
            "Each person waits for one line and one way, and boards only a train that stops where they are going, so a crowded station can sit beside part-empty trains. The peak load is the fullest departure of the day. Run more trains on the busiest line above, or a line to where they are going.",
            "每位乘客只等一條路線的一個方向，而且只上會停他目的地的車，所以車站擁擠時，列車仍可能沒坐滿。尖峰載客率是當天最滿的一班。請在上面候車最多的路線加開列車，或開一條到他們目的地的路線。"
        )
        if groups.contains(where: { serviceLevel(of: $0.line, at: clock.now) == nil }) {
            note += language.text(
                " A closed line's passengers wait overnight for its first train.",
                "已收班路線的乘客會留在站內，等到首班車。"
            )
        }
        return note
    }
}
