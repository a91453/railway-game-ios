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
            // Decision 223: a train on a trip shows it as a flight card;
            // one without a trip keeps the line of text.
            if let card = session.world.trainCard(of: train, in: session.language) {
                TrainCardView(card: card, language: session.language)
            } else {
                Text(verbatim: text)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("inspector.train.details")
            }
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
        let codes = LineBadge.codes(for: session.world.lines)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(lines, id: \.self) { id in
                    if let line = session.world.line(id: id) {
                        Button {
                            session.selectLine(id)
                            screen.panel = .lines
                        } label: {
                            HStack(spacing: 4) {
                                // Decision 216: the line's badge.
                                LineCodeBadge(code: codes[id] ?? "", color: Palette.lineColor(id, custom: line.color), size: .small)
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

/// The train card's trip (ARCHITECTURE decision 223, option A "航班條",
/// `docs/art/airline-ui-borrow-2026-10-14/`): first and last stops large
/// at either end with their times, the timetable's arrival struck through
/// beside the expected one when late; a bar with the train on it and the
/// distance left; when it left and when it gets in; and its speed, next
/// stop and load. ``TrainCard`` works it out from the world.
struct TrainCardView: View {
    let card: TrainCard
    let language: DisplayLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(verbatim: language.text("This trip", "本趟"))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                Spacer(minLength: 4)
                TrainStatusCapsule(card: card, language: language)
            }
            HStack(alignment: .bottom, spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: card.origin)
                        .font(.title3.weight(.heavy))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    HStack(spacing: 3) {
                        Text(verbatim: card.departure.clockText).fontWeight(.bold)
                        Text(verbatim: language.text("dep", "發"))
                    }
                    .font(.caption2.monospacedDigit())
                }
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 1) {
                    Text(verbatim: card.terminus)
                        .font(.title3.weight(.heavy))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    HStack(spacing: 3) {
                        LateTimeText(scheduled: card.arrival.clockText, expected: card.isLate ? card.expectedArrival.clockText : nil)
                        Text(verbatim: language.text("arr", "到"))
                    }
                    .font(.caption2.monospacedDigit())
                }
            }
            .foregroundStyle(Theme.textPrimary)
            TrainTripProgressBar(progress: card.progress)
            Text(verbatim: card.remainingText(in: language))
                .font(.caption2.weight(.bold).monospacedDigit())
                .foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: .infinity)
            HStack {
                Text(verbatim: card.departureText(in: language))
                    .foregroundStyle(Theme.textSecondary)
                Spacer(minLength: 4)
                Text(verbatim: card.arrivalText(in: language))
                    .fontWeight(.semibold)
                    .foregroundStyle(card.isLate ? Theme.warning : Theme.textPrimary)
            }
            .font(.caption2.monospacedDigit())
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            HStack(spacing: 6) {
                stat(language.text("Speed", "時速"), "\(card.speed) km/h")
                stat(language.text("Next stop", "下一站"), card.nextStopText(in: language))
                if let load = card.load {
                    stat(load.titleText(in: language), "\(load.percentage)%", fill: Double(min(load.percentage, 100)) / 100)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("inspector.train.card")
    }

    /// One of the three figures: its name small, its value bold, on a chip;
    /// with `fill`, a load bar under it.
    private func stat(_ title: String, _ value: String, fill: Double? = nil) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(verbatim: title)
                .font(.system(size: 10))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
            Text(verbatim: value)
                .font(.footnote.weight(.bold).monospacedDigit())
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let fill {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.chip)
                        Capsule().fill(Palette.ink).frame(width: proxy.size.width * fill)
                    }
                }
                .frame(height: 4)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.chip, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// A trip's bar (decision 223): a `chip` groove filled in `primary` up to
/// how far the train has gone, with the map's train (``MapGlyph/train``)
/// on a warm station disc at its head.
struct TrainTripProgressBar: View {
    let progress: Double
    var height: CGFloat = 8
    var marker: CGFloat = 22

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let head = width * min(1, max(0, progress))
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.chip).frame(height: height)
                Capsule().fill(Theme.primary).frame(width: max(height, head), height: height)
                MapGlyph.train.image
                    .resizable()
                    .scaledToFit()
                    .frame(width: marker * 0.68, height: marker * 0.68)
                    .foregroundStyle(Palette.stationSymbol)
                    .frame(width: marker, height: marker)
                    .background(Palette.station, in: Circle())
                    .overlay(Circle().strokeBorder(Palette.ink, lineWidth: 1.5))
                    .offset(x: min(max(0, head - marker / 2), max(0, width - marker)))
            }
            .frame(height: marker)
        }
        .frame(height: marker)
        .accessibilityHidden(true)
    }
}

/// A time that may have moved (decision 223): on time, the time alone;
/// late, the timetable's struck through in `textSecondary` and the
/// expected one bold in `warning`.
struct LateTimeText: View {
    let scheduled: String
    let expected: String?

    var body: some View {
        if let expected {
            HStack(spacing: 3) {
                Text(verbatim: scheduled)
                    .strikethrough(true, color: Theme.textSecondary)
                    .foregroundStyle(Theme.textSecondary)
                Text(verbatim: expected)
                    .fontWeight(.bold)
                    .foregroundStyle(Theme.warning)
            }
        } else {
            Text(verbatim: scheduled).fontWeight(.bold)
        }
    }
}

/// The status capsule of the train card, the follow bar and the station's
/// board (decision 223): an icon and words on a solid colour, so a late
/// train never shows by colour alone (`success` and `warning` are nearly
/// the same grey, `docs/UI_THEME.md`).
struct TrainStatusCapsule: View {
    enum Kind {
        case onTime, late, lateBehind, boarding, neutral
    }

    let text: String
    let kind: Kind
    /// The icon alone, where the words do not fit (the station's board on
    /// a narrow card); VoiceOver still reads the words.
    var symbolOnly = false

    init(text: String, kind: Kind) {
        self.text = text
        self.kind = kind
    }

    init(card: TrainCard, language: DisplayLanguage) {
        self.text = card.statusText(in: language)
        self.kind = card.showsPunctuality ? (card.isLate ? .late : .onTime) : .neutral
    }

    init(row: DepartureBoard.Row, language: DisplayLanguage, symbolOnly: Bool = false) {
        self.text = row.status.text(in: language)
        self.symbolOnly = symbolOnly
        switch row.status {
        case .boarding: self.kind = .boarding
        case .passes: self.kind = .neutral
        case .onTime: self.kind = .onTime
        case .late: self.kind = .late
        case .lateBehind: self.kind = .lateBehind
        }
    }

    var body: some View {
        if symbolOnly {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 3)
                    .background(fill, in: Capsule())
                    .foregroundStyle(foreground)
                    .fixedSize()
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(verbatim: text))
            }
        } else {
            HStack(spacing: 3) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 9, weight: .bold))
                        .accessibilityHidden(true)
                }
                Text(verbatim: text)
                    .font(.caption2.weight(.bold))
                    .lineLimit(1)
            }
            .padding(.leading, symbol == nil ? 7 : 5)
            .padding(.trailing, 7)
            .padding(.vertical, 2)
            .background(fill, in: Capsule())
            .foregroundStyle(foreground)
            .fixedSize()
        }
    }

    private var symbol: String? {
        switch kind {
        case .onTime: "checkmark"
        case .late: "clock"
        case .lateBehind: "arrow.down.to.line"
        case .boarding, .neutral: nil
        }
    }

    private var fill: Color {
        switch kind {
        case .onTime: Theme.success
        case .late, .lateBehind: Theme.warning
        case .boarding: Theme.primary
        case .neutral: Theme.chip
        }
    }

    private var foreground: Color {
        kind == .neutral ? Theme.textSecondary : Theme.onPrimary
    }
}
