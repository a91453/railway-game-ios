import GameCore

// Decision 438 (the screens): the bus tool's roads mode. A finger dragged
// over the map draws a road through the cells it passes, each beside the
// last; the tool shows what GameCore's quote (`roadQuote(along:)`) makes
// of it, and the action button lays it (`buildRoad(along:)`). A tap on one
// of the player's roads picks the stretch it belongs to, to take up
// (`removeRoads(_:)`); the city's roads cannot be taken up. Nothing here
// is a game rule: GameCore prices the road and refuses what cannot be
// laid or taken up, and a refused edit changes nothing.
//
// After the island city's road tool (`Railway/island_city_reference_clean`,
// `g11.js`, `paving`): a road painted cell by cell under the finger. Here
// the cells the finger skipped between two moves are filled in, and the
// road is laid only on the action button, as the bus tool's routes are.

/// What the bus tool draws (decision 438).
public enum BusToolMode: Hashable, Sendable, CaseIterable {
    /// Bus routes: from a station, or between stops on the roads.
    case routes
    /// The player's own roads.
    case roads
}

/// The road the bus tool's roads mode draws (presentation state only): the
/// cells the finger went over, in order, each beside the last.
public struct RoadDraft: Hashable, Sendable {
    public private(set) var cells: [CellPosition] = []

    public init() {}

    public var isEmpty: Bool { cells.isEmpty }

    /// Goes on to `cell` from the last cell, corner to corner and then
    /// straight on, so that no cell is skipped; a step back onto the cell
    /// before the last takes the last back. At most
    /// ``RoadGrid/longestBuiltRoad`` cells.
    mutating func extend(to cell: CellPosition) {
        guard var at = cells.last else {
            cells = [cell]
            return
        }
        while at != cell {
            let next = CellPosition(row: at.row + (cell.row - at.row).signum(), column: at.column + (cell.column - at.column).signum())
            if cells.count >= 2, cells[cells.count - 2] == next {
                cells.removeLast()
            } else {
                guard cells.count < RoadGrid.longestBuiltRoad else { return }
                cells.append(next)
            }
            at = next
        }
    }
}

/// What the drawn road would be, as GameCore quotes it.
public struct RoadPreview: Hashable, Sendable {
    /// The cells with no road yet, which it lays.
    public let laid: [CellPosition]
    /// Their metres and price.
    public let metres: Int64
    public let price: Money
    /// Why it cannot be laid, as the player reads it; `nil` when it can.
    public let problem: String?
    /// The cell on water or too steep, when that is why.
    public let refused: CellPosition?
    /// The metres of the drawn road on road already there (the city's
    /// streets or the player's own), which it joins and does not lay again
    /// (decision 476's sequel).
    public var joined: Int64 = 0

    /// Whether the action button lays it: no problem, and a cell to lay.
    public var canBuild: Bool {
        problem == nil && !laid.isEmpty
    }

    /// `draft` quoted in `world`; `nil` with no cell.
    static func make(_ draft: RoadDraft, in world: GameWorld, language: DisplayLanguage) -> RoadPreview? {
        guard !draft.isEmpty else { return nil }
        do throws(GameError) {
            let quote = try world.roadQuote(along: draft.cells)
            var problem: String?
            if quote.price > .zero, !world.economy.canAfford(quote.price) {
                problem = GameError.insufficientFunds(required: quote.price, available: world.economy.balance).playerMessage(in: language)
            }
            var joined: Int64 = 0
            if let roads = world.roads {
                var seen = Set<CellPosition>()
                for (index, cell) in draft.cells.enumerated() where roads.contains(cell) && seen.insert(cell).inserted {
                    joined += index == 0 ? RoadGrid.straightMetres : RoadGrid.metres(from: draft.cells[index - 1], to: cell)
                }
            }
            return RoadPreview(laid: quote.cells, metres: quote.metres, price: quote.price, problem: problem, refused: nil, joined: joined)
        } catch {
            var refused: CellPosition?
            var problem = error.playerMessage(in: language)
            switch error {
            case .onWater(let row, let column), .roadTooSteep(let row, let column):
                refused = CellPosition(row: row, column: column)
                problem = language.text("A road can't go here: water or a slope too steep.", "這裡不能鋪路：是水面或太陡的坡。")
            default:
                break
            }
            return RoadPreview(laid: [], metres: 0, price: .zero, problem: problem, refused: refused)
        }
    }

    /// The line the bus tool shows: how much new road, and what is road
    /// already (joined, free).
    public func line(in language: DisplayLanguage) -> String? {
        guard problem == nil else { return nil }
        guard !laid.isEmpty else {
            return language.text("There's a road here already.", "這裡已經有路了。")
        }
        let new = language.text("\(BusRouteText.distance(metres, in: language)) of new road", "新鋪 \(BusRouteText.distance(metres, in: language))")
        guard joined > 0 else { return new }
        return language.text(
            "\(new); joins \(BusRouteText.distance(joined, in: language)) of road already there, free",
            "\(new)，接上現有的路 \(BusRouteText.distance(joined, in: language))，這段不用錢"
        )
    }
}

/// One of the player's roads picked to take up (decision 438): the stretch
/// of their cells joined to the cell tapped.
public struct RoadRemoval: Hashable, Sendable {
    public let cells: [CellPosition]
    /// Why it cannot be taken up (a bus route goes along it); `nil` when it
    /// can.
    public let problem: String?

    public var canRemove: Bool { problem == nil }
}

/// The player's roads and the road drawn, for the 2D map (decision 438;
/// decision 476: drawn as the base map's lanes are, each road one line
/// through its cells' middles, ``RoadCentreLines``).
public struct RoadMapOverlay: Hashable, Sendable {
    /// On a real-world map, whose base map does not have them, the player's
    /// roads as streets.
    public var streets: [[PlanPoint]] = []
    /// While the roads mode is open, the player's roads, marked along their
    /// middle so that the roads that can be taken up show.
    public var own: [[PlanPoint]] = []
    /// The road drawn, as it would be laid (with its joins to the roads
    /// beside it), drawn faint.
    public var draft: [[PlanPoint]] = []
    /// The cell a road can't go on, ringed dashed red.
    public var refused: CellPosition?
    public var isBuildable = false
    /// The stretch picked to take up.
    public var removal: [[PlanPoint]] = []
}

extension GameSession {
    /// Whether the bus tool draws routes or roads (decision 438). Lets go
    /// of what was drawn in the other.
    public func setBusMode(_ mode: BusToolMode) {
        guard mode != busMode else { return }
        busMode = mode
        clearBusDraft()
        clearRoadDraft()
        message = nil
    }

    /// The finger at `end` of a drag in the roads mode that began at
    /// `start`: the road drawn goes on through the cells it passes. A drag
    /// that begins on the last cell of the road drawn carries it on; any
    /// other begins a new road.
    public func dragRoad(from start: PlanPoint, to end: PlanPoint) {
        guard busMode == .roads, world.roads != nil else { return }
        if roadDragStart != start {
            roadDragStart = start
            roadRemoval = nil
            if roadDraft.cells.last != CellPosition(containing: start) { roadDraft = RoadDraft() }
            roadDraft.extend(to: CellPosition(containing: start))
        }
        guard world.bounds.contains(end) else { return }
        let before = roadDraft
        roadDraft.extend(to: CellPosition(containing: end))
        if roadDraft != before || roadPreview == nil { refreshRoadPreview() }
    }

    /// The finger lifted: the road drawn stays, to lay with the action
    /// button.
    public func endRoadDrag(from start: PlanPoint, to end: PlanPoint) {
        dragRoad(from: start, to: end)
        roadDragStart = nil
    }

    /// The drag was taken over (a second finger): the road drawn goes.
    public func cancelRoadDrag() {
        roadDragStart = nil
        clearRoadDraft()
    }

    /// A tap in the roads mode: on one of the player's roads picks its
    /// stretch to take up, a tap on it again lets go; on the city's road
    /// says it cannot be taken up.
    func tapRoadTool(at point: PlanPoint) {
        guard let roads = world.roads else { return }
        let cell = CellPosition(containing: point)
        roadDraft = RoadDraft()
        roadPreview = nil
        if roadRemoval?.cells.contains(cell) == true {
            roadRemoval = nil
            return
        }
        roadRemoval = nil
        guard roads.contains(cell) else {
            message = StatusMessage(kind: .failure, text: language.text(
                "Drag across the map to lay a road. Tap one of your roads to take it up.",
                "在地圖上拖過要鋪路的地方。點自己鋪的路可以拆掉。"
            ))
            return
        }
        guard roads.built.contains(cell) else {
            message = StatusMessage(kind: .failure, text: language.text(
                "This is the city's road; it can't be taken up.", "這是城市的路，不能拆。"
            ))
            return
        }
        let stretch = Self.ownStretch(at: cell, in: roads)
        var problem: String?
        var copy = world
        do throws(GameError) {
            try copy.removeRoads(stretch)
        } catch {
            if case .roadInUse(let id) = error {
                let name = BusRouteText.name(id, city: world.busRoute(id: id)?.station == nil, in: language)
                problem = language.text(
                    "\(name) runs on this road. Change the route first.", "\(name)走這段路，要先改路線。"
                )
            } else {
                problem = error.playerMessage(in: language)
            }
        }
        roadRemoval = RoadRemoval(cells: stretch, problem: problem)
    }

    /// The stretch of the player's road cells joined to `cell` (side by
    /// side or corner to corner), the nearest first, at most
    /// ``RoadGrid/longestBuiltRoad``: it goes on through the player's cells
    /// the city has no road in, so a stretch ends where it meets the city's
    /// roads.
    static func ownStretch(at cell: CellPosition, in roads: RoadGrid) -> [CellPosition] {
        var found = [cell], seen: Set<CellPosition> = [cell], next = 0
        while next < found.count, found.count < RoadGrid.longestBuiltRoad {
            let at = found[next]
            next += 1
            guard at == cell || !roads.cells.contains(at) else { continue }
            for dr in -1...1 {
                for dc in -1...1 where dr != 0 || dc != 0 {
                    let near = CellPosition(row: at.row + dr, column: at.column + dc)
                    guard roads.built.contains(near), !roads.cells.contains(near), seen.insert(near).inserted,
                          found.count < RoadGrid.longestBuiltRoad else { continue }
                    found.append(near)
                }
            }
        }
        return found
    }

    /// Lays the road drawn, or takes up the stretch picked, and pays for
    /// it. Returns whether it did.
    @discardableResult
    public func confirmRoad() -> Bool {
        if let removal = roadRemoval {
            guard removal.canRemove else { return false }
            let done = perform(.removeRoads(removal.cells.map(PlayerCommand.Edit.BusStop.init))) { _, _, _ in
                language.text("The road is taken up.", "這段路拆掉了。")
            }
            guard done != nil else { return false }
            clearRoadDraft()
            return true
        }
        guard let preview = roadPreview, preview.canBuild else { return false }
        let done = perform(.buildRoad(along: roadDraft.cells.map(PlayerCommand.Edit.BusStop.init))) { _, _, after in
            // Decision 476: the price the button showed, also with
            // unlimited funds, where the cash does not go down.
            after.economy.unlimitedFunds
                ? language.text(
                    "The road is built. It cost \(preview.price.moneyText); with unlimited funds nothing is paid.",
                    "路鋪好了。造價 \(preview.price.moneyText)，資金無限不扣錢。"
                )
                : language.text("The road is built, for \(preview.price.moneyText).", "路鋪好了，花費 \(preview.price.moneyText)。")
        }
        guard done != nil else { return false }
        clearRoadDraft()
        return true
    }

    /// Lets go of the road drawn and the stretch picked.
    public func clearRoadDraft() {
        roadDraft = RoadDraft()
        roadPreview = nil
        roadRemoval = nil
        roadDragStart = nil
    }

    /// Takes back the road drawn's last cell.
    public func removeLastRoadCell() {
        guard !roadDraft.isEmpty else { return }
        var cells = roadDraft.cells
        cells.removeLast()
        roadDraft = RoadDraft()
        for cell in cells { roadDraft.extend(to: cell) }
        refreshRoadPreview()
    }

    func refreshRoadPreview() {
        roadPreview = RoadPreview.make(roadDraft, in: world, language: language)
    }

    /// The player's roads and the road drawn, for the 2D map: `nil` outside
    /// the roads mode on a map with no base map (whose streets draw the
    /// player's roads with the city's), and with nothing to draw.
    public var roadMapOverlay: RoadMapOverlay? {
        guard let roads = world.roads else { return nil }
        let inMode = tool == .bus && busMode == .roads
        let real = world.geoAnchor != nil
        guard inMode || (real && !roads.built.isEmpty) else { return nil }
        var overlay = RoadMapOverlay()
        let own = RoadCentreLines.lines(of: roads.built)
        if real { overlay.streets = own }
        if inMode {
            overlay.own = own
            let drawn = Set(roadDraft.cells)
            if !drawn.isEmpty {
                // With the roads beside it, which it joins (only those: the
                // whole map's would be slow to go through every frame).
                var near = drawn
                for cell in drawn {
                    for dr in -1...1 {
                        for dc in -1...1 {
                            let beside = CellPosition(row: cell.row + dr, column: cell.column + dc)
                            if real ? roads.built.contains(beside) : roads.contains(beside) { near.insert(beside) }
                        }
                    }
                }
                overlay.draft = RoadCentreLines.lines(of: near, touching: drawn)
            }
            overlay.refused = roadPreview?.refused
            overlay.isBuildable = roadPreview?.canBuild ?? false
            if let removal = roadRemoval?.cells { overlay.removal = RoadCentreLines.lines(of: Set(removal)) }
        }
        return overlay
    }
}
