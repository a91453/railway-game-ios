import GameCore

/// Decision 403 (續二): the horn of the train the 3D map follows, by the
/// kind of train: the follow bar's horn button blows it, and a Taiwan
/// Railway train (electric, diesel or steam) blows it by itself, as its
/// driver would, as it nears a stop and as it runs into a tunnel. Each
/// voice is a file made by `tools/audio/make_game_audio.py` (`horn()`),
/// from the synth of decision 343; never part of the world, never saved.
public enum TrainHorn: String, CaseIterable, Hashable, Sendable {
    /// A Taiwan Railway EMU's or electric locomotive's two-tone air horn.
    case electric
    /// A diesel locomotive's three-chime air horn.
    case diesel
    /// A steam locomotive's whistle.
    case steam
    /// The high-speed train's electronic horn.
    case highSpeed
    /// A metro train's short electronic horn.
    case metro

    /// The horn of `train`: by its type's family and, for the Taiwan
    /// Railway's, what hauls it. A train without a type (the standard car)
    /// sounds as an EMU, as its running sound is the electric one
    /// (decision 343); a train that runs as a high-speed train has the
    /// high-speed horn whatever its type.
    public static func of(_ train: Train) -> TrainHorn {
        if train.performance.isHighSpeed { return .highSpeed }
        guard let type = train.type else { return .electric }
        switch type.family {
        case .highSpeed: return .highSpeed
        case .metro, .special: return .metro
        case .railway: break
        }
        switch type.rawValue {
        // The Chu-Kuang behind an R100 or R200, and the Blue Train behind
        // its R100-class R135 (decision 286).
        case "R100CK", "R200CK", "BLUE": return .diesel
        // The era's steam train and the Midsummer Formosa's CT273.
        case "STEAM", "SUMMER": return .steam
        default: return .electric
        }
    }

    /// Whether the horn also blows by itself, nearing a stop and running
    /// into a tunnel: the Taiwan Railway's horns, whose drivers blow them
    /// there (its running rules: before a station and before a tunnel).
    /// The high-speed line and the metros have no level crossings or
    /// workers on the track to warn, and their drivers do not.
    public var blowsByItself: Bool {
        switch self {
        case .electric, .diesel, .steam: true
        case .highSpeed, .metro: false
        }
    }

    /// The file the app plays, in its bundle's `Audio` resources.
    public var resource: (name: String, extension: String) {
        ("horn-\(rawValue)", "wav")
    }

    /// How fast the game may run for the horn to blow by itself: 1×, the
    /// speed of a ride. At 10× (the fastest while following on the 3D map,
    /// decision 360) stops come every few seconds, and a horn at each would
    /// talk over the music.
    static let byItselfUpTo: GameSpeed = .x1

    /// Where the followed train is, for the horn that blows by itself: the
    /// stop it nears within ``Map3DDriverHUD/approachMetres``, if any, and
    /// whether its head is in a tunnel. Taken after each step and compared
    /// with the one before (``blowsByItself(from:to:)``).
    struct Place: Hashable, Sendable {
        let train: TrainID
        /// The stop of its timetable it nears (its index and the
        /// timetable's cycle), within a kilometre; `nil` when it nears
        /// none.
        let nearing: Stop?
        let inTunnel: Bool

        struct Stop: Hashable, Sendable {
            let stop: Int
            let cycle: Int64
        }
    }

    /// Whether the horn blows by itself between two places of the followed
    /// train: the same train, now within a kilometre of a stop it was not
    /// nearing before, or its head now in a tunnel it was not in. Never
    /// for the first place seen (following just began).
    static func blowsByItself(from before: Place?, to after: Place) -> Bool {
        guard let before, before.train == after.train else { return false }
        let nears = after.nearing != nil && after.nearing != before.nearing
        let entersTunnel = after.inTunnel && !before.inTunnel
        return nears || entersTunnel
    }
}

extension GameWorld {
    /// Where train `id` is for its horn (``TrainHorn/Place``), or `nil` for
    /// an unknown train or one off the track.
    func hornPlace(of id: TrainID) -> TrainHorn.Place? {
        guard let train = train(id: id), case .onEdge(let traversal, let offset)? = train.position else { return nil }
        var nearing: TrainHorn.Place.Stop?
        // As the driving display measures the way to the next stop.
        if case .travellingToStop(let stop, let cycle)? = train.execution,
           let run = train.times?.run, let curve = runCurve(of: run, for: train.performance) {
            let elapsed = max(0, clock.now.seconds - run.start.seconds)
            let done = elapsed >= run.seconds ? run.length : curve.distance(at: elapsed * 1000)
            if max(0, run.length - done) / WorldCoordinate.unitsPerMetre <= Map3DDriverHUD.approachMetres {
                nearing = .init(stop: stop, cycle: cycle)
            }
        }
        var inTunnel = false
        if let edge = network.edge(traversal.edge) {
            let along = traversal.direction == .forward ? offset : edge.length - offset
            let spans = edge.sectionSpans
            let span = spans.first { $0.start <= along && along < $0.end } ?? spans.last
            inTunnel = span?.kind == .tunnel
        }
        return TrainHorn.Place(train: id, nearing: nearing, inTunnel: inTunnel)
    }
}
