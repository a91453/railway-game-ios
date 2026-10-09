import GameCore
import GamePresentation
import SwiftUI

/// The whole map, small, over the map's bottom trailing corner (decision
/// 116): the ground, the track, the lines and the stations
/// (``MiniMap``), and a frame round what the map view shows. A tap or a
/// drag on it moves the map there. Folds to a button, and stays folded or
/// open as the player left it.
struct MiniMapView: View {
    /// What it draws; `nil` until it has been worked out.
    let map: MiniMap?
    /// What the map view shows.
    let visible: WorldRegion
    let language: DisplayLanguage
    /// Moves the map to the world point given.
    let onJump: (MiniMap.WorldPoint) -> Void
    @AppStorage("map.minimap.open") private var isOpen = true

    /// The small map's longer side, in points.
    static let longestSide = 120.0

    var body: some View {
        Group {
            if isOpen, let map {
                content(map)
            } else {
                foldedButton
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isOpen)
    }

    private func content(_ map: MiniMap) -> some View {
        let size = MiniMap.size(of: map.region, longestSide: Self.longestSide)
        let projection = MiniMapProjection(region: map.region, size: size)
        return ZStack(alignment: .topTrailing) {
            MiniMapCanvas(map: map, projection: projection)
                .equatable()
                .overlay {
                    if let frame = projection.frame(of: visible) {
                        let rect = CGRect(
                            x: frame.topLeft.x, y: frame.topLeft.y,
                            width: max(4, frame.bottomRight.x - frame.topLeft.x),
                            height: max(4, frame.bottomRight.y - frame.topLeft.y)
                        )
                        Path(rect)
                            .stroke(Theme.primary, lineWidth: 1.5)
                            .allowsHitTesting(false)
                    }
                }
                .frame(width: size.width, height: size.height)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { drag in
                            onJump(projection.worldPoint(at: ScreenPoint(x: drag.location.x, y: drag.location.y)))
                        }
                )
                .accessibilityHidden(true)
            Button {
                isOpen = false
            } label: {
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
                    .frame(width: 22, height: 22)
                    .background(.thinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .padding(3)
            .accessibilityLabel(Text(verbatim: language.text("Hide the overview map", "收起小地圖")))
            .accessibilityIdentifier("map.minimap.fold")
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Theme.panelBorder, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
        .transition(.scale(scale: 0.6, anchor: .bottomTrailing).combined(with: .opacity))
    }

    private var foldedButton: some View {
        Button {
            isOpen = true
        } label: {
            Image(systemName: "map")
                .font(.title3)
                .frame(width: 44, height: 44)
                .glassBackground(in: Circle(), interactive: true)
        }
        .disabled(map == nil)
        .accessibilityLabel(Text(verbatim: language.text("Show the overview map", "顯示小地圖")))
        .accessibilityIdentifier("map.minimap.open")
    }
}

/// The small map's drawing, redrawn only when what it draws changes, not
/// when the frame moves.
private struct MiniMapCanvas: View, Equatable {
    let map: MiniMap
    let projection: MiniMapProjection

    var body: some View {
        Canvas { context, _ in
            let whole = CGRect(origin: .zero, size: CGSize(width: projection.size.width, height: projection.size.height))
            context.fill(Path(whole), with: .color(Palette.land))
            func point(_ world: MiniMap.WorldPoint) -> CGPoint {
                let screen = projection.screenPoint(of: world)
                return CGPoint(x: screen.x, y: screen.y)
            }
            var track = Path()
            for segment in map.track {
                track.move(to: point(segment.from))
                track.addLine(to: point(segment.to))
            }
            context.stroke(track, with: .color(Palette.track.opacity(0.7)), lineWidth: 1)
            for line in map.lines {
                var path = Path()
                path.addLines(line.stops.map(point))
                context.stroke(path, with: .color(Palette.lineColor(line.id, custom: line.color)),
                               style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
            for station in map.stations {
                let at = point(station)
                context.fill(Path(ellipseIn: CGRect(x: at.x - 1.5, y: at.y - 1.5, width: 3, height: 3)),
                             with: .color(Theme.textPrimary))
            }
        }
        .drawingGroup()
    }
}
