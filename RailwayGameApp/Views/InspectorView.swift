import GameCore
import GamePresentation
import SwiftUI

/// Shows the selected station, read from the world (Stage F1; see
/// `GameSession.selectionText()`); with the network tool (Stage C1), what
/// its taps have picked instead. On a station, a button opens its
/// ridership (Stage C2).
struct InspectorView: View {
    let session: GameSession
    @Environment(GameScreenState.self) private var screen

    var body: some View {
        inspector
            .themeCard(padding: 10, cornerRadius: 12)
    }

    @ViewBuilder
    private var inspector: some View {
        if session.tool == .network {
            networkInspector
        } else {
            VStack(alignment: .leading, spacing: 8) {
                selectionInspector
                selectionDetails
            }
        }
    }

    /// Decision 184: what a train or the track picked by the select tool
    /// adds: the train's line, load and lateness, the lines along the track,
    /// and a way to each line's details.
    @ViewBuilder
    private var selectionDetails: some View {
        if let train = session.tappedTrainID, let text = session.world.trainInspectionText(of: train, in: session.language) {
            Text(verbatim: text)
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("inspector.train.details")
            if let line = session.world.assignedLine(of: train) {
                lineButtons([line])
            }
        } else if session.tool == .select, session.selectedStationID == nil, let edge = session.selectedTrackEdge,
                  let inspection = session.world.trackInspection(of: edge), !inspection.lines.isEmpty {
            lineButtons(inspection.lines)
        }
    }

    /// A chip for each of `lines` that opens the line's details.
    private func lineButtons(_ lines: [LineID]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(lines, id: \.self) { id in
                    if let line = session.world.line(id: id) {
                        Button {
                            session.selectLine(id)
                            screen.panel = .lines
                        } label: {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Palette.lineColor(id, custom: line.color))
                                    .frame(width: 10, height: 10)
                                    .accessibilityHidden(true)
                                Text(verbatim: line.name)
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                                Image(systemName: "chevron.right")
                                    .font(.caption2.weight(.bold))
                                    .accessibilityHidden(true)
                            }
                            .padding(.horizontal, 8)
                            .frame(height: 30)
                        }
                        .buttonStyle(ThemeSelectableButtonStyle(isActive: false))
                        .accessibilityLabel(Text(verbatim: session.language.text("Open \(line.name)", "開啟 \(line.name)")))
                        .accessibilityIdentifier("inspector.line.\(id.rawValue)")
                    }
                }
            }
        }
    }

    private var networkInspector: some View {
        Group {
            HStack(alignment: .center, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Theme.primary.opacity(0.14))
                        .frame(width: 30, height: 30)
                    Image(systemName: "pencil.and.ruler.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.primary)
                }
                .accessibilityHidden(true)

                Text(session.networkDraftText())
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
        }
    }

    /// The selection's mark: track, or a station, train or building.
    private var selectionGlyph: String {
        session.selectedStationID == nil && session.tappedTrainID == nil && session.selectedBuildingID == nil
            && session.selectedTrackEdge != nil ? "point.topleft.down.to.point.bottomright.curvepath" : "tram.fill"
    }

    private var selectionInspector: some View {
        HStack(spacing: 10) {
            HStack(spacing: 10) {
                if let text = session.selectionText() {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Theme.accent)
                            .frame(width: 30, height: 30)
                        Image(systemName: selectionGlyph)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Theme.onAccent)
                    }
                    .accessibilityHidden(true)

                    Text(verbatim: text)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        // Three lines: in a phone's card "Station · Ruifang ·
                        // 2 platforms, 128 m" took two and lost its end.
                        .lineLimit(session.selectedBuildingID == nil && session.selectedTrackEdge == nil ? 3 : 7)
                        .truncationMode(.tail)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Theme.panelBorder)
                            .frame(width: 30, height: 30)
                        Image(systemName: "scope")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .accessibilityHidden(true)

                    Text(verbatim: session.language.text("Tap a station, a train or the track to see it.", "點車站、列車或軌道來查看。"))
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            if session.selectedBuildingID != nil {
                Button {
                    session.sellSelectedBuilding()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "dollarsign.circle.fill")
                            .font(.caption.weight(.bold))
                        Text("Sell")
                            .font(.caption.weight(.semibold))
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 30)
                }
                .buttonStyle(ThemeSelectableButtonStyle(isActive: false))
                .accessibilityLabel("Sell")
                .accessibilityHint("Opens the building tool's sale of this building, with the price it would bring.")
            }
            if session.selectedStation != nil {
                Button {
                    screen.panel = .station
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "person.2.fill")
                            .font(.caption.weight(.bold))
                        Text("Ridership")
                            .font(.caption.weight(.semibold))
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 30)
                }
                .buttonStyle(ThemeSelectableButtonStyle(isActive: screen.panel == .station))
                .accessibilityLabel("Ridership")
                .accessibilityHint("Shows the station's ridership: what kind of place it serves, its trips and its passengers.")
            }
        }
    }
}
