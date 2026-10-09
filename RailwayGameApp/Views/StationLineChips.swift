import GameCore
import GamePresentation
import SwiftUI

/// The lines calling at the selected station, under its nameboard
/// (ARCHITECTURE decision 112): a tag in each line's colour that opens the
/// line, and one that starts a new line here, its other end tapped next on
/// the map. A row that scrolls sideways when the station has many lines.
/// The owner's site marks a stop's transfers with a bordered tag the same
/// way (`Railway/site_archive_clean/index.html`, `.xfer-tag`).
struct StationLineChips: View {
    let session: GameSession
    let station: Station
    @Environment(GameScreenState.self) private var screen

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(session.world.lines(callingAt: station.id), id: \.id) { line in
                    chip(line)
                }
                newLine
            }
            .padding(.vertical, 2)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
    }

    private func chip(_ line: ServiceLine) -> some View {
        let color = Palette.lineColor(line.id, custom: line.color)
        return Button {
            session.selectLine(line.id)
            screen.panel = .lines
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 10, height: 10)
                Text(verbatim: line.name)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 32)
            .background(Theme.panel, in: Capsule())
            .overlay(Capsule().strokeBorder(color, lineWidth: 2))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: line.name))
        .accessibilityHint(Text(verbatim: session.language.text("Opens the line.", "打開這條路線。")))
    }

    private var newLine: some View {
        Button {
            session.startLineFromSelectedStation()
            screen.panel = .lines
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(.caption.weight(.bold))
                Text(verbatim: session.language.text("New line from here", "從這站開新路線"))
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 32)
        }
        .buttonStyle(ThemeSelectableButtonStyle(isActive: false))
        .accessibilityIdentifier("station.newLine")
    }
}
