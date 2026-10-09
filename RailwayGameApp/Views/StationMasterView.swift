import GameCore
import GamePresentation
import SwiftUI

/// The station master's face (decision 118), drawn here rather than from
/// art: a round face under a cap in the region's colours
/// (``RegionStyle/stationMasterCap``) with a badge on it, in a circle.
struct StationMasterAvatar: View {
    var size: CGFloat = 40
    @Environment(\.regionStyle) private var region

    var body: some View {
        ZStack {
            Circle().fill(Theme.panel)
            // The face.
            Circle()
                .fill(Color(red: 0.95, green: 0.80, blue: 0.66))
                .frame(width: size * 0.52, height: size * 0.52)
                .offset(y: size * 0.1)
            // Eyes and a smile.
            HStack(spacing: size * 0.12) {
                Circle().frame(width: size * 0.05, height: size * 0.05)
                Circle().frame(width: size * 0.05, height: size * 0.05)
            }
            .foregroundStyle(Color.black.opacity(0.75))
            .offset(y: size * 0.1)
            Capsule()
                .trim(from: 0.55, to: 0.95)
                .stroke(Color.black.opacity(0.6), lineWidth: max(1, size * 0.03))
                .frame(width: size * 0.18, height: size * 0.1)
                .rotationEffect(.degrees(180))
                .offset(y: size * 0.2)
            // The cap: its crown, its band and the visor.
            UnevenRoundedRectangle(topLeadingRadius: size * 0.16, bottomLeadingRadius: 2, bottomTrailingRadius: 2, topTrailingRadius: size * 0.16)
                .fill(region.stationMasterCap)
                .frame(width: size * 0.62, height: size * 0.22)
                .offset(y: -size * 0.17)
            Capsule()
                .fill(region.stationMasterCap)
                .frame(width: size * 0.7, height: size * 0.07)
                .offset(y: -size * 0.04)
            Circle()
                .fill(region.stationMasterBadge)
                .frame(width: size * 0.12, height: size * 0.12)
                .offset(y: -size * 0.17)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Theme.panelBorder, lineWidth: 1))
        .accessibilityHidden(true)
    }
}

/// The station master beside the dock (decision 118): says the advice in a
/// bubble when it changes, for a few seconds, and again when tapped. A dot
/// on the face while there is advice not on screen. Not during the
/// tutorial, whose card the station master speaks instead.
struct StationMasterCorner: View {
    let session: GameSession
    /// The most width the bubble may take.
    let maxBubbleWidth: CGFloat
    @State private var isTalking = false
    @State private var lastSpoken: StationMasterAdvice?
    @State private var talk = 0

    /// How long the bubble stays.
    private static let speakingTime = Duration.seconds(7)

    var body: some View {
        let advice = StationMasterAdvice(world: session.world)
        HStack(alignment: .bottom, spacing: 8) {
            Button {
                if isTalking {
                    isTalking = false
                } else if advice != nil {
                    isTalking = true
                    talk &+= 1
                }
            } label: {
                StationMasterAvatar(size: 44)
                    .overlay(alignment: .topTrailing) {
                        if let advice, !isTalking {
                            Circle()
                                .fill(advice.isWorry ? Theme.warning : Theme.primary)
                                .frame(width: 11, height: 11)
                                .overlay(Circle().strokeBorder(Theme.panel, lineWidth: 2))
                        }
                    }
                    .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(verbatim: session.language.text("Station master", "站長")))
            .accessibilityValue(Text(verbatim: advice?.text(in: session.language) ?? ""))
            .accessibilityIdentifier("stationMaster")
            if isTalking, let advice, maxBubbleWidth >= 140 {
                let width = min(maxBubbleWidth, 320)
                // One line when it fits, else wrapped at the width it has.
                ViewThatFits(in: .horizontal) {
                    bubble(advice) { $0.fixedSize() }
                    bubble(advice) { $0.fixedSize(horizontal: false, vertical: true).frame(width: width - 24, alignment: .leading) }
                }
                .frame(maxWidth: width, alignment: .leading)
                .onTapGesture { isTalking = false }
                .accessibilityHidden(true)
                .transition(.scale(scale: 0.8, anchor: .bottomLeading).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3, bounce: 0.3), value: isTalking)
        .onChange(of: advice, initial: true) { _, advice in
            // New advice is said once by itself; the same again is not.
            guard let advice, advice != lastSpoken else {
                if advice == nil { isTalking = false }
                return
            }
            lastSpoken = advice
            isTalking = true
            talk &+= 1
        }
        .task(id: talk) {
            try? await Task.sleep(for: Self.speakingTime)
            guard !Task.isCancelled else { return }
            isTalking = false
        }
    }

    /// The advice in a glass bubble, its text laid out by `sized`.
    private func bubble<Sized: View>(_ advice: StationMasterAdvice, sized: (Text) -> Sized) -> some View {
        sized(
            Text(verbatim: advice.text(in: session.language))
                .font(.footnote.weight(.medium))
                .foregroundStyle(Theme.textPrimary)
        )
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassBackground(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(advice.isWorry ? Theme.warning.opacity(0.6) : Theme.panelBorder, lineWidth: 1)
        )
    }
}
