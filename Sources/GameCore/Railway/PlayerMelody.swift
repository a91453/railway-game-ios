/// Decision 883: a departure melody the player wrote in the melody
/// workshop (decision 219, stage 4), kept in the world and played by the
/// stations set to it (``Station/playerMelody``). GameCore only keeps and
/// checks the notes; no rule reads them, and the app plays them on its
/// sampled piano at the official melodies' 150 bpm in 3/4 (decision 853).

/// A player melody's number, from 1.
public struct PlayerMelodyID: RawRepresentable, Hashable, Comparable, Codable, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static func < (lhs: PlayerMelodyID, rhs: PlayerMelodyID) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// One note of a player melody, in the game's score ticks (960 a beat,
/// the research note's §2.14).
public struct MelodyNote: Hashable, Codable, Sendable {
    /// Its MIDI pitch, ``PlayerMelody/pitches``.
    public var pitch: Int
    /// When it starts, in ticks from the melody's start.
    public var start: Int
    /// How long it is held, in ticks.
    public var length: Int

    public init(pitch: Int, start: Int, length: Int) {
        self.pitch = pitch
        self.start = start
        self.length = length
    }

    /// Notes in the order a melody keeps them: by start, then pitch.
    static func precedes(_ lhs: MelodyNote, _ rhs: MelodyNote) -> Bool {
        (lhs.start, lhs.pitch) < (rhs.start, rhs.pitch)
    }
}

/// A melody the player wrote (decision 883).
public struct PlayerMelody: Hashable, Codable, Sendable, Identifiable {
    /// Ticks a beat, as every score of the game (research note §2.14).
    public static let ticksPerBeat = 960
    /// Its length: four bars of three beats, as the official melodies'
    /// (decision 853); a note ends by then, and the last one rings on.
    public static let length = 4 * 3 * ticksPerBeat
    /// The shortest step a note may start on or last: a sixteenth.
    public static let step = ticksPerBeat / 4
    /// The pitches a note may have: C5 to C7, the official melodies'
    /// register (the research note's §3 allows C3–C7; the high piano
    /// carries on a phone's speaker over the music).
    public static let pitches = 72...96
    /// The most notes one melody holds (the research note's §3).
    public static let maximumNotes = 128
    /// The most melodies one world holds.
    public static let maximumMelodies = 16

    public let id: PlayerMelodyID
    /// Its name, which the station panel lists it by.
    public internal(set) var name: String
    /// Its notes, by start and then pitch, at least one, no two alike in
    /// start and pitch (``isValid(_:)``).
    public internal(set) var notes: [MelodyNote]

    init(id: PlayerMelodyID, name: String, notes: [MelodyNote]) {
        self.id = id
        self.name = name
        self.notes = notes
    }

    /// Whether `notes` can be a melody: 1 to ``maximumNotes`` notes, each
    /// pitch in ``pitches``, each start and length a whole number of
    /// ``step``s, each note at least one step long and ending by
    /// ``length``, in order of start and pitch with no two alike in both.
    public static func isValid(_ notes: [MelodyNote]) -> Bool {
        guard (1...maximumNotes).contains(notes.count) else { return false }
        for (index, note) in notes.enumerated() {
            guard pitches.contains(note.pitch), note.start >= 0, note.length >= step,
                  note.start % step == 0, note.length % step == 0, note.length <= length - note.start
            else { return false }
            if index > 0, !MelodyNote.precedes(notes[index - 1], note) { return false }
        }
        return true
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, notes
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(PlayerMelodyID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        notes = try container.decode([MelodyNote].self, forKey: .notes)
        guard name.contains(where: { !$0.isWhitespace }) else {
            throw DecodingError.dataCorruptedError(forKey: .name, in: container, debugDescription: "Melody \(id.rawValue) has no name.")
        }
        guard Self.isValid(notes) else {
            throw DecodingError.dataCorruptedError(
                forKey: .notes, in: container,
                debugDescription: "Melody \(id.rawValue): 1 to \(Self.maximumNotes) notes, pitches \(Self.pitches), on sixteenths within \(Self.length) ticks, in order and none twice."
            )
        }
    }
}

extension GameWorld {
    /// Decision 883: adds a melody the player wrote, named `name`, with
    /// `notes`. Free; no rule reads it.
    ///
    /// - Throws, checked in this order: ``GameError/invalidName``,
    ///   ``GameError/invalidMelody`` (``PlayerMelody/isValid(_:)``),
    ///   ``GameError/tooManyMelodies`` or ``GameError/idsExhausted``.
    @discardableResult
    public mutating func addPlayerMelody(named name: String, notes: [MelodyNote]) throws(GameError) -> PlayerMelody {
        guard name.contains(where: { !$0.isWhitespace }) else { throw .invalidName }
        guard PlayerMelody.isValid(notes) else { throw .invalidMelody }
        guard playerMelodies.count < PlayerMelody.maximumMelodies else { throw .tooManyMelodies }
        let (id, next) = try Self.allocateID(from: nextPlayerMelodyID)
        let melody = PlayerMelody(id: PlayerMelodyID(rawValue: id), name: name, notes: notes)
        nextPlayerMelodyID = next
        playerMelodies.append(melody)
        return melody
    }

    /// Decision 883: rewrites melody `id`, its name and its notes; the
    /// stations set to it play the new notes.
    ///
    /// - Throws, checked in this order: ``GameError/unknownPlayerMelody(_:)``,
    ///   ``GameError/invalidName`` or ``GameError/invalidMelody``.
    public mutating func editPlayerMelody(_ id: PlayerMelodyID, name: String, notes: [MelodyNote]) throws(GameError) {
        guard let index = playerMelodies.firstIndex(where: { $0.id == id }) else { throw .unknownPlayerMelody(id) }
        guard name.contains(where: { !$0.isWhitespace }) else { throw .invalidName }
        guard PlayerMelody.isValid(notes) else { throw .invalidMelody }
        playerMelodies[index].name = name
        playerMelodies[index].notes = notes
    }

    /// Decision 883: removes melody `id`; the stations set to it play each
    /// line's own again.
    ///
    /// - Throws: ``GameError/unknownPlayerMelody(_:)``.
    public mutating func removePlayerMelody(_ id: PlayerMelodyID) throws(GameError) {
        guard let index = playerMelodies.firstIndex(where: { $0.id == id }) else { throw .unknownPlayerMelody(id) }
        playerMelodies.remove(at: index)
        stopPlaying(id)
    }

    /// Decision 883: the player melody `id`, or `nil` when there is none.
    public func playerMelody(id: PlayerMelodyID) -> PlayerMelody? {
        playerMelodies.first { $0.id == id }
    }

    /// Why the player melodies break a rule of decision 883: numbers
    /// unique, ascending and handed out, no more than
    /// ``PlayerMelody/maximumMelodies``, and every station set to one set
    /// to a melody that exists and to no official melody as well.
    func playerMelodiesProblem() -> String? {
        guard Self.isStrictlyIncreasing(playerMelodies.map(\.id.rawValue), below: nextPlayerMelodyID),
              playerMelodies.allSatisfy({ $0.id.rawValue >= 1 }) else {
            return "Player melody IDs must be unique, ascending, from 1 and below nextPlayerMelodyID."
        }
        guard playerMelodies.count <= PlayerMelody.maximumMelodies else {
            return "A world holds at most \(PlayerMelody.maximumMelodies) player melodies."
        }
        let ids = Set(playerMelodies.map(\.id))
        for station in stations {
            guard let melody = station.playerMelody else { continue }
            guard ids.contains(melody) else { return "Station \(station.id.rawValue) plays player melody \(melody.rawValue), which does not exist." }
            guard station.departureMelody == nil else { return "Station \(station.id.rawValue) is set to a player melody and an official one." }
        }
        return nil
    }
}
