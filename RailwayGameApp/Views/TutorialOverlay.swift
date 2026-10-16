import GamePresentation
import SwiftUI

extension View {
    /// The reference's tour card and outlines, attached at the root of the
    /// screen whose controls report TutorialTargetBounds. Sheets need their
    /// own attachment when C5 adds targets inside them. `panelTargets`:
    /// the targets inside a panel beside the map, on the screen (global
    /// coordinates), which report there (`tutorialPanelTarget(_:)`).
    /// `mapSites`: where the places the step has the player tap on the map
    /// stand on the screen (global coordinates), as the map reports them.
    func tutorialOverlay(session: GameSession, panelTargets: [TutorialTarget: CGRect] = [:], mapSites: [CGRect] = []) -> some View {
        overlayPreferenceValue(TutorialTargetBounds.self) { anchors in
            GeometryReader { proxy in
                if let tutorial = session.tutorial {
                    let viewport = CGRect(origin: .zero, size: proxy.size)
                    // A panel beside the map: what is inside it shows only
                    // within it.
                    let panel = anchors[.sidePanel]?.visibleFrame(in: proxy, viewport: viewport)
                    let origin = proxy.frame(in: .global).origin
                    let inPanels = panelTargets.compactMapValues { frame -> CGRect? in
                        guard let panel else { return nil }
                        let visible = frame.offsetBy(dx: -origin.x, dy: -origin.y).intersection(panel)
                        return visible.isNull || visible.isEmpty ? nil : visible
                    }
                    let frameOf = { (target: TutorialTarget) -> CGRect? in
                        anchors[target]?.visibleFrame(in: proxy, viewport: viewport) ?? inPanels[target]
                    }
                    let frames = tutorial.step.targets.compactMap(frameOf)
                    // Every control the player may need stays clear of the card,
                    // whatever its size (a full-width Build Track button is
                    // one). The map is the exception: it fills the screen and
                    // is tapped past the card.
                    let controls = Set(anchors.keys).union(inPanels.keys)
                        .filter { $0 != .map && !tutorialPanels.contains($0) }
                        .compactMap(frameOf)
                    // A panel beside the map, kept clear as the step's own
                    // controls are: at the line step a card over the lines
                    // panel left Pick on Map and Create Line out of reach on a
                    // phone (2026-10-12). The details card only where there is
                    // room: its controls are marked, and with the largest text
                    // covering it beats covering the tools.
                    let panels = frameOf(.sidePanel).map { [$0] } ?? []
                    let backdrops = frameOf(.detailsCard).map { [$0] } ?? []
                    // What the step asks the player to use matters most when
                    // no placement leaves every control clear.
                    // So do the places the step has the player tap on the
                    // map (its track's ends, its stations), where the map shows them (decision 188, later
                    // fix): on a phone on its side, the card stood over both
                    // of the line's stations beside the lines panel.
                    let mapFrame = frameOf(.map)
                    let sites = mapSites.compactMap { site -> CGRect? in
                        guard let mapFrame else { return nil }
                        let visible = site.offsetBy(dx: -origin.x, dy: -origin.y).intersection(mapFrame)
                        return visible.isNull || visible.isEmpty ? nil : visible
                    }
                    let required = tutorial.step.targets.filter { $0 != .map }.compactMap(frameOf)
                    // The map's own frame, so the card leaves some of it
                    // free to tap even where little of it shows; a step that
                    // is only read has nothing to tap there (decision 188).
                    let map = tutorial.step.goal == .read ? nil : mapFrame
                    TutorialOverlay(
                        session: session, tutorial: tutorial, frames: frames,
                        placement: TutorialCardPlacement(
                            target: frames.first.map { TutorialCardPlacement.Frame($0) },
                            controls: controls.map { TutorialCardPlacement.Frame($0) },
                            panels: panels.map { TutorialCardPlacement.Frame($0) },
                            backdrops: backdrops.map { TutorialCardPlacement.Frame($0) },
                            required: required.map { TutorialCardPlacement.Frame($0) },
                            sites: sites.map { TutorialCardPlacement.Frame($0) },
                            map: map.map { TutorialCardPlacement.Frame($0) }
                        )
                    )
                }
            }
        }
    }
}

/// The areas the tutorial's card weighs on their own, not as controls: a
/// panel beside the map and the details card.
private let tutorialPanels: [TutorialTarget] = [.detailsCard, .sidePanel]

/// The overlay's coordinates, the frames' (the GeometryReader's).
private let tutorialOverlaySpace = "tutorial.overlay"

/// Only the card receives touches: outlining a tool or the map must leave
/// it usable, because Next waits for the player to perform the step. Kept
/// across steps, it moves a done step on by itself (decision 188) and
/// keeps the player's choice to open or fold the card for the rest of its
/// chapter.
private struct TutorialOverlay: View {
    let session: GameSession
    let tutorial: Tutorial
    let frames: [CGRect]
    let placement: TutorialCardPlacement
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    /// The player's choice, folded or open, for each chapter they made one
    /// in: the steps move on by themselves, and a player who folded the
    /// card to watch the map had to fold it again on every step
    /// (TestFlight 54.1). A new chapter opens it again.
    @State private var foldedChapters: [TutorialChapter: Bool] = [:]
    /// The map's data layer (``PopTravelMode``, a device preference kept
    /// across games, the map view's): the tutorial starts without one, as
    /// a layer left on from the last game, its legend at the trailing side,
    /// stood where the steps' controls are (TestFlight 55.1).
    @AppStorage("mapPopTravelMode") private var popTravelModeName = ""
    /// The layer the player had on when the tutorial started, put back
    /// when it ends unless they chose one during it.
    @State private var layerBeforeTutorial: String?

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(frames.indices, id: \.self) { index in
                let frame = frames[index]
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Theme.accent, lineWidth: 3)
                    // Decision 122: the station master's lantern lights it.
                    .shadow(color: Theme.accent.opacity(0.8), radius: 8)
                    .background {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.black.opacity(0.35), lineWidth: 5)
                    }
                    .frame(width: frame.width + 6, height: frame.height + 6)
                    .position(x: frame.midX, y: frame.midY)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)

            TutorialCardSlot(
                session: session, tutorial: tutorial, placement: placement,
                chapterFold: Binding(
                    get: { foldedChapters[tutorial.step.chapter] },
                    set: { foldedChapters[tutorial.step.chapter] = $0 }
                )
            )
            .id(tutorial.index)
        }
        // The frames are the overlay's; the card checks its own in them.
        .coordinateSpace(.named(tutorialOverlaySpace))
        // A done step moves on by itself after a moment, longer with
        // VoiceOver, which has the title to read; a step that comes undone
        // meanwhile, or another step, cancels it.
        .task(id: AutoAdvance(index: tutorial.index, ready: session.tutorialAdvancesByItself)) {
            guard session.tutorialAdvancesByItself else { return }
            let index = tutorial.index
            do {
                try await Task.sleep(for: voiceOverEnabled ? Duration.milliseconds(1_500) : Self.autoAdvanceDelay)
            } catch {
                return
            }
            session.showNextTutorialStep(from: index)
        }
        .onAppear(perform: hideDataLayer)
        .onChange(of: tutorial.index) { _, index in
            // Started again (the game menu): the first step, not by Back.
            if index == 0, !tutorial.reachedByBack {
                foldedChapters = [:]
                hideDataLayer()
            }
        }
        .onDisappear {
            if let layer = layerBeforeTutorial, popTravelModeName.isEmpty {
                popTravelModeName = layer
            }
        }
    }

    /// Takes the map's data layer away for the tutorial, remembering the
    /// player's.
    private func hideDataLayer() {
        guard !popTravelModeName.isEmpty else { return }
        if layerBeforeTutorial == nil { layerBeforeTutorial = popTravelModeName }
        popTravelModeName = ""
    }

    /// How long a done step waits before it moves on. A UI test can make
    /// it longer (`-tutorial-advance-ms`, Debug builds only), to hold a
    /// touch on the card across the step moving on.
    private static let autoAdvanceDelay: Duration = {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-tutorial-advance-ms"), arguments.indices.contains(index + 1),
           let milliseconds = Int(arguments[index + 1]) {
            return .milliseconds(milliseconds)
        }
        #endif
        return Tutorial.autoAdvanceDelay
    }()

    /// What restarts the wait before a done step moves on.
    private struct AutoAdvance: Equatable {
        let index: Int
        let ready: Bool
    }
}

/// The step's card, or the card folded to its title: from the second step
/// folded until the player opens it (decision 188, later fix), by the
/// player with its ⌄
/// button, or by itself while, open, it would cover what the step asks for
/// (``TutorialCardPlacement/leavesStepFree(_:)``), as it could on a phone
/// on its side with a panel open (``TutorialCardFold``). The player's
/// choice holds for the rest of the chapter (``TutorialOverlay``), but on a
/// step to read or one reached by Back, which wait for Next: there only a
/// choice made on the step counts, and a done one opens, so Next shows. New
/// for each step (`.id`).
private struct TutorialCardSlot: View {
    let session: GameSession
    let tutorial: Tutorial
    let placement: TutorialCardPlacement
    /// The player's choice in the step's chapter, kept across its steps.
    @Binding var chapterFold: Bool?
    /// The player's choice on this step, open or folded; `nil` until they
    /// make one.
    @State private var folded: Bool?
    /// Folded by itself: open, it covered what the step asks for.
    @State private var fold = TutorialCardFold()
    /// Where the card is laid out, in the overlay's coordinates.
    @State private var bounds: CGRect = .zero
    /// The step has waited long enough to offer "Skip this step".
    @State private var waitedForSkip = false
    /// Compact height: a phone, held on its side.
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    /// Whether the step waits for Next, so the chapter's choice does not
    /// carry into it.
    private var waitsForNext: Bool {
        tutorial.step.goal == .read || tutorial.reachedByBack
    }

    private var isFolded: Bool {
        fold.showsFolded(
            stepChoice: folded, chapterChoice: chapterFold, waitsForNext: waitsForNext, isDone: session.isTutorialStepDone,
            isFirstStep: tutorial.isFirstStep
        )
    }

    /// Whether the open card may fold by itself.
    private var mayFold: Bool {
        TutorialCardFold.mayFold(stepChoice: folded, isDone: session.isTutorialStepDone)
    }

    /// Changes ``fold`` only when `change` changes it.
    private func updateFold(_ change: (inout TutorialCardFold) -> Void) {
        var next = fold
        change(&next)
        if next != fold { fold = next }
    }

    /// The player folds or opens the card: for this step and the rest of
    /// its chapter.
    private func choose(folded value: Bool) {
        folded = value
        chapterFold = value
    }

    /// Whether the card offers "Skip this step" (decision 188): for an
    /// action step not done, at once when something is wrong, else after
    /// the step's wait.
    private func offersSkip(hint: TutorialHint?, done: Bool) -> Bool {
        !done && tutorial.step.goal != .read && (hint?.isProblem == true || waitedForSkip)
    }

    /// Narrower and shorter on a phone on its side, whose map is short and
    /// wide: the explanation scrolls, so the map shows beside the card.
    private var sized: TutorialCardPlacement {
        var placement = placement
        let compact = verticalSizeClass == .compact
        placement.maxWidth = compact ? 320 : 340
        placement.maxHeight = compact ? TutorialCardPlacement.compactMaxHeight : .infinity
        return placement
    }

    var body: some View {
        let hint = session.tutorialHint
        let skips = offersSkip(hint: hint, done: session.isTutorialStepDone)
        TutorialCardLayout(placement: isFolded ? sized.folded : sized) {
            if isFolded {
                FoldedTutorialCard(session: session, tutorial: tutorial, hint: hint, offersSkip: skips) {
                    UITestTrace.action("tutorial.unfold")
                    choose(folded: false)
                }
            } else {
                TutorialCard(session: session, tutorial: tutorial, hint: hint, offersSkip: skips) {
                    UITestTrace.action("tutorial.fold")
                    choose(folded: true)
                }
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(tutorialOverlaySpace)) } action: { frame in
                    updateFold { $0.cardPlaced(at: TutorialCardPlacement.Frame(frame), by: sized, mayFold: mayFold) }
                }
            }
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(tutorialOverlaySpace)) } action: { bounds = $0 }
        // What is on screen changed: a new screen (a panel opened or closed,
        // the device turned, a button the step asks for came into view)
        // opens the card again to see whether it fits now; the places to tap
        // moving with the map fold an open card they come under, though it
        // does not move (``TutorialCardFold``).
        .onChange(of: sized, initial: true) { _, placement in
            updateFold { $0.screenChanged(to: placement, in: TutorialCardPlacement.Frame(bounds), mayFold: mayFold) }
        }
        .task {
            try? await Task.sleep(for: .seconds(tutorial.step.skipOfferSeconds))
            if !Task.isCancelled { waitedForSkip = true }
        }
        // What is wrong is said to VoiceOver as it comes.
        .onChange(of: hint?.text) { _, text in
            if let text, hint?.isProblem == true {
                AccessibilityNotification.Announcement(text).post()
            }
        }
    }
}

/// Measures the actual card (including translated text and Dynamic Type)
/// and puts it where ``TutorialCardPlacement`` says.
private struct TutorialCardLayout: Layout {
    let placement: TutorialCardPlacement

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let card = subviews.first else { return }
        let frame = placement.frame(in: TutorialCardPlacement.Frame(bounds)) { proposed in
            let size = card.sizeThatFits(ProposedViewSize(width: CGFloat(proposed.width), height: CGFloat(proposed.height)))
            return TutorialCardPlacement.Size(width: Double(size.width), height: Double(size.height))
        }
        card.place(
            at: CGPoint(x: CGFloat(frame.x), y: CGFloat(frame.y)), anchor: .topLeading,
            proposal: ProposedViewSize(width: CGFloat(frame.width), height: CGFloat(frame.height))
        )
    }
}

extension TutorialCardPlacement.Frame {
    /// `rect`, in the placement's own rectangles (GamePresentation has no
    /// CoreGraphics).
    init(_ rect: CGRect) {
        self.init(x: Double(rect.minX), y: Double(rect.minY), width: Double(rect.width), height: Double(rect.height))
    }
}

private struct TutorialCard: View {
    let session: GameSession
    let tutorial: Tutorial
    /// What is wrong, or what comes next (``GameSession/tutorialHint``).
    let hint: TutorialHint?
    /// Whether "Skip this step" shows.
    let offersSkip: Bool
    /// Folds the card to its title.
    let fold: () -> Void
    @AccessibilityFocusState private var focusesTitle: Bool
    /// The lantern beside a problem, as large as its text.
    @ScaledMetric(relativeTo: .footnote) private var lanternSize = 14.0
    /// Compact height: a phone, held on its side, where the card is
    /// smaller so more of the screen stays free.
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var isCompact: Bool {
        verticalSizeClass == .compact
    }

    var body: some View {
        VStack(alignment: .leading, spacing: isCompact ? 8 : 12) {
            // Keep the actions visible even when the explanation needs to
            // scroll on a small landscape screen or with larger text.
            ViewThatFits(in: .vertical) {
                explanation.fixedSize(horizontal: false, vertical: true)
                ScrollView { explanation }
                    .scrollBounceBehavior(.basedOnSize)
            }
            // Outside the scrolling: what is wrong, and the way out, always show.
            statusRow
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { navigationButtons }
                VStack(alignment: .leading, spacing: 8) { navigationButtons }
            }
        }
        .padding(isCompact ? 12 : 16)
        .controlSize(isCompact ? ControlSize.regular : ControlSize.large)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Theme.panelBorder, lineWidth: 1)
                .allowsHitTesting(false)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tutorial.card")
        // The card is new for each step (`.id`). Move VoiceOver to its title
        // once it is on screen: set while the card is being inserted, the
        // focus is dropped.
        .task(id: tutorial.index) {
            try? await Task.sleep(for: .milliseconds(100))
            focusesTitle = true
        }
    }

    private var explanation: some View {
        VStack(alignment: .leading, spacing: isCompact ? 6 : 10) {
            HStack(spacing: 8) {
                // Decision 118: the station master gives the tutorial.
                StationMasterAvatar(size: isCompact ? 24 : 28, mood: session.isTutorialStepDone ? .happy : .normal)
                HStack(spacing: 0) {
                    Text("Step \(tutorial.index + 1) of \(tutorial.steps.count)")
                        .monospacedDigit()
                        .accessibilityIdentifier("tutorial.progress")
                    Text(verbatim: " · " + tutorial.step.chapter.title(in: session.language))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Theme.primary.opacity(0.14), in: Capsule())
                // Out of the way: what the card would cover is always in
                // reach (on a phone, the lines panel at the line step).
                Button(action: fold) {
                    Image(systemName: "chevron.down")
                        .font(.footnote.weight(.bold))
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.primary)
                .background(Theme.primary.opacity(0.14), in: Circle())
                .accessibilityLabel(Text(verbatim: session.language.text("Minimize Tutorial", "收合教學")))
                .accessibilityIdentifier("tutorial.fold")
            }

            Text(verbatim: tutorial.step.title(in: session.language))
                .font(isCompact ? Font.subheadline.weight(.bold) : Font.headline.weight(.bold))
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($focusesTitle)
                .accessibilityIdentifier("tutorial.title")
            Text(verbatim: tutorial.step.body(in: session.language))
                .font(isCompact ? Font.footnote : Font.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(Theme.textPrimary)
    }

    /// What is wrong (a problem, in the lantern's colour) or what comes
    /// next, else, where there is room, that the step waits; and "Skip
    /// this step" when the card offers it (decision 188).
    @ViewBuilder
    private var statusRow: some View {
        let waits = hint == nil && !isCompact && !session.isTutorialStepDone
        if hint != nil || waits || offersSkip {
            HStack(alignment: .center, spacing: 8) {
                if let hint, hint.isProblem {
                    HStack(spacing: 6) {
                        lantern
                        Text(verbatim: hint.text)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(Theme.warning)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Theme.warning.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                } else if let hint {
                    Text(verbatim: hint.text)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else if waits {
                    HStack(spacing: 6) {
                        lantern
                        Text("Complete this step to continue.")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(Theme.warning)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                if offersSkip {
                    Button {
                        UITestTrace.action("tutorial.skipStep")
                        session.skipTutorialStep()
                    } label: {
                        // A fingertip's 44 points to tap; on a phone on its
                        // side the row lays out 36 tall, the rest reaching
                        // into the spacing above and below it.
                        Text(verbatim: session.language.text("Skip this step", "略過這一步"))
                            .font(.footnote.weight(.semibold))
                            .underline()
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                            .padding(.vertical, isCompact ? -4 : 0)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.primary)
                    .accessibilityIdentifier("tutorial.skipStep")
                }
            }
        }
    }

    /// Decision 122: the station master's lantern.
    private var lantern: some View {
        Image("StationMasterLantern")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: lanternSize, height: lanternSize)
            .foregroundStyle(Theme.warning)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var navigationButtons: some View {
        Button("Skip") {
            UITestTrace.action("tutorial.skip")
            session.skipTutorial()
        }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("tutorial.skip")
        if !tutorial.isFirstStep {
            Button("Back") {
                UITestTrace.action("tutorial.back")
                session.showPreviousTutorialStep()
            }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("tutorial.back")
        }
        Button {
            UITestTrace.action("tutorial.next")
            session.showNextTutorialStep()
        } label: {
            Group {
                if tutorial.isLastStep {
                    Text(verbatim: session.language.text("Finish", "完成教學"))
                } else {
                    Text("Next")
                }
            }
            .frame(minHeight: isCompact ? 36 : 44)
        }
        .buttonStyle(ThemeProminentButtonStyle())
        .disabled(!session.isTutorialStepDone)
        .accessibilityIdentifier("tutorial.next")
    }
}

/// The card folded to its step and title, at the card's place, so the
/// controls it covered are in reach; a tap opens it again, which its
/// trailing "Tap for help" says (a player's report on 59.1 did not find
/// the open card's buttons). "Skip this step" shows beside it as on the
/// open card, when the step has waited long enough or something is wrong.
private struct FoldedTutorialCard: View {
    let session: GameSession
    let tutorial: Tutorial
    /// Marked when something is wrong.
    let hint: TutorialHint?
    /// Whether "Skip this step" shows.
    let offersSkip: Bool
    let unfold: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: unfold) {
                HStack(spacing: 8) {
                    StationMasterAvatar(size: 24, mood: session.isTutorialStepDone ? .happy : .normal)
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 0) {
                            Text("Step \(tutorial.index + 1) of \(tutorial.steps.count)")
                                .monospacedDigit()
                                .accessibilityIdentifier("tutorial.progress")
                            Text(verbatim: " · " + tutorial.step.chapter.title(in: session.language))
                            if hint?.isProblem == true {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .foregroundStyle(Theme.warning)
                                    .padding(.leading, 4)
                            }
                        }
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Theme.primary)
                        .lineLimit(1)
                        Text(verbatim: tutorial.step.title(in: session.language))
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                    }
                    HStack(spacing: 3) {
                        Text(verbatim: session.language.text("Tap for help", "點我看說明"))
                            .font(.caption2.weight(.bold))
                            .lineLimit(1)
                        Image(systemName: "chevron.up")
                            .font(.caption2.weight(.bold))
                    }
                    .foregroundStyle(Theme.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Theme.primary.opacity(0.14), in: Capsule())
                    // Where the capsule is narrow, the title is cut short
                    // first.
                    .layoutPriority(1)
                }
                .padding(.leading, 12)
                .padding(.trailing, offersSkip ? 8 : 12)
                .padding(.vertical, 6)
                .frame(minHeight: 44)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(verbatim: session.language.text(
                "Show Tutorial: \(tutorial.step.title(in: .english))",
                "展開教學：\(tutorial.step.title(in: .traditionalChinese))"
            )))
            .accessibilityIdentifier("tutorial.unfold")
            if offersSkip {
                Divider()
                    .frame(height: 24)
                Button {
                    UITestTrace.action("tutorial.skipStep")
                    session.skipTutorialStep()
                } label: {
                    Text(verbatim: session.language.text("Skip this step", "略過這一步"))
                        .font(.footnote.weight(.semibold))
                        .underline()
                        .lineLimit(1)
                        .padding(.leading, 8)
                        .padding(.trailing, 12)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.primary)
                .layoutPriority(1)
                .accessibilityIdentifier("tutorial.skipStep")
            }
        }
        .background(Theme.panel, in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(Theme.panelBorder, lineWidth: 1)
                .allowsHitTesting(false)
        }
        .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
        // As tall as it needs, and as wide up to the width the placement
        // offers (``TutorialCardPlacement``), never wider than the screen:
        // with a long title and large text the title is cut short.
        .fixedSize(horizontal: false, vertical: true)
    }
}
