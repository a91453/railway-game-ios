import GamePresentation
import SwiftUI

extension View {
    /// The reference's tour card and outlines, attached at the root of the
    /// screen whose controls report TutorialTargetBounds. Sheets need their
    /// own attachment when C5 adds targets inside them. `panelTargets`:
    /// the targets inside a panel beside the map, on the screen (global
    /// coordinates), which report there (`tutorialPanelTarget(_:)`).
    func tutorialOverlay(session: GameSession, panelTargets: [TutorialTarget: CGRect] = [:]) -> some View {
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
                    // The details card and a panel beside the map, kept clear
                    // as the step's own controls are: at the line step a card
                    // over the lines panel left Pick on Map and Create Line out
                    // of reach on a phone (2026-10-12).
                    let panels = tutorialPanels.compactMap(frameOf)
                    // What the step asks the player to use matters most when
                    // no placement leaves every control clear.
                    let required = tutorial.step.targets.filter { $0 != .map }.compactMap(frameOf)
                    // The map's own frame, so the card leaves some of it
                    // free to tap even where little of it shows.
                    let map = frameOf(.map)
                    TutorialOverlay(
                        session: session, tutorial: tutorial, frames: frames,
                        placement: TutorialCardPlacement(
                            target: frames.first.map { TutorialCardPlacement.Frame($0) },
                            controls: controls.map { TutorialCardPlacement.Frame($0) },
                            panels: panels.map { TutorialCardPlacement.Frame($0) },
                            required: required.map { TutorialCardPlacement.Frame($0) },
                            map: map.map { TutorialCardPlacement.Frame($0) }
                        )
                    )
                }
            }
        }
    }
}

/// The areas the tutorial's card keeps clear of as of the step's own
/// controls: the details card and a panel beside the map.
private let tutorialPanels: [TutorialTarget] = [.detailsCard, .sidePanel]

/// The overlay's coordinates, the frames' (the GeometryReader's).
private let tutorialOverlaySpace = "tutorial.overlay"

/// Only the card receives touches: outlining a tool or the map must leave
/// it usable, because Next waits for the player to perform the step.
private struct TutorialOverlay: View {
    let session: GameSession
    let tutorial: Tutorial
    let frames: [CGRect]
    let placement: TutorialCardPlacement

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

            TutorialCardSlot(session: session, tutorial: tutorial, placement: placement)
                .id(tutorial.index)
        }
        // The frames are the overlay's; the card checks its own in them.
        .coordinateSpace(.named(tutorialOverlaySpace))
    }
}

/// The step's card, or the card folded to its title: by the player, with
/// its ⌄ button, or by itself while, open, it would cover what the step
/// asks for (``TutorialCardPlacement/leavesStepFree(_:)``), as it could on
/// a phone on its side with a panel open. A step that is done opens it, so
/// Next shows, unless the player folded it. New for each step (`.id`).
private struct TutorialCardSlot: View {
    let session: GameSession
    let tutorial: Tutorial
    let placement: TutorialCardPlacement
    /// The player's choice, open or folded; `nil` until they make one.
    @State private var folded: Bool?
    /// Folded by itself: open, it covered what the step asks for.
    @State private var foldedItself = false
    /// Compact height: a phone, held on its side.
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var isFolded: Bool {
        if session.isTutorialStepDone { return folded == true }
        return folded ?? foldedItself
    }

    /// Narrower on a phone on its side, whose map is short and wide.
    private var sized: TutorialCardPlacement {
        var placement = placement
        placement.maxWidth = verticalSizeClass == .compact ? 320 : 340
        return placement
    }

    var body: some View {
        TutorialCardLayout(placement: sized) {
            if isFolded {
                FoldedTutorialCard(session: session, tutorial: tutorial) {
                    UITestTrace.action("tutorial.unfold")
                    folded = false
                }
            } else {
                TutorialCard(session: session, tutorial: tutorial) {
                    UITestTrace.action("tutorial.fold")
                    folded = true
                }
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(tutorialOverlaySpace)) } action: { frame in
                    if folded == nil, !session.isTutorialStepDone, !placement.leavesStepFree(TutorialCardPlacement.Frame(frame)) {
                        foldedItself = true
                    }
                }
            }
        }
        // What is on screen changed (a panel opened or closed, the device
        // turned, a button the step asks for came into view): open the card
        // again and see whether it fits now.
        .onChange(of: Fit(placement)) { _, _ in
            foldedItself = false
        }
    }

    /// What decides whether the card fits, without the frames of controls
    /// that scroll, which change on every frame of a scroll.
    private struct Fit: Equatable {
        let map: [Double]?
        let required: Int

        init(_ placement: TutorialCardPlacement) {
            map = placement.map.map { map in [map.x, map.y, map.width, map.height].map { $0.rounded() } }
            required = placement.required.count
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
    /// Folds the card to its title.
    let fold: () -> Void
    @AccessibilityFocusState private var focusesTitle: Bool
    /// The lantern beside "Complete this step", as large as its text.
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
                HStack(spacing: 6) {
                    Text("Step \(tutorial.index + 1) of \(tutorial.steps.count)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.primary)
                        .monospacedDigit()
                        .accessibilityIdentifier("tutorial.progress")
                    Spacer(minLength: 0)
                }
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
            if !session.isTutorialStepDone {
                HStack(spacing: 6) {
                    // Decision 122: the station master's lantern.
                    Image("StationMasterLantern")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: lanternSize, height: lanternSize)
                        .foregroundStyle(Theme.warning)
                        .accessibilityHidden(true)
                    Text("Complete this step to continue.")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Theme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Theme.warning.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(Theme.textPrimary)
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
                    Text("Done")
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
/// controls it covered are in reach; a tap opens it again.
private struct FoldedTutorialCard: View {
    let session: GameSession
    let tutorial: Tutorial
    let unfold: () -> Void

    var body: some View {
        Button(action: unfold) {
            HStack(spacing: 8) {
                StationMasterAvatar(size: 24, mood: session.isTutorialStepDone ? .happy : .normal)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Step \(tutorial.index + 1) of \(tutorial.steps.count)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Theme.primary)
                        .monospacedDigit()
                    Text(verbatim: tutorial.step.title(in: session.language))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                }
                Image(systemName: "chevron.up")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Theme.primary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(minHeight: 44)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .background(Theme.panel, in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(Theme.panelBorder, lineWidth: 1)
                .allowsHitTesting(false)
        }
        .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
        .fixedSize()
        .accessibilityLabel(Text(verbatim: session.language.text(
            "Show Tutorial: \(tutorial.step.title(in: .english))",
            "展開教學：\(tutorial.step.title(in: .traditionalChinese))"
        )))
        .accessibilityIdentifier("tutorial.unfold")
    }
}
