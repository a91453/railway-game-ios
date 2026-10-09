import GameCore
import GamePresentation
import SwiftUI

/// The lines calling at the selected station, under its nameboard
/// (ARCHITECTURE decision 112): a tag in each line's colour that opens the
/// line, and one that starts a new line here, its other end tapped next on
/// the map. The tags wrap onto more rows (decision 123): a row that
/// scrolled sideways showed its last tag cut in two, as if it were broken.
/// The owner's site marks a stop's transfers with a bordered tag the same
/// way (`Railway/site_archive_clean/index.html`, `.xfer-tag`).
struct StationLineChips: View {
    let session: GameSession
    let station: Station
    @Environment(GameScreenState.self) private var screen

    var body: some View {
        ChipFlow(spacing: 6) {
            ForEach(session.world.lines(callingAt: station.id), id: \.id) { line in
                chip(line)
            }
            newLine
        }
        .padding(.vertical, 2)
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

/// Lays its views out in rows, left to right, starting a new row when the
/// next one would pass the width it is offered.
private struct ChipFlow: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(subviews, width: proposal.width ?? .infinity)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                    proposal: ProposedViewSize(width: min(size.width, bounds.width), height: size.height)
                )
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            if !row.indices.isEmpty, needed > width {
                rows.append(row)
                row = Row()
            }
            row.width = row.indices.isEmpty ? min(size.width, width) : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
        }
        if !row.indices.isEmpty { rows.append(row) }
        return rows
    }
}
