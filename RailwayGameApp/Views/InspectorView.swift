import GameCore
import GamePresentation
import SwiftUI

/// Shows the selected station, read from the world (Stage F1; see
/// `GameSession.selectionText()`); with the network tool (Stage C1), what
/// its taps have picked instead. On a station, a button opens its
/// ridership (Stage C2).
struct InspectorView: View {
    let session: GameSession
    @Environment(GameScreenState.self) private var screen

    var body: some View {
        inspector
            .themeCard(padding: 10, cornerRadius: 12)
    }

    @ViewBuilder
    private var inspector: some View {
        if session.tool == .network {
            HStack(alignment: .center, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Theme.primary.opacity(0.14))
                        .frame(width: 30, height: 30)
                    Image(systemName: "pencil.and.ruler.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.primary)
                }
                .accessibilityHidden(true)

                Text(session.networkDraftText())
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
        } else {
            selectionInspector
        }
    }

    private var selectionInspector: some View {
        HStack(spacing: 10) {
            HStack(spacing: 10) {
                if let text = session.selectionText() {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Theme.accent)
                            .frame(width: 30, height: 30)
                        Image(systemName: "tram.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Theme.onAccent)
                    }
                    .accessibilityHidden(true)

                    Text(verbatim: text)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        // Three lines: in a phone's card "Station · Ruifang ·
                        // 2 platforms, 128 m" took two and lost its end.
                        .lineLimit(3)
                        .truncationMode(.tail)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Theme.panelBorder)
                            .frame(width: 30, height: 30)
                        Image(systemName: "scope")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .accessibilityHidden(true)

                    Text("Tap a station to select it.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            if session.selectedStation != nil {
                Button {
                    screen.panel = .station
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "person.2.fill")
                            .font(.caption.weight(.bold))
                        Text("Ridership")
                            .font(.caption.weight(.semibold))
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 30)
                }
                .buttonStyle(ThemeSelectableButtonStyle(isActive: screen.panel == .station))
                .accessibilityLabel("Ridership")
                .accessibilityHint("Shows the station's ridership: what kind of place it serves, its trips and its passengers.")
            }
        }
    }
}
