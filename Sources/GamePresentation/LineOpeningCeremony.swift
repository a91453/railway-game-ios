import GameCore

// Decision 1044 (FUSE-OPENING-CEREMONY): a bought real line's opening
// ceremony. Buying a line signs the contract (decision 315's card and its
// tune); its opening is the moment the first of its trains leaves a
// station with passengers. Then the 2D map looks over the line, a bugle
// call plays (`SoundCue.lineOpened`), a banner over the map says the line
// opened (closed with a tap, or by itself after a few seconds) and the
// secretary room's news log keeps a line of it (`NewsCategory.opening`).
//
// Only presentation: which lines wait for their opening is kept in the
// session (never saved), and "the first train out" is read from the world
// after each step. GameCore, the save and the golden scenarios know
// nothing of it. A line bought and not yet opened when the app closes
// has no ceremony after it opens again.

/// A line's opening, as the banner shows it.
public struct LineOpening: Hashable, Sendable, Identifiable {
    public let line: LineID
    public let name: String
    /// The line's colour, for the banner's ribbon; `nil` for the accent.
    public let color: LineColor?
    /// The station the first train left.
    public let from: String
    /// Where it is going: the last station of its timetable.
    public let to: String

    public var id: LineID { line }

    /// The banner's title.
    public func title(in language: DisplayLanguage) -> String {
        language.text("\(name) is open", "\(name)通車")
    }

    /// The banner's line under the title.
    public func detail(in language: DisplayLanguage) -> String {
        language.text("The first train has left \(from) for \(to).", "首班車從\(from)開出，開往\(to)。")
    }

    /// The news log's line.
    func newsText(in language: DisplayLanguage) -> String {
        language.text(
            "\(name) opened: the first train left \(from) for \(to).",
            "\(name)通車：首班車從\(from)開往\(to)。"
        )
    }

    /// The opening of `line` in `world`, when one of its trains is running
    /// with passengers: placed, not running empty (``Train/isDeadheading``)
    /// and on its way from a stop of its timetable to the next. `nil`
    /// while none is, or once the line is gone.
    static func of(_ line: LineID, in world: GameWorld) -> LineOpening? {
        guard let service = world.line(id: line) else { return nil }
        for id in service.assignedTrains {
            guard let train = world.train(id: id), train.position != nil, !train.isDeadheading,
                  case .travellingToStop(let stop, let cycle)? = train.execution,
                  stop > 0 || cycle > 0, !train.timetable.isEmpty else { continue }
            let left = (stop > 0 ? stop : train.timetable.count) - 1
            guard train.timetable.indices.contains(left),
                  let from = world.station(id: train.timetable[left].station)?.name,
                  let to = train.timetable.last.flatMap({ world.station(id: $0.station)?.name }) else { continue }
            return LineOpening(line: line, name: service.name, color: service.color, from: from, to: to)
        }
        return nil
    }
}

extension GameSession {
    /// How long the banner stays when nobody closes it.
    public static let lineOpeningShown: Duration = .seconds(8)

    /// Whether this game holds opening ceremonies: as the new-train cards
    /// (decision 566), not the demo, the tutorial or a lesson.
    var showsLineOpenings: Bool { showsTrainArrivals }

    /// Decision 1044: the lines `lines` were just bought; each one's
    /// ceremony waits for its first train.
    func awaitOpening(of lines: [LineID]) {
        guard showsLineOpenings else { return }
        for line in lines where !awaitingOpenings.contains(line) {
            awaitingOpenings.append(line)
        }
    }

    /// After a step: the first line waiting whose first train is out has
    /// its ceremony, unless a card is in front (the purchase card, a new
    /// train's card) or a banner is already showing; it waits for them.
    /// A line that is gone (sold, undone) waits no more.
    func noteLineOpenings() {
        guard !awaitingOpenings.isEmpty else { return }
        awaitingOpenings.removeAll { world.line(id: $0) == nil }
        guard lineOpening == nil, lastLineAcquired == nil, shownRealLineOffer == nil, trainArrivals.isEmpty else { return }
        for (index, line) in awaitingOpenings.enumerated() {
            guard let opening = LineOpening.of(line, in: world) else { continue }
            awaitingOpenings.remove(at: index)
            holdCeremony(opening)
            return
        }
    }

    /// The ceremony itself: the banner, the bugle call, the news log's
    /// line and, unless the camera follows a vehicle, the map over the line.
    func holdCeremony(_ opening: LineOpening) {
        lineOpening = opening
        let today = world.clock.now.seconds / GameTime.secondsPerDay
        news.add(day: today, .opening, target: .line(opening.line.rawValue)) { opening.newsText(in: $0) }
        playSound?(.lineOpened)
        if !isFollowingVehicle, let region = AmbientDirector.region(of: .line(opening.line), in: world) {
            lookOver(region)
        }
    }

    /// The banner closed, by a tap or by itself.
    public func dismissLineOpening() {
        lineOpening = nil
    }

    /// "Go" on the banner: the line selected and its page open, as the
    /// news log's "Go" on the line, and the banner closed.
    public func goToLineOpening() {
        guard let opening = lineOpening else { return }
        lineOpening = nil
        guard world.line(id: opening.line) != nil else { return }
        selectLine(opening.line)
    }
}
