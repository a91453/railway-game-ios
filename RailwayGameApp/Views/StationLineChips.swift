import GameCore
import GamePresentation
import SwiftUI

/// The lines calling at the selected station, under its nameboard
/// (ARCHITECTURE decision 112): a tag in each line's colour that opens the
/// line, and one that starts a new line here, its other end tapped next on
/// the map and the line made there (decision 100, later). The tags wrap onto more rows (decision 123): a row that
/// scrolled sideways showed its last tag cut in two, as if it were broken.
/// The owner's site marks a stop's transfers with a bordered tag the same
/// way (`Railway/site_archive_clean/index.html`, `.xfer-tag`).
struct StationLineChips: View {
    let session: GameSession
    let station: Station
    @Environment(GameScreenState.self) private var screen

    /// Decision 216: redraws the tags when the line palette changes.
    @AppStorage(LinePalette.key) private var linePalette: LinePalette = .standard

    var body: some View {
        let codes = LineBadge.codes(for: session.world.lines)
        return ChipFlow(spacing: 6) {
            ForEach(session.world.lines(callingAt: station.id), id: \.id) { line in
                chip(line, codes: codes)
            }
            newLine
        }
        .padding(.vertical, 2)
    }

    private func chip(_ line: ServiceLine, codes: [LineID: String]) -> some View {
        let color = Palette.lineColor(line.id, custom: line.color)
        return Button {
            session.selectLine(line.id)
            screen.panel = .lines
        } label: {
            HStack(spacing: 6) {
                // Decision 216: the line's code on its badge, where a dot
                // of its colour was.
                LineCodeBadge(code: codes[line.id] ?? "", color: color, size: .small)
                Text(verbatim: line.name)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                // Decision 168: a high-speed line's tag carries a bolt.
                if line.isHighSpeed {
                    Image(systemName: "bolt.fill")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 32)
            .background(Theme.panel, in: Capsule())
            .overlay(Capsule().strokeBorder(color, lineWidth: 2))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: line.isHighSpeed ? session.language.text("\(line.name), high-speed", "\(line.name)，高鐵") : line.name))
        .accessibilityHint(Text(verbatim: session.language.text("Opens the line.", "打開這條路線。")))
    }

    private var newLine: some View {
        // Decision 100, later: the line is picked and made on the map,
        // beside its last station; the lines panel opens once it is made.
        Button {
            session.startLineFromSelectedStation()
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

/// Decision 214 (`docs/UI_THEME.md` 機廠): a pale capsule with the depot's
/// garage, saying a train or a line's trains stand in their depot, or are
/// leaving or entering it: the fleet list, the train card and the line
/// panel.
struct DepotBadge: View {
    let text: String
    var glyph: MapGlyph = .depot

    init(text: String, glyph: MapGlyph = .depot) {
        self.text = text
        self.glyph = glyph
    }

    init(_ state: TrainDepotState, language: DisplayLanguage) {
        text = state.text(in: language)
        switch state {
        case .pullingOut: glyph = .depotOut
        case .pullingIn: glyph = .depotIn
        case .inDepot: glyph = .depot
        }
    }

    var body: some View {
        HStack(spacing: 3) {
            glyph.image
                .resizable()
                .scaledToFit()
                .frame(width: 13, height: 13)
                .accessibilityHidden(true)
            Text(verbatim: text)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(Theme.textSecondary)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Theme.chip)
        .clipShape(Capsule())
        .accessibilityElement(children: .combine)
    }
}

/// A line's badge (ARCHITECTURE decision 216, `docs/UI_THEME.md` 線號徽章):
/// a white tag edged in navy (``Palette/markerFill``, ``Palette/ink``), a
/// patch of the line's colour at its left, and the line's code in navy,
/// which reads 13.29:1 (9.64:1 dark) whatever the line's colour, so lines
/// tell themselves apart by their codes and not by colour alone.
struct LineCodeBadge: View {
    enum Size {
        /// 14 points high, the code 9 points: beside a line's name in a
        /// list or a tag (the reference's `station-line-chip`).
        case small
        /// 18 points high, the code 11 points: a line's own row or card.
        case regular

        var height: CGFloat { self == .small ? 14 : 18 }
        var font: CGFloat { self == .small ? 9 : 11 }
    }

    let code: String
    let color: Color
    var size: Size = .regular

    var body: some View {
        let height = size.height
        let corner = height * 0.22
        HStack(spacing: 0) {
            color
                .frame(width: height * 0.42)
            Rectangle()
                .fill(Palette.ink)
                .frame(width: 1)
            Text(verbatim: code)
                .font(.system(size: size.font, weight: .heavy, design: .rounded))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, height * 0.21)
                .frame(minWidth: height * 0.9)
        }
        .frame(height: height)
        .background(Palette.markerFill)
        .clipShape(RoundedRectangle(cornerRadius: corner))
        .overlay(RoundedRectangle(cornerRadius: corner).strokeBorder(Palette.ink, lineWidth: 1.5))
        // Its own font: the badge keeps its size with Dynamic Type, as the
        // map's does, and the line's name beside it carries the reading.
        .accessibilityHidden(true)
    }
}
