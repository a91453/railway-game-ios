import GameCore
import GamePresentation
import SwiftUI

/// Shows the selected tile's coordinates and contents, read from the world.
struct InspectorView: View {
    let session: GameSession

    var body: some View {
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
            Spacer(minLength: 0)
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
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
