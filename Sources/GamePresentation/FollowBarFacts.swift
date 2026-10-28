import GameCore

/// Decision 471 (UI health check K, 2-19): what the follow bar
/// (``GameSession/followedTrain``) shows of the world, read through
/// ``GameSession/followBar`` and ``GameSession/followProgress``, which
/// change only when what they show does. The bar read the whole world
/// itself, and the frame round it asked for the followed train, so while a
/// train was followed every tick rebuilt the frame and the bar's five
/// layouts (decision 367's frame, decision 377's way out of it).
///
/// The trip's progress, which moves at almost every tick, is apart
/// (``GameSession/followProgress``), so only the bar's progress bar looks
/// again for it.
public struct FollowBarFacts: Equatable, Sendable {
    /// The trip's times and status, the follow bar's part of the train's
    /// card (``TrainCard``); `nil` while the train has no card.
    public struct Trip: Equatable, Sendable {
        /// "HH:MM" of the trip's departure and the timetable's arrival.
        public var departure: String
        public var arrival: String
        /// "HH:MM" of the expected arrival when late, `nil` on time.
        public var expectedArrival: String?
        /// ``TrainCard/statusText(in:)``.
        public var statusText: String
        /// ``TrainCard/showsPunctuality``.
        public var showsPunctuality: Bool
        /// ``TrainCard/isLate``.
        public var isLate: Bool

        public init(card: TrainCard, in language: DisplayLanguage) {
            departure = card.departure.clockText
            arrival = card.arrival.clockText
            expectedArrival = card.isLate ? card.expectedArrival.clockText : nil
            statusText = card.statusText(in: language)
            showsPunctuality = card.showsPunctuality
            isLate = card.isLate
        }
    }

    public var train: TrainID
    public var name: String
    /// The line the train runs for, for its badge; `nil` for none.
    public var line: LineID?
    /// The line's badge code (``LineBadge/codes(for:)``).
    public var lineCode: String
    /// The line's own colour, if the player chose one.
    public var lineColor: LineColor?
    /// The text after the name (``FollowBarInfo/detail(in:times:)``),
    /// without the times when ``trip`` shows them; `nil` or empty for none.
    public var detail: String?
    public var trip: Trip?
    /// The speed the game runs at, `nil` while paused: the speed shortcut
    /// it matches is filled.
    public var runningSpeed: GameSpeed?

    /// The bar's facts for train `id` in `world`, or `nil` for an unknown
    /// train; `card` is its ``GameWorld/trainCard(of:in:)``.
    public init?(train id: TrainID, in world: GameWorld, card: TrainCard?, language: DisplayLanguage) {
        guard let train = world.train(id: id) else { return nil }
        let info = world.followBarInfo(of: id, in: language)
        self.train = id
        name = train.name
        line = info?.line
        lineCode = line.flatMap { LineBadge.codes(for: world.lines)[$0] } ?? ""
        lineColor = line.flatMap { world.line(id: $0)?.color }
        detail = info?.detail(in: language, times: card == nil)
        trip = card.map { Trip(card: $0, in: language) }
        runningSpeed = world.clock.isPaused ? nil : world.clock.speed
    }

    /// The trip's progress the bar draws, 0 to 1, in thousandths: a tenth
    /// of a point on the bar's 72 points, so a tick that moves the train
    /// less than that leaves it as it was.
    public static func progress(of card: TrainCard?) -> Double {
        guard let card else { return 0 }
        return (card.progress * 1000).rounded() / 1000
    }
}

extension GameSession {
    /// Works ``followBar`` and ``followProgress`` out again after the world
    /// or the followed train changed, and sets each only when it differs.
    func refreshFollowBar() {
        guard let train = followedTrain else {
            if followBar != nil { followBar = nil }
            if followProgress != 0 { followProgress = 0 }
            return
        }
        let card = world.trainCard(of: train.id, in: language)
        let facts = FollowBarFacts(train: train.id, in: world, card: card, language: language)
        if facts != followBar { followBar = facts }
        let progress = FollowBarFacts.progress(of: card)
        if progress != followProgress { followProgress = progress }
    }
}
