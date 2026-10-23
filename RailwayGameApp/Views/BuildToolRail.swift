import GameCore
import GamePresentation
import SwiftUI

/// The tools, in a column down the map's leading edge while building
/// (decision 114): the track network, trains and buildings, then Done,
/// which goes back to looking at the map (the Select tool). The dock's
/// Build entry (``BuildEntry``) opens it; there is no Select button in
/// the dock any more, as a tap on the map selects whenever no tool is
/// chosen. In the tutorial too only while building (decision 226, later:
/// the tutorial uses the game's own controls; its first step points at
/// Build).
struct BuildToolRail: View {
    let session: GameSession
    /// The most height the rail may take: between the status pill and the
    /// dock. Past it the rail scrolls.
    let maxHeight: CGFloat

    /// The column's width: 66.1's 72 points, wider than the phone's tools
    /// column, as the map has room to spare beside it (``ToolColumn``).
    static let width = CGFloat(ToolColumn.railWidth)

    /// Whether the rail shows.
    @MainActor
    static func isShown(_ session: GameSession) -> Bool {
        ScreenTools.showsBuildingTools(tool: session.tool)
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
        // Decision 388: its edges, for the alignment UI test.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("hud.rail")
        // Offered only the room between the pill and the dock, from the top.
        .frame(maxHeight: maxHeight, alignment: .top)
    }

    private func column(compact: Bool) -> some View {
        BuildToolButtons(session: session)
            .padding(ToolColumnStyle.tilePadding)
            .environment(\.toolColumnStyle, ToolColumnStyle(compact: compact, buttonWidth: CGFloat(ToolColumn.railButtonWidth)))
    }
}

/// The building tools and Done, one under the other, in the size the
/// column they stand in gives them (``ToolColumnStyle``): the rail beside
/// the map (``BuildToolRail``), or a group of the phone's tools column.
struct BuildToolButtons: View {
    let session: GameSession
    /// Whether Done closes the group: not where it stands apart, pinned
    /// over Build (``BuildDoneButton``).
    var includesDone = true
    @Environment(\.toolColumnStyle) private var column

    var body: some View {
        VStack(spacing: ToolColumnStyle.buttonSpacing) {
            // Decision 266: in a lesson, only the tools it has unlocked.
            ForEach(ConstructionTool.networkTools.filter { $0 != .select && session.allows($0) }, id: \.self) { tool in
                toolButton(tool)
            }
            if includesDone {
                if column?.compact != true {
                    Divider()
                        .padding(.horizontal, 6)
                }
                BuildDoneButton(session: session)
            }
        }
    }

    private func toolButton(_ tool: ConstructionTool) -> some View {
        let isActive = session.tool == tool
        return Button {
            // A tool chosen again stays chosen: Done, or Build in the dock,
            // goes back to looking at the map.
            UITestTrace.action("tool.\(tool)")
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
}

/// Done: back to looking at the map.
struct BuildDoneButton: View {
    let session: GameSession

    var body: some View {
        let isActive = session.tool == .select
        return Button {
            UITestTrace.action("tool.select")
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
/// pressed again, closes them and goes back to looking at the map. In the
/// tutorial only on its step that asks for that (Done's), as its other
/// steps wait for a tool to stay chosen (as decision 104's second tap).
struct BuildEntry: View {
    let session: GameSession

    var body: some View {
        let isActive = session.tool != .select
        Button {
            if !isActive {
                session.selectTool(.network)
            } else if session.tutorial.map({ $0.step.goal == .chooseTool(.select) }) ?? true {
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
        .tutorialTarget(.buildEntry)
    }
}
