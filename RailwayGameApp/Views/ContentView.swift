import GameCore
import GamePresentation
import SwiftUI

/// The game screen: HUD, map and controls.
///
/// The map has the screen. On a phone in portrait it runs up under the
/// status bar, the HUD floats over its top in glass, and the controls sit
/// in a drawer under it that folds down to the tool picker
/// (``ControlDrawer``). On an iPad either way up, and on a phone on its
/// side, the map fills the screen and the HUD and controls float over its
/// trailing side in a glass card that folds up the same way
/// (``ControlCard``).
struct ContentView: View {
    let session: GameSession
    /// Saves the game and goes back to the start screen (Stage C4).
    let launcher: GameLauncher
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(GameAudio.self) private var audio
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
            if isWide || horizontalSizeClass == .regular {
                cardLayout
            } else {
                phoneLayout
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
        case .settings:
            SettingsView(audio: audio)
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
                    .environment(\.mapInsets, EdgeInsets(top: max(0, phoneHUDBottom - phoneMapTop) + 8, leading: 0, bottom: 0, trailing: 0))
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

    /// iPads either way up, and phones on their side: the map fills the
    /// screen, and the HUD and controls float over its trailing side in a
    /// glass card. The card stops above a real-world map's bottom strip,
    /// whose Apple logo and legal link nothing may cover
    /// (``AppleMapBackground``).
    private var cardLayout: some View {
        GeometryReader { proxy in
            let width = min(Self.cardWidth, (proxy.size.width * Self.cardMaxShare).rounded())
            let strip = RealWorldFrame(world: session.world) == nil ? 0 : AppleMapBackground.attributionHeight
            map
                .environment(\.mapInsets, EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: width + Self.cardMargin))
                .overlay(alignment: .topTrailing) {
                    ControlCard(session: session, launcher: launcher)
                        .frame(width: width)
                        .padding(Self.cardMargin)
                        .padding(.bottom, strip)
                }
        }
    }

    /// The control card's width, as the sidebar it replaces, and the most
    /// of the screen's width it takes on a small phone on its side.
    private static let cardWidth: CGFloat = 360
    private static let cardMaxShare: CGFloat = 0.45
    private static let cardMargin: CGFloat = 10

    private var map: some View {
        MapView(session: session, camera: $mapCamera)
            // A new game is a new map view: its cached track geometry
            // belongs to the world it was drawn from.
            .id(ObjectIdentifier(session))
            // The tutorial outlines, and keeps free, the part of the map that
            // shows: not what the HUD or the control card float over.
            .overlay {
                MapTutorialTarget()
            }
            // The status banner is at the top of the map view, above its
            // construction HUD and traffic key.
    }
}

/// The part of the map the screen's own controls do not float over
/// (``EnvironmentValues/mapInsets``), marked as the tutorial's map.
private struct MapTutorialTarget: View {
    @Environment(\.mapInsets) private var insets

    var body: some View {
        Color.clear
            .padding(insets)
            .tutorialTarget(.map)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// When the controls' details (``ControlPanel``'s details: the selection,
/// the tool's options and the action button) show under the tool picker,
/// in a phone's drawer and in the control card: by themselves when there
/// is something to show (a tool other than Select, a selection) and not
/// otherwise, so the map gets the screen; or as the player chose, until
/// what they would show changes; and always during the tutorial, which
/// points at controls in them.
private enum ControlDetails {
    /// What the details would be about; a change drops the player's choice.
    struct Subject: Equatable {
        let tool: ConstructionTool
        let station: StationID?
        let train: TrainID?
        let hasSelection: Bool

        @MainActor
        init(_ session: GameSession) {
            tool = session.tool
            station = session.selectedStationID
            train = session.tappedTrainID
            hasSelection = session.selectionText() != nil
        }
    }

    /// `choice` is the player's: open or folded, `nil` to follow what
    /// there is to show.
    @MainActor
    static func isOpen(_ session: GameSession, choice: Bool?) -> Bool {
        session.tutorial != nil || (choice ?? (session.tool != .select || session.selectionText() != nil))
    }
}

/// Opens or folds the controls' details. Hidden during the tutorial, when
/// they stay open.
private struct ControlDetailsToggle: View {
    let isOpen: Bool
    /// Whether the details open below the button (the card) or above it
    /// (the drawer).
    let opensDownward: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isOpen == opensDownward ? "chevron.up" : "chevron.down")
                .font(.subheadline.weight(.bold))
                .frame(width: 40, height: 38)
        }
        .buttonStyle(ThemeSelectableButtonStyle(isActive: false))
        .accessibilityLabel(isOpen ? "Hide Controls" : "Show Controls")
        .accessibilityIdentifier("controls.toggle")
    }
}

/// A phone's controls, in glass under the map: the tool picker always, and
/// under it the details when they show (``ControlDetails``).
private struct ControlDrawer: View {
    let session: GameSession
    let detailsHeight: CGFloat
    /// The player's choice: open or folded, `nil` to follow what there is
    /// to show.
    @State private var choice: Bool?

    var body: some View {
        let isOpen = ControlDetails.isOpen(session, choice: choice)
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                ControlPanel(session: session, arrangement: .tools)
                if session.tutorial == nil {
                    ControlDetailsToggle(isOpen: isOpen, opensDownward: false) {
                        choice = !isOpen
                    }
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
        .onChange(of: ControlDetails.Subject(session)) { _, _ in
            choice = nil
        }
    }
}

/// The HUD and the controls on an iPad, or a phone on its side, in a glass
/// card over the map: the HUD and the tool picker always, and under them
/// the details and the network overview when the details show
/// (``ControlDetails``). Open, the card runs down the map's side and its
/// details scroll.
private struct ControlCard: View {
    let session: GameSession
    let launcher: GameLauncher
    /// The player's choice: open or folded, `nil` to follow what there is
    /// to show.
    @State private var choice: Bool?

    var body: some View {
        let isOpen = ControlDetails.isOpen(session, choice: choice)
        VStack(alignment: .leading, spacing: 12) {
            HUDView(session: session, launcher: launcher)
            HStack(spacing: 8) {
                ControlPanel(session: session, arrangement: .tools)
                if session.tutorial == nil {
                    ControlDetailsToggle(isOpen: isOpen, opensDownward: true) {
                        choice = !isOpen
                    }
                }
            }
            if isOpen {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ControlPanel(session: session, arrangement: .details)
                        Divider()
                        NetworkOverview(session: session)
                    }
                }
                .tutorialClip()
                .transition(.opacity)
            }
        }
        .padding(14)
        .glassBackground(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .animation(.easeInOut(duration: 0.2), value: isOpen)
        .onChange(of: ControlDetails.Subject(session)) { _, _ in
            choice = nil
        }
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
        // Settings is a panel too: a sheet of the HUD's own could not show
        // while Lines or Station is open (the HUD stays usable behind them)
        // and closed when turning the device rebuilt the HUD.
        case lines, economy, station, timetable, fleet, mapLayers, dataSources, settings

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
