import GameCore
import GamePresentation
import SwiftUI

/// The game screen: HUD, map and controls.
///
/// Tall screens (phones, and iPads in portrait) stack the map above the
/// controls; wide screens put the controls in a sidebar next to the map.
struct ContentView: View {
    let session: GameSession

    var body: some View {
        GeometryReader { proxy in
            if proxy.size.width > proxy.size.height {
                wideLayout
            } else {
                tallLayout
            }
        }
    }

    private var tallLayout: some View {
        VStack(spacing: 0) {
            HUDView(session: session)
                .padding(.horizontal)
                .padding(.vertical, 10)
                .background(.bar)
            Divider()
            MapView(session: session)
            Divider()
            controls
                .padding()
                .background(.bar)
        }
    }

    private var wideLayout: some View {
        HStack(spacing: 0) {
            MapView(session: session)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HUDView(session: session)
                    Divider()
                    controls
                }
                .padding()
            }
            .frame(width: 340)
            .background(.bar)
        }
    }

    private var controls: some View {
        InspectorView(session: session)
    }
}
