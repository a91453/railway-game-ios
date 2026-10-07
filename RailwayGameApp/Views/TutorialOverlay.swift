import GamePresentation
import SwiftUI

extension View {
    /// The reference's tour card and outlines, attached at the root of the
    /// screen whose controls report TutorialTargetBounds. Sheets need their
    /// own attachment when C5 adds targets inside them.
    func tutorialOverlay(session: GameSession) -> some View {
        overlayPreferenceValue(TutorialTargetBounds.self) { anchors in
            GeometryReader { proxy in
                if let tutorial = session.tutorial {
                    let viewport = CGRect(origin: .zero, size: proxy.size)
                    let frames = tutorial.step.targets.compactMap { target -> CGRect? in
                        anchors[target]?.visibleFrame(in: proxy, viewport: viewport)
                    }
                    // Every control the player may need stays clear of the card,
                    // whatever its size (a full-width Build Track button is
                    // one). The map is the exception: it fills the screen and
                    // is tapped past the card.
                    let controls = anchors.compactMap { target, anchor -> CGRect? in
                        target == .map ? nil : anchor.visibleFrame(in: proxy, viewport: viewport)
                    }
                    // What the step asks the player to use matters most when
                    // no placement leaves every control clear.
                    let required = tutorial.step.targets.compactMap { target -> CGRect? in
                        target == .map ? nil : anchors[target]?.visibleFrame(in: proxy, viewport: viewport)
                    }
                    TutorialOverlay(session: session, tutorial: tutorial, frames: frames, controls: controls, required: required)
                }
            }
        }
    }
}

/// Only the card receives touches: outlining a tool or the map must leave
/// it usable, because Next waits for the player to perform the step.
private struct TutorialOverlay: View {
    let session: GameSession
    let tutorial: Tutorial
    let frames: [CGRect]
    let controls: [CGRect]
    let required: [CGRect]

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(frames.indices, id: \.self) { index in
                let frame = frames[index]
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Theme.accent, lineWidth: 3)
                    .background {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.black.opacity(0.35), lineWidth: 5)
                    }
                    .frame(width: frame.width + 6, height: frame.height + 6)
                    .position(x: frame.midX, y: frame.midY)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)

            TutorialCardLayout(target: frames.first, controls: controls, required: required) {
                TutorialCard(session: session, tutorial: tutorial)
                    .id(tutorial.index)
            }
        }
    }
}

/// Measures the actual card (including translated text and Dynamic Type),
/// then tries below/above the first visible target, with sides as a fallback
/// for wide screens, then inside a large target such as the map, then the
/// centre and the edges. The first placement that covers no control wins;
/// when every one covers something, the one that covers least, sparing the
/// step's own controls first. Missing targets use the centre.
private struct TutorialCardLayout: Layout {
    let target: CGRect?
    let controls: [CGRect]
    /// The step's own controls (not the map), among `controls`.
    let required: [CGRect]
    private let margin: CGFloat = 16
    private let gap: CGFloat = 12

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let card = subviews.first else { return }
        let available = bounds.insetBy(dx: min(margin, bounds.width / 4), dy: min(margin, bounds.height / 4))
        let cardProposal = ProposedViewSize(width: min(340, available.width), height: available.height)
        let size = card.sizeThatFits(cardProposal)
        let centred = CGPoint(x: available.midX - size.width / 2, y: available.midY - size.height / 2)
        var origin = centred

        if let target {
            // Anchors are local to the overlay's GeometryReader. Layout's
            // placement bounds can have a nonzero origin, so put the target
            // in that same coordinate space before comparing candidates.
            let target = target.offsetBy(dx: bounds.minX, dy: bounds.minY)
            // Keep the other controls usable too. `controls` leaves out the
            // map, which can be tapped outside the card.
            let obstacles = controls.map { $0.offsetBy(dx: bounds.minX, dy: bounds.minY) }
            let required = self.required.map { $0.offsetBy(dx: bounds.minX, dy: bounds.minY) }
            let x = max(available.minX, min(target.midX - size.width / 2, available.maxX - size.width))
            let y = max(available.minY, min(target.midY - size.height / 2, available.maxY - size.height))
            let candidates = [
                CGPoint(x: x, y: target.maxY + gap),
                CGPoint(x: x, y: target.minY - gap - size.height),
                CGPoint(x: target.maxX + gap, y: y),
                CGPoint(x: target.minX - gap - size.width, y: y),
                // Inside a target as large as the map, along its bottom or
                // top: the rest of it stays free to tap.
                CGPoint(x: x, y: target.maxY - gap - size.height),
                CGPoint(x: x, y: target.minY + gap),
                centred,
                CGPoint(x: available.minX, y: centred.y),
                CGPoint(x: available.maxX - size.width, y: centred.y),
                CGPoint(x: centred.x, y: available.minY),
                CGPoint(x: centred.x, y: available.maxY - size.height),
                CGPoint(x: available.minX, y: available.minY),
                CGPoint(x: available.maxX - size.width, y: available.minY),
                CGPoint(x: available.minX, y: available.maxY - size.height),
                CGPoint(x: available.maxX - size.width, y: available.maxY - size.height),
            ]
            func covered(_ rects: [CGRect], by frame: CGRect) -> CGFloat {
                rects.reduce(0) { sum, rect in
                    let common = rect.intersection(frame)
                    return common.isNull ? sum : sum + common.width * common.height
                }
            }
            func cost(_ frame: CGRect) -> CGFloat {
                covered(required, by: frame) * 1_000 + covered(obstacles, by: frame)
            }
            let placements = candidates
                .map { CGRect(origin: $0, size: size) }
                .filter { available.contains($0) }
            // `min` keeps the first of equals, so the first placement that
            // covers nothing wins, as the order above intends.
            origin = placements.min { cost($0) < cost($1) }?.origin ?? centred
        }
        card.place(at: origin, anchor: .topLeading, proposal: ProposedViewSize(size))
    }
}

private struct TutorialCard: View {
    let session: GameSession
    let tutorial: Tutorial
    @AccessibilityFocusState private var focusesTitle: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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
        .padding(16)
        .controlSize(.large)
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
        VStack(alignment: .leading, spacing: 10) {
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

            Text(verbatim: tutorial.step.title(in: session.language))
                .font(.headline.weight(.bold))
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($focusesTitle)
                .accessibilityIdentifier("tutorial.title")
            Text(verbatim: tutorial.step.body(in: session.language))
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            if !session.isTutorialStepDone {
                HStack(spacing: 6) {
                    Image(systemName: "hand.tap.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.warning)
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
        Button("Skip") { session.skipTutorial() }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("tutorial.skip")
        if !tutorial.isFirstStep {
            Button("Back") { session.showPreviousTutorialStep() }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("tutorial.back")
        }
        Button {
            session.showNextTutorialStep()
        } label: {
            Group {
                if tutorial.isLastStep {
                    Text("Done")
                } else {
                    Text("Next")
                }
            }
            .frame(minHeight: 44)
        }
        .buttonStyle(ThemeProminentButtonStyle())
        .disabled(!session.isTutorialStepDone)
        .accessibilityIdentifier("tutorial.next")
    }
}
