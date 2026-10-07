import GameCore
import GamePresentation
import SwiftUI

/// The game screen: HUD, map and controls.
///
/// Tall screens stack the map above the controls (on iPad the controls then
/// sit side by side); wide screens put the controls in a sidebar next to the
/// map.
struct ContentView: View {
    let session: GameSession
    /// Saves the game and goes back to the start screen (Stage C4).
    let launcher: GameLauncher
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var isWide = false
    /// Lives above both layouts: switching them must not discard the camera.
    @State private var mapCamera: PlanCamera?
    /// The open panel and the map's layer settings, above both layouts for
    /// the same reason: turning the device swaps them and rebuilds every
    /// view under them.
    @State private var screen = GameScreenState()

    var body: some View {
        Group {
            if isWide {
                wideLayout
            } else {
                tallLayout
            }
        }
        .background {
            // Measured ignoring the keyboard: otherwise typing a station name
            // on an iPad in portrait would flip the layout and end editing.
            GeometryReader { proxy in
                Color.clear
                    .onChange(of: proxy.size, initial: true) { _, size in
                        isWide = size.width > size.height
                    }
            }
            .ignoresSafeArea(.keyboard)
        }
        // Inside the text size limit below: the tutorial's card shares the
        // screen with the controls it must not cover.
        .tutorialOverlay(session: session)
        // The map and controls share one screen, so text stops growing at the
        // largest standard size instead of pushing the map off screen.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        // Presented from here, above both layouts, so a layout switch
        // neither closes the panel nor loses what is typed in it.
        .sheet(item: $screen.panel) { panel in
            panelSheet(panel)
        }
        .environment(screen)
        .onChange(of: ObjectIdentifier(session)) { _, _ in
            mapCamera = nil
            screen.stopPopTravelPlay()
            screen = GameScreenState()
        }
        .onDisappear {
            screen.stopPopTravelPlay()
        }
    }

    @ViewBuilder
    private func panelSheet(_ panel: GameScreenState.Panel) -> some View {
        switch panel {
        case .lines:
            LinesPanel(session: session)
                .presentationDetents([.medium, .large])
                // The map stays usable behind the half-height sheet, so
                // stations can be selected for a new line.
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        case .economy:
            EconomyPanel(session: session)
                .presentationDetents([.medium, .large])
        case .station:
            StationPanel(session: session)
                .presentationDetents([.medium, .large])
                // The map stays usable behind the half-height sheet, so
                // another station can be selected.
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        case .timetable:
            TimetableEditor(session: session)
                .presentationDetents([.medium, .large])
        case .fleet:
            FleetOverviewSheet(session: session)
        case .mapLayers:
            StoredMapLayerSheet()
        case .dataSources:
            DataSourcesView(language: session.language)
        }
    }

    private var tallLayout: some View {
        VStack(spacing: 0) {
            HUDView(session: session, launcher: launcher)
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
            Divider()
            if horizontalSizeClass == .regular {
                // iPad portrait: the whole map across the full width, and
                // the controls get the rest of the height.
                map
                    .aspectRatio(Self.mapAspectRatio, contentMode: .fit)
                    .layoutPriority(1)
                Divider()
                ScrollView {
                    ControlPanel(session: session, arrangement: .sideBySide)
                        .padding()
                }
                .tutorialClip()
                .background(.ultraThinMaterial)
            } else {
                // Phones: the map keeps a fixed share of the height and the
                // controls scroll below it. When the map took whatever the
                // controls left, text that changes length as the game runs
                // (a train's status and riders) resized it every game
                // minute, and what it showed slid up and down; and controls
                // taller than the space left were drawn over one another.
                GeometryReader { proxy in
                    VStack(spacing: 0) {
                        map
                            .frame(height: (proxy.size.height * Self.phoneMapShare).rounded())
                        Divider()
                        ScrollView {
                            ControlPanel(session: session, arrangement: .column)
                                .padding()
                        }
                        .tutorialClip()
                        .background(.ultraThinMaterial)
                    }
                }
            }
        }
    }

    /// The share of the height under the HUD the map keeps on a phone.
    private static let phoneMapShare: CGFloat = 0.5

    /// The map view's shape on an iPad in portrait: 4:3, the shape of the
    /// 32 × 24 map before Stage E1. The view is a window on the map now, so
    /// a new game's square 16 km map does not take the controls' room.
    private static let mapAspectRatio: CGFloat = 4.0 / 3.0

    private var wideLayout: some View {
        HStack(spacing: 0) {
            map
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HUDView(session: session, launcher: launcher)
                    Divider()
                    ControlPanel(session: session, arrangement: .column)
                    Divider()
                    NetworkOverview(session: session)
                }
                .padding()
            }
            .tutorialClip()
            .frame(width: 360)
            .background(.ultraThinMaterial)
        }
    }

    private var map: some View {
        MapView(session: session, camera: $mapCamera)
            // A new game is a new map view: its cached track geometry
            // belongs to the world it was drawn from.
            .id(ObjectIdentifier(session))
            .tutorialTarget(.map)
            // The status banner is at the top of the map view, above its
            // construction HUD and traffic key.
    }
}

/// What the game screen shows besides the world: the panel that is open and
/// the population and travel layer's opacity, hour and playback. View state
/// only, never game state; it lives above the tall and wide layouts
/// (``ContentView``), so turning the device closes no panel and resets no
/// layer setting.
@MainActor
@Observable
final class GameScreenState {
    /// The sheets the game screen presents, one at a time.
    enum Panel: String, Identifiable {
        case lines, economy, station, timetable, fleet, mapLayers, dataSources

        var id: Self { self }
    }

    var panel: Panel?
    /// The layer's opacity once the player has moved its slider (the
    /// reference's `_popTravelOpacityUserSet`); until then each layer's own
    /// (``PopTravel/baseOpacity(for:compactWidth:)``).
    var popTravelOpacity: Double?
    /// The timeline's hour, and whether it plays (the reference's
    /// `G.popTravelHour` and `G.popTravelPlaying`).
    var popTravelHour = PopTravel.defaultHour
    private(set) var isPlayingPopTravel = false
    @ObservationIgnored private var popTravelPlay: Task<Void, Never>?

    /// Play: the next hour every 1.2 s, back to 0 after 23
    /// (`startPopTravelPlay`).
    func startPopTravelPlay() {
        guard popTravelPlay == nil else { return }
        isPlayingPopTravel = true
        popTravelPlay = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: PopTravel.playInterval)
                guard !Task.isCancelled, let self else { return }
                self.popTravelHour = PopTravel.nextHour(after: self.popTravelHour)
            }
        }
    }

    func stopPopTravelPlay() {
        popTravelPlay?.cancel()
        popTravelPlay = nil
        isPlayingPopTravel = false
    }
}
