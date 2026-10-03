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
        .onChange(of: ObjectIdentifier(session)) { _, _ in mapCamera = nil }
    }

    private var tallLayout: some View {
        VStack(spacing: 0) {
            HUDView(session: session, launcher: launcher)
                .padding(.horizontal)
                .padding(.vertical, 10)
                .background(.bar)
            Divider()
            if horizontalSizeClass == .regular {
                // iPad portrait: the whole map across the full width, and
                // the controls get the rest of the height.
                map
                    .aspectRatio(mapAspectRatio, contentMode: .fit)
                    .layoutPriority(1)
                Divider()
                ScrollView {
                    ControlPanel(session: session, arrangement: .sideBySide)
                        .padding()
                }
                .tutorialClip()
                .background(.bar)
            } else {
                map
                Divider()
                ControlPanel(session: session, arrangement: .column)
                    .padding()
                    .background(.bar)
            }
        }
    }

    private var mapAspectRatio: CGFloat {
        let map = session.world.map
        return CGFloat(map.width) / CGFloat(map.height)
    }

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
            .background(.bar)
        }
    }

    private var map: some View {
        MapView(session: session, camera: $mapCamera)
            .tutorialTarget(.map)
            .overlay(alignment: .top) {
                StatusBanner(session: session)
            }
    }
}
