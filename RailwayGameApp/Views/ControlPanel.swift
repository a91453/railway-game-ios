import GameCore
import GamePresentation
import SwiftUI

/// Tool picker, selection inspector, tool options and the action button.
struct ControlPanel: View {
    enum Arrangement {
        /// Everything in one column (phones, and the sidebar on wide screens).
        case column
        /// Tools and action on the left, options on the right (iPad portrait).
        case sideBySide
    }

    let session: GameSession
    let arrangement: Arrangement

    var body: some View {
        switch arrangement {
        case .column:
            VStack(alignment: .leading, spacing: 12) {
                ToolPicker(session: session)
                InspectorView(session: session)
                ToolOptions(session: session)
                    .frame(minHeight: ToolOptions.minimumHeight, alignment: .topLeading)
                ActionButton(session: session)
            }
        case .sideBySide:
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    ToolPicker(session: session, showsDetails: true)
                    InspectorView(session: session)
                    ActionButton(session: session)
                }
                .frame(maxWidth: 360)
                Divider()
                VStack(alignment: .leading, spacing: 16) {
                    ToolOptions(session: session)
                        .frame(minHeight: ToolOptions.minimumHeight, alignment: .topLeading)
                    Divider()
                    NetworkOverview(session: session)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }
}

/// One button per tool the app offers (Stage F1: the track network only),
/// a row of compact buttons, or a list with what each tool costs where
/// there is room. The active tool is filled, the others outlined, so the
/// state does not depend on colour alone.
private struct ToolPicker: View {
    let session: GameSession
    var showsDetails = false

    var body: some View {
        let layout = showsDetails
            ? AnyLayout(VStackLayout(spacing: 6))
            : AnyLayout(HStackLayout(spacing: 8))
        layout {
            ForEach(ConstructionTool.networkTools, id: \.self) { tool in
                let isActive = session.tool == tool
                Button {
                    session.selectTool(tool)
                } label: {
                    if showsDetails {
                        detailedLabel(for: tool, isActive: isActive)
                    } else {
                        compactLabel(for: tool, isActive: isActive)
                    }
                }
                .buttonStyle(SelectableButtonStyle(isActive: isActive))
                .accessibilityLabel(tool.accessibilityName)
                // Stable across localizations for screenshot-only UI tests.
                .accessibilityIdentifier("tool.\(tool)")
                .accessibilityAddTraits(isActive ? .isSelected : [])
                .tutorialTarget(TutorialTarget(tool: tool))
            }
        }
    }

    private func compactLabel(for tool: ConstructionTool, isActive: Bool) -> some View {
        VStack(spacing: 2) {
            Image(systemName: tool.systemImage)
                .font(.body.weight(.semibold))
            Text(tool.title(in: session.language))
                .font(.caption.weight(isActive ? .bold : .regular))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, minHeight: 40)
    }

    private func detailedLabel(for tool: ConstructionTool, isActive: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: tool.systemImage)
                .font(.title3.weight(.semibold))
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(tool.title(in: session.language))
                    .font(.subheadline.weight(isActive ? .bold : .semibold))
                Text(detail(for: tool))
                    .font(.caption)
                    .opacity(0.8)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    }

    private func detail(for tool: ConstructionTool) -> String {
        let costs = session.world.economy.costs
        switch tool {
        case .select: return String(localized: "Inspect stations and track")
        case .network: return String(localized: "Track, platforms and stations · \(costs.track.moneyText) per 16 m")
        case .train: return String(localized: "Place and send trains · \(costs.train.moneyText) each")
        }
    }
}

/// What the active tool needs besides a tap on the map.
private struct ToolOptions: View {
    /// Keeps the panel from jumping in height between tools.
    static let minimumHeight = 116.0

    @Bindable var session: GameSession

    var body: some View {
        switch session.tool {
        case .select:
            Label("Choose Network to build track, platforms and stations. Selecting only inspects.", systemImage: "info.circle")
                .font(.footnote)
                .foregroundStyle(.secondary)
        case .network:
            NetworkControls(session: session)
        case .train:
            TrainControls(session: session)
        }
    }
}

/// Applies the train tool to the selected station, or, with the network
/// tool, builds, adds or removes what its taps picked. Shows the cost read
/// from the world's economy or GameCore's preview; GameCore decides whether
/// the action is allowed.
private struct ActionButton: View {
    let session: GameSession

    var body: some View {
        if let title {
            Button {
                act()
            } label: {
                Label(title, systemImage: session.tool.systemImage)
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 32)
            }
            .buttonStyle(.borderedProminent)
            .tint(isRemoval ? Color.red : Color.accentColor)
            .disabled(!isReady)
            .accessibilityHint(hint)
            .tutorialTarget(.actionButton)
        }
    }

    private var isRemoval: Bool {
        session.tool == .network && session.networkMode == .remove
    }

    private var isReady: Bool {
        guard session.tool == .network else { return session.selectedPoint != nil }
        switch session.networkMode {
        case .build: return session.networkPreview != nil
        case .platform, .remove: return session.networkEdgePoint != nil
        }
    }

    private func act() {
        guard session.tool == .network else {
            session.applyTool()
            return
        }
        switch session.networkMode {
        case .build: session.buildNetworkTrack()
        case .platform: session.addNetworkPlatform()
        case .remove: session.removeNetworkEdge()
        }
    }

    private var hint: String {
        guard !isReady else { return "" }
        return session.tool == .network ? String(localized: "Tap the map first.") : String(localized: "Select a station on the map first.")
    }

    private var title: String? {
        switch session.tool {
        case .select: return nil
        case .network:
            switch session.networkMode {
            case .build:
                guard let cost = session.networkPreview?.cost else { return String(localized: "Build Track") }
                return String(localized: "Build Track · \(cost.moneyText)")
            case .platform: return String(localized: "Add Platform")
            case .remove: return String(localized: "Remove Track")
            }
        case .train:
            // Placing and sending both act on the selected train.
            guard let train = session.selectedTrain else { return nil }
            return train.position == nil ? String(localized: "Place \(train.name) Here") : String(localized: "Send \(train.name) Here")
        }
    }
}

/// The result of the last action, shown over the top of the map and
/// announced to VoiceOver, since focus stays on the button that caused it.
struct StatusBanner: View {
    let session: GameSession

    var body: some View {
        Group {
            if let message = session.message {
                banner(for: message)
            }
        }
        .onChange(of: session.message) { _, message in
            if let message {
                AccessibilityNotification.Announcement(message.text).post()
            }
        }
    }

    private func banner(for message: StatusMessage) -> some View {
        let isSuccess = message.kind == .success
        let kindName = isSuccess ? String(localized: "Done") : String(localized: "Problem")
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(isSuccess ? Color.green : Color.orange)
                .accessibilityLabel(kindName)
            Text(message.text)
                .font(.footnote.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button {
                session.dismissMessage()
            } label: {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.bold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Dismiss message")
        }
        .padding(.leading, 12)
        .padding(.vertical, 4)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isSuccess ? Color.green.opacity(0.5) : Color.orange.opacity(0.7))
        )
        .accessibilityElement(children: .contain)
        .padding(10)
    }
}

/// Filled when active, outlined otherwise, so state does not rely on colour.
struct SelectableButtonStyle: ButtonStyle {
    let isActive: Bool

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 10)
        configuration.label
            .padding(.vertical, 4)
            .foregroundStyle(isActive ? Color.white : Color.primary)
            .background(isActive ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.fill.tertiary), in: shape)
            .overlay(shape.strokeBorder(isActive ? Color.clear : Color.secondary.opacity(0.35)))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(shape)
    }
}

extension ConstructionTool {
    var systemImage: String {
        switch self {
        case .select: "hand.point.up.left"
        case .network: "point.topleft.down.curvedto.point.bottomright.up"
        case .train: "train.side.front.car"
        }
    }

    var accessibilityName: String {
        switch self {
        case .select: String(localized: "Select tool")
        case .network: String(localized: "Track network tool")
        case .train: String(localized: "Train tool")
        }
    }
}
