import GameCore
import GamePresentation
import SwiftUI

/// Shows the selected tile's coordinates and contents, read from the world;
/// with the network tool (Stage C1), what its taps have picked instead. On
/// a station, a button opens its ridership (Stage C2).
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
            tileInspector
        }
    }

    private var tileInspector: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "scope")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                if let position = session.selection {
                    Text(verbatim: "x \(position.x), y \(position.y)")
                        .monospacedDigit()
                        .fontWeight(.semibold)
                    Text(summary(at: position))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                } else {
                    Text("Tap a tile to select it.")
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

    /// The tile's contents and, at a station, who waits there by line and
    /// direction (G1c).
    private func summary(at position: GridPosition) -> String {
        let text = session.world.tileSummary(at: position, in: session.language)
        guard case .station(let id)? = session.world.map.tile(at: position)?.type,
              let waiting = session.world.waitingSummary(at: id, in: session.language)
        else { return text }
        return "\(text) · \(waiting)"
    }
}
