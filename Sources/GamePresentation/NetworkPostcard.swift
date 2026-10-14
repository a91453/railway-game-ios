import Foundation
import GameCore

// The network postcard (decision 215): one picture of the player's network
// to share, the game's shop window. What it says and where each part goes
// are worked out here, so Linux tests can check them; the app draws it
// (`PostcardView`) with the map's own drawing and hands the picture to the
// system's share sheet.
//
// The owner's choice, 2026-10-14: of three drafts (a nameboard header, a
// postcard with a stamp, a portrait poster) the poster, by the player's,
// the developer's and the art's view together: upright, it fills a phone
// and the feeds it is shared to (4:5); its title is the largest thing on
// it. Seen on a device it was found ugly, the round station master badge
// above all; v2 (the planning session's choice C, same day) frames the map
// to the network and draws the lines as a route map's (``PostcardNetwork``).

/// What the postcard says.
public struct NetworkPostcard: Hashable, Sendable {
    /// One of the figures under or beside the map.
    public struct Figure: Hashable, Sendable {
        public let value: String
        public let label: String
    }

    /// A line in the legend: its badge (decision 216) and its name.
    public struct LegendLine: Hashable, Sendable {
        public let id: LineID
        public let code: String
        public let name: String
        public let color: LineColor?
    }

    /// How the card is laid out (decision 215, v2: the owner's choice C):
    /// a network taller than wide stands in a narrow map with the legend
    /// and figures in a column beside it; any other fills the width, the
    /// legend and figures under it.
    public enum Shape: Hashable, Sendable {
        case tall, wide
    }

    /// The company's name, as the player wrote it (``companyName(_:in:)``):
    /// the title, the only large words on the card.
    public let title: String
    /// The game's date and the company's title (decision 181).
    public let subtitle: String
    /// The game's name, small in the corner: v2 drops the line over the
    /// title, so the name is written once.
    public let wordmark: String
    /// At most ``figureLimit`` figures, none of them 0: yesterday's riders,
    /// the track, the stations, the lines, in that order.
    public let figures: [Figure]
    /// The lines with their badges, when there are two or more: one line
    /// needs no key.
    public let legend: [LegendLine]
    /// The credit the map on it needs (``DataSourceCredits``), or empty.
    public let credit: String
    /// The part of the world the map shows: what is built, with room round
    /// it (``margin``), or the whole map before anything is.
    public let region: WorldRegion

    /// The share of the built region's longer side left round it.
    public static let margin = 0.08
    /// The longest company name kept, in characters.
    public static let nameLimit = 16
    /// The most figures on the card.
    public static let figureLimit = 3

    public init(world: GameWorld, companyName: String, in language: DisplayLanguage) {
        title = Self.companyName(companyName, in: language)
        let rank = CompanyRank(world: world)
        subtitle = "\(world.clock.now.date.text(in: language)) ・ \(rank.title.title(in: language))"
        wordmark = language.text("Along the Line", "沿線")
        figures = Self.figures(lines: world.lines.count, figures: rank.figures, in: language)
        legend = Self.legend(of: world)
        // Decision 215: the postcard draws the game's own map, never Apple's
        // or OpenStreetMap's base map (they cannot be drawn into a picture),
        // so it owes only the railways' credit, on a real-world map, where
        // the stations and the traced lines come from TDX and OpenStreetMap
        // (and v2's coast, from OpenStreetMap too).
        credit = world.geoAnchor == nil ? "" : DataSourceCredits.mapCorner(baseMap: false, railways: true, in: language)
        region = Self.region(of: world)
    }

    /// Tall when the map's region is a tenth taller than it is wide.
    public var shape: Shape {
        region.height > region.width * 1.1 ? .tall : .wide
    }

    /// `name` trimmed and cut to ``nameLimit`` characters; the game's
    /// default name when nothing is left.
    public static func companyName(_ name: String, in language: DisplayLanguage) -> String {
        let trimmed = name.split(whereSeparator: \.isNewline).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return defaultCompanyName(in: language) }
        return String(trimmed.prefix(nameLimit))
    }

    public static func defaultCompanyName(in language: DisplayLanguage) -> String {
        language.text("My Railway", "我的鐵道")
    }

    /// Decision 215, v2: a 0 on a new game looks like nothing works, so a
    /// figure that is 0 is left out, and at most three are kept, riders
    /// first.
    static func figures(lines: Int, figures: CompanyFigures, in language: DisplayLanguage) -> [Figure] {
        let all: [(Int64, Figure)] = [
            (figures.yesterdayRiders, Figure(value: Money(figures.yesterdayRiders).displayText, label: language.text("riders yesterday", "昨日旅客"))),
            (figures.trackMetres, Figure(value: RankMeasure.network.valueText(figures.trackMetres), label: language.text("of track", "路網長度"))),
            (Int64(figures.stations), Figure(value: Money(Int64(figures.stations)).displayText, label: language.text(figures.stations == 1 ? "station" : "stations", "座車站"))),
            (Int64(lines), Figure(value: Money(Int64(lines)).displayText, label: language.text(lines == 1 ? "line" : "lines", "條路線"))),
        ]
        return Array(all.filter { $0.0 != 0 }.map(\.1).prefix(figureLimit))
    }

    static func legend(of world: GameWorld) -> [LegendLine] {
        guard world.lines.count > 1 else { return [] }
        let codes = LineBadge.codes(for: world.lines)
        return world.lines.map { LegendLine(id: $0.id, code: codes[$0.id] ?? "", name: $0.name, color: $0.color) }
    }

    static func region(of world: GameWorld) -> WorldRegion {
        guard let built = WorldRegion.built(in: world) else { return WorldRegion(bounds: world.bounds) }
        // At least 256 m across, so one station alone is not drawn huge.
        let least = Double(256 * WorldCoordinate.unitsPerMetre)
        let side = max(built.width, built.height, least)
        let middle = (x: (built.minX + built.maxX) / 2, y: (built.minY + built.maxY) / 2)
        let half = (width: max(built.width, least) / 2, height: max(built.height, least) / 2)
        return WorldRegion(
            minX: middle.x - half.width, minY: middle.y - half.height,
            maxX: middle.x + half.width, maxY: middle.y + half.height
        ).expanded(by: side * margin)
    }
}

/// Where each part of the postcard goes, in points of a card
/// ``size`` large; the app renders it at ``scale`` (1200 by 1500 pixels).
///
/// Decision 215, v2 (the owner's choice C, `docs/art/postcard-v2-2026-10-14/`):
/// the station master's head beside the title, inside the card; under it
/// the map, framed to the network. A tall network's map is as narrow as
/// it needs, the legend and the figures in a column beside it; a wide
/// one's fills the width down to the legend's row and the figures'.
public enum PostcardLayout {
    public struct Frame: Hashable, Sendable {
        public let x: Double
        public let y: Double
        public let width: Double
        public let height: Double

        public init(x: Double, y: Double, width: Double, height: Double) {
            self.x = x
            self.y = y
            self.width = width
            self.height = height
        }

        public var maxX: Double { x + width }
        public var maxY: Double { y + height }

        public func intersects(_ other: Frame) -> Bool {
            x < other.maxX && other.x < maxX && y < other.maxY && other.y < maxY
        }

        public func contains(_ other: Frame) -> Bool {
            x <= other.x && y <= other.y && other.maxX <= maxX && other.maxY <= maxY
        }
    }

    /// Where the map, the legend and the figures go on one card.
    public struct Parts: Hashable, Sendable {
        public let map: Frame
        /// One frame a legend entry: as many as fit, the last of them
        /// ``NetworkPostcard/legend``'s "+N" when not all do.
        public let legend: [Frame]
        public let figures: [Frame]
    }

    /// The card, 4:5 upright, about a phone's width.
    public static let size = (width: 400.0, height: 500.0)
    /// Pixels per point of the picture shared.
    public static let scale = 3.0
    /// The card's navy edge and its corner.
    public static let border = 4.0
    public static let cornerRadius = 15.0

    /// The station master's head, in a rounded square beside the title.
    public static let stationMaster = Frame(x: 18, y: 18, width: 50, height: 50)
    public static let stationMasterCornerRadius = 11.0
    public static let title = Frame(x: 78, y: 16, width: 304, height: 36)
    public static let subtitle = Frame(x: 79, y: 52, width: 302, height: 14)
    /// What the map, legend and figures share: under the title, over the
    /// credit.
    public static let body = Frame(x: 14, y: 82, width: 372, height: 384)
    public static let mapCornerRadius = 9.0
    /// The credit, along the bottom on the left; the game's name on the right.
    public static let credit = Frame(x: 18, y: 474, width: 286, height: 12)
    public static let wordmark = Frame(x: 308, y: 472, width: 74, height: 16)

    /// A tall map is never narrower than this or wider than ``tallMapWidest``.
    public static let tallMapNarrowest = 160.0
    public static let tallMapWidest = 250.0
    public static let gap = 8.0
    public static let figureSpacing = 6.0
    public static let tallFigureHeight = 58.0
    public static let wideFigureHeight = 54.0
    public static let legendRow = 18.0
    /// The most legend entries in a wide card's row.
    public static let wideLegendLimit = 4

    /// The parts of a card for a network of `shape`, its map's region
    /// `aspect` (width over height) wide, with `legend` lines in the key
    /// and `figures` figures.
    public static func parts(shape: NetworkPostcard.Shape, aspect: Double, legend: Int, figures: Int) -> Parts {
        switch shape {
        case .tall:
            let width = min(max(body.height * aspect, tallMapNarrowest), tallMapWidest)
            let map = Frame(x: body.x, y: body.y, width: width, height: body.height)
            let column = (x: map.maxX + gap, width: body.maxX - map.maxX - gap)
            let figureFrames = (0..<figures).map { index in
                let bottom = body.maxY - Double(figures - 1 - index) * (tallFigureHeight + figureSpacing)
                return Frame(x: column.x, y: bottom - tallFigureHeight, width: column.width, height: tallFigureHeight)
            }
            let floor = (figureFrames.first?.y ?? body.maxY) - gap
            let fit = max(0, Int((floor - body.y - gap) / legendRow))
            let legendFrames = (0..<min(legend, fit)).map {
                Frame(x: column.x, y: body.y + gap + Double($0) * legendRow, width: column.width, height: legendRow)
            }
            return Parts(map: map, legend: legendFrames, figures: figureFrames)
        case .wide:
            let figureTop = body.maxY - wideFigureHeight
            let legendTop = figureTop - gap - (legend > 0 ? legendRow : 0)
            let map = Frame(x: body.x, y: body.y, width: body.width, height: legendTop - body.y - (legend > 0 ? 2 : gap))
            let shown = min(legend, wideLegendLimit)
            let legendFrames = (0..<shown).map {
                Frame(x: body.x + Double($0) * body.width / Double(shown), y: legendTop, width: body.width / Double(shown), height: legendRow)
            }
            let width = (body.width - figureSpacing * Double(max(figures - 1, 0))) / Double(max(figures, 1))
            let figureFrames = (0..<figures).map {
                Frame(x: body.x + Double($0) * (width + figureSpacing), y: figureTop, width: width, height: wideFigureHeight)
            }
            return Parts(map: map, legend: legendFrames, figures: figureFrames)
        }
    }

    /// The parts of `postcard`'s card.
    public static func parts(of postcard: NetworkPostcard) -> Parts {
        parts(
            shape: postcard.shape, aspect: postcard.region.width / max(postcard.region.height, 1),
            legend: postcard.legend.count, figures: postcard.figures.count
        )
    }

    /// The type sizes, in points.
    public static let titleSize = 30.0
    public static let subtitleSize = 10.0
    public static let wordmarkSize = 10.0
    public static let figureValueSize = 19.0
    public static let figureLabelSize = 8.0
    public static let legendSize = 9.5
    public static let creditSize = 6.5
}

extension NetworkPostcard {
    /// One entry of the legend: a line, or how many more there are.
    public enum LegendEntry: Hashable, Sendable {
        case line(LegendLine)
        case more(Int)
    }

    /// The legend in `slots` entries: every line when they fit, otherwise
    /// the first ones and "+N" for the rest in the last slot.
    public func legendEntries(slots: Int) -> [LegendEntry] {
        guard slots > 0 else { return [] }
        guard legend.count > slots else { return legend.map(LegendEntry.line) }
        return legend.prefix(slots - 1).map(LegendEntry.line) + [.more(legend.count - slots + 1)]
    }
}

/// The map's projection on the postcard: `region` fitted into a view
/// `size` large, north up, no closer than the map's closest zoom
/// (``MapScale/largestSize``).
public struct PostcardProjection: MapProjection, Hashable, Sendable {
    public let pointsPerUnit: Double
    private let centerX: Double
    private let centerY: Double
    private let size: ScreenSize

    public init(region: WorldRegion, size: ScreenSize) {
        self.size = size
        let fit = min(size.width / max(region.width, 1), size.height / max(region.height, 1))
        pointsPerUnit = min(fit, MapScale.largestSize / Double(MapScale.referenceLength))
        centerX = (region.minX + region.maxX) / 2
        centerY = (region.minY + region.maxY) / 2
    }

    public func screenPoint(worldX x: Double, worldY y: Double) -> ScreenPoint {
        ScreenPoint(x: (x - centerX) * pointsPerUnit + size.width / 2, y: (y - centerY) * pointsPerUnit + size.height / 2)
    }

    public func worldPosition(at point: ScreenPoint) -> (x: Double, y: Double) {
        ((point.x - size.width / 2) / pointsPerUnit + centerX, (point.y - size.height / 2) / pointsPerUnit + centerY)
    }

    public var visibleRegion: WorldRegion {
        let start = worldPosition(at: ScreenPoint(x: 0, y: 0))
        let end = worldPosition(at: ScreenPoint(x: size.width, y: size.height))
        return WorldRegion(minX: start.x, minY: start.y, maxX: end.x, maxY: end.y)
    }
}
