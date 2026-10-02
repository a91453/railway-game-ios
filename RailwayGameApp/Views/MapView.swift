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
                    world: session.world,
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
        guard let position = session.selection else { return String(localized: "No tile selected") }
        let summary = session.world.tileSummary(at: position, in: session.language)
        return String(localized: "Tile x \(position.x), y \(position.y), \(summary)")
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

/// Draws the whole map, the track network and the placed trains in one
/// `Canvas` and turns taps into grid positions.
///
/// Equatable so that game ticks that change only the world's clock do not
/// redraw it (only the map, the track network and the trains are drawn); a
/// tick that moves a train does, and the train is drawn where GameCore now
/// has it.
private struct MapCanvas: View, Equatable {
    let world: GameWorld
    let selectedTrainID: TrainID?
    let selection: GridPosition?
    let tileSize: Double
    let session: GameSession

    nonisolated static func == (lhs: MapCanvas, rhs: MapCanvas) -> Bool {
        lhs.world.map == rhs.world.map
            && lhs.world.trains == rhs.world.trains
            && lhs.world.network == rhs.world.network
            && lhs.selectedTrainID == rhs.selectedTrainID
            && lhs.selection == rhs.selection
            && lhs.tileSize == rhs.tileSize
            && lhs.session === rhs.session
    }

    var body: some View {
        let world = world, selectedTrainID = selectedTrainID
        let selection = selection, tileSize = tileSize
        Canvas { context, _ in
            TileArt.drawMap(
                world,
                selectedTrainID: selectedTrainID,
                selection: selection,
                tileSize: tileSize,
                in: context
            )
        }
        .frame(width: tileSize * Double(world.map.width), height: tileSize * Double(world.map.height))
        .contentShape(Rectangle())
        .onTapGesture { location in
            session.select(MapScale.position(atX: location.x, y: location.y, tileSize: tileSize))
        }
    }
}
