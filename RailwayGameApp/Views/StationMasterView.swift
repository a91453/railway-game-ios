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
    /// Under a panel beside the map: shows nothing, but stays, so it
    /// remembers what it has said.
    var isCovered = false
    @State private var isTalking = false
    @State private var lastSpoken: StationMasterAdvice?
    @State private var talk = 0
    /// The advice, worked out again only when an edit or a new game hour
    /// can have changed it (decision 184, later): not at every tick.
    @State private var advice: StationMasterAdvice?
    /// Decision 224: the company's title it wears, worked out with the
    /// advice (the rank reads the whole network).
    @State private var title: StationMasterTitle?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Decision 194, later: a losing line's bubble opens the line panel.
    @Environment(GameScreenState.self) private var screen

    /// How long the bubble stays.
    private static let speakingTime = Duration.seconds(7)
    /// The avatar's side.
    static let avatarSize: CGFloat = 44

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if !isCovered {
                corner
            }
        }
        .onChange(of: session.stationMasterRefreshKey, initial: true) {
            advice = StationMasterAdvice(world: session.world, worstLosingLine: { session.worstLosingLine })
            title = StationMasterTitle.isShown(in: session.world) ? StationMasterTitle(rank: CompanyRank(world: session.world)) : nil
        }
        .onChange(of: advice, initial: true) { _, advice in
            if advice == nil { isTalking = false }
            sayIfNew(advice)
        }
        // Advice that came while a side panel left no room for the bubble
        // is said once the room is back.
        .onChange(of: hasRoom) { _, _ in sayIfNew(advice) }
        .task(id: talk) {
            try? await Task.sleep(for: Self.speakingTime)
            guard !Task.isCancelled else { return }
            isTalking = false
        }
    }

    private var corner: some View {
        HStack(alignment: .bottom, spacing: 8) {
            // Decision 224 (6C): the company's title under the avatar.
            VStack(spacing: -3) {
            Button {
                if isTalking {
                    // Decision 175, later: a second tap, while it talks,
                    // puts the bubble away. The news log is the bell's.
                    isTalking = false
                } else {
                    // With nothing to advise it says all is well
                    // (decision 123).
                    isTalking = true
                    talk &+= 1
                }
            } label: {
                StationMasterAvatar(size: Self.avatarSize, mood: mood(advice))
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
            if let title, StationMasterTitle.isShown(in: session.world) {
                titleBadge(title)
            }
            }
            if isTalking, hasRoom {
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
                .onTapGesture {
                    // Decision 177: advice that points at a place takes
                    // the map there. Decision 175, later: advice about a
                    // station takes the map there and, while selecting,
                    // selects it; any other only puts the bubble away.
                    isTalking = false
                    if let line = advice?.line {
                        // Decision 194, later: a losing line opens in the
                        // line panel, its card saying why.
                        session.selectLine(line)
                        screen.panel = .lines
                    } else if let target = advice?.cameraTarget {
                        session.lookAt(target)
                    } else if let id = advice.flatMap(stationID(of:)), let station = session.world.station(id: id) {
                        session.lookAt(station.point)
                        if session.tool == .select { session.selectStation(id) }
                    }
                }
                .accessibilityHidden(true)
                .transition(.scale(scale: 0.8, anchor: .bottomLeading).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3, bounce: 0.3), value: isTalking)
    }

    /// The title on a warm plate with a navy edge, and under it how far to
    /// the next title; opens the goals panel, where the rank is.
    private func titleBadge(_ title: StationMasterTitle) -> some View {
        let language = session.language
        return Button {
            screen.panel = .goals
        } label: {
            VStack(spacing: 2) {
                Text(verbatim: title.title.title(in: language))
                    .font(.system(size: 10, weight: .heavy))
                    .lineLimit(1)
                    .fixedSize()
                    .foregroundStyle(Theme.onAccent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Palette.ink, lineWidth: 1.5))
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.panel)
                        Capsule().fill(Theme.primary).frame(width: proxy.size.width * title.progress)
                    }
                    .overlay(Capsule().strokeBorder(Palette.ink, lineWidth: 1))
                }
                .frame(width: 40, height: 5)
            }
            .frame(minWidth: 44, minHeight: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: title.title.title(in: language)))
        .accessibilityHint(Text(verbatim: language.text("Opens your company's rank.", "打開公司評等。")))
        .accessibilityIdentifier("stationMaster.title")
    }

    /// The station the advice is about, if it is about one.
    private func stationID(of advice: StationMasterAdvice) -> StationID? {
        switch advice {
        case .stationFull(let station, _), .stationCrowded(let station, _),
             .underserved(let station, _, _), .townGrew(let station, _, _),
             .materialsShort(let station, _):
            station
        default:
            nil
        }
    }

    /// Whether the bubble has the width it needs to show.
    private var hasRoom: Bool { maxBubbleWidth >= 140 }

    /// New advice is said once by itself; the same again is not. Without
    /// room for the bubble it is kept, with its dot, until there is.
    private func sayIfNew(_ advice: StationMasterAdvice?) {
        guard let advice, advice != lastSpoken, hasRoom else { return }
        lastSpoken = advice
        isTalking = true
        talk &+= 1
    }

    private func mood(_ advice: StationMasterAdvice?) -> StationMasterMood {
        guard let advice else { return .happy }
        // Decision 128: pleased when a town grew; decision 153, when a
        // goal was met.
        if advice.isCheer { return .happy }
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
