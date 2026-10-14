import GameCore
import GamePresentation
import SwiftUI

/// The company's titles as a line (ARCHITECTURE decision 224, option 1C,
/// `docs/art/railway-ui-redesign-2026-10-14/s1-*.png`): each title a
/// station, the ones reached filled navy, the line teal as far as the
/// score has come, and the company's train on a warm disc where it
/// stands. The title held and the next are named; the rest are dots.
struct PromotionLineView: View {
    let line: PromotionLine
    let language: DisplayLanguage

    var body: some View {
        GeometryReader { proxy in
            let count = line.titles.count
            let inset: CGFloat = 14
            let width = proxy.size.width - 2 * inset
            let x = { (index: Double) in inset + width * index / Double(max(1, count - 1)) }
            ZStack(alignment: .topLeading) {
                Capsule()
                    .fill(Theme.chip)
                    .overlay(Capsule().strokeBorder(Palette.ink, lineWidth: 1.5))
                    .frame(width: width, height: 8)
                    .offset(x: inset, y: 10)
                Capsule()
                    .fill(Theme.primary)
                    .overlay(Capsule().strokeBorder(Palette.ink, lineWidth: 1.5))
                    .frame(width: max(8, x(line.position) - inset), height: 8)
                    .offset(x: inset, y: 10)
                ForEach(Array(line.titles.enumerated()), id: \.offset) { index, title in
                    let reached = line.isReached(index)
                    Circle()
                        .fill(reached ? Palette.ink : Palette.markerFill)
                        .overlay(Circle().strokeBorder(Palette.ink, lineWidth: 2))
                        .frame(width: 14, height: 14)
                        .offset(x: x(Double(index)) - 7, y: 7)
                    if index == Int(line.position) || index == Int(line.position) + 1 {
                        Text(verbatim: title.title(in: language))
                            .font(.system(size: 10, weight: index == Int(line.position) ? .heavy : .medium))
                            .foregroundStyle(index == Int(line.position) ? Theme.textPrimary : Theme.textSecondary)
                            .fixedSize()
                            .frame(width: 80)
                            .offset(x: min(max(0, x(Double(index)) - 40), proxy.size.width - 80), y: 26)
                    }
                }
                MapGlyph.train.image
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
                    .foregroundStyle(Palette.stationSymbol)
                    .frame(width: 28, height: 28)
                    .background(Palette.station, in: Circle())
                    .overlay(Circle().strokeBorder(Palette.ink, lineWidth: 2))
                    .offset(x: x(line.position) - 14, y: 0)
            }
        }
        .frame(height: 44)
        .accessibilityHidden(true)
    }
}

/// The rank's seven measures as the cars of a train (decision 224, 1C):
/// each car names its measure, its points out of its full marks, and six
/// squares filled as far as the points go; a coupler between the cars,
/// the last car's nose rounded, wheels under them and the track below.
struct ScoreTrainView: View {
    let rank: CompanyRank
    let language: DisplayLanguage

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(Array(rank.parts.enumerated()), id: \.offset) { index, part in
                        car(part, isFront: index == rank.parts.count - 1)
                    }
                }
                Capsule()
                    .fill(Palette.track)
                    .frame(height: 5)
                    .padding(.top, 2)
            }
            .padding(.vertical, 4)
        }
    }

    private func car(_ part: CompanyRank.Part, isFront: Bool) -> some View {
        let shape = UnevenRoundedRectangle(cornerRadii: .init(topLeading: 6, bottomLeading: 6, bottomTrailing: 6,
                                                               topTrailing: isFront ? 18 : 6), style: .continuous)
        return VStack(alignment: .leading, spacing: 3) {
            Text(verbatim: part.measure.title(in: language))
                .font(.system(size: 10, weight: .heavy))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(verbatim: "\(part.points)")
                    .font(.headline.monospacedDigit())
                Text(verbatim: "/\(part.maximum)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Theme.textSecondary)
            }
            HStack(spacing: 2) {
                let filled = part.filledCells(of: 6)
                ForEach(0..<6, id: \.self) { cell in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(cell < filled ? Theme.primary : Theme.chip)
                        .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(Theme.panelBorder, lineWidth: 1))
                        .frame(height: 8)
                }
            }
        }
        .foregroundStyle(Theme.textPrimary)
        .padding(.horizontal, 7)
        .padding(.vertical, 6)
        .frame(width: 92, height: 74, alignment: .topLeading)
        .background(Theme.panel, in: shape)
        .overlay(shape.strokeBorder(Palette.ink, lineWidth: 2))
        .overlay(alignment: .bottom) {
            HStack {
                Circle().fill(Palette.ink).frame(width: 10, height: 10)
                Spacer()
                Circle().fill(Palette.ink).frame(width: 10, height: 10)
            }
            .padding(.horizontal, 16)
            .offset(y: 5)
        }
        .overlay(alignment: .trailing) {
            if !isFront {
                Rectangle().fill(Palette.ink).frame(width: 8, height: 4).offset(x: 7, y: 8)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: rank.partText(part, in: language)))
    }
}
