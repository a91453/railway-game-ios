import GameCore
import GamePresentation
import SwiftUI

/// Draws map tiles and trains. Shared by the map and the track-direction
/// preview, so a piece looks the same before and after it is built.
///
/// Tile kinds differ in shape, not only colour: track is drawn as rails,
/// a station as a badge with a train symbol, a train as a disc. Zoomed out
/// (``MapDetail/overview``), track is a thin line and a station a plain
/// square, without the grid.
enum TileArt {
    static func drawMap(
        _ map: GridMap,
        trains: [Train],
        selectedTrainID: TrainID?,
        selection: GridPosition?,
        tileSize: Double,
        in context: GraphicsContext
    ) {
        let detail = MapScale.detail(forTileSize: tileSize)
        let bounds = CGRect(x: 0, y: 0, width: tileSize * Double(map.width), height: tileSize * Double(map.height))
        context.fill(Path(bounds), with: .color(Palette.land))
        if detail == .full {
            drawGrid(columns: map.width, rows: map.height, tileSize: tileSize, in: context)
        }

        for tile in map.tiles {
            let rect = rect(for: tile.position, tileSize: tileSize)
            switch (tile.type, detail) {
            case (.empty, _):
                break
            case (.track(let connections), .full):
                drawTrack(connections, in: rect, context: context)
            case (.track(let connections), .overview):
                drawTrackLine(connections, in: rect, context: context)
            case (.station, .full):
                drawStation(in: rect, context: context)
            case (.station, .overview):
                context.fill(Path(rect.insetBy(dx: rect.width * 0.1, dy: rect.height * 0.1)), with: .color(Palette.station))
            case (.turnout(let connections, let stem), .full):
                drawTrack(connections, in: rect, context: context)
                drawStemMark(stem, in: rect, context: context)
            case (.turnout(let connections, _), .overview):
                drawTrackLine(connections, in: rect, context: context)
            case (.crossing, .full):
                drawTrack([.north, .south], in: rect, context: context)
                drawTrack([.east, .west], in: rect, context: context)
                drawCrossingMark(in: rect, context: context)
            case (.crossing, .overview):
                drawTrackLine([.north, .east, .south, .west], in: rect, context: context)
            }
        }

        if let selection, map.contains(selection) {
            drawSelection(in: rect(for: selection, tileSize: tileSize), context: context)
        }

        for train in trains {
            guard let position = train.position else { continue }
            drawBody(of: train, tileSize: tileSize, in: context)
            drawTrain(at: position, isSelected: train.id == selectedTrainID, tileSize: tileSize, in: context)
        }
    }

    /// A disc where GameCore has the train, with a short bar toward the way
    /// it faces. Drawn at the position after the last tick: nothing is
    /// interpolated between ticks, so a moving train visibly steps.
    static func drawTrain(at position: TrainPosition, isSelected: Bool, tileSize: Double, in context: GraphicsContext) {
        let center = MapScale.center(of: position, tileSize: tileSize)
        let facing = MapScale.facing(of: position)
        let radius = tileSize * 0.26
        let noseLength = radius * 1.7

        var nose = Path()
        nose.move(to: CGPoint(x: center.x, y: center.y))
        nose.addLine(to: CGPoint(x: center.x + facing.dx * noseLength, y: center.y + facing.dy * noseLength))
        let noseWidth = max(2, tileSize * 0.12)
        context.stroke(nose, with: .color(Palette.train), style: StrokeStyle(lineWidth: noseWidth, lineCap: .round))

        let disc = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        context.fill(disc, with: .color(Palette.train))
        // The selected train gets a thick accent ring, so it does not rely on
        // colour alone.
        let ring = isSelected ? Color.accentColor : Color(uiColor: .systemBackground)
        context.stroke(disc, with: .color(ring), lineWidth: isSelected ? 3 : 1.5)
    }

    /// A thick line from the head back along the track the train's body
    /// lies over, to its tail (see `MapScale.bodyPoints(of:tileSize:)`);
    /// nothing for a train of one car.
    static func drawBody(of train: Train, tileSize: Double, in context: GraphicsContext) {
        let points = MapScale.bodyPoints(of: train, tileSize: tileSize)
        guard points.count > 1 else { return }
        var body = Path()
        body.move(to: CGPoint(x: points[0].x, y: points[0].y))
        for point in points.dropFirst() {
            body.addLine(to: CGPoint(x: point.x, y: point.y))
        }
        context.stroke(body, with: .color(Palette.train.opacity(0.75)), style: StrokeStyle(lineWidth: max(3, tileSize * 0.3), lineCap: .round, lineJoin: .round))
    }

    static func rect(for position: GridPosition, tileSize: Double) -> CGRect {
        CGRect(x: Double(position.x) * tileSize, y: Double(position.y) * tileSize, width: tileSize, height: tileSize)
    }

    static func drawTrack(_ connections: TrackConnections, in rect: CGRect, context: GraphicsContext) {
        guard !connections.isEmpty else { return }
        var context = context
        // Round caps join the pieces neatly at the centre; clipping keeps
        // them from spilling into neighbouring tiles.
        context.clip(to: Path(rect))

        let path = trackPath(connections, in: rect)
        let ballastWidth = rect.width * 0.42
        let railWidth = max(1.5, rect.width * 0.1)
        context.stroke(path, with: .color(Palette.ballast), style: StrokeStyle(lineWidth: ballastWidth, lineCap: .round, lineJoin: .round))
        context.stroke(path, with: .color(Palette.rail), style: StrokeStyle(lineWidth: railWidth, lineCap: .round, lineJoin: .round))

        if let end = connections.directions.first, connections.directions.count == 1 {
            // A buffer stop across the open end of a dead end.
            var bar = Path()
            let half = rect.width * 0.22
            let center = CGPoint(x: rect.midX, y: rect.midY)
            switch end {
            case .north, .south:
                bar.move(to: CGPoint(x: center.x - half, y: center.y))
                bar.addLine(to: CGPoint(x: center.x + half, y: center.y))
            case .east, .west:
                bar.move(to: CGPoint(x: center.x, y: center.y - half))
                bar.addLine(to: CGPoint(x: center.x, y: center.y + half))
            }
            context.stroke(bar, with: .color(Palette.rail), style: StrokeStyle(lineWidth: railWidth * 1.4, lineCap: .round))
        }
    }

    /// A turnout's stem: a short bar across the rails at the stem's edge,
    /// so the piece is told apart from a plain junction by shape.
    static func drawStemMark(_ stem: TrackDirection, in rect: CGRect, context: GraphicsContext) {
        let edge = edgeMidpoint(stem, of: rect)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        // A third of the way from the edge toward the centre.
        let at = CGPoint(x: edge.x + (center.x - edge.x) / 3, y: edge.y + (center.y - edge.y) / 3)
        let half = rect.width * 0.2
        var bar = Path()
        switch stem {
        case .north, .south:
            bar.move(to: CGPoint(x: at.x - half, y: at.y))
            bar.addLine(to: CGPoint(x: at.x + half, y: at.y))
        case .east, .west:
            bar.move(to: CGPoint(x: at.x, y: at.y - half))
            bar.addLine(to: CGPoint(x: at.x, y: at.y + half))
        }
        context.stroke(bar, with: .color(Palette.rail), style: StrokeStyle(lineWidth: max(1.5, rect.width * 0.08), lineCap: .round))
    }

    /// A crossing: an open square in the middle, where the two tracks pass
    /// over each other without joining.
    static func drawCrossingMark(in rect: CGRect, context: GraphicsContext) {
        let side = rect.width * 0.3
        let square = CGRect(x: rect.midX - side / 2, y: rect.midY - side / 2, width: side, height: side)
        context.fill(Path(square), with: .color(Palette.ballast))
        context.stroke(Path(square), with: .color(Palette.rail), lineWidth: max(1, rect.width * 0.05))
    }

    /// Track as one thin line along its connections, for the overview.
    static func drawTrackLine(_ connections: TrackConnections, in rect: CGRect, context: GraphicsContext) {
        guard !connections.isEmpty else { return }
        context.stroke(
            trackPath(connections, in: rect), with: .color(Palette.rail),
            style: StrokeStyle(lineWidth: max(1, rect.width * 0.2), lineCap: .round, lineJoin: .round)
        )
    }

    static func drawStation(in rect: CGRect, context: GraphicsContext) {
        let badgeRect = rect.insetBy(dx: rect.width * 0.08, dy: rect.height * 0.08)
        let badge = Path(roundedRect: badgeRect, cornerRadius: rect.width * 0.18)
        context.fill(badge, with: .color(Palette.station))
        context.stroke(badge, with: .color(Palette.rail.opacity(0.5)), lineWidth: 1)

        var symbol = context.resolve(Image(systemName: "tram.fill"))
        symbol.shading = .color(Palette.stationSymbol)
        let natural = symbol.size
        guard natural.width > 0, natural.height > 0 else { return }
        let box = badgeRect.width * 0.62
        let scale = min(box / natural.width, box / natural.height)
        let size = CGSize(width: natural.width * scale, height: natural.height * scale)
        context.draw(symbol, in: CGRect(
            x: badgeRect.midX - size.width / 2,
            y: badgeRect.midY - size.height / 2,
            width: size.width,
            height: size.height
        ))
    }

    private static func drawGrid(columns: Int, rows: Int, tileSize: Double, in context: GraphicsContext) {
        let width = tileSize * Double(columns)
        let height = tileSize * Double(rows)
        var grid = Path()
        for column in 0...columns {
            let x = Double(column) * tileSize
            grid.move(to: CGPoint(x: x, y: 0))
            grid.addLine(to: CGPoint(x: x, y: height))
        }
        for row in 0...rows {
            let y = Double(row) * tileSize
            grid.move(to: CGPoint(x: 0, y: y))
            grid.addLine(to: CGPoint(x: width, y: y))
        }
        context.stroke(grid, with: .color(Palette.gridLine), lineWidth: 0.5)
    }

    private static func drawSelection(in rect: CGRect, context: GraphicsContext) {
        // A thick outline with a contrasting halo, so the selection does not
        // rely on colour alone and stays visible on every kind of tile.
        let outline = Path(rect.insetBy(dx: 1.5, dy: 1.5))
        context.stroke(outline, with: .color(Color(uiColor: .systemBackground)), lineWidth: 5)
        context.stroke(outline, with: .color(.accentColor), lineWidth: 3)
    }

    private static func trackPath(_ connections: TrackConnections, in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let directions = connections.directions
        var path = Path()
        if directions.count == 2, connections != [.north, .south], connections != [.east, .west] {
            path.move(to: edgeMidpoint(directions[0], of: rect))
            path.addQuadCurve(to: edgeMidpoint(directions[1], of: rect), control: center)
        } else {
            for direction in directions {
                path.move(to: center)
                path.addLine(to: edgeMidpoint(direction, of: rect))
            }
        }
        return path
    }

    private static func edgeMidpoint(_ direction: TrackDirection, of rect: CGRect) -> CGPoint {
        switch direction {
        case .north: CGPoint(x: rect.midX, y: rect.minY)
        case .east: CGPoint(x: rect.maxX, y: rect.midY)
        case .south: CGPoint(x: rect.midX, y: rect.maxY)
        case .west: CGPoint(x: rect.minX, y: rect.midY)
        }
    }
}
