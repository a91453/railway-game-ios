import GameCore
import GamePresentation
import SwiftUI

/// The tools, in a column down the map's leading edge while building
/// (decision 114): the track network, trains and buildings, then Done,
/// which goes back to looking at the map (the Select tool). The dock's
/// Build entry (``BuildEntry``) opens it; there is no Select button in
/// the dock any more, as a tap on the map selects whenever no tool is
/// chosen. Shown throughout the tutorial, whose steps point at the tools.
struct BuildToolRail: View {
    let session: GameSession
    /// The most height the rail may take: between the status pill and the
    /// dock. Past it the rail scrolls.
    let maxHeight: CGFloat

    /// The column's width.
    static let width: CGFloat = 72

    /// Whether the rail shows.
    @MainActor
    static func isShown(_ session: GameSession) -> Bool {
        session.tool != .select || session.tutorial != nil
    }

    /// The column with names under the icons where it fits, else the icons
    /// alone (decision 123: a phone held sideways has less room than the
    /// labelled column between the pill and the dock, and the last button,
    /// Done, was cut in half; the names stay the buttons' accessibility
    /// labels), else the icons scrolling. Chosen by `ViewThatFits`, not by
    /// heights the rail measured and kept: a rail on screen from the first
    /// frame (a game opened at a later tutorial step) kept its scroll view
    /// below its buttons once the screen settled, and Done could not be
    /// tapped (TutorialUITests, run 38259103200).
    var body: some View {
        ViewThatFits(in: .vertical) {
            column(compact: false)
            column(compact: true)
            ScrollView {
                column(compact: true)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
            .tutorialClip()
        }
        .frame(width: Self.width)
        .glassBackground(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        // Offered only the room between the pill and the dock, from the top.
        .frame(maxHeight: maxHeight, alignment: .top)
    }

    private func column(compact: Bool) -> some View {
        VStack(spacing: compact ? 4 : 6) {
            ForEach(ConstructionTool.networkTools.filter { $0 != .select }, id: \.self) { tool in
                toolButton(tool, compact: compact)
            }
            if !compact {
                Divider()
                    .padding(.horizontal, 6)
            }
            doneButton(compact: compact)
        }
        .padding(compact ? 4 : 6)
    }

    private func toolButton(_ tool: ConstructionTool, compact: Bool) -> some View {
        let isActive = session.tool == tool
        return Button {
            // A tool chosen again stays chosen: Done, or Build in the dock,
            // goes back to looking at the map.
            UITestTrace.action("tool.\(tool)")
            session.selectTool(tool)
        } label: {
            label(tool.systemImage, tool.title(in: session.language), isActive: isActive, compact: compact)
        }
        .buttonStyle(ThemeSelectableButtonStyle(isActive: isActive))
        .accessibilityLabel(tool.accessibilityName)
        // Stable across localizations for the Traditional Chinese toolbar UI test.
        .accessibilityIdentifier("tool.\(tool)")
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .tutorialTarget(TutorialTarget(tool: tool))
    }

    /// Back to looking at the map. Selected while no tool is chosen, which
    /// only shows during the tutorial (the rail is hidden otherwise).
    private func doneButton(compact: Bool) -> some View {
        let isActive = session.tool == .select
        return Button {
            UITestTrace.action("tool.select")
            session.selectTool(.select)
        } label: {
            label("xmark", session.language.text("Done", "完成"), isActive: isActive, compact: compact)
        }
        .buttonStyle(ThemeSelectableButtonStyle(isActive: isActive))
        .accessibilityLabel(Text(verbatim: session.language.text("Done building", "完成建設")))
        // The Select tool's identifier: the tutorial and the UI tests choose
        // it by this name.
        .accessibilityIdentifier("tool.select")
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .tutorialTarget(TutorialTarget(tool: .select))
    }

    @ViewBuilder
    private func label(_ systemImage: String, _ title: String, isActive: Bool, compact: Bool) -> some View {
        if compact {
            // 32 points and the style's 4 above and below: four buttons in
            // the room a phone held sideways leaves.
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .frame(minWidth: 48, maxWidth: .infinity, minHeight: 32)
        } else {
            TabLabel(systemImage: systemImage, title: title, isActive: isActive)
        }
    }
}

/// The dock's way into building (decision 114): opens the tools at the
/// map's edge (``BuildToolRail``), starting with the track network, and,
/// pressed again, closes them and goes back to looking at the map. Not
/// in the tutorial, whose steps wait for a tool to stay chosen (as
/// decision 104's second tap).
struct BuildEntry: View {
    let session: GameSession

    var body: some View {
        let isActive = session.tool != .select
        Button {
            if !isActive {
                session.selectTool(.network)
            } else if session.tutorial == nil {
                session.selectTool(.select)
            }
        } label: {
            TabLabel(systemImage: "hammer.fill", title: session.language.text("Build", "建設"), isActive: isActive)
        }
        .buttonStyle(ThemeSelectableButtonStyle(isActive: isActive))
        .accessibilityLabel(Text(verbatim: session.language.text("Construction", "建設")))
        .accessibilityHint(Text(verbatim: session.language.text(
            "Shows the track, train and building tools at the map's edge.",
            "在地圖邊緣顯示軌道、列車與建築工具。"
        )))
        .accessibilityIdentifier("dock.build")
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}
