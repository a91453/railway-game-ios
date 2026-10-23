import GameCore
import GamePresentation
import SwiftUI

/// What is being built where the player is looking (ARCHITECTURE decision
/// 107): a flag at each end of the track previewed, and beside its end, or
/// beside the building shown, a pill to cancel it or build it, with what
/// it costs. Beside a place picked for a platform (decision 108) the pill
/// says who lives and works within a station's walk, and a ring shows how
/// far that is. The finger that drew it is already there, so the player need
/// not look away to the details card, whose button does the same.
/// SimCity BuildIt puts ✗ and ✓ beside what is placed, and Train Valley 2
/// and OpenTTD's touch build ask once, at the end of a drag; the code is
/// the project's own.
struct MapBuildConfirm: View {
    let session: GameSession
    let camera: PlanCamera
    let viewport: ScreenSize
    /// What floats over the map's edges (``EnvironmentValues/mapInsets``).
    let insets: EdgeInsets
    /// The top of the map's clear area without the banner and other cards
    /// under the top controls: where the pill may go when there is no room
    /// under them.
    let mapTop: CGFloat
    /// The map's own buttons and keys near its edges (the layer and map
    /// buttons, the legend and the zoom buttons), in the map's
    /// coordinates: the pill keeps off them, which it went over on a phone
    /// held sideways (a player's report); and the new line's station pair
    /// drawer, which covered its ✓ (decision 384).
    var avoiding: [CGRect] = []
    @Environment(GameScreenState.self) private var screen
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var pillSize = CGSize(width: 160, height: 44)

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Decision 100, later: the new line picked on the map, under
            // its ✓.
            if let draft = session.mapLineDraft {
                MapLineDraftPath(draft: draft, camera: camera)
            }
            if let build = confirmation {
                if build.showsCatchment {
                    catchmentRing(at: camera.screenPoint(of: build.anchor))
                }
                if let start = build.start {
                    flag("flag.fill", at: camera.screenPoint(of: start), tint: Theme.primary)
                }
                if let end = build.flaggedEnd {
                    flag("flag.checkered", at: camera.screenPoint(of: end), tint: Theme.primary)
                }
                pill(build)
                    .onGeometryChange(for: CGSize.self) { $0.size } action: { pillSize = $0 }
                    .offset(placement(below: camera.screenPoint(of: build.anchor), clearance: build.clearance))
                    .transition(.pop(reduceMotion: reduceMotion))
            }
        }
        .frame(width: viewport.width, height: viewport.height, alignment: .topLeading)
        // Decision 253: a small thing popping up where the finger is.
        .animation(MotionRule.pop.layout(reduceMotion: reduceMotion), value: confirmation != nil)
    }

    private var confirmation: BuildConfirmation? {
        let screen = screen
        let openLines: @MainActor () -> Void = { screen.panel = GameScreenState.Panel.lines }
        return BuildConfirmation(session, linesPanelOpen: screen.panel == .lines, openLines: openLines)
    }

    /// Whether the pill is on the map, with `panel` open: the map's cell
    /// tooltips give way to it.
    static func isShown(_ session: GameSession, panel: GameScreenState.Panel?) -> Bool {
        BuildConfirmation(session, linesPanelOpen: panel == .lines, openLines: {}) != nil
    }

    private func flag(_ systemImage: String, at point: ScreenPoint, tint: Color) -> some View {
        Image(systemName: systemImage)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(tint)
            .frame(width: 28, height: 28)
            .background(Theme.panel, in: Circle())
            .overlay(Circle().strokeBorder(Theme.panelBorder, lineWidth: 1))
            // The flag stands above its point, so the point stays in sight.
            .offset(x: point.x - 14, y: point.y - 36)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// A station's walk around the platform site (decision 108): 800 m,
    /// ``Land/catchmentRadius``, at the map's scale.
    private func catchmentRing(at point: ScreenPoint) -> some View {
        let radius = Double(Land.catchmentRadius) * camera.pointsPerUnit
        return Circle()
            .fill(Theme.primary.opacity(0.10))
            .overlay(Circle().strokeBorder(Theme.primary.opacity(0.7), style: StrokeStyle(lineWidth: 2, dash: [6, 4])))
            .frame(width: radius * 2, height: radius * 2)
            .offset(x: point.x - radius, y: point.y - radius)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func pill(_ build: BuildConfirmation) -> some View {
        let maxWidth = BuildConfirmLayout.maximumWidth(
            viewportWidth: viewport.width, leading: Double(insets.leading), trailing: Double(insets.trailing)
        )
        return WidthLimit(maxWidth: maxWidth) {
            HStack(spacing: CGFloat(StationPairDrawerLayout.pillSpacing)) {
                pairDrawer(pillWidth: maxWidth)
                words(build)
            }
            .padding(CGFloat(StationPairDrawerLayout.pillPadding))
            .glassBackground(in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        }
    }

    /// Decision 384: on a phone on its side the new line's last two
    /// stations, compared, ride in the pill beside its words (not in the
    /// tutorial, whose card leads), so the drawer and the ✓ move together
    /// and neither covers the other, open or folded.
    @ViewBuilder private func pairDrawer(pillWidth: Double) -> some View {
        let draft = session.lineDraft
        if StationPairDrawerLayout.ridesInPill(compactHeight: verticalSizeClass == .compact),
           session.tutorial == nil, session.mapLineDraft != nil, draft.count >= 2,
           let maxHeight = StationPairDrawerLayout.maximumHeightInPill(available: clearHeight, pillWidth: pillWidth) {
            StationPairDrawer(
                session: session, from: draft[draft.count - 2], to: draft[draft.count - 1],
                startsFolded: true, maxHeight: CGFloat(maxHeight)
            )
            .frame(width: CGFloat(StationPairDrawerLayout.widthInPill))
        }
    }

    /// The height the pill may stand in, between the controls along the
    /// map's top and bottom edges.
    private var clearHeight: Double {
        viewport.height - Double(insets.top) - Double(insets.bottom) - 2 * BuildConfirmLayout.margin
    }

    /// What the pill says and its buttons.
    private func words(_ build: BuildConfirmation) -> some View {
        VStack(spacing: 4) {
            if let caption = build.caption {
                // A long refusal wraps within the map's clear band rather
                // than running under the card beside it (TestFlight 67.1).
                Text(verbatim: caption)
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8)
                    .accessibilityIdentifier("map.build.catchment")
            }
            buttons(build)
                .fixedSize()
        }
    }

    private func buttons(_ build: BuildConfirmation) -> some View {
        HStack(spacing: 6) {
            // Decision 100, later: the new line's last stop taken back
            // (the reference's `undoLastStation`).
            if let undo = build.undo {
                Button {
                    undo()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.body.weight(.bold))
                        .frame(width: 44, height: 40)
                }
                .buttonStyle(ThemeSelectableButtonStyle(isActive: false))
                .accessibilityLabel(Text(verbatim: session.language.text("Take Back the Last Stop", "取消上一站")))
                .accessibilityIdentifier("map.build.undo")
            }
            // Decision 336: the land is not bought yet; this ends building
            // and starts choosing a tile, as the map's own button (hidden
            // while building, TestFlight 56.1) does.
            if build.expandsMap {
                Button {
                    session.startChoosingMapTile()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.square.dashed")
                            .font(.body.weight(.bold))
                        Text(verbatim: session.language.text("Expand Map", "擴建地圖"))
                            .font(.subheadline.weight(.bold))
                    }
                    .padding(.horizontal, 6)
                    .frame(minHeight: 40)
                }
                .buttonStyle(ThemeSelectableButtonStyle(isActive: false))
                .accessibilityIdentifier("map.build.expandMap")
            }
            Button {
                build.cancel()
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.bold))
                    .frame(width: 44, height: 40)
            }
            .buttonStyle(ThemeSelectableButtonStyle(isActive: false))
            .accessibilityLabel(Text(verbatim: session.language.text("Cancel", "取消")))
            .accessibilityIdentifier("map.build.cancel")
            Button {
                build.confirm()
            } label: {
                HStack(spacing: 6) {
                    // A tile of the map says what it buys, in another
                    // colour, so it is not taken for a build's ✓
                    // (TestFlight 56.1).
                    Image(systemName: build.kind == .mapTile ? "cart.fill" : "checkmark")
                        .font(.body.weight(.bold))
                    if build.kind == .mapTile {
                        Text(verbatim: session.language.text("Buy tile", "購買地塊"))
                            .font(.subheadline.weight(.bold))
                    }
                    if let cost = build.cost {
                        Text(verbatim: cost.moneyText)
                            .font(.subheadline.weight(.bold))
                            .monospacedDigit()
                    }
                }
                .frame(minHeight: 40)
            }
            .buttonStyle(ThemeProminentButtonStyle(isPurchase: build.kind == .mapTile))
            .disabled(!build.canConfirm)
            // Not "Build Track …": the details card's button has that name,
            // and the tutorial's UI test finds it, alone, by it
            // (``BuildConfirmation/confirmName(in:)``).
            .accessibilityLabel(Text(verbatim: build.confirmName(in: session.language)))
            .accessibilityIdentifier(build.kind == .mapTile ? "map.expansion.buy" : "map.build.confirm")
            // Decision 188: the tutorial's build steps point at it.
            .tutorialTarget(.mapConfirm)
        }
    }

    /// Where the pill goes: under `point`, past what is shown there by
    /// `clearance`, or over it when there is no room below; kept clear of
    /// the controls along the map's edges.
    private func placement(below point: ScreenPoint, clearance: Double) -> CGSize {
        let margin = BuildConfirmLayout.margin
        let width = Double(pillSize.width), height = Double(pillSize.height)
        let minX = Double(insets.leading) + margin
        let maxX = viewport.width - Double(insets.trailing) - width - margin
        let x = BuildConfirmLayout.originX(
            anchorX: point.x, width: width, viewportWidth: viewport.width,
            leading: Double(insets.leading), trailing: Double(insets.trailing)
        )
        let top = Double(insets.top) + margin
        let bottom = viewport.height - Double(insets.bottom) - margin
        var y = point.y + clearance
        if y + height > bottom {
            y = point.y - clearance - height
        }
        // Under a tall banner there may be no room between it and the
        // dock: the buttons then go over the banner's foot, whole and
        // tappable, rather than under the dock (decision 190's report).
        let highest = top <= bottom - height ? top : max(0, min(Double(mapTop) + margin, bottom - height))
        y = min(max(y, highest), max(highest, bottom - height))
        let placed = BuildConfirmLayout.keepingOff(
            avoiding.map { ScreenFrame($0) }, x: x, y: y, width: width, height: height, minX: minX, maxX: maxX, highest: highest
        )
        return CGSize(width: placed.x, height: placed.y)
    }
}

/// Its content at its own size, given no more than `maxWidth` across:
/// words wrap there, and the pill measures no wider than they need (a
/// frame's `maxWidth` would stretch to it).
private struct WidthLimit: Layout {
    let maxWidth: Double

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        subviews.first?.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil)) ?? .zero
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(width: bounds.width, height: bounds.height))
    }
}

/// The build the pill confirms: the stretch of track previewed, or the
/// building shown.
@MainActor
private struct BuildConfirmation {
    let start: PlanPoint?
    let flaggedEnd: PlanPoint?
    /// Where the pill goes under.
    let anchor: PlanPoint
    /// How far under it, in points: past the building shown.
    let clearance: Double
    let cost: Money?
    let canConfirm: Bool
    let kind: Kind
    /// A line over the buttons: who lives and works around a platform site
    /// (decision 108).
    let caption: String?
    let showsCatchment: Bool
    let cancel: @MainActor () -> Void
    let confirm: @MainActor () -> Void
    /// Takes back the new line's last stop (decision 100, later).
    var undo: (@MainActor () -> Void)?
    /// Decision 336: what is drawn lies on land not bought yet, and the
    /// pill offers to go and expand the map.
    var expandsMap = false

    enum Kind {
        case track, platform, building, sale, mapTile, line, addStop
    }

    /// `linesPanelOpen`: whether the lines panel is open, where a station
    /// tapped can join the line it shows; `openLines` opens it, once a
    /// new line is made, for its trains.
    init?(_ session: GameSession, linesPanelOpen: Bool, openLines: @escaping @MainActor () -> Void) {
        // Decision 100, later: a new line, picked on the map, is made
        // there, beside its last station; a stretch of track being drawn
        // keeps its own ✓. It is the map's ✓ only where a tap on the map
        // picks the line's stations (MapView's tap): beside the lines
        // panel, or with Select while no tile is being chosen; else the
        // ✓ of the tool or the tile comes first.
        if session.networkPreview == nil,
           linesPanelOpen || (session.tool == .select && !session.isChoosingMapTile),
           let draft = session.mapLineDraft {
            start = nil
            flaggedEnd = nil
            anchor = draft.anchor
            clearance = 22
            cost = nil
            canConfirm = draft.canCreate
            kind = .line
            caption = draft.caption
            showsCatchment = false
            cancel = { session.clearLineDraft() }
            confirm = {
                // Decision 303: the card first, where the game runs the
                // line's trains; its Open Line opens the lines panel.
                session.confirmLineDraft()
                if session.mapLineDraft == nil, session.lineConfirmation == nil { openLines() }
            }
            if session.lineDraft.count >= 2 {
                undo = { session.removeLastLineDraftStop() }
            }
            return
        }
        // Decision 196, later: a station tapped beside the lines panel
        // joins the line it shows, where it fits.
        if linesPanelOpen, session.tool == .select, let suggestion = session.mapStopSuggestion {
            start = nil
            flaggedEnd = nil
            anchor = suggestion.anchor
            clearance = 22
            cost = nil
            canConfirm = true
            kind = .addStop
            caption = suggestion.caption
            showsCatchment = false
            cancel = { session.clearSelection() }
            confirm = { session.addStationToSelectedLine(suggestion.station) }
            return
        }
        // Decision 160: the tile of the map chosen to buy, at its middle.
        if session.isChoosingMapTile {
            guard let quote = session.chosenMapTileQuote else { return nil }
            let area = session.world.mapArea(of: quote.tile)
            start = nil
            flaggedEnd = nil
            anchor = PlanPoint(x: (area.minX + area.maxX) / 2, y: (area.minY + area.maxY) / 2)
            clearance = 18
            cost = quote.price
            canConfirm = quote.isUnlocked && session.world.economy.canAfford(quote.price)
            kind = .mapTile
            caption = session.chosenMapTileCaption
            showsCatchment = false
            cancel = { session.clearChosenMapTile() }
            confirm = { _ = session.buyChosenMapTile() }
            return
        }
        // Decision 247: the track card's upgrade, where the track was
        // tapped, with its whole price.
        if session.tool == .select, let preview = session.trackUpgradePreview, let point = session.selectedPoint {
            start = nil
            flaggedEnd = nil
            anchor = point
            clearance = 18
            cost = preview.cost
            canConfirm = preview.problem == nil && preview.cost != nil
            kind = .track
            caption = preview.problem ?? preview.note
            showsCatchment = false
            cancel = { session.cancelTrackUpgrade() }
            confirm = { session.buildTrackUpgrade() }
            return
        }
        switch session.tool {
        case .network where session.networkMode == .platform:
            // Decision 108: the place picked for a platform, and who lives
            // and works around it.
            guard let site = session.platformSitePlanPoint, let catchment = session.platformSiteCatchment else { return nil }
            start = nil
            flaggedEnd = nil
            anchor = site
            clearance = 18
            // Decision 190: a grade is levelled first, for what relaying
            // the track costs; where it cannot be, ✓ says why when tapped.
            // A new station's price is in it too.
            let levelling = session.networkPlatformLevelling
            cost = session.networkPlatformCost
            canConfirm = true
            kind = .platform
            caption = [session.platformSiteCaption(catchment, at: site), levelling?.caption(in: session.language)]
                .compactMap(\.self).joined(separator: "\n")
            showsCatchment = true
            cancel = { session.clearNetworkDraft() }
            confirm = { session.addNetworkPlatform() }
        case .network:
            guard session.networkMode == .build, let preview = session.networkPreview,
                  let end = session.networkEndPlanPoint else { return nil }
            start = session.networkStartPlanPoint
            flaggedEnd = end
            anchor = end
            clearance = 18
            cost = preview.cost
            canConfirm = preview.problem == nil && preview.cost != nil
            kind = .track
            caption = preview.crossoverNote
            showsCatchment = false
            cancel = { session.clearNetworkDraft() }
            confirm = { session.buildNetworkTrack() }
            expandsMap = session.offersMapExpansion(for: preview.problem)
        case .building where session.buildingMode == .sell:
            // Decision 130: the building chosen to sell, and what it brings.
            guard let sale = session.salePreview else { return nil }
            start = nil
            flaggedEnd = nil
            anchor = sale.building.centre
            clearance = 44
            cost = sale.quote.price > .zero ? sale.quote.price : nil
            canConfirm = true
            kind = .sale
            caption = session.saleGainText
            showsCatchment = false
            cancel = { session.clearSaleCandidate() }
            confirm = { _ = session.confirmSale() }
        case .building:
            guard let preview = session.buildingPreview else { return nil }
            start = nil
            flaggedEnd = nil
            anchor = preview.centre
            clearance = 44
            cost = preview.cost
            canConfirm = preview.problem == nil
            kind = .building
            caption = nil
            showsCatchment = false
            cancel = { session.clearBuildingSite() }
            confirm = { _ = session.confirmBuilding() }
            expandsMap = session.offersMapExpansion(for: preview.problem)
        case .select, .train:
            return nil
        }
    }

    func confirmName(in language: DisplayLanguage) -> String {
        // Not "Build Track …" nor "Add Platform": the details card's
        // buttons have those names.
        let what = switch kind {
        case .track: language.text("Build this stretch", "建造這一段")
        case .platform: language.text("Put a platform here", "在這裡加月台")
        case .building: language.text("Build here", "蓋在這裡")
        case .sale: language.text("Sell to the city", "賣給城市")
        case .mapTile: language.text("Buy tile", "購買地塊")
        case .line: language.text("Create this line", "建立這條路線")
        case .addStop: language.text("Add to the line", "加入路線")
        }
        guard let cost else { return what }
        return "\(what), \(cost.moneyText)"
    }
}

/// The new line picked on the map (decision 100, later): a line through
/// the stations it will call at, in the theme's teal with the icon's navy
/// edge (the art style), and the stations tapped numbered in the order they
/// were. The reference draws its line being placed as a 5-point line in the
/// line's colour (`Ci/`'s `metro-preview-layer`); the numbers are this
/// project's own.
private struct MapLineDraftPath: View {
    let draft: MapLineDraft
    let camera: PlanCamera

    var body: some View {
        ZStack(alignment: .topLeading) {
            path.stroke(Theme.textPrimary, style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
            path.stroke(Theme.primary, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            ForEach(draft.picked.indices, id: \.self) { index in
                badge(index + 1, at: camera.screenPoint(of: draft.picked[index]))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The line through the stations it will call at, on the screen.
    private var path: Path {
        var path = Path()
        let points: [CGPoint] = draft.calls.map { point in
            let screen = camera.screenPoint(of: point)
            return CGPoint(x: screen.x, y: screen.y)
        }
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        return path
    }

    /// The order a station was tapped in, over it.
    private func badge(_ number: Int, at point: ScreenPoint) -> some View {
        Text(verbatim: String(number))
            .font(.caption.weight(.bold))
            .monospacedDigit()
            .foregroundStyle(Theme.textPrimary)
            .frame(width: 24, height: 24)
            .background(Theme.panel, in: Circle())
            .overlay(Circle().strokeBorder(Theme.textPrimary, lineWidth: 2))
            .offset(x: point.x - 12, y: point.y - 12)
    }
}
