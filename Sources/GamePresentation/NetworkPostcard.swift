import Foundation
import GameCore

// The network postcard (decision 215): one picture of the player's network
// to share, the game's shop window. What it says and where each part goes
// are worked out here, so Linux tests can check them; the app draws it
// (`PostcardView`) with the map's own drawing and hands the picture to the
// system's share sheet.
//
// The owner's choice, 2026-10-14: of three drafts (a nameboard header, a
// postcard with a stamp, a portrait poster) the poster, C, by the player's,
// the developer's and the art's view together: upright, it fills a phone
// and the feeds it is shared to (4:5); its parts stack, so its layout is a
// few fixed frames; its title is the largest thing on it.

/// What the postcard says.
public struct NetworkPostcard: Hashable, Sendable {
    /// One of the four figures under the map.
    public struct Figure: Hashable, Sendable {
        public let value: String
        public let label: String
    }

    /// The small line over the title: the game's name.
    public let eyebrow: String
    /// The company's name, as the player wrote it (``companyName(_:in:)``).
    public let title: String
    /// The game's date and the company's title (decision 181).
    public let subtitle: String
    /// Lines, stations, track and yesterday's riders, in that order.
    public let figures: [Figure]
    /// The credit the map on it needs (``DataSourceCredits``), or empty.
    public let credit: String
    /// The part of the world the map shows: what is built, with room round
    /// it (``margin``), or the whole map before anything is.
    public let region: WorldRegion

    /// The share of the built region's longer side left round it.
    public static let margin = 0.08
    /// The longest company name kept, in characters.
    public static let nameLimit = 16

    public init(world: GameWorld, companyName: String, in language: DisplayLanguage) {
        eyebrow = language.text("ALONG THE LINE", "ALONG THE LINE ・ 沿線")
        title = Self.companyName(companyName, in: language)
        let rank = CompanyRank(world: world)
        subtitle = "\(world.clock.now.date.text(in: language)) ・ \(rank.title.title(in: language))"
        figures = Self.figures(lines: world.lines.count, figures: rank.figures, in: language)
        // Decision 215: the postcard draws the game's own map, never Apple's
        // or OpenStreetMap's base map (they cannot be drawn into a picture),
        // so it owes only the railways' credit, on a real-world map, where
        // the stations and the traced lines come from TDX and OpenStreetMap.
        credit = world.geoAnchor == nil ? "" : DataSourceCredits.mapCorner(baseMap: false, railways: true, in: language)
        region = Self.region(of: world)
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

    static func figures(lines: Int, figures: CompanyFigures, in language: DisplayLanguage) -> [Figure] {
        [
            Figure(value: Money(Int64(lines)).displayText, label: language.text(lines == 1 ? "line" : "lines", "條路線")),
            Figure(value: Money(Int64(figures.stations)).displayText, label: language.text(figures.stations == 1 ? "station" : "stations", "座車站")),
            Figure(value: RankMeasure.network.valueText(figures.trackMetres), label: language.text("of track", "路網長度")),
            Figure(value: Money(figures.yesterdayRiders).displayText, label: language.text("riders yesterday", "昨日旅客")),
        ]
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

    /// The card, 4:5 upright, about a phone's width.
    public static let size = (width: 400.0, height: 500.0)
    /// Pixels per point of the picture shared.
    public static let scale = 3.0
    /// The card's navy edge and its corner.
    public static let border = 4.0
    public static let cornerRadius = 15.0

    public static let eyebrow = Frame(x: 18, y: 14, width: 364, height: 14)
    public static let title = Frame(x: 16, y: 28, width: 368, height: 40)
    public static let subtitle = Frame(x: 18, y: 68, width: 364, height: 16)
    /// The map, with its own navy edge and corner.
    public static let map = Frame(x: 10, y: 90, width: 380, height: 296)
    public static let mapCornerRadius = 9.0
    /// The credit, under the map's left corner.
    public static let credit = Frame(x: 16, y: 389, width: 262, height: 10)
    /// The four figures, two by two.
    public static let figures = Frame(x: 14, y: 402, width: 262, height: 84)
    public static let figureSpacing = 5.0
    /// The station master in a round badge, over the map's lower right corner.
    public static let stationMaster = Frame(x: 286, y: 384, width: 100, height: 100)

    /// The frame of figure `index` (0 to 3: left to right, top to bottom).
    public static func figure(_ index: Int) -> Frame {
        let width = (figures.width - figureSpacing) / 2, height = (figures.height - figureSpacing) / 2
        return Frame(
            x: figures.x + Double(index % 2) * (width + figureSpacing),
            y: figures.y + Double(index / 2) * (height + figureSpacing),
            width: width, height: height
        )
    }

    /// The type sizes, in points.
    public static let eyebrowSize = 9.5
    public static let titleSize = 32.0
    public static let subtitleSize = 10.0
    public static let figureValueSize = 17.0
    public static let figureLabelSize = 8.0
    public static let creditSize = 6.0
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
