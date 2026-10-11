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
    @State private var pillSize = CGSize(width: 160, height: 44)

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let build = BuildConfirmation(session) {
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
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
        }
        .frame(width: viewport.width, height: viewport.height, alignment: .topLeading)
        .animation(.spring(duration: 0.25, bounce: 0.3), value: BuildConfirmation(session) != nil)
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
        VStack(spacing: 4) {
            if let caption = build.caption {
                Text(verbatim: caption)
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 8)
                    .accessibilityIdentifier("map.build.catchment")
            }
            buttons(build)
        }
        .padding(6)
        .glassBackground(in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .fixedSize()
    }

    private func buttons(_ build: BuildConfirmation) -> some View {
        HStack(spacing: 6) {
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
                    Image(systemName: "checkmark")
                        .font(.body.weight(.bold))
                    if let cost = build.cost {
                        Text(verbatim: cost.moneyText)
                            .font(.subheadline.weight(.bold))
                            .monospacedDigit()
                    }
                }
                .frame(minHeight: 40)
            }
            .buttonStyle(ThemeProminentButtonStyle())
            .disabled(!build.canConfirm)
            // Not "Build Track …": the details card's button has that name,
            // and the tutorial's UI test finds it, alone, by it
            // (``BuildConfirmation/confirmName(in:)``).
            .accessibilityLabel(Text(verbatim: build.confirmName(in: session.language)))
            .accessibilityIdentifier("map.build.confirm")
        }
    }

    /// Where the pill goes: under `point`, past what is shown there by
    /// `clearance`, or over it when there is no room below; kept clear of
    /// the controls along the map's edges.
    private func placement(below point: ScreenPoint, clearance: Double) -> CGSize {
        let margin = 8.0
        let width = Double(pillSize.width), height = Double(pillSize.height)
        let minX = Double(insets.leading) + margin
        let maxX = viewport.width - Double(insets.trailing) - width - margin
        let x = min(max(point.x - width / 2, minX), max(minX, maxX))
        let top = Double(insets.top) + margin
        let bottom = viewport.height - Double(insets.bottom) - margin
        var y = point.y + clearance
        if y + height > bottom {
            y = point.y - clearance - height
        }
        y = min(max(y, top), max(top, bottom - height))
        return CGSize(width: x, height: y)
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

    enum Kind {
        case track, platform, building, sale, mapTile
    }

    init?(_ session: GameSession) {
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
        switch session.tool {
        case .network where session.networkMode == .platform:
            // Decision 108: the place picked for a platform, and who lives
            // and works around it.
            guard let site = session.platformSitePlanPoint, let catchment = session.platformSiteCatchment else { return nil }
            start = nil
            flaggedEnd = nil
            anchor = site
            clearance = 18
            cost = nil
            canConfirm = true
            kind = .platform
            caption = session.platformSiteCaption(catchment, at: site)
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
            caption = nil
            showsCatchment = false
            cancel = { session.clearNetworkDraft() }
            confirm = { session.buildNetworkTrack() }
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
        case .mapTile: language.text("Buy this tile", "買下這一塊")
        }
        guard let cost else { return what }
        return "\(what), \(cost.moneyText)"
    }
}
