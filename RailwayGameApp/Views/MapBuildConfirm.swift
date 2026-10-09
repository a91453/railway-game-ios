import GameCore
import GamePresentation
import SwiftUI

/// What is being built where the player is looking (ARCHITECTURE decision
/// 107): a flag at each end of the track previewed, and beside its end, or
/// beside the building shown, a pill to cancel it or build it, with what
/// it costs. The finger that drew it is already there, so the player need
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

    private func pill(_ build: BuildConfirmation) -> some View {
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
            // and the tutorial's UI test finds it, alone, by it.
            .accessibilityLabel(Text(verbatim: build.confirmName(in: session.language)))
            .accessibilityIdentifier("map.build.confirm")
        }
        .padding(6)
        .glassBackground(in: Capsule())
        .fixedSize()
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
    let isTrack: Bool
    let cancel: @MainActor () -> Void
    let confirm: @MainActor () -> Void

    init?(_ session: GameSession) {
        switch session.tool {
        case .network:
            guard session.networkMode == .build, let preview = session.networkPreview,
                  let end = session.networkEndPlanPoint else { return nil }
            start = session.networkStartPlanPoint
            flaggedEnd = end
            anchor = end
            clearance = 18
            cost = preview.cost
            canConfirm = preview.problem == nil && preview.cost != nil
            isTrack = true
            cancel = { session.clearNetworkDraft() }
            confirm = { session.buildNetworkTrack() }
        case .building:
            guard let preview = session.buildingPreview else { return nil }
            start = nil
            flaggedEnd = nil
            anchor = preview.centre
            clearance = 44
            cost = preview.cost
            canConfirm = preview.problem == nil
            isTrack = false
            cancel = { session.clearBuildingSite() }
            confirm = { _ = session.confirmBuilding() }
        case .select, .train:
            return nil
        }
    }

    func confirmName(in language: DisplayLanguage) -> String {
        let what = isTrack ? language.text("Build this stretch", "建造這一段") : language.text("Build here", "蓋在這裡")
        guard let cost else { return what }
        return "\(what), \(cost.moneyText)"
    }
}
