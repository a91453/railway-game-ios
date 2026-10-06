import GameCore
import SwiftUI
import UIKit

/// Map and UI colours, each with a light and a dark variant so the app stays
/// readable and aesthetically pleasing in both appearances.
enum Palette {
    static let land = dynamic(light: (0.86, 0.91, 0.81), dark: (0.16, 0.21, 0.16))
    static let mapEdge = dynamic(light: (0.55, 0.62, 0.52), dark: (0.30, 0.36, 0.30))
    static let ballast = dynamic(light: (0.68, 0.64, 0.58), dark: (0.40, 0.38, 0.35))
    static let rail = dynamic(light: (0.24, 0.21, 0.19), dark: (0.90, 0.88, 0.84))
    static let station = dynamic(light: (0.82, 0.36, 0.08), dark: (0.93, 0.50, 0.18))
    static let stationSymbol = Color.white
    static let train = dynamic(light: (0.10, 0.36, 0.78), dark: (0.45, 0.68, 1.00))

    // Transit Semantic Colors
    static let metroBlue = dynamic(light: (0.07, 0.45, 0.88), dark: (0.24, 0.60, 1.00))
    static let metroGreen = dynamic(light: (0.13, 0.62, 0.36), dark: (0.22, 0.78, 0.48))
    static let metroAmber = dynamic(light: (0.88, 0.52, 0.08), dark: (0.96, 0.65, 0.20))
    static let metroPurple = dynamic(light: (0.48, 0.28, 0.82), dark: (0.65, 0.48, 0.95))
    static let metroCyan = dynamic(light: (0.05, 0.60, 0.72), dark: (0.20, 0.75, 0.88))
    static let metroRed = dynamic(light: (0.85, 0.24, 0.24), dark: (0.95, 0.38, 0.38))

    /// The casing under a train's movement authority (Stage V4e): the
    /// `Railway/` site's `followCase` (#fffdf6 light, #10141c dark), which
    /// it draws under a followed train's route.
    static let followCase = dynamic(light: (1.00, 0.992, 0.965), dark: (0.063, 0.078, 0.110))

    // The `Ci/` reference's train-panel load bar (app-panels CSS): the
    // track is `--metro-user-panel-field` (#d1d4d7 light, #484d54 dark),
    // the fill one neutral ink (#000 on the light card, #f9fafb on the
    // dark panel) and `.is-overload` red (#d85946 light, #ef4444 dark).
    static let paxBarTrack = dynamic(light: (0.820, 0.831, 0.843), dark: (0.282, 0.302, 0.329))
    static let paxBarFill = dynamic(light: (0.0, 0.0, 0.0), dark: (0.976, 0.980, 0.984))
    static let paxBarOverload = dynamic(light: (0.847, 0.349, 0.275), dark: (0.937, 0.267, 0.267))

    /// The colour a line is drawn with in the lines panel and the follow
    /// bar's dot: the one the player chose (`custom`, the line's
    /// ``LineColor``), or else one picked from the line's ID, as the lines
    /// panel always has.
    static func lineColor(_ id: LineID, custom: LineColor? = nil) -> Color {
        if let custom {
            return color(custom)
        }
        let colors: [Color] = [metroBlue, metroGreen, metroAmber, metroPurple, metroCyan, metroRed]
        return colors[abs(Int(id.rawValue)) % colors.count]
    }

    /// A ``LineColor`` as a SwiftUI colour.
    static func color(_ line: LineColor) -> Color {
        Color(
            red: Double((line.rgb >> 16) & 0xFF) / 255,
            green: Double((line.rgb >> 8) & 0xFF) / 255,
            blue: Double(line.rgb & 0xFF) / 255
        )
    }

    // Surfaces and Borders
    static let cardBackground = dynamic(light: (1.00, 1.00, 1.00), dark: (0.14, 0.15, 0.18))
    static let cardBorder = dynamicAlpha(light: (0.0, 0.0, 0.0, 0.08), dark: (1.0, 1.0, 1.0, 0.12))
    static let chipBackground = dynamicAlpha(light: (0.0, 0.0, 0.0, 0.05), dark: (1.0, 1.0, 1.0, 0.08))

    private static func dynamic(
        light: (Double, Double, Double),
        dark: (Double, Double, Double)
    ) -> Color {
        Color(uiColor: UIColor { traits in
            let rgb = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
        })
    }

    private static func dynamicAlpha(
        light: (Double, Double, Double, Double),
        dark: (Double, Double, Double, Double)
    ) -> Color {
        Color(uiColor: UIColor { traits in
            let rgba = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: rgba.0, green: rgba.1, blue: rgba.2, alpha: rgba.3)
        })
    }
}

/// A clean, tactile card modifier for grouping management options.
struct MetroCardModifier: ViewModifier {
    var padding: CGFloat = 12
    var cornerRadius: CGFloat = 14

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Palette.cardBackground, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Palette.cardBorder, lineWidth: 1)
            }
    }
}

extension View {
    func metroCard(padding: CGFloat = 12, cornerRadius: CGFloat = 14) -> some View {
        modifier(MetroCardModifier(padding: padding, cornerRadius: cornerRadius))
    }
}
