import GameCore
import GamePresentation
import SwiftUI

/// Tool picker, selected-tile inspector, tool options and the action button.
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
                    .frame(minHeight: TrackPieceEditor.height, alignment: .topLeading)
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
                        .frame(minHeight: TrackPieceEditor.height, alignment: .topLeading)
                    Divider()
                    NetworkOverview(session: session)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }
}

/// One button per construction tool: a row of compact buttons, or a list
/// with what each tool costs where there is room. The active tool is filled,
/// the others outlined, so the state does not depend on colour alone.
private struct ToolPicker: View {
    let session: GameSession
    var showsDetails = false

    var body: some View {
        let layout = showsDetails
            ? AnyLayout(VStackLayout(spacing: 6))
            : AnyLayout(HStackLayout(spacing: 8))
        layout {
            ForEach(ConstructionTool.allCases, id: \.self) { tool in
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
                .accessibilityAddTraits(isActive ? .isSelected : [])
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
        case .select: return String(localized: "Inspect a tile")
        case .buildTrack: return String(localized: "Lay a track piece · \(costs.track.moneyText)")
        case .buildStation: return String(localized: "Build a station · \(costs.station.moneyText)")
        case .removeTrack: return String(localized: "Remove track · free, no refund")
        case .train: return String(localized: "Place and send trains · \(costs.train.moneyText) each")
        }
    }
}

/// What the active tool needs besides a tile.
private struct ToolOptions: View {
    @Bindable var session: GameSession

    var body: some View {
        switch session.tool {
        case .select:
            Label("Choose Track, Station or Remove to build. Selecting only inspects.", systemImage: "info.circle")
                .font(.footnote)
                .foregroundStyle(.secondary)
        case .buildTrack:
            TrackPieceEditor(session: session)
        case .buildStation:
            VStack(alignment: .leading, spacing: 6) {
                Picker("Station", selection: $session.growsStation) {
                    Text("New station").tag(false)
                    Text("Grow a station").tag(true)
                }
                .pickerStyle(.segmented)
                if session.growsStation {
                    Label("Select an empty tile beside a station: it grows onto it, and track beside the new tile becomes platform.", systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Station name")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("Station name", text: $session.stationName)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                }
            }
        case .removeTrack:
            Label("Removing track is free, but its cost is not refunded.", systemImage: "info.circle")
                .font(.footnote)
                .foregroundStyle(.secondary)
        case .train:
            TrainControls(session: session)
        }
    }
}

/// Applies the active tool to the selected tile. Shows the cost read from
/// the world's economy; GameCore decides whether the action is allowed.
private struct ActionButton: View {
    let session: GameSession

    var body: some View {
        if let title {
            Button {
                session.applyTool()
            } label: {
                Label(title, systemImage: session.tool.systemImage)
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 32)
            }
            .buttonStyle(.borderedProminent)
            .tint(session.tool == .removeTrack ? Color.red : Color.accentColor)
            .disabled(session.selection == nil)
            .accessibilityHint(hint)
        }
    }

    private var hint: String {
        session.selection == nil ? String(localized: "Select a tile on the map first.") : ""
    }

    private var title: String? {
        let costs = session.world.economy.costs
        switch session.tool {
        case .select: return nil
        case .buildTrack: return String(localized: "Build Track · \(costs.track.moneyText)")
        case .buildStation:
            return session.growsStation
                ? String(localized: "Grow Station · \(costs.station.moneyText)")
                : String(localized: "Build Station · \(costs.station.moneyText)")
        case .removeTrack: return String(localized: "Remove Track")
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
        case .buildTrack: "road.lanes"
        case .buildStation: "tram.fill"
        case .removeTrack: "trash"
        case .train: "train.side.front.car"
        }
    }

    var accessibilityName: String {
        switch self {
        case .select: String(localized: "Select tool")
        case .buildTrack: String(localized: "Build track tool")
        case .buildStation: String(localized: "Build station tool")
        case .removeTrack: String(localized: "Remove track tool")
        case .train: String(localized: "Train tool")
        }
    }
}
