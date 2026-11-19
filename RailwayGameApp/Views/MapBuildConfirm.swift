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
/// OpenTTD's touch build asks once, at the end of a drag; the code is
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
    /// How wide ✕ ✓ are, measured: whether the words fit beside them
    /// (``BuildConfirmLayout/arrangement(compactHeight:hasWords:ridesWithDrawer:hasFixes:roomBeside:)``).
    @State private var buttonsWidth: CGFloat?

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
                // Decision 803: not under the finger that draws the
                // stretch, which hid it and the stretch's end; it pops up
                // when the finger lets go. The flags stay.
                if BuildConfirmLayout.pillShows(fingerDraws: build.fingerDraws) {
                    pill(build)
                        .onGeometryChange(for: CGSize.self) { $0.size } action: { pillSize = $0 }
                        // The tutorial's folded card keeps clear of it all,
                        // not only its ✓ (Mac playtest 2026-11-08, A2).
                        .tutorialTarget(.mapConfirmCard)
                        .offset(placement(below: camera.screenPoint(of: build.anchor), clearance: build.clearance,
                                           keepingOff: siteObstacles(build)))
                        .transition(.pop(reduceMotion: reduceMotion))
                }
            }
        }
        .frame(width: viewport.width, height: viewport.height, alignment: .topLeading)
        // Decision 253: a small thing popping up where the finger is.
        .animation(MotionRule.pop.layout(reduceMotion: reduceMotion), value: confirmation != nil)
        .animation(MotionRule.pop.layout(reduceMotion: reduceMotion), value: session.buildFingerDraws)
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

    /// Whether the pill says why the stretch drawn is refused, beside the
    /// ✓ it greys (decision 800): the construction HUD then leaves it out.
    static func saysProblem(_ session: GameSession, panel: GameScreenState.Panel?) -> Bool {
        BuildConfirmation(session, linesPanelOpen: panel == .lines, openLines: {})?.problem != nil
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
            .glassBackground(cornerRadius: 26)
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

    /// What the pill says and its buttons. Decision 800: a stretch's
    /// words stand beside its ✕ ✓ on a short screen (a phone held
    /// sideways), where under one another they left the pill no room
    /// but over the construction HUD and the stretch. Decision 803: every
    /// build's words do (a platform's place, a building, a road, a bus or
    /// ferry route), but the new line's, whose drawer is beside them.
    /// Continued: a refusal with fixes there has why across the top and
    /// one row of the fixes and ✕ ✓ under it.
    @ViewBuilder
    private func words(_ build: BuildConfirmation) -> some View {
        let pillWidth = BuildConfirmLayout.maximumWidth(
            viewportWidth: viewport.width, leading: Double(insets.leading), trailing: Double(insets.trailing)
        )
        let arrangement = BuildConfirmLayout.arrangement(
            compactHeight: verticalSizeClass == .compact, hasWords: build.hasWords, ridesWithDrawer: build.kind == .line,
            hasFixes: build.heights?.fixes.isEmpty == false,
            roomBeside: buttonsWidth.map { BuildConfirmLayout.wordsRoomBeside(pillWidth: pillWidth, buttonsWidth: Double($0)) }
        )
        let height = CGFloat(BuildConfirmLayout.buttonHeight(arrangement))
        switch arrangement {
        case .beside:
            HStack(spacing: CGFloat(BuildConfirmLayout.besideSpacing)) {
                PillColumn {
                    said(build, arrangement: arrangement)
                }
                buttons(build, height: height)
                    .fixedSize()
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { buttonsWidth = $0 }
            }
        case .strip:
            PillColumn {
                said(build, arrangement: arrangement)
                HStack(spacing: 6) {
                    if let heights = build.heights {
                        EqualCells { fixButtons(heights.fixes, height: height) }
                    }
                    buttons(build, height: height)
                        .fixedSize()
                }
            }
        case .stacked:
            PillColumn {
                if build.hasWords {
                    said(build, arrangement: arrangement)
                }
                if let heights = build.heights, !heights.fixes.isEmpty {
                    EqualCells { fixButtons(heights.fixes, height: height) }
                }
                // Decision 646: the height is slid on the construction
                // HUD's cell; the pill keeps only ✕ ✓ and a refusal's
                // fixes.
                buttons(build, height: height)
                    .fixedSize()
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { buttonsWidth = $0 }
            }
        }
    }

    /// The pill's words: a caption, why the stretch is refused, and what
    /// to do where no fix is offered (decision 629). Each wraps within
    /// the column (``PillColumn``).
    @ViewBuilder
    private func said(_ build: BuildConfirmation, arrangement: BuildConfirmLayout.Arrangement) -> some View {
        if let caption = build.caption {
            // Beside the buttons it wraps no wider than a refusal does,
            // so the pill stays off the map's middle.
            captionLine(caption, beside: arrangement == .beside)
                .layoutValue(key: WordsCap.self, value: arrangement == .beside ? BuildConfirmLayout.wordsWidth : Double.infinity)
        }
        if let problem = build.problem {
            problemLine(problem, spoken: build.spokenProblem ?? problem, slim: arrangement == .strip)
                .layoutValue(key: WordsCap.self, value: BuildConfirmLayout.wordsWidth)
        }
        if let heights = build.heights, let note = heights.note {
            Text(verbatim: heights.noteBrief ?? note)
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8)
                .accessibilityLabel(Text(verbatim: note))
                .accessibilityIdentifier("map.build.heightNote")
                .layoutValue(key: WordsCap.self, value: BuildConfirmLayout.wordsWidth)
        }
    }

    /// A long refusal wraps within the map's clear band rather than
    /// running under the card beside it (TestFlight 67.1).
    private func captionLine(_ caption: String, beside: Bool) -> some View {
        Text(verbatim: caption)
            .font(.caption.weight(.semibold))
            .monospacedDigit()
            .multilineTextAlignment(beside ? .leading : .center)
            .foregroundStyle(Theme.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 8)
            .accessibilityIdentifier("map.build.catchment")
    }

    /// Decision 800: why the stretch is refused, beside the ✓ it greys;
    /// the construction HUD said it, where the pill then stood over it
    /// (the owner's report from 0.6.0 (134), a phone held sideways).
    /// Decision 803, continued: one short line, as wide as the pill
    /// (#2302's screenshots: narrower than it, at its leading side);
    /// VoiceOver reads the whole sentence (`spoken`). It still wraps at
    /// any text size.
    private func problemLine(_ problem: String, spoken: String, slim: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption.weight(.bold))
            Text(verbatim: problem)
                .font(.caption.weight(.medium))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Theme.warning)
        .padding(.horizontal, 10)
        .padding(.vertical, slim ? 3 : 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: session.language.text("Problem: \(spoken)", "問題：\(spoken)")))
        .accessibilityIdentifier("map.build.problem")
    }

    /// At most one fix up and one down (decision 629), each a cell of
    /// ``EqualCells``; written out rather than with a `ForEach`
    /// (CRASH101's row closure).
    @ViewBuilder
    private func fixButtons(_ fixes: [NetworkHeightFix], height: CGFloat) -> some View {
        if let up = fixes.first(where: { $0.change > 0 }) { fixButton(up, height: height) }
        if let down = fixes.first(where: { $0.change < 0 }) { fixButton(down, height: height) }
    }

    /// Decision 803, continued: its arrow, what it does in a word or two
    /// and its price. Which end moves and how far are on the flags and
    /// the height cell once it is applied; VoiceOver reads them here.
    private func fixButton(_ fix: NetworkHeightFix, height: CGFloat) -> some View {
        let language = session.language
        return Button {
            session.applyNetworkHeightFix(fix)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: fix.change > 0 ? "arrow.up.to.line" : "arrow.down.to.line")
                    .font(.body.weight(.bold))
                Text(verbatim: fix.buttonTitle(in: language))
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)
                // Decision 800: no "NT$ 0" where it costs nothing.
                if let price = BuildConfirmLayout.priceText(of: fix.cost, in: language) {
                    Text(verbatim: price)
                        .font(.subheadline)
                        .monospacedDigit()
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 8)
            // The selectable style's 4 above and below make up `height`.
            .frame(maxWidth: .infinity, minHeight: height - 8)
        }
        .buttonStyle(ThemeSelectableButtonStyle(isActive: false))
        .accessibilityLabel(Text(verbatim: [fix.title(in: language), BuildConfirmLayout.priceText(of: fix.cost, in: language)]
                .compactMap(\.self).joined(separator: " ")))
        .accessibilityIdentifier(fix.change > 0 ? "map.build.fixUp" : "map.build.fixDown")
    }

    private func buttons(_ build: BuildConfirmation, height: CGFloat) -> some View {
        HStack(spacing: 6) {
            // Decision 100, later: the new line's last stop taken back
            // (the reference's `undoLastStation`).
            if let undo = build.undo {
                Button {
                    undo()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.body.weight(.bold))
                        .frame(width: 44, height: height - 8)
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
                    .frame(minHeight: height - 8)
                }
                .buttonStyle(ThemeSelectableButtonStyle(isActive: false))
                .accessibilityIdentifier("map.build.expandMap")
            }
            if build.buysLine {
                Button {
                    session.offerTracedSaleLine()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "signature")
                            .font(.body.weight(.bold))
                        Text(verbatim: TracedSaleHint.buttonTitle(in: session.language))
                            .font(.subheadline.weight(.bold))
                    }
                    .padding(.horizontal, 6)
                    .frame(minHeight: height - 8)
                }
                .buttonStyle(ThemeSelectableButtonStyle(isActive: false))
                .accessibilityIdentifier("map.build.buyLine")
            }
            Button {
                build.cancel()
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.bold))
                    .frame(width: 44, height: height - 8)
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
                    if let price = BuildConfirmLayout.priceText(of: build.cost, in: session.language) {
                        // Decision 523, continued: in 萬 or 億 in Chinese.
                        Text(verbatim: price)
                            .font(.subheadline.weight(.bold))
                            .monospacedDigit()
                    }
                }
                // As tall as ✕ beside it (the selectable style adds 4
                // above and below), and never narrower: the main action is
                // not the smallest.
                .frame(minWidth: 44, minHeight: height)
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
    /// Decision 744: while a station's place is chosen, the place and the
    /// track around it, which the pill keeps off so the line stays in
    /// sight (a player's report, 2026-11-14).
    /// Decision 800: while a stretch of track is drawn, the stretch and
    /// the flags at its ends, which the pill stood over where the dock
    /// held it up (the owner's report from 0.6.0 (134)).
    private func siteObstacles(_ build: BuildConfirmation) -> [ScreenFrame] {
        guard camera.pointsPerUnit > 0 else { return [] }
        let anchor = camera.screenPoint(of: build.anchor)
        let reach = Double(max(pillSize.width, pillSize.height)) + 2 * BuildConfirmLayout.margin
        if build.kind == .track, !build.stretch.isEmpty {
            // Twice as far: moved off the end, the pill may reach that
            // much more of the stretch.
            return BuildConfirmLayout.stretchObstacles(
                build.stretch.map { camera.screenPoint(of: $0) },
                flags: [build.start, build.flaggedEnd].compactMap(\.self).map { camera.screenPoint(of: $0) },
                around: anchor, reach: 2 * reach
            )
        }
        // The new line's last station (and the one a stop joins), which
        // the pill is anchored beside: on a phone held sideways with a
        // message over the map there may be no room above or below it,
        // and the pill stood over the station and the next one along, so
        // a touch meant for the next station pressed ✕ (iOS 27.2, pull
        // request #2453).
        if build.kind == .line || build.kind == .addStop {
            return BuildConfirmLayout.siteObstacles([], around: anchor, reach: reach)
        }
        guard build.kind == .platform else { return [] }
        let lines = session.trackLines(near: build.anchor, within: reach / camera.pointsPerUnit)
            .map { $0.map { camera.screenPoint(of: $0) } }
        return BuildConfirmLayout.siteObstacles(lines, around: anchor, reach: reach)
    }

    private func placement(below point: ScreenPoint, clearance: Double, keepingOff site: [ScreenFrame] = []) -> CGSize {
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
            avoiding.map { ScreenFrame($0) } + site, x: x, y: y, width: width, height: height, minX: minX, maxX: maxX, highest: highest,
            lowest: max(highest, bottom - height)
        )
        return CGSize(width: placed.x, height: placed.y)
    }
}

/// Its content at its own size, given no more than `maxWidth` across (and
/// no more than it is offered, beside the buttons in a row): words wrap
/// there, and the pill measures no wider than they need (a frame's
/// `maxWidth` would stretch to it).
private struct WidthLimit: Layout {
    let maxWidth: Double

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        subviews.first?.sizeThatFits(ProposedViewSize(width: min(maxWidth, proposal.width ?? maxWidth), height: nil)) ?? .zero
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(width: bounds.width, height: bounds.height))
    }
}

/// The width a child of ``PillColumn`` that is words wraps at; `nil` for
/// buttons, which do not wrap.
private struct WordsCap: LayoutValueKey {
    static let defaultValue: Double? = nil
}

/// Decision 803, continued: the pill's words and buttons one over another,
/// every one given the width of the widest
/// (``BuildConfirmLayout/columnWidth(_:limit:)``): why a stretch is refused
/// runs as wide as the pill, and the fixes fill it under it. A child
/// narrower than that (✕ ✓) stands in the middle.
private struct PillColumn: Layout {
    var spacing: CGFloat = 4

    private func columnWidth(_ proposal: ProposedViewSize, _ subviews: Subviews) -> CGFloat {
        let limit = proposal.width.flatMap { $0.isFinite ? Double($0) : nil }
        return CGFloat(BuildConfirmLayout.columnWidth(
            subviews.map { (ideal: Double($0.sizeThatFits(.unspecified).width), cap: $0[WordsCap.self]) }, limit: limit
        ))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard !subviews.isEmpty else { return .zero }
        let width = columnWidth(proposal, subviews)
        let heights = subviews.map { $0.sizeThatFits(ProposedViewSize(width: width, height: nil)).height }
        return CGSize(width: width, height: heights.reduce(0, +) + spacing * CGFloat(subviews.count - 1))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for subview in subviews {
            let offered = ProposedViewSize(width: bounds.width, height: nil)
            let size = subview.sizeThatFits(offered)
            subview.place(at: CGPoint(x: bounds.midX, y: y), anchor: .top, proposal: offered)
            y += size.height + spacing
        }
    }
}

/// Decision 803, continued: a refusal's fixes as cells of one width
/// (``BuildConfirmLayout/equalCells(ideal:available:spacing:)``), side by
/// side where they fit and one over another where they do not.
private struct EqualCells: Layout {
    var spacing: CGFloat = 6

    private func cells(_ width: CGFloat?, _ subviews: Subviews) -> (cell: CGFloat, stacked: Bool, height: CGFloat) {
        let ideals = subviews.map { $0.sizeThatFits(.unspecified) }
        let found = BuildConfirmLayout.equalCells(
            ideal: ideals.map { Double($0.width) }, available: width.map { Double($0) }, spacing: Double(spacing)
        )
        return (CGFloat(found.cell), found.stacked, ideals.map(\.height).max() ?? 0)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard !subviews.isEmpty else { return .zero }
        let plan = cells(proposal.width, subviews)
        let count = CGFloat(subviews.count), gaps = spacing * (count - 1)
        return plan.stacked ? CGSize(width: plan.cell, height: plan.height * count + gaps)
            : CGSize(width: plan.cell * count + gaps, height: plan.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let plan = cells(bounds.width, subviews)
        var x = bounds.minX, y = bounds.minY
        for subview in subviews {
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: plan.cell, height: plan.height))
            if plan.stacked { y += plan.height + spacing } else { x += plan.cell + spacing }
        }
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
    /// Decision 468, later: the trace runs along a real line for sale,
    /// and the pill offers its purchase card.
    var buysLine = false
    /// Decision 629: the stretch's new end moved up and down, and the
    /// heights that get round a refusal.
    var heights: NetworkHeightCard?
    /// Decision 800: why the stretch drawn is refused, said beside the ✓
    /// it greys; `nil` while a finger still draws it (the pill is under
    /// the finger, and the construction HUD says it).
    var problem: String?
    /// ``problem`` whole, for VoiceOver: the pill writes one short line
    /// (decision 803, continued).
    var spokenProblem: String?
    /// The stretch drawn, which the pill keeps off.
    var stretch: [PlanPoint] = []
    /// Decision 803: a finger still draws the stretch; the pill waits for
    /// it to let go. Continued: a road drawn and a building moved too.
    var fingerDraws = false

    /// Whether the pill says anything over (or beside) its buttons.
    var hasWords: Bool {
        caption != nil || problem != nil || heights?.note != nil || heights?.fixes.isEmpty == false
    }

    enum Kind {
        case track, platform, building, sale, mapTile, line, addStop, busRoute, road, roadRemoval, ferryRoute
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
        // Decision 568: the same test the screen puts its other controls
        // away by (``GameSession/drawsLineOnMap(linesPanelOpen:)``).
        if session.drawsLineOnMap(linesPanelOpen: linesPanelOpen),
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
            // Decision 507: an island layout's price is its tracks' too,
            // and where it cannot be laid the pill says why.
            let layout = session.networkStationLayoutPreview
            cost = layout.map(\.cost) ?? session.networkPlatformCost
            canConfirm = true
            kind = .platform
            caption = [session.platformSiteCaption(catchment, at: site), levelling?.caption(in: session.language), layout?.problem]
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
            let canBuild = preview.problem == nil && preview.cost != nil
            canConfirm = canBuild
            kind = .track
            // Decision 468, later: a trace along a real line for sale says
            // so, and the pill offers its purchase card.
            let sale = session.tracedSaleHint
            // Decision 803: a stretch has ✕ ✓ and its price alone; its
            // notes (the first stretch is straight, a double track's
            // crossovers) are the details card's.
            caption = BuildConfirmLayout.stretchCaption(offer: [sale?.text, sale?.shortfall])
            showsCatchment = false
            cancel = { session.clearNetworkDraft() }
            confirm = { session.buildNetworkTrack() }
            expandsMap = session.offersMapExpansion(for: preview.problem)
            buysLine = sale != nil
            heights = session.networkHeightCard
            fingerDraws = session.buildFingerDraws
            if !fingerDraws, let refusal = BuildConfirmLayout.refusal(of: preview) {
                problem = refusal.shown
                spokenProblem = refusal.spoken
            }
            stretch = preview.points.map(\.plan)
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
            fingerDraws = session.buildFingerDraws
        case .bus where session.busMode == .ferries:
            // Decision 585: the ferry route drawn, beside its last pier.
            guard let preview = session.ferryPreview, let last = session.ferryDraft.last else { return nil }
            start = nil
            flaggedEnd = nil
            anchor = last.middle
            clearance = 18
            cost = preview.price > .zero ? preview.price : nil
            canConfirm = preview.problem == nil
            kind = .ferryRoute
            caption = preview.problem
            showsCatchment = false
            cancel = { session.clearBusDraft() }
            confirm = { _ = session.buildFerryRoute() }
            undo = { session.undoFerryPier() }
        case .bus where session.busMode == .roads:
            // Decision 438: the road drawn, beside its last cell; or the
            // stretch of the player's road picked to take up.
            start = nil
            flaggedEnd = nil
            clearance = 18
            showsCatchment = false
            cancel = { session.clearRoadDraft() }
            fingerDraws = session.buildFingerDraws
            if let removal = session.roadRemoval, let first = removal.cells.first {
                anchor = first.middle
                cost = nil
                canConfirm = removal.canRemove
                kind = .roadRemoval
                caption = removal.problem
                confirm = { _ = session.confirmRoad() }
            } else {
                guard let preview = session.roadPreview, let last = session.roadDraft.cells.last else { return nil }
                anchor = last.middle
                cost = preview.price > .zero ? preview.price : nil
                canConfirm = preview.canBuild
                kind = .road
                caption = preview.problem
                confirm = { _ = session.confirmRoad() }
                undo = { session.removeLastRoadCell() }
            }
        case .bus:
            // Decision 400, 10i-5: the bus route drawn, beside its last stop.
            guard let preview = session.busPreview, let last = session.busDraft.stops.last else { return nil }
            start = nil
            flaggedEnd = nil
            anchor = last.middle
            clearance = 18
            cost = preview.price > .zero ? preview.price : nil
            canConfirm = preview.canOpen
            kind = .busRoute
            caption = preview.problem
            showsCatchment = false
            cancel = { session.clearBusDraft() }
            confirm = { _ = session.confirmBusRoute() }
            undo = { session.removeLastBusStop() }
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
        case .busRoute: language.text("Open this bus route", "開這條公車路線")
        case .road: language.text("Build this road", "鋪這段路")
        case .roadRemoval: language.text("Take up this road", "拆掉這段路")
        case .ferryRoute: language.text("Open this ferry route", "開這條渡輪航線")
        }
        guard let price = BuildConfirmLayout.priceText(of: cost, in: language) else { return what }
        return "\(what), \(price)"
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
