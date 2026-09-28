import GameCore
import GamePresentation
import SwiftUI

/// Chooses the directions of the next track piece: a compass of N/E/S/W
/// toggles around a live preview, plus common pieces and a rotate button.
/// The result is the session's `TrackConnections`; no bitmasks are shown.
struct TrackPieceEditor: View {
    static let buttonSize = 36.0
    static let height = buttonSize * 3 + 8

    let session: GameSession

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            compass
            VStack(alignment: .leading, spacing: 8) {
                Text(session.trackConnections.summary)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                HStack(spacing: 6) {
                    ForEach(TrackPiece.allCases, id: \.self) { piece in
                        // Highlighted when the current piece has this shape,
                        // in any rotation.
                        let isActive = session.trackConnections.shapeName == piece.connections.shapeName
                        Button {
                            session.selectTrackPiece(piece)
                        } label: {
                            TrackPreview(connections: piece.connections)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                .frame(width: Self.buttonSize - 10, height: Self.buttonSize - 10)
                                .frame(width: Self.buttonSize, height: Self.buttonSize - 8)
                        }
                        .buttonStyle(SelectableButtonStyle(isActive: isActive))
                        .accessibilityLabel(piece.title)
                        .accessibilityAddTraits(isActive ? .isSelected : [])
                    }
                }
                Button {
                    session.rotateTrackPiece()
                } label: {
                    Label("Rotate", systemImage: "rotate.right")
                        .font(.subheadline)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Rotate piece clockwise")
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
                TrackPreview(connections: session.trackConnections)
                    .frame(width: Self.buttonSize, height: Self.buttonSize)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .accessibilityLabel("Preview: \(session.trackConnections.summary)")
                toggle(.east)
            }
            GridRow {
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                toggle(.south)
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
            }
        }
    }

    private func toggle(_ direction: TrackDirection) -> some View {
        let isOn = session.trackConnections.contains(TrackConnections(direction))
        let state: String = isOn ? "On" : "Off"
        return Button {
            session.toggleTrackDirection(direction)
        } label: {
            Text(direction.abbreviation)
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
        .accessibilityLabel("\(direction.name) connection")
        .accessibilityValue(state)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// One tile drawn exactly as the map draws it.
struct TrackPreview: View {
    let connections: TrackConnections

    var body: some View {
        let connections = connections
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            context.fill(Path(rect), with: .color(Palette.land))
            TileArt.drawTrack(connections, in: rect, context: context)
        }
    }
}
