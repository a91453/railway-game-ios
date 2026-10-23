import GameCore
import GamePresentation
import SwiftUI

/// While a new line's stations are picked on the map, the last two picked
/// side by side (ARCHITECTURE decision 224, option 3B,
/// `a91453/railway-reference-private: Railway/game-art-previews/docs/art/railway-ui-redesign-2026-10-14/s3-*.png`): their names with
/// the distance and running time between them on a warm stamp, and each
/// figure as two bars growing out from the middle, navy for the first and
/// teal for the second, the figure at each end. Folds to its top line.
/// ``StationPairComparison`` works it out (a trial line's path), off the
/// main actor, each time the pair changes.
struct StationPairDrawer: View {
    let session: GameSession
    let from: StationID
    let to: StationID
    @State private var comparison: StationPairComparison?
    @State private var isFolded: Bool
    private let startsFolded: Bool

    /// `startsFolded`: whether it opens folded to its top line
    /// (``StationPairDrawerLayout/startsFolded(compactHeight:)``).
    init(session: GameSession, from: StationID, to: StationID, startsFolded: Bool = false) {
        self.session = session
        self.from = from
        self.to = to
        self.startsFolded = startsFolded
        _isFolded = State(initialValue: startsFolded)
    }

    private struct Pair: Hashable {
        let from: StationID
        let to: StationID
        let edits: Int
    }

    var body: some View {
        let language = session.language
        VStack(spacing: 6) {
            if let comparison {
                header(comparison, language: language)
                if !isFolded {
                    ForEach(comparison.measures, id: \.self) { measure in
                        bars(measure, comparison, language: language)
                    }
                }
            } else {
                ProgressView()
                    .frame(height: 28)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: StationPairDrawerLayout.maximumWidth)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Palette.ink, lineWidth: 1.5))
        .onChange(of: to) {
            // Decision 384: folded again for each station picked, so the
            // map's ✓ beside it has room on a short screen.
            if startsFolded { isFolded = true }
        }
        .task(id: Pair(from: from, to: to, edits: session.editSerial)) {
            let world = session.world
            let (a, b) = (from, to)
            comparison = await Task.detached(priority: .userInitiated) {
                StationPairComparison(world: world, from: a, to: b)
            }.value
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("map.stationPair")
    }

    private func header(_ comparison: StationPairComparison, language: DisplayLanguage) -> some View {
        HStack(spacing: 8) {
            swatch(Theme.textPrimary)
            Text(verbatim: comparison.from.name)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 4)
            VStack(spacing: 0) {
                Text(verbatim: comparison.distanceText(in: language))
                    .font(.subheadline.weight(.heavy).monospacedDigit())
                Text(verbatim: comparison.timeText(in: language))
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(Theme.onAccent)
            .padding(.horizontal, 12)
            .padding(.vertical, 3)
            .background(Theme.accent, in: Capsule())
            .overlay(Capsule().strokeBorder(Palette.ink, lineWidth: 1.5))
            .accessibilityElement(children: .combine)
            Spacer(minLength: 4)
            Text(verbatim: comparison.to.name)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            swatch(Theme.primary)
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isFolded.toggle() }
            } label: {
                Image(systemName: isFolded ? "chevron.up" : "chevron.down")
                    .font(.caption.weight(.bold))
                    .frame(width: 32, height: 32)
                    .background(Theme.chip, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(verbatim: isFolded ? language.text("Show the comparison", "展開比較") : language.text("Fold the comparison", "收起比較")))
            .accessibilityIdentifier("map.stationPair.fold")
        }
        .foregroundStyle(Theme.textPrimary)
    }

    /// A square of the side's colour, so the bars' colours have a key.
    private func swatch(_ color: Color) -> some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(color)
            .frame(width: 12, height: 12)
            .accessibilityHidden(true)
    }

    /// One figure: the first station's bar growing left from the middle,
    /// the second's growing right, the figures at the outer ends.
    private func bars(_ measure: StationPairComparison.Measure, _ comparison: StationPairComparison, language: DisplayLanguage) -> some View {
        HStack(spacing: 6) {
            Text(verbatim: StationPairComparison.valueText(comparison.from.value(measure)))
                .font(.caption.weight(.bold).monospacedDigit())
                .frame(width: 52, alignment: .trailing)
            GeometryReader { proxy in
                Capsule()
                    .fill(Theme.textPrimary)
                    .frame(width: proxy.size.width * comparison.fraction(measure, of: comparison.from))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .frame(height: 9)
            Text(verbatim: measure.title(in: language))
                .font(.caption2.weight(.heavy))
                .frame(width: 58)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            GeometryReader { proxy in
                Capsule()
                    .fill(Theme.primary)
                    .frame(width: proxy.size.width * comparison.fraction(measure, of: comparison.to))
            }
            .frame(height: 9)
            Text(verbatim: StationPairComparison.valueText(comparison.to.value(measure)))
                .font(.caption.weight(.bold).monospacedDigit())
                .frame(width: 52, alignment: .leading)
        }
        .foregroundStyle(Theme.textPrimary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(measure.title(in: language)): \(comparison.from.name) \(StationPairComparison.valueText(comparison.from.value(measure))), \(comparison.to.name) \(StationPairComparison.valueText(comparison.to.value(measure)))"))
    }
}
