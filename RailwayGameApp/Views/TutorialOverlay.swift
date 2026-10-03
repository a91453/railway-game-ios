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
                    let controls = anchors.values.compactMap { anchor -> CGRect? in
                        let visible = proxy[anchor].intersection(viewport)
                        return visible.isEmpty || visible.isNull ? nil : visible
                    }
                    let frames = tutorial.step.targets.compactMap { target -> CGRect? in
                        guard let anchor = anchors[target] else { return nil }
                        let visible = proxy[anchor].intersection(viewport)
                        return visible.isEmpty || visible.isNull ? nil : visible
                    }
                    TutorialOverlay(session: session, tutorial: tutorial, frames: frames, controls: controls)
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

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(frames.indices, id: \.self) { index in
                let frame = frames[index]
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.accentColor, lineWidth: 3)
                    .background {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color(uiColor: .systemBackground), lineWidth: 5)
                    }
                    .frame(width: frame.width + 4, height: frame.height + 4)
                    .position(x: frame.midX, y: frame.midY)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)

            TutorialCardLayout(target: frames.first, controls: controls) {
                TutorialCard(session: session, tutorial: tutorial)
                    .id(tutorial.index)
            }
        }
    }
}

/// Measures the actual card (including translated text and Dynamic Type),
/// then tries below/above the first visible target, with sides as a fallback
/// for wide screens. Missing targets and insufficient space use the centre.
private struct TutorialCardLayout: Layout {
    let target: CGRect?
    let controls: [CGRect]
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
            // Keep other small controls usable too. A large target can
            // still be used outside the card (for example, tapping a map).
            let obstacles = controls.filter { $0.width <= size.width && $0.height <= size.height }
                .map { $0.offsetBy(dx: bounds.minX, dy: bounds.minY) }
            let x = max(available.minX, min(target.midX - size.width / 2, available.maxX - size.width))
            let y = max(available.minY, min(target.midY - size.height / 2, available.maxY - size.height))
            let candidates = [
                CGPoint(x: x, y: target.maxY + gap),
                CGPoint(x: x, y: target.minY - gap - size.height),
                CGPoint(x: target.maxX + gap, y: y),
                CGPoint(x: target.minX - gap - size.width, y: y),
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
            origin = candidates.first {
                let frame = CGRect(origin: $0, size: size)
                return available.contains(frame) && !obstacles.contains { $0.intersects(frame) }
            } ?? centred
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
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.primary.opacity(0.15))
                .allowsHitTesting(false)
        }
        .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tutorial.card")
        .onChange(of: tutorial.index, initial: true) { _, _ in
            focusesTitle = true
        }
    }

    private var explanation: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Step \(tutorial.index + 1) of \(tutorial.steps.count)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .accessibilityIdentifier("tutorial.progress")
            Text(verbatim: tutorial.step.title(in: session.language))
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($focusesTitle)
                .accessibilityIdentifier("tutorial.title")
            Text(verbatim: tutorial.step.body(in: session.language))
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            if !session.isTutorialStepDone {
                Label("Complete this step to continue.", systemImage: "hand.tap")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
            if tutorial.isLastStep {
                Text("Done")
            } else {
                Text("Next")
            }
        }
        .buttonStyle(.borderedProminent)
        .disabled(!session.isTutorialStepDone)
        .accessibilityIdentifier("tutorial.next")
    }
}
