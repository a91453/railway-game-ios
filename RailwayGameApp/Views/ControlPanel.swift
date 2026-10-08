import GameCore
import GamePresentation
import SwiftUI

/// Tool picker, selection inspector, tool options and the action button,
/// in two parts: the tool picker, always shown, and the details under it,
/// which the screen can fold away (``ContentView``).
struct ControlPanel: View {
    enum Arrangement {
        /// The tool picker alone, in a row.
        case tools
        /// The tool picker alone, as a list with what each tool does and
        /// costs: an iPad's open control card, which has the room.
        case detailedTools
        /// The selection inspector, the tool's options and the action
        /// button, in one column.
        case details
    }

    let session: GameSession
    let arrangement: Arrangement

    var body: some View {
        switch arrangement {
        case .tools, .detailedTools:
            HStack(alignment: arrangement == .detailedTools ? .top : .center, spacing: 8) {
                ToolPicker(session: session, showsDetails: arrangement == .detailedTools)
                // Hidden during the tutorial, as the details toggle is, so
                // its steps' spotlights stay where they were; the session
                // refuses Undo then too (``GameSession/canUndo``).
                if session.tutorial == nil {
                    UndoButton(session: session)
                }
            }
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
/// in a row, or a list with what each tool does and costs where there is
/// room. The active tool is filled and its name bold, so the state does not
/// depend on colour alone.
private struct ToolPicker: View {
    let session: GameSession
    var showsDetails = false

    var body: some View {
        let layout = showsDetails
            ? AnyLayout(VStackLayout(spacing: 6))
            : AnyLayout(HStackLayout(spacing: 6))
        layout {
            ForEach(ConstructionTool.networkTools, id: \.self) { tool in
                let isActive = session.tool == tool
                Button {
                    session.selectTool(tool)
                } label: {
                    if showsDetails {
                        detailedLabel(for: tool, isActive: isActive)
                    } else {
                        label(for: tool, isActive: isActive)
                    }
                }
                .buttonStyle(ThemeSelectableButtonStyle(isActive: isActive))
                .accessibilityLabel(tool.accessibilityName)
                // Stable across localizations for the Traditional Chinese toolbar UI test.
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

    private func detailedLabel(for tool: ConstructionTool, isActive: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: tool.systemImage)
                .font(.body.weight(.semibold))
                .frame(width: 34, height: 34)
                .background(isActive ? Theme.onPrimary.opacity(0.2) : Theme.chip, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(tool.title(in: session.language))
                    .font(.subheadline.weight(isActive ? .bold : .semibold))
                Text(detail(for: tool))
                    .font(.caption)
                    .foregroundStyle(isActive ? Theme.onPrimary : Theme.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
    }

    private func detail(for tool: ConstructionTool) -> String {
        let costs = session.world.economy.costs
        switch tool {
        case .select: return String(localized: "Inspect stations and track")
        case .network: return String(localized: "Track, platforms and stations · \(costs.track.moneyText) per 16 m")
        case .train: return String(localized: "Place and send trains · \(costs.train.moneyText) each")
        case .building: return String(localized: "Houses, shops and offices, where you tap")
        }
    }
}

/// Takes back the last edit (ARCHITECTURE decision 82, MapBuilder's undo
/// button). Disabled while there is nothing to take back: before any edit,
/// and once game time has moved on since, so in practice while paused.
private struct UndoButton: View {
    let session: GameSession

    var body: some View {
        Button {
            session.undo()
        } label: {
            Image(systemName: "arrow.uturn.backward")
                .font(.subheadline.weight(.bold))
                .frame(width: 40, height: 38)
                .opacity(session.canUndo ? 1 : 0.4)
        }
        .buttonStyle(ThemeSelectableButtonStyle(isActive: false))
        .disabled(!session.canUndo)
        .accessibilityLabel("Undo")
        .accessibilityHint("Takes back the last edit, refunding what it cost. Only until game time moves on.")
        .accessibilityIdentifier("controls.undo")
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
        case .building:
            BuildingControls(session: session)
        }
    }
}

/// The building tool (city building P0-A, decision 92): what a tap on the
/// map puts up, and how many the player has put up. GameCore decides
/// whether a building fits where the player taps.
private struct BuildingControls: View {
    @Bindable var session: GameSession

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ForEach(PlacedBuildingKind.allCases, id: \.self) { kind in
                    let isActive = session.buildingKind == kind
                    Button {
                        session.buildingKind = kind
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: kind.systemImage)
                                .font(.subheadline.weight(.semibold))
                            Text(kind.title(in: session.language))
                                .font(.subheadline.weight(isActive ? .bold : .medium))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity, minHeight: 38)
                    }
                    .buttonStyle(ThemeSelectableButtonStyle(isActive: isActive))
                    .accessibilityIdentifier("building.kind.\(kind.rawValue)")
                    .accessibilityAddTraits(isActive ? .isSelected : [])
                }
            }
            Label("Tap open ground on the map to build. It cannot stand on track, a station or another building.", systemImage: "hand.tap")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
            Text(verbatim: session.placedBuildingsText)
                .font(.footnote.weight(.semibold))
                .monospacedDigit()
                .accessibilityIdentifier("building.count")
        }
    }
}

extension PlacedBuildingKind {
    var systemImage: String {
        switch self {
        case .house: "house.fill"
        case .shop: "storefront.fill"
        case .office: "building.2.fill"
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
        // The building tool acts on the tap itself.
        case .select, .building: return nil
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
        // By the serial, not the message: the same text posted again (a
        // second save) is announced again and waits its own while.
        .onChange(of: session.messageSerial) {
            if let message = session.message {
                AccessibilityNotification.Announcement(message.text).post()
            }
        }
        // A success clears itself (``StatusMessage/autoDismissDelay``), so
        // a panel's banner does not stay over its last row; a newer message
        // restarts the wait, and a problem stays until dismissed.
        .task(id: session.messageSerial) {
            let serial = session.messageSerial
            guard let message = session.message, let delay = message.autoDismissDelay else { return }
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            session.dismissMessage(posted: serial)
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
        case .building: "building.2"
        }
    }

    var accessibilityName: String {
        switch self {
        case .select: String(localized: "Select tool")
        case .network: String(localized: "Track network tool")
        case .train: String(localized: "Train tool")
        case .building: String(localized: "Building tool")
        }
    }
}
