import GameCore
import GamePresentation
import SwiftUI

/// Tool picker, selection inspector, tool options and the action button,
/// in two parts: the tool picker, always shown, and the details under it,
/// which the screen can fold away (``ContentView``).
struct ControlPanel: View {
    enum Arrangement {
        /// The tool picker alone.
        case tools
        /// The selection inspector, the tool's options and the action
        /// button, in one column.
        case details
    }

    let session: GameSession
    let arrangement: Arrangement

    var body: some View {
        switch arrangement {
        case .tools:
            ToolPicker(session: session)
        case .details:
            VStack(alignment: .leading, spacing: 12) {
                InspectorView(session: session)
                ToolOptions(session: session)
                    .frame(minHeight: ToolOptions.minimumHeight, alignment: .topLeading)
                ActionButton(session: session)
            }
        }
    }
}

/// One button per tool the app offers (Stage F1: the track network only),
/// in a row. The active tool is filled and its name bold, so the state does
/// not depend on colour alone.
private struct ToolPicker: View {
    let session: GameSession

    var body: some View {
        HStack(spacing: 6) {
            ForEach(ConstructionTool.networkTools, id: \.self) { tool in
                let isActive = session.tool == tool
                Button {
                    session.selectTool(tool)
                } label: {
                    label(for: tool, isActive: isActive)
                }
                .buttonStyle(ThemeSelectableButtonStyle(isActive: isActive))
                .accessibilityLabel(tool.accessibilityName)
                // Stable across localizations for screenshot-only UI tests.
                .accessibilityIdentifier("tool.\(tool)")
                .accessibilityAddTraits(isActive ? .isSelected : [])
                .tutorialTarget(TutorialTarget(tool: tool))
            }
        }
        .padding(3)
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(Theme.panelBorder, lineWidth: 1)
        )
    }

    private func label(for tool: ConstructionTool, isActive: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: tool.systemImage)
                .font(.subheadline.weight(.semibold))
            Text(tool.title(in: session.language))
                .font(.subheadline.weight(isActive ? .bold : .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, minHeight: 38)
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
                .foregroundStyle(Theme.textSecondary)
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
                HStack(spacing: 8) {
                    Image(systemName: session.tool.systemImage)
                        .font(.body.weight(.bold))
                    Text(title)
                        .font(.headline.weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(ThemeProminentButtonStyle(isDestructive: isRemoval))
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
        // A success clears itself (``StatusMessage/autoDismissDelay``), so
        // a panel's banner does not stay over its last row; a newer message
        // restarts the wait, and a problem stays until dismissed.
        .task(id: session.message) {
            guard let message = session.message, let delay = message.autoDismissDelay else { return }
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            session.dismissMessage(message)
        }
    }

    private func banner(for message: StatusMessage) -> some View {
        let isSuccess = message.kind == .success
        let kindName = isSuccess ? String(localized: "Done") : String(localized: "Problem")
        let tintColor = isSuccess ? Theme.success : Theme.warning
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(tintColor)
                .accessibilityLabel(kindName)
            Text(message.text)
                .font(.footnote.weight(.medium))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button {
                session.dismissMessage()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .frame(width: 26, height: 26)
                    .background(Theme.panelBorder, in: Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.textSecondary)
            .accessibilityLabel("Dismiss message")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glassBackground(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(tintColor.opacity(0.5), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .padding(10)
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
