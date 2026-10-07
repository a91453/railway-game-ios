import GameCore
import GamePresentation
import SwiftUI

/// The game screen: HUD, map and controls.
///
/// Phones in portrait give the map the screen: it runs up under the status
/// bar, the HUD floats over its top in glass, and the controls sit in a
/// drawer under it that folds down to the tool picker (``ControlDrawer``).
/// iPads in portrait stack the map above the controls, which sit side by
/// side; wide screens put the controls in a sidebar next to the map.
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
    /// Where a phone's map starts and its floating HUD ends, in the game
    /// screen's coordinates (``screenSpace``): how far down the map's own
    /// banners start.
    @State private var phoneMapTop: CGFloat = 0
    @State private var phoneHUDBottom: CGFloat = 0

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
            DataSourcesView(launcher: launcher)
        }
    }

    @ViewBuilder
    private var tallLayout: some View {
        if horizontalSizeClass == .regular {
            // iPad portrait: the whole map across the full width, and the
            // controls get the rest of the height.
            VStack(spacing: 0) {
                HUDView(session: session, launcher: launcher)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                Divider()
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
            }
        } else {
            phoneLayout
        }
    }

    /// Phones in portrait: the map from the top of the screen down to the
    /// control drawer, with the HUD floating over it in glass. The map ends
    /// where the drawer starts rather than running under it too: a
    /// real-world map's bottom strip holds Apple's logo and legal link,
    /// which nothing may cover (``AppleMapBackground``).
    private var phoneLayout: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                map
                    .environment(\.mapTopInset, max(0, phoneHUDBottom - phoneMapTop) + 8)
                    .onGeometryChange(for: CGFloat.self) { geometry in
                        geometry.frame(in: .named(Self.screenSpace)).minY
                    } action: { top in
                        phoneMapTop = top
                    }
                    .ignoresSafeArea(.container, edges: .top)
                ControlDrawer(
                    session: session,
                    detailsHeight: (proxy.size.height * Self.phoneDetailsShare).rounded()
                )
            }
        }
        .overlay(alignment: .top) {
            HUDView(session: session, launcher: launcher)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .glassBackground(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .padding(.horizontal, 8)
                .onGeometryChange(for: CGFloat.self) { geometry in
                    geometry.frame(in: .named(Self.screenSpace)).maxY
                } action: { bottom in
                    phoneHUDBottom = bottom
                }
        }
        .coordinateSpace(.named(Self.screenSpace))
    }

    /// The share of the height an open control drawer's details take on a
    /// phone. A fixed share, not their own height: text that changes
    /// length as the game runs (a train's status and riders) would resize
    /// the map every game minute, and what it showed would slide up and
    /// down.
    private static let phoneDetailsShare: CGFloat = 0.42

    /// The game screen's coordinates, in which a phone's HUD and map are
    /// measured.
    private nonisolated static let screenSpace = "gameScreen"

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

/// A phone's controls, in glass under the map: the tool picker always, and
/// under it what the tool and the selection need (``ControlPanel``'s
/// details). The details open by themselves when there is something to
/// show (a tool other than Select, a selection, the tutorial) and fold
/// away when there is not, so the map gets the screen; the player can open
/// or fold them too, until what they would show changes.
private struct ControlDrawer: View {
    let session: GameSession
    let detailsHeight: CGFloat
    /// The player's choice: open or folded, `nil` to follow ``hasDetails``.
    @State private var choice: Bool?

    /// What the details would be about; a change drops the player's choice.
    private struct Subject: Equatable {
        let tool: ConstructionTool
        let station: StationID?
        let train: TrainID?
        let hasSelection: Bool
    }

    private var subject: Subject {
        Subject(
            tool: session.tool,
            station: session.selectedStationID,
            train: session.tappedTrainID,
            hasSelection: session.selectionText() != nil
        )
    }

    private var hasDetails: Bool {
        session.tool != .select || session.selectionText() != nil
    }

    /// The tutorial points at controls in the details, so they stay open
    /// while it runs.
    private var isOpen: Bool {
        session.tutorial != nil || (choice ?? hasDetails)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                ControlPanel(session: session, arrangement: .tools)
                if session.tutorial == nil {
                    toggle
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            if isOpen {
                ScrollView {
                    ControlPanel(session: session, arrangement: .details)
                        .padding(.horizontal)
                        .padding(.bottom)
                }
                .tutorialClip()
                .frame(height: detailsHeight)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background {
            Color.clear
                .glassBackground(in: Rectangle())
                .ignoresSafeArea(.container, edges: .bottom)
        }
        .overlay(alignment: .top) {
            Divider()
        }
        .animation(.easeInOut(duration: 0.2), value: isOpen)
        .onChange(of: subject) { _, _ in
            choice = nil
        }
    }

    private var toggle: some View {
        Button {
            choice = !isOpen
        } label: {
            Image(systemName: isOpen ? "chevron.down" : "chevron.up")
                .font(.subheadline.weight(.bold))
                .frame(width: 40, height: 38)
        }
        .buttonStyle(ThemeSelectableButtonStyle(isActive: false))
        .accessibilityLabel(isOpen ? "Hide Controls" : "Show Controls")
        .accessibilityIdentifier("controls.toggle")
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
