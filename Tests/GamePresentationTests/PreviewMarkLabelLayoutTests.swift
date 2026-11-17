import GamePresentation
import XCTest

/// The owner's screenshot of 2026-11-18, in points: a stretch drawn from a
/// node at (376, 156) that bends right and falls away to its end at
/// (604, 188), its tightest curve at its start, so the capsule "Radius 150
/// · 65 km/h" (some 136 by 18 points) stood centred over the start flag.
final class PreviewMarkLabelLayoutTests: XCTestCase {
    private static let start = ScreenPoint(x: 376, y: 156)
    private static let end = ScreenPoint(x: 604, y: 188)
    private static let label = (width: 136.0, height: 18.0)
    /// The track already laid that the stretch leaves, rising to the
    /// start, then the stretch: up a little past the start, then down.
    private static let track: [ScreenPoint] = [
        ScreenPoint(x: 130, y: 207), ScreenPoint(x: 250, y: 190), ScreenPoint(x: 376, y: 156),
        ScreenPoint(x: 420, y: 152), ScreenPoint(x: 480, y: 156), ScreenPoint(x: 540, y: 172), end,
    ]

    private func covers(_ a: ScreenFrame, _ b: ScreenFrame) -> Bool {
        min(a.x + a.width, b.x + b.width) > max(a.x, b.x) && min(a.y + a.height, b.y + b.height) > max(a.y, b.y)
    }

    func testTheCapsuleAtTheStartFlagMovesOffTheFlag() throws {
        let frame = try XCTUnwrap(PreviewMarkLabelLayout.place(
            [(point: Self.start, size: Self.label)], flags: [Self.start, Self.end], track: Self.track
        ).first)
        let flag = PreviewMarkLabelLayout.flagFrame(at: Self.start)
        XCTAssertFalse(covers(frame, flag), "\(frame) covers the start flag \(flag)")
        XCTAssertFalse(covers(frame, PreviewMarkLabelLayout.flagFrame(at: Self.end)))
        // Still beside its dot: within a capsule's width of it.
        XCTAssertLessThan(abs(frame.x + frame.width / 2 - Self.start.x), Self.label.width + 30)
        XCTAssertLessThan(abs(frame.y + frame.height / 2 - Self.start.y), 40)
        // And off the track: no point of the line inside it.
        for point in Self.track {
            XCTAssertFalse(point.x > frame.x && point.x < frame.x + frame.width && point.y > frame.y && point.y < frame.y + frame.height)
        }
    }

    func testACapsuleAwayFromTheFlagsStaysOverItsDot() throws {
        let middle = ScreenPoint(x: 480, y: 156)
        let frame = try XCTUnwrap(PreviewMarkLabelLayout.place(
            [(point: middle, size: Self.label)], flags: [Self.start, Self.end], track: Self.track
        ).first)
        XCTAssertEqual(frame, PreviewMarkLabelLayout.frame(.above, at: middle, size: Self.label))
    }

    func testTwoCapsulesAtOnePlaceDoNotCoverEachOther() {
        let frames = PreviewMarkLabelLayout.place(
            [(point: Self.start, size: Self.label), (point: Self.start, size: (width: 80, height: 18))],
            flags: [Self.start, Self.end], track: Self.track
        )
        XCTAssertEqual(frames.count, 2)
        XCTAssertFalse(covers(frames[0], frames[1]), "\(frames)")
        for frame in frames {
            XCTAssertFalse(covers(frame, PreviewMarkLabelLayout.flagFrame(at: Self.start)))
        }
    }

    func testACapsuleGoesUnderWhenTheTrackRunsOverTheDot() throws {
        // A hairpin over the dot: the track passes 20 points above it.
        let dot = ScreenPoint(x: 300, y: 300)
        let track = [ScreenPoint(x: 150, y: 300), dot, ScreenPoint(x: 450, y: 300),
                     ScreenPoint(x: 450, y: 280), ScreenPoint(x: 150, y: 280)]
        let frame = try XCTUnwrap(PreviewMarkLabelLayout.place([(point: dot, size: Self.label)], flags: [], track: track).first)
        XCTAssertGreaterThan(frame.y, dot.y, "\(frame) is not under the dot")
    }
}
