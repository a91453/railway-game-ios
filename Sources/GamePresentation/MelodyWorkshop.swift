import Foundation
import GameCore

/// Decision 883: the melody workshop (decision 219, stage 4): a small
/// piano roll the player writes a departure melody on, four bars of 3/4
/// in eighths across and the C major scale from C5 to C7 down the side,
/// as the official melodies are written (decision 853). What the roll
/// holds, what a tap does and what the workshop says are here, so a Linux
/// test can hold them; the app draws it. The draft is the panel's own
/// until it is saved, through a ``GameWorld`` command.
public struct MelodyDraft: Hashable, Sendable {
    /// The roll's rows, top first: the C major scale from C7 down to C5.
    public static let rows: [Int] = [96, 95, 93, 91, 89, 88, 86, 84, 83, 81, 79, 77, 76, 74, 72]
    /// Ticks a column of the roll: an eighth.
    public static let column = PlayerMelody.ticksPerBeat / 2
    /// The roll's columns: four bars of six eighths.
    public static let columns = PlayerMelody.length / column
    /// Columns a bar, where the roll draws a bar line.
    public static let columnsPerBar = 6

    /// How long a note the player puts down is.
    public enum NoteLength: Int, CaseIterable, Hashable, Sendable {
        case eighth = 1, quarter = 2, dottedQuarter = 3, half = 4, dottedHalf = 6

        /// Its name on the workshop's picker.
        public func title(in language: DisplayLanguage) -> String {
            switch self {
            case .eighth: language.text("Eighth", "八分")
            case .quarter: language.text("Quarter", "四分")
            case .dottedQuarter: language.text("Dotted quarter", "附點四分")
            case .half: language.text("Half", "二分")
            case .dottedHalf: language.text("Dotted half", "附點二分")
            }
        }
    }

    /// The melody it rewrites, `nil` for a new one.
    public var melody: PlayerMelodyID?
    /// Its name.
    public var name: String
    /// Its notes, by start and pitch.
    public private(set) var notes: [MelodyNote]
    /// How long the next note put down is.
    public var length: NoteLength = .quarter

    /// A new melody's draft, empty, named for the first number no melody
    /// of `world` is called by.
    public init(newIn world: GameWorld, language: DisplayLanguage) {
        let names = Set(world.playerMelodies.map(\.name))
        let number = (1...).first { !names.contains(Self.defaultName($0, in: language)) } ?? 1
        melody = nil
        name = Self.defaultName(number, in: language)
        notes = []
    }

    /// The draft of melody `melody`, to rewrite it.
    public init(editing melody: PlayerMelody) {
        self.melody = melody.id
        name = melody.name
        notes = melody.notes
    }

    /// A new melody's name.
    static func defaultName(_ number: Int, in language: DisplayLanguage) -> String {
        language.text("My melody \(number)", "我的旋律 \(number)")
    }

    /// Whether the roll's cell at `row`, `column` sounds: a note of its
    /// pitch starts there or is held over it.
    public func sounds(row: Int, column: Int) -> Bool {
        note(row: row, column: column) != nil
    }

    /// Whether a note starts at the cell (the roll draws a note from it).
    public func starts(row: Int, column: Int) -> Bool {
        guard Self.rows.indices.contains(row) else { return false }
        return notes.contains { $0.pitch == Self.rows[row] && $0.start == column * Self.column }
    }

    private func note(row: Int, column: Int) -> Int? {
        guard Self.rows.indices.contains(row) else { return nil }
        let pitch = Self.rows[row], tick = column * Self.column
        return notes.firstIndex { $0.pitch == pitch && $0.start <= tick && tick < $0.start + $0.length }
    }

    /// A tap on the cell at `row`, `column`: the note sounding there goes;
    /// else a note of ``length`` goes down from it (to the end of the
    /// roll at most), taking the place of any of its pitch it would
    /// overlap. Nothing past ``PlayerMelody/maximumNotes``.
    public mutating func tap(row: Int, column: Int) {
        guard Self.rows.indices.contains(row), (0..<Self.columns).contains(column) else { return }
        if let index = note(row: row, column: column) {
            notes.remove(at: index)
            return
        }
        let pitch = Self.rows[row], start = column * Self.column
        let length = min(self.length.rawValue * Self.column, PlayerMelody.length - start)
        notes.removeAll { $0.pitch == pitch && $0.start < start + length && start < $0.start + $0.length }
        guard notes.count < PlayerMelody.maximumNotes else { return }
        notes.append(MelodyNote(pitch: pitch, start: start, length: length))
        notes.sort { ($0.start, $0.pitch) < ($1.start, $1.pitch) }
    }

    /// Every note gone.
    public mutating func clear() {
        notes = []
    }

    /// The notes of official melody `melody`'s tune (its piano part, not
    /// its accompaniment), to start from.
    public mutating func start(from melody: DepartureMelody) {
        notes = Self.tune(of: melody).map { MelodyNote(pitch: $0.0, start: $0.1 * Self.column, length: $0.2 * Self.column) }
    }

    /// Whether it can be saved: a name and a note at least.
    public var canSave: Bool {
        name.contains { !$0.isWhitespace } && PlayerMelody.isValid(notes)
    }

    /// Official melody `melody`'s tune, (pitch, column, columns), from
    /// `tools/audio/scores/departure-<melody>.score.json`'s first track.
    static func tune(of melody: DepartureMelody) -> [(Int, Int, Int)] {
        switch melody {
        case .a: [(79, 0, 2), (84, 2, 2), (88, 4, 2), (93, 6, 3), (91, 9, 1), (89, 10, 2), (88, 12, 2), (86, 14, 2), (89, 16, 2), (88, 18, 6)]
        case .b: [(96, 0, 2), (93, 2, 2), (89, 4, 2), (91, 6, 4), (88, 10, 2), (89, 12, 2), (88, 14, 1), (89, 15, 1), (93, 16, 2), (91, 18, 6)]
        case .c: [(84, 0, 4), (86, 4, 2), (88, 6, 4), (89, 10, 2), (93, 12, 3), (91, 15, 1), (86, 16, 2), (84, 18, 6)]
        case .d: [(88, 0, 3), (84, 3, 1), (79, 4, 2), (89, 6, 3), (86, 9, 1), (81, 10, 2), (91, 12, 2), (88, 14, 2), (86, 16, 2), (84, 18, 6)]
        case .e: [(93, 0, 1), (91, 1, 1), (89, 2, 2), (86, 4, 2), (88, 6, 2), (91, 8, 4), (89, 12, 1), (91, 13, 1), (93, 14, 4), (91, 18, 2), (88, 20, 4)]
        case .f: [(91, 0, 4), (88, 4, 2), (88, 6, 4), (84, 10, 2), (86, 12, 2), (89, 14, 2), (93, 16, 2), (91, 18, 6)]
        }
    }

    /// A row's note name, as the roll labels it (C5 to C7).
    public static func rowTitle(_ row: Int) -> String {
        let pitch = rows[row]
        let names = [0: "C", 2: "D", 4: "E", 5: "F", 7: "G", 9: "A", 11: "B"]
        return "\(names[pitch % 12] ?? "")\(pitch / 12 - 1)"
    }

    /// The workshop's title.
    public static func title(in language: DisplayLanguage) -> String {
        language.text("Melody workshop", "旋律工作坊")
    }

    /// What the workshop does for the player.
    public static func note(in language: DisplayLanguage) -> String {
        language.text(
            "Tap the grid to put a note down or take it away. Saved melodies can be played at any station.",
            "點格子放下或拿掉一個音。存好的旋律可以指定給任何車站。"
        ) + " " + StationSoundsChoice.quietPhoneNote(in: language)
    }
}

extension GameSession {
    /// Decision 883: plays `notes` once, as a station set to them would.
    public func playMelodyPreview(_ notes: [MelodyNote]) {
        guard !notes.isEmpty else { return }
        preview(.playerDeparture(notes))
    }

    /// Decision 883: saves `draft`, a new melody or the one it rewrites,
    /// through ``GameWorld`` and, for a new one with a station selected,
    /// sets that station to play it. Returns the melody, or `nil` when
    /// refused.
    @discardableResult
    public func saveMelody(_ draft: MelodyDraft) -> PlayerMelodyID? {
        let name = draft.name.trimmingCharacters(in: .whitespaces)
        if let id = draft.melody {
            let done = perform(.editPlayerMelody(id, name: name, notes: draft.notes)) { _, _, _ in
                language.text("\(name) is saved.", "\(name) 已經存好。")
            }
            return done == nil ? nil : id
        }
        let station = selectedStation.flatMap { $0.isDepot ? nil : $0 }
        let done = perform(.addPlayerMelody(name: name, notes: draft.notes)) { _, _, _ in
            language.text("\(name) is saved.", "\(name) 已經存好。")
        }
        guard done != nil, let id = world.playerMelodies.last?.id else { return nil }
        if let station { setStationPlayerMelody(station, id) }
        return id
    }

    /// Decision 883: deletes melody `id`; the stations set to it play each
    /// line's own again.
    public func deleteMelody(_ id: PlayerMelodyID) {
        guard let melody = world.playerMelody(id: id) else { return }
        perform(.removePlayerMelody(id)) { _, _, _ in
            language.text("\(melody.name) is deleted.", "\(melody.name) 已經刪除。")
        }
    }

    /// Decision 883: sets the selected station to play melody `id`, and
    /// plays it once.
    public func setSelectedStationPlayerMelody(_ id: PlayerMelodyID) {
        guard let station = selectedStation else { return }
        setStationPlayerMelody(station, id)
    }

    private func setStationPlayerMelody(_ station: Station, _ id: PlayerMelodyID) {
        guard let melody = world.playerMelody(id: id) else { return }
        let done = perform(.setStationPlayerMelody(station.id, id)) { _, _, _ in
            language.text("\(station.name) now plays \(melody.name) as doors close.", "\(station.name) 的發車旋律改為\(melody.name)。")
        }
        if done != nil { playMelodyPreview(melody.notes) }
    }
}
