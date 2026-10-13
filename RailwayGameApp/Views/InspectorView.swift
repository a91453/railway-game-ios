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
            // TestFlight 56.1: a train looked at with no tool had no way to
            // follow it; the train tool's button (`train.follow`) sat behind
            // Build since decision 114. The card's head never scrolls, so
            // the button shows with the line beside it. The train tool has
            // its own button among its options.
            let line = session.world.assignedLine(of: train)
            let followable = session.tool == .select && session.world.train(id: train)?.position != nil
            if line != nil || followable {
                HStack(spacing: 6) {
                    if let line {
                        lineButtons([line])
                    } else {
                        Spacer(minLength: 0)
                    }
                    if followable {
                        followButton(train)
                    }
                }
            }
        } else if session.tool == .select, session.selectedStationID == nil, let edge = session.selectedTrackEdge,
                  let inspection = session.trackInspection(of: edge), !inspection.lines.isEmpty {
            lineButtons(inspection.lines)
        }
    }

    /// Follows train `id` with the camera, or stops; looks and acts as the
    /// train tool's follow button (`TrainControls`).
    private func followButton(_ id: TrainID) -> some View {
        let following = session.isFollowing(id)
        let language = session.language
        return Button {
            session.toggleFollowTrain(id)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: following ? "location.fill" : "location")
                    .font(.caption2.weight(.bold))
                Text(verbatim: following ? language.text("Following", "跟隨中") : language.text("Follow", "跟隨"))
                    .font(.caption2.weight(.bold))
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(following ? Theme.primary.opacity(0.14) : Theme.chip)
            .foregroundStyle(following ? Theme.primary : Theme.textPrimary)
            .clipShape(Capsule())
            .fixedSize()
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("inspector.train.follow")
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
                    // Not two lines: a start's hint, a platform's place
                    // with its grade warning, and a real map's height and
                    // line took three or four in a phone's card, and lost
                    // their end (TestFlight 54.1).
                    .lineLimit(8)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("inspector.status")
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
            .accessibilityIdentifier("inspector.status")
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
                .accessibilityIdentifier("inspector.ridership")
                // Decision 188: the tutorial's ridership step points at it.
                .tutorialTarget(.ridership)
            }
        }
    }
}
