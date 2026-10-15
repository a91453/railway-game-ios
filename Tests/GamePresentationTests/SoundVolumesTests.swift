@testable import GamePresentation
import XCTest

/// Decision 219, stage 2: the settings' three volumes (music, station
/// chimes, other effects), which sound follows which, and that the
/// defaults leave every sound as loud as before.
final class SoundVolumesTests: XCTestCase {
    func testEveryArrivalIsAChimeAndEverythingElseAnEffect() {
        for chime in StationChime.allCases {
            for watched in [false, true] {
                for motif in [false, true] {
                    XCTAssertEqual(SoundCue.arrival(watched: watched, chime: chime, motif: motif).category, .chimes)
                }
            }
        }
        for cue: SoundCue in [.track, .transition, .built, .income, .refused, .warning] {
            XCTAssertEqual(cue.category, .effects, "\(cue)")
        }
    }

    func testTheDefaultsPlayEverySoundAsBefore() {
        let volumes = SoundVolumes()
        for category in SoundCategory.allCases {
            XCTAssertEqual(volumes.level(of: category), 1)
            XCTAssertEqual(volumes.volume(0.45, for: category), 0.45)
        }
        // Nothing kept on the device yet: the same.
        XCTAssertEqual(SoundVolumes(stored: { _ in nil }), volumes)
    }

    func testEachLevelScalesOnlyItsOwnCategory() {
        var volumes = SoundVolumes()
        volumes.setLevel(0.5, of: .chimes)
        XCTAssertEqual(volumes.volume(0.6, for: .chimes), 0.3, accuracy: 1e-6)
        XCTAssertEqual(volumes.volume(0.6, for: .music), 0.6)
        XCTAssertEqual(volumes.volume(0.6, for: .effects), 0.6)
        volumes.setLevel(0, of: .music)
        XCTAssertEqual(volumes.volume(0.45, for: .music), 0)
        XCTAssertEqual(volumes.chimes, 0.5)
        XCTAssertEqual(volumes.effects, 1)
    }

    func testLevelsStayWithinZeroAndOne() {
        var volumes = SoundVolumes(music: -0.5, chimes: 2, effects: .nan)
        XCTAssertEqual(volumes.music, 0)
        XCTAssertEqual(volumes.chimes, 1)
        XCTAssertEqual(volumes.effects, 1)
        volumes.setLevel(.infinity, of: .music)
        XCTAssertEqual(volumes.music, 1)
        volumes.setLevel(-.infinity, of: .effects)
        XCTAssertEqual(volumes.effects, 0)
    }

    func testTheStoredVolumesAreReadByTheirKeys() {
        let stored: [String: Any] = [
            "audio.volume.music": 0.25,
            "audio.volume.chimes": 0.0,
            "audio.volume.effects": "loud",
        ]
        let volumes = SoundVolumes(stored: { stored[$0] })
        XCTAssertEqual(volumes.music, 0.25)
        XCTAssertEqual(volumes.chimes, 0)
        // Not a number: as if never set.
        XCTAssertEqual(volumes.effects, 1)
        XCTAssertEqual(Set(SoundCategory.allCases.map(SoundVolumes.key(for:))).count, 3)
    }
}
