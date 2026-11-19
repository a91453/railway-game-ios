import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 883: the melody workshop's piano roll, saving a melody and
/// setting a station to it, the piano the app plays it on, and what a
/// watched train plays leaving a station set to it.
final class MelodyWorkshopTests: XCTestCase {
    private static let west = StationID(rawValue: 1)
    private static let east = StationID(rawValue: 2)

    /// Two stations 160 m apart and a line between them.
    private func makeStationsWorld() throws -> GameWorld {
        var world = try makeWorld(width: 16_384, height: 6_144, balance: 1_000_000)
        try world.buildStation(named: "West", at: PlanPoint(x: 2_560, y: 3_584))
        try world.buildStation(named: "East", at: PlanPoint(x: 12_800, y: 3_584))
        try world.createLine(named: "Shuttle", stops: [Self.west, Self.east])
        return world
    }

    func testTheRollIsTheOfficialMelodiesStaff() throws {
        XCTAssertEqual(MelodyDraft.rows.count, 15)
        XCTAssertEqual(MelodyDraft.rows.first, PlayerMelody.pitches.upperBound)
        XCTAssertEqual(MelodyDraft.rows.last, PlayerMelody.pitches.lowerBound)
        XCTAssertTrue(MelodyDraft.rows.allSatisfy { [0, 2, 4, 5, 7, 9, 11].contains($0 % 12) }, "the C major scale")
        XCTAssertEqual(MelodyDraft.columns, 24)
        XCTAssertEqual(MelodyDraft.rowTitle(0), "C7")
        XCTAssertEqual(MelodyDraft.rowTitle(14), "C5")
        XCTAssertEqual(MelodyDraft.rowTitle(4), "F6")
        for melody in DepartureMelody.allCases {
            let tune = MelodyDraft.tune(of: melody)
            XCTAssertTrue(tune.allSatisfy { MelodyDraft.rows.contains($0.0) }, "\(melody) fits the roll")
            var draft = MelodyDraft(newIn: try makeStationsWorld(), language: .english)
            draft.start(from: melody)
            XCTAssertTrue(draft.canSave, "\(melody) is a melody")
        }
    }

    /// The tunes are the scores' first tracks, note for note.
    func testTheTunesAreTheOfficialScores() throws {
        let scores = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("tools/audio/scores")
        for melody in DepartureMelody.allCases {
            let data = try Data(contentsOf: scores.appendingPathComponent("departure-\(melody.rawValue).score.json"))
            let score = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
            let track = try XCTUnwrap((score["tracks"] as? [[String: Any]])?.first?["notes"] as? [[String: Int]])
            XCTAssertEqual(track.map { [$0["pitch"]!, $0["start"]! / 480, $0["length"]! / 480] }, MelodyDraft.tune(of: melody).map { [$0.0, $0.1, $0.2] })
        }
    }

    func testATapPutsANoteDownOrTakesItAway() throws {
        var draft = MelodyDraft(newIn: try makeStationsWorld(), language: .traditionalChinese)
        XCTAssertEqual(draft.name, "我的旋律 1")
        XCTAssertFalse(draft.canSave, "a note at least")
        draft.length = .half
        draft.tap(row: 7, column: 2)
        XCTAssertEqual(draft.notes, [MelodyNote(pitch: 84, start: 960, length: 1_920)])
        XCTAssertTrue(draft.sounds(row: 7, column: 5))
        XCTAssertFalse(draft.sounds(row: 7, column: 6))
        XCTAssertTrue(draft.starts(row: 7, column: 2))
        XCTAssertFalse(draft.starts(row: 7, column: 3))
        draft.length = .eighth
        draft.tap(row: 0, column: 0)
        XCTAssertEqual(draft.notes.first, MelodyNote(pitch: 96, start: 0, length: 480), "kept in order")
        draft.tap(row: 7, column: 4)
        XCTAssertEqual(draft.notes.count, 1, "a tap on a held note takes it away")
        draft.length = .dottedHalf
        draft.tap(row: 3, column: 22)
        XCTAssertEqual(draft.notes.last, MelodyNote(pitch: 91, start: 10_560, length: 960), "cut at the roll's end")
        draft.length = .half
        draft.tap(row: 3, column: 20)
        XCTAssertEqual(draft.notes.filter { $0.pitch == 91 }, [MelodyNote(pitch: 91, start: 9_600, length: 1_920)], "in place of the note it overlaps")
        draft.tap(row: 15, column: 0)
        draft.tap(row: 0, column: 24)
        XCTAssertEqual(draft.notes.count, 2, "off the roll does nothing")
        draft.clear()
        XCTAssertTrue(draft.notes.isEmpty)
        draft.start(from: .e)
        XCTAssertTrue(PlayerMelody.isValid(draft.notes))
    }

    @MainActor
    func testSavingSetsTheSelectedStationAndATrainPlaysIt() throws {
        let session = GameSession(world: try makeStationsWorld())
        var heard: [SoundCue] = []
        session.playSound = { heard.append($0) }
        session.selectStation(Self.west)
        var draft = MelodyDraft(newIn: session.world, language: .english)
        draft.start(from: .c)
        let id = try XCTUnwrap(session.saveMelody(draft))
        let notes = try XCTUnwrap(session.world.playerMelody(id: id)?.notes)
        XCTAssertEqual(session.world.station(id: Self.west)?.playerMelody, id, "a new melody goes to the station it was written for")
        XCTAssertEqual(heard, [.playerDeparture(notes)])
        XCTAssertEqual(session.selectedStationSounds?.playerMelody, id)
        XCTAssertEqual(session.selectedStationSounds?.playerMelodies.map(\.name), ["My melody 1"])
        XCTAssertEqual(MelodyDraft(newIn: session.world, language: .english).name, "My melody 2")
        let row = try XCTUnwrap(session.selectedStationSounds)
        XCTAssertEqual(row.melodyPick, .player(id))
        XCTAssertEqual(row.melodyPicks.count, 1 + DepartureMelody.allCases.count + 1)
        XCTAssertEqual(row.melodyTitle(.player(id), in: .english), "My melody 1")
        XCTAssertEqual(row.melodyTitle(.official(.b), in: .traditionalChinese), "旋律二")
        session.setSelectedStationMelody(.official(.b))
        XCTAssertEqual(session.selectedStationSounds?.melodyPick, .official(.b))
        session.setSelectedStationMelody(.lines)
        XCTAssertEqual(session.selectedStationSounds?.melodyPick, .lines)
        session.setSelectedStationMelody(.player(id))
        heard.removeAll()

        var world = session.world
        let train = try world.purchaseTrain(named: "T").id
        XCTAssertEqual(DepartureMelody.cue(train, at: Self.west, in: world), .playerDeparture(notes))
        XCTAssertEqual(DepartureMelody.cue(train, at: Self.east, in: world), .departure(.a), "a train on no line elsewhere")

        var edit = MelodyDraft(editing: try XCTUnwrap(session.world.playerMelody(id: id)))
        edit.name = "Home"
        edit.tap(row: 0, column: 0)
        XCTAssertEqual(session.saveMelody(edit), id)
        XCTAssertEqual(session.world.playerMelodies.map(\.name), ["Home"])
        session.selectStation(Self.east)
        session.setSelectedStationPlayerMelody(id)
        XCTAssertEqual(session.world.station(id: Self.east)?.playerMelody, id)
        session.deleteMelody(id)
        XCTAssertTrue(session.world.playerMelodies.isEmpty)
        XCTAssertNil(session.world.station(id: Self.west)?.playerMelody)
        XCTAssertNil(session.world.station(id: Self.east)?.playerMelody)
        XCTAssertEqual(heard, [.playerDeparture(edit.notes)], "a station set to it plays it once")
        XCTAssertEqual(session.commandLog.entries.suffix(4).map(\.action), [
            .command(.edit(.setStationPlayerMelody(Self.west, id))),
            .command(.edit(.editPlayerMelody(id, name: "Home", notes: edit.notes))),
            .command(.edit(.setStationPlayerMelody(Self.east, id))),
            .command(.edit(.removePlayerMelody(id))),
        ])
    }

    func testEveryTextHasBothLanguages() {
        for language in [DisplayLanguage.english, .traditionalChinese] {
            XCTAssertEqual(Set(MelodyDraft.NoteLength.allCases.map { $0.title(in: language) }).count, MelodyDraft.NoteLength.allCases.count)
            XCTAssertFalse(MelodyDraft.title(in: language).isEmpty)
            XCTAssertFalse(MelodyDraft.note(in: language).isEmpty)
        }
    }

    /// The app's piano files, as `tools/audio/make_game_audio.py` makes them.
    static func synth() throws -> PlayerMelodySynth {
        let audio = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("RailwayGameApp/Resources/Audio")
        var files: [Int: [UInt8]] = [:]
        for root in PlayerMelodySynth.roots {
            files[root] = Array(try Data(contentsOf: audio.appendingPathComponent(PlayerMelodySynth.sampleName(root) + ".wav")))
        }
        return try XCTUnwrap(PlayerMelodySynth(wavFiles: files))
    }

    /// A melody plays as long as an official one, at its peak,
    /// the same every time, and as a WAV file the app can play. With
    /// `MELODY_PREVIEW_DIR` set, the six official tunes played this way
    /// are written there for listening.
    func testTheSynthPlaysAMelodyAsTheOfficialOnesAre() throws {
        let synth = try Self.synth()
        var draft = MelodyDraft(newIn: try makeStationsWorld(), language: .english)
        draft.start(from: .a)
        let start = ContinuousClock.now
        let frames = synth.render(draft.notes)
        XCTAssertLessThan(ContinuousClock.now - start, .seconds(5))
        XCTAssertEqual(frames.count, 7 * PlayerMelodySynth.rate + 4 * PlayerMelodySynth.rate / 5, "7.8 s")
        let peak = frames.map(abs).max() ?? 0
        XCTAssertEqual(peak, PlayerMelodySynth.peak, accuracy: 0.001)
        XCTAssertEqual(frames.last ?? 1, 0, accuracy: 0.0001, "ends in silence")
        XCTAssertGreaterThan(frames[PlayerMelodySynth.rate / 10].magnitude, 0.01, "the first note sounds at once")
        XCTAssertEqual(synth.render(draft.notes), frames, "the same every time")
        let wav = PlayerMelodySynth.wav(frames)
        XCTAssertEqual(wav.count, 44 + 2 * frames.count)
        let back = try XCTUnwrap(PlayerMelodySynth.frames(ofWAV: wav))
        XCTAssertEqual(back.count, frames.count)
        XCTAssertNil(PlayerMelodySynth.frames(ofWAV: Array(wav.prefix(30))))
        XCTAssertNil(PlayerMelodySynth(samples: [74: [0.1]]), "a recording for every root")

        if let directory = ProcessInfo.processInfo.environment["MELODY_PREVIEW_DIR"] {
            for melody in DepartureMelody.allCases {
                var draft = MelodyDraft(newIn: try makeStationsWorld(), language: .english)
                draft.start(from: melody)
                try Data(PlayerMelodySynth.wav(synth.render(draft.notes)))
                    .write(to: URL(fileURLWithPath: directory).appendingPathComponent("player-\(melody.rawValue).wav"))
            }
            var chords = MelodyDraft(newIn: try makeStationsWorld(), language: .english)
            chords.length = .eighth
            for (column, row) in [(0, 14), (1, 12), (2, 10), (3, 7), (4, 5), (5, 3), (6, 0)] { chords.tap(row: row, column: column) }
            try Data(PlayerMelodySynth.wav(synth.render(chords.notes))).write(to: URL(fileURLWithPath: directory).appendingPathComponent("player-range.wav"))
        }
    }
}
