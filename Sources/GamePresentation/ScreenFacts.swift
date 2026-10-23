import GameCore

/// Decision 367 (§22.2 25a; TestFlight 83.1: the whole High Speed Rail at
/// 600×, 5 fps, 200 ms a frame the readout could not place): what the
/// screen's frame (the app's `ContentView`, round the map, the pill, the
/// tools and the cards) shows of the world. Read through
/// ``GameSession/screenFacts``, which changes only when one of them does:
/// the frame read the world itself, so every tick rebuilt the whole screen.
public struct ScreenFacts: Equatable, Sendable {
    /// The real-world map's frame (``RealWorldFrame``), `nil` on a blank map.
    public var realWorldFrame: RealWorldFrame?
    /// ``GameSession/nextSteps``.
    public var nextSteps: NextSteps?
    /// Whether the inspector has something to say of the selection
    /// (``GameSession/selectionText()`` is not `nil`).
    public var hasSelection: Bool
    /// Decision 377: whether the game menu shows the goals (a challenge,
    /// the city's requests or the next steps; decisions 86 and 183).
    public var showsGoals: Bool
    /// Decision 377: whether the game menu shows the sights (decision 174).
    public var showsTourism: Bool

    public init(
        realWorldFrame: RealWorldFrame? = nil, nextSteps: NextSteps? = nil, hasSelection: Bool = false,
        showsGoals: Bool = false, showsTourism: Bool = false
    ) {
        self.realWorldFrame = realWorldFrame
        self.nextSteps = nextSteps
        self.hasSelection = hasSelection
        self.showsGoals = showsGoals
        self.showsTourism = showsTourism
    }
}

extension GameSession {
    /// Works ``screenFacts`` out again after the world, the tutorial, the
    /// news or the selection changed, and sets it only when it differs, so
    /// a tick that leaves them as they were tells nothing reading it to
    /// look again.
    func refreshScreenFacts() {
        let steps = nextSteps
        let facts = ScreenFacts(
            realWorldFrame: RealWorldFrame(world: world), nextSteps: steps, hasSelection: selectionText() != nil,
            showsGoals: world.scenario != nil || world.hasCityRequests || steps != nil, showsTourism: world.hasTourism
        )
        if facts != screenFacts { screenFacts = facts }
    }
}
