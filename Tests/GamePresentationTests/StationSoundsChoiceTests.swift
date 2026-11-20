import GameCore
@testable import GamePresentation
import XCTest

/// Decision 866: the station panel's sounds row, the arrival chime and the
/// departure melody the player picks for a station, each pick played once.
final class StationSoundsChoiceTests: XCTestCase {
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

    func testAStationRingsTheChimeThePlayerSetElseItsOwn() throws {
        var world = try makeStationsWorld()
        XCTAssertEqual(StationChime.of(Self.west, in: world), .local)
        try world.setStationChime(Self.west, to: .tourist)
        XCTAssertEqual(StationChime.of(Self.west, in: world), .tourist, "the player's pick")
        XCTAssertEqual(StationChime.automatic(Self.west, in: world), .local, "what its place calls for is unchanged")
        XCTAssertEqual(StationChime.of(Self.east, in: world), .local, "another station keeps its own")
        let row = try XCTUnwrap(StationSoundsChoice(of: Self.west, in: world))
        XCTAssertEqual(row.chime, .tourist)
        XCTAssertNil(row.departureMelody)
        XCTAssertEqual(row.chimeTitle(nil, in: .traditionalChinese), "自動（小站鈴）", "automatic says what it rings")
        XCTAssertEqual(row.chimeTitle(.metro, in: .traditionalChinese), "轉乘站鈴")
        XCTAssertEqual(StationSoundsChoice.melodyTitle(nil, in: .traditionalChinese), "依路線")
        XCTAssertEqual(StationSoundsChoice.melodyTitle(.c, in: .english), "Melody 3")
        XCTAssertNil(StationSoundsChoice(of: StationID(rawValue: 9), in: world))
    }

    func testEveryChoiceHasANameInBothLanguages() {
        for language in [DisplayLanguage.english, .traditionalChinese] {
            XCTAssertEqual(Set(StationChime.allCases.map { $0.title(in: language) }).count, StationChime.allCases.count)
            XCTAssertEqual(Set(DepartureMelody.allCases.map { $0.title(in: language) }).count, DepartureMelody.allCases.count)
            XCTAssertFalse(StationSoundsChoice.note(in: language).isEmpty)
        }
    }

    func testTheRowIsTheOperationsGroupsLast() {
        XCTAssertEqual(StationPanelPart.sounds.group, .operations)
        XCTAssertEqual(StationPanelGroup.operations.parts.last, .sounds)
    }

    /// Picking sets the station through the command the log keeps, says
    /// so, and plays the pick once; automatic plays what the station rings
    /// now, and each line's own the first line's melody.
    @MainActor
    func testPickingSetsTheStationAndPlaysThePick() throws {
        let session = GameSession(world: try makeStationsWorld())
        var heard: [SoundCue] = []
        session.playSound = { heard.append($0) }
        session.selectStation(Self.west)
        session.setSelectedStationChime(.metro)
        XCTAssertEqual(session.world.station(id: Self.west)?.chime, .metro)
        XCTAssertEqual(session.message?.kind, .success)
        session.setSelectedStationChime(nil)
        XCTAssertNil(session.world.station(id: Self.west)?.chime)
        session.setSelectedStationDepartureMelody(.b)
        XCTAssertEqual(session.world.station(id: Self.west)?.departureMelody, .b)
        session.setSelectedStationDepartureMelody(nil)
        XCTAssertNil(session.world.station(id: Self.west)?.departureMelody)
        XCTAssertEqual(heard, [
            .arrival(watched: true, chime: .metro), .arrival(watched: true, chime: .local),
            .departure(.b), .departure(DepartureMelody.of(lineNamed: "Shuttle", atStationNamed: "West")),
        ])
        XCTAssertEqual(session.commandLog.entries.suffix(4).map(\.action), [
            .command(.edit(.setStationChime(Self.west, .metro))), .command(.edit(.setStationChime(Self.west, nil))),
            .command(.edit(.setStationDepartureMelody(Self.west, .b))), .command(.edit(.setStationDepartureMelody(Self.west, nil))),
        ])
    }

    /// Decision 883 (later): the play buttons beside the pickers play
    /// what the station is set to through the player's own way in, the
    /// one that sounds with the sounds switched off; a station no line
    /// calls at plays melody 1, a depot nothing.
    @MainActor
    func testThePlayButtonsPlayWhatTheStationIsSetTo() throws {
        var world = try makeStationsWorld()
        try world.buildStation(named: "Alone", at: PlanPoint(x: 7_680, y: 1_024))
        let alone = try XCTUnwrap(world.stations.last?.id)
        let session = GameSession(world: world)
        var heard: [SoundCue] = []
        var asked: [SoundCue] = []
        session.playSound = { heard.append($0) }
        session.previewSound = { asked.append($0) }
        session.previewSelectedStationChime()
        session.previewSelectedStationMelody()
        XCTAssertEqual(asked, [], "no station selected")
        session.selectStation(Self.west)
        session.previewSelectedStationChime()
        session.previewSelectedStationMelody()
        session.setSelectedStationChime(.tourist)
        session.setSelectedStationDepartureMelody(.e)
        session.previewSelectedStationChime()
        session.previewSelectedStationMelody()
        session.selectStation(alone)
        session.previewSelectedStationMelody()
        let own = SoundCue.departure(DepartureMelody.of(lineNamed: "Shuttle", atStationNamed: "West"))
        XCTAssertEqual(asked, [
            .arrival(watched: true, chime: .local), own,
            .arrival(watched: true, chime: .tourist), .departure(.e),
            .arrival(watched: true, chime: .tourist), .departure(.e),
            .departure(.a),
        ])
        XCTAssertEqual(heard, [], "never through the game's own sounds, which the switch turns off")
        for language in [DisplayLanguage.english, .traditionalChinese] {
            XCTAssertTrue(StationSoundsChoice.note(in: language).hasSuffix(StationSoundsChoice.silentModeNote(in: language)))
            XCTAssertTrue(MelodyDraft.note(in: language).hasSuffix(StationSoundsChoice.silentModeNote(in: language)))
        }
    }
}
