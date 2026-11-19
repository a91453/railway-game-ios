import Foundation

// Decision 882: a name board at the back of every platform, the station's
// name in the game on it, as on a real platform, the same rule on the
// ground, on a viaduct and under ground.

/// The name boards' letters: Noto Sans TC Bold's glyphs on a grid of
/// ``grid`` cells, each as a few rectangles (``packed``, made by
/// `tools/platform-name-board/build_glyphs.py`), for every character of
/// the game's bundled names, kana and Latin letters.
public enum Map3DBoardGlyphs {
    /// A glyph's cells across and down.
    public static let grid = 16

    /// A glyph: how many cells it takes along a line, and its filled
    /// cells as rectangles, `x` and `y` from its top left.
    public struct Glyph: Equatable, Sendable {
        public let width: Int
        public let rectangles: [Rectangle]
    }

    public struct Rectangle: Equatable, Sendable {
        public let x: Int, y: Int, width: Int, height: Int
    }

    /// Every glyph, read once from ``packed``.
    public static let glyphs: [Character: Glyph] = {
        guard let data = Data(base64Encoded: packed, options: .ignoreUnknownCharacters) else { return [:] }
        let bytes = [UInt8](data)
        var table: [Character: Glyph] = [:], index = 0
        while index < bytes.count {
            let lead = bytes[index]
            let length = lead < 0x80 ? 1 : lead < 0xE0 ? 2 : lead < 0xF0 ? 3 : 4
            guard index + length + 2 <= bytes.count,
                  let text = String(bytes: bytes[index..<index + length], encoding: .utf8), let character = text.first else { break }
            index += length
            let width = Int(bytes[index]) + 1, count = Int(bytes[index + 1])
            index += 2
            guard index + 2 * count <= bytes.count else { break }
            let rectangles = (0..<count).map { n -> Rectangle in
                let place = bytes[index + 2 * n], size = bytes[index + 2 * n + 1]
                return Rectangle(x: Int(place >> 4), y: Int(place & 15), width: Int(size >> 4) + 1, height: Int(size & 15) + 1)
            }
            index += 2 * count
            table[character] = Glyph(width: width, rectangles: rectangles)
        }
        return table
    }()

    /// A space's width, in cells.
    static let spaceWidth = 5

    /// `text` set on one line: its width in cells and its filled cells as
    /// rectangles, `x` from the line's left; a character with no glyph
    /// is left out.
    public static func layout(_ text: String) -> (width: Int, rectangles: [Rectangle]) {
        var x = 0, rectangles: [Rectangle] = []
        for character in text {
            if character.isWhitespace {
                x += spaceWidth
                continue
            }
            guard let glyph = glyphs[character] else { continue }
            rectangles += glyph.rectangles.map { Rectangle(x: x + $0.x, y: $0.y, width: $0.width, height: $0.height) }
            x += glyph.width
        }
        return (x, rectangles)
    }
}

extension Map3DPlatformProps {
    /// A name board: its face ``nameBoardLength`` long and
    /// ``nameBoardHeight`` tall, its foot ``nameBoardFoot`` over the
    /// platform, on two posts at the platform's back.
    static let nameBoardLength: Float = 3
    static let nameBoardHeight: Float = 0.8
    static let nameBoardFoot: Float = 1.5
    static let nameBoardDepth: Float = 0.1
    /// Where along the old version's module (decision 860) a board
    /// stands: in its one long gap, between the square column and the
    /// poster boards (21.2 to 28.5 m), under the second hung sign.
    static let nameBoardInModule: Float = 24.87
    static let nameBoardRoom: ClosedRange<Float> = 21.3...28.4
    /// How far a board's end keeps from a canopy's column.
    static let nameBoardColumnClearance: Float = 0.4

    /// Decision 882: the middles of a platform's name boards, along a
    /// platform `length` long and `depth` deep (half of an `island` or a
    /// side platform) whose line runs as the furniture's module does when
    /// `forward`: in the middle module's gap and every second module's
    /// out from it, moved within the gap to keep clear of the `bins` and
    /// of the canopy's `columns`, which would stand before it seen from
    /// the train (one that cannot is left out); none on a platform the
    /// furniture would not stand on.
    public static func nameBoards(length: Float, depth: Float, island: Bool, forward: Bool, bins: [Float],
                                  columns: [Float] = []) -> [Float] {
        guard island ? 2 * depth >= Map3DUndergroundStations.furnishedIsland : depth >= furnishedPlatform else { return [] }
        let (count, start) = Map3DOldIslandModule.modules(along: length)
        guard count > 0 else { return [] }
        let middle = count / 2, half = nameBoardLength / 2
        return (0..<count).filter { ($0 - middle) % 2 == 0 }.compactMap { number in
            let base = start + Float(number) * Map3DOldIslandModule.length
            let wanted = base + nameBoardInModule
            let room = (base + nameBoardRoom.lowerBound + half)...(base + nameBoardRoom.upperBound - half)
            let spot = stride(from: Float(0), through: 3, by: 0.25).flatMap { [wanted + $0, wanted - $0] }.first { at in
                let along = forward ? at : length - at
                return room.contains(at) && bins.allSatisfy { abs($0 - along) >= binHalfLength + furnitureBinClearance + half }
                    && columns.allSatisfy { abs($0 - along) >= nameBoardColumnClearance + half }
            }
            return spot.map { forward ? $0 : length - $0 }
        }.sorted()
    }
}

extension Map3DScene.Builder {
    /// Decision 882: a name board with its foot's middle at `foot` (the
    /// platform's back), facing `out` (towards the track), `name` on its
    /// face in navy on white, a band of the canopy's blue along its top;
    /// its face lit at night (`underground`: always).
    static func addNameBoard(_ mesh: inout Map3DMesh, foot: Map3DPoint, out: Map3DPoint, name: String, underground: Bool) {
        typealias Props = Map3DPlatformProps
        guard let out = Map3DPoint(out.x, 0, out.z).normalized else { return }
        let along = Map3DPoint(-out.z, 0, out.x)
        let length = Props.nameBoardLength, height = Props.nameBoardHeight, depth = Props.nameBoardDepth
        let middle = foot + out * (depth / 2)
        // The two posts, a little in from its ends.
        for end: Float in [-1, 1] {
            mesh.addBox(base: middle + along * (end * (length / 2 - 0.25)), forward: along, length: 0.06, width: 0.06,
                        height: Props.nameBoardFoot, top: Map3DPalette.steel, side: Map3DPalette.steel)
        }
        let board = middle + Map3DPoint(0, Props.nameBoardFoot, 0)
        let first = mesh.vertices.count
        mesh.addBox(base: board, forward: along, length: length, width: depth, height: height,
                    top: Map3DPalette.sidewalk, side: Map3DPalette.sidewalk)
        if underground { mesh.makeGlowing(from: first) } else { mesh.makeNightLit(from: first) }
        mesh.addBox(base: board + Map3DPoint(0, height - 0.1, 0), forward: along, length: length + 0.02, width: depth + 0.02, height: 0.1,
                    top: Map3DPalette.canopy, side: Map3DPalette.canopy)
        // The name, as large as fits under the band.
        let text = Map3DBoardGlyphs.layout(name)
        guard text.width > 0 else { return }
        let grid = Float(Map3DBoardGlyphs.grid)
        let cell = min(0.62 / grid, (length - 0.3) / Float(text.width))
        let face = board + out * (depth / 2 + 0.01)
        // The reader, facing the board from the track, reads to their right.
        let right = Map3DPoint(out.z, 0, -out.x)
        let left = -Float(text.width) * cell / 2, top = (height - 0.1) / 2 + grid * cell / 2
        for r in text.rectangles {
            let x0 = left + Float(r.x) * cell, x1 = x0 + Float(r.width) * cell
            let y1 = top - Float(r.y) * cell, y0 = y1 - Float(r.height) * cell
            func corner(_ x: Float, _ y: Float) -> Map3DPoint { face + right * x + Map3DPoint(0, y, 0) }
            mesh.addQuad(corner(x0, y0), corner(x1, y0), corner(x1, y1), corner(x0, y1), color: Map3DPalette.playerRim)
        }
    }
}
