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
    @State private var contentHeight: CGFloat = 0

    /// The column's width.
    static let width: CGFloat = 72

    /// Whether the rail shows.
    @MainActor
    static func isShown(_ session: GameSession) -> Bool {
        session.tool != .select || session.tutorial != nil
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                ForEach(ConstructionTool.networkTools.filter { $0 != .select }, id: \.self) { tool in
                    toolButton(tool)
                }
                Divider()
                    .padding(.horizontal, 6)
                doneButton
            }
            .padding(6)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(.hidden)
        .tutorialClip()
        .frame(width: Self.width, height: min(max(contentHeight, 1), maxHeight))
        .glassBackground(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func toolButton(_ tool: ConstructionTool) -> some View {
        let isActive = session.tool == tool
        return Button {
            // A tool chosen again stays chosen: Done, or Build in the dock,
            // goes back to looking at the map.
            session.selectTool(tool)
        } label: {
            TabLabel(systemImage: tool.systemImage, title: tool.title(in: session.language), isActive: isActive)
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
    private var doneButton: some View {
        let isActive = session.tool == .select
        return Button {
            session.selectTool(.select)
        } label: {
            TabLabel(systemImage: "xmark", title: session.language.text("Done", "完成"), isActive: isActive)
        }
        .buttonStyle(ThemeSelectableButtonStyle(isActive: isActive))
        .accessibilityLabel(Text(verbatim: session.language.text("Done building", "完成建設")))
        // The Select tool's identifier: the tutorial and the UI tests choose
        // it by this name.
        .accessibilityIdentifier("tool.select")
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .tutorialTarget(TutorialTarget(tool: .select))
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
        .padding(3)
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(Theme.panelBorder, lineWidth: 1)
        )
    }
}
