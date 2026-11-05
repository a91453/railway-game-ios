import Foundation

/// Neutral study identifiers. Route-to-paint mapping belongs to a later feature.
public enum Map3DCoachLivery: String, CaseIterable, Sendable {
    case warmRed = "warm-red"
    case blueWhite = "blue-white"
    case seaGreen = "sea-green"
    case goldNavy = "gold-navy"
    case slateCream = "slate-cream"
    case skySlate = "sky-slate"
    case forestWhite = "forest-white"
    case tourismOrange = "tourism-orange"

    public var nameZH: String {
        switch self {
        case .warmRed: "暖紅快線"
        case .blueWhite: "藍白快線"
        case .seaGreen: "海綠快線"
        case .goldNavy: "金藍快線"
        case .slateCream: "灰米快線"
        case .skySlate: "晴藍快線"
        case .forestWhite: "森白快線"
        case .tourismOrange: "觀光接駁"
        }
    }
    public var nameEN: String {
        switch self {
        case .warmRed: "Warm Red Express"
        case .blueWhite: "Blue White Express"
        case .seaGreen: "Sea Green Express"
        case .goldNavy: "Gold Navy Express"
        case .slateCream: "Slate Cream Express"
        case .skySlate: "Sky Slate Express"
        case .forestWhite: "Forest White Express"
        case .tourismOrange: "Tourism Shuttle"
        }
    }
    /// All paint is selected from the existing 3D palette. No new hex colours.
    public var paint: (body: UInt32, belt: UInt32, nose: UInt32, roof: UInt32) {
        switch self {
        case .warmRed: (Map3DCoachBus.bodyColor,Map3DCoachBus.accentColor,Map3DCoachBus.accentColor,Map3DCoachBus.bodyColor)
        case .blueWhite: (Map3DPalette.shopAwnings[3],Map3DPalette.canopy,Map3DPalette.shopAwnings[2],Map3DPalette.shopAwnings[3])
        case .seaGreen: (Map3DPalette.shopAwnings[0],Map3DPalette.shopAwnings[3],Map3DPalette.playerRim,Map3DPalette.shopAwnings[0])
        case .goldNavy: (Map3DPalette.playerRim,Map3DPalette.platformEdge,Map3DPalette.platformEdge,Map3DPalette.playerRim)
        case .slateCream: (Map3DPalette.tunnelLining,Map3DPalette.shopAwnings[1],Map3DPalette.shopAwnings[1],Map3DPalette.tankWhite)
        case .skySlate: (Map3DPalette.shopAwnings[2],Map3DPalette.shopAwnings[3],Map3DPalette.platformEdge,Map3DPalette.roof)
        case .forestWhite: (Map3DPalette.park,Map3DPalette.playerRim,Map3DPalette.canopy,Map3DPalette.park)
        case .tourismOrange: (Map3DPalette.tankWhite,Map3DPalette.track,Map3DPalette.containers[3],Map3DPalette.track)
        }
    }
    public var isTourism: Bool { self == .tourismOrange }
}
