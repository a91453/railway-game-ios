import GameCore
import GamePresentation
import SwiftUI

/// Shows the selected station, read from the world (Stage F1; see
/// `GameSession.selectionText()`); with the network tool (Stage C1), what
/// its taps have picked instead. On a station, a button opens its
/// ridership (Stage C2).
struct InspectorView: View {
    let session: GameSession
    @State private var showsStation = false

    var body: some View {
        inspector
            .sheet(isPresented: $showsStation) {
                StationPanel(session: session)
                    .presentationDetents([.medium, .large])
                    // The map stays usable behind the half-height sheet, so
                    // another station can be selected.
                    .presentationBackgroundInteraction(.enabled(upThrough: .medium))
            }
    }

    @ViewBuilder
    private var inspector: some View {
        if session.tool == .network {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "scope")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(session.networkDraftText())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .font(.subheadline)
            .accessibilityElement(children: .combine)
        } else {
            selectionInspector
        }
    }

    private var selectionInspector: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "scope")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                if let text = session.selectionText() {
                    Text(verbatim: text)
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Tap a station to select it.")
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            if session.selectedStation != nil {
                Button {
                    showsStation = true
                } label: {
                    Image(systemName: "person.2.fill")
                        .font(.subheadline.weight(.bold))
                        .frame(width: 44, height: 28)
                }
                .buttonStyle(SelectableButtonStyle(isActive: showsStation))
                .accessibilityLabel("Ridership")
                .accessibilityHint("Shows the station's ridership: what kind of place it serves, its trips and its passengers.")
            }
        }
        .font(.subheadline)
    }
}
