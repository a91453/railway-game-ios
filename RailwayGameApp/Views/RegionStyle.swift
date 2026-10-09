import SwiftUI
import UIKit

/// The look of the country a game is in (ARCHITECTURE decision 106): the
/// few colours and shapes that say "Taiwan's railways" or, later, "Japan's",
/// on top of the app's own ``Theme``, which stays the same everywhere.
/// Swapping a region swaps only these; the screen's layout and its controls
/// do not change.
///
/// Only Taiwan exists so far. Its colours are taken from Taiwan's railways,
/// not from the owner's website: no railway publishes its colour codes, so
/// the values are close matches, to be checked on a device.
/// - ``nameboard``: the blue of TRA's ordinary trains (藍皮普快), which the
///   railway restored after historical research for the 藍皮解憂號 in 2021.
struct RegionStyle: Sendable {
    /// The station nameboard's ground.
    let nameboard: Color
    /// Text on ``nameboard``, at least 4.5:1 on it in both appearances.
    let onNameboard: Color
    /// The station master's cap and the badge on it (decision 118).
    let stationMasterCap: Color
    let stationMasterBadge: Color

    /// Taiwan: the 藍皮 blue nameboard with white text (8.1:1); a lighter
    /// blue in dark mode with navy text (7.3:1). The station master wears
    /// TRA's dark navy cap with a gold badge (close matches, as the
    /// nameboard's).
    static let taiwan = RegionStyle(
        nameboard: RegionStyle.dynamic(light: 0x1D4F91, dark: 0x8DB6EE),
        onNameboard: RegionStyle.dynamic(light: 0xFFFFFF, dark: 0x162544),
        stationMasterCap: RegionStyle.dynamic(light: 0x1B2A47, dark: 0x2A3D63),
        stationMasterBadge: RegionStyle.dynamic(light: 0xD4A72C, dark: 0xE6BE4F)
    )

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let rgb = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: Double((rgb >> 16) & 0xFF) / 255,
                green: Double((rgb >> 8) & 0xFF) / 255,
                blue: Double(rgb & 0xFF) / 255,
                alpha: 1
            )
        })
    }
}

extension EnvironmentValues {
    /// The region the game is in (decision 106). Taiwan until a game can be
    /// somewhere else.
    @Entry var regionStyle = RegionStyle.taiwan
}

/// A station's name as its region writes it on the platform: for Taiwan a
/// blue board with the name in white. A long name shrinks, then wraps, so
/// "Frankfurt (Main) Hauptbahnhof" fits as well as "臺北".
struct StationNameboard: View {
    let name: String
    @Environment(\.regionStyle) private var region

    var body: some View {
        Text(verbatim: name)
            .font(.title3.weight(.bold))
            .foregroundStyle(region.onNameboard)
            .lineLimit(2)
            .minimumScaleFactor(0.7)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 40)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(region.nameboard, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            // The website's tactile edge: a hard shadow under the board.
            .background(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.black.opacity(0.22))
                    .offset(y: 3)
            }
            .accessibilityAddTraits(.isHeader)
    }
}
