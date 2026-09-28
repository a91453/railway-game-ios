import GameCore
import GamePresentation
import SwiftUI

/// The scrollable, zoomable map. It draws `session.world.map` directly, so
/// every command result shows up on the next frame.
struct MapView: View {
    let session: GameSession
    /// Tile size the player zoomed to; `nil` follows the viewport. View-only state.
    @State private var zoomedTileSize: Double?

    var body: some View {
        GeometryReader { proxy in
            let map = session.world.map
            let fitting = MapScale.fittingSize(
                width: proxy.size.width,
                height: proxy.size.height,
                columns: map.width,
                rows: map.height
            )
            let tileSize = zoomedTileSize.map { MapScale.clamped($0, fitting: fitting) }
                ?? MapScale.automaticSize(fitting: fitting)

            ScrollView([.horizontal, .vertical]) {
                MapCanvas(
                    map: map,
                    trains: session.world.trains,
                    selectedTrainID: session.selectedTrainID,
                    selection: session.selection,
                    tileSize: tileSize,
                    session: session
                )
                .equatable()
                .accessibilityElement()
                .accessibilityLabel("Map, \(map.width) by \(map.height) tiles")
                .accessibilityValue(selectionDescription)
                .accessibilityHint("Use the actions to move the selected tile.")
                .accessibilityAction(named: "Select tile to the north") { session.moveSelection(.north) }
                .accessibilityAction(named: "Select tile to the east") { session.moveSelection(.east) }
                .accessibilityAction(named: "Select tile to the south") { session.moveSelection(.south) }
                .accessibilityAction(named: "Select tile to the west") { session.moveSelection(.west) }
                // Centres the map when it is smaller than the viewport.
                .frame(minWidth: proxy.size.width, minHeight: proxy.size.height)
            }
            .background(Color(uiColor: .secondarySystemBackground))
            .overlay(alignment: .bottomTrailing) {
                zoomControls(tileSize: tileSize, fitting: fitting)
            }
        }
    }

    private var selectionDescription: String {
        guard let position = session.selection else { return "No tile selected" }
        return "Tile x \(position.x), y \(position.y), \(session.world.tileSummary(at: position))"
    }

    private func zoomControls(tileSize: Double, fitting: Double) -> some View {
        HStack(spacing: 0) {
            Button {
                zoomedTileSize = MapScale.zoomedOut(from: tileSize, fitting: fitting)
            } label: {
                Image(systemName: "minus.magnifyingglass")
                    .frame(width: 44, height: 44)
            }
            .disabled(tileSize <= MapScale.minimumSize(fitting: fitting))
            .accessibilityLabel("Zoom out")

            Divider().frame(height: 24)

            Button {
                zoomedTileSize = MapScale.zoomedIn(from: tileSize, fitting: fitting)
            } label: {
                Image(systemName: "plus.magnifyingglass")
                    .frame(width: 44, height: 44)
            }
            .disabled(tileSize >= MapScale.largestSize)
            .accessibilityLabel("Zoom in")
        }
        .font(.title3)
        .background(.regularMaterial, in: Capsule())
        .padding(12)
    }
}

/// Draws the whole map and its placed trains in one `Canvas` and turns taps
/// into grid positions.
///
/// Equatable so that game ticks that change only the world's clock do not
/// redraw it; a tick that moves a train does, and the train is drawn where
/// GameCore now has it.
private struct MapCanvas: View, Equatable {
    let map: GridMap
    let trains: [Train]
    let selectedTrainID: TrainID?
    let selection: GridPosition?
    let tileSize: Double
    let session: GameSession

    nonisolated static func == (lhs: MapCanvas, rhs: MapCanvas) -> Bool {
        lhs.map == rhs.map
            && lhs.trains == rhs.trains
            && lhs.selectedTrainID == rhs.selectedTrainID
            && lhs.selection == rhs.selection
            && lhs.tileSize == rhs.tileSize
            && lhs.session === rhs.session
    }

    var body: some View {
        let map = map, trains = trains, selectedTrainID = selectedTrainID
        let selection = selection, tileSize = tileSize
        Canvas { context, _ in
            TileArt.drawMap(
                map,
                trains: trains,
                selectedTrainID: selectedTrainID,
                selection: selection,
                tileSize: tileSize,
                in: context
            )
        }
        .frame(width: tileSize * Double(map.width), height: tileSize * Double(map.height))
        .contentShape(Rectangle())
        .onTapGesture { location in
            session.select(MapScale.position(atX: location.x, y: location.y, tileSize: tileSize))
        }
    }
}
