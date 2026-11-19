import Foundation
import GameCore

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
    /// A name board, the old version's (SwiftRailMac's side platform
    /// modules `45e46be7` and `460efb19`: 4.1 m by 1.77 m, scaled as the
    /// furniture by 0.66): ``nameBoardLength`` long and
    /// ``nameBoardHeight`` tall in its grey frame, its foot
    /// ``nameBoardFoot`` over the platform, on two posts at the
    /// platform's back.
    static let nameBoardLength: Float = 2.7
    static let nameBoardHeight: Float = 1.17
    static let nameBoardFoot: Float = 1.3
    static let nameBoardDepth: Float = 0.1
    /// The frame's width round the white face.
    static let nameBoardFrame: Float = 0.06
    /// The old board's green band across its face, from its bottom (a
    /// share of the face's height), and its colour off the old texture.
    static let nameBoardBand: ClosedRange<Float> = 0.30...0.43
    public static let nameBoardGreen = Map3DColor.rgb(0x106118)
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
    /// Decision 882: the second name of each of `world`'s stations that is
    /// a real one (as the station card's nameboard, decision 845): the
    /// official English name under a Chinese name, the Chinese one under
    /// an English name; none where the two are the same.
    static func boardSecondNames(_ world: GameWorld, _ railways: RealRailways, _ frame: RealWorldFrame) -> [StationID: String] {
        var names: [StationID: String] = [:]
        for station in world.stations where !station.isDepot {
            let at = frame.coordinate(worldX: Double(station.location.x), worldY: Double(station.location.y))
            let real = railways.stations(named: station.name, near: RealRailways.Coordinate(latitude: at.latitude, longitude: at.longitude))
            guard let first = real.first(where: { $0.english != nil }) ?? real.first else { continue }
            let key = RealRailways.stationKey(station.name)
            let english = first.english.map(RealRailways.Station.shown)
            let second = english.map { RealRailways.stationKey($0) == key } ?? false ? first.chinese : english
            if let second, RealRailways.stationKey(second) != key { names[station.id] = second }
        }
        return names
    }

    /// Decision 882: a name board with its foot's middle at `foot` (the
    /// platform's back), facing `out` (towards the track), as the old
    /// version's: a white face in a grey frame, a green band across it,
    /// `name` in navy over the band; its face lit at night
    /// (`underground`: always).
    static func addNameBoard(_ mesh: inout Map3DMesh, foot: Map3DPoint, out: Map3DPoint, name: String, second: String? = nil,
                             underground: Bool) {
        typealias Props = Map3DPlatformProps
        guard let out = Map3DPoint(out.x, 0, out.z).normalized else { return }
        let along = Map3DPoint(-out.z, 0, out.x)
        let length = Props.nameBoardLength, height = Props.nameBoardHeight, depth = Props.nameBoardDepth
        let frame = Props.nameBoardFrame
        let middle = foot + out * (depth / 2)
        // The two posts, a little in from its ends.
        for end: Float in [-1, 1] {
            mesh.addBox(base: middle + along * (end * (length / 2 - 0.25)), forward: along, length: 0.06, width: 0.06,
                        height: Props.nameBoardFoot, top: Map3DPalette.steel, side: Map3DPalette.steel)
        }
        let board = middle + Map3DPoint(0, Props.nameBoardFoot, 0)
        mesh.addBox(base: board, forward: along, length: length, width: depth, height: height,
                    top: Map3DPalette.rail, side: Map3DPalette.rail)
        // The face, a little proud of the frame on the track's side.
        let faceLength = length - 2 * frame, faceHeight = height - 2 * frame
        let face = board + out * (depth / 2 + 0.005) + Map3DPoint(0, frame, 0)
        // The reader, facing the board from the track, reads to their right.
        let right = Map3DPoint(out.z, 0, -out.x)
        func quad(_ x0: Float, _ y0: Float, _ x1: Float, _ y1: Float, _ lift: Float, _ colour: UInt32) {
            func corner(_ x: Float, _ y: Float) -> Map3DPoint { face + out * lift + right * x + Map3DPoint(0, y, 0) }
            mesh.addQuad(corner(x0, y0), corner(x1, y0), corner(x1, y1), corner(x0, y1), color: colour)
        }
        let first = mesh.vertices.count
        quad(-faceLength / 2, 0, faceLength / 2, faceHeight, 0, Map3DPalette.sidewalk)
        if underground { mesh.makeGlowing(from: first) } else { mesh.makeNightLit(from: first) }
        let band = Props.nameBoardBand
        quad(-faceLength / 2, faceHeight * band.lowerBound, faceLength / 2, faceHeight * band.upperBound, 0.004, Props.nameBoardGreen)
        // An arrow at each end of the band, pointing out, as on the
        // railway's boards.
        let bandLow = faceHeight * band.lowerBound, bandHigh = faceHeight * band.upperBound, mid = (bandLow + bandHigh) / 2
        let arrow = (bandHigh - bandLow) * 0.8
        for end: Float in [-1, 1] {
            let tip = end * (faceLength / 2 - 0.05), back = tip - end * arrow
            let a = face + out * 0.008 + right * tip + Map3DPoint(0, mid, 0)
            let b = face + out * 0.008 + right * back + Map3DPoint(0, mid + arrow / 2, 0)
            let c = face + out * 0.008 + right * back + Map3DPoint(0, mid - arrow / 2, 0)
            // Counter-clockwise seen from the track.
            mesh.addFan(end > 0 ? [c, a, b] : [a, c, b], normal: out, color: Map3DPalette.sidewalk)
        }
        // The name over the band, as large as fits, its second name small
        // under it when it has one.
        let grid = Float(Map3DBoardGlyphs.grid)
        let room = faceHeight * (1 - band.upperBound)
        func write(_ text: (width: Int, rectangles: [Map3DBoardGlyphs.Rectangle]), height: Float, middle: Float) {
            guard text.width > 0 else { return }
            let cell = min(height / grid, (faceLength - 0.2) / Float(text.width))
            let left = -Float(text.width) * cell / 2, top = middle + grid * cell / 2
            for r in text.rectangles {
                let x0 = left + Float(r.x) * cell, x1 = x0 + Float(r.width) * cell
                let y1 = top - Float(r.y) * cell, y0 = y1 - Float(r.height) * cell
                quad(x0, y0, x1, y1, 0.008, Map3DPalette.playerRim)
            }
        }
        let main = Map3DBoardGlyphs.layout(name)
        let other = second.map(Map3DBoardGlyphs.layout) ?? (width: 0, rectangles: [])
        if other.width > 0 {
            write(main, height: room * 0.66, middle: bandHigh + room * 0.62)
            write(other, height: room * 0.3, middle: bandHigh + room * 0.17)
        } else {
            write(main, height: room * 0.92, middle: bandHigh + room / 2)
        }
    }
}
