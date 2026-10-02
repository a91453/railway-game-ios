import GameCore
import GamePresentation
import SwiftUI

/// Chooses the directions of the next track piece: a compass of N/E/S/W
/// toggles around a live preview, plus common pieces, a rotate button and
/// a menu for a plain piece, a turnout and its stem, or a level crossing
/// (Stage C2). The result is the session's `TrackConnections` and piece
/// kind; no bitmasks are shown.
struct TrackPieceEditor: View {
    static let buttonSize = 36.0
    static let height = buttonSize * 3 + 8

    let session: GameSession

    var body: some View {
        let language = session.language
        HStack(alignment: .top, spacing: 16) {
            compass
            VStack(alignment: .leading, spacing: 8) {
                Text(session.trackConnections.summary(in: language))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                HStack(spacing: 6) {
                    ForEach(TrackPiece.allCases, id: \.self) { piece in
                        // Highlighted when the current piece has this shape,
                        // in any rotation.
                        let isActive = session.trackConnections.shapeName(in: language) == piece.connections.shapeName(in: language)
                        Button {
                            session.selectTrackPiece(piece)
                        } label: {
                            TrackPreview(connections: piece.connections)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                .frame(width: Self.buttonSize - 10, height: Self.buttonSize - 10)
                                .frame(width: Self.buttonSize, height: Self.buttonSize - 8)
                        }
                        .buttonStyle(SelectableButtonStyle(isActive: isActive))
                        .accessibilityLabel(piece.title(in: language))
                        .accessibilityAddTraits(isActive ? .isSelected : [])
                    }
                }
                HStack(spacing: 6) {
                    Button {
                        session.rotateTrackPiece()
                    } label: {
                        Label("Rotate", systemImage: "rotate.right")
                            .labelStyle(.iconOnly)
                            .font(.subheadline)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Rotate piece clockwise")
                    kindMenu
                }
            }
        }
        .frame(minHeight: Self.height, alignment: .top)
    }

    private var compass: some View {
        Grid(horizontalSpacing: 4, verticalSpacing: 4) {
            GridRow {
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                toggle(.north)
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
            }
            GridRow {
                toggle(.west)
                TrackPreview(connections: session.trackConnections, layout: session.trackPieceLayout)
                    .frame(width: Self.buttonSize, height: Self.buttonSize)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .accessibilityLabel("Preview: \(session.trackConnections.summary(in: session.language))")
                toggle(.east)
            }
            GridRow {
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                toggle(.south)
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
            }
        }
    }

    /// Plain, turnout or crossing, and a turnout's stem among the piece's
    /// exits (Stage C2).
    private var kindMenu: some View {
        let language = session.language
        return Menu {
            Picker("Piece", selection: Binding(get: { session.trackPieceKind }, set: { session.setTrackPieceKind($0) })) {
                ForEach(TrackPieceKind.allCases, id: \.self) { kind in
                    Text(kind.title(in: language)).tag(kind)
                }
            }
            if session.trackPieceKind == .turnout {
                Picker("Stem", selection: Binding(get: { session.turnoutStem }, set: { session.setTurnoutStem($0) })) {
                    ForEach(session.trackConnections.directions, id: \.self) { direction in
                        Text(direction.name(in: language)).tag(direction)
                    }
                }
            }
        } label: {
            Text(verbatim: session.trackPieceKindText)
                .font(.subheadline)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel("Piece: \(session.trackPieceKindText)")
        .accessibilityHint("Chooses a plain piece, a turnout and the exit that joins the others, or a level crossing.")
    }

    private func toggle(_ direction: TrackDirection) -> some View {
        let isOn = session.trackConnections.contains(TrackConnections(direction))
        let state = isOn ? String(localized: "On") : String(localized: "Off")
        return Button {
            session.toggleTrackDirection(direction)
        } label: {
            Text(direction.abbreviation(in: session.language))
                .font(.subheadline.weight(.bold))
                .frame(width: Self.buttonSize, height: Self.buttonSize)
                .foregroundStyle(isOn ? Color.white : Color.primary)
                .background(
                    isOn ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.fill.tertiary),
                    in: RoundedRectangle(cornerRadius: 8)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(isOn ? Color.clear : Color.secondary.opacity(0.35))
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(direction.name(in: session.language)) connection")
        .accessibilityValue(state)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// One tile drawn exactly as the map draws it.
struct TrackPreview: View {
    let connections: TrackConnections
    var layout: TrackLayout = .open

    var body: some View {
        let connections = connections
        let layout = layout
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            context.fill(Path(rect), with: .color(Palette.land))
            switch layout {
            case .open:
                TileArt.drawTrack(connections, in: rect, context: context)
            case .turnout(let stem):
                TileArt.drawTrack(connections, in: rect, context: context)
                TileArt.drawStemMark(stem, in: rect, context: context)
            case .crossing:
                TileArt.drawTrack([.north, .south], in: rect, context: context)
                TileArt.drawTrack([.east, .west], in: rect, context: context)
                TileArt.drawCrossingMark(in: rect, context: context)
            }
        }
    }
}
