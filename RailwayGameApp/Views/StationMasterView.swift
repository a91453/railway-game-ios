import GameCore
import GamePresentation
import SwiftUI

/// How the station master looks (decision 122): pleased when there is
/// nothing to fix, worried (the lantern dimmed) over a worry.
enum StationMasterMood: String {
    case normal = "Normal"
    case happy = "Happy"
    case worried = "Worried"
}

/// The station master's face (decision 118): since decision 122 the
/// region's character (``RegionStyle/stationMasterArt``), for Taiwan the
/// yellow tit with its lantern, drawn as SVG in the asset catalog, in a
/// circle.
struct StationMasterAvatar: View {
    var size: CGFloat = 40
    var mood: StationMasterMood = .normal
    @Environment(\.regionStyle) private var region

    /// Narrower than this, the avatar shows the head alone, a size up, so
    /// the face still reads (decision 122).
    private static let headOnlyBelow: CGFloat = 60

    var body: some View {
        Image(region.stationMasterArt + mood.rawValue)
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .scaleEffect(size < Self.headOnlyBelow ? 1.45 : 1, anchor: UnitPoint(x: 0.44, y: 0.3))
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// How long the bubble stays.
    private static let speakingTime = Duration.seconds(7)

    var body: some View {
        let advice = StationMasterAdvice(world: session.world)
        HStack(alignment: .bottom, spacing: 8) {
            Button {
                if isTalking {
                    isTalking = false
                } else {
                    // With nothing to advise it says all is well
                    // (decision 123).
                    isTalking = true
                    talk &+= 1
                }
            } label: {
                StationMasterAvatar(size: 44, mood: mood(advice))
                    // Decision 122: a hop each time it speaks, not with
                    // Reduce Motion.
                    .keyframeAnimator(initialValue: 0.0, trigger: reduceMotion ? 0 : talk) { content, lift in
                        content.offset(y: -lift)
                    } keyframes: { _ in
                        SpringKeyframe(8, duration: 0.15)
                        SpringKeyframe(0, duration: 0.35, spring: .bouncy)
                    }
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
            .accessibilityValue(Text(verbatim: said(advice)))
            .accessibilityIdentifier("stationMaster")
            if isTalking, maxBubbleWidth >= 140 {
                let width = min(maxBubbleWidth, 320)
                let worry = advice?.isWorry ?? false
                // One line when it fits, else wrapped at the width it has.
                ViewThatFits(in: .horizontal) {
                    bubble(said(advice), worry: worry) { $0.fixedSize() }
                    bubble(said(advice), worry: worry) {
                        $0.fixedSize(horizontal: false, vertical: true).frame(width: width - 24, alignment: .leading)
                    }
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

    private func mood(_ advice: StationMasterAdvice?) -> StationMasterMood {
        guard let advice else { return .happy }
        return advice.isWorry ? .worried : .normal
    }

    /// The advice, or that all is well.
    private func said(_ advice: StationMasterAdvice?) -> String {
        advice?.text(in: session.language) ?? StationMasterAdvice.allWellText(in: session.language)
    }

    /// What it says in a glass bubble, its text laid out by `sized`.
    private func bubble<Sized: View>(_ text: String, worry: Bool, sized: (Text) -> Sized) -> some View {
        sized(
            Text(verbatim: text)
                .font(.footnote.weight(.medium))
                .foregroundStyle(Theme.textPrimary)
        )
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassBackground(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(worry ? Theme.warning.opacity(0.6) : Theme.panelBorder, lineWidth: 1)
        )
    }
}
