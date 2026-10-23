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

/// A face of a challenge's story (decision 387): the station master's, or
/// the character's portrait from the asset catalog, in a circle.
struct StoryPortrait: View {
    let speaker: StoryCharacter
    var size: CGFloat = 40

    var body: some View {
        if let portrait = speaker.portrait {
            Image(portrait)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Theme.panelBorder, lineWidth: 1))
                .accessibilityHidden(true)
        } else {
            StationMasterAvatar(size: size)
        }
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
    /// Decision 332: the one-time word about riders who take a scooter or
    /// a car instead, worked out off the main actor once a game day until
    /// it has been said.
    @State private var modeShiftHint: StationMasterAdvice?
    @AppStorage(ModeShiftHint.seenKey) private var modeShiftHintSeen = false
    /// Decision 387: the challenge's story, told here, a beat at a time,
    /// in the bubble's place and with its speaker's face.
    @State private var teller = StoryTeller()
    /// The game the teller has looked at: another is told afresh.
    @State private var tellerGame: ObjectIdentifier?
    @State private var storyQueue: [StoryBeat] = []
    @State private var storyBeat: StoryBeat?
    /// The station master's line under the story's (the festival to come),
    /// worked out when the beat is told.
    @State private var storyAdvice: StationMasterAdvice?
    /// Advice a story card has said already, not said again by itself.
    @State private var coveredAdvice: StationMasterAdvice?
    @State private var storyTalk = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Decision 194, later: a losing line's bubble opens the line panel.
    @Environment(GameScreenState.self) private var screen

    /// How long the bubble stays.
    private static let speakingTime = Duration.seconds(7)
    /// How long a story card stays: a longer line than the advice's.
    private static let storyTime = Duration.seconds(14)
    /// The avatar's side.
    static let avatarSize: CGFloat = 44
    /// How tall the avatar stands with the title under it (the title's
    /// least height, 28, less the 3 they overlap): the height of a phone's
    /// bottom row, which what floats over the map keeps above.
    static let standingHeight: CGFloat = avatarSize + 28 - 3

    // Decision 379: timed for the frame readout.
    var body: some View { timed(.stationMasterBody) { timedBody } }

    @ViewBuilder private var timedBody: some View {
        ZStack(alignment: .bottomLeading) {
            if !isCovered {
                corner
            }
        }
        .onChange(of: session.stationMasterRefreshKey, initial: true) {
            // The advice first: a goal's cheer the story waits for.
            refreshAdvice()
            lookForStory()
            title = StationMasterTitle.isShown(in: session.world) ? StationMasterTitle(rank: CompanyRank(world: session.world)) : nil
        }
        .onChange(of: modeShiftHint) { refreshAdvice() }
        .task(id: modeShiftHintDay) { await workOutModeShiftHint(modeShiftHintDay) }
        // Once said and put away, the hint gives way to the other advice.
        .onChange(of: isTalking) { _, talking in
            if !talking, modeShiftHintSeen, modeShiftHint != nil { modeShiftHint = nil }
            // Decision 387: a beat waiting for the bubble follows it.
            if !talking { tellNextBeat() }
        }
        .onChange(of: advice, initial: true) { _, advice in
            if advice == nil { isTalking = false }
            sayIfNew(advice)
        }
        // Advice that came while a side panel left no room for the bubble
        // is said once the room is back.
        .onChange(of: hasRoom) { _, _ in sayIfNew(advice) }
        // Decision 387: not while paused or building, nor without room;
        // a card put away by that comes back when play goes on.
        .onChange(of: canTell) { _, can in
            if can {
                tellNextBeat()
            } else if let beat = storyBeat {
                storyQueue.insert(beat, at: 0)
                storyBeat = nil
            }
        }
        .task(id: storyTalk) {
            guard storyTalk > 0 else { return }
            try? await Task.sleep(for: Self.storyTime)
            guard !Task.isCancelled else { return }
            finishBeat()
        }
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
                if storyBeat != nil {
                    finishBeat()
                } else if isTalking {
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
                Group {
                    if let storyBeat {
                        StoryPortrait(speaker: storyBeat.speaker, size: Self.avatarSize)
                    } else {
                        StationMasterAvatar(size: Self.avatarSize, mood: mood(advice))
                    }
                }
                    // Decision 122: a hop each time it speaks, not with
                    // Reduce Motion.
                    .keyframeAnimator(initialValue: 0.0, trigger: reduceMotion ? 0 : talk) { content, lift in
                        content.offset(y: -lift)
                    } keyframes: { _ in
                        SpringKeyframe(8, duration: 0.15)
                        SpringKeyframe(0, duration: 0.35, spring: .bouncy)
                    }
                    .overlay(alignment: .topTrailing) {
                        if let advice, !isTalking, storyBeat == nil {
                            Circle()
                                .fill(advice.isWorry ? Theme.warning : Theme.primary)
                                .frame(width: 11, height: 11)
                                .overlay(Circle().strokeBorder(Theme.panel, lineWidth: 2))
                        }
                    }
                    .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(verbatim: storyBeat?.speaker.name(in: session.language) ?? session.language.text("Station master", "站長")))
            .accessibilityValue(Text(verbatim: storyBeat.map { $0.text(in: session.language) } ?? said(advice)))
            .accessibilityIdentifier("stationMaster")
            if let title, StationMasterTitle.isShown(in: session.world) {
                titleBadge(title)
            }
            }
            if let storyBeat, hasRoom {
                storyCard(storyBeat)
            } else if isTalking, hasRoom {
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
        .animation(MotionRule.pop.layout(reduceMotion: reduceMotion), value: storyBeat)
    }

    /// Decision 387: a beat of the challenge's story, who says it over what
    /// they say, and under it the station master's word it carries; a tap
    /// puts it away.
    private func storyCard(_ beat: StoryBeat) -> some View {
        let language = session.language
        return VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: beat.speaker.name(in: language))
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.primary)
            Text(verbatim: beat.text(in: language))
                .font(.footnote.weight(.medium))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if let storyAdvice {
                Divider()
                Text(verbatim: storyAdvice.text(in: language))
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(width: min(maxBubbleWidth, 340), alignment: .leading)
        .glassBackground(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.panelBorder, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture { finishBeat() }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("storyCard")
        .transition(.pop(anchor: .bottomLeading, reduceMotion: reduceMotion))
    }

    /// Whether a story card may show now: the game running, not building,
    /// with room for it. Not while the building tools are out or the map
    /// shows a ✓ (a new line picked with Select, say), even with the clock
    /// running: the card then waits rather than standing near them.
    private var canTell: Bool {
        !isCovered && hasRoom && !session.world.clock.isPaused && !session.isPausedForBuilding
            && !BuildToolRail.isShown(session) && !MapBuildConfirm.isShown(session, panel: screen.panel)
    }

    /// The beats of a day the teller sees begin, queued; another game
    /// starts the teller afresh.
    private func lookForStory() {
        let game = ObjectIdentifier(session)
        if tellerGame != game {
            tellerGame = game
            teller = StoryTeller()
            storyQueue = []
            storyBeat = nil
        }
        storyQueue += teller.look(at: session.world)
        tellNextBeat()
    }

    /// Tells the next queued beat, when nothing else is being told and it
    /// may. A goal's cheer not yet said goes first, and the card waits for
    /// the bubble, never beside it (decision 387); a bubble saying what the
    /// card stands for gives way to it.
    private func tellNextBeat() {
        guard storyBeat == nil, canTell, let beat = storyQueue.first else { return }
        if case .goalMet? = advice, advice != lastSpoken, advice != coveredAdvice {
            sayIfNew(advice)
            return
        }
        let covered = beat.advice(in: session.world)
        guard !isTalking || (covered != nil && covered == lastSpoken) else { return }
        storyQueue.removeFirst()
        storyAdvice = beat.adviceLine(in: session.world)
        if let covered {
            // Decision 387: one card, not the story and the advice apart.
            coveredAdvice = covered
            lastSpoken = covered
        }
        isTalking = false
        storyBeat = beat
        storyTalk &+= 1
    }

    /// Puts the card away; the next beat, else the advice waiting, follows.
    private func finishBeat() {
        guard storyBeat != nil else { return }
        storyBeat = nil
        storyAdvice = nil
        tellNextBeat()
        if storyBeat == nil { sayIfNew(advice) }
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
             .materialsShort(let station, _), .modeShift(let station):
            station
        default:
            nil
        }
    }

    private func refreshAdvice() {
        let own = StationMasterAdvice(world: session.world, worstLosingLine: { session.worstLosingLine })
        advice = ModeShiftHint.advice(own, hint: modeShiftHint)
    }

    /// The game day the hint is worked out for, or `nil` once said, with
    /// riders who cannot switch, or in the tutorial or a lesson.
    private var modeShiftHintDay: Int64? {
        let tutorialRuns = session.tutorial != nil || session.lesson != nil
        guard ModeShiftHint.looks(in: session.world, seen: modeShiftHintSeen, tutorialRuns: tutorialRuns) else { return nil }
        return session.world.clock.now.seconds / GameTime.secondsPerDay
    }

    /// Works out ``modeShiftHint`` off the main actor: it reads every
    /// station's trips.
    private func workOutModeShiftHint(_ day: Int64?) async {
        guard day != nil else { return }
        let world = session.world
        let hint = await Task.detached(priority: .utility) {
            world.modeShiftHint()
        }.value
        guard !Task.isCancelled else { return }
        modeShiftHint = hint
    }

    /// Whether the bubble has the width it needs to show.
    private var hasRoom: Bool { maxBubbleWidth >= 140 }

    /// New advice is said once by itself; the same again is not. Without
    /// room for the bubble it is kept, with its dot, until there is.
    private func sayIfNew(_ advice: StationMasterAdvice?) {
        guard let advice, advice != lastSpoken, advice != coveredAdvice, storyBeat == nil, hasRoom else { return }
        if case .modeShift = advice {
            // Decision 332: said once, leaving what was said before it as
            // said, so that is not said again when the hint goes.
            guard !modeShiftHintSeen else { return }
            modeShiftHintSeen = true
        } else {
            lastSpoken = advice
        }
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
