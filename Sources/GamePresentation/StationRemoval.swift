import GameCore

// Demolishing a station (ARCHITECTURE decision 83): the station panel's
// one GameWorld command (MapBuilder's `handleStationDelete`, the `Ci/`
// metro game's `confirmDeleteStationAllLines`), through `performEdit`, so
// Undo puts the station back.

extension GameSession {
    /// Demolishes the selected station through
    /// `GameWorld.removeStation(_:)`: it goes from every line, a line left
    /// with too few stops goes, and the passengers waiting there leave.
    /// Refused while a train running a service calls there or carries its
    /// passengers; for a line's train the message says to take it off the
    /// line first, since only then can its service be stopped.
    public func removeSelectedStation() {
        guard let station = selectedStation else {
            message = StatusMessage(kind: .failure, text: language.text("Select a station on the map first.", "請先在地圖上選擇車站。"))
            return
        }
        let lines = world.lines
        do throws(GameError) {
            try performEdit { world throws(GameError) in try world.removeStation(station.id) }
        } catch {
            if case .trainServiceActive(let train) = error, let line = world.assignedLine(of: train).flatMap(world.line(id:)) {
                message = StatusMessage(kind: .failure, text: language.text(
                    "Train #\(train.rawValue) of \(line.name) serves \(station.name). Take it off the line and stop its service first.",
                    "\(line.name) 的列車 #\(train.rawValue) 服務 \(station.name)。請先讓它離開路線並停止服務。"
                ))
            } else {
                message = StatusMessage(kind: .failure, text: error.playerMessage(in: language))
            }
            return
        }
        let gone = lines.filter { world.line(id: $0.id) == nil }.map(\.name)
        dropSelectionOfMissing()
        message = StatusMessage(kind: .success, text: gone.isEmpty
            ? language.text(
                "Demolished \(station.name). Its lines no longer call there.",
                "已拆除 \(station.name)。路線不再停靠這站。"
            )
            : language.text(
                "Demolished \(station.name). Too few stops were left on \(gone.joined(separator: ", ")), so the line went too.",
                "已拆除 \(station.name)。\(gone.joined(separator: "、")) 剩下的車站不足，路線也一併刪除。"
            ))
    }
}
